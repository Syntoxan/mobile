import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

const double _kViewX = 0.022;
const double _kViewY = 0.004;
const double _kViewW = 0.930;
const double _kViewH = 0.620;
const double _kViewAspect = _kViewW / _kViewH;
const double _kOpticalLift = 0.036;
const double _kTau = math.pi * 2;

const double _kFlowerX = 0.304;
const double _kFlowerY = 0.346;
const double _kStemW = 0.022;
const double _kPetalR = 0.126;

const Color _cInk = Color(0xFF454140);
const Color _cEye = Color(0xFF3E3A39);
const Color _cWhite = Color(0xFFFFFFFF);
const Color _cPetal = Color(0xFFFADCE4);
const Color _cPetalDeep = Color(0xFFF4B8C8);
const Color _cStem = Color(0xFFA8D8B9);
const Color _cFilament = Color(0xFF8A6E58);
const Color _cPollen = Color(0xFFF3D98C);

const List<double> _kPetalAngles = [-2.0944, -0.9076, 0.8029, 1.9548, 3.0718];
const List<double> _kPetalScales = [1.00, 1.04, 0.98, 1.02, 0.97];

const List<double> _tBody = [
  0.392, 0.236,
  0.392, 0.208, 0.414, 0.194, 0.444, 0.194,
  0.474, 0.194, 0.494, 0.220, 0.522, 0.220,
  0.552, 0.220, 0.574, 0.202, 0.604, 0.204,
  0.636, 0.206, 0.656, 0.236, 0.670, 0.280,
  0.686, 0.328, 0.708, 0.392, 0.714, 0.464,
  0.718, 0.516, 0.694, 0.544, 0.642, 0.548,
  0.584, 0.552, 0.500, 0.570, 0.436, 0.562,
  0.386, 0.556, 0.344, 0.532, 0.344, 0.480,
  0.342, 0.416, 0.366, 0.346, 0.382, 0.296,
  0.388, 0.276, 0.392, 0.258, 0.392, 0.236,
];

const List<double> _tCleanArmL = [
  0.412, 0.418, 0.445, 0.390, 0.488, 0.415, 0.455, 0.458,
];
const List<double> _tCleanArmR = [
  0.516, 0.402, 0.476, 0.438, 0.492, 0.472, 0.542, 0.465,
];
const List<double> _tCleanStemTail = [
  0.522, 0.466, 0.542, 0.482, 0.558, 0.498, 0.572, 0.516,
];

const List<double> _tMouth = [
  0.478, 0.339,
  0.478, 0.350, 0.490, 0.353, 0.495, 0.343,
  0.500, 0.353, 0.512, 0.350, 0.512, 0.339,
];

const List<double> _tEye = [
  0.0105, 0.0,
  0.0105, 0.00674, 0.0058, 0.0122, 0.0, 0.0122,
  -0.0058, 0.0122, -0.0105, 0.00674, -0.0105, 0.0,
  -0.0105, -0.00674, -0.0058, -0.0122, 0.0, -0.0122,
  0.0058, -0.0122, 0.0105, -0.00674, 0.0105, 0.0,
];

const List<double> _tStem = [
  0.340, 0.352, 0.376, 0.348, 0.408, 0.368, 0.444, 0.408,
];

const List<double> _tPetal = [
  0.006, 0.0,
  0.022, -0.030, 0.054, -0.050, 0.092, -0.046,
  0.112, -0.044, 0.128, -0.032, 0.126, -0.016,
  0.124, -0.010, 0.116, -0.004, 0.110, 0.0,
  0.116, 0.004, 0.124, 0.010, 0.126, 0.016,
  0.128, 0.032, 0.112, 0.044, 0.092, 0.046,
  0.054, 0.050, 0.022, 0.030, 0.006, 0.0,
];

const List<double> _tFloater = [
  0.0, 0.040,
  -0.020, 0.028, -0.044, 0.004, -0.042, -0.020,
  -0.040, -0.034, -0.016, -0.036, 0.0, -0.016,
  0.016, -0.036, 0.040, -0.034, 0.042, -0.020,
  0.044, 0.004, 0.020, 0.028, 0.0, 0.040,
];

