import 'package:flutter_test/flutter_test.dart';
import 'package:lexistack/core/daily.dart';
import 'package:lexistack/core/prng.dart';
import 'package:lexistack/core/scoring.dart';

void main() {
  group('prng', () {
    test('mul32 matches exact 32-bit multiplication', () {
      expect(mul32(0xFFFFFFFF, 0xFFFFFFFF), 1);
      expect(mul32(0x6D2B79F5, 3), (0x6D2B79F5 * 3) % 4294967296);
      expect(
        mul32(123456789, 987654321),
        (BigInt.from(123456789) * BigInt.from(987654321) % BigInt.two.pow(32))
            .toInt(),
      );
    });

    test('mulberry32 reference sequence (same on VM and web)', () {
      // Reference values from the canonical JavaScript Mulberry32 with seed 1.
      final r = Prng(1);
      expect([for (var i = 0; i < 3; i++) r.nextUint32()], kMulberrySeed1);
    });

    test('fnv1a32 reference values', () {
      expect(fnv1a32(''), 0x811C9DC5);
      expect(fnv1a32('a'), 0xE40C292C);
      expect(fnv1a32('foobar'), 0xBF9CF968);
    });
  });

  group('daily dates', () {
    test('day index counts civil days since 2026-01-01', () {
      expect(dailyDayIndex(const CivilDate(2026, 1, 1)), 0);
      expect(dailyDayIndex(const CivilDate(2026, 10, 28)), 300);
      expect(dailyDayIndex(const CivilDate(2025, 12, 31)), -1);
      expect(dailyPoolIndex(const CivilDate(2025, 12, 31), 8), 7);
      expect(dailyPoolIndex(const CivilDate(2026, 1, 9), 8), 0);
    });

    test('DST transitions do not skip or repeat days', () {
      // Europe and the US change clocks around these dates.
      for (final start in [
        const CivilDate(2026, 3, 7),
        const CivilDate(2026, 3, 28),
        const CivilDate(2026, 10, 24),
        const CivilDate(2026, 10, 31),
      ]) {
        for (var i = 0; i < 4; i++) {
          final d = start.addDays(i);
          expect(dailyDayIndex(d), dailyDayIndex(start) + i);
          final local = DateTime(d.year, d.month, d.day, 23, 59);
          expect(CivilDate.fromDateTime(local), d);
        }
      }
    });

    test('leap days', () {
      const feb28 = CivilDate(2028, 2, 28);
      expect(feb28.addDays(1).toString(), '2028-02-29');
      expect(feb28.addDays(2).toString(), '2028-03-01');
      expect(
        dailyDayIndex(const CivilDate(2028, 3, 1)) - dailyDayIndex(feb28),
        2,
      );
      expect(CivilDate.tryParse('2027-02-29'), isNull);
      expect(CivilDate.tryParse('2028-02-29'), const CivilDate(2028, 2, 29));
      expect(CivilDate.tryParse('28-10-2026'), isNull);
    });

    test('streaks', () {
      const today = CivilDate(2026, 10, 28);
      expect(currentDailyStreak({}, today), 0);
      final outcomes = {
        '2026-10-25': true,
        '2026-10-26': true,
        '2026-10-27': true,
      };
      expect(currentDailyStreak(outcomes, today), 3, reason: 'ends yesterday');
      expect(currentDailyStreak({...outcomes, '2026-10-28': true}, today), 4);
      expect(currentDailyStreak({...outcomes, '2026-10-28': false}, today), 0);
      expect(currentDailyStreak({...outcomes, '2026-10-26': false}, today), 1);
      expect(
        currentDailyStreak(outcomes, today.addDays(2)),
        0,
        reason: 'missed day breaks the streak',
      );
    });
  });

  group('share text', () {
    test('exact daily win format', () {
      final text = buildShareText(
        header: dailyShareHeader('2026-10-27'),
        won: true,
        mistakes: 2,
        groupsSolved: 4,
        rows: [
          [1, 1, 1, 2],
          [1, 2, 1, 2],
          [1, 1, 1, 1],
          [2, 2, 2, 2],
          [3, 3, 3, 3],
          [4, 4, 4, 4],
        ],
      );
      expect(
        text,
        'LexiStack · Daily 2026-10-27\n'
        '★★☆ · 2 mistakes\n'
        '🟨🟨🟨🟩\n'
        '🟨🟩🟨🟩\n'
        '🟨🟨🟨🟨\n'
        '🟩🟩🟩🟩\n'
        '🟦🟦🟦🟦\n'
        '🟪🟪🟪🟪',
      );
    });

    test('campaign loss format', () {
      final text = buildShareText(
        header: campaignShareHeader('Everyday Echoes', 3),
        won: false,
        mistakes: 4,
        groupsSolved: 1,
        rows: [
          [1, 1, 1, 1],
        ],
      );
      expect(
        text,
        'LexiStack · Everyday Echoes #3\n1/4 groups · 4 mistakes\n🟨🟨🟨🟨',
      );
    });
  });
}

/// First three Mulberry32 outputs for seed 1.
const kMulberrySeed1 = [2693262067, 11749833, 2265367787];
