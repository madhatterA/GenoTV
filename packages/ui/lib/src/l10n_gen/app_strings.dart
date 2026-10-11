import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_strings_en.dart';
import 'app_strings_fa.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppStrings
/// returned by `AppStrings.of(context)`.
///
/// Applications need to include `AppStrings.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n_gen/app_strings.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppStrings.localizationsDelegates,
///   supportedLocales: AppStrings.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppStrings.supportedLocales
/// property.
abstract class AppStrings {
  AppStrings(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppStrings of(BuildContext context) {
    return Localizations.of<AppStrings>(context, AppStrings)!;
  }

  static const LocalizationsDelegate<AppStrings> delegate =
      _AppStringsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('fa'),
  ];

  /// App UI: title; displayed in app screens.
  ///
  /// In en, this message translates to:
  /// **'Video Player'**
  String get app_title;

  /// Settings UI: language_title; displayed in settings screens.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settings_language_title;

  /// Settings UI: language_system; displayed in settings screens.
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get settings_language_system;

  /// Settings UI: language_en; displayed in settings screens.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get settings_language_en;

  /// Settings UI: language_fa; displayed in settings screens.
  ///
  /// In en, this message translates to:
  /// **'فارسی'**
  String get settings_language_fa;

  /// Common UI: retry; displayed in shared shell, browse, detail, dialogs and buttons.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get common_retry;

  /// Common UI: cancel; displayed in shared shell, browse, detail, dialogs and buttons.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get common_cancel;

  /// Common UI: close; displayed in shared shell, browse, detail, dialogs and buttons.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get common_close;

  /// Common UI: back; displayed in shared shell, browse, detail, dialogs and buttons.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get common_back;

  /// Common UI: play; displayed in shared shell, browse, detail, dialogs and buttons.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get common_play;

  /// Common UI: resume; displayed in shared shell, browse, detail, dialogs and buttons.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get common_resume;

  /// Common UI: seeAll; displayed in shared shell, browse, detail, dialogs and buttons.
  ///
  /// In en, this message translates to:
  /// **'See all'**
  String get common_seeAll;

  /// Common UI: loading; displayed in shared shell, browse, detail, dialogs and buttons.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get common_loading;

  /// Common UI: details; displayed in shared shell, browse, detail, dialogs and buttons.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get common_details;

  /// Common UI: on; displayed in shared shell, browse, detail, dialogs and buttons.
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get common_on;

  /// Common UI: off; displayed in shared shell, browse, detail, dialogs and buttons.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get common_off;

  /// Common UI: auto; displayed in shared shell, browse, detail, dialogs and buttons.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get common_auto;

  /// Common UI: anyYear; displayed in shared shell, browse, detail, dialogs and buttons.
  ///
  /// In en, this message translates to:
  /// **'Any year'**
  String get common_anyYear;

  /// Common UI: apply; displayed in shared shell, browse, detail, dialogs and buttons.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get common_apply;

  /// Common UI: clear; displayed in shared shell, browse, detail, dialogs and buttons.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get common_clear;

  /// Common UI: clearAll; displayed in shared shell, browse, detail, dialogs and buttons.
  ///
  /// In en, this message translates to:
  /// **'Clear all'**
  String get common_clearAll;

  /// Common UI: default; displayed in shared shell, browse, detail, dialogs and buttons.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get common_default;

  /// Common UI: genres; displayed in shared shell, browse, detail, dialogs and buttons.
  ///
  /// In en, this message translates to:
  /// **'Genres'**
  String get common_genres;

  /// Common UI: less; displayed in shared shell, browse, detail, dialogs and buttons.
  ///
  /// In en, this message translates to:
  /// **'Less'**
  String get common_less;

  /// Common UI: more; displayed in shared shell, browse, detail, dialogs and buttons.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get common_more;

  /// Common UI: movies; displayed in shared shell, browse, detail, dialogs and buttons.
  ///
  /// In en, this message translates to:
  /// **'Movies'**
  String get common_movies;

  /// Common UI: pause; displayed in shared shell, browse, detail, dialogs and buttons.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get common_pause;

  /// Common UI: playLink; displayed in shared shell, browse, detail, dialogs and buttons.
  ///
  /// In en, this message translates to:
  /// **'Play link'**
  String get common_playLink;

  /// Common UI: search; displayed in shared shell, browse, detail, dialogs and buttons.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get common_search;

  /// Common UI: tv; displayed in shared shell, browse, detail, dialogs and buttons.
  ///
  /// In en, this message translates to:
  /// **'TV'**
  String get common_tv;

  /// Common UI: tvShows; displayed in shared shell, browse, detail, dialogs and buttons.
  ///
  /// In en, this message translates to:
  /// **'TV shows'**
  String get common_tvShows;

  /// Common UI: watched; displayed in shared shell, browse, detail, dialogs and buttons.
  ///
  /// In en, this message translates to:
  /// **'Watched'**
  String get common_watched;

  /// Common UI: liked; displayed in shared shell, browse, detail, dialogs and buttons.
  ///
  /// In en, this message translates to:
  /// **'Liked'**
  String get common_liked;

  /// Common UI: home; displayed in shared shell, browse, detail, dialogs and buttons.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get common_home;

  /// Common UI: settings; displayed in shared shell, browse, detail, dialogs and buttons.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get common_settings;

  /// Artwork UI: unavailable; displayed in artwork screens.
  ///
  /// In en, this message translates to:
  /// **'Artwork unavailable'**
  String get artwork_unavailable;

  /// Cast UI: airPlay; displayed in cast screens.
  ///
  /// In en, this message translates to:
  /// **'AirPlay'**
  String get cast_airPlay;

  /// Cast UI: checking; displayed in cast screens.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get cast_checking;

  /// Cast UI: looking; displayed in cast screens.
  ///
  /// In en, this message translates to:
  /// **'Looking for devices…'**
  String get cast_looking;

  /// Cast UI: notCompatible; displayed in cast screens.
  ///
  /// In en, this message translates to:
  /// **'This device can\'t play this file'**
  String get cast_notCompatible;

  /// Cast UI: stop; displayed in cast screens.
  ///
  /// In en, this message translates to:
  /// **'Stop casting'**
  String get cast_stop;

  /// Cast UI: title; displayed in cast screens.
  ///
  /// In en, this message translates to:
  /// **'Cast'**
  String get cast_title;

  /// Detail UI: about; displayed in detail screens.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get detail_about;

  /// Detail UI: cast; displayed in detail screens.
  ///
  /// In en, this message translates to:
  /// **'Cast'**
  String get detail_cast;

  /// Detail UI: info; displayed in detail screens.
  ///
  /// In en, this message translates to:
  /// **'Info'**
  String get detail_info;

  /// Detail UI: kindMovie; displayed in detail screens.
  ///
  /// In en, this message translates to:
  /// **'Movie'**
  String get detail_kindMovie;

  /// Detail UI: kindTvShow; displayed in detail screens.
  ///
  /// In en, this message translates to:
  /// **'TV Show'**
  String get detail_kindTvShow;

  /// Detail UI: like; displayed in detail screens.
  ///
  /// In en, this message translates to:
  /// **'Like'**
  String get detail_like;

  /// Detail UI: moreLikeThis; displayed in detail screens.
  ///
  /// In en, this message translates to:
  /// **'More like this'**
  String get detail_moreLikeThis;

  /// Detail UI: trailer; displayed in detail screens.
  ///
  /// In en, this message translates to:
  /// **'Trailer'**
  String get detail_trailer;

  /// Detail UI: trailers; displayed in detail screens.
  ///
  /// In en, this message translates to:
  /// **'Trailers'**
  String get detail_trailers;

  /// Detail UI: unlike; displayed in detail screens.
  ///
  /// In en, this message translates to:
  /// **'Remove from Liked'**
  String get detail_unlike;

  /// Detail UI: watchlist; displayed in detail screens.
  ///
  /// In en, this message translates to:
  /// **'Watchlist'**
  String get detail_watchlist;

  /// Episode UI: details; displayed in series episode rows.
  ///
  /// In en, this message translates to:
  /// **'Episode details'**
  String get episode_details;

  /// Filter UI: allCountries; displayed in filter screens.
  ///
  /// In en, this message translates to:
  /// **'All countries'**
  String get filter_allCountries;

  /// Filter UI: country; displayed in filter screens.
  ///
  /// In en, this message translates to:
  /// **'Country'**
  String get filter_country;

  /// Filter UI: sort; displayed in filter screens.
  ///
  /// In en, this message translates to:
  /// **'Sort'**
  String get filter_sort;

  /// Genres UI: noMatch; displayed in genres screens.
  ///
  /// In en, this message translates to:
  /// **'No genres match'**
  String get genres_noMatch;

  /// Genres UI: search; displayed in genres screens.
  ///
  /// In en, this message translates to:
  /// **'Search genres'**
  String get genres_search;

  /// Grid UI: loadFailed; displayed in grid screens.
  ///
  /// In en, this message translates to:
  /// **'Could not load titles'**
  String get grid_loadFailed;

  /// Library UI: empty; displayed in library screens.
  ///
  /// In en, this message translates to:
  /// **'Your library is empty'**
  String get library_empty;

  /// Library UI: noMatch; displayed in library screens.
  ///
  /// In en, this message translates to:
  /// **'No titles match this filter'**
  String get library_noMatch;

  /// Library UI: openFeatured; displayed in library screens.
  ///
  /// In en, this message translates to:
  /// **'Open featured title'**
  String get library_openFeatured;

  /// Library UI: refresh; displayed in library screens.
  ///
  /// In en, this message translates to:
  /// **'Refresh library'**
  String get library_refresh;

  /// Library UI: searchTitle; displayed in library screens.
  ///
  /// In en, this message translates to:
  /// **'Search title'**
  String get library_searchTitle;

  /// Library UI: series; displayed in library screens.
  ///
  /// In en, this message translates to:
  /// **'Series'**
  String get library_series;

  /// Menu UI: mediaOptions; displayed in menu screens.
  ///
  /// In en, this message translates to:
  /// **'Media options'**
  String get menu_mediaOptions;

  /// Person UI: knownFor; displayed in person screens.
  ///
  /// In en, this message translates to:
  /// **'Known for'**
  String get person_knownFor;

  /// Playlink UI: clearConfirm; displayed in playLink screens.
  ///
  /// In en, this message translates to:
  /// **'Clear all recent links?'**
  String get playlink_clearConfirm;

  /// Playlink UI: hint; displayed in playLink screens. LTR: URLs, file names and diagnostic codes remain LTR.
  ///
  /// In en, this message translates to:
  /// **'Torrent / https link'**
  String get playlink_hint;

  /// Playlink UI: import; displayed in playLink screens. LTR: URLs, file names and diagnostic codes remain LTR.
  ///
  /// In en, this message translates to:
  /// **'Import .torrent'**
  String get playlink_import;

  /// Playlink UI: insert; displayed in playLink screens.
  ///
  /// In en, this message translates to:
  /// **'Insert link'**
  String get playlink_insert;

  /// Playlink UI: recent; displayed in playLink screens.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get playlink_recent;

  /// Playlink UI: recentEmpty; displayed in playLink screens.
  ///
  /// In en, this message translates to:
  /// **'Links you play will appear here.'**
  String get playlink_recentEmpty;

  /// Play UI: finding; displayed in play screens.
  ///
  /// In en, this message translates to:
  /// **'Finding sources…'**
  String get play_finding;

  /// Play UI: infoFileName; displayed in play screens. LTR: URLs, file names and diagnostic codes remain LTR.
  ///
  /// In en, this message translates to:
  /// **'File name'**
  String get play_infoFileName;

  /// Play UI: infoRelease; displayed in play screens. LTR: URLs, file names and diagnostic codes remain LTR.
  ///
  /// In en, this message translates to:
  /// **'Release'**
  String get play_infoRelease;

  /// Play UI: insertLink; displayed in play screens.
  ///
  /// In en, this message translates to:
  /// **'Insert link…'**
  String get play_insertLink;

  /// Play UI: pickProvider; displayed in play screens.
  ///
  /// In en, this message translates to:
  /// **'Pick a provider'**
  String get play_pickProvider;

  /// Play UI: refresh; displayed in play screens.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get play_refresh;

  /// Play UI: sortSeeds; displayed in play screens.
  ///
  /// In en, this message translates to:
  /// **'Seeds'**
  String get play_sortSeeds;

  /// Play UI: sortSize; displayed in play screens.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get play_sortSize;

  /// Play UI: sortStreams; displayed in play screens.
  ///
  /// In en, this message translates to:
  /// **'Sort streams'**
  String get play_sortStreams;

  /// Play UI: torrent; displayed in play screens.
  ///
  /// In en, this message translates to:
  /// **'Torrent'**
  String get play_torrent;

  /// Row UI: scrollLeft; displayed in row screens.
  ///
  /// In en, this message translates to:
  /// **'Scroll left'**
  String get row_scrollLeft;

  /// Row UI: scrollRight; displayed in row screens.
  ///
  /// In en, this message translates to:
  /// **'Scroll right'**
  String get row_scrollRight;

  /// Search UI: hint; displayed in search screens.
  ///
  /// In en, this message translates to:
  /// **'Search your libraries'**
  String get search_hint;

  /// Search UI: noResults; displayed in search screens.
  ///
  /// In en, this message translates to:
  /// **'No results'**
  String get search_noResults;

  /// Search UI: noResultsBody; displayed in search screens.
  ///
  /// In en, this message translates to:
  /// **'Check the spelling or try another title.'**
  String get search_noResultsBody;

  /// Search UI: promptTitle; displayed in search screens.
  ///
  /// In en, this message translates to:
  /// **'Search movies and shows'**
  String get search_promptTitle;

