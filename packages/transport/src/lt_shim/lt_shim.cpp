#include "lt_shim.h"
#include <algorithm>
#include <chrono>
#include <condition_variable>
#include <cstdio>
#include <cstring>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <string>
#include <thread>
#include <unordered_map>
#include <unordered_set>
#include <vector>
#include <libtorrent/add_torrent_params.hpp>
#include <libtorrent/alert_types.hpp>
#include <libtorrent/announce_entry.hpp>
#include <libtorrent/load_torrent.hpp>
#include <libtorrent/magnet_uri.hpp>
#include <libtorrent/read_resume_data.hpp>
#include <libtorrent/session.hpp>
#include <libtorrent/settings_pack.hpp>
#include <libtorrent/torrent_handle.hpp>
#include <libtorrent/write_resume_data.hpp>

namespace {
struct Session;
struct Torrent {
  Session* owner{};
  libtorrent::torrent_handle handle;
  std::string save_path;
  std::vector<libtorrent::tcp::endpoint> hinted_peers;
  bool closing{};
  bool removed{};
};
struct Session {
  std::mutex mutex;
  std::condition_variable alerts_changed;
  std::unique_ptr<libtorrent::session> session;
  std::vector<std::unique_ptr<Torrent>> torrents;
  std::vector<std::pair<transport_lt_alert, std::string>> pending_alerts;
  std::string error;
};
// Raw handles cross the C ABI, so pointer validity must be checked without
// touching the pointed-to object. The registry lock is held for the complete
// native operation (including session destruction), which prevents a late
// Dart call from racing deletion of either object.
std::mutex registry_mutex;
std::unordered_set<Session*> live_sessions;
std::unordered_map<Torrent*, Session*> live_torrents;
template <typename F> int32_t call(Session* s, F&& f) {
  if (!s) return -1;
  std::lock_guard<std::mutex> registry_guard(registry_mutex);
  if (!live_sessions.count(s) || !s->session) return -1;
  std::lock_guard<std::mutex> guard(s->mutex);
  try { s->error.clear(); return f(); }
  catch (const std::exception& e) { s->error = e.what(); return -1; }
  catch (...) { s->error = "unknown libtorrent exception"; return -1; }
}
template <typename F> int32_t call(Torrent* t, F&& f) {
  if (!t) return -1;
  std::lock_guard<std::mutex> registry_guard(registry_mutex);
  const auto it = live_torrents.find(t);
  if (it == live_torrents.end() || !live_sessions.count(it->second) || !it->second->session || it->first->closing) return -1;
  auto* s = it->second;
  std::lock_guard<std::mutex> guard(s->mutex);
  try { s->error.clear(); return f(t); }
  catch (const std::exception& e) { s->error = e.what(); return -1; }
  catch (...) { s->error = "unknown libtorrent exception"; return -1; }
}
template <typename F> int32_t call_pair(Session* s, Torrent* t, F&& f) {
  if (!s || !t) return -1;
  std::lock_guard<std::mutex> registry_guard(registry_mutex);
  const auto it = live_torrents.find(t);
  if (!live_sessions.count(s) || it == live_torrents.end() || it->second != s || !s->session) return -1;
  std::lock_guard<std::mutex> guard(s->mutex);
  try { s->error.clear(); return f(t); }
  catch (const std::exception& e) { s->error = e.what(); return -1; }
  catch (...) { s->error = "unknown libtorrent exception"; return -1; }
}
std::string text(const char* p, int32_t n) {
  if (!p || n < 0 || n > (1 << 20)) throw std::invalid_argument("invalid string length");
  return {p, static_cast<size_t>(n)};
}
void copy_text(const std::string& value, char* out, int32_t cap, int32_t* len) {
  if (len) *len = static_cast<int32_t>(value.size());
  if (!out || cap <= 0) return;
  const auto n = std::min<size_t>(value.size(), static_cast<size_t>(cap - 1));
  std::memcpy(out, value.data(), n); out[n] = 0;
}
Torrent* add_handle(Session* s, libtorrent::torrent_handle h, const std::string& path,
  std::vector<libtorrent::tcp::endpoint> peers = {}) {
  auto t = std::make_unique<Torrent>();
  t->owner = s; t->handle = std::move(h); t->save_path = path; t->hinted_peers = std::move(peers);
  auto* result = t.get();
  s->torrents.push_back(std::move(t));
  live_torrents.emplace(result, s);
  return result;
}
Torrent* valid(void* p) {
  auto* t = static_cast<Torrent*>(p);
  std::lock_guard<std::mutex> guard(registry_mutex);
  return live_torrents.count(t) ? t : nullptr;
}
int kind(libtorrent::alert const* a) {
  if (libtorrent::alert_cast<libtorrent::metadata_received_alert>(a)) return TRANSPORT_LT_ALERT_METADATA;
  if (libtorrent::alert_cast<libtorrent::piece_finished_alert>(a)) return TRANSPORT_LT_ALERT_PIECE_FINISHED;
  if (libtorrent::alert_cast<libtorrent::torrent_error_alert>(a)) return TRANSPORT_LT_ALERT_TORRENT_ERROR;
  if (libtorrent::alert_cast<libtorrent::file_error_alert>(a)) return TRANSPORT_LT_ALERT_FILE_ERROR;
  if (libtorrent::alert_cast<libtorrent::tracker_error_alert>(a)) return TRANSPORT_LT_ALERT_TRACKER_ERROR;
  if (libtorrent::alert_cast<libtorrent::torrent_finished_alert>(a)) return TRANSPORT_LT_ALERT_TORRENT_FINISHED;
  if (libtorrent::alert_cast<libtorrent::state_changed_alert>(a)) return TRANSPORT_LT_ALERT_STATE_CHANGED;
  if (libtorrent::alert_cast<libtorrent::peer_disconnected_alert>(a)
      || libtorrent::alert_cast<libtorrent::peer_error_alert>(a)) return TRANSPORT_LT_ALERT_PEER_DISCONNECTED;
  if (libtorrent::alert_cast<libtorrent::alerts_dropped_alert>(a)) return TRANSPORT_LT_ALERT_ALERTS_DROPPED;
  if (libtorrent::alert_cast<libtorrent::save_resume_data_alert>(a)) return TRANSPORT_LT_ALERT_RESUME_DATA;
  if (libtorrent::alert_cast<libtorrent::torrent_removed_alert>(a)) return TRANSPORT_LT_ALERT_TORRENT_REMOVED;
  return 0;
}

void queue_alert(Session* s, libtorrent::alert const* a) {
  const auto k = kind(a);
  if (!k) return;
  transport_lt_alert o{};
  o.kind = k; o.piece = -1; o.peers = -1;
  if (auto* ta = dynamic_cast<libtorrent::torrent_alert const*>(a))
    for (auto& candidate : s->torrents)
      if (candidate->handle == ta->handle) {
        o.torrent = reinterpret_cast<uintptr_t>(candidate.get());
        if (libtorrent::alert_cast<libtorrent::torrent_removed_alert>(a)) {
          candidate->removed = true;
          candidate->handle = {};
        }
        break;
      }
  // Retired handle events must not be broadcast to unrelated live torrents.
  if (dynamic_cast<libtorrent::torrent_alert const*>(a) && o.torrent == 0) return;
  if (auto* piece = libtorrent::alert_cast<libtorrent::piece_finished_alert>(a))
    o.piece = static_cast<int32_t>(piece->piece_index);
  if (auto* error = libtorrent::alert_cast<libtorrent::torrent_error_alert>(a))
    o.error_code = error->error.value();
  if (auto* error = libtorrent::alert_cast<libtorrent::file_error_alert>(a))
    o.error_code = error->error.value();
  if (auto* peer = libtorrent::alert_cast<libtorrent::peer_disconnected_alert>(a))
    o.peers = peer->handle.is_valid() ? peer->handle.status().num_peers : -1;
  if (auto* peer = libtorrent::alert_cast<libtorrent::peer_error_alert>(a))
    o.peers = peer->handle.is_valid() ? peer->handle.status().num_peers : -1;
  s->pending_alerts.emplace_back(o, a->message());
}
template <typename P> libtorrent::add_torrent_params decode(P const* data, int32_t size) {
  return libtorrent::load_torrent_buffer(libtorrent::span<char const>(reinterpret_cast<char const*>(data), static_cast<size_t>(size)));
}
}

