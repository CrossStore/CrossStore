#include "EspNowBackend.h"
#if CROSSMUX_ESP_CHAT
#include <HalStorage.h>
#include <Logging.h>

#include <algorithm>
#include <cstdio>

#include "ChatSession.h"

namespace chat {
namespace {
constexpr char GROUPS[] = "/.crosspoint/esp_chat/groups-v1.txt";
constexpr char TEMP[] = "/.crosspoint/esp_chat/groups-v1.part";
bool due(uint32_t now, uint32_t deadline) { return static_cast<int32_t>(now - deadline) >= 0; }
}  // namespace
bool EspNowBackend::member(uint32_t group) const {
  return group == 0 || std::find(groups_, groups_ + groupCount_, group) != groups_ + groupCount_;
}
bool EspNowBackend::loadGroups() {
  if (!Storage.exists(GROUPS)) return true;
  auto file = Storage.open(GROUPS);
  if (!file || file.size() > MAX_CONTACTS * 7 || file.size() % 7) return false;
  while (file.available()) {
    char digits[8]{};
    if (file.read(reinterpret_cast<uint8_t*>(digits), 7) != 7 || digits[6] != '\n') return false;
    digits[6] = 0;
    const auto group = espchat::groupNumber(digits);
    if (!group || member(group)) return false;
    groups_[groupCount_++] = group;
  }
  return true;
}
bool EspNowBackend::begin() {
  identity_ = HalEspNow::deviceId();
  boot_ = HalEspNow::randomNumber() | 1u;
  if (!identity_ || !loadGroups()) return false;
  std::snprintf(session_.state.identity, sizeof(session_.state.identity), "%012llX",
                static_cast<unsigned long long>(identity_));
  for (uint8_t i = 0; i < groupCount_; ++i) {
    char name[8];
    espchat::roomName(groups_[i], name, sizeof(name));
    session_.contact(name, true);
  }
  started_ = transport_.begin();
  return started_;
}
AddResult EspNowBackend::join(const char* input) {
  const auto group = espchat::groupNumber(input);
  if (!group) return AddResult::InvalidId;
  if (member(group)) return AddResult::Existing;
  if (groupCount_ == MAX_CONTACTS) return AddResult::Limit;
  {
    auto file = Storage.open(TEMP, O_WRONLY | O_CREAT | O_TRUNC);
    if (!file) return AddResult::StorageError;
    for (unsigned i = 0; i <= groupCount_; ++i) {
      char line[8];
      std::snprintf(line, sizeof(line), "%06lu\n", static_cast<unsigned long>(i == groupCount_ ? group : groups_[i]));
      if (file.write(reinterpret_cast<const uint8_t*>(line), 7) != 7) return AddResult::StorageError;
    }
    file.flush();
  }
  if (!Storage.replaceFile(TEMP, GROUPS)) return AddResult::StorageError;
  groups_[groupCount_++] = group;
  char name[8];
  espchat::roomName(group, name, sizeof(name));
  session_.contact(name, true);
  return AddResult::Accepted;
}
bool EspNowBackend::send(const char* room, const char* text, uint32_t id) {
  if (pending_ || !espchat::validRoom(room) || !member(espchat::groupNumber(room)) || !HalEspNow::channel())
    return false;
  tx_ = {};
  tx_.type = espchat::Type::Text;
  tx_.room = espchat::groupNumber(room);
  tx_.sender = identity_;
  tx_.session = boot_;
  tx_.sequence = id;
  std::snprintf(tx_.text, sizeof(tx_.text), "%s", text);
  receipts_ = {};
  attempts_ = 0;
  sent_ = false;
  pending_ = true;
  retryAt_ = 0;
  return true;
}
bool EspNowBackend::transmit(const espchat::Packet& packet, Flight flight, uint32_t now) {
  const auto length = espchat::encode(packet, wire_, sizeof(wire_));
  if (!length || !transport_.send(wire_, length)) return false;
  flight_ = flight;
  flightAt_ = now;
  return true;
}
void EspNowBackend::queueAck(uint32_t now) {
  for (auto& ack : acks_) {
    if (ack.recipient == rx_.sender && ack.session == rx_.session && ack.sequence == rx_.sequence) return;
    if (!ack.recipient) {
      ack = {rx_.sender, rx_.room, rx_.session, rx_.sequence, now + 80 + HalEspNow::randomNumber() % 320};
      return;
    }
  }
}
void EspNowBackend::receive(uint32_t now) {
  // Bounded work per tick; callbacks never perform SD writes or acquire Session's mutex.
  for (unsigned i = 0; i < 4 && transport_.receive(frame_); ++i) {
    if (!espchat::decode(frame_.data, frame_.length, rx_) || rx_.sender != frame_.sender || rx_.sender == identity_)
      continue;
    if (rx_.type == espchat::Type::Bye)
      presence_.leave(rx_.sender);
    else
      presence_.seen(rx_.sender, now);
    session_.state.radioRssi = frame_.rssi;
    switch (rx_.type) {
      case espchat::Type::Hello:
      case espchat::Type::Bye:
        break;
      case espchat::Type::Text: {
        if (!member(rx_.room)) break;
        // Existing duplicate ring compares only these three bounded identity fields.
        if (!duplicates_.contains(rx_.sender, rx_.session, rx_.sequence)) {
          char room[8], sender[13];
          espchat::roomName(rx_.room, room, sizeof(room));
          std::snprintf(sender, sizeof(sender), "%012llX", static_cast<unsigned long long>(rx_.sender));
          if (!session_.received(room, reinterpret_cast<const uint8_t*>(rx_.text), std::strlen(rx_.text), rx_.sequence,
                                 sender))
            break;
          duplicates_.remember(rx_.sender, rx_.session, rx_.sequence);
        }
        queueAck(now);  // Lost receipts are retried even when the message was already stored.
        break;
      }
      case espchat::Type::Ack:
        if (pending_ && rx_.recipient == identity_ && rx_.session == boot_ && rx_.sequence == tx_.sequence &&
            rx_.room == tx_.room && receipts_.add(rx_.sender)) {
          char room[8];
          espchat::roomName(tx_.room, room, sizeof(room));
          session_.receipt(room, tx_.sequence, receipts_.count());
        }
        break;
    }
  }
}
void EspNowBackend::finish() {
  if (!pending_) return;
  char room[8];
  espchat::roomName(tx_.room, room, sizeof(room));
  const auto result =
      receipts_.count() ? Delivery::Delivered : (!tx_.room && sent_ ? Delivery::Sent : Delivery::Failed);
  session_.updateDelivery(room, tx_.sequence, result);
  pending_ = false;
}
void EspNowBackend::tick(uint32_t now) {
  const uint8_t channel = HalEspNow::channel();
  if (session_.state.channel != channel) {
    session_.state.channel = channel;
    ++session_.state.revision;
  }
  if (!channel) {
    if (started_) {
      transport_.end();
      started_ = false;
      flight_ = Flight::None;
      finish();
    }
    session_.status(Status::Connecting);
    return;
  }
  if (!started_) {
    if (!due(now, restartAt_)) return;
    started_ = transport_.begin();
    restartAt_ = now + 3000;
    if (!started_) {
      session_.status(Status::Connecting);
      return;
    }
  }
  session_.status(Status::Online);
  receive(now);
  unsigned nearby = 0;
  // Presence exposes a bounded count without registering public senders as joined rooms.
  nearby = presence_.countOnline(now);
  if (session_.state.nearbyCount != nearby) {
    session_.state.nearbyCount = nearby;
    ++session_.state.revision;
  }
  const auto result = transport_.takeTxResult();
  if (result == HalEspNow::TxResult::Pending) {
    if (now - flightAt_ > 2000) {
      transport_.end();
      started_ = false;
      flight_ = Flight::None;
      finish();
    }
    return;
  }
  if (result == HalEspNow::TxResult::Sent && flight_ == Flight::Text) sent_ = true;
  flight_ = Flight::None;
  for (auto& ack : acks_) {
    if (!ack.recipient || !due(now, ack.due)) continue;
    scratch_ = {};
    scratch_.type = espchat::Type::Ack;
    scratch_.sender = identity_;
    scratch_.room = ack.room;
    scratch_.recipient = ack.recipient;
    scratch_.session = ack.session;
    scratch_.sequence = ack.sequence;
    if (transmit(scratch_, Flight::Ack, now))
      ack = {};
    else
      ack.due = now + 200;
    return;
  }
  if (pending_ && due(now, retryAt_)) {
    if (attempts_ == (tx_.room ? 3 : 1)) {
      finish();
      return;
    }
    ++attempts_;
    transmit(tx_, Flight::Text, now);
    retryAt_ = now + 1400 + HalEspNow::randomNumber() % 400;
    return;
  }
  if (due(now, helloAt_)) {
    scratch_ = {};
    scratch_.sender = identity_;
    scratch_.session = boot_;
    scratch_.sequence = ++beacon_;
    transmit(scratch_, Flight::Hello, now);
    helloAt_ = now + 10000 + HalEspNow::randomNumber() % 1000;
  }
}
void EspNowBackend::stop() {
  finish();
  transport_.end();
  started_ = false;
}
}  // namespace chat
#endif
