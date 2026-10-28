import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/controller.dart';
import '../core/content.dart';
import '../core/game.dart';
import 'common.dart';
import 'result_view.dart';
import 'theme.dart';

enum _Tone { info, success, warning, danger }

class BoardScreen extends StatefulWidget {
  const BoardScreen({super.key, required this.attemptId});

  /// The attempt this screen shows; used to release it on close.
  final String attemptId;

  @override
  State<BoardScreen> createState() => _BoardScreenState();
}

class _BoardScreenState extends State<BoardScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );
  late AppController _controller;

  /// The game this screen was opened for. It keeps showing a finished result
  /// even after the controller moves on (e.g. while "Next level" animates in).
  ActiveGame? _game;
  String? _message;
  _Tone _tone = _Tone.info;
  Timer? _messageTimer;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller = AppScope.of(context);
    final a = _controller.active;
    if (_game == null && a?.attemptId == widget.attemptId) _game = a;
  }

  @override
  void dispose() {
    _controller.closeGame(widget.attemptId);
    _messageTimer?.cancel();
    _shake.dispose();
    super.dispose();
  }

  void _say(String text, _Tone tone) {
    _messageTimer?.cancel();
    setState(() {
      _message = text;
      _tone = tone;
    });
    _messageTimer = Timer(const Duration(milliseconds: 2200), () {
      if (mounted) setState(() => _message = null);
    });
  }

  bool get _haptics => _controller.progress.haptics;

  void _tap(String id) {
    if (_controller.tap(id)) Haptics.selection(_haptics);
  }

  void _drop(String source, String target) {
    if (_controller.dragOnto(source, target)) Haptics.selection(_haptics);
  }

  void _dropOnTray(String source) {
    if (_controller.dropOnTray(source)) Haptics.selection(_haptics);
  }

  void _submit() {
    final g = _controller.active?.game;
    if (g == null) return;
    if (!g.canSubmit) {
      _say('Select four tiles to submit (${g.selection.length}/4)', _Tone.info);
      return;
    }
    final r = _controller.submit();
    switch (r) {
      case SubmitSolved(:final category, :final victory):
        Haptics.solve(_haptics);
        _say(
          victory ? 'All four groups found!' : 'Solved: ${category.title}',
          _Tone.success,
        );
      case SubmitMismatch(:final isOneAway, :final pendingLoss):
        Haptics.mistake(_haptics);
        if (!context.reduceMotion) _shake.forward(from: 0);
        final lives = _controller.active?.game.lives ?? 0;
        _say(
          pendingLoss
              ? 'Out of lives'
              : isOneAway
              ? 'One Away! $lives ${lives == 1 ? 'life' : 'lives'} left'
              : 'Not a group. $lives ${lives == 1 ? 'life' : 'lives'} left',
          isOneAway ? _Tone.warning : _Tone.danger,
        );
      case SubmitAlreadyGuessed():
        _say('Already guessed! No life lost.', _Tone.info);
      case SubmitRejected(:final reason):
        _say(reason, _Tone.info);
    }
  }

  void _booster(Booster b) {
    final blocker = _controller.boosterBlocker(b);
    if (blocker != null) {
      _say('${_boosterName(b)}: $blocker', _Tone.info);
      return;
    }
    final g = _controller.active!.game;
    final pairsBefore = g.pairs.length;
    if (!_controller.useBooster(b)) return;
    Haptics.booster(_haptics);
    switch (b) {
      case Booster.pairMagnet:
        final pair = g.pairs.values.elementAt(pairsBefore);
        final words = pair.map((id) => g.level.tiles[id]!.word).join(' + ');
        _say('Pair Magnet: $words belong together', _Tone.success);
      case Booster.categoryPeek:
        _say(
          'Category Peek: ${g.level.categoryById(g.peeked.last)!.title}',
          _Tone.success,
        );
      case Booster.extraLife:
        _say(
          'Extra Life! ${g.lives} ${g.lives == 1 ? 'life' : 'lives'} now',
          _Tone.success,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final a = _game;
    if (a == null || (!identical(c.active, a) && !a.game.isFinal)) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'This puzzle is no longer available.\n'
                  'A new day has started or progress was reset.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Back'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final g = a.game;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(a.level.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(
              a.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
                color: context.palette.inkSoft,
              ),
            ),
          ],
        ),
        actions: [
          CoinBadge(coins: c.progress.coins),
          const SizedBox(width: 12),
        ],
      ),
      body: SafeArea(
        top: false,
        child: g.isFinal
            ? ResultView(active: a)
            : Column(
                children: [
                  if (c.storageFailed) const StorageWarning(),
                  _StatusRow(game: g),
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(child: _boardScroll(g)),
                        Positioned(
                          left: 16,
                          right: 16,
                          bottom: 8,
                          child: _Toast(message: _message, tone: _tone),
                        ),
                      ],
                    ),
                  ),
                  if (g.status == GameStatus.lostPendingDecision)
                    PendingLossPanel(onMessage: (m) => _say(m, _Tone.info))
                  else
                    _Dock(
                      game: g,
                      onDeselect: () => c.deselectAll(),
                      onShuffle: () {
                        if (c.shuffle()) Haptics.selection(_haptics);
                      },
                      onSubmit: _submit,
                      onTrayDrop: _dropOnTray,
                      onTrayTap: _tap,
                      onBooster: _booster,
                    ),
                ],
              ),
      ),
    );
  }

  Widget _boardScroll(PuzzleGame g) {
    final unsolved = g.unsolvedCategories;
    final peeked = unsolved.where((c) => g.peeked.contains(c.id)).toList();
    final hidden = unsolved.length - peeked.length;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 64),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final cat in g.solvedCategories)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _SolveReveal(
                key: ValueKey(cat.id),
                child: GroupBanner(category: cat),
              ),
            ),
          if (unsolved.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _SlotGrid(peeked: peeked, hidden: hidden),
            ),
          AnimatedBuilder(
            animation: _shake,
            builder: (context, _) {
              final t = _shake.value;
              final dx = _shake.isAnimating
                  ? math.sin(t * math.pi * 6) * 7 * (1 - t)
                  : 0.0;
              return _TileGrid(
                game: g,
                shakeOffset: dx,
                onTap: _tap,
                onDrop: _drop,
              );
            },
          ),
        ],
      ),
    );
  }
}

