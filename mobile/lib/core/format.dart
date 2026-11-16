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
