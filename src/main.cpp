/*
 * ESP32 Mesh Network with OLED + Web Interface - COMPLETE WORKING VERSION
 * Mesh discovery fixed + Web server for sending messages
 */

#include <Arduino.h>
#include <painlessMesh.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <ESPAsyncWebServer.h>

// Mesh Configuration
#define MESH_PREFIX     "ESP32Mesh"
#define MESH_PASSWORD   "meshpass123"
#define MESH_PORT       5555

// OLED Configuration
#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 64
#define OLED_RESET    -1
#define SCREEN_ADDRESS 0x3C

// I2C Pins
#define I2C_SDA 21
#define I2C_SCL 22

// Web Server Configuration
#define WEB_SERVER_PORT 80

// Objects
Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, OLED_RESET);
Scheduler userScheduler;
painlessMesh mesh;
AsyncWebServer server(WEB_SERVER_PORT);

// Variables
String nodeID = "";
unsigned long lastDisplayUpdate = 0;
const unsigned long DISPLAY_UPDATE_INTERVAL = 500;

// Message queue
#define MAX_MESSAGES 10
String messageQueue[MAX_MESSAGES];
int messageIndex = 0;
bool oledWorking = false;

// Function declarations
void receivedCallback(uint32_t from, String &msg);
void newConnectionCallback(uint32_t nodeId);
void changedConnectionCallback();
void nodeTimeAdjustedCallback(int32_t offset);
void setupDisplay();
void updateDisplay();
void addMessage(String msg);
void setupWebServer();

// Periodic task to show mesh status
Task taskShowStatus(10000, TASK_FOREVER, []() {
  Serial.println("\n📊 MESH STATUS:");
  Serial.printf("   My Node: %u\n", mesh.getNodeId());
  Serial.printf("   Connected: %d nodes\n", mesh.getNodeList().size());
  Serial.printf("   Uptime: %lu sec\n", millis() / 1000);

  if (mesh.getNodeList().size() == 0) {
    Serial.println("   ⚠️  No other nodes connected yet");
  }
});

void setup() {
  Serial.begin(115200);
  delay(1000);

  Serial.println("\n\n╔═══════════════════════════════════════════╗");
  Serial.println("║  ESP32 Mesh + OLED + Web - WORKING v2.0  ║");
  Serial.println("╚═══════════════════════════════════════════╝\n");

  // Step 1: Initialize OLED
  Serial.println("[1/3] Initializing OLED...");
  Wire.begin(I2C_SDA, I2C_SCL);
  delay(100);
  setupDisplay();

  // Step 2: Initialize Mesh
  Serial.println("\n[2/3] Initializing Mesh Network...");

  // Set mesh callbacks BEFORE init
  mesh.setDebugMsgTypes(ERROR | STARTUP | CONNECTION);
  mesh.onReceive(&receivedCallback);
  mesh.onNewConnection(&newConnectionCallback);
  mesh.onChangedConnections(&changedConnectionCallback);
  mesh.onNodeTimeAdjusted(&nodeTimeAdjustedCallback);

  // Initialize mesh (this starts WiFi in mesh mode)
  mesh.init(MESH_PREFIX, MESH_PASSWORD, &userScheduler, MESH_PORT);

  nodeID = String(mesh.getNodeId());

  Serial.println("✓ Mesh initialized!");
  Serial.printf("  Node ID: %u\n", mesh.getNodeId());
  Serial.printf("  Short ID: %s\n", nodeID.substring(nodeID.length() - 4).c_str());

  // Step 3: Setup Web Server on mesh
  Serial.println("\n[3/3] Starting Web Server...");
  setupWebServer();

  // Add status task
  userScheduler.addTask(taskShowStatus);
  taskShowStatus.enable();

  // Initial messages
  addMessage("Node:" + nodeID.substring(nodeID.length() - 4));
  addMessage("Ready!");

  Serial.println("\n╔═══════════════════════════════════════════╗");
  Serial.println("║            STARTUP COMPLETE!              ║");
  Serial.println("╚═══════════════════════════════════════════╝");
  Serial.printf("OLED: %s\n", oledWorking ? "✓ Working" : "✗ Disabled");
  Serial.printf("Mesh: ✓ Active (%s)\n", MESH_PREFIX);
  Serial.printf("Web:  ✓ Running on mesh IP\n\n");
  Serial.println("📝 To connect:");
  Serial.println("   1. Another device must join the mesh");
  Serial.println("   2. Access web via mesh IP (check painlessMesh docs)");
  Serial.println("   3. Or send messages programmatically\n");
  Serial.println("🔄 Waiting for nodes to connect...\n");
}

void loop() {
  mesh.update();

  if (millis() - lastDisplayUpdate > DISPLAY_UPDATE_INTERVAL) {
    updateDisplay();
    lastDisplayUpdate = millis();
  }
}

void setupDisplay() {
  if(!display.begin(SSD1306_SWITCHCAPVCC, SCREEN_ADDRESS)) {
    Serial.println("✗ OLED not found");
    Serial.println("  Check wiring or change SCREEN_ADDRESS to 0x3D");
    oledWorking = false;
    return;
  }

  oledWorking = true;
  Serial.println("✓ OLED OK at 0x" + String(SCREEN_ADDRESS, HEX));

  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(SSD1306_WHITE);
  display.setCursor(10, 20);
  display.println("ESP32 Mesh");
  display.setCursor(10, 35);
  display.println("Initializing...");
  display.display();
  delay(800);
}

