#pragma once
#include <Arduino.h>
#include <ESPAsyncWebServer.h>
#include <painlessMesh.h>

// ── Mesh OTA packet prefix ────────────────────────────────────────────────
#define OTA_PREFIX  "__OTA__|"

// ── OTA state exposed for status polling ─────────────────────────────────
enum OTAState : uint8_t {
    OTA_IDLE = 0,
    OTA_UPLOADING,        // receiving firmware bytes from browser
    OTA_DISTRIBUTING,     // broadcasting chunks to mesh peers
    OTA_FLASHING_SELF,    // writing LittleFS binary to OTA partition
    OTA_DONE,
    OTA_ERROR
};

struct OTAStatus {
    OTAState state       = OTA_IDLE;
    uint8_t  uploadPct   = 0;    // 0-100 % of browser upload received
    int      sentChunks  = 0;    // chunks broadcast so far
    int      totalChunks = 0;    // total chunks for this firmware
    int      ackedNodes  = 0;    // mesh peers that ACK'd receipt
    int      peerCount   = 0;    // mesh peer count at time of start
    char     errMsg[64]  = {};
};

// Shared status — read by /ota/status handler in main.cpp
extern OTAStatus g_otaStatus;

// ── API ───────────────────────────────────────────────────────────────────

// Call from setup() — registers /update GET+POST + /ota/status routes
void setupOTA(AsyncWebServer& server, painlessMesh& mesh);

// Call from loop() — drives chunk-broadcast state machine (non-blocking)
void loopOTA();

// Call from receivedCallback() in main.cpp for every incoming mesh message.
// Returns true if the message was an OTA control packet and was consumed.
bool handleOTAMessage(const String& msg, uint32_t fromId);
