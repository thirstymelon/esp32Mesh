#include "ble_mesh.h"
#include "crypto.h"
#include "peer_db.h"
#include "chat_history.h"
#include "wifi_mesh.h"
#include "nvs_storage.h"

// NimBLE Host Headers
#include "host/ble_att.h"
#include "host/ble_hs.h"
#include "host/ble_store.h"
#include "host/ble_uuid.h"
#include "nimble/nimble_port.h"
#include "nimble/nimble_port_freertos.h"
#include "services/gap/ble_svc_gap.h"
#include "services/gatt/ble_svc_gatt.h"
#include "store/config/ble_store_config.h"

// ESP-IDF Timer
#include "esp_timer.h"

// Define BLE Handles
uint16_t status_val_handle = 0;
uint16_t peers_val_handle = 0;
uint16_t chat_val_handle = 0;
uint16_t cmd_val_handle = 0;
uint16_t ecdh_val_handle = 0;
uint16_t ota_val_handle = 0;

uint16_t ble_conn_handle = BLE_HS_CONN_HANDLE_NONE;
uint8_t ble_own_addr_type = 0;

// Define OTA Variables
esp_ota_handle_t ota_update_handle = 0;
const esp_partition_t *ota_update_partition = NULL;
uint32_t ota_image_size = 0;
uint32_t ota_bytes_written = 0;
bool ota_in_progress = false;
uint32_t ota_last_notified_bytes = 0;

// Define Buffers
uint8_t s_peers_buf[3072] = {0};
uint8_t s_notify_buf[CHAT_HDR_LEN + AES_GCM_OVERHEAD + MAX_TEXT_LEN + 1] = {0};

// ECDH Context setup imports
#include "mbedtls/sha256.h"
#include "mbedtls/ecdh.h"
#include "mbedtls/entropy.h"
#include "mbedtls/ctr_drbg.h"

#define CHAT_WRITE_MIN (4 + 1 + AES_GCM_OVERHEAD + 1)

// ─── GATT ACCESS CALLBACKS ───────────────────────────────────────────────

static int ble_chr_status_cb(uint16_t conn_handle, uint16_t attr_handle,
                             struct ble_gatt_access_ctxt *ctxt, void *arg) {
  if (ctxt->op != BLE_GATT_ACCESS_OP_READ_CHR)
    return BLE_ATT_ERR_REQ_NOT_SUPPORTED;

  uint8_t payload[31] = {0};
  uint32_t uptime =
      (uint32_t)(esp_timer_get_time() / 1000000ULL) + mesh_time_offset_s;

  xSemaphoreTake(peer_mutex, portMAX_DELAY);
  uint16_t peer_count = 0;
  for (int i = 0; i < peer_db_count; i++) {
    if (peer_db[i].is_online)
      peer_count++;
  }
  xSemaphoreGive(peer_mutex);

  memcpy(payload, &my_node_id, 4);
  memcpy(payload + 4, &uptime, 4);
  memcpy(payload + 8, &peer_count, 2);
  payload[10] = group_key_epoch;
  strncpy((char *)payload + 11, my_nickname, 20);

  os_mbuf_append(ctxt->om, payload, sizeof(payload));
  return 0;
}

static int ble_chr_peers_cb(uint16_t conn_handle, uint16_t attr_handle,
                            struct ble_gatt_access_ctxt *ctxt, void *arg) {
  if (ctxt->op != BLE_GATT_ACCESS_OP_READ_CHR)
    return BLE_ATT_ERR_REQ_NOT_SUPPORTED;

  xSemaphoreTake(peers_buf_mutex, portMAX_DELAY);
  int plen = 0;

  xSemaphoreTake(peer_mutex, portMAX_DELAY);

  uint16_t node_count = 1;
  for (int i = 0; i < peer_db_count; i++) {
    if (peer_db[i].is_online)
      node_count++;
  }
  memcpy(s_peers_buf, &node_count, 2);
  plen = 2;

  uint32_t now = esp_log_timestamp();
  uint32_t direct[32];
  uint8_t dcnt = 0;
  for (int i = 0; i < peer_db_count; i++) {
    if (peer_db[i].is_online && (now - peer_db[i].last_seen_ms <= 15000)) {
      if (dcnt < 32)
        direct[dcnt++] = peer_db[i].id;
    }
  }
  if (plen + 26 + dcnt * 4 <= (int)sizeof(s_peers_buf)) {
    memcpy(s_peers_buf + plen, &my_node_id, 4);
    s_peers_buf[plen + 4] = 1;
    strncpy((char *)s_peers_buf + plen + 5, my_nickname, 20);
    s_peers_buf[plen + 25] = dcnt;
    plen += 26;
    for (int i = 0; i < dcnt; i++) {
      memcpy(s_peers_buf + plen, &direct[i], 4);
      plen += 4;
    }
  }

  for (int p = 0; p < peer_db_count; p++) {
    if (!peer_db[p].is_online)
      continue;
    int needed = 26 + peer_db[p].neighbor_count * 4;
    if (plen + needed > (int)sizeof(s_peers_buf))
      break;
    memcpy(s_peers_buf + plen, &peer_db[p].id, 4);
    s_peers_buf[plen + 4] = 1;
    strncpy((char *)s_peers_buf + plen + 5, peer_db[p].nick, 20);
    s_peers_buf[plen + 25] = peer_db[p].neighbor_count;
    plen += 26;
    for (int n = 0; n < peer_db[p].neighbor_count; n++) {
      memcpy(s_peers_buf + plen, &peer_db[p].neighbors[n], 4);
      plen += 4;
    }
  }
  xSemaphoreGive(peer_mutex);

  os_mbuf_append(ctxt->om, s_peers_buf, plen);
  xSemaphoreGive(peers_buf_mutex);
  return 0;
}

