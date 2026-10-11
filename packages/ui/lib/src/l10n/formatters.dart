import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:shamsi_date/shamsi_date.dart';

import 'app_text.dart';

String _tag(BuildContext context) => isFarsi(context) ? 'fa' : 'en';

String _int(BuildContext context, int n) =>
    NumberFormat.decimalPattern(_tag(context)).format(n);

/// 1250 -> "1,250" / «۱٬۲۵۰».
String formatCount(BuildContext context, int n) => _int(context, n);

/// "1h 42m" / «۱ ساعت و ۴۲ دقیقه»; a zero part is left out.
String formatDuration(
  BuildContext context,
  Duration d, {
  bool includeZeroMinutes = false,
}) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60);
  if (isFarsi(context)) {
    final h = '${_int(context, hours)} ساعت';
    final m = '${_int(context, minutes)} دقیقه';
    if (hours == 0) return m;
    return minutes == 0 ? h : '$h و $m';
  }
  if (hours == 0) return '${minutes}m';
  return minutes == 0 && !includeZeroMinutes
      ? '${hours}h'
      : '${hours}h ${minutes}m';
}

/// 1503238553 -> "1.4 GB" / «۱٫۴ گیگابایت» (binary steps, one decimal).
String formatFileSize(
  BuildContext context,
  int bytes, {
  bool decimalBytes = false,
}) {
  const en = ['B', 'KB', 'MB', 'GB', 'TB'];
  const fa = ['بایت', 'کیلوبایت', 'مگابایت', 'گیگابایت', 'ترابایت'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < en.length - 1) {
    value /= 1024;
    unit++;
  }
  final number = unit == 0 && !decimalBytes
      ? _int(context, bytes)
      : NumberFormat('0.0', _tag(context)).format(value);
  return '$number ${isFarsi(context) ? fa[unit] : en[unit]}';
}

/// 0.42 -> "42%" / «۴۲٪».
String formatPercent(BuildContext context, double fraction) =>
    '${NumberFormat('0', _tag(context)).format((fraction * 100).round())}'
    '${isFarsi(context) ? '٪' : '%'}';

/// Gregorian year without a group separator: "2024" / «۲۰۲۴».
String formatYear(BuildContext context, int year) =>
    NumberFormat('0', _tag(context)).format(year);

/// "Sep 20, 2026" / Jalali «۲۹ شهریور ۱۴۰۵».
String formatDate(BuildContext context, DateTime date) {
  if (!isFarsi(context)) return DateFormat.yMMMd('en').format(date);
  final j = Jalali.fromDateTime(date);
  final f = NumberFormat('0', 'fa');
  return '${f.format(j.day)} ${j.formatter.mN} ${f.format(j.year)}';
}

/// "2h ago" / «۲ ساعت پیش»; a day or more back reads "Yesterday" / «دیروز», then
/// days, then the full date after a week. [now] exists for tests.
String formatRelative(BuildContext context, DateTime time, {DateTime? now}) {
  final diff = (now ?? DateTime.now()).difference(time);
  final fa = isFarsi(context);
  String ago(int n, String en, String faUnit) =>
      fa ? '${_int(context, n)} $faUnit پیش' : '$n$en ago';
  if (diff.inMinutes < 1) return fa ? 'همین حالا' : 'Just now';
  if (diff.inHours < 1) return ago(diff.inMinutes, 'm', 'دقیقه');
  if (diff.inDays < 1) return ago(diff.inHours, 'h', 'ساعت');
  if (diff.inDays == 1) return fa ? 'دیروز' : 'Yesterday';
  if (diff.inDays < 7) return ago(diff.inDays, 'd', 'روز');
  return formatDate(context, time);
}
