import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/rendering.dart' show PlatformViewHitTestBehavior;
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:media_kit/media_kit.dart';

import 'subtitle_overlay.dart';

/// How the video is currently reaching the display.
enum SurfaceMode {
  /// mpv draws into a native EDR surface and the source is HDR on an EDR display.
  hdrNative,

  /// mpv draws into the native surface but output is SDR (SDR source or no EDR display).
  sdrNative,

  /// No native surface; the caller keeps media_kit's texture path.
  texture,
}

/// Current surface mode and why. `reason` is always set.
@immutable
final class SurfaceState {
  const SurfaceState(this.mode, this.reason);

  final SurfaceMode mode;
  final String reason;

  @override
  bool operator ==(Object other) =>
      other is SurfaceState && other.mode == mode && other.reason == reason;

  @override
  int get hashCode => Object.hash(mode, reason);

  @override
  String toString() => 'SurfaceState(${mode.name}: $reason)';
}

/// Pure mode decision; the only place the HDR/SDR/texture policy lives.
SurfaceState resolveSurfaceState({
  required double edrHeadroom,
  required bool hdrSource,
}) {
  final headroom = edrHeadroom.toStringAsFixed(2);
  if (edrHeadroom <= 1.0) {
    return SurfaceState(
      SurfaceMode.sdrNative,
      'display reports no EDR headroom ($headroom)',
    );
  }
  if (!hdrSource) {
    return SurfaceState(
      SurfaceMode.sdrNative,
      'source is SDR; EDR headroom $headroom unused',
    );
  }
  return SurfaceState(
    SurfaceMode.hdrNative,
    'HDR source on EDR display, headroom $headroom',
  );
}

/// Sets mpv properties in order on the player this surface belongs to (Android: the plugin
/// owns the SurfaceView, Dart owns the player). `reseek` re-opens the video chain at the
/// current position after a video output change.
typedef MpvControl = Future<void> Function(
  List<(String, String)> properties, {
  required bool reseek,
});

/// What the Android surface reads from the player besides setting mpv properties: the
/// subtitle cue text for the Flutter overlay, the video shape for aspect/zoom, and the
/// selected subtitle track (image subtitles cannot be drawn by the overlay).
final class AndroidPlayerFeed {
  const AndroidPlayerFeed({
    required this.read,
    required this.observe,
    required this.unobserve,
    required this.subtitleText,
    required this.videoSize,
    required this.subtitleTrack,
  });

  /// The feed from a media_kit [Player].
  factory AndroidPlayerFeed.of(Player player) {
    NativePlayer backend() => player.platform as NativePlayer;
    return AndroidPlayerFeed(
      read: (name) => backend().getProperty(name),
      observe: (name, changed) =>
          backend().observeProperty(name, (_) async => changed()),
      unobserve: (name) => backend().unobserveProperty(name),
      subtitleText: player.stream.subtitle.map((s) => s.first),
      videoSize: player.stream.videoParams.map(
        (p) => (p.dw ?? 0) > 0 && (p.dh ?? 0) > 0
            ? Size(p.dw!.toDouble(), p.dh!.toDouble())
            : null,
      ),
      subtitleTrack: player.stream.track.map<void>((_) {}),
    );
  }

  /// mpv property getter; an unavailable property reads as an empty string.
  final Future<String> Function(String name) read;
  final Future<void> Function(String name, void Function() changed) observe;
  final Future<void> Function(String name) unobserve;

  /// mpv `sub-text`.
  final Stream<String> subtitleText;

  /// Display size of the decoded video (after pixel aspect); null until known.
  final Stream<Size?> videoSize;

  /// Fires when the selected subtitle track changes.
  final Stream<void> subtitleTrack;
}