static int ble_chr_chat_cb(uint16_t conn_handle, uint16_t attr_handle,
                           struct ble_gatt_access_ctxt *ctxt, void *arg) {
  // Fix: thread-safe stack allocation instead of shared static buffer
  uint8_t local_chat_buf[CHAT_HDR_LEN + AES_GCM_OVERHEAD + MAX_TEXT_LEN + 1];

  if (ctxt->op == BLE_GATT_ACCESS_OP_WRITE_CHR) {
    uint16_t len = OS_MBUF_PKTLEN(ctxt->om);
    if (len < CHAT_WRITE_MIN || len > 256)
      return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;

    uint8_t buf[256];
    ble_hs_mbuf_to_flat(ctxt->om, buf, len, NULL);

    uint32_t dest_id;
    memcpy(&dest_id, buf, 4);
    uint8_t channel_id = buf[4];

    const uint8_t *blob = buf + 5;
    size_t blob_len = len - 5;
    if (blob_len < AES_GCM_OVERHEAD)
      return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;

    // Fix: Calculate tag pointer from the true payload bounds to support varying text sizes
    const uint8_t *nonce = blob;
    const uint8_t *ciphertext = blob + AES_GCM_NONCE_LEN;
    const uint8_t *tag = blob + blob_len - AES_GCM_TAG_LEN;

    size_t cipher_len = blob_len - AES_GCM_OVERHEAD;
    if (cipher_len > MAX_TEXT_LEN)
      cipher_len = MAX_TEXT_LEN;

    char plaintext[MAX_TEXT_LEN + 1] = {0};
    const uint8_t *key = ble_session_established ? ble_session_key : AES_KEY;

    if (aes_gcm_decrypt(ciphertext, cipher_len, key, nonce, tag,
                        (uint8_t *)plaintext) != 0) {
      ESP_LOGW(TAG, "Chat write: auth decrypt failed");
      return BLE_ATT_ERR_UNLIKELY;
    }
    plaintext[cipher_len] = '\0';

    uint32_t now_ts =
        (uint32_t)(esp_timer_get_time() / 1000000ULL) + mesh_time_offset_s;
    uint8_t flags = (uint8_t)(1 | (dest_id != 0 ? 2 : 0)); // is_me | is_dm
    rotate_session_if_needed();
    uint32_t current_seq = my_seq++;
    add_to_history(my_node_id, dest_id, flags, plaintext, now_ts, my_session_id, (uint16_t)current_seq, channel_id);

    uint8_t mesh_plain[MAX_TEXT_LEN + 2];
    mesh_plain[0] = channel_id;
    memcpy(mesh_plain + 1, plaintext, cipher_len);
    size_t mesh_plain_len = cipher_len + 1;

    MeshPacket pkt = {};
    pkt.magic = PACKET_MAGIC;
    pkt.type = PKT_CHAT;
    pkt.seq = current_seq;
    pkt.session_id = my_session_id;
    pkt.src_id = my_node_id;
    pkt.dest_id = dest_id;

    uint8_t m_nonce[AES_GCM_NONCE_LEN];
    uint8_t m_cipher[MAX_TEXT_LEN + 2];
    uint8_t m_tag[AES_GCM_TAG_LEN];

    const uint8_t *m_key = (dest_id == 0) ? current_group_key : AES_KEY;
    pkt.epoch = (dest_id == 0) ? group_key_epoch : 0;

    if (aes_gcm_encrypt(mesh_plain, mesh_plain_len, m_key, m_nonce, m_cipher,
                        m_tag) != 0) {
      return BLE_ATT_ERR_UNLIKELY;
    }

    memcpy(pkt.payload, m_nonce, AES_GCM_NONCE_LEN);
    memcpy(pkt.payload + AES_GCM_NONCE_LEN, m_cipher, mesh_plain_len);
    memcpy(pkt.payload + AES_GCM_NONCE_LEN + mesh_plain_len, m_tag,
           AES_GCM_TAG_LEN);
    pkt.payload_len = (uint16_t)(AES_GCM_OVERHEAD + mesh_plain_len);

    send_mesh_packet(&pkt);
    return 0;

  } else if (ctxt->op == BLE_GATT_ACCESS_OP_READ_CHR) {
    xSemaphoreTake(chat_mutex, portMAX_DELAY);
    if (history_sync_active && history_sync_index < history_sync_count) {
      ChatMessage msg = history_sync_buffer[history_sync_index++];
      if (history_sync_index >= history_sync_count) {
        history_sync_active = false;
      }
      xSemaphoreGive(chat_mutex);

      size_t tlen = strnlen(msg.text, MAX_TEXT_LEN);
      uint8_t nonce[AES_GCM_NONCE_LEN], cipher[MAX_TEXT_LEN], tag[AES_GCM_TAG_LEN];
      const uint8_t *key = ble_session_established ? ble_session_key : AES_KEY;

      if (aes_gcm_encrypt((uint8_t *)msg.text, tlen, key, nonce, cipher, tag) != 0) {
        return BLE_ATT_ERR_UNLIKELY;
      }

      int off = 0;
      memcpy(local_chat_buf + off, &msg.sender, 4);
      off += 4;
      memcpy(local_chat_buf + off, &msg.dest, 4);
      off += 4;
      memcpy(local_chat_buf + off, &msg.ts, 4);
      off += 4;
      local_chat_buf[off++] = msg.flags;
      memcpy(local_chat_buf + off, &msg.session_id, 2);
      off += 2;
      memcpy(local_chat_buf + off, &msg.seq, 2);
      off += 2;
      local_chat_buf[off++] = msg.channel_id;

      memcpy(local_chat_buf + off, nonce, AES_GCM_NONCE_LEN);
      off += AES_GCM_NONCE_LEN;
      memcpy(local_chat_buf + off, cipher, tlen);
      off += tlen;
      memcpy(local_chat_buf + off, tag, AES_GCM_TAG_LEN);
      off += AES_GCM_TAG_LEN;

      os_mbuf_append(ctxt->om, local_chat_buf, off);
      return 0;
    }
    xSemaphoreGive(chat_mutex);

    xSemaphoreTake(chat_mutex, portMAX_DELAY);
    if (chat_count == 0) {
      xSemaphoreGive(chat_mutex);
      return 0;
    }
    int latest = (chat_tail + chat_count - 1) % CHAT_HISTORY_MAX;
    ChatMessage msg = chat_history[latest];
    xSemaphoreGive(chat_mutex);

    size_t tlen = strnlen(msg.text, MAX_TEXT_LEN);
    uint8_t nonce[AES_GCM_NONCE_LEN], cipher[MAX_TEXT_LEN], tag[AES_GCM_TAG_LEN];
    const uint8_t *key = ble_session_established ? ble_session_key : AES_KEY;

    if (aes_gcm_encrypt((uint8_t *)msg.text, tlen, key, nonce, cipher, tag) != 0) {
      return BLE_ATT_ERR_UNLIKELY;
    }

    int off = 0;
    memcpy(local_chat_buf + off, &msg.sender, 4);
    off += 4;
    memcpy(local_chat_buf + off, &msg.dest, 4);
    off += 4;
    memcpy(local_chat_buf + off, &msg.ts, 4);
    off += 4;
    local_chat_buf[off++] = msg.flags;
    memcpy(local_chat_buf + off, &msg.session_id, 2);
    off += 2;
    memcpy(local_chat_buf + off, &msg.seq, 2);
    off += 2;
    local_chat_buf[off++] = msg.channel_id;

    memcpy(local_chat_buf + off, nonce, AES_GCM_NONCE_LEN);
    off += AES_GCM_NONCE_LEN;
    memcpy(local_chat_buf + off, cipher, tlen);
    off += tlen;
    memcpy(local_chat_buf + off, tag, AES_GCM_TAG_LEN);
    off += AES_GCM_TAG_LEN;

    os_mbuf_append(ctxt->om, local_chat_buf, off);
    return 0;
  }
  return BLE_ATT_ERR_REQ_NOT_SUPPORTED;
}

