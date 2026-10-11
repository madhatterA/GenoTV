#include "remux.h"
#include <errno.h>
#if !defined(_WIN32)
#include <dirent.h>
#include <unistd.h>
#endif
#include <libavutil/time.h>
#include <fcntl.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <libavformat/avformat.h>
#include <libavutil/mem.h>
#if defined(_WIN32)
#include "windows_files.h"
#endif

struct RemuxJob {
    char *input, *output, *format;
    char **subtitles;
    int *keep, keep_count, subtitle_count, started;
    int64_t max_us, deadline;
    AVFormatContext *probe;
    atomic_int canceled;
    atomic_int_fast64_t position, duration, packets;
    char error[256];
};

typedef struct {
    AVFormatContext *context;
    AVPacket *packet;
    int *mapping, ready, finished;
} Input;

static atomic_int_fast64_t live_jobs;

static int fail(RemuxJob *job, int code, const char *action) {
    char detail[AV_ERROR_MAX_STRING_SIZE];
    av_strerror(code, detail, sizeof(detail));
    snprintf(job->error, sizeof(job->error), "%s: %s", action, detail);
    return code;
}

static int local_path(const char *path) {
    if (!path || !*path || strstr(path, "://")) return 0;
#if defined(_WIN32)
    if (((path[0] >= 'A' && path[0] <= 'Z') || (path[0] >= 'a' && path[0] <= 'z')) && path[1] == ':' &&
        (path[2] == '/' || path[2] == '\\')) return 1;
#endif
    const char *colon = strchr(path, ':');
    const char *slash = strchr(path, '/');
    return !colon || (slash && slash < colon);
}

static int input_path(const char *path) {
    if (path && !strncmp(path, "http://", 7)) return 1;
#if defined(_WIN32)
    return local_path(path) && remux_windows_regular_file(path);
#else
    struct stat info;
    return local_path(path) && stat(path, &info) == 0 && S_ISREG(info.st_mode);
#endif
}

static char *hls_directory(const char *path) {
    const char *slash = strrchr(path, '/');
#if defined(_WIN32)
    const char *backslash = strrchr(path, '\\');
    if (backslash && (!slash || backslash > slash)) slash = backslash;
#endif
    if (!slash || slash == path || !slash[1]) return NULL;
    return strndup(path, (size_t)(slash - path));
}

static void remove_hls(const char *directory) {
#if defined(_WIN32)
    remux_windows_remove_hls(directory);
#else
    DIR *dir = opendir(directory);
    if (!dir) return;
    struct dirent *entry;
    while ((entry = readdir(dir))) {
        if (!strcmp(entry->d_name, ".") || !strcmp(entry->d_name, "..")) continue;
        unlinkat(dirfd(dir), entry->d_name, 0);
    }
    closedir(dir);
    rmdir(directory);
#endif
}

/* Multi-file muxers cannot honor this API's exclusive single-output ownership. */
static int single_file_format(const char *format) {
    return format && (!strcmp(format, "mp4") || !strcmp(format, "mov") ||
                      !strcmp(format, "matroska") || !strcmp(format, "mpegts"));
}

RemuxJob *remux_create(void) {
    RemuxJob *job = calloc(1, sizeof(*job));
    if (job) {
        atomic_init(&job->canceled, 0);
        atomic_init(&job->position, 0);
        atomic_init(&job->duration, 0);
        atomic_init(&job->packets, 0);
        atomic_fetch_add(&live_jobs, 1);
    }
    return job;
}

int remux_configure(RemuxJob *job, const char *input, const char *output,
                    const char *format, int64_t max_us) {
    if (!job) return AVERROR(EINVAL);
    if (job->started || job->input || !input_path(input) || !local_path(output) ||
        (!single_file_format(format) && (!format || strcmp(format, "hls"))) || max_us < 0)
        return fail(job, AVERROR(EINVAL), "Invalid remux configuration");
#if defined(_WIN32)
    if (remux_windows_path_exists(output) == 0)
#else
    struct stat destination;
    if (lstat(output, &destination) == 0)
#endif
        return fail(job, AVERROR(EEXIST), "Output already exists");
    if (errno != ENOENT) return fail(job, AVERROR(errno), "Cannot inspect output");
    char *in = strdup(input), *out = strdup(output), *fmt = strdup(format);
    if (!in || !out || !fmt) {
        free(in); free(out); free(fmt);
        return fail(job, AVERROR(ENOMEM), "Copy configuration");
    }
    job->input = in; job->output = out; job->format = fmt; job->max_us = max_us;
    job->error[0] = '\0';
    return 0;
}

