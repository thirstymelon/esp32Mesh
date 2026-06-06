#pragma once

#include "common.h"

void save_nick_nvs(uint32_t id, const char *nick);
void load_nick_nvs(uint32_t id, char *out, size_t max_len);
