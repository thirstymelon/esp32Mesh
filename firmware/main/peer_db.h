#pragma once

#include "common.h"

void compact_peer_db(void);
PeerEntry *peer_find_or_insert(uint32_t id);
void update_peer_nick(uint32_t id, const char *nick);
void update_peer_heartbeat(uint32_t id, const char *nick,
                          const uint32_t *neighbors,
                          uint8_t neighbor_count,
                          bool has_client);
void sanitize_ascii(char *str, size_t max_len);
