/// Catalog-wide content validation shared by the CLI and tests.
///
/// Pure Dart; file I/O is the caller's job, so files are passed in as
/// `name -> contents` (null when the file does not exist).
library;

import 'content.dart';

enum ValidationMode {
  /// Final production check: every listed file must exist and the catalog
  /// must contain at least four campaign packs and a daily pool.
  strict,

  /// Development check: validates only listed files that already exist.
  partial,

  /// A standalone candidate pack checked against the installed catalog.
  candidate,
}

class PackSummary {
  const PackSummary(
    this.fileName,
    this.packId,
    this.title,
    this.levels,
    this.isDaily,
  );

  final String fileName;
  final String packId;
  final String title;
  final int levels;
  final bool isDaily;
}

class ValidationReport {
  ValidationReport(this.mode);

  final ValidationMode mode;
  final List<ContentIssue> issues = [];
  final List<PackSummary> packs = [];
  final List<String> notes = [];

  List<ContentIssue> get errors => issues.where((i) => i.isError).toList();
  List<ContentIssue> get warnings => issues.where((i) => !i.isError).toList();
  bool get ok => errors.isEmpty;
  int get campaignLevels =>
      packs.where((p) => !p.isDaily).fold(0, (s, p) => s + p.levels);
  int get dailyLevels =>
      packs.where((p) => p.isDaily).fold(0, (s, p) => s + p.levels);
}

/// Validates the installed catalog.
///
/// In [ValidationMode.candidate] mode pass [candidateName]/[candidateSource]:
/// a candidate whose pack ID matches an installed pack replaces it for the
/// check, otherwise it is checked as an additional campaign pack.
ValidationReport validateCatalog({
  required String? manifestSource,
  required Map<String, String?> files,
  ValidationMode mode = ValidationMode.strict,
  String? candidateName,
  String? candidateSource,
}) {
  final report = ValidationReport(mode);
  final issues = report.issues;
  if (manifestSource == null) {
    issues.add(const ContentIssue('manifest.json', 'manifest file is missing'));
    return report;
  }
  final manifest = parseManifest(manifestSource, issues);
  if (manifest == null) return report;

  final parsed = <({String file, Pack pack, bool isDaily})>[];
  var present = 0;
  for (final f in manifest.allFiles) {
    final isDaily = manifest.daily.contains(f);
    final src = files[f];
    if (src == null) {
      if (mode == ValidationMode.strict) {
        issues.add(ContentIssue(f, 'file listed in manifest does not exist'));
      } else {
        report.notes.add('$f is listed but not present yet (skipped)');
      }
      continue;
    }
    present++;
    final pack = parsePack(f, src, issues);
    if (pack != null) parsed.add((file: f, pack: pack, isDaily: isDaily));
  }

  if (mode == ValidationMode.candidate) {
    final name = candidateName ?? 'candidate.json';
    final candidate = parsePack(name, candidateSource ?? '', issues);
    if (candidate != null) {
      final idx = parsed.indexWhere((p) => p.pack.id == candidate.id);
      if (idx >= 0) {
        report.notes.add(
          'candidate "${candidate.id}" is a REPLACEMENT for '
          '${parsed[idx].file}',
        );
        parsed[idx] = (
          file: name,
          pack: candidate,
          isDaily: parsed[idx].isDaily,
        );
      } else {
        report.notes.add('candidate "${candidate.id}" is an ADDITIONAL pack');
        parsed.add((file: name, pack: candidate, isDaily: false));
      }
    }
  } else if (present == 0) {
    issues.add(
      const ContentIssue('manifest.json', 'no listed content file exists yet'),
    );
  }

  if (mode == ValidationMode.strict) {
    if (manifest.campaign.length < 4) {
      issues.add(
        ContentIssue(
          'manifest.json',
          'strict mode requires at least 4 campaign packs (has ${manifest.campaign.length})',
        ),
      );
    }
    if (manifest.daily.isEmpty) {
      issues.add(
        const ContentIssue(
          'manifest.json',
          'strict mode requires a daily pool file',
        ),
      );
    }
  }

  for (final p in parsed) {
    report.packs.add(
      PackSummary(
        p.file,
        p.pack.id,
        p.pack.title,
        p.pack.levels.length,
        p.isDaily,
      ),
    );
  }
  _crossChecks(parsed.map((p) => p.pack).toList(), issues);
  return report;
}