extern "C" transport_lt_session transport_lt_session_create(void) {
  auto* s = new (std::nothrow) Session(); if (!s) return nullptr;
  {
    std::lock_guard<std::mutex> registry_guard(registry_mutex);
    live_sessions.insert(s);
  }
  try {
    libtorrent::settings_pack p;
    p.set_int(libtorrent::settings_pack::alert_queue_size, 20000);
    p.set_int(libtorrent::settings_pack::alert_mask,
      static_cast<int>(static_cast<unsigned int>(
        libtorrent::alert_category::status
        | libtorrent::alert_category::error
        | libtorrent::alert_category::storage
        | libtorrent::alert_category::tracker
        | libtorrent::alert_category::piece_progress)));
    // Native playback uses explicit trackers/peers and TCP piece exchange.
    // Disable unsolicited UDP discovery/port mapping so teardown cannot race
    // a late DHT routing-table packet after the last torrent is removed.
    p.set_bool(libtorrent::settings_pack::enable_dht, false);
    p.set_bool(libtorrent::settings_pack::enable_lsd, false);
    p.set_bool(libtorrent::settings_pack::enable_upnp, false);
    p.set_bool(libtorrent::settings_pack::enable_natpmp, false);
    p.set_bool(libtorrent::settings_pack::enable_outgoing_utp, false);
    p.set_bool(libtorrent::settings_pack::enable_incoming_utp, false);
    s->session = std::make_unique<libtorrent::session>(p);
  } catch (const std::exception& e) { s->error = e.what(); }
  return s;
}
extern "C" void transport_lt_session_destroy(transport_lt_session raw) {
  auto* s = static_cast<Session*>(raw); if (!s) return;
  std::lock_guard<std::mutex> registry_guard(registry_mutex);
  if (!live_sessions.erase(s)) return;
  std::lock_guard<std::mutex> guard(s->mutex);
  if (s->session) {
    // Let session::~session abort and join all worker-owned torrents. Calling
    // remove_torrent here is asynchronous and can race disk/peer callbacks;
    // keep every torrent_handle alive until that drain has completed.
    s->session.reset();
    for (auto& t : s->torrents) live_torrents.erase(t.get());
    s->torrents.clear();
  }
  delete s;
}
extern "C" int32_t transport_lt_session_last_error(transport_lt_session raw, char* out, int32_t cap) {
  auto* s = static_cast<Session*>(raw);
  if (!s) { if (out && cap > 0) out[0] = 0; return 0; }
  std::lock_guard<std::mutex> registry_guard(registry_mutex);
  if (!live_sessions.count(s)) { if (out && cap > 0) out[0] = 0; return 0; }
  std::lock_guard<std::mutex> guard(s->mutex); int32_t len = 0; copy_text(s->error, out, cap, &len); return len;
}

