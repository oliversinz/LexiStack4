import 'package:flutter_test/flutter_test.dart';
import 'package:lexistack/core/game.dart';
import 'package:lexistack/core/scoring.dart';

import '../support/fixtures.dart';

void main() {
  final level = oracleLevel();
  PuzzleGame fresh([int seed = 7]) => PuzzleGame.fresh(level, seed);
  void select(PuzzleGame g, List<String> words) {
    for (final id in tids(level, words)) {
      expect(g.toggle(id), isTrue, reason: 'select $id');
    }
  }

  group('rule oracle', () {
    test('game 1: exact match solves A', () {
      final g = fresh();
      expect(g.order, hasLength(16));
      select(g, ['JUPITER', 'MARS', 'SATURN', 'VENUS']);
      final r = g.submit();
      expect(r, isA<SubmitSolved>());
      expect((r as SubmitSolved).category.id, 'a');
      expect(r.victory, isFalse);
      expect(g.solved, ['a']);
      expect(g.order, hasLength(12));
      expect(g.lives, 4);
      expect(g.selection, isEmpty);
      expect(g.combo, 1);
    });

    test('game 2: one away, already guessed, standard mismatch', () {
      final g = fresh();
      select(g, ['MARS', 'VENUS', 'SATURN', 'MERCURY']);
      final r1 = g.submit();
      expect(r1, isA<SubmitMismatch>());
      expect((r1 as SubmitMismatch).isOneAway, isTrue);
      expect(g.lives, 3);
      expect(g.guesses, hasLength(1));
      expect(g.selection, hasLength(4), reason: 'selection retained');

      g.deselectAll();
      select(g, ['MERCURY', 'SATURN', 'VENUS', 'MARS']);
      expect(g.submit(), isA<SubmitAlreadyGuessed>());
      expect(g.lives, 3);
      expect(g.mistakes, 1);
      expect(g.guesses, hasLength(1));

      g.deselectAll();
      select(g, ['MARS', 'VENUS', 'MERCURY', 'GOLD']);
      final r3 = g.submit();
      expect(r3, isA<SubmitMismatch>());
      expect((r3 as SubmitMismatch).isOneAway, isFalse);
      expect(g.lives, 2);
      expect(g.solved, isEmpty, reason: 'A stays unsolved');
      expect(g.guesses.map((x) => x.correct), [false, false]);
    });
  });

  group('selection', () {
    test('fifth tile is ignored and deselect clears', () {
      final g = fresh();
      select(g, ['MARS', 'VENUS', 'SATURN', 'GOLD']);
      expect(g.toggle(tid(level, 'IRON')), isFalse);
      expect(g.selection, hasLength(4));
      expect(
        g.toggle(tid(level, 'GOLD')),
        isTrue,
        reason: 'tap again deselects',
      );
      expect(g.selection, hasLength(3));
      expect(g.deselectAll(), isTrue);
      expect(g.selection, isEmpty);
    });

    test('drag onto tile and tray add to selection additively', () {
      final g = fresh();
      expect(g.dragOnto(tid(level, 'MARS'), tid(level, 'VENUS')), isTrue);
      expect(g.selection, tids(level, ['MARS', 'VENUS']));
      expect(g.dropOnTray(tid(level, 'SATURN')), isTrue);
      expect(g.dragOnto(tid(level, 'MARS'), tid(level, 'JUPITER')), isTrue);
      expect(g.selection, tids(level, ['MARS', 'VENUS', 'SATURN', 'JUPITER']));
      expect(g.dropOnTray(tid(level, 'GOLD')), isFalse, reason: 'cap of four');
      expect(g.submit(), isA<SubmitSolved>());
    });

    test('solved tiles are not selectable', () {
      final g = fresh();
      select(g, ['MARS', 'VENUS', 'SATURN', 'JUPITER']);
      g.submit();
      expect(g.toggle(tid(level, 'MARS')), isFalse);
      expect(g.dropOnTray(tid(level, 'VENUS')), isFalse);
    });

    test('shuffle is free, keeps selection and is deterministic', () {
      final a = fresh(42);
      final b = fresh(42);
      expect(a.order, b.order);
      expect(fresh(43).order, isNot(a.order));
      select(a, ['MARS', 'GOLD']);
      final before = List.of(a.selection);
      a.shuffle();
      b.shuffle();
      expect(a.order, b.order);
      expect(a.selection, before);
      expect(a.lives, 4);
      expect(a.mistakes, 0);
      expect(a.order.toSet(), level.tiles.keys.toSet());
    });
  });

  group('submission', () {
    test('invalid submissions change nothing', () {
      final g = fresh();
      select(g, ['MARS', 'VENUS', 'SATURN']);
      expect(g.canSubmit, isFalse);
      expect(g.submit(), isA<SubmitRejected>());
      expect(g.lives, 4);
      expect(g.guesses, isEmpty);
    });

    test('combo resets on a mistake', () {
      final g = fresh();
      select(g, ['MARS', 'VENUS', 'SATURN', 'JUPITER']);
      g.submit();
      select(g, ['LEAD', 'GOLD', 'IRON', 'MERCURY']);
      g.submit();
      expect(g.combo, 2);
      select(g, ['ALPHA', 'BETA', 'KEY', 'MILE']);
      g.submit();
      expect(g.combo, 0);
      expect(g.bestCombo, 2);
    });

    test('exactly four groups win', () {
      final g = fresh();
      for (final c in level.categories) {
        for (final id in c.tileIds) {
          g.toggle(id);
        }
        final r = g.submit() as SubmitSolved;
        expect(r.victory, c.tier == 4);
      }
      expect(g.status, GameStatus.won);
      expect(g.stars, 3);
      expect(g.submit(), isA<SubmitRejected>());
      expect(g.shuffle(), isFalse);
    });

    test('zero lives enters pending loss; accept finalizes', () {
      final g = fresh();
      final wrong = [
        ['MARS', 'LEAD', 'ALPHA', 'KEY'],
        ['VENUS', 'GOLD', 'BETA', 'MILE'],
        ['SATURN', 'IRON', 'GAMMA', 'CORNER'],
        ['JUPITER', 'MERCURY', 'DELTA', 'SAND'],
      ];
      for (final w in wrong) {
        g.deselectAll();
        select(g, w);
        g.submit();
      }
      expect(g.lives, 0);
      expect(g.status, GameStatus.lostPendingDecision);
      expect(g.toggle(tid(level, 'MARS')), isFalse);
      expect(g.usePairMagnet(), isNull);
      expect(g.useCategoryPeek(), isNull);
      expect(g.acceptLoss(), isTrue);
      expect(g.status, GameStatus.lostFinal);
      expect(g.useExtraLife(), isFalse, reason: 'no rescue after reveal');
      expect(g.acceptLoss(), isFalse);
    });

    test(
      'extra life rescues a pending loss at one life; stars use mistakes',
      () {
        final g = fresh();
        final wrong = [
          ['MARS', 'LEAD', 'ALPHA', 'KEY'],
          ['VENUS', 'GOLD', 'BETA', 'MILE'],
          ['SATURN', 'IRON', 'GAMMA', 'CORNER'],
          ['JUPITER', 'MERCURY', 'DELTA', 'SAND'],
        ];
        for (final w in wrong) {
          g.deselectAll();
          select(g, w);
          g.submit();
        }
        expect(g.useExtraLife(), isTrue);
        expect(g.status, GameStatus.playing);
        expect(g.lives, 1);
        g.deselectAll();
        for (final c in level.categories) {
          for (final id in c.tileIds) {
            g.toggle(id);
          }
          g.submit();
        }
        expect(g.status, GameStatus.won);
        expect(g.mistakes, 4);
        expect(g.stars, 1);
      },
    );
  });

  group('boosters', () {
    test('pair magnet prefers the most recently selected tile group', () {
      final g = fresh();
      select(g, ['MARS', 'GOLD']);
      final pair = g.usePairMagnet()!;
      expect(pair, [tid(level, 'GOLD'), tid(level, 'MERCURY')]);
      expect(g.pairs.keys, ['b']);
      // Group b already has a pair: fall back to the lowest tier without one.
      final second = g.usePairMagnet()!;
      expect(second, tids(level, ['MARS', 'VENUS']));
    });

    test(
      'pair magnet without selection uses lowest tier; none left rejects',
      () {
        final g = fresh();
        expect(g.usePairMagnet(), tids(level, ['MARS', 'VENUS']));
        expect(g.usePairMagnet(), tids(level, ['MERCURY', 'LEAD']));
        expect(g.usePairMagnet(), tids(level, ['ALPHA', 'BETA']));
        expect(g.usePairMagnet(), tids(level, ['KEY', 'MILE']));
        expect(g.pairMagnetTarget(), isNull);
        expect(g.usePairMagnet(), isNull);
      },
    );

    test('category peek reveals lowest unsolved unpeeked title', () {
      final g = fresh();
      select(g, ['MARS', 'VENUS', 'SATURN', 'JUPITER']);
      g.submit();
      expect(g.useCategoryPeek()!.id, 'b');
      expect(g.useCategoryPeek()!.id, 'c');
      expect(g.useCategoryPeek()!.id, 'd');
      expect(g.useCategoryPeek(), isNull);
    });

    test('extra life rejected at four lives', () {
      final g = fresh();
      expect(g.canExtraLife, isFalse);
      expect(g.useExtraLife(), isFalse);
      select(g, ['MARS', 'LEAD', 'ALPHA', 'KEY']);
      g.submit();
      expect(g.useExtraLife(), isTrue);
      expect(g.lives, 4);
      expect(g.mistakes, 1);
      expect(g.stars, 2);
    });

    test('stars thresholds', () {
      expect(starsForMistakes(0), 3);
      expect(starsForMistakes(1), 2);
      expect(starsForMistakes(2), 2);
      expect(starsForMistakes(3), 1);
      expect(starsForMistakes(7), 1);
    });
  });

  group('persistence', () {
    test('round trip keeps every field and the PRNG stream', () {
      final g = fresh(99);
      select(g, ['MARS', 'VENUS', 'SATURN', 'MERCURY']);
      g.submit();
      g.usePairMagnet();
      g.useCategoryPeek();
      select(g, []);
      g.deselectAll();
      select(g, ['GOLD']);
      final restored = PuzzleGame.fromJson(level, g.toJson());
      expect(restored.toJson(), g.toJson());
      g.shuffle();
      restored.shuffle();
      expect(restored.order, g.order);
    });

    test('inconsistent saved data is rejected', () {
      final g = fresh();
      final j = g.toJson();
      expect(
        () => PuzzleGame.fromJson(level, {...j, 'lives': 9}),
        throwsFormatException,
      );
      expect(
        () => PuzzleGame.fromJson(level, {
          ...j,
          'order': ['x.0'],
        }),
        throwsFormatException,
      );
      expect(
        () => PuzzleGame.fromJson(level, {...j, 'status': 'won'}),
        throwsFormatException,
      );
      expect(
        () => PuzzleGame.fromJson(level, {...j, 'mistakes': 2}),
        throwsFormatException,
      );
      expect(
        () => PuzzleGame.fromJson(level, {...j, 'levelId': 'other'}),
        throwsFormatException,
      );
    });
  });
}
