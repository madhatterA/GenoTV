#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/../../.." && pwd -P)"
mkdir -p "$root/test_media"
ffmpeg -hide_banner -loglevel error -f lavfi -i color=c=black:s=64x64:r=10 \
  -f lavfi -i sine=frequency=440:sample_rate=48000 \
  -f lavfi -i sine=frequency=880:sample_rate=48000 \
  -t 2 -map 0:v -map 1:a -map 2:a -c:v libx264 -threads 1 -c:a aac \
  -y "$root/test_media/remux-small.mkv"
printf '1\n00:00:00,000 --> 00:00:01,500\nremux subtitle proof\n' > "$root/test_media/remux-subtitles.srt"
ffmpeg -hide_banner -loglevel error -i "$root/test_media/remux-subtitles.srt" \
  -c:s copy -y "$root/test_media/remux-subtitles.mkv"