// Hold payload before the torrent is added. Magnet metadata must remain live.
static void hold_payload(libtorrent::add_torrent_params& p) {
  p.flags &= ~libtorrent::torrent_flags::auto_managed;
  p.flags |= libtorrent::torrent_flags::default_dont_download;
  p.file_priorities.clear();
  p.piece_priorities.clear();
  if (p.ti) {
    p.flags |= libtorrent::torrent_flags::paused;
    p.file_priorities.assign(p.ti->num_files(), libtorrent::dont_download);
    p.piece_priorities.assign(p.ti->num_pieces(), libtorrent::dont_download);
  } else {
    p.flags &= ~libtorrent::torrent_flags::paused;
    p.flags |= libtorrent::torrent_flags::upload_mode;
  }
}
extern "C" transport_lt_torrent transport_lt_add_magnet(transport_lt_session raw, const char* magnet, int32_t magnet_len, const char* path, int32_t path_len, int32_t payload_paused) {
  auto* s = static_cast<Session*>(raw); if (!s) return nullptr; Torrent* result = nullptr;
  call(s, [&] {
    const auto save = text(path, path_len);
    auto p = libtorrent::parse_magnet_uri(text(magnet, magnet_len));
    p.save_path = save; if (payload_paused) hold_payload(p);
    // x.pe magnet hints are deliberately retained as explicit connection
    // attempts. Tracker announces remain enabled, but a local legal fixture
    // must not starve behind another verifier peer while waiting for its first
    // announce response.
    const auto peers = p.peers;
    auto handle = s->session->add_torrent(std::move(p));
    for (const auto& peer : peers) handle.connect_peer(peer);
    result = add_handle(s, std::move(handle), save, peers);
    return 0;
  }); return result;
}
extern "C" transport_lt_torrent transport_lt_add_torrent(transport_lt_session raw, const uint8_t* data, int32_t size, const char* path, int32_t path_len, int32_t payload_paused) {
  auto* s = static_cast<Session*>(raw); if (!s || !data || size <= 0) return nullptr; Torrent* result = nullptr;
  call(s, [&] { const auto save = text(path, path_len); auto p = decode(data, size); p.save_path = save; if (payload_paused) hold_payload(p); result = add_handle(s, s->session->add_torrent(std::move(p)), save); return 0; }); return result;
}
extern "C" transport_lt_torrent transport_lt_load_resume(transport_lt_session raw, const uint8_t* data, int32_t size, const char* path, int32_t path_len, int32_t payload_paused) {
  auto* s = static_cast<Session*>(raw); if (!s || !data || size <= 0) return nullptr; Torrent* result = nullptr;
  call(s, [&] { const auto save = text(path, path_len); auto p = libtorrent::read_resume_data(libtorrent::span<char const>(reinterpret_cast<char const*>(data), static_cast<size_t>(size))); p.save_path = save; if (payload_paused) hold_payload(p); result = add_handle(s, s->session->add_torrent(std::move(p)), save); return 0; }); return result;
}
extern "C" int32_t transport_lt_torrent_remove(transport_lt_session raw, transport_lt_torrent raw_t, int32_t del) {
  auto* s = static_cast<Session*>(raw); auto* t = static_cast<Torrent*>(raw_t);
  return call_pair(s, t, [&](Torrent* x) {
    if (x->closing) return 0;
    if (!x->handle.is_valid()) { x->closing = true; return 0; }
    x->closing = true;
    // Keep the torrent_handle alive until session destruction. libtorrent's
    // remove request is asynchronous; dropping the last handle immediately
    // can race peer/disk callbacks and corrupt their allocator state.
    s->session->remove_torrent(x->handle, del ? libtorrent::session_handle::delete_files : libtorrent::remove_flags_t{});
    return 0;
  });
}
extern "C" void transport_lt_torrent_close(transport_lt_torrent raw) {
  auto* t = static_cast<Torrent*>(raw); if (!t) return;
  Session* owner = nullptr;
  {
    std::lock_guard<std::mutex> registry_guard(registry_mutex);
    const auto it = live_torrents.find(t);
    if (it != live_torrents.end()) owner = it->second;
  }
  if (owner) transport_lt_torrent_remove(owner, t, 0);
}
extern "C" int32_t transport_lt_torrent_close_complete(transport_lt_torrent raw) {
  auto* t = static_cast<Torrent*>(raw); if (!t) return 1;
  std::lock_guard<std::mutex> registry_guard(registry_mutex);
  const auto it = live_torrents.find(t);
  if (it == live_torrents.end()) return 1;
  auto* s = it->second;
  std::lock_guard<std::mutex> guard(s->mutex);
  return t->removed ? 1 : 0;
}
extern "C" int32_t transport_lt_torrent_metadata_ready(transport_lt_torrent raw) { auto* t = valid(raw); return t ? call(t, [](Torrent* x) { return x->handle.torrent_file() ? 1 : 0; }) : 0; }
extern "C" int32_t transport_lt_torrent_file_count(transport_lt_torrent raw) { auto* t = valid(raw); return t ? call(t, [](Torrent* x) { auto i = x->handle.torrent_file(); return i ? i->num_files() : 0; }) : -1; }
extern "C" int32_t transport_lt_torrent_piece_length(transport_lt_torrent raw) { auto* t = valid(raw); return t ? call(t, [](Torrent* x) { auto i = x->handle.torrent_file(); return i ? i->piece_length() : 0; }) : -1; }
extern "C" int32_t transport_lt_torrent_piece_count(transport_lt_torrent raw) { auto* t = valid(raw); return t ? call(t, [](Torrent* x) { auto i = x->handle.torrent_file(); return i ? i->num_pieces() : 0; }) : -1; }
extern "C" int32_t transport_lt_torrent_info_hash(transport_lt_torrent raw, char* out, int32_t cap) { auto* t = valid(raw); if (!t || !out || cap < 41) return -1; return call(t, [&](Torrent* x) { static constexpr char digits[] = "0123456789abcdef"; const auto hash = x->handle.info_hashes().v1; for (int i = 0; i < 20; ++i) { const auto byte = static_cast<unsigned char>(hash.data()[i]); out[i * 2] = digits[byte >> 4]; out[i * 2 + 1] = digits[byte & 15]; } out[40] = 0; return 40; }); }
extern "C" int32_t transport_lt_torrent_file_info(transport_lt_torrent raw, int32_t index, transport_lt_file_info* out, char* path, int32_t cap) {
  auto* t = valid(raw); if (!t || !out || index < 0) return -1; return call(t, [&](Torrent* x) { auto i = x->handle.torrent_file(); if (!i || index >= i->num_files()) throw std::out_of_range("file index"); const auto file = libtorrent::file_index_t(index); auto const& f = i->files(); out->offset = f.file_offset(file); out->size = f.file_size(file); out->is_pad = f.pad_file_at(file) ? 1 : 0; auto name = f.file_path(file); copy_text(name, path, cap, &out->path_length); return out->path_length; });
}
extern "C" int32_t transport_lt_torrent_piece_available(transport_lt_torrent raw, int32_t piece) { auto* t = valid(raw); return t && piece >= 0 ? call(t, [&](Torrent* x) { auto i = x->handle.torrent_file(); return i && piece < i->num_pieces() && x->handle.have_piece(libtorrent::piece_index_t(piece)) ? 1 : 0; }) : 0; }
extern "C" int32_t transport_lt_torrent_copy_piece_bitfield(transport_lt_torrent raw, uint8_t* out, int32_t cap) {
  auto* t = valid(raw); if (!t || !out || cap <= 0) return -1;
  return call(t, [&](Torrent* x) {
    auto i = x->handle.torrent_file(); if (!i) return 0;
    if (cap < i->num_pieces()) return -2;
    // One synchronous status call, rather than one thread round-trip per piece.
    const auto status = x->handle.status(libtorrent::torrent_handle::query_pieces);
    for (int n = 0; n < i->num_pieces(); ++n)
      out[n] = n < status.pieces.size() && status.pieces[libtorrent::piece_index_t(n)] ? 1 : 0;
    return i->num_pieces();
  });
}
extern "C" int32_t transport_lt_torrent_read(transport_lt_torrent raw, int32_t fi, int64_t off, uint8_t* out, int32_t cap) {
  auto* t = static_cast<Torrent*>(raw);
  if (!t || !out || cap <= 0 || fi < 0 || off < 0) return -1;
  Session* s = nullptr;
  {
    std::lock_guard<std::mutex> registry_guard(registry_mutex);
    const auto it = live_torrents.find(t);
    if (it == live_torrents.end() || !live_sessions.count(it->second)) return -1;
    s = it->second;
  }
  std::unique_lock<std::mutex> lock(s->mutex);
  try {
    if (!s->session || t->closing) throw std::invalid_argument("torrent is closed");
    auto i = t->handle.torrent_file(); if (!i || fi >= i->num_files()) return -1;
    const auto file = libtorrent::file_index_t(fi); auto const& files = i->files();
    const auto size = files.file_size(file); if (off >= size) return 0;
    const auto n = static_cast<int32_t>(std::min<int64_t>(cap, size - off));
    const auto piece_length = std::max<int64_t>(1, i->piece_length());
    const auto global_start = files.file_offset(file) + off;
    const auto global_end = global_start + n - 1;
    const auto first_piece = global_start / piece_length;
    const auto last_piece = global_end / piece_length;
    const auto piece_deadline = std::chrono::steady_clock::now() + std::chrono::seconds(10);
    while (std::chrono::steady_clock::now() < piece_deadline) {
      bool have_all = true;
      for (auto piece = first_piece; piece <= last_piece; ++piece)
        if (!t->handle.have_piece(libtorrent::piece_index_t(piece))) { have_all = false; break; }
      if (have_all) break;
      lock.unlock();
      std::this_thread::sleep_for(std::chrono::milliseconds(10));
      lock.lock();
    }
    for (auto piece = first_piece; piece <= last_piece; ++piece)
      if (!t->handle.have_piece(libtorrent::piece_index_t(piece)))
        throw std::runtime_error("requested torrent piece is not available");
    // A verified piece can still be held in libtorrent's write cache. Read
    // through that cache; a full-length sparse disk read may contain zeros.
    std::unordered_map<int32_t, std::vector<uint8_t>> piece_data;
    for (auto piece = first_piece; piece <= last_piece; ++piece)
      t->handle.read_piece(libtorrent::piece_index_t(piece));
    const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(10);
    auto ready = [&] {
      for (auto piece = first_piece; piece <= last_piece; ++piece)
        if (!piece_data.count(static_cast<int32_t>(piece))) return false;
      return true;
    };
    // FFI reads are synchronous on the Dart isolate, so the Dart alert timer
    // cannot run while this call is blocked. Pump only the native completion
    // alerts here; the regular alert poller still receives all other alerts.
    while (!ready() && std::chrono::steady_clock::now() < deadline) {
      std::vector<libtorrent::alert*> alerts;
      s->session->pop_alerts(&alerts);
      for (auto* alert : alerts) {
        queue_alert(s, alert);
        if (auto* piece = libtorrent::alert_cast<libtorrent::read_piece_alert>(alert)) {
          const auto index = static_cast<int32_t>(piece->piece);
          if (piece->handle != t->handle || index < first_piece || index > last_piece) continue;
          if (piece->error) throw std::runtime_error("torrent piece " + std::to_string(index)
            + " read failed: " + piece->error.message());
          if (piece->buffer && piece->size > 0) {
            auto& bytes = piece_data[static_cast<int32_t>(piece->piece)];
            bytes.assign(reinterpret_cast<const uint8_t*>(piece->buffer.get()),
              reinterpret_cast<const uint8_t*>(piece->buffer.get()) + piece->size);
          }
        }
      }
      if (!ready()) s->session->wait_for_alert(libtorrent::milliseconds(10));
    }
    if (!ready()) throw std::runtime_error("torrent read_piece alert timeout");
    int32_t copied = 0;
    for (auto piece = first_piece; piece <= last_piece; ++piece) {
      const auto it = piece_data.find(static_cast<int32_t>(piece));
      if (it == piece_data.end()) throw std::runtime_error("missing torrent read_piece data");
      const auto piece_start = piece * piece_length;
      const auto from = static_cast<size_t>(std::max<int64_t>(0, global_start - piece_start));
      const auto to = static_cast<size_t>(std::min<int64_t>(it->second.size(), global_end - piece_start + 1));
      if (from > to || to - from > static_cast<size_t>(n - copied))
        throw std::runtime_error("torrent read_piece returned short data");
      std::memcpy(out + copied, it->second.data() + from, to - from);
      copied += static_cast<int32_t>(to - from);
      piece_data.erase(it);
    }
    if (copied != n) throw std::runtime_error("torrent read_piece returned short data");
    return n;
  } catch (const std::exception& e) {
    s->error = e.what();
    return -1;
  } catch (...) {
    s->error = "unknown libtorrent exception";
    return -1;
  }
}
extern "C" int32_t transport_lt_torrent_prioritize_files(transport_lt_torrent raw, const uint8_t* priorities, int32_t count) { auto* t = valid(raw); if (!t || !priorities || count < 0) return -1; return call(t, [&](Torrent* x) { auto i = x->handle.torrent_file(); if (!i || count != i->num_files()) return -1; std::vector<libtorrent::download_priority_t> p; for (int n = 0; n < count; ++n) p.push_back(static_cast<libtorrent::download_priority_t>(std::min<uint8_t>(7, priorities[n]))); x->handle.prioritize_files(p); return 0; }); }
extern "C" int32_t transport_lt_torrent_file_priority(transport_lt_torrent raw, int32_t index) { auto* t = valid(raw); if (!t || index < 0) return -1; return call(t, [&](Torrent* x) { auto const priorities = x->handle.get_file_priorities(); return index < static_cast<int32_t>(priorities.size()) ? static_cast<int32_t>(static_cast<std::uint8_t>(priorities[static_cast<size_t>(index)])) : -1; }); }
extern "C" int32_t transport_lt_torrent_set_piece_priority(transport_lt_torrent raw, int32_t piece, int32_t priority) {
  auto* t = valid(raw);
  if (!t || piece < 0 || priority < 0 || priority > 7) return -1;
  return call(t, [&](Torrent* x) {
    const auto before = x->handle.status();
    const bool restart_peers = priority > 0 && before.is_finished
      && before.num_peers == 0;
    x->handle.piece_priority(libtorrent::piece_index_t(piece), static_cast<libtorrent::download_priority_t>(priority));
    if (restart_peers) {
      // A fully downloaded bounded window is "finished": seeds disconnect.
      // Re-adding the same candidate keeps its old connection history, so
      // rebuild the empty peer list once as it becomes unfinished instead.
      // No retry timer or cooldown setting changes.
      x->handle.status();
      if (!x->hinted_peers.empty()) x->handle.clear_peers();
      x->handle.resume();
      x->handle.force_reannounce();
      for (const auto& peer : x->hinted_peers) x->handle.connect_peer(peer);
    }
    return 0;
  });
}
extern "C" int32_t transport_lt_torrent_set_piece_deadline(transport_lt_torrent raw, int32_t piece, int32_t ms) { auto* t = valid(raw); if (!t || piece < 0 || ms < 0) return -1; return call(t, [&](Torrent* x) { x->handle.resume(); for (const auto& peer : x->hinted_peers) x->handle.connect_peer(peer); x->handle.set_piece_deadline(libtorrent::piece_index_t(piece), ms); return 0; }); }
extern "C" int32_t transport_lt_torrent_clear_piece_deadlines(transport_lt_torrent raw) { auto* t = valid(raw); return t ? call(t, [](Torrent* x) { x->handle.clear_piece_deadlines(); return 0; }) : -1; }
extern "C" int32_t transport_lt_torrent_status(transport_lt_torrent raw, int32_t* peers, int32_t* state, int64_t* done, int64_t* total, int32_t* rate) { auto* t = valid(raw); if (!t || !peers || !state || !done || !total || !rate) return -1; return call(t, [&](Torrent* x) { auto s = x->handle.status(libtorrent::status_flags_t::all()); *peers = s.num_peers; *state = static_cast<int32_t>(s.state); *done = s.total_done; *total = s.total_wanted; *rate = s.download_payload_rate; return 0; }); }
extern "C" int32_t transport_lt_torrent_stats(transport_lt_torrent raw, transport_lt_stats* out) { auto* t = valid(raw); if (!t || !out) return -1; return call(t, [&](Torrent* x) { auto s = x->handle.status(libtorrent::status_flags_t::all()); out->total_upload = s.all_time_upload; out->distributed_copies = s.distributed_copies; out->upload_rate = s.upload_payload_rate; out->num_seeds = s.num_seeds; out->num_peers = s.num_peers; out->num_complete = s.num_complete; out->num_incomplete = s.num_incomplete; out->num_pieces = s.num_pieces; return 0; }); }
namespace {
template <typename F> void each_line(const std::string& block, F&& f) {
  size_t i = 0;
  while (i < block.size()) {
    auto e = block.find('\n', i); if (e == std::string::npos) e = block.size();
    const auto line = block.substr(i, e - i); i = e + 1;
    const auto eq = line.find('=');
    if (line.empty()) continue;
    if (eq == std::string::npos) throw std::invalid_argument("malformed option line");
    f(line.substr(0, eq), line.substr(eq + 1));
  }
}
}
extern "C" int32_t transport_lt_session_set(transport_lt_session raw, const char* block, int32_t len) {
  auto* s = static_cast<Session*>(raw); if (!s) return -1;
  return call(s, [&] {
    libtorrent::settings_pack p; int32_t n = 0;
    each_line(text(block, len), [&](std::string const& k, std::string const& v) {
      const int id = libtorrent::setting_by_name(k);
      if (id < 0) throw std::invalid_argument("unknown setting " + k);
      switch (id & libtorrent::settings_pack::type_mask) {
        case libtorrent::settings_pack::string_type_base: p.set_str(id, v); break;
        case libtorrent::settings_pack::int_type_base: p.set_int(id, std::stoi(v)); break;
        default: p.set_bool(id, v == "1" || v == "true"); break;
      }
      ++n;
    });
    s->session->apply_settings(std::move(p));
    return n;
  });
}
extern "C" int32_t transport_lt_session_get(transport_lt_session raw, const char* name, int32_t nlen, char* out, int32_t cap) {
  auto* s = static_cast<Session*>(raw); if (!s) return -1;
  return call(s, [&] {
    const auto k = text(name, nlen); const int id = libtorrent::setting_by_name(k);
    if (id < 0) throw std::invalid_argument("unknown setting " + k);
    const auto cur = s->session->get_settings(); std::string v;
    switch (id & libtorrent::settings_pack::type_mask) {
      case libtorrent::settings_pack::string_type_base: v = cur.get_str(id); break;
      case libtorrent::settings_pack::int_type_base: v = std::to_string(cur.get_int(id)); break;
      default: v = cur.get_bool(id) ? "1" : "0"; break;
    }
    int32_t l = 0; copy_text(v, out, cap, &l); return l;
  });
}
extern "C" int32_t transport_lt_torrent_set(transport_lt_torrent raw, const char* block, int32_t len) {
  auto* t = valid(raw); if (!t) return -1;
  return call(t, [&](Torrent* x) {
    int32_t n = 0;
    each_line(text(block, len), [&](std::string const& k, std::string const& v) {
      if (k == "download_limit") x->handle.set_download_limit(std::stoi(v));
      else if (k == "upload_limit") x->handle.set_upload_limit(std::stoi(v));
      else if (k == "max_connections") x->handle.set_max_connections(std::stoi(v));
      else if (k == "pex") { if (v == "1") x->handle.unset_flags(libtorrent::torrent_flags::disable_pex); else x->handle.set_flags(libtorrent::torrent_flags::disable_pex); }
      else if (k == "tracker") x->handle.add_tracker(libtorrent::announce_entry(v));
      else throw std::invalid_argument("unknown torrent option " + k);
      ++n;
    });
    return n;
  });
}
extern "C" int32_t transport_lt_torrent_get(transport_lt_torrent raw, const char* name, int32_t nlen, char* out, int32_t cap) {
  auto* t = valid(raw); if (!t) return -1;
  return call(t, [&](Torrent* x) {
    const auto k = text(name, nlen); std::string v;
    if (k == "download_limit") v = std::to_string(x->handle.download_limit());
    else if (k == "upload_limit") v = std::to_string(x->handle.upload_limit());
    else if (k == "max_connections") v = std::to_string(x->handle.max_connections());
    else if (k == "pex") v = (x->handle.flags() & libtorrent::torrent_flags::disable_pex) ? "0" : "1";
    else if (k == "total_upload") v = std::to_string(x->handle.status(libtorrent::status_flags_t{}).all_time_upload);
    else if (k == "total_download") v = std::to_string(x->handle.status(libtorrent::status_flags_t{}).all_time_download);
    else if (k == "tracker") { for (auto const& e : x->handle.trackers()) { if (!v.empty()) v += '\n'; v += e.url; } }
    else throw std::invalid_argument("unknown torrent option " + k);
    int32_t l = 0; copy_text(v, out, cap, &l); return l;
  });
}
extern "C" int32_t transport_lt_pop_alerts(transport_lt_session raw, transport_lt_alert* out, int32_t cap, char* messages, int32_t messages_cap) {
  auto* s = static_cast<Session*>(raw);
  if (!s || cap < 0 || (cap && !out) || messages_cap < 0) return -1;
  return call(s, [&] {
    std::vector<libtorrent::alert*> alerts;
    s->session->pop_alerts(&alerts);
    for (auto* alert : alerts) queue_alert(s, alert);
    int32_t count = 0, cursor = 0;
    for (auto const& pending : s->pending_alerts) {
      if (count == cap) break;
      auto& o = out[count++];
      o = pending.first;
      if (messages && cursor < messages_cap) {
        const auto n = std::min<int32_t>(static_cast<int32_t>(pending.second.size()), messages_cap - cursor);
        std::memcpy(messages + cursor, pending.second.data(), static_cast<size_t>(n));
        o.message_length = n;
        cursor += n;
      }
    }
    s->pending_alerts.erase(s->pending_alerts.begin(), s->pending_alerts.begin() + count);
    return count;
  });
}
extern "C" int32_t transport_lt_torrent_save_resume(transport_lt_torrent raw, uint8_t* out, int32_t cap) { auto* t = valid(raw); if (!t || !out || cap <= 0) return -1; return call(t, [&](Torrent* x) { auto bytes = libtorrent::write_resume_data_buf(x->handle.get_resume_data(libtorrent::torrent_handle::save_info_dict)); if (cap < static_cast<int32_t>(bytes.size())) return -static_cast<int32_t>(bytes.size()); std::memcpy(out, bytes.data(), bytes.size()); return static_cast<int32_t>(bytes.size()); }); }
// Replaces the torrent's libtorrent handle by a fresh add of `p`.
// remove_torrent() is asynchronous.  Never overwrite x->handle while
// the old handle can still receive disk/peer callbacks: the wrapper is a
// stable ABI identity and the removed alert is the retirement barrier.
// `between` runs once the old handle is gone (its files are closed) and
// before the new one is added.
template <typename F> static void replace_handle(Session* s, Torrent* x, libtorrent::add_torrent_params p, F&& between) {
  for (const auto& peer : p.peers)
    if (std::find(x->hinted_peers.begin(), x->hinted_peers.end(), peer) == x->hinted_peers.end())
      x->hinted_peers.push_back(peer);
  const auto old_handle = x->handle;
  // Peers we are talking to now: a fresh handle starts with none.
  std::vector<libtorrent::tcp::endpoint> connected;
  if (old_handle.is_valid()) {
    std::vector<libtorrent::peer_info> peers;
    old_handle.get_peer_info(peers);
    for (auto const& peer : peers) {
      connected.push_back(peer.ip);
      if (std::find(x->hinted_peers.begin(), x->hinted_peers.end(), peer.ip) == x->hinted_peers.end())
        x->hinted_peers.push_back(peer.ip);
    }
  }
  x->closing = true;
  if (old_handle.is_valid()) s->session->remove_torrent(old_handle);
  bool removed = !old_handle.is_valid();
  const auto deadline = std::chrono::steady_clock::now() + std::chrono::seconds(10);
  while (!removed && std::chrono::steady_clock::now() < deadline) {
    std::vector<libtorrent::alert*> alerts;
    s->session->pop_alerts(&alerts);
    for (auto* alert : alerts) {
      queue_alert(s, alert);
      if (auto* done = libtorrent::alert_cast<libtorrent::torrent_removed_alert>(alert))
        if (done->handle == old_handle) removed = true;
    }
    if (!removed) std::this_thread::sleep_for(std::chrono::milliseconds(10));
  }
  if (!removed) throw std::runtime_error("resume replacement timed out waiting for torrent_removed_alert");
  between();
  x->handle = s->session->add_torrent(std::move(p));
  // Announce again and reconnect the peers we were using and those we were
  // told about.
  x->handle.resume();
  x->handle.force_reannounce();
  for (const auto& peer : x->hinted_peers) x->handle.connect_peer(peer);
  for (const auto& peer : connected) x->handle.connect_peer(peer);
  x->closing = false;
  x->removed = false;
}