void setupWebServer() {
  // Root page
  server.on("/", HTTP_GET, [](AsyncWebServerRequest *request){
    String html = "<!DOCTYPE html><html><head>";
    html += "<meta name='viewport' content='width=device-width, initial-scale=1'>";
    html += "<style>";
    html += "body{font-family:Arial;max-width:600px;margin:20px auto;padding:20px;background:#f5f5f5}";
    html += ".container{background:white;padding:30px;border-radius:10px;box-shadow:0 2px 10px rgba(0,0,0,0.1)}";
    html += "h1{color:#2196F3;text-align:center;margin-bottom:10px}";
    html += ".info{background:#e3f2fd;padding:15px;border-radius:5px;margin:15px 0}";
    html += "input{width:100%;padding:12px;margin:10px 0;border:2px solid #ddd;border-radius:5px;box-sizing:border-box;font-size:16px}";
    html += "button{background:#4CAF50;color:white;padding:15px;border:none;border-radius:5px;cursor:pointer;width:100%;font-size:16px;font-weight:bold}";
    html += "button:hover{background:#45a049}";
    html += ".status{background:#fff3cd;padding:10px;border-left:4px solid #ffc107;margin:15px 0}";
    html += "</style></head><body>";
    html += "<div class='container'>";
    html += "<h1>🌐 ESP32 Mesh Network</h1>";
    html += "<div class='info'>";
    html += "<b>📡 Node ID:</b> " + nodeID + "<br>";
    html += "<b>🔗 Connected Nodes:</b> " + String(mesh.getNodeList().size()) + "<br>";
    html += "<b>⏱ Uptime:</b> " + String(millis() / 1000) + " seconds";
    html += "</div>";
    html += "<h2>📤 Send Message</h2>";
    html += "<form action='/send' method='POST'>";
    html += "<input type='text' name='message' placeholder='Type your message...' maxlength='100' required autofocus>";
    html += "<button type='submit'>Send to All Nodes</button>";
    html += "</form>";
    html += "<div class='status'>";
    html += "<b>ℹ️ Status:</b> ";
    if (mesh.getNodeList().size() > 0) {
      html += "✓ Connected to mesh";
    } else {
      html += "⚠ No other nodes detected";
    }
    html += "</div>";
    html += "</div></body></html>";

    request->send(200, "text/html", html);
  });

  // Send message endpoint
  server.on("/send", HTTP_POST, [](AsyncWebServerRequest *request){
    if (request->hasParam("message", true)) {
      String message = request->getParam("message", true)->value();

      // Broadcast to mesh
      mesh.sendBroadcast(message);

      Serial.println("📤 Sent via web: " + message);
      addMessage("Me:" + message.substring(0, 17));

      // Redirect back
      request->redirect("/");
    } else {
      request->send(400, "text/plain", "Bad Request");
    }
  });

  server.begin();
  Serial.println("✓ Web server started");
}

void addMessage(String msg) {
  messageQueue[messageIndex] = msg;
  messageIndex = (messageIndex + 1) % MAX_MESSAGES;
}

void updateDisplay() {
  if (!oledWorking) return;

  display.clearDisplay();
  display.setTextSize(1);
  display.setTextColor(SSD1306_WHITE);

  // Header
  display.setCursor(0, 0);
  display.print("N:");
  display.print(nodeID.substring(nodeID.length() - 4));
  display.print(" C:");
  display.println(mesh.getNodeList().size());
  display.drawLine(0, 9, SCREEN_WIDTH, 9, SSD1306_WHITE);

  // Messages (last 5)
  int y = 12;
  int startIdx = max(0, messageIndex - 5);

  for (int i = startIdx; i < messageIndex && i < startIdx + 5; i++) {
    if (y >= SCREEN_HEIGHT) break;

    display.setCursor(0, y);
    String msg = messageQueue[i % MAX_MESSAGES];

    if (msg.length() > 21) {
      display.println(msg.substring(0, 21));
      y += 10;
    } else {
      display.println(msg);
      y += 10;
    }
  }

  display.display();
}

void receivedCallback(uint32_t from, String &msg) {
  Serial.printf("📨 FROM %u: %s\n", from, msg.c_str());

  String fromShort = String(from).substring(String(from).length() - 4);
  addMessage(fromShort + ":" + msg.substring(0, 15));
}

void newConnectionCallback(uint32_t nodeId) {
  Serial.printf("\n🎉 NEW NODE: %u\n", nodeId);
  Serial.printf("   Total: %d nodes\n\n", mesh.getNodeList().size() + 1);

  addMessage("+" + String(nodeId).substring(String(nodeId).length() - 4));
}

void changedConnectionCallback() {
  Serial.println("🔄 Topology changed");
  Serial.printf("   Nodes: %d\n", mesh.getNodeList().size());
}

void nodeTimeAdjustedCallback(int32_t offset) {
  // Time sync callback
}
