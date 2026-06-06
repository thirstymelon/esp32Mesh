#include "wifi_mesh.h"
#include "crypto.h"
#include "peer_db.h"
#include "chat_history.h"

#include "esp_wifi.h"
#include "esp_mac.h"
#include "esp_timer.h"
#include "esp_random.h"
#include "host/ble_hs.h"

static void send_historical_message(ChatMessage *msg) {
  MeshPacket pkt = {};
  pkt.magic = PACKET_MAGIC;
  pkt.type = PKT_CHAT;
  pkt.seq = msg->seq;
  pkt.session_id = msg->session_id;
  pkt.src_id = msg->sender;
  pkt.dest_id = msg->dest;
  pkt.epoch = group_key_epoch;

  size_t text_len = strlen(msg->text);
  uint8_t mesh_plain[MAX_TEXT_LEN + 2];
  mesh_plain[0] = msg->channel_id;
  memcpy(mesh_plain + 1, msg->text, text_len);
  size_t mesh_plain_len = text_len + 1;

  uint8_t m_nonce[AES_GCM_NONCE_LEN];
  uint8_t m_cipher[MAX_TEXT_LEN + 2];
  uint8_t m_tag[AES_GCM_TAG_LEN];

  const uint8_t *m_key = (msg->dest == 0) ? current_group_key : AES_KEY;

  if (aes_gcm_encrypt(mesh_plain, mesh_plain_len, m_key, m_nonce, m_cipher, m_tag) == 0) {
    memcpy(pkt.payload, m_nonce, AES_GCM_NONCE_LEN);
    memcpy(pkt.payload + AES_GCM_NONCE_LEN, m_cipher, mesh_plain_len);
    memcpy(pkt.payload + AES_GCM_NONCE_LEN + mesh_plain_len, m_tag, AES_GCM_TAG_LEN);
    pkt.payload_len = (uint16_t)(AES_GCM_OVERHEAD + mesh_plain_len);
    send_mesh_packet(&pkt);
  }
}

void send_mesh_packet(MeshPacket *pkt) {
  static const uint8_t broadcast_mac[6] = {0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF};
  size_t sz = sizeof(MeshPacket) - MESH_PAYLOAD_MAX + pkt->payload_len;

  esp_err_t ret = esp_now_send(broadcast_mac, (uint8_t *)pkt, sz);
  if (ret != ESP_OK) {
    esp_now_peer_info_t peer_info = {};
    memset(&peer_info, 0, sizeof(peer_info));
    memcpy(peer_info.peer_addr, broadcast_mac, ESP_NOW_ETH_ALEN);
    peer_info.channel = 1;
    peer_info.ifidx = WIFI_IF_AP;
    peer_info.encrypt = false;
    
    if (esp_now_is_peer_exist(broadcast_mac)) {
      esp_now_del_peer(broadcast_mac);
    }
    esp_now_add_peer(&peer_info);
    esp_now_send(broadcast_mac, (uint8_t *)pkt, sz);
  }
}

