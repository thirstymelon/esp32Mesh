#include <Arduino.h>
#include <painlessMesh.h>
#include <ESPAsyncWebServer.h>
#include <Wire.h>
#include <LittleFS.h>
#include <U8g2lib.h>

#include "ota.h"
#include "secrets.h"

// ─── TUNABLES ─────────────────────────────────────────────────────────────
#define MAX_MESSAGES   30
#define MSG_HASH_POOL  48
#define MAX_NODES      16
#define NICK_SYNC_PFX  "__NK__"

// ─── OLED ─────────────────────────────────────────────────────────────────
#define SCREEN_W   128
#define SCREEN_H    64
#define I2C_SDA     21
#define I2C_SCL     22

U8G2_SSD1306_128X64_NONAME_F_HW_I2C u8g2(U8G2_R0, U8X8_PIN_NONE);
bool oledOK = false;

// ─── OLED TIMINGS ─────────────────────────────────────────────────────────
#define O_FPS_MS       75
#define O_BLINK_MS    520
#define O_SCAN_MS     340
#define O_FLASH_MS   1800
#define O_MSG_TIMEOUT 10000

// ─── DATA STRUCTURES ──────────────────────────────────────────────────────
struct ChatMessage {
    String   sender;   // decimal uint32 string
    String   text;
    bool     isMe;
    bool     isDM;
    uint32_t ts;       // mesh µs / 1000
};

struct NodeEntry {
    uint32_t id;
    String   nick;
};

// ─── GLOBALS ──────────────────────────────────────────────────────────────
Scheduler      userScheduler;
painlessMesh   mesh;
AsyncWebServer server(80);

ChatMessage chat[MAX_MESSAGES];
int         chatCount = 0;

NodeEntry   nickDb[MAX_NODES];
int         nickCount = 0;

uint32_t    hashes[MSG_HASH_POOL] = {};
int         hashHead = 0;

// ─── OLED STATE ───────────────────────────────────────────────────────────
enum OledScreen { SCR_STATUS, SCR_MESSAGES };
OledScreen oScreen    = SCR_STATUS;
uint32_t   oMsgTimer  = 0;
uint32_t   oLastDraw  = 0;
bool       oBlink     = false;
uint32_t   oBlinkT    = 0;
uint8_t    oScanDot   = 0;
uint32_t   oScanT     = 0;
bool       oNewFlash  = false;
uint32_t   oNewFlashT = 0;

// ─── HELPERS ──────────────────────────────────────────────────────────────
static uint32_t djb2(const String& s) {
    uint32_t h = 5381;
    for (char c : s) h = ((h << 5) + h) ^ (uint8_t)c;
    return h ? h : 1;
}

static bool isDuplicate(const String& msg) {
    uint32_t h = djb2(msg);
    for (int i = 0; i < MSG_HASH_POOL; i++)
        if (hashes[i] == h) return true;
    hashes[hashHead] = h;
    hashHead = (hashHead + 1) % MSG_HASH_POOL;
    return false;
}

static void pushMessage(const String& sender,
                        const String& text,
                        bool isMe,
                        bool isDM = false) {

    if (chatCount < MAX_MESSAGES) {
        chat[chatCount++] = {
            sender,
            text,
            isMe,
            isDM,
            (uint32_t)(mesh.getNodeTime() / 1000ULL)
        };

    } else {
        for (int i = 1; i < MAX_MESSAGES; i++) { chat[i - 1] = chat[i]; }
        chat[MAX_MESSAGES - 1] = {
            sender,
            text,
            isMe,
            isDM,
            (uint32_t)(mesh.getNodeTime() / 1000ULL)
        };
    }
}

static String escapeJSON(const String& s) {
    String o; o.reserve(s.length() + 4);
    for (char c : s) {
        if      (c == '"')  o += "\\\"";
        else if (c == '\\') o += "\\\\";
        else if (c == '\n') o += "\\n";
        else if (c == '\r') ; // drop
        else                o += c;
    }
    return o;
}

// ── NickName helpers ──────────────────────────────────────────────────────────
static const char* ADJS[]  = {"Swift","Bold","Bright","Dark","Fast",
                               "Cool","Sharp","Wild","Keen","Calm"};
static const char* NOUNS[] = {"Fox","Hawk","Wolf","Bear","Lynx",
                               "Kite","Wren","Crab","Moth","Ibis"};

static String autoNick(uint32_t id) {
    return String(ADJS[id % 10]) + String(NOUNS[(id >> 4) % 10]);
}

