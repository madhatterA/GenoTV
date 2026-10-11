#import "aria2_shim.h"
#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstring>
#include <mutex>
#include <new>
#include <stdexcept>
#include <string>
#include <thread>
#include <unordered_set>
#include <vector>
#if __has_include(<aria2/aria2.h>)
#include <aria2/aria2.h>
#define TRANSPORT_HAS_LIBARIA2 1
#endif

namespace {
struct AriaSession {
#if TRANSPORT_HAS_LIBARIA2
  aria2::Session* session = nullptr;
#endif
  #if TRANSPORT_HAS_LIBARIA2
  // Paused jobs live in aria2’s waiting queue but need no event polling.
  std::unordered_set<aria2::A2Gid> paused;
  #endif
  std::string error;
  std::mutex error_mutex;
  std::mutex mutex;
  std::thread runner;
  std::atomic<bool> stop{false};
  // Set by a caller that lost try_lock; the worker then leaves a gap so the
  // caller's retry can win (std::mutex is unfair and the worker relocks at once).
  std::atomic<bool> contended{false};
};

#if TRANSPORT_HAS_LIBARIA2
struct AriaLibraryLifetime {
  std::once_flag init_once;
  std::atomic<int32_t> init_result{-1};

  ~AriaLibraryLifetime() noexcept {
    if (init_result.load(std::memory_order_acquire) == 0) {
      try {
        aria2::libraryDeinit();
      } catch (...) {
      }
    }
  }
};

AriaLibraryLifetime& library_lifetime() {
  static AriaLibraryLifetime lifetime;
  return lifetime;
}

int32_t ensure_library_initialized() noexcept {
  auto& lifetime = library_lifetime();
  try {
    std::call_once(lifetime.init_once, [&lifetime] {
      try {
        lifetime.init_result.store(
            aria2::libraryInit(), std::memory_order_release);
      } catch (...) {
        lifetime.init_result.store(-1, std::memory_order_release);
      }
    });
  } catch (...) {
    return -1;
  }
  return lifetime.init_result.load(std::memory_order_acquire);
}

void delete_download_handle(aria2::DownloadHandle*& handle) noexcept {
  if (!handle) return;
  try {
    aria2::deleteDownloadHandle(handle);
  } catch (...) {
  }
  handle = nullptr;
}

void finalize_session(AriaSession* session) noexcept {
  if (!session) return;
  try {
    std::lock_guard<std::mutex> lock(session->mutex);
    if (session->session) {
      try {
        aria2::sessionFinal(session->session);
      } catch (...) {
      }
      session->session = nullptr;
    }
  } catch (...) {
  }
}
#endif

std::string bounded(const char* p, int32_t n) {
  if (n < 0 || n > (1 << 20) || (!p && n != 0)) {
    throw std::invalid_argument("invalid aria2 string");
  }
  return p ? std::string(p, static_cast<size_t>(n)) : std::string();
}

void set_error(AriaSession* s, const std::exception& e) noexcept {
  try {
    std::lock_guard<std::mutex> lock(s->error_mutex);
    s->error = e.what();
  } catch (...) {
  }
}

void set_error_message(AriaSession* s, const std::string& message) noexcept {
  try {
    std::lock_guard<std::mutex> lock(s->error_mutex);
    s->error = message;
  } catch (...) {
  }
}

void set_busy_error(AriaSession* s) noexcept {
  s->contended.store(true, std::memory_order_relaxed);
  set_error_message(s, "aria2 session busy");
}

void set_unknown_error(AriaSession* s) noexcept {
  set_error_message(s, "unknown aria2 native exception");
}

#if TRANSPORT_HAS_LIBARIA2
void add_headers(aria2::KeyVals* options, const std::string& block) {
  size_t start = 0;
  while (start < block.size()) {
    const auto end = block.find('\n', start);
    auto header = block.substr(start, end == std::string::npos
        ? std::string::npos
        : end - start);
    if (!header.empty() && header.back() == '\r') header.pop_back();
    if (!header.empty()) options->emplace_back("header", std::move(header));
    if (end == std::string::npos) break;
    start = end + 1;
  }
}

void add_options(aria2::KeyVals* options, const std::string& block) {
  size_t start = 0;
  while (start < block.size()) {
    const auto end = block.find('\n', start);
    const auto line = block.substr(start, end == std::string::npos
        ? std::string::npos
        : end - start);
    const auto separator = line.find('=');
    if (separator == std::string::npos || separator == 0) {
      throw std::invalid_argument("invalid aria2 option");
    }
    options->emplace_back(
        line.substr(0, separator), line.substr(separator + 1));
    if (end == std::string::npos) break;
    start = end + 1;
  }
}

void run_loop(AriaSession* s) noexcept {
  try {
    while (!s->stop.load(std::memory_order_relaxed)) {
      if (s->contended.exchange(false, std::memory_order_relaxed)) {
        std::this_thread::sleep_for(std::chrono::milliseconds(10));
      }
      bool idle = false;
      {
        std::lock_guard<std::mutex> lock(s->mutex);
        if (!s->session) return;
        try {
          // RUN_ONCE blocks up to 1 s when aria2 has nothing to do, and every
          // API call waits for it; with no active/waiting download, sleep instead.
          const auto stat = aria2::getGlobalStat(s->session);
          idle = stat.numActive == 0 && stat.numWaiting == s->paused.size();
          const auto result = idle ? 0 : aria2::run(s->session, aria2::RUN_ONCE);
          if (result < 0) {
            set_error_message(s, "aria2 run failed: " + std::to_string(result));
            s->stop.store(true, std::memory_order_relaxed);
          }
        } catch (const std::exception& e) {
          set_error(s, e);
          s->stop.store(true, std::memory_order_relaxed);
        } catch (...) {
          set_unknown_error(s);
          s->stop.store(true, std::memory_order_relaxed);
        }
      }
      if (idle) std::this_thread::sleep_for(std::chrono::milliseconds(20));
    }
  } catch (const std::exception& e) {
    set_error(s, e);
    s->stop.store(true, std::memory_order_relaxed);
  } catch (...) {
    set_unknown_error(s);
    s->stop.store(true, std::memory_order_relaxed);
  }
}
#endif
}  // namespace

