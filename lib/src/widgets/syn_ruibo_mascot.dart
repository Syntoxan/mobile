import 'package:flutter/material.dart';

import 'syn_hidden_menu_screen.dart';

class SynMascotIcon extends StatefulWidget {
  const SynMascotIcon({super.key, this.size = 40});

  final double size;

  @override
  State<SynMascotIcon> createState() => _SynMascotIconState();
}

class _SynMascotIconState extends State<SynMascotIcon>
    with TickerProviderStateMixin {
  static bool _likedMemory = false;
  static const int _tapGoal = 3;
  static const int _tapGapMs = 700;
  static const Cubic _pressEase = Cubic(0.2, 0.8, 0.2, 1);

  late final AnimationController _color;
  late final AnimationController _burst;
  late final AnimationController _press;
  late final Animation<double> _colorCurve;
  late final Animation<double> _pressCurve;
  late bool _liked;
  int _taps = 0;
  DateTime? _lastTap;

  @override
  void initState() {
    super.initState();
    _liked = _likedMemory;
    _color = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
      value: _liked ? 1 : 0,
    );
    _burst = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
      value: 1,
    );
    _press = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _colorCurve = CurvedAnimation(
      parent: _color,
      curve: Curves.ease,
      reverseCurve: Curves.ease.flipped,
    );
    _pressCurve = CurvedAnimation(
      parent: _press,
      curve: _pressEase,
      reverseCurve: _pressEase.flipped,
    );
  }

  @override
  void dispose() {
    _color.dispose();
    _burst.dispose();
    _press.dispose();
    super.dispose();
  }

  void _onTap() {
    _press.value = 0;
    final bool liked = !_liked;
    setState(() => _liked = liked);
    _likedMemory = liked;
    if (liked) {
      _color.forward();
      _burst.forward(from: 0);
    } else {
      _color.reverse();
      _burst.value = 1;
    }
    _countTap();
  }

  void _countTap() {
    final DateTime now = DateTime.now();
    final DateTime? last = _lastTap;
    if (last == null || now.difference(last).inMilliseconds > _tapGapMs) {
      _taps = 0;
    }
    _lastTap = now;
    _taps += 1;
    if (_taps >= _tapGoal) {
      _taps = 0;
      _lastTap = null;
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(
          builder: (_) => const SynHiddenMenuScreen(),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) {
        if (!_liked) _press.forward();
      },
      onTapCancel: () => _press.reverse(),
      onTap: _onTap,
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.square(widget.size),
          painter: _SynHeartPainter(
            liked: _liked,
            color: _colorCurve,
            burst: _burst,
            press: _pressCurve,
          ),
        ),
      ),
    );
  }
}

class _SynHeartPainter extends CustomPainter {
  _SynHeartPainter({
    required this.liked,
    required this.color,
    required this.burst,
    required this.press,
  }) : super(repaint: Listenable.merge([color, burst, press]));

  final bool liked;
  final Animation<double> color;
  final Animation<double> burst;
  final Animation<double> press;

  static const Color _red = Color(0xFFFF2D55);
  static const Color _cyan = Color(0xFF3DFFDA);
  static const Cubic _jellyCurve = Cubic(0.175, 0.885, 0.32, 1.275);
  static const double _heartBox = 22;

  static const List<Offset> _sparkNear = [
    Offset(-18, -18),
    Offset(18, 18),
    Offset(-18, 18),
    Offset(18, -18),
    Offset(0, -22),
    Offset(0, 22),
  ];
  static const List<Offset> _sparkFar = [
    Offset(-35, -35),
    Offset(35, 35),
    Offset(-35, 35),
    Offset(35, -35),
    Offset(0, -40),
    Offset(0, 40),
  ];
  static const List<Color> _sparkColor = [
    _red,
    _cyan,
    _cyan,
    _red,
    _red,
    _cyan,
  ];

