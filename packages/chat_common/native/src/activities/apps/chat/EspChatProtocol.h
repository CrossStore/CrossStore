#pragma once

#include <algorithm>
#include <cstdio>

#include "RadioChatProtocol.h"

namespace chat::espchat {
// CrossMux single-hop, plaintext ESP-NOW rooms. Group IDs are routing labels,
// not secrets. Keep every packet <=250 bytes for ESP-NOW v1/v2 interoperability.
enum class Type : uint8_t { Hello = 1, Text = 2, Ack = 3, Bye = 4 };
constexpr size_t HEADER = 32;
constexpr size_t MAX_FRAME = HEADER + MAX_TEXT;
constexpr uint32_t MAX_GROUP = 999999;
static_assert(MAX_FRAME <= 250);
struct Packet {
  Type type = Type::Hello;
  uint32_t room = 0;
  uint64_t sender = 0;
  uint32_t session = 0;
  uint32_t sequence = 0;
  uint64_t recipient = 0;  // ACK destination; text is broadcast.
  char text[MAX_TEXT + 1]{};
};
inline uint32_t groupNumber(const char* text) {
  if (!text || !*text) return 0;
  if (*text == 'G') ++text;
  const size_t length = std::strlen(text);
  if (!length || length > 6) return 0;
  uint32_t value = 0;
  for (size_t i = 0; i < length; ++i) {
    if (text[i] < '0' || text[i] > '9') return 0;
    value = value * 10 + static_cast<unsigned>(text[i] - '0');
  }
  return value;
}
inline void roomName(uint32_t room, char* out, size_t capacity) {
  if (room)
    std::snprintf(out, capacity, "G%06lu", static_cast<unsigned long>(room));
  else
    std::snprintf(out, capacity, "*");
}
inline bool validRoom(const char* text) {
  return text && (!std::strcmp(text, "*") || (std::strlen(text) == 7 && text[0] == 'G' && groupNumber(text)));
}
inline bool valid(const Packet& p, size_t length) {
  if (!p.sender || p.sender >> 48 || !p.session || !p.sequence || p.room > MAX_GROUP) return false;
  switch (p.type) {
    case Type::Text:
      return !p.recipient && validText(reinterpret_cast<const uint8_t*>(p.text), length);
    case Type::Ack:
      return !length && p.recipient && !(p.recipient >> 48);
    case Type::Hello:
    case Type::Bye:
      return !length && !p.recipient && !p.room;
  }
  return false;
}
inline size_t encode(const Packet& p, uint8_t* out, size_t capacity) {
  const auto length = strnlen(p.text, sizeof(p.text));
  if (!out || capacity < HEADER + length || !valid(p, length)) return 0;
  out[0] = 'C';
  out[1] = 'E';
  out[2] = 1;
  out[3] = static_cast<uint8_t>(p.type);
  radio::put(out + 4, p.room, 4);
  radio::put(out + 8, p.sender, 8);
  radio::put(out + 16, p.session, 4);
  radio::put(out + 20, p.sequence, 4);
  radio::put(out + 24, p.recipient, 8);
  std::memcpy(out + HEADER, p.text, length);
  return HEADER + length;
}
inline bool decode(const uint8_t* in, size_t length, Packet& p) {
  if (!in || length < HEADER || length > MAX_FRAME || in[0] != 'C' || in[1] != 'E' || in[2] != 1 || in[3] < 1 ||
      in[3] > 4)
    return false;
  p = {};
  p.type = static_cast<Type>(in[3]);
  p.room = radio::get(in + 4, 4);
  p.sender = radio::get(in + 8, 8);
  p.session = radio::get(in + 16, 4);
  p.sequence = radio::get(in + 20, 4);
  p.recipient = radio::get(in + 24, 8);
  std::memcpy(p.text, in + HEADER, length - HEADER);
  return valid(p, length - HEADER);
}
class ReceiptSet {
  uint64_t senders_[8]{};
  uint8_t count_ = 0;

 public:
  bool add(uint64_t sender) {
    if (!sender || count_ == 8) return false;
    if (std::find(senders_, senders_ + count_, sender) != senders_ + count_) return false;
    senders_[count_++] = sender;
    return true;
  }
  uint8_t count() const { return count_; }
};
}  // namespace chat::espchat
