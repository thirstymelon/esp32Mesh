#include <stdio.h>
#include <string.h>

// FreeRTOS
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"

// NVS
#include "nvs.h"
#include "nvs_flash.h"

// Wi-Fi / ESP-NOW
#include "esp_event.h"
#include "esp_log.h"
#include "esp_mac.h"
#include "esp_netif.h"
#include "esp_now.h"
#include "esp_random.h"
#include "esp_timer.h"
#include "esp_wifi.h"

// NimBLE
#include "host/ble_att.h"
#include "host/ble_hs.h"
#include "host/ble_store.h"
#include "host/ble_uuid.h"
#include "nimble/nimble_port.h"
#include "nimble/nimble_port_freertos.h"
#include "services/gap/ble_svc_gap.h"
#include "services/gatt/ble_svc_gatt.h"
#include "store/config/ble_store_config.h"

// mbedTLS Cryptography & ECDH
#include "mbedtls/gcm.h"
#include "mbedtls/sha256.h"
#include "mbedtls/ecdh.h"
#include "mbedtls/entropy.h"
#include "mbedtls/ctr_drbg.h"

void ble_store_config_init(void);

static const char *TAG = "MeshOS";

// ─── STATIC CRYPTO KEYS & SECURITY STATE ─────────────────────────────────
static const uint8_t AES_KEY[16] = {
    0x4D, 0x65, 0x73, 0x68, 0x4F, 0x53, 0x4B, 0x65,
    0x79, 0x31, 0x32, 0x33, 0x21, 0x40, 0x23, 0x24}; // "MeshOSKey123!@#$"

#define AES_GCM_NONCE_LEN 12
#define AES_GCM_TAG_LEN 16
#define AES_GCM_OVERHEAD (AES_GCM_NONCE_LEN + AES_GCM_TAG_LEN) // 28 bytes

#ifndef MIN
#define MIN(a, b) ((a) < (b) ? (a) : (b))
#endif

#define MAX_PEERS 32
#define MAX_NEIGHBORS 16

// Max plaintext per chat packet: 200 payload bytes − 28 AES overhead - 1 channel_id = 171
#define MAX_TEXT_LEN 171
#define MESH_PAYLOAD_MAX 200

// BLE Connection Security (ECDH)
static uint8_t ble_session_key[16];
static bool ble_session_established = false;
static uint8_t server_pub_key[65]; // 0x04 + 64 bytes P-256 public key

// Group Key Ratchet (Broadcasts)
static uint8_t current_group_key[16] = {
    0x4D, 0x65, 0x73, 0x68, 0x4F, 0x53, 0x4B, 0x65,
    0x79, 0x31, 0x32, 0x33, 0x21, 0x40, 0x23, 0x24};
static uint8_t group_key_epoch = 0;

static void ratchet_group_key(void) {
  mbedtls_sha256_context sha_ctx;
  mbedtls_sha256_init(&sha_ctx);
  mbedtls_sha256_starts(&sha_ctx, 0);
  mbedtls_sha256_update(&sha_ctx, current_group_key, 16);
  uint8_t hash[32];
  mbedtls_sha256_finish(&sha_ctx, hash);
  mbedtls_sha256_free(&sha_ctx);
  memcpy(current_group_key, hash, 16);
  group_key_epoch++;
  ESP_LOGI(TAG, "Group key ratcheted to epoch %u", (unsigned)group_key_epoch);
}

static const uint8_t *get_group_key_for_epoch(uint8_t epoch) {
  if (epoch == group_key_epoch) {
    return current_group_key;
  }
  if (epoch > group_key_epoch) {
    while (group_key_epoch < epoch) {
      ratchet_group_key();
    }
    return current_group_key;
  }
  // Fallback to current key for past epochs
  return current_group_key;
}

// ─── AES-GCM HELPERS ─────────────────────────────────────────────────────

static int aes_gcm_encrypt(const uint8_t *plaintext, size_t len,
                           const uint8_t *key,
                           uint8_t *out_nonce, uint8_t *out_ciphertext,
                           uint8_t *out_tag) {
  esp_fill_random(out_nonce, AES_GCM_NONCE_LEN);
  mbedtls_gcm_context ctx;
  mbedtls_gcm_init(&ctx);
  int ret = mbedtls_gcm_setkey(&ctx, MBEDTLS_CIPHER_ID_AES, key, 128);
  if (ret == 0) {
    ret = mbedtls_gcm_crypt_and_tag(&ctx, MBEDTLS_GCM_ENCRYPT, len, out_nonce,
                                    AES_GCM_NONCE_LEN, NULL, 0, plaintext,
                                    out_ciphertext, AES_GCM_TAG_LEN, out_tag);
  }
  mbedtls_gcm_free(&ctx);
  return ret;
}

