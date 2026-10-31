import 'package:flutter/widgets.dart';

/// Farsi names of every TMDB movie and TV genre. The backend keeps English
/// (TMDB, matching, storage); only the label shown in Farsi mode is
/// translated here, keyed by TMDB id or by the English name.
const List<(int, String, String)> tmdbGenres = [
  (28, 'Action', 'اکشن'),
  (12, 'Adventure', 'ماجراجویی'),
  (16, 'Animation', 'انیمیشن'),
  (35, 'Comedy', 'کمدی'),
  (80, 'Crime', 'جنایی'),
  (99, 'Documentary', 'مستند'),
  (18, 'Drama', 'درام'),
  (10751, 'Family', 'خانوادگی'),
  (14, 'Fantasy', 'فانتزی'),
  (36, 'History', 'تاریخی'),
  (27, 'Horror', 'ترسناک'),
  (10402, 'Music', 'موسیقی'),
  (9648, 'Mystery', 'رازآلود'),
  (10749, 'Romance', 'عاشقانه'),
  (878, 'Science Fiction', 'علمی‌تخیلی'),
  (10770, 'TV Movie', 'فیلم تلویزیونی'),
  (53, 'Thriller', 'هیجان‌انگیز'),
  (10752, 'War', 'جنگی'),
  (37, 'Western', 'وسترن'),
  (10759, 'Action & Adventure', 'اکشن و ماجراجویی'),
  (10762, 'Kids', 'کودکان'),
  (10763, 'News', 'اخبار'),
  (10764, 'Reality', 'واقعی'),
  (10765, 'Sci-Fi & Fantasy', 'علمی‌تخیلی و فانتزی'),
  (10766, 'Soap', 'سریال روزانه'),
  (10767, 'Talk', 'گفت‌وگو'),
  (10768, 'War & Politics', 'جنگ و سیاست'),
];

/// The Farsi name for a TMDB genre [id] or English [name]; null when unknown.
String? genreNameFa({int? id, String? name}) {
  for (final (gid, en, fa) in tmdbGenres) {
    if (gid == id || (name != null && en.toLowerCase() == name.toLowerCase())) {
      return fa;
    }
  }
  return null;
}

/// The genre label to show: Farsi in Farsi mode, otherwise (or when the genre
/// is unknown) the English [name].
String genreLabel(BuildContext context, String name, {int? id}) =>
    Localizations.localeOf(context).languageCode == 'fa'
    ? genreNameFa(id: id, name: name) ?? name
    : name;