void _crossChecks(List<Pack> packs, List<ContentIssue> issues) {
  final packIds = <String>{};
  for (final p in packs) {
    if (!packIds.add(p.id)) {
      issues.add(ContentIssue(p.fileName, 'duplicate pack id "${p.id}"'));
    }
  }

  final levelIds = <String, String>{};
  final titles = <String, String>{};
  final levelTitles = <String, String>{};
  final tileLevels = <String, Set<String>>{};
  final boards = <String, String>{};
  final allCats = <({String loc, Set<String> tiles})>[];

  for (final p in packs) {
    for (final l in p.levels) {
      final loc = '${p.fileName} ${l.id}';
      final prev = levelIds[l.id];
      if (prev != null && prev != p.fileName) {
        issues.add(ContentIssue(loc, 'level id also used in $prev'));
      }
      levelIds[l.id] = p.fileName;

      final lt = normalizeTitle(l.title);
      final prevTitle = levelTitles[lt];
      if (prevTitle != null) {
        issues.add(
          ContentIssue(
            loc,
            'level title "${l.title}" also used by $prevTitle',
            isError: false,
          ),
        );
      }
      levelTitles[lt] = loc;

      final board = <String>[];
      for (final c in l.categories) {
        final cLoc = '$loc ${c.id}';
        final t = normalizeTitle(c.title);
        final prevCat = titles[t];
        if (prevCat != null) {
          issues.add(
            ContentIssue(
              cLoc,
              'category title "${c.title}" duplicates $prevCat',
            ),
          );
        }
        titles[t] = cLoc;
        final norm = c.tiles.map(normalizeTile).toSet();
        for (final other in allCats) {
          final shared = other.tiles.intersection(norm);
          if (shared.length >= 3) {
            issues.add(
              ContentIssue(
                cLoc,
                'shares ${shared.length} tiles (${shared.join(', ')}) with ${other.loc}',
              ),
            );
          }
        }
        allCats.add((loc: cLoc, tiles: norm));
        for (final tile in norm) {
          (tileLevels[tile] ??= <String>{}).add(l.id);
          board.add(tile);
        }
        _factWarnings(l, c, cLoc, issues);
      }
      final key = (board..sort()).join('|');
      final dup = boards[key];
      if (dup != null) {
        issues.add(ContentIssue(loc, 'board is identical to $dup'));
      }
      boards[key] = loc;

      for (var h = 0; h < l.redHerrings.length; h++) {
        final rh = l.redHerrings[h];
        for (final t in rh.tiles) {
          if (!_mentions(rh.note, t)) {
            issues.add(
              ContentIssue(
                '$loc redHerrings[$h]',
                'note does not mention its tile "$t"',
                isError: false,
              ),
            );
          }
        }
      }
    }
  }

  final overused = tileLevels.entries.where((e) => e.value.length > 2).toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  for (final e in overused) {
    issues.add(
      ContentIssue(
        'catalog',
        'tile "${e.key}" appears in ${e.value.length} levels (max 2): ${e.value.join(', ')}',
      ),
    );
  }
}

/// Warns when a category's fact names a tile that belongs to another
/// category on the same board, which can leak or muddle answers.
void _factWarnings(Level l, Category c, String loc, List<ContentIssue> issues) {
  for (final other in l.categories) {
    if (other.id == c.id) continue;
    for (final t in other.tiles) {
      if (_mentions(c.triviaFact, t)) {
        issues.add(
          ContentIssue(
            loc,
            'trivia fact names "$t", a tile from another group (${other.id})',
            isError: false,
          ),
        );
      }
    }
  }
}

bool _mentions(String text, String tile) {
  final pattern = RegExp(
    '(^|[^A-Za-z0-9])${RegExp.escape(tile)}(?=\$|[^A-Za-z0-9])',
    caseSensitive: false,
  );
  return pattern.hasMatch(text);
}

/// Human-readable multi-line report used by the CLI.
String formatReport(ValidationReport r) {
  final b = StringBuffer();
  final modeLabel = switch (r.mode) {
    ValidationMode.strict => 'STRICT (final)',
    ValidationMode.partial => 'PARTIAL (development)',
    ValidationMode.candidate => 'CANDIDATE',
  };
  b.writeln('LexiStack content validation â€” mode: $modeLabel');
  for (final n in r.notes) {
    b.writeln('  note: $n');
  }
  for (final i in r.issues) {
    b.writeln('  $i');
  }
  b.writeln('Packs:');
  for (final p in r.packs) {
    b.writeln(
      '  ${p.fileName.padRight(16)} ${p.packId.padRight(10)} '
      '${p.levels} levels${p.isDaily ? ' (daily pool)' : ''}  "${p.title}"',
    );
  }
  final campaignPacks = r.packs.where((p) => !p.isDaily).length;
  b.writeln(
    'Totals: $campaignPacks campaign packs, ${r.campaignLevels} campaign '
    'levels, ${r.dailyLevels} daily levels, '
    '${r.campaignLevels + r.dailyLevels} levels total.',
  );
  b.writeln(
    'Result: ${r.errors.length} errors, ${r.warnings.length} warnings'
    '${r.mode == ValidationMode.partial ? ' (partial catalog â€” not a final pass)' : ''}.',
  );
  return b.toString();
}
