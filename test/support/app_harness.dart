import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexistack/app/controller.dart';
import 'package:lexistack/app/storage.dart';
import 'package:lexistack/core/content.dart';
import 'package:lexistack/ui/app.dart';

import 'fixtures.dart';

final Catalog productionCatalog = loadProductionCatalog();

bool _fontsLoaded = false;

/// Loads the bundled fonts (and Material icons) so widget tests and
/// screenshots measure real glyphs instead of the placeholder test font.
/// Call from `setUpAll`.
Future<void> loadAppFonts() async {
  if (_fontsLoaded) return;
  _fontsLoaded = true;
  Future<ByteData> bytes(String path) async =>
      ByteData.sublistView(File(path).readAsBytesSync());
  final sans = FontLoader('LexiSans');
  for (final w in ['Regular', 'Medium', 'Bold', 'Black']) {
    sans.addFont(bytes('assets/fonts/Roboto-$w.ttf'));
  }
  await sans.load();
  await (FontLoader(
    'LexiCondensed',
  )..addFont(bytes('assets/fonts/RobotoCondensed-Bold.ttf'))).load();
  // The Material icon font ships with the Flutter SDK; locate it from
  // FLUTTER_ROOT or from the flutter_tester executable inside bin/cache.
  final exe = Platform.resolvedExecutable.replaceAll('\\', '/');
  final cacheAt = exe.indexOf('/bin/cache/');
  final root =
      Platform.environment['FLUTTER_ROOT'] ??
      (cacheAt > 0 ? exe.substring(0, cacheAt) : null);
  final icons = File(
    '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  );
  if (root != null && icons.existsSync()) {
    await (FontLoader('MaterialIcons')..addFont(bytes(icons.path))).load();
  }
}

/// A mutable clock for date-dependent flows.
class TestClock {
  TestClock(this.now);
  DateTime now;
  DateTime call() => now;
}

/// Pumps the real app with in-memory storage and a fixed clock.
Future<AppController> pumpApp(
  WidgetTester tester, {
  MemoryProgressStore? store,
  TestClock? clock,
  Size size = const Size(390, 844),
  double textScale = 1.0,
  Key? boundaryKey,
}) async {
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(tester.view.reset);
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  final controller = AppController(
    catalog: productionCatalog,
    store: store ?? MemoryProgressStore(),
    clock: (clock ?? TestClock(DateTime(2026, 10, 28, 12))).call,
  );
  await controller.load();
  // Drop any previous app so a "restart" really starts from scratch.
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(
    RepaintBoundary(
      key: boundaryKey,
      child: LexiStackApp(controller: controller),
    ),
  );
  await tester.pumpAndSettle();
  return controller;
}

Finder tileFinder(Level level, String word) =>
    find.byKey(ValueKey('tile-${level.tileIdForWord(word)}'));

/// Taps the four tiles of [category] (scrolling them into view first).
Future<void> tapGroup(
  WidgetTester tester,
  Level level,
  Category category,
) async {
  for (final id in category.tileIds) {
    final f = find.byKey(ValueKey('tile-$id'));
    await tester.ensureVisible(f);
    await tester.tap(f);
    await tester.pump(const Duration(milliseconds: 150));
  }
}

Future<void> tapSubmit(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('submit')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// Fails if a framework error (like a RenderFlex overflow) was reported.
void expectNoFrameworkErrors(WidgetTester tester) {
  expect(tester.takeException(), isNull);
}
