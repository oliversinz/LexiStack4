/// Level content model and tolerant JSON parser.
///
/// Pure Dart: shared by the Flutter app, the unit tests and the standalone
/// `tool/validate_levels.dart` CLI. Parsing never throws on malformed input;
/// it records [ContentIssue]s with file/level/category locations instead.
library;

import 'dart:convert';

const int kSchemaVersion = 2;
const int kLevelsPerFile = 8;
const int kFactMin = 40;
const int kFactMax = 160;

/// A single parse/validation finding.
class ContentIssue {
  const ContentIssue(this.location, this.message, {this.isError = true});

  final String location;
  final String message;
  final bool isError;

  @override
  String toString() => '${isError ? 'ERROR' : 'WARNING'} $location: $message';
}

class Category {
  const Category({
    required this.id,
    required this.title,
    required this.tier,
    required this.tiles,
    required this.triviaFact,
  });

  final String id;
  final String title;
  final int tier;
  final List<String> tiles;
  final String triviaFact;

  /// Stable tile identity: category ID plus ordinal, independent of the word.
  String tileId(int ordinal) => '$id.$ordinal';
  List<String> get tileIds => [
    for (var i = 0; i < tiles.length; i++) tileId(i),
  ];
}

class RedHerring {
  const RedHerring({required this.tiles, required this.note});

  final List<String> tiles;
  final String note;
}

class TileInfo {
  const TileInfo({
    required this.id,
    required this.word,
    required this.category,
  });

  final String id;
  final String word;
  final Category category;
  int get tier => category.tier;
}

class Level {
  Level({
    required this.id,
    required this.packId,
    required this.title,
    required this.number,
    required List<Category> categories,
    required this.redHerrings,
  }) : categories = List.unmodifiable(
         [...categories]..sort((a, b) => a.tier.compareTo(b.tier)),
       ) {
    for (final c in this.categories) {
      for (var i = 0; i < c.tiles.length; i++) {
        final info = TileInfo(id: c.tileId(i), word: c.tiles[i], category: c);
        tiles[info.id] = info;
      }
    }
  }

  final String id;
  final String packId;
  final String title;

  /// 1-based position inside its pack.
  final int number;

  /// Sorted by tier 1..4.
  final List<Category> categories;
  final List<RedHerring> redHerrings;

  /// All 16 tiles keyed by stable tile ID, in canonical (tier, ordinal) order.
  final Map<String, TileInfo> tiles = {};

  Category? categoryById(String id) {
    for (final c in categories) {
      if (c.id == id) return c;
    }
    return null;
  }

  /// Tile IDs whose word matches [word] (normalized).
  String? tileIdForWord(String word) {
    final n = normalizeTile(word);
    for (final t in tiles.values) {
      if (normalizeTile(t.word) == n) return t.id;
    }
    return null;
  }
}

class Pack {
  const Pack({
    required this.id,
    required this.title,
    required this.description,
    required this.levels,
    required this.fileName,
  });

  final String id;
  final String title;
  final String description;
  final List<Level> levels;
  final String fileName;
}

/// The loaded production catalog: campaign packs in manifest order plus the
/// separate daily-only packs.
class Catalog {
  Catalog({required this.campaign, required this.daily}) {
    for (final p in [...campaign, ...daily]) {
      for (final l in p.levels) {
        _levels[l.id] = l;
        _packs[l.id] = p;
      }
    }
  }

  final List<Pack> campaign;
  final List<Pack> daily;
  final Map<String, Level> _levels = {};
  final Map<String, Pack> _packs = {};

  Level? levelById(String id) => _levels[id];
  Pack? packOfLevel(String levelId) => _packs[levelId];
  Iterable<Level> get campaignLevels => campaign.expand((p) => p.levels);

  /// Daily boards in manifest order; the pool repeats every
  /// `dailyPool.length` days.
  List<Level> get dailyPool => [for (final p in daily) ...p.levels];
}

class Manifest {
  const Manifest({required this.campaign, required this.daily});

  final List<String> campaign;

  /// Daily-only pack files (the manifest accepts one name or a list).
  final List<String> daily;

  List<String> get allFiles => [...campaign, ...daily];
}

String normalizeTile(String s) =>
    s.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');

String normalizeTitle(String s) =>
    s.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');

final RegExp _idPattern = RegExp(r'^[a-z0-9][a-z0-9_]*$');
final RegExp _categoryIdPattern = RegExp(r'^[a-z0-9][a-z0-9_-]*$');
final RegExp _tileWord = RegExp(r"^[A-Z0-9]+(?:[-'][A-Z0-9]+)*$");