static int aes_gcm_decrypt(const uint8_t *ciphertext, size_t len,
                           const uint8_t *key,
                           const uint8_t *nonce, const uint8_t *tag,
                           uint8_t *out_plaintext) {
  mbedtls_gcm_context ctx;
  mbedtls_gcm_init(&ctx);
  int ret = mbedtls_gcm_setkey(&ctx, MBEDTLS_CIPHER_ID_AES, key, 128);
  if (ret == 0) {
    ret = mbedtls_gcm_auth_decrypt(&ctx, len, nonce, AES_GCM_NONCE_LEN, NULL, 0,
                                   tag, AES_GCM_TAG_LEN, ciphertext,
                                   out_plaintext);
  }
  mbedtls_gcm_free(&ctx);
  return ret;
}

// ─── DATA STRUCTURES ─────────────────────────────────────────────────────

struct ChatMessage {
  uint32_t sender;
  uint32_t dest;
  uint32_t ts;
  uint8_t flags;               // bit0: is_me, bit1: is_dm
  uint16_t session_id;
  uint16_t seq;
  uint8_t channel_id;          // Channel number
  char text[MAX_TEXT_LEN + 1]; // plaintext, null-terminated
};
typedef struct ChatMessage ChatMessage;

struct PeerEntry {
  uint32_t id;
  char nick[21];
  uint32_t last_seen_ms;
  uint32_t neighbors[MAX_NEIGHBORS];
  uint8_t neighbor_count;
  bool is_online;
};
typedef struct PeerEntry PeerEntry;

enum PacketType { PKT_HEARTBEAT = 0, PKT_CHAT = 2, PKT_NICK_SYNC = 3, PKT_HISTORY_REQ = 4 };

struct MeshPacket {
  uint16_t magic;
  uint8_t type;
  uint8_t epoch;
  uint16_t seq;
  uint16_t session_id;
  uint32_t src_id;
  uint32_t dest_id;
  uint16_t payload_len;
  uint8_t payload[MESH_PAYLOAD_MAX];
} __attribute__((packed));
typedef struct MeshPacket MeshPacket;

#define PACKET_MAGIC 0xC0DE

// BLE notification/read wire format for chat:
// [4 sender][4 dest][4 ts][1 flags][2 session_id][2 seq][1 channel_id][12 nonce][N ciphertext][16 tag]
#define CHAT_HDR_LEN 18

// ─── GATT HANDLES & GLOBALS ──────────────────────────────────────────────

static uint16_t status_val_handle;
static uint16_t peers_val_handle;
static uint16_t chat_val_handle;
static uint16_t cmd_val_handle;
static uint16_t ecdh_val_handle;

static uint16_t ble_conn_handle = BLE_HS_CONN_HANDLE_NONE;
static uint8_t ble_own_addr_type = 0;

static void send_mesh_packet(MeshPacket *pkt); // forward decl

static uint32_t my_node_id = 0;
static char my_nickname[21] = "Unknown";
static uint16_t my_session_id = 0;
static uint16_t my_seq = 0;
static uint32_t mesh_time_offset_s = 0;

// ─── RING BUFFER (CHAT HISTORY) ──────────────────────────────────────────

#define CHAT_HISTORY_MAX 30
static ChatMessage chat_history[CHAT_HISTORY_MAX];
static int chat_tail = 0;
static int chat_count = 0;
static SemaphoreHandle_t chat_mutex = NULL;

// ─── PEER DATABASE ───────────────────────────────────────────────────────

static PeerEntry peer_db[MAX_PEERS];
static int peer_db_count = 0;
static SemaphoreHandle_t peer_mutex = NULL;

// ─── DUPLICATE FILTER ────────────────────────────────────────────────────

static uint32_t dup_hashes[48] = {0};
static int dup_head = 0;
static SemaphoreHandle_t hash_mutex = NULL;

// ─── STATIC SERIALISATION BUFFERS (no heap allocation) ──────────────────
static uint8_t s_peers_buf[3072];
static SemaphoreHandle_t peers_buf_mutex = NULL;

static ChatMessage s_sync_snap[CHAT_HISTORY_MAX];
static uint8_t s_notify_buf[CHAT_HDR_LEN + AES_GCM_OVERHEAD + MAX_TEXT_LEN + 1];
static uint8_t s_chat_read_buf[CHAT_HDR_LEN + AES_GCM_OVERHEAD + MAX_TEXT_LEN + 1];

// ─── AUTO-NICKNAME WORDS ─────────────────────────────────────────────────

static const char *ADJS[] = {"Swift", "Bold",  "Bright", "Dark", "Fast",
                             "Cool",  "Sharp", "Wild",   "Keen", "Calm"};
static const char *NOUNS[] = {"Fox",  "Hawk", "Wolf", "Bear", "Lynx",
                               "Kite", "Wren", "Crab", "Moth", "Ibis"};

static void get_auto_nick(uint32_t id, char *buf, size_t max_len) {
  snprintf(buf, max_len, "%s%s", ADJS[id % 10], NOUNS[(id >> 4) % 10]);
}

// Nickname sanitization helper (ASCII validation)
static void sanitize_ascii(char *str, size_t max_len) {
  for (size_t i = 0; i < max_len && str[i] != '\0'; i++) {
    if ((uint8_t)str[i] < 0x20 || (uint8_t)str[i] > 0x7E) {
      str[i] = '_';
    }
  }
}

