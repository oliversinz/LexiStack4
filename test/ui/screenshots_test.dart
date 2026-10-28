// Captures real app screenshots into docs/screenshots/.
//
//   flutter test test/ui/screenshots_test.dart --dart-define=SCREENSHOTS=true
//
// Without the define the scenes still render (and must not overflow), but no
// files are written.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexistack/app/controller.dart';
import 'package:lexistack/app/storage.dart';
import 'package:lexistack/core/content.dart';
import 'package:lexistack/ui/home_screen.dart';
import 'package:lexistack/ui/packs_screen.dart';

import '../support/app_harness.dart';

const writeFiles = bool.fromEnvironment('SCREENSHOTS');
const shotKey = ValueKey('screenshot-boundary');

Future<void> capture(
  WidgetTester tester,
  String name, {
  double ratio = 2,
}) async {
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
  if (!writeFiles) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(shotKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: ratio);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File('docs/screenshots/$name.png')
      ..createSync(recursive: true)
      ..writeAsBytesSync(png!.buffer.asUint8List());
  });
}

void solve(AppController c, Category cat) {
  c.deselectAll();
  cat.tileIds.forEach(c.tap);
  c.submit();
}

/// A lived-in save: a few campaign wins and a three-day daily streak.
Future<MemoryProgressStore> seededStore() async {
  final store = MemoryProgressStore();
  final clock = TestClock(DateTime(2026, 10, 25, 9));
  final c = AppController(
    catalog: productionCatalog,
    store: store,
    clock: clock.call,
  );
  await c.load();
  for (final (id, mistakes) in [
    ('pack1_lvl01', 0),
    ('pack1_lvl02', 1),
    ('pack1_lvl03', 0),
    ('pack3_lvl01', 2),
  ]) {
    final a = c.openCampaign(id)!;
    for (var i = 0; i < mistakes; i++) {
      c.deselectAll();
      for (final cat in a.level.categories) {
        c.tap(cat.tileIds[i]);
      }
      c.submit();
    }
    for (final cat in a.level.categories) {
      solve(c, cat);
    }
  }
  for (var d = 25; d <= 27; d++) {
    clock.now = DateTime(2026, 10, d, 9);
    final a = c.openDaily()!;
    for (final cat in a.level.categories) {
      solve(c, cat);
    }
  }
  await c.flush();
  return store;
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets('phone screenshots', (tester) async {
    final c = await pumpApp(
      tester,
      store: await seededStore(),
      boundaryKey: shotKey,
    );
    await capture(tester, '01_home');

    final level = c.catalog.levelById('pack2_lvl01')!;
    Category cat(String id) => level.categoryById(id)!;
    openBoard(
      tester.element(find.byType(HomeScreen)),
      c.openCampaign(level.id),
    );
    await tester.pumpAndSettle();
    for (final w in ['MARS', 'JUNO', 'FIRE', 'SLEET']) {
      c.tap(level.tileIdForWord(w)!);
    }
    await capture(tester, '02_board_selected');

    // A wrong guess that falls for the MARS/VENUS red herring, then two solves.
    c.deselectAll();
    for (final w in ['MARS', 'VENUS', 'JUNO', 'MINERVA']) {
      c.tap(level.tileIdForWord(w)!);
    }
    c.submit();
    solve(c, cat('g1'));
    solve(c, cat('g2'));
    c.deselectAll();
    c.useBooster(Booster.categoryPeek);
    await capture(tester, '03_board_solved');

    solve(c, cat('g3'));
    solve(c, cat('g4'));
    await capture(tester, '04_result');

    await tester.pageBack();
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(HomeScreen))).push(
      MaterialPageRoute<void>(
        builder: (_) => const PacksScreen(initialIndex: 0),
      ),
    );
    await capture(tester, '05_packs');
  });

  testWidgets('desktop frame screenshot', (tester) async {
    final c = await pumpApp(
      tester,
      store: await seededStore(),
      size: const Size(1280, 800),
      boundaryKey: shotKey,
    );
    final level = c.catalog.levelById('pack1_lvl04')!;
    openBoard(
      tester.element(find.byType(HomeScreen)),
      c.openCampaign(level.id),
    );
    await tester.pumpAndSettle();
    solve(c, level.categories[0]);
    for (final w in ['BAT', 'CLUB', 'OFTEN']) {
      c.tap(level.tileIdForWord(w)!);
    }
    await capture(tester, '06_desktop_frame', ratio: 1);
  });
}