static int ble_chr_ecdh_cb(uint16_t conn_handle, uint16_t attr_handle,
                           struct ble_gatt_access_ctxt *ctxt, void *arg) {
  if (ctxt->op == BLE_GATT_ACCESS_OP_WRITE_CHR) {
    uint16_t len = OS_MBUF_PKTLEN(ctxt->om);
    if (len != 65) {
      ESP_LOGE(TAG, "ECDH write length error: expected 65, got %u", len);
      return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
    }

    uint8_t client_pub[65];
    ble_hs_mbuf_to_flat(ctxt->om, client_pub, 65, NULL);

    if (client_pub[0] != 0x04) {
      ESP_LOGE(TAG, "ECDH public key prefix error: expected 0x04, got 0x%02X", client_pub[0]);
      return BLE_ATT_ERR_UNLIKELY;
    }

    // Reset session state for new handshake
    ble_session_established = false;
    memset(ble_session_key, 0, 16);

    int ret = crypto_calc_session_key(client_pub);
    if (ret != 0) {
      ESP_LOGE(TAG, "crypto_calc_session_key failed: -0x%04X", -ret);
    } else {
      ESP_LOGI(TAG, "ECDH session established!");
    }

    return ble_session_established ? 0 : BLE_ATT_ERR_UNLIKELY;

  } else if (ctxt->op == BLE_GATT_ACCESS_OP_READ_CHR) {
    os_mbuf_append(ctxt->om, server_pub_key, 65);
    return 0;
  }
  return BLE_ATT_ERR_REQ_NOT_SUPPORTED;
}

