import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/controller.dart';
import '../core/content.dart';
import '../core/game.dart';
import '../core/scoring.dart';
import 'board_screen.dart';
import 'common.dart';
import 'theme.dart';

/// Shown in place of the dock at zero lives: no spoilers until the player
/// explicitly reveals the answers.
class PendingLossPanel extends StatelessWidget {
  const PendingLossPanel({super.key, required this.onMessage});

  final void Function(String message) onMessage;

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final p = context.palette;
    final blocker = c.boosterBlocker(Booster.extraLife);
    return Container(
      key: const ValueKey('pending-loss'),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.border)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              'Out of lives',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 20,
                color: p.ink,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'The remaining groups stay hidden. Buy one more life to keep this '
            'attempt going, or reveal the answers and accept the loss.',
            style: TextStyle(color: p.inkSoft, height: 1.3),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            key: const ValueKey('rescue'),
            onPressed: blocker == null
                ? () {
                    if (c.useBooster(Booster.extraLife)) {
                      Haptics.booster(c.progress.haptics);
                      onMessage('Extra Life! Back in the game with 1 life');
                    }
                  }
                : null,
            icon: const Icon(Icons.favorite_rounded),
            label: Text(
              blocker == null
                  ? 'Extra Life · $kExtraLifeCost coins'
                  : 'Extra Life · $kExtraLifeCost coins ($blocker)',
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const ValueKey('accept-loss'),
            onPressed: c.acceptLoss,
            child: const Text('Reveal answers & accept loss'),
          ),
        ],
      ),
    );
  }
}

/// Final outcome: stars, coins, every group with its fact, red herrings,
/// the spoiler-free share grid and navigation.
class ResultView extends StatelessWidget {
  const ResultView({super.key, required this.active});

  final ActiveGame active;

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final p = context.palette;
    final g = active.game;
    final won = g.status == GameStatus.won;
    final result = active.result;
    final coins = result?.coinsEarned ?? 0;
    final share = result?.shareText;
    final next = active.isDaily ? null : c.nextLevelAfter(active.level);

    // Red herrings whose tiles the player actually fell for come first.
    final wrongWords = {
      for (final guess in g.guesses.where((x) => !x.correct))
        for (final id in guess.tileIds) normalizeTile(g.level.tiles[id]!.word),
    };
    bool caught(RedHerring h) =>
        h.tiles.any((t) => wrongWords.contains(normalizeTile(t)));
    final herrings = [...g.level.redHerrings]
      ..sort((a, b) => (caught(b) ? 1 : 0) - (caught(a) ? 1 : 0));

    return ListView(
      key: const ValueKey('result'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        Panel(
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        won ? 'Solved!' : 'Answers revealed',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                          color: p.ink,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (won)
                      StarRow(stars: g.stars, size: 34)
                    else
                      Text(
                        '${g.solved.length}/4 groups found',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: p.ink,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      '${g.mistakes} ${g.mistakes == 1 ? 'mistake' : 'mistakes'}'
                      '${g.rescues > 0 ? ' · ${g.rescues} extra ${g.rescues == 1 ? 'life' : 'lives'} used' : ''}',
                      style: TextStyle(color: p.inkSoft),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: p.bg,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: p.border),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CoinIcon(size: 18, color: p.coin),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              coins > 0
                                  ? '+$coins coins'
                                  : won
                                  ? 'No coins (already rewarded)'
                                  : 'No coins this time',
                              key: const ValueKey('coins-earned'),
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: p.ink,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (result != null) ...[
                const SizedBox(width: 12),
                ShareGrid(rows: result.rows),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                key: const ValueKey('share'),
                onPressed: share == null
                    ? null
                    : () async {
                        await Clipboard.setData(ClipboardData(text: share));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Result copied — no spoilers included',
                              ),
                            ),
                          );
                        }
                      },
                icon: const Icon(Icons.ios_share_rounded),
                label: const Text('Share'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                key: const ValueKey('result-next'),
                onPressed: () => _next(context, c, next, won),
                child: Text(
                  next != null
                      ? 'Next level'
                      : active.isDaily || won
                      ? 'Done'
                      : 'Try again',
                ),
              ),
            ),
          ],
        ),
        if (herrings.isNotEmpty) const SectionLabel('Red herrings'),
        for (final h in herrings)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Panel(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.set_meal_rounded, color: p.accent, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            for (final t in h.tiles)
                              Text(
                                t,
                                style: TextStyle(
                                  fontFamily: kCondensed,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                  color: p.ink,
                                ),
                              ),
                            if (caught(h))
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1,
                                ),
                                decoration: BoxDecoration(
                                  color: tierColors[0],
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'You took the bait',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w800,
                                    color: tierInk,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          h.note,
                          style: TextStyle(
                            color: p.ink,
                            height: 1.3,
                            fontSize: 13.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        const SectionLabel('The four groups'),
        for (final cat in g.level.categories)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Stack(
              children: [
                GroupBanner(category: cat),
                if (!won && !g.solved.contains(cat.id))
                  Positioned(
                    right: 10,
                    bottom: 8,
                    child: Text(
                      'Missed',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: tierInk.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  void _next(BuildContext context, AppController c, Level? next, bool won) {
    final nav = Navigator.of(context);
    if (next != null || (!active.isDaily && !won)) {
      final a = c.openCampaign(next?.id ?? active.level.id);
      if (a != null) {
        nav.pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => BoardScreen(attemptId: a.attemptId),
          ),
        );
        return;
      }
    }
    nav.pop();
  }
}

/// Spoiler-free preview of the share grid as colored squares (one row per
/// evaluated guess, in selection order).
class ShareGrid extends StatelessWidget {
  const ShareGrid({super.key, required this.rows});

  final List<List<int>> rows;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${rows.length} guesses',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final r in rows.take(10))
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final t in r)
                    Container(
                      width: 13,
                      height: 13,
                      margin: const EdgeInsets.only(right: 3),
                      decoration: BoxDecoration(
                        color: tierColor(t),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
