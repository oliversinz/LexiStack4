import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexistack/app/controller.dart';
import 'package:lexistack/app/progress.dart';
import 'package:lexistack/app/storage.dart';
import 'package:lexistack/core/content.dart';
import 'package:lexistack/core/game.dart';
import 'package:lexistack/core/scoring.dart';

import '../support/app_harness.dart' show TestClock, productionCatalog;

Catalog get catalog => productionCatalog;
Level campaignLevel(int pack, int n) => catalog.campaign[pack].levels[n - 1];

Future<AppController> boot({
  MemoryProgressStore? store,
  TestClock? clock,
}) async {
  final c = AppController(
    catalog: catalog,
    store: store ?? MemoryProgressStore(),
    clock: (clock ?? TestClock(DateTime(2026, 10, 28, 12))).call,
  );
  await c.load();
  return c;
}

/// Submits [n] wrong guesses that share at most one tile with any group.
void makeMistakes(AppController c, int n) {
  final level = c.active!.level;
  for (var i = 0; i < n; i++) {
    c.deselectAll();
    for (final cat in level.categories) {
      c.tap(cat.tileIds[i % 4]);
    }
    expect(c.submit(), isA<SubmitMismatch>());
  }
}

/// Solves every remaining group in tier order.
void solveAll(AppController c) {
  final g = c.active!.game;
  c.deselectAll();
  for (final cat in g.unsolvedCategories) {
    cat.tileIds.forEach(c.tap);
    expect(c.submit(), isA<SubmitSolved>());
  }
}

/// Plays a campaign level to victory with [mistakes] wrong guesses.
ActiveGame winLevel(AppController c, Level level, {int mistakes = 0}) {
  final a = c.openCampaign(level.id)!;
  makeMistakes(c, mistakes);
  solveAll(c);
  return a;
}

