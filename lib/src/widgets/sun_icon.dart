import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class SunIcon extends StatefulWidget {
  final double size;
  const SunIcon({super.key, this.size = 64});

  @override
  State<SunIcon> createState() => _SunIconState();
}

class _SunIconState extends State<SunIcon>
    with SingleTickerProviderStateMixin {
  ui.FragmentShader? _shader;
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(hours: 1),
    )..repeat();
    _loadShader();
  }

  Future<void> _loadShader() async {
    try {
                  final program = await ui.FragmentProgram.fromAsset('shaders/sun.frag');
      if (!mounted) return;
      setState(() => _shader = program.fragmentShader());
    } catch (e) {
      debugPrint('SunIcon shader load failed: $e');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
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
            ? const SizedBox.shrink()
            : AnimatedBuilder(
                animation: _controller,
                builder: (_, __) {
                  final t = _controller.value *
                      _controller.duration!.inMilliseconds /
                      1000.0;
                  return CustomPaint(
                    size: Size.square(widget.size),
                    painter: _SunPainter(shader, t),
                  );
                },
              ),
      ),
    );
  }
}

class _SunPainter extends CustomPainter {
  final ui.FragmentShader shader;
  final double time;

  _SunPainter(this.shader, this.time);

  @override
  void paint(Canvas canvas, Size size) {
    shader.setFloat(0, size.width);
    shader.setFloat(1, size.height);
    shader.setFloat(2, time);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(covariant _SunPainter old) => old.time != time;
}
