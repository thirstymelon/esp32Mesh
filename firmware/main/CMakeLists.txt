idf_component_register(SRCS "main.c" "crypto.c" "nvs_storage.c" "peer_db.c" "chat_history.c" "wifi_mesh.c" "ble_mesh.c"
                       INCLUDE_DIRS "."
                       PRIV_REQUIRES nvs_flash esp_wifi bt mbedtls)
