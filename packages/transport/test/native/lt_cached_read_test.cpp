// Model the pinned disk backend's verified-but-unflushed cache state.
#include "../../src/lt_shim/lt_shim.cpp"
#include <atomic>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <libtorrent/create_torrent.hpp>
#include <libtorrent/disk_interface.hpp>
#include <libtorrent/disk_buffer_holder.hpp>
#include <libtorrent/hasher.hpp>
#include <boost/asio/post.hpp>

namespace lt = libtorrent;
constexpr int piece_size = 16384;

class CachedDisk final : public lt::disk_interface, public lt::buffer_allocator_interface {
 public:
  inline static std::atomic<bool> fail_reads{false};
  explicit CachedDisk(lt::io_context& io) : io_(io) {}
  lt::storage_holder new_torrent(lt::storage_params const& p, std::shared_ptr<void> const&) override {
    auto id = lt::storage_index_t(static_cast<int>(bytes_.size()));
    bytes_.push_back(std::vector<char>(p.files.file_size(lt::file_index_t(0)), p.files.file_name(lt::file_index_t(0))[0]));
    return lt::storage_holder(id, *this);
  }
  void remove_torrent(lt::storage_index_t) override {}
  void async_read(lt::storage_index_t id, lt::peer_request const& r,
      std::function<void(lt::disk_buffer_holder, lt::storage_error const&)> done,
      lt::disk_job_flags_t) override {
    if (fail_reads) {
      boost::asio::post(io_, [done = std::move(done)] {
        done({}, lt::storage_error(lt::error_code(boost::system::errc::io_error, lt::generic_category())));
      });
      return;
    }
    auto* buffer = new char[r.length];
    std::memcpy(buffer, bytes_[static_cast<unsigned int>(id)].data() + r.start, r.length);
    boost::asio::post(io_, [this, buffer, done = std::move(done)]() mutable {
      done(lt::disk_buffer_holder(*this, buffer), {});
    });
  }
  bool async_write(lt::storage_index_t, lt::peer_request const&, char const*,
      std::shared_ptr<lt::disk_observer>, std::function<void(lt::storage_error const&)>,
      lt::disk_job_flags_t) override { throw std::logic_error("fixture must not download"); }
  void async_hash(lt::storage_index_t id, lt::piece_index_t piece, lt::span<lt::sha256_hash>,
      lt::disk_job_flags_t,
      std::function<void(lt::piece_index_t, lt::sha1_hash const&, lt::storage_error const&)> done) override {
    auto const& bytes = bytes_[static_cast<unsigned int>(id)];
    auto hash = lt::hasher(bytes.data() + static_cast<int>(piece) * piece_size, piece_size).final();
    boost::asio::post(io_, [piece, hash, done = std::move(done)] { done(piece, hash, {}); });
  }
  void async_hash2(lt::storage_index_t, lt::piece_index_t, int, lt::disk_job_flags_t,
      std::function<void(lt::piece_index_t, lt::sha256_hash const&, lt::storage_error const&)>) override {
    throw std::logic_error("v1 fixture must not hash v2");
  }
  void async_move_storage(lt::storage_index_t, std::string path, lt::move_flags_t,
      std::function<void(lt::status_t, std::string const&, lt::storage_error const&)> done) override {
    boost::asio::post(io_, [path, done = std::move(done)] { done(lt::status_t{}, path, {}); });
  }
  void async_release_files(lt::storage_index_t, std::function<void()> done) override {
    if (done) boost::asio::post(io_, std::move(done));
  }
  void async_check_files(lt::storage_index_t, lt::add_torrent_params const*,
      lt::aux::vector<std::string, lt::file_index_t>,
      std::function<void(lt::status_t, lt::storage_error const&)> done) override {
    boost::asio::post(io_, [done = std::move(done)] { done(lt::status_t{}, {}); });
  }
  void async_stop_torrent(lt::storage_index_t, std::function<void()> done) override {
    if (done) boost::asio::post(io_, std::move(done));
  }
  void async_rename_file(lt::storage_index_t, lt::file_index_t index, std::string name,
      std::function<void(std::string const&, lt::file_index_t, lt::storage_error const&)> done) override {
    boost::asio::post(io_, [index, name, done = std::move(done)] { done(name, index, {}); });
  }
  void async_delete_files(lt::storage_index_t, lt::remove_flags_t,
      std::function<void(lt::storage_error const&)> done) override {
    boost::asio::post(io_, [done = std::move(done)] { done({}); });
  }
  void async_set_file_priority(lt::storage_index_t,
      lt::aux::vector<lt::download_priority_t, lt::file_index_t> priorities,
      std::function<void(lt::storage_error const&,
          lt::aux::vector<lt::download_priority_t, lt::file_index_t>)> done) override {
    boost::asio::post(io_, [priorities = std::move(priorities), done = std::move(done)] { done({}, priorities); });
  }
  void async_clear_piece(lt::storage_index_t, lt::piece_index_t piece,
      std::function<void(lt::piece_index_t)> done) override {
    boost::asio::post(io_, [piece, done = std::move(done)] { done(piece); });
  }
  void update_stats_counters(lt::counters&) const override {}
  std::vector<lt::open_file_state> get_status(lt::storage_index_t) const override { return {}; }
  void abort(bool) override {}
  void submit_jobs() override {}
  void settings_updated() override {}
  void free_disk_buffer(char* buffer) override { delete[] buffer; }
  void free_multiple_buffers(lt::span<char*> buffers) override {
    for (auto* buffer : buffers) delete[] buffer;
  }
 private:
  lt::io_context& io_;
  std::vector<std::vector<char>> bytes_;
};

