import 'package:flutter/material.dart';

import '../app/controller.dart';
import 'home_screen.dart';
import 'theme.dart';

class LexiStackApp extends StatelessWidget {
  const LexiStackApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: controller,
      child: ListenableBuilder(
        listenable: controller,
        builder: (context, _) => MaterialApp(
          title: 'LexiStack',
          debugShowCheckedModeBanner: false,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: switch (controller.progress.theme) {
            'light' => ThemeMode.light,
            'dark' => ThemeMode.dark,
            _ => ThemeMode.system,
          },
          builder: (context, child) => DesktopFrame(child: child!),
          home: const HomeScreen(),
        ),
      ),
    );
  }
}

/// On wide viewports, centers the mobile interface (max 460 px) on a
/// decorated backdrop; on phones it is a pass-through.
class DesktopFrame extends StatelessWidget {
  const DesktopFrame({super.key, required this.child});

  static const breakpoint = 520.0;
  static const maxWidth = 460.0;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        if (c.maxWidth <= breakpoint) return child;
        final p = context.palette;
        final mq = MediaQuery.of(context);
        final height = (c.maxHeight - 48).clamp(480.0, 940.0).toDouble();
        final size = Size(maxWidth, height.clamp(0, c.maxHeight).toDouble());
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: Theme.of(context).brightness == Brightness.light
                  ? const [
                      Color(0xFF2B2442),
                      Color(0xFF4A3B6B),
                      Color(0xFF7A4E6E),
                    ]
                  : const [
                      Color(0xFF07060B),
                      Color(0xFF1A1428),
                      Color(0xFF2B1B33),
                    ],
            ),
          ),
          child: Stack(
            children: [
              const Positioned.fill(child: _BackdropTiles()),
              Center(
                child: Container(
                  width: size.width,
                  height: size.height,
                  decoration: BoxDecoration(
                    color: p.bg,
                    borderRadius: BorderRadius.circular(32),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x66000000),
                        blurRadius: 40,
                        offset: Offset(0, 18),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: MediaQuery(
                    data: mq.copyWith(
                      size: size,
                      padding: EdgeInsets.zero,
                      viewPadding: EdgeInsets.zero,
                      viewInsets: EdgeInsets.zero,
                    ),
                    child: child,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Faint scattered letter tiles behind the desktop frame.
class _BackdropTiles extends StatelessWidget {
  const _BackdropTiles();

  static const _tiles = [
    (0.08, 0.14, 'L', -0.2),
    (0.16, 0.62, 'E', 0.15),
    (0.06, 0.84, 'X', -0.1),
    (0.88, 0.12, 'I', 0.18),
    (0.82, 0.48, 'S', -0.12),
    (0.91, 0.80, 'K', 0.1),
    (0.24, 0.30, 'T', 0.08),
    (0.74, 0.70, 'A', -0.16),
    (0.72, 0.26, 'C', 0.2),
  ];

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, c) => Stack(
          children: [
            for (final (x, y, ch, angle) in _tiles)
              Positioned(
                left: c.maxWidth * x - 32,
                top: c.maxHeight * y - 32,
                child: Transform.rotate(
                  angle: angle,
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.12),
                        width: 1.5,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      ch,
                      style: TextStyle(
                        fontFamily: kCondensed,
                        fontWeight: FontWeight.w700,
                        fontSize: 30,
                        color: Colors.white.withValues(alpha: 0.18),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
