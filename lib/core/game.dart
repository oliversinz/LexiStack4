/// Pure-Dart puzzle rules: selection, submission, lives, boosters, and the
/// explicit result state machine. No Flutter imports.
library;

import 'content.dart';
import 'prng.dart';
import 'scoring.dart';

enum GameStatus { playing, won, lostPendingDecision, lostFinal }

sealed class SubmitResult {
  const SubmitResult();
}

class SubmitSolved extends SubmitResult {
  const SubmitSolved(this.category, {required this.victory});
  final Category category;
  final bool victory;
}

class SubmitMismatch extends SubmitResult {
  const SubmitMismatch({required this.isOneAway, required this.pendingLoss});
  final bool isOneAway;
  final bool pendingLoss;
}

class SubmitAlreadyGuessed extends SubmitResult {
  const SubmitAlreadyGuessed();
}

class SubmitRejected extends SubmitResult {
  const SubmitRejected(this.reason);
  final String reason;
}

/// One evaluated four-tile guess, in the order the tiles were selected.
class GuessRecord {
  const GuessRecord({
    required this.tileIds,
    required this.tiers,
    required this.correct,
  });

  final List<String> tileIds;
  final List<int> tiers;
  final bool correct;

  Map<String, Object?> toJson() => {
    'tiles': tileIds,
    'tiers': tiers,
    'correct': correct,
  };
}

class PuzzleGame {
  /// A fresh game: four lives, all 16 tiles shuffled deterministically.
  PuzzleGame.fresh(this.level, int seed) : _rng = Prng(seed) {
    order = level.tiles.keys.toList();
    _rng.shuffle(order);
  }

  PuzzleGame._restored(this.level, this._rng);

  final Level level;
  final Prng _rng;

  /// Unsolved tile IDs in display order.
  late List<String> order;

  /// Selected tile IDs in selection order (max 4).
  final List<String> selection = [];

  /// Solved category IDs in solve order.
  final List<String> solved = [];

  /// Unordered keys of every evaluated wrong guess.
  final Set<String> wrongKeys = {};
  final List<GuessRecord> guesses = [];

  /// Category ID -> two tile IDs revealed by Pair Magnet.
  final Map<String, List<String>> pairs = {};

  /// Category IDs whose titles were revealed by Category Peek.
  final List<String> peeked = [];

  int lives = kMaxLives;
  int mistakes = 0;
  int combo = 0;
  int bestCombo = 0;
  int rescues = 0;
  GameStatus status = GameStatus.playing;

  bool get isPlaying => status == GameStatus.playing;
  bool get isFinal =>
      status == GameStatus.won || status == GameStatus.lostFinal;
  int get stars => starsForMistakes(mistakes);

  List<Category> get unsolvedCategories =>
      level.categories.where((c) => !solved.contains(c.id)).toList();

  List<Category> get solvedCategories =>
      solved.map((id) => level.categoryById(id)!).toList();

  bool isSelectable(String tileId) => isPlaying && order.contains(tileId);

  bool get canSubmit =>
      isPlaying &&
      selection.length == 4 &&
      selection.toSet().length == 4 &&
      selection.every(order.contains);

  // ---- Selection ---------------------------------------------------------

  /// Toggles a tile. Returns true when the selection changed.
  bool toggle(String tileId) {
    if (!isSelectable(tileId)) return false;
    if (selection.remove(tileId)) return true;
    return _add(tileId);
  }

  bool _add(String tileId) {
    if (!isSelectable(tileId) || selection.contains(tileId)) return false;
    if (selection.length >= 4) return false;
    selection.add(tileId);
    return true;
  }

  /// Dragging [source] onto [target] adds both (subject to the cap).
  bool dragOnto(String source, String target) {
    final a = _add(source);
    final b = _add(target);
    return a || b;
  }

  /// Dropping [source] onto the selection tray adds it.
  bool dropOnTray(String source) => _add(source);

  bool deselectAll() {
    if (selection.isEmpty) return false;
    selection.clear();
    return true;
  }

  /// Reorders unsolved tiles. Free; never changes selection or lives.
  bool shuffle() {
    if (!isPlaying) return false;
    _rng.shuffle(order);
    return true;
  }

  // ---- Submission --------------------------------------------------------

  static String keyOf(Iterable<String> tileIds) =>
      (tileIds.toList()..sort()).join('|');

