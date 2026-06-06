#pragma once

#include "common.h"
#include "host/ble_hs.h"

extern const struct ble_gatt_svc_def ble_svc_defs[];

void ble_advertise(void);
void ble_advertise_task(void *pvParameters);
void ble_host_task(void *param);
void ble_on_sync(void);
void ble_sync_trigger_task(void *pvParameters);
int ble_gap_event(struct ble_gap_event *event, void *arg);
void gatt_svr_register_cb(struct ble_gatt_register_ctxt *ctxt, void *arg);
void ble_store_config_init(void);