// Private copies of OTA state for the finalize task, isolated from the main
// OTA globals so the disconnect / Begin handlers don't race with the task.
static esp_ota_handle_t s_ota_finalize_handle = 0;
static const esp_partition_t *s_ota_finalize_partition = NULL;
static uint32_t s_ota_finalize_image_size = 0;

// Forward declaration — ota_finalize_task calls ota_notify_status which is
// defined later in this file (after the ECDH callback).
static void ota_notify_status(uint8_t status, uint32_t progress);

// OTA finalize task — runs esp_ota_end and esp_ota_set_boot_partition in a
// dedicated FreeRTOS task instead of inside the NimBLE GATT callback.
// Flash verification and partition writes can block for tens of milliseconds,
// which would stall the BLE host task and risk connection supervision timeout.
static void ota_finalize_task(void *pvParameters) {
  ESP_LOGI(TAG, "OTA finalize: verifying firmware image...");

  esp_err_t err = esp_ota_end(s_ota_finalize_handle);
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "ota_finalize: esp_ota_end failed, err = %d", err);
    ota_notify_status(0xFF, 0x04);
    s_ota_finalize_handle = 0;
    s_ota_finalize_partition = NULL;
    s_ota_finalize_image_size = 0;
    vTaskDelete(NULL);
    return;
  }
  s_ota_finalize_handle = 0;

  ESP_LOGI(TAG, "OTA finalize: setting boot partition...");
  err = esp_ota_set_boot_partition(s_ota_finalize_partition);
  if (err != ESP_OK) {
    ESP_LOGE(TAG, "ota_finalize: esp_ota_set_boot_partition failed, err = %d", err);
    ota_notify_status(0xFF, 0x05);
    s_ota_finalize_partition = NULL;
    s_ota_finalize_image_size = 0;
    vTaskDelete(NULL);
    return;
  }

  ESP_LOGI(TAG, "OTA finalize: image verified, boot partition updated. Rebooting...");
  ota_notify_status(0x02, s_ota_finalize_image_size);

  s_ota_finalize_handle = 0;
  s_ota_finalize_partition = NULL;
  s_ota_finalize_image_size = 0;

  // Short delay to let the notification be sent, then reboot
  vTaskDelay(pdMS_TO_TICKS(1000));
  esp_restart();
  vTaskDelete(NULL);
}

// Send a GATT notification on the OTA characteristic with status and progress.
static void ota_notify_status(uint8_t status, uint32_t progress) {
  if (ble_conn_handle == BLE_HS_CONN_HANDLE_NONE) return;

  uint8_t payload[5];
  payload[0] = status;
  memcpy(payload + 1, &progress, 4);

  struct os_mbuf *om = ble_hs_mbuf_from_flat(payload, sizeof(payload));
  if (om) {
    ble_gatts_notify_custom(ble_conn_handle, ota_val_handle, om);
  }
}