// ─── DUPLICATE DETECTION ─────────────────────────────────────────────────

static uint32_t djb2(const uint8_t *data, size_t len) {
  uint32_t h = 5381;
  for (size_t i = 0; i < len; i++)
    h = ((h << 5) + h) ^ data[i];
  return h ? h : 1;
}

static bool is_duplicate(uint32_t sender_id, uint16_t session_id, uint16_t seq) {
  uint8_t buf[8];
  memcpy(buf, &sender_id, 4);
  memcpy(buf + 4, &session_id, 2);
  memcpy(buf + 6, &seq, 2);
  uint32_t h = djb2(buf, 8);

  xSemaphoreTake(hash_mutex, portMAX_DELAY);
  for (int i = 0; i < 48; i++) {
    if (dup_hashes[i] == h) {
      xSemaphoreGive(hash_mutex);
      return true;
    }
  }
  dup_hashes[dup_head] = h;
  dup_head = (dup_head + 1) % 48;
  xSemaphoreGive(hash_mutex);
  return false;
}

// ─── NVS NICKNAME PERSISTENCE ────────────────────────────────────────────

static void save_nick_nvs(uint32_t id, const char *nick) {
  nvs_handle_t h;
  if (nvs_open("mesh_nvs", NVS_READWRITE, &h) != ESP_OK)
    return;
  if (id == my_node_id) {
    nvs_set_str(h, "my_nick", nick);
  } else {
    char key[16];
    snprintf(key, sizeof(key), "n_%x", (unsigned)id);
    nvs_set_str(h, key, nick);
  }
  nvs_commit(h);
  nvs_close(h);
}

static void load_nick_nvs(uint32_t id, char *out, size_t max_len) {
  nvs_handle_t h;
  bool found = false;
  if (nvs_open("mesh_nvs", NVS_READONLY, &h) == ESP_OK) {
    size_t sz = max_len;
    if (id == my_node_id) {
      found = (nvs_get_str(h, "my_nick", out, &sz) == ESP_OK);
    } else {
      char key[16];
      snprintf(key, sizeof(key), "n_%x", (unsigned)id);
      found = (nvs_get_str(h, key, out, &sz) == ESP_OK);
    }
    nvs_close(h);
  }
  if (!found)
    get_auto_nick(id, out, max_len);
}

// ─── CHAT HISTORY ────────────────────────────────────────────────────────

static void add_to_history(uint32_t sender, uint32_t dest, uint8_t flags,
                           const char *plaintext, uint32_t ts, uint16_t session_id, uint16_t seq, uint8_t channel_id) {
  xSemaphoreTake(chat_mutex, portMAX_DELAY);
  int idx;
  if (chat_count < CHAT_HISTORY_MAX) {
    idx = (chat_tail + chat_count) % CHAT_HISTORY_MAX;
    chat_count++;
  } else {
    idx = chat_tail;
    chat_tail = (chat_tail + 1) % CHAT_HISTORY_MAX;
  }
  chat_history[idx].sender = sender;
  chat_history[idx].dest = dest;
  chat_history[idx].ts = ts;
  chat_history[idx].flags = flags;
  chat_history[idx].session_id = session_id;
  chat_history[idx].seq = seq;
  chat_history[idx].channel_id = channel_id;
  strncpy(chat_history[idx].text, plaintext, MAX_TEXT_LEN);
  chat_history[idx].text[MAX_TEXT_LEN] = '\0';
  xSemaphoreGive(chat_mutex);

  if (ble_conn_handle != BLE_HS_CONN_HANDLE_NONE) {
    ble_gatts_chr_updated(chat_val_handle);
  }
}

// ─── PEER DATABASE MANAGEMENT ────────────────────────────────────────────

static void compact_peer_db(void) {
  int write = 0;
  for (int read = 0; read < peer_db_count; read++) {
    if (peer_db[read].is_online) {
      if (write != read)
        peer_db[write] = peer_db[read];
      write++;
    }
  }
  peer_db_count = write;
  ESP_LOGI(TAG, "Peer DB compacted → %d active peers", write);
}

static PeerEntry *peer_find_or_insert(uint32_t id) {
  for (int i = 0; i < peer_db_count; i++) {
    if (peer_db[i].id == id)
      return &peer_db[i];
  }
  if (peer_db_count >= MAX_PEERS) {
    compact_peer_db();
  }
  if (peer_db_count < MAX_PEERS) {
    PeerEntry *p = &peer_db[peer_db_count++];
    memset(p, 0, sizeof(PeerEntry));
    p->id = id;
    return p;
  }
  return NULL;
}

static void update_peer_nick(uint32_t id, const char *nick) {
  if (id == my_node_id) return;
  bool is_new = false;

  xSemaphoreTake(peer_mutex, portMAX_DELAY);
  PeerEntry *p = peer_find_or_insert(id);
  if (p) {
    if (p->last_seen_ms == 0)
      is_new = true;
    strncpy(p->nick, nick, 20);
    p->nick[20] = '\0';
    sanitize_ascii(p->nick, 20);
    p->is_online = true;
    p->last_seen_ms = esp_log_timestamp();
  }
  xSemaphoreGive(peer_mutex);

  if (is_new)
    save_nick_nvs(id, nick);

  if (ble_conn_handle != BLE_HS_CONN_HANDLE_NONE) {
    ble_gatts_chr_updated(peers_val_handle);
  }
}