  /// Search UI: promptBody; displayed in search screens.
  ///
  /// In en, this message translates to:
  /// **'Type a title, a person or a year.'**
  String get search_promptBody;

  /// Search UI: recent; displayed in search screens.
  ///
  /// In en, this message translates to:
  /// **'Recent searches'**
  String get search_recent;

  /// Sort UI: popularity; displayed in sort screens.
  ///
  /// In en, this message translates to:
  /// **'Popularity'**
  String get sort_popularity;

  /// Sort UI: rating; displayed in sort screens.
  ///
  /// In en, this message translates to:
  /// **'Rating'**
  String get sort_rating;

  /// Sort UI: releaseDate; displayed in sort screens.
  ///
  /// In en, this message translates to:
  /// **'Release date'**
  String get sort_releaseDate;

  /// Sort UI: titleAz; displayed in sort screens.
  ///
  /// In en, this message translates to:
  /// **'Title A–Z'**
  String get sort_titleAz;

  /// State UI: emptyTitle; displayed in state screens.
  ///
  /// In en, this message translates to:
  /// **'Nothing here yet'**
  String get state_emptyTitle;

  /// Year UI: from; displayed in browse year picker.
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get year_from;

  /// Year UI: pastYear; displayed in browse year picker.
  ///
  /// In en, this message translates to:
  /// **'Past year'**
  String get year_pastYear;

  /// Year UI: range; displayed in browse year picker.
  ///
  /// In en, this message translates to:
  /// **'Range'**
  String get year_range;

  /// Year UI: single; displayed in browse year picker.
  ///
  /// In en, this message translates to:
  /// **'Single'**
  String get year_single;

  /// Year UI: singleOrRange; displayed in browse year picker.
  ///
  /// In en, this message translates to:
  /// **'Single year or range'**
  String get year_singleOrRange;

  /// Year UI: title; displayed in browse year picker.
  ///
  /// In en, this message translates to:
  /// **'Year'**
  String get year_title;

  /// Year UI: to; displayed in browse year picker.
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get year_to;

  /// Failure UI: transportHttpNoRangeSupport; displayed in error states.
  ///
  /// In en, this message translates to:
  /// **'This HTTP source does not support seeking.'**
  String get failure_transportHttpNoRangeSupport;

  /// Failure UI: transportHttpValidatorChanged; displayed in error states.
  ///
  /// In en, this message translates to:
  /// **'The HTTP file changed while it was loading.'**
  String get failure_transportHttpValidatorChanged;

  /// Failure UI: transportHttpUnreachable; displayed in error states.
  ///
  /// In en, this message translates to:
  /// **'The HTTP source could not be reached.'**
  String get failure_transportHttpUnreachable;

  /// Failure UI: transportRangeUnsatisfiable; displayed in error states.
  ///
  /// In en, this message translates to:
  /// **'The requested media range is unavailable.'**
  String get failure_transportRangeUnsatisfiable;

  /// Failure UI: transportTorrentNoMetadata; displayed in error states.
  ///
  /// In en, this message translates to:
  /// **'Torrent metadata did not arrive in time.'**
  String get failure_transportTorrentNoMetadata;

  /// Failure UI: transportTorrentNoPeers; displayed in error states.
  ///
  /// In en, this message translates to:
  /// **'This torrent has no available peers.'**
  String get failure_transportTorrentNoPeers;

  /// Failure UI: transportTorrentStalled; displayed in error states.
  ///
  /// In en, this message translates to:
  /// **'The torrent stopped delivering the requested media.'**
  String get failure_transportTorrentStalled;

  /// Failure UI: transportTorrentFileError; displayed in error states.
  ///
  /// In en, this message translates to:
  /// **'The torrent could not access its media files.'**
  String get failure_transportTorrentFileError;

  /// Failure UI: transportTorrentFileNotFound; displayed in error states.
  ///
  /// In en, this message translates to:
  /// **'The requested file is not in the torrent.'**
  String get failure_transportTorrentFileNotFound;

  /// Failure UI: transportEngineUnavailable; displayed in error states.
  ///
  /// In en, this message translates to:
  /// **'The streaming engine is unavailable on this device.'**
  String get failure_transportEngineUnavailable;

  /// Failure UI: transportLocalNotFound; displayed in error states.
  ///
  /// In en, this message translates to:
  /// **'The local file could not be found.'**
  String get failure_transportLocalNotFound;

  /// Failure UI: transportLocalNotReadable; displayed in error states.
  ///
  /// In en, this message translates to:
  /// **'The local file could not be read.'**
  String get failure_transportLocalNotReadable;

  /// Failure UI: transportLocalEmpty; displayed in error states.
  ///
  /// In en, this message translates to:
  /// **'The local file is empty.'**
  String get failure_transportLocalEmpty;

  /// Failure UI: transportLocalUnsupportedUri; displayed in error states.
  ///
  /// In en, this message translates to:
  /// **'This local source URI is not supported.'**
  String get failure_transportLocalUnsupportedUri;

  /// Failure UI: playbackOpenFailed; displayed in error states.
  ///
  /// In en, this message translates to:
  /// **'The media could not be opened.'**
  String get failure_playbackOpenFailed;

  /// Failure UI: playbackDecodeFailed; displayed in error states.
  ///
  /// In en, this message translates to:
  /// **'The media could not be decoded.'**
  String get failure_playbackDecodeFailed;

  /// Failure UI: playbackEngineCrashed; displayed in error states.
  ///
  /// In en, this message translates to:
  /// **'The playback engine stopped unexpectedly.'**
  String get failure_playbackEngineCrashed;

  /// Failure UI: playbackSourceUnreachable; displayed in error states.
  ///
  /// In en, this message translates to:
  /// **'The playback source became unreachable.'**
  String get failure_playbackSourceUnreachable;

  /// Failure UI: playbackUnsupportedCodec; displayed in error states.
  ///
  /// In en, this message translates to:
  /// **'This media uses an unsupported codec.'**
  String get failure_playbackUnsupportedCodec;

  /// Failure UI: playbackTrackSelectionFailed; displayed in error states.
  ///
  /// In en, this message translates to:
  /// **'The requested playback track could not be selected.'**
  String get failure_playbackTrackSelectionFailed;

  /// Failure UI: playbackSubtitleLoadFailed; displayed in error states.
  ///
  /// In en, this message translates to:
  /// **'The external subtitle could not be loaded.'**
  String get failure_playbackSubtitleLoadFailed;

  /// Failure UI: platformUnsupported; displayed in error states.
  ///
  /// In en, this message translates to:
  /// **'This operation is not supported on this platform.'**
  String get failure_platformUnsupported;

  /// Failure UI: platformPermissionDenied; displayed in error states.
  ///
  /// In en, this message translates to:
  /// **'The platform denied the required permission.'**
  String get failure_platformPermissionDenied;

  /// Failure UI: platformDisplaySwitchFailed; displayed in error states.
  ///
  /// In en, this message translates to:
  /// **'The display mode could not be changed.'**
  String get failure_platformDisplaySwitchFailed;

  /// Failure UI: platformAudioDeviceLost; displayed in error states.
  ///
  /// In en, this message translates to:
  /// **'The selected audio device is no longer available.'**
  String get failure_platformAudioDeviceLost;

  /// Failure UI: platformProbeFailed; displayed in error states.
  ///
  /// In en, this message translates to:
  /// **'Platform capabilities could not be determined.'**
  String get failure_platformProbeFailed;

  /// Failure UI: appUnexpected; displayed in error states.
  ///
  /// In en, this message translates to:
  /// **'The application encountered an unexpected failure.'**
  String get failure_appUnexpected;

  /// Failure UI: appCancelled; displayed in error states.
  ///
  /// In en, this message translates to:
  /// **'The operation was cancelled before completion.'**
  String get failure_appCancelled;

  /// Badge UI: progress; displayed in media progress badges.
  ///
  /// In en, this message translates to:
  /// **'Progress {percent} percent'**
  String badge_progress(String percent);

  /// Badge UI: unwatchedEpisodes; displayed in media progress badges.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, other{{number} unwatched episodes}}'**
  String badge_unwatchedEpisodes(int count, String number);

  /// Cast UI: castingTo; displayed in cast screens.
  ///
  /// In en, this message translates to:
  /// **'Casting to {device}'**
  String cast_castingTo(String device);

  /// Detail UI: browse; displayed in detail screens.
  ///
  /// In en, this message translates to:
  /// **'Browse {label}'**
  String detail_browse(String label);

  /// Detail UI: resumeAt; displayed in detail screens.
  ///
  /// In en, this message translates to:
  /// **'Resume {time}'**
  String detail_resumeAt(String time);

  /// Episode UI: title; displayed in series episode rows.
  ///
  /// In en, this message translates to:
  /// **'E{number} · {title}'**
  String episode_title(String number, String title);

  /// Episode UI: minutes; displayed in series episode rows.
  ///
  /// In en, this message translates to:
  /// **'{minutes} min'**
  String episode_minutes(String minutes);

  /// Filter UI: sortBy; displayed in filter screens.
  ///
  /// In en, this message translates to:
  /// **'Sort: {sort}'**
  String filter_sortBy(String sort);

  /// Filter UI: yearRange; displayed in filter screens.
  ///
  /// In en, this message translates to:
  /// **'{from} – {to}'**
  String filter_yearRange(String from, String to);

  /// Home UI: featuredItem; displayed in home screens.
  ///
  /// In en, this message translates to:
  /// **'Featured item {index} of {count}'**
  String home_featuredItem(String index, String count);

  /// Playlink UI: remove; displayed in playLink screens.
  ///
  /// In en, this message translates to:
  /// **'Remove {label}'**
  String playlink_remove(String label);

  /// Play UI: seeders; displayed in play screens.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, other{{number} seeders}}'**
  String play_seeders(int count, String number);

  /// Rating UI: imdb; displayed in detail rating badges.
  ///
  /// In en, this message translates to:
  /// **'IMDb rating {score}'**
  String rating_imdb(String score);

  /// Rating UI: tmdb; displayed in detail rating badges.
  ///
  /// In en, this message translates to:
  /// **'TMDB rating {score}'**
  String rating_tmdb(String score);

  /// Rating UI: tomatoFresh; displayed in detail rating badges.
  ///
  /// In en, this message translates to:
  /// **'Rotten Tomatoes fresh {score}'**
  String rating_tomatoFresh(String score);

  /// Rating UI: tomatoRotten; displayed in detail rating badges.
  ///
  /// In en, this message translates to:
  /// **'Rotten Tomatoes rotten {score}'**
  String rating_tomatoRotten(String score);

  /// Continue Watching row context menu removal action.
  ///
  /// In en, this message translates to:
  /// **'Remove from Continue Watching'**
  String get shelf_removeContinue;

  /// Year UI: lastYears; displayed in browse year picker.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, other{Last {number} years}}'**
  String year_lastYears(int count, String number);

  /// Failure UI: unknown; displayed in error states. LTR: URLs, file names and diagnostic codes remain LTR.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong while processing this request ({code}).'**
  String failure_unknown(String code);

  /// common UI: dismiss, shown in the corresponding shell, screen or state.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get common_dismiss;

  /// state UI: errorTitle, shown in the corresponding shell, screen or state.
  ///
  /// In en, this message translates to:
  /// **'Unable to continue'**
  String get state_errorTitle;

  /// state UI: hideCode, shown in the corresponding shell, screen or state.
  ///
  /// In en, this message translates to:
  /// **'Hide error code'**
  String get state_hideCode;

  /// state UI: showCode, shown in the corresponding shell, screen or state.
  ///
  /// In en, this message translates to:
  /// **'Show error code'**
  String get state_showCode;

  /// state UI: offline, shown in the corresponding shell, screen or state.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline'**
  String get state_offline;

  /// state UI: offlineBody, shown in the corresponding shell, screen or state.
  ///
  /// In en, this message translates to:
  /// **'Check your connection. We\'ll retry automatically.'**
  String get state_offlineBody;

  /// state UI: reconnecting, shown in the corresponding shell, screen or state.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting…'**
  String get state_reconnecting;

  /// state UI: retryFailed, shown in the corresponding shell, screen or state.
  ///
  /// In en, this message translates to:
  /// **'Still offline. Try again.'**
  String get state_retryFailed;

  /// home UI: trendingMovies, shown in the corresponding shell, screen or state.
  ///
  /// In en, this message translates to:
  /// **'Trending Movies'**
  String get home_trendingMovies;

  /// home UI: trendingShows, shown in the corresponding shell, screen or state.
  ///
  /// In en, this message translates to:
  /// **'Trending Shows'**
  String get home_trendingShows;

  /// liked UI: emptyTitle, shown in the corresponding shell, screen or state.
  ///
  /// In en, this message translates to:
  /// **'No liked titles yet'**
  String get liked_emptyTitle;

  /// liked UI: emptyBody, shown in the corresponding shell, screen or state.
  ///
  /// In en, this message translates to:
  /// **'Titles you like appear here.'**
  String get liked_emptyBody;

  /// liked UI: browseMovies, shown in the corresponding shell, screen or state.
  ///
  /// In en, this message translates to:
  /// **'Browse movies'**
  String get liked_browseMovies;

  /// app UI: resolvingCache, shown in the corresponding shell, screen or state.
  ///
  /// In en, this message translates to:
  /// **'resolving cache path…'**
  String get app_resolvingCache;

  /// state UI: loading, shown in the corresponding shell, screen or state.
  ///
  /// In en, this message translates to:
  /// **'Loading'**
  String get state_loading;

  /// Play link validation or source-provider error shown to the viewer. LTR: paths, host names and HTTP status codes.
  ///
  /// In en, this message translates to:
  /// **'Not a playable link: bad magnet link.'**
  String get playlink_badMagnet;

  /// Play link validation or source-provider error shown to the viewer. LTR: paths, host names and HTTP status codes.
  ///
  /// In en, this message translates to:
  /// **'Not a playable link.'**
  String get playlink_invalid;

