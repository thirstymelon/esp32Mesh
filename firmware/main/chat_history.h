#pragma once

#include "common.h"

void add_to_history(uint32_t sender, uint32_t dest, uint8_t flags,
                   const char *plaintext, uint32_t ts, uint16_t session_id, uint16_t seq, uint8_t channel_id);
bool is_duplicate(uint32_t sender_id, uint16_t session_id, uint32_t seq);
uint32_t djb2(const uint8_t *data, size_t len);