int remux_keep(RemuxJob *job, int index) {
    if (!job) return AVERROR(EINVAL);
    if (job->started || !job->input || index < 0)
        return fail(job, AVERROR(EINVAL), "Invalid kept stream");
    for (int i = 0; i < job->keep_count; i++)
        if (job->keep[i] == index) return 0;
    int *list = realloc(job->keep, (size_t)(job->keep_count + 1) * sizeof(*list));
    if (!list) return fail(job, AVERROR(ENOMEM), "Add kept stream");
    job->keep = list;
    job->keep[job->keep_count++] = index;
    return 0;
}

int remux_subtitle(RemuxJob *job, const char *path) {
    if (!job) return AVERROR(EINVAL);
    if (job->started || !job->input || !input_path(path))
        return fail(job, AVERROR(EINVAL), "Invalid subtitle input");
    char *copy = strdup(path);
    if (!copy) return fail(job, AVERROR(ENOMEM), "Copy subtitle path");
    char **list = realloc(job->subtitles, (size_t)(job->subtitle_count + 1) * sizeof(*list));
    if (!list) { free(copy); return fail(job, AVERROR(ENOMEM), "Add subtitle"); }
    job->subtitles = list;
    job->subtitles[job->subtitle_count++] = copy;
    return 0;
}

static int interrupted(void *opaque) {
    RemuxJob *job = opaque;
    return atomic_load(&job->canceled) ||
           (job->deadline && av_gettime_relative() >= job->deadline);
}

static int write_bytes(void *opaque, const uint8_t *buffer, int size) {
    int fd = *(int *)opaque, offset = 0;
    while (offset < size) {
        ssize_t count = write(fd, buffer + offset, (size_t)(size - offset));
        if (count < 0) { if (errno == EINTR) continue; return AVERROR(errno); }
        if (!count) return AVERROR(EIO);
        offset += (int)count;
    }
    return size;
}

static int64_t seek_bytes(void *opaque, int64_t offset, int whence) {
    int fd = *(int *)opaque;
    if (whence == AVSEEK_SIZE) {
        struct stat info;
        return fstat(fd, &info) < 0 ? AVERROR(errno) : info.st_size;
    }
    off_t result = lseek(fd, (off_t)offset, whence & ~AVSEEK_FORCE);
    return result < 0 ? AVERROR(errno) : result;
}

static int open_input(RemuxJob *job, Input *input, const char *path) {
    input->context = avformat_alloc_context();
    if (!input->context) return AVERROR(ENOMEM);
    input->context->interrupt_callback = (AVIOInterruptCB){interrupted, job};
    /* Probe real decoder metadata, bounded to two seconds of input media. */
    input->context->max_analyze_duration = 2 * AV_TIME_BASE;
    AVDictionary *options = NULL;
    int result = av_dict_set(&options, "protocol_whitelist", "file,http,tcp", 0);
    if (result < 0) { av_dict_free(&options); return result; }
    job->deadline = av_gettime_relative() + 5 * AV_TIME_BASE;
    result = avformat_open_input(&input->context, path, NULL, &options);
    av_dict_free(&options);
    if (result < 0) return result;
    result = avformat_find_stream_info(input->context, NULL);
    if (result < 0) return result;
    job->deadline = 0;
    input->mapping = av_malloc_array(input->context->nb_streams, sizeof(int));
    input->packet = av_packet_alloc();
    if (!input->mapping || !input->packet) return AVERROR(ENOMEM);
    for (unsigned i = 0; i < input->context->nb_streams; i++) input->mapping[i] = -1;
    return 0;
}

int remux_probe(RemuxJob *job, const char *path) {
    if (!job || job->started || !input_path(path)) return AVERROR(EINVAL);
    job->started = 1;
    Input input = {0};
    int result = open_input(job, &input, path);
    av_free(input.mapping);
    av_packet_free(&input.packet);
    if (result < 0) {
        avformat_close_input(&input.context);
        return fail(job, result, "Probe input");
    }
    job->probe = input.context;
    return (int)job->probe->nb_streams;
}

const char *remux_stream_type(RemuxJob *job, int index) {
    if (!job || !job->probe || (unsigned)index >= job->probe->nb_streams) return "unknown";
    const char *type = av_get_media_type_string(job->probe->streams[index]->codecpar->codec_type);
    return type ? type : "unknown";
}

int remux_stream_attached_picture(RemuxJob *job, int index) {
    if (!job || !job->probe || (unsigned)index >= job->probe->nb_streams) return 0;
    return !!(job->probe->streams[index]->disposition & AV_DISPOSITION_ATTACHED_PIC);
}

const char *remux_stream_codec(RemuxJob *job, int index) {
    if (!job || !job->probe || (unsigned)index >= job->probe->nb_streams) return "unknown";
    return avcodec_get_name(job->probe->streams[index]->codecpar->codec_id);
}

