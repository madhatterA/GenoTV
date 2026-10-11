import 'package:intl/intl.dart';

import '../l10n_gen/app_strings.dart';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Section titles and icons, in [SettingSection] (source) order.
Map<SettingSection, (String, IconData)> sectionInfo(AppStrings strings) => {
  SettingSection.playback: (
    strings.settings_playback_title,
    PhosphorIconsRegular.playCircle,
  ),
  SettingSection.video: (
    strings.settings_video_title,
    PhosphorIconsRegular.filmSlate,
  ),
  SettingSection.audio: (
    strings.settings_audio_title,
    PhosphorIconsRegular.waveform,
  ),
  SettingSection.subtitles: (
    strings.settings_subtitles_title,
    PhosphorIconsRegular.subtitles,
  ),
  SettingSection.display: (
    strings.settings_display_title,
    PhosphorIconsRegular.desktop,
  ),
  SettingSection.streaming: (
    strings.settings_streaming_title,
    PhosphorIconsRegular.wifiHigh,
  ),
  SettingSection.downloads: (
    strings.settings_downloads_title,
    PhosphorIconsRegular.downloadSimple,
  ),
  SettingSection.languages: (
    strings.settings_languages_title,
    PhosphorIconsRegular.globe,
  ),
  SettingSection.performance: (
    strings.settings_performance_title,
    PhosphorIconsRegular.gauge,
  ),
  SettingSection.advanced: (
    strings.settings_advanced_title,
    PhosphorIconsRegular.sliders,
  ),
};

/// Whether [def] is shown: its tier is switched on and the platform has the
/// capability it requires (a setting the platform cannot do is hidden).
/// Expert content needs Advanced on as well.
bool isSettingVisible(
  SettingDef def, {
  required bool showAdvanced,
  required bool showExpert,
  required Set<SettingCapability> available,
  String? os,
}) =>
    (def.requires == SettingCapability.none ||
        ((os == 'android' || os == 'ios') &&
            def.id == 'audio.deviceKeepAlive') ||
        available.contains(def.requires)) &&
    switch (def.tier) {
      SettingTier.basic => true,
      SettingTier.advanced => showAdvanced,
      SettingTier.expert => showAdvanced && showExpert,
    };

/// The visible settings of [section] (its own plus those it is also listed
/// in), in schema order.
List<SettingDef> visibleSettings(
  SettingSection section, {
  required bool showAdvanced,
  required bool showExpert,
  required Set<SettingCapability> available,
  List<String>? passthroughFormats,
  String? os,
}) => <SettingDef>[
  for (final def in settingDefs)
    if ((def.section == section || def.alsoIn.contains(section)) &&
        isSettingVisible(
          def,
          showAdvanced: showAdvanced,
          showExpert: showExpert,
          available: available,
          os: os,
        ) &&
        // Kodi 1.6 (macOS, Windows): multichannel PCM follows the speaker
        // layout; there is no setting for it.
        (def.id != 'audio.multichannelLpcm' ||
            (os != 'macos' && os != 'windows')) &&
        (passthroughFormats == null ||
            (!def.id.startsWith('audio.receiver.') &&
                def.id != 'audio.ac3Transcode') ||
            passthroughFormats.contains(switch (def.id) {
              'audio.receiver.dolbyDigital' || 'audio.ac3Transcode' => 'ac3',
              'audio.receiver.ddPlus' => 'eac3',
              'audio.receiver.dts' => 'dts',
              'audio.receiver.dtsHd' => 'dtsHd',
              'audio.receiver.trueHd' => 'trueHd',
              _ => '', // Atmos and DTS:X follow their carrier, as in Kodi.
            })))
      def,
];

