#include "common.h"
#include "crypto.h"
#include "nvs_storage.h"
#include "peer_db.h"
#include "chat_history.h"
#include "wifi_mesh.h"
#include "ble_mesh.h"

// ESP Headers
#include "nvs_flash.h"
#include "esp_event.h"
#include "esp_netif.h"
#include "esp_wifi.h"
#include "esp_mac.h"
#include "esp_random.h"

// NimBLE Host
#include "host/ble_hs.h"
#include "nimble/nimble_port.h"
#include "nimble/nimble_port_freertos.h"
#include "services/gap/ble_svc_gap.h"
#include "services/gatt/ble_svc_gatt.h"

// Define log tag
const char *TAG = "MeshOS";

// Define global shared variables
uint32_t my_node_id = 0;
char my_nickname[21] = "Unknown";
uint16_t my_session_id = 0;
uint32_t my_seq = 0;
uint32_t mesh_time_offset_s = 0;

// Define Mutexes
SemaphoreHandle_t chat_mutex = NULL;
SemaphoreHandle_t peer_mutex = NULL;
SemaphoreHandle_t hash_mutex = NULL;
SemaphoreHandle_t peers_buf_mutex = NULL;
SemaphoreHandle_t notify_mutex = NULL;

void rotate_session_if_needed(void) {
  if (my_seq > 65000) {
    my_session_id = (uint16_t)(esp_random() & 0xFFFF);
    while (my_session_id == 0) {
      my_session_id = (uint16_t)(esp_random() & 0xFFFF);
    }
    my_seq = 0;
    ESP_LOGI(TAG, "Session ID rotated to %04X due to sequence wrap", my_session_id);
  }
}

// ─── MAIN ENTRY POINT ────────────────────────────────────────────────────

void app_main(void) {
  esp_err_t ret = nvs_flash_init();
  if (ret == ESP_ERR_NVS_NO_FREE_PAGES ||
      ret == ESP_ERR_NVS_NEW_VERSION_FOUND) {
    ESP_ERROR_CHECK(nvs_flash_erase());
    ret = nvs_flash_init();
  }
  ESP_ERROR_CHECK(ret);

  // Initialize Mutexes
  chat_mutex = xSemaphoreCreateMutex();
  peer_mutex = xSemaphoreCreateMutex();
  hash_mutex = xSemaphoreCreateMutex();
  peers_buf_mutex = xSemaphoreCreateMutex();
  notify_mutex = xSemaphoreCreateMutex();
  configASSERT(chat_mutex && peer_mutex && hash_mutex && peers_buf_mutex && notify_mutex);

  // Initialize Crypto (ECDH server key) - Do this early
  crypto_init();

  // Read STA MAC to build unique node ID
  uint8_t mac[6];
  esp_read_mac(mac, ESP_MAC_WIFI_STA);
  my_node_id = ((uint32_t)mac[2] << 24) | ((uint32_t)mac[3] << 16) |
               ((uint32_t)mac[4] << 8) | (uint32_t)mac[5];
  
  load_nick_nvs(my_node_id, my_nickname, sizeof(my_nickname));
  
  // Set up initial session ID
  my_session_id = (uint16_t)(esp_random() & 0xFFFF);
  while (my_session_id == 0) {
    my_session_id = (uint16_t)(esp_random() & 0xFFFF);
  }
  ESP_LOGI(TAG, "Node ID: %08X  Nick: %s  Session: %04X", (unsigned)my_node_id, my_nickname, my_session_id);

  // Wi-Fi AP Mode Initialization
  ESP_ERROR_CHECK(esp_netif_init());
  ESP_ERROR_CHECK(esp_event_loop_create_default());
  wifi_init_config_t cfg = WIFI_INIT_CONFIG_DEFAULT();
  ESP_ERROR_CHECK(esp_wifi_init(&cfg));
  ESP_ERROR_CHECK(esp_wifi_set_storage(WIFI_STORAGE_RAM));
  ESP_ERROR_CHECK(esp_wifi_set_mode(WIFI_MODE_AP));

  wifi_config_t wifi_cfg = {};
  snprintf((char *)wifi_cfg.ap.ssid, sizeof(wifi_cfg.ap.ssid), "MeshOS_%08X", (unsigned)my_node_id);
  strncpy((char *)wifi_cfg.ap.password, "MeshOSPassword", sizeof(wifi_cfg.ap.password));
  wifi_cfg.ap.channel = 1;
  wifi_cfg.ap.max_connection = 4;
  wifi_cfg.ap.authmode = WIFI_AUTH_WPA2_PSK;
  wifi_cfg.ap.ssid_hidden = 0;
  ESP_ERROR_CHECK(esp_wifi_set_config(WIFI_IF_AP, &wifi_cfg));
  ESP_ERROR_CHECK(esp_wifi_start());
  ESP_LOGI(TAG, "Wi-Fi AP started");

  // ESP-NOW Mesh Protocol Setup
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

  // NimBLE BLE Stack Initialization
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

  // Run Heartbeat Loop in background
  xTaskCreate(mesh_heartbeat_task, "mesh_hb", 4096, NULL, 5, NULL);
}
