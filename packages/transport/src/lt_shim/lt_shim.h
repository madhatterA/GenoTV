#ifndef TRANSPORT_LT_SHIM_H_
#define TRANSPORT_LT_SHIM_H_
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef void* transport_lt_session;
typedef void* transport_lt_torrent;
typedef struct transport_lt_file_info { int64_t offset; int64_t size; int32_t path_length; int32_t is_pad; } transport_lt_file_info;
/* Live torrent counters (libtorrent torrent_status): rates in bytes/s, num_complete/num_incomplete are the tracker's scrape (-1 when it sent none). */
typedef struct transport_lt_stats { int64_t total_upload; float distributed_copies; int32_t upload_rate; int32_t num_seeds; int32_t num_peers; int32_t num_complete; int32_t num_incomplete; int32_t num_pieces; } transport_lt_stats;
typedef struct transport_lt_alert { int32_t kind; int32_t piece; int32_t peers; int32_t error_code; int32_t message_length; uintptr_t torrent; } transport_lt_alert;
enum { TRANSPORT_LT_ALERT_METADATA=1, TRANSPORT_LT_ALERT_PIECE_FINISHED, TRANSPORT_LT_ALERT_TORRENT_ERROR, TRANSPORT_LT_ALERT_FILE_ERROR, TRANSPORT_LT_ALERT_TRACKER_ERROR, TRANSPORT_LT_ALERT_TORRENT_FINISHED, TRANSPORT_LT_ALERT_STATE_CHANGED, TRANSPORT_LT_ALERT_PEER_DISCONNECTED, TRANSPORT_LT_ALERT_RESUME_DATA, TRANSPORT_LT_ALERT_ALERTS_DROPPED, TRANSPORT_LT_ALERT_TORRENT_REMOVED };
transport_lt_session transport_lt_session_create(void);
void transport_lt_session_destroy(transport_lt_session session);
int32_t transport_lt_session_last_error(transport_lt_session session, char* out, int32_t capacity);
transport_lt_torrent transport_lt_add_magnet(transport_lt_session session, const char* magnet, int32_t magnet_length, const char* save_path, int32_t save_path_length, int32_t payload_paused);
transport_lt_torrent transport_lt_add_torrent(transport_lt_session session, const uint8_t* data, int32_t data_length, const char* save_path, int32_t save_path_length, int32_t payload_paused);
transport_lt_torrent transport_lt_load_resume(transport_lt_session session, const uint8_t* data, int32_t data_length, const char* save_path, int32_t save_path_length, int32_t payload_paused);
int32_t transport_lt_torrent_remove(transport_lt_session session, transport_lt_torrent torrent, int32_t delete_files);
void transport_lt_torrent_close(transport_lt_torrent torrent);
int32_t transport_lt_torrent_close_complete(transport_lt_torrent torrent);
int32_t transport_lt_torrent_metadata_ready(transport_lt_torrent torrent);
int32_t transport_lt_torrent_file_count(transport_lt_torrent torrent);
int32_t transport_lt_torrent_piece_length(transport_lt_torrent torrent);
int32_t transport_lt_torrent_piece_count(transport_lt_torrent torrent);
int32_t transport_lt_torrent_info_hash(transport_lt_torrent torrent, char* out, int32_t capacity);
int32_t transport_lt_torrent_file_info(transport_lt_torrent torrent, int32_t index, transport_lt_file_info* out, char* path, int32_t path_capacity);
int32_t transport_lt_torrent_piece_available(transport_lt_torrent torrent, int32_t piece);
int32_t transport_lt_torrent_copy_piece_bitfield(transport_lt_torrent torrent, uint8_t* out, int32_t capacity);
int32_t transport_lt_torrent_read(transport_lt_torrent torrent, int32_t file_index, int64_t file_offset, uint8_t* out, int32_t capacity);
int32_t transport_lt_torrent_prioritize_files(transport_lt_torrent torrent, const uint8_t* priorities, int32_t count);
int32_t transport_lt_torrent_file_priority(transport_lt_torrent torrent, int32_t index);
int32_t transport_lt_torrent_set_piece_priority(transport_lt_torrent torrent, int32_t piece, int32_t priority);
int32_t transport_lt_torrent_set_piece_deadline(transport_lt_torrent torrent, int32_t piece, int32_t deadline_ms);
int32_t transport_lt_torrent_clear_piece_deadlines(transport_lt_torrent torrent);
int32_t transport_lt_torrent_status(transport_lt_torrent torrent, int32_t* peers, int32_t* state, int64_t* downloaded, int64_t* total, int32_t* download_rate);
int32_t transport_lt_torrent_stats(transport_lt_torrent torrent, transport_lt_stats* out);
int32_t transport_lt_pop_alerts(transport_lt_session session, transport_lt_alert* out, int32_t capacity, char* messages, int32_t messages_capacity);
int32_t transport_lt_torrent_save_resume(transport_lt_torrent torrent, uint8_t* out, int32_t capacity);
int32_t transport_lt_torrent_load_resume(transport_lt_session session, transport_lt_torrent torrent, const uint8_t* data, int32_t data_length);
/* Forgets the given downloaded pieces (ascending) and frees their disk blocks; returns the count or a negative error. */
int32_t transport_lt_torrent_evict_pieces(transport_lt_session session, transport_lt_torrent torrent, const int32_t* pieces, int32_t count);

int32_t transport_lt_torrent_initialize_download(transport_lt_session session, transport_lt_torrent torrent, int32_t file, int32_t first_piece, int32_t end_piece);
/* Session settings by libtorrent name ("name=value" lines; int, bool or string by the setting's type). Returns the count applied or a negative error. */
int32_t transport_lt_session_set(transport_lt_session session, const char* block, int32_t block_length);
/* Current value of one session setting as text; returns its length or a negative error. */
int32_t transport_lt_session_get(transport_lt_session session, const char* name, int32_t name_length, char* out, int32_t capacity);
/* Per-torrent options ("key=value" lines): download_limit, upload_limit, max_connections, pex (0/1), tracker (URL, appended). */
int32_t transport_lt_torrent_set(transport_lt_torrent torrent, const char* block, int32_t block_length);
/* Current value of one per-torrent option as text (tracker: newline-joined URLs; total_upload / total_download: all-time bytes); returns its length or a negative error. */
int32_t transport_lt_torrent_get(transport_lt_torrent torrent, const char* name, int32_t name_length, char* out, int32_t capacity);
/* Returns 0 or a negative error. Offsets are rounded inward to the volume block size. */
int32_t transport_lt_fs_punch_hole(const char* path, int32_t path_len, int64_t offset, int64_t length);
/* Bytes actually allocated in [offset, offset+length) (length < 0: to end of file); negative on error. */
int64_t transport_lt_fs_allocated_bytes(const char* path, int32_t path_len, int64_t offset, int64_t length);
/* Bytes available to this user on the volume holding path; negative on error. */
int64_t transport_lt_fs_free_bytes(const char* path, int32_t path_len);
#ifdef __cplusplus
}
#endif
#endif
