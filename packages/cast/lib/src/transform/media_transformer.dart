import 'dart:io';

import '../core/cast_media.dart';
import '../core/media_proxy.dart';
import '../core/media_transformer.dart';
import '../protocols/dlna/capability.dart';
import '../remux/remuxer.dart';
import '../utils/logger.dart';
import 'audio_capability.dart';
import 'progressive_output.dart';

final class CastTransformFailure implements Exception {
  const CastTransformFailure([this.cause]);
  final Object? cause;
  String get message => 'Not compatible — pick another quality';
  @override
  String toString() => cause == null ? message : '$message ($cause)';
}

final class CastTransformPlan {
  CastTransformPlan({
    required this.direct,
    required this.outputType,
    required this.audioSupport,
    required List<int> keepStreams,
    required List<int> droppedAudioStreams,
  }) : keepStreams = List.unmodifiable(keepStreams),
       droppedAudioStreams = List.unmodifiable(droppedAudioStreams);
  final bool direct;
  final CastMediaType outputType;
  final AudioSupport audioSupport;
  final List<int> keepStreams;
  final List<int> droppedAudioStreams;
}

CastTransformPlan planCastTransform({
  required CastCompatibility compatibility,
  required CastMediaType inputType,
  required List<RemuxStream> streams,
  required AudioCapability audioCapability,
  bool embedSubtitles = false,
}) {
  if (compatibility == CastCompatibility.notCompatible) {
    throw const CastTransformFailure();
  }
  final outputType = embedSubtitles
      ? CastMediaType.mkv
      : switch (compatibility) {
          CastCompatibility.remuxToMp4 => CastMediaType.mp4,
          CastCompatibility.remuxToHls => CastMediaType.hls,
          _ => inputType,
        };
  final audio = streams.where((stream) => stream.type == 'audio');
  final dropped = audio
      .where((stream) => !audioCapability.supports(stream.codec))
      .map((stream) => stream.index)
      .toList();
  if (!streams.any(
        (stream) => stream.type == 'video' && !stream.attachedPicture,
      ) ||
      (audio.isNotEmpty && dropped.length == audio.length)) {
    throw const CastTransformFailure();
  }
  final direct =
      compatibility == CastCompatibility.direct &&
      dropped.isEmpty &&
      !embedSubtitles;
  return CastTransformPlan(
    direct: direct,
    outputType: outputType,
    audioSupport: audioCapability.support,
    keepStreams: [
      for (final stream in streams)
        if (((stream.type == 'video' && !stream.attachedPicture) ||
                stream.type == 'audio' ||
                (stream.type == 'subtitle' &&
                    outputType == CastMediaType.mkv)) &&
            !dropped.contains(stream.index))
          stream.index,
    ],
    droppedAudioStreams: dropped,
  );
}

/// Owns its remux task, generated route and temporary assets until disposed.
final class CastTransformResult extends TransformedMedia {
  CastTransformResult({
    required super.proxyUrl,
    required super.effectiveType,
    required this.audioSupport,
    this.droppedAudioStreams = const [],
    this.task,
    this.release,
  });
  final AudioSupport audioSupport;
  bool get audioSupportUnknown => audioSupport == AudioSupport.unknown;
  final List<int> droppedAudioStreams;
  final RemuxTask? task;
  final Future<void> Function()? release;
  Future<void>? _disposing;
  Future<RemuxOutcome> get done async {
    try {
      return await (task?.done ?? Future.value(RemuxOutcome.completed));
    } catch (error) {
      throw CastTransformFailure(error);
    }
  }

  @override
  Future<void> dispose() => _disposing ??= release?.call() ?? Future.value();
}

/// Maps explicit device compatibility and audio facts to stream-copy jobs.
final class CastRemuxMediaTransformer implements MediaTransformer {
  CastRemuxMediaTransformer({
    required this.compatibility,
    required this.audioCapability,
    this.embedSubtitles = false,
    this.remuxer,
    this.maxDuration,
    List<RemuxStream>? streams,
  }) : streams = streams == null ? null : List.unmodifiable(streams);
  final CastCompatibility compatibility;
  final AudioCapability audioCapability;
  final bool embedSubtitles;
  final Duration? maxDuration;
  final List<RemuxStream>? streams;
  final Remuxer? remuxer;

