#include <WiFi.h>
#include <HTTPClient.h>
#include <ArduinoJson.h>
#include <Keypad.h>
#include <LiquidCrystal.h>

// ── WiFi & Server ─────────────────────────────────────────────────────────────
const char* ssid       = "Wokwi-GUEST";
const char* password   = "";
const char* serverBase = "https://4b12-41-139-167-17.ngrok-free.app";
const int   DEFAULT_OFFICE_ID = 10;

// ── LCD: RS, EN, D4, D5, D6, D7 ──────────────────────────────────────────────
LiquidCrystal lcd(23, 5, 18, 19, 21, 22);

// ── Keypad ────────────────────────────────────────────────────────────────────
const byte ROWS = 4, COLS = 4;
char keys[ROWS][COLS] = {
  {'1','2','3','A'},
  {'4','5','6','B'},
  {'7','8','9','C'},
  {'*','0','#','D'}
};
byte rowPins[ROWS] = {12, 13, 14, 27};
byte colPins[COLS] = {26, 25, 33, 32};
Keypad keypad = Keypad(makeKeymap(keys), rowPins, colPins, ROWS, COLS);

// ── State ─────────────────────────────────────────────────────────────────────
String dqmsInput    = "";          // what user is typing (e.g. "C100")
String nowServing   = "---";       // top row: current serving ticket
unsigned long lastPoll = 0;
const unsigned long POLL_MS = 3000;

// ── Helpers ───────────────────────────────────────────────────────────────────
String pad16(String s) {
  while ((int)s.length() < 16) s += ' ';
  return s.substring(0, 16);
}

void drawScreen() {
  // Row 0: Now Serving
  lcd.setCursor(0, 0);
  lcd.print(pad16("Now: " + nowServing));
  // Row 1: DQMS input
  lcd.setCursor(0, 1);
  lcd.print(pad16("DQMS: " + dqmsInput));
}

// ── Poll /api/display/:officeId ───────────────────────────────────────────────
void pollDisplay() {
  if (WiFi.status() != WL_CONNECTED) return;

  HTTPClient http;
  http.setTimeout(3000);
  String url = String(serverBase) + "/api/display/" + String(DEFAULT_OFFICE_ID);
  http.begin(url);
  http.addHeader("ngrok-skip-browser-warning", "true");
  int code = http.GET();

  if (code == 200) {
    StaticJsonDocument<256> doc;
    deserializeJson(doc, http.getString());
    String serving = doc["now_serving"] | "---";
    if (serving != nowServing) {
      nowServing = serving;
      drawScreen();
    }
  }
  http.end();
}

// ── Register DQMS number into queue ──────────────────────────────────────────
void registerDQMS() {
  if (dqmsInput.length() == 0) {
    lcd.setCursor(0, 1); lcd.print(pad16("Enter DQMS No!"));
    delay(1000);
    drawScreen();
    return;
  }

  lcd.setCursor(0, 1); lcd.print(pad16("Registering..."));

  HTTPClient http;
  http.setTimeout(5000);
  http.begin(String(serverBase) + "/api/register");
  http.addHeader("Content-Type", "application/json");
  http.addHeader("ngrok-skip-browser-warning", "true");

  String body = "{\"dqmsNumber\":\"" + dqmsInput + "\",\"officeId\":" + String(DEFAULT_OFFICE_ID) + "}";
  int code = http.POST(body);

  if (code == 200 || code == 201) {
    StaticJsonDocument<512> doc;
    deserializeJson(doc, http.getString());
    String ticket = doc["data"]["ticket_number"] | "???";
    lcd.setCursor(0, 1); lcd.print(pad16("Ticket: #" + ticket));
    delay(3000);
  } else {
    lcd.setCursor(0, 1); lcd.print(pad16("Error: " + String(code)));
    delay(2000);
  }
  http.end();
  dqmsInput = "";
  drawScreen();
}

// ── Setup ─────────────────────────────────────────────────────────────────────
void setup() {
  Serial.begin(115200);
  lcd.begin(16, 2);

  lcd.setCursor(0, 0); lcd.print(pad16("Connecting WiFi"));
  lcd.setCursor(0, 1); lcd.print(pad16("Please wait..."));

  WiFi.begin(ssid, password);
  int attempts = 0;
  while (WiFi.status() != WL_CONNECTED && attempts < 40) {
    delay(500); attempts++;
  }

  if (WiFi.status() == WL_CONNECTED) {
    lcd.setCursor(0, 0); lcd.print(pad16("WiFi OK!"));
  } else {
    lcd.setCursor(0, 0); lcd.print(pad16("WiFi Failed!"));
  }
  delay(1000);

  pollDisplay();   // fetch immediately on boot
  drawScreen();
}

// ── Loop ──────────────────────────────────────────────────────────────────────
void loop() {

  // 1) Keypad — always first, non-blocking
  char key = keypad.getKey();
  if (key != NO_KEY) {
    Serial.print("Key: "); Serial.println(key);

    if ((key >= '0' && key <= '9') || (key >= 'A' && key <= 'D')) {
      // Letters A-D used as prefix letters (A,B,C,D)
      if ((int)dqmsInput.length() < 10) {
        dqmsInput += key;
        lcd.setCursor(0, 1);
        lcd.print(pad16("DQMS: " + dqmsInput));
      }
    }
    else if (key == '*') {
      // Clear input
      dqmsInput = "";
      drawScreen();
    }
    else if (key == '#') {
      // Submit
      registerDQMS();
    }
  }

  // 2) Poll server every POLL_MS — non-blocking
  unsigned long now = millis();
  if (now - lastPoll >= POLL_MS) {
    lastPoll = now;
    pollDisplay();
  }
}
