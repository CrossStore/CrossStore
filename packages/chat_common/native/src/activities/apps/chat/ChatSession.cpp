#include "ChatSession.h"

#if CROSSMUX_CHAT
#include <Arduino.h>
#include <HalMemory.h>
#include <Logging.h>
#include <Memory.h>

#include <cstdio>

#include "EspNowBackend.h"
#include "system/SystemMessages.h"

namespace chat {
namespace {
systemMessages::Source noticeSource(Kind kind) {
  switch (kind) {
    case Kind::Radio:
      return systemMessages::Source::Radio;
    case Kind::Wifi:
      return systemMessages::Source::Wifi;
    case Kind::EspNow:
      return systemMessages::Source::EspNow;
  }
  return systemMessages::Source::Radio;
}
void radioName(uint64_t id, char* out) {
  uint8_t bytes[8];
  radio::put(bytes, id, sizeof(bytes));
  hex(bytes, sizeof(bytes), out);
}
uint64_t radioAddress(const char* id) {
  uint8_t bytes[8];
  return unhex(id, bytes, sizeof(bytes)) ? radio::get(bytes, sizeof(bytes)) : 0;
}
}  // namespace

Session::Session(Kind kind)
    : kind_(kind),
      store_(kind)
#if CROSSMUX_TOX_CHAT
      ,
      tox_(*this)
#endif
{
  mutex_ = xSemaphoreCreateMutexStatic(&mutexStorage_);
}
Session::~Session() { stop(); }
bool Session::start() {
  if (task_ || !mutex_) return false;
  stop_.store(false);
  done_.store(false);
  // Tox's nested crypto path needs 16 KiB. RF left 13,124 bytes unused on the
  // 16 KiB bench stack; 8 KiB keeps headroom while returning 8 KiB internal RAM
  // to foreground network activities when both listeners are enabled.
  const uint32_t stackBytes = kind_ == Kind::Wifi ? 16384 : 8192;
  if (xTaskCreate(trampoline, "Chat", stackBytes, this, 1, &task_) != pdPASS) {
    task_ = nullptr;
    LOG_ERR("CHAT", "OOM: %u-byte worker stack", static_cast<unsigned>(stackBytes));
    return false;
  }
  return true;
}
void Session::stop() {
  if (!task_) return;
  stop_.store(true);
  while (!done_.load()) vTaskDelay(pdMS_TO_TICKS(10));
  // Worker has released all protocol/file owners and suspended itself. Delete
  // the task before freeing the activity/session storage it used to reference.
  vTaskDelete(task_);
  task_ = nullptr;
}
bool Session::copySnapshot(Snapshot& out) {
  if (xSemaphoreTake(mutex_, pdMS_TO_TICKS(20)) != pdTRUE) return false;
  out = state;
  xSemaphoreGive(mutex_);
  return true;
}
bool Session::enqueue(Action action, const char* peer, const char* text, uint32_t id) {
  if (!active() || std::strlen(peer) > MAX_ID || std::strlen(text) > MAX_TEXT) return false;
  if (xSemaphoreTake(mutex_, pdMS_TO_TICKS(20)) != pdTRUE) return false;
  const bool espBusy =
#if CROSSMUX_ESP_CHAT
      kind_ == Kind::EspNow && esp_ && esp_->busy() && (action == Action::Send || action == Action::Retry);
#else
      false;
#endif
  const bool available = !espBusy && command_.action == Action::None &&
                         !(kind_ == Kind::Radio && pending_ && (action == Action::Send || action == Action::Retry));
  if (available) {
    command_.action = action;
    command_.id = id;
    std::strcpy(command_.peer, peer);
    std::strcpy(command_.text, text);
    if (action == Action::Add) {
      state.addResult = AddResult::Pending;
      ++state.revision;
    }
  }
  xSemaphoreGive(mutex_);
  return available;
}
bool Session::send(const char* peer, const char* text) {
  return validText(reinterpret_cast<const uint8_t*>(text), std::strlen(text)) && enqueue(Action::Send, peer, text);
}
bool Session::retry(const char* peer, uint32_t id) { return enqueue(Action::Retry, peer, "", id); }
bool Session::add(const char* id) { return enqueue(Action::Add, id, ""); }
bool Session::discover() { return enqueue(Action::Discover, "", ""); }
void Session::viewing(const char* peer) {
  // Clear immediately even if a busy storage checkpoint delays the peer copy:
  // closing a view must never suppress later background notifications.
  viewActive_.store(false);
  if (std::strlen(peer) > MAX_ID || xSemaphoreTake(mutex_, pdMS_TO_TICKS(20)) != pdTRUE) return;
  std::strcpy(viewedPeer_, peer);
  viewActive_.store(*peer != 0);
  if (*peer) systemMessages::read(noticeSource(kind_), peer);
  xSemaphoreGive(mutex_);
}
void Session::status(Status value) {
  if (state.status == value) return;
  state.status = value;
  ++state.revision;
}
void Session::contact(const char* peer, bool online, bool request) {
  if (std::strlen(peer) > MAX_ID) return;
  for (size_t i = 0; i < state.contactCount; ++i) {
    auto& entry = state.contacts[i];
    if (std::strcmp(entry.id, peer)) continue;
    if (entry.online != online || entry.request != request) {
      if (request && !entry.request)
        systemMessages::post(systemMessages::Source::Wifi, peer, "", systemMessages::NoticeKind::FriendRequest);
      entry.online = online;
      entry.request = request;
      ++state.revision;
    }
    return;
  }
  if (state.contactCount == MAX_CONTACTS) return;
  auto& entry = state.contacts[state.contactCount++];
  std::strcpy(entry.id, peer);
  entry.online = online;
  entry.request = request;
  if (request) systemMessages::post(systemMessages::Source::Wifi, peer, "", systemMessages::NoticeKind::FriendRequest);
  ++state.revision;
}
bool Session::record(const Message& message) {
  Store::apply(state, message);
  if (!store_.append(message)) {
    status(Status::StorageError);
    LOG_ERR("CHAT", "Message checkpoint failed");
    return false;
  }
  return true;
}
bool Session::received(const char* peer, const uint8_t* text, size_t length, uint32_t id, const char* sender) {
  if (!validText(text, length) || std::strlen(peer) > MAX_ID || std::strlen(sender) > 12) return false;
  Message message;
  std::strcpy(message.peer, peer);
  std::memcpy(message.text, text, length);
  message.id = id;
  std::strcpy(message.sender, sender);
  // ESP ACKs promise a persisted message. A failed write must not enter the
  // visible history or duplicate ring, since the sender will retry it.
  bool stored = false;
  if (kind_ == Kind::EspNow) {
    if (!store_.append(message)) {
      status(Status::StorageError);
      return false;
    }
    Store::apply(state, message);
    stored = true;
  } else {
    stored = record(message);
  }
  if (!viewActive_.load() || std::strcmp(viewedPeer_, peer)) {
    systemMessages::post(noticeSource(kind_), peer, message.text);
  }
  return stored;
}
void Session::receipt(const char* peer, uint32_t id, uint8_t count) {
  for (size_t i = 0; i < state.messageCount; ++i) {
    auto& message = state.messages[i];
    if (message.id != id || message.delivery == Delivery::Received || std::strcmp(message.peer, peer)) continue;
    message.receipts = count;
    ++state.revision;
    if (!store_.append(message)) status(Status::StorageError);
    return;
  }
}
void Session::delivery(const char* peer, uint32_t id, Delivery value) {
  for (size_t i = 0; i < state.messageCount; ++i) {
    auto& message = state.messages[i];
    if (message.id != id || message.delivery == Delivery::Received || std::strcmp(message.peer, peer)) continue;
    message.delivery = value;
    ++state.revision;
    if (!store_.append(message)) status(Status::StorageError);
    return;
  }
}
void Session::delivered(const char* peer, uint32_t id) { delivery(peer, id, Delivery::Delivered); }
void Session::trampoline(void* ptr) { static_cast<Session*>(ptr)->run(); }
void Session::run() {
  {
    // Radio SPI and protocol timers work at the normal idle CPU clock too.
    // Do not hold HalPowerManager's single-owner lock across render tasks.
    xSemaphoreTake(mutex_, portMAX_DELAY);
    status(Status::Starting);
    bool ready = store_.load(state);
    if (!ready) status(Status::StorageError);
    for (size_t i = 0; i < state.messageCount; ++i) {
      if (state.messages[i].id >= nextId_) nextId_ = state.messages[i].id + 1;
    }
    if (!nextId_) nextId_ = 1;
    if (ready) {
      switch (kind_) {
        case Kind::Radio:
          radioId_ = HalRadio::deviceId();
          radioSession_ = HalRadio::randomNumber();
          nextId_ = HalRadio::randomNumber() | 1u;
          radioName(radioId_, state.identity);
          for (size_t i = 0; i < state.messageCount; ++i) {
            if (std::strlen(state.messages[i].peer) == 16) contact(state.messages[i].peer, false);
          }
          ready = radio_.begin();
          status(ready ? Status::Online : Status::Failed);
          helloPending_ = ready;
          helloAt_ = millis() + (HalRadio::randomNumber() % 1000);
          break;
        case Kind::Wifi:
#if CROSSMUX_TOX_CHAT
          ready = tox_.begin();
#else
          ready = false;
#endif
          status(ready ? Status::Connecting : Status::Failed);
          break;
        case Kind::EspNow:
#if CROSSMUX_ESP_CHAT
          // Bounded RX/ACK/duplicate storage (~5 KiB) is too large for the worker
          // stack, and belongs only to an active ESP session, not RF/Tox/readers.
          esp_ = makeUniqueNoThrow<EspNowBackend>(*this);
          if (!esp_) LOG_ERR("CHAT", "OOM: ESP backend %u bytes", static_cast<unsigned>(sizeof(EspNowBackend)));
          ready = esp_ && esp_->begin();
#else
          ready = false;
#endif
          status(ready ? Status::Online : Status::Failed);
          break;
      }
    }
    const auto internal = HalMemory::getInternalHeap();
    const auto psram = HalMemory::getPsramHeap();
    LOG_INF("CHAT", "Ready=%d kind=%u session=%u internal free/largest=%u/%u PSRAM free/largest=%u/%u", ready,
            static_cast<unsigned>(kind_), static_cast<unsigned>(sizeof(Session)),
            static_cast<unsigned>(internal.freeBytes), static_cast<unsigned>(internal.largestBlockBytes),
            static_cast<unsigned>(psram.freeBytes), static_cast<unsigned>(psram.largestBlockBytes));
    xSemaphoreGive(mutex_);
    while (!stop_.load() && ready) {
      xSemaphoreTake(mutex_, portMAX_DELAY);
      const uint32_t now = millis();
      processCommand(now);
      switch (kind_) {
        case Kind::Radio:
          radioTick(now);
          break;
        case Kind::Wifi:
#if CROSSMUX_TOX_CHAT
          tox_.tick(now);
#endif
          break;
        case Kind::EspNow:
#if CROSSMUX_ESP_CHAT
          esp_->tick(now);
#endif
          break;
      }
      xSemaphoreGive(mutex_);
      vTaskDelay(pdMS_TO_TICKS(10));
    }
    xSemaphoreTake(mutex_, portMAX_DELAY);
    if (kind_ == Kind::Radio) {
      radioLeave();
      radio_.end();
    }
#if CROSSMUX_TOX_CHAT
    if (kind_ == Kind::Wifi) tox_.stop();
#endif
#if CROSSMUX_ESP_CHAT
    if (esp_) {
      esp_->stop();
      esp_.reset();
    }
#endif
    if (command_.action == Action::Send) {
      Message unsent;
      std::strcpy(unsent.peer, command_.peer);
      std::strcpy(unsent.text, command_.text);
      unsent.id = nextId_++;
      unsent.delivery = Delivery::Failed;
      if (kind_ == Kind::EspNow) std::snprintf(unsent.sender, sizeof(unsent.sender), "%.12s", state.identity);
      record(unsent);
      command_ = {};
    }
    for (size_t i = 0; i < state.messageCount; ++i) {
      auto& message = state.messages[i];
      if (message.delivery == Delivery::Pending) {
        message.delivery = Delivery::Failed;
        if (!store_.append(message)) status(Status::StorageError);
      }
    }
    LOG_INF("CHAT", "Worker stopped kind=%u, stack remaining=%u", static_cast<unsigned>(kind_),
            static_cast<unsigned>(uxTaskGetStackHighWaterMark(nullptr)));
    xSemaphoreGive(mutex_);
  }
  done_.store(true);
  vTaskSuspend(nullptr);
}
bool Session::transmit(const radio::Packet& packet) {
  const size_t length = radio::encode(packet, wire_, sizeof(wire_));
  return length && radio_.send(wire_, length);
}
void Session::processCommand(uint32_t now) {
  if (kind_ == Kind::Radio && (command_.action == Action::Send || command_.action == Action::Retry) &&
      (radio_.busy() || pending_))
    return;
  switch (command_.action) {
    case Action::None:
      return;
    case Action::Discover:
      switch (kind_) {
        case Kind::Radio:
          helloPending_ = true;
          helloAt_ = now;
          break;
        case Kind::Wifi:
#if CROSSMUX_TOX_CHAT
          if (!tox_.discover(now)) status(Status::Failed);
#endif
          break;
        case Kind::EspNow:
#if CROSSMUX_ESP_CHAT
          if (esp_) esp_->discover();
#endif
          break;
      }
      break;
    case Action::Add:
#if CROSSMUX_ESP_CHAT
      if (kind_ == Kind::EspNow && esp_) {
        state.addResult = esp_->join(command_.peer);
        ++state.revision;
      }
#endif
#if CROSSMUX_TOX_CHAT
      if (kind_ == Kind::Wifi) {
        state.addResult = tox_.add(command_.peer);
        ++state.revision;
      }
#endif
      break;
    case Action::Retry:
    case Action::Send: {
      Message message;
      const bool retrying = command_.action == Action::Retry;
      if (retrying) {
        bool found = false;
        for (size_t i = 0; i < state.messageCount; ++i) {
          const auto& previous = state.messages[i];
          if (previous.id == command_.id && previous.delivery == Delivery::Failed &&
              std::strcmp(previous.peer, command_.peer) == 0) {
            std::strcpy(command_.text, previous.text);
            found = true;
            break;
          }
        }
        if (!found) {
          command_ = {};
          return;
        }
      }
      std::strcpy(message.peer, command_.peer);
      std::strcpy(message.text, command_.text);
      message.delivery = Delivery::Failed;
      switch (kind_) {
        case Kind::Radio: {
          const bool broadcast = std::strcmp(command_.peer, "*") == 0;
          const uint64_t address = broadcast ? 0 : radioAddress(command_.peer);
          message.id = retrying ? command_.id : nextId_++;
          if ((!broadcast && (!address || !presence_.online(address, now))) || !message.id) break;
          pendingPacket_ = {};
          pendingPacket_.type = radio::Type::Text;
          pendingPacket_.sender = radioId_;
          pendingPacket_.recipient = address;
          pendingPacket_.session = radioSession_;
          pendingPacket_.sequence = message.id;
          std::strcpy(pendingPacket_.text, command_.text);
          if (!transmit(pendingPacket_)) break;
          message.delivery = Delivery::Pending;
          pending_ = !broadcast;
          publicId_ = broadcast ? message.id : 0;
          attempts_ = 1;
          retryAt_ = now + 4000 + (HalRadio::randomNumber() % 1000);
          break;
        }
        case Kind::Wifi:
          message.id = retrying ? command_.id : nextId_++;
#if CROSSMUX_TOX_CHAT
          if (tox_.send(command_.peer, command_.text, message.id)) message.delivery = Delivery::Pending;
#endif
          break;
        case Kind::EspNow:
          message.id = retrying ? command_.id : nextId_++;
#if CROSSMUX_ESP_CHAT
          std::snprintf(message.sender, sizeof(message.sender), "%.12s", state.identity);
          if (esp_ && esp_->send(command_.peer, command_.text, message.id)) message.delivery = Delivery::Pending;
#endif
          break;
      }
      record(message);
      break;
    }
  }
  command_ = {};
}
void Session::radioTick(uint32_t now) {
  size_t length = 0;
  int16_t rssi = 0;
  const auto result = radio_.poll(wire_, sizeof(wire_), length, rssi);
  switch (result) {
    case HalRadio::Result::Idle:
      break;
    case HalRadio::Result::Sent:
    case HalRadio::Result::Failed:
      if (publicId_) {
        delivery("*", publicId_, result == HalRadio::Result::Sent ? Delivery::Sent : Delivery::Failed);
        publicId_ = 0;
      }
      break;
    case HalRadio::Result::Received:
      if (radio::decode(wire_, length, rxPacket_) && rxPacket_.sender != radioId_ &&
          (!rxPacket_.recipient || rxPacket_.recipient == radioId_)) {
        char peer[17];
        radioName(rxPacket_.sender, peer);
        const auto countBefore = state.contactCount;
        if (rxPacket_.type == radio::Type::Bye)
          presence_.leave(rxPacket_.sender);
        else
          presence_.seen(rxPacket_.sender, now);
        contact(peer, presence_.online(rxPacket_.sender, now));
        state.radioRssi = rssi;
        switch (rxPacket_.type) {
          case radio::Type::Bye:
            if (pending_ && pendingPacket_.recipient == rxPacket_.sender) {
              delivery(peer, pendingPacket_.sequence, Delivery::Failed);
              pending_ = false;
            }
            break;
          case radio::Type::Hello:
            if (state.contactCount != countBefore) {
              helloPending_ = true;
              helloAt_ = now + 300 + (HalRadio::randomNumber() % 700);
            }
            break;
          case radio::Type::Text:
            if (!duplicates_.contains(rxPacket_)) {
              received(rxPacket_.recipient ? peer : "*", reinterpret_cast<uint8_t*>(rxPacket_.text),
                       std::strlen(rxPacket_.text), rxPacket_.sequence);
              duplicates_.remember(rxPacket_);
            }
            // Re-ACK duplicates: the previous ACK may be the packet that was lost.
            if (rxPacket_.recipient) {
              ackPacket_ = {};
              ackPacket_.type = radio::Type::Ack;
              ackPacket_.sender = radioId_;
              ackPacket_.recipient = rxPacket_.sender;
              ackPacket_.session = rxPacket_.session;
              ackPacket_.sequence = rxPacket_.sequence;
              ackPending_ = true;
            }
            break;
          case radio::Type::Ack:
            if (pending_ && rxPacket_.recipient == radioId_ && rxPacket_.sender == pendingPacket_.recipient &&
                rxPacket_.session == radioSession_ && rxPacket_.sequence == pendingPacket_.sequence) {
              delivered(peer, pendingPacket_.sequence);
              pending_ = false;
            }
            break;
        }
      }
      break;
  }
  for (size_t i = 0; i < state.contactCount; ++i) {
    auto& entry = state.contacts[i];
    const bool online = presence_.online(radioAddress(entry.id), now);
    if (entry.online != online) {
      entry.online = online;
      ++state.revision;
    }
  }
  if (radio_.busy()) return;
  if (ackPending_) {
    ackPending_ = !transmit(ackPacket_);
    return;
  }
  if (pending_ && static_cast<int32_t>(now - retryAt_) >= 0) {
    if (attempts_ >= 3) {
      char peer[17];
      radioName(pendingPacket_.recipient, peer);
      delivery(peer, pendingPacket_.sequence, Delivery::Failed);
      presence_.leave(pendingPacket_.recipient);
      contact(peer, false);
      pending_ = false;
    } else {
      ++attempts_;
      transmit(pendingPacket_);
      retryAt_ = now + 4000 + (HalRadio::randomNumber() % 1000);
    }
    return;
  }
  if (helloPending_ && static_cast<int32_t>(now - helloAt_) >= 0) {
    rxPacket_ = {};
    rxPacket_.sender = radioId_;
    rxPacket_.session = radioSession_;
    rxPacket_.sequence = nextId_++;
    const bool sent = transmit(rxPacket_);
    helloPending_ = true;
    helloAt_ = now + (sent ? radio::Presence::HEARTBEAT_MS : 5000) + HalRadio::randomNumber() % 1000;
  }
}
void Session::radioLeave() {
  // Give an in-flight frame a bounded chance to complete, then announce exit.
  auto finish = [this]() {
    const uint32_t start = millis();
    while (radio_.busy() && millis() - start < 800) {
      size_t length = 0;
      int16_t rssi = 0;
      radio_.poll(wire_, sizeof(wire_), length, rssi);
      vTaskDelay(pdMS_TO_TICKS(10));
    }
  };
  finish();
  if (state.status == Status::Online && !radio_.busy()) {
    rxPacket_ = {};
    rxPacket_.type = radio::Type::Bye;
    rxPacket_.sender = radioId_;
    rxPacket_.session = radioSession_;
    rxPacket_.sequence = nextId_++;
    if (transmit(rxPacket_)) finish();
  }
}
}  // namespace chat
#endif