/// Returns a problem description, or null when [tile] is a well-formed tile.
String? tileFormatProblem(String tile) {
  if (tile.isEmpty || tile.trim().isEmpty) return 'tile is blank';
  if (tile != tile.trim()) return 'tile "$tile" has leading/trailing spaces';
  if (tile != tile.toUpperCase()) return 'tile "$tile" is not uppercase';
  final words = tile.split(' ');
  if (words.length > 2) return 'tile "$tile" has more than two words';
  for (final w in words) {
    if (!_tileWord.hasMatch(w)) {
      return 'tile "$tile" contains an invalid word "$w"';
    }
    final letters = w.replaceAll(RegExp(r"[-']"), '').length;
    if (letters > 10) return 'tile "$tile" has a word longer than 10 letters';
  }
  return null;
}

/// Returns a problem description, or null when [fact] is acceptable.
String? factProblem(String fact) {
  final f = fact.trim();
  if (f != fact) return 'trivia fact has leading/trailing whitespace';
  if (f.length < kFactMin || f.length > kFactMax) {
    return 'trivia fact must be $kFactMin-$kFactMax characters (has ${f.length})';
  }
  if (!RegExp(r'[.!?]$').hasMatch(f)) {
    return 'trivia fact must end with sentence punctuation';
  }
  if (RegExp(r'[.!?]\s+[A-Z]').hasMatch(f.substring(0, f.length - 1))) {
    return 'trivia fact must be exactly one sentence';
  }
  return null;
}

Manifest? parseManifest(String source, List<ContentIssue> issues) {
  const loc = 'manifest.json';
  Object? root;
  try {
    root = jsonDecode(source);
  } on FormatException catch (e) {
    issues.add(ContentIssue(loc, 'malformed JSON: ${e.message}'));
    return null;
  }
  if (root is! Map<String, Object?>) {
    issues.add(const ContentIssue(loc, 'root must be an object'));
    return null;
  }
  bool isNames(Object? v) =>
      v is List && v.every((e) => e is String && e.isNotEmpty);
  final campaign = root['campaign'];
  var daily = root['daily'] ?? const <String>[];
  if (daily is String && daily.isNotEmpty) daily = [daily];
  if (!isNames(campaign)) {
    issues.add(
      const ContentIssue(loc, '"campaign" must be a list of file names'),
    );
    return null;
  }
  if (!isNames(daily)) {
    issues.add(
      const ContentIssue(
        loc,
        '"daily" must be a file name or a list of file names',
      ),
    );
    return null;
  }
  final manifest = Manifest(
    campaign: (campaign as List).cast<String>(),
    daily: (daily as List).cast<String>(),
  );
  final all = manifest.allFiles;
  if (all.toSet().length != all.length) {
    issues.add(const ContentIssue(loc, 'a file is listed more than once'));
    return null;
  }
  return manifest;
}

/// Parses one pack file; all problems are appended to [issues]. Returns null
/// only when the pack metadata itself is unusable, so cross-file checks still
/// see every level that parsed. Callers must treat any error as fatal.
Pack? parsePack(String fileName, String source, List<ContentIssue> issues) {
  Object? root;
  try {
    root = jsonDecode(source);
  } on FormatException catch (e) {
    issues.add(ContentIssue(fileName, 'malformed JSON: ${e.message}'));
    return null;
  }
  if (root is! Map<String, Object?>) {
    issues.add(ContentIssue(fileName, 'root must be an object'));
    return null;
  }
  final reader = _Reader(fileName, issues);
  final version = reader.integer(root, 'schemaVersion', fileName);
  if (version != null && version != kSchemaVersion) {
    issues.add(
      ContentIssue(
        fileName,
        'unsupported schemaVersion $version (expected $kSchemaVersion)',
      ),
    );
  }
  final packMap = reader.object(root, 'pack', fileName);
  String? packId;
  String? packTitle;
  String? packDescription;
  if (packMap != null) {
    final loc = '$fileName pack';
    packId = reader.string(packMap, 'id', loc);
    packTitle = reader.string(packMap, 'title', loc);
    packDescription = reader.string(packMap, 'description', loc);
    if (packId != null && !_idPattern.hasMatch(packId)) {
      issues.add(ContentIssue(loc, 'pack id "$packId" must match [a-z0-9_]'));
    }
  }
  final levelsRaw = reader.list(root, 'levels', fileName);
  final levels = <Level>[];
  if (levelsRaw != null) {
    if (levelsRaw.length != kLevelsPerFile) {
      issues.add(
        ContentIssue(
          fileName,
          'must contain exactly $kLevelsPerFile levels (has ${levelsRaw.length})',
        ),
      );
    }
    final seenIds = <String>{};
    for (var i = 0; i < levelsRaw.length; i++) {
      final level = _parseLevel(reader, levelsRaw[i], i, packId, fileName);
      if (level == null) continue;
      if (!seenIds.add(level.id)) {
        issues.add(ContentIssue('$fileName ${level.id}', 'duplicate level id'));
      }
      levels.add(level);
    }
  }
  if (packId == null || packTitle == null || packDescription == null) {
    return null;
  }
  return Pack(
    id: packId,
    title: packTitle,
    description: packDescription,
    levels: List.unmodifiable(levels),
    fileName: fileName,
  );
}

