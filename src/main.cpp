#include <Arduino.h>
#include <painlessMesh.h>
#include <ESPAsyncWebServer.h>
#include <Wire.h>
#include "web_page.h"
#include <U8g2lib.h>

// ─── CONFIG ────────────────────────────────────────────────────────────────
#define MESH_PREFIX    "ESP32Mesh"
#define MESH_PASSWORD  "meshpass123"
#define MESH_PORT      5555
#define MESH_CHANNEL   6
#define MAX_MESSAGES   30
#define MSG_HASH_POOL  48

// ─── OLED ──────────────────────────────────────────────────────────────────
#define SCREEN_W  128
#define SCREEN_H   64
#define I2C_SDA    21
#define I2C_SCL    22

U8G2_SSD1306_128X64_NONAME_F_HW_I2C u8g2(U8G2_R0, U8X8_PIN_NONE);
bool oledOK = false;

// ─── NICKNAME DB ───────────────────────────────────────────────────────────
#define MAX_NODES 16
// Prefix that distinguishes nickname-sync packets from chat packets
#define NICK_SYNC_PREFIX "__NK__"

struct NodeEntry {
    uint32_t id;
    String   nick;
};
NodeEntry nickDb[MAX_NODES];
int       nickDbCount = 0;

// Auto-generate a deterministic name from a node ID.
// 10 adjectives × 10 nouns = 100 unique combos — plenty for a small mesh.
String autoNick(uint32_t id) {
    static const char* ADJS[]  = {
        "Swift","Bold","Bright","Dark","Fast",
        "Cool","Sharp","Wild","Keen","Calm"
    };
    static const char* NOUNS[] = {
        "Fox","Hawk","Wolf","Bear","Lynx",
        "Kite","Wren","Crab","Moth","Ibis"
    };
    return String(ADJS[id % 10]) + String(NOUNS[(id >> 4) % 10]);
}

// Return stored nickname for a node, or auto-generated fallback.
String getNick(uint32_t id) {
    for (int i = 0; i < nickDbCount; i++)
        if (nickDb[i].id == id) return nickDb[i].nick;
    return autoNick(id);
}

// Upsert a nickname into the local DB.
void storeNick(uint32_t id, const String &nick) {
    for (int i = 0; i < nickDbCount; i++) {
        if (nickDb[i].id == id) { nickDb[i].nick = nick; return; }
    }
    if (nickDbCount < MAX_NODES)
        nickDb[nickDbCount++] = { id, nick };
}

// ─── OLED STATE MACHINE ────────────────────────────────────────────────────
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

#define O_FPS_MS      75
#define O_BLINK_MS    520
#define O_SCAN_MS     340
#define O_FLASH_MS    1800
#define O_MSG_TIMEOUT 10000

// ─── DATA ──────────────────────────────────────────────────────────────────
struct ChatMessage {
    String   sender;   // full uint32_t as decimal string
    String   text;
    bool     isMe;
    uint32_t ts;
};

// ─── GLOBALS ───────────────────────────────────────────────────────────────
Scheduler      userScheduler;
painlessMesh   mesh;
AsyncWebServer server(80);

ChatMessage chat[MAX_MESSAGES];
int         chatCount = 0;

uint32_t msgHashes[MSG_HASH_POOL] = {};
int      hashHead = 0;

// Broadcast this node's own nickname across the mesh.
// Defined here (after mesh global) so mesh is in scope.
void broadcastOwnNick() {
    String own = getNick(mesh.getNodeId());
    String pkt = String(NICK_SYNC_PREFIX)
               + String(mesh.getNodeId()) + "|" + own;
    mesh.sendBroadcast(pkt);
}

// ─── HELPERS ───────────────────────────────────────────────────────────────
uint32_t simpleHash(const String &s) {
    uint32_t h = 5381;
    for (char c : s) h = ((h << 5) + h) ^ (uint8_t)c;
    return h ? h : 1;
}

bool isDuplicate(const String &payload) {
    uint32_t h = simpleHash(payload);
    for (int i = 0; i < MSG_HASH_POOL; i++)
        if (msgHashes[i] == h) return true;
    msgHashes[hashHead] = h;
    hashHead = (hashHead + 1) % MSG_HASH_POOL;
    return false;
}

void pushMessage(const String &sender, const String &text, bool isMe) {
    if (chatCount < MAX_MESSAGES) chatCount++;
    for (int i = chatCount - 1; i > 0; i--)
        chat[i] = chat[i - 1];
    chat[0] = { sender, text, isMe, (uint32_t)mesh.getNodeTime() / 1000 };
}