  /// Play link validation or source-provider error shown to the viewer. LTR: paths, host names and HTTP status codes.
  ///
  /// In en, this message translates to:
  /// **'Torrent file not found: {path}'**
  String playlink_fileMissing(String path);

  /// Play link validation or source-provider error shown to the viewer. LTR: paths, host names and HTTP status codes.
  ///
  /// In en, this message translates to:
  /// **'Could not reach {host}.'**
  String playlink_unreachable(String host);

  /// Play link validation or source-provider error shown to the viewer. LTR: paths, host names and HTTP status codes.
  ///
  /// In en, this message translates to:
  /// **'The torrent link answered {status}.'**
  String playlink_httpStatus(String status);

  /// Play link validation or source-provider error shown to the viewer. LTR: paths, host names and HTTP status codes.
  ///
  /// In en, this message translates to:
  /// **'The torrent file is larger than 10 MB.'**
  String get playlink_tooLarge;

  /// Play link validation or source-provider error shown to the viewer. LTR: paths, host names and HTTP status codes.
  ///
  /// In en, this message translates to:
  /// **'The link did not return a torrent file.'**
  String get playlink_notTorrent;

  /// Play link validation or source-provider error shown to the viewer. LTR: paths, host names and HTTP status codes.
  ///
  /// In en, this message translates to:
  /// **'Could not download the torrent from {host}.'**
  String playlink_downloadFailed(String host);

  /// Play link validation or source-provider error shown to the viewer. LTR: paths, host names and HTTP status codes.
  ///
  /// In en, this message translates to:
  /// **'This provider is unavailable right now.'**
  String get play_providerUnavailable;

  /// Error below cast target rows when connecting fails.
  ///
  /// In en, this message translates to:
  /// **'Couldn\'t cast to {device}'**
  String cast_failedToCast(String device);

  /// App subtitle-file import dialog or validation error, shown by the importing widget. LTR: file names and raw filesystem diagnostics.
  ///
  /// In en, this message translates to:
  /// **'Subtitles'**
  String get subtitle_picker;

  /// App subtitle-file import dialog or validation error, shown by the importing widget. LTR: file names and raw filesystem diagnostics.
  ///
  /// In en, this message translates to:
  /// **'Not a valid zip file.'**
  String get subtitle_invalidZip;

  /// App subtitle-file import dialog or validation error, shown by the importing widget. LTR: file names and raw filesystem diagnostics.
  ///
  /// In en, this message translates to:
  /// **'Zip directory is damaged.'**
  String get subtitle_damagedDirectory;

  /// App subtitle-file import dialog or validation error, shown by the importing widget. LTR: file names and raw filesystem diagnostics.
  ///
  /// In en, this message translates to:
  /// **'Unsafe file name in zip: {name}'**
  String subtitle_unsafeName(String name);

  /// App subtitle-file import dialog or validation error, shown by the importing widget. LTR: file names and raw filesystem diagnostics.
  ///
  /// In en, this message translates to:
  /// **'Zip entry is encrypted: {name}'**
  String subtitle_encrypted(String name);

  /// App subtitle-file import dialog or validation error, shown by the importing widget. LTR: file names and raw filesystem diagnostics.
  ///
  /// In en, this message translates to:
  /// **'Subtitle in zip is too large: {name}'**
  String subtitle_entryTooLarge(String name);

  /// App subtitle-file import dialog or validation error, shown by the importing widget. LTR: file names and raw filesystem diagnostics.
  ///
  /// In en, this message translates to:
  /// **'Unsupported zip compression: {name}'**
  String subtitle_unsupportedCompression(String name);

  /// App subtitle-file import dialog or validation error, shown by the importing widget. LTR: file names and raw filesystem diagnostics.
  ///
  /// In en, this message translates to:
  /// **'Zip entry is damaged: {name}'**
  String subtitle_damagedEntry(String name);

  /// App subtitle-file import dialog or validation error, shown by the importing widget. LTR: file names and raw filesystem diagnostics.
  ///
  /// In en, this message translates to:
  /// **'Zip file is damaged.'**
  String get subtitle_damagedZip;

  /// App subtitle-file import dialog or validation error, shown by the importing widget. LTR: file names and raw filesystem diagnostics.
  ///
  /// In en, this message translates to:
  /// **'No subtitle files found in the zip.'**
  String get subtitle_emptyZip;

  /// App subtitle-file import dialog or validation error, shown by the importing widget. LTR: file names and raw filesystem diagnostics.
  ///
  /// In en, this message translates to:
  /// **'Unsupported file type: {name}'**
  String subtitle_unsupportedType(String name);

  /// App subtitle-file import dialog or validation error, shown by the importing widget. LTR: file names and raw filesystem diagnostics.
  ///
  /// In en, this message translates to:
  /// **'File is too large: {name}'**
  String subtitle_fileTooLarge(String name);

  /// App subtitle-file import dialog or validation error, shown by the importing widget. LTR: file names and raw filesystem diagnostics.
  ///
  /// In en, this message translates to:
  /// **'Could not read {name}: {error}'**
  String subtitle_readFailed(String name, String error);

  /// No description provided for @settings_playback_resume_label.
  ///
  /// In en, this message translates to:
  /// **'Resume playback'**
  String get settings_playback_resume_label;

  /// No description provided for @settings_playback_autoPlayNext_label.
  ///
  /// In en, this message translates to:
  /// **'Auto-play next episode'**
  String get settings_playback_autoPlayNext_label;

  /// No description provided for @settings_playback_rememberPosition_label.
  ///
  /// In en, this message translates to:
  /// **'Remember position'**
  String get settings_playback_rememberPosition_label;

  /// No description provided for @settings_playback_speed_label.
  ///
  /// In en, this message translates to:
  /// **'Playback speed'**
  String get settings_playback_speed_label;

  /// No description provided for @settings_playback_syncToDisplay_label.
  ///
  /// In en, this message translates to:
  /// **'Sync to display'**
  String get settings_playback_syncToDisplay_label;

  /// No description provided for @settings_playback_avSyncCorrection_label.
  ///
  /// In en, this message translates to:
  /// **'A/V sync correction'**
  String get settings_playback_avSyncCorrection_label;

  /// No description provided for @settings_playback_cachePreset_label.
  ///
  /// In en, this message translates to:
  /// **'Cache preset'**
  String get settings_playback_cachePreset_label;

  /// No description provided for @settings_playback_demuxerCacheSize_label.
  ///
  /// In en, this message translates to:
  /// **'Demuxer cache size'**
  String get settings_playback_demuxerCacheSize_label;

  /// No description provided for @settings_playback_readAhead_label.
  ///
  /// In en, this message translates to:
  /// **'Read ahead'**
  String get settings_playback_readAhead_label;

  /// No description provided for @settings_playback_networkTimeout_label.
  ///
  /// In en, this message translates to:
  /// **'Network timeout'**
  String get settings_playback_networkTimeout_label;

  /// No description provided for @settings_video_hwdec_label.
  ///
  /// In en, this message translates to:
  /// **'Hardware decoding'**
  String get settings_video_hwdec_label;

  /// No description provided for @settings_video_hdr_label.
  ///
  /// In en, this message translates to:
  /// **'HDR handling'**
  String get settings_video_hdr_label;

  /// No description provided for @settings_video_matchFrameRate_label.
  ///
  /// In en, this message translates to:
  /// **'Match frame rate'**
  String get settings_video_matchFrameRate_label;

  /// No description provided for @settings_video_matchResolution_label.
  ///
  /// In en, this message translates to:
  /// **'Match resolution'**
  String get settings_video_matchResolution_label;

  /// No description provided for @settings_video_aspectRatio_label.
  ///
  /// In en, this message translates to:
  /// **'Aspect ratio'**
  String get settings_video_aspectRatio_label;

  /// No description provided for @settings_video_decoder_label.
  ///
  /// In en, this message translates to:
  /// **'Video decoder'**
  String get settings_video_decoder_label;

  /// No description provided for @settings_video_scalingQuality_label.
  ///
  /// In en, this message translates to:
  /// **'Scaling quality'**
  String get settings_video_scalingQuality_label;

  /// No description provided for @settings_video_toneMapping_label.
  ///
  /// In en, this message translates to:
  /// **'HDR to SDR tone mapping'**
  String get settings_video_toneMapping_label;

  /// No description provided for @settings_video_pixelFormat_label.
  ///
  /// In en, this message translates to:
  /// **'Pixel format'**
  String get settings_video_pixelFormat_label;

  /// No description provided for @settings_video_bitDepth_label.
  ///
  /// In en, this message translates to:
  /// **'Bit depth'**
  String get settings_video_bitDepth_label;

  /// No description provided for @settings_video_chroma_label.
  ///
  /// In en, this message translates to:
  /// **'Chroma'**
  String get settings_video_chroma_label;

  /// No description provided for @settings_video_dithering_label.
  ///
  /// In en, this message translates to:
  /// **'Dithering'**
  String get settings_video_dithering_label;

  /// No description provided for @settings_video_interpolation_label.
  ///
  /// In en, this message translates to:
  /// **'Interpolation'**
  String get settings_video_interpolation_label;

  /// No description provided for @settings_video_debanding_label.
  ///
  /// In en, this message translates to:
  /// **'Debanding'**
  String get settings_video_debanding_label;

  /// No description provided for @settings_video_gpuRendering_label.
  ///
  /// In en, this message translates to:
  /// **'GPU rendering options'**
  String get settings_video_gpuRendering_label;

  /// No description provided for @settings_video_displayModeWhitelist_label.
  ///
  /// In en, this message translates to:
  /// **'Display mode whitelist'**
  String get settings_video_displayModeWhitelist_label;

  /// No description provided for @settings_audio_outputDevice_label.
  ///
  /// In en, this message translates to:
  /// **'Output device'**
  String get settings_audio_outputDevice_label;

  /// No description provided for @settings_audio_speakerLayout_label.
  ///
  /// In en, this message translates to:
  /// **'Speaker layout'**
  String get settings_audio_speakerLayout_label;

  /// No description provided for @settings_audio_normalizeVolume_label.
  ///
  /// In en, this message translates to:
  /// **'Normalize volume'**
  String get settings_audio_normalizeVolume_label;

  /// No description provided for @settings_audio_outputMode_label.
  ///
  /// In en, this message translates to:
  /// **'Output mode'**
  String get settings_audio_outputMode_label;

  /// No description provided for @settings_audio_passthrough_label.
  ///
  /// In en, this message translates to:
  /// **'Passthrough'**
  String get settings_audio_passthrough_label;

  /// No description provided for @settings_audio_passthroughDevice_label.
  ///
  /// In en, this message translates to:
  /// **'Passthrough device'**
  String get settings_audio_passthroughDevice_label;

  /// No description provided for @settings_audio_receiver_dolbyDigital_label.
  ///
  /// In en, this message translates to:
  /// **'Receiver supports Dolby Digital'**
  String get settings_audio_receiver_dolbyDigital_label;

  /// No description provided for @settings_audio_receiver_ddPlus_label.
  ///
  /// In en, this message translates to:
  /// **'Receiver supports Dolby Digital Plus'**
  String get settings_audio_receiver_ddPlus_label;

  /// No description provided for @settings_audio_receiver_dts_label.
  ///
  /// In en, this message translates to:
  /// **'Receiver supports DTS'**
  String get settings_audio_receiver_dts_label;

  /// No description provided for @settings_audio_receiver_trueHd_label.
  ///
  /// In en, this message translates to:
  /// **'Receiver supports Dolby TrueHD'**
  String get settings_audio_receiver_trueHd_label;

  /// No description provided for @settings_audio_receiver_dtsHd_label.
  ///
  /// In en, this message translates to:
  /// **'Receiver supports DTS-HD'**
  String get settings_audio_receiver_dtsHd_label;

  /// No description provided for @settings_audio_receiver_atmos_label.
  ///
  /// In en, this message translates to:
  /// **'Receiver supports Dolby Atmos'**
  String get settings_audio_receiver_atmos_label;

  /// No description provided for @settings_audio_receiver_dtsX_label.
  ///
  /// In en, this message translates to:
  /// **'Receiver supports DTS:X'**
  String get settings_audio_receiver_dtsX_label;

  /// No description provided for @settings_audio_multichannelLpcm_label.
  ///
  /// In en, this message translates to:
  /// **'Multichannel LPCM'**
  String get settings_audio_multichannelLpcm_label;

  /// No description provided for @settings_audio_ac3Transcode_label.
  ///
  /// In en, this message translates to:
  /// **'AC3 transcoding'**
  String get settings_audio_ac3Transcode_label;

  /// No description provided for @settings_audio_stereoUpmix_label.
  ///
  /// In en, this message translates to:
  /// **'Stereo upmix'**
  String get settings_audio_stereoUpmix_label;

  /// No description provided for @settings_audio_downmixDialogue_label.
  ///
  /// In en, this message translates to:
  /// **'Downmix dialogue'**
  String get settings_audio_downmixDialogue_label;

  /// No description provided for @settings_audio_resamplingQuality_label.
  ///
  /// In en, this message translates to:
  /// **'Resampling quality'**
  String get settings_audio_resamplingQuality_label;

  /// No description provided for @settings_audio_sampleRate_label.
  ///
  /// In en, this message translates to:
  /// **'Sample rate'**
  String get settings_audio_sampleRate_label;

  /// No description provided for @settings_audio_exclusiveMode_label.
  ///
  /// In en, this message translates to:
  /// **'Exclusive mode'**
  String get settings_audio_exclusiveMode_label;

  /// No description provided for @settings_audio_deviceKeepAlive_label.
  ///
  /// In en, this message translates to:
  /// **'Device keep alive'**
  String get settings_audio_deviceKeepAlive_label;

