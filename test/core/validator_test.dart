import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexistack/core/validator.dart';

import '../support/fixtures.dart';

const fullManifest =
    '{"campaign": ["p1.json", "p2.json", "p3.json", "p4.json"], "daily": "d.json"}';

Map<String, String?> fullFiles() => {
  'p1.json': jsonEncode(syntheticPack('p1', 1)),
  'p2.json': jsonEncode(syntheticPack('p2', 2)),
  'p3.json': jsonEncode(syntheticPack('p3', 3)),
  'p4.json': jsonEncode(syntheticPack('p4', 4)),
  'd.json': jsonEncode(syntheticPack('daily', 5)),
};

ValidationReport strict(
  Map<String, String?> files, [
  String manifest = fullManifest,
]) => validateCatalog(manifestSource: manifest, files: files);

/// Mutates one decoded pack and re-encodes it.
String edit(
  String packId,
  int salt,
  void Function(Map<String, dynamic> pack) change,
) {
  final p = jsonDecode(
    jsonEncode(syntheticPack(packId, salt)),
  ) as Map<String, dynamic>;
  change(p);
  return jsonEncode(p);
}

Matcher hasErrorContaining(String text) => predicate<ValidationReport>(
  (r) => r.errors.any((e) => e.toString().contains(text)),
  'has an error containing "$text"',
);