  SubmitResult submit() {
    if (!isPlaying) return const SubmitRejected('The game is not in play.');
    if (!canSubmit) return const SubmitRejected('Select exactly four tiles.');
    final key = keyOf(selection);
    if (wrongKeys.contains(key)) return const SubmitAlreadyGuessed();

    final tiles = selection.map((id) => level.tiles[id]!).toList();
    final counts = <String, int>{};
    for (final t in tiles) {
      counts[t.category.id] = (counts[t.category.id] ?? 0) + 1;
    }
    final record = GuessRecord(
      tileIds: List.of(selection),
      tiers: tiles.map((t) => t.tier).toList(),
      correct: counts.length == 1,
    );
    guesses.add(record);

    if (counts.length == 1) {
      final cat = tiles.first.category;
      solved.add(cat.id);
      order.removeWhere((id) => level.tiles[id]!.category.id == cat.id);
      selection.clear();
      combo++;
      if (combo > bestCombo) bestCombo = combo;
      final victory = solved.length == level.categories.length;
      if (victory) status = GameStatus.won;
      return SubmitSolved(cat, victory: victory);
    }

    final oneAway = counts.values.any((n) => n == 3);
    wrongKeys.add(key);
    mistakes++;
    lives--;
    combo = 0;
    if (lives <= 0) {
      lives = 0;
      status = GameStatus.lostPendingDecision;
    }
    return SubmitMismatch(isOneAway: oneAway, pendingLoss: lives == 0);
  }

  /// Explicitly accepts a pending loss and reveals the board.
  bool acceptLoss() {
    if (status != GameStatus.lostPendingDecision) return false;
    status = GameStatus.lostFinal;
    selection.clear();
    return true;
  }

  // ---- Boosters (coins are handled by the caller) -------------------------

  /// The pair Pair Magnet would reveal, or null if it is not applicable.
  List<String>? pairMagnetTarget() {
    if (!isPlaying) return null;
    final unsolved = unsolvedCategories;
    if (selection.isNotEmpty) {
      final recent = level.tiles[selection.last]!;
      final cat = recent.category;
      if (!pairs.containsKey(cat.id) && unsolved.contains(cat)) {
        final other = cat.tileIds.firstWhere((id) => id != recent.id);
        return [recent.id, other];
      }
    }
    for (final c in unsolved) {
      if (!pairs.containsKey(c.id)) return c.tileIds.take(2).toList();
    }
    return null;
  }

  List<String>? usePairMagnet() {
    final target = pairMagnetTarget();
    if (target == null) return null;
    pairs[level.tiles[target.first]!.category.id] = target;
    return target;
  }

  Category? categoryPeekTarget() {
    if (!isPlaying) return null;
    for (final c in unsolvedCategories) {
      if (!peeked.contains(c.id)) return c;
    }
    return null;
  }

  Category? useCategoryPeek() {
    final c = categoryPeekTarget();
    if (c != null) peeked.add(c.id);
    return c;
  }

  bool get canExtraLife =>
      (status == GameStatus.playing && lives < kMaxLives) ||
      status == GameStatus.lostPendingDecision;

  bool useExtraLife() {
    if (!canExtraLife) return false;
    if (status == GameStatus.lostPendingDecision) {
      status = GameStatus.playing;
      lives = 1;
    } else {
      lives++;
    }
    rescues++;
    return true;
  }

  /// Tiers per evaluated guess, used for the share grid.
  List<List<int>> get shareRows => [for (final g in guesses) g.tiers];

  // ---- Persistence -------------------------------------------------------

  Map<String, Object?> toJson() => {
    'levelId': level.id,
    'rng': _rng.state,
    'order': order,
    'selection': selection,
    'solved': solved,
    'wrong': wrongKeys.toList(),
    'guesses': [for (final g in guesses) g.toJson()],
    'pairs': pairs,
    'peeked': peeked,
    'lives': lives,
    'mistakes': mistakes,
    'combo': combo,
    'bestCombo': bestCombo,
    'rescues': rescues,
    'status': status.name,
  };

