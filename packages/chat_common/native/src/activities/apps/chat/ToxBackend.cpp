#include "ToxBackend.h"

#if CROSSMUX_TOX_CHAT
#include <HalMemory.h>
#include <HalStorage.h>
#include <I18n.h>
#include <Logging.h>
#include <toxcore/network.h>
#include <toxcore/tox_private.h>

#include <algorithm>
#include <cstddef>

#include "ChatSession.h"

namespace chat {
namespace {
constexpr size_t TOX_MEMORY_LIMIT = 3 * 1024 * 1024;
constexpr size_t SAVE_LIMIT = 256 * 1024;
constexpr char SAVE[] = "/.crosspoint/wifi_chat/identity.tox";
constexpr char BACKUP[] = "/.crosspoint/wifi_chat/identity.tox.previous";
constexpr char TEMP[] = "/.crosspoint/wifi_chat/identity.tox.part";
struct alignas(std::max_align_t) Allocation {
  size_t bytes;
};
// From https://nodes.tox.chat/json, checked 2026-10-18. Numeric hosts avoid
// blocking DNS in the worker. LAN discovery remains enabled independently.
struct Bootstrap {
  const char* host;
  const char* key;
  uint16_t udpPort;
  uint16_t tcpPort;
};
constexpr Bootstrap NODES[] = {
    {"119.59.101.63", "197F746696062FA3BD07BB3BC0656ABD6692B4DAA27DACF0F474754F2B09B060", 33445, 443},
    {"144.172.88.203", "2016A0F2797EE3A8B004BA623F11AAFC8146F1B8F45107232A1A1AECCE856674", 33445, 443},
    {"144.217.167.73", "7E5668E0EE09E19F320AD47902419331FFEE147BB3606769CFBE921A2A2FD34C", 33445, 3389},
    {"172.105.109.31", "D46E97CF995DC1820B92B7D899E152A217D36ABE22730FEA4B6BF1BFC06C617C", 33445, 33445},
};
}  // namespace

const Memory_Funcs ToxBackend::memoryFunctions_ = {allocate, reallocate, release};
ToxBackend::ToxBackend(Session& session) : session_(session), memory_{&memoryFunctions_, this} {}
ToxBackend::~ToxBackend() { stop(); }
void* ToxBackend::allocate(void* self, uint32_t bytes) {
  auto& backend = *static_cast<ToxBackend*>(self);
  const size_t size = static_cast<size_t>(bytes) + sizeof(Allocation);
  if (size > TOX_MEMORY_LIMIT || backend.allocated_ > TOX_MEMORY_LIMIT - size) {
    LOG_ERR("CHAT", "Tox memory cap: %u + %u", static_cast<unsigned>(backend.allocated_), static_cast<unsigned>(size));
    return nullptr;
  }
  // Tox owns these variable-sized blocks and releases them through release().
  // Stack/static cannot satisfy its allocator ABI; never consume internal RAM.
  auto storage = HalMemory::allocatePsram(size);
  if (!storage) {
    LOG_ERR("CHAT", "Tox PSRAM allocation failed: %u", static_cast<unsigned>(size));
    return nullptr;
  }
  auto* allocation = reinterpret_cast<Allocation*>(storage.release());
  allocation->bytes = size;
  backend.allocated_ += size;
  return allocation + 1;
}
void ToxBackend::release(void* self, void* ptr) {
  if (!ptr) return;
  auto& backend = *static_cast<ToxBackend*>(self);
  auto* allocation = static_cast<Allocation*>(ptr) - 1;
  backend.allocated_ -= allocation->bytes;
  HalMemory::PsramDeleter{}(reinterpret_cast<uint8_t*>(allocation));
}
// Invoked by c-toxcore through memoryFunctions_, not by a direct C++ call.
// cppcheck-suppress unusedPrivateFunction
void* ToxBackend::reallocate(void* self, void* ptr, uint32_t bytes) {
  if (!bytes) {
    release(self, ptr);
    return nullptr;
  }
  void* replacement = allocate(self, bytes);  // cap includes old + new peak
  if (!replacement) return nullptr;
  if (ptr) {
    const auto* old = static_cast<Allocation*>(ptr) - 1;
    std::memcpy(replacement, ptr, std::min<size_t>(bytes, old->bytes - sizeof(Allocation)));
    release(self, ptr);
  }
  return replacement;
}
bool ToxBackend::peerKey(uint32_t number, char* out) const {
  uint8_t key[TOX_PUBLIC_KEY_SIZE];
  if (!tox_friend_get_public_key(tox_, number, key, nullptr)) return false;
  hex(key, sizeof(key), out);
  return true;
}
bool ToxBackend::begin() {
  Tox_Options* options = tox_options_new(nullptr);
  if (!options) {
    LOG_ERR("CHAT", "Tox options allocation failed");
    return false;
  }
  tox_options_set_ipv6_enabled(options, false);
  tox_options_set_local_discovery_enabled(options, true);
  tox_options_set_experimental_groups_persistence(options, false);
  tox_options_set_start_port(options, 33445);
  tox_options_set_end_port(options, 33445);
  tox_options_set_log_callback(options, [](Tox*, Tox_Log_Level level, const char*, uint32_t line, const char* function,
                                           const char* message, void*) {
    if (level >= TOX_LOG_LEVEL_WARNING) LOG_ERR("TOX", "%s:%u %s", function, line, message);
  });
  HalMemory::PsramBuffer saved;
  // Recover an interrupted rename without generating a different identity.
  const char* checkpoint = Storage.exists(SAVE) ? SAVE : Storage.exists(BACKUP) ? BACKUP : TEMP;
  if (Storage.exists(checkpoint)) {
    auto file = Storage.open(checkpoint);
    const size_t size = file ? file.size() : 0;
    // Bounded cold load, released immediately after tox_new. A corrupt identity
    // fails closed instead of silently replacing the user's private key.
    if (!size || size > SAVE_LIMIT || !(saved = HalMemory::allocatePsram(size)) ||
        file.read(saved.get(), size) != static_cast<int>(size)) {
      tox_options_free(options);
      return false;
    }
    tox_options_set_savedata_type(options, TOX_SAVEDATA_TYPE_TOX_SAVE);
    tox_options_set_savedata_data(options, saved.get(), size);
  }
  Tox_System system = tox_default_system();
  system.mem = &memory_;
  const Tox_Options_Testing testing{&system};
  Tox_Err_New error;
  tox_ = tox_new_testing(options, &error, &testing, nullptr);
  tox_options_free(options);
  saved.reset();
  if (!tox_ || error != TOX_ERR_NEW_OK) {
    LOG_ERR("CHAT", "Tox initialization failed: %d", static_cast<int>(error));
    if (tox_) tox_kill(tox_);
    tox_ = nullptr;
    return false;
  }
  if (tox_self_get_friend_list_size(tox_) > MAX_CONTACTS) {
    tox_kill(tox_);
    tox_ = nullptr;
    return false;
  }
  uint8_t address[TOX_ADDRESS_SIZE];
  tox_self_get_address(tox_, address);
  hex(address, sizeof(address), session_.state.identity);
  tox_self_set_name(tox_, reinterpret_cast<const uint8_t*>("CrossMux"), 8, nullptr);
  tox_callback_friend_message(
      tox_, [](Tox*, uint32_t peer, Tox_Message_Type type, const uint8_t* text, size_t length, void* user) {
        auto& backend = *static_cast<ToxBackend*>(user);
        char key[65];
        if (type == TOX_MESSAGE_TYPE_NORMAL && backend.peerKey(peer, key)) {
          LOG_INF("CHAT", "Tox received peer=%u bytes=%u", peer, static_cast<unsigned>(length));
          backend.session_.received(key, text, length, 0);
        }
      });
  tox_callback_friend_read_receipt(tox_, [](Tox*, uint32_t peer, uint32_t id, void* user) {
    auto& backend = *static_cast<ToxBackend*>(user);
    char key[65];
    if (!backend.peerKey(peer, key)) return;
    for (auto& receipt : backend.receipts_) {
      // Retire exactly the matching slot while dispatching its receipt.
      // cppcheck-suppress useStlAlgorithm
      if (receipt.used && receipt.peer == peer && receipt.transportId == id) {
        backend.session_.delivered(key, receipt.localId);
        receipt.used = false;
        break;
      }
    }
  });
  tox_callback_friend_connection_status(tox_, [](Tox*, uint32_t peer, Tox_Connection connection, void* user) {
    auto& backend = *static_cast<ToxBackend*>(user);
    char key[65];
    LOG_INF("CHAT", "Tox friend=%u connection=%d", peer, static_cast<int>(connection));
    if (backend.peerKey(peer, key)) backend.session_.contact(key, connection != TOX_CONNECTION_NONE);
    auto& state = backend.session_.state;
    if (connection != TOX_CONNECTION_NONE && peer == backend.lastAddedFriend_ &&
        (state.addResult == AddResult::Requested || state.addResult == AddResult::Accepted)) {
      state.addResult = AddResult::None;
      ++state.revision;
    }
  });
  tox_callback_friend_request(tox_, [](Tox*, const uint8_t* key, const uint8_t*, size_t, void* user) {
    auto& backend = *static_cast<ToxBackend*>(user);
    char id[65];
    hex(key, TOX_PUBLIC_KEY_SIZE, id);
    LOG_INF("CHAT", "Tox friend request received from %.8s", id);
    backend.session_.contact(id, false, true);  // explicit approval in the UI
  });
  refreshContacts();
  dirty_ = true;
  if (!save()) {
    tox_kill(tox_);
    tox_ = nullptr;
    return false;
  }
  bootstrap();
  LOG_INF("CHAT", "Tox ready id=%.8s udp=%u friends=%u protocol allocation=%u bytes", session_.state.identity,
          tox_self_get_udp_port(tox_, nullptr), static_cast<unsigned>(tox_self_get_friend_list_size(tox_)),
          static_cast<unsigned>(allocated_));
  return true;
}
void ToxBackend::refreshContacts() {
  uint32_t friends[MAX_CONTACTS];
  const size_t count = tox_self_get_friend_list_size(tox_);
  if (count > MAX_CONTACTS) return;
  tox_self_get_friend_list(tox_, friends);
  for (size_t i = 0; i < count; ++i) {
    char key[65];
    if (peerKey(friends[i], key)) {
      session_.contact(key, tox_friend_get_connection_status(tox_, friends[i], nullptr) != TOX_CONNECTION_NONE);
    }
  }
}
void ToxBackend::bootstrap() {
  for (const auto& node : NODES) {
    uint8_t key[TOX_PUBLIC_KEY_SIZE];
    if (!unhex(node.key, key, sizeof(key))) continue;
    Tox_Err_Bootstrap udpError, tcpError;
    tox_bootstrap(tox_, node.host, node.udpPort, key, &udpError);
    tox_add_tcp_relay(tox_, node.host, node.tcpPort, key, &tcpError);
    if (udpError != TOX_ERR_BOOTSTRAP_OK || tcpError != TOX_ERR_BOOTSTRAP_OK)
      LOG_ERR("CHAT", "Bootstrap %s rejected: udp=%d tcp=%d", node.host, static_cast<int>(udpError),
              static_cast<int>(tcpError));
  }
}
void ToxBackend::tick(uint32_t now) {
  if (!tox_) return;
  discoveryTick(now);
  if (now - lastIterate_ < tox_iteration_interval(tox_)) return;
  lastIterate_ = now;
  tox_iterate(tox_, this);
  if (session_.state.status != Status::StorageError) {
    const auto connection = tox_self_get_connection_status(tox_);
    const Status status = connection == TOX_CONNECTION_NONE ? Status::Connecting : Status::Online;
    if (status != session_.state.status)
      LOG_INF("CHAT", "Tox network connection=%d friends=%u", static_cast<int>(connection),
              static_cast<unsigned>(tox_self_get_friend_list_size(tox_)));
    session_.status(status);
  }
  if (now - lastBootstrap_ >= 30000 && tox_self_get_connection_status(tox_) == TOX_CONNECTION_NONE) {
    lastBootstrap_ = now;
    bootstrap();
  }
}
bool ToxBackend::discover(uint32_t now) {
  if (!tox_) return false;
  stopDiscovery();
  const auto* network = tox_get_system(tox_)->ns;
  const Socket socket = net_socket(network, net_family_ipv4(), TOX_SOCK_DGRAM, TOX_PROTO_UDP);
  discoverySocket_ = net_socket_to_native(socket);
  IP_Port bind{};
  bind.ip.family = net_family_ipv4();
  bind.port = net_htons(nearby::PORT);
  if (!sock_valid(socket) || !net_set_socket_nonblock(network, socket) || !net_set_socket_broadcast(network, socket) ||
      ns_bind(network, socket, &bind) != 0) {
    LOG_ERR("CHAT", "Nearby discovery socket unavailable");
    stopDiscovery();
    return false;
  }
  discoveryStarted_ = now;
  discoverySent_ = now - 1000;
  session_.state.nearby.active = true;
  ++session_.state.revision;
  return true;
}
void ToxBackend::stopDiscovery() {
  if (discoverySocket_ >= 0) {
    ns_close(tox_get_system(tox_)->ns, net_socket_from_native(discoverySocket_));
    discoverySocket_ = -1;
  }
  if (session_.state.nearby.active) {
    session_.state.nearby.active = false;
    ++session_.state.revision;
  }
}
void ToxBackend::discoveryTick(uint32_t now) {
  auto& directory = session_.state.nearby;
  if (directory.expire(now)) ++session_.state.revision;
  if (!directory.active) return;
  if (now - discoveryStarted_ >= nearby::WINDOW_MS) {
    stopDiscovery();
    return;
  }
  const auto* network = tox_get_system(tox_)->ns;
  const Socket socket = net_socket_from_native(discoverySocket_);
  // Reuse Tox's network abstraction. One nonblocking UDP socket, no application
  // heap buffers; at most four bounded datagrams per worker tick.
  uint8_t bytes[nearby::FRAME_BYTES + 1];
  nearby::Packet packet;
  uint8_t self[TOX_ADDRESS_SIZE];
  tox_self_get_address(tox_, self);
  if (now - discoverySent_ >= 1000) {
    discoverySent_ = now;
    std::memcpy(packet.address, self, sizeof(self));
    tox_self_get_dht_id(tox_, packet.dht);
    packet.port = tox_self_get_udp_port(tox_, nullptr);
    IP_Port destination{};
    destination.ip.family = net_family_ipv4();
    destination.ip.ip.v4 = net_get_ip4_broadcast();
    destination.port = net_htons(nearby::PORT);
    if (nearby::encode(packet, bytes, nearby::FRAME_BYTES))
      ns_sendto(network, socket, bytes, nearby::FRAME_BYTES, &destination);
  }
  for (unsigned i = 0; i < 4; ++i) {
    IP_Port sender{};
    const int size = ns_recvfrom(network, socket, bytes, sizeof(bytes), &sender);
    if (size < 0) break;
    if (!nearby::decode(bytes, static_cast<size_t>(size), packet) || !net_family_is_ipv4(sender.ip.family) ||
        !std::memcmp(packet.address, self, nearby::KEY_BYTES))
      continue;
    if (directory.seen(packet.address, self, now)) {
      ++session_.state.revision;
      // Seed the actual sender's DHT endpoint so a LAN-only pair need not wait
      // for public bootstrap nodes. Discovery never accepts a friend request.
      char host[TOX_INET_ADDRSTRLEN];
      if (ip_parse_addr(&sender.ip, host, sizeof(host))) {
        LOG_INF("CHAT", "Nearby Tox endpoint %s:%u", host, packet.port);
        tox_bootstrap(tox_, host, packet.port, packet.dht, nullptr);
      }
    }
  }
}
AddResult ToxBackend::add(const char* address) {
  lastAddedFriend_ = UINT32_MAX;
  if (!tox_) return AddResult::Failed;
  uint8_t bytes[TOX_ADDRESS_SIZE];
  const bool invitation = std::strlen(address) == TOX_ADDRESS_SIZE * 2;
  if (!unhex(address, bytes, invitation ? TOX_ADDRESS_SIZE : TOX_PUBLIC_KEY_SIZE) ||
      (invitation && !nearby::validAddress(bytes)))
    return AddResult::InvalidId;
  Tox_Err_Friend_By_Public_Key lookup;
  const uint32_t existingFriend = tox_friend_by_public_key(tox_, bytes, &lookup);
  // Existing friends do not consume another slot, even at the contact limit.
  // Still let tox_friend_add update a changed nospam value on a valid address.
  if (lookup != TOX_ERR_FRIEND_BY_PUBLIC_KEY_OK && tox_self_get_friend_list_size(tox_) >= MAX_CONTACTS)
    return AddResult::Limit;
  Tox_Err_Friend_Add error;
  uint32_t number;
  if (invitation) {
    const char* message = tr(STR_CHAT_INVITE);
    number = tox_friend_add(tox_, bytes, reinterpret_cast<const uint8_t*>(message), std::strlen(message), &error);
  } else {
    bool requested = false;
    for (size_t i = 0; i < session_.state.contactCount; ++i) {
      const auto& entry = session_.state.contacts[i];
      if (entry.request && std::strcmp(address, entry.id) == 0) requested = true;
    }
    if (!requested) return AddResult::Failed;
    number = tox_friend_add_norequest(tox_, bytes, &error);
  }
  switch (error) {
    case TOX_ERR_FRIEND_ADD_OK:
      break;
    case TOX_ERR_FRIEND_ADD_SET_NEW_NOSPAM:
      number = existingFriend;
      break;
    case TOX_ERR_FRIEND_ADD_ALREADY_SENT:
      refreshContacts();
      return AddResult::Existing;
    case TOX_ERR_FRIEND_ADD_OWN_KEY:
    case TOX_ERR_FRIEND_ADD_BAD_CHECKSUM:
      return AddResult::InvalidId;
    case TOX_ERR_FRIEND_ADD_NULL:
    case TOX_ERR_FRIEND_ADD_TOO_LONG:
    case TOX_ERR_FRIEND_ADD_NO_MESSAGE:
    case TOX_ERR_FRIEND_ADD_MALLOC:
      LOG_ERR("CHAT", "Tox add %.8s failed: %d", address, static_cast<int>(error));
      return AddResult::Failed;
  }
  LOG_INF("CHAT", "Tox add %.8s accepted locally (%s)", address, invitation ? "request" : "approval");
  dirty_ = true;
  refreshContacts();
  if (!save()) {
    session_.status(Status::StorageError);
    return AddResult::StorageError;
  }
  lastAddedFriend_ = number;
  return invitation ? AddResult::Requested : AddResult::Accepted;
}
bool ToxBackend::send(const char* peer, const char* text, uint32_t id) {
  uint8_t key[TOX_PUBLIC_KEY_SIZE];
  if (!tox_ || !unhex(peer, key, sizeof(key))) {
    LOG_ERR("CHAT", "Tox send: unavailable or invalid peer key");
    return false;
  }
  Tox_Err_Friend_By_Public_Key lookup;
  const uint32_t number = tox_friend_by_public_key(tox_, key, &lookup);
  if (lookup != TOX_ERR_FRIEND_BY_PUBLIC_KEY_OK) {
    LOG_ERR("CHAT", "Tox send: peer lookup failed %d", static_cast<int>(lookup));
    return false;
  }
  Receipt* slot = nullptr;
  for (auto& receipt : receipts_) {
    // Fixed-capacity slot reservation; keep the ownership transition explicit.
    // cppcheck-suppress useStlAlgorithm
    if (!receipt.used) {
      slot = &receipt;
      break;
    }
  }
  if (!slot) {
    LOG_ERR("CHAT", "Tox send: receipt window full");
    return false;
  }
  Tox_Err_Friend_Send_Message error;
  const uint32_t transportId = tox_friend_send_message(
      tox_, number, TOX_MESSAGE_TYPE_NORMAL, reinterpret_cast<const uint8_t*>(text), std::strlen(text), &error);
  if (error != TOX_ERR_FRIEND_SEND_MESSAGE_OK) {
    LOG_ERR("CHAT", "Tox send peer=%u error=%d connection=%d network=%d", number, static_cast<int>(error),
            static_cast<int>(tox_friend_get_connection_status(tox_, number, nullptr)),
            static_cast<int>(tox_self_get_connection_status(tox_)));
    return false;
  }
  *slot = {number, transportId, id, true};
  return true;
}
bool ToxBackend::save() {
  if (!tox_ || !dirty_) return true;
  const size_t length = tox_get_savedata_size(tox_);
  if (!length || length > SAVE_LIMIT) return false;
  // Tox's serializer requires one contiguous output. At most 256 KiB PSRAM,
  // only on identity/contact changes and exit, released immediately afterward.
  auto bytes = HalMemory::allocatePsram(length);
  if (!bytes) {
    LOG_ERR("CHAT", "Tox savedata allocation failed: %u", static_cast<unsigned>(length));
    return false;
  }
  tox_get_savedata(tox_, bytes.get());
  {
    auto file = Storage.open(TEMP, O_WRONLY | O_CREAT | O_TRUNC);
    if (!file || file.write(bytes.get(), length) != length) return false;
    file.flush();
  }
  if (Storage.exists(SAVE)) {
    if (Storage.exists(BACKUP) && !Storage.remove(BACKUP)) return false;
    if (!Storage.rename(SAVE, BACKUP)) return false;
  }
  if (!Storage.rename(TEMP, SAVE)) return false;
  dirty_ = false;
  return true;
}
void ToxBackend::stop() {
  if (!tox_) return;
  stopDiscovery();
  dirty_ = true;
  if (!save()) LOG_ERR("CHAT", "Identity save failed; previous checkpoint retained");
  tox_kill(tox_);
  tox_ = nullptr;
  LOG_INF("CHAT", "Tox released, outstanding allocation=%u", static_cast<unsigned>(allocated_));
}
}  // namespace chat
#endif
