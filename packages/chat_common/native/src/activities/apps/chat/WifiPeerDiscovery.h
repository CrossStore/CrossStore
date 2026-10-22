#pragma once

#include <cstddef>
#include <cstdint>
#include <cstring>

namespace chat::nearby {
constexpr size_t ADDRESS_BYTES = 38;
constexpr size_t KEY_BYTES = 32;
constexpr size_t CAPACITY = 8;
constexpr size_t FRAME_BYTES = 78;
constexpr uint16_t PORT = 33446;
constexpr uint32_t WINDOW_MS = 60000;
constexpr uint32_t EXPIRY_MS = 15000;

struct Packet {
  uint8_t address[ADDRESS_BYTES]{};
  uint8_t dht[KEY_BYTES]{};
  uint16_t port = 0;
};
inline bool validAddress(const uint8_t* address) {
  uint8_t checksum[2]{};
  bool hasKey = false;
  for (size_t i = 0; i < ADDRESS_BYTES - 2; ++i) {
    checksum[i % 2] ^= address[i];
    if (i < KEY_BYTES && address[i]) hasKey = true;
  }
  return hasKey && checksum[0] == address[36] && checksum[1] == address[37];
}
inline bool encode(const Packet& packet, uint8_t* out, size_t size) {
  if (size != FRAME_BYTES || !packet.port || !validAddress(packet.address)) return false;
  std::memcpy(out, "CMXP\1\1", 6);
  std::memcpy(out + 6, packet.address, ADDRESS_BYTES);
  std::memcpy(out + 44, packet.dht, KEY_BYTES);
  out[76] = static_cast<uint8_t>(packet.port >> 8);
  out[77] = static_cast<uint8_t>(packet.port);
  return true;
}
inline bool decode(const uint8_t* bytes, size_t size, Packet& out) {
  if (size != FRAME_BYTES || std::memcmp(bytes, "CMXP\1\1", 6)) return false;
  std::memcpy(out.address, bytes + 6, ADDRESS_BYTES);
  std::memcpy(out.dht, bytes + 44, KEY_BYTES);
  out.port = static_cast<uint16_t>((bytes[76] << 8) | bytes[77]);
  bool hasDht = false;
  for (const auto byte : out.dht) hasDht |= byte != 0;
  return out.port && hasDht && validAddress(out.address);
}
struct Peer {
  uint8_t address[ADDRESS_BYTES]{};
  uint32_t seenAt = 0;
};
struct Directory {
  Peer peers[CAPACITY]{};
  uint8_t count = 0;
  bool active = false;
  bool seen(const uint8_t* address, const uint8_t* self, uint32_t now) {
    if (!validAddress(address) || !std::memcmp(address, self, KEY_BYTES)) return false;
    for (size_t i = 0; i < count; ++i) {
      auto& peer = peers[i];
      if (std::memcmp(peer.address, address, KEY_BYTES)) continue;
      const bool changed = std::memcmp(peer.address, address, ADDRESS_BYTES) != 0;
      std::memcpy(peer.address, address, ADDRESS_BYTES);
      peer.seenAt = now;
      return changed;
    }
    if (count == CAPACITY) return false;
    auto& peer = peers[count++];
    std::memcpy(peer.address, address, ADDRESS_BYTES);
    peer.seenAt = now;
    return true;
  }
  bool expire(uint32_t now) {
    const uint8_t previous = count;
    size_t kept = 0;
    for (size_t i = 0; i < count; ++i) {
      if (now - peers[i].seenAt < EXPIRY_MS) peers[kept++] = peers[i];
    }
    count = static_cast<uint8_t>(kept);
    return count != previous;
  }
};
}  // namespace chat::nearby
