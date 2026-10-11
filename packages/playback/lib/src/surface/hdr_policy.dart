/// What the native video surface is told about HDR sources.
enum HdrPolicy {
  /// HDR sources go out as HDR when the display can show it.
  auto,

  /// Every source is presented as SDR; mpv tone-maps HDR to SDR.
  forceSdr,

  /// HDR sources are passed through as HDR whenever the display can show it.
  passthrough;

  /// Whether a source with transfer function [gamma] is reported to the
  /// native surface as HDR.
  bool reportsHdr(String? gamma) =>
      this != forceSdr && (gamma == 'pq' || gamma == 'hlg');
}