static int add_stream(AVFormatContext *output, Input *input, int index) {
    AVStream *source = input->context->streams[index];
    AVStream *destination = avformat_new_stream(output, NULL);
    if (!destination) return AVERROR(ENOMEM);
    int result = avcodec_parameters_copy(destination->codecpar, source->codecpar);
    if (result < 0) return result;
    destination->codecpar->codec_tag = 0;
    destination->time_base = source->time_base;
    destination->disposition = source->disposition;
    result = av_dict_copy(&destination->metadata, source->metadata, 0);
    if (result < 0) return result;
    input->mapping[index] = destination->index;
    return 0;
}

static int64_t packet_time(Input *input) {
    AVPacket *packet = input->packet;
    int64_t timestamp = packet->dts != AV_NOPTS_VALUE ? packet->dts : packet->pts;
    if (timestamp == AV_NOPTS_VALUE) return 0;
    return av_rescale_q(timestamp, input->context->streams[packet->stream_index]->time_base,
                        AV_TIME_BASE_Q);
}

static int next_packet(Input *input, RemuxJob *job) {
    while (!input->ready && !input->finished) {
        if (interrupted(job)) return AVERROR_EXIT;
        job->deadline = av_gettime_relative() + 5 * AV_TIME_BASE;
        int result = av_read_frame(input->context, input->packet);
        job->deadline = 0;
        if (result == AVERROR_EOF) { input->finished = 1; break; }
        if (result < 0) return result;
        if (input->mapping[input->packet->stream_index] < 0) {
            av_packet_unref(input->packet);
            continue;
        }
        int64_t start = input->context->start_time == AV_NOPTS_VALUE ? 0 : input->context->start_time;
        if (job->max_us && packet_time(input) - start >= job->max_us) {
            av_packet_unref(input->packet);
            input->finished = 1;
            break;
        }
        input->ready = 1;
    }
    return 0;
}