Level? _parseLevel(
  _Reader r,
  Object? raw,
  int index,
  String? packId,
  String fileName,
) {
  final issues = r.issues;
  var loc = '$fileName levels[$index]';
  if (raw is! Map<String, Object?>) {
    issues.add(ContentIssue(loc, 'level must be an object'));
    return null;
  }
  final id = r.string(raw, 'id', loc);
  if (id != null) {
    loc = '$fileName $id';
    if (!_idPattern.hasMatch(id)) {
      issues.add(ContentIssue(loc, 'level id must match [a-z0-9_]'));
    } else if (packId != null && !id.startsWith('${packId}_')) {
      issues.add(ContentIssue(loc, 'level id must start with "${packId}_"'));
    }
  }
  final levelPackId = r.string(raw, 'packId', loc);
  if (levelPackId != null && packId != null && levelPackId != packId) {
    issues.add(
      ContentIssue(
        loc,
        'packId "$levelPackId" does not match parent pack "$packId"',
      ),
    );
  }
  final title = r.string(raw, 'title', loc);
  if (title != null && title.length > 40) {
    issues.add(ContentIssue(loc, 'title longer than 40 characters'));
  }
  final catsRaw = r.list(raw, 'categories', loc);
  final categories = <Category>[];
  if (catsRaw != null) {
    if (catsRaw.length != 4) {
      issues.add(
        ContentIssue(
          loc,
          'must have exactly 4 categories (has ${catsRaw.length})',
        ),
      );
    }
    final ids = <String>{};
    for (var c = 0; c < catsRaw.length; c++) {
      final cat = _parseCategory(r, catsRaw[c], '$loc categories[$c]');
      if (cat == null) continue;
      if (!ids.add(cat.id)) {
        issues.add(ContentIssue('$loc ${cat.id}', 'duplicate category id'));
      }
      categories.add(cat);
    }
    if (categories.length == catsRaw.length) {
      final tiers = categories.map((c) => c.tier).toList()..sort();
      if (tiers.join(',') != '1,2,3,4') {
        issues.add(
          ContentIssue(
            loc,
            'categories must use tiers 1, 2, 3 and 4 exactly once',
          ),
        );
      }
    }
    final seen = <String>{};
    for (final c in categories) {
      for (final t in c.tiles) {
        if (!seen.add(normalizeTile(t))) {
          issues.add(
            ContentIssue(
              '$loc ${c.id}',
              'tile "$t" appears twice on the board',
            ),
          );
        }
      }
    }
  }
  final herrings = <RedHerring>[];
  final rhRaw = r.list(raw, 'redHerrings', loc);
  if (rhRaw != null) {
    if (rhRaw.isEmpty) {
      issues.add(ContentIssue(loc, 'at least one red herring is required'));
    }
    final board = {
      for (final c in categories)
        for (final t in c.tiles) normalizeTile(t),
    };
    for (var h = 0; h < rhRaw.length; h++) {
      final hLoc = '$loc redHerrings[$h]';
      final m = rhRaw[h];
      if (m is! Map<String, Object?>) {
        issues.add(ContentIssue(hLoc, 'red herring must be an object'));
        continue;
      }
      final tiles = r.stringList(m, 'tiles', hLoc);
      final note = r.string(m, 'note', hLoc);
      if (tiles == null || note == null) continue;
      if (tiles.isEmpty) {
        issues.add(ContentIssue(hLoc, 'red herring must reference a tile'));
      }
      for (final t in tiles) {
        if (!board.contains(normalizeTile(t))) {
          issues.add(ContentIssue(hLoc, 'tile "$t" is not on this board'));
        }
      }
      if (note.trim().length < 20 || note.length > 300) {
        issues.add(ContentIssue(hLoc, 'note must be 20-300 characters'));
      }
      herrings.add(RedHerring(tiles: tiles, note: note));
    }
  }
  if (id == null || levelPackId == null || title == null) return null;
  return Level(
    id: id,
    packId: levelPackId,
    title: title,
    number: index + 1,
    categories: categories,
    redHerrings: herrings,
  );
}