static String getNick(uint32_t id) {
    for (int i = 0; i < nickCount; i++)
        if (nickDb[i].id == id) return nickDb[i].nick;
    return autoNick(id);
}

static void syncAllNicknames() {
    for (int i = 0; i < nickCount; i++) {
        String pkt =
            String(NICK_SYNC_PFX) +
            String(nickDb[i].id) +
            "|" +
            nickDb[i].nick;

        mesh.sendBroadcast(pkt);
        delay(10);
    }
}

static void storeNick(uint32_t id, const String& nick) {
    for (int i = 0; i < nickCount; i++) {
        if (nickDb[i].id == id) { nickDb[i].nick = nick; return; }
    }
    if (nickCount < MAX_NODES) nickDb[nickCount++] = { id, nick };
}

static void broadcastNick() {
    String pkt = String(NICK_SYNC_PFX) + String(mesh.getNodeId())
               + "|" + getNick(mesh.getNodeId());
    mesh.sendBroadcast(pkt);
}

// ── File serving helper — checks html_gz/*.gz first ──────────────────────
static void sendFile(AsyncWebServerRequest* r,
                     const char* htmlPath, const char* mime) {
    // Build gz candidate: "/index.html" → "/html_gz/index.html.gz"
    String fname = String(htmlPath).substring(1); // strip leading /
    String gz    = "/html_gz/" + fname + ".gz";

    if (LittleFS.exists(gz)) {
        auto res = r->beginResponse(LittleFS, gz, mime);
        res->addHeader("Content-Encoding", "gzip");
        res->addHeader("Cache-Control",    "no-cache");
        r->send(res);
        return;
    }
    // Fall back to template/ directory
    String tmpl = "/template/" + fname;
    if (LittleFS.exists(tmpl)) {
        auto res = r->beginResponse(LittleFS, tmpl, mime);
        res->addHeader("Cache-Control", "no-cache");
        r->send(res);
        return;
    }
    // Bare path
    if (LittleFS.exists(htmlPath)) {
        auto res = r->beginResponse(LittleFS, htmlPath, mime);
        res->addHeader("Cache-Control", "no-cache");
        r->send(res);
        return;
    }
    r->send(404, "text/plain",
            String(htmlPath) + " not found — run build.sh then pio run -t uploadfs");
}

// ─── OLED PRIMITIVES ──────────────────────────────────────────────────────
static void oledBars(int x, int y, int peers) {
    const uint8_t bh[3] = {3, 5, 7};
    int filled = min(peers, 3);
    for (int i = 0; i < 3; i++) {
        int bx = x + i * 3, by = y - bh[i] + 1;
        if (i < filled) u8g2.drawBox(bx, by, 2, bh[i]);
        else            u8g2.drawFrame(bx, by, 2, bh[i]);
    }
}

static void oledHeader(const char* label) {
    int peers = (int)mesh.getNodeList().size();
    u8g2.setFont(u8g2_font_5x7_tf);
    if (peers > 0 && oBlink) u8g2.drawDisc(3, 4, 2);
    else                      u8g2.drawCircle(3, 4, 2);
    u8g2.setCursor(8, 8);
    u8g2.print(label);
    oledBars(119, 9, peers);
    u8g2.drawLine(0, 11, SCREEN_W, 11);
}

// ─── SCREEN: STATUS ───────────────────────────────────────────────────────
static void oledDrawStatus() {
    u8g2.clearBuffer();
    oledHeader("MESH OS");

    int peers = (int)mesh.getNodeList().size();

    if (peers > 0) {
        u8g2.drawDisc(7, 22, 4);
        u8g2.setFont(u8g2_font_6x10_tf);
        u8g2.setCursor(16, 26); u8g2.print("ONLINE");
    } else {
        u8g2.drawCircle(7, 22, 4);
        u8g2.setFont(u8g2_font_6x10_tf);
        u8g2.setCursor(16, 26); u8g2.print("SCANNING");
        u8g2.setFont(u8g2_font_5x7_tf);
        for (int i = 0; i < (int)oScanDot; i++) u8g2.print('.');
    }

    // Own nickname centred large
    u8g2.setFont(u8g2_font_6x13B_tf);
    String nick = getNick(mesh.getNodeId());
    int tw = u8g2.getStrWidth(nick.c_str());
    u8g2.drawStr((SCREEN_W - tw) / 2, 43, nick.c_str());

    // Short node ID below nick
    u8g2.setFont(u8g2_font_4x6_tf);
    String nid = String(mesh.getNodeId()).substring(0, 8);
    tw = u8g2.getStrWidth(nid.c_str());
    u8g2.drawStr((SCREEN_W - tw) / 2, 51, nid.c_str());

    // Stats row
    u8g2.setFont(u8g2_font_5x7_tf);
    String pl = String(peers) + (peers == 1 ? " peer" : " peers");
    u8g2.setCursor(0, 54); u8g2.print(pl);
    if (chatCount > 0) {
        String ml = String(chatCount) + " msg";
        tw = u8g2.getStrWidth(ml.c_str());
        u8g2.setCursor(SCREEN_W - tw, 54); u8g2.print(ml);
    }

    // Mesh-synced uptime
    uint32_t s = (uint32_t)(mesh.getNodeTime() / 1000000ULL);
    uint32_t m = s / 60; s %= 60;
    uint32_t h = m / 60; m %= 60;
    char up[16];
    snprintf(up, sizeof(up), "up %02u:%02u:%02u", h, m, s);
    u8g2.setFont(u8g2_font_4x6_tf);
    tw = u8g2.getStrWidth(up);
    u8g2.drawStr((SCREEN_W - tw) / 2, 63, up);

    u8g2.sendBuffer();
}

