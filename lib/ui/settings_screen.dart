import 'package:flutter/material.dart';

import 'common.dart';
import 'theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            const SectionLabel('Theme'),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'system',
                  label: Text('System'),
                  icon: Icon(Icons.brightness_auto_rounded),
                ),
                ButtonSegment(
                  value: 'light',
                  label: Text('Light'),
                  icon: Icon(Icons.light_mode_rounded),
                ),
                ButtonSegment(
                  value: 'dark',
                  label: Text('Dark'),
                  icon: Icon(Icons.dark_mode_rounded),
                ),
              ],
              selected: {c.progress.theme},
              showSelectedIcon: false,
              onSelectionChanged: (s) => c.setTheme(s.first),
            ),
            const SectionLabel('Feedback'),
            Panel(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: SwitchListTile(
                key: const ValueKey('haptics-switch'),
                title: const Text('Haptic feedback'),
                subtitle: const Text(
                  'Vibration on selection, solves, mistakes and boosters',
                ),
                value: c.progress.haptics,
                onChanged: c.setHaptics,
              ),
            ),
            const SectionLabel('Progress'),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Progress is stored only on this device. Resetting restores '
                    '150 coins and clears stars, statistics, streaks and saved games.',
                    style: TextStyle(color: p.inkSoft, height: 1.3),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const ValueKey('reset-progress'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: p.accent,
                      side: BorderSide(color: p.accent, width: 1.5),
                    ),
                    onPressed: () => _confirmReset(context),
                    icon: const Icon(Icons.restart_alt_rounded),
                    label: const Text('Reset progress to default'),
                  ),
                ],
              ),
            ),
            const SectionLabel('About'),
            Panel(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ListTile(
                title: const Text('Licenses'),
                subtitle: const Text(
                  'Roboto fonts (Apache 2.0) and Flutter packages',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => showLicensePage(
                  context: context,
                  applicationName: 'LexiStack',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmReset(BuildContext context) async {
    final c = AppScope.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('Reset all progress?'),
        content: const Text(
          'Coins, stars, statistics, daily streaks and unfinished games will be '
          'erased. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialog).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('reset-confirm'),
            onPressed: () => Navigator.of(dialog).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (ok == true) {
      c.resetProgress();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Progress reset. Fresh start with 150 coins.'),
          ),
        );
      }
    }
  }
}
