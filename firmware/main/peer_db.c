#include "peer_db.h"
#include "nvs_storage.h"
#include "host/ble_hs.h"

// Define peer database variables
PeerEntry peer_db[MAX_PEERS] = {{0}};
int peer_db_count = 0;

void sanitize_ascii(char *str, size_t max_len) {
  for (size_t i = 0; i < max_len && str[i] != '\0'; i++) {
    if ((uint8_t)str[i] < 0x20 || (uint8_t)str[i] > 0x7E) {
      str[i] = '_';
    }
  }
}

void compact_peer_db(void) {
  int write = 0;
  for (int read = 0; read < peer_db_count; read++) {
    if (peer_db[read].is_online) {
      if (write != read)
        peer_db[write] = peer_db[read];
      write++;
    }
  }
  int evicted = peer_db_count - write;
  peer_db_count = write;
  ESP_LOGI(TAG, "Peer DB compacted → %d active peers (evicted %d offline)", write, evicted);
}

PeerEntry *peer_find_or_insert(uint32_t id) {
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
    p->has_client = false;
    return p;
  }
  return NULL;
}

void update_peer_nick(uint32_t id, const char *nick) {
  if (id == my_node_id) return;
  bool is_new = false;

  xSemaphoreTake(peer_mutex, portMAX_DELAY);
  PeerEntry *p = peer_find_or_insert(id);
  if (p) {
    if (p->last_seen_ms == 0 || strcmp(p->nick, nick) != 0)
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

void update_peer_heartbeat(uint32_t id, const char *nick,
                          const uint32_t *neighbors,
                          uint8_t neighbor_count,
                          bool has_client) {
  if (id == my_node_id) return;
  bool is_new = false;

  xSemaphoreTake(peer_mutex, portMAX_DELAY);
  PeerEntry *p = peer_find_or_insert(id);
  if (p) {
    if (p->last_seen_ms == 0 || strcmp(p->nick, nick) != 0)
      is_new = true;
    strncpy(p->nick, nick, 20);
    p->nick[20] = '\0';
    sanitize_ascii(p->nick, 20);
    p->is_online = true;
    p->last_seen_ms = esp_log_timestamp();
    p->neighbor_count = MIN(neighbor_count, MAX_NEIGHBORS);
    memcpy(p->neighbors, neighbors, p->neighbor_count * 4);
    p->has_client = has_client;
  }
  xSemaphoreGive(peer_mutex);

  if (is_new)
    save_nick_nvs(id, nick);
  if (ble_conn_handle != BLE_HS_CONN_HANDLE_NONE) {
    ble_gatts_chr_updated(peers_val_handle);
  }
}