String escapeJSON(const String &s) {
    String o;
    o.reserve(s.length() + 4);
    for (char c : s) {
        if      (c == '"')  o += "\\\"";
        else if (c == '\\') o += "\\\\";
        else if (c == '\n') o += "\\n";
        else if (c == '\r') o += "\\r";
        else                o += c;
    }
    return o;
}

// ─── OLED PRIMITIVES ───────────────────────────────────────────────────────
void oledBars(int x, int y, int peers) {
    const uint8_t bh[3] = { 3, 5, 7 };
    int filled = min(peers, 3);
    for (int i = 0; i < 3; i++) {
        int bx = x + i * 3;
        int by = y - bh[i] + 1;
        if (i < filled) u8g2.drawBox(bx, by, 2, bh[i]);
        else            u8g2.drawFrame(bx, by, 2, bh[i]);
    }
}

void oledHeader(const char *label) {
    int peers = (int)mesh.getNodeList().size();
    u8g2.setFont(u8g2_font_5x7_tf);
    if (peers > 0 && oBlink) u8g2.drawDisc(3, 4, 2);
    else                      u8g2.drawCircle(3, 4, 2);
    u8g2.setCursor(8, 8);
    u8g2.print(label);
    oledBars(119, 9, peers);
    u8g2.drawLine(0, 11, SCREEN_W, 11);
}

// ─── SCREEN: STATUS ────────────────────────────────────────────────────────
void oledDrawStatus() {
    u8g2.clearBuffer();
    oledHeader("MESH OS");

    int peers = (int)mesh.getNodeList().size();

    if (peers > 0) {
        u8g2.drawDisc(7, 22, 4);
        u8g2.setFont(u8g2_font_6x10_tf);
        u8g2.setCursor(16, 26);
        u8g2.print("ONLINE");
    } else {
        u8g2.drawCircle(7, 22, 4);
        u8g2.setFont(u8g2_font_6x10_tf);
        u8g2.setCursor(16, 26);
        u8g2.print("SCANNING");
        u8g2.setFont(u8g2_font_5x7_tf);
        for (int i = 0; i < (int)oScanDot; i++) u8g2.print(".");
    }

    // Own nickname (large-ish, centred)
    u8g2.setFont(u8g2_font_6x13B_tf);
    String nick = getNick(mesh.getNodeId());
    int tw = u8g2.getStrWidth(nick.c_str());
    u8g2.drawStr((SCREEN_W - tw) / 2, 43, nick.c_str());

    // Node ID (small, centred below nickname)
    u8g2.setFont(u8g2_font_4x6_tf);
    String nid = String(mesh.getNodeId()).substring(0, 8);
    tw = u8g2.getStrWidth(nid.c_str());
    u8g2.drawStr((SCREEN_W - tw) / 2, 51, nid.c_str());

    // Stats row
    u8g2.setFont(u8g2_font_5x7_tf);
    String pl = String(peers) + (peers == 1 ? " peer" : " peers");
    u8g2.setCursor(0, 54);
    u8g2.print(pl);
    if (chatCount > 0) {
        String ml = String(chatCount) + " msg";
        tw = u8g2.getStrWidth(ml.c_str());
        u8g2.setCursor(SCREEN_W - tw, 54);
        u8g2.print(ml);
    }

    // Mesh-synced uptime clock
    uint32_t sec = (uint32_t)(mesh.getNodeTime() / 1000000ULL);
    uint32_t mn  = sec / 60; sec %= 60;
    uint32_t hr  = mn  / 60; mn  %= 60;
    char up[16];
    snprintf(up, sizeof(up), "up %02u:%02u:%02u",
             (unsigned)hr, (unsigned)mn, (unsigned)sec);
    u8g2.setFont(u8g2_font_4x6_tf);
    tw = u8g2.getStrWidth(up);
    u8g2.drawStr((SCREEN_W - tw) / 2, 63, up);

    u8g2.sendBuffer();
}

