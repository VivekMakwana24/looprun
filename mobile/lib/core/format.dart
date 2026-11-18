String formatDistance(double meters) {
  if (meters < 1000) return '${meters.round()} m';
  return '${(meters / 1000).toStringAsFixed(2)} km';
}

String _two(int v) => v.toString().padLeft(2, '0');

String formatDuration(int ms) {
  final total = ms ~/ 1000;
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  if (h > 0) return '$h:${_two(m)}:${_two(s)}';
  return '${_two(m)}:${_two(s)}';
}

/// Kilometres with two decimals and no unit ("3.42"); the unit is drawn separately.
String formatKm(double meters) => (meters / 1000).toStringAsFixed(2);

/// Placeholder for a value the app does not have.
const String noValue = '--';

/// Pace as "m:ss" per kilometre, or [noValue] while it cannot be worked out honestly
/// (under 50 m, no time, or slower than 60 min/km, which is standing around).
String formatPace(int elapsedMs, double meters) {
  if (meters < 50 || elapsedMs <= 0) return noValue;
  final secPerKm = (elapsedMs / 1000) / (meters / 1000);
  if (!secPerKm.isFinite || secPerKm >= 3600) return noValue;
  final total = secPerKm.round();
  return '${total ~/ 60}:${_two(total % 60)}';
}

/// "2026-W47" (the server's ISO week) -> "WEEK 47"; null when the text is not in that form.
String? formatWeekLabel(String isoWeek) {
  final m = RegExp(r'^\d{4}-W(\d{1,2})$').firstMatch(isoWeek.trim());
  if (m == null) return null;
  return 'WEEK ${int.parse(m.group(1)!)}';
}

const List<String> _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const List<String> _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "Mon 16 Nov, 06:42" in the given (local) time.
String formatRunDate(DateTime t) {
  return '${_weekdays[t.weekday - 1]} ${t.day} ${_months[t.month - 1]}, ${_two(t.hour)}:${_two(t.minute)}';
}

/// "16 Nov" in the given (local) time.
String formatDayMonth(DateTime t) => '${t.day} ${_months[t.month - 1]}';

/// Pace in seconds per kilometre as "m:ss", or [noValue] when the server sent none (under 100 m, or still
/// processing) or when it is slower than 60 min/km.
String formatPaceSeconds(double? secPerKm) {
  if (secPerKm == null || !secPerKm.isFinite || secPerKm <= 0 || secPerKm >= 3600) return noValue;
  final total = secPerKm.round();
  return '${total ~/ 60}:${_two(total % 60)}';
}

/// Moving time in whole seconds as "m:ss" or "h:mm:ss"; [noValue] when unknown.
String formatMovingSeconds(int? seconds) => seconds == null ? noValue : formatDuration(seconds * 1000);

/// "just now", "5 min ago", "3 h ago", "2 d ago", else "16 Nov". [now] is a parameter for tests.
String formatAgo(DateTime then, {DateTime? now}) {
  final diff = (now ?? DateTime.now()).difference(then);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  if (diff.inDays < 7) return '${diff.inDays} d ago';
  return formatDayMonth(then);
}

/// Up to two capital letters from a display name ("Anna Lee" -> "AL", "Runner-1a2b" -> "R1"). "?" when empty.
String initialsOf(String name) {
  final words = name.trim().split(RegExp(r'[\s\-_]+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return '?';
  String first(String w) => String.fromCharCode(w.runes.first).toUpperCase();
  if (words.length == 1) return first(words[0]);
  return first(words[0]) + first(words[1]);
}
