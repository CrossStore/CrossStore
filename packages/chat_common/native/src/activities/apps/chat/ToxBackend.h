#pragma once

#include "ChatBuildConfig.h"
#if CROSSMUX_TOX_CHAT
#include <toxcore/mem.h>
#include <toxcore/tox.h>

#include "ChatModel.h"

namespace chat {
class Session;
class ToxBackend {
 public:
  explicit ToxBackend(Session& session);
  ~ToxBackend();
  bool begin();
  void tick(uint32_t now);
  AddResult add(const char* address);
  bool discover(uint32_t now);
  bool send(const char* peer, const char* text, uint32_t id);
  bool save();
  void stop();

 private:
  Session& session_;
  Tox* tox_ = nullptr;
  uint32_t lastBootstrap_ = 0;
  uint32_t lastIterate_ = 0;
  uint32_t lastAddedFriend_ = UINT32_MAX;
  bool dirty_ = false;
  size_t allocated_ = 0;
  Memory memory_{};
  int discoverySocket_ = -1;  // Native handle; keep Tox's Network type out of Arduino headers.
  uint32_t discoveryStarted_ = 0;
  uint32_t discoverySent_ = 0;
  void discoveryTick(uint32_t now);
  void stopDiscovery();
  struct Receipt {
    uint32_t peer = 0;
    uint32_t transportId = 0;
    uint32_t localId = 0;
    bool used = false;
  } receipts_[MAX_MESSAGES]{};
  static const Memory_Funcs memoryFunctions_;
  static void* allocate(void* self, uint32_t bytes);
  static void* reallocate(void* self, void* ptr, uint32_t bytes);
  static void release(void* self, void* ptr);
  void refreshContacts();
  bool peerKey(uint32_t number, char* out) const;
  void bootstrap();
};
}  // namespace chat
#endif