/// How the video sits in its box when the decoder (not mpv) scales it: `vo=mediacodec_embed`
/// stretches to the whole SurfaceView, so the view itself takes the video's shape.
@immutable
final class VideoFrame {
  const VideoFrame({
    this.aspect,
    this.keepAspect = true,
    this.panscan = 0,
    this.zoom = 0,
    this.panX = 0,
    this.panY = 0,
  });

  /// Display width / height; null until the video size is known.
  final double? aspect;
  final bool keepAspect;

  /// mpv `panscan`: 0 fits inside the box, 1 covers it.
  final double panscan;

  /// mpv `video-zoom` (log2 scale) and `video-pan-x/y` (fractions of the video size); the
  /// display calibration setting writes them.
  final double zoom;
  final double panX;
  final double panY;

  VideoFrame copyWith({
    double? aspect,
    bool? keepAspect,
    double? panscan,
    double? zoom,
    double? panX,
    double? panY,
  }) => VideoFrame(
    aspect: aspect ?? this.aspect,
    keepAspect: keepAspect ?? this.keepAspect,
    panscan: panscan ?? this.panscan,
    zoom: zoom ?? this.zoom,
    panX: panX ?? this.panX,
    panY: panY ?? this.panY,
  );

  @override
  bool operator ==(Object other) =>
      other is VideoFrame &&
      other.aspect == aspect &&
      other.keepAspect == keepAspect &&
      other.panscan == panscan &&
      other.zoom == zoom &&
      other.panX == panX &&
      other.panY == panY;

  @override
  int get hashCode =>
      Object.hash(aspect, keepAspect, panscan, zoom, panX, panY);

  /// The size the video occupies in [box] when mpv does not scale it.
  Size sizeIn(Size box) {
    final a = aspect;
    final scale = math.pow(2, zoom).toDouble();
    if (!keepAspect || a == null || a <= 0 || box.isEmpty) return box * scale;
    final fit = a > box.aspectRatio
        ? Size(box.width, box.width / a)
        : Size(box.height * a, box.height);
    final cover = a > box.aspectRatio
        ? Size(box.height * a, box.height)
        : Size(box.width, box.width / a);
    return Size.lerp(fit, cover, panscan.clamp(0.0, 1.0))! * scale;
  }

  /// Where the video sits relative to the box centre.
  Offset shiftOf(Size size) => Offset(panX * size.width, panY * size.height);
}

const MethodChannel _channel = MethodChannel('video_surface');

/// A native HDR-capable video surface for one media_kit [Player].
///
/// mpv renders into a `CAMetalLayer` (EDR, half-float, extended linear Display P3) owned by
/// this plugin; Flutter widgets stack above [build]. Dispose it before the [Player].
/// A native Android surface failure that must be shown instead of changing renderers.
class AndroidSurfaceException implements Exception {
  const AndroidSurfaceException(this.message);
  final String message;
  @override
  String toString() => 'Android surface: $message';
}

final class NativeVideoSurface {
  NativeVideoSurface._(this._id, this.state, this._hdrSource, this._headroom);

  final int? _id;
  StreamSubscription<bool>? _hdrSub;
  bool _hdrSource;
  double _headroom;
  bool _disposed = false;
  bool _released = false;

  /// Current [SurfaceState]; listen to follow HDR/SDR changes and display moves.
  final ValueNotifier<SurfaceState> state;
  final failure = ValueNotifier<AndroidSurfaceException?>(null);
  final nativeSubtitleOverlay = ValueNotifier<bool>(false);

  /// Creates the surface for [player]; on failure returns a `texture`-mode surface whose
  /// reason is the failure.
  static Future<NativeVideoSurface> attach(Player player) {
    return create(
      handle: player.handle,
      hdrSource: player.stream.videoParams.map(
        (p) => p.gamma == 'pq' || p.gamma == 'hlg',
      ),
      feed: AndroidPlayerFeed.of(player),
      mpv: (properties, {required bool reseek}) async {
        final backend = player.platform as NativePlayer;
        for (final (name, value) in properties) {
          await backend.setProperty(name, value);
        }
        if (reseek && player.state.playlist.medias.isNotEmpty) {
          await player.seek(player.state.position);
        }
      },
    );
  }