void main() {
  group('economy and campaign', () {
    test('fresh state', () async {
      final c = await boot();
      expect(c.progress.coins, kStartingCoins);
      expect(c.stats.gamesPlayed, 0);
      expect(c.isUnlocked(campaignLevel(0, 1)), isTrue);
      expect(c.isUnlocked(campaignLevel(0, 2)), isFalse);
      for (final p in catalog.campaign) {
        expect(c.isUnlocked(p.levels.first), isTrue, reason: p.id);
      }
    });

    test('first win rewards 50 / 30 / 15 by mistakes', () async {
      final c = await boot();
      for (final (n, mistakes, reward) in [
        (1, 0, 50),
        (2, 2, 30),
        (3, 3, 15),
      ]) {
        final before = c.progress.coins;
        final a = winLevel(c, campaignLevel(0, n), mistakes: mistakes);
        expect(a.result!.coinsEarned, reward);
        expect(c.progress.coins, before + reward);
        expect(c.bestStars(a.level.id), starsForMistakes(mistakes));
      }
      expect(c.isUnlocked(campaignLevel(0, 4)), isTrue);
      expect(
        c.isUnlocked(campaignLevel(1, 2)),
        isFalse,
        reason: 'packs independent',
      );
    });

    test('replays: best stars only improve, practice +5 once', () async {
      final c = await boot();
      final level = campaignLevel(0, 1);
      winLevel(c, level, mistakes: 3);
      expect(c.bestStars(level.id), 1);
      final coins = c.progress.coins;
      final r1 = winLevel(c, level, mistakes: 0).result!;
      expect(r1.coinsEarned, kPracticeReward);
      expect(c.bestStars(level.id), 3);
      final r2 = winLevel(c, level, mistakes: 3).result!;
      expect(r2.coinsEarned, 0);
      expect(c.bestStars(level.id), 3, reason: 'never lowered');
      expect(c.progress.coins, coins + kPracticeReward);
    });

    test('rescued win still scores by mistakes', () async {
      final c = await boot();
      c.openCampaign(campaignLevel(0, 1).id);
      makeMistakes(c, 4);
      expect(c.active!.game.status, GameStatus.lostPendingDecision);
      expect(c.useBooster(Booster.extraLife), isTrue);
      expect(c.progress.coins, kStartingCoins - kExtraLifeCost);
      solveAll(c);
      expect(c.active!.result!.stars, 1);
      expect(c.active!.result!.coinsEarned, 15);
    });

    test('continue campaign picks the latest unfinished attempt, then earliest unwon', () async {
      final c = await boot();
      expect(c.continueCampaignLevel(), campaignLevel(0, 1));
      c.openCampaign(campaignLevel(2, 1).id);
      c.openCampaign(campaignLevel(1, 1).id);
      expect(c.continueCampaignLevel(), campaignLevel(1, 1));
      c.openCampaign(campaignLevel(2, 1).id);
      makeMistakes(c, 4);
      expect(
        c.continueCampaignLevel(),
        campaignLevel(2, 1),
        reason: 'pending loss counts as unfinished',
      );
      expect(c.openCampaign(campaignLevel(0, 3).id), isNull, reason: 'locked');
    });

    test('everything won -> no continue target', () async {
      final c = await boot();
      for (final l in catalog.campaignLevels) {
        winLevel(c, l);
      }
      expect(c.continueCampaignLevel(), isNull);
      expect(c.progress.bestStars.length, 32);
    });
  });

  group('boosters', () {
    test('costs, targeting and rejection without charge', () async {
      final c = await boot();
      final level = campaignLevel(0, 1);
      c.openCampaign(level.id);
      final g = c.active!.game;
      c.tap(level.categories[2].tileIds[3]);
      expect(c.useBooster(Booster.pairMagnet), isTrue);
      expect(g.pairs[level.categories[2].id], [
        level.categories[2].tileIds[3],
        level.categories[2].tileIds[0],
      ]);
      expect(c.progress.coins, 120);
      expect(c.useBooster(Booster.categoryPeek), isTrue);
      expect(g.peeked, [level.categories.first.id]);
      expect(c.progress.coins, 80);

      expect(c.boosterBlocker(Booster.extraLife), 'Lives are full');
      expect(c.useBooster(Booster.extraLife), isFalse);
      expect(c.progress.coins, 80);

      c.useBooster(Booster.categoryPeek); // 40 left
      c.useBooster(Booster.pairMagnet); // 10 left
      final snapshot = jsonEncode(g.toJson());
      expect(c.boosterBlocker(Booster.categoryPeek), 'Not enough coins');
      expect(c.useBooster(Booster.categoryPeek), isFalse);
      expect(c.progress.coins, 10);
      expect(jsonEncode(g.toJson()), snapshot, reason: 'no game change');
    });

    test('booster effects persist across reload without recharging', () async {
      final store = MemoryProgressStore();
      final c = await boot(store: store);
      final level = campaignLevel(0, 1);
      c.openCampaign(level.id);
      c.useBooster(Booster.pairMagnet);
      c.useBooster(Booster.categoryPeek);
      await c.flush();
      final order = List.of(c.active!.game.order);

      final c2 = await boot(store: store);
      expect(c2.progress.coins, 80);
      final a = c2.openCampaign(level.id)!;
      expect(a.game.order, order, reason: 'same board, not rerolled');
      expect(a.game.pairs, hasLength(1));
      expect(a.game.peeked, hasLength(1));
      expect(c2.progress.coins, 80);
    });
  });

  group('daily', () {
    test('same date gives the same board; +25 bonus once', () async {
      final clock = TestClock(DateTime(2026, 10, 28, 9));
      final c1 = await boot(clock: clock);
      final c2 = await boot(clock: clock);
      final a1 = c1.openDaily()!;
      final a2 = c2.openDaily()!;
      expect(a1.level.id, a2.level.id);
      expect(a1.game.order, a2.game.order);
      expect(a1.level.id, catalog.dailyPool[300 % 8].id);

      solveAll(c1);
      expect(a1.result!.coinsEarned, 50 + kDailyBonus);
      expect(c1.progress.coins, 150 + 75);
      expect(c1.dailyStatus, DailyStatus.won);
      final again = c1.openDaily()!;
      expect(
        again.game.isFinal,
        isTrue,
        reason: 'shows result, no new attempt',
      );
      expect(c1.progress.coins, 225);
      expect(c1.stats.gamesPlayed, 1);
      expect(
        c1.todaysDailyResult!.shareText,
        startsWith('LexiStack · Daily 2026-10-28\n★★★ · 0 mistakes'),
      );
    });

    test(
      'tomorrow is a fresh attempt; stale unfinished daily is discarded',
      () async {
        final clock = TestClock(DateTime(2026, 10, 28, 23, 50));
        final store = MemoryProgressStore();
        final c = await boot(clock: clock, store: store);
        c.openDaily();
        c.useBooster(Booster.categoryPeek);
        makeMistakes(c, 1);
        await c.flush();

        clock.now = DateTime(2026, 10, 29, 0, 5);
        expect(
          c.tap(c.active!.game.order.first),
          isFalse,
          reason: 'stale board',
        );
        expect(c.active, isNull);
        expect(c.dailyStatus, DailyStatus.notStarted);
        final next = c.openDaily()!;
        expect(next.date, '2026-10-29');
        expect(next.game.mistakes, 0);
        expect(next.game.peeked, isEmpty);
        expect(c.progress.dailyOutcomes, isEmpty, reason: 'not a win or loss');
        expect(c.stats.gamesPlayed, 0);

        // A restart on the new day also drops yesterday's board.
        await c.flush();
        final reloaded = await boot(store: store, clock: clock);
        expect(reloaded.progress.daily?.date, '2026-10-29');
      },
    );

    test('streaks continue, break and keep the best', () async {
      final clock = TestClock(DateTime(2026, 10, 20, 12));
      final c = await boot(clock: clock);
      void playDaily({required bool win}) {
        c.openDaily();
        if (win) {
          solveAll(c);
        } else {
          makeMistakes(c, 4);
          c.acceptLoss();
        }
      }

      for (var d = 20; d <= 22; d++) {
        clock.now = DateTime(2026, 10, d, 12);
        playDaily(win: true);
      }
      expect(c.dailyStreak, 3);
      clock.now = DateTime(2026, 10, 23, 12);
      expect(c.dailyStreak, 3, reason: 'today not played yet');
      playDaily(win: false);
      expect(c.dailyStreak, 0);
      expect(c.progress.bestDailyStreak, 3);
      clock.now = DateTime(2026, 10, 25, 12);
      playDaily(win: true);
      expect(c.dailyStreak, 1, reason: 'missed day breaks the streak');
      expect(c.progress.bestDailyStreak, 3);
      expect(c.stats.gamesPlayed, 5);
      expect(c.stats.wins, 4);
    });
  });

  group('stats and results', () {
    test(
      'active and pending games do not count; finalize counts once',
      () async {
        final store = MemoryProgressStore();
        final c = await boot(store: store);
        c.openCampaign(campaignLevel(0, 1).id);
        makeMistakes(c, 4);
        expect(c.stats.gamesPlayed, 0, reason: 'pending loss');
        expect(c.acceptLoss(), isTrue);
        expect(c.acceptLoss(), isFalse);
        expect(c.stats.gamesPlayed, 1);
        expect(c.stats.wins, 0);
        await c.flush();
        final c2 = await boot(store: store);
        expect(c2.stats.gamesPlayed, 1, reason: 'no double count after reload');
        expect(c2.hasUnfinished(campaignLevel(0, 1).id), isFalse);
      },
    );

    test('win distribution and perfect wins', () async {
      final c = await boot();
      winLevel(c, campaignLevel(0, 1), mistakes: 0);
      winLevel(c, campaignLevel(0, 2), mistakes: 1);
      winLevel(c, campaignLevel(0, 3), mistakes: 2);
      final s = c.stats;
      expect(s.perfectWins, 1);
      expect(s.distribution, [1, 1, 1, 0, 0]);
    });
  });

  test('distribution 4+ bucket via rescue', () async {
    final c = await boot();
    c.openCampaign(campaignLevel(0, 1).id);
    makeMistakes(c, 4);
    c.useBooster(Booster.extraLife);
    solveAll(c);
    expect(c.stats.distribution, [0, 0, 0, 0, 1]);
  });

  group('persistence and recovery', () {
    test('unfinished attempt round-trips exactly', () async {
      final store = MemoryProgressStore();
      final c = await boot(store: store);
      final level = campaignLevel(1, 1);
      c.openCampaign(level.id);
      makeMistakes(c, 1);
      c.tap(level.categories[1].tileIds[2]);
      c.shuffle();
      await c.flush();
      final saved = jsonEncode(c.active!.game.toJson());
      final c2 = await boot(store: store);
      final a = c2.openCampaign(level.id)!;
      expect(jsonEncode(a.game.toJson()), saved);
      expect(c2.progress.encode(), isNot(contains('"version":2')));
    });

    test('pending loss is still pending after restart', () async {
      final store = MemoryProgressStore();
      final c = await boot(store: store);
      c.openCampaign(campaignLevel(0, 1).id);
      makeMistakes(c, 4);
      await c.flush();
      final c2 = await boot(store: store);
      final a = c2.openCampaign(campaignLevel(0, 1).id)!;
      expect(a.game.status, GameStatus.lostPendingDecision);
    });

    test('unreadable or wrong-version documents reset safely', () async {
      for (final raw in [
        'not json',
        '[]',
        jsonEncode({'version': 99, 'coins': 5}),
      ]) {
        final c = await boot(store: MemoryProgressStore(raw));
        expect(c.progress.coins, kStartingCoins);
        expect(c.loadNotice, contains('reset'));
      }
    });

    test('corrupt or orphaned attempts are dropped, valid data kept', () async {
      final c = await boot();
      winLevel(c, campaignLevel(0, 1), mistakes: 1);
      c.openCampaign(campaignLevel(0, 2).id);
      makeMistakes(c, 1);
      final doc = jsonDecode(c.progress.encode()) as Map<String, dynamic>;
      final attempts = doc['campaignAttempts'] as Map<String, dynamic>;
      attempts['pack9_lvl01'] = {
        'attemptId': 'pack9_lvl01#1',
        'seq': 3,
        'game': attempts['pack1_lvl02']['game'],
      };
      attempts['pack1_lvl02']['game']['lives'] = 9;
      doc['history'] = [
        ...doc['history'] as List,
        {'broken': true},
      ];
      doc['bestStars']['pack1_lvl05'] = 7;

      final c2 = await boot(store: MemoryProgressStore(jsonEncode(doc)));
      expect(c2.progress.coins, c.progress.coins);
      expect(c2.bestStars('pack1_lvl01'), 2);
      expect(c2.progress.bestStars.containsKey('pack1_lvl05'), isFalse);
      expect(c2.progress.history, hasLength(1));
      expect(c2.progress.campaignAttempts, isEmpty);
      expect(c2.loadNotice, contains('skipped'));
    });

    test('writes are serialized and failures are surfaced', () async {
      final store = MemoryProgressStore();
      final c = await boot(store: store);
      c.openCampaign(campaignLevel(0, 1).id);
      for (final id in c.active!.game.order.take(3)) {
        c.tap(id);
      }
      await c.flush();
      final decoded = PlayerProgress.decode(store.data).progress;
      expect(
        decoded.campaignAttempts['pack1_lvl01']!.game['selection'],
        hasLength(3),
        reason: 'last write wins',
      );

      store.failWrites = true;
      c.deselectAll();
      await c.flush();
      expect(c.storageFailed, isTrue);
      store.failWrites = false;
      c.tap(c.active!.game.order.first);
      await c.flush();
      expect(c.storageFailed, isFalse);
    });

    test('reset restores the exact fresh state', () async {
      final c = await boot(clock: TestClock(DateTime(2026, 10, 28)));
      winLevel(c, campaignLevel(0, 1));
      c.openDaily();
      solveAll(c);
      c.setTheme('dark');
      c.setHaptics(false);
      c.resetProgress();
      expect(c.progress.encode(), PlayerProgress().encode());
      expect(c.dailyStatus, DailyStatus.notStarted);
    });
  });
}