const List<List<double>> _tStamens = [
  [0.0000, -0.0060, 0.0032, -0.0130, -0.0032, -0.0216, 0.0000, -0.0300],
  [0.0047, -0.0037, 0.0122, -0.0055, 0.0128, -0.0141, 0.0205, -0.0160],
  [0.0058, 0.0015, 0.0118, 0.0063, 0.0231, 0.0025, 0.0310, 0.0077],
  [0.0026, 0.0054, 0.0028, 0.0131, 0.0117, 0.0167, 0.0123, 0.0252],
  [-0.0026, 0.0054, -0.0086, 0.0103, -0.0066, 0.0208, -0.0131, 0.0270],
  [-0.0058, 0.0015, -0.0134, 0.0000, -0.0174, 0.0076, -0.0252, 0.0063],
  [-0.0047, -0.0037, -0.0083, -0.0105, -0.0201, -0.0117, -0.0252, -0.0197],
];

const List<double> _tPollenAt = [
  0.0000, -0.0300,
  0.0205, -0.0160,
  0.0310, 0.0077,
  0.0123, 0.0252,
  -0.0131, 0.0270,
  -0.0252, 0.0063,
  -0.0252, -0.0197,
];

const List<double> _tDot = [
  0.0065, 0.0,
  0.0065, 0.00359, 0.00359, 0.0065, 0.0, 0.0065,
  -0.00359, 0.0065, -0.0065, 0.00359, -0.0065, 0.0,
  -0.0065, -0.00359, -0.00359, -0.0065, 0.0, -0.0065,
  0.00359, -0.0065, 0.0065, -0.00359, 0.0065, 0.0,
];

const List<double> _tPistil = [
  0.0075, 0.0,
  0.0075, 0.00414, 0.00414, 0.0075, 0.0, 0.0075,
  -0.00414, 0.0075, -0.0075, 0.00414, -0.0075, 0.0,
  -0.0075, -0.00414, -0.00414, -0.0075, 0.0, -0.0075,
  0.00414, -0.0075, 0.0075, -0.00414, 0.0075, 0.0,
];

/// Floating petal at its resting position (taken from the reference image).
class _SynFloater {
  const _SynFloater(this.cx, this.cy, this.rot, this.scale);
  final double cx, cy, rot, scale;
}

const List<_SynFloater> _kFloaters = [
  _SynFloater(0.572, 0.076, 0.45, 0.92),
  _SynFloater(0.106, 0.244, -0.75, 0.92),
  _SynFloater(0.872, 0.556, -0.30, 0.96),
];

enum _SynLayer { rim, art }

double _synRoundPx(double v, double dpr) => (v * dpr).roundToDouble() / dpr;

double _synContentCenterY(double boxH, double dpr, double k) =>
    _synRoundPx(boxH / 2 - _kOpticalLift * k, dpr);

Path _synCubicPath(List<double> t, {bool close = true}) {
  final p = Path()..moveTo(t[0], t[1]);
  for (var i = 2; i + 5 < t.length; i += 6) {
    p.cubicTo(t[i], t[i + 1], t[i + 2], t[i + 3], t[i + 4], t[i + 5]);
  }
  if (close) p.close();
  return p;
}

Path _synCubicMany(List<List<double>> tables) {
  final p = Path();
  for (final t in tables) {
    p.addPath(_synCubicPath(t, close: false), Offset.zero);
  }
  return p;
}

Path _synInkRibbon(Path src, double halfW, double seed) {
  final out = Path();
  for (final m in src.computeMetrics()) {
    final len = m.length;
    if (len <= 0.0) continue;
    final n = math.max(32, (len / 0.004).ceil());
    final a = <Offset>[];
    final b = <Offset>[];
    for (var i = 0; i <= n; i++) {
      final d = len * (i % n) / n;
      final tg = m.getTangentForOffset(d);
      if (tg == null) continue;
      final l = tg.vector.distance;
      if (l == 0.0) continue;
      final phase = _kTau * (i % n) / n;
      final f = 1.0 +
          0.16 * math.sin(phase * 5.0 + seed) +
          0.08 * math.sin(phase * 11.0 + seed * 2.3);
      final nx = -tg.vector.dy / l * halfW * f;
      final ny = tg.vector.dx / l * halfW * f;
      a.add(Offset(tg.position.dx + nx, tg.position.dy + ny));
      b.add(Offset(tg.position.dx - nx, tg.position.dy - ny));
    }
    if (a.length < 3) continue;
    out.moveTo(a.first.dx, a.first.dy);
    for (var i = 1; i < a.length; i++) {
      out.lineTo(a[i].dx, a[i].dy);
    }
    for (var i = b.length - 1; i >= 0; i--) {
      out.lineTo(b[i].dx, b[i].dy);
    }
    out.close();
  }
  return out;
}