  /// No description provided for @settings_subtitles_autoEnable_label.
  ///
  /// In en, this message translates to:
  /// **'Auto enable'**
  String get settings_subtitles_autoEnable_label;

  /// No description provided for @settings_subtitles_hearingImpaired_label.
  ///
  /// In en, this message translates to:
  /// **'Hearing impaired'**
  String get settings_subtitles_hearingImpaired_label;

  /// No description provided for @settings_subtitles_font_label.
  ///
  /// In en, this message translates to:
  /// **'Font'**
  String get settings_subtitles_font_label;

  /// No description provided for @settings_subtitles_position_label.
  ///
  /// In en, this message translates to:
  /// **'Position'**
  String get settings_subtitles_position_label;

  /// No description provided for @settings_subtitles_encoding_label.
  ///
  /// In en, this message translates to:
  /// **'Encoding'**
  String get settings_subtitles_encoding_label;

  /// No description provided for @settings_subtitles_border_label.
  ///
  /// In en, this message translates to:
  /// **'Border'**
  String get settings_subtitles_border_label;

  /// No description provided for @settings_subtitles_shadow_label.
  ///
  /// In en, this message translates to:
  /// **'Shadow'**
  String get settings_subtitles_shadow_label;

  /// No description provided for @settings_subtitles_background_label.
  ///
  /// In en, this message translates to:
  /// **'Background'**
  String get settings_subtitles_background_label;

  /// No description provided for @settings_subtitles_delay_label.
  ///
  /// In en, this message translates to:
  /// **'Delay'**
  String get settings_subtitles_delay_label;

  /// No description provided for @settings_subtitles_forcedBehaviour_label.
  ///
  /// In en, this message translates to:
  /// **'Forced behaviour'**
  String get settings_subtitles_forcedBehaviour_label;

  /// No description provided for @settings_subtitles_assStyling_label.
  ///
  /// In en, this message translates to:
  /// **'ASS/SSA styling'**
  String get settings_subtitles_assStyling_label;

  /// No description provided for @settings_display_monitor_label.
  ///
  /// In en, this message translates to:
  /// **'Monitor'**
  String get settings_display_monitor_label;

  /// No description provided for @settings_display_fullscreenMode_label.
  ///
  /// In en, this message translates to:
  /// **'Fullscreen mode'**
  String get settings_display_fullscreenMode_label;

  /// No description provided for @settings_display_refreshRate_label.
  ///
  /// In en, this message translates to:
  /// **'Refresh rate'**
  String get settings_display_refreshRate_label;

  /// No description provided for @settings_display_hdrOutputMode_label.
  ///
  /// In en, this message translates to:
  /// **'Hdr output mode'**
  String get settings_display_hdrOutputMode_label;

  /// No description provided for @settings_display_calibration_label.
  ///
  /// In en, this message translates to:
  /// **'Calibration'**
  String get settings_display_calibration_label;

  /// No description provided for @settings_streaming_quality_label.
  ///
  /// In en, this message translates to:
  /// **'Quality'**
  String get settings_streaming_quality_label;

  /// No description provided for @settings_streaming_protocol_label.
  ///
  /// In en, this message translates to:
  /// **'Protocol'**
  String get settings_streaming_protocol_label;

  /// No description provided for @settings_streaming_cacheSizeLimit_label.
  ///
  /// In en, this message translates to:
  /// **'Cache size limit'**
  String get settings_streaming_cacheSizeLimit_label;

  /// No description provided for @settings_streaming_bufferSize_label.
  ///
  /// In en, this message translates to:
  /// **'Buffer size'**
  String get settings_streaming_bufferSize_label;

  /// No description provided for @settings_streaming_prebuffer_label.
  ///
  /// In en, this message translates to:
  /// **'Prebuffer'**
  String get settings_streaming_prebuffer_label;

  /// No description provided for @settings_streaming_maxHttpConnections_label.
  ///
  /// In en, this message translates to:
  /// **'Max HTTP connections'**
  String get settings_streaming_maxHttpConnections_label;

  /// No description provided for @settings_streaming_connectionTimeout_label.
  ///
  /// In en, this message translates to:
  /// **'Connection timeout'**
  String get settings_streaming_connectionTimeout_label;

  /// No description provided for @settings_streaming_retryCount_label.
  ///
  /// In en, this message translates to:
  /// **'Retry count'**
  String get settings_streaming_retryCount_label;

  /// No description provided for @settings_streaming_proxy_label.
  ///
  /// In en, this message translates to:
  /// **'Proxy'**
  String get settings_streaming_proxy_label;

  /// No description provided for @settings_streaming_userAgent_label.
  ///
  /// In en, this message translates to:
  /// **'User agent'**
  String get settings_streaming_userAgent_label;

  /// No description provided for @settings_streaming_headers_label.
  ///
  /// In en, this message translates to:
  /// **'Custom HTTP headers'**
  String get settings_streaming_headers_label;

  /// No description provided for @settings_streaming_tls_label.
  ///
  /// In en, this message translates to:
  /// **'TLS options'**
  String get settings_streaming_tls_label;

  /// No description provided for @settings_downloads_bandwidthLimit_label.
  ///
  /// In en, this message translates to:
  /// **'Bandwidth limit'**
  String get settings_downloads_bandwidthLimit_label;

  /// No description provided for @settings_downloads_torrentDownLimit_label.
  ///
  /// In en, this message translates to:
  /// **'Torrent down limit'**
  String get settings_downloads_torrentDownLimit_label;

  /// No description provided for @settings_downloads_torrentUpLimit_label.
  ///
  /// In en, this message translates to:
  /// **'Torrent up limit'**
  String get settings_downloads_torrentUpLimit_label;

  /// No description provided for @settings_downloads_connectionLimit_label.
  ///
  /// In en, this message translates to:
  /// **'Connection limit'**
  String get settings_downloads_connectionLimit_label;

  /// No description provided for @settings_downloads_peerLimit_label.
  ///
  /// In en, this message translates to:
  /// **'Peer limit'**
  String get settings_downloads_peerLimit_label;

  /// No description provided for @settings_downloads_seeding_label.
  ///
  /// In en, this message translates to:
  /// **'Seeding'**
  String get settings_downloads_seeding_label;

  /// No description provided for @settings_downloads_tracker_label.
  ///
  /// In en, this message translates to:
  /// **'Tracker'**
  String get settings_downloads_tracker_label;

  /// No description provided for @settings_downloads_dht_label.
  ///
  /// In en, this message translates to:
  /// **'DHT'**
  String get settings_downloads_dht_label;

  /// No description provided for @settings_downloads_pex_label.
  ///
  /// In en, this message translates to:
  /// **'PEX'**
  String get settings_downloads_pex_label;

  /// No description provided for @settings_languages_preferOriginalAudio_label.
  ///
  /// In en, this message translates to:
  /// **'Prefer original audio'**
  String get settings_languages_preferOriginalAudio_label;

  /// No description provided for @settings_languages_preferForcedSubtitles_label.
  ///
  /// In en, this message translates to:
  /// **'Prefer forced subtitles'**
  String get settings_languages_preferForcedSubtitles_label;

  /// No description provided for @settings_languages_preferBestAudio_label.
  ///
  /// In en, this message translates to:
  /// **'Prefer best audio'**
  String get settings_languages_preferBestAudio_label;

  /// No description provided for @settings_languages_trackPriority_label.
  ///
  /// In en, this message translates to:
  /// **'Track priority'**
  String get settings_languages_trackPriority_label;

  /// No description provided for @settings_performance_mode_label.
  ///
  /// In en, this message translates to:
  /// **'Mode'**
  String get settings_performance_mode_label;

  /// No description provided for @settings_performance_gpuQuality_label.
  ///
  /// In en, this message translates to:
  /// **'GPU quality'**
  String get settings_performance_gpuQuality_label;

  /// No description provided for @settings_performance_backgroundPreload_label.
  ///
  /// In en, this message translates to:
  /// **'Background preload'**
  String get settings_performance_backgroundPreload_label;

  /// No description provided for @settings_performance_decoderThreads_label.
  ///
  /// In en, this message translates to:
  /// **'Decoder threads'**
  String get settings_performance_decoderThreads_label;

  /// No description provided for @settings_advanced_diagnostics_label.
  ///
  /// In en, this message translates to:
  /// **'Playback diagnostics'**
  String get settings_advanced_diagnostics_label;

  /// No description provided for @settings_advanced_customMpvOptions_label.
  ///
  /// In en, this message translates to:
  /// **'Custom mpv options'**
  String get settings_advanced_customMpvOptions_label;

  /// No description provided for @settings_playback_preferredAudioLanguage_label.
  ///
  /// In en, this message translates to:
  /// **'Preferred audio language'**
  String get settings_playback_preferredAudioLanguage_label;

  /// No description provided for @settings_playback_preferredSubtitleLanguage_label.
  ///
  /// In en, this message translates to:
  /// **'Preferred subtitle language'**
  String get settings_playback_preferredSubtitleLanguage_label;

  /// No description provided for @settings_playback_defaultSubtitleSize_label.
  ///
  /// In en, this message translates to:
  /// **'Subtitle size'**
  String get settings_playback_defaultSubtitleSize_label;

  /// No description provided for @settings_app_language_label.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settings_app_language_label;

  /// No description provided for @settings_language_choice_en.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get settings_language_choice_en;

  /// No description provided for @settings_language_choice_fa.
  ///
  /// In en, this message translates to:
  /// **'Persian'**
  String get settings_language_choice_fa;

  /// No description provided for @settings_language_choice_ar.
  ///
  /// In en, this message translates to:
  /// **'Arabic'**
  String get settings_language_choice_ar;

  /// No description provided for @settings_language_choice_fr.
  ///
  /// In en, this message translates to:
  /// **'French'**
  String get settings_language_choice_fr;

  /// No description provided for @settings_language_choice_de.
  ///
  /// In en, this message translates to:
  /// **'German'**
  String get settings_language_choice_de;

  /// No description provided for @settings_language_choice_es.
  ///
  /// In en, this message translates to:
  /// **'Spanish'**
  String get settings_language_choice_es;

  /// No description provided for @settings_language_choice_tr.
  ///
  /// In en, this message translates to:
  /// **'Turkish'**
  String get settings_language_choice_tr;

  /// No description provided for @settings_language_choice_ru.
  ///
  /// In en, this message translates to:
  /// **'Russian'**
  String get settings_language_choice_ru;

  /// No description provided for @settings_language_choice_ja.
  ///
  /// In en, this message translates to:
  /// **'Japanese'**
  String get settings_language_choice_ja;

  /// No description provided for @settings_language_choice_ko.
  ///
  /// In en, this message translates to:
  /// **'Korean'**
  String get settings_language_choice_ko;

  /// No description provided for @settings_language_choice_zh.
  ///
  /// In en, this message translates to:
  /// **'Chinese'**
  String get settings_language_choice_zh;

  /// No description provided for @settings_playback_resume_choice_Ask.
  ///
  /// In en, this message translates to:
  /// **'Ask'**
  String get settings_playback_resume_choice_Ask;

  /// No description provided for @settings_playback_resume_choice_Always.
  ///
  /// In en, this message translates to:
  /// **'Always'**
  String get settings_playback_resume_choice_Always;

  /// No description provided for @settings_playback_resume_choice_Never.
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get settings_playback_resume_choice_Never;

  /// No description provided for @settings_playback_cachePreset_choice_Low_latency.
  ///
  /// In en, this message translates to:
  /// **'Low latency'**
  String get settings_playback_cachePreset_choice_Low_latency;

  /// No description provided for @settings_playback_cachePreset_choice_Balanced.
  ///
  /// In en, this message translates to:
  /// **'Balanced'**
  String get settings_playback_cachePreset_choice_Balanced;

  /// No description provided for @settings_playback_cachePreset_choice_Large.
  ///
  /// In en, this message translates to:
  /// **'Large'**
  String get settings_playback_cachePreset_choice_Large;

  /// No description provided for @settings_video_hdr_choice_Force_SDR.
  ///
  /// In en, this message translates to:
  /// **'Force SDR'**
  String get settings_video_hdr_choice_Force_SDR;

  /// No description provided for @settings_video_hdr_choice_Passthrough_HDR.
  ///
  /// In en, this message translates to:
  /// **'Passthrough HDR'**
  String get settings_video_hdr_choice_Passthrough_HDR;

  /// No description provided for @settings_video_matchFrameRate_choice_On_start_stop.
  ///
  /// In en, this message translates to:
  /// **'On start-stop'**
  String get settings_video_matchFrameRate_choice_On_start_stop;

  /// No description provided for @settings_video_matchFrameRate_choice_Always.
  ///
  /// In en, this message translates to:
  /// **'Always'**
  String get settings_video_matchFrameRate_choice_Always;

  /// No description provided for @settings_video_aspectRatio_choice_Original.
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get settings_video_aspectRatio_choice_Original;

  /// No description provided for @settings_video_aspectRatio_choice_Fit.
  ///
  /// In en, this message translates to:
  /// **'Fit'**
  String get settings_video_aspectRatio_choice_Fit;

  /// No description provided for @settings_video_aspectRatio_choice_Fill.
  ///
  /// In en, this message translates to:
  /// **'Fill'**
  String get settings_video_aspectRatio_choice_Fill;

  /// No description provided for @settings_video_aspectRatio_choice_Stretch.
  ///
  /// In en, this message translates to:
  /// **'Stretch'**
  String get settings_video_aspectRatio_choice_Stretch;

  /// No description provided for @settings_video_decoder_choice_hardware.
  ///
  /// In en, this message translates to:
  /// **'hardware'**
  String get settings_video_decoder_choice_hardware;

  /// No description provided for @settings_video_decoder_choice_software.
  ///
  /// In en, this message translates to:
  /// **'software'**
  String get settings_video_decoder_choice_software;

