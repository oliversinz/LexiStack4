import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexistack/app/controller.dart';
import 'package:lexistack/app/storage.dart';
import 'package:lexistack/core/content.dart';
import 'package:lexistack/core/game.dart';
import 'package:lexistack/ui/board_screen.dart';
import 'package:lexistack/ui/common.dart';
import 'package:lexistack/ui/home_screen.dart';

import '../support/app_harness.dart';

/// Records platform calls (clipboard, haptics) made by the app.
class PlatformLog {
  PlatformLog(WidgetTester tester) {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        calls.add(call);
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
  }

  final List<MethodCall> calls = [];
  String? clipboard;

  int get haptics =>
      calls.where((c) => c.method == 'HapticFeedback.vibrate').length;
}

Future<void> openFirstLevel(WidgetTester tester) async {
  final button = find.byKey(const ValueKey('continue-campaign'));
  // The home list is lazy: return to the top so the card is built again.
  await tester.drag(find.byType(Scrollable).first, const Offset(0, 4000));
  await tester.pumpAndSettle();
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
}

Level activeLevel(AppController c) => c.active!.level;

Future<void> tapTile(WidgetTester tester, String id) async {
  final f = find.byKey(ValueKey('tile-$id'));
  await tester.ensureVisible(f);
  await tester.tap(f);
  await tester.pump(const Duration(milliseconds: 150));
}

/// One tile from each group: a guess that overlaps every group by one.
Future<void> submitSpread(WidgetTester tester, Level level, int ordinal) async {
  for (final cat in level.categories) {
    await tapTile(tester, cat.tileIds[ordinal]);
  }
  await tapSubmit(tester);
}

Future<void> tapDeselect(WidgetTester tester) async {
  await tester.tap(find.text('Deselect'));
  await tester.pump();
}

Future<void> solveRemaining(WidgetTester tester, AppController c) async {
  for (final cat in c.active!.game.unsolvedCategories) {
    for (final id in cat.tileIds) {
      await tapTile(tester, id);
    }
    await tapSubmit(tester);
  }
  await tester.pumpAndSettle();
}

Hearts heartsWidget(WidgetTester tester) =>
    tester.widget<Hearts>(find.byType(Hearts));

