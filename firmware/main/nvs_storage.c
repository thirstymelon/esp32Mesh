#include "nvs_storage.h"
#include "nvs.h"

// ─── AUTO-NICKNAME WORDS ─────────────────────────────────────────────────

static const char *ADJS[] = {"Swift", "Bold",  "Bright", "Dark", "Fast",
                             "Cool",  "Sharp", "Wild",   "Keen", "Calm"};
static const char *NOUNS[] = {"Fox",  "Hawk", "Wolf", "Bear", "Lynx",
                               "Kite", "Wren", "Crab", "Moth", "Ibis"};

static void get_auto_nick(uint32_t id, char *buf, size_t max_len) {
  snprintf(buf, max_len, "%s%s", ADJS[id % 10], NOUNS[(id >> 4) % 10]);
}

void save_nick_nvs(uint32_t id, const char *nick) {
  nvs_handle_t h;
  if (nvs_open("mesh_nvs", NVS_READWRITE, &h) != ESP_OK)
    return;

  char existing[21] = {0};
  size_t sz = sizeof(existing);
  bool changed = true;

  if (id == my_node_id) {
    if (nvs_get_str(h, "my_nick", existing, &sz) == ESP_OK && strcmp(existing, nick) == 0) {
      changed = false;
    }
  } else {
    char key[16];
    snprintf(key, sizeof(key), "n_%x", (unsigned)id);
    if (nvs_get_str(h, key, existing, &sz) == ESP_OK && strcmp(existing, nick) == 0) {
      changed = false;
    }
  }

  if (changed) {
    if (id == my_node_id) {
      nvs_set_str(h, "my_nick", nick);
    } else {
      char key[16];
      snprintf(key, sizeof(key), "n_%x", (unsigned)id);
      nvs_set_str(h, key, nick);
    }
    nvs_commit(h);
    ESP_LOGI(TAG, "NVS nickname updated for %08X: %s", (unsigned)id, nick);
  }
  nvs_close(h);
}

void load_nick_nvs(uint32_t id, char *out, size_t max_len) {
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