  /// No description provided for @settings_video_scalingQuality_choice_Fast.
  ///
  /// In en, this message translates to:
  /// **'Fast'**
  String get settings_video_scalingQuality_choice_Fast;

  /// No description provided for @settings_video_scalingQuality_choice_Balanced.
  ///
  /// In en, this message translates to:
  /// **'Balanced'**
  String get settings_video_scalingQuality_choice_Balanced;

  /// No description provided for @settings_video_scalingQuality_choice_High.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get settings_video_scalingQuality_choice_High;

  /// No description provided for @settings_video_toneMapping_choice_clip.
  ///
  /// In en, this message translates to:
  /// **'clip'**
  String get settings_video_toneMapping_choice_clip;

  /// No description provided for @settings_video_toneMapping_choice_mobius.
  ///
  /// In en, this message translates to:
  /// **'mobius'**
  String get settings_video_toneMapping_choice_mobius;

  /// No description provided for @settings_video_toneMapping_choice_reinhard.
  ///
  /// In en, this message translates to:
  /// **'reinhard'**
  String get settings_video_toneMapping_choice_reinhard;

  /// No description provided for @settings_video_toneMapping_choice_hable.
  ///
  /// In en, this message translates to:
  /// **'hable'**
  String get settings_video_toneMapping_choice_hable;

  /// No description provided for @settings_video_toneMapping_choice_gamma.
  ///
  /// In en, this message translates to:
  /// **'gamma'**
  String get settings_video_toneMapping_choice_gamma;

  /// No description provided for @settings_video_toneMapping_choice_linear.
  ///
  /// In en, this message translates to:
  /// **'linear'**
  String get settings_video_toneMapping_choice_linear;

  /// No description provided for @settings_video_toneMapping_choice_spline.
  ///
  /// In en, this message translates to:
  /// **'spline'**
  String get settings_video_toneMapping_choice_spline;

  /// No description provided for @settings_video_toneMapping_choice_bt_2390.
  ///
  /// In en, this message translates to:
  /// **'bt.2390'**
  String get settings_video_toneMapping_choice_bt_2390;

  /// No description provided for @settings_video_toneMapping_choice_bt_2446a.
  ///
  /// In en, this message translates to:
  /// **'bt.2446a'**
  String get settings_video_toneMapping_choice_bt_2446a;

  /// No description provided for @settings_video_toneMapping_choice_st2094_40.
  ///
  /// In en, this message translates to:
  /// **'st2094-40'**
  String get settings_video_toneMapping_choice_st2094_40;

  /// No description provided for @settings_video_toneMapping_choice_st2094_10.
  ///
  /// In en, this message translates to:
  /// **'st2094-10'**
  String get settings_video_toneMapping_choice_st2094_10;

  /// No description provided for @settings_video_pixelFormat_choice_nv12.
  ///
  /// In en, this message translates to:
  /// **'nv12'**
  String get settings_video_pixelFormat_choice_nv12;

  /// No description provided for @settings_video_pixelFormat_choice_yuv420p.
  ///
  /// In en, this message translates to:
  /// **'yuv420p'**
  String get settings_video_pixelFormat_choice_yuv420p;

  /// No description provided for @settings_video_pixelFormat_choice_yuv420p10.
  ///
  /// In en, this message translates to:
  /// **'yuv420p10'**
  String get settings_video_pixelFormat_choice_yuv420p10;

  /// No description provided for @settings_video_pixelFormat_choice_yuv422p.
  ///
  /// In en, this message translates to:
  /// **'yuv422p'**
  String get settings_video_pixelFormat_choice_yuv422p;

  /// No description provided for @settings_video_pixelFormat_choice_yuv422p10.
  ///
  /// In en, this message translates to:
  /// **'yuv422p10'**
  String get settings_video_pixelFormat_choice_yuv422p10;

  /// No description provided for @settings_video_pixelFormat_choice_yuv444p.
  ///
  /// In en, this message translates to:
  /// **'yuv444p'**
  String get settings_video_pixelFormat_choice_yuv444p;

  /// No description provided for @settings_video_pixelFormat_choice_yuv444p10.
  ///
  /// In en, this message translates to:
  /// **'yuv444p10'**
  String get settings_video_pixelFormat_choice_yuv444p10;

  /// No description provided for @settings_video_pixelFormat_choice_rgb24.
  ///
  /// In en, this message translates to:
  /// **'rgb24'**
  String get settings_video_pixelFormat_choice_rgb24;

  /// No description provided for @settings_video_chroma_choice_4_2_0.
  ///
  /// In en, this message translates to:
  /// **'4:2:0'**
  String get settings_video_chroma_choice_4_2_0;

  /// No description provided for @settings_video_chroma_choice_4_2_2.
  ///
  /// In en, this message translates to:
  /// **'4:2:2'**
  String get settings_video_chroma_choice_4_2_2;

  /// No description provided for @settings_video_chroma_choice_4_4_4.
  ///
  /// In en, this message translates to:
  /// **'4:4:4'**
  String get settings_video_chroma_choice_4_4_4;

  /// No description provided for @settings_video_dithering_choice_fruit.
  ///
  /// In en, this message translates to:
  /// **'fruit'**
  String get settings_video_dithering_choice_fruit;

  /// No description provided for @settings_video_dithering_choice_ordered.
  ///
  /// In en, this message translates to:
  /// **'ordered'**
  String get settings_video_dithering_choice_ordered;

  /// No description provided for @settings_video_gpuRendering_choice_opengl.
  ///
  /// In en, this message translates to:
  /// **'opengl'**
  String get settings_video_gpuRendering_choice_opengl;

  /// No description provided for @settings_audio_speakerLayout_choice_Stereo.
  ///
  /// In en, this message translates to:
  /// **'Stereo'**
  String get settings_audio_speakerLayout_choice_Stereo;

  /// No description provided for @settings_audio_outputMode_choice_Best_Match.
  ///
  /// In en, this message translates to:
  /// **'Best Match'**
  String get settings_audio_outputMode_choice_Best_Match;

  /// No description provided for @settings_audio_outputMode_choice_Fixed.
  ///
  /// In en, this message translates to:
  /// **'Fixed'**
  String get settings_audio_outputMode_choice_Fixed;

  /// No description provided for @settings_audio_outputMode_choice_Optimized.
  ///
  /// In en, this message translates to:
  /// **'Optimized'**
  String get settings_audio_outputMode_choice_Optimized;

  /// No description provided for @settings_audio_resamplingQuality_choice_Fast.
  ///
  /// In en, this message translates to:
  /// **'Fast'**
  String get settings_audio_resamplingQuality_choice_Fast;

  /// No description provided for @settings_audio_resamplingQuality_choice_Balanced.
  ///
  /// In en, this message translates to:
  /// **'Balanced'**
  String get settings_audio_resamplingQuality_choice_Balanced;

  /// No description provided for @settings_audio_resamplingQuality_choice_High.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get settings_audio_resamplingQuality_choice_High;

  /// No description provided for @settings_subtitles_hearingImpaired_choice_Prefer.
  ///
  /// In en, this message translates to:
  /// **'Prefer'**
  String get settings_subtitles_hearingImpaired_choice_Prefer;

  /// No description provided for @settings_subtitles_hearingImpaired_choice_Avoid.
  ///
  /// In en, this message translates to:
  /// **'Avoid'**
  String get settings_subtitles_hearingImpaired_choice_Avoid;

  /// No description provided for @settings_subtitles_hearingImpaired_choice_No_preference.
  ///
  /// In en, this message translates to:
  /// **'No preference'**
  String get settings_subtitles_hearingImpaired_choice_No_preference;

  /// No description provided for @settings_subtitles_encoding_choice_utf_8.
  ///
  /// In en, this message translates to:
  /// **'utf-8'**
  String get settings_subtitles_encoding_choice_utf_8;

  /// No description provided for @settings_subtitles_encoding_choice_cp1250.
  ///
  /// In en, this message translates to:
  /// **'cp1250'**
  String get settings_subtitles_encoding_choice_cp1250;

  /// No description provided for @settings_subtitles_encoding_choice_cp1251.
  ///
  /// In en, this message translates to:
  /// **'cp1251'**
  String get settings_subtitles_encoding_choice_cp1251;

  /// No description provided for @settings_subtitles_encoding_choice_cp1252.
  ///
  /// In en, this message translates to:
  /// **'cp1252'**
  String get settings_subtitles_encoding_choice_cp1252;

  /// No description provided for @settings_subtitles_encoding_choice_cp1253.
  ///
  /// In en, this message translates to:
  /// **'cp1253'**
  String get settings_subtitles_encoding_choice_cp1253;

  /// No description provided for @settings_subtitles_encoding_choice_cp1254.
  ///
  /// In en, this message translates to:
  /// **'cp1254'**
  String get settings_subtitles_encoding_choice_cp1254;

  /// No description provided for @settings_subtitles_encoding_choice_cp1256.
  ///
  /// In en, this message translates to:
  /// **'cp1256'**
  String get settings_subtitles_encoding_choice_cp1256;

  /// No description provided for @settings_subtitles_encoding_choice_iso_8859_1.
  ///
  /// In en, this message translates to:
  /// **'iso-8859-1'**
  String get settings_subtitles_encoding_choice_iso_8859_1;

  /// No description provided for @settings_subtitles_encoding_choice_iso_8859_2.
  ///
  /// In en, this message translates to:
  /// **'iso-8859-2'**
  String get settings_subtitles_encoding_choice_iso_8859_2;

  /// No description provided for @settings_subtitles_encoding_choice_shift_jis.
  ///
  /// In en, this message translates to:
  /// **'shift_jis'**
  String get settings_subtitles_encoding_choice_shift_jis;

  /// No description provided for @settings_subtitles_encoding_choice_gbk.
  ///
  /// In en, this message translates to:
  /// **'gbk'**
  String get settings_subtitles_encoding_choice_gbk;

  /// No description provided for @settings_subtitles_encoding_choice_big5.
  ///
  /// In en, this message translates to:
  /// **'big5'**
  String get settings_subtitles_encoding_choice_big5;

  /// No description provided for @settings_subtitles_encoding_choice_euc_kr.
  ///
  /// In en, this message translates to:
  /// **'euc-kr'**
  String get settings_subtitles_encoding_choice_euc_kr;

  /// No description provided for @settings_subtitles_forcedBehaviour_choice_Always.
  ///
  /// In en, this message translates to:
  /// **'Always'**
  String get settings_subtitles_forcedBehaviour_choice_Always;

  /// No description provided for @settings_subtitles_forcedBehaviour_choice_Never.
  ///
  /// In en, this message translates to:
  /// **'Never'**
  String get settings_subtitles_forcedBehaviour_choice_Never;

  /// No description provided for @settings_subtitles_assStyling_choice_Embedded.
  ///
  /// In en, this message translates to:
  /// **'Embedded'**
  String get settings_subtitles_assStyling_choice_Embedded;

  /// No description provided for @settings_subtitles_assStyling_choice_Override.
  ///
  /// In en, this message translates to:
  /// **'Override'**
  String get settings_subtitles_assStyling_choice_Override;

  /// No description provided for @settings_subtitles_assStyling_choice_Hybrid.
  ///
  /// In en, this message translates to:
  /// **'Hybrid'**
  String get settings_subtitles_assStyling_choice_Hybrid;

  /// No description provided for @settings_display_fullscreenMode_choice_Windowed.
  ///
  /// In en, this message translates to:
  /// **'Windowed'**
  String get settings_display_fullscreenMode_choice_Windowed;

  /// No description provided for @settings_display_fullscreenMode_choice_Fullscreen.
  ///
  /// In en, this message translates to:
  /// **'Fullscreen'**
  String get settings_display_fullscreenMode_choice_Fullscreen;

  /// No description provided for @settings_display_hdrOutputMode_choice_SDR.
  ///
  /// In en, this message translates to:
  /// **'SDR'**
  String get settings_display_hdrOutputMode_choice_SDR;

  /// No description provided for @settings_display_hdrOutputMode_choice_HDR10.
  ///
  /// In en, this message translates to:
  /// **'HDR10'**
  String get settings_display_hdrOutputMode_choice_HDR10;

  /// No description provided for @settings_display_hdrOutputMode_choice_Dolby_Vision.
  ///
  /// In en, this message translates to:
  /// **'Dolby Vision'**
  String get settings_display_hdrOutputMode_choice_Dolby_Vision;

  /// No description provided for @settings_streaming_quality_choice_Original.
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get settings_streaming_quality_choice_Original;

  /// No description provided for @settings_streaming_protocol_choice_HTTP.
  ///
  /// In en, this message translates to:
  /// **'HTTP'**
  String get settings_streaming_protocol_choice_HTTP;

  /// No description provided for @settings_streaming_protocol_choice_Torrent.
  ///
  /// In en, this message translates to:
  /// **'Torrent'**
  String get settings_streaming_protocol_choice_Torrent;

  /// No description provided for @settings_streaming_tls_choice_Verify.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get settings_streaming_tls_choice_Verify;

  /// No description provided for @settings_streaming_tls_choice_Don_t_verify.
  ///
  /// In en, this message translates to:
  /// **'Don\'t verify'**
  String get settings_streaming_tls_choice_Don_t_verify;

  /// No description provided for @settings_downloads_seeding_choice_ratio.
  ///
  /// In en, this message translates to:
  /// **'ratio'**
  String get settings_downloads_seeding_choice_ratio;

  /// No description provided for @settings_downloads_seeding_choice_duration.
  ///
  /// In en, this message translates to:
  /// **'duration'**
  String get settings_downloads_seeding_choice_duration;

  /// No description provided for @settings_languages_preferBestAudio_choice_Atmos.
  ///
  /// In en, this message translates to:
  /// **'Atmos'**
  String get settings_languages_preferBestAudio_choice_Atmos;