int remux_run(RemuxJob *job) {
    if (!job) return AVERROR(EINVAL);
    if (job->started || !job->input || !job->keep_count)
        return fail(job, AVERROR(EINVAL), "Remux requires configuration and kept streams");
    job->started = 1;
    job->error[0] = '\0';
    int count = job->subtitle_count + 1, result = 0, fd = -1, owned = 0;
    const char *action = "Allocate remux resources";
    Input *inputs = calloc((size_t)count, sizeof(*inputs));
    char *directory = !strcmp(job->format, "hls") ? hls_directory(job->output) : NULL;
    int is_hls = !strcmp(job->format, "hls");
    AVFormatContext *output = NULL;
    AVIOContext *io = NULL;
    AVDictionary *options = NULL;
    if (!inputs) { result = AVERROR(ENOMEM); goto end; }
    action = "Open input";
    for (int i = 0; i < count; i++) {
        result = open_input(job, &inputs[i], i ? job->subtitles[i - 1] : job->input);
        if (result < 0) goto end;
    }
    atomic_store(&job->duration, inputs[0].context->duration == AV_NOPTS_VALUE ? 0 : inputs[0].context->duration);
    action = "Create output streams";
    result = avformat_alloc_output_context2(&output, NULL, job->format, job->output);
    if (result < 0 || !output) { if (result >= 0) result = AVERROR(ENOMEM); goto end; }
    output->interrupt_callback = (AVIOInterruptCB){interrupted, job};
    output->strict_std_compliance = FF_COMPLIANCE_UNOFFICIAL;
    result = av_dict_copy(&output->metadata, inputs[0].context->metadata, 0);
    if (result < 0) goto end;
    for (int i = 0; i < job->keep_count; i++) {
        int index = job->keep[i];
        if ((unsigned)index >= inputs[0].context->nb_streams) { result = AVERROR(EINVAL); goto end; }
        result = add_stream(output, &inputs[0], index);
        if (result < 0) goto end;
    }
    for (int i = 1; i < count; i++) {
        int added = 0;
        for (unsigned s = 0; s < inputs[i].context->nb_streams; s++) {
            if (inputs[i].context->streams[s]->codecpar->codec_type != AVMEDIA_TYPE_SUBTITLE) continue;
            result = add_stream(output, &inputs[i], (int)s);
            if (result < 0) goto end;
            added++;
        }
        if (!added) { result = AVERROR(EINVAL); goto end; }
    }
    if (interrupted(job)) { result = AVERROR_EXIT; goto end; }
    action = "Create exclusive output";
    if (is_hls) {
        if (!directory) { result = AVERROR(EINVAL); goto end; }
        if (mkdir(directory, 0700) < 0) { result = AVERROR(errno); goto end; }
        owned = 1;
        result = av_dict_set(&options, "hls_flags", "temp_file", 0);
        if (result >= 0) result = av_dict_set(&options, "hls_time", "1", 0);
        if (result >= 0) result = av_dict_set(&options, "hls_list_size", "0", 0);
        if (result < 0) goto end;
    } else {
        fd = open(job->output, O_WRONLY | O_CREAT | O_EXCL, 0600);
        if (fd < 0) { result = AVERROR(errno); goto end; }
        owned = 1;
        unsigned char *buffer = av_malloc(32768);
        if (!buffer) { result = AVERROR(ENOMEM); goto end; }
        io = avio_alloc_context(buffer, 32768, 1, &fd, NULL, write_bytes, seek_bytes);
        if (!io) { av_free(buffer); result = AVERROR(ENOMEM); goto end; }
        output->pb = io;
        output->flags |= AVFMT_FLAG_CUSTOM_IO;
    }
    if (!strcmp(job->format, "mp4")) {
        result = av_dict_set(&options, "movflags", "frag_keyframe+empty_moov+default_base_moof+delay_moov+write_colr", 0);
        if (result < 0) goto end;
    }
    action = "Write output header (stream-copy codec compatibility)";
    result = avformat_write_header(output, &options);
    if (result < 0) goto end;
    action = "Copy packets";
    for (;;) {
        int selected = -1;
        for (int i = 0; i < count; i++) {
            result = next_packet(&inputs[i], job);
            if (result < 0) goto end;
            if (inputs[i].ready && (selected < 0 || packet_time(&inputs[i]) < packet_time(&inputs[selected])))
                selected = i;
        }
        if (selected < 0) break;
        Input *input = &inputs[selected];
        AVPacket *packet = input->packet;
        int index = packet->stream_index;
        int64_t time = packet_time(input);
        int64_t start = input->context->start_time == AV_NOPTS_VALUE ? 0 : input->context->start_time;
        packet->stream_index = input->mapping[index];
        av_packet_rescale_ts(packet, input->context->streams[index]->time_base,
                            output->streams[packet->stream_index]->time_base);
        packet->pos = -1;
        result = av_interleaved_write_frame(output, packet);
        input->ready = 0;
        if (result < 0) goto end;
        if (io) {
            avio_flush(io);
            if (io->error < 0) { result = io->error; goto end; }
        }
        atomic_fetch_add(&job->packets, 1);
        if (selected == 0 && time - start > atomic_load(&job->position))
            atomic_store(&job->position, time - start);
    }
    if (interrupted(job)) { result = AVERROR_EXIT; goto end; }
    action = "Finalize output";
    result = av_write_trailer(output);
    if (result >= 0 && io) {
        avio_flush(io);
        if (io->error < 0) result = io->error;
    }
end:
    av_dict_free(&options);
    if (inputs) {
        for (int i = 0; i < count; i++) {
            av_packet_free(&inputs[i].packet);
            av_free(inputs[i].mapping);
            avformat_close_input(&inputs[i].context);
        }
        free(inputs);
    }
    if (output) output->pb = NULL;
    avformat_free_context(output);
    if (io) { av_freep(&io->buffer); avio_context_free(&io); }
    if (fd >= 0 && close(fd) < 0 && result >= 0) result = AVERROR(errno);
    if (atomic_load(&job->canceled)) result = AVERROR_EXIT;
    if (result < 0 && owned) {
        if (is_hls) remove_hls(directory); else unlink(job->output);
    }
    free(directory);
    if (result == AVERROR_EXIT && atomic_load(&job->canceled)) {
        snprintf(job->error, sizeof(job->error), "Remux canceled");
        return 1;
    }
    return result < 0 ? fail(job, result, action) : 0;
}

void remux_cancel(RemuxJob *job) { if (job) atomic_store(&job->canceled, 1); }
int64_t remux_position(RemuxJob *job) { return job ? atomic_load(&job->position) : 0; }
int64_t remux_duration(RemuxJob *job) { return job ? atomic_load(&job->duration) : 0; }
int64_t remux_packets(RemuxJob *job) { return job ? atomic_load(&job->packets) : 0; }
const char *remux_error(RemuxJob *job) { return job ? job->error : "Invalid remux job"; }
void remux_destroy(RemuxJob *job) {
    if (!job) return;
    avformat_close_input(&job->probe);
    free(job->input); free(job->output); free(job->format); free(job->keep);
    for (int i = 0; i < job->subtitle_count; i++) free(job->subtitles[i]);
    free(job->subtitles);
    free(job);
    atomic_fetch_sub(&live_jobs, 1);
}
int64_t remux_live_jobs(void) { return atomic_load(&live_jobs); }
void *remux_alloc(int64_t bytes) { return bytes > 0 && (uint64_t)bytes <= SIZE_MAX ? malloc((size_t)bytes) : NULL; }
void remux_free(void *pointer) { free(pointer); }
