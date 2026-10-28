/// Civil-date arithmetic for the Daily Puzzle (pure Dart).
library;

/// A calendar date without time or time zone.
class CivilDate implements Comparable<CivilDate> {
  const CivilDate(this.year, this.month, this.day);

  /// The local calendar date of [local] (its year/month/day fields).
  factory CivilDate.fromDateTime(DateTime local) =>
      CivilDate(local.year, local.month, local.day);

  /// Parses `YYYY-MM-DD`; returns null for anything else or impossible dates.
  static CivilDate? tryParse(String s) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
    if (m == null) return null;
    final d = CivilDate(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
    final check = DateTime.utc(d.year, d.month, d.day);
    if (check.year != d.year || check.month != d.month || check.day != d.day) {
      return null;
    }
    return d;
  }

  final int year;
  final int month;
  final int day;

  /// Days since 1970-01-01, computed on UTC midnights so DST never matters.
  int get epochDay =>
      DateTime.utc(year, month, day).millisecondsSinceEpoch ~/ 86400000;

  CivilDate addDays(int n) =>
      CivilDate.fromDateTime(DateTime.utc(year, month, day + n));

  @override
  int compareTo(CivilDate other) => epochDay.compareTo(other.epochDay);

  @override
  bool operator ==(Object other) =>
      other is CivilDate && other.epochDay == epochDay;

  @override
  int get hashCode => epochDay;

  @override
  String toString() =>
      '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';
}

const CivilDate dailyEpoch = CivilDate(2026, 1, 1);

/// Number of civil days since 2026-01-01 (negative before it).
int dailyDayIndex(CivilDate date) => date.epochDay - dailyEpoch.epochDay;

/// Index into the daily pool; the pool repeats every [poolSize] days.
int dailyPoolIndex(CivilDate date, int poolSize) {
  final i = dailyDayIndex(date) % poolSize;
  return i < 0 ? i + poolSize : i;
}

/// Consecutive finalized daily wins ending today, or ending yesterday when
/// today has no finalized result yet. A finalized loss today yields zero.
int currentDailyStreak(Map<String, bool> outcomes, CivilDate today) {
  final todayResult = outcomes[today.toString()];
  if (todayResult == false) return 0;
  var day = todayResult == true ? today : today.addDays(-1);
  var streak = 0;
  while (outcomes[day.toString()] == true) {
    streak++;
    day = day.addDays(-1);
  }
  return streak;
}
