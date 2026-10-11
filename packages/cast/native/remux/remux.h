#ifndef CAST_REMUX_H
#define CAST_REMUX_H
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct RemuxJob RemuxJob;
#if defined(_WIN32)
#define REMUX_API __declspec(dllexport)
#else
#define REMUX_API __attribute__((visibility("default")))
#endif
/* Configure/add before run. Poll/cancel during run; destroy after run returns. */
REMUX_API RemuxJob *remux_create(void);
REMUX_API int remux_configure(RemuxJob *, const char *, const char *, const char *, int64_t);
REMUX_API int remux_keep(RemuxJob *, int);
REMUX_API int remux_subtitle(RemuxJob *, const char *);
/* 0: finalized, 1: canceled, negative: failure. Error text is stable after run. */
REMUX_API int remux_run(RemuxJob *);
REMUX_API int remux_probe(RemuxJob *, const char *);
REMUX_API const char *remux_stream_type(RemuxJob *, int);
REMUX_API const char *remux_stream_codec(RemuxJob *, int);
REMUX_API int remux_stream_attached_picture(RemuxJob *, int);
REMUX_API void remux_cancel(RemuxJob *);
REMUX_API int64_t remux_position(RemuxJob *);
REMUX_API int64_t remux_duration(RemuxJob *);
REMUX_API int64_t remux_packets(RemuxJob *);
REMUX_API const char *remux_error(RemuxJob *);
REMUX_API void remux_destroy(RemuxJob *);
REMUX_API int64_t remux_live_jobs(void);
REMUX_API void *remux_alloc(int64_t);
REMUX_API void remux_free(void *);
#ifdef __cplusplus
}
#endif
#endif
