#ifndef TRANSPORT_ARIA2_SHIM_H_
#define TRANSPORT_ARIA2_SHIM_H_
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

// Memory ownership: all out-parameters are caller-owned buffers. The shim
// copies aria2 data into those buffers and never returns an internal pointer.
// transport_aria2_destroy owns the opaque session handle. Dart attaches a
// NativeFinalizer as a backstop and calls destroy explicitly during dispose.
// aria2 libraryInit/libraryDeinit are process-lifetime one-time operations;
// sessions do not initialize or deinitialize the global library.
//
// transport_aria2_status writes the fixed-layout status struct and bitfield.
// If bitfield_capacity is smaller than the required byte count it writes the
// required count to status.bitfield_length and returns -2; the caller must
// allocate that many bytes and call again. A non-null bitfield is required
// whenever the required count is non-zero.
//
// Threading: one native worker owns aria2::run(RUN_ONCE). All other calls
// try the same per-session mutex and never call network I/O themselves. A
// concurrent call returns -3 (busy) immediately; Dart retries asynchronously.
// transport_aria2_poll remains for host/test harnesses and must not be called
// from the Dart main isolate because aria2::run(RUN_ONCE) may wait up to 1s.
typedef void* transport_aria2_session;
typedef uint64_t transport_aria2_gid;
typedef struct transport_aria2_download_status {
  int32_t state;
  int32_t error_code;
  int32_t connections;
  int32_t piece_length;
  int32_t piece_count;
  int64_t total_length;
  int64_t completed_length;
  int32_t download_rate;
  int32_t bitfield_length;
} transport_aria2_download_status;

transport_aria2_session transport_aria2_create(void);
void transport_aria2_destroy(transport_aria2_session session);
int32_t transport_aria2_last_error(
    transport_aria2_session session, char* out, int32_t capacity);
int32_t transport_aria2_add_uri(
    transport_aria2_session session,
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
    transport_aria2_gid* gid);
int32_t transport_aria2_poll(transport_aria2_session session);
int32_t transport_aria2_status(
    transport_aria2_session session,
    transport_aria2_gid gid,
    transport_aria2_download_status* out,
    uint8_t* bitfield,
    int32_t bitfield_capacity);
int32_t transport_aria2_change_option(
    transport_aria2_session session,
    transport_aria2_gid gid,
    const char* name,
    int32_t name_length,
    const char* value,
    int32_t value_length);
/* Current value of one per-download option as text; returns its length or a negative error. */
int32_t transport_aria2_get_option(
    transport_aria2_session session,
    transport_aria2_gid gid,
    const char* name,
    int32_t name_length,
    char* out,
    int32_t capacity);
int32_t transport_aria2_remove(
    transport_aria2_session session, transport_aria2_gid gid);
int32_t transport_aria2_set_paused(
    transport_aria2_session session, transport_aria2_gid gid, int32_t paused);

#ifdef __cplusplus
}
#endif
#endif
