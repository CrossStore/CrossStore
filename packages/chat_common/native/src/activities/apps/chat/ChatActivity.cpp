#include "ChatActivity.h"

#if CROSSMUX_CHAT
#include <I18n.h>
#include <Logging.h>
#include <Memory.h>
#include <WiFi.h>

#include <algorithm>

#include "ChatService.h"
#include "activities/network/WifiSelectionActivity.h"
#include "activities/util/KeyboardEntryActivity.h"
#include "activities/util/SystemMessagesActivity.h"
#include "components/UITheme.h"
#include "fontIds.h"
#include "system/SystemMessages.h"

namespace fui = freeink::ui;
namespace {
const char* statusText(chat::Status status) {
  switch (status) {
    case chat::Status::Stopped:
      return tr(STR_CHAT_STOPPED);
    case chat::Status::Starting:
      return tr(STR_CHAT_STARTING);
    case chat::Status::Connecting:
      return tr(STR_CONNECTING);
    case chat::Status::Online:
      return tr(STR_CHAT_ONLINE);
    case chat::Status::Failed:
      return tr(STR_CHAT_FAILED);
    case chat::Status::StorageError:
      return tr(STR_CHAT_STORAGE_ERROR);
  }
  return "";
}
const char* deliveryText(chat::Delivery delivery) {
  switch (delivery) {
    case chat::Delivery::Received:
      return tr(STR_CHAT_RECEIVED);
    case chat::Delivery::Pending:
      return tr(STR_CHAT_PENDING);
    case chat::Delivery::Sent:
      return tr(STR_CHAT_BROADCAST_SENT);
    case chat::Delivery::Delivered:
      return tr(STR_CHAT_DELIVERED);
    case chat::Delivery::Failed:
      return tr(STR_CHAT_SEND_FAILED);
  }
  return "";
}
const char* addResultText(chat::AddResult result) {
  switch (result) {
    case chat::AddResult::None:
      return nullptr;
    case chat::AddResult::Pending:
      return tr(STR_CHAT_ADD_PENDING);
    case chat::AddResult::Requested:
      return tr(STR_CHAT_REQUEST_SUBMITTED);
    case chat::AddResult::Accepted:
      return tr(STR_CHAT_REQUEST_ACCEPTED);
    case chat::AddResult::Existing:
      return tr(STR_CHAT_ALREADY_ADDED);
    case chat::AddResult::InvalidId:
      return tr(STR_CHAT_INVALID_ID);
    case chat::AddResult::Limit:
      return tr(STR_CHAT_CONTACT_LIMIT);
    case chat::AddResult::StorageError:
      return tr(STR_CHAT_STORAGE_ERROR);
    case chat::AddResult::Failed:
      return tr(STR_CHAT_ACTION_FAILED);
  }
  return nullptr;
}
}  // namespace

