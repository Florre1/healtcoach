import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'theme.dart';

/// Ambient light lives behind every route; cards blur the real backdrop.
class GlassBackground extends StatelessWidget {
  final Widget child;
  const GlassBackground({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ColoredBox(
      color: dark ? Colors.black : const Color(0xffedf1ed),
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-1, -1),
                    radius: 1.1,
                    colors: [
                      Color(dark ? 0x8c1c6e58 : 0x332a9870),
                      Colors.transparent,
                    ],
                    stops: const [0, .75],
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(1, -.9),
                    radius: .85,
                    colors: [
                      lime.withValues(alpha: dark ? .16 : .25),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(1, 1),
                    radius: 1,
                    colors: [
                      const Color(0xff264896)
                          .withValues(alpha: dark ? .38 : .13),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-1, .45),
                    radius: .75,
                    colors: [
                      const Color(0xff145a5a)
                          .withValues(alpha: dark ? .30 : .08),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
          BackdropGroup(child: child),
        ],
      ),
    );
  }
}

class GlassSurface extends StatelessWidget {
  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final bool prominent, floating;
  const GlassSurface({
    super.key,
    required this.child,
    this.radius = 26,
    this.padding = EdgeInsets.zero,
    this.prominent = false,
    this.floating = false,
  });
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final highContrast = MediaQuery.highContrastOf(context);
    final shape = BorderRadius.circular(radius);
    final content = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: shape,
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: dark
              ? [
                  Colors.white.withValues(alpha: floating ? .14 : .10),
                  Colors.white.withValues(alpha: floating ? .08 : .045),
                ]
              : [
                  Colors.white.withValues(alpha: .82),
                  Colors.white.withValues(alpha: .48),
                ],
        ),
        border: Border.all(
          width: .7,
          color: dark
              ? Colors.white.withValues(alpha: highContrast ? .45 : .16)
              : Colors.white.withValues(alpha: .85),
        ),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: shape,
          gradient: prominent
              ? RadialGradient(
                  center: Alignment.topRight,
                  radius: 1.1,
                  colors: [
                    lime.withValues(alpha: dark ? .15 : .28),
                    Colors.transparent,
                  ],
                )
              : null,
        ),
        child: Padding(padding: padding, child: child),
      ),
    );
    final filter = ImageFilter.blur(
      sigmaX: floating ? 24 : 29,
      sigmaY: floating ? 24 : 29,
    );
    return Container(
      decoration: BoxDecoration(
        borderRadius: shape,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? .26 : .045),
            blurRadius: floating ? 32 : 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: shape,
        child: floating
            ? BackdropFilter(filter: filter, child: content)
            : BackdropFilter.grouped(filter: filter, child: content),
      ),
    );
  }
}

class GlassNavigation extends StatelessWidget {
  final int selected;
  final ValueChanged<int> onSelected;
  const GlassNavigation({
    super.key,
    required this.selected,
    required this.onSelected,
  });
  @override
  Widget build(BuildContext context) {
    const labels = ['Heute', 'Verlauf', 'Messungen', 'Profil'];
    const icons = [
      CupertinoIcons.square_grid_2x2,
      CupertinoIcons.chart_bar_alt_fill,
      CupertinoIcons.list_bullet,
      CupertinoIcons.person,
    ];
    final dark = Theme.of(context).brightness == Brightness.dark;
    return GlassSurface(
      radius: 35,
      floating: true,
      padding: const EdgeInsets.all(4),
      child: SizedBox(
        height: 56,
        child: LayoutBuilder(
          builder: (context, size) => Stack(
            children: [
              AnimatedAlign(
                alignment: Alignment(-1 + selected * 2 / 3, 0),
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 350),
                curve: Curves.easeOutCubic,
                child: Container(
                  width: size.maxWidth / 4,
                  height: 56,
                  decoration: BoxDecoration(
                    color: (dark ? Colors.white : forest).withValues(
                      alpha: .12,
                    ),
                    borderRadius: BorderRadius.circular(29),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: .18),
                      width: .5,
                    ),
                  ),
                ),
              ),
              Row(
                children: List.generate(
                  4,
                  (i) => Expanded(
                    child: Semantics(
                      selected: selected == i,
                      button: true,
                      label: labels[i],
                      child: ExcludeSemantics(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(29),
                          onTap: () => onSelected(i),
                          child: SizedBox(
                            height: 56,
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  icons[i],
                                  size: 23,
                                  applyTextScaling: false,
                                  color: selected == i
                                      ? Theme.of(context).colorScheme.primary
                                      : null,
                                ),
                                const SizedBox(height: 3),
                                Flexible(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    child: Text(
                                      labels[i],
                                      maxLines: 1,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: selected == i
                                            ? Theme.of(context)
                                                  .colorScheme
                                                  .primary
                                            : null,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
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

class GoalRing extends StatelessWidget {
  final double progress;
  const GoalRing({super.key, required this.progress});
  @override
  Widget build(BuildContext context) => Semantics(
    label: '${(progress * 100).round()} Prozent des Ziels erreicht',
    child: SizedBox(
      width: 92,
      height: 92,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: CustomPaint(
              painter: _RingPainter(
                progress,
                Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${(progress * 100).round()} %',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                'geschafft',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    ),
  );
}

class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  _RingPainter(this.progress, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(7, 7, size.width - 14, size.height - 14);
    final pen = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 9
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(
      rect,
      0,
      math.pi * 2,
      false,
      pen..color = color.withValues(alpha: .12),
    );
    if (progress > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * progress,
        false,
        pen
          ..color = color.withValues(alpha: .30)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4),
      );
      canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * progress,
        false,
        pen
          ..color = color
          ..maskFilter = null,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress || old.color != color;
}

class GlassSheet extends StatelessWidget {
  final Widget child;
  const GlassSheet({super.key, required this.child});
  @override
  Widget build(BuildContext context) => GlassSurface(
    radius: 34,
    floating: true,
    child: Material(
      color: Theme.of(context).brightness == Brightness.dark
          ? const Color(0xc71e1e21)
          : const Color(0xddeef2ee),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 5,
              margin: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.onSurface
                    .withValues(alpha: .28),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            Flexible(child: child),
          ],
        ),
      ),
    ),
  );
}