static int ble_chr_ota_cb(uint16_t conn_handle, uint16_t attr_handle,
                          struct ble_gatt_access_ctxt *ctxt, void *arg) {
  if (ctxt->op != BLE_GATT_ACCESS_OP_WRITE_CHR) {
    return BLE_ATT_ERR_REQ_NOT_SUPPORTED;
  }

  uint16_t len = OS_MBUF_PKTLEN(ctxt->om);
  if (len < 1 || len > 512) {
    return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
  }

  uint8_t buf[512];
  ble_hs_mbuf_to_flat(ctxt->om, buf, len, NULL);
  uint8_t cmd = buf[0];

  if (cmd == 1) { // Begin OTA
    if (len < 5) return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;
    memcpy(&ota_image_size, buf + 1, 4);
    ESP_LOGI("OTA", "OTA Begin command received. Size: %u bytes", (unsigned)ota_image_size);

    if (ota_in_progress) {
      if (ota_update_handle != 0) {
        esp_ota_abort(ota_update_handle);
      }
      ota_in_progress = false;
      ota_update_handle = 0;
    }

    ota_update_partition = esp_ota_get_next_update_partition(NULL);
    if (!ota_update_partition) {
      ESP_LOGE("OTA", "Failed to find OTA update partition");
      ota_notify_status(0xFF, 0x01);
      return BLE_ATT_ERR_UNLIKELY;
    }

    esp_err_t err = esp_ota_begin(ota_update_partition, ota_image_size, &ota_update_handle);
    if (err != ESP_OK) {
      ESP_LOGE("OTA", "esp_ota_begin failed, err = %d", err);
      ota_notify_status(0xFF, 0x02);
      return BLE_ATT_ERR_UNLIKELY;
    }

    ota_bytes_written = 0;
    ota_in_progress = true;
    ota_last_notified_bytes = 0;
    ESP_LOGI("OTA", "OTA initialization successful. Erased partition ready.");
    ota_notify_status(0x01, 0);
    return 0;

  } else if (cmd == 2) { // Write chunk
    if (!ota_in_progress || ota_update_handle == 0) {
      ESP_LOGE("OTA", "Write chunk received but OTA is not in progress");
      ota_notify_status(0xFF, 0x03);
      return BLE_ATT_ERR_UNLIKELY;
    }

    size_t chunk_len = len - 1;
    esp_err_t err = esp_ota_write(ota_update_handle, buf + 1, chunk_len);
    if (err != ESP_OK) {
      ESP_LOGE("OTA", "esp_ota_write failed at %u bytes, err = %d", (unsigned)ota_bytes_written, err);
      esp_ota_abort(ota_update_handle);
      ota_in_progress = false;
      ota_update_handle = 0;
      ota_notify_status(0xFF, 0x03);
      return BLE_ATT_ERR_UNLIKELY;
    }

    ota_bytes_written += chunk_len;
    
    if (ota_bytes_written == ota_image_size || (ota_bytes_written - ota_last_notified_bytes >= 32768)) {
      ota_notify_status(0x01, ota_bytes_written);
      ota_last_notified_bytes = ota_bytes_written;
    }
    return 0;

  } else if (cmd == 3) { // End OTA
    if (!ota_in_progress || ota_update_handle == 0) {
      ESP_LOGE("OTA", "End OTA received but OTA is not in progress");
      ota_notify_status(0xFF, 0x03);
      return BLE_ATT_ERR_UNLIKELY;
    }

    if (ota_bytes_written != ota_image_size) {
      ESP_LOGE("OTA", "Incomplete upload: wrote %u of %u bytes — aborting",
               (unsigned)ota_bytes_written, (unsigned)ota_image_size);
      esp_ota_abort(ota_update_handle);
      ota_in_progress = false;
      ota_update_handle = 0;
      ota_notify_status(0xFF, 0x06);
      return BLE_ATT_ERR_UNLIKELY;
    }

    // Copy OTA state to private globals for the finalize task, then clear
    // the main OTA state so the disconnect / Begin handlers don't race with
    // the background task by trying to abort or re-use the handle.
    s_ota_finalize_handle = ota_update_handle;
    s_ota_finalize_partition = ota_update_partition;
    s_ota_finalize_image_size = ota_image_size;

    // Clear main OTA state immediately — the finalize task owns the handle now.
    ota_in_progress = false;
    ota_update_handle = 0;
    ota_update_partition = NULL;
    ota_image_size = 0;
    ota_bytes_written = 0;
    ota_last_notified_bytes = 0;

    // Defer flash verification and boot partition update to a separate
    // FreeRTOS task so the NimBLE host task is not blocked during slow
    // flash operations (esp_ota_end validates the image hash, and
    // esp_ota_set_boot_partition writes to flash).
    ESP_LOGI(TAG, "OTA End command received. Deferring finalization to background task...");
    if (xTaskCreate(ota_finalize_task, "ota_finalize", 3072, NULL, 5, NULL) != pdPASS) {
      ESP_LOGE("OTA", "Failed to create ota_finalize task");
      // Can't notify via OTA characteristic — ble_conn_handle may be stale
      // or the handle was already cleared. The node will retry on next boot.
      return BLE_ATT_ERR_UNLIKELY;
    }

    // Return immediately — NimBLE sends the write response right away,
    // avoiding any BLE supervision timeout while flash operations run.
    return 0;
  }

  return BLE_ATT_ERR_REQ_NOT_SUPPORTED;
}