  static final Path _heart = Path()
    ..moveTo(20.84, 4.61)
    ..arcToPoint(const Offset(13.06, 4.61),
        radius: const Radius.circular(5.5), clockwise: false)
    ..lineTo(12, 5.67)
    ..lineTo(10.94, 4.61)
    ..arcToPoint(const Offset(3.16, 12.39),
        radius: const Radius.circular(5.5), clockwise: false)
    ..lineTo(4.22, 13.45)
    ..lineTo(12, 21.23)
    ..lineTo(19.78, 13.45)
    ..lineTo(20.84, 12.39)
    ..arcToPoint(const Offset(20.84, 4.61),
        radius: const Radius.circular(5.5), clockwise: false)
    ..close();

  static double _ease(Curve curve, double x) =>
      curve.transform(x.clamp(0.0, 1.0).toDouble());

  static double _lerp(double a, double b, double x) => a + (b - a) * x;

  static double _jelly(double t) {
    if (t < 0.4) return _lerp(0.75, 1.35, _ease(_jellyCurve, t / 0.4));
    if (t < 0.7) {
      return _lerp(1.35, 0.95, _ease(_jellyCurve, (t - 0.4) / 0.3));
    }
    return _lerp(0.95, 1.0, _ease(_jellyCurve, (t - 0.7) / 0.3));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = Offset(size.width / 2, size.height / 2);
    final double t = burst.value;
    final double scale = liked ? _jelly(t) : 1 - 0.25 * press.value;

    if (liked) {
      _paintSparks(canvas, center, t);
      _paintRipple(canvas, center, t);
    }

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale);
    canvas.scale(_heartBox / 24);
    canvas.translate(-12, -12);
    if (liked) {
      canvas.drawPath(
        _heart,
        Paint()
          ..style = PaintingStyle.fill
          ..isAntiAlias = true
          ..color = _red,
      );
    }
    canvas.drawPath(
      _heart,
      Paint()
        ..style = PaintingStyle.stroke
        ..isAntiAlias = true
        ..strokeWidth = 1.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..color = Color.lerp(Colors.white, _red, color.value)!,
    );
    canvas.restore();
  }

  void _paintSparks(Canvas canvas, Offset c, double t) {
    final double opacity = t <= 0.15
        ? _ease(Curves.easeOut, t / 0.15)
        : 1 - _ease(Curves.easeOut, (t - 0.15) / 0.85);
    if (opacity <= 0) return;
    final bool first = t <= 0.5;
    final double p =
        _ease(Curves.easeOut, first ? t / 0.5 : (t - 0.5) / 0.5);
    final double radius = first ? 2 - p : 1 - p;
    final double alpha = (first ? p : 1 - p) * opacity;
    if (radius <= 0 || alpha <= 0) return;

    canvas.save();
    canvas.clipPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Rect.fromCircle(center: c, radius: 80)),
        Path()..addOval(Rect.fromCircle(center: c, radius: 2)),
      ),
    );
    for (int i = 0; i < 6; i++) {
      final Offset o = first
          ? _sparkNear[i] * p
          : Offset.lerp(_sparkNear[i], _sparkFar[i], p)!;
      canvas.drawCircle(
        c + o,
        radius,
        Paint()
          ..isAntiAlias = true
          ..color = _sparkColor[i].withAlpha((alpha * 255).round()),
      );
    }
    canvas.restore();
  }

  void _paintRipple(Canvas canvas, Offset c, double t) {
    final double p = _ease(Curves.easeOut, t);
    final double bw = 3 * (1 - p);
    final double alpha = 0.6 * (1 - p);
    if (bw <= 0 || alpha <= 0) return;
    final double s = 0.5 + 1.1 * p;
    canvas.drawCircle(
      c,
      s * (16 + bw / 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..isAntiAlias = true
        ..strokeWidth = bw * s
        ..color = _red.withAlpha((alpha * 255).round()),
    );
  }

  @override
  bool shouldRepaint(covariant _SynHeartPainter oldDelegate) =>
      oldDelegate.liked != liked;
}
