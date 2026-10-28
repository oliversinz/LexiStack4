import 'package:flutter/material.dart';

import 'common.dart';
import 'theme.dart';

class StatsScreen extends StatelessWidget {
  const StatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final s = c.stats;
    final p = context.palette;
    final maxBar = s.distribution.fold(1, (m, v) => v > m ? v : m);
    Widget tile(String value, String label) => Expanded(
      child: Panel(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: p.ink,
              ),
            ),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: p.inkSoft),
            ),
          ],
        ),
      ),
    );
    const labels = ['0', '1', '2', '3', '4+'];
    return Scaffold(
      appBar: AppBar(title: const Text('Statistics')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            Row(
              children: [
                tile('${s.gamesPlayed}', 'Games played'),
                const SizedBox(width: 10),
                tile('${(s.winRate * 100).round()}%', 'Win rate'),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                tile('${s.perfectWins}', 'Perfect wins\n(0 mistakes)'),
                const SizedBox(width: 10),
                tile('${s.wins}', 'Wins'),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                tile('${s.currentStreak}', 'Daily streak'),
                const SizedBox(width: 10),
                tile('${s.bestStreak}', 'Best daily streak'),
              ],
            ),
            const SectionLabel('Mistakes per win'),
            Panel(
              child: Column(
                children: [
                  for (var i = 0; i < 5; i++)
                    Semantics(
                      label:
                          '${s.distribution[i]} wins with ${labels[i]} mistakes',
                      excludeSemantics: true,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 28,
                              child: Text(
                                labels[i],
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: p.ink,
                                ),
                              ),
                            ),
                            Expanded(
                              child: LayoutBuilder(
                                builder: (context, box) {
                                  final v = s.distribution[i];
                                  final w =
                                      28 + (box.maxWidth - 28) * v / maxBar;
                                  return Align(
                                    alignment: Alignment.centerLeft,
                                    child: Container(
                                      width: w,
                                      height: 26,
                                      alignment: Alignment.centerRight,
                                      padding: const EdgeInsets.only(right: 8),
                                      decoration: BoxDecoration(
                                        color: v == 0
                                            ? p.surfaceAlt
                                            : tierColor(i.clamp(0, 3) + 1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '$v',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: tierInk,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Only finished games count. An unfinished board or a loss still '
              'waiting for your decision is not included.',
              style: TextStyle(fontSize: 12.5, color: p.inkSoft),
            ),
          ],
        ),
      ),
    );
  }
}