int32_t transport_lt_torrent_initialize_download(transport_lt_session raw, transport_lt_torrent raw_t, int32_t file, int32_t first_piece, int32_t end_piece) {
  auto* s = static_cast<Session*>(raw); auto* t = static_cast<Torrent*>(raw_t);
  return call_pair(s, t, [&](Torrent* x) {
    auto info = x->handle.torrent_file();
    if (!info || file < 0 || file >= info->num_files() || first_piece < 0 || end_piece <= first_piece || end_piece > info->num_pieces())
      throw std::runtime_error("invalid initial torrent download window");
    auto p = x->handle.get_resume_data();
    if (!p.ti) p.ti = std::make_shared<libtorrent::torrent_info>(*info);
    p.save_path = x->save_path;
    p.file_priorities.assign(info->num_files(), libtorrent::dont_download);
    p.file_priorities[file] = libtorrent::top_priority;
    p.piece_priorities.assign(info->num_pieces(), libtorrent::dont_download);
    for (int32_t piece = first_piece; piece < end_piece; ++piece)
      p.piece_priorities[piece] = libtorrent::default_priority;
    // add_torrent_params installs both priority vectors together, unlike the
    // asynchronous prioritize_files API which resets custom piece priorities.
    p.flags &= ~(libtorrent::torrent_flags::upload_mode
      | libtorrent::torrent_flags::default_dont_download
      | libtorrent::torrent_flags::auto_managed);
    p.flags |= libtorrent::torrent_flags::paused;
    replace_handle(s, x, std::move(p), [] {});
    return 0;
  });
}
extern "C" int32_t transport_lt_torrent_load_resume(transport_lt_session raw, transport_lt_torrent raw_t, const uint8_t* data, int32_t size) {
  auto* s = static_cast<Session*>(raw); auto* t = static_cast<Torrent*>(raw_t);
  if (!data || size <= 0) return -1;
  return call_pair(s, t, [&](Torrent* x) {
    auto p = libtorrent::read_resume_data(libtorrent::span<char const>(reinterpret_cast<char const*>(data), static_cast<size_t>(size)));
    p.save_path = x->save_path;
    replace_handle(s, x, std::move(p), [] {});
    return 0;
  });
}
// Forgets `count` downloaded pieces (ascending indexes): the torrent is
// re-added from its own resume data with those pieces cleared, and their disk
// blocks are punched out while no handle has the files open. libtorrent has no
// public "un-have piece", so this is the supported route (add_torrent_params::have_pieces).
extern "C" int32_t transport_lt_torrent_evict_pieces(transport_lt_session raw, transport_lt_torrent raw_t, const int32_t* pieces, int32_t count) {
  auto* s = static_cast<Session*>(raw); auto* t = static_cast<Torrent*>(raw_t);
  if (!pieces || count <= 0) return -1;
  return call_pair(s, t, [&](Torrent* x) {
    if (!x->handle.is_valid()) throw std::runtime_error("torrent has no live handle");
    auto info = x->handle.torrent_file();
    if (!info) throw std::runtime_error("torrent metadata not ready");
    auto p = x->handle.get_resume_data();
    if (!p.ti) p.ti = std::make_shared<libtorrent::torrent_info>(*info);
    p.save_path = x->save_path;
    const auto& files = info->files();
    for (int32_t i = 0; i < count; i++) {
      const libtorrent::piece_index_t piece{pieces[i]};
      if (p.have_pieces.size() > pieces[i]) p.have_pieces.clear_bit(piece);
      if (p.verified_pieces.size() > pieces[i]) p.verified_pieces.clear_bit(piece);
      p.unfinished_pieces.erase(piece);
      if (p.piece_priorities.size() < static_cast<size_t>(info->num_pieces()))
        p.piece_priorities = x->handle.get_piece_priorities();
      p.piece_priorities[pieces[i]] = libtorrent::dont_download;
    }
    replace_handle(s, x, std::move(p), [&] {
      // Merge consecutive pieces into one punch per file run.
      std::string run_path; int64_t run_start = 0, run_end = 0;
      auto flush = [&] {
        if (run_end > run_start && transport_lt_fs_punch_hole(run_path.data(), static_cast<int32_t>(run_path.size()), run_start, run_end - run_start) != 0)
          throw std::runtime_error("torrent cache hole punching failed");
        run_end = run_start = 0;
      };
      for (int32_t i = 0; i < count; i++) {
        const libtorrent::piece_index_t piece{pieces[i]};
        for (auto const& slice : info->map_block(piece, 0, info->piece_size(piece))) {
          if (files.pad_file_at(slice.file_index)) continue;
          const auto path = files.file_path(slice.file_index, x->save_path);
          if (path != run_path || slice.offset != run_end) { flush(); run_path = path; run_start = slice.offset; }
          run_end = slice.offset + slice.size;
        }
      }
      flush();
    });
    return count;
  });
}