// ─── SCREEN: MESSAGES ──────────────────────────────────────────────────────
void oledDrawMessages() {
    u8g2.clearBuffer();
    char hdr[16];
    snprintf(hdr, sizeof(hdr), "MSGS [%d]", chatCount);
    oledHeader(hdr);

    u8g2.setFont(u8g2_font_5x8_tf);

    int showCount = min(chatCount, 4);
    int firstIdx  = showCount - 1;

    bool flashLit = oNewFlash &&
                    (((millis() - oNewFlashT) / 300) % 2 == 0);

    int y = 21;
    for (int i = firstIdx; i >= 0; i--) {
        bool isNewest = (i == 0);

        if (isNewest && flashLit) {
            u8g2.setDrawColor(1);
            u8g2.drawBox(0, y - 8, SCREEN_W, 10);
            u8g2.setDrawColor(0);
        }

        String senderDisplay;
        if (chat[i].isMe) {
            senderDisplay = ">";
        } else {
            // Show own nick of the sender if known, else short ID
            uint32_t sid = (uint32_t)strtoul(chat[i].sender.c_str(), nullptr, 10);
            String sn = getNick(sid);
            senderDisplay = sn.substring(0, min((int)sn.length(), 5)) + ":";
        }

        String line = senderDisplay + " " + chat[i].text;
        if ((int)line.length() > 25) line = line.substring(0, 24) + '~';

        u8g2.setCursor(0, y);
        u8g2.print(line);

        if (isNewest && flashLit) u8g2.setDrawColor(1);
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
        int barW = (int)((float)(O_MSG_TIMEOUT - elapsed) / O_MSG_TIMEOUT * 70);
        if (barW > 0) u8g2.drawBox(SCREEN_W - barW, 59, barW, 3);
    }

    u8g2.sendBuffer();
}

// ─── PUBLIC OLED API ───────────────────────────────────────────────────────
void oledTriggerMessages() {
    if (!oledOK) return;
    oScreen    = SCR_MESSAGES;
    oMsgTimer  = millis();
    oNewFlash  = true;
    oNewFlashT = millis();
    oLastDraw  = 0;
}

void updateOLED() {
    if (!oledOK) return;
    uint32_t now = millis();
    if (now - oLastDraw < O_FPS_MS) return;
    oLastDraw = now;

    if (now - oBlinkT >= O_BLINK_MS) { oBlink = !oBlink; oBlinkT = now; }
    if (now - oScanT  >= O_SCAN_MS)  { oScanDot = (oScanDot + 1) % 4; oScanT = now; }
    if (oNewFlash && (now - oNewFlashT >= O_FLASH_MS)) oNewFlash = false;
    if (oScreen == SCR_MESSAGES && (now - oMsgTimer >= (uint32_t)O_MSG_TIMEOUT))
        oScreen = SCR_STATUS;

    switch (oScreen) {
        case SCR_STATUS:   oledDrawStatus();   break;
        case SCR_MESSAGES: oledDrawMessages(); break;
    }
}

// ─── MESH CALLBACKS ────────────────────────────────────────────────────────
void receivedCallback(uint32_t from, String &msg) {
    if (isDuplicate(msg)) return;

    // ── Nickname sync packet ─────────────────────────────────────────────
    if (msg.startsWith(NICK_SYNC_PREFIX)) {
        String body = msg.substring(strlen(NICK_SYNC_PREFIX));
        int sep = body.indexOf('|');
        if (sep > 0) {
            uint32_t id  = (uint32_t)strtoul(body.substring(0, sep).c_str(), nullptr, 10);
            String   nick = body.substring(sep + 1);
            nick.trim();
            if (nick.length() > 0 && nick.length() <= 20) {
                storeNick(id, nick);
                // Re-broadcast to propagate to further nodes (dedup prevents loops)
                mesh.sendBroadcast(msg);
            }
        }
        return;
    }

    // ── Regular chat packet ──────────────────────────────────────────────
    int sep = msg.indexOf('|');
    if (sep < 0) return;

    String sender = msg.substring(0, sep);
    String text   = msg.substring(sep + 1);

    if (sender == String(mesh.getNodeId())) return;   // drop self-echo

    pushMessage(sender, text, false);   // store full ID string as sender
    oledTriggerMessages();
}

void newConnectionCallback(uint32_t nodeId) {
    Serial.printf("[MESH] +Node: %u  |  total: %d\n",
                  nodeId, (int)mesh.getNodeList().size());
    // Re-announce own nickname so newly joined node learns it
    broadcastOwnNick();
    oLastDraw = 0;
}

void droppedConnectionCallback(uint32_t nodeId) {
    Serial.printf("[MESH] -Node: %u  |  total: %d\n",
                  nodeId, (int)mesh.getNodeList().size());
    oLastDraw = 0;
}

void changedConnectionsCallback() {
    Serial.printf("[MESH] Topology changed | nodes: %d\n",
                  (int)mesh.getNodeList().size());
    oLastDraw = 0;
}

void nodeTimeAdjustedCallback(int32_t offset) {
    Serial.printf("[MESH] Time adj: %d µs\n", offset);
}

