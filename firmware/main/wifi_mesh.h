#pragma once

#include "common.h"
#include "esp_now.h"

void send_mesh_packet(MeshPacket *pkt);
void esp_now_recv_cb(const esp_now_recv_info_t *recv_info, const uint8_t *data, int len);
void mesh_heartbeat_task(void *pvParameters);