static void update_peer_heartbeat(uint32_t id, const char *nick,
                                  const uint32_t *neighbors,
                                  uint8_t neighbor_count) {
  if (id == my_node_id) return;
  bool is_new = false;

  xSemaphoreTake(peer_mutex, portMAX_DELAY);
  PeerEntry *p = peer_find_or_insert(id);
  if (p) {
    if (p->last_seen_ms == 0)
      is_new = true;
    strncpy(p->nick, nick, 20);
    p->nick[20] = '\0';
    sanitize_ascii(p->nick, 20);
    p->is_online = true;
    p->last_seen_ms = esp_log_timestamp();
    p->neighbor_count = MIN(neighbor_count, MAX_NEIGHBORS);
    memcpy(p->neighbors, neighbors, p->neighbor_count * 4);
  }
  xSemaphoreGive(peer_mutex);

  if (is_new)
    save_nick_nvs(id, nick);
  if (ble_conn_handle != BLE_HS_CONN_HANDLE_NONE) {
    ble_gatts_chr_updated(peers_val_handle);
  }
}

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

// ─── ESP-NOW RECEIVE CALLBACK ────────────────────────────────────────────

static void esp_now_recv_cb(const esp_now_recv_info_t *recv_info,
                             const uint8_t *data, int len) {
  if (len < (int)(sizeof(MeshPacket) - MESH_PAYLOAD_MAX))
    return;

  MeshPacket pkt;
  memcpy(&pkt, data, MIN((int)sizeof(MeshPacket), len));
  if (pkt.magic != PACKET_MAGIC)
    return;
  if (pkt.src_id == my_node_id)
    return;
  if (is_duplicate(pkt.src_id, pkt.session_id, pkt.seq))
    return;

  if (pkt.type == PKT_HEARTBEAT) {
    send_mesh_packet(&pkt); // Relay

    if (pkt.payload_len >= 22) {
      char nick[22];
      memcpy(nick, pkt.payload, 21);
      nick[21] = '\0';
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
      update_peer_heartbeat(pkt.src_id, nick, neighbors, valid);
    }

  } else if (pkt.type == PKT_NICK_SYNC) {
    char nick[21];
    int cplen = MIN((int)pkt.payload_len, 20);
    memcpy(nick, pkt.payload, cplen);
    nick[cplen] = '\0';
    update_peer_nick(pkt.src_id, nick);
    ESP_LOGI(TAG, "Sync Nick %u: %s", pkt.src_id, nick);
    send_mesh_packet(&pkt);

  } else if (pkt.type == PKT_HISTORY_REQ) {
    send_mesh_packet(&pkt); // Relay request

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

  } else if (pkt.type == PKT_CHAT) {
    if (pkt.payload_len < (uint16_t)AES_GCM_OVERHEAD)
      return;
    size_t cipher_len = pkt.payload_len - AES_GCM_OVERHEAD;
    if (cipher_len == 0 || cipher_len > (MAX_TEXT_LEN + 1))
      return;

    const uint8_t *nonce = pkt.payload;
    const uint8_t *ciphertext = pkt.payload + AES_GCM_NONCE_LEN;
    const uint8_t *tag = ciphertext + cipher_len;

    // Decrypt based on destination
    const uint8_t *key = (pkt.dest_id == 0) ? get_group_key_for_epoch(pkt.epoch) : AES_KEY;

    uint8_t decrypted[MAX_TEXT_LEN + 2] = {0};
    if (aes_gcm_decrypt(ciphertext, cipher_len, key, nonce, tag, decrypted) != 0) {
      ESP_LOGW(TAG, "Auth decrypt failed from node %u", pkt.src_id);
      return;
    }

    // Packet contains: [1 channel_id][N text]
    uint8_t channel_id = decrypted[0];
    char *text = (char *)(decrypted + 1);
    size_t text_len = cipher_len - 1;
    text[text_len] = '\0';

    uint32_t now_ts =
        (uint32_t)(esp_timer_get_time() / 1000000ULL) + mesh_time_offset_s;

    if (pkt.dest_id == 0) {
      ESP_LOGI(TAG, "Broadcast from %u (ch %u): %s", pkt.src_id, channel_id, text);
      add_to_history(pkt.src_id, 0, 0, text, now_ts, pkt.session_id, pkt.seq, channel_id);
      send_mesh_packet(&pkt); // Relay
    } else if (pkt.dest_id == my_node_id) {
      ESP_LOGI(TAG, "DM from %u: %s", pkt.src_id, text);
      add_to_history(pkt.src_id, my_node_id, 2, text, now_ts, pkt.session_id, pkt.seq, channel_id);
    } else {
      send_mesh_packet(&pkt); // Relay DM
    }
  }
}

