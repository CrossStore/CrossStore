#pragma once

#include <cstddef>
#include <cstdint>
#include <cstring>

#include "WifiPeerDiscovery.h"

namespace chat {
enum class Kind : uint8_t { Radio, Wifi, EspNow };
enum class Status : uint8_t { Stopped, Starting, Online, Connecting, Failed, StorageError };
enum class Delivery : uint8_t { Received, Pending, Sent, Delivered, Failed };
// The worker's friend operation result is independent of network connectivity.
// Keep it until another friend operation so a later network tick cannot hide it.
enum class AddResult : uint8_t { None, Pending, Requested, Accepted, Existing, InvalidId, Limit, StorageError, Failed };
constexpr size_t MAX_TEXT = 192;
constexpr size_t MAX_CONTACTS = 8;
constexpr size_t MAX_MESSAGES = 24;
constexpr size_t MAX_ID = 76;

struct Contact {
  char id[MAX_ID + 1]{};
  bool online = false;
  bool request = false;
};
struct Message {
  char peer[MAX_ID + 1]{};
  char text[MAX_TEXT + 1]{};
  uint32_t id = 0;
  Delivery delivery = Delivery::Received;
  // ESP group identity/receipts; empty for the unchanged RF/Tox v1 logs.
  char sender[13]{};
  uint8_t receipts = 0;
};
struct Snapshot {
  char identity[MAX_ID + 1]{};
  Contact contacts[MAX_CONTACTS]{};
  Message messages[MAX_MESSAGES]{};
  uint8_t contactCount = 0;
  uint8_t messageCount = 0;
  Status status = Status::Stopped;
  AddResult addResult = AddResult::None;
  uint32_t revision = 0;
  int16_t radioRssi = 0;
  uint8_t channel = 0;
  uint8_t nearbyCount = 0;
  nearby::Directory nearby;
};

inline bool validText(const uint8_t* text, size_t length) {
  if (!text || length == 0 || length > MAX_TEXT) return false;
  // Validate complete UTF-8; reject controls, overlong encodings and surrogates.
  for (size_t i = 0; i < length;) {
    const uint8_t first = text[i++];
    if (first < 0x80) {
      if (first < 0x20 || first == 0x7f) return false;
      continue;
    }
    unsigned remaining = 0;
    uint32_t code = 0, minimum = 0;
    if (first >= 0xc2 && first <= 0xdf) {
      remaining = 1;
      code = first & 31;
      minimum = 0x80;
    } else if (first >= 0xe0 && first <= 0xef) {
      remaining = 2;
      code = first & 15;
      minimum = 0x800;
    } else if (first >= 0xf0 && first <= 0xf4) {
      remaining = 3;
      code = first & 7;
      minimum = 0x10000;
    } else {
      return false;
    }
    if (remaining > length - i) return false;
    while (remaining--) {
      const uint8_t next = text[i++];
      if ((next & 0xc0) != 0x80) return false;
      code = (code << 6) | (next & 63);
    }
    if (code < minimum || code > 0x10ffff || (code >= 0xd800 && code <= 0xdfff)) return false;
  }
  return true;
}

inline int hexDigit(char c) {
  if (c >= '0' && c <= '9') return c - '0';
  if (c >= 'a' && c <= 'f') return c - 'a' + 10;
  if (c >= 'A' && c <= 'F') return c - 'A' + 10;
  return -1;
}
inline bool unhex(const char* text, uint8_t* output, size_t bytes) {
  if (!text || std::strlen(text) != bytes * 2) return false;
  for (size_t i = 0; i < bytes; ++i) {
    const int hi = hexDigit(text[i * 2]), lo = hexDigit(text[i * 2 + 1]);
    if (hi < 0 || lo < 0) return false;
    output[i] = static_cast<uint8_t>((hi << 4) | lo);
  }
  return true;
}
inline void hex(const uint8_t* bytes, size_t length, char* output) {
  constexpr char DIGITS[] = "0123456789ABCDEF";
  for (size_t i = 0; i < length; ++i) {
    output[i * 2] = DIGITS[bytes[i] >> 4];
    output[i * 2 + 1] = DIGITS[bytes[i] & 15];
  }
  output[length * 2] = 0;
}
}  // namespace chat