static int ble_chr_cmd_cb(uint16_t conn_handle, uint16_t attr_handle,
                           struct ble_gatt_access_ctxt *ctxt, void *arg) {
  if (ctxt->op != BLE_GATT_ACCESS_OP_WRITE_CHR)
    return BLE_ATT_ERR_REQ_NOT_SUPPORTED;

  uint16_t len = OS_MBUF_PKTLEN(ctxt->om);
  if (len < 1 || len > 64)
    return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;

  uint8_t buf[64];
  ble_hs_mbuf_to_flat(ctxt->om, buf, len, NULL);
  uint8_t cmd_id = buf[0];

  if (cmd_id == 1) { // Set Nickname
    if (len > 1) {
      int nick_len = MIN((int)len - 1, 20);
      for (int i = 0; i < nick_len; i++) {
        if (buf[1 + i] < 0x20 || buf[1 + i] > 0x7E)
          buf[1 + i] = '_';
      }
      memcpy(my_nickname, buf + 1, nick_len);
      my_nickname[nick_len] = '\0';
      save_nick_nvs(my_node_id, my_nickname);
      ESP_LOGI(TAG, "Nickname → %s", my_nickname);

      MeshPacket pkt = {};
      pkt.magic = PACKET_MAGIC;
      pkt.type = PKT_NICK_SYNC;
      rotate_session_if_needed();
      pkt.seq = my_seq++;
      pkt.session_id = my_session_id;
      pkt.src_id = my_node_id;
      pkt.dest_id = 0;
      pkt.payload_len = nick_len;
      memcpy(pkt.payload, my_nickname, nick_len);
      send_mesh_packet(&pkt);

      if (ble_conn_handle != BLE_HS_CONN_HANDLE_NONE) {
        ble_gatts_chr_updated(status_val_handle);
        ble_gatts_chr_updated(peers_val_handle);
      }
    }

  } else if (cmd_id == 3) { // Sync Messages
    uint32_t since_ts = 0;
    if (len >= 5) {
      memcpy(&since_ts, buf + 1, 4);
    }
    ESP_LOGI(TAG, "Sync Request received, since ts: %u", (unsigned)since_ts);

    xSemaphoreTake(chat_mutex, portMAX_DELAY);
    history_sync_active = false;
    history_sync_index = 0;
    history_sync_count = 0;
    for (int i = 0; i < chat_count; i++) {
      ChatMessage msg = chat_history[(chat_tail + i) % CHAT_HISTORY_MAX];
      if (msg.ts > since_ts) {
        if (history_sync_count < CHAT_HISTORY_MAX) {
          history_sync_buffer[history_sync_count++] = msg;
        }
      }
    }
    bool has_sync = (history_sync_count > 0);
    if (has_sync) {
      history_sync_active = true;
      history_sync_index = 0;
    }
    xSemaphoreGive(chat_mutex);

    if (has_sync) {
      xTaskCreate(ble_sync_trigger_task, "ble_sync", 2048, NULL, 5, NULL);
    }

    xSemaphoreTake(peer_mutex, portMAX_DELAY);
    for (int i = 0; i < peer_db_count; i++) {
      if (peer_db[i].is_online && peer_db[i].has_client) {
        ESP_LOGI(TAG, "Sending unicast history request to client-bearing peer: %08X", (unsigned)peer_db[i].id);
        MeshPacket req_pkt = {};
        req_pkt.magic = PACKET_MAGIC;
        req_pkt.type = PKT_HISTORY_REQ;
        req_pkt.src_id = my_node_id;
        req_pkt.dest_id = peer_db[i].id;
        rotate_session_if_needed();
        req_pkt.seq = my_seq++;
        req_pkt.session_id = my_session_id;
        req_pkt.payload_len = 0;
        send_mesh_packet(&req_pkt);
      }
    }
    xSemaphoreGive(peer_mutex);

  } else if (cmd_id == 4) { // Time Sync
    if (len >= 5) {
      uint32_t client_time = 0;
      memcpy(&client_time, buf + 1, 4);
      uint32_t uptime = (uint32_t)(esp_timer_get_time() / 1000000ULL);
      mesh_time_offset_s = (client_time > uptime) ? (client_time - uptime) : 0;
      ESP_LOGI(TAG, "Time synced → epoch %u", (unsigned)client_time);
      if (ble_conn_handle != BLE_HS_CONN_HANDLE_NONE) {
        ble_gatts_chr_updated(status_val_handle);
      }
    }
  } else if (cmd_id == 5) { // Rotate Group Key
    ratchet_group_key();
    rotate_session_if_needed();
    if (ble_conn_handle != BLE_HS_CONN_HANDLE_NONE) {
      ble_gatts_chr_updated(status_val_handle);
    }
  }
  return 0;
}

// ─── GATT SERVICE DEFINITIONS ────────────────────────────────────────────

// All UUIDs use the DECAFBAD-CAFE-4BEE-B00B-0000000000xx base
// that matches the iOS/macOS app definitions.
static const ble_uuid128_t mesh_svc_uuid = {
    .u = {.type = BLE_UUID_TYPE_128},
    .value = {0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0B, 0xB0, 0xEE, 0x4B,
              0xFE, 0xCA, 0xAD, 0xFB, 0xCA, 0xDE}};
static const ble_uuid128_t mesh_chr_status_uuid = {
    .u = {.type = BLE_UUID_TYPE_128},
    .value = {0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0B, 0xB0, 0xEE, 0x4B,
              0xFE, 0xCA, 0xAD, 0xFB, 0xCA, 0xDE}};
static const ble_uuid128_t mesh_chr_peers_uuid = {
    .u = {.type = BLE_UUID_TYPE_128},
    .value = {0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0B, 0xB0, 0xEE, 0x4B,
              0xFE, 0xCA, 0xAD, 0xFB, 0xCA, 0xDE}};
static const ble_uuid128_t mesh_chr_chat_uuid = {
    .u = {.type = BLE_UUID_TYPE_128},
    .value = {0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0B, 0xB0, 0xEE, 0x4B,
              0xFE, 0xCA, 0xAD, 0xFB, 0xCA, 0xDE}};
static const ble_uuid128_t mesh_chr_cmd_uuid = {
    .u = {.type = BLE_UUID_TYPE_128},
    .value = {0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0B, 0xB0, 0xEE, 0x4B,
              0xFE, 0xCA, 0xAD, 0xFB, 0xCA, 0xDE}};