// ─── ESP-NOW SEND WITH RETRY & RE-REGISTRATION ───────────────────────────

static void send_mesh_packet(MeshPacket *pkt) {
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

// ─── GATT CALLBACKS ──────────────────────────────────────────────────────

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
  payload[10] = group_key_epoch; // key epoch at byte 10
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

// BLE write (app→firmware): [4 dest_id][1 channel_id][12 nonce][N ciphertext][16 tag]
#define CHAT_WRITE_MIN (4 + 1 + AES_GCM_OVERHEAD + 1)

static int ble_chr_chat_cb(uint16_t conn_handle, uint16_t attr_handle,
                           struct ble_gatt_access_ctxt *ctxt, void *arg) {
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
    size_t cipher_len = blob_len - AES_GCM_OVERHEAD;
    if (cipher_len > MAX_TEXT_LEN)
      cipher_len = MAX_TEXT_LEN;

    const uint8_t *nonce = blob;
    const uint8_t *ciphertext = blob + AES_GCM_NONCE_LEN;
    const uint8_t *tag = ciphertext + cipher_len;

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
    uint16_t current_seq = my_seq++;
    add_to_history(my_node_id, dest_id, flags, plaintext, now_ts, my_session_id, current_seq, channel_id);

    // Mesh encryption: prefix text with channel_id
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
    if (chat_count == 0) {
      xSemaphoreGive(chat_mutex);
      return 0;
    }
    int latest = (chat_tail + chat_count - 1) % CHAT_HISTORY_MAX;
    ChatMessage msg = chat_history[latest];
    xSemaphoreGive(chat_mutex);

    size_t tlen = strnlen(msg.text, MAX_TEXT_LEN);
    uint8_t nonce[AES_GCM_NONCE_LEN], cipher[MAX_TEXT_LEN],
        tag[AES_GCM_TAG_LEN];
    const uint8_t *key = ble_session_established ? ble_session_key : AES_KEY;

    if (aes_gcm_encrypt((uint8_t *)msg.text, tlen, key, nonce, cipher, tag) != 0) {
      return BLE_ATT_ERR_UNLIKELY;
    }

    int off = 0;
    memcpy(s_chat_read_buf + off, &msg.sender, 4);
    off += 4;
    memcpy(s_chat_read_buf + off, &msg.dest, 4);
    off += 4;
    memcpy(s_chat_read_buf + off, &msg.ts, 4);
    off += 4;
    s_chat_read_buf[off++] = msg.flags;
    memcpy(s_chat_read_buf + off, &msg.session_id, 2);
    off += 2;
    memcpy(s_chat_read_buf + off, &msg.seq, 2);
    off += 2;
    s_chat_read_buf[off++] = msg.channel_id;

    memcpy(s_chat_read_buf + off, nonce, AES_GCM_NONCE_LEN);
    off += AES_GCM_NONCE_LEN;
    memcpy(s_chat_read_buf + off, cipher, tlen);
    off += tlen;
    memcpy(s_chat_read_buf + off, tag, AES_GCM_TAG_LEN);
    off += AES_GCM_TAG_LEN;

    os_mbuf_append(ctxt->om, s_chat_read_buf, off);
    return 0;
  }
  return BLE_ATT_ERR_REQ_NOT_SUPPORTED;
}