  /// [attach] with the player's pieces passed in directly.
  static Future<NativeVideoSurface> create({
    required Future<int> handle,
    required Stream<bool> hdrSource,
    MpvControl? mpv,
    AndroidPlayerFeed? feed,
    @visibleForTesting String? operatingSystem,
  }) async {
    final os = operatingSystem ?? Platform.operatingSystem;
    // The one platform gate: other OSes keep the texture path until their phases land.
    // iOS: native gpu-next/MoltenVK Metal output, with VideoToolbox textures imported by the engine.
    if (os != 'macos' &&
        os != 'ios' &&
        os != 'tvos' &&
        os != 'windows' &&
        !(os == 'android' && mpv != null)) {
      return NativeVideoSurface._(
        null,
        ValueNotifier(
          SurfaceState(
            SurfaceMode.texture,
            os == 'android'
                ? 'android surface needs an mpv control'
                : 'native surface not implemented on this platform',
          ),
        ),
        false,
        1,
      );
    }
    final Map<Object?, Object?> info;
    try {
      info = (await _channel.invokeMapMethod<Object?, Object?>('create', {
        'handle': await handle,
      }))!;
    } on PlatformException catch (e) {
      if (os == 'android') {
        throw AndroidSurfaceException('${e.code}: ${e.message}');
      }
      return NativeVideoSurface._(
        null,
        ValueNotifier(
          SurfaceState(SurfaceMode.texture, '${e.code}: ${e.message}'),
        ),
        false,
        1,
      );
    }
    final id = info['id']! as int;
    final headroom = _headroomOf(info, android: os == 'android');
    final surface = NativeVideoSurface._(
      id,
      ValueNotifier(
        resolveSurfaceState(edrHeadroom: headroom, hdrSource: false),
      ),
      false,
      headroom,
    );
    if (os == 'android') {
      if (info['overlaySupported'] != true) {
        await _channel.invokeMethod<void>('dispose', {'id': id});
        throw const AndroidSurfaceException(
          'native subtitle overlay is unavailable',
        );
      }
      surface._mpv = mpv;
      try {
        await mpv!([
          ..._androidOptions,
          // The bundled libass has no system fonts: the plugin ships Vazirmatn (Latin +
          // Persian/Arabic) and mpv draws every text subtitle with it; MKV fonts still win.
          if (info['fontsDir'] case final String dir) ...[
            ('sub-fonts-dir', dir),
            ('osd-fonts-dir', dir),
          ],
        ], reseek: false);
        if (feed != null) await surface._followPlayer(feed);
      } catch (error) {
        await surface.dispose();
        throw AndroidSurfaceException('mpv Android options: $error');
      }
    }
    surface._hdrSub = hdrSource.listen((hdr) {
      surface._hdrSource = hdr;
      unawaited(surface._pushSource());
    });
    _channel.setMethodCallHandler(_onNative);
    _live[id] = surface;
    return surface;
  }

  static final Map<int, NativeVideoSurface> _live = {};

  /// Tells native whether the window needs HDR output, then re-evaluates the mpv output.
  Future<void> _pushSource() async {
    final id = _id;
    if (_disposed || id == null) return;
    try {
      await _channel.invokeMethod<void>('source', {
        'id': id,
        'hdr': _hdrSource,
      });
      if (!_disposed) {
        _publish();
        _scheduleAndroid();
      }
    } catch (error, stack) {
      if (!_disposed) {
        if (_mpv != null) {
          _failAndroid(error, stack);
        } else {
          state.value = SurfaceState(
            SurfaceMode.texture,
            'native source update failed: $error',
          );
        }
      }
    }
  }

