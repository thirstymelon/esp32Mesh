#include "chat_history.h"
#include "host/ble_hs.h"

// Define chat history variables
ChatMessage chat_history[CHAT_HISTORY_MAX] = {{0}};
int chat_tail = 0;
int chat_count = 0;

// Define history sync variables
bool history_sync_active = false;
int history_sync_index = 0;
int history_sync_count = 0;
ChatMessage history_sync_buffer[CHAT_HISTORY_MAX] = {{0}};

// Define duplicate detection variables
static uint32_t dup_hashes[48] = {0};
static int dup_head = 0;

uint32_t djb2(const uint8_t *data, size_t len) {
  uint32_t h = 5381;
  for (size_t i = 0; i < len; i++)
    h = ((h << 5) + h) ^ data[i];
  return h ? h : 1;
}

bool is_duplicate(uint32_t sender_id, uint16_t session_id, uint32_t seq) {
  uint8_t buf[10];
  memcpy(buf, &sender_id, 4);
  memcpy(buf + 4, &session_id, 2);
  memcpy(buf + 6, &seq, 4);
  uint32_t h = djb2(buf, 10);

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

void add_to_history(uint32_t sender, uint32_t dest, uint8_t flags,
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
