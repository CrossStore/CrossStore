#pragma once

#include "ChatBuildConfig.h"
#if CROSSMUX_CHAT
#include <cstdio>

#include "ChatSession.h"
#include "WifiIdentityQr.h"
#include "activities/UiListActivity.h"

class ChatActivity final : public UiListActivity {
 public:
  ChatActivity(GfxRenderer& renderer, MappedInputManager& input, chat::Kind kind, const char* peer = "",
               bool returnToParent = false)
      : UiListActivity("Chat", renderer, input), kind_(kind), returnToParent_(returnToParent) {
    std::snprintf(initialPeer_, sizeof(initialPeer_), "%s", peer);
  }
  void onEnter() override;
  void onExit() override;
  void prepareForSleep() override;
  void loop() override;

 private:
  enum class View : uint8_t { Home, Options, Thread, Detail, Identity, PeerInfo, Nearby, PairConfirm };
  enum class PairAction : uint8_t { Invite, Accept };
  enum class IdentityFormat : uint8_t { Qr, FullText };
  chat::Kind kind_;
  View view_ = View::Home;
  chat::Session* session_ = nullptr;  // service-owned; released before activity destruction
  char initialPeer_[chat::MAX_ID + 1]{};
  bool returnToParent_ = false;
  chat::Snapshot snapshot_{};
  char peer_[chat::MAX_ID + 1]{};
  char detail_[chat::MAX_TEXT + 1]{};
  // Fixed buffers avoid per-frame allocation; released with this activity.
  char draft_[chat::MAX_TEXT + 1]{};
  char peerTitle_[40]{};
  char myCode_[64]{};
  char pairId_[chat::MAX_ID + 1]{};
  char pairTitle_[40]{};
  PairAction pairAction_ = PairAction::Invite;
  IdentityFormat identityFormat_ = IdentityFormat::Qr;
  View identityReturn_ = View::Options;
  chat::WifiIdentityQr identityQr_;
  char contactTitles_[chat::MAX_CONTACTS][40]{};
  uint8_t olderOffset_ = 0;
  uint8_t pageMessages_ = 1;
  bool hasOlder_ = false;
  char lines_[12][chat::MAX_TEXT + 1]{};
  uint8_t lineCount_ = 0;
  uint8_t messageIndices_[chat::MAX_MESSAGES]{};
  uint8_t messageCount_ = 0;
  freeink::ui::ListItem rows_[chat::MAX_MESSAGES + 5]{};
  int rowCount_ = 0;
  freeink::ui::ButtonProps buttonProps_;
  uint32_t refreshedAt_ = 0;

  bool commandFailed_ = false;
  void connect();
  void startSession();
  void stopSession();
  void compose();
  void addContact();
  void makeLines(const char* text);
  void refreshRows();
  void buildThread(UiScreen& screen);
  void buildIdentity(UiScreen& screen);
  void openIdentity();
  void pageThread(bool older);
  bool peerOnline() const;
  void openContact(const char* peer);
  void openThread(const char* peer);
  static void peerTitle(const char* id, char* out, size_t size);
  bool handleButtons() override;
  void navigateButtons() override;
  bool handleListSwipe(MappedInputManager::SwipeDir swipe, int startX, int startY) override;
  void drawFooter() override;
  int listCount() const override { return rowCount_; }
  void buildScreen(UiScreen& screen) override;
  void activateIndex(int index) override;
  void onBackButton() override;
  const char* headerTitle() const override;
};
#endif