/// The row title of [def]: an explicit name where the id would read badly,
/// otherwise the id's last segment as a sentence ("syncToDisplay" ->
/// "Sync to display").
String settingLabel(SettingDef def, AppStrings strings) => switch (def.id) {
  'playback.resume' => strings.settings_playback_resume_label,
  'playback.autoPlayNext' => strings.settings_playback_autoPlayNext_label,
  'playback.rememberPosition' =>
    strings.settings_playback_rememberPosition_label,
  'playback.speed' => strings.settings_playback_speed_label,
  'playback.syncToDisplay' => strings.settings_playback_syncToDisplay_label,
  'playback.avSyncCorrection' =>
    strings.settings_playback_avSyncCorrection_label,
  'playback.cachePreset' => strings.settings_playback_cachePreset_label,
  'playback.demuxerCacheSize' =>
    strings.settings_playback_demuxerCacheSize_label,
  'playback.readAhead' => strings.settings_playback_readAhead_label,
  'playback.networkTimeout' => strings.settings_playback_networkTimeout_label,
  'video.hwdec' => strings.settings_video_hwdec_label,
  'video.hdr' => strings.settings_video_hdr_label,
  'video.matchFrameRate' => strings.settings_video_matchFrameRate_label,
  'video.matchResolution' => strings.settings_video_matchResolution_label,
  'video.aspectRatio' => strings.settings_video_aspectRatio_label,
  'video.decoder' => strings.settings_video_decoder_label,
  'video.scalingQuality' => strings.settings_video_scalingQuality_label,
  'video.toneMapping' => strings.settings_video_toneMapping_label,
  'video.pixelFormat' => strings.settings_video_pixelFormat_label,
  'video.bitDepth' => strings.settings_video_bitDepth_label,
  'video.chroma' => strings.settings_video_chroma_label,
  'video.dithering' => strings.settings_video_dithering_label,
  'video.interpolation' => strings.settings_video_interpolation_label,
  'video.debanding' => strings.settings_video_debanding_label,
  'video.gpuRendering' => strings.settings_video_gpuRendering_label,
  'video.displayModeWhitelist' =>
    strings.settings_video_displayModeWhitelist_label,
  'audio.outputDevice' => strings.settings_audio_outputDevice_label,
  'audio.speakerLayout' => strings.settings_audio_speakerLayout_label,
  'audio.normalizeVolume' => strings.settings_audio_normalizeVolume_label,
  'audio.outputMode' => strings.settings_audio_outputMode_label,
  'audio.passthrough' => strings.settings_audio_passthrough_label,
  'audio.passthroughDevice' => strings.settings_audio_passthroughDevice_label,
  'audio.receiver.dolbyDigital' =>
    strings.settings_audio_receiver_dolbyDigital_label,
  'audio.receiver.ddPlus' => strings.settings_audio_receiver_ddPlus_label,
  'audio.receiver.dts' => strings.settings_audio_receiver_dts_label,
  'audio.receiver.trueHd' => strings.settings_audio_receiver_trueHd_label,
  'audio.receiver.dtsHd' => strings.settings_audio_receiver_dtsHd_label,
  'audio.receiver.atmos' => strings.settings_audio_receiver_atmos_label,
  'audio.receiver.dtsX' => strings.settings_audio_receiver_dtsX_label,
  'audio.multichannelLpcm' => strings.settings_audio_multichannelLpcm_label,
  'audio.ac3Transcode' => strings.settings_audio_ac3Transcode_label,
  'audio.stereoUpmix' => strings.settings_audio_stereoUpmix_label,
  'audio.downmixDialogue' => strings.settings_audio_downmixDialogue_label,
  'audio.resamplingQuality' => strings.settings_audio_resamplingQuality_label,
  'audio.sampleRate' => strings.settings_audio_sampleRate_label,
  'audio.exclusiveMode' => strings.settings_audio_exclusiveMode_label,
  'audio.deviceKeepAlive' => strings.settings_audio_deviceKeepAlive_label,
  'subtitles.autoEnable' => strings.settings_subtitles_autoEnable_label,
  'subtitles.hearingImpaired' =>
    strings.settings_subtitles_hearingImpaired_label,
  'subtitles.font' => strings.settings_subtitles_font_label,
  'subtitles.position' => strings.settings_subtitles_position_label,
  'subtitles.encoding' => strings.settings_subtitles_encoding_label,
  'subtitles.border' => strings.settings_subtitles_border_label,
  'subtitles.shadow' => strings.settings_subtitles_shadow_label,
  'subtitles.background' => strings.settings_subtitles_background_label,
  'subtitles.delay' => strings.settings_subtitles_delay_label,
  'subtitles.forcedBehaviour' =>
    strings.settings_subtitles_forcedBehaviour_label,
  'subtitles.assStyling' => strings.settings_subtitles_assStyling_label,
  'display.monitor' => strings.settings_display_monitor_label,
  'display.fullscreenMode' => strings.settings_display_fullscreenMode_label,
  'display.refreshRate' => strings.settings_display_refreshRate_label,
  'display.hdrOutputMode' => strings.settings_display_hdrOutputMode_label,
  'display.calibration' => strings.settings_display_calibration_label,
  'streaming.quality' => strings.settings_streaming_quality_label,
  'streaming.protocol' => strings.settings_streaming_protocol_label,
  'streaming.cacheSizeLimit' => strings.settings_streaming_cacheSizeLimit_label,
  'streaming.bufferSize' => strings.settings_streaming_bufferSize_label,
  'streaming.prebuffer' => strings.settings_streaming_prebuffer_label,
  'streaming.maxHttpConnections' =>
    strings.settings_streaming_maxHttpConnections_label,
  'streaming.connectionTimeout' =>
    strings.settings_streaming_connectionTimeout_label,
  'streaming.retryCount' => strings.settings_streaming_retryCount_label,
  'streaming.proxy' => strings.settings_streaming_proxy_label,
  'streaming.userAgent' => strings.settings_streaming_userAgent_label,
  'streaming.headers' => strings.settings_streaming_headers_label,
  'streaming.tls' => strings.settings_streaming_tls_label,
  'downloads.bandwidthLimit' => strings.settings_downloads_bandwidthLimit_label,
  'downloads.torrentDownLimit' =>
    strings.settings_downloads_torrentDownLimit_label,
  'downloads.torrentUpLimit' => strings.settings_downloads_torrentUpLimit_label,
  'downloads.connectionLimit' =>
    strings.settings_downloads_connectionLimit_label,
  'downloads.peerLimit' => strings.settings_downloads_peerLimit_label,
  'downloads.seeding' => strings.settings_downloads_seeding_label,
  'downloads.tracker' => strings.settings_downloads_tracker_label,
  'downloads.dht' => strings.settings_downloads_dht_label,
  'downloads.pex' => strings.settings_downloads_pex_label,
  'languages.preferOriginalAudio' =>
    strings.settings_languages_preferOriginalAudio_label,
  'languages.preferForcedSubtitles' =>
    strings.settings_languages_preferForcedSubtitles_label,
  'languages.preferBestAudio' =>
    strings.settings_languages_preferBestAudio_label,
  'languages.trackPriority' => strings.settings_languages_trackPriority_label,
  'performance.mode' => strings.settings_performance_mode_label,
  'performance.gpuQuality' => strings.settings_performance_gpuQuality_label,
  'performance.backgroundPreload' =>
    strings.settings_performance_backgroundPreload_label,
  'performance.decoderThreads' =>
    strings.settings_performance_decoderThreads_label,
  'advanced.diagnostics' => strings.settings_advanced_diagnostics_label,
  'advanced.customMpvOptions' =>
    strings.settings_advanced_customMpvOptions_label,
  'playback.preferredAudioLanguage' =>
    strings.settings_playback_preferredAudioLanguage_label,
  'playback.preferredSubtitleLanguage' =>
    strings.settings_playback_preferredSubtitleLanguage_label,
  'playback.defaultSubtitleSize' =>
    strings.settings_playback_defaultSubtitleSize_label,
  'app.language' => strings.settings_app_language_label,
  _ => throw ArgumentError.value(def.id, 'def.id'),
};