  @override
  Future<CastTransformResult> transform(
    CastMedia media,
    MediaProxy proxy,
  ) async {
    if (compatibility == CastCompatibility.notCompatible) {
      throw const CastTransformFailure();
    }
    final subtitleTracks = [
      ...media.subtitles,
      if (media.defaultSubtitle != null &&
          !media.subtitles.any(
            (track) => track.url == media.defaultSubtitle!.url,
          ))
        media.defaultSubtitle!,
    ];
    final embed = embedSubtitles && subtitleTracks.isNotEmpty;
    // Unknown DLNA audio passes through unchanged under the owner ruling.
    if (compatibility == CastCompatibility.direct &&
        audioCapability.support == AudioSupport.unknown &&
        !embed) {
      return _direct(media, proxy);
    }
    final native = remuxer ?? Remuxer();
    String? inputRoute;
    Directory? work;
    ProgressiveOutput? output;
    final subtitleRoutes = <String>[];
    try {
      final String input;
      if (media.source != null) {
        inputRoute = proxy.registerSource(
          media.source!,
          fileExtension: media.fileExtension,
        );
        input = inputRoute;
      } else if (media.isLocalFile) {
        input = media.url;
      } else if (Uri.tryParse(media.url)?.scheme == 'file') {
        input = Uri.parse(media.url).toFilePath();
      } else {
        inputRoute = proxy.registerMedia(media.url, headers: media.httpHeaders);
        input = inputRoute;
      }
      final facts = streams ?? await native.probe(input);
      final plan = planCastTransform(
        compatibility: compatibility,
        inputType: media.type,
        streams: facts,
        audioCapability: audioCapability,
        embedSubtitles: embed,
      );
      if (plan.direct) {
        if (inputRoute != null) proxy.unregisterMedia(inputRoute);
        return await _direct(media, proxy);
      }
      work = await Directory.systemTemp.createTemp('cast-transform-');
      final (format, leaf) = switch (plan.outputType) {
        CastMediaType.mp4 => ('mp4', 'stream.mp4'),
        CastMediaType.hls => ('hls', 'hls/stream.m3u8'),
        CastMediaType.mkv => ('matroska', 'stream.mkv'),
        CastMediaType.mpegTs => ('mpegts', 'stream.ts'),
      };
      final subtitles = <String>[];
      if (embed) {
        for (final subtitle in subtitleTracks) {
          final uri = Uri.parse(subtitle.url);
          if (uri.scheme == 'file') {
            subtitles.add(uri.toFilePath());
          } else if (uri.scheme.isEmpty) {
            subtitles.add(subtitle.url);
          } else {
            final route = proxy.registerMedia(
              subtitle.url,
              headers: media.httpHeaders,
            );
            subtitleRoutes.add(route);
            subtitles.add(route);
          }
        }
      }
      final task = native.start(
        input: input,
        output: '${work.path}/$leaf',
        format: format,
        keepStreams: plan.keepStreams,
        subtitleInputs: subtitles,
        maxDuration: maxDuration,
      );
      final generated = ProgressiveOutput(
        task: task,
        file: File('${work.path}/$leaf'),
        directory: work,
        type: plan.outputType,
        proxy: proxy,
        inputRoutes: [?inputRoute, ...subtitleRoutes],
      );
      output = generated;
      final prefix = proxy.registerGeneratedMedia(
        serve: generated.serve,
        dispose: generated.dispose,
      );
      generated.prefix = prefix;
      await generated.ready;
      return CastTransformResult(
        proxyUrl: '$prefix${File(leaf).uri.pathSegments.last}',
        effectiveType: plan.outputType,
        audioSupport: plan.audioSupport,
        droppedAudioStreams: plan.droppedAudioStreams,
        task: task,
        release: generated.dispose,
      );
    } catch (error, stack) {
      CastLogger.error('Media transform failed: $error\n$stack');
      if (output != null) {
        await output.dispose();
      } else {
        if (work != null) await work.delete(recursive: true);
        if (inputRoute != null) proxy.unregisterMedia(inputRoute);
        for (final route in subtitleRoutes) {
          proxy.unregisterMedia(route);
        }
      }
      if (error is CastTransformFailure) rethrow;
      throw CastTransformFailure(error);
    }
  }

  Future<CastTransformResult> _direct(CastMedia media, MediaProxy proxy) async {
    final direct = await const DefaultMediaTransformer().transform(
      media,
      proxy,
    );
    return CastTransformResult(
      proxyUrl: direct.proxyUrl,
      effectiveType: direct.effectiveType,
      audioSupport: audioCapability.support,
      release: () async {
        proxy.unregisterMedia(direct.proxyUrl);
      },
    );
  }
}