Category? _parseCategory(_Reader r, Object? raw, String loc) {
  final issues = r.issues;
  if (raw is! Map<String, Object?>) {
    issues.add(ContentIssue(loc, 'category must be an object'));
    return null;
  }
  final id = r.string(raw, 'id', loc);
  if (id != null) {
    loc = loc.replaceFirst(RegExp(r'categories\[\d+\]$'), id);
    if (!_categoryIdPattern.hasMatch(id)) {
      issues.add(ContentIssue(loc, 'category id must match [a-z0-9_-]'));
    }
  }
  final title = r.string(raw, 'title', loc);
  final tier = r.integer(raw, 'difficultyTier', loc);
  if (tier != null && (tier < 1 || tier > 4)) {
    issues.add(ContentIssue(loc, 'difficultyTier must be 1-4 (is $tier)'));
  }
  final tiles = r.stringList(raw, 'tiles', loc);
  if (tiles != null) {
    if (tiles.length != 4) {
      issues.add(
        ContentIssue(loc, 'must have exactly 4 tiles (has ${tiles.length})'),
      );
    }
    for (final t in tiles) {
      final p = tileFormatProblem(t);
      if (p != null) issues.add(ContentIssue(loc, p));
    }
    if (tiles.map(normalizeTile).toSet().length != tiles.length) {
      issues.add(ContentIssue(loc, 'duplicate tile within category'));
    }
  }
  final fact = r.string(raw, 'triviaFact', loc);
  if (fact != null) {
    final p = factProblem(fact);
    if (p != null) issues.add(ContentIssue(loc, p));
  }
  if (id == null ||
      title == null ||
      tier == null ||
      tiles == null ||
      fact == null) {
    return null;
  }
  return Category(
    id: id,
    title: title,
    tier: tier,
    tiles: List.unmodifiable(tiles),
    triviaFact: fact,
  );
}

/// Typed field access that reports actionable errors instead of throwing.
class _Reader {
  _Reader(this.file, this.issues);

  final String file;
  final List<ContentIssue> issues;

  Object? _field(Map<String, Object?> m, String key, String loc, String type) {
    if (!m.containsKey(key)) {
      issues.add(ContentIssue(loc, 'missing "$key" ($type)'));
      return null;
    }
    return m[key];
  }

  String? string(Map<String, Object?> m, String key, String loc) {
    final v = _field(m, key, loc, 'string');
    if (v == null && !m.containsKey(key)) return null;
    if (v is! String || v.trim().isEmpty) {
      issues.add(ContentIssue(loc, '"$key" must be a non-empty string'));
      return null;
    }
    return v;
  }

  int? integer(Map<String, Object?> m, String key, String loc) {
    final v = _field(m, key, loc, 'integer');
    if (v == null && !m.containsKey(key)) return null;
    if (v is! int) {
      issues.add(ContentIssue(loc, '"$key" must be an integer'));
      return null;
    }
    return v;
  }

  Map<String, Object?>? object(Map<String, Object?> m, String key, String loc) {
    final v = _field(m, key, loc, 'object');
    if (v == null && !m.containsKey(key)) return null;
    if (v is! Map<String, Object?>) {
      issues.add(ContentIssue(loc, '"$key" must be an object'));
      return null;
    }
    return v;
  }

  List<Object?>? list(Map<String, Object?> m, String key, String loc) {
    final v = _field(m, key, loc, 'array');
    if (v == null && !m.containsKey(key)) return null;
    if (v is! List<Object?>) {
      issues.add(ContentIssue(loc, '"$key" must be an array'));
      return null;
    }
    return v;
  }

  List<String>? stringList(Map<String, Object?> m, String key, String loc) {
    final v = list(m, key, loc);
    if (v == null) return null;
    if (v.any((e) => e is! String)) {
      issues.add(ContentIssue(loc, '"$key" must contain only strings'));
      return null;
    }
    return v.cast<String>();
  }
}

/// Parses a full catalog from already-loaded file contents. Throws a
/// [FormatException] listing every error; production content is validated by
/// `tool/validate_levels.dart`, so this only fails on a broken build.
Catalog parseCatalog(String manifestSource, Map<String, String> files) {
  final issues = <ContentIssue>[];
  final manifest = parseManifest(manifestSource, issues);
  final campaign = <Pack>[];
  final daily = <Pack>[];
  if (manifest != null) {
    for (final f in manifest.allFiles) {
      final src = files[f];
      if (src == null) {
        issues.add(ContentIssue(f, 'missing content file'));
        continue;
      }
      final p = parsePack(f, src, issues);
      if (p != null) (manifest.daily.contains(f) ? daily : campaign).add(p);
    }
  }
  final errors = issues.where((i) => i.isError).toList();
  if (errors.isNotEmpty || manifest == null) {
    throw FormatException('Invalid level content:\n${errors.join('\n')}');
  }
  return Catalog(campaign: campaign, daily: daily);
}
