#include "ota.h"
#include <LittleFS.h>
#include <Update.h>
#include <MD5Builder.h>

// ── Pull credentials from secrets.h if present, else fall back ────────────
#if __has_include("secrets.h")
  #include "secrets.h"
#else
  #ifndef OTA_USER
    #define OTA_USER "admin"
  #endif
  #ifndef OTA_PASS
    #define OTA_PASS "changeme"
  #endif
#endif

// ── Constants ─────────────────────────────────────────────────────────────
#define OTA_BIN_PATH    "/ota.bin"
#define OTA_CHUNK_BYTES  512
#define OTA_CHUNK_MS      40    // ms between broadcast chunks
#define OTA_ANNOUNCE_MS 2500    // wait after announce before chunking
#define OTA_ACK_WAIT_MS 60000   // max ms to wait for all peer ACKs

// ── Shared status ─────────────────────────────────────────────────────────
OTAStatus g_otaStatus;

// ── Module-private state ──────────────────────────────────────────────────
static painlessMesh* s_mesh          = nullptr;
static bool          s_authOK        = false;
static bool          s_targetAll     = false;
static File          s_uploadFile;
static size_t        s_uploadExpected = 0;
static size_t        s_uploadReceived = 0;

// Chunk-broadcast state machine
static int      s_chunkSeq    = 0;    // next chunk index to send
static uint32_t s_chunkTimer  = 0;    // millis() of last chunk sent
static uint32_t s_announceAt  = 0;    // millis() when announce was sent
static char     s_md5[33]     = {};

// ── Helpers ───────────────────────────────────────────────────────────────
static String escErr(const char* s) {
    String j = "{\"error\":\""; j += s; j += "\"}";
    return j;
}

static bool checkAuth(AsyncWebServerRequest* r) {
    String pw = r->hasParam("pw", true) ? r->getParam("pw", true)->value()
              : r->hasParam("pw")       ? r->getParam("pw")->value()
              : "";
    return pw == String(OTA_PASS);
}

// Reboot helper via a one-shot FreeRTOS timer
static void rebootNow(TimerHandle_t) { ESP.restart(); }
static void scheduleReboot(uint32_t ms) {
    TimerHandle_t t = xTimerCreate("reboot", pdMS_TO_TICKS(ms), pdFALSE,
                                   nullptr, rebootNow);
    if (t) xTimerStart(t, 0);
}

// b64Enc duplicate (crypto.cpp may not be included in all builds)
static const char B64C[] =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

static String b64EncLocal(const uint8_t* d, size_t n) {
    String o; o.reserve(((n + 2) / 3) * 4);
    for (size_t i = 0; i < n; i += 3) {
        uint32_t v = ((uint32_t)d[i] << 16)
                   | (i+1 < n ? (uint32_t)d[i+1] << 8 : 0)
                   | (i+2 < n ? (uint32_t)d[i+2]      : 0);
        o += B64C[(v>>18)&63]; o += B64C[(v>>12)&63];
        o += (i+1 < n) ? B64C[(v>>6)&63] : '=';
        o += (i+2 < n) ? B64C[(v   )&63] : '=';
    }
    return o;
}