  /// Restores a saved game, validating every reference against [level].
  /// Throws [FormatException] when the data is inconsistent.
  factory PuzzleGame.fromJson(Level level, Map<String, Object?> j) {
    Never bad(String why) => throw FormatException('saved game: $why');
    int integer(String k, int min, int max) {
      final v = j[k];
      if (v is! int || v < min || v > max) bad('$k out of range');
      return v;
    }

    List<String> ids(Object? v, String what) {
      if (v is! List || v.any((e) => e is! String)) bad('$what malformed');
      return v.cast<String>().toList();
    }

    if (j['levelId'] != level.id) bad('level mismatch');
    final g = PuzzleGame._restored(level, Prng(integer('rng', 0, 0xFFFFFFFF)));
    final statusName = j['status'];
    final status = GameStatus.values
        .where((s) => s.name == statusName)
        .firstOrNull;
    if (status == null) bad('unknown status');
    g.status = status;

    final solved = ids(j['solved'], 'solved');
    if (solved.toSet().length != solved.length ||
        solved.any((id) => level.categoryById(id) == null)) {
      bad('solved groups invalid');
    }
    g.solved.addAll(solved);

    final order = ids(j['order'], 'order');
    final expected = level.tiles.keys
        .where((id) => !solved.contains(level.tiles[id]!.category.id))
        .toSet();
    if (order.length != expected.length || !expected.containsAll(order)) {
      bad('tile order does not match unsolved tiles');
    }
    g.order = order;

    final selection = ids(j['selection'], 'selection');
    if (selection.length > 4 ||
        selection.toSet().length != selection.length ||
        !selection.every(expected.contains)) {
      bad('selection invalid');
    }
    g.selection.addAll(selection);

    final guessesRaw = j['guesses'];
    if (guessesRaw is! List) bad('guesses malformed');
    for (final raw in guessesRaw) {
      if (raw is! Map) bad('guess malformed');
      final tiles = ids(raw['tiles'], 'guess tiles');
      if (tiles.length != 4 ||
          tiles.toSet().length != 4 ||
          tiles.any((id) => !level.tiles.containsKey(id))) {
        bad('guess tiles invalid');
      }
      final tiers = tiles.map((id) => level.tiles[id]!.tier).toList();
      final correct =
          tiles.map((id) => level.tiles[id]!.category.id).toSet().length == 1;
      if (raw['correct'] != correct) bad('guess correctness mismatch');
      g.guesses.add(
        GuessRecord(tileIds: tiles, tiers: tiers, correct: correct),
      );
    }

    final wrong = ids(j['wrong'], 'wrong');
    final wrongFromGuesses = {
      for (final x in g.guesses.where((x) => !x.correct)) keyOf(x.tileIds),
    };
    if (wrong.toSet().length != wrong.length ||
        !wrongFromGuesses.containsAll(wrong) ||
        wrong.length != wrongFromGuesses.length) {
      bad('wrong guesses inconsistent');
    }
    g.wrongKeys.addAll(wrong);
    final correctCount = g.guesses.where((x) => x.correct).length;
    if (correctCount != solved.length) bad('solved count mismatch');

    g.mistakes = integer('mistakes', 0, 1000);
    if (g.mistakes != wrong.length) bad('mistake count mismatch');
    g.lives = integer('lives', 0, kMaxLives);
    g.combo = integer('combo', 0, 4);
    g.bestCombo = integer('bestCombo', 0, 4);
    g.rescues = integer('rescues', 0, 1000);
    if (g.lives + g.mistakes != kMaxLives + g.rescues) {
      bad('lives do not match mistakes and rescues');
    }

    final pairsRaw = j['pairs'];
    if (pairsRaw is! Map) bad('pairs malformed');
    for (final e in pairsRaw.entries) {
      final cat = level.categoryById('${e.key}');
      final pair = ids(e.value, 'pair');
      if (cat == null ||
          pair.length != 2 ||
          pair.toSet().length != 2 ||
          !pair.every(cat.tileIds.contains)) {
        bad('pair invalid');
      }
      g.pairs[cat.id] = pair;
    }
    final peeked = ids(j['peeked'], 'peeked');
    if (peeked.toSet().length != peeked.length ||
        peeked.any((id) => level.categoryById(id) == null)) {
      bad('peeked invalid');
    }
    g.peeked.addAll(peeked);

    final allSolved = solved.length == level.categories.length;
    switch (status) {
      case GameStatus.won:
        if (!allSolved) bad('won without all groups');
      case GameStatus.playing:
        if (allSolved || g.lives == 0) bad('playing state inconsistent');
      case GameStatus.lostPendingDecision:
      case GameStatus.lostFinal:
        if (allSolved || g.lives != 0) bad('lost state inconsistent');
    }
    return g;
  }
}
