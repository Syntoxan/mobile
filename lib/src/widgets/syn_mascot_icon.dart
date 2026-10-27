import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Mascot colour in light mode (near-black).
const Color synPlateColor = Color(0xFF17131F);

/// Mascot colour in dark mode.
const Color synFaceColor = Color(0xFFFFFFFF);

/// Vertical centre of the visible mascot inside its unit square. The painter
/// uses it to centre the mascot in its box, which lifts it up to sit level with
/// the text next to it.
const double _synContentCenterY = 0.52960;

const List<Offset> _synFaceVertices = <Offset>[
  Offset(0.21425, 0.32470),
  Offset(0.78044, 0.24860),
  Offset(0.78334, 0.84276),
  Offset(0.21648, 0.84276),
];
const List<double> _synFaceRadii = <double>[0.05085, 0.07136, 0.03457, 0.03457];

const List<double> _synEyeLeft = <double>[0.37633, 0.57434, 0.07014, 0.10665, -0.00223];
const List<double> _synEyeRight = <double>[0.62249, 0.52253, 0.06942, 0.08413, -0.02957];

const List<double> _synHornLeft = <double>[
  0.21447, 0.45817, 0.21052, 0.46266, 0.20722, 0.47160,
  0.20141, 0.47385, 0.18914, 0.47860, 0.17459, 0.46422,
  0.16733, 0.45635, 0.14450, 0.43159, 0.13059, 0.39849,
  0.11411, 0.36943, 0.08659, 0.37506, 0.09462, 0.46385,
  0.09861, 0.48169, 0.11593, 0.55919, 0.17690, 0.60453,
  0.25726, 0.59093,
];

const List<double> _synHornRight = <double>[
  0.70048, 0.43474, 0.80067, 0.47673, 0.87880, 0.41223,
  0.89933, 0.31568, 0.90395, 0.29395, 0.91276, 0.23440,
  0.89467, 0.21645, 0.87517, 0.22541, 0.83831, 0.28230,
  0.81674, 0.30084, 0.80838, 0.30802, 0.79045, 0.32344,
  0.77798, 0.31795, 0.77384, 0.31613, 0.77129, 0.30693,
  0.76757, 0.30346,
];

const List<double> _synGroovesLeft = <double>[
  0.16875, 0.53759, 0.16067, 0.55376, 0.15424, 0.56212, 0.13441, 0.56212, 0.00540,
  0.19440, 0.52644, 0.19440, 0.53738, 0.17841, 0.57996, 0.16340, 0.57996, 0.00677,
  0.21113, 0.53424, 0.21113, 0.54989, 0.21447, 0.59765, 0.21447, 0.60204, 0.00642,
];

const List<double> _synGroovesRight = <double>[
  0.78316, 0.38482, 0.78316, 0.40578, 0.78316, 0.43762, 0.78316, 0.45708, 0.00571,
  0.80546, 0.37925, 0.80546, 0.40847, 0.82440, 0.41882, 0.84323, 0.42824, 0.00576,
  0.84226, 0.37925, 0.84926, 0.39326, 0.85564, 0.40529, 0.85564, 0.41582, 0.00422,
];

final Path _synFacePath = _synRoundedPolygon(_synFaceVertices, _synFaceRadii);
final Path _synHornsPath = _synBuildHorns();
final Path _synEyesPath = _synBuildEyes();
final List<_SynGroove> _synGrooves = _synBuildGrooves();

Offset _synUnit(Offset o) => o / o.distance;

double _synRoundPx(double v, double dpr) => (v * dpr).roundToDouble() / dpr;

void _synCubic(Path path, Offset a, Offset b, Offset c) {
  path.cubicTo(a.dx, a.dy, b.dx, b.dy, c.dx, c.dy);
}

Path _synRoundedPolygon(List<Offset> v, List<double> r) {
  final int n = v.length;
  final List<Offset> start = <Offset>[];
  final List<Offset> end = <Offset>[];
  final List<Offset> c1 = <Offset>[];
  final List<Offset> c2 = <Offset>[];
  for (int i = 0; i < n; i++) {
    final Offset q = v[i];
    final Offset a = _synUnit(v[(i + n - 1) % n] - q);
    final Offset b = _synUnit(v[(i + 1) % n] - q);
    final double cosTheta = math.min(1.0, math.max(-1.0, a.dx * b.dx + a.dy * b.dy));
    final double theta = math.acos(cosTheta);
    final double t = r[i] / math.tan(theta / 2.0);
    final double k = 4.0 / 3.0 * math.tan((math.pi - theta) / 4.0) * r[i];
    start.add(q + a * t);
    end.add(q + b * t);
    c1.add(start[i] - a * k);
    c2.add(end[i] - b * k);
  }
  final Path path = Path()..moveTo(end[0].dx, end[0].dy);
  for (int i = 1; i < n; i++) {
    path.lineTo(start[i].dx, start[i].dy);
    _synCubic(path, c1[i], c2[i], end[i]);
  }
  path.lineTo(start[0].dx, start[0].dy);
  _synCubic(path, c1[0], c2[0], end[0]);
  path.close();
  return path;
}