// ECDH Key Exchange GATT callback
static int ble_chr_ecdh_cb(uint16_t conn_handle, uint16_t attr_handle,
                           struct ble_gatt_access_ctxt *ctxt, void *arg) {
  if (ctxt->op == BLE_GATT_ACCESS_OP_WRITE_CHR) {
    uint16_t len = OS_MBUF_PKTLEN(ctxt->om);
    if (len != 65) return BLE_ATT_ERR_INVALID_ATTR_VALUE_LEN;

    uint8_t client_pub[65];
    ble_hs_mbuf_to_flat(ctxt->om, client_pub, 65, NULL);

    if (client_pub[0] != 0x04) return BLE_ATT_ERR_UNLIKELY;

    mbedtls_ecdh_context ecdh;
    mbedtls_ecdh_init(&ecdh);

    mbedtls_entropy_context entropy;
    mbedtls_ctr_drbg_context ctr_drbg;
    mbedtls_entropy_init(&entropy);
    mbedtls_ctr_drbg_init(&ctr_drbg);
    const char *pers = "mesh_ecdh";
    mbedtls_ctr_drbg_seed(&ctr_drbg, mbedtls_entropy_func, &entropy, (const uint8_t *)pers, strlen(pers));

    if (mbedtls_ecdh_setup(&ecdh, MBEDTLS_ECP_DP_SECP256R1) != 0) {
      goto cleanup;
    }

    size_t olen = 0;
    if (mbedtls_ecdh_make_public(&ecdh, &olen, server_pub_key, 65, mbedtls_ctr_drbg_random, &ctr_drbg) != 0) {
      goto cleanup;
    }

    if (mbedtls_ecdh_read_public(&ecdh, client_pub, 65) != 0) {
      goto cleanup;
    }

    uint8_t secret[32];
    size_t secret_len = 0;
    if (mbedtls_ecdh_calc_secret(&ecdh, &secret_len, secret, 32, mbedtls_ctr_drbg_random, &ctr_drbg) == 0) {
      mbedtls_sha256_context sha;
      mbedtls_sha256_init(&sha);
      mbedtls_sha256_starts(&sha, 0);
      mbedtls_sha256_update(&sha, secret, 32);
      uint8_t hash[32];
      mbedtls_sha256_finish(&sha, hash);
      mbedtls_sha256_free(&sha);

      memcpy(ble_session_key, hash, 16);
      ble_session_established = true;
      ESP_LOGI(TAG, "ECDH session established!");
    }

  cleanup:
    mbedtls_ctr_drbg_free(&ctr_drbg);
    mbedtls_entropy_free(&entropy);
    mbedtls_ecdh_free(&ecdh);
    return 0;

  } else if (ctxt->op == BLE_GATT_ACCESS_OP_READ_CHR) {
    if (!ble_session_established) return BLE_ATT_ERR_UNLIKELY;
    os_mbuf_append(ctxt->om, server_pub_key, 65);
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

    int snap_count = 0;
    xSemaphoreTake(chat_mutex, portMAX_DELAY);
    for (int i = 0; i < chat_count; i++) {
      ChatMessage msg = chat_history[(chat_tail + i) % CHAT_HISTORY_MAX];
      if (msg.ts > since_ts) {
        s_sync_snap[snap_count++] = msg;
      }
    }
    xSemaphoreGive(chat_mutex);

    for (int i = 0; i < snap_count; i++) {
      size_t tlen = strnlen(s_sync_snap[i].text, MAX_TEXT_LEN);
      uint8_t nonce[AES_GCM_NONCE_LEN], cipher[MAX_TEXT_LEN],
          tag[AES_GCM_TAG_LEN];
      const uint8_t *key = ble_session_established ? ble_session_key : AES_KEY;

      if (aes_gcm_encrypt((uint8_t *)s_sync_snap[i].text, tlen, key, nonce, cipher,
                          tag) != 0)
        continue;

      int off = 0;
      memcpy(s_notify_buf + off, &s_sync_snap[i].sender, 4);
      off += 4;
      memcpy(s_notify_buf + off, &s_sync_snap[i].dest, 4);
      off += 4;
      memcpy(s_notify_buf + off, &s_sync_snap[i].ts, 4);
      off += 4;
      s_notify_buf[off++] = s_sync_snap[i].flags;
      memcpy(s_notify_buf + off, &s_sync_snap[i].session_id, 2);
      off += 2;
      memcpy(s_notify_buf + off, &s_sync_snap[i].seq, 2);
      off += 2;
      s_notify_buf[off++] = s_sync_snap[i].channel_id;

      memcpy(s_notify_buf + off, nonce, AES_GCM_NONCE_LEN);
      off += AES_GCM_NONCE_LEN;
      memcpy(s_notify_buf + off, cipher, tlen);
      off += tlen;
      memcpy(s_notify_buf + off, tag, AES_GCM_TAG_LEN);
      off += AES_GCM_TAG_LEN;

      struct os_mbuf *om = ble_hs_mbuf_from_flat(s_notify_buf, off);
      if (om)
        ble_gatts_notify_custom(conn_handle, chat_val_handle, om);
      vTaskDelay(pdMS_TO_TICKS(30));
    }

    // Also broadcast a history request over ESP-NOW to fetch older messages from other nodes
    MeshPacket req_pkt = {};
    req_pkt.magic = PACKET_MAGIC;
    req_pkt.type = PKT_HISTORY_REQ;
    req_pkt.src_id = my_node_id;
    req_pkt.dest_id = 0;
    req_pkt.seq = my_seq++;
    req_pkt.session_id = my_session_id;
    req_pkt.payload_len = 0;
    send_mesh_packet(&req_pkt);

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
    if (ble_conn_handle != BLE_HS_CONN_HANDLE_NONE) {
      ble_gatts_chr_updated(status_val_handle);
    }
  }
  return 0;
}

// ─── GATT SERVICE DEFINITION ─────────────────────────────────────────────

static const ble_uuid128_t mesh_svc_uuid = {
    .u = {.type = BLE_UUID_TYPE_128},
    .value = {0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0b, 0xb0, 0xee, 0x4b, 0xfe,
              0xca, 0xad, 0xfb, 0xca, 0xde}};
static const ble_uuid128_t mesh_chr_status_uuid = {
    .u = {.type = BLE_UUID_TYPE_128},
    .value = {0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0b, 0xb0, 0xee, 0x4b, 0xfe,
              0xca, 0xad, 0xfb, 0xca, 0xde}};
static const ble_uuid128_t mesh_chr_peers_uuid = {
    .u = {.type = BLE_UUID_TYPE_128},
    .value = {0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0b, 0xb0, 0xee, 0x4b, 0xfe,
              0xca, 0xad, 0xfb, 0xca, 0xde}};