String _boosterName(Booster b) => switch (b) {
  Booster.pairMagnet => 'Pair Magnet',
  Booster.categoryPeek => 'Category Peek',
  Booster.extraLife => 'Extra Life',
};

IconData _boosterIcon(Booster b) => switch (b) {
  Booster.pairMagnet => Icons.link_rounded,
  Booster.categoryPeek => Icons.visibility_rounded,
  Booster.extraLife => Icons.favorite_rounded,
};

class StorageWarning extends StatelessWidget {
  const StorageWarning({super.key});

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Container(
      width: double.infinity,
      color: context.palette.accent.withValues(alpha: 0.15),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Text(
        'Progress could not be saved on this device. It will retry on your next move.',
        style: TextStyle(fontSize: 12.5, color: context.palette.ink),
      ),
    ),
  );
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.game});

  final PuzzleGame game;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        children: [
          Hearts(lives: game.lives),
          const Spacer(),
          if (game.combo >= 2)
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: Text(
                'Streak ×${game.combo}',
                style: TextStyle(fontWeight: FontWeight.w700, color: p.ink),
              ),
            ),
          Text(
            '${game.mistakes} ${game.mistakes == 1 ? 'mistake' : 'mistakes'}',
            style: TextStyle(color: p.inkSoft, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

/// Placeholder slots for groups not yet found; peeked titles show here.
class _SlotGrid extends StatelessWidget {
  const _SlotGrid({required this.peeked, required this.hidden});

  final List<Category> peeked;
  final int hidden;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    Widget slot(Widget child, {Color? color, String? label}) => Semantics(
      label: label,
      excludeSemantics: label != null,
      child: Container(
        constraints: const BoxConstraints(minHeight: 34),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color ?? Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: color == null ? p.border : Colors.transparent,
            width: 1.5,
          ),
        ),
        alignment: Alignment.centerLeft,
        child: child,
      ),
    );
    final slots = <Widget>[
      for (final c in peeked)
        slot(
          Row(
            children: [
              const Icon(Icons.visibility_rounded, size: 15, color: tierInk),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  c.title,
                  maxLines: 2,
                  style: const TextStyle(
                    fontFamily: kCondensed,
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: tierInk,
                  ),
                ),
              ),
            ],
          ),
          color: tierColor(c.tier).withValues(alpha: 0.85),
          label: 'Peeked group title: ${c.title}',
        ),
      for (var i = 0; i < hidden; i++)
        slot(
          Text(
            'Hidden group',
            style: TextStyle(
              fontSize: 12.5,
              color: p.inkSoft,
              fontWeight: FontWeight.w500,
            ),
          ),
          label: 'Hidden group',
        ),
    ];
    return LayoutBuilder(
      builder: (context, c) {
        final w = (c.maxWidth - 8) / 2;
        return Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [for (final s in slots) SizedBox(width: w, child: s)],
        );
      },
    );
  }
}