void _synAddHorn(Path path, List<double> d) {
  path.moveTo(d[0], d[1]);
  for (int i = 2; i + 5 < d.length; i += 6) {
    path.cubicTo(d[i], d[i + 1], d[i + 2], d[i + 3], d[i + 4], d[i + 5]);
  }
  path.close();
}

Path _synBuildHorns() {
  final Path path = Path();
  _synAddHorn(path, _synHornLeft);
  _synAddHorn(path, _synHornRight);
  return path;
}

void _synAddEllipse(Path path, List<double> e) {
  final double cx = e[0];
  final double cy = e[1];
  final double rx = e[2];
  final double ry = e[3];
  final double cr = math.cos(e[4]);
  final double sr = math.sin(e[4]);
  final double k = 4.0 / 3.0 * math.tan(math.pi / 8.0);
  Offset synPt(double x, double y) =>
      Offset(cx + x * cr - y * sr, cy + x * sr + y * cr);
  final Offset first = synPt(rx, 0);
  path.moveTo(first.dx, first.dy);
  _synCubic(path, synPt(rx, ry * k), synPt(rx * k, ry), synPt(0, ry));
  _synCubic(path, synPt(-rx * k, ry), synPt(-rx, ry * k), synPt(-rx, 0));
  _synCubic(path, synPt(-rx, -ry * k), synPt(-rx * k, -ry), synPt(0, -ry));
  _synCubic(path, synPt(rx * k, -ry), synPt(rx, -ry * k), synPt(rx, 0));
  path.close();
}

Path _synBuildEyes() {
  final Path path = Path();
  _synAddEllipse(path, _synEyeLeft);
  _synAddEllipse(path, _synEyeRight);
  return path;
}

class _SynGroove {
  const _SynGroove(this.path, this.width);

  final Path path;
  final double width;
}

List<_SynGroove> _synBuildGrooves() {
  final List<_SynGroove> out = <_SynGroove>[];
  for (final List<double> d in <List<double>>[_synGroovesLeft, _synGroovesRight]) {
    for (int i = 0; i + 8 < d.length; i += 9) {
      final Path p = Path()
        ..moveTo(d[i], d[i + 1])
        ..cubicTo(d[i + 2], d[i + 3], d[i + 4], d[i + 5], d[i + 6], d[i + 7]);
      out.add(_SynGroove(p, d[i + 8]));
    }
  }
  return out;
}

/// The Syntoxan mascot, drawn without any background plate.
///
/// Black in light mode and white in dark mode unless [color] is given. The eyes
/// and horn grooves are real transparent cut-outs, so the background shows
/// through them.
class SynMascotIcon extends StatelessWidget {
  const SynMascotIcon({super.key, this.size, this.color});

  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final double s = size ?? iconTheme.size ?? 24.0;
    final double dpr = MediaQuery.devicePixelRatioOf(context);
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color mascotColor = color ?? (isDark ? synFaceColor : synPlateColor);
    return Semantics(
      label: 'Syntoxan mascot',
      image: true,
      child: RepaintBoundary(
        child: SizedBox(
          width: s,
          height: s,
          child: CustomPaint(painter: _SynMascotPainter(mascotColor, dpr)),
        ),
      ),
    );
  }
}

class _SynMascotPainter extends CustomPainter {
  const _SynMascotPainter(this.color, this.dpr);

  final Color color;
  final double dpr;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) {
      return;
    }
    final double s = math.min(size.width, size.height);
    final double left = _synRoundPx((size.width - s) / 2.0, dpr);
    // Centre the visible mascot (not the empty unit square) vertically.
    final double top = _synRoundPx(size.height / 2.0 - _synContentCenterY * s, dpr);

    final Paint fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;
    // Cut-out paint: removes whatever was drawn underneath inside this layer.
    final Paint eyes = Paint()
      ..color = const Color(0xFF000000)
      ..style = PaintingStyle.fill
      ..blendMode = BlendMode.dstOut
      ..isAntiAlias = true;

    canvas.saveLayer(Offset.zero & size, Paint());

    canvas.save();
    canvas.translate(left, top);
    canvas.scale(s, s);
    canvas.drawPath(_synHornsPath, fill);
    canvas.drawPath(_synFacePath, fill);

    canvas.save();
    canvas.clipPath(_synHornsPath);
    for (final _SynGroove g in _synGrooves) {
      final double physical = g.width * s * dpr;
      final double coverage = math.min(1.0, math.max(0.0, physical / 1.0));
      final int alpha = (coverage * 255.0).round();
      final Paint groove = Paint()
        ..color = Color.fromARGB(alpha, 0, 0, 0)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = math.max(g.width, 1.0 / (dpr * s))
        ..blendMode = BlendMode.dstOut
        ..isAntiAlias = true;
      canvas.drawPath(g.path, groove);
    }
    canvas.restore();

    canvas.drawPath(_synEyesPath, eyes);
    canvas.restore();

    canvas.restore(); // saveLayer
  }

  @override
  bool shouldRepaint(covariant _SynMascotPainter oldDelegate) =>
      oldDelegate.dpr != dpr || oldDelegate.color != color;
}
