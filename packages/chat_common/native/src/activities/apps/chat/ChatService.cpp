#include "ChatService.h"
#if CROSSMUX_CHAT
#include <HalEspNow.h>
#include <HalStorage.h>
#include <Logging.h>
#include <Memory.h>
#include <WiFi.h>

#include <memory>

#include "AppCapabilities.h"
#include "ChatSession.h"
#include "WifiCredentialStore.h"
namespace chat::service {
namespace {
struct Slot {
  std::unique_ptr<Session> session;
  uint8_t clients = 0;
  bool background = false;
  bool attempted = false;
};
Slot slots[3];
static_assert(static_cast<unsigned>(Kind::EspNow) == 2);
bool loaded = false;
bool stopped = false;
bool wifiOwned = false;
uint32_t joinAt = 0;
uint8_t joinAttempts = 0;
constexpr char PREFS[] = "/.crosspoint/chat-background-v2.txt";
constexpr char TEMP[] = "/.crosspoint/chat-background-v2.part";
size_t index(Kind kind) { return static_cast<size_t>(kind); }
bool ensureEspWifi() {
  const bool wasOff = WiFi.getMode() == WIFI_OFF;
  if (!HalEspNow::startWifi()) return false;
  if (wasOff) wifiOwned = true;
  return true;
}
bool supported(Kind kind) {
  switch (kind) {
    case Kind::Radio:
      return CROSSMUX_LORA_CHAT && appCapabilities::allows(appCapabilities::Requirement::Radio);
    case Kind::Wifi:
      return CROSSMUX_TOX_CHAT && appCapabilities::allows(appCapabilities::Requirement::WifiChat);
    case Kind::EspNow:
      return CROSSMUX_ESP_CHAT && appCapabilities::allows(appCapabilities::Requirement::EspNow);
  }
  return false;
}
Session* start(Kind kind) {
  auto& slot = slots[index(kind)];
  if (slot.session && (slot.session->active() || slot.clients)) return slot.session.get();
  slot.session.reset();
  slot.attempted = true;
  if (!supported(kind) || stopped) return nullptr;
  if (kind == Kind::EspNow && !ensureEspWifi()) return nullptr;
  // Bounded session is allocated only for an active foreground/background
  // listener, and freed when disabled or sleeping. No permanent reader cost.
  slot.session = makeUniqueNoThrow<Session>(kind);
  if (!slot.session || !slot.session->start()) {
    LOG_ERR("CHAT", "OOM/start failure for service (%u bytes)", static_cast<unsigned>(sizeof(Session)));
    slot.session.reset();
  }
  return slot.session.get();
}
}  // namespace
Session* acquire(Kind kind) {
  auto* session = start(kind);
  if (session) ++slots[index(kind)].clients;
  return session;
}
void release(Kind kind) {
  auto& slot = slots[index(kind)];
  if (slot.session) slot.session->viewing("");
  if (slot.clients) --slot.clients;
  if (!slot.background && !slot.clients) slot.session.reset();
  if (!slots[index(Kind::Wifi)].session && !slots[index(Kind::EspNow)].session && wifiOwned) {
    WiFi.mode(WIFI_OFF);
    wifiOwned = false;
  }
}
bool background(Kind kind) { return slots[index(kind)].background; }
bool setBackground(Kind kind, bool enabled) {
  if (!supported(kind) || stopped) return false;
  const auto i = index(kind);
  char flags[4] = {slots[0].background ? '1' : '0', slots[1].background ? '1' : '0', slots[2].background ? '1' : '0',
                   '\n'};
  flags[i] = enabled ? '1' : '0';
  {
    auto file = Storage.open(TEMP, O_WRONLY | O_CREAT | O_TRUNC);
    if (!file || file.write(flags, sizeof(flags)) != sizeof(flags)) return false;
    file.flush();
  }
  if (!Storage.replaceFile(TEMP, PREFS)) return false;
  slots[i].background = enabled;
  if (!enabled && !slots[i].clients) release(kind);
  joinAttempts = 0;
  return true;
}
void ownWifi() { wifiOwned = true; }
void tick(bool allowWifiJoin) {
  if (stopped || !Storage.ready()) return;
  static uint32_t lastTick = 0;
  if (loaded && millis() - lastTick < 500) return;
  lastTick = millis();
  if (!loaded) {
    loaded = true;
    const bool legacy = !Storage.exists(PREFS);
    char flags[4]{};
    auto file = Storage.open(legacy ? "/.crosspoint/chat-background-v1.txt" : PREFS);
    const size_t count = legacy ? 2 : 3;
    bool valid = file && file.size() == count + 1 && file.read(flags, count + 1) == count + 1 && flags[count] == '\n';
    for (size_t i = 0; i < count; ++i) valid = valid && (flags[i] == '0' || flags[i] == '1');
    if (valid)
      for (size_t i = 0; i < count; ++i) slots[i].background = flags[i] == '1' && supported(static_cast<Kind>(i));
  }
  auto& esp = slots[index(Kind::EspNow)];
  if (esp.background && (allowWifiJoin || (WiFi.getMode() & WIFI_STA))) {
    if (ensureEspWifi() && !esp.attempted) start(Kind::EspNow);
  }

  if (slots[0].background && !slots[0].attempted) start(Kind::Radio);
  if (!slots[1].background || slots[1].clients) return;
  if (WiFi.status() == WL_CONNECTED) {
    if (!slots[1].attempted) start(Kind::Wifi);
    return;
  }
  // Reconnect only when this service owns Wi-Fi. An unrelated AP/transfer
  // activity must never be displaced by a background retry.
  if (!allowWifiJoin || (WiFi.getMode() != WIFI_OFF && WiFi.getMode() != WIFI_STA) ||
      (WiFi.getMode() != WIFI_OFF && !wifiOwned))
    return;
  const uint32_t now = millis();
  if (joinAttempts >= 3 || (joinAttempts && now - joinAt < 30000)) return;
  // Boot does not load the Wi-Fi store. Match the foreground selector's cold
  // load once per reconnect cycle; reuse its bounded (eight-network) store.
  if (joinAttempts == 0 && WIFI_STORE.getCredentialCount() == 0) WIFI_STORE.loadFromFile();
  joinAt = now;
  ++joinAttempts;
  // Credential store returns a bounded saved credential; the temporary strings
  // exist only for this cold reconnect and are released immediately.
  const auto credential = WIFI_STORE.findCredential(WIFI_STORE.getLastConnectedSsid());
  if (!credential) return;
  LOG_INF("CHAT", "Starting background Wi-Fi reconnect (%u/3)", joinAttempts);
  wifiOwned = true;
  WiFi.mode(WIFI_STA);
  WiFi.begin(credential->ssid.c_str(), credential->password.c_str());
}
void stopForSleep() {
  stopped = true;
  for (auto& slot : slots) {
    slot.session.reset();
    slot.clients = 0;
  }
  if (wifiOwned) {
    WiFi.mode(WIFI_OFF);
    wifiOwned = false;
  }
}
}  // namespace chat::service
#endif