  /// No description provided for @settings_languages_preferBestAudio_choice_lossless.
  ///
  /// In en, this message translates to:
  /// **'lossless'**
  String get settings_languages_preferBestAudio_choice_lossless;

  /// No description provided for @settings_languages_preferBestAudio_choice_highest_channel.
  ///
  /// In en, this message translates to:
  /// **'highest-channel'**
  String get settings_languages_preferBestAudio_choice_highest_channel;

  /// No description provided for @settings_performance_mode_choice_Battery_saver.
  ///
  /// In en, this message translates to:
  /// **'Battery saver'**
  String get settings_performance_mode_choice_Battery_saver;

  /// No description provided for @settings_performance_mode_choice_Quality.
  ///
  /// In en, this message translates to:
  /// **'Quality'**
  String get settings_performance_mode_choice_Quality;

  /// No description provided for @settings_performance_gpuQuality_choice_Fast.
  ///
  /// In en, this message translates to:
  /// **'Fast'**
  String get settings_performance_gpuQuality_choice_Fast;

  /// No description provided for @settings_performance_gpuQuality_choice_High.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get settings_performance_gpuQuality_choice_High;

  /// No description provided for @settings_playback_defaultSubtitleSize_choice_Small.
  ///
  /// In en, this message translates to:
  /// **'Small'**
  String get settings_playback_defaultSubtitleSize_choice_Small;

  /// No description provided for @settings_playback_defaultSubtitleSize_choice_Normal.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get settings_playback_defaultSubtitleSize_choice_Normal;

  /// No description provided for @settings_playback_defaultSubtitleSize_choice_Large.
  ///
  /// In en, this message translates to:
  /// **'Large'**
  String get settings_playback_defaultSubtitleSize_choice_Large;

  /// No description provided for @settings_playback_defaultSubtitleSize_choice_Extra_large.
  ///
  /// In en, this message translates to:
  /// **'Extra large'**
  String get settings_playback_defaultSubtitleSize_choice_Extra_large;

  /// No description provided for @settings_forcedOnly.
  ///
  /// In en, this message translates to:
  /// **'Forced only'**
  String get settings_forcedOnly;

  /// No description provided for @settings_original.
  ///
  /// In en, this message translates to:
  /// **'Original'**
  String get settings_original;

  /// No description provided for @settings_none.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get settings_none;

  /// No description provided for @settings_applyNext.
  ///
  /// In en, this message translates to:
  /// **'Applies on next playback'**
  String get settings_applyNext;

  /// No description provided for @settings_restartNeeded.
  ///
  /// In en, this message translates to:
  /// **'Restart needed'**
  String get settings_restartNeeded;

  /// No description provided for @settings_playback_title.
  ///
  /// In en, this message translates to:
  /// **'Playback'**
  String get settings_playback_title;

  /// No description provided for @settings_video_title.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get settings_video_title;

  /// No description provided for @settings_audio_title.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get settings_audio_title;

  /// No description provided for @settings_subtitles_title.
  ///
  /// In en, this message translates to:
  /// **'Subtitles'**
  String get settings_subtitles_title;

  /// No description provided for @settings_display_title.
  ///
  /// In en, this message translates to:
  /// **'Display'**
  String get settings_display_title;

  /// No description provided for @settings_streaming_title.
  ///
  /// In en, this message translates to:
  /// **'Streaming & Network'**
  String get settings_streaming_title;

  /// No description provided for @settings_downloads_title.
  ///
  /// In en, this message translates to:
  /// **'Downloads & Torrent'**
  String get settings_downloads_title;

  /// No description provided for @settings_languages_title.
  ///
  /// In en, this message translates to:
  /// **'Languages & Tracks'**
  String get settings_languages_title;

  /// No description provided for @settings_performance_title.
  ///
  /// In en, this message translates to:
  /// **'Performance'**
  String get settings_performance_title;

  /// No description provided for @settings_advanced_title.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get settings_advanced_title;

  /// No description provided for @settings_decrease.
  ///
  /// In en, this message translates to:
  /// **'Decrease'**
  String get settings_decrease;

  /// No description provided for @settings_increase.
  ///
  /// In en, this message translates to:
  /// **'Increase'**
  String get settings_increase;

  /// No description provided for @settings_unlimited.
  ///
  /// In en, this message translates to:
  /// **'Unlimited'**
  String get settings_unlimited;

  /// No description provided for @settings_providers.
  ///
  /// In en, this message translates to:
  /// **'Providers'**
  String get settings_providers;

  /// No description provided for @settings_advancedSettings.
  ///
  /// In en, this message translates to:
  /// **'Advanced settings'**
  String get settings_advancedSettings;

  /// No description provided for @settings_expert.
  ///
  /// In en, this message translates to:
  /// **'Expert'**
  String get settings_expert;

  /// No description provided for @settings_diagnostics.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get settings_diagnostics;

  /// No description provided for @settings_skipForward.
  ///
  /// In en, this message translates to:
  /// **'Skip forward'**
  String get settings_skipForward;

  /// No description provided for @settings_verboseLogging.
  ///
  /// In en, this message translates to:
  /// **'Verbose logging'**
  String get settings_verboseLogging;

  /// No description provided for @settings_clearCache.
  ///
  /// In en, this message translates to:
  /// **'Clear cache'**
  String get settings_clearCache;

  /// No description provided for @settings_deviceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Saved audio device unavailable; using Auto.'**
  String get settings_deviceUnavailable;

  /// No description provided for @settings_noReceiverFormats.
  ///
  /// In en, this message translates to:
  /// **'No receiver formats selected'**
  String get settings_noReceiverFormats;

  /// No description provided for @player_replayTen.
  ///
  /// In en, this message translates to:
  /// **'Replay 10 seconds'**
  String get player_replayTen;

  /// No description provided for @player_skipThirty.
  ///
  /// In en, this message translates to:
  /// **'Skip 30 seconds'**
  String get player_skipThirty;

  /// No description provided for @player_loading.
  ///
  /// In en, this message translates to:
  /// **'Loading'**
  String get player_loading;

  /// No description provided for @player_chapters.
  ///
  /// In en, this message translates to:
  /// **'Chapters'**
  String get player_chapters;

  /// No description provided for @player_advanced.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get player_advanced;

  /// No description provided for @player_copyDebug.
  ///
  /// In en, this message translates to:
  /// **'Copy debug info'**
  String get player_copyDebug;

  /// No description provided for @player_castTo.
  ///
  /// In en, this message translates to:
  /// **'Cast to'**
  String get player_castTo;

  /// No description provided for @player_close.
  ///
  /// In en, this message translates to:
  /// **'Close player'**
  String get player_close;

  /// No description provided for @player_subtitles.
  ///
  /// In en, this message translates to:
  /// **'Subtitles'**
  String get player_subtitles;

  /// No description provided for @player_audio.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get player_audio;

  /// No description provided for @player_options.
  ///
  /// In en, this message translates to:
  /// **'Options'**
  String get player_options;

  /// No description provided for @player_downloadInfo.
  ///
  /// In en, this message translates to:
  /// **'Download info'**
  String get player_downloadInfo;

  /// No description provided for @player_upNext.
  ///
  /// In en, this message translates to:
  /// **'Up Next'**
  String get player_upNext;

  /// No description provided for @player_download.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get player_download;

  /// No description provided for @player_nextEpisode.
  ///
  /// In en, this message translates to:
  /// **'Next episode'**
  String get player_nextEpisode;

  /// No description provided for @player_addSubtitleFile.
  ///
  /// In en, this message translates to:
  /// **'Add subtitle file…'**
  String get player_addSubtitleFile;

  /// No description provided for @player_defaultBadge.
  ///
  /// In en, this message translates to:
  /// **'DEFAULT'**
  String get player_defaultBadge;

  /// No description provided for @player_tracks.
  ///
  /// In en, this message translates to:
  /// **'Tracks'**
  String get player_tracks;

  /// No description provided for @player_video.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get player_video;

  /// No description provided for @player_upNextUpper.
  ///
  /// In en, this message translates to:
  /// **'UP NEXT'**
  String get player_upNextUpper;

  /// No description provided for @player_playNext.
  ///
  /// In en, this message translates to:
  /// **'Play Next'**
  String get player_playNext;

  /// No description provided for @player_countdownCanceled.
  ///
  /// In en, this message translates to:
  /// **'Countdown canceled'**
  String get player_countdownCanceled;

  /// No description provided for @player_resumeCountdown.
  ///
  /// In en, this message translates to:
  /// **'Resume countdown'**
  String get player_resumeCountdown;

  /// No description provided for @player_pauseCountdown.
  ///
  /// In en, this message translates to:
  /// **'Pause countdown'**
  String get player_pauseCountdown;

  /// No description provided for @player_cancelCountdown.
  ///
  /// In en, this message translates to:
  /// **'Cancel countdown'**
  String get player_cancelCountdown;

  /// No description provided for @player_season.
  ///
  /// In en, this message translates to:
  /// **'Season'**
  String get player_season;

  /// No description provided for @player_show.
  ///
  /// In en, this message translates to:
  /// **'Show'**
  String get player_show;

  /// No description provided for @providers_noAccount.
  ///
  /// In en, this message translates to:
  /// **'No account needed'**
  String get providers_noAccount;

  /// No description provided for @providers_unavailable.
  ///
  /// In en, this message translates to:
  /// **'Sign-in is not available in the app yet'**
  String get providers_unavailable;

  /// No description provided for @providers_signedIn.
  ///
  /// In en, this message translates to:
  /// **'Signed in'**
  String get providers_signedIn;

  /// No description provided for @providers_signedOut.
  ///
  /// In en, this message translates to:
  /// **'Not signed in'**
  String get providers_signedOut;

  /// No description provided for @providers_free.
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get providers_free;

  /// No description provided for @providers_signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get providers_signOut;

  /// No description provided for @providers_signInQr.
  ///
  /// In en, this message translates to:
  /// **'Sign in with QR code'**
  String get providers_signInQr;

  /// No description provided for @providers_signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get providers_signIn;

  /// No description provided for @providers_buy.
  ///
  /// In en, this message translates to:
  /// **'Buy account'**
  String get providers_buy;

  /// No description provided for @providers_username.
  ///
  /// In en, this message translates to:
  /// **'Username or email'**
  String get providers_username;

  /// No description provided for @providers_password.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get providers_password;

  /// No description provided for @providers_signingIn.
  ///
  /// In en, this message translates to:
  /// **'Signing in…'**
  String get providers_signingIn;

  /// No description provided for @providers_newCode.
  ///
  /// In en, this message translates to:
  /// **'New code'**
  String get providers_newCode;

  /// No description provided for @player_infoFormat.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get player_infoFormat;

  /// No description provided for @player_infoSize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get player_infoSize;

  /// No description provided for @player_infoLength.
  ///
  /// In en, this message translates to:
  /// **'Length'**
  String get player_infoLength;

  /// No description provided for @player_infoBitrate.
  ///
  /// In en, this message translates to:
  /// **'Bitrate'**
  String get player_infoBitrate;

  /// No description provided for @player_infoVideo.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get player_infoVideo;

  /// No description provided for @player_infoAudio.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get player_infoAudio;

  /// No description provided for @player_infoSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Subtitle'**
  String get player_infoSubtitle;

  /// No description provided for @player_infoFile.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get player_infoFile;

  /// No description provided for @player_infoStreams.
  ///
  /// In en, this message translates to:
  /// **'Streams'**
  String get player_infoStreams;

  /// No description provided for @player_backToSubtitles.
  ///
  /// In en, this message translates to:
  /// **'Back to subtitles'**
  String get player_backToSubtitles;

  /// No description provided for @player_noSubtitleSources.
  ///
  /// In en, this message translates to:
  /// **'No subtitle sources yet'**
  String get player_noSubtitleSources;

  /// No description provided for @player_size.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get player_size;

  /// No description provided for @player_position.
  ///
  /// In en, this message translates to:
  /// **'Position'**
  String get player_position;

  /// No description provided for @player_aspectRatio.
  ///
  /// In en, this message translates to:
  /// **'Aspect ratio'**
  String get player_aspectRatio;

  /// No description provided for @player_downloadSubtitles.
  ///
  /// In en, this message translates to:
  /// **'Download subtitles…'**
  String get player_downloadSubtitles;

  /// No description provided for @player_subtitleUri.
  ///
  /// In en, this message translates to:
  /// **'Subtitle URI'**
  String get player_subtitleUri;

  /// No description provided for @player_subtitleUriHint.
  ///
  /// In en, this message translates to:
  /// **'https://… or file:///…'**
  String get player_subtitleUriHint;

  /// No description provided for @player_addExternalSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Add external subtitle'**
  String get player_addExternalSubtitle;

  /// No description provided for @player_fillScreen.
  ///
  /// In en, this message translates to:
  /// **'Fill screen'**
  String get player_fillScreen;

  /// No description provided for @player_speed.
  ///
  /// In en, this message translates to:
  /// **'Speed'**
  String get player_speed;

  /// No description provided for @player_reset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get player_reset;

  /// No description provided for @player_delay.
  ///
  /// In en, this message translates to:
  /// **'Delay {value} s'**
  String player_delay(String value);

  /// No description provided for @player_decreaseSubtitleDelay.
  ///
  /// In en, this message translates to:
  /// **'Decrease subtitle delay'**
  String get player_decreaseSubtitleDelay;

  /// No description provided for @player_decreaseAudioDelay.
  ///
  /// In en, this message translates to:
  /// **'Decrease audio delay'**
  String get player_decreaseAudioDelay;

  /// No description provided for @player_increaseSubtitleDelay.
  ///
  /// In en, this message translates to:
  /// **'Increase subtitle delay'**
  String get player_increaseSubtitleDelay;

