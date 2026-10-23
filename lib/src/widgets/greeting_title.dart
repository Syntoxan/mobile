import 'package:flutter/material.dart';

class GreetingTitle extends StatefulWidget {
  const GreetingTitle({super.key, required this.text, this.style});

  final String text;
  final TextStyle? style;

  @override
  State<GreetingTitle> createState() => _GreetingTitleState();
}

class _GreetingTitleState extends State<GreetingTitle>
    with SingleTickerProviderStateMixin {
  static const _totalSeconds = 315;

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(seconds: _totalSeconds),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  static const _kt = <double>[0, 0.84, 0.85, 0.86, 0.875, 0.89, 0.90, 0.92, 0.93, 1];
  static const _kv = <double>[1, 1, 0.2, 1, 0.1, 0.85, 0.2, 0.2, 1, 1];

  static double _flicker(double p) {
    for (var i = 1; i < _kt.length; i++) {
      if (p <= _kt[i]) {
        final f = (p - _kt[i - 1]) / (_kt[i] - _kt[i - 1]);
        return _kv[i - 1] + (_kv[i] - _kv[i - 1]) * f;
      }
    }
    return 1;
  }

  static const _flick = <int, List<double>>{
    1: [5, 0],
    5: [7, 1.5],
    7: [9, 3],
  };

  double _opacity(int i, double secs) {
    final f = _flick[i];
    if (f == null) return 1;
    final period = f[0];
    final delay = f[1];
    final phase = (((secs - delay) % period) + period) % period;
    return _flicker(phase / period);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sat = isDark ? 0.90 : 0.65;
    final light = isDark ? 0.78 : 0.40;

    final base = widget.style ??
        const TextStyle(fontFamily: 'InstrumentSerif', fontSize: 20);
    final letters = widget.text.split('');

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final secs = _c.value * _totalSeconds;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < letters.length; i++)
                Builder(builder: (context) {
                  final hue = (i * 45 + 250) % 360;
                  final color =
                      HSLColor.fromAHSL(1, hue.toDouble(), sat, light).toColor();
                  return Opacity(
                    opacity: _opacity(i, secs),
                    child: Text(
                      letters[i],
                      maxLines: 1,
                      style: base.copyWith(
                        color: color,
                        shadows: isDark
                            ? [
                                Shadow(
                                  color: color.withOpacity(0.5),
                                  blurRadius: 3.5,
                                ),
                              ]
                            : const [],
                      ),
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }
}