// ─── BOOT SPLASH ───────────────────────────────────────────────────────────
static void bootSplash(const char *status, const char *detail = nullptr) {
    u8g2.clearBuffer();
    u8g2.setFont(u8g2_font_7x13B_tf);
    const char *title = "MESH  OS";
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

// ─── SETUP ─────────────────────────────────────────────────────────────────
void setup() {
    Serial.begin(115200);

    Wire.begin(I2C_SDA, I2C_SCL);
    delay(100);
    u8g2.begin();
    u8g2.setPowerSave(0);
    oledOK = true;
    bootSplash("initializing...");

    mesh.setDebugMsgTypes(ERROR | STARTUP);
    mesh.init(MESH_PREFIX, MESH_PASSWORD, &userScheduler,
              MESH_PORT, WIFI_AP_STA, MESH_CHANNEL);

    mesh.onReceive(&receivedCallback);
    mesh.onNewConnection(&newConnectionCallback);
    mesh.onDroppedConnection(&droppedConnectionCallback);
    mesh.onChangedConnections(&changedConnectionsCallback);
    mesh.onNodeTimeAdjusted(&nodeTimeAdjustedCallback);

    // ── Register own nickname in DB and broadcast it ──────────────────
    uint32_t myId = mesh.getNodeId();
    storeNick(myId, autoNick(myId));
    // Broadcast deferred to newConnectionCallback when first peer appears

    // ── HTTP routes ───────────────────────────────────────────────────

    server.on("/", HTTP_GET, [](AsyncWebServerRequest *r) {
        r->send(200, "text/html", index_html);
    });

    server.on("/send", HTTP_GET, [](AsyncWebServerRequest *r) {
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

    // Set (or update) a nickname — broadcasts the change to the whole mesh
    server.on("/setnick", HTTP_GET, [](AsyncWebServerRequest *r) {
        if (r->hasParam("id") && r->hasParam("nick")) {
            uint32_t id  = (uint32_t)strtoul(
                r->getParam("id")->value().c_str(), nullptr, 10);
            String nick = r->getParam("nick")->value();
            nick.trim();
            if (nick.length() == 0 || nick.length() > 20) {
                r->send(400, "text/plain", "bad nick");
                return;
            }
            storeNick(id, nick);
            // Build and broadcast the sync packet
            String pkt = String(NICK_SYNC_PREFIX) + String(id) + "|" + nick;
            mesh.sendBroadcast(pkt);
        }
        r->send(200, "text/plain", "OK");
    });

    server.on("/data", HTTP_GET, [](AsyncWebServerRequest *r) {
        String json = "{";
        json += "\"nodeId\":\""   + String(mesh.getNodeId()) + "\",";

        auto nodes = mesh.getNodeList();
        json += "\"nodeCount\":"  + String(nodes.size())     + ",";

        json += "\"peers\":[";
        bool fn = true;
        for (auto &id : nodes) {
            if (!fn) json += ",";
            json += "\"" + String(id) + "\"";
            fn = false;
        }
        json += "],";

        json += "\"topology\":"   + mesh.subConnectionJson() + ",";

        // Mesh-synchronized time (µs)
        json += "\"meshTime\":"   + String(mesh.getNodeTime()) + ",";

        // All known nicknames
        json += "\"nicknames\":[";
        bool fnk = true;
        for (int i = 0; i < nickDbCount; i++) {
            if (!fnk) json += ",";
            json += "{\"id\":\"" + String(nickDb[i].id) + "\","
                    "\"nick\":\"" + escapeJSON(nickDb[i].nick) + "\"}";
            fnk = false;
        }
        json += "],";

        // Messages (oldest → newest)
        json += "\"messages\":[";
        bool fm = true;
        for (int i = chatCount - 1; i >= 0; i--) {
            if (!fm) json += ",";
            json += "{\"sender\":\"" + escapeJSON(chat[i].sender) + "\","
                    "\"text\":\""    + escapeJSON(chat[i].text)   + "\","
                    "\"ts\":"        + String(chat[i].ts)          + ","
                    "\"me\":"        + (chat[i].isMe ? "true" : "false") + "}";
            fm = false;
        }
        json += "]}";
        r->send(200, "application/json", json);
    });

    server.on("/nodes", HTTP_GET, [](AsyncWebServerRequest *r) {
        r->send(200, "text/html", nodes_html);
    });

    server.begin();

    String nick = getNick(myId);
    bootSplash(("hi, " + nick).c_str(),
               String(myId).substring(0, 8).c_str());
    delay(1000);

    Serial.printf("[BOOT] Node %u (%s) ready\n",
                  myId, nick.c_str());
}

// ─── LOOP ──────────────────────────────────────────────────────────────────
void loop() {
    mesh.update();
    updateOLED();
}