// ─── SCREEN: MESSAGES ─────────────────────────────────────────────────────
static void oledDrawMessages() {
    u8g2.clearBuffer();
    char hdr[18];
    snprintf(hdr, sizeof(hdr), "MSGS [%d]", chatCount);
    oledHeader(hdr);

    u8g2.setFont(u8g2_font_5x8_tf);

    int show  = min(chatCount, 4);
    bool flit = oNewFlash && (((millis() - oNewFlashT) / 300) % 2 == 0);

    int y = 21;
    for (int i = show - 1; i >= 0; i--) {
        bool newest = (i == 0);
        if (newest && flit) {
            u8g2.setDrawColor(1); u8g2.drawBox(0, y - 8, SCREEN_W, 10);
            u8g2.setDrawColor(0);
        }

        String pfx;
        if (chat[i].isMe) {
            pfx = chat[i].isDM ? "DM>" : ">";
        } else {
            uint32_t sid = (uint32_t)strtoul(chat[i].sender.c_str(), nullptr, 10);
            pfx = getNick(sid).substring(0, 5) + (chat[i].isDM ? "!:" : ":");
        }

        String line = pfx + " " + chat[i].text;
        if ((int)line.length() > 25) line = line.substring(0, 24) + '~';

        u8g2.setCursor(0, y); u8g2.print(line);

        if (newest && flit) u8g2.setDrawColor(1);
        y += 11;
    }

    if (chatCount == 0) {
        u8g2.setFont(u8g2_font_5x7_tf);
        int tw = u8g2.getStrWidth("no messages yet");
        u8g2.drawStr((SCREEN_W - tw) / 2, 38, "no messages yet");
    }

    u8g2.drawLine(0, 56, SCREEN_W, 56);
    u8g2.setFont(u8g2_font_4x6_tf);
    if (oNewFlash) { u8g2.setCursor(0, 63); u8g2.print("NEW"); }

    uint32_t elapsed = millis() - oMsgTimer;
    if (elapsed < (uint32_t)O_MSG_TIMEOUT) {
        int bw = (int)((float)(O_MSG_TIMEOUT - elapsed) / O_MSG_TIMEOUT * 72);
        if (bw > 0) u8g2.drawBox(SCREEN_W - bw, 59, bw, 3);
    }

    u8g2.sendBuffer();
}

// ─── OLED API ─────────────────────────────────────────────────────────────
static void oledTriggerMessages() {
    if (!oledOK) return;
    oScreen    = SCR_MESSAGES;
    oMsgTimer  = millis();
    oNewFlash  = true;
    oNewFlashT = millis();
    oLastDraw  = 0;
}

static void updateOLED() {
    if (!oledOK) return;
    uint32_t now = millis();
    if (now - oLastDraw < O_FPS_MS) return;
    oLastDraw = now;

    if (now - oBlinkT >= O_BLINK_MS) { oBlink = !oBlink; oBlinkT = now; }
    if (now - oScanT  >= O_SCAN_MS)  { oScanDot = (oScanDot + 1) % 4; oScanT = now; }
    if (oNewFlash && now - oNewFlashT >= O_FLASH_MS) oNewFlash = false;
    if (oScreen == SCR_MESSAGES && now - oMsgTimer >= (uint32_t)O_MSG_TIMEOUT)
        oScreen = SCR_STATUS;

    switch (oScreen) {
        case SCR_STATUS:   oledDrawStatus();   break;
        case SCR_MESSAGES: oledDrawMessages(); break;
    }
}