  /// No description provided for @player_increaseAudioDelay.
  ///
  /// In en, this message translates to:
  /// **'Increase audio delay'**
  String get player_increaseAudioDelay;

  /// No description provided for @player_info.
  ///
  /// In en, this message translates to:
  /// **'Info'**
  String get player_info;

  /// No description provided for @player_bottom.
  ///
  /// In en, this message translates to:
  /// **'Bottom'**
  String get player_bottom;

  /// No description provided for @player_raised.
  ///
  /// In en, this message translates to:
  /// **'Raised'**
  String get player_raised;

  /// No description provided for @providers_signInTo.
  ///
  /// In en, this message translates to:
  /// **'Sign in to {name}'**
  String providers_signInTo(String name);

  /// No description provided for @providers_scanInstructions.
  ///
  /// In en, this message translates to:
  /// **'Scan with a phone signed in to {name}, or open {url} there.'**
  String providers_scanInstructions(String name, String url);

  /// No description provided for @settings_seconds.
  ///
  /// In en, this message translates to:
  /// **'{value} seconds'**
  String settings_seconds(String value);

  /// No description provided for @settings_nothingToClear.
  ///
  /// In en, this message translates to:
  /// **'Nothing to clear'**
  String get settings_nothingToClear;

  /// No description provided for @settings_freedMb.
  ///
  /// In en, this message translates to:
  /// **'Freed {value} MB'**
  String settings_freedMb(String value);

  /// No description provided for @settings_freedGb.
  ///
  /// In en, this message translates to:
  /// **'Freed {value} GB'**
  String settings_freedGb(String value);

  /// No description provided for @state_noMedia.
  ///
  /// In en, this message translates to:
  /// **'No media is available.'**
  String get state_noMedia;

  /// No description provided for @state_offlineWithPeriod.
  ///
  /// In en, this message translates to:
  /// **'You\'re offline.'**
  String get state_offlineWithPeriod;

  /// No description provided for @player_connecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get player_connecting;

  /// No description provided for @player_fetchingMetadata.
  ///
  /// In en, this message translates to:
  /// **'Fetching metadata…'**
  String get player_fetchingMetadata;

  /// No description provided for @player_preparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing video…'**
  String get player_preparing;

  /// No description provided for @player_bufferingProgress.
  ///
  /// In en, this message translates to:
  /// **'Buffering {percent}%{speed}'**
  String player_bufferingProgress(int percent, String speed);

  /// No description provided for @player_preparingProgress.
  ///
  /// In en, this message translates to:
  /// **'Preparing video… {progress}'**
  String player_preparingProgress(String progress);

  /// No description provided for @player_skipIntro.
  ///
  /// In en, this message translates to:
  /// **'Skip Intro'**
  String get player_skipIntro;

  /// No description provided for @player_skipCredits.
  ///
  /// In en, this message translates to:
  /// **'Skip Credits'**
  String get player_skipCredits;

  /// No description provided for @player_skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get player_skip;

  /// No description provided for @player_sourceTorrent_magnet.
  ///
  /// In en, this message translates to:
  /// **'Torrent magnet'**
  String get player_sourceTorrent_magnet;

  /// No description provided for @player_sourceTorrent_file.
  ///
  /// In en, this message translates to:
  /// **'Torrent file'**
  String get player_sourceTorrent_file;

  /// No description provided for @player_sourceLocal_file.
  ///
  /// In en, this message translates to:
  /// **'Local file'**
  String get player_sourceLocal_file;

  /// No description provided for @player_sourceWaiting_for_status.
  ///
  /// In en, this message translates to:
  /// **'Waiting for status'**
  String get player_sourceWaiting_for_status;

  /// No description provided for @player_sourceResolving_source.
  ///
  /// In en, this message translates to:
  /// **'Resolving source'**
  String get player_sourceResolving_source;

  /// No description provided for @player_sourceReading_metadata.
  ///
  /// In en, this message translates to:
  /// **'Reading metadata'**
  String get player_sourceReading_metadata;

  /// No description provided for @player_sourceBuffering.
  ///
  /// In en, this message translates to:
  /// **'Buffering'**
  String get player_sourceBuffering;

  /// No description provided for @player_sourceReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get player_sourceReady;

  /// No description provided for @player_sourceStalled.
  ///
  /// In en, this message translates to:
  /// **'Stalled'**
  String get player_sourceStalled;

  /// No description provided for @player_sourceFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get player_sourceFailed;

  /// No description provided for @player_sourceClosed.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get player_sourceClosed;

  /// No description provided for @diagnostics_Resolution.
  ///
  /// In en, this message translates to:
  /// **'Resolution'**
  String get diagnostics_Resolution;

  /// No description provided for @diagnostics_Status.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get diagnostics_Status;

  /// No description provided for @diagnostics_Log_folder.
  ///
  /// In en, this message translates to:
  /// **'Log folder'**
  String get diagnostics_Log_folder;

  /// No description provided for @diagnostics_Hardware_decoding.
  ///
  /// In en, this message translates to:
  /// **'Hardware decoding'**
  String get diagnostics_Hardware_decoding;

  /// No description provided for @diagnostics_Decoders.
  ///
  /// In en, this message translates to:
  /// **'Decoders'**
  String get diagnostics_Decoders;

  /// No description provided for @diagnostics_HDR_output.
  ///
  /// In en, this message translates to:
  /// **'HDR output'**
  String get diagnostics_HDR_output;

  /// No description provided for @diagnostics_HDR_formats.
  ///
  /// In en, this message translates to:
  /// **'HDR formats'**
  String get diagnostics_HDR_formats;

  /// No description provided for @diagnostics_Display_mode_switching.
  ///
  /// In en, this message translates to:
  /// **'Display mode switching'**
  String get diagnostics_Display_mode_switching;

  /// No description provided for @diagnostics_Audio_passthrough.
  ///
  /// In en, this message translates to:
  /// **'Audio passthrough'**
  String get diagnostics_Audio_passthrough;

  /// No description provided for @diagnostics_Passthrough_formats.
  ///
  /// In en, this message translates to:
  /// **'Passthrough formats'**
  String get diagnostics_Passthrough_formats;

  /// No description provided for @diagnostics_Decoder_fallback.
  ///
  /// In en, this message translates to:
  /// **'Decoder fallback'**
  String get diagnostics_Decoder_fallback;

  /// No description provided for @diagnostics_Video_codec.
  ///
  /// In en, this message translates to:
  /// **'Video codec'**
  String get diagnostics_Video_codec;

  /// No description provided for @diagnostics_Decoder.
  ///
  /// In en, this message translates to:
  /// **'Decoder'**
  String get diagnostics_Decoder;

  /// No description provided for @diagnostics_Pixel_format.
  ///
  /// In en, this message translates to:
  /// **'Pixel format'**
  String get diagnostics_Pixel_format;

  /// No description provided for @diagnostics_Color_matrix.
  ///
  /// In en, this message translates to:
  /// **'Color matrix'**
  String get diagnostics_Color_matrix;

  /// No description provided for @diagnostics_Transfer_function.
  ///
  /// In en, this message translates to:
  /// **'Transfer function'**
  String get diagnostics_Transfer_function;

  /// No description provided for @diagnostics_Color_primaries.
  ///
  /// In en, this message translates to:
  /// **'Color primaries'**
  String get diagnostics_Color_primaries;

  /// No description provided for @diagnostics_HDR_signal_peak.
  ///
  /// In en, this message translates to:
  /// **'HDR signal peak'**
  String get diagnostics_HDR_signal_peak;

  /// No description provided for @diagnostics_HDR_max_CLL.
  ///
  /// In en, this message translates to:
  /// **'HDR max CLL'**
  String get diagnostics_HDR_max_CLL;

  /// No description provided for @diagnostics_HDR_max_FALL.
  ///
  /// In en, this message translates to:
  /// **'HDR max FALL'**
  String get diagnostics_HDR_max_FALL;

  /// No description provided for @diagnostics_Audio_codec.
  ///
  /// In en, this message translates to:
  /// **'Audio codec'**
  String get diagnostics_Audio_codec;

  /// No description provided for @diagnostics_Audio_format.
  ///
  /// In en, this message translates to:
  /// **'Audio format'**
  String get diagnostics_Audio_format;

  /// No description provided for @diagnostics_Audio_output.
  ///
  /// In en, this message translates to:
  /// **'Audio output'**
  String get diagnostics_Audio_output;

  /// No description provided for @diagnostics_Audio_output_format.
  ///
  /// In en, this message translates to:
  /// **'Audio output format'**
  String get diagnostics_Audio_output_format;

  /// No description provided for @diagnostics_Playback.
  ///
  /// In en, this message translates to:
  /// **'Playback'**
  String get diagnostics_Playback;

  /// No description provided for @diagnostics_Position.
  ///
  /// In en, this message translates to:
  /// **'Position'**
  String get diagnostics_Position;

  /// No description provided for @diagnostics_Duration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get diagnostics_Duration;

  /// No description provided for @diagnostics_Paused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get diagnostics_Paused;

  /// No description provided for @diagnostics_Volume.
  ///
  /// In en, this message translates to:
  /// **'Volume'**
  String get diagnostics_Volume;

  /// No description provided for @diagnostics_Video_width.
  ///
  /// In en, this message translates to:
  /// **'Video width'**
  String get diagnostics_Video_width;

  /// No description provided for @diagnostics_Video_height.
  ///
  /// In en, this message translates to:
  /// **'Video height'**
  String get diagnostics_Video_height;

  /// No description provided for @diagnostics_supported.
  ///
  /// In en, this message translates to:
  /// **'Supported'**
  String get diagnostics_supported;

  /// No description provided for @diagnostics_unsupported.
  ///
  /// In en, this message translates to:
  /// **'Not supported'**
  String get diagnostics_unsupported;

  /// No description provided for @diagnostics_copy.
  ///
  /// In en, this message translates to:
  /// **'Copy diagnostics'**
  String get diagnostics_copy;

  /// No description provided for @diagnostics_copied.
  ///
  /// In en, this message translates to:
  /// **'Diagnostics copied'**
  String get diagnostics_copied;

  /// No description provided for @diagnostics_deviceCapabilities.
  ///
  /// In en, this message translates to:
  /// **'Device capabilities'**
  String get diagnostics_deviceCapabilities;

  /// No description provided for @player_sourceStatus.
  ///
  /// In en, this message translates to:
  /// **'{state} · {speed} B/s · {connections} connections · {ranges} available ranges'**
  String player_sourceStatus(
    String state,
    String speed,
    int connections,
    int ranges,
  );

  /// No description provided for @player_stats_Source.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get player_stats_Source;

  /// No description provided for @player_stats_Provider.
  ///
  /// In en, this message translates to:
  /// **'Provider'**
  String get player_stats_Provider;

  /// No description provided for @player_stats_Host.
  ///
  /// In en, this message translates to:
  /// **'Host'**
  String get player_stats_Host;

  /// No description provided for @player_stats_Protocol.
  ///
  /// In en, this message translates to:
  /// **'Protocol'**
  String get player_stats_Protocol;

  /// No description provided for @player_stats_TLS.
  ///
  /// In en, this message translates to:
  /// **'TLS'**
  String get player_stats_TLS;

  /// No description provided for @player_stats_Connections.
  ///
  /// In en, this message translates to:
  /// **'Connections'**
  String get player_stats_Connections;

  /// No description provided for @player_stats_Network.
  ///
  /// In en, this message translates to:
  /// **'Network'**
  String get player_stats_Network;

  /// No description provided for @player_stats_Speed.
  ///
  /// In en, this message translates to:
  /// **'Speed'**
  String get player_stats_Speed;

  /// No description provided for @player_stats_Speed_down.
  ///
  /// In en, this message translates to:
  /// **'Speed down'**
  String get player_stats_Speed_down;

  /// No description provided for @player_stats_Speed_up.
  ///
  /// In en, this message translates to:
  /// **'Speed up'**
  String get player_stats_Speed_up;

  /// No description provided for @player_stats_Pieces.
  ///
  /// In en, this message translates to:
  /// **'Pieces'**
  String get player_stats_Pieces;

  /// No description provided for @player_stats_Piece_size.
  ///
  /// In en, this message translates to:
  /// **'Piece size'**
  String get player_stats_Piece_size;

  /// No description provided for @player_stats_Swarm_tracker_.
  ///
  /// In en, this message translates to:
  /// **'Swarm (tracker)'**
  String get player_stats_Swarm_tracker_;

  /// No description provided for @player_stats_Availability.
  ///
  /// In en, this message translates to:
  /// **'Availability'**
  String get player_stats_Availability;

  /// No description provided for @player_stats_Info_hash.
  ///
  /// In en, this message translates to:
  /// **'Info-hash'**
  String get player_stats_Info_hash;

  /// No description provided for @player_stats_Time_left.
  ///
  /// In en, this message translates to:
  /// **'Time left'**
  String get player_stats_Time_left;

  /// No description provided for @player_stats_Buffer.
  ///
  /// In en, this message translates to:
  /// **'Buffer'**
  String get player_stats_Buffer;

  /// No description provided for @player_stats_Buffered_ahead.
  ///
  /// In en, this message translates to:
  /// **'Buffered ahead'**
  String get player_stats_Buffered_ahead;

  /// No description provided for @player_stats_Cache_in_memory.
  ///
  /// In en, this message translates to:
  /// **'Cache in memory'**
  String get player_stats_Cache_in_memory;

  /// No description provided for @player_stats_Cache_read_speed.
  ///
  /// In en, this message translates to:
  /// **'Cache read speed'**
  String get player_stats_Cache_read_speed;

  /// No description provided for @player_stats_Video.
  ///
  /// In en, this message translates to:
  /// **'Video'**
  String get player_stats_Video;

