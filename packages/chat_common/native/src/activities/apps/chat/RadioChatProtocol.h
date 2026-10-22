#pragma once

#include "ChatModel.h"

namespace chat::radio {
// Public, single-hop short messages. No encryption/authentication is claimed.
// Versioned bytes, not packed C structs; safe on every MCU alignment.
enum class Type : uint8_t { Hello = 1, Text = 2, Ack = 3, Bye = 4 };
constexpr size_t HEADER = 28;
constexpr size_t MAX_FRAME = HEADER + MAX_TEXT;
struct Packet {
  Type type = Type::Hello;
  uint64_t sender = 0;
  uint64_t recipient = 0;  // zero = public room
  uint32_t session = 0;
  uint32_t sequence = 0;
  char text[MAX_TEXT + 1]{};
};
inline void put(uint8_t* out, uint64_t value, size_t bytes) {
  for (size_t i = 0; i < bytes; ++i) out[i] = static_cast<uint8_t>(value >> (8 * i));
}
inline uint64_t get(const uint8_t* in, size_t bytes) {
  uint64_t value = 0;
  for (size_t i = 0; i < bytes; ++i) value |= uint64_t{in[i]} << (8 * i);
  return value;
}
inline size_t encode(const Packet& packet, uint8_t* out, size_t capacity) {
  const size_t length = strnlen(packet.text, sizeof(packet.text));
  if (!out || !packet.sender || !packet.sequence || capacity < HEADER + length) return 0;
  if (static_cast<uint8_t>(packet.type) < 1 || static_cast<uint8_t>(packet.type) > 4) return 0;
  switch (packet.type) {
    case Type::Text:
      if (!validText(reinterpret_cast<const uint8_t*>(packet.text), length)) return 0;
      break;
    case Type::Hello:
    case Type::Ack:
    case Type::Bye:
      if (length) return 0;
      break;
  }
  out[0] = 'C';
  out[1] = 'R';
  out[2] = 1;
  out[3] = static_cast<uint8_t>(packet.type);
  put(out + 4, packet.sender, 8);
  put(out + 12, packet.recipient, 8);
  put(out + 20, packet.session, 4);
  put(out + 24, packet.sequence, 4);
  std::memcpy(out + HEADER, packet.text, length);
  return HEADER + length;
}
inline bool decode(const uint8_t* input, size_t length, Packet& packet) {
  if (!input || length < HEADER || length > MAX_FRAME || input[0] != 'C' || input[1] != 'R' || input[2] != 1)
    return false;
  if (input[3] < 1 || input[3] > 4) return false;
  const Type type = static_cast<Type>(input[3]);
  const size_t textLength = length - HEADER;
  if (type == Type::Text ? !validText(input + HEADER, textLength) : textLength != 0) return false;
  if (!get(input + 4, 8) || !get(input + 24, 4)) return false;
  packet = {};
  packet.type = type;
  packet.sender = get(input + 4, 8);
  packet.recipient = get(input + 12, 8);
  packet.session = static_cast<uint32_t>(get(input + 20, 4));
  packet.sequence = static_cast<uint32_t>(get(input + 24, 4));
  std::memcpy(packet.text, input + HEADER, textLength);
  return true;
}

class DuplicateWindow {
  struct Entry {
    uint64_t sender = 0;
    uint32_t session = 0;
    uint32_t sequence = 0;
  };
  Entry entries_[32]{};
  uint8_t next_ = 0;

 public:
  bool contains(const Packet& packet) const { return contains(packet.sender, packet.session, packet.sequence); }
  bool contains(uint64_t sender, uint32_t session, uint32_t sequence) const {
    // Keep the fixed wire-identity comparison next to its bounded ring storage.
    // cppcheck-suppress useStlAlgorithm
    for (const auto& e : entries_) {
      if (e.sender == sender && e.session == session && e.sequence == sequence) return true;
    }
    return false;
  }
  void remember(const Packet& packet) { remember(packet.sender, packet.session, packet.sequence); }
  void remember(uint64_t sender, uint32_t session, uint32_t sequence) {
    entries_[next_] = {sender, session, sequence};
    next_ = (next_ + 1) % 32;
  }
};
}  // namespace chat::radio