class _SolveReveal extends StatelessWidget {
  const _SolveReveal({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: context.motion(350),
      curve: Curves.easeOutBack,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0, 1).toDouble(),
        child: Transform.scale(
          scale: 0.85 + 0.15 * t,
          alignment: Alignment.bottomCenter,
          child: child,
        ),
      ),
      child: child,
    );
  }
}

class _TileGrid extends StatelessWidget {
  const _TileGrid({
    required this.game,
    required this.shakeOffset,
    required this.onTap,
    required this.onDrop,
  });

  final PuzzleGame game;
  final double shakeOffset;
  final void Function(String id) onTap;
  final void Function(String source, String target) onDrop;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        const gap = 8.0;
        final w = (c.maxWidth - gap * 3) / 4;
        final h = (w * 0.86).clamp(52.0, 84.0);
        final font = (w * 0.2).clamp(12.0, 17.0);
        final order = game.order;
        return Semantics(
          label: 'Board, ${order.length} tiles',
          container: true,
          child: Column(
            children: [
              for (var r = 0; r * 4 < order.length; r++)
                Padding(
                  padding: EdgeInsets.only(
                    bottom: r * 4 + 4 < order.length ? gap : 0,
                  ),
                  child: Row(
                    children: [
                      for (var i = r * 4; i < r * 4 + 4; i++) ...[
                        if (i > r * 4) const SizedBox(width: gap),
                        SizedBox(
                          width: w,
                          height: h,
                          child: i < order.length
                              ? _buildTile(order[i], w, h, font)
                              : null,
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTile(String id, double w, double h, double font) {
    final selected = game.selection.contains(id);
    final tile = TileCard(
      key: ValueKey('tile-$id'),
      id: id,
      word: game.level.tiles[id]!.word,
      selected: selected,
      pair: _pairOf(id),
      width: w,
      height: h,
      fontSize: font,
      onTap: () => onTap(id),
      onDropped: (source) => onDrop(source, id),
    );
    return selected && shakeOffset != 0
        ? Transform.translate(offset: Offset(shakeOffset, 0), child: tile)
        : tile;
  }

  int? _pairOf(String id) {
    var n = 0;
    for (final e in game.pairs.entries) {
      n++;
      if (!game.solved.contains(e.key) && e.value.contains(id)) return n;
    }
    return null;
  }
}

/// A word tile: tap to toggle, long-press and drag onto a tile or the tray.
class TileCard extends StatefulWidget {
  const TileCard({
    super.key,
    required this.id,
    required this.word,
    required this.selected,
    required this.width,
    required this.height,
    required this.fontSize,
    required this.onTap,
    required this.onDropped,
    this.pair,
  });

  final String id;
  final String word;
  final bool selected;
  final int? pair;
  final double width;
  final double height;
  final double fontSize;
  final VoidCallback onTap;
  final void Function(String source) onDropped;

  @override
  State<TileCard> createState() => _TileCardState();
}

class _TileCardState extends State<TileCard> {
  bool _pressed = false;

  Widget _face(
    BuildContext context, {
    bool hover = false,
    bool lifted = false,
  }) {
    final p = context.palette;
    final selected = widget.selected;
    final fg = selected ? p.tileSelectedInk : p.tileInk;
    return AnimatedContainer(
      duration: context.motion(120),
      curve: Curves.easeOut,
      width: widget.width,
      height: widget.height,
      transform: Matrix4.translationValues(0, selected ? -2 : 0, 0),
      decoration: BoxDecoration(
        color: selected ? p.tileSelected : p.tile,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: hover
              ? p.accent
              : widget.pair != null
              ? tierColors[(widget.pair! - 1) % 4]
              : p.border,
          width: hover || widget.pair != null ? 2.5 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: p.tileEdge,
            offset: Offset(0, selected || lifted ? 5 : 3),
          ),
          if (lifted)
            const BoxShadow(
              color: Color(0x40000000),
              blurRadius: 16,
              offset: Offset(0, 10),
            ),
        ],
      ),
      child: Stack(
        children: [
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 4),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  widget.word.replaceAll(' ', '\n'),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  softWrap: false,
                  style: TextStyle(
                    fontFamily: kCondensed,
                    fontWeight: FontWeight.w700,
                    fontSize: widget.fontSize,
                    height: 1.05,
                    letterSpacing: 0.3,
                    color: fg,
                  ),
                ),
              ),
            ),
          ),
          if (widget.pair != null)
            Positioned(
              top: 3,
              right: 3,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: tierColors[(widget.pair! - 1) % 4],
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.link_rounded, size: 10, color: tierInk),
                    Text(
                      '${widget.pair}',
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w800,
                        color: tierInk,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final label =
        '${widget.word}${widget.pair != null ? ', linked pair ${widget.pair}' : ''}';
    return Semantics(
      button: true,
      selected: widget.selected,
      label: label,
      hint: widget.selected
          ? 'Selected. Double tap to deselect.'
          : 'Double tap to select.',
      onTap: widget.onTap,
      excludeSemantics: true,
      child: DragTarget<String>(
        onWillAcceptWithDetails: (d) => d.data != widget.id,
        onAcceptWithDetails: (d) => widget.onDropped(d.data),
        builder: (context, candidates, _) => LongPressDraggable<String>(
          data: widget.id,
          delay: const Duration(milliseconds: 250),
          hapticFeedbackOnStart: false,
          feedback: Material(
            type: MaterialType.transparency,
            child: Transform.scale(
              scale: 1.06,
              child: _face(context, lifted: true),
            ),
          ),
          childWhenDragging: Opacity(opacity: 0.35, child: _face(context)),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => setState(() => _pressed = true),
            onTapUp: (_) => setState(() => _pressed = false),
            onTapCancel: () => setState(() => _pressed = false),
            onTap: widget.onTap,
            child: AnimatedScale(
              scale: _pressed ? 0.93 : (widget.selected ? 1.03 : 1.0),
              duration: context.motion(120),
              curve: Curves.easeOut,
              child: _face(context, hover: candidates.isNotEmpty),
            ),
          ),
        ),
      ),
    );
  }
}

class _Toast extends StatelessWidget {
  const _Toast({required this.message, required this.tone});

  final String? message;
  final _Tone tone;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final (bg, fg) = switch (tone) {
      _Tone.success => (tierColors[1], tierInk),
      _Tone.warning => (tierColors[0], tierInk),
      _Tone.danger => (p.primary, p.onPrimary),
      _Tone.info => (p.primary, p.onPrimary),
    };
    return IgnorePointer(
      child: AnimatedSwitcher(
        duration: context.motion(180),
        transitionBuilder: (c, a) => FadeTransition(
          opacity: a,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, 0.3),
              end: Offset.zero,
            ).animate(a),
            child: c,
          ),
        ),
        child: message == null
            ? const SizedBox.shrink()
            : Center(
                key: ValueKey(message),
                child: Semantics(
                  liveRegion: true,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x33000000),
                          blurRadius: 12,
                          offset: Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Text(
                      message!,
                      key: const ValueKey('feedback'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: fg,
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _Dock extends StatelessWidget {
  const _Dock({
    required this.game,
    required this.onDeselect,
    required this.onShuffle,
    required this.onSubmit,
    required this.onTrayDrop,
    required this.onTrayTap,
    required this.onBooster,
  });

  final PuzzleGame game;
  final VoidCallback onDeselect;
  final VoidCallback onShuffle;
  final VoidCallback onSubmit;
  final void Function(String id) onTrayDrop;
  final void Function(String id) onTrayTap;
  final void Function(Booster b) onBooster;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final n = game.selection.length;
    return Container(
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.border)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Tray(game: game, onDrop: onTrayDrop, onTap: onTrayTap),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onShuffle,
                  style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                  child: const _IconLabel(
                    icon: Icons.shuffle_rounded,
                    label: 'Shuffle',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Semantics(
                  hint: n == 0 ? 'Nothing selected' : null,
                  child: OutlinedButton(
                    onPressed: n == 0 ? null : onDeselect,
                    style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
                    child: const _IconLabel(
                      icon: Icons.close_rounded,
                      label: 'Deselect',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 1,
                child: Semantics(
                  hint: game.canSubmit
                      ? null
                      : 'Select four tiles first, $n of 4 selected',
                  child: GestureDetector(
                    // Explains why Submit is disabled when tapped.
                    onTap: game.canSubmit ? null : onSubmit,
                    child: FilledButton(
                      key: const ValueKey('submit'),
                      onPressed: game.canSubmit ? onSubmit : null,
                      style: FilledButton.styleFrom(padding: EdgeInsets.zero),
                      child: const _IconLabel(
                        icon: Icons.check_rounded,
                        label: 'Submit',
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (final b in Booster.values) ...[
                if (b != Booster.pairMagnet) const SizedBox(width: 8),
                Expanded(
                  child: _BoosterButton(booster: b, onTap: () => onBooster(b)),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _IconLabel extends StatelessWidget {
  const _IconLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, size: 18), const SizedBox(width: 4), Text(label)],
      ),
    ),
  );
}

class _Tray extends StatelessWidget {
  const _Tray({required this.game, required this.onDrop, required this.onTap});

  final PuzzleGame game;
  final void Function(String id) onDrop;
  final void Function(String id) onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final sel = game.selection;
    return DragTarget<String>(
      onWillAcceptWithDetails: (d) => !sel.contains(d.data) && sel.length < 4,
      onAcceptWithDetails: (d) => onDrop(d.data),
      builder: (context, candidates, _) => Semantics(
        container: true,
        label: 'Selection tray, ${sel.length} of 4 selected',
        child: Container(
          key: const ValueKey('tray'),
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: candidates.isNotEmpty
                ? p.accent.withValues(alpha: 0.12)
                : p.bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: candidates.isNotEmpty ? p.accent : p.border,
              width: candidates.isNotEmpty ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              for (var i = 0; i < 4; i++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(3),
                    child: i < sel.length
                        ? Semantics(
                            button: true,
                            label:
                                'Selected ${game.level.tiles[sel[i]]!.word}, double tap to remove',
                            excludeSemantics: true,
                            onTap: () => onTap(sel[i]),
                            child: GestureDetector(
                              onTap: () => onTap(sel[i]),
                              child: Container(
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: p.tileSelected,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                ),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    game.level.tiles[sel[i]]!.word,
                                    style: TextStyle(
                                      fontFamily: kCondensed,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12,
                                      color: p.tileSelectedInk,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          )
                        : ExcludeSemantics(
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: p.border),
                              ),
                            ),
                          ),
                  ),
                ),
              ExcludeSemantics(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Text(
                    '${sel.length}/4',
                    key: const ValueKey('selection-count'),
                    style: TextStyle(fontWeight: FontWeight.w800, color: p.ink),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BoosterButton extends StatelessWidget {
  const _BoosterButton({required this.booster, required this.onTap});

  final Booster booster;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = AppScope.of(context);
    final p = context.palette;
    final blocker = c.boosterBlocker(booster);
    final enabled = blocker == null;
    final name = _boosterName(booster);
    final cost = boosterCost(booster);
    return Semantics(
      button: true,
      enabled: enabled,
      label: '$name, $cost coins${enabled ? '' : ', unavailable: $blocker'}',
      excludeSemantics: true,
      onTap: onTap,
      child: Tooltip(
        message: enabled ? '$name · $cost coins' : blocker,
        child: Material(
          key: ValueKey('booster-${booster.name}'),
          color: enabled ? p.bg : p.surfaceAlt.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 52),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: p.border),
              ),
              child: Opacity(
                opacity: enabled ? 1 : 0.55,
                child: Row(
                  children: [
                    Icon(
                      _boosterIcon(booster),
                      size: 20,
                      color: enabled ? p.accent : p.inkSoft,
                    ),
                    const SizedBox(width: 5),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              name,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12.5,
                                color: p.ink,
                              ),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CoinIcon(size: 12, color: p.coin),
                              const SizedBox(width: 3),
                              Text(
                                '$cost',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: p.inkSoft,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
