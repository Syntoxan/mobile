import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

class SynBlackHoleIcon extends StatefulWidget {
  const SynBlackHoleIcon({super.key, this.size = 48});

  final double size;

  @override
  State<SynBlackHoleIcon> createState() => _SynBlackHoleIconState();
}

class _SynBlackHoleIconState extends State<SynBlackHoleIcon> with SingleTickerProviderStateMixin {
  static Future<ui.FragmentProgram>? _synProgramFuture;

  final ValueNotifier<double> _synTime = ValueNotifier<double>(0);
  late final Ticker _synTicker;
  ui.FragmentShader? _synShader;

  @override
  void initState() {
    super.initState();
    _synProgramFuture ??= ui.FragmentProgram.fromAsset('shaders/black_hole.frag');
    _synProgramFuture!.then((program) {
      if (!mounted) return;
      setState(() => _synShader = program.fragmentShader());
    });
    _synTicker = createTicker((elapsed) {
      _synTime.value = elapsed.inMicroseconds / 1000000.0;
    })..start();
  }

  @override
  void dispose() {
    _synTicker.dispose();
    _synTime.dispose();
    _synShader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shader = _synShader;
    if (shader == null) {
      return SizedBox(width: widget.size, height: widget.size);
    }
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return RepaintBoundary(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: CustomPaint(
          painter: _SynBlackHolePainter(shader, _synTime, isDark ? 1.0 : 0.0),
        ),
      ),
    );
  }
}

class _SynBlackHolePainter extends CustomPainter {
  _SynBlackHolePainter(this.shader, this.time, this.dark) : super(repaint: time);

  final ui.FragmentShader shader;
  final ValueNotifier<double> time;
  final double dark;

  @override
  void paint(Canvas canvas, Size size) {
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, time.value)
      ..setFloat(3, dark);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_SynBlackHolePainter old) => old.dark != dark || old.shader != shader;
}