void main() {
  setUpAll(loadAppFonts);

  testWidgets('1: home shows coins, four packs and the daily card', (
    tester,
  ) async {
    final c = await pumpApp(tester);
    expect(find.byKey(const ValueKey('coin-balance')), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('coin-balance'))).data,
      '150',
    );
    expect(find.textContaining('Daily Stack · 2026-10-28'), findsOneWidget);
    for (final p in c.catalog.campaign) {
      await tester.scrollUntilVisible(find.text(p.title), 200);
      expect(find.text(p.title), findsOneWidget);
    }
    await tester.scrollUntilVisible(find.text('Science & Nature'), -200);
    await tester.tap(find.text('Science & Nature'));
    await tester.pumpAndSettle();
    expect(find.text('Campaign'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('level-pack2_lvl01')));
    await tester.pumpAndSettle();
    expect(find.byType(BoardScreen), findsOneWidget);
    expect(find.text('Night Sky'), findsOneWidget);
  });

  testWidgets(
    '2: board has 16 tiles; 4 selected enables submit; solve reveals fact',
    (tester) async {
      final c = await pumpApp(tester);
      await openFirstLevel(tester);
      expect(find.byType(TileCard), findsNWidgets(16));
      expect(find.text('Hidden group'), findsNWidgets(4));
      final level = activeLevel(c);
      final cat = level.categories[1];
      FilledButton submit() =>
          tester.widget(find.byKey(const ValueKey('submit')));
      for (var i = 0; i < 3; i++) {
        await tapTile(tester, cat.tileIds[i]);
      }
      expect(submit().onPressed, isNull);
      await tapTile(tester, cat.tileIds[3]);
      expect(submit().onPressed, isNotNull);
      await tapSubmit(tester);
      await tester.pumpAndSettle();
      expect(find.text(cat.title), findsOneWidget);
      expect(find.text(cat.triviaFact), findsOneWidget);
      expect(find.byType(TileCard), findsNWidgets(12));
    },
  );

  testWidgets('3: one away, duplicate guess, fifth tile, drag selection', (
    tester,
  ) async {
    final c = await pumpApp(tester);
    await openFirstLevel(tester);
    final level = activeLevel(c);
    final a = level.categories[0];
    final b = level.categories[1];
    for (final id in [...a.tileIds.take(3), b.tileIds[0]]) {
      await tapTile(tester, id);
    }
    await tapSubmit(tester);
    expect(find.textContaining('One Away!'), findsOneWidget);
    expect(heartsWidget(tester).lives, 3);
    expect(find.text('1 mistake'), findsOneWidget);

    // Fifth tile is ignored while four are selected.
    await tapTile(tester, b.tileIds[1]);
    expect(find.text('4/4'), findsOneWidget);
    expect(c.active!.game.selection, isNot(contains(b.tileIds[1])));

    // Same set again in a different order: no life lost.
    await tapDeselect(tester);
    for (final id in [b.tileIds[0], a.tileIds[2], a.tileIds[0], a.tileIds[1]]) {
      await tapTile(tester, id);
    }
    await tapSubmit(tester);
    expect(find.textContaining('Already guessed'), findsOneWidget);
    expect(heartsWidget(tester).lives, 3);
    await tapDeselect(tester);
    expect(find.text('0/4'), findsOneWidget);

    // Long-press drag a tile onto another tile, then onto the tray.
    Future<void> drag(Finder from, Finder to) async {
      await tester.ensureVisible(from);
      final g = await tester.startGesture(tester.getCenter(from));
      await tester.pump(const Duration(milliseconds: 400));
      await g.moveBy(const Offset(4, 4));
      await tester.pump();
      await g.moveTo(tester.getCenter(to));
      await tester.pump();
      await g.up();
      await tester.pumpAndSettle();
    }

    final t1 = find.byKey(ValueKey('tile-${a.tileIds[0]}'));
    final t2 = find.byKey(ValueKey('tile-${a.tileIds[1]}'));
    await drag(t1, t2);
    expect(c.active!.game.selection, [a.tileIds[0], a.tileIds[1]]);
    await drag(
      find.byKey(ValueKey('tile-${a.tileIds[2]}')),
      find.byKey(const ValueKey('tray')),
    );
    expect(find.text('3/4'), findsOneWidget);
  });

  testWidgets('4: boosters update the board and coins', (tester) async {
    final c = await pumpApp(tester);
    await openFirstLevel(tester);
    final level = activeLevel(c);
    String coins() =>
        tester.widget<Text>(find.byKey(const ValueKey('coin-balance'))).data!;

    await tester.tap(find.byKey(const ValueKey('booster-pairMagnet')));
    await tester.pumpAndSettle();
    expect(coins(), '120');
    expect(find.byIcon(Icons.link_rounded), findsWidgets);
    expect(
      tester
          .widget<TileCard>(
            find.byKey(ValueKey('tile-${level.categories[0].tileIds[0]}')),
          )
          .pair,
      1,
    );

    await tester.tap(find.byKey(const ValueKey('booster-categoryPeek')));
    await tester.pumpAndSettle();
    expect(coins(), '80');
    expect(find.text(level.categories[0].title), findsOneWidget);
    expect(find.text('Hidden group'), findsNWidgets(3));

    // Extra Life is rejected at full lives and costs nothing.
    await tester.tap(find.byKey(const ValueKey('booster-extraLife')));
    await tester.pump();
    expect(find.textContaining('Lives are full'), findsOneWidget);
    expect(coins(), '80');

    await submitSpread(tester, level, 1);
    expect(heartsWidget(tester).lives, 3);
    await tester.tap(find.byKey(const ValueKey('booster-extraLife')));
    await tester.pumpAndSettle();
    expect(heartsWidget(tester).lives, 4);
    expect(coins(), '20');
  });

  testWidgets('5: pending loss hides answers; rescue; final reveal', (
    tester,
  ) async {
    final c = await pumpApp(tester);
    await openFirstLevel(tester);
    final level = activeLevel(c);
    for (var i = 0; i < 4; i++) {
      await tapDeselect(tester);
      await submitSpread(tester, level, i);
    }
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pending-loss')), findsOneWidget);
    for (final cat in level.categories) {
      expect(find.text(cat.title), findsNothing, reason: 'no spoilers');
      expect(find.text(cat.triviaFact), findsNothing);
    }
    await tester.tap(find.byKey(const ValueKey('rescue')));
    await tester.pumpAndSettle();
    expect(c.active!.game.status, GameStatus.playing);
    expect(heartsWidget(tester).lives, 1);
    expect(find.text('90'), findsOneWidget);

    await tapDeselect(tester);
    for (final id in [
      level.categories[0].tileIds[0],
      level.categories[1].tileIds[0],
      level.categories[2].tileIds[1],
      level.categories[3].tileIds[2],
    ]) {
      await tapTile(tester, id);
    }
    await tapSubmit(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('pending-loss')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('accept-loss')));
    await tester.pumpAndSettle();
    expect(c.active!.game.status, GameStatus.lostFinal);
    expect(find.text('Answers revealed'), findsOneWidget);
    for (final cat in level.categories) {
      await tester.scrollUntilVisible(find.text(cat.title), 200);
      expect(find.text(cat.title), findsOneWidget);
    }
    expect(c.stats.gamesPlayed, 1);
  });

  testWidgets('6: persistence across restart, no farming, reset', (
    tester,
  ) async {
    final store = MemoryProgressStore();
    var c = await pumpApp(tester, store: store);
    await openFirstLevel(tester);
    await solveRemaining(tester, c);
    expect(find.text('Solved!'), findsOneWidget);
    expect(find.text('+50 coins'), findsOneWidget);
    await c.flush();

    // Restart: a fresh controller and widget tree on the same storage.
    c = await pumpApp(tester, store: store);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('coin-balance'))).data,
      '200',
    );
    expect(
      find.text('Home Comforts'),
      findsOneWidget,
      reason: 'continue -> level 2',
    );

    // Replay level 1 twice: +5 once, then nothing.
    Future<void> replayLevel1() async {
      final a = c.openCampaign('pack1_lvl01');
      openBoard(
        tester.element(find.byType(HomeScreen, skipOffstage: false)),
        a,
      );
      await tester.pumpAndSettle();
      await solveRemaining(tester, c);
      await tester.tap(find.byKey(const ValueKey('result-next')));
      await tester.pumpAndSettle();
    }

    await replayLevel1();
    await replayLevel1();
    // Both replays used "Next level", landing on level 2's board.
    expect(c.progress.coins, 205);
    await c.flush();

    c = await pumpApp(tester, store: store);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reset-progress')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(c.progress.coins, 205, reason: 'cancel keeps progress');
    await tester.tap(find.byKey(const ValueKey('reset-progress')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('reset-confirm')));
    await tester.pumpAndSettle();
    expect(c.progress.coins, 150);
    expect(c.stats.gamesPlayed, 0);
    expect(c.progress.bestStars, isEmpty);
  });

  testWidgets('7: daily share text is exact and rewards are paid once', (
    tester,
  ) async {
    final log = PlatformLog(tester);
    final c = await pumpApp(tester);
    await tester.tap(find.byKey(const ValueKey('daily-play')));
    await tester.pumpAndSettle();
    final level = activeLevel(c);
    await submitSpread(tester, level, 0);
    await tapDeselect(tester);
    await solveRemaining(tester, c);
    expect(
      find.text('+55 coins'),
      findsOneWidget,
      reason: '30 for 2 stars + 25',
    );

    await tester.tap(find.byKey(const ValueKey('share')));
    await tester.pumpAndSettle();
    expect(
      log.clipboard,
      'LexiStack · Daily 2026-10-28\n'
      '★★☆ · 1 mistake\n'
      '🟨🟩🟦🟪\n'
      '🟨🟨🟨🟨\n'
      '🟩🟩🟩🟩\n'
      '🟦🟦🟦🟦\n'
      '🟪🟪🟪🟪',
    );
    for (final cat in level.categories) {
      expect(log.clipboard, isNot(contains(cat.title)));
      for (final t in cat.tiles) {
        expect(log.clipboard, isNot(contains(t)));
      }
    }

    await tester.tap(find.byKey(const ValueKey('result-next')));
    await tester.pumpAndSettle();
    expect(find.text('View result'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('daily-play')));
    await tester.pumpAndSettle();
    expect(find.text('Solved!'), findsOneWidget);
    expect(c.progress.coins, 205);
    expect(c.stats.gamesPlayed, 1);
  });

  testWidgets('haptics follow the setting', (tester) async {
    final log = PlatformLog(tester);
    final c = await pumpApp(tester);
    await openFirstLevel(tester);
    await tapTile(tester, activeLevel(c).categories[0].tileIds[0]);
    expect(log.haptics, 1);
    c.setHaptics(false);
    await tester.pump();
    await tapTile(tester, activeLevel(c).categories[0].tileIds[1]);
    expect(log.haptics, 1);
  });

  group('8: layouts render without overflow', () {
    Future<void> tour(WidgetTester tester, Size size, double scale) async {
      final c = await pumpApp(tester, size: size, textScale: scale);
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Played'), 200);
      await tester.tap(find.text('Played'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Pop Culture & Wordplay'), 200);
      await tester.tap(find.text('Pop Culture & Wordplay'));
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await openFirstLevel(tester);
      final level = activeLevel(c);
      for (final cat in level.categories.skip(1)) {
        for (final id in cat.tileIds) {
          await tapTile(tester, id);
        }
        await tapSubmit(tester);
      }
      c.useBooster(Booster.categoryPeek);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await solveRemaining(tester, c);
      expect(find.text('Solved!'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }

    testWidgets('360x640 at 1.3x text', (tester) async {
      await tour(tester, const Size(360, 640), 1.3);
    });

    testWidgets('390x844', (tester) async {
      await tour(tester, const Size(390, 844), 1.0);
    });

    testWidgets('1280x800 desktop frame', (tester) async {
      await tour(tester, const Size(1280, 800), 1.0);
      expect(tester.getSize(find.byType(BoardScreen)).width, 460);
    });
  });
}
