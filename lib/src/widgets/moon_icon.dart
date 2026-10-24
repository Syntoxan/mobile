import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class MoonIcon extends StatefulWidget {
  const MoonIcon({super.key, this.size = 64});
  final double size;

  @override
  State<MoonIcon> createState() => _MoonIconState();
}

class _MoonIconState extends State<MoonIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  ui.FragmentShader? _shader;

  @override
  void initState() {
    super.initState();
    // uTime = value * 3600 s (loops hourly; keeps float precision high)
    _ctrl = AnimationController(vsync: this, duration: const Duration(hours: 1))
      ..repeat();
    _load();
  }

  Future<void> _load() async {
        final program = await ui.FragmentProgram.fromAsset('shaders/moon.frag');
    if (!mounted) return;
    setState(() => _shader = program.fragmentShader());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shader = _shader;
    return RepaintBoundary(
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: shader == null
            ? null
            : CustomPaint(painter: _MoonPainter(shader, _ctrl)),
      ),
    );
  }
}

class _MoonPainter extends CustomPainter {
  _MoonPainter(this.shader, this.ctrl) : super(repaint: ctrl);

  final ui.FragmentShader shader;
  final AnimationController ctrl;
  final Paint _paint = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, ctrl.value * 3600.0);
    canvas.drawRect(Offset.zero & size, _paint..shader = shader);
  }

  @override
  bool shouldRepaint(covariant _MoonPainter old) => old.shader != shader;
}
