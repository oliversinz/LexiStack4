import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/controller.dart';
import '../core/content.dart';
import 'board_screen.dart';
import 'common.dart';
import 'packs_screen.dart';
import 'settings_screen.dart';
import 'stats_screen.dart';
import 'theme.dart';

/// Opens the board for [a] (if any) on top of the current route.
void openBoard(BuildContext context, ActiveGame? a) {
  if (a == null) return;
  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => BoardScreen(attemptId: a.attemptId),
    ),
  );
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final c = AppScope.of(context);
      final notice = c.loadNotice;
      if (notice != null) {
        c.loadNotice = null;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(notice)));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Wordmark(),
                  ),
                ),
                CoinBadge(coins: c.progress.coins),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Settings',
                  icon: const Icon(Icons.settings_rounded),
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SettingsScreen(),
                    ),
                  ),
                ),
              ],
            ),
            if (c.storageFailed) ...[
              const SizedBox(height: 8),
              const StorageWarning(),
            ],
            const SizedBox(height: 16),
            const _ContinueCard(),
            const SectionLabel('Daily puzzle'),
            const _DailyCard(),
            const SectionLabel('Your stats'),
            const _StatsStrip(),
            const SectionLabel('Campaign packs'),
            for (var i = 0; i < c.catalog.campaign.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _PackCard(index: i),
              ),
          ],
        ),
      ),
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard();

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final p = context.palette;
    final level = c.continueCampaignLevel();
    final pack = level == null ? null : c.catalog.packOfLevel(level.id);
    final resuming = level != null && c.hasUnfinished(level.id);
    final total = c.catalog.campaignLevels.length;
    final won = c.catalog.campaignLevels.where((l) => c.isWon(l.id)).length;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: p.primary,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'CAMPAIGN · $won/$total WON',
            style: TextStyle(
              fontFamily: kCondensed,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.4,
              fontSize: 13,
              color: p.onPrimary.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            level == null ? 'Every level won!' : level.title,
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: p.onPrimary,
            ),
          ),
          Text(
            level == null
                ? 'Replay any level to improve your stars.'
                : '${pack!.title} · Level ${level.number}'
                      '${resuming ? ' · in progress' : ''}',
            style: TextStyle(color: p.onPrimary.withValues(alpha: 0.85)),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const ValueKey('continue-campaign'),
              style: FilledButton.styleFrom(
                backgroundColor: tierColors[0],
                foregroundColor: tierInk,
              ),
              onPressed: () {
                if (level == null) {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const PacksScreen(initialIndex: 0),
                    ),
                  );
                } else {
                  openBoard(context, c.openCampaign(level.id));
                }
              },
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(
                level == null
                    ? 'Choose a pack'
                    : resuming
                    ? 'Resume'
                    : 'Continue Campaign',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DailyCard extends StatelessWidget {
  const _DailyCard();

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final p = context.palette;
    final status = c.dailyStatus;
    final result = c.todaysDailyResult;
    final streak = c.dailyStreak;
    final (statusText, action) = switch (status) {
      DailyStatus.unavailable => ('No daily boards installed', null),
      DailyStatus.notStarted => ('A fresh board is waiting', 'Play today'),
      DailyStatus.inProgress => ('In progress', 'Resume'),
      DailyStatus.won => (
        'Solved with ${result?.mistakes ?? 0} '
            '${result?.mistakes == 1 ? 'mistake' : 'mistakes'}',
        'View result',
      ),
      DailyStatus.lost => ('Not solved today', 'View result'),
    };
    final boardAvailable =
        status == DailyStatus.notStarted ||
        status == DailyStatus.inProgress ||
        c.progress.daily?.date == c.today.toString();
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: tierColors[2],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.today_rounded, color: tierInk),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Daily Stack · ${c.today}',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: p.ink,
                      ),
                    ),
                    Text(
                      statusText,
                      key: const ValueKey('daily-status'),
                      style: TextStyle(color: p.inkSoft),
                    ),
                  ],
                ),
              ),
              if (status == DailyStatus.won && result != null)
                StarRow(stars: result.stars, size: 18),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                Icons.local_fire_department_rounded,
                color: p.accent,
                size: 20,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '$streak-day streak · best ${c.progress.bestDailyStreak}',
                  style: TextStyle(fontWeight: FontWeight.w600, color: p.ink),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${c.catalog.dailyPool.length} handcrafted daily boards rotate, so a '
            'board returns every ${c.catalog.dailyPool.length} days.',
            style: TextStyle(fontSize: 12, color: p.inkSoft),
          ),
          if (action != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (boardAvailable)
                  Expanded(
                    child: FilledButton(
                      key: const ValueKey('daily-play'),
                      onPressed: () => openBoard(context, c.openDaily()),
                      child: Text(action),
                    ),
                  ),
                if (result != null) ...[
                  if (boardAvailable) const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const ValueKey('daily-share'),
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: result.shareText),
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Daily result copied'),
                            ),
                          );
                        }
                      },
                      icon: const Icon(Icons.ios_share_rounded),
                      label: const Text('Share'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StatsStrip extends StatelessWidget {
  const _StatsStrip();

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final s = c.stats;
    final p = context.palette;
    Widget cell(String value, String label) => Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: p.ink,
            ),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: p.inkSoft),
          ),
        ],
      ),
    );
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => const StatsScreen())),
        child: Panel(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          child: Semantics(
            button: true,
            hint: 'Open statistics',
            child: Row(
              children: [
                cell('${s.gamesPlayed}', 'Played'),
                cell('${(s.winRate * 100).round()}%', 'Win rate'),
                cell('${s.perfectWins}', 'Perfect'),
                cell('${s.bestStreak}', 'Best streak'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PackCard extends StatelessWidget {
  const _PackCard({required this.index});

  final int index;

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final p = context.palette;
    final Pack pack = c.catalog.campaign[index];
    final won = c.wonInPack(pack);
    final stars = pack.levels.fold(0, (s, l) => s + c.bestStars(l.id));
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PacksScreen(initialIndex: index),
          ),
        ),
        child: Panel(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: packColor(index),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(packIcon(index), color: tierInk),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      pack.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: p.ink,
                      ),
                    ),
                    Text(
                      pack.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: p.inkSoft),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$won/${pack.levels.length}',
                    style: TextStyle(fontWeight: FontWeight.w800, color: p.ink),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.star_rounded, size: 16, color: p.coin),
                      Text(
                        '$stars',
                        style: TextStyle(fontSize: 12.5, color: p.inkSoft),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
