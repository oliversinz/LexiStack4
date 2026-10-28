/// The single versioned progress document and its tolerant decoder.
library;

import 'dart:convert';

import '../core/daily.dart';
import '../core/scoring.dart';

const int kProgressVersion = 1;

/// A finalized attempt. Self-contained so history and share text survive
/// even if the level is later removed from the content files.
class ResultSummary {
  const ResultSummary({
    required this.attemptId,
    required this.levelId,
    required this.isDaily,
    required this.header,
    required this.won,
    required this.mistakes,
    required this.groupsSolved,
    required this.coinsEarned,
    required this.rows,
    this.date,
  });

  final String attemptId;
  final String levelId;
  final bool isDaily;
  final String header;
  final String? date;
  final bool won;
  final int mistakes;
  final int groupsSolved;
  final int coinsEarned;
  final List<List<int>> rows;

  int get stars => won ? starsForMistakes(mistakes) : 0;

  String get shareText => buildShareText(
    header: header,
    won: won,
    mistakes: mistakes,
    groupsSolved: groupsSolved,
    rows: rows,
  );

  Map<String, Object?> toJson() => {
    'attemptId': attemptId,
    'levelId': levelId,
    'daily': isDaily,
    'header': header,
    'date': date,
    'won': won,
    'mistakes': mistakes,
    'groups': groupsSolved,
    'coins': coinsEarned,
    'rows': rows,
  };

  static ResultSummary? fromJson(Object? j) {
    if (j is! Map) return null;
    final rows = j['rows'];
    final mistakes = j['mistakes'];
    final groups = j['groups'];
    final coins = j['coins'];
    final date = j['date'];
    if (j['attemptId'] is! String ||
        j['levelId'] is! String ||
        j['daily'] is! bool ||
        j['header'] is! String ||
        j['won'] is! bool ||
        mistakes is! int ||
        mistakes < 0 ||
        groups is! int ||
        groups < 0 ||
        groups > 4 ||
        coins is! int ||
        coins < 0 ||
        (date != null &&
            (date is! String || CivilDate.tryParse(date) == null)) ||
        rows is! List ||
        !rows.every(
          (r) =>
              r is List &&
              r.length == 4 &&
              r.every((t) => t is int && t >= 1 && t <= 4),
        )) {
      return null;
    }
    if (j['won'] == true && groups != 4) return null;
    return ResultSummary(
      attemptId: j['attemptId'] as String,
      levelId: j['levelId'] as String,
      isDaily: j['daily'] as bool,
      header: j['header'] as String,
      date: date as String?,
      won: j['won'] as bool,
      mistakes: mistakes,
      groupsSolved: groups,
      coinsEarned: coins,
      rows: [for (final r in rows) (r as List).cast<int>()],
    );
  }
}

/// An unfinished campaign attempt (raw game JSON is validated against the
/// level by the controller on load).
class SavedAttempt {
  const SavedAttempt({
    required this.attemptId,
    required this.seq,
    required this.game,
  });

  final String attemptId;
  final int seq;
  final Map<String, Object?> game;

  Map<String, Object?> toJson() => {
    'attemptId': attemptId,
    'seq': seq,
    'game': game,
  };

  static SavedAttempt? fromJson(Object? j) {
    if (j is! Map ||
        j['attemptId'] is! String ||
        j['seq'] is! int ||
        j['game'] is! Map<String, Object?>) {
      return null;
    }
    return SavedAttempt(
      attemptId: j['attemptId'] as String,
      seq: j['seq'] as int,
      game: j['game'] as Map<String, Object?>,
    );
  }
}

/// Today's daily attempt, kept after it finishes so the result can be shown.
class DailyAttempt {
  const DailyAttempt({required this.date, required this.game});

  final String date;
  final Map<String, Object?> game;

  Map<String, Object?> toJson() => {'date': date, 'game': game};

  static DailyAttempt? fromJson(Object? j) {
    if (j is! Map ||
        j['date'] is! String ||
        CivilDate.tryParse(j['date'] as String) == null ||
        j['game'] is! Map<String, Object?>) {
      return null;
    }
    return DailyAttempt(
      date: j['date'] as String,
      game: j['game'] as Map<String, Object?>,
    );
  }
}

const themeModes = ['system', 'light', 'dark'];

class PlayerProgress {
  PlayerProgress();