extern "C" transport_aria2_session transport_aria2_create(void) {
#if !TRANSPORT_HAS_LIBARIA2
  return nullptr;
#else
  AriaSession* wrapper = nullptr;
  try {
    wrapper = new (std::nothrow) AriaSession();
    if (!wrapper) return nullptr;
    const auto init_result = ensure_library_initialized();
    if (init_result != 0) {
      set_error_message(
          wrapper, "aria2 libraryInit failed: " + std::to_string(init_result));
      return wrapper;
    }
    aria2::SessionConfig config;
    config.keepRunning = true;
    config.useSignalHandler = false;
    aria2::KeyVals options;
    wrapper->session = aria2::sessionNew(options, config);
    if (!wrapper->session) {
      set_error_message(wrapper, "aria2 sessionNew failed");
      return wrapper;
    }
    wrapper->runner = std::thread(run_loop, wrapper);
  } catch (const std::exception& e) {
    if (wrapper) {
      finalize_session(wrapper);
      set_error(wrapper, e);
    }
  } catch (...) {
    if (wrapper) {
      finalize_session(wrapper);
      set_unknown_error(wrapper);
    }
  }
  return wrapper;
#endif
}

extern "C" void transport_aria2_destroy(transport_aria2_session raw) {
  auto* s = static_cast<AriaSession*>(raw);
  if (!s) return;
#if TRANSPORT_HAS_LIBARIA2
  s->stop.store(true, std::memory_order_relaxed);
  try {
    if (s->runner.joinable()) s->runner.join();
  } catch (...) {
    // A join failure leaves the worker owning the wrapper; do not free it.
    return;
  }
  finalize_session(s);
#endif
  try {
    delete s;
  } catch (...) {
  }
}

extern "C" int32_t transport_aria2_last_error(
    transport_aria2_session raw, char* out, int32_t capacity) {
  auto* s = static_cast<AriaSession*>(raw);
  if (!s) {
    if (out && capacity > 0) out[0] = 0;
    return 0;
  }
  try {
    std::lock_guard<std::mutex> lock(s->error_mutex);
    const auto length = static_cast<int32_t>(s->error.size());
    const auto copied = capacity <= 0
        ? 0
        : std::min<int32_t>(length, capacity - 1);
    if (out && capacity > 0) {
      std::memcpy(out, s->error.data(), static_cast<size_t>(copied));
      out[copied] = 0;
    }
    return length;
  } catch (...) {
    if (out && capacity > 0) out[0] = 0;
    return -1;
  }
}

