#pragma once

#include <qrcode.h>

#include <cstdio>

#include "ChatModel.h"

namespace chat {
struct WifiIdentityQr {
  // Version 5 / medium ECC fits the 80-byte tox: URI. Keep the 172-byte
  // module buffer in the activity; no allocation or encoding during render.
  static constexpr uint8_t VERSION = 5;
  static constexpr int QUIET_MODULES = 4;
  static constexpr size_t BUFFER_BYTES = ((VERSION * 4 + 17) * (VERSION * 4 + 17) + 7) / 8;
  uint8_t modules[BUFFER_BYTES]{};
  QRCode code{};
  bool ready = false;

  bool init(const char* id) {
    ready = false;
    uint8_t address[nearby::ADDRESS_BYTES];
    if (!unhex(id, address, sizeof(address)) || !nearby::validAddress(address)) return false;
    char payload[MAX_ID + 5];
    std::snprintf(payload, sizeof(payload), "tox:%s", id);
    ready = qrcode_getBufferSize(VERSION) <= sizeof(modules) &&
            qrcode_initText(&code, modules, VERSION, ECC_MEDIUM, payload) == 0;
    return ready;
  }
};
}  // namespace chat