  int coins = kStartingCoins;
  final Map<String, int> bestStars = {};
  final Set<String> practicePaid = {};
  final Map<String, int> attemptCounter = {};
  final List<ResultSummary> history = [];
  final Map<String, bool> dailyOutcomes = {};
  int bestDailyStreak = 0;
  final Map<String, SavedAttempt> campaignAttempts = {};
  DailyAttempt? daily;
  int seq = 0;
  String theme = 'system';
  bool haptics = true;

  Map<String, Object?> toJson() => {
    'version': kProgressVersion,
    'coins': coins,
    'bestStars': bestStars,
    'practicePaid': practicePaid.toList()..sort(),
    'attemptCounter': attemptCounter,
    'history': [for (final h in history) h.toJson()],
    'dailyOutcomes': dailyOutcomes,
    'bestDailyStreak': bestDailyStreak,
    'campaignAttempts': {
      for (final e in campaignAttempts.entries) e.key: e.value.toJson(),
    },
    'daily': daily?.toJson(),
    'seq': seq,
    'settings': {'theme': theme, 'haptics': haptics},
  };

  String encode() => jsonEncode(toJson());

  /// Decodes a stored document. A missing, unreadable or wrong-version
  /// document yields fresh defaults; otherwise each field is salvaged
  /// independently and every discarded piece is listed in `problems`.
  static ({PlayerProgress progress, List<String> problems, bool reset}) decode(
    String? raw,
  ) {
    final p = PlayerProgress();
    final problems = <String>[];
    if (raw == null) return (progress: p, problems: problems, reset: false);
    Object? root;
    try {
      root = jsonDecode(raw);
    } on FormatException {
      return (progress: p, problems: ['unreadable document'], reset: true);
    }
    if (root is! Map<String, Object?>) {
      return (
        progress: p,
        problems: ['document is not an object'],
        reset: true,
      );
    }
    if (root['version'] != kProgressVersion) {
      return (
        progress: p,
        problems: ['unsupported version ${root['version']}'],
        reset: true,
      );
    }

    final coins = root['coins'];
    if (coins is int && coins >= 0 && coins <= 100000000) {
      p.coins = coins;
    } else {
      problems.add('coins');
    }

    final seen = <String>{};
    for (final h in _list(root['history'], 'history', problems)) {
      final r = ResultSummary.fromJson(h);
      if (r == null || !seen.add(r.attemptId)) {
        problems.add('history entry');
      } else {
        p.history.add(r);
      }
    }

    _map(root['bestStars'], 'bestStars', problems).forEach((k, v) {
      if (v is int && v >= 1 && v <= 3) {
        p.bestStars[k] = v;
      } else {
        problems.add('bestStars.$k');
      }
    });
    for (final v in _list(root['practicePaid'], 'practicePaid', problems)) {
      if (v is String) p.practicePaid.add(v);
    }
    _map(root['attemptCounter'], 'attemptCounter', problems).forEach((k, v) {
      if (v is int && v >= 0) p.attemptCounter[k] = v;
    });
    _map(root['dailyOutcomes'], 'dailyOutcomes', problems).forEach((k, v) {
      if (v is bool && CivilDate.tryParse(k) != null) {
        p.dailyOutcomes[k] = v;
      } else {
        problems.add('dailyOutcomes.$k');
      }
    });
    final best = root['bestDailyStreak'];
    if (best is int && best >= 0) {
      p.bestDailyStreak = best;
    } else {
      problems.add('bestDailyStreak');
    }
    _map(root['campaignAttempts'], 'campaignAttempts', problems).forEach((
      k,
      v,
    ) {
      final a = SavedAttempt.fromJson(v);
      if (a == null) {
        problems.add('campaign attempt $k');
      } else {
        p.campaignAttempts[k] = a;
      }
    });
    if (root['daily'] != null) {
      p.daily = DailyAttempt.fromJson(root['daily']);
      if (p.daily == null) problems.add('daily attempt');
    }
    final seq = root['seq'];
    if (seq is int && seq >= 0) p.seq = seq;
    final settings = root['settings'];
    if (settings is Map) {
      if (themeModes.contains(settings['theme'])) {
        p.theme = settings['theme'] as String;
      }
      if (settings['haptics'] is bool) p.haptics = settings['haptics'] as bool;
    }
    return (progress: p, problems: problems, reset: false);
  }

  static List<Object?> _list(Object? v, String what, List<String> problems) {
    if (v is List) return v;
    if (v != null) problems.add(what);
    return const [];
  }

  static Map<String, Object?> _map(
    Object? v,
    String what,
    List<String> problems,
  ) {
    if (v is Map<String, Object?>) return v;
    if (v != null) problems.add(what);
    return const {};
  }
}