// ─── MESH CALLBACKS ───────────────────────────────────────────────────────
void receivedCallback(uint32_t from, String& msg) {
    if (isDuplicate(msg)) return;

    // Hand off to OTA handler first
    if (handleOTAMessage(msg, from)) return;

    // Nick sync packet
    if (msg.startsWith(NICK_SYNC_PFX)) {
        String body = msg.substring(strlen(NICK_SYNC_PFX));
        int sep = body.indexOf('|');
        if (sep > 0) {
            uint32_t id   = (uint32_t)strtoul(body.substring(0, sep).c_str(), nullptr, 10);
            String   nick = body.substring(sep + 1);
            nick.trim();
            if (nick.length() > 0 && nick.length() <= 20) {
                storeNick(id, nick);
                mesh.sendBroadcast(msg);   // relay for multi-hop (dedup stops loops)
            }
        }
        return;
    }

    // Regular chat packet: "senderId|text"
    int sep = msg.indexOf('|');
    if (sep < 0) return;

    String sender = msg.substring(0, sep);
    String text   = msg.substring(sep + 1);

    if (sender == String(mesh.getNodeId())) return;   // drop self-echo

    pushMessage(sender, text, false);
    oledTriggerMessages();
}

void newConnectionCallback(uint32_t nodeId) {
    Serial.printf("[MESH] +Node %u  peers=%d\n",
                  nodeId, (int)mesh.getNodeList().size());
    syncAllNicknames();
    oLastDraw = 0;
}

void droppedConnectionCallback(uint32_t nodeId) {
    Serial.printf("[MESH] -Node %u  peers=%d\n",
                  nodeId, (int)mesh.getNodeList().size());
    oLastDraw = 0;
}

void changedConnectionsCallback() {
    Serial.printf("[MESH] Topology changed  peers=%d\n",
                  (int)mesh.getNodeList().size());
    oLastDraw = 0;
}

void nodeTimeAdjustedCallback(int32_t offset) {
    Serial.printf("[MESH] Time adj %d µs\n", offset);
}

// ─── BOOT SPLASH ──────────────────────────────────────────────────────────
static void bootSplash(const char* status, const char* detail = nullptr) {
    u8g2.clearBuffer();
    u8g2.setFont(u8g2_font_7x13B_tf);
    const char* title = "MESH  OS";
    int tw = u8g2.getStrWidth(title);
    u8g2.drawStr((SCREEN_W - tw) / 2, 22, title);
    u8g2.drawLine(14, 27, SCREEN_W - 14, 27);
    if (detail) {
        u8g2.setFont(u8g2_font_5x7_tf);
        tw = u8g2.getStrWidth(detail);
        u8g2.drawStr((SCREEN_W - tw) / 2, 41, detail);
    }
    u8g2.setFont(u8g2_font_4x6_tf);
    tw = u8g2.getStrWidth(status);
    u8g2.drawStr((SCREEN_W - tw) / 2, detail ? 56 : 48, status);
    u8g2.sendBuffer();
}

