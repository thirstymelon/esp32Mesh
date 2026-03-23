#include <Arduino.h>
#include <painlessMesh.h>
#include <ESPAsyncWebServer.h>
#include <Wire.h>
#include "web_page.h"
#include <U8g2lib.h>

// CONFIG

U8G2_SSD1306_128X64_NONAME_F_HW_I2C u8g2(U8G2_R0, U8X8_PIN_NONE);

#define MESH_PREFIX     "ESP32Mesh"
#define MESH_PASSWORD   "meshpass123"
#define MESH_PORT       5555
#define MESH_CHANNEL    6

#define MAX_MESSAGES    20

// OLED

#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64
#define I2C_SDA 21
#define I2C_SCL 22

bool oledOK = false;

// STRUCT

struct ChatMessage {
    String sender;
    String text;
    bool isMe;
};

// GLOBALS

Scheduler userScheduler;
painlessMesh mesh;
AsyncWebServer server(80);

ChatMessage chat[MAX_MESSAGES];
int chatCount = 0;

// HELPERS

void pushMessage(const String &sender, const String &text, bool isMe) {

    if (chatCount < MAX_MESSAGES) chatCount++;

    for (int i = chatCount - 1; i > 0; i--)
        chat[i] = chat[i - 1];

    chat[0] = { sender, text, isMe };
}

String escapeJSON(const String &s) {
    String o;
    for (char c : s) {
        if (c == '"' || c == '\\') o += '\\';
        o += c;
    }
    return o;
}

// OLED UI

void updateOLED() {

    if (!oledOK) return;

    u8g2.clearBuffer();
    u8g2.setFont(u8g2_font_6x12_tf);

    String nodeStr = String(mesh.getNodeId()).substring(0, 4);
    String countStr = String(mesh.getNodeList().size());

    u8g2.setCursor(0, 10);
    u8g2.print("Node ");
    u8g2.print(nodeStr);
    u8g2.print(" | ");
    u8g2.print(countStr);

    u8g2.drawLine(0, 12, SCREEN_WIDTH, 12);

    int y = 24;

    for (int i = 0; i < 4 && i < chatCount; i++) {

        String prefix = chat[i].isMe ? " " : chat[i].sender + ": ";
        String line = prefix + chat[i].text;

        u8g2.setCursor(0, y);
        u8g2.print(line.substring(0, 21));

        y += 12;
    }

    u8g2.sendBuffer();
}

// MESH

void receivedCallback(uint32_t from, String &msg) {

    int sep = msg.indexOf('|');
    if (sep < 0) return;

    String sender = msg.substring(0, sep);
    String text   = msg.substring(sep + 1);

    if (sender == String(mesh.getNodeId())) return;

    pushMessage(sender.substring(0,4), text, false);
    updateOLED();
}

// SETUP

void setup() {

    Serial.begin(115200);

    Wire.begin(I2C_SDA, I2C_SCL);
    delay(100);

    u8g2.begin();
    u8g2.setPowerSave(0);

    u8g2.clearBuffer();
    u8g2.setFont(u8g2_font_6x12_tf);

    const char* msg = "MESH INIT";

    int textWidth = u8g2.getStrWidth(msg);

    int x = (SCREEN_WIDTH - textWidth) / 2;

    int y = (SCREEN_HEIGHT / 2);

    u8g2.drawStr(x, y, msg);

    u8g2.sendBuffer();

    oledOK = true;

    
    mesh.init(MESH_PREFIX, MESH_PASSWORD, &userScheduler,
              MESH_PORT, WIFI_AP_STA, MESH_CHANNEL);

    mesh.onReceive(&receivedCallback);

    server.on("/", HTTP_GET, [](AsyncWebServerRequest *r){
        r->send_P(200,"text/html",index_html);
    });

    server.on("/send", HTTP_GET, [](AsyncWebServerRequest *r){

        if(r->hasParam("msg")){
            String text=r->getParam("msg")->value();
            pushMessage("Me", text, true);
            updateOLED();

            String payload=String(mesh.getNodeId())+"|"+text;
            mesh.sendBroadcast(payload);
        }
        r->send(200,"text/plain","OK");
    });

    server.on("/data", HTTP_GET, [](AsyncWebServerRequest *r){

        String json="{";
        json+="\"nodeId\":\""+String(mesh.getNodeId())+"\",";
        json+="\"nodeCount\":\""+String(mesh.getNodeList().size())+"\",";


        json+="\"nodeIdList\":[";
        auto nodes = mesh.getNodeList();
        for(auto &&id : nodes){
            json+="\""+String(id)+"\",";
        }
        json+="],";

        json+="\"messages\":[";

        for(int i=chatCount-1;i>=0;i--){
            json+="{";
            json+="\"sender\":\""+escapeJSON(chat[i].sender)+"\",";
            json+="\"text\":\""+escapeJSON(chat[i].text)+"\",";
            json+="\"me\":"+String(chat[i].isMe?"true":"false");
            json+="},";
        }

        json+="]}";
        json.replace(",]","]");

        r->send(200,"application/json",json);
    });


    server.on("/nodes", HTTP_GET, [](AsyncWebServerRequest *r){
        r->send_P(200,"text/html",nodes_html);
    });

    server.begin();
}



void loop() {
    mesh.update();
}
