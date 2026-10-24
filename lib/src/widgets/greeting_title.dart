import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class GreetingTitle extends StatefulWidget {
  const GreetingTitle({super.key, required this.text, this.style});

  final String text;
  final TextStyle? style;

  @override
  State<GreetingTitle> createState() => _GreetingTitleState();
}

class _GreetingTitleState extends State<GreetingTitle>
    with SingleTickerProviderStateMixin {
  ui.FragmentShader? _shader;
  final ValueNotifier<double> _t = ValueNotifier<double>(0);
  late final Ticker _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((d) => _t.value = d.inMicroseconds / 1000000.0)
      ..start();
    ui.FragmentProgram.fromAsset('shaders/syntoxan_crystal.frag').then((p) {
      if (mounted) setState(() => _shader = p.fragmentShader());
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _t.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.style ??
        const TextStyle(fontFamily: 'InstrumentSerif', fontSize: 20);
    final fontSize = base.fontSize ?? 20;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final shader = _shader;

    if (shader == null) {
      return Text(widget.text, style: base, maxLines: 1);
    }

    return RepaintBoundary(
      child: ValueListenableBuilder<double>(
        valueListenable: _t,
        child: Text(
          widget.text,
          style: base.copyWith(color: Colors.white),
          maxLines: 1,
        ),
        builder: (context, t, child) => ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (Rect b) {
            shader
              ..setFloat(0, b.width)
              ..setFloat(1, b.height)
              ..setFloat(2, t)
              ..setFloat(3, fontSize * dpr);
            return shader;
          },
          child: child,
        ),
      ),
    );
  }
}
