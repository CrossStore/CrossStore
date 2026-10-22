#pragma once
#include "ChatBuildConfig.h"
#if CROSSMUX_CHAT
#include "ChatModel.h"
namespace chat {
class Session;
// Only the main/activity task mutates ownership. Workers own their sessions'
// transport and storage; foreground views borrow a session until release().
namespace service {
Session* acquire(Kind kind);
void release(Kind kind);
bool background(Kind kind);
bool setBackground(Kind kind, bool enabled);
void ownWifi();
void tick(bool allowWifiJoin);
void stopForSleep();
}  // namespace service
}  // namespace chat
#endif
