import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexistack/ui/board_screen.dart';

import '../support/app_harness.dart';

void main() {
  setUpAll(loadAppFonts);

  testWidgets('home -> first level -> solve a group shows banner and fact', (
    tester,
  ) async {
    final c = await pumpApp(tester);
    expect(find.text('150'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('continue-campaign')));
    await tester.pumpAndSettle();

    final level = c.catalog.campaign.first.levels.first;
    expect(find.byType(TileCard), findsNWidgets(16));
    final cat = level.categories.first;
    await tapGroup(tester, level, cat);
    expect(find.text('4/4'), findsOneWidget);
    await tapSubmit(tester);
    await tester.pumpAndSettle();
    expect(find.text(cat.title), findsWidgets);
    expect(find.text(cat.triviaFact), findsOneWidget);
    expectNoFrameworkErrors(tester);
  });
}