  /// No description provided for @player_stats_Codec.
  ///
  /// In en, this message translates to:
  /// **'Codec'**
  String get player_stats_Codec;

  /// No description provided for @player_stats_Resolution.
  ///
  /// In en, this message translates to:
  /// **'Resolution'**
  String get player_stats_Resolution;

  /// No description provided for @player_stats_Display_size.
  ///
  /// In en, this message translates to:
  /// **'Display size'**
  String get player_stats_Display_size;

  /// No description provided for @player_stats_Frame_rate.
  ///
  /// In en, this message translates to:
  /// **'Frame rate'**
  String get player_stats_Frame_rate;

  /// No description provided for @player_stats_Bitrate.
  ///
  /// In en, this message translates to:
  /// **'Bitrate'**
  String get player_stats_Bitrate;

  /// No description provided for @player_stats_Pixel_format.
  ///
  /// In en, this message translates to:
  /// **'Pixel format'**
  String get player_stats_Pixel_format;

  /// No description provided for @player_stats_Colour.
  ///
  /// In en, this message translates to:
  /// **'Colour'**
  String get player_stats_Colour;

  /// No description provided for @player_stats_Hardware_decoding.
  ///
  /// In en, this message translates to:
  /// **'Hardware decoding'**
  String get player_stats_Hardware_decoding;

  /// No description provided for @player_stats_Dropped_frames.
  ///
  /// In en, this message translates to:
  /// **'Dropped frames'**
  String get player_stats_Dropped_frames;

  /// No description provided for @player_stats_A_V_sync.
  ///
  /// In en, this message translates to:
  /// **'A/V sync'**
  String get player_stats_A_V_sync;

  /// No description provided for @player_stats_Audio.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get player_stats_Audio;

  /// No description provided for @player_stats_Channels.
  ///
  /// In en, this message translates to:
  /// **'Channels'**
  String get player_stats_Channels;

  /// No description provided for @player_stats_Sample_rate.
  ///
  /// In en, this message translates to:
  /// **'Sample rate'**
  String get player_stats_Sample_rate;

  /// No description provided for @player_stats_Output.
  ///
  /// In en, this message translates to:
  /// **'Output'**
  String get player_stats_Output;

  /// No description provided for @player_stats_Subtitles.
  ///
  /// In en, this message translates to:
  /// **'Subtitles'**
  String get player_stats_Subtitles;

  /// No description provided for @player_stats_Track.
  ///
  /// In en, this message translates to:
  /// **'Track'**
  String get player_stats_Track;

  /// No description provided for @player_stats_Player.
  ///
  /// In en, this message translates to:
  /// **'Player'**
  String get player_stats_Player;

  /// No description provided for @player_stats_Container.
  ///
  /// In en, this message translates to:
  /// **'Container'**
  String get player_stats_Container;

  /// No description provided for @player_stats_Position.
  ///
  /// In en, this message translates to:
  /// **'Position'**
  String get player_stats_Position;

  /// No description provided for @player_stats_Engine.
  ///
  /// In en, this message translates to:
  /// **'Engine'**
  String get player_stats_Engine;

  /// No description provided for @player_stats_Downloaded.
  ///
  /// In en, this message translates to:
  /// **'Downloaded'**
  String get player_stats_Downloaded;

  /// No description provided for @player_stats_Progress.
  ///
  /// In en, this message translates to:
  /// **'Progress'**
  String get player_stats_Progress;

  /// No description provided for @player_statsTitle.
  ///
  /// In en, this message translates to:
  /// **'Stats for nerds'**
  String get player_statsTitle;

  /// No description provided for @player_stats_Download_speed.
  ///
  /// In en, this message translates to:
  /// **'Download speed'**
  String get player_stats_Download_speed;

  /// No description provided for @player_stats_Upload_speed.
  ///
  /// In en, this message translates to:
  /// **'Upload speed'**
  String get player_stats_Upload_speed;

  /// No description provided for @player_stats_Seeds_connected.
  ///
  /// In en, this message translates to:
  /// **'Seeds connected'**
  String get player_stats_Seeds_connected;

  /// No description provided for @player_stats_Peers_connected.
  ///
  /// In en, this message translates to:
  /// **'Peers connected'**
  String get player_stats_Peers_connected;

  /// No description provided for @player_stats_Swarm.
  ///
  /// In en, this message translates to:
  /// **'Swarm'**
  String get player_stats_Swarm;

  /// No description provided for @player_audioOutput.
  ///
  /// In en, this message translates to:
  /// **'Audio output: {value}'**
  String player_audioOutput(String value);

  /// No description provided for @player_castTab.
  ///
  /// In en, this message translates to:
  /// **'cast'**
  String get player_castTab;

  /// No description provided for @player_triviaTab.
  ///
  /// In en, this message translates to:
  /// **'trivia'**
  String get player_triviaTab;

  /// No description provided for @player_filmographyTab.
  ///
  /// In en, this message translates to:
  /// **'filmography'**
  String get player_filmographyTab;

  /// No description provided for @player_subtitleUriError.
  ///
  /// In en, this message translates to:
  /// **'Enter an HTTP, HTTPS or file subtitle URI.'**
  String get player_subtitleUriError;

  /// No description provided for @settings_numericChoice.
  ///
  /// In en, this message translates to:
  /// **'{value}'**
  String settings_numericChoice(String value);

  /// No description provided for @settings_valueUnit.
  ///
  /// In en, this message translates to:
  /// **'{value} {unit}'**
  String settings_valueUnit(String value, String unit);

  /// No description provided for @settings_unit_connections.
  ///
  /// In en, this message translates to:
  /// **'connections'**
  String get settings_unit_connections;

  /// No description provided for @settings_unit_retries.
  ///
  /// In en, this message translates to:
  /// **'retries'**
  String get settings_unit_retries;

  /// No description provided for @settings_unit_peers.
  ///
  /// In en, this message translates to:
  /// **'peers'**
  String get settings_unit_peers;

  /// No description provided for @settings_unit_threads.
  ///
  /// In en, this message translates to:
  /// **'threads'**
  String get settings_unit_threads;

  /// No description provided for @settings_unit_seconds.
  ///
  /// In en, this message translates to:
  /// **'s'**
  String get settings_unit_seconds;

  /// No description provided for @settings_unit_px.
  ///
  /// In en, this message translates to:
  /// **'px'**
  String get settings_unit_px;

  /// No description provided for @settings_unit_dB.
  ///
  /// In en, this message translates to:
  /// **'dB'**
  String get settings_unit_dB;

  /// No description provided for @settings_unit_MB.
  ///
  /// In en, this message translates to:
  /// **'MB'**
  String get settings_unit_MB;

  /// No description provided for @settings_unit_KBps.
  ///
  /// In en, this message translates to:
  /// **'KB/s'**
  String get settings_unit_KBps;

  /// No description provided for @settings_unit_percent.
  ///
  /// In en, this message translates to:
  /// **'%'**
  String get settings_unit_percent;

  /// No description provided for @settings_working.
  ///
  /// In en, this message translates to:
  /// **'Working...'**
  String get settings_working;

  /// No description provided for @settings_failed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get settings_failed;

  /// No description provided for @settings_invalidTrackRule.
  ///
  /// In en, this message translates to:
  /// **'Invalid rule \"{token}\". Use lang:<code>, original, atmos, lossless, channels or default.'**
  String settings_invalidTrackRule(String token);

  /// No description provided for @player_playbackPosition.
  ///
  /// In en, this message translates to:
  /// **'Playback position'**
  String get player_playbackPosition;

  /// No description provided for @player_chapterEyebrow.
  ///
  /// In en, this message translates to:
  /// **'CHAPTER {number} · {name}'**
  String player_chapterEyebrow(int number, String name);

  /// No description provided for @player_chapter.
  ///
  /// In en, this message translates to:
  /// **'Chapter {number}'**
  String player_chapter(int number);

  /// No description provided for @player_insights.
  ///
  /// In en, this message translates to:
  /// **'Insights'**
  String get player_insights;

  /// No description provided for @player_contentFilter.
  ///
  /// In en, this message translates to:
  /// **'Content Filter'**
  String get player_contentFilter;

  /// No description provided for @player_filterOn.
  ///
  /// In en, this message translates to:
  /// **'{label} (on)'**
  String player_filterOn(String label);

  /// No description provided for @player_action_subtitles.
  ///
  /// In en, this message translates to:
  /// **'subtitles'**
  String get player_action_subtitles;

  /// No description provided for @player_action_audio.
  ///
  /// In en, this message translates to:
  /// **'audio'**
  String get player_action_audio;

  /// No description provided for @player_action_info.
  ///
  /// In en, this message translates to:
  /// **'info'**
  String get player_action_info;

  /// No description provided for @player_action_upNext.
  ///
  /// In en, this message translates to:
  /// **'upNext'**
  String get player_action_upNext;

  /// No description provided for @player_failure_openFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to open the media'**
  String get player_failure_openFailed;

  /// No description provided for @player_failure_decodeFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to decode the media'**
  String get player_failure_decodeFailed;

  /// No description provided for @player_failure_engineCrashed.
  ///
  /// In en, this message translates to:
  /// **'The playback engine crashed'**
  String get player_failure_engineCrashed;

  /// No description provided for @player_failure_sourceUnreachable.
  ///
  /// In en, this message translates to:
  /// **'The media source became unreachable'**
  String get player_failure_sourceUnreachable;

  /// No description provided for @player_failure_unsupportedCodec.
  ///
  /// In en, this message translates to:
  /// **'Unsupported codec: {detail}'**
  String player_failure_unsupportedCodec(String detail);

  /// No description provided for @player_failure_trackSelectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to select playback track: {detail}'**
  String player_failure_trackSelectionFailed(String detail);

  /// No description provided for @player_failure_subtitleLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load external subtitle: {detail}'**
  String player_failure_subtitleLoadFailed(String detail);

  /// No description provided for @player_unableToSelectTrack.
  ///
  /// In en, this message translates to:
  /// **'Unable to select track: {error}'**
  String player_unableToSelectTrack(String error);

  /// No description provided for @settings_adjust.
  ///
  /// In en, this message translates to:
  /// **'{action} {title}'**
  String settings_adjust(String action, String title);

  /// No description provided for @player_transportHttpNoRangeSupport.
  ///
  /// In en, this message translates to:
  /// **'This server does not support ranged reads.'**
  String get player_transportHttpNoRangeSupport;

  /// No description provided for @player_transportHttpValidatorChanged.
  ///
  /// In en, this message translates to:
  /// **'The HTTP file changed while it was loading.'**
  String get player_transportHttpValidatorChanged;

  /// No description provided for @player_transportHttpUnreachable.
  ///
  /// In en, this message translates to:
  /// **'The HTTP source cannot be reached right now.'**
  String get player_transportHttpUnreachable;

  /// No description provided for @player_transportRangeUnsatisfiable.
  ///
  /// In en, this message translates to:
  /// **'The requested byte range is unavailable.'**
  String get player_transportRangeUnsatisfiable;

  /// No description provided for @player_transportTorrentNoMetadata.
  ///
  /// In en, this message translates to:
  /// **'Torrent metadata has not arrived.'**
  String get player_transportTorrentNoMetadata;

  /// No description provided for @player_transportTorrentNoPeers.
  ///
  /// In en, this message translates to:
  /// **'This torrent has no available peers.'**
  String get player_transportTorrentNoPeers;

  /// No description provided for @player_transportTorrentStalled.
  ///
  /// In en, this message translates to:
  /// **'The torrent stopped making progress.'**
  String get player_transportTorrentStalled;

  /// No description provided for @player_transportTorrentFileError.
  ///
  /// In en, this message translates to:
  /// **'The torrent could not access its files.'**
  String get player_transportTorrentFileError;

  /// No description provided for @player_transportTorrentFileNotFound.
  ///
  /// In en, this message translates to:
  /// **'The requested torrent file was not found.'**
  String get player_transportTorrentFileNotFound;

  /// No description provided for @player_transportEngineUnavailable.
  ///
  /// In en, this message translates to:
  /// **'The native transport engine is unavailable.'**
  String get player_transportEngineUnavailable;

  /// No description provided for @player_transportUnknownTransport.
  ///
  /// In en, this message translates to:
  /// **'The source reported an unknown transport failure.'**
  String get player_transportUnknownTransport;

  /// No description provided for @settings_choiceMbps.
  ///
  /// In en, this message translates to:
  /// **'{value} Mbps'**
  String settings_choiceMbps(String value);

  /// No description provided for @settings_choiceGB.
  ///
  /// In en, this message translates to:
  /// **'{value} GB'**
  String settings_choiceGB(String value);

  /// No description provided for @player_playbackRate.
  ///
  /// In en, this message translates to:
  /// **'{value}×'**
  String player_playbackRate(String value);

  /// No description provided for @providers_codeExpired.
  ///
  /// In en, this message translates to:
  /// **'The code expired. Make a new one.'**
  String get providers_codeExpired;

  /// No description provided for @common_enabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get common_enabled;

  /// No description provided for @common_disabled.
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get common_disabled;

  /// No description provided for @player_optionFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to apply option: {error}'**
  String player_optionFailed(String error);

  /// No description provided for @player_subtitleNotAdded.
  ///
  /// In en, this message translates to:
  /// **'Subtitle was not added.'**
  String get player_subtitleNotAdded;
}

class _AppStringsDelegate extends LocalizationsDelegate<AppStrings> {
  const _AppStringsDelegate();

  @override
  Future<AppStrings> load(Locale locale) {
    return SynchronousFuture<AppStrings>(lookupAppStrings(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'fa'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppStringsDelegate old) => false;
}

AppStrings lookupAppStrings(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppStringsEn();
    case 'fa':
      return AppStringsFa();
  }

  throw FlutterError(
    'AppStrings.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
