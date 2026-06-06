#pragma once

#include <stdio.h>
#include <string.h>

// FreeRTOS
#include "freertos/FreeRTOS.h"
#include "freertos/semphr.h"
#include "freertos/task.h"

// ESP
#include "esp_log.h"
#include "esp_err.h"
#include "esp_ota_ops.h"

// Caching and limits
#define MAX_PEERS 32
#define MAX_NEIGHBORS 16
#define MAX_TEXT_LEN 171
#define MESH_PAYLOAD_MAX 200
#define CHAT_HISTORY_MAX 30
#define PACKET_MAGIC 0xC0DE

#define AES_GCM_NONCE_LEN 12
#define AES_GCM_TAG_LEN 16
#define AES_GCM_OVERHEAD (AES_GCM_NONCE_LEN + AES_GCM_TAG_LEN) // 28 bytes
#define CHAT_HDR_LEN 18

#ifndef MIN
#define MIN(a, b) ((a) < (b) ? (a) : (b))
#endif

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
  bool has_client;
};
typedef struct PeerEntry PeerEntry;

enum PacketType { 
  PKT_HEARTBEAT = 0, 
  PKT_CHAT = 2, 
  PKT_NICK_SYNC = 3, 
  PKT_HISTORY_REQ = 4 
};

struct MeshPacket {
  uint16_t magic;
  uint8_t type;
  uint8_t epoch;
  uint32_t seq;
  uint16_t session_id;
  uint32_t src_id;
  uint32_t dest_id;
  uint16_t payload_len;
  uint8_t payload[MESH_PAYLOAD_MAX];
} __attribute__((packed));
typedef struct MeshPacket MeshPacket;

// ─── SHARED GLOBALS (DECLARED) ───────────────────────────────────────────

extern const char *TAG;
extern const uint8_t AES_KEY[16];

extern uint32_t my_node_id;
extern char my_nickname[21];
extern uint16_t my_session_id;
extern uint32_t my_seq;
extern uint32_t mesh_time_offset_s;

// Mutexes
extern SemaphoreHandle_t chat_mutex;
extern SemaphoreHandle_t peer_mutex;
extern SemaphoreHandle_t hash_mutex;
extern SemaphoreHandle_t peers_buf_mutex;
extern SemaphoreHandle_t notify_mutex;

// Peer Database
extern PeerEntry peer_db[MAX_PEERS];
extern int peer_db_count;

// Chat History Ring Buffer
extern ChatMessage chat_history[CHAT_HISTORY_MAX];
extern int chat_tail;
extern int chat_count;

// History Sync State
extern bool history_sync_active;
extern int history_sync_index;
extern int history_sync_count;
extern ChatMessage history_sync_buffer[CHAT_HISTORY_MAX];

// BLE Handles and Connection State
extern uint16_t status_val_handle;
extern uint16_t peers_val_handle;
extern uint16_t chat_val_handle;
extern uint16_t cmd_val_handle;
extern uint16_t ecdh_val_handle;
extern uint16_t ota_val_handle;

extern uint16_t ble_conn_handle;
extern uint8_t ble_own_addr_type;

// OTA State
extern esp_ota_handle_t ota_update_handle;
extern const esp_partition_t *ota_update_partition;
extern uint32_t ota_image_size;
extern uint32_t ota_bytes_written;
extern bool ota_in_progress;
extern uint32_t ota_last_notified_bytes;

// Serialisation Buffers
extern uint8_t s_notify_buf[CHAT_HDR_LEN + AES_GCM_OVERHEAD + MAX_TEXT_LEN + 1];

// ─── HELPER DECLARATIONS ─────────────────────────────────────────────────
void rotate_session_if_needed(void);