const char* ChatActivity::headerTitle() const {
  if (view_ == View::Thread || view_ == View::Detail || view_ == View::PeerInfo) return peerTitle_;
  if (view_ == View::Identity) return tr(STR_CHAT_MY_ID);
  if (view_ == View::Options) return tr(STR_CHAT_OPTIONS);
  if (view_ == View::Nearby) return tr(STR_CHAT_DISCOVER);
  if (view_ == View::PairConfirm) return pairTitle_;
  switch (kind_) {
    case chat::Kind::Radio:
      return tr(STR_RF_CHAT);
    case chat::Kind::Wifi:
      return tr(STR_WIFI_CHAT);
    case chat::Kind::EspNow:
      return tr(STR_ESP_CHAT);
  }
  return "";
}
void ChatActivity::onEnter() {
  UiListActivity::onEnter();
  {
    RenderLock lock;
    refreshRows();
  }
  connect();
}
void ChatActivity::connect() {
  if (session_ && session_->active()) return;
  if (kind_ != chat::Kind::Wifi) {
    startSession();
    return;
  }
  if (WiFi.getMode() == WIFI_OFF) chat::service::ownWifi();
  if (WiFi.status() == WL_CONNECTED) {
    startSession();
    return;
  }
  startActivityForResultWith<WifiSelectionActivity>([this](const ActivityResult& result) {
    const auto* wifi = std::get_if<WifiResult>(&result.data);
    if (!result.isCancelled && wifi && wifi->connected)
      startSession();
    else
      chat::service::release(kind_);
  });
}
void ChatActivity::startSession() {
  stopSession();
  session_ = chat::service::acquire(kind_);
  const bool started = session_ != nullptr;
  RenderLock lock;
  if (!started) {
    LOG_ERR("CHAT", "Session allocation/start failed (%u bytes)", static_cast<unsigned>(sizeof(chat::Session)));
    session_ = nullptr;
    snapshot_.status = chat::Status::Failed;
  }
  refreshRows();
  requestUpdate();
}
void ChatActivity::stopSession() {
  if (session_) chat::service::release(kind_);
  session_ = nullptr;
}
void ChatActivity::prepareForSleep() { session_ = nullptr; }
void ChatActivity::onExit() {
  stopSession();
  Activity::onExit();
}
void ChatActivity::loop() {
  const uint32_t now = millis();
  if (session_ && now - refreshedAt_ >= 1000) {
    refreshedAt_ = now;
    RenderLock lock;
    const uint32_t revision = snapshot_.revision;
    if (session_->copySnapshot(snapshot_) && (snapshot_.revision != revision || initialPeer_[0])) {
      // Resolve notification navigation only after loading the contact state:
      // a pending request must open approval, not an unusable conversation.
      if (initialPeer_[0]) {
        openContact(initialPeer_);
        initialPeer_[0] = 0;
      }
      refreshRows();
      requestUpdate();
    }
  }
  UiListActivity::loop();
}
void ChatActivity::refreshRows() {
  closeRouting();
  if (session_)
    session_->viewing(view_ == View::Thread || view_ == View::Detail || view_ == View::PeerInfo ? peer_ : "");
  rowCount_ = 0;
  const char* addResult = addResultText(snapshot_.addResult);
  if (kind_ == chat::Kind::EspNow) {
    switch (snapshot_.addResult) {
      case chat::AddResult::Accepted:
        addResult = tr(STR_ESP_GROUP_JOINED);
        break;
      case chat::AddResult::Existing:
        addResult = tr(STR_ESP_GROUP_JOINED);
        break;
      case chat::AddResult::Limit:
        addResult = tr(STR_ESP_GROUP_LIMIT);
        break;
      case chat::AddResult::InvalidId:
        addResult = tr(STR_ESP_GROUP_INVALID);
        break;
      case chat::AddResult::None:
      case chat::AddResult::Pending:
      case chat::AddResult::Requested:
      case chat::AddResult::StorageError:
      case chat::AddResult::Failed:
        break;
    }
    std::snprintf(myCode_, sizeof(myCode_), tr(STR_ESP_CHANNEL_NEARBY), snapshot_.channel, snapshot_.nearbyCount);
  }
  auto row = [this](const char* label, const char* subtitle = nullptr) {
    auto& item = rows_[rowCount_];
    item = {};
    item.label = label;
    item.subtitle = subtitle;
    item.actionValue = static_cast<int16_t>(rowCount_++);
  };
  switch (view_) {
    case View::Options:
      row(commandFailed_ ? tr(STR_CHAT_ACTION_FAILED) : statusText(snapshot_.status),
          addResult                     ? addResult
          : kind_ == chat::Kind::Radio  ? tr(STR_CHAT_RF_PUBLIC)
          : kind_ == chat::Kind::EspNow ? tr(STR_ESP_DESCRIPTION)
                                        : tr(STR_CHAT_WIFI_DESCRIPTION));
      row(tr(STR_CHAT_MY_ID));
      row(kind_ == chat::Kind::EspNow ? tr(STR_ESP_JOIN_GROUP) : tr(STR_CHAT_DISCOVER));
      row(tr(STR_CHAT_BACKGROUND), tr(STR_CHAT_BACKGROUND_HINT));
      rows_[rowCount_ - 1].value = chat::service::background(kind_) ? tr(STR_STATE_ON) : tr(STR_STATE_OFF);
      row(tr(STR_SYSTEM_MESSAGES));
      if (kind_ == chat::Kind::Wifi) row(tr(STR_CHAT_MANUAL_ID));
      break;
    case View::Nearby:
      std::snprintf(myCode_, sizeof(myCode_), tr(STR_CHAT_MY_CODE), 8, snapshot_.identity);
      row(myCode_, tr(STR_CHAT_NEARBY_HINT));
      row(tr(STR_CHAT_SEARCH_AGAIN), commandFailed_            ? tr(STR_CHAT_ACTION_FAILED)
                                     : snapshot_.nearby.active ? tr(STR_CHAT_SEARCHING)
                                                               : tr(STR_CHAT_SEARCH_FINISHED));
      for (size_t i = 0; i < snapshot_.nearby.count; ++i) {
        char id[chat::MAX_ID + 1];
        chat::hex(snapshot_.nearby.peers[i].address, chat::nearby::ADDRESS_BYTES, id);
        peerTitle(id, contactTitles_[i], sizeof(contactTitles_[i]));
        row(contactTitles_[i], tr(STR_CHAT_PAIR_SELECT));
      }
      if (!snapshot_.nearby.count) row(tr(STR_CHAT_NO_NEARBY), tr(STR_CHAT_NEARBY_NETWORK_HINT));
      break;
    case View::PairConfirm:
      row(tr(STR_CHAT_COMPARE_CODE), pairTitle_);
      row(pairAction_ == PairAction::Invite ? tr(STR_CHAT_SEND_REQUEST) : tr(STR_CHAT_APPROVE_REQUEST));
      row(tr(STR_CANCEL));
      break;
    case View::Home:
      row(tr(STR_CHAT_OPTIONS), commandFailed_ ? tr(STR_CHAT_ACTION_FAILED)
                                : addResult    ? addResult
                                : kind_ == chat::Kind::EspNow && snapshot_.status == chat::Status::Online
                                    ? myCode_
                                    : statusText(snapshot_.status));
      if (addResult) rows_[rowCount_ - 1].value = statusText(snapshot_.status);
      if (kind_ != chat::Kind::Wifi) {
        const char* preview = tr(STR_CHAT_EMPTY);
        for (int j = snapshot_.messageCount - 1; j >= 0; --j) {
          if (!std::strcmp(snapshot_.messages[j].peer, "*")) {
            preview = snapshot_.messages[j].text;
            break;
          }
        }
        row(tr(STR_CHAT_PUBLIC_ROOM), preview);
      }
      for (size_t i = 0; i < snapshot_.contactCount; ++i) {
        const auto& entry = snapshot_.contacts[i];
        peerTitle(entry.id, contactTitles_[i], sizeof(contactTitles_[i]));
        const char* preview = tr(STR_CHAT_EMPTY);
        for (int j = snapshot_.messageCount - 1; j >= 0; --j) {
          if (!std::strcmp(snapshot_.messages[j].peer, entry.id)) {
            preview = snapshot_.messages[j].text;
            break;
          }
        }
        row(contactTitles_[i], entry.request ? tr(STR_CHAT_ACCEPT_REQUEST) : preview);
        rows_[rowCount_ - 1].value = kind_ == chat::Kind::EspNow
                                         ? tr(STR_ESP_GROUP_JOINED)
                                         : (entry.online ? tr(STR_CHAT_PEER_ONLINE) : tr(STR_CHAT_OFFLINE));
      }
      break;
    case View::Thread: {
      const uint8_t previousCount = messageCount_;
      messageCount_ = 0;
      for (int i = snapshot_.messageCount - 1; i >= 0; --i) {
        if (!std::strcmp(snapshot_.messages[i].peer, peer_)) messageIndices_[messageCount_++] = static_cast<uint8_t>(i);
      }
      if (olderOffset_ && messageCount_ > previousCount) olderOffset_ += messageCount_ - previousCount;
      olderOffset_ = std::min<int>(olderOffset_, std::max(0, messageCount_ - 1));
      // Four controls followed by message actions; all hit rects are drawn below.
      rowCount_ = 4 + messageCount_;
      break;
    }
    case View::Detail:
    case View::PeerInfo:
      for (size_t i = 0; i < lineCount_; ++i) row(lines_[i]);
      break;
    case View::Identity:
      rowCount_ = 1;
      break;
  }
}
void ChatActivity::buildScreen(UiScreen& screen) {
  if (view_ == View::Thread) {
    buildThread(screen);
    return;
  }
  if (view_ == View::Identity) {
    buildIdentity(screen);
    return;
  }
  const auto& metrics = UITheme::getInstance().getMetrics();
  screen.setContentMargin(fui::Insets{static_cast<int16_t>(metrics.topPadding + metrics.headerHeight), 0,
                                      static_cast<int16_t>(metrics.buttonHintsHeight), 0});
  screen.spacer(static_cast<int16_t>(metrics.verticalSpacing));
  fui::ListProps props;
  props.items = rows_;
  props.count = static_cast<uint16_t>(rowCount_);
  props.action = ACTION_ROW;
  props.inputMask = fui::InputTouch;
  syncListViewport(screen, props);
  screen.list(props);
}
void ChatActivity::makeLines(const char* text) {
  lineCount_ = 0;
  const int available = renderer.getScreenWidth() - UITheme::getInstance().getMetrics().contentSidePadding * 2 - 24;
  size_t offset = 0;
  while (text[offset] && lineCount_ < 12) {
    auto& line = lines_[lineCount_++];
    size_t used = 0;
    while (text[offset] && used < chat::MAX_TEXT) {
      size_t bytes = 1;
      while (text[offset + bytes] && (static_cast<uint8_t>(text[offset + bytes]) & 0xc0) == 0x80) ++bytes;
      if (used + bytes > chat::MAX_TEXT) break;
      std::memcpy(line + used, text + offset, bytes);
      line[used + bytes] = 0;
      if (used && renderer.getTextWidth(UI_12_FONT_ID, line) > available) {
        line[used] = 0;
        break;
      }
      used += bytes;
      offset += bytes;
    }
    line[used] = 0;
  }
}
void ChatActivity::compose() {
  startActivityForResultWith<KeyboardEntryActivity>(
      [this](const ActivityResult& result) {
        const auto* input = std::get_if<KeyboardResult>(&result.data);
        if (result.isCancelled || !input) return;
        RenderLock lock;
        commandFailed_ = !session_ || !session_->send(peer_, input->text.c_str());
        std::snprintf(draft_, sizeof(draft_), "%s", commandFailed_ ? input->text.c_str() : "");
        olderOffset_ = 0;
        refreshRows();
        requestUpdate();
      },
      tr(STR_CHAT_COMPOSE), draft_, chat::MAX_TEXT, InputType::Text);
}
void ChatActivity::addContact() {
  startActivityForResultWith<KeyboardEntryActivity>(
      [this](const ActivityResult& result) {
        const auto* input = std::get_if<KeyboardResult>(&result.data);
        if (result.isCancelled || !input) return;
        RenderLock lock;
        commandFailed_ = !session_ || !session_->add(input->text.c_str());
        refreshRows();
        requestUpdate();
      },
      kind_ == chat::Kind::EspNow ? tr(STR_ESP_GROUP_PROMPT) : tr(STR_CHAT_ADD_CONTACT), "",
      kind_ == chat::Kind::EspNow ? 6 : chat::MAX_ID, InputType::Text);
}
void ChatActivity::activateIndex(int index) {
  RenderLock lock;
  if (index < 0 || index >= rowCount_) return;
  app.clearTapFlash();
  switch (view_) {
    case View::Options: {
      if (index == 0) {
        lock.unlock();
        connect();
        return;
      }
      if (index == 1) {
        openIdentity();
      } else if (index == 2) {
        if (kind_ == chat::Kind::EspNow) {
          lock.unlock();
          addContact();
          return;
        }
        commandFailed_ = !session_ || !session_->discover();
        if (kind_ == chat::Kind::Wifi) view_ = View::Nearby;
      } else if (index == 3) {
        commandFailed_ = !chat::service::setBackground(kind_, !chat::service::background(kind_));
      } else if (index == 4) {
        lock.unlock();
        startActivityForResultWith<SystemMessagesActivity>([](const ActivityResult&) {});
        return;
      } else if (index == 5 && kind_ == chat::Kind::Wifi) {
        lock.unlock();
        addContact();
        return;
      }
      break;
    }
    case View::Nearby:
      if (index == 0) {
        openIdentity();
      } else if (index == 1) {
        commandFailed_ = !session_ || !session_->discover();
      } else if (index - 2 < snapshot_.nearby.count) {
        // Freeze the selected address while confirming; discovery can expire
        // or reorder its rows in the meantime.
        chat::hex(snapshot_.nearby.peers[index - 2].address, chat::nearby::ADDRESS_BYTES, pairId_);
        peerTitle(pairId_, pairTitle_, sizeof(pairTitle_));
        pairAction_ = PairAction::Invite;
        view_ = View::PairConfirm;
        for (size_t i = 0; i < snapshot_.contactCount; ++i) {
          const auto& entry = snapshot_.contacts[i];
          if (std::strncmp(entry.id, pairId_, chat::nearby::KEY_BYTES * 2)) continue;
          openContact(entry.id);
          break;
        }
      }
      break;
    case View::PairConfirm:
      if (index == 0) return;
      if (index == 1) {
        commandFailed_ = !session_ || !session_->add(pairId_);
        if (!commandFailed_) view_ = View::Home;
      } else {
        view_ = pairAction_ == PairAction::Invite ? View::Nearby : View::Home;
      }
      break;
    case View::Home: {
      if (index == 0) {
        view_ = View::Options;
      } else if (kind_ != chat::Kind::Wifi && index == 1) {
        openThread("*");
      } else {
        const int contact = index - (kind_ != chat::Kind::Wifi ? 2 : 1);
        if (contact < 0 || contact >= snapshot_.contactCount) return;
        const auto& entry = snapshot_.contacts[contact];
        openContact(entry.id);
      }
      break;
    }
    case View::Thread:
      switch (index) {
        case 0:
          lock.unlock();
          compose();
          return;
        case 1:
        case 2:
          lock.unlock();
          pageThread(index == 1);
          return;
        case 3:
          makeLines(kind_ == chat::Kind::EspNow ? tr(STR_ESP_DESCRIPTION)
                                                : (std::strcmp(peer_, "*") == 0 ? tr(STR_CHAT_RF_PUBLIC) : peer_));
          view_ = View::PeerInfo;
          break;
        default: {
          const int messageIndex = index - 4;
          if (messageIndex < 0 || messageIndex >= messageCount_) return;
          const auto& message = snapshot_.messages[messageIndices_[messageIndex]];
          if (message.delivery == chat::Delivery::Failed) {
            commandFailed_ = !session_ || !session_->retry(peer_, message.id);
          } else {
            std::strcpy(detail_, message.text);
            makeLines(detail_);
            view_ = View::Detail;
          }
          break;
        }
      }
      break;
    case View::Detail:
    case View::PeerInfo:
      lock.unlock();
      onBackButton();
      return;
    case View::Identity:
      if (kind_ != chat::Kind::Wifi) {
        lock.unlock();
        onBackButton();
        return;
      }
      identityFormat_ = identityFormat_ == IdentityFormat::Qr ? IdentityFormat::FullText : IdentityFormat::Qr;
      break;
  }
  nav = {};
  refreshRows();
  requestUpdate();
}
void ChatActivity::onBackButton() {
  RenderLock lock;
  switch (view_) {
    case View::Home:
      lock.unlock();
      if (returnToParent_)
        finish();
      else
        activityManager.goToApps();
      return;
    case View::Thread:
    case View::Options:
      view_ = View::Home;
      break;
    case View::Identity:
      view_ = identityReturn_;
      break;
    case View::Nearby:
      view_ = View::Options;
      break;
    case View::PairConfirm:
      view_ = pairAction_ == PairAction::Invite ? View::Nearby : View::Home;
      break;
    case View::Detail:
    case View::PeerInfo:
      view_ = View::Thread;
      break;
  }
  nav = {};
  refreshRows();
  requestUpdate();
}
void ChatActivity::peerTitle(const char* id, char* out, size_t size) {
  if (!std::strcmp(id, "*")) {
    std::snprintf(out, size, "%s", tr(STR_CHAT_PUBLIC_ROOM));
    return;
  }
  if (id[0] == 'G' && std::strlen(id) == 7) {
    std::snprintf(out, size, tr(STR_ESP_GROUP_TITLE), id + 1);
    return;
  }
  char shortId[9]{};
  const size_t length = std::strlen(id);
  // RF IDs are little-endian MAC bytes followed by zero padding.
  std::snprintf(shortId, sizeof(shortId), "%.*s", length == 16 ? 4 : 8, length == 16 ? id + 8 : id);
  std::snprintf(out, size, tr(STR_CHAT_DEVICE), shortId);
}
void ChatActivity::openContact(const char* peer) {
  for (size_t i = 0; i < snapshot_.contactCount; ++i) {
    const auto& entry = snapshot_.contacts[i];
    if (std::strcmp(entry.id, peer) || !entry.request) continue;
    std::snprintf(pairId_, sizeof(pairId_), "%s", entry.id);
    peerTitle(pairId_, pairTitle_, sizeof(pairTitle_));
    pairAction_ = PairAction::Accept;
    view_ = View::PairConfirm;
    systemMessages::read(systemMessages::Source::Wifi, peer);
    return;
  }
  openThread(peer);
}
void ChatActivity::openThread(const char* peer) {
  std::strcpy(peer_, peer);
  peerTitle(peer_, peerTitle_, sizeof(peerTitle_));
  draft_[0] = 0;
  commandFailed_ = false;
  olderOffset_ = 0;
  messageCount_ = 0;
  view_ = View::Thread;
}
bool ChatActivity::peerOnline() const {
  for (size_t i = 0; i < snapshot_.contactCount; ++i) {
    if (!std::strcmp(snapshot_.contacts[i].id, peer_)) return snapshot_.contacts[i].online;
  }
  return false;
}
void ChatActivity::openIdentity() {
  identityReturn_ = view_;
  identityFormat_ = kind_ == chat::Kind::Wifi ? IdentityFormat::Qr : IdentityFormat::FullText;
  makeLines(snapshot_.identity[0] ? snapshot_.identity : tr(STR_CHAT_STARTING));
  std::snprintf(myCode_, sizeof(myCode_), tr(STR_CHAT_MY_CODE), 8, snapshot_.identity);
  if (kind_ == chat::Kind::Wifi && !identityQr_.init(snapshot_.identity))
    LOG_ERR("CHAT", "Identity unavailable for QR encoding");
  view_ = View::Identity;
}
void ChatActivity::buildIdentity(UiScreen& screen) {
  const auto& metrics = UITheme::getInstance().getMetrics();
  const auto safe = UITheme::getInstance().getScreenSafeArea(renderer, true);
  auto& target = screen.target();
  const int16_t margin = std::max(12, metrics.contentSidePadding);
  const int16_t left = safe.x + margin;
  const int16_t width = safe.width - margin * 2;
  const int16_t top = std::max(safe.y, metrics.topPadding + metrics.headerHeight) + 12;
  const int16_t bottom = safe.y + safe.height - 12;
  auto text = screen.theme().bodyText;
  text.align = fui::TextAlign::Center;
  const int16_t lineHeight = target.lineHeight(text.font);
  auto hint = screen.theme().smallText;
  hint.align = fui::TextAlign::Center;
  hint.maxLines = 2;
  const int16_t hintHeight = target.lineHeight(hint.font) * 2;
  const int16_t buttonHeight = std::max<int>(44, lineHeight + 20);
  const int16_t buttonTop = bottom - buttonHeight;
  const int16_t contentTop = top + lineHeight + 12;
  const int16_t contentBottom = buttonTop - hintHeight - 24;
  const int16_t contentHeight = std::max<int>(0, contentBottom - contentTop);
  target.text({left, top, width, lineHeight}, myCode_, text);
  switch (identityFormat_) {
    case IdentityFormat::Qr: {
      const int modules = identityQr_.code.size + chat::WifiIdentityQr::QUIET_MODULES * 2;
      const int16_t px = std::min<int>(width, contentHeight) / modules;
      if (identityQr_.ready && px >= 1) {
        const int16_t size = modules * px;
        const int16_t x = left + (width - size) / 2;
        const int16_t y = contentTop + (contentHeight - size) / 2;
        target.fill({x, y, size, size}, fui::Paint::solid(fui::Color::White));
        for (uint8_t row = 0; row < identityQr_.code.size; ++row) {
          for (uint8_t col = 0; col < identityQr_.code.size; ++col) {
            if (!qrcode_getModule(&identityQr_.code, col, row)) continue;
            const int16_t moduleX = x + (col + chat::WifiIdentityQr::QUIET_MODULES) * px;
            const int16_t moduleY = y + (row + chat::WifiIdentityQr::QUIET_MODULES) * px;
            target.fill({moduleX, moduleY, px, px}, fui::Paint::solid(fui::Color::Black));
          }
        }
      } else {
        target.text({left, contentTop, width, contentHeight}, tr(STR_CHAT_ID_NOT_READY), hint);
      }
      break;
    }
    case IdentityFormat::FullText: {
      int16_t y = contentTop + std::max<int>(0, (contentHeight - lineCount_ * lineHeight) / 2);
      for (size_t i = 0; i < lineCount_; ++i) {
        target.text({left, y, width, lineHeight}, lines_[i], text);
        y += lineHeight;
      }
      break;
    }
  }
  target.text({left, static_cast<int16_t>(buttonTop - hintHeight - 12), width, hintHeight},
              identityFormat_ == IdentityFormat::Qr ? tr(STR_CHAT_QR_HINT) : tr(STR_CHAT_ONE_ID_HINT), hint);
  buttonProps_ = {};
  buttonProps_.label = kind_ != chat::Kind::Wifi               ? tr(STR_BACK)
                       : identityFormat_ == IdentityFormat::Qr ? tr(STR_CHAT_FULL_ID)
                                                               : tr(STR_CHAT_SHOW_QR);
  buttonProps_.action = ACTION_ROW;
  buttonProps_.value = 0;
  buttonProps_.inputMask = fui::InputTouch;
  buttonProps_.radius = 8;
  screen.button(buttonProps_, {left, buttonTop, width, buttonHeight});
}
void ChatActivity::buildThread(UiScreen& screen) {
  const auto& metrics = UITheme::getInstance().getMetrics();
  auto& target = screen.target();
  const int16_t margin = std::max(12, metrics.contentSidePadding);
  const int16_t width = renderer.getScreenWidth() - margin * 2;
  const int16_t top = metrics.topPadding + metrics.headerHeight + 8;
  const int16_t bottom = renderer.getScreenHeight() - metrics.buttonHintsHeight - 8;
  const int16_t smallHeight = target.lineHeight(screen.theme().smallText.font);
  const int16_t statusHeight = smallHeight * 2;
  const bool publicRoom = !std::strcmp(peer_, "*");
  char status[112]{};
  if (commandFailed_) {
    std::snprintf(status, sizeof(status), "%s", tr(STR_CHAT_BUSY_DRAFT));
  } else if (snapshot_.status != chat::Status::Online) {
    std::snprintf(status, sizeof(status), "%s", statusText(snapshot_.status));
  } else if (kind_ == chat::Kind::EspNow) {
    std::snprintf(status, sizeof(status), tr(STR_ESP_CHANNEL_NEARBY), snapshot_.channel, snapshot_.nearbyCount);
  } else if (publicRoom) {
    unsigned online = 0;
    for (size_t i = 0; i < snapshot_.contactCount; ++i)
      if (snapshot_.contacts[i].online) ++online;
    std::snprintf(status, sizeof(status), tr(STR_CHAT_NEARBY_COUNT), online);
  } else {
    std::snprintf(status, sizeof(status), "%s", peerOnline() ? tr(STR_CHAT_PEER_ONLINE) : tr(STR_CHAT_PEER_OFFLINE));
  }
  auto small = screen.theme().smallText;
  small.maxLines = 2;
  target.text({margin, top, width, statusHeight}, status, small);
  const int16_t toolbarY = top + statusHeight + 6;
  const int16_t controlWidth = (width - 16) / 3;
  const int16_t composeY = bottom - 54;
  const int16_t messageTop = toolbarY + 44 + 12;
  const int16_t messageBottom = composeY - 12;
  const int16_t maxWidth = width * 4 / 5;
  auto textStyle = screen.theme().bodyText;
  const int16_t lineHeight = target.lineHeight(textStyle.font);
  textStyle.maxLines =
      std::max(1, std::min(12, (messageBottom - messageTop - 24 - smallHeight) / std::max<int>(1, lineHeight)));
  int16_t y = messageBottom;
  uint8_t drawn = 0;
  for (size_t i = olderOffset_; i < messageCount_; ++i) {
    const auto& message = snapshot_.messages[messageIndices_[i]];
    const bool outgoing = message.delivery != chat::Delivery::Received;
    const auto measured = fui::measureWrappedText(target, message.text, textStyle, maxWidth - 24);
    const int16_t bubbleWidth = std::max<int>(64, measured.width + 24);
    const int16_t bubbleHeight = std::max<int>(44, measured.height + 20);
    const bool showSender = !outgoing && kind_ == chat::Kind::EspNow && message.sender[0];
    const int16_t deliveryHeight = outgoing || showSender ? smallHeight + 4 : 0;
    const int16_t total = bubbleHeight + deliveryHeight;
    if (y - total < messageTop) break;
    y -= total;
    const int16_t x = outgoing ? margin + width - bubbleWidth : margin;
    const fui::Rect bubble{x, y, bubbleWidth, bubbleHeight};
    target.fill(bubble, fui::Paint::solid(outgoing ? fui::Color::Black : fui::Color::White), 10);
    target.stroke(bubble, fui::Paint::solid(fui::Color::Black), 1, 10);
    auto bubbleText = textStyle;
    bubbleText.color = outgoing ? fui::Color::White : fui::Color::Black;
    target.text(bubble.inset(fui::Insets{10, 12, 10, 12}), message.text, bubbleText);
    char caption[64]{};
    if (outgoing && kind_ == chat::Kind::EspNow && message.receipts)
      std::snprintf(caption, sizeof(caption), tr(STR_ESP_RECEIPTS), message.receipts);
    else if (showSender)
      std::snprintf(caption, sizeof(caption), tr(STR_CHAT_DEVICE), message.sender + 6);
    else
      std::snprintf(caption, sizeof(caption), "%s", deliveryText(message.delivery));
    if (outgoing || showSender) {
      auto deliveryStyle = screen.theme().smallText;
      deliveryStyle.align = outgoing ? fui::TextAlign::Right : fui::TextAlign::Left;
      target.text({margin, static_cast<int16_t>(y + bubbleHeight + 4), width, smallHeight}, caption, deliveryStyle);
    }
    // Include the full delivery label: short bubbles can have a wider retry
    // caption. Its hit area must match the visible text, not just the bubble.
    const int16_t statusWidth =
        outgoing ? target.measureText(screen.theme().smallText.font, caption, screen.theme().smallText).width : 0;
    const int16_t hitWidth = std::min<int>(width, std::max<int>(bubbleWidth, statusWidth));
    const int16_t hitX = outgoing ? margin + width - hitWidth : x;
    screen.frame().hit({hitX, y, hitWidth, total}, ACTION_ROW, static_cast<int16_t>(i + 4), fui::InputTouch);
    y -= 16;
    ++drawn;
  }
  pageMessages_ = std::max<uint8_t>(1, drawn);
  hasOlder_ = olderOffset_ + drawn < messageCount_;
  if (!messageCount_) {
    auto empty = screen.theme().bodyText;
    empty.align = fui::TextAlign::Center;
    empty.maxLines = 3;
    target.text({margin, messageTop, width, static_cast<int16_t>(messageBottom - messageTop)}, tr(STR_CHAT_EMPTY),
                empty);
  }
  const auto control = [&](int16_t x, int16_t w, const char* label, int16_t action, bool enabled) {
    buttonProps_ = {};
    auto& props = buttonProps_;
    props.label = label;
    props.action = ACTION_ROW;
    props.value = action;
    props.inputMask = fui::InputTouch;
    props.enabled = enabled;
    props.radius = 8;
    props.text = screen.theme().smallText;
    screen.button(props, {x, toolbarY, w, 44});
  };
  control(margin, controlWidth, tr(STR_CHAT_OLDER), 1, hasOlder_);
  control(margin + controlWidth + 8, controlWidth, tr(STR_CHAT_NEWER), 2, olderOffset_ > 0);
  control(margin + (controlWidth + 8) * 2, controlWidth, tr(STR_CHAT_DETAILS), 3, true);
  buttonProps_ = {};
  auto& composeButton = buttonProps_;
  composeButton.label = draft_[0] ? tr(STR_CHAT_EDIT_DRAFT) : tr(STR_CHAT_COMPOSE);
  composeButton.action = ACTION_ROW;
  composeButton.value = 0;
  composeButton.inputMask = fui::InputTouch;
  composeButton.radius = 10;
  screen.button(composeButton, {margin, composeY, width, 54});
}
void ChatActivity::pageThread(bool older) {
  RenderLock lock;
  if ((older && !hasOlder_) || (!older && !olderOffset_)) return;
  olderOffset_ = older ? std::min<int>(messageCount_ - 1, olderOffset_ + pageMessages_)
                       : std::max<int>(0, olderOffset_ - pageMessages_);
  closeRouting();
  requestUpdate();
}
bool ChatActivity::handleButtons() {
  if (view_ != View::Thread && view_ != View::Identity) return UiListActivity::handleButtons();
  if (mappedInput.wasReleased(MappedInputManager::Button::Back)) {
    onBackButton();
    return true;
  }
  if (mappedInput.wasReleased(MappedInputManager::Button::Confirm)) {
    if (view_ == View::Identity)
      activateIndex(0);
    else
      compose();
    return true;
  }
  return false;
}
void ChatActivity::navigateButtons() {
  if (view_ == View::Identity) return;
  if (view_ != View::Thread) {
    UiListActivity::navigateButtons();
    return;
  }
  buttonNavigator.onPreviousRelease([this] { pageThread(true); });
  buttonNavigator.onNextRelease([this] { pageThread(false); });
}
bool ChatActivity::handleListSwipe(MappedInputManager::SwipeDir swipe, int x, int y) {
  if (view_ == View::Identity) return false;
  if (view_ != View::Thread) return UiListActivity::handleListSwipe(swipe, x, y);
  if (swipe == MappedInputManager::SwipeDir::Down || swipe == MappedInputManager::SwipeDir::Up) {
    pageThread(swipe == MappedInputManager::SwipeDir::Down);
    return true;
  }
  return false;
}
void ChatActivity::drawFooter() {
  if (view_ == View::Identity) {
    const auto labels = mappedInput.mapLabels(tr(STR_BACK), tr(STR_CHAT_DETAILS), "", "");
    GUI.drawButtonHintsWithStyle(renderer, labels.btn1, labels.btn2, labels.btn3, labels.btn4, usesUpstreamStyle());
    return;
  }
  if (view_ != View::Thread) {
    UiListActivity::drawFooter();
    return;
  }
  const auto labels = mappedInput.mapLabels(tr(STR_BACK), tr(STR_CHAT_COMPOSE), tr(STR_CHAT_OLDER), tr(STR_CHAT_NEWER));
  GUI.drawButtonHintsWithStyle(renderer, labels.btn1, labels.btn2, labels.btn3, labels.btn4, usesUpstreamStyle());
}
#endif
