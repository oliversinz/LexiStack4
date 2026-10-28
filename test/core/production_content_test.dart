import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexistack/core/game.dart';
import 'package:lexistack/core/validator.dart';

import '../support/fixtures.dart';

void main() {
  test('production catalog passes strict validation with zero warnings', () {
    final files = <String, String?>{
      for (final f in Directory('assets/levels').listSync().whereType<File>())
        f.uri.pathSegments.last: f.readAsStringSync(),
    };
    final r = validateCatalog(
      manifestSource: files.remove('manifest.json'),
      files: files,
    );
    expect(r.errors, isEmpty);
    expect(r.warnings, isEmpty);
    expect(r.packs.map((p) => p.fileName), [
      'pack1.json',
      'pack2.json',
      'pack3.json',
      'pack4.json',
      'daily.json',
    ]);
    expect(r.campaignLevels, 32);
    expect(r.dailyLevels, 8);
  });

  test('every shipped level is solvable with its intended groups', () {
    final catalog = loadProductionCatalog();
    final levels = [...catalog.campaignLevels, ...catalog.dailyPool];
    expect(levels, hasLength(40));
    for (final level in levels) {
      final g = PuzzleGame.fresh(level, 1);
      for (final c in level.categories) {
        c.tileIds.forEach(g.toggle);
        expect(g.submit(), isA<SubmitSolved>(), reason: '${level.id} ${c.id}');
      }
      expect(g.status, GameStatus.won, reason: level.id);
      expect(g.stars, 3);
    }
  });
}
