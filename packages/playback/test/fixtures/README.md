# Playback fixtures

`Butterfly-209.mp4` is copied from the retained media_kit example at
`research/technical/playback/media_kit/video_player_media_kit/example/assets/Butterfly-209.mp4`,
from the `media_kit` pinned source row in `research/README.md` (commit `c533e446755f`).

`sample.srt` and `sample.ass` are minimal hand-authored legal subtitle fixtures. The generated
multi-track fixture was created with Homebrew ffmpeg 9.0.1:

```text
ffmpeg -f lavfi -i testsrc2=size=320x180:rate=24000/1001:duration=4 \
  -f lavfi -i sine=frequency=440:sample_rate=48000:duration=4 \
  -f lavfi -i sine=frequency=880:sample_rate=48000:duration=4 \
  -i sample.srt -i sample.ass -i chapters.ffmeta -map 0:v -map 1:a -map 2:a \
  -map 3:0 -map 4:0 -map_metadata 5 -map_chapters 5 -c:v libx264 \
  -pix_fmt yuv420p -r 24000/1001 -c:a aac -t 4 -c:s copy multi_track_23976.mkv
```

It contains H.264 at 24000/1001 fps, two AAC audio tracks, SRT and ASS subtitle tracks,
and two titled chapters.

Subtitle fixtures are UTF-8. media_kit/libmpv performs its normal subtitle charset
autodetection; media_kit 1.2.6 does not expose a typed `sub-codepage` setter, so playback does
not guess or rewrite Windows-125x files. Callers needing a legacy codepage must provide a
UTF-8 conversion before loading.
