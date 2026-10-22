#pragma once

#include "ChatModel.h"

namespace chat {
class Store {
 public:
  explicit Store(Kind kind) : kind_(kind) {}
  bool load(Snapshot& snapshot);
  bool append(const Message& message);
  static void apply(Snapshot& snapshot, const Message& message);

 private:
  Kind kind_;
  char line_[384]{};  // worker-owned scratch, never on the small MCU task stack
  const char* path() const;
  bool parse(Message& message);
};
}  // namespace chat