static const ble_uuid128_t mesh_chr_ecdh_uuid = {
    .u = {.type = BLE_UUID_TYPE_128},
    .value = {0x05, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0B, 0xB0, 0xEE, 0x4B,
              0xFE, 0xCA, 0xAD, 0xFB, 0xCA, 0xDE}};
static const ble_uuid128_t mesh_chr_ota_uuid = {
    .u = {.type = BLE_UUID_TYPE_128},
    .value = {0x06, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0B, 0xB0, 0xEE, 0x4B,
              0xFE, 0xCA, 0xAD, 0xFB, 0xCA, 0xDE}};

const struct ble_gatt_svc_def ble_svc_defs[] = {
    {
        .type = BLE_GATT_SVC_TYPE_PRIMARY,
        .uuid = &mesh_svc_uuid.u,
        .characteristics =
            (struct ble_gatt_chr_def[]){
                {
                    .uuid = &mesh_chr_status_uuid.u,
                    .access_cb = ble_chr_status_cb,
                    .flags = BLE_GATT_CHR_F_READ | BLE_GATT_CHR_F_NOTIFY,
                },
                {
                    .uuid = &mesh_chr_peers_uuid.u,
                    .access_cb = ble_chr_peers_cb,
                    .flags = BLE_GATT_CHR_F_READ | BLE_GATT_CHR_F_NOTIFY,
                },
                {
                    .uuid = &mesh_chr_chat_uuid.u,
                    .access_cb = ble_chr_chat_cb,
                    .flags = BLE_GATT_CHR_F_READ | BLE_GATT_CHR_F_WRITE |
                             BLE_GATT_CHR_F_NOTIFY,
                },
                {
                    .uuid = &mesh_chr_cmd_uuid.u,
                    .access_cb = ble_chr_cmd_cb,
                    .flags = BLE_GATT_CHR_F_WRITE,
                },
                {
                    .uuid = &mesh_chr_ecdh_uuid.u,
                    .access_cb = ble_chr_ecdh_cb,
                    .flags = BLE_GATT_CHR_F_READ | BLE_GATT_CHR_F_WRITE,
                },
                {
                    .uuid = &mesh_chr_ota_uuid.u,
                    .access_cb = ble_chr_ota_cb,
                    .flags = BLE_GATT_CHR_F_WRITE | BLE_GATT_CHR_F_WRITE_NO_RSP |
                             BLE_GATT_CHR_F_NOTIFY,
                },
                {0},
            },
    },
    {0},
};

// ─── GAP / ADVERTISING ───────────────────────────────────────────────────

void ble_advertise(void) {
  struct ble_hs_adv_fields fields = {};
  fields.flags = BLE_HS_ADV_F_DISC_GEN | BLE_HS_ADV_F_BREDR_UNSUP;
  fields.uuids128 = (ble_uuid128_t *)&mesh_svc_uuid;
  fields.num_uuids128 = 1;
  fields.uuids128_is_complete = 1;
  if (ble_gap_adv_set_fields(&fields) != 0)
    return;

  char adv_name[32];
  snprintf(adv_name, sizeof(adv_name), "MeshOS_%08X", (unsigned)my_node_id);
  struct ble_hs_adv_fields rsp = {};
  rsp.name = (uint8_t *)adv_name;
  rsp.name_len = strlen(adv_name);
  rsp.name_is_complete = 1;
  if (ble_gap_adv_rsp_set_fields(&rsp) != 0)
    return;

  struct ble_gap_adv_params params = {};
  params.conn_mode = BLE_GAP_CONN_MODE_UND;
  params.disc_mode = BLE_GAP_DISC_MODE_GEN;
  params.itvl_min = 160;
  params.itvl_max = 320;
  ble_gap_adv_start(ble_own_addr_type, NULL, BLE_HS_FOREVER, &params,
                    ble_gap_event, NULL);
}

static bool s_advertising_active = false;

void ble_advertise_task(void *pvParameters) {
  if (s_advertising_active) {
    vTaskDelete(NULL);
    return;
  }
  s_advertising_active = true;
  
  vTaskDelay(pdMS_TO_TICKS(200));
  ble_advertise();
  
  s_advertising_active = false;
  vTaskDelete(NULL);
}

