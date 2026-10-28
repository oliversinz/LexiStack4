/// Application state: progression, economy, daily rules and persistence.
///
/// A single [ChangeNotifier]; the UI listens to it and calls its methods.
library;

import 'package:flutter/foundation.dart';

import '../core/content.dart';
import '../core/daily.dart';
import '../core/game.dart';
import '../core/prng.dart';
import '../core/scoring.dart';
import 'progress.dart';
import 'storage.dart';

typedef Clock = DateTime Function();

enum Booster { pairMagnet, categoryPeek, extraLife }

int boosterCost(Booster b) => switch (b) {
  Booster.pairMagnet => kPairMagnetCost,
  Booster.categoryPeek => kCategoryPeekCost,
  Booster.extraLife => kExtraLifeCost,
};

enum DailyStatus { unavailable, notStarted, inProgress, won, lost }

/// The game currently open on the board screen.
class ActiveGame {
  ActiveGame({
    required this.attemptId,
    required this.level,
    required this.game,
    required this.header,
    required this.subtitle,
    this.date,
  });

  final String attemptId;
  final Level level;
  final PuzzleGame game;

  /// Share-text first line, e.g. `LexiStack · Everyday Echoes #3`.
  final String header;

  /// Board subtitle, e.g. `Everyday Echoes · Level 3`.
  final String subtitle;

  /// Civil date for a daily game, null for campaign.
  final String? date;

  bool get isDaily => date != null;

  /// Set once the attempt is finalized and settled.
  ResultSummary? result;
}

class Stats {
  const Stats({
    required this.gamesPlayed,
    required this.wins,
    required this.perfectWins,
    required this.distribution,
    required this.currentStreak,
    required this.bestStreak,
  });

  final int gamesPlayed;
  final int wins;
  final int perfectWins;

  /// Wins by mistakes: 0, 1, 2, 3, 4+.
  final List<int> distribution;
  final int currentStreak;
  final int bestStreak;

  double get winRate => gamesPlayed == 0 ? 0 : wins / gamesPlayed;
}

class AppController extends ChangeNotifier {
  AppController({required this.catalog, required this.store, Clock? clock})
    : clock = clock ?? DateTime.now;

  final Catalog catalog;
  final ProgressStore store;
  final Clock clock;

  PlayerProgress progress = PlayerProgress();
  ActiveGame? active;

  /// Set when the last write failed; cleared by the next successful write.
  bool storageFailed = false;

  /// One-shot notice for the UI after a reset/salvage on load.
  String? loadNotice;

  Future<void> _writes = Future.value();

  CivilDate get today => CivilDate.fromDateTime(clock());

  // ---- Loading & saving ---------------------------------------------------

  Future<void> load() async {
    String? raw;
    try {
      raw = await store.read();
    } catch (_) {
      raw = null;
      loadNotice = 'Saved progress could not be read.';
    }
    final decoded = PlayerProgress.decode(raw);
    progress = decoded.progress;
    final problems = [...decoded.problems];
    if (decoded.reset) {
      loadNotice = 'Saved progress was unreadable and has been reset.';
    }

    // Validate unfinished campaign attempts against the current content.
    for (final entry in progress.campaignAttempts.entries.toList()) {
      final game = _restore(entry.key, entry.value.game);
      if (game == null || game.isFinal) {
        progress.campaignAttempts.remove(entry.key);
        if (game == null) problems.add('campaign attempt ${entry.key}');
      }
    }
    _checkDailyDate();
    final d = progress.daily;
    if (d != null) {
      final level = _dailyLevelFor(CivilDate.tryParse(d.date)!);
      if (level == null || _restore(level.id, d.game) == null) {
        progress.daily = null;
        problems.add('daily attempt');
      }
    }
    if (problems.isNotEmpty && !decoded.reset) {
      loadNotice ??= 'Some saved data was damaged and has been skipped.';
    }
    if (problems.isNotEmpty || decoded.reset) _save();
    notifyListeners();
  }

