// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_strings.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppStringsEn extends AppStrings {
  AppStringsEn([String locale = 'en']) : super(locale);

  @override
  String get app_title => 'GenoTV';

  @override
  String get settings_language_title => 'Language';

  @override
  String get settings_language_system => 'System default';

  @override
  String get settings_language_en => 'English';

  @override
  String get settings_language_fa => 'فارسی';

  @override
  String get common_retry => 'Retry';

  @override
  String get common_cancel => 'Cancel';

  @override
  String get common_close => 'Close';

  @override
  String get common_back => 'Back';

  @override
  String get common_play => 'Play';

  @override
  String get common_resume => 'Resume';

  @override
  String get common_seeAll => 'See all';

  @override
  String get common_loading => 'Loading…';

  @override
  String get common_details => 'Details';

  @override
  String get common_on => 'On';

  @override
  String get common_off => 'Off';

  @override
  String get common_auto => 'Auto';

  @override
  String get common_anyYear => 'Any year';

  @override
  String get common_apply => 'Apply';

  @override
  String get common_clear => 'Clear';

  @override
  String get common_clearAll => 'Clear all';

  @override
  String get common_default => 'Default';

  @override
  String get common_genres => 'Genres';

  @override
  String get common_less => 'Less';

  @override
  String get common_more => 'More';

  @override
  String get common_movies => 'Movies';

  @override
  String get common_pause => 'Pause';

  @override
  String get common_playLink => 'Play link';

  @override
  String get common_search => 'Search';

  @override
  String get common_tv => 'TV';

  @override
  String get common_tvShows => 'TV shows';

  @override
  String get common_watched => 'Watched';

  @override
  String get common_liked => 'Liked';

  @override
  String get common_home => 'Home';

  @override
  String get common_settings => 'Settings';

  @override
  String get artwork_unavailable => 'Artwork unavailable';

  @override
  String get cast_airPlay => 'AirPlay';

  @override
  String get cast_checking => 'Checking…';

  @override
  String get cast_looking => 'Looking for devices…';

  @override
  String get cast_notCompatible => 'This device can\'t play this file';

  @override
  String get cast_stop => 'Stop casting';

  @override
  String get cast_title => 'Cast';

  @override
  String get detail_about => 'About';

  @override
  String get detail_cast => 'Cast';

  @override
  String get detail_info => 'Info';

  @override
  String get detail_kindMovie => 'Movie';

  @override
  String get detail_kindTvShow => 'TV Show';

  @override
  String get detail_like => 'Like';

  @override
  String get detail_moreLikeThis => 'More like this';

  @override
  String get detail_trailer => 'Trailer';

  @override
  String get detail_trailers => 'Trailers';

  @override
  String get detail_unlike => 'Remove from Liked';

  @override
  String get detail_watchlist => 'Watchlist';

  @override
  String get episode_details => 'Episode details';

  @override
  String get filter_allCountries => 'All countries';

  @override
  String get filter_country => 'Country';

  @override
  String get filter_sort => 'Sort';

  @override
  String get genres_noMatch => 'No genres match';

  @override
  String get genres_search => 'Search genres';

  @override
  String get grid_loadFailed => 'Could not load titles';

  @override
  String get library_empty => 'Your library is empty';

  @override
  String get library_noMatch => 'No titles match this filter';

  @override
  String get library_openFeatured => 'Open featured title';

  @override
  String get library_refresh => 'Refresh library';

  @override
  String get library_searchTitle => 'Search title';

  @override
  String get library_series => 'Series';

  @override
  String get menu_mediaOptions => 'Media options';

  @override
  String get person_knownFor => 'Known for';

  @override
  String get playlink_clearConfirm => 'Clear all recent links?';

  @override
  String get playlink_hint => 'Torrent / https link';

  @override
  String get playlink_import => 'Import .torrent';

  @override
  String get playlink_insert => 'Insert link';

  @override
  String get playlink_recent => 'Recent';

  @override
  String get playlink_recentEmpty => 'Links you play will appear here.';

  @override
  String get play_finding => 'Finding sources…';

  @override
  String get play_infoFileName => 'File name';

  @override
  String get play_infoRelease => 'Release';

  @override
  String get play_insertLink => 'Insert link…';

  @override
  String get play_pickProvider => 'Pick a provider';

  @override
  String get play_refresh => 'Refresh';

  @override
  String get play_sortSeeds => 'Seeds';

  @override
  String get play_sortSize => 'Size';

  @override
  String get play_sortStreams => 'Sort streams';

  @override
  String get play_torrent => 'Torrent';

  @override
  String get row_scrollLeft => 'Scroll left';

  @override
  String get row_scrollRight => 'Scroll right';

  @override
  String get search_hint => 'Search your libraries';

  @override
  String get search_noResults => 'No results';

  @override
  String get search_noResultsBody => 'Check the spelling or try another title.';

  @override
  String get search_promptTitle => 'Search movies and shows';

  @override
  String get search_promptBody => 'Type a title, a person or a year.';

  @override
  String get search_recent => 'Recent searches';

  @override
  String get sort_popularity => 'Popularity';

  @override
  String get sort_rating => 'Rating';

  @override
  String get sort_releaseDate => 'Release date';

  @override
  String get sort_titleAz => 'Title A–Z';

  @override
  String get state_emptyTitle => 'Nothing here yet';

  @override
  String get year_from => 'From';

  @override
  String get year_pastYear => 'Past year';

  @override
  String get year_range => 'Range';

  @override
  String get year_single => 'Single';

  @override
  String get year_singleOrRange => 'Single year or range';

  @override
  String get year_title => 'Year';

  @override
  String get year_to => 'To';

  @override
  String get failure_transportHttpNoRangeSupport =>
      'This HTTP source does not support seeking.';

  @override
  String get failure_transportHttpValidatorChanged =>
      'The HTTP file changed while it was loading.';

  @override
  String get failure_transportHttpUnreachable =>
      'The HTTP source could not be reached.';

  @override
  String get failure_transportRangeUnsatisfiable =>
      'The requested media range is unavailable.';

  @override
  String get failure_transportTorrentNoMetadata =>
      'Torrent metadata did not arrive in time.';

  @override
  String get failure_transportTorrentNoPeers =>
      'This torrent has no available peers.';

  @override
  String get failure_transportTorrentStalled =>
      'The torrent stopped delivering the requested media.';

  @override
  String get failure_transportTorrentFileError =>
      'The torrent could not access its media files.';

  @override
  String get failure_transportTorrentFileNotFound =>
      'The requested file is not in the torrent.';

  @override
  String get failure_transportEngineUnavailable =>
      'The streaming engine is unavailable on this device.';

  @override
  String get failure_transportLocalNotFound =>
      'The local file could not be found.';

  @override
  String get failure_transportLocalNotReadable =>
      'The local file could not be read.';

  @override
  String get failure_transportLocalEmpty => 'The local file is empty.';

  @override
  String get failure_transportLocalUnsupportedUri =>
      'This local source URI is not supported.';

  @override
  String get failure_playbackOpenFailed => 'The media could not be opened.';

  @override
  String get failure_playbackDecodeFailed => 'The media could not be decoded.';

  @override
  String get failure_playbackEngineCrashed =>
      'The playback engine stopped unexpectedly.';

  @override
  String get failure_playbackSourceUnreachable =>
      'The playback source became unreachable.';

  @override
  String get failure_playbackUnsupportedCodec =>
      'This media uses an unsupported codec.';

  @override
  String get failure_playbackTrackSelectionFailed =>
      'The requested playback track could not be selected.';

  @override
  String get failure_playbackSubtitleLoadFailed =>
      'The external subtitle could not be loaded.';

  @override
  String get failure_platformUnsupported =>
      'This operation is not supported on this platform.';

  @override
  String get failure_platformPermissionDenied =>
      'The platform denied the required permission.';

  @override
  String get failure_platformDisplaySwitchFailed =>
      'The display mode could not be changed.';

  @override
  String get failure_platformAudioDeviceLost =>
      'The selected audio device is no longer available.';

  @override
  String get failure_platformProbeFailed =>
      'Platform capabilities could not be determined.';

  @override
  String get failure_appUnexpected =>
      'The application encountered an unexpected failure.';

  @override
  String get failure_appCancelled =>
      'The operation was cancelled before completion.';

  @override
  String badge_progress(String percent) {
    return 'Progress $percent percent';
  }

  @override
  String badge_unwatchedEpisodes(int count, String number) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$number unwatched episodes',
    );
    return '$_temp0';
  }

  @override
  String cast_castingTo(String device) {
    return 'Casting to $device';
  }

  @override
  String detail_browse(String label) {
    return 'Browse $label';
  }

  @override
  String detail_resumeAt(String time) {
    return 'Resume $time';
  }

  @override
  String episode_title(String number, String title) {
    return 'E$number · $title';
  }

  @override
  String episode_minutes(String minutes) {
    return '$minutes min';
  }

  @override
  String filter_sortBy(String sort) {
    return 'Sort: $sort';
  }

  @override
  String filter_yearRange(String from, String to) {
    return '$from – $to';
  }

  @override
  String home_featuredItem(String index, String count) {
    return 'Featured item $index of $count';
  }

  @override
  String playlink_remove(String label) {
    return 'Remove $label';
  }

  @override
  String play_seeders(int count, String number) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$number seeders',
    );
    return '$_temp0';
  }

  @override
  String rating_imdb(String score) {
    return 'IMDb rating $score';
  }

  @override
  String rating_tmdb(String score) {
    return 'TMDB rating $score';
  }

  @override
  String rating_tomatoFresh(String score) {
    return 'Rotten Tomatoes fresh $score';
  }

  @override
  String rating_tomatoRotten(String score) {
    return 'Rotten Tomatoes rotten $score';
  }

  @override
  String get shelf_removeContinue => 'Remove from Continue Watching';

  @override
  String year_lastYears(int count, String number) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Last $number years',
    );
    return '$_temp0';
  }

  @override
  String failure_unknown(String code) {
    return 'Something went wrong while processing this request ($code).';
  }

  @override
  String get common_dismiss => 'Dismiss';

  @override
  String get state_errorTitle => 'Unable to continue';

  @override
  String get state_hideCode => 'Hide error code';

  @override
  String get state_showCode => 'Show error code';

  @override
  String get state_offline => 'You\'re offline';

  @override
  String get state_offlineBody =>
      'Check your connection. We\'ll retry automatically.';

  @override
  String get state_reconnecting => 'Reconnecting…';

  @override
  String get state_retryFailed => 'Still offline. Try again.';

  @override
  String get home_trendingMovies => 'Trending Movies';

  @override
  String get home_trendingShows => 'Trending Shows';

  @override
  String get liked_emptyTitle => 'No liked titles yet';

  @override
  String get liked_emptyBody => 'Titles you like appear here.';

  @override
  String get liked_browseMovies => 'Browse movies';

  @override
  String get app_resolvingCache => 'resolving cache path…';

  @override
  String get state_loading => 'Loading';

  @override
  String get playlink_badMagnet => 'Not a playable link: bad magnet link.';

  @override
  String get playlink_invalid => 'Not a playable link.';

  @override
  String playlink_fileMissing(String path) {
    return 'Torrent file not found: $path';
  }

  @override
  String playlink_unreachable(String host) {
    return 'Could not reach $host.';
  }

  @override
  String playlink_httpStatus(String status) {
    return 'The torrent link answered $status.';
  }

  @override
  String get playlink_tooLarge => 'The torrent file is larger than 10 MB.';

  @override
  String get playlink_notTorrent => 'The link did not return a torrent file.';

  @override
  String playlink_downloadFailed(String host) {
    return 'Could not download the torrent from $host.';
  }

  @override
  String get play_providerUnavailable =>
      'This provider is unavailable right now.';

  @override
  String cast_failedToCast(String device) {
    return 'Couldn\'t cast to $device';
  }

  @override
  String get subtitle_picker => 'Subtitles';

  @override
  String get subtitle_invalidZip => 'Not a valid zip file.';

  @override
  String get subtitle_damagedDirectory => 'Zip directory is damaged.';

  @override
  String subtitle_unsafeName(String name) {
    return 'Unsafe file name in zip: $name';
  }

  @override
  String subtitle_encrypted(String name) {
    return 'Zip entry is encrypted: $name';
  }

  @override
  String subtitle_entryTooLarge(String name) {
    return 'Subtitle in zip is too large: $name';
  }

  @override
  String subtitle_unsupportedCompression(String name) {
    return 'Unsupported zip compression: $name';
  }

  @override
  String subtitle_damagedEntry(String name) {
    return 'Zip entry is damaged: $name';
  }

  @override
  String get subtitle_damagedZip => 'Zip file is damaged.';

  @override
  String get subtitle_emptyZip => 'No subtitle files found in the zip.';

  @override
  String subtitle_unsupportedType(String name) {
    return 'Unsupported file type: $name';
  }

  @override
  String subtitle_fileTooLarge(String name) {
    return 'File is too large: $name';
  }

  @override
  String subtitle_readFailed(String name, String error) {
    return 'Could not read $name: $error';
  }

  @override
  String get settings_playback_resume_label => 'Resume playback';

  @override
  String get settings_playback_autoPlayNext_label => 'Auto-play next episode';

  @override
  String get settings_playback_rememberPosition_label => 'Remember position';

  @override
  String get settings_playback_speed_label => 'Playback speed';

  @override
  String get settings_playback_syncToDisplay_label => 'Sync to display';

  @override
  String get settings_playback_avSyncCorrection_label => 'A/V sync correction';

  @override
  String get settings_playback_cachePreset_label => 'Cache preset';

  @override
  String get settings_playback_demuxerCacheSize_label => 'Demuxer cache size';

  @override
  String get settings_playback_readAhead_label => 'Read ahead';

  @override
  String get settings_playback_networkTimeout_label => 'Network timeout';

  @override
  String get settings_video_hwdec_label => 'Hardware decoding';

  @override
  String get settings_video_hdr_label => 'HDR handling';

  @override
  String get settings_video_matchFrameRate_label => 'Match frame rate';

  @override
  String get settings_video_matchResolution_label => 'Match resolution';

  @override
  String get settings_video_aspectRatio_label => 'Aspect ratio';

  @override
  String get settings_video_decoder_label => 'Video decoder';

  @override
  String get settings_video_scalingQuality_label => 'Scaling quality';

  @override
  String get settings_video_toneMapping_label => 'HDR to SDR tone mapping';

  @override
  String get settings_video_pixelFormat_label => 'Pixel format';

  @override
  String get settings_video_bitDepth_label => 'Bit depth';

  @override
  String get settings_video_chroma_label => 'Chroma';

  @override
  String get settings_video_dithering_label => 'Dithering';

  @override
  String get settings_video_interpolation_label => 'Interpolation';

  @override
  String get settings_video_debanding_label => 'Debanding';

  @override
  String get settings_video_gpuRendering_label => 'GPU rendering options';

  @override
  String get settings_video_displayModeWhitelist_label =>
      'Display mode whitelist';

  @override
  String get settings_audio_outputDevice_label => 'Output device';

  @override
  String get settings_audio_speakerLayout_label => 'Speaker layout';

  @override
  String get settings_audio_normalizeVolume_label => 'Normalize volume';

  @override
  String get settings_audio_outputMode_label => 'Output mode';

  @override
  String get settings_audio_passthrough_label => 'Passthrough';

  @override
  String get settings_audio_passthroughDevice_label => 'Passthrough device';

  @override
  String get settings_audio_receiver_dolbyDigital_label =>
      'Receiver supports Dolby Digital';

  @override
  String get settings_audio_receiver_ddPlus_label =>
      'Receiver supports Dolby Digital Plus';

  @override
  String get settings_audio_receiver_dts_label => 'Receiver supports DTS';

  @override
  String get settings_audio_receiver_trueHd_label =>
      'Receiver supports Dolby TrueHD';

  @override
  String get settings_audio_receiver_dtsHd_label => 'Receiver supports DTS-HD';

  @override
  String get settings_audio_receiver_atmos_label =>
      'Receiver supports Dolby Atmos';

  @override
  String get settings_audio_receiver_dtsX_label => 'Receiver supports DTS:X';

  @override
  String get settings_audio_multichannelLpcm_label => 'Multichannel LPCM';

  @override
  String get settings_audio_ac3Transcode_label => 'AC3 transcoding';

  @override
  String get settings_audio_stereoUpmix_label => 'Stereo upmix';

  @override
  String get settings_audio_downmixDialogue_label => 'Downmix dialogue';

  @override
  String get settings_audio_resamplingQuality_label => 'Resampling quality';

  @override
  String get settings_audio_sampleRate_label => 'Sample rate';

  @override
  String get settings_audio_exclusiveMode_label => 'Exclusive mode';

  @override
  String get settings_audio_deviceKeepAlive_label => 'Device keep alive';

  @override
  String get settings_subtitles_autoEnable_label => 'Auto enable';

  @override
  String get settings_subtitles_hearingImpaired_label => 'Hearing impaired';

  @override
  String get settings_subtitles_font_label => 'Font';

  @override
  String get settings_subtitles_position_label => 'Position';

  @override
  String get settings_subtitles_encoding_label => 'Encoding';

  @override
  String get settings_subtitles_border_label => 'Border';

  @override
  String get settings_subtitles_shadow_label => 'Shadow';

  @override
  String get settings_subtitles_background_label => 'Background';

  @override
  String get settings_subtitles_delay_label => 'Delay';

  @override
  String get settings_subtitles_forcedBehaviour_label => 'Forced behaviour';

  @override
  String get settings_subtitles_assStyling_label => 'ASS/SSA styling';

  @override
  String get settings_display_monitor_label => 'Monitor';

  @override
  String get settings_display_fullscreenMode_label => 'Fullscreen mode';

  @override
  String get settings_display_refreshRate_label => 'Refresh rate';

  @override
  String get settings_display_hdrOutputMode_label => 'Hdr output mode';

  @override
  String get settings_display_calibration_label => 'Calibration';

  @override
  String get settings_streaming_quality_label => 'Quality';

  @override
  String get settings_streaming_protocol_label => 'Protocol';

  @override
  String get settings_streaming_cacheSizeLimit_label => 'Cache size limit';

  @override
  String get settings_streaming_bufferSize_label => 'Buffer size';

  @override
  String get settings_streaming_prebuffer_label => 'Prebuffer';

  @override
  String get settings_streaming_maxHttpConnections_label =>
      'Max HTTP connections';

  @override
  String get settings_streaming_connectionTimeout_label => 'Connection timeout';

  @override
  String get settings_streaming_retryCount_label => 'Retry count';

  @override
  String get settings_streaming_proxy_label => 'Proxy';

  @override
  String get settings_streaming_userAgent_label => 'User agent';

  @override
  String get settings_streaming_headers_label => 'Custom HTTP headers';

  @override
  String get settings_streaming_tls_label => 'TLS options';

  @override
  String get settings_downloads_bandwidthLimit_label => 'Bandwidth limit';

  @override
  String get settings_downloads_torrentDownLimit_label => 'Torrent down limit';

  @override
  String get settings_downloads_torrentUpLimit_label => 'Torrent up limit';

  @override
  String get settings_downloads_connectionLimit_label => 'Connection limit';

  @override
  String get settings_downloads_peerLimit_label => 'Peer limit';

  @override
  String get settings_downloads_seeding_label => 'Seeding';

  @override
  String get settings_downloads_tracker_label => 'Tracker';

  @override
  String get settings_downloads_dht_label => 'DHT';

  @override
  String get settings_downloads_pex_label => 'PEX';

  @override
  String get settings_languages_preferOriginalAudio_label =>
      'Prefer original audio';

  @override
  String get settings_languages_preferForcedSubtitles_label =>
      'Prefer forced subtitles';

  @override
  String get settings_languages_preferBestAudio_label => 'Prefer best audio';

  @override
  String get settings_languages_trackPriority_label => 'Track priority';

  @override
  String get settings_performance_mode_label => 'Mode';

  @override
  String get settings_performance_gpuQuality_label => 'GPU quality';

  @override
  String get settings_performance_backgroundPreload_label =>
      'Background preload';

  @override
  String get settings_performance_decoderThreads_label => 'Decoder threads';

  @override
  String get settings_advanced_diagnostics_label => 'Playback diagnostics';

  @override
  String get settings_advanced_customMpvOptions_label => 'Custom mpv options';

  @override
  String get settings_playback_preferredAudioLanguage_label =>
      'Preferred audio language';

  @override
  String get settings_playback_preferredSubtitleLanguage_label =>
      'Preferred subtitle language';

  @override
  String get settings_playback_defaultSubtitleSize_label => 'Subtitle size';

  @override
  String get settings_app_language_label => 'Language';

  @override
  String get settings_language_choice_en => 'English';

  @override
  String get settings_language_choice_fa => 'Persian';

  @override
  String get settings_language_choice_ar => 'Arabic';

  @override
  String get settings_language_choice_fr => 'French';

  @override
  String get settings_language_choice_de => 'German';

  @override
  String get settings_language_choice_es => 'Spanish';

  @override
  String get settings_language_choice_tr => 'Turkish';

  @override
  String get settings_language_choice_ru => 'Russian';

  @override
  String get settings_language_choice_ja => 'Japanese';

  @override
  String get settings_language_choice_ko => 'Korean';

  @override
  String get settings_language_choice_zh => 'Chinese';

  @override
  String get settings_playback_resume_choice_Ask => 'Ask';

  @override
  String get settings_playback_resume_choice_Always => 'Always';

  @override
  String get settings_playback_resume_choice_Never => 'Never';

  @override
  String get settings_playback_cachePreset_choice_Low_latency => 'Low latency';

  @override
  String get settings_playback_cachePreset_choice_Balanced => 'Balanced';

  @override
  String get settings_playback_cachePreset_choice_Large => 'Large';

  @override
  String get settings_video_hdr_choice_Force_SDR => 'Force SDR';

  @override
  String get settings_video_hdr_choice_Passthrough_HDR => 'Passthrough HDR';

  @override
  String get settings_video_matchFrameRate_choice_On_start_stop =>
      'On start-stop';

  @override
  String get settings_video_matchFrameRate_choice_Always => 'Always';

  @override
  String get settings_video_aspectRatio_choice_Original => 'Original';

  @override
  String get settings_video_aspectRatio_choice_Fit => 'Fit';

  @override
  String get settings_video_aspectRatio_choice_Fill => 'Fill';

  @override
  String get settings_video_aspectRatio_choice_Stretch => 'Stretch';

  @override
  String get settings_video_decoder_choice_hardware => 'hardware';

  @override
  String get settings_video_decoder_choice_software => 'software';

  @override
  String get settings_video_scalingQuality_choice_Fast => 'Fast';

  @override
  String get settings_video_scalingQuality_choice_Balanced => 'Balanced';

  @override
  String get settings_video_scalingQuality_choice_High => 'High';

  @override
  String get settings_video_toneMapping_choice_clip => 'clip';

  @override
  String get settings_video_toneMapping_choice_mobius => 'mobius';

  @override
  String get settings_video_toneMapping_choice_reinhard => 'reinhard';

  @override
  String get settings_video_toneMapping_choice_hable => 'hable';

  @override
  String get settings_video_toneMapping_choice_gamma => 'gamma';

  @override
  String get settings_video_toneMapping_choice_linear => 'linear';

  @override
  String get settings_video_toneMapping_choice_spline => 'spline';

  @override
  String get settings_video_toneMapping_choice_bt_2390 => 'bt.2390';

  @override
  String get settings_video_toneMapping_choice_bt_2446a => 'bt.2446a';

  @override
  String get settings_video_toneMapping_choice_st2094_40 => 'st2094-40';

  @override
  String get settings_video_toneMapping_choice_st2094_10 => 'st2094-10';

  @override
  String get settings_video_pixelFormat_choice_nv12 => 'nv12';

  @override
  String get settings_video_pixelFormat_choice_yuv420p => 'yuv420p';

  @override
  String get settings_video_pixelFormat_choice_yuv420p10 => 'yuv420p10';

  @override
  String get settings_video_pixelFormat_choice_yuv422p => 'yuv422p';

  @override
  String get settings_video_pixelFormat_choice_yuv422p10 => 'yuv422p10';

  @override
  String get settings_video_pixelFormat_choice_yuv444p => 'yuv444p';

  @override
  String get settings_video_pixelFormat_choice_yuv444p10 => 'yuv444p10';

  @override
  String get settings_video_pixelFormat_choice_rgb24 => 'rgb24';

  @override
  String get settings_video_chroma_choice_4_2_0 => '4:2:0';

  @override
  String get settings_video_chroma_choice_4_2_2 => '4:2:2';

  @override
  String get settings_video_chroma_choice_4_4_4 => '4:4:4';

  @override
  String get settings_video_dithering_choice_fruit => 'fruit';

  @override
  String get settings_video_dithering_choice_ordered => 'ordered';

  @override
  String get settings_video_gpuRendering_choice_opengl => 'opengl';

  @override
  String get settings_audio_speakerLayout_choice_Stereo => 'Stereo';

  @override
  String get settings_audio_outputMode_choice_Best_Match => 'Best Match';

  @override
  String get settings_audio_outputMode_choice_Fixed => 'Fixed';

  @override
  String get settings_audio_outputMode_choice_Optimized => 'Optimized';

  @override
  String get settings_audio_resamplingQuality_choice_Fast => 'Fast';

  @override
  String get settings_audio_resamplingQuality_choice_Balanced => 'Balanced';

  @override
  String get settings_audio_resamplingQuality_choice_High => 'High';

  @override
  String get settings_subtitles_hearingImpaired_choice_Prefer => 'Prefer';

  @override
  String get settings_subtitles_hearingImpaired_choice_Avoid => 'Avoid';

  @override
  String get settings_subtitles_hearingImpaired_choice_No_preference =>
      'No preference';

  @override
  String get settings_subtitles_encoding_choice_utf_8 => 'utf-8';

  @override
  String get settings_subtitles_encoding_choice_cp1250 => 'cp1250';

  @override
  String get settings_subtitles_encoding_choice_cp1251 => 'cp1251';

  @override
  String get settings_subtitles_encoding_choice_cp1252 => 'cp1252';

  @override
  String get settings_subtitles_encoding_choice_cp1253 => 'cp1253';

  @override
  String get settings_subtitles_encoding_choice_cp1254 => 'cp1254';

  @override
  String get settings_subtitles_encoding_choice_cp1256 => 'cp1256';

  @override
  String get settings_subtitles_encoding_choice_iso_8859_1 => 'iso-8859-1';

  @override
  String get settings_subtitles_encoding_choice_iso_8859_2 => 'iso-8859-2';

  @override
  String get settings_subtitles_encoding_choice_shift_jis => 'shift_jis';

  @override
  String get settings_subtitles_encoding_choice_gbk => 'gbk';

  @override
  String get settings_subtitles_encoding_choice_big5 => 'big5';

  @override
  String get settings_subtitles_encoding_choice_euc_kr => 'euc-kr';

  @override
  String get settings_subtitles_forcedBehaviour_choice_Always => 'Always';

  @override
  String get settings_subtitles_forcedBehaviour_choice_Never => 'Never';

  @override
  String get settings_subtitles_assStyling_choice_Embedded => 'Embedded';

  @override
  String get settings_subtitles_assStyling_choice_Override => 'Override';

  @override
  String get settings_subtitles_assStyling_choice_Hybrid => 'Hybrid';

  @override
  String get settings_display_fullscreenMode_choice_Windowed => 'Windowed';

  @override
  String get settings_display_fullscreenMode_choice_Fullscreen => 'Fullscreen';

  @override
  String get settings_display_hdrOutputMode_choice_SDR => 'SDR';

  @override
  String get settings_display_hdrOutputMode_choice_HDR10 => 'HDR10';

  @override
  String get settings_display_hdrOutputMode_choice_Dolby_Vision =>
      'Dolby Vision';

  @override
  String get settings_streaming_quality_choice_Original => 'Original';

  @override
  String get settings_streaming_protocol_choice_HTTP => 'HTTP';

  @override
  String get settings_streaming_protocol_choice_Torrent => 'Torrent';

  @override
  String get settings_streaming_tls_choice_Verify => 'Verify';

  @override
  String get settings_streaming_tls_choice_Don_t_verify => 'Don\'t verify';

  @override
  String get settings_downloads_seeding_choice_ratio => 'ratio';

  @override
  String get settings_downloads_seeding_choice_duration => 'duration';

  @override
  String get settings_languages_preferBestAudio_choice_Atmos => 'Atmos';

  @override
  String get settings_languages_preferBestAudio_choice_lossless => 'lossless';

  @override
  String get settings_languages_preferBestAudio_choice_highest_channel =>
      'highest-channel';

  @override
  String get settings_performance_mode_choice_Battery_saver => 'Battery saver';

  @override
  String get settings_performance_mode_choice_Quality => 'Quality';

  @override
  String get settings_performance_gpuQuality_choice_Fast => 'Fast';

  @override
  String get settings_performance_gpuQuality_choice_High => 'High';

  @override
  String get settings_playback_defaultSubtitleSize_choice_Small => 'Small';

  @override
  String get settings_playback_defaultSubtitleSize_choice_Normal => 'Normal';

  @override
  String get settings_playback_defaultSubtitleSize_choice_Large => 'Large';

  @override
  String get settings_playback_defaultSubtitleSize_choice_Extra_large =>
      'Extra large';

  @override
  String get settings_forcedOnly => 'Forced only';

  @override
  String get settings_original => 'Original';

  @override
  String get settings_none => 'None';

  @override
  String get settings_applyNext => 'Applies on next playback';

  @override
  String get settings_restartNeeded => 'Restart needed';

  @override
  String get settings_playback_title => 'Playback';

  @override
  String get settings_video_title => 'Video';

  @override
  String get settings_audio_title => 'Audio';

  @override
  String get settings_subtitles_title => 'Subtitles';

  @override
  String get settings_display_title => 'Display';

  @override
  String get settings_streaming_title => 'Streaming & Network';

  @override
  String get settings_downloads_title => 'Downloads & Torrent';

  @override
  String get settings_languages_title => 'Languages & Tracks';

  @override
  String get settings_performance_title => 'Performance';

  @override
  String get settings_advanced_title => 'Advanced';

  @override
  String get settings_decrease => 'Decrease';

  @override
  String get settings_increase => 'Increase';

  @override
  String get settings_unlimited => 'Unlimited';

  @override
  String get settings_providers => 'Providers';

  @override
  String get settings_advancedSettings => 'Advanced settings';

  @override
  String get settings_expert => 'Expert';

  @override
  String get settings_diagnostics => 'Diagnostics';

  @override
  String get settings_skipForward => 'Skip forward';

  @override
  String get settings_verboseLogging => 'Verbose logging';

  @override
  String get settings_clearCache => 'Clear cache';

  @override
  String get settings_deviceUnavailable =>
      'Saved audio device unavailable; using Auto.';

  @override
  String get settings_noReceiverFormats => 'No receiver formats selected';

  @override
  String get player_replayTen => 'Replay 10 seconds';

  @override
  String get player_skipThirty => 'Skip 30 seconds';

  @override
  String get player_loading => 'Loading';

  @override
  String get player_chapters => 'Chapters';

  @override
  String get player_advanced => 'Advanced';

  @override
  String get player_copyDebug => 'Copy debug info';

  @override
  String get player_castTo => 'Cast to';

  @override
  String get player_close => 'Close player';

  @override
  String get player_subtitles => 'Subtitles';

  @override
  String get player_audio => 'Audio';

  @override
  String get player_options => 'Options';

  @override
  String get player_downloadInfo => 'Download info';

  @override
  String get player_upNext => 'Up Next';

  @override
  String get player_download => 'Download';

  @override
  String get player_nextEpisode => 'Next episode';

  @override
  String get player_addSubtitleFile => 'Add subtitle file…';

  @override
  String get player_defaultBadge => 'DEFAULT';

  @override
  String get player_tracks => 'Tracks';

  @override
  String get player_video => 'Video';

  @override
  String get player_upNextUpper => 'UP NEXT';

  @override
  String get player_playNext => 'Play Next';

  @override
  String get player_countdownCanceled => 'Countdown canceled';

  @override
  String get player_resumeCountdown => 'Resume countdown';

  @override
  String get player_pauseCountdown => 'Pause countdown';

  @override
  String get player_cancelCountdown => 'Cancel countdown';

  @override
  String get player_season => 'Season';

  @override
  String get player_show => 'Show';

  @override
  String get providers_noAccount => 'No account needed';

  @override
  String get providers_unavailable => 'Sign-in is not available in the app yet';

  @override
  String get providers_signedIn => 'Signed in';

  @override
  String get providers_signedOut => 'Not signed in';

  @override
  String get providers_free => 'Free';

  @override
  String get providers_signOut => 'Sign out';

  @override
  String get providers_signInQr => 'Sign in with QR code';

  @override
  String get providers_signIn => 'Sign in';

  @override
  String get providers_buy => 'Buy account';

  @override
  String get providers_username => 'Username or email';

  @override
  String get providers_password => 'Password';

  @override
  String get providers_signingIn => 'Signing in…';

  @override
  String get providers_newCode => 'New code';

  @override
  String get player_infoFormat => 'Format';

  @override
  String get player_infoSize => 'Size';

  @override
  String get player_infoLength => 'Length';

  @override
  String get player_infoBitrate => 'Bitrate';

  @override
  String get player_infoVideo => 'Video';

  @override
  String get player_infoAudio => 'Audio';

  @override
  String get player_infoSubtitle => 'Subtitle';

  @override
  String get player_infoFile => 'File';

  @override
  String get player_infoStreams => 'Streams';

  @override
  String get player_backToSubtitles => 'Back to subtitles';

  @override
  String get player_noSubtitleSources => 'No subtitle sources yet';

  @override
  String get player_size => 'Size';

  @override
  String get player_position => 'Position';

  @override
  String get player_aspectRatio => 'Aspect ratio';

  @override
  String get player_downloadSubtitles => 'Download subtitles…';

  @override
  String get player_subtitleUri => 'Subtitle URI';

  @override
  String get player_subtitleUriHint => 'https://… or file:///…';

  @override
  String get player_addExternalSubtitle => 'Add external subtitle';

  @override
  String get player_fillScreen => 'Fill screen';

  @override
  String get player_speed => 'Speed';

  @override
  String get player_reset => 'Reset';

  @override
  String player_delay(String value) {
    return 'Delay $value s';
  }

  @override
  String get player_decreaseSubtitleDelay => 'Decrease subtitle delay';

  @override
  String get player_decreaseAudioDelay => 'Decrease audio delay';

  @override
  String get player_increaseSubtitleDelay => 'Increase subtitle delay';

  @override
  String get player_increaseAudioDelay => 'Increase audio delay';

  @override
  String get player_info => 'Info';

  @override
  String get player_bottom => 'Bottom';

  @override
  String get player_raised => 'Raised';

  @override
  String providers_signInTo(String name) {
    return 'Sign in to $name';
  }

  @override
  String providers_scanInstructions(String name, String url) {
    return 'Scan with a phone signed in to $name, or open $url there.';
  }

  @override
  String settings_seconds(String value) {
    return '$value seconds';
  }

  @override
  String get settings_nothingToClear => 'Nothing to clear';

  @override
  String settings_freedMb(String value) {
    return 'Freed $value MB';
  }

  @override
  String settings_freedGb(String value) {
    return 'Freed $value GB';
  }

  @override
  String get state_noMedia => 'No media is available.';

  @override
  String get state_offlineWithPeriod => 'You\'re offline.';

  @override
  String get player_connecting => 'Connecting…';

  @override
  String get player_fetchingMetadata => 'Fetching metadata…';

  @override
  String get player_preparing => 'Preparing video…';

  @override
  String player_bufferingProgress(int percent, String speed) {
    final intl.NumberFormat percentNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String percentString = percentNumberFormat.format(percent);

    return 'Buffering $percentString%$speed';
  }

  @override
  String player_preparingProgress(String progress) {
    return 'Preparing video… $progress';
  }

  @override
  String get player_skipIntro => 'Skip Intro';

  @override
  String get player_skipCredits => 'Skip Credits';

  @override
  String get player_skip => 'Skip';

  @override
  String get player_sourceTorrent_magnet => 'Torrent magnet';

  @override
  String get player_sourceTorrent_file => 'Torrent file';

  @override
  String get player_sourceLocal_file => 'Local file';

  @override
  String get player_sourceWaiting_for_status => 'Waiting for status';

  @override
  String get player_sourceResolving_source => 'Resolving source';

  @override
  String get player_sourceReading_metadata => 'Reading metadata';

  @override
  String get player_sourceBuffering => 'Buffering';

  @override
  String get player_sourceReady => 'Ready';

  @override
  String get player_sourceStalled => 'Stalled';

  @override
  String get player_sourceFailed => 'Failed';

  @override
  String get player_sourceClosed => 'Closed';

  @override
  String get diagnostics_Resolution => 'Resolution';

  @override
  String get diagnostics_Status => 'Status';

  @override
  String get diagnostics_Log_folder => 'Log folder';

  @override
  String get diagnostics_Hardware_decoding => 'Hardware decoding';

  @override
  String get diagnostics_Decoders => 'Decoders';

  @override
  String get diagnostics_HDR_output => 'HDR output';

  @override
  String get diagnostics_HDR_formats => 'HDR formats';

  @override
  String get diagnostics_Display_mode_switching => 'Display mode switching';

  @override
  String get diagnostics_Audio_passthrough => 'Audio passthrough';

  @override
  String get diagnostics_Passthrough_formats => 'Passthrough formats';

  @override
  String get diagnostics_Decoder_fallback => 'Decoder fallback';

  @override
  String get diagnostics_Video_codec => 'Video codec';

  @override
  String get diagnostics_Decoder => 'Decoder';

  @override
  String get diagnostics_Pixel_format => 'Pixel format';

  @override
  String get diagnostics_Color_matrix => 'Color matrix';

  @override
  String get diagnostics_Transfer_function => 'Transfer function';

  @override
  String get diagnostics_Color_primaries => 'Color primaries';

  @override
  String get diagnostics_HDR_signal_peak => 'HDR signal peak';

  @override
  String get diagnostics_HDR_max_CLL => 'HDR max CLL';

  @override
  String get diagnostics_HDR_max_FALL => 'HDR max FALL';

  @override
  String get diagnostics_Audio_codec => 'Audio codec';

  @override
  String get diagnostics_Audio_format => 'Audio format';

  @override
  String get diagnostics_Audio_output => 'Audio output';

  @override
  String get diagnostics_Audio_output_format => 'Audio output format';

  @override
  String get diagnostics_Playback => 'Playback';

  @override
  String get diagnostics_Position => 'Position';

  @override
  String get diagnostics_Duration => 'Duration';

  @override
  String get diagnostics_Paused => 'Paused';

  @override
  String get diagnostics_Volume => 'Volume';

  @override
  String get diagnostics_Video_width => 'Video width';

  @override
  String get diagnostics_Video_height => 'Video height';

  @override
  String get diagnostics_supported => 'Supported';

  @override
  String get diagnostics_unsupported => 'Not supported';

  @override
  String get diagnostics_copy => 'Copy diagnostics';

  @override
  String get diagnostics_copied => 'Diagnostics copied';

  @override
  String get diagnostics_deviceCapabilities => 'Device capabilities';

  @override
  String player_sourceStatus(
    String state,
    String speed,
    int connections,
    int ranges,
  ) {
    final intl.NumberFormat connectionsNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String connectionsString = connectionsNumberFormat.format(
      connections,
    );
    final intl.NumberFormat rangesNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String rangesString = rangesNumberFormat.format(ranges);

    return '$state · $speed B/s · $connectionsString connections · $rangesString available ranges';
  }

  @override
  String get player_stats_Source => 'Source';

  @override
  String get player_stats_Provider => 'Provider';

  @override
  String get player_stats_Host => 'Host';

  @override
  String get player_stats_Protocol => 'Protocol';

  @override
  String get player_stats_TLS => 'TLS';

  @override
  String get player_stats_Connections => 'Connections';

  @override
  String get player_stats_Network => 'Network';

  @override
  String get player_stats_Speed => 'Speed';

  @override
  String get player_stats_Speed_down => 'Speed down';

  @override
  String get player_stats_Speed_up => 'Speed up';

  @override
  String get player_stats_Pieces => 'Pieces';

  @override
  String get player_stats_Piece_size => 'Piece size';

  @override
  String get player_stats_Swarm_tracker_ => 'Swarm (tracker)';

  @override
  String get player_stats_Availability => 'Availability';

  @override
  String get player_stats_Info_hash => 'Info-hash';

  @override
  String get player_stats_Time_left => 'Time left';

  @override
  String get player_stats_Buffer => 'Buffer';

  @override
  String get player_stats_Buffered_ahead => 'Buffered ahead';

  @override
  String get player_stats_Cache_in_memory => 'Cache in memory';

  @override
  String get player_stats_Cache_read_speed => 'Cache read speed';

  @override
  String get player_stats_Video => 'Video';

  @override
  String get player_stats_Codec => 'Codec';

  @override
  String get player_stats_Resolution => 'Resolution';

  @override
  String get player_stats_Display_size => 'Display size';

  @override
  String get player_stats_Frame_rate => 'Frame rate';

  @override
  String get player_stats_Bitrate => 'Bitrate';

  @override
  String get player_stats_Pixel_format => 'Pixel format';

  @override
  String get player_stats_Colour => 'Colour';

  @override
  String get player_stats_Hardware_decoding => 'Hardware decoding';

  @override
  String get player_stats_Dropped_frames => 'Dropped frames';

  @override
  String get player_stats_A_V_sync => 'A/V sync';

  @override
  String get player_stats_Audio => 'Audio';

  @override
  String get player_stats_Channels => 'Channels';

  @override
  String get player_stats_Sample_rate => 'Sample rate';

  @override
  String get player_stats_Output => 'Output';

  @override
  String get player_stats_Subtitles => 'Subtitles';

  @override
  String get player_stats_Track => 'Track';

  @override
  String get player_stats_Player => 'Player';

  @override
  String get player_stats_Container => 'Container';

  @override
  String get player_stats_Position => 'Position';

  @override
  String get player_stats_Engine => 'Engine';

  @override
  String get player_stats_Downloaded => 'Downloaded';

  @override
  String get player_stats_Progress => 'Progress';

  @override
  String get player_statsTitle => 'Stats for nerds';

  @override
  String get player_stats_Download_speed => 'Download speed';

  @override
  String get player_stats_Upload_speed => 'Upload speed';

  @override
  String get player_stats_Seeds_connected => 'Seeds connected';

  @override
  String get player_stats_Peers_connected => 'Peers connected';

  @override
  String get player_stats_Swarm => 'Swarm';

  @override
  String player_audioOutput(String value) {
    return 'Audio output: $value';
  }

  @override
  String get player_castTab => 'cast';

  @override
  String get player_triviaTab => 'trivia';

  @override
  String get player_filmographyTab => 'filmography';

  @override
  String get player_subtitleUriError =>
      'Enter an HTTP, HTTPS or file subtitle URI.';

  @override
  String settings_numericChoice(String value) {
    return '$value';
  }

  @override
  String settings_valueUnit(String value, String unit) {
    return '$value $unit';
  }

  @override
  String get settings_unit_connections => 'connections';

  @override
  String get settings_unit_retries => 'retries';

  @override
  String get settings_unit_peers => 'peers';

  @override
  String get settings_unit_threads => 'threads';

  @override
  String get settings_unit_seconds => 's';

  @override
  String get settings_unit_px => 'px';

  @override
  String get settings_unit_dB => 'dB';

  @override
  String get settings_unit_MB => 'MB';

  @override
  String get settings_unit_KBps => 'KB/s';

  @override
  String get settings_unit_percent => '%';

  @override
  String get settings_working => 'Working...';

  @override
  String get settings_failed => 'Failed';

  @override
  String settings_invalidTrackRule(String token) {
    return 'Invalid rule \"$token\". Use lang:<code>, original, atmos, lossless, channels or default.';
  }

  @override
  String get player_playbackPosition => 'Playback position';

  @override
  String player_chapterEyebrow(int number, String name) {
    final intl.NumberFormat numberNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String numberString = numberNumberFormat.format(number);

    return 'CHAPTER $numberString · $name';
  }

  @override
  String player_chapter(int number) {
    final intl.NumberFormat numberNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String numberString = numberNumberFormat.format(number);

    return 'Chapter $numberString';
  }

  @override
  String get player_insights => 'Insights';

  @override
  String get player_contentFilter => 'Content Filter';

  @override
  String player_filterOn(String label) {
    return '$label (on)';
  }

  @override
  String get player_action_subtitles => 'subtitles';

  @override
  String get player_action_audio => 'audio';

  @override
  String get player_action_info => 'info';

  @override
  String get player_action_upNext => 'upNext';

  @override
  String get player_failure_openFailed => 'Failed to open the media';

  @override
  String get player_failure_decodeFailed => 'Failed to decode the media';

  @override
  String get player_failure_engineCrashed => 'The playback engine crashed';

  @override
  String get player_failure_sourceUnreachable =>
      'The media source became unreachable';

  @override
  String player_failure_unsupportedCodec(String detail) {
    return 'Unsupported codec: $detail';
  }

  @override
  String player_failure_trackSelectionFailed(String detail) {
    return 'Failed to select playback track: $detail';
  }

  @override
  String player_failure_subtitleLoadFailed(String detail) {
    return 'Failed to load external subtitle: $detail';
  }

  @override
  String player_unableToSelectTrack(String error) {
    return 'Unable to select track: $error';
  }

  @override
  String settings_adjust(String action, String title) {
    return '$action $title';
  }

  @override
  String get player_transportHttpNoRangeSupport =>
      'This server does not support ranged reads.';

  @override
  String get player_transportHttpValidatorChanged =>
      'The HTTP file changed while it was loading.';

  @override
  String get player_transportHttpUnreachable =>
      'The HTTP source cannot be reached right now.';

  @override
  String get player_transportRangeUnsatisfiable =>
      'The requested byte range is unavailable.';

  @override
  String get player_transportTorrentNoMetadata =>
      'Torrent metadata has not arrived.';

  @override
  String get player_transportTorrentNoPeers =>
      'This torrent has no available peers.';

  @override
  String get player_transportTorrentStalled =>
      'The torrent stopped making progress.';

  @override
  String get player_transportTorrentFileError =>
      'The torrent could not access its files.';

  @override
  String get player_transportTorrentFileNotFound =>
      'The requested torrent file was not found.';

  @override
  String get player_transportEngineUnavailable =>
      'The native transport engine is unavailable.';

  @override
  String get player_transportUnknownTransport =>
      'The source reported an unknown transport failure.';

  @override
  String settings_choiceMbps(String value) {
    return '$value Mbps';
  }

  @override
  String settings_choiceGB(String value) {
    return '$value GB';
  }

  @override
  String player_playbackRate(String value) {
    return '$value×';
  }

  @override
  String get providers_codeExpired => 'The code expired. Make a new one.';

  @override
  String get common_enabled => 'Enabled';

  @override
  String get common_disabled => 'Disabled';

  @override
  String player_optionFailed(String error) {
    return 'Unable to apply option: $error';
  }

  @override
  String get player_subtitleNotAdded => 'Subtitle was not added.';
}
