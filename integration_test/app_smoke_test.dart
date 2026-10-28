// On-device smoke test (Android emulator or phone):
//
//   flutter test integration_test/app_smoke_test.dart -d <device-id>
//
// Exercises real gameplay, touch drag, haptics/clipboard platform calls and
// persistence through shared_preferences on the device.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lexistack/app/controller.dart';
import 'package:lexistack/app/storage.dart';
import 'package:lexistack/main.dart';
import 'package:lexistack/ui/app.dart';
import 'package:lexistack/ui/board_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('play, drag, share and persist on device', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    final catalog = await loadCatalog(rootBundle);
    expect(catalog.campaignLevels.length, 32);
    expect(catalog.dailyPool.length, 8);

    var controller = AppController(
      catalog: catalog,
      store: SharedPrefsProgressStore(),
    );
    await controller.load();
    await tester.pumpWidget(LexiStackApp(controller: controller));
    await tester.pumpAndSettle();
    expect(find.text('150'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('continue-campaign')));
    await tester.pumpAndSettle();
    expect(find.byType(TileCard), findsNWidgets(16));
    final level = controller.active!.level;

    // Touch drag: long-press one tile and drop it on another.
    final a = level.categories[0];
    final from = find.byKey(ValueKey('tile-${a.tileIds[0]}'));
    final to = find.byKey(ValueKey('tile-${a.tileIds[1]}'));
    final gesture = await tester.startGesture(tester.getCenter(from));
    await tester.pump(const Duration(milliseconds: 500));
    await gesture.moveBy(const Offset(6, 6));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(to));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(controller.active!.game.selection, [a.tileIds[0], a.tileIds[1]]);

    // Finish every group by tapping (haptics go to the real platform).
    for (final id in a.tileIds.skip(2)) {
      await tester.tap(find.byKey(ValueKey('tile-$id')));
      await tester.pump();
    }
    await tester.tap(find.byKey(const ValueKey('submit')));
    await tester.pumpAndSettle();
    for (final cat in level.categories.skip(1)) {
      for (final id in cat.tileIds) {
        final f = find.byKey(ValueKey('tile-$id'));
        await tester.ensureVisible(f);
        await tester.tap(f);
        await tester.pump();
      }
      await tester.tap(find.byKey(const ValueKey('submit')));
      await tester.pumpAndSettle();
    }
    expect(find.text('Solved!'), findsOneWidget);
    expect(find.text('+50 coins'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('share')));
    await tester.pumpAndSettle();
    final clip = await Clipboard.getData(Clipboard.kTextPlain);
    expect(
      clip?.text,
      startsWith('LexiStack · Everyday Echoes #1\n★★★ · 0 mistakes'),
    );

    // Persistence: a new controller reading the same device storage.
    await controller.flush();
    controller = AppController(
      catalog: catalog,
      store: SharedPrefsProgressStore(),
    );
    await controller.load();
    expect(controller.progress.coins, 200);
    expect(controller.bestStars(level.id), 3);
    expect(controller.stats.gamesPlayed, 1);
    expect(controller.storageFailed, isFalse);
  });
}