static const ble_uuid128_t mesh_chr_chat_uuid = {
    .u = {.type = BLE_UUID_TYPE_128},
    .value = {0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0b, 0xb0, 0xee, 0x4b, 0xfe,
              0xca, 0xad, 0xfb, 0xca, 0xde}};
static const ble_uuid128_t mesh_chr_cmd_uuid = {
    .u = {.type = BLE_UUID_TYPE_128},
    .value = {0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0b, 0xb0, 0xee, 0x4b, 0xfe,
              0xca, 0xad, 0xfb, 0xca, 0xde}};
static const ble_uuid128_t mesh_chr_ecdh_uuid = {
    .u = {.type = BLE_UUID_TYPE_128},
    .value = {0x05, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0b, 0xb0, 0xee, 0x4b, 0xfe,
              0xca, 0xad, 0xfb, 0xca, 0xde}};

static const struct ble_gatt_svc_def ble_svc_defs[] = {
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
                {0},
            },
    },
    {0},
};

// ─── GAP / ADVERTISING ───────────────────────────────────────────────────

static int ble_gap_event(struct ble_gap_event *event, void *arg);

static void ble_advertise(void) {
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
  params.itvl_min = 160; // 100 ms (160 * 0.625ms)
  params.itvl_max = 320; // 200 ms (320 * 0.625ms)
  ble_gap_adv_start(ble_own_addr_type, NULL, BLE_HS_FOREVER, &params,
                    ble_gap_event, NULL);
}

static int ble_gap_event(struct ble_gap_event *event, void *arg) {
  struct ble_gap_conn_desc desc;
  switch (event->type) {
  case BLE_GAP_EVENT_CONNECT:
    ESP_LOGI(TAG, "BLE connected");
    ble_conn_handle = event->connect.conn_handle;
    
    // Request connection parameters update for better coexistence with Wi-Fi/ESP-NOW
    struct ble_gap_upd_params conn_params = {
        .itvl_min = 24,             // 30 ms (24 * 1.25ms)
        .itvl_max = 40,             // 50 ms (40 * 1.25ms)
        .latency = 0,
        .supervision_timeout = 400, // 4 seconds (400 * 10ms)
        .min_ce_len = 0,
        .max_ce_len = 0,
    };
    ble_gap_update_params(ble_conn_handle, &conn_params);
    break;

  case BLE_GAP_EVENT_DISCONNECT:
    ESP_LOGI(TAG, "BLE disconnected (reason %d)", event->disconnect.reason);
    ble_conn_handle = BLE_HS_CONN_HANDLE_NONE;
    ble_session_established = false; // Reset session key on disconnect
    ble_advertise();
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

static void gatt_svr_register_cb(struct ble_gatt_register_ctxt *ctxt,
                                 void *arg) {
  if (ctxt->op != BLE_GATT_REGISTER_OP_CHR)
    return;

  static const ble_uuid128_t s_uuid = {
      .u = {.type = BLE_UUID_TYPE_128},
      .value = {0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0b, 0xb0, 0xee, 0x4b,
                0xfe, 0xca, 0xad, 0xfb, 0xca, 0xde}};
  static const ble_uuid128_t p_uuid = {
      .u = {.type = BLE_UUID_TYPE_128},
      .value = {0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0b, 0xb0, 0xee, 0x4b,
                0xfe, 0xca, 0xad, 0xfb, 0xca, 0xde}};
  static const ble_uuid128_t c_uuid = {
      .u = {.type = BLE_UUID_TYPE_128},
      .value = {0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0b, 0xb0, 0xee, 0x4b,
                0xfe, 0xca, 0xad, 0xfb, 0xca, 0xde}};
  static const ble_uuid128_t k_uuid = {
      .u = {.type = BLE_UUID_TYPE_128},
      .value = {0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0b, 0xb0, 0xee, 0x4b,
                0xfe, 0xca, 0xad, 0xfb, 0xca, 0xde}};
  static const ble_uuid128_t e_uuid = {
      .u = {.type = BLE_UUID_TYPE_128},
      .value = {0x05, 0x00, 0x00, 0x00, 0x00, 0x00, 0x0b, 0xb0, 0xee, 0x4b,
                0xfe, 0xca, 0xad, 0xfb, 0xca, 0xde}};

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
}

static void ble_host_task(void *param) {
  nimble_port_run();
  nimble_port_freertos_deinit();
}

static void ble_on_sync(void) {
  ble_hs_id_infer_auto(0, &ble_own_addr_type);
  ble_att_set_preferred_mtu(512);
  ble_advertise();
}

// ─── PERIODIC HEARTBEAT TASK ─────────────────────────────────────────────

static void mesh_heartbeat_task(void *pvParameters) {
  while (1) {
    vTaskDelay(pdMS_TO_TICKS(5000));

    // Dynamic AP SSID hiding once mesh is formed
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
        ESP_LOGI(TAG, "Peer offline: %u", peer_db[i].id);
      }
    }
    // Compact DB immediately on offline peer event to maintain array density
    if (changed) {
      compact_peer_db();
    }
    xSemaphoreGive(peer_mutex);

    if (changed && ble_conn_handle != BLE_HS_CONN_HANDLE_NONE) {
      ble_gatts_chr_updated(peers_val_handle);
      ble_gatts_chr_updated(status_val_handle);
    }

    MeshPacket pkt = {};
    pkt.magic = PACKET_MAGIC;
    pkt.type = PKT_HEARTBEAT;
    pkt.seq = my_seq++;
    pkt.session_id = my_session_id;
    pkt.epoch = group_key_epoch;
    pkt.src_id = my_node_id;
    pkt.dest_id = 0;

    strncpy((char *)pkt.payload, my_nickname, 20);
    pkt.payload[20] = '\0';

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
    }
  }
}

