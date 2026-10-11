# Native torrent engine

`lt_shim` is the only C ABI around libtorrent. It is pinned to libtorrent-rasterbar
2.1.1 and accepts a `TRANSPORT_LIBTORRENT_ROOT` prefix at build time; production
bundles must provide that prefix for each target architecture. The app never loads
Homebrew paths at runtime.

The ABI uses opaque session/torrent handles. Strings and byte buffers are caller-owned;
all output is copied before a call returns. `transport_lt_pop_alerts` drains alerts on
the Dart polling thread; libtorrent worker threads never invoke Dart. `read` reads
the selected file on disk after Dart has verified piece availability.

Libtorrent is BSD-3-Clause. Boost and OpenSSL are transitive dependencies and must be
included in each platform's release notices; see the pinned dependency manifest in
`research/technical/torrent/libtorrent/LICENSE` and the platform build output.