void main() {
  test('valid full synthetic catalog passes strict with no warnings', () {
    final r = strict(fullFiles());
    expect(r.errors, isEmpty);
    expect(r.warnings, isEmpty);
    expect(r.campaignLevels, 32);
    expect(r.dailyLevels, 8);
  });

  test('partial accepts a subset; strict rejects the same subset', () {
    const manifest = '{"campaign": ["p1.json", "p2.json"]}';
    final files = {'p1.json': fullFiles()['p1.json']};
    final partial = validateCatalog(
      manifestSource: manifest,
      files: files,
      mode: ValidationMode.partial,
    );
    expect(partial.ok, isTrue);
    expect(partial.notes.single, contains('p2.json'));
    expect(formatReport(partial), contains('not a final pass'));

    final full = strict(files, manifest);
    expect(full.ok, isFalse);
    expect(
      full,
      hasErrorContaining('p2.json: file listed in manifest does not exist'),
    );
    expect(full, hasErrorContaining('at least 4 campaign packs'));
    expect(full, hasErrorContaining('daily pool'));
  });

  test('partial still needs at least one existing file', () {
    final r = validateCatalog(
      manifestSource: '{"campaign": ["p1.json"]}',
      files: {},
      mode: ValidationMode.partial,
    );
    expect(r, hasErrorContaining('no listed content file'));
  });

  test('strict allows future expansion beyond four packs', () {
    final files = {
      ...fullFiles(),
      'p5.json': jsonEncode(syntheticPack('p5', 6)),
    };
    final r = strict(
      files,
      '{"campaign": ["p1.json", "p2.json", "p3.json", "p4.json", "p5.json"], "daily": "d.json"}',
    );
    expect(r.ok, isTrue);
    expect(r.campaignLevels, 40);
  });

  test('malformed JSON and wrong types are reported, not thrown', () {
    final files = fullFiles()..['p2.json'] = '{"schemaVersion": 2, "levels": [';
    expect(strict(files), hasErrorContaining('p2.json: malformed JSON'));
    final typed = fullFiles()
      ..['p3.json'] = edit(
        'p3',
        3,
        (p) => p['levels'][0]['categories'][0]['tiles'] = 'NOPE',
      );
    expect(strict(typed), hasErrorContaining('"tiles" must be an array'));
    final version = fullFiles()
      ..['p1.json'] = edit('p1', 1, (p) => p['schemaVersion'] = 1);
    expect(strict(version), hasErrorContaining('unsupported schemaVersion 1'));
  });

  test('structural level errors', () {
    final cases = <String, void Function(Map<String, dynamic>)>{
      'must contain exactly 8 levels': (p) =>
          (p['levels'] as List).removeLast(),
      'does not match parent pack': (p) => p['levels'][0]['packId'] = 'p2',
      'must have exactly 4 categories': (p) =>
          (p['levels'][0]['categories'] as List).removeLast(),
      'tiers 1, 2, 3 and 4': (p) =>
          p['levels'][0]['categories'][3]['difficultyTier'] = 3,
      'must have exactly 4 tiles': (p) =>
          (p['levels'][0]['categories'][0]['tiles'] as List).removeLast(),
      'not uppercase': (p) =>
          p['levels'][0]['categories'][0]['tiles'][0] = 'lower',
      'more than two words': (p) =>
          p['levels'][0]['categories'][0]['tiles'][0] = 'ONE TWO THREE',
      'longer than 10 letters': (p) =>
          p['levels'][0]['categories'][0]['tiles'][0] = 'EXTRAORDINARY',
      'appears twice on the board': (p) =>
          p['levels'][0]['categories'][1]['tiles'][0] =
              p['levels'][0]['categories'][0]['tiles'][0],
      'trivia fact must be 40-160': (p) =>
          p['levels'][0]['categories'][0]['triviaFact'] = 'Too short.',
      'exactly one sentence': (p) =>
          p['levels'][0]['categories'][0]['triviaFact'] = 'This is the first sentence here. And this is a second sentence too.',
      'duplicate category id': (p) =>
          p['levels'][0]['categories'][1]['id'] = 'g1',
      'duplicate level id': (p) => p['levels'][1]['id'] = p['levels'][0]['id'],
      'at least one red herring': (p) => p['levels'][0]['redHerrings'] = [],
      'is not on this board': (p) =>
          p['levels'][0]['redHerrings'][0]['tiles'] = ['ELSEWHERE'],
      'note must be 20-300': (p) =>
          p['levels'][0]['redHerrings'][0]['note'] = 'short',
      'must start with "p1_"': (p) => p['levels'][0]['id'] = 'other_lvl01',
    };
    for (final e in cases.entries) {
      final files = fullFiles()..['p1.json'] = edit('p1', 1, e.value);
      expect(strict(files), hasErrorContaining(e.key), reason: e.key);
    }
  });

  test('cross-file duplicates', () {
    // Same tile in three different levels across files.
    final shared = fullFiles()
      ..['p2.json'] = edit('p2', 2, (p) {
        p['levels'][0]['categories'][0]['tiles'][1] = 'SHARED';
        p['levels'][1]['categories'][0]['tiles'][1] = 'SHARED';
      })
      ..['p3.json'] = edit('p3', 3, (p) {
        p['levels'][0]['categories'][0]['tiles'][1] = 'SHARED';
      });
    expect(strict(shared), hasErrorContaining('"SHARED" appears in 3 levels'));

    final titles = fullFiles()
      ..['p4.json'] = edit('p4', 4, (p) {
        p['levels'][0]['categories'][0]['title'] = 'group p1 1 1';
      });
    expect(strict(titles), hasErrorContaining('duplicates'));

    final overlap = fullFiles()
      ..['d.json'] = edit('daily', 5, (p) {
        final source = syntheticPack('p1', 1)['levels'] as List;
        final tiles =
            ((source[0] as Map)['categories'] as List)[0]['tiles'] as List;
        p['levels'][0]['categories'][0]['tiles'] = [...tiles.take(3), 'QFRESH'];
      });
    expect(strict(overlap), hasErrorContaining('shares 3 tiles'));

    final ids = fullFiles()
      ..['d.json'] = edit('daily', 5, (p) => p['pack']['id'] = 'p1');
    expect(strict(ids), hasErrorContaining('duplicate pack id'));
  });

  test('fact naming another group tile is a warning', () {
    final files = fullFiles()
      ..['p1.json'] = edit('p1', 1, (p) {
        final other = p['levels'][0]['categories'][1]['tiles'][0];
        p['levels'][0]['categories'][0]['triviaFact'] =
            'This fact accidentally mentions $other, which belongs elsewhere.';
      });
    final r = strict(files);
    expect(r.ok, isTrue);
    expect(r.warnings.single.message, contains('another group'));
  });

  test('candidate replacement versus addition', () {
    final replacement = validateCatalog(
      manifestSource: fullManifest,
      files: fullFiles(),
      mode: ValidationMode.candidate,
      candidateName: 'new_p2.json',
      candidateSource: jsonEncode(syntheticPack('p2', 2)),
    );
    expect(replacement.ok, isTrue);
    expect(replacement.notes.single, contains('REPLACEMENT'));
    expect(replacement.campaignLevels, 32);

    final addition = validateCatalog(
      manifestSource: fullManifest,
      files: fullFiles(),
      mode: ValidationMode.candidate,
      candidateName: 'p9.json',
      candidateSource: jsonEncode(syntheticPack('p9', 9)),
    );
    expect(addition.ok, isTrue);
    expect(addition.notes.single, contains('ADDITIONAL'));
    expect(addition.campaignLevels, 40);

    final clash = validateCatalog(
      manifestSource: fullManifest,
      files: fullFiles(),
      mode: ValidationMode.candidate,
      candidateName: 'p9.json',
      candidateSource: jsonEncode(syntheticPack('p9', 1)),
    );
    expect(clash.ok, isFalse, reason: 'reuses p1 tiles and titles in new pack');
  });
}