/// What the user reads for stored choice [value] of [def].
String choiceLabel(SettingDef def, String value, AppStrings strings) {
  if (value == 'auto' || value == 'Auto') return strings.common_auto;
  if (value == 'On') return strings.common_on;
  if (value == 'Enabled') return strings.common_enabled;
  if (value == 'Disabled') return strings.common_disabled;
  if (value == 'forced_only') return strings.settings_forcedOnly;
  if (value == 'no' || value == 'Off') return strings.common_off;
  if (def.id == preferredAudioLanguageSetting.id && value.isEmpty) {
    return strings.settings_original;
  }
  if (def.id == preferredSubtitleLanguageSetting.id && value.isEmpty) {
    return strings.common_off;
  }
  if (def.id == preferredAudioLanguageSetting.id ||
      def.id == preferredSubtitleLanguageSetting.id) {
    return switch (value) {
      'en' => strings.settings_language_choice_en,
      'fa' => strings.settings_language_choice_fa,
      'ar' => strings.settings_language_choice_ar,
      'fr' => strings.settings_language_choice_fr,
      'de' => strings.settings_language_choice_de,
      'es' => strings.settings_language_choice_es,
      'tr' => strings.settings_language_choice_tr,
      'ru' => strings.settings_language_choice_ru,
      'ja' => strings.settings_language_choice_ja,
      'ko' => strings.settings_language_choice_ko,
      'zh' => strings.settings_language_choice_zh,
      _ => value.isEmpty ? strings.settings_none : value,
    };
  }
  if (num.tryParse(value) case final number?) {
    return strings.settings_numericChoice(
      strings.localeName == 'fa'
          ? NumberFormat(
              value.contains('.')
                  ? '0.${'0'.padRight(value.split('.').last.length, '0')}'
                  : '0',
              strings.localeName,
            ).format(number)
          : value,
    );
  }
  final unitValue = RegExp(r'^([0-9]+) (Mbps|GB)$').firstMatch(value);
  if (unitValue != null) {
    final number = NumberFormat(
      '0',
      strings.localeName,
    ).format(int.parse(unitValue[1]!));
    return unitValue[2] == 'Mbps'
        ? strings.settings_choiceMbps(number)
        : strings.settings_choiceGB(number);
  }
  return switch ((def.id, value)) {
    ('playback.resume', "Ask") => strings.settings_playback_resume_choice_Ask,
    ('playback.resume', "Always") =>
      strings.settings_playback_resume_choice_Always,
    ('playback.resume', "Never") =>
      strings.settings_playback_resume_choice_Never,
    ('playback.cachePreset', "Low latency") =>
      strings.settings_playback_cachePreset_choice_Low_latency,
    ('playback.cachePreset', "Balanced") =>
      strings.settings_playback_cachePreset_choice_Balanced,
    ('playback.cachePreset', "Large") =>
      strings.settings_playback_cachePreset_choice_Large,
    ('video.hdr', "Force SDR") => strings.settings_video_hdr_choice_Force_SDR,
    ('video.hdr', "Passthrough HDR") =>
      strings.settings_video_hdr_choice_Passthrough_HDR,
    ('video.matchFrameRate', "On start-stop") =>
      strings.settings_video_matchFrameRate_choice_On_start_stop,
    ('video.matchFrameRate', "Always") =>
      strings.settings_video_matchFrameRate_choice_Always,
    ('video.aspectRatio', "Original") =>
      strings.settings_video_aspectRatio_choice_Original,
    ('video.aspectRatio', "Fit") =>
      strings.settings_video_aspectRatio_choice_Fit,
    ('video.aspectRatio', "Fill") =>
      strings.settings_video_aspectRatio_choice_Fill,
    ('video.aspectRatio', "Stretch") =>
      strings.settings_video_aspectRatio_choice_Stretch,
    ('video.decoder', "hardware") =>
      strings.settings_video_decoder_choice_hardware,
    ('video.decoder', "software") =>
      strings.settings_video_decoder_choice_software,
    ('video.scalingQuality', "Fast") =>
      strings.settings_video_scalingQuality_choice_Fast,
    ('video.scalingQuality', "Balanced") =>
      strings.settings_video_scalingQuality_choice_Balanced,
    ('video.scalingQuality', "High") =>
      strings.settings_video_scalingQuality_choice_High,
    ('video.toneMapping', "clip") =>
      strings.settings_video_toneMapping_choice_clip,
    ('video.toneMapping', "mobius") =>
      strings.settings_video_toneMapping_choice_mobius,
    ('video.toneMapping', "reinhard") =>
      strings.settings_video_toneMapping_choice_reinhard,
    ('video.toneMapping', "hable") =>
      strings.settings_video_toneMapping_choice_hable,
    ('video.toneMapping', "gamma") =>
      strings.settings_video_toneMapping_choice_gamma,
    ('video.toneMapping', "linear") =>
      strings.settings_video_toneMapping_choice_linear,
    ('video.toneMapping', "spline") =>
      strings.settings_video_toneMapping_choice_spline,
    ('video.toneMapping', "bt.2390") =>
      strings.settings_video_toneMapping_choice_bt_2390,
    ('video.toneMapping', "bt.2446a") =>
      strings.settings_video_toneMapping_choice_bt_2446a,
    ('video.toneMapping', "st2094-40") =>
      strings.settings_video_toneMapping_choice_st2094_40,
    ('video.toneMapping', "st2094-10") =>
      strings.settings_video_toneMapping_choice_st2094_10,
    ('video.pixelFormat', "nv12") =>
      strings.settings_video_pixelFormat_choice_nv12,
    ('video.pixelFormat', "yuv420p") =>
      strings.settings_video_pixelFormat_choice_yuv420p,
    ('video.pixelFormat', "yuv420p10") =>
      strings.settings_video_pixelFormat_choice_yuv420p10,
    ('video.pixelFormat', "yuv422p") =>
      strings.settings_video_pixelFormat_choice_yuv422p,
    ('video.pixelFormat', "yuv422p10") =>
      strings.settings_video_pixelFormat_choice_yuv422p10,
    ('video.pixelFormat', "yuv444p") =>
      strings.settings_video_pixelFormat_choice_yuv444p,
    ('video.pixelFormat', "yuv444p10") =>
      strings.settings_video_pixelFormat_choice_yuv444p10,
    ('video.pixelFormat', "rgb24") =>
      strings.settings_video_pixelFormat_choice_rgb24,
    ('video.chroma', "4:2:0") => strings.settings_video_chroma_choice_4_2_0,
    ('video.chroma', "4:2:2") => strings.settings_video_chroma_choice_4_2_2,
    ('video.chroma', "4:4:4") => strings.settings_video_chroma_choice_4_4_4,
    ('video.dithering', "fruit") =>
      strings.settings_video_dithering_choice_fruit,
    ('video.dithering', "ordered") =>
      strings.settings_video_dithering_choice_ordered,
    ('video.gpuRendering', "opengl") =>
      strings.settings_video_gpuRendering_choice_opengl,
    ('audio.speakerLayout', "Stereo") =>
      strings.settings_audio_speakerLayout_choice_Stereo,
    ('audio.outputMode', "Best Match") =>
      strings.settings_audio_outputMode_choice_Best_Match,
    ('audio.outputMode', "Fixed") =>
      strings.settings_audio_outputMode_choice_Fixed,
    ('audio.outputMode', "Optimized") =>
      strings.settings_audio_outputMode_choice_Optimized,
    ('audio.resamplingQuality', "Fast") =>
      strings.settings_audio_resamplingQuality_choice_Fast,
    ('audio.resamplingQuality', "Balanced") =>
      strings.settings_audio_resamplingQuality_choice_Balanced,
    ('audio.resamplingQuality', "High") =>
      strings.settings_audio_resamplingQuality_choice_High,
    ('subtitles.hearingImpaired', "Prefer") =>
      strings.settings_subtitles_hearingImpaired_choice_Prefer,
    ('subtitles.hearingImpaired', "Avoid") =>
      strings.settings_subtitles_hearingImpaired_choice_Avoid,
    ('subtitles.hearingImpaired', "No preference") =>
      strings.settings_subtitles_hearingImpaired_choice_No_preference,
    ('subtitles.encoding', "utf-8") =>
      strings.settings_subtitles_encoding_choice_utf_8,
    ('subtitles.encoding', "cp1250") =>
      strings.settings_subtitles_encoding_choice_cp1250,
    ('subtitles.encoding', "cp1251") =>
      strings.settings_subtitles_encoding_choice_cp1251,
    ('subtitles.encoding', "cp1252") =>
      strings.settings_subtitles_encoding_choice_cp1252,
    ('subtitles.encoding', "cp1253") =>
      strings.settings_subtitles_encoding_choice_cp1253,
    ('subtitles.encoding', "cp1254") =>
      strings.settings_subtitles_encoding_choice_cp1254,
    ('subtitles.encoding', "cp1256") =>
      strings.settings_subtitles_encoding_choice_cp1256,
    ('subtitles.encoding', "iso-8859-1") =>
      strings.settings_subtitles_encoding_choice_iso_8859_1,
    ('subtitles.encoding', "iso-8859-2") =>
      strings.settings_subtitles_encoding_choice_iso_8859_2,
    ('subtitles.encoding', "shift_jis") =>
      strings.settings_subtitles_encoding_choice_shift_jis,
    ('subtitles.encoding', "gbk") =>
      strings.settings_subtitles_encoding_choice_gbk,
    ('subtitles.encoding', "big5") =>
      strings.settings_subtitles_encoding_choice_big5,
    ('subtitles.encoding', "euc-kr") =>
      strings.settings_subtitles_encoding_choice_euc_kr,
    ('subtitles.forcedBehaviour', "Always") =>
      strings.settings_subtitles_forcedBehaviour_choice_Always,
    ('subtitles.forcedBehaviour', "Never") =>
      strings.settings_subtitles_forcedBehaviour_choice_Never,
    ('subtitles.assStyling', "Embedded") =>
      strings.settings_subtitles_assStyling_choice_Embedded,
    ('subtitles.assStyling', "Override") =>
      strings.settings_subtitles_assStyling_choice_Override,
    ('subtitles.assStyling', "Hybrid") =>
      strings.settings_subtitles_assStyling_choice_Hybrid,
    ('display.fullscreenMode', "Windowed") =>
      strings.settings_display_fullscreenMode_choice_Windowed,
    ('display.fullscreenMode', "Fullscreen") =>
      strings.settings_display_fullscreenMode_choice_Fullscreen,
    ('display.hdrOutputMode', "SDR") =>
      strings.settings_display_hdrOutputMode_choice_SDR,
    ('display.hdrOutputMode', "HDR10") =>
      strings.settings_display_hdrOutputMode_choice_HDR10,
    ('display.hdrOutputMode', "Dolby Vision") =>
      strings.settings_display_hdrOutputMode_choice_Dolby_Vision,
    ('streaming.quality', "Original") =>
      strings.settings_streaming_quality_choice_Original,
    ('streaming.protocol', "HTTP") =>
      strings.settings_streaming_protocol_choice_HTTP,
    ('streaming.protocol', "Torrent") =>
      strings.settings_streaming_protocol_choice_Torrent,
    ('streaming.tls', "Verify") => strings.settings_streaming_tls_choice_Verify,
    ('streaming.tls', "Don't verify") =>
      strings.settings_streaming_tls_choice_Don_t_verify,
    ('downloads.seeding', "ratio") =>
      strings.settings_downloads_seeding_choice_ratio,
    ('downloads.seeding', "duration") =>
      strings.settings_downloads_seeding_choice_duration,
    ('languages.preferBestAudio', "Atmos") =>
      strings.settings_languages_preferBestAudio_choice_Atmos,
    ('languages.preferBestAudio', "lossless") =>
      strings.settings_languages_preferBestAudio_choice_lossless,
    ('languages.preferBestAudio', "highest-channel") =>
      strings.settings_languages_preferBestAudio_choice_highest_channel,
    ('performance.mode', "Battery saver") =>
      strings.settings_performance_mode_choice_Battery_saver,
    ('performance.mode', "Quality") =>
      strings.settings_performance_mode_choice_Quality,
    ('performance.gpuQuality', "Fast") =>
      strings.settings_performance_gpuQuality_choice_Fast,
    ('performance.gpuQuality', "High") =>
      strings.settings_performance_gpuQuality_choice_High,
    ('playback.defaultSubtitleSize', "Small") =>
      strings.settings_playback_defaultSubtitleSize_choice_Small,
    ('playback.defaultSubtitleSize', "Normal") =>
      strings.settings_playback_defaultSubtitleSize_choice_Normal,
    ('playback.defaultSubtitleSize', "Large") =>
      strings.settings_playback_defaultSubtitleSize_choice_Large,
    ('playback.defaultSubtitleSize', "Extra large") =>
      strings.settings_playback_defaultSubtitleSize_choice_Extra_large,
    ('app.language', "system") => strings.settings_language_system,
    ('app.language', "en") => strings.settings_language_en,
    ('app.language', "fa") => strings.settings_language_fa,
    (_, '') => strings.settings_none,
    _ => value,
  };
}

/// Deferred settings explain when they apply; immediate settings need no note.
String? applyNote(SettingDef def, AppStrings strings) =>
    def.kind == SettingKind.page
    ? null
    : switch (def.apply) {
        SettingApply.live => null,
        SettingApply.nextVideo => strings.settings_applyNext,
        SettingApply.restart => strings.settings_restartNeeded,
      };

String settingUnit(String unit, AppStrings strings) => switch (unit) {
  'connections' => strings.settings_unit_connections,
  'retries' => strings.settings_unit_retries,
  'peers' => strings.settings_unit_peers,
  'threads' => strings.settings_unit_threads,
  's' => strings.settings_unit_seconds,
  'px' => strings.settings_unit_px,
  'dB' => strings.settings_unit_dB,
  'MB' => strings.settings_unit_MB,
  'KB/s' => strings.settings_unit_KBps,
  '%' => strings.settings_unit_percent,
  _ => unit,
};