class _SynArt {
  _SynArt._();

  static final Path body = _synCubicPath(_tBody);
  static final Path cleanArmL = _synCubicPath(_tCleanArmL, close: false);
  static final Path cleanArmR = _synCubicPath(_tCleanArmR, close: false);
  static final Path cleanStemTail = _synCubicPath(_tCleanStemTail, close: false);
  static final Path mouth = _synCubicPath(_tMouth, close: false);
  static final Path eye = _synCubicPath(_tEye);
  static final Path stem = _synCubicPath(_tStem, close: false);
  static final Path petal = _synCubicPath(_tPetal);
  static final Path floater = _synCubicPath(_tFloater);
  static final Path stamens = _synCubicMany(_tStamens);
  static final Path pistil = _synCubicPath(_tPistil);
  static final Path pollen = _buildPollen();

  static const Offset eyeL = Offset(0.448, 0.328);
  static const Offset eyeR = Offset(0.542, 0.332);

  static Path _buildPollen() {
    final p = Path();
    for (var i = 0; i + 1 < _tPollenAt.length; i += 2) {
      p.addPath(
        _synCubicPath(_tDot),
        Offset(_tPollenAt[i], _tPollenAt[i + 1]),
      );
    }
    return p;
  }
}

class _SynInk {
  const _SynInk._(
    this.wMain,
    this.wFine,
    this.wRim,
    this.body,
    this.petal,
    this.floater,
  );

  final double wMain, wFine, wRim;
  final Path body, petal, floater;

  factory _SynInk.build(double height, double dpr) {
    final k = height / _kViewH;
    final wMain = math.max(_synRoundPx(height * 0.030, dpr), 1.5 / dpr) / k;
    final wFine = math.max(_synRoundPx(height * 0.016, dpr), 1.0 / dpr) / k;
    final wRim = math.max(_synRoundPx(height * 0.020, dpr), 1.0 / dpr) / k;
    final half = wMain / 2;
    return _SynInk._(
      wMain,
      wFine,
      wRim,
      _synInkRibbon(_SynArt.body, half, 0.7),
      _synInkRibbon(_SynArt.petal, half, 1.4),
      _synInkRibbon(_SynArt.floater, half, 4.1),
    );
  }
}

/// Static sakura-flower mascot. Nothing moves: no sway, breathing, blinking,
/// floating petals or tap bounce.
class SynSakuraMascot extends StatelessWidget {
  const SynSakuraMascot({
    super.key,
    this.size = 36.0,
    this.animate = false,
    this.rimColor = const Color(0xFFE6DAFF),
  });

  const SynSakuraMascot.interactive({
    super.key,
    this.size = 36.0,
    this.animate = false,
    this.rimColor = const Color(0xFFE6DAFF),
  });

  /// Height of the drawing box (width = size * 1.5).
  final double size;

  /// Kept only so old call sites still compile. Has no effect.
  final bool animate;

  /// Soft glow behind the outline so it stays visible on a dark background.
  final Color rimColor;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return SizedBox(
      width: size * _kViewAspect,
      height: size,
      child: CustomPaint(
        painter: _SynSakuraPainter(dpr: dpr, height: size, rim: rimColor),
      ),
    );
  }
}

class _SynSakuraPainter extends CustomPainter {
  _SynSakuraPainter({
    required this.dpr,
    required this.height,
    required this.rim,
  }) : ink = _SynInk.build(height, dpr);

  final double dpr;
  final double height;
  final Color rim;
  final _SynInk ink;

  static const List<int> _haloAlpha = [0x30, 0x1E, 0x12];

  final Paint _fill = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.fill;

  final Paint _line = Paint()
    ..isAntiAlias = true
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  final Paint _petalFill = Paint()
    ..isAntiAlias = true
    ..shader = ui.Gradient.radial(
      Offset.zero,
      _kPetalR,
      const [_cPetalDeep, _cPetal],
      const [0.10, 1.0],
    );

  final Paint _floatFill = Paint()
    ..isAntiAlias = true
    ..shader = ui.Gradient.radial(
      const Offset(0.0, 0.030),
      0.070,
      const [_cPetalDeep, _cPetal],
      const [0.0, 1.0],
    );