extern "C" int32_t transport_aria2_add_uri(
    transport_aria2_session raw,
    const char* uri,
    int32_t uri_length,
    const char* directory,
    int32_t directory_length,
    const char* output,
    int32_t output_length,
    const char* headers,
    int32_t headers_length,
    const char* option_block,
    int32_t option_block_length,
    transport_aria2_gid* gid) {
#if !TRANSPORT_HAS_LIBARIA2
  (void)raw; (void)uri; (void)uri_length; (void)directory;
  (void)directory_length; (void)output; (void)output_length;
  (void)headers; (void)headers_length; (void)option_block;
  (void)option_block_length; (void)gid;
  return -1;
#else
  auto* s = static_cast<AriaSession*>(raw);
  if (!s || !s->session || !gid) return -1;
  try {
    std::unique_lock<std::mutex> lock(s->mutex, std::try_to_lock);
    if (!lock.owns_lock()) {
      set_busy_error(s);
      return -3;
    }
    const auto uri_value = bounded(uri, uri_length);
    const auto directory_value = bounded(directory, directory_length);
    const auto output_value = bounded(output, output_length);
    const auto headers_value = bounded(headers, headers_length);
    const auto options_value = bounded(option_block, option_block_length);
    aria2::KeyVals options;
    if (!directory_value.empty()) options.emplace_back("dir", directory_value);
    if (!output_value.empty()) options.emplace_back("out", output_value);
    add_headers(&options, headers_value);
    add_options(&options, options_value);
    std::vector<std::string> uris{uri_value};
    aria2::A2Gid value = 0;
    const auto result = aria2::addUri(s->session, &value, uris, options);
    if (result != 0) {
      set_error_message(s, "aria2 addUri failed: " + std::to_string(result));
      return result;
    }
    *gid = value;
    return 0;
  } catch (const std::exception& e) {
    set_error(s, e);
    return -1;
  } catch (...) {
    set_unknown_error(s);
    return -1;
  }
#endif
}

extern "C" int32_t transport_aria2_poll(transport_aria2_session raw) {
#if !TRANSPORT_HAS_LIBARIA2
  (void)raw;
  return -1;
#else
  auto* s = static_cast<AriaSession*>(raw);
  if (!s || !s->session) return -1;
  try {
    std::unique_lock<std::mutex> lock(s->mutex, std::try_to_lock);
    if (!lock.owns_lock()) {
      set_busy_error(s);
      return -3;
    }
    return aria2::run(s->session, aria2::RUN_ONCE);
  } catch (const std::exception& e) {
    set_error(s, e);
    return -1;
  } catch (...) {
    set_unknown_error(s);
    return -1;
  }
#endif
}

extern "C" int32_t transport_aria2_status(
    transport_aria2_session raw,
    transport_aria2_gid gid,
    transport_aria2_download_status* out,
    uint8_t* bitfield,
    int32_t capacity) {
#if !TRANSPORT_HAS_LIBARIA2
  (void)raw; (void)gid; (void)out; (void)bitfield; (void)capacity;
  return -1;
#else
  auto* s = static_cast<AriaSession*>(raw);
  if (!s || !s->session || !out || capacity < 0) return -1;
  aria2::DownloadHandle* handle = nullptr;
  try {
    std::unique_lock<std::mutex> lock(s->mutex, std::try_to_lock);
    if (!lock.owns_lock()) {
      set_busy_error(s);
      return -3;
    }
    handle = aria2::getDownloadHandle(s->session, gid);
    if (!handle) {
      set_error_message(s, "aria2 download handle not found");
      return -1;
    }
    out->state = static_cast<int32_t>(handle->getStatus());
    out->error_code = handle->getErrorCode();
    out->connections = handle->getConnections();
    out->piece_length = static_cast<int32_t>(handle->getPieceLength());
    out->piece_count = handle->getNumPieces();
    out->total_length = handle->getTotalLength();
    out->completed_length = handle->getCompletedLength();
    out->download_rate = handle->getDownloadSpeed();
    const auto bits = handle->getBitfield();
    out->bitfield_length = static_cast<int32_t>(bits.size());
    if (capacity < out->bitfield_length ||
        (out->bitfield_length > 0 && !bitfield)) {
      delete_download_handle(handle);
      return capacity < out->bitfield_length ? -2 : -1;
    }
    if (!bits.empty()) {
      std::memcpy(bitfield, bits.data(), bits.size());
    }
    delete_download_handle(handle);
    return 0;
  } catch (const std::exception& e) {
    delete_download_handle(handle);
    set_error(s, e);
    return -1;
  } catch (...) {
    delete_download_handle(handle);
    set_unknown_error(s);
    return -1;
  }
#endif
}