int ble_gap_event(struct ble_gap_event *event, void *arg) {
  struct ble_gap_conn_desc desc;
  switch (event->type) {
  case BLE_GAP_EVENT_CONNECT:
    ESP_LOGI(TAG, "BLE connected");
    ble_conn_handle = event->connect.conn_handle;
    ble_gap_adv_stop();
    
    struct ble_gap_upd_params conn_params = {
        .itvl_min = 24,
        .itvl_max = 40,
        .latency = 0,
        .supervision_timeout = 400,
        .min_ce_len = 0,
        .max_ce_len = 0,
    };
    ble_gap_update_params(ble_conn_handle, &conn_params);
    break;

  case BLE_GAP_EVENT_DISCONNECT:
    ESP_LOGI(TAG, "BLE disconnected (reason %d)", event->disconnect.reason);
    ble_conn_handle = BLE_HS_CONN_HANDLE_NONE;
    ble_session_established = false;
    memset(ble_session_key, 0, 16);
    
    if (ota_in_progress) {
      if (ota_update_handle != 0) {
        esp_ota_abort(ota_update_handle);
      }
      ota_in_progress = false;
      ota_update_handle = 0;
      ESP_LOGW("OTA", "OTA session aborted due to client disconnection");
    }
    
    xTaskCreate(ble_advertise_task, "ble_adv", 2048, NULL, 5, NULL);
    break;

  case BLE_GAP_EVENT_REPEAT_PAIRING:
    if (ble_gap_conn_find(event->repeat_pairing.conn_handle, &desc) == 0) {
      ble_store_util_delete_peer(&desc.peer_id_addr);
    }
    return BLE_GAP_REPEAT_PAIRING_RETRY;

  default:
    break;
  }
  return 0;
}

void gatt_svr_register_cb(struct ble_gatt_register_ctxt *ctxt,
                                 void *arg) {
  if (ctxt->op != BLE_GATT_REGISTER_OP_CHR)
    return;

  static const ble_uuid128_t s_uuid = {
      .u = {.type = BLE_UUID_TYPE_128},
      .value = {0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0B, 0xB0, 0xEE, 0x4B,
                0xFE, 0xCA, 0xAD, 0xFB, 0xCA, 0xDE}};
  static const ble_uuid128_t p_uuid = {
      .u = {.type = BLE_UUID_TYPE_128},
      .value = {0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0B, 0xB0, 0xEE, 0x4B,
                0xFE, 0xCA, 0xAD, 0xFB, 0xCA, 0xDE}};
  static const ble_uuid128_t c_uuid = {
      .u = {.type = BLE_UUID_TYPE_128},
      .value = {0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0B, 0xB0, 0xEE, 0x4B,
                0xFE, 0xCA, 0xAD, 0xFB, 0xCA, 0xDE}};
  static const ble_uuid128_t k_uuid = {
      .u = {.type = BLE_UUID_TYPE_128},
      .value = {0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0B, 0xB0, 0xEE, 0x4B,
                0xFE, 0xCA, 0xAD, 0xFB, 0xCA, 0xDE}};
  static const ble_uuid128_t e_uuid = {
      .u = {.type = BLE_UUID_TYPE_128},
      .value = {0x05, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0B, 0xB0, 0xEE, 0x4B,
                0xFE, 0xCA, 0xAD, 0xFB, 0xCA, 0xDE}};
  static const ble_uuid128_t o_uuid = {
      .u = {.type = BLE_UUID_TYPE_128},
      .value = {0x06, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0B, 0xB0, 0xEE, 0x4B,
                0xFE, 0xCA, 0xAD, 0xFB, 0xCA, 0xDE}};

  if (ble_uuid_cmp(ctxt->chr.chr_def->uuid, &s_uuid.u) == 0)
    status_val_handle = ctxt->chr.val_handle;
  else if (ble_uuid_cmp(ctxt->chr.chr_def->uuid, &p_uuid.u) == 0)
    peers_val_handle = ctxt->chr.val_handle;
  else if (ble_uuid_cmp(ctxt->chr.chr_def->uuid, &c_uuid.u) == 0)
    chat_val_handle = ctxt->chr.val_handle;
  else if (ble_uuid_cmp(ctxt->chr.chr_def->uuid, &k_uuid.u) == 0)
    cmd_val_handle = ctxt->chr.val_handle;
  else if (ble_uuid_cmp(ctxt->chr.chr_def->uuid, &e_uuid.u) == 0)
    ecdh_val_handle = ctxt->chr.val_handle;
  else if (ble_uuid_cmp(ctxt->chr.chr_def->uuid, &o_uuid.u) == 0)
    ota_val_handle = ctxt->chr.val_handle;
}

void ble_host_task(void *param) {
  nimble_port_run();
  nimble_port_freertos_deinit();
}

void ble_on_sync(void) {
  ble_hs_id_infer_auto(0, &ble_own_addr_type);
  ble_att_set_preferred_mtu(512);
  ble_advertise();
}

void ble_sync_trigger_task(void *pvParameters) {
  int remaining = CHAT_HISTORY_MAX;
  while (remaining-- > 0) {
    if (ble_conn_handle == BLE_HS_CONN_HANDLE_NONE) {
      ESP_LOGW(TAG, "BLE disconnected during history sync, aborting");
      break;
    }

    xSemaphoreTake(chat_mutex, portMAX_DELAY);
    bool active = history_sync_active && (history_sync_index < history_sync_count);
    xSemaphoreGive(chat_mutex);
    if (!active) break;

    ble_gatts_chr_updated(chat_val_handle);
    vTaskDelay(pdMS_TO_TICKS(30));
  }
  vTaskDelete(NULL);
}