  void _stroke(Canvas c, Path p, Color color, double w) {
    _line
      ..color = color
      ..strokeWidth = w;
    c.drawPath(p, _line);
  }

  void _halo(Canvas c, Path p, double scale) {
    if (rim.alpha == 0) return;
    final base = ink.wMain + 2 * ink.wRim;
    for (var i = 3; i >= 1; i--) {
      _stroke(
        c,
        p,
        rim.withAlpha(_haloAlpha[i - 1]),
        (base + i * ink.wRim * 1.4) / scale,
      );
    }
    _stroke(c, p, rim.withAlpha(0xA8), base / scale);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.height <= 0) return;
    final k = size.height / _kViewH;
    final ox = _synRoundPx((size.width - _kViewW * k) / 2 - _kViewX * k, dpr);
    final oy = _synRoundPx(
      _synContentCenterY(size.height, dpr, k) - (_kViewY + _kViewH / 2) * k,
      dpr,
    );

    canvas.save();
    canvas.translate(ox, oy);
    canvas.scale(k, k);
    _body(canvas, _SynLayer.rim);
    _floaters(canvas, _SynLayer.rim);
    _body(canvas, _SynLayer.art);
    _floaters(canvas, _SynLayer.art);
    canvas.restore();
  }

  void _body(Canvas c, _SynLayer layer) {
    if (layer == _SynLayer.rim) {
      _flower(c, layer);
      _halo(c, _SynArt.body, 1.0);
      return;
    }

    _fill.color = _cWhite;
    c.drawPath(_SynArt.body, _fill);
    _fill.color = _cInk;
    c.drawPath(ink.body, _fill);

    _face(c);

    _flower(c, layer);
    _stroke(c, _SynArt.cleanArmL, _cInk, ink.wMain);
    _stroke(c, _SynArt.cleanArmR, _cInk, ink.wMain);
    _stroke(c, _SynArt.cleanStemTail, _cInk, ink.wMain);
  }

  void _eye(Canvas c, Offset o) {
    c.save();
    c.translate(o.dx, o.dy);
    c.drawPath(_SynArt.eye, _fill);
    c.restore();
  }

  void _face(Canvas c) {
    _fill.color = _cEye;
    _eye(c, _SynArt.eyeL);
    _eye(c, _SynArt.eyeR);
    _stroke(c, _SynArt.mouth, _cInk, ink.wMain * 0.85);
  }

  void _flower(Canvas c, _SynLayer layer) {
    final isRim = layer == _SynLayer.rim;

    if (!isRim) {
      _stroke(c, _SynArt.stem, _cInk, _kStemW + ink.wMain * 1.6);
      _stroke(c, _SynArt.stem, _cStem, _kStemW);
    }

    for (var i = 0; i < _kPetalAngles.length; i++) {
      final s = _kPetalScales[i];
      c.save();
      c.translate(_kFlowerX, _kFlowerY);
      c.rotate(_kPetalAngles[i]);
      c.scale(s, s);
      if (isRim) {
        _halo(c, _SynArt.petal, s);
      } else {
        c.drawPath(_SynArt.petal, _petalFill);
        _fill.color = _cInk;
        c.drawPath(ink.petal, _fill);
      }
      c.restore();
    }

    if (!isRim) _stamens(c);
  }

  void _stamens(Canvas c) {
    c.save();
    c.translate(_kFlowerX, _kFlowerY);
    _stroke(c, _SynArt.stamens, _cFilament, ink.wFine);
    _fill.color = _cPollen;
    c.drawPath(_SynArt.pollen, _fill);
    _stroke(c, _SynArt.pollen, _cFilament, ink.wFine * 0.7);
    _fill.color = _cFilament;
    c.drawPath(_SynArt.pistil, _fill);
    c.restore();
  }

  void _floaters(Canvas c, _SynLayer layer) {
    for (final f in _kFloaters) {
      c.save();
      c.translate(f.cx, f.cy);
      c.rotate(f.rot);
      c.scale(f.scale, f.scale);
      if (layer == _SynLayer.rim) {
        _halo(c, _SynArt.floater, f.scale);
      } else {
        c.drawPath(_SynArt.floater, _floatFill);
        _fill.color = _cInk;
        c.drawPath(ink.floater, _fill);
      }
      c.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _SynSakuraPainter old) =>
      old.height != height || old.dpr != dpr || old.rim != rim;
}
