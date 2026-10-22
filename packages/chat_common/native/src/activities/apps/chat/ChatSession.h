#pragma once

#include "ChatBuildConfig.h"
#if CROSSMUX_CHAT
#include <HalRadio.h>
#include <freertos/FreeRTOS.h>
#include <freertos/semphr.h>
#include <freertos/task.h>

#include <atomic>
#include <memory>

#include "ChatModel.h"
#include "ChatStore.h"
#include "RadioChatProtocol.h"
#include "RadioPresence.h"
#include "ToxBackend.h"

namespace chat {
class EspNowBackend;
class Session {
 public:
  explicit Session(Kind kind);
  ~Session();
  bool start();
  void stop();
  bool copySnapshot(Snapshot& out);
  bool send(const char* peer, const char* text);
  bool add(const char* id);
  bool retry(const char* peer, uint32_t id);
  bool discover();
  void viewing(const char* peer);
  bool active() const { return task_ && !done_.load(); }

  // Worker-only callbacks; caller already owns mutex_.
  Snapshot state{};
  bool received(const char* peer, const uint8_t* text, size_t length, uint32_t id, const char* sender = "");
  void delivered(const char* peer, uint32_t id);
  void receipt(const char* peer, uint32_t id, uint8_t count);
  void updateDelivery(const char* peer, uint32_t id, Delivery value) { delivery(peer, id, value); }
  void contact(const char* peer, bool online, bool request = false);
  void status(Status value);

 private:
  enum class Action : uint8_t { None, Send, Retry, Add, Discover };
  struct Command {
    Action action = Action::None;
    uint32_t id = 0;
    char peer[MAX_ID + 1]{};
    char text[MAX_TEXT + 1]{};
  } command_;
  std::atomic<bool> viewActive_{false};
  char viewedPeer_[MAX_ID + 1]{};
  Kind kind_;
  Store store_;
  StaticSemaphore_t mutexStorage_{};
  SemaphoreHandle_t mutex_ = nullptr;
  TaskHandle_t task_ = nullptr;
  std::atomic<bool> stop_{false};
  std::atomic<bool> done_{false};
  HalRadio radio_;
  radio::DuplicateWindow duplicates_;
  radio::Presence presence_;
  radio::Packet rxPacket_{};
  radio::Packet pendingPacket_{};
  radio::Packet ackPacket_{};
  uint8_t wire_[radio::MAX_FRAME]{};
  uint64_t radioId_ = 0;
  uint32_t radioSession_ = 0;
  uint32_t nextId_ = 1;
  uint32_t retryAt_ = 0;
  uint8_t attempts_ = 0;
  bool pending_ = false;
  bool ackPending_ = false;
  bool helloPending_ = false;
  uint32_t helloAt_ = 0;
  uint32_t publicId_ = 0;
#if CROSSMUX_TOX_CHAT
  ToxBackend tox_;
#endif
#if CROSSMUX_ESP_CHAT
  std::unique_ptr<EspNowBackend> esp_;
#endif
  static void trampoline(void* ptr);
  void run();
  void radioTick(uint32_t now);
  void radioLeave();
  bool transmit(const radio::Packet& packet);
  bool enqueue(Action action, const char* peer, const char* text, uint32_t id = 0);
  void processCommand(uint32_t now);
  bool record(const Message& message);
  void delivery(const char* peer, uint32_t id, Delivery value);
};
}  // namespace chat
#endif