void esp_now_recv_cb(const esp_now_recv_info_t *recv_info,
                     const uint8_t *data, int len) {
  if (len < (int)(sizeof(MeshPacket) - MESH_PAYLOAD_MAX))
    return;

  MeshPacket pkt;
  memcpy(&pkt, data, MIN((int)sizeof(MeshPacket), len));
  if (pkt.magic != PACKET_MAGIC)
    return;
  if (pkt.src_id == my_node_id)
    return;

  if (pkt.payload_len > MESH_PAYLOAD_MAX) {
    ESP_LOGW(TAG, "Dropping packet from %08X: oversized payload_len %u", (unsigned)pkt.src_id, (unsigned)pkt.payload_len);
    return;
  }
  size_t pkt_claimed_size = sizeof(MeshPacket) - MESH_PAYLOAD_MAX + pkt.payload_len;
  if (pkt_claimed_size > (size_t)len) {
    ESP_LOGW(TAG, "Dropping packet from %08X: truncated payload (claimed %u, got %d)",
             (unsigned)pkt.src_id, (unsigned)pkt.payload_len, len);
    return;
  }

  if (is_duplicate(pkt.src_id, pkt.session_id, pkt.seq))
    return;

  if (pkt.type == PKT_HEARTBEAT) {
    send_mesh_packet(&pkt); // Relay

    if (pkt.payload_len >= 22) {
      char nick[21];
      memcpy(nick, pkt.payload, 20);
      nick[20] = '\0';
      uint8_t flags = pkt.payload[20];
      bool has_client = (flags & 1) != 0;
      uint8_t count = pkt.payload[21];
      uint32_t neighbors[MAX_NEIGHBORS] = {0};
      uint8_t valid = 0;
      if (pkt.payload_len >= (uint16_t)(22 + count * 4)) {
        int total = MIN((int)count, MAX_NEIGHBORS);
        for (int i = 0; i < total; i++) {
          memcpy(&neighbors[i], pkt.payload + 22 + i * 4, 4);
        }
        valid = (uint8_t)total;
      }
      update_peer_heartbeat(pkt.src_id, nick, neighbors, valid, has_client);
    }

  } else if (pkt.type == PKT_NICK_SYNC) {
    char nick[21];
    int cplen = MIN((int)pkt.payload_len, 20);
    memcpy(nick, pkt.payload, cplen);
    nick[cplen] = '\0';
    update_peer_nick(pkt.src_id, nick);
    ESP_LOGI(TAG, "Sync Nick %u: %s", (unsigned)pkt.src_id, nick);
    send_mesh_packet(&pkt);

  } else if (pkt.type == PKT_HISTORY_REQ) {
    if (pkt.dest_id == 0) {
      // Broadcast history request: ignored to prevent broadcast storm
      return;
    }
    
    if (pkt.dest_id != my_node_id) {
      // Unicast request for someone else: relay it
      send_mesh_packet(&pkt);
      return;
    }

    ESP_LOGI(TAG, "History sync request from node %08X received", (unsigned)pkt.src_id);

    if (ble_conn_handle != BLE_HS_CONN_HANDLE_NONE && ble_session_established) {
      char req_body[32];
      snprintf(req_body, sizeof(req_body), "REQ_HIST:%08X", (unsigned)pkt.src_id);
      size_t tlen = strlen(req_body);
      
      uint8_t nonce[AES_GCM_NONCE_LEN], cipher[32], tag[AES_GCM_TAG_LEN];
      if (aes_gcm_encrypt((uint8_t *)req_body, tlen, ble_session_key, nonce, cipher, tag) == 0) {
        xSemaphoreTake(notify_mutex, portMAX_DELAY);
        int off = 0;
        uint32_t sender = my_node_id;
        uint32_t dest = pkt.src_id;
        uint32_t ts = 0;
        uint8_t flags = 0x10; // History query flag
        uint16_t sess = 0;
        uint16_t sq = 0;
        uint8_t ch = 0;

        memcpy(s_notify_buf + off, &sender, 4);
        off += 4;
        memcpy(s_notify_buf + off, &dest, 4);
        off += 4;
        memcpy(s_notify_buf + off, &ts, 4);
        off += 4;
        s_notify_buf[off++] = flags;
        memcpy(s_notify_buf + off, &sess, 2);
        off += 2;
        memcpy(s_notify_buf + off, &sq, 2);
        off += 2;
        s_notify_buf[off++] = ch;

        memcpy(s_notify_buf + off, nonce, AES_GCM_NONCE_LEN);
        off += AES_GCM_NONCE_LEN;
        memcpy(s_notify_buf + off, cipher, tlen);
        off += tlen;
        memcpy(s_notify_buf + off, tag, AES_GCM_TAG_LEN);
        off += AES_GCM_TAG_LEN;

        struct os_mbuf *om = ble_hs_mbuf_from_flat(s_notify_buf, off);
        xSemaphoreGive(notify_mutex);
        if (om) {
          ble_gatts_notify_custom(ble_conn_handle, chat_val_handle, om);
          ESP_LOGI(TAG, "Notified client of history request from %08X", (unsigned)pkt.src_id);
        }
      }
    } else {
      xSemaphoreTake(chat_mutex, portMAX_DELAY);
      int total_msgs = chat_count;
      xSemaphoreGive(chat_mutex);

      for (int i = 0; i < total_msgs; i++) {
        xSemaphoreTake(chat_mutex, portMAX_DELAY);
        ChatMessage msg = chat_history[(chat_tail + i) % CHAT_HISTORY_MAX];
        xSemaphoreGive(chat_mutex);

        send_historical_message(&msg);
        vTaskDelay(pdMS_TO_TICKS(50));
      }
    }

  } else if (pkt.type == PKT_CHAT) {
    if (pkt.payload_len < (uint16_t)AES_GCM_OVERHEAD)
      return;
    size_t cipher_len = pkt.payload_len - AES_GCM_OVERHEAD;
    if (cipher_len == 0 || cipher_len > (MAX_TEXT_LEN + 1))
      return;

    const uint8_t *nonce = pkt.payload;
    const uint8_t *ciphertext = pkt.payload + AES_GCM_NONCE_LEN;
    const uint8_t *tag = ciphertext + cipher_len;

    const uint8_t *key;
    if (pkt.dest_id == 0) {
      key = get_group_key_for_epoch(pkt.epoch);
      if (key == NULL) {
        ESP_LOGW(TAG, "Group key epoch %u too old to decrypt broadcast from node %u", pkt.epoch, pkt.src_id);
        return;
      }
    } else {
      key = AES_KEY;
    }

    uint8_t decrypted[MAX_TEXT_LEN + 2] = {0};
    if (aes_gcm_decrypt(ciphertext, cipher_len, key, nonce, tag, decrypted) != 0) {
      ESP_LOGW(TAG, "Auth decrypt failed from node %u", pkt.src_id);
      return;
    }

    uint8_t channel_id = decrypted[0];
    char *text = (char *)(decrypted + 1);
    size_t text_len = cipher_len - 1;
    text[text_len] = '\0';

    uint32_t now_ts =
        (uint32_t)(esp_timer_get_time() / 1000000ULL) + mesh_time_offset_s;

    if (pkt.dest_id == 0) {
      ESP_LOGI(TAG, "Broadcast from %u (ch %u): %s", (unsigned)pkt.src_id, channel_id, text);
      add_to_history(pkt.src_id, 0, 0, text, now_ts, pkt.session_id, pkt.seq, channel_id);
      send_mesh_packet(&pkt); // Relay
    } else if (pkt.dest_id == my_node_id) {
      ESP_LOGI(TAG, "DM from %u: %s", (unsigned)pkt.src_id, text);
      add_to_history(pkt.src_id, my_node_id, 2, text, now_ts, pkt.session_id, pkt.seq, channel_id);
    } else {
      send_mesh_packet(&pkt); // Relay DM
    }
  }
}