  static Future<void> _onNative(MethodCall call) async {
    final info = call.arguments as Map<Object?, Object?>;
    final s = _live[info['id']];
    if (s == null || s._disposed) return;
    if (call.method == 'surface') {
      s._wid = info['wid']! as int;
      s._overlayWid = (info['overlayWid'] as num?)?.toInt() ?? 0;
      s._width = info['width']! as int;
      s._height = info['height']! as int;
      s._scheduleAndroid();
      await s._androidChain;
      return;
    }
    if (call.method == 'failed') {
      if (s._mpv != null) {
        s._failAndroid(
          AndroidSurfaceException('${info['message']}'),
          StackTrace.current,
        );
      } else {
        s.state.value = SurfaceState(
          SurfaceMode.texture,
          'native failure: ${info['message']}',
        );
      }
      return;
    }
    if (call.method != 'screen') return;
    final headroom = _headroomOf(info, android: s._mpv != null);
    if (headroom == s._headroom) return;
    s._headroom = headroom;
    s._publish();
  }

  static double _headroomOf(
    Map<Object?, Object?> info, {
    bool android = false,
  }) {
    const proofHeadroom = int.fromEnvironment('VP_PROOF_HEADROOM');
    if (android && proofHeadroom > 0) return proofHeadroom.toDouble();
    return (info['headroom']! as num).toDouble();
  }

  MpvControl? _mpv;
  int _wid = 0;
  int _overlayWid = 0;
  int _width = 0;
  int _height = 0;
  ({int wid, int overlayWid, bool embed})? _attached;
  Future<void> _androidChain = Future.value();
  AndroidPlayerFeed? _feed;
  final _feedSubs = <StreamSubscription<Object?>>[];
  final _observed = <String>[];
  String? _savedHwdec;

  /// The video's shape inside the view; only `mediacodec_embed` needs it (see [VideoFrame]).
  final frame = ValueNotifier<VideoFrame>(const VideoFrame());

  /// HDR would use `mediacodec_embed`, but the selected subtitle is a picture mpv can only
  /// draw on `vo=gpu` (PGS/VobSub): that file plays through gpu instead.
  // media_kit's Android defaults that a VideoController would otherwise set.
  // media_kit starts every player with vid=no and only a VideoController turns it on. Without
  // an output mpv ends playback at once, so play blind on vo=null until the SurfaceView exists
  // and [_applyAndroid] switches it over.
  static const _androidOptions = <(String, String)>[
    ('vo', 'null'),
    ('vid', 'auto'),
    ('sub-use-margins', 'no'),
    ('sub-font-provider', 'none'),
    ('embeddedfonts', 'yes'),
    ('sub-font', 'Vazirmatn'),
    ('sub-scale-with-window', 'yes'),
    ('hwdec-codecs', 'h264,hevc,mpeg4,mpeg2video,vp8,vp9,av1'),
  ];

  void _scheduleAndroid() {
    if (_mpv == null) return;
    _androidChain = _androidChain.then((_) => _applyAndroid());
  }

  /// Reads the video shape and mpv aspect options shared by both Android surfaces.
  Future<void> _followPlayer(AndroidPlayerFeed feed) async {
    _feed = feed;
    _feedSubs.addAll([
      feed.videoSize.listen((size) {
        final ok = size != null && size.width > 0 && size.height > 0;
        _setFrame(aspect: ok ? size.width / size.height : null);
      }),
    ]);
    for (final name in _frameOptions) {
      await feed.observe(name, () => unawaited(_readAspectOptions()));
      _observed.add(name);
    }
    await _readAspectOptions();
  }

  static const _frameOptions = [
    'keepaspect',
    'panscan',
    'video-zoom',
    'video-pan-x',
    'video-pan-y',
  ];

  void _setFrame({double? aspect}) =>
      frame.value = frame.value.copyWith(aspect: aspect);