// ─── SETUP ────────────────────────────────────────────────────────────────
void setup() {
    Serial.begin(115200);

    // ── LittleFS ──────────────────────────────────────────────────────────
    if (!LittleFS.begin(true)) {
        Serial.println("[BOOT] LittleFS mount failed");
    } else {
        Serial.printf("[BOOT] LittleFS OK  used=%u  total=%u\n",
                      (unsigned)LittleFS.usedBytes(),
                      (unsigned)LittleFS.totalBytes());
    }

    // ── OLED ──────────────────────────────────────────────────────────────
    Wire.begin(I2C_SDA, I2C_SCL);
    delay(80);
    u8g2.begin();
    u8g2.setPowerSave(0);
    oledOK = true;
    bootSplash("initializing...");

    // ── Mesh ──────────────────────────────────────────────────────────────
    mesh.setDebugMsgTypes(ERROR | STARTUP);
    mesh.init(MESH_PREFIX, MESH_PASSWORD, &userScheduler,
              MESH_PORT, WIFI_AP_STA, MESH_CHANNEL);

    mesh.onReceive(&receivedCallback);
    mesh.onNewConnection(&newConnectionCallback);
    mesh.onDroppedConnection(&droppedConnectionCallback);
    mesh.onChangedConnections(&changedConnectionsCallback);
    mesh.onNodeTimeAdjusted(&nodeTimeAdjustedCallback);

    // Store own auto-nick
    uint32_t myId = mesh.getNodeId();
    storeNick(myId, autoNick(myId));

    // ── HTTP routes ────────────────────────────────────────────────────────

    server.on("/", HTTP_GET, [](AsyncWebServerRequest* r) {
        sendFile(r, "/index.html", "text/html");
    });
    server.on("/nodes", HTTP_GET, [](AsyncWebServerRequest* r) {
        sendFile(r, "/nodes.html", "text/html");
    });
    // /update GET+POST handled by setupOTA
    server.serveStatic("/style/", LittleFS, "/style/")
          .setCacheControl("max-age=86400");

    // ── Send message ──────────────────────────────────────────────────────
    server.on("/send", HTTP_GET, [](AsyncWebServerRequest* r) {
        if (r->hasParam("msg")) {
            String text = r->getParam("msg")->value();
            text.trim();
            if (!text.length()) { r->send(400, "text/plain", "empty"); return; }
            if (text.length() > 200) text = text.substring(0, 200);

            pushMessage(String(mesh.getNodeId()), text, true);
            oledTriggerMessages();

            String payload = String(mesh.getNodeId()) + "|" + text;
            mesh.sendBroadcast(payload);
        }
        r->send(200, "text/plain", "OK");
    });

    // ── Set nickname ──────────────────────────────────────────────────────
    server.on("/setnick", HTTP_GET, [](AsyncWebServerRequest* r) {
        if (!r->hasParam("id") || !r->hasParam("nick")) {
            r->send(400, "text/plain", "missing params"); return;
        }
        uint32_t id  = (uint32_t)strtoul(
            r->getParam("id")->value().c_str(), nullptr, 10);
        String nick = r->getParam("nick")->value();
        nick.trim();
        if (!nick.length() || nick.length() > 20) {
            r->send(400, "text/plain", "bad nick"); return;
        }
        storeNick(id, nick);
        // Broadcast to mesh
        String pkt = String(NICK_SYNC_PFX) + String(id) + "|" + nick;
        mesh.sendBroadcast(pkt);
        r->send(200, "text/plain", "OK");
    });

    // ── Data API ─────────────────────────────────────────────────────────
    server.on("/data", HTTP_GET, [](AsyncWebServerRequest* r) {
        uint32_t myId = mesh.getNodeId();
        auto     nl   = mesh.getNodeList();

        String j = "{";
        j += "\"nodeId\":\""   + String(myId)    + "\",";
        j += "\"nodeCount\":"  + String(nl.size()) + ",";
        j += "\"meshTime\":"   + String(mesh.getNodeTime()) + ",";
        j += "\"topology\":"   + mesh.subConnectionJson() + ",";

        // Peers array
        j += "\"peers\":[";
        bool fn = true;
        for (auto& id : nl) {
            if (!fn) j += ",";
            j += "\"" + String(id) + "\"";
            fn = false;
        }
        j += "],";

        // Nicknames
        j += "\"nicknames\":[";
        for (int i = 0; i < nickCount; i++) {
            if (i) j += ",";
            j += "{\"id\":\"" + String(nickDb[i].id)
               + "\",\"nick\":\"" + escapeJSON(nickDb[i].nick) + "\"}";
        }
        j += "],";

        // Messages (oldest → newest so browser can append)
        j += "\"messages\":[";
        bool fm = true;
        for (int i = 0; i < chatCount; i++) {
            if (!fm) j += ",";
            j += "{\"sender\":\"" + escapeJSON(chat[i].sender) + "\","
               + "\"text\":\""    + escapeJSON(chat[i].text)   + "\","
               + "\"ts\":"        + String(chat[i].ts)          + ","
               + "\"dm\":"        + (chat[i].isDM  ? "true" : "false") + ","
               + "\"me\":"        + (chat[i].isMe  ? "true" : "false") + "}";
            fm = false;
        }
        j += "]}";

        r->send(200, "application/json", j);
    });

    // ── OTA (GET /update served here too, POST handled in setupOTA) ───────
    setupOTA(server, mesh);

    server.begin();

    // Show own nick on splash
    String nick = getNick(myId);
    bootSplash(("hi, " + nick).c_str(),
               String(myId).substring(0, 8).c_str());
    delay(900);

    Serial.printf("[BOOT] Node %u  nick=%s  ready\n", myId, nick.c_str());
}

// ─── LOOP ─────────────────────────────────────────────────────────────────
void loop() {
    mesh.update();
    updateOLED();
    loopOTA();   // drives mesh OTA chunk distribution (no-op when idle)
}