// ── setupOTA ──────────────────────────────────────────────────────────────
void setupOTA(AsyncWebServer& server, painlessMesh& mesh) {
    s_mesh = &mesh;

    // ── GET /update — serve the OTA page ────────────────────────────────
    server.on("/update", HTTP_GET, [](AsyncWebServerRequest* r) {
        // Check html_gz first, fall back to template/
        if (LittleFS.exists("/html_gz/update.html.gz")) {
            auto res = r->beginResponse(LittleFS,
                                        "/html_gz/update.html.gz", "text/html");
            res->addHeader("Content-Encoding", "gzip");
            res->addHeader("Cache-Control", "no-cache");
            r->send(res);
        } else if (LittleFS.exists("/template/update.html")) {
            auto res = r->beginResponse(LittleFS,
                                        "/template/update.html", "text/html");
            res->addHeader("Cache-Control", "no-cache");
            r->send(res);
        } else {
            r->send(404, "text/plain", "update.html not found — run build.sh then pio run -t uploadfs");
        }
    });

    // ── GET /ota/status — JSON progress for browser polling ─────────────
    server.on("/ota/status", HTTP_GET, [](AsyncWebServerRequest* r) {
        static const char* NAMES[] = {
            "idle","uploading","distributing","flashing","done","error" };
        OTAState st = g_otaStatus.state;
        String j = "{";
        j += "\"state\":\"";      j += NAMES[(int)st]; j += "\",";
        j += "\"uploadPct\":";    j += g_otaStatus.uploadPct;   j += ",";
        j += "\"sentChunks\":";   j += g_otaStatus.sentChunks;  j += ",";
        j += "\"totalChunks\":";  j += g_otaStatus.totalChunks; j += ",";
        j += "\"ackedNodes\":";   j += g_otaStatus.ackedNodes;  j += ",";
        j += "\"peerCount\":";    j += g_otaStatus.peerCount;   j += ",";
        j += "\"errMsg\":\"";     j += g_otaStatus.errMsg;       j += "\"}";
        r->send(200, "application/json", j);
    });

    // ── GET /ota/setpw?old=X&new=Y — change OTA password ───────────────
    server.on("/ota/setpw", HTTP_GET, [](AsyncWebServerRequest* r) {
        if (!r->hasParam("old") || !r->hasParam("new")) {
            r->send(400, "application/json", escErr("missing params"));
            return;
        }
        if (r->getParam("old")->value() != String(OTA_PASS)) {
            r->send(403, "application/json", escErr("wrong password"));
            return;
        }
        // Password changes require firmware recompile in this build —
        // for NVS-based persistence integrate with storage.h
        r->send(200, "application/json",
                "{\"ok\":true,\"note\":\"recompile with new OTA_PASS or use NVS\"}");
    });

    // ── POST /update — firmware upload ──────────────────────────────────
    //
    //  URL params:  ?pw=<password>&target=<this|all>
    //  Body:        multipart/form-data with field 'firmware' (.bin file)
    //
    server.on("/update", HTTP_POST,

        // ── Response handler (called after full upload completes) ────────
        [](AsyncWebServerRequest* r) {
            if (!s_authOK) {
                r->send(401, "application/json", escErr("wrong password"));
                g_otaStatus = {};
                return;
            }

            if (s_targetAll) {
                // Firmware saved to LittleFS; loopOTA() will distribute.
                // Close the upload file if still open.
                if (s_uploadFile) s_uploadFile.close();

                // Compute MD5 of stored binary
                MD5Builder md5b; md5b.begin();
                {
                    File f = LittleFS.open(OTA_BIN_PATH, "r");
                    if (!f) {
                        r->send(500, "application/json",
                                escErr("failed to open ota.bin"));
                        g_otaStatus.state = OTA_ERROR;
                        return;
                    }
                    uint8_t tmp[256];
                    while (f.available()) { size_t n = f.read(tmp, sizeof(tmp)); md5b.add(tmp, n); }
                    f.close();
                }
                md5b.calculate();
                md5b.toString().toCharArray(s_md5, sizeof(s_md5));

                // Prepare distribution
                int totalChunks =
                    ((int)LittleFS.open(OTA_BIN_PATH,"r").size()
                     + OTA_CHUNK_BYTES - 1) / OTA_CHUNK_BYTES;

                g_otaStatus.state       = OTA_DISTRIBUTING;
                g_otaStatus.totalChunks = totalChunks;
                g_otaStatus.sentChunks  = 0;
                g_otaStatus.ackedNodes  = 0;
                g_otaStatus.peerCount   = (int)s_mesh->getNodeList().size();

                // Send ANNOUNCE
                String ann = String(OTA_PREFIX) + "ANNOUNCE|"
                           + LittleFS.open(OTA_BIN_PATH,"r").size()
                           + "|" + s_md5
                           + "|" + totalChunks;
                s_mesh->sendBroadcast(ann);
                s_announceAt  = millis();
                s_chunkSeq    = 0;
                s_chunkTimer  = millis();

                Serial.printf("[OTA] Announce sent: %d chunks, md5=%s\n",
                              totalChunks, s_md5);

                r->send(200, "application/json",
                        "{\"status\":\"distributing\"}");
            } else {
                // Single-node: Update library already streamed; just end it.
                if (Update.hasError()) {
                    r->send(500, "application/json",
                            escErr(Update.errorString()));
                    g_otaStatus.state = OTA_ERROR;
                    snprintf(g_otaStatus.errMsg, sizeof(g_otaStatus.errMsg),
                             "%s", Update.errorString());
                } else {
                    g_otaStatus.state    = OTA_DONE;
                    g_otaStatus.uploadPct = 100;
                    r->send(200, "application/json",
                            "{\"status\":\"ok_restart\"}");
                    scheduleReboot(600);
                }
            }
        },

        // ── Upload handler (called for each chunk of the multipart body) ─
        [](AsyncWebServerRequest* r, String /*fn*/,
           size_t index, uint8_t* data, size_t len, bool final) {

            if (index == 0) {
                // First chunk — authenticate and initialise
                s_authOK    = checkAuth(r);
                s_targetAll = r->hasParam("target") &&
                              r->getParam("target")->value() == "all";

                if (!s_authOK) return;

                g_otaStatus      = {};   // reset
                g_otaStatus.state = OTA_UPLOADING;

                // Determine Content-Length if available
                s_uploadExpected = r->contentLength();
                s_uploadReceived = 0;

                if (s_targetAll) {
                    // Save to LittleFS for later distribution
                    LittleFS.remove(OTA_BIN_PATH);
                    s_uploadFile = LittleFS.open(OTA_BIN_PATH, "w");
                    if (!s_uploadFile) {
                        Serial.println("[OTA] Failed to open ota.bin for writing");
                        s_authOK = false;
                        return;
                    }
                    Serial.println("[OTA] Saving firmware to LittleFS...");
                } else {
                    // Stream directly to Update library
                    if (!Update.begin(UPDATE_SIZE_UNKNOWN, U_FLASH)) {
                        Serial.printf("[OTA] Update.begin failed: %s\n",
                                      Update.errorString());
                        s_authOK = false;
                        return;
                    }
                    Serial.println("[OTA] Streaming to Update...");
                }
            }

            if (!s_authOK) return;

            if (s_targetAll) {
                if (s_uploadFile && len > 0) {
                    s_uploadFile.write(data, len);
                }
            } else {
                if (len > 0 && Update.write(data, len) != len) {
                    Serial.printf("[OTA] Write error: %s\n", Update.errorString());
                }
            }

            s_uploadReceived += len;
            if (s_uploadExpected > 0)
                g_otaStatus.uploadPct =
                    (uint8_t)((s_uploadReceived * 100) / s_uploadExpected);

            if (final) {
                if (s_targetAll) {
                    if (s_uploadFile) { s_uploadFile.close(); }
                    Serial.printf("[OTA] LittleFS save complete: %u bytes\n",
                                  (unsigned)s_uploadReceived);
                } else {
                    if (!Update.end(true)) {
                        Serial.printf("[OTA] Update.end failed: %s\n",
                                      Update.errorString());
                    } else {
                        Serial.printf("[OTA] Flash OK: %u bytes\n",
                                      (unsigned)s_uploadReceived);
                    }
                }
            }
        }
    ); // server.on /update POST
}

