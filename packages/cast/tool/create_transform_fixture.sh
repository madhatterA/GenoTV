#!/usr/bin/env bash
# Test-only codec fixture and longer stream-copy input; no playback or downloads.
set -euo pipefail
root="$(cd "$(dirname "$0")/../../.." && pwd)"
ffmpeg -v error -y -i "$root/test_media/remux-small.mkv" \
  -map 0 -c:v copy -c:a:0 ac3 -c:a:1 copy "$root/test_media/transform-audio.mkv"
ffmpeg -v error -y -stream_loop 3 -i "$root/test_media/transform-audio.mkv" \
  -t 8 -map 0 -c copy "$root/test_media/transform-streaming.mkv"