void mesh_heartbeat_task(void *pvParameters) {
  while (1) {
    vTaskDelay(pdMS_TO_TICKS(5000));

    static bool ssid_hidden_active = false;
    if (!ssid_hidden_active) {
      bool has_online_peers = false;
      xSemaphoreTake(peer_mutex, portMAX_DELAY);
      for (int i = 0; i < peer_db_count; i++) {
        if (peer_db[i].is_online) {
          has_online_peers = true;
          break;
        }
      }
      xSemaphoreGive(peer_mutex);

      if (has_online_peers) {
        wifi_config_t wifi_cfg;
        if (esp_wifi_get_config(WIFI_IF_AP, &wifi_cfg) == ESP_OK) {
          wifi_cfg.ap.ssid_hidden = 1;
          esp_wifi_set_config(WIFI_IF_AP, &wifi_cfg);
          esp_wifi_stop();
          esp_wifi_start();
          ESP_LOGI(TAG, "Mesh formed with active peers. AP SSID is now hidden.");
          ssid_hidden_active = true;
        }
      }
    }

    xSemaphoreTake(peer_mutex, portMAX_DELAY);
    bool changed = false;
    uint32_t offline_now = esp_log_timestamp();
    for (int i = 0; i < peer_db_count; i++) {
      if (peer_db[i].is_online &&
          (offline_now - peer_db[i].last_seen_ms > 15000)) {
        peer_db[i].is_online = false;
        changed = true;
        ESP_LOGI(TAG, "Peer offline: %u", (unsigned)peer_db[i].id);
      }
    }
    xSemaphoreGive(peer_mutex);

    if (changed && ble_conn_handle != BLE_HS_CONN_HANDLE_NONE) {
      ble_gatts_chr_updated(peers_val_handle);
      ble_gatts_chr_updated(status_val_handle);
    }

    MeshPacket pkt = {};
    pkt.magic = PACKET_MAGIC;
    pkt.type = PKT_HEARTBEAT;
    rotate_session_if_needed();
    pkt.seq = my_seq++;
    pkt.session_id = my_session_id;
    pkt.epoch = group_key_epoch;
    pkt.src_id = my_node_id;
    pkt.dest_id = 0;

    strncpy((char *)pkt.payload, my_nickname, 20);
    pkt.payload[20] = (ble_conn_handle != BLE_HS_CONN_HANDLE_NONE && ble_session_established) ? 1 : 0;

    xSemaphoreTake(peer_mutex, portMAX_DELAY);
    uint32_t nb_now = esp_log_timestamp();
    uint32_t direct[32];
    uint8_t dcnt = 0;
    for (int i = 0; i < peer_db_count; i++) {
      if (peer_db[i].is_online && (nb_now - peer_db[i].last_seen_ms <= 15000)) {
        if (dcnt < 32)
          direct[dcnt++] = peer_db[i].id;
      }
    }
    xSemaphoreGive(peer_mutex);

    uint8_t cnt = MIN(dcnt, 40u);
    pkt.payload[21] = cnt;
    for (int i = 0; i < cnt; i++) {
      memcpy(pkt.payload + 22 + i * 4, &direct[i], 4);
    }
    pkt.payload_len = 22 + cnt * 4;
    send_mesh_packet(&pkt);

    if (ble_conn_handle != BLE_HS_CONN_HANDLE_NONE) {
      ble_gatts_chr_updated(status_val_handle);

      // Send telemetry notification on Chat characteristic (flag 0x40)
      xSemaphoreTake(notify_mutex, portMAX_DELAY);
      uint32_t sender = my_node_id;
      uint32_t dest = 0;
      uint32_t uptime = (uint32_t)(esp_timer_get_time() / 1000000ULL);
      uint8_t flags = 0x40; // Telemetry
      uint16_t sess = my_session_id;
      uint16_t sq = my_seq++;
      uint8_t ch = 0;
      uint8_t battery = 100; // Mock battery at 100%

      memcpy(s_notify_buf, &sender, 4);
      memcpy(s_notify_buf + 4, &dest, 4);
      memcpy(s_notify_buf + 8, &uptime, 4);
      s_notify_buf[12] = flags;
      memcpy(s_notify_buf + 13, &sess, 2);
      memcpy(s_notify_buf + 15, &sq, 2);
      s_notify_buf[17] = ch;
      s_notify_buf[18] = battery;

      struct os_mbuf *om = ble_hs_mbuf_from_flat(s_notify_buf, 19);
      xSemaphoreGive(notify_mutex);
      if (om) {
        ble_gatts_notify_custom(ble_conn_handle, chat_val_handle, om);
      }
    }
  }
}
