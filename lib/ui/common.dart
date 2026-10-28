import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/content.dart';
import 'theme.dart';

/// Haptic feedback that respects the setting and never throws.
class Haptics {
  static void _run(bool enabled, Future<void> Function() f) {
    if (!enabled) return;
    f().catchError((Object _) {});
  }

  static void selection(bool on) => _run(on, HapticFeedback.selectionClick);
  static void solve(bool on) => _run(on, HapticFeedback.mediumImpact);
  static void mistake(bool on) => _run(on, HapticFeedback.heavyImpact);
  static void booster(bool on) => _run(on, HapticFeedback.lightImpact);
}

class CoinBadge extends StatelessWidget {
  const CoinBadge({super.key, required this.coins});

  final int coins;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      label: '$coins coins',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: p.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CoinIcon(size: 18, color: p.coin),
            const SizedBox(width: 6),
            Text(
              '$coins',
              key: const ValueKey('coin-balance'),
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 15,
                color: p.ink,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CoinIcon extends StatelessWidget {
  const CoinIcon({super.key, this.size = 16, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: color,
      border: Border.all(
        color: Colors.black.withValues(alpha: 0.18),
        width: 1.5,
      ),
    ),
    alignment: Alignment.center,
    child: Text(
      'L',
      style: TextStyle(
        fontFamily: kCondensed,
        fontWeight: FontWeight.w700,
        fontSize: size * 0.6,
        height: 1,
        color: const Color(0xFF3A2A00),
      ),
    ),
  );
}

class Hearts extends StatelessWidget {
  const Hearts({super.key, required this.lives, this.max = 4});

  final int lives;
  final int max;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      label: '$lives of $max lives left',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < max; i++)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: AnimatedSwitcher(
                duration: context.motion(250),
                transitionBuilder: (c, a) =>
                    ScaleTransition(scale: a, child: c),
                child: Icon(
                  i < lives ? Icons.favorite : Icons.favorite_border,
                  key: ValueKey(i < lives),
                  size: 22,
                  color: i < lives ? p.accent : p.inkSoft,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class StarRow extends StatelessWidget {
  const StarRow({super.key, required this.stars, this.size = 20});

  final int stars;
  final double size;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      label: '$stars of 3 stars',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            Icon(
              i < stars ? Icons.star_rounded : Icons.star_outline_rounded,
              size: size,
              color: i < stars ? p.coin : p.inkSoft,
            ),
        ],
      ),
    );
  }
}

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 20, bottom: 10),
    child: Semantics(
      header: true,
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontFamily: kCondensed,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.6,
          fontSize: 13,
          color: context.palette.inkSoft,
        ),
      ),
    ),
  );
}

/// A rounded surface card used across screens.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding, this.color});

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // A Material (not a DecoratedBox) so list tiles inside can show ink.
    return Material(
      color: color ?? p.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: p.border),
      ),
      child: Padding(
        padding: padding ?? const EdgeInsets.all(16),
        child: child,
      ),
    );
  }
}

/// A revealed group: tier color, title, the four words and the fact.
class GroupBanner extends StatelessWidget {
  const GroupBanner({super.key, required this.category, this.showFact = true});

  final Category category;
  final bool showFact;

  @override
  Widget build(BuildContext context) {
    final tier = category.tier;
    return Semantics(
      container: true,
      label:
          'Solved group, tier $tier ${tierNames[tier - 1]}: '
          '${category.title}. ${category.tiles.join(', ')}.'
          '${showFact ? ' ${category.triviaFact}' : ''}',
      excludeSemantics: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
        decoration: BoxDecoration(
          color: tierColor(tier),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    category.title,
                    style: const TextStyle(
                      fontFamily: kCondensed,
                      fontWeight: FontWeight.w700,
                      fontSize: 17,
                      letterSpacing: 0.6,
                      color: tierInk,
                    ),
                  ),
                ),
                TierChip(tier: tier),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              category.tiles.join(' · '),
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13.5,
                color: tierInk,
              ),
            ),
            if (showFact) ...[
              const SizedBox(height: 6),
              Text(
                category.triviaFact,
                style: const TextStyle(
                  fontSize: 13,
                  height: 1.3,
                  color: tierInk,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Small tier label so meaning never depends on color alone.
class TierChip extends StatelessWidget {
  const TierChip({super.key, required this.tier});

  final int tier;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
    decoration: BoxDecoration(
      color: Colors.white.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      'T$tier · ${tierNames[tier - 1]}',
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: tierInk,
      ),
    ),
  );
}

IconData packIcon(int index) => const [
  Icons.local_cafe_rounded,
  Icons.science_rounded,
  Icons.account_balance_rounded,
  Icons.movie_filter_rounded,
][index % 4];

Color packColor(int index) => tierColors[index % 4];

/// The LexiStack wordmark: three stacked tiles and the name.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      label: 'LexiStack',
      header: true,
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 34,
            height: 34,
            child: Stack(
              children: [
                for (var i = 0; i < 3; i++)
                  Positioned(
                    left: i * 4.0,
                    top: 12 - i * 6.0,
                    child: Container(
                      width: 24,
                      height: 16,
                      decoration: BoxDecoration(
                        color: tierColors[i],
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: p.ink, width: 1.5),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'LEXISTACK',
                style: TextStyle(
                  fontFamily: kSans,
                  fontWeight: FontWeight.w900,
                  fontSize: 22,
                  letterSpacing: 1.5,
                  color: p.ink,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
