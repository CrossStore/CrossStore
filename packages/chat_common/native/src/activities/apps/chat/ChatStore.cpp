#include "ChatStore.h"

#include <HalStorage.h>

#include <cstdio>
#include <cstdlib>

#include "EspChatProtocol.h"

namespace chat {
const char* Store::path() const {
  switch (kind_) {
    case Kind::Radio:
      return "/.crosspoint/rf_chat/messages-v1.txt";
    case Kind::Wifi:
      return "/.crosspoint/wifi_chat/messages-v1.txt";
    case Kind::EspNow:
      return "/.crosspoint/esp_chat/messages-v2.txt";
  }
  return "";
}
void Store::apply(Snapshot& snapshot, const Message& message) {
  for (size_t i = 0; i < snapshot.messageCount; ++i) {
    auto& previous = snapshot.messages[i];
    if (previous.id == message.id && std::strcmp(previous.peer, message.peer) == 0 &&
        previous.delivery != Delivery::Received && message.delivery != Delivery::Received) {
      previous = message;
      ++snapshot.revision;
      return;
    }
  }
  if (snapshot.messageCount == MAX_MESSAGES) {
    std::memmove(snapshot.messages, snapshot.messages + 1, (MAX_MESSAGES - 1) * sizeof(Message));
    --snapshot.messageCount;
  }
  snapshot.messages[snapshot.messageCount++] = message;
  ++snapshot.revision;
}
bool Store::parse(Message& message) {
  char* first = std::strchr(line_, '|');
  if (!first || static_cast<size_t>(first - line_) > MAX_ID) return false;
  *first++ = 0;
  const size_t peerLength = std::strlen(line_);
  if (kind_ == Kind::EspNow) {
    if (!espchat::validRoom(line_)) return false;
  } else if (std::strcmp(line_, "*") != 0) {
    if (peerLength != 16 && peerLength != 64) return false;
    for (size_t i = 0; i < peerLength; ++i)
      if (hexDigit(line_[i]) < 0) return false;
  }
  char* second = std::strchr(first, '|');
  if (!second) return false;
  *second++ = 0;
  char* third = std::strchr(second, '|');
  if (!third) return false;
  *third++ = 0;
  message = {};
  if (kind_ == Kind::EspNow) {
    char* sender = third;
    char* receipts = std::strchr(sender, '|');
    if (!receipts || receipts - sender != 12) return false;
    *receipts++ = 0;
    uint8_t mac[6];
    if (!unhex(sender, mac, sizeof(mac))) return false;
    third = std::strchr(receipts, '|');
    if (!third) return false;
    *third++ = 0;
    if (receipts[0] < '0' || receipts[0] > '8' || receipts[1]) return false;
    std::strcpy(message.sender, sender);
    message.receipts = receipts[0] - '0';
  }
  const size_t length = std::strlen(third);
  if (!validText(reinterpret_cast<const uint8_t*>(third), length)) return false;
  char* end = nullptr;
  const auto id = std::strtoul(first, &end, 16);
  if (!*first || *end || id > UINT32_MAX) return false;
  if (second[0] < '0' || second[0] > '4' || second[1]) return false;
  std::strcpy(message.peer, line_);
  std::memcpy(message.text, third, length);
  message.id = static_cast<uint32_t>(id);
  message.delivery = static_cast<Delivery>(second[0] - '0');
  // A previous boot cannot retain a live transport's pending receipt.
  if (message.delivery == Delivery::Pending) message.delivery = Delivery::Failed;
  return true;
}
bool Store::load(Snapshot& snapshot) {
  const char* directory = nullptr;
  switch (kind_) {
    case Kind::Radio:
      directory = "/.crosspoint/rf_chat";
      break;
    case Kind::Wifi:
      directory = "/.crosspoint/wifi_chat";
      break;
    case Kind::EspNow:
      directory = "/.crosspoint/esp_chat";
      break;
  }
  if (!Storage.ensureDirectoryExists(directory)) return false;
  if (!Storage.exists(path())) return true;
  auto file = Storage.open(path());
  if (!file || file.size() > 128 * 1024 + sizeof(line_)) return false;
  size_t position = 0;
  bool oversized = false;
  Message message;  // 280-byte bounded cold-path record; worker has at least an 8 KiB stack
  while (file.available()) {
    const int value = file.read();
    if (value < 0) return false;
    if (value == '\n') {
      line_[position] = 0;
      if (!oversized && parse(message)) apply(snapshot, message);
      position = 0;
      oversized = false;
    } else if (position + 1 < sizeof(line_)) {
      line_[position++] = static_cast<char>(value);
    } else {
      oversized = true;
    }
  }
  // A torn final line is ignored. append() inserts a newline first to keep
  // subsequent records separate after an interrupted write.
  return true;
}
bool Store::append(const Message& message) {
  const int length = kind_ == Kind::EspNow ? std::snprintf(line_, sizeof(line_), "\n%s|%08lX|%u|%s|%u|%s\n",
                                                           message.peer, static_cast<unsigned long>(message.id),
                                                           static_cast<unsigned>(message.delivery), message.sender,
                                                           static_cast<unsigned>(message.receipts), message.text)
                                           : std::snprintf(line_, sizeof(line_), "\n%s|%08lX|%u|%s\n", message.peer,
                                                           static_cast<unsigned long>(message.id),
                                                           static_cast<unsigned>(message.delivery), message.text);
  if (length <= 0 || static_cast<size_t>(length) >= sizeof(line_)) return false;
  {
    auto file = Storage.open(path());
    if (file && file.size() >= 128 * 1024) {
      // Closed by scope before rename below.
    } else {
      auto output = Storage.open(path(), O_WRONLY | O_CREAT | O_APPEND);
      if (!output) return false;
      const bool ok = output.write(reinterpret_cast<const uint8_t*>(line_), length) == static_cast<size_t>(length);
      output.flush();
      return ok;
    }
  }
  const char* archive = nullptr;
  switch (kind_) {
    case Kind::Radio:
      archive = "/.crosspoint/rf_chat/messages-v1.previous.txt";
      break;
    case Kind::Wifi:
      archive = "/.crosspoint/wifi_chat/messages-v1.previous.txt";
      break;
    case Kind::EspNow:
      archive = "/.crosspoint/esp_chat/messages-v2.previous.txt";
      break;
  }
  if (Storage.exists(archive) && !Storage.remove(archive)) return false;
  if (!Storage.rename(path(), archive)) return false;
  auto output = Storage.open(path(), O_WRONLY | O_CREAT | O_APPEND);
  if (!output) return false;
  const bool ok = output.write(reinterpret_cast<const uint8_t*>(line_), length) == static_cast<size_t>(length);
  output.flush();
  return ok;
}
}  // namespace chat
