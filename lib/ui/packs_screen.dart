import 'package:flutter/material.dart';

import '../core/content.dart';
import 'common.dart';
import 'home_screen.dart';
import 'theme.dart';

class PacksScreen extends StatefulWidget {
  const PacksScreen({super.key, required this.initialIndex});

  final int initialIndex;

  @override
  State<PacksScreen> createState() => _PacksScreenState();
}

class _PacksScreenState extends State<PacksScreen> {
  late int _index = widget.initialIndex;

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final p = context.palette;
    final packs = c.catalog.campaign;
    final pack = packs[_index.clamp(0, packs.length - 1)];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Campaign'),
        actions: [
          CoinBadge(coins: c.progress.coins),
          const SizedBox(width: 12),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            LayoutBuilder(
              builder: (context, box) {
                final w = (box.maxWidth - 10) / 2;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (var i = 0; i < packs.length; i++)
                      SizedBox(
                        width: w,
                        child: _PackTab(
                          index: i,
                          selected: i == _index,
                          onTap: () => setState(() => _index = i),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 18),
            Semantics(
              header: true,
              child: Text(
                pack.title,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: p.ink,
                ),
              ),
            ),
            Text(pack.description, style: TextStyle(color: p.inkSoft)),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, box) {
                final w = (box.maxWidth - 10) / 2;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final l in pack.levels)
                      SizedBox(
                        width: w,
                        child: _LevelCard(level: l),
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _PackTab extends StatelessWidget {
  const _PackTab({
    required this.index,
    required this.selected,
    required this.onTap,
  });

  final int index;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final p = context.palette;
    final pack = c.catalog.campaign[index];
    return Semantics(
      button: true,
      selected: selected,
      label:
          '${pack.title}, ${c.wonInPack(pack)} of ${pack.levels.length} levels won',
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: selected ? packColor(index) : p.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 60),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: selected ? tierInk : p.border,
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  packIcon(index),
                  color: selected ? tierInk : p.ink,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        pack.title,
                        maxLines: 2,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                          height: 1.15,
                          color: selected ? tierInk : p.ink,
                        ),
                      ),
                      Text(
                        '${c.wonInPack(pack)}/${pack.levels.length} won',
                        style: TextStyle(
                          fontSize: 12,
                          color: selected ? tierInk : p.inkSoft,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LevelCard extends StatelessWidget {
  const _LevelCard({required this.level});

  final Level level;

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final p = context.palette;
    final unlocked = c.isUnlocked(level);
    final won = c.isWon(level.id);
    final inProgress = c.hasUnfinished(level.id);
    final stars = c.bestStars(level.id);
    final status = !unlocked
        ? 'Locked'
        : inProgress
        ? 'In progress'
        : won
        ? 'Replay'
        : 'Play';
    return Semantics(
      button: true,
      enabled: unlocked,
      label:
          'Level ${level.number}, ${unlocked ? level.title : 'locked'}'
          '${won ? ', best $stars of 3 stars' : ''}, $status',
      excludeSemantics: true,
      onTap: () => _open(context),
      child: Material(
        key: ValueKey('level-${level.id}'),
        color: unlocked ? p.surface : p.surfaceAlt.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _open(context),
          child: Container(
            constraints: const BoxConstraints(minHeight: 92),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: inProgress ? p.accent : p.border,
                width: inProgress ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '${level.number}'.padLeft(2, '0'),
                      style: TextStyle(
                        fontFamily: kCondensed,
                        fontWeight: FontWeight.w700,
                        fontSize: 22,
                        color: unlocked ? p.ink : p.inkSoft,
                      ),
                    ),
                    const Spacer(),
                    if (!unlocked)
                      Icon(Icons.lock_rounded, size: 18, color: p.inkSoft)
                    else if (won)
                      StarRow(stars: stars, size: 16),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  unlocked ? level.title : 'Win level ${level.number - 1}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: unlocked ? p.ink : p.inkSoft,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (won && !inProgress)
                      Icon(Icons.replay_rounded, size: 14, color: p.inkSoft),
                    if (won && !inProgress) const SizedBox(width: 3),
                    Text(
                      status,
                      style: TextStyle(
                        fontSize: 12,
                        color: inProgress ? p.accent : p.inkSoft,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _open(BuildContext context) {
    final c = AppScope.of(context);
    if (!c.isUnlocked(level)) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Win level ${level.number - 1} of this pack to unlock it.',
          ),
        ),
      );
      return;
    }
    if (c.isWon(level.id) && !c.hasUnfinished(level.id)) {
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        builder: (sheet) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Replay “${level.title}”?',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Text('Best so far: '),
                    StarRow(stars: c.bestStars(level.id), size: 18),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  c.progress.practicePaid.contains(level.id)
                      ? 'Practice coins for this level were already claimed. Your best stars can still improve.'
                      : 'Your first replay win pays 5 practice coins. Your best stars can improve but never drop.',
                  style: TextStyle(color: sheet.palette.inkSoft),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  key: const ValueKey('replay-confirm'),
                  onPressed: () {
                    Navigator.of(sheet).pop();
                    openBoard(context, c.openCampaign(level.id));
                  },
                  child: const Text('Replay level'),
                ),
              ],
            ),
          ),
        ),
      );
      return;
    }
    openBoard(context, c.openCampaign(level.id));
  }
}
