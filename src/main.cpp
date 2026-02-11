#include <Arduino.h>
#include <painlessMesh.h>
#include <ESPAsyncWebServer.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>

/* ================= CONFIG ================= */

#define MESH_PREFIX     "ESP32Mesh"
#define MESH_PASSWORD   "meshpass123"
#define MESH_PORT       5555
#define MESH_CHANNEL    6

#define MAX_MESSAGES    20

/* ================= OLED ================= */

#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64
#define OLED_RESET -1
#define SCREEN_ADDRESS 0x3C
#define I2C_SDA 21
#define I2C_SCL 22

Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, OLED_RESET);
bool oledOK = false;

/* ================= STRUCT ================= */

struct ChatMessage {
    String sender;
    String text;
    bool isMe;
};

/* ================= GLOBALS ================= */

Scheduler userScheduler;
painlessMesh mesh;
AsyncWebServer server(80);

ChatMessage chat[MAX_MESSAGES];
int chatCount = 0;

/* ================= HELPERS ================= */

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

/* ================= OLED UI ================= */

void updateOLED() {

    if (!oledOK) return;

    display.clearDisplay();
    display.setTextSize(1);
    display.setTextColor(SSD1306_WHITE);

    // Header
    display.setCursor(0, 0);
    display.print("Node ");
    display.print(String(mesh.getNodeId()).substring(0,4));
    display.print(" | ");
    display.print(mesh.getNodeList().size());

    display.drawLine(0, 10, SCREEN_WIDTH, 10, SSD1306_WHITE);

    // Show last 4 messages
    int y = 14;

    for (int i = 0; i < 4 && i < chatCount; i++) {

        display.setCursor(0, y);

        String prefix = chat[i].isMe ? "Me: " : chat[i].sender + ": ";
        String line = prefix + chat[i].text;

        display.println(line.substring(0, 21));
        y += 12;
    }

    display.display();
}

/* ================= HTML ================= */

const char index_html[] PROGMEM = R"rawliteral(
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Mesh Chat</title>
<style>
body{
    margin:0;
    padding:20px;
    background:#000;
    color:#fff;
    font-family:system-ui;
}
.container{max-width:600px;margin:auto;}
h1{text-align:center;margin-bottom:15px;}
.info{
    display:flex;
    justify-content:space-between;
    font-size:13px;
    opacity:.7;
    margin-bottom:12px;
}
.chat{
    min-height:320px;
    padding:14px;
    border-radius:16px;
    outline:1px solid #333;
    display:flex;
    flex-direction:column;
    gap:10px;
    overflow-y:auto;
}
.msg{
    max-width:80%;
    padding:10px 14px;
    border-radius:18px;
    font-size:14px;
}
.me{
    align-self:flex-end;
    background:#fff;
    color:#000;
}
.other{
    align-self:flex-start;
    border:1px solid #333;
}
.input-row{
    display:flex;
    gap:10px;
    margin-top:14px;
}
input{
    flex:1;
    padding:14px;
    border-radius:999px;
    border:1px solid #444;
    background:#000;
    color:#fff;
}
button{
    padding:14px 20px;
    border-radius:999px;
    border:1px solid #fff;
    background:#fff;
    color:#000;
    font-weight:600;
}
</style>
</head>
<body>
<div class="container">
<h1>Mesh Chat</h1>

<div class="info">
<div>Node: <span id="nodeId">-</span></div>
<div>Peers: <span id="nodeCount">-</span></div>
</div>

<div class="chat" id="chat"></div>

<div class="input-row">
<input id="msg" placeholder="Type message"
onkeydown="if(event.key==='Enter')send()">
<button onclick="send()">Send</button>
</div>
</div>

<script>
let rendered = 0;

function send(){
    const i=document.getElementById('msg');
    const t=i.value.trim();
    if(!t)return;
    fetch('/send?msg='+encodeURIComponent(t));
    i.value='';
}

function update(){
fetch('/data').then(r=>r.json()).then(d=>{

document.getElementById('nodeId').textContent=d.nodeId;
document.getElementById('nodeCount').textContent=d.nodeCount;

const box=document.getElementById('chat');

for(let i=rendered;i<d.messages.length;i++){
    const m=d.messages[i];
    const div=document.createElement('div');
    div.className='msg '+(m.me?'me':'other');
    div.textContent=(m.me?'Me: ':m.sender+': ')+m.text;
    box.appendChild(div);
}

rendered=d.messages.length;
box.scrollTop=box.scrollHeight;

});
}

setInterval(update,1000);
update();
</script>
</body>
</html>
)rawliteral";

/* ================= MESH ================= */

void receivedCallback(uint32_t from, String &msg) {

    int sep = msg.indexOf('|');
    if (sep < 0) return;

    String sender = msg.substring(0, sep);
    String text   = msg.substring(sep + 1);

    if (sender == String(mesh.getNodeId())) return;

    pushMessage(sender.substring(0,4), text, false);
    updateOLED();
}

/* ================= SETUP ================= */

void setup() {

    Serial.begin(115200);

    // OLED
    Wire.begin(I2C_SDA, I2C_SCL);
    if(display.begin(SSD1306_SWITCHCAPVCC, SCREEN_ADDRESS))
        oledOK = true;

    // Mesh
    mesh.init(MESH_PREFIX, MESH_PASSWORD, &userScheduler,
              MESH_PORT, WIFI_AP_STA, MESH_CHANNEL);

    mesh.onReceive(&receivedCallback);

    // Web
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

    server.begin();
}

/* ================= LOOP ================= */

void loop() {
    mesh.update();
}