extern "C" int32_t transport_aria2_change_option(
    transport_aria2_session raw,
    transport_aria2_gid gid,
    const char* name,
    int32_t name_length,
    const char* value,
    int32_t value_length) {
#if !TRANSPORT_HAS_LIBARIA2
  (void)raw; (void)gid; (void)name; (void)name_length; (void)value;
  (void)value_length;
  return -1;
#else
  auto* s = static_cast<AriaSession*>(raw);
  if (!s || !s->session) return -1;
  aria2::DownloadHandle* handle = nullptr;
  try {
    std::unique_lock<std::mutex> lock(s->mutex, std::try_to_lock);
    if (!lock.owns_lock()) {
      set_busy_error(s);
      return -3;
    }
    const auto name_value = bounded(name, name_length);
    const auto value_value = bounded(value, value_length);
    aria2::KeyVals options;
    options.emplace_back(name_value, value_value);
    const auto result = aria2::changeOption(s->session, gid, options);
    if (result != 0) {
      set_error_message(s, "aria2 changeOption failed: " + std::to_string(result));
      return result;
    }
    handle = aria2::getDownloadHandle(s->session, gid);
    if (!handle) {
      set_error_message(s, "aria2 download handle not found after changeOption");
      return -1;
    }
    const auto actual = handle->getOption(name_value);
    delete_download_handle(handle);
    if (actual != value_value) {
      set_error_message(s, "aria2 changeOption did not take effect");
      return -1;
    }
    return 0;
  } catch (const std::exception& e) {
    delete_download_handle(handle);
    set_error(s, e);
    return -1;
  } catch (...) {
    delete_download_handle(handle);
    set_unknown_error(s);
    return -1;
  }
#endif
}

extern "C" int32_t transport_aria2_get_option(
    transport_aria2_session raw,
    transport_aria2_gid gid,
    const char* name,
    int32_t name_length,
    char* out,
    int32_t capacity) {
#if !TRANSPORT_HAS_LIBARIA2
  (void)raw; (void)gid; (void)name; (void)name_length; (void)out;
  (void)capacity;
  return -1;
#else
  auto* s = static_cast<AriaSession*>(raw);
  if (!s || !s->session || !out || capacity <= 0) return -1;
  aria2::DownloadHandle* handle = nullptr;
  try {
    std::unique_lock<std::mutex> lock(s->mutex, std::try_to_lock);
    if (!lock.owns_lock()) {
      set_busy_error(s);
      return -3;
    }
    handle = aria2::getDownloadHandle(s->session, gid);
    if (!handle) {
      set_error_message(s, "aria2 download handle not found");
      return -1;
    }
    const auto value = handle->getOption(bounded(name, name_length));
    delete_download_handle(handle);
    const auto n = std::min<size_t>(value.size(), static_cast<size_t>(capacity - 1));
    std::memcpy(out, value.data(), n);
    out[n] = 0;
    return static_cast<int32_t>(value.size());
  } catch (const std::exception& e) {
    delete_download_handle(handle);
    set_error(s, e);
    return -1;
  } catch (...) {
    delete_download_handle(handle);
    set_unknown_error(s);
    return -1;
  }
#endif
}

extern "C" int32_t transport_aria2_remove(
    transport_aria2_session raw, transport_aria2_gid gid) {
#if !TRANSPORT_HAS_LIBARIA2
  (void)raw; (void)gid;
  return -1;
#else
  auto* s = static_cast<AriaSession*>(raw);
  if (!s || !s->session) return -1;
  try {
    std::unique_lock<std::mutex> lock(s->mutex, std::try_to_lock);
    if (!lock.owns_lock()) {
      set_busy_error(s);
      return -3;
    }
    const auto result = aria2::removeDownload(s->session, gid);
    if (result != 0) {
      set_error_message(s, "aria2 removeDownload failed: " + std::to_string(result));
    } else {
      s->paused.erase(gid);
    }
    return result;
  } catch (const std::exception& e) {
    set_error(s, e);
    return -1;
  } catch (...) {
    set_unknown_error(s);
    return -1;
  }
#endif
}

extern "C" int32_t transport_aria2_set_paused(
    transport_aria2_session raw, transport_aria2_gid gid, int32_t paused) {
#if !TRANSPORT_HAS_LIBARIA2
  (void)raw; (void)gid; (void)paused;
  return -1;
#else
  auto* s = static_cast<AriaSession*>(raw);
  if (!s || !s->session) return -1;
  try {
    std::unique_lock<std::mutex> lock(s->mutex, std::try_to_lock);
    if (!lock.owns_lock()) {
      set_busy_error(s);
      return -3;
    }
    const auto result = paused ? aria2::pauseDownload(s->session, gid, true)
                               : aria2::unpauseDownload(s->session, gid);
    if (result != 0) {
      set_error_message(s, "aria2 pause/unpause failed: " + std::to_string(result));
    } else if (paused) {
      s->paused.insert(gid);
    } else {
      s->paused.erase(gid);
    }
    return result;
  } catch (const std::exception& e) {
    set_error(s, e);
    return -1;
  } catch (...) {
    set_unknown_error(s);
    return -1;
  }
#endif
}
