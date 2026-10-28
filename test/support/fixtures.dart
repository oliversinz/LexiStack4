import 'dart:convert';
import 'dart:io';

import 'package:lexistack/core/content.dart';

/// The rule-oracle level from the brief: A = planets, B = metals.
Level oracleLevel() {
  const json = '''
{
  "schemaVersion": 2,
  "pack": {"id": "test", "title": "Test Pack", "description": "Fixture"},
  "levels": [
    {
      "id": "test_lvl01", "packId": "test", "title": "Oracle",
      "categories": [
        {"id": "a", "title": "PLANETS", "difficultyTier": 1,
         "tiles": ["MARS", "VENUS", "SATURN", "JUPITER"],
         "triviaFact": "Jupiter is so massive that it contains more than twice the mass of all other planets."},
        {"id": "b", "title": "METALS", "difficultyTier": 2,
         "tiles": ["MERCURY", "LEAD", "GOLD", "IRON"],
         "triviaFact": "Gold is so malleable that a single gram can be beaten into a very thin, wide sheet."},
        {"id": "c", "title": "GREEK LETTERS", "difficultyTier": 3,
         "tiles": ["ALPHA", "BETA", "GAMMA", "DELTA"],
         "triviaFact": "The word alphabet joins alpha and beta, the first two letters of the Greek alphabet."},
        {"id": "d", "title": "___STONE", "difficultyTier": 4,
         "tiles": ["KEY", "MILE", "CORNER", "SAND"],
         "triviaFact": "A keystone is the wedge at the top of an arch that locks the other stones in place."}
      ],
      "redHerrings": [
        {"tiles": ["MERCURY"], "note": "MERCURY is also a planet, but the metals need it."}
      ]
    }
  ]
}''';
  final issues = <ContentIssue>[];
  final pack = parsePack('test.json', _padLevels(json), issues);
  if (pack == null) throw StateError(issues.join('\n'));
  return pack.levels.first;
}

/// parsePack requires 8 levels per file; pad the oracle file with copies
/// using distinct IDs (only the first level is used by tests).
String _padLevels(String json) {
  final root = jsonDecode(json) as Map<String, Object?>;
  final levels = root['levels'] as List;
  final first = levels.first as Map<String, Object?>;
  for (var i = 2; i <= 8; i++) {
    levels.add({...first, 'id': 'test_lvl0$i'});
  }
  return jsonEncode(root);
}

/// Tile ID for a word on [level].
String tid(Level level, String word) => level.tileIdForWord(word)!;

List<String> tids(Level level, List<String> words) => [
  for (final w in words) tid(level, w),
];

/// Loads the production catalog straight from the asset files on disk.
Catalog loadProductionCatalog() {
  final manifest = File('assets/levels/manifest.json').readAsStringSync();
  final files = <String, String>{};
  for (final f in Directory('assets/levels').listSync().whereType<File>()) {
    final name = f.uri.pathSegments.last;
    if (name.endsWith('.json') && name != 'manifest.json') {
      files[name] = f.readAsStringSync();
    }
  }
  return parseCatalog(manifest, files);
}

/// Encodes n as uppercase letters (A, B, ..., Z, BA, BB, ...).
String letters(int n) {
  const a = 65;
  var s = '';
  do {
    s = String.fromCharCode(a + n % 26) + s;
    n ~/= 26;
  } while (n > 0);
  return s;
}

/// A structurally valid synthetic pack with unique tiles and titles.
/// [salt] keeps tiles unique across packs.
Map<String, Object?> syntheticPack(String packId, int salt, {int levels = 8}) {
  var counter = salt * 1000;
  final levelList = <Map<String, Object?>>[];
  for (var l = 1; l <= levels; l++) {
    final cats = <Map<String, Object?>>[];
    for (var c = 1; c <= 4; c++) {
      cats.add({
        'id': 'g$c',
        'title': 'GROUP $packId $l $c',
        'difficultyTier': c,
        'tiles': [for (var t = 0; t < 4; t++) 'Q${letters(counter++)}'],
        'triviaFact': 'This synthetic fact is long enough to satisfy the validator rules.',
      });
    }
    final lure = (cats.first['tiles'] as List).first as String;
    levelList.add({
      'id': '${packId}_lvl${l.toString().padLeft(2, '0')}',
      'packId': packId,
      'title': 'Level $packId $l',
      'categories': cats,
      'redHerrings': [
        {
          'tiles': [lure],
          'note': '$lure looks like it fits elsewhere but does not.',
        },
      ],
    });
  }
  return {
    'schemaVersion': 2,
    'pack': {'id': packId, 'title': 'Pack $packId', 'description': 'Synthetic'},
    'levels': levelList,
  };
}