  PuzzleGame? _restore(String levelId, Map<String, Object?> json) {
    final level = catalog.levelById(levelId);
    if (level == null) return null;
    try {
      return PuzzleGame.fromJson(level, json);
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  void _save() {
    if (active case final a?) _syncActive(a);
    final snapshot = progress.encode();
    _writes = _writes.then((_) async {
      try {
        await store.write(snapshot);
        if (storageFailed) {
          storageFailed = false;
          notifyListeners();
        }
      } catch (_) {
        storageFailed = true;
        notifyListeners();
      }
    });
  }

  /// Completes when every queued write has finished.
  Future<void> flush() => _writes;

  void _syncActive(ActiveGame a) {
    final g = a.game;
    if (a.isDaily) {
      if (a.date == progress.daily?.date || progress.daily == null) {
        progress.daily = DailyAttempt(date: a.date!, game: g.toJson());
      }
    } else if (!g.isFinal) {
      final prev = progress.campaignAttempts[a.level.id];
      progress.campaignAttempts[a.level.id] = SavedAttempt(
        attemptId: a.attemptId,
        seq: prev?.seq ?? progress.seq,
        game: g.toJson(),
      );
    }
  }

  void _changed() {
    _save();
    notifyListeners();
  }

  // ---- Campaign -----------------------------------------------------------

  bool isWon(String levelId) => progress.bestStars.containsKey(levelId);
  int bestStars(String levelId) => progress.bestStars[levelId] ?? 0;
  bool hasUnfinished(String levelId) =>
      progress.campaignAttempts.containsKey(levelId);

  bool isUnlocked(Level level) {
    if (level.number == 1) return true;
    final pack = catalog.packOfLevel(level.id);
    if (pack == null) return false;
    return isWon(pack.levels[level.number - 2].id);
  }

  int wonInPack(Pack pack) => pack.levels.where((l) => isWon(l.id)).length;

  /// Most recently entered unfinished attempt, else the earliest unlocked
  /// never-won level; null when everything is won.
  Level? continueCampaignLevel() {
    final unfinished = progress.campaignAttempts.entries.toList()
      ..sort((a, b) => b.value.seq.compareTo(a.value.seq));
    for (final e in unfinished) {
      final level = catalog.levelById(e.key);
      if (level != null) return level;
    }
    for (final level in catalog.campaignLevels) {
      if (isUnlocked(level) && !isWon(level.id)) return level;
    }
    return null;
  }

  /// Opens a campaign level: resumes its unfinished attempt if there is one,
  /// otherwise starts a new attempt (a replay when the level is already won).
  ActiveGame? openCampaign(String levelId) {
    final level = catalog.levelById(levelId);
    final pack = catalog.packOfLevel(levelId);
    if (level == null || pack == null || !catalog.campaign.contains(pack)) {
      return null;
    }
    if (!isUnlocked(level)) return null;
    final saved = progress.campaignAttempts[levelId];
    PuzzleGame? game;
    String attemptId;
    if (saved != null) {
      game = _restore(levelId, saved.game);
      attemptId = saved.attemptId;
    } else {
      attemptId = '';
    }
    if (game == null) {
      final n = (progress.attemptCounter[levelId] ?? 0) + 1;
      progress.attemptCounter[levelId] = n;
      attemptId = '$levelId#$n';
      game = PuzzleGame.fresh(level, fnv1a32(attemptId));
    }
    progress.seq++;
    progress.campaignAttempts[levelId] = SavedAttempt(
      attemptId: attemptId,
      seq: progress.seq,
      game: game.toJson(),
    );
    active = ActiveGame(
      attemptId: attemptId,
      level: level,
      game: game,
      header: campaignShareHeader(pack.title, level.number),
      subtitle: '${pack.title} · Level ${level.number}',
    );
    _changed();
    return active;
  }

  // ---- Daily --------------------------------------------------------------

  Level? _dailyLevelFor(CivilDate date) {
    final pool = catalog.dailyPool;
    if (pool.isEmpty) return null;
    return pool[dailyPoolIndex(date, pool.length)];
  }

  Level? get todaysDailyLevel => _dailyLevelFor(today);

  /// Drops a previous date's daily attempt. Returns true if one was dropped.
  bool _checkDailyDate() {
    final d = progress.daily;
    if (d == null || d.date == today.toString()) return false;
    progress.daily = null;
    if (active?.date == d.date) active = null;
    return true;
  }

  DailyStatus get dailyStatus {
    if (_dailyLevelFor(today) == null) return DailyStatus.unavailable;
    final outcome = progress.dailyOutcomes[today.toString()];
    if (outcome != null) return outcome ? DailyStatus.won : DailyStatus.lost;
    final d = progress.daily;
    if (d != null && d.date == today.toString()) return DailyStatus.inProgress;
    return DailyStatus.notStarted;
  }

  /// Today's finalized result, if any.
  ResultSummary? get todaysDailyResult => _historyFor('daily:$today');

  ResultSummary? _historyFor(String attemptId) {
    for (final h in progress.history) {
      if (h.attemptId == attemptId) return h;
    }
    return null;
  }

  /// Opens today's daily: resumes it, or shows the finished result, or starts
  /// the single attempt for this date.
  ActiveGame? openDaily() {
    if (_checkDailyDate()) _save();
    final date = today;
    final level = _dailyLevelFor(date);
    if (level == null) return null;
    final key = date.toString();
    PuzzleGame? game;
    final saved = progress.daily;
    if (saved != null && saved.date == key) {
      game = _restore(level.id, saved.game);
    }
    final finished = _historyFor('daily:$key');
    // A finalized daily whose board was not kept is shown from its summary
    // on the home screen; never start a second attempt for the date.
    if (game == null && finished != null) return null;
    game ??= PuzzleGame.fresh(level, fnv1a32('daily:$key'));
    progress.daily = DailyAttempt(date: key, game: game.toJson());
    active = ActiveGame(
      attemptId: 'daily:$key',
      level: level,
      game: game,
      header: dailyShareHeader(key),
      subtitle: 'Daily Stack · $key',
      date: key,
    )..result = finished;
    _changed();
    return active;
  }

  int get dailyStreak => currentDailyStreak(progress.dailyOutcomes, today);

  // ---- Game actions -------------------------------------------------------

  /// Returns the active game if it can still be played on; drops a daily
  /// that belongs to a previous date.
  ActiveGame? _playable() {
    final a = active;
    if (a == null) return null;
    if (a.isDaily && a.date != today.toString()) {
      _checkDailyDate();
      active = null;
      _changed();
      return null;
    }
    return a;
  }

  bool tap(String tileId) => _selectionAction((g) => g.toggle(tileId));
  bool dragOnto(String source, String target) =>
      _selectionAction((g) => g.dragOnto(source, target));
  bool dropOnTray(String source) =>
      _selectionAction((g) => g.dropOnTray(source));
  bool deselectAll() => _selectionAction((g) => g.deselectAll());
  bool shuffle() => _selectionAction((g) => g.shuffle());

  bool _selectionAction(bool Function(PuzzleGame g) action) {
    final a = _playable();
    if (a == null) return false;
    final changed = action(a.game);
    if (changed) _changed();
    return changed;
  }

  SubmitResult submit() {
    final a = _playable();
    if (a == null) return const SubmitRejected('No game in progress.');
    final r = a.game.submit();
    if (r is SubmitSolved || r is SubmitMismatch) {
      if (a.game.isFinal) _finalize(a);
      _changed();
    }
    return r;
  }

  /// Explicitly accepts a pending loss and reveals the answers.
  bool acceptLoss() {
    final a = _playable();
    if (a == null || !a.game.acceptLoss()) return false;
    _finalize(a);
    _changed();
    return true;
  }

  /// Why a booster cannot be used right now, or null if it can.
  String? boosterBlocker(Booster b) {
    final a = active;
    if (a == null) return 'No game in progress';
    final g = a.game;
    final applicable = switch (b) {
      Booster.pairMagnet => g.pairMagnetTarget() != null,
      Booster.categoryPeek => g.categoryPeekTarget() != null,
      Booster.extraLife => g.canExtraLife,
    };
    if (!applicable) {
      if (g.isFinal) return 'Game over';
      if (g.status == GameStatus.lostPendingDecision) return 'Out of lives';
      return switch (b) {
        Booster.pairMagnet => 'Every group already has a pair',
        Booster.categoryPeek => 'All titles revealed',
        Booster.extraLife => 'Lives are full',
      };
    }
    if (progress.coins < boosterCost(b)) return 'Not enough coins';
    return null;
  }

  /// Applies a booster; coins are charged once, only if it succeeds.
  bool useBooster(Booster b) {
    final a = _playable();
    if (a == null || boosterBlocker(b) != null) return false;
    final ok = switch (b) {
      Booster.pairMagnet => a.game.usePairMagnet() != null,
      Booster.categoryPeek => a.game.useCategoryPeek() != null,
      Booster.extraLife => a.game.useExtraLife(),
    };
    if (!ok) return false;
    progress.coins -= boosterCost(b);
    _changed();
    return true;
  }

  /// Settles a finalized attempt exactly once: coins, stars, streaks, stats.
  void _finalize(ActiveGame a) {
    final g = a.game;
    final existing = _historyFor(a.attemptId);
    if (existing != null) {
      a.result = existing;
      return;
    }
    final won = g.status == GameStatus.won;
    var coins = 0;
    if (a.isDaily) {
      if (won) coins = firstWinReward(g.stars) + kDailyBonus;
      progress.dailyOutcomes[a.date!] = won;
      final streak = dailyStreak;
      if (streak > progress.bestDailyStreak) progress.bestDailyStreak = streak;
    } else {
      final id = a.level.id;
      if (won) {
        if (!isWon(id)) {
          coins = firstWinReward(g.stars);
        } else if (progress.practicePaid.add(id)) {
          coins = kPracticeReward;
        }
        if (g.stars > bestStars(id)) progress.bestStars[id] = g.stars;
      }
      progress.campaignAttempts.remove(id);
    }
    progress.coins += coins;
    final summary = ResultSummary(
      attemptId: a.attemptId,
      levelId: a.level.id,
      isDaily: a.isDaily,
      header: a.header,
      date: a.date,
      won: won,
      mistakes: g.mistakes,
      groupsSolved: g.solved.length,
      coinsEarned: coins,
      rows: g.shareRows,
    );
    progress.history.add(summary);
    a.result = summary;
  }

  /// Releases [attemptId] when its board closes. Does not notify: it is called
  /// from widget disposal and nothing outside the board shows the game.
  void closeGame(String attemptId) {
    if (active?.attemptId == attemptId) active = null;
  }

  /// Next campaign level in the same pack after the active one, if unlocked.
  Level? nextLevelAfter(Level level) {
    final pack = catalog.packOfLevel(level.id);
    if (pack == null || !catalog.campaign.contains(pack)) return null;
    if (level.number >= pack.levels.length) return null;
    final next = pack.levels[level.number];
    return isUnlocked(next) ? next : null;
  }

  // ---- Stats & settings ---------------------------------------------------

  Stats get stats {
    final h = progress.history;
    final wins = h.where((r) => r.won).toList();
    final dist = List.filled(5, 0);
    for (final w in wins) {
      dist[w.mistakes.clamp(0, 4)]++;
    }
    return Stats(
      gamesPlayed: h.length,
      wins: wins.length,
      perfectWins: wins.where((w) => w.mistakes == 0).length,
      distribution: dist,
      currentStreak: dailyStreak,
      bestStreak: progress.bestDailyStreak,
    );
  }

  void setTheme(String mode) {
    if (!themeModes.contains(mode) || progress.theme == mode) return;
    progress.theme = mode;
    _changed();
  }

  void setHaptics(bool on) {
    if (progress.haptics == on) return;
    progress.haptics = on;
    _changed();
  }

  /// Restores the exact fresh state.
  void resetProgress() {
    progress = PlayerProgress();
    active = null;
    _changed();
  }
}
