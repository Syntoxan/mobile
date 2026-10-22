import 'dart:math' as math;
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
    duration: const Duration(milliseconds: 4200),
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = isDark ? _dark : _light;
    final textStyle = (widget.style ??
            const TextStyle(
              fontFamily: 'Prata',
              fontSize: 22,
              letterSpacing: 1.5,
            ))
        .copyWith(color: Colors.white);

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        child: Text(widget.text, style: textStyle, maxLines: 1),
        builder: (context, child) {
          final t = (_c.value / 0.55).clamp(0.0, 1.0);
          final p = 1.0 - Curves.easeInOut.transform(t);
          return ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (Rect b) {
              final w = b.width;
              final h = b.height;
              final imgW = w * 2.5;
              final cx = -1.5 * w * p + imgW / 2;
              final cy = h / 2;
              final a = 110 * math.pi / 180;
              final dx = math.sin(a);
              final dy = -math.cos(a);
              final len = imgW * dx.abs() + h * dy.abs();
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
      ),
    );
  }
}