  Future<void> _readAspectOptions() async {
    final feed = _feed!;
    final v = [for (final name in _frameOptions) await feed.read(name)];
    if (_disposed) return;
    double number(int i) => double.tryParse(v[i]) ?? 0;
    frame.value = frame.value.copyWith(
      keepAspect: v[0] != 'no',
      panscan: number(1),
      zoom: number(2),
      panX: number(3),
      panY: number(4),
    );
  }

  /// Points mpv at the SurfaceView. mpv draws with vo=gpu (MediaCodec zero-copy through
  /// AImageReader: bundled libmpv 0.36 has hwdec_aimagereader). HDR on an HDR display uses
  /// vo=mediacodec_embed so the decoder feeds the HDR window directly (the bundled libmpv's
  /// gpu context cannot output PQ); it has no OSD, so a picture subtitle (PGS/VobSub) sends
  /// that file through vo=gpu with hwdec=mediacodec-copy. mpv draws all subtitles on gpu;
  /// on mediacodec_embed the text ones are the Flutter overlay in [build].
  Future<void> _applyAndroid() async {
    final mpv = _mpv;
    if (mpv == null || _disposed || failure.value != null) return;
    final wid = _wid, overlayWid = _overlayWid;
    final embed = state.value.mode == SurfaceMode.hdrNative;
    try {
      if (wid == 0 || overlayWid == 0) {
        if (_attached != null) {
          await mpv(const [
            ('vo', 'null'),
            ('wid', '0'),
            ('vo-mediacodec-embed-overlay-surface', '0'),
            ('vid', 'no'),
          ], reseek: false);
          _attached = null;
          nativeSubtitleOverlay.value = false;
        }
        await _releaseRetired(wid, overlayWid);
        return;
      }
      final size = ('android-surface-size', '${_width}x$_height');
      if (_attached?.wid == wid &&
          _attached?.overlayWid == overlayWid &&
          _attached?.embed == embed) {
        await mpv([size], reseek: false);
        return;
      }
      final hwdec = await _hwdecFor(embed);
      final visibility = await _feed?.read('sub-visibility');
      await mpv([
        const ('vo', 'null'),
        size,
        ('wid', '$wid'),
        ('vo-mediacodec-embed-overlay-surface', embed ? '$overlayWid' : '0'),
        if (hwdec != null) ('hwdec', hwdec),
        if (!embed) ...const [('opengl-es', 'yes'), ('gpu-context', 'android')],
        ('vo', embed ? 'mediacodec_embed' : 'gpu'),
        const ('vid', 'auto'),
        ('sub-visibility', visibility == 'no' ? 'no' : 'yes'),
      ], reseek: true);
      _attached = (wid: wid, overlayWid: overlayWid, embed: embed);
      nativeSubtitleOverlay.value = embed;
      await _releaseRetired(wid, overlayWid);
    } catch (error, stack) {
      if (!_disposed) _failAndroid(error, stack);
    }
  }

  Future<void> _releaseRetired(int wid, int overlayWid) =>
      _channel.invokeMethod<void>('releaseRetired', {
        'id': _id,
        'wid': wid,
        'overlayWid': overlayWid,
      });

