// Plug this ESP32 into any regular wall outlet - NOT the UPS. Its own power
// state becomes a free "is mains actually back?" signal: it only boots when
// it has power, so on every boot it connects to WiFi and sends a
// Wake-on-LAN magic packet to xero (the homelab server), which has no other
// way to know mains has returned after the power-outage watchdog
// (watchdog_power.sh) shuts it down gracefully while the UPS still has
// charge left - see the "Power-outage watchdog" entry in PROJECTS.md for
// the full context on why a graceful shutdown doesn't trigger the BIOS's
// own "restore on AC power loss" behavior.
#include <WiFi.h>
#include <WiFiUdp.h>
#include "secrets.h"

// xero's enp1s0 MAC address
byte targetMac[6] = { 0x68, 0x1D, 0xEF, 0x38, 0x8C, 0x72 };

IPAddress broadcastIP(192, 168, 1, 255);
const int WOL_PORT = 9;

WiFiUDP udp;

void sendMagicPacket() {
  byte packet[102];
  for (int i = 0; i < 6; i++) packet[i] = 0xFF;
  for (int i = 0; i < 16; i++) {
    memcpy(&packet[6 + i * 6], targetMac, 6);
  }
  udp.beginPacket(broadcastIP, WOL_PORT);
  udp.write(packet, sizeof(packet));
  udp.endPacket();
}

void setup() {
  Serial.begin(115200);
  delay(500);
  Serial.println("Booting - connecting to WiFi...");

  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  unsigned long start = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - start < 30000) {
    delay(500);
    Serial.print(".");
  }

  if (WiFi.status() == WL_CONNECTED) {
    Serial.println("\nWiFi connected: " + WiFi.localIP().toString());
    delay(2000);  // let the network settle before broadcasting
    Serial.println("Sending magic packet (x3)...");
    for (int i = 0; i < 3; i++) {
      sendMagicPacket();
      delay(300);
    }
    Serial.println("Done.");
  } else {
    Serial.println("\nWiFi connect failed after 30s - giving up this boot.");
  }
}

void loop() {
  // nothing to do - sits idle until the next power cycle
}