// ── loopOTA — non-blocking chunk-broadcast state machine ─────────────────
//  Call from loop().
void loopOTA() {
    if (!s_mesh) return;
    if (g_otaStatus.state != OTA_DISTRIBUTING) return;

    uint32_t now = millis();

    // Wait for announce settle time before sending first chunk
    if (now - s_announceAt < OTA_ANNOUNCE_MS) return;

    if (s_chunkSeq >= g_otaStatus.totalChunks) {
        // All chunks sent — send END
        static bool endSent = false;
        if (!endSent) {
            String endPkt = String(OTA_PREFIX) + "END|" + s_md5;
            s_mesh->sendBroadcast(endPkt);
            endSent = true;
            Serial.printf("[OTA] END sent — waiting for ACKs (%d peers)\n",
                          g_otaStatus.peerCount);
        }

        // Wait for ACKs or timeout
        static uint32_t endAt = 0;
        if (endAt == 0) endAt = now;

        bool allAcked  = (g_otaStatus.ackedNodes >= g_otaStatus.peerCount
                          && g_otaStatus.peerCount > 0);
        bool timedOut  = (now - endAt > OTA_ACK_WAIT_MS);

        if (allAcked || timedOut) {
            if (timedOut && !allAcked)
                Serial.printf("[OTA] ACK timeout (%d/%d)\n",
                              g_otaStatus.ackedNodes, g_otaStatus.peerCount);

            endSent = false; endAt = 0;
            g_otaStatus.state = OTA_FLASHING_SELF;
            Serial.println("[OTA] Flashing self from LittleFS...");

            // Flash self
            File f = LittleFS.open(OTA_BIN_PATH, "r");
            if (!f) {
                snprintf(g_otaStatus.errMsg, sizeof(g_otaStatus.errMsg),
                         "open ota.bin failed");
                g_otaStatus.state = OTA_ERROR;
                return;
            }

            size_t fsz = f.size();
            if (!Update.begin(fsz, U_FLASH)) {
                f.close();
                snprintf(g_otaStatus.errMsg, sizeof(g_otaStatus.errMsg),
                         "%s", Update.errorString());
                g_otaStatus.state = OTA_ERROR;
                return;
            }
            Update.setMD5(s_md5);

            uint8_t buf[512];
            while (f.available()) {
                size_t n = f.read(buf, sizeof(buf));
                if (Update.write(buf, n) != n) {
                    f.close();
                    snprintf(g_otaStatus.errMsg, sizeof(g_otaStatus.errMsg),
                             "write: %s", Update.errorString());
                    g_otaStatus.state = OTA_ERROR;
                    return;
                }
            }
            f.close();

            if (!Update.end(true)) {
                snprintf(g_otaStatus.errMsg, sizeof(g_otaStatus.errMsg),
                         "end: %s", Update.errorString());
                g_otaStatus.state = OTA_ERROR;
                return;
            }

            LittleFS.remove(OTA_BIN_PATH);
            g_otaStatus.state = OTA_DONE;
            Serial.println("[OTA] Self-flash OK — rebooting...");
            scheduleReboot(500);
        }
        return;
    }

    // Throttle chunk sends
    if (now - s_chunkTimer < OTA_CHUNK_MS) return;
    s_chunkTimer = now;

    File f = LittleFS.open(OTA_BIN_PATH, "r");
    if (!f) {
        snprintf(g_otaStatus.errMsg, sizeof(g_otaStatus.errMsg),
                 "open failed mid-dist");
        g_otaStatus.state = OTA_ERROR;
        return;
    }

    // Seek to this chunk's offset and read
    f.seek((size_t)s_chunkSeq * OTA_CHUNK_BYTES);
    uint8_t buf[OTA_CHUNK_BYTES];
    size_t  n = f.read(buf, sizeof(buf));
    f.close();

    if (n > 0) {
        String pkt = String(OTA_PREFIX) + "CHUNK|"
                   + s_chunkSeq + "|"
                   + b64EncLocal(buf, n);
        s_mesh->sendBroadcast(pkt);
        g_otaStatus.sentChunks = ++s_chunkSeq;
    }
}