  void _failAndroid(Object error, StackTrace stack) {
    final problem = error is AndroidSurfaceException
        ? error
        : AndroidSurfaceException('$error');
    failure.value = problem;
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: problem,
        stack: stack,
        library: 'video_surface',
        context: ErrorDescription('attaching the Android subtitle overlay'),
      ),
    );
  }

  /// The hwdec value to set for this attach, or null to leave the user's choice alone.
  /// [copy] switches a zero-copy MediaCodec choice to its copy variant and remembers it.
  Future<String?> _hwdecFor(bool embed) async {
    if (embed) {
      _savedHwdec ??= await _feed?.read('hwdec');
      return 'mediacodec';
    }
    final saved = _savedHwdec;
    _savedHwdec = null;
    return saved;
  }

  void _publish() => state.value = resolveSurfaceState(
    edrHeadroom: _headroom,
    hdrSource: _hdrSource,
  );

  /// The widget showing the video; stack Flutter controls above it. Only valid while
  /// [state] is not [SurfaceMode.texture].
  Widget build() {
    final id = _id;
    if (id == null) {
      throw StateError('no native surface: ${state.value.reason}');
    }
    if (_mpv != null) return _AndroidVideo(this, _androidView(id));
    if (Platform.isIOS || Platform.operatingSystem == 'tvos') {
      return UiKitView(
        key: ValueKey<int>(id),
        viewType: 'video_surface/view',
        creationParams: {'id': id},
        creationParamsCodec: const StandardMessageCodec(),
      );
    }
    // Windows has no platform views: mpv owns a child window under Flutter's view and
    // Flutter punches a hole over it (see [_VideoHole]).
    if (Platform.isWindows) return _VideoHole(key: ValueKey<int>(id), id: id);
    return AppKitView(
      key: ValueKey<int>(id),
      viewType: 'video_surface/view',
      creationParams: {'id': id},
      creationParamsCodec: const StandardMessageCodec(),
    );
  }

  // Hybrid composition: the SurfaceView stays its own compositor layer.
  Widget _androidView(int id) => PlatformViewLink(
    key: ValueKey<int>(id),
    viewType: 'video_surface/view',
    surfaceFactory: (context, controller) => AndroidViewSurface(
      controller: controller as AndroidViewController,
      gestureRecognizers: const {},
      hitTestBehavior: PlatformViewHitTestBehavior.transparent,
    ),
    onCreatePlatformView: (params) =>
        PlatformViewsService.initExpensiveAndroidView(
            id: params.id,
            viewType: 'video_surface/view',
            layoutDirection: TextDirection.ltr,
            creationParams: {'id': id},
            creationParamsCodec: const StandardMessageCodec(),
            onFocus: () => params.onFocusChanged(true),
          )
          ..addOnPlatformViewCreatedListener(params.onPlatformViewCreated)
          ..create(),
  );

  /// Native diagnostics: EDR headroom, `peak` (max linear value in the last frame, 1.0 =
  /// SDR white), frames rendered and whether the layer requests EDR.
  Future<Map<String, Object?>> probe() async {
    final id = _id;
    if (id == null) return {};
    return Map<String, Object?>.from(
      (await _channel.invokeMapMethod<String, Object?>('probe', {'id': id}))!,
    );
  }

  /// Windows: the child window's real rect vs the rect Dart asked for, window DPI, monitors.
  Future<Map<String, Object?>> geometry() async {
    final id = _id;
    if (id == null) return {};
    return Map<String, Object?>.from(
      (await _channel.invokeMapMethod<String, Object?>('geometry', {
        'id': id,
      }))!,
    );
  }

  /// Main screen EDR headroom (`edr` now, `potential` maximum); 1.0 means SDR only.
  static Future<Map<String, double>> screenEdr() async =>
      (await _channel.invokeMapMethod<String, double>('screenEdr'))!;

  /// Live native objects (`views`, `instances`, `ioSurfaces`, `glContexts`).
  static Future<Map<String, int>> nativeCounters() async =>
      (await _channel.invokeMapMethod<String, int>('counters'))!;

  /// Frees the native render context and surface. Call before disposing the [Player].
  Future<void> dispose({bool engineDisposed = false}) async {
    if (_released) return;
    _disposed = true;
    await _hdrSub?.cancel();
    for (final sub in _feedSubs) {
      await sub.cancel();
    }
    if (!engineDisposed) {
      for (final name in _observed) {
        await _feed!.unobserve(name);
      }
      await _androidChain;
      // Failed detach must retain JNI references until the owner destroys mpv.
      if (_mpv != null && _attached != null) {
        await _mpv!(const [
          ('vo', 'null'),
          ('wid', '0'),
          ('vo-mediacodec-embed-overlay-surface', '0'),
          ('vid', 'no'),
        ], reseek: false);
      }
    }
    final id = _id;
    if (id != null) {
      await _channel.invokeMethod<void>('dispose', {'id': id});
      _live.remove(id);
    }
    _released = true;
    state.dispose();
    frame.dispose();
    failure.dispose();
    nativeSubtitleOverlay.dispose();
  }
}

