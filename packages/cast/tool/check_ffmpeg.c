#include <libavcodec/avcodec.h>
#include <libavformat/avformat.h>
#include <libavutil/opt.h>
#include <stdio.h>

int main(void)
{
    void *opaque = NULL;
    const AVCodec *codec;
    while ((codec = av_codec_iterate(&opaque)) != NULL) {
        if (av_codec_is_encoder(codec)) {
            fputs("FAIL: encoder implementation registered\n", stderr);
            return 1;
        }
    }
    if (!avcodec_find_decoder(AV_CODEC_ID_H264) ||
        !avcodec_find_decoder(AV_CODEC_ID_HEVC) ||
        !avcodec_find_decoder(AV_CODEC_ID_AAC) ||
        !avcodec_find_decoder(AV_CODEC_ID_AC3) ||
        !avcodec_find_decoder(AV_CODEC_ID_EAC3)) {
        fputs("FAIL: required probe decoder absent\n", stderr);
        return 1;
    }
    if (avcodec_find_encoder(AV_CODEC_ID_H264) != NULL ||
        avcodec_find_encoder(AV_CODEC_ID_HEVC) != NULL ||
        avcodec_find_encoder(AV_CODEC_ID_AAC) != NULL ||
        avcodec_find_encoder(AV_CODEC_ID_AC3) != NULL ||
        avcodec_find_encoder(AV_CODEC_ID_EAC3) != NULL) {
        fputs("FAIL: encoder found\n", stderr);
        return 1;
    }
    AVFormatContext *output = NULL;
    int result = avformat_alloc_output_context2(&output, NULL, "mp4", NULL);
    if (result < 0 || output == NULL) {
        fputs("FAIL: mp4 output allocation\n", stderr);
        return 1;
    }
    result = av_opt_set(output->priv_data, "movflags",
                        "frag_keyframe+empty_moov+default_base_moof+delay_moov", 0);
    avformat_free_context(output);
    if (result < 0) {
        fputs("FAIL: fragmented mp4 flags\n", stderr);
        return 1;
    }
    puts("PASS: codec registry contains zero encoders; required probe decoders present");
    puts("PASS: H264/HEVC/AAC/AC3/EAC3 encoder lookups return NULL");
    puts("PASS: MP4 muxer accepts fragment flags (no remux claimed)");
    return 0;
}