int main() {
  auto dir = std::filesystem::temp_directory_path() / ("lt-cached-read-" + std::to_string(getpid()));
  std::filesystem::create_directories(dir);
  auto* s = new Session;
  lt::session_params params;
  params.settings.set_bool(lt::settings_pack::enable_dht, false);
  params.settings.set_bool(lt::settings_pack::enable_lsd, false);
  params.settings.set_str(lt::settings_pack::listen_interfaces, "");
  params.disk_io_constructor = [](lt::io_context& io, lt::settings_interface const&, lt::counters&) {
    return std::make_unique<CachedDisk>(io);
  };
  s->session = std::make_unique<lt::session>(std::move(params));
  live_sessions.insert(s);
  auto add = [&](char fill, bool incomplete = false) {
    std::string name(1, fill);
    const int size = incomplete ? 2 * piece_size : piece_size;
    std::vector<char> bytes(size, fill);
    std::ofstream disk(dir / name, std::ios::binary);
    std::vector<char> zeros(size, 0);
    disk.write(zeros.data(), zeros.size());
    disk.close();
    lt::file_storage files;
    files.add_file(name, size);
    lt::create_torrent creator(files, piece_size, lt::create_torrent::v1_only);
    for (int i = 0; i < size / piece_size; ++i)
      creator.set_hash(lt::piece_index_t(i), lt::hasher(bytes.data() + i * piece_size, piece_size).final());
    lt::add_torrent_params p;
    auto encoded = creator.generate_buf();
    p.ti = std::make_shared<lt::torrent_info>(encoded.data(), static_cast<int>(encoded.size()));
    p.save_path = dir.string();
    if (incomplete) {
      p.flags = {};
      p.have_pieces.resize(2, false);
      p.have_pieces.set_bit(lt::piece_index_t(0));
    } else {
      p.flags = lt::torrent_flags::seed_mode;
      p.verified_pieces.resize(1, true);
    }
    return add_handle(s, s->session->add_torrent(std::move(p)), dir.string());
  };
  auto* a = add('a');
  auto* b = add('b');
  // Queue the other torrent's same-index completion before reading a.
  b->handle.read_piece(lt::piece_index_t(0));
  bool ok = true;
  for (auto [torrent, fill] : {std::pair{a, 'a'}, std::pair{b, 'b'}}) {
    std::vector<uint8_t> got(piece_size);
    const bool verified = transport_lt_torrent_piece_available(torrent, 0) == 1;
    const int count = transport_lt_torrent_read(torrent, 0, 0, got.data(), got.size());
    const bool correct = std::all_of(got.begin(), got.end(), [fill](uint8_t byte) { return byte == fill; });
    std::cout << "verified cached piece " << fill << ": have=" << verified << " read=" << count
              << " first=" << int(got[0]) << " expected=" << int(fill)
              << " " << (verified && count == piece_size && correct ? "PASS" : "FAIL") << '\n';
    ok &= verified && count == piece_size && correct;
  }
  auto* c = add('c', true);
  const bool c_available = transport_lt_torrent_piece_available(c, 0) == 1;
  transport_lt_torrent_set_piece_deadline(c, 1, 0);
  transport_lt_torrent_clear_piece_deadlines(c);
  c->handle.status(); // Drain the earlier async deadline commands on the network thread.
  std::vector<lt::alert*> alerts;
  s->session->pop_alerts(&alerts);
  int cancelled_reads = 0;
  for (auto* alert : alerts)
    if (auto* read = lt::alert_cast<lt::read_piece_alert>(alert))
      if (read->handle == c->handle && read->error) ++cancelled_reads;
  std::vector<uint8_t> c_bytes(piece_size);
  const int c_count = transport_lt_torrent_read(c, 0, 0, c_bytes.data(), c_bytes.size());
  const bool c_correct = std::all_of(c_bytes.begin(), c_bytes.end(), [](uint8_t byte) { return byte == 'c'; });
  const bool deadline_ok = c_available && cancelled_reads == 0 && c_count == piece_size && c_correct;
  std::cout << "deadline scheduling does not request piece buffers: canceled=" << cancelled_reads
            << " have=" << c_available << " read=" << c_count << " " << (deadline_ok ? "PASS" : "FAIL") << '\n';
  ok &= deadline_ok;
  // An outside caller's canceled deadline for piece 1 must not fail a piece 0 read.
  c->handle.set_piece_deadline(lt::piece_index_t(1), 0, lt::torrent_handle::alert_when_available);
  c->handle.clear_piece_deadlines();
  c->handle.status();
  const int unrelated_count = transport_lt_torrent_read(c, 0, 0, c_bytes.data(), c_bytes.size());
  const bool unrelated_ok = unrelated_count == piece_size
      && std::all_of(c_bytes.begin(), c_bytes.end(), [](uint8_t byte) { return byte == 'c'; });
  std::cout << "unrelated canceled piece ignored: " << (unrelated_ok ? "PASS" : "FAIL") << '\n';
  ok &= unrelated_ok;
  CachedDisk::fail_reads = true;
  const int failed_count = transport_lt_torrent_read(c, 0, 0, c_bytes.data(), c_bytes.size());
  const bool error_ok = failed_count == -1 && s->error.find("torrent piece 0 read failed") != std::string::npos;
  std::cout << "requested read error surfaced: read=" << failed_count << " " << s->error
            << " " << (error_ok ? "PASS" : "FAIL") << '\n';
  ok &= error_ok;
  transport_lt_session_destroy(s);
  std::filesystem::remove_all(dir);
  return ok ? 0 : 1;
}