// ── handleOTAMessage — called from receivedCallback in main.cpp ───────────
bool handleOTAMessage(const String& msg, uint32_t fromId) {
    if (!msg.startsWith(OTA_PREFIX)) return false;

    String body = msg.substring(strlen(OTA_PREFIX));  // after "__OTA__|"

    // ── ANNOUNCE ─────────────────────────────────────────────────────────
    if (body.startsWith("ANNOUNCE|")) {
        if (g_otaStatus.state == OTA_DISTRIBUTING) return true; // we're sender

        // Parse: "size|md5|chunks"
        String rest = body.substring(9);
        int p1 = rest.indexOf('|'), p2 = rest.indexOf('|', p1+1),
            p3 = rest.indexOf('|', p2+1);
        if (p1 < 0 || p2 < 0 || p3 < 0) return true;

        size_t  fsz    = (size_t)rest.substring(0, p1).toInt();
        String  md5str = rest.substring(p1+1, p2);
        int     chunks = rest.substring(p3+1).toInt();

        md5str.toCharArray(s_md5, sizeof(s_md5));

        if (!Update.begin(fsz, U_FLASH)) {
            Serial.printf("[OTA-RX] begin failed: %s\n", Update.errorString());
            return true;
        }
        Update.setMD5(s_md5);

        g_otaStatus.state       = OTA_UPLOADING;  // reuse for rx progress
        g_otaStatus.totalChunks = chunks;
        g_otaStatus.sentChunks  = 0;

        Serial.printf("[OTA-RX] Announced: %u bytes, %d chunks, md5=%s\n",
                      fsz, chunks, s_md5);
        return true;
    }

    // ── CHUNK ────────────────────────────────────────────────────────────
    if (body.startsWith("CHUNK|")) {
        if (g_otaStatus.state == OTA_DISTRIBUTING) return true; // sender ignores own
        if (!Update.isRunning()) return true;

        String rest = body.substring(6);
        int    p1   = rest.indexOf('|');
        if (p1 < 0) return true;

        // int seq = rest.substring(0, p1).toInt();  // unused but available
        String b64 = rest.substring(p1 + 1);

        // Decode base64
        auto b64DecLocal = [](const String& in, uint8_t* out, size_t outLen) -> int {
            const char* LUT = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
            auto val = [LUT](char c) -> int {
                for (int i = 0; i < 64; i++) if (LUT[i]==c) return i;
                return -1;
            };
            size_t len = in.length();
            if (len%4) return -1;
            size_t outL = len/4*3;
            if (in[len-1]=='=') outL--;
            if (in[len-2]=='=') outL--;
            if (outL > outLen) return -1;
            size_t j=0;
            for (size_t i=0; i<len; i+=4) {
                int a=val(in[i]),b=val(in[i+1]),c=val(in[i+2]),d=val(in[i+3]);
                if (a<0||b<0) return -1;
                uint32_t v=((uint32_t)a<<18)|((uint32_t)b<<12)
                          |((uint32_t)(c<0?0:c)<<6)|((uint32_t)(d<0?0:d));
                if (j<outL) out[j++]=(v>>16)&0xFF;
                if (j<outL) out[j++]=(v>> 8)&0xFF;
                if (j<outL) out[j++]=(v    )&0xFF;
            }
            return (int)outL;
        };

        uint8_t buf[OTA_CHUNK_BYTES + 32];
        int     n = b64DecLocal(b64, buf, sizeof(buf));
        if (n > 0) {
            Update.write(buf, (size_t)n);
            g_otaStatus.sentChunks++;
        }
        return true;
    }

    // ── END ──────────────────────────────────────────────────────────────
    if (body.startsWith("END|")) {
        if (g_otaStatus.state == OTA_DISTRIBUTING) return true;
        if (!Update.isRunning()) return true;

        if (!Update.end(true)) {
            Serial.printf("[OTA-RX] end failed: %s\n", Update.errorString());
            g_otaStatus.state = OTA_ERROR;
            snprintf(g_otaStatus.errMsg, sizeof(g_otaStatus.errMsg),
                     "%s", Update.errorString());
        } else {
            Serial.println("[OTA-RX] Flash OK — sending ACK, rebooting...");
            // ACK the sender
            if (s_mesh) {
                String ack = String(OTA_PREFIX) + "ACK|" + String(s_mesh->getNodeId());
                s_mesh->sendBroadcast(ack);
            }
            g_otaStatus.state = OTA_DONE;
            scheduleReboot(800);
        }
        return true;
    }

    // ── ACK ──────────────────────────────────────────────────────────────
    if (body.startsWith("ACK|")) {
        if (g_otaStatus.state == OTA_DISTRIBUTING) {
            g_otaStatus.ackedNodes++;
            Serial.printf("[OTA] ACK from %u (%d/%d)\n",
                          fromId,
                          g_otaStatus.ackedNodes,
                          g_otaStatus.peerCount);
        }
        return true;
    }

    return false;  // unknown sub-type
}