// ─── MAIN ────────────────────────────────────────────────────────────────

void app_main(void) {
  esp_err_t ret = nvs_flash_init();
  if (ret == ESP_ERR_NVS_NO_FREE_PAGES ||
      ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
    ESP_ERROR_CHECK(nvs_flash_erase());
    ret = nvs_flash_init();
  }
  ESP_ERROR_CHECK(ret);

  chat_mutex = xSemaphoreCreateMutex();
  peer_mutex = xSemaphoreCreateMutex();
  hash_mutex = xSemaphoreCreateMutex();
  peers_buf_mutex = xSemaphoreCreateMutex();
  configASSERT(chat_mutex && peer_mutex && hash_mutex && peers_buf_mutex);

  uint8_t mac[6];
  esp_read_mac(mac, ESP_MAC_WIFI_STA);
  my_node_id = ((uint32_t)mac[2] << 24) | ((uint32_t)mac[3] << 16) |
               ((uint32_t)mac[4] << 8) | (uint32_t)mac[5];
  load_nick_nvs(my_node_id, my_nickname, sizeof(my_nickname));
  my_session_id = (uint16_t)(esp_random() & 0xFFFF);
  ESP_LOGI(TAG, "Node ID: %08X  Nick: %s  Session: %04X", (unsigned)my_node_id, my_nickname, my_session_id);

  ESP_ERROR_CHECK(esp_netif_init());
  ESP_ERROR_CHECK(esp_event_loop_create_default());
  wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
  ESP_ERROR_CHECK(esp_wifi_init(&cfg));
  ESP_ERROR_CHECK(esp_wifi_set_storage(WIFI_STORAGE_RAM));
  ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_AP));

  wifi_config_t wifi_cfg = {};
  snprintf((char *)wifi_cfg.ap.ssid, sizeof(wifi_cfg.ap.ssid), "MeshOS_%08X",
           (unsigned)my_node_id);
  strncpy((char *)wifi_cfg.ap.password, "MeshOSPassword",
          sizeof(wifi_cfg.ap.password));
  wifi_cfg.ap.channel = 1;
  wifi_cfg.ap.max_connection = 4;
  wifi_cfg.ap.authmode = WIFI_AUTH_WPA2_PSK;
  wifi_cfg.ap.ssid_hidden = 0;
  ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_AP, &wifi_cfg));
  ESP_ERROR_CHECK(esp_wifi_start());
  ESP_LOGI(TAG, "Wi-Fi AP started");

  ESP_ERROR_CHECK(esp_now_init());
  ESP_ERROR_CHECK(esp_now_register_recv_cb(esp_now_recv_cb));

  esp_now_peer_info_t peer_info = {};
  memset(&peer_info, 0, sizeof(peer_info));
  memset(peer_info.peer_addr, 0xFF, ESP_NOW_ETH_ALEN);
  peer_info.channel = 1;
  peer_info.ifidx = WIFI_IF_AP;
  peer_info.encrypt = false;
  ESP_ERROR_CHECK(esp_now_add_peer(&peer_info));
  ESP_LOGI(TAG, "ESP-NOW mesh ready");

  nimble_port_init();
  ble_hs_cfg.sync_cb = ble_on_sync;
  ble_hs_cfg.gatts_register_cb = gatt_svr_register_cb;
  ble_hs_cfg.store_status_cb = ble_store_util_status_rr;
  ble_hs_cfg.sm_io_cap = BLE_HS_IO_NO_INPUT_OUTPUT;
  ble_hs_cfg.sm_oob_data_flag = 0;
  ble_hs_cfg.sm_bonding = 0;
  ble_hs_cfg.sm_mitm = 0;
  ble_hs_cfg.sm_sc = 1;
  ble_hs_cfg.sm_our_key_dist =
      BLE_SM_PAIR_KEY_DIST_ENC | BLE_SM_PAIR_KEY_DIST_ID;
  ble_hs_cfg.sm_their_key_dist =
      BLE_SM_PAIR_KEY_DIST_ENC | BLE_SM_PAIR_KEY_DIST_ID;

  ESP_ERROR_CHECK(ble_gatts_count_cfg(ble_svc_defs));
  ESP_ERROR_CHECK(ble_gatts_add_svcs(ble_svc_defs));
  ble_store_config_init();
  nimble_port_freertos_init(ble_host_task);
  ESP_LOGI(TAG, "BLE GATT server ready");

  xTaskCreate(mesh_heartbeat_task, "mesh_hb", 4096, NULL, 5, NULL);
}
