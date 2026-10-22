#pragma once

#include <algorithm>
#include <iterator>

#include "ChatModel.h"

namespace chat::radio {
// Listener presence only: exit beacons are best-effort; missing heartbeats
// expire even after abrupt power loss. Unsigned elapsed time handles millis wrap.
class Presence {
 public:
  static constexpr uint32_t HEARTBEAT_MS = 15000;
  static constexpr uint32_t TIMEOUT_MS = 45000;
  void seen(uint64_t id, uint32_t now) {
    if (!id) return;
    auto* entry = std::find_if(std::begin(entries_), std::end(entries_), [id](const Entry& e) { return e.id == id; });
    if (entry == std::end(entries_))
      entry = std::find_if(std::begin(entries_), std::end(entries_), [](const Entry& e) { return e.id == 0; });
    if (entry != std::end(entries_)) *entry = {id, now, true};
  }
  void leave(uint64_t id) {
    auto* entry = std::find_if(std::begin(entries_), std::end(entries_), [id](const Entry& e) { return e.id == id; });
    if (entry != std::end(entries_)) entry->online = false;
  }
  bool online(uint64_t id, uint32_t now) const {
    const auto* entry =
        std::find_if(std::begin(entries_), std::end(entries_), [id](const Entry& e) { return e.id == id; });
    return entry != std::end(entries_) && entry->online && now - entry->at < TIMEOUT_MS;
  }
  unsigned countOnline(uint32_t now) const {
    return std::count_if(std::begin(entries_), std::end(entries_),
                         [now](const Entry& e) { return e.id && e.online && now - e.at < TIMEOUT_MS; });
  }

 private:
  struct Entry {
    uint64_t id = 0;
    uint32_t at = 0;
    bool online = false;
  } entries_[MAX_CONTACTS]{};
};
}  // namespace chat::radio