/// The Android video box. mpv's own gpu output fills the SurfaceView; `mediacodec_embed`
/// stretches the decoder output over the whole view, so there the view takes the video's
/// shape (aspect, Fill, Stretch). Flutter draws the text subtitles above it. The platform
/// view keeps one place in the tree so a mode change never recreates the Surface.
class _AndroidVideo extends StatelessWidget {
  const _AndroidVideo(this.surface, this.view);

  final NativeVideoSurface surface;
  final Widget view;

  @override
  Widget build(BuildContext context) {
    final feed = surface._feed;
    return ListenableBuilder(
      listenable: Listenable.merge([
        surface.state,
        surface.frame,
        surface.nativeSubtitleOverlay,
      ]),
      builder: (context, _) {
        final embed = surface.state.value.mode == SurfaceMode.hdrNative;
        return Stack(
          fit: StackFit.expand,
          children: [
            LayoutBuilder(
              builder: (context, box) {
                final size = embed
                    ? surface.frame.value.sizeIn(box.biggest)
                    : box.biggest;
                return ClipRect(
                  child: Center(
                    child: Transform.translate(
                      offset: embed
                          ? surface.frame.value.shiftOf(size)
                          : Offset.zero,
                      child: OverflowBox(
                        minWidth: size.width,
                        maxWidth: size.width,
                        minHeight: size.height,
                        maxHeight: size.height,
                        child: view,
                      ),
                    ),
                  ),
                );
              },
            ),
            if (feed != null && embed && !surface.nativeSubtitleOverlay.value)
              SubtitleOverlay(text: feed.subtitleText, read: feed.read),
          ],
        );
      },
    );
  }
}

/// Transparent hole over the native child window, kept in sync with the layout: clears the
/// Flutter surface under it and tells the plugin the rect (physical pixels) on every change.
class _VideoHole extends LeafRenderObjectWidget {
  const _VideoHole({super.key, required this.id});

  final int id;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderVideoHole(id);

  @override
  void updateRenderObject(BuildContext context, _RenderVideoHole renderObject) {
    renderObject.id = id;
  }

  @override
  void didUnmountRenderObject(_RenderVideoHole renderObject) =>
      renderObject.hide();
}

class _RenderVideoHole extends RenderBox {
  _RenderVideoHole(this.id);

  int id;
  Rect? _sent;

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void performResize() {
    super.performResize();
    markNeedsPaint();
  }

  @override
  bool hitTestSelf(Offset position) => false;

  @override
  void paint(PaintingContext context, Offset offset) {
    context.canvas.drawRect(
      offset & size,
      Paint()..color = const Color(0xFF010203),
    );
    final scale = _scale();
    final rect = Rect.fromPoints(
      localToGlobal(Offset.zero) * scale,
      localToGlobal(size.bottomRight(Offset.zero)) * scale,
    );
    if (rect == _sent) return;
    _sent = rect;
    unawaited(_push(rect, visible: true));
  }

  double _scale() =>
      WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;

  void hide() {
    _sent = null;
    unawaited(_push(Rect.zero, visible: false));
  }

  Future<void> _push(Rect r, {required bool visible}) async {
    try {
      await _channel.invokeMethod<void>('rect', {
        'id': id,
        'x': r.left.round(),
        'y': r.top.round(),
        'w': r.width.round(),
        'h': r.height.round(),
        'visible': visible ? 1 : 0,
      });
    } on PlatformException catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'video_surface',
          context: ErrorDescription('while placing the native video window'),
        ),
      );
    }
  }
}
