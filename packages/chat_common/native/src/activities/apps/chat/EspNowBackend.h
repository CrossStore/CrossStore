#pragma once
#include "ChatBuildConfig.h"
#if CROSSMUX_ESP_CHAT
#include <HalEspNow.h>

#include "EspChatProtocol.h"
#include "RadioPresence.h"

namespace chat {
class Session;
class EspNowBackend {
 public:
  explicit EspNowBackend(Session& session) : session_(session) {}
  ~EspNowBackend() { stop(); }
  bool begin();
  void stop();
  void tick(uint32_t now);
  bool send(const char* room, const char* text, uint32_t id);
  bool busy() const { return pending_; }
  AddResult join(const char* group);
  void discover() { helloAt_ = 0; }

 private:
  enum class Flight : uint8_t { None, Text, Ack, Hello };
  Session& session_;
  HalEspNow transport_;
  HalEspNow::Frame frame_{};
  espchat::Packet rx_{}, tx_{}, scratch_{};
  uint8_t wire_[espchat::MAX_FRAME]{};
  struct Ack {
    uint64_t recipient = 0;
    uint32_t room = 0, session = 0, sequence = 0, due = 0;
  } acks_[8]{};
  radio::DuplicateWindow duplicates_;
  radio::Presence presence_;
  espchat::ReceiptSet receipts_;
  uint32_t groups_[MAX_CONTACTS]{};
  uint8_t groupCount_ = 0;
  uint64_t identity_ = 0;
  uint32_t boot_ = 0, beacon_ = 1, helloAt_ = 0, retryAt_ = 0, flightAt_ = 0, restartAt_ = 0;
  uint8_t attempts_ = 0;
  bool pending_ = false, sent_ = false, started_ = false;
  Flight flight_ = Flight::None;
  bool member(uint32_t group) const;
  bool loadGroups();
  void receive(uint32_t now);
  void queueAck(uint32_t now);
  bool transmit(const espchat::Packet& packet, Flight flight, uint32_t now);
  void finish();
};
}  // namespace chat
#endif
