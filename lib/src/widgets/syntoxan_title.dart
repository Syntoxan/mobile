import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class SyntoxanTitle extends StatefulWidget {
  const SyntoxanTitle({super.key, this.text = 'SYNTOXAN', this.style});

  final String text;
  final TextStyle? style;

  @override
  State<SyntoxanTitle> createState() => _SyntoxanTitleState();
}

class _SyntoxanTitleState extends State<SyntoxanTitle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 6500),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  static const _stops = <double>[0.0, 0.30, 0.40, 0.46, 0.52, 0.58, 0.70, 1.0];

  static const _dark = <Color>[
    Color(0xFF8F95A4), Color(0xFF8F95A4), Color(0xFFD5D9E3), Color(0xFFFFFFFF),
    Color(0xFFD0BCFF), Color(0xFF6B7180), Color(0xFF8F95A4), Color(0xFF8F95A4),
  ];

  static const _light = <Color>[
    Color(0xFF3D4250), Color(0xFF3D4250), Color(0xFF6A7185), Color(0xFFA9B3C9),
    Color(0xFF6750A4), Color(0xFF1C2029), Color(0xFF3D4250), Color(0xFF3D4250),
  ];

  static double _e(double x) => Curves.easeInOut.transform(x.clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = isDark ? _dark : _light;
    final starColor = isDark ? const Color(0xFFD0BCFF) : const Color(0xFF6750A4);

    final base = (widget.style ??
            const TextStyle(
              fontFamily: 'Prata',
              fontSize: 18,
              letterSpacing: 1,
            ))
        .copyWith(color: Colors.white);
    final text = Text(widget.text, style: base, maxLines: 1);

    // Layer 1: titanium chrome shine
    final shine = AnimatedBuilder(
      animation: _c,
      child: text,
      builder: (context, child) {
        final p = 1.0 - _e(_c.value / 0.55);
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (Rect b) {
            final w = b.width;
            final h = b.height;
            final imgW = w * 2.5;
            final cx = -1.5 * w * p + imgW / 2;
            final cy = h / 2;
            const dx = 0.9396926; // sin(110deg)
            const dy = 0.3420201; // -cos(110deg)
            final len = imgW * dx + h * dy;
            return ui.Gradient.linear(
              Offset(cx - dx * len / 2, cy - dy * len / 2),
              Offset(cx + dx * len / 2, cy + dy * len / 2),
              colors,
              _stops,
            );
          },
          child: child,
        );
      },
    );

    // Layer 2: brushed lines (1px dark, 1px clear)
    final lines = ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: (Rect b) => ui.Gradient.linear(
        Offset.zero,
        const Offset(0, 2),
        const [
          Color(0x38000000), Color(0x38000000),
          Color(0x00000000), Color(0x00000000),
        ],
        const [0.0, 0.5, 0.5, 1.0],
        TileMode.repeated,
      ),
      child: text,
    );

    // Layer 3: flying star
    final star = Positioned.fill(
      child: IgnorePointer(
        child: LayoutBuilder(
          builder: (context, cons) {
            return AnimatedBuilder(
              animation: _c,
              builder: (context, _) {
                final v = _c.value;
                final left = -0.04 + 1.08 * _e(v / 0.55);

                double op;
                if (v < 0.06) {
                  op = _e(v / 0.06);
                } else if (v <= 0.49) {
                  op = 1;
                } else if (v <= 0.55) {
                  op = 1 - _e((v - 0.49) / 0.06);
                } else {
                  op = 0;
                }
                if (op <= 0.001) return const SizedBox.shrink();

                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: left * cons.maxWidth,
                      top: -9,
                      child: Opacity(
                        opacity: op,
                        child: Text(
                          '\u2726',
                          maxLines: 1,
                          softWrap: false,
                          style: base.copyWith(
                            fontSize: 11,
                            letterSpacing: 0,
                            color: starColor,
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            );
          },
        ),
      ),
    );

    return RepaintBoundary(
      child: Stack(
        clipBehavior: Clip.none,
        children: [shine, lines, star],
      ),
    );
  }
}
