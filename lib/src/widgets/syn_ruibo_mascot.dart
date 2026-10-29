import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

// ----------------------------------------------------------------------------
//  TUNING (change here only)
// ----------------------------------------------------------------------------

/// Where (0..1 of widget height) the optical centre of the head sits.
/// 0.5 = head centre is exactly on the AppBar title centre line.
const double _synContentCenterY = 0.5;

/// How many head-space units fit into the widget side (smaller = bigger robot).
const double _kViewSpan = 2.9;

/// Head-space point that lands in the widget centre.
const double _kViewCx = -0.10;
const double _kViewCy = -0.04;

/// Camera distance in head-space units (fov ~ 24deg look).
const double _kCamDist = 7.0;

/// true = exact perspective homography on the glass, false = affine fallback.
const bool kSynScreenPerspective = true;

/// Number of bars shown in the battery face.
const int kSynBatteryBars = 4;

/// Snap a logical size to the physical pixel grid (razor sharp edges).
double _synRoundPx(double v, double dpr) => (v * dpr).roundToDouble() / dpr;

// ----------------------------------------------------------------------------
//  PUBLIC WIDGET
// ----------------------------------------------------------------------------

enum SynRuiBoFace { happy, battery }

class SynRuiBoMascot extends StatefulWidget {
  const SynRuiBoMascot({
    super.key,
    this.size = 44.0,
    this.animate = false,
    this.tapToToggle = false,
    this.initialFace = SynRuiBoFace.happy,
    this.onTap,
  });

  final double size;
  final bool animate;
  final bool tapToToggle;
  final SynRuiBoFace initialFace;
  final VoidCallback? onTap;

  @override
  State<SynRuiBoMascot> createState() => _SynRuiBoMascotState();
}

class _SynRuiBoMascotState extends State<SynRuiBoMascot>
    with TickerProviderStateMixin {
  late SynRuiBoFace _face = widget.initialFace;
  AnimationController? _ctrl;
  final _SynPictureCache _cache = _SynPictureCache();

  @override
  void initState() {
    super.initState();
    _syncAnim();
  }

  @override
  void didUpdateWidget(covariant SynRuiBoMascot oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnim();
  }

  void _syncAnim() {
    if (widget.animate && _ctrl == null) {
      _ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 4200),
      )..repeat();
    } else if (!widget.animate && _ctrl != null) {
      _ctrl!.dispose();
      _ctrl = null;
    }
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (widget.tapToToggle) {
      setState(() {
        _face = _face == SynRuiBoFace.happy
            ? SynRuiBoFace.battery
            : SynRuiBoFace.happy;
      });
    }
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final px = _synRoundPx(widget.size, dpr);
    Widget child = RepaintBoundary(
      child: CustomPaint(
        size: Size(px, px),
        isComplex: true,
        willChange: widget.animate,
        painter: _SynRuiBoPainter(face: _face, cache: _cache, phase: _ctrl),
      ),
    );
    if (widget.tapToToggle || widget.onTap != null) {
      child = GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _handleTap,
        child: child,
      );
    }
    return SizedBox(width: px, height: px, child: child);
  }
}

class _SynPictureCache {
  ui.Picture? _pic;
  Size? _size;
  SynRuiBoFace? _face;

  void paint(Canvas canvas, Size size, SynRuiBoFace face) {
    if (_pic == null || _size != size || _face != face) {
      final rec = ui.PictureRecorder();
      final c = Canvas(rec);
      _SynRuiBoRenderer(size).paint(c, face);
      _pic = rec.endRecording();
      _size = size;
      _face = face;
    }
    canvas.drawPicture(_pic!);
  }
}

class _SynRuiBoPainter extends CustomPainter {
  _SynRuiBoPainter({required this.face, required this.cache, this.phase})
      : super(repaint: phase);

  final SynRuiBoFace face;
  final _SynPictureCache cache;
  final Animation<double>? phase;

  @override
  void paint(Canvas canvas, Size size) {
    final p = phase;
    if (p != null) {
      final t = p.value * 2 * math.pi;
      _SynRuiBoRenderer(
        size,
        rx: 0.05 + 0.010 * math.sin(t),
        ry: 0.22 + 0.050 * math.sin(t),
        rz: 0.14 + 0.020 * math.sin(t + 1.1),
      ).paint(canvas, face);
      return;
    }
    cache.paint(canvas, size, face);
  }

  @override
  bool shouldRepaint(covariant _SynRuiBoPainter old) =>
      old.face != face || old.phase != phase || !identical(old.cache, cache);
}

// ----------------------------------------------------------------------------
//  MATH: vectors, matrices, camera
// ----------------------------------------------------------------------------

/// cos(k * 7.5deg), k = 0..12  (sin(k * 7.5deg) == table[12 - k])
const List<double> _kQuarterCos = <double>[
  1.0, 0.9914448614, 0.9659258263, 0.9238795325, 0.8660254038,
  0.7933533403, 0.7071067812, 0.6087614290, 0.5, 0.3826834324,
  0.2588190451, 0.1305261922, 0.0,
];

const List<double> _kIdent = <double>[1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0];

class _V3 {
  const _V3(this.x, this.y, this.z);
  final double x, y, z;

  _V3 operator +(_V3 o) => _V3(x + o.x, y + o.y, z + o.z);
  _V3 operator -(_V3 o) => _V3(x - o.x, y - o.y, z - o.z);
  double dot(_V3 o) => x * o.x + y * o.y + z * o.z;
  _V3 cross(_V3 o) =>
      _V3(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  _V3 get unit {
    final l = math.sqrt(x * x + y * y + z * z);
    return l < 1e-9 ? this : _V3(x / l, y / l, z / l);
  }
}

List<double> _mul3(List<double> a, List<double> b) {
  final r = List<double>.filled(9, 0.0);
  for (int i = 0; i < 3; i++) {
    for (int j = 0; j < 3; j++) {
      double s = 0.0;
      for (int k = 0; k < 3; k++) {
        s += a[i * 3 + k] * b[k * 3 + j];
      }
      r[i * 3 + j] = s;
    }
  }
  return r;
}

/// Same Euler order as Three.js 'XYZ':  R = Rx * Ry * Rz
List<double> _rotXYZ(double rx, double ry, double rz) {
  final cx = math.cos(rx), sx = math.sin(rx);
  final cy = math.cos(ry), sy = math.sin(ry);
  final cz = math.cos(rz), sz = math.sin(rz);
  final ryz = _mul3(
    <double>[cy, 0.0, sy, 0.0, 1.0, 0.0, -sy, 0.0, cy],
    <double>[cz, -sz, 0.0, sz, cz, 0.0, 0.0, 0.0, 1.0],
  );
  return _mul3(<double>[1.0, 0.0, 0.0, 0.0, cx, -sx, 0.0, sx, cx], ryz);
}

/// Rotation about a pivot (head turns around the neck).
class _Xf {
  const _Xf(this.m, this.pivot);
  final List<double> m;
  final _V3 pivot;

  _V3 dir(_V3 v) => _V3(
        m[0] * v.x + m[1] * v.y + m[2] * v.z,
        m[3] * v.x + m[4] * v.y + m[5] * v.z,
        m[6] * v.x + m[7] * v.y + m[8] * v.z,
      );
  _V3 pos(_V3 p) => dir(p - pivot) + pivot;
}

const _V3 _kNeckPivot = _V3(0, -0.85, 0);

/// Local frame: rotate about Z then translate.
class _Frame {
  const _Frame(this.o, this.a);
  final _V3 o;
  final double a;
  _V3 d(_V3 v) {
    final c = math.cos(a), s = math.sin(a);
    return _V3(v.x * c - v.y * s, v.x * s + v.y * c, v.z);
  }

  _V3 p(_V3 v) => d(v) + o;
}

class _Cam {
  _Cam(Size s) : this._(s, math.min(s.width, s.height) / _kViewSpan);
  _Cam._(Size s, double u)
      : scale = u,
        ox = s.width / 2 - _kViewCx * u,
        oy = s.height * _synContentCenterY + _kViewCy * u;

  final double scale, ox, oy;

  Offset proj(_V3 q) {
    final k = _kCamDist / (_kCamDist - q.z);
    return Offset(ox + q.x * k * scale, oy - q.y * k * scale);
  }
}


class _Rgb {
  const _Rgb(this.r, this.g, this.b);
  final double r, g, b;
  _Rgb lerp(_Rgb o, double t) =>
      _Rgb(r + (o.r - r) * t, g + (o.g - g) * t, b + (o.b - b) * t);
}

class _Mat {
  const _Mat(this.spec, this.shin, this.rim);
  final double spec, shin, rim;
}

const _Rgb _kShellAlb = _Rgb(100, 105, 116);
const _Rgb _kBezelAlb = _Rgb(122, 127, 137);
const _Rgb _kEarAlb = _Rgb(126, 129, 136);
const _Rgb _kEarHi = _Rgb(150, 154, 162);
const _Rgb _kEarInner = _Rgb(74, 76, 82);
const _Rgb _kEarInnerTop = _Rgb(98, 100, 107);
const _Rgb _kDarkRing = _Rgb(30, 31, 35);
const _Rgb _kHornBase = _Rgb(120, 124, 132);
const _Rgb _kHornDark = _Rgb(34, 35, 40);
const _Rgb _kBodyAlb = _Rgb(76, 78, 87);

const _Mat _kMatShell = _Mat(0.10, 16.0, 0.30);
const _Mat _kMatEar = _Mat(0.25, 28.0, 0.25);
const _Mat _kMatMetal = _Mat(0.40, 40.0, 0.30);
const _Mat _kMatHorn = _Mat(0.60, 55.0, 0.35);
const _Mat _kMatBody = _Mat(0.07, 12.0, 0.25);
const _Mat _kMatDark = _Mat(0.04, 10.0, 0.0);

const _V3 _kKey = _V3(-0.358, 0.597, 0.717);
const _V3 _kFill = _V3(0.770, 0.154, 0.617);
const _V3 _kBack = _V3(0.0, 0.625, -0.780);

double _pow(double b, double e) => math.pow(b, e).toDouble();

int _b8(double v) {
  final i = v.round();
  return i < 0 ? 0 : (i > 255 ? 255 : i);
}

Color _c(double r, double g, double b) =>
    Color.fromARGB(255, _b8(r), _b8(g), _b8(b));

double _smooth(double e0, double e1, double x) {
  double t = (x - e0) / (e1 - e0);
  t = t < 0.0 ? 0.0 : (t > 1.0 ? 1.0 : t);
  return t * t * (3.0 - 2.0 * t);
}

/// n, v: unit vectors in camera space (v points to the camera)
Color _shade(_Rgb a, _V3 n, _V3 v, _Mat m) {
  final amb = 0.62 + 0.14 * n.y;
  final k = math.max(0.0, n.dot(_kKey));
  final f = math.max(0.0, n.dot(_kFill));
  final b = math.max(0.0, n.dot(_kBack));
  final diff = amb + 0.46 * k + 0.18 * f + 0.16 * b;
  final h = (_kKey + v).unit;
  final sp = m.spec * _pow(math.max(0.0, n.dot(h)), m.shin);
  final nv = math.max(0.0, n.dot(v));
  final rim = m.rim * _pow(1.0 - nv, 3.0) * (0.35 + 0.65 * (n.y * 0.5 + 0.5));
  return _c(
    a.r * diff + 255.0 * sp + 150.0 * rim,
    a.g * diff + 255.0 * sp + 158.0 * rim,
    a.b * diff + 255.0 * sp + 175.0 * rim,
  );
}

// ----------------------------------------------------------------------------
//  MESH BUILDING
// ----------------------------------------------------------------------------

class _Poly {
  _Poly(this.pts, this.nrm, this.albedo, this.mat);
  final List<_V3> pts;
  final List<_V3> nrm;
  final _Rgb albedo;
  final _Mat mat;
}

/// Generic parametric grid -> quads.  i = around (u), j = along (v).
List<_Poly> _grid({
  required int nu,
  required int nv,
  required bool wrap,
  required _V3 Function(int i, int j) pos,
  required _V3 Function(int i, int j) nor,
  required _Rgb Function(int j) albedo,
  required _Mat mat,
}) {
  final out = <_Poly>[];
  final iMax = wrap ? nu : nu - 1;
  for (int j = 0; j < nv; j++) {
    for (int i = 0; i < iMax; i++) {
      final i2 = (i + 1) % nu;
      out.add(_Poly(
        <_V3>[pos(i, j), pos(i2, j), pos(i2, j + 1), pos(i, j + 1)],
        <_V3>[nor(i, j), nor(i2, j), nor(i2, j + 1), nor(i, j + 1)],
        albedo(j),
        mat,
      ));
    }
  }
  return out;
}

List<_Poly> _box(_V3 c, _V3 h, _Rgb alb, _Mat mat) {
  _Poly face(_V3 n, _V3 u, _V3 v) {
    final o = c + _V3(n.x * h.x, n.y * h.y, n.z * h.z);
    return _Poly(
      <_V3>[o + u + v, o - u + v, o - u - v, o + u - v],
      <_V3>[n, n, n, n],
      alb,
      mat,
    );
  }

  final ex = _V3(h.x, 0, 0), ey = _V3(0, h.y, 0), ez = _V3(0, 0, h.z);
  return <_Poly>[
    face(const _V3(1, 0, 0), ey, ez),
    face(const _V3(-1, 0, 0), ey, ez),
    face(const _V3(0, 1, 0), ex, ez),
    face(const _V3(0, -1, 0), ex, ez),
    face(const _V3(0, 0, 1), ex, ey),
    face(const _V3(0, 0, -1), ex, ey),
  ];
}

const double _kHw = 0.83; // 1.66 / 2
const double _kHh = 0.68; // 1.36 / 2
const double _kR = 0.50;
const double _kBevel = 0.22;
const double _kHalfDepth = 0.25;

_V3 _rrDir(int i) {
  final k = i ~/ 13, s = i % 13;
  final c = _kQuarterCos[s], sn = _kQuarterCos[12 - s];
  switch (k) {
    case 0:
      return _V3(c, sn, 0);
    case 1:
      return _V3(-sn, c, 0);
    case 2:
      return _V3(-c, -sn, 0);
    default:
      return _V3(sn, -c, 0);
  }
}

/// Point i of the offset rounded-rect (corner centres stay fixed, radius grows).
_V3 _rrPoint(int i, double hw, double hh, double r, double off, double z,
    double cy) {
  final d = _rrDir(i);
  final k = i ~/ 13;
  final cxs = (k == 0 || k == 3) ? hw - r : -(hw - r);
  final cys = (k == 0 || k == 1) ? hh - r : -(hh - r);
  final rad = r + off;
  return _V3(cxs + rad * d.x, cys + rad * d.y + cy, z);
}

List<_Poly> _buildHeadShell() {
  // profile rows: [offset, z, normalRadial, normalZ]  (quarter-circle bevels)
  final prof = <List<double>>[];
  const nb = 6, nf = 8;
  for (int k = 0; k <= nb; k++) {
    final a = (k / nb) * math.pi / 2;
    prof.add(<double>[
      _kBevel * math.sin(a),
      -_kHalfDepth - _kBevel * math.cos(a),
      math.sin(a),
      -math.cos(a),
    ]);
  }
  for (int k = 0; k <= nf; k++) {
    final a = (1 - k / nf) * math.pi / 2;
    prof.add(<double>[
      _kBevel * math.sin(a),
      _kHalfDepth + _kBevel * math.cos(a),
      math.sin(a),
      math.cos(a),
    ]);
  }
  return _grid(
    nu: 52,
    nv: prof.length - 1,
    wrap: true,
    pos: (i, j) {
      final p = prof[j];
      return _rrPoint(i, _kHw, _kHh, _kR, p[0], p[1], 0.0);
    },
    nor: (i, j) {
      final p = prof[j];
      final d = _rrDir(i);
      return _V3(d.x * p[2], d.y * p[2], p[3]);
    },
    albedo: (j) {
      final zc = (prof[j][1] + prof[j + 1][1]) * 0.5;
      return _kShellAlb.lerp(_kBezelAlb, _smooth(0.20, 0.30, zc));
    },
    mat: _kMatShell,
  );
}

List<_Poly> _buildEar(double s) {
  const int nu = 32;
  const double r = 0.33, z0 = -0.05;

  _V3 pt(int i, double rad, double x) {
    final a = 2 * math.pi * i / nu;
    return _V3(s * x, rad * math.cos(a), z0 + rad * math.sin(a));
  }

  _V3 radial(int i) {
    final a = 2 * math.pi * i / nu;
    return _V3(0, math.cos(a), math.sin(a));
  }

  final face = _V3(s, 0, 0);
  final out = <_Poly>[];

  out.addAll(_grid(
    nu: nu,
    nv: 1,
    wrap: true,
    pos: (i, j) => pt(i, r, 1.04 + 0.16 * j),
    nor: (i, j) => radial(i),
    albedo: (j) => _kEarAlb,
    mat: _kMatEar,
  ));

  void ring(double r0, double r1, double x, _Rgb alb, _Mat mat) {
    out.addAll(_grid(
      nu: nu,
      nv: 1,
      wrap: true,
      pos: (i, j) => pt(i, r0 + (r1 - r0) * j, x),
      nor: (i, j) => face,
      albedo: (j) => alb,
      mat: mat,
    ));
  }

  ring(0.330, 0.295, 1.20, _kEarHi, _kMatEar); // bevel edge
  ring(0.295, 0.250, 1.20, _kEarAlb, _kMatEar); // pad face
  ring(0.250, 0.190, 1.20, _kDarkRing, _kMatDark); // recessed dark ring

  out.addAll(_grid(
    nu: nu,
    nv: 1,
    wrap: true,
    pos: (i, j) => pt(i, 0.19, 1.20 + 0.03 * j),
    nor: (i, j) => radial(i),
    albedo: (j) => _kEarInner,
    mat: _kMatEar,
  ));
  ring(0.190, 0.0, 1.23, _kEarInnerTop, _kMatEar); // inner disc top

  // thin vertical blade sticking up from the outer edge of the ear
  out.addAll(_box(_V3(s * 1.255, 0.30, -0.03), const _V3(0.022, 0.16, 0.085),
      _kEarAlb, _kMatEar));
  return out;
}

List<_Poly> _buildHorn(double s) {
  final f = _Frame(_V3(s * 0.60, 0.84, -0.10), -s * 0.30);
  final out = <_Poly>[];
  const int nu = 24;
  double ang(int i, int n) => 2 * math.pi * i / n;

  // flat disc / annulus (kx, kz = oval axes)
  void disc(double y, double r0, double r1, double kx, double kz, _Rgb alb,
      _Mat mat) {
    out.addAll(_grid(
      nu: nu,
      nv: 1,
      wrap: true,
      pos: (i, j) {
        final a = ang(i, nu);
        final r = r0 + (r1 - r0) * j;
        return f.p(_V3(r * kx * math.cos(a), y, r * kz * math.sin(a)));
      },
      nor: (i, j) => f.d(const _V3(0, 1, 0)),
      albedo: (j) => alb,
      mat: mat,
    ));
  }

  // 1) oval metallic base
  out.addAll(_grid(
    nu: nu,
    nv: 1,
    wrap: true,
    pos: (i, j) {
      final a = ang(i, nu);
      return f.p(_V3(0.150 * math.cos(a), 0.045 * j, 0.105 * math.sin(a)));
    },
    nor: (i, j) {
      final a = ang(i, nu);
      return f.d(_V3(math.cos(a) / 0.150, 0, math.sin(a) / 0.105).unit);
    },
    albedo: (j) => _kHornBase,
    mat: _kMatMetal,
  ));
  disc(0.045, 1.0, 0.0, 0.150, 0.105, _kHornBase, _kMatMetal);

  // 2) step ring
  out.addAll(_grid(
    nu: nu,
    nv: 1,
    wrap: true,
    pos: (i, j) {
      final a = ang(i, nu);
      return f.p(
          _V3(0.105 * math.cos(a), 0.045 + 0.040 * j, 0.105 * math.sin(a)));
    },
    nor: (i, j) {
      final a = ang(i, nu);
      return f.d(_V3(math.cos(a), 0, math.sin(a)));
    },
    albedo: (j) => _kHornDark,
    mat: _kMatHorn,
  ));
  disc(0.085, 0.105, 0.092, 1.0, 1.0, _kHornDark, _kMatHorn);

  // 3) ribbed tapered cone (8 molded ridges)
  const int ridges = 8, nuC = 32;
  const double y0 = 0.085, hC = 0.165, rBot = 0.092, rTop = 0.064;
  const double amp = 0.09;
  const double slope = (rTop - rBot) / hC;
  out.addAll(_grid(
    nu: nuC,
    nv: 3,
    wrap: true,
    pos: (i, j) {
      final a = 2 * math.pi * i / nuC;
      final t = j / 3;
      final rr = (rBot + (rTop - rBot) * t) * (1 + amp * math.cos(ridges * a));
      return f.p(_V3(rr * math.cos(a), y0 + hC * t, rr * math.sin(a)));
    },
    nor: (i, j) {
      final a = 2 * math.pi * i / nuC;
      final t = j / 3;
      final r0 = rBot + (rTop - rBot) * t;
      final q = 1 + amp * math.cos(ridges * a);
      final rr = r0 * q;
      final dR = -r0 * amp * ridges * math.sin(ridges * a);
      final ty = _V3(slope * q * math.cos(a), 1, slope * q * math.sin(a));
      final tp = _V3(dR * math.cos(a) - rr * math.sin(a), 0,
          dR * math.sin(a) + rr * math.cos(a));
      return f.d(ty.cross(tp).unit);
    },
    albedo: (j) => _kHornDark,
    mat: _kMatHorn,
  ));

  // 4) rounded cap
  const double rc = 0.066;
  out.addAll(_grid(
    nu: nu,
    nv: 4,
    wrap: true,
    pos: (i, j) {
      final a = ang(i, nu);
      final t = (j / 4) * math.pi / 2;
      return f.p(_V3(rc * math.cos(t) * math.cos(a), y0 + hC + rc * math.sin(t),
          rc * math.cos(t) * math.sin(a)));
    },
    nor: (i, j) {
      final a = ang(i, nu);
      final t = (j / 4) * math.pi / 2;
      return f.d(
          _V3(math.cos(t) * math.cos(a), math.sin(t), math.cos(t) * math.sin(a)));
    },
    albedo: (j) => _kHornDark,
    mat: _kMatHorn,
  ));
  return out;
}

List<_Poly> _buildBody() {
  final out = <_Poly>[];

  // torso (ellipsoid, extends below the frame so the bust is cleanly cropped)
  const int nu = 32, nvT = 16;
  const double cy = -1.15, rx = 0.62, ry = 0.55, rz = 0.50;
  out.addAll(_grid(
    nu: nu,
    nv: nvT,
    wrap: true,
    pos: (i, j) {
      final a = 2 * math.pi * i / nu, t = math.pi * j / nvT;
      return _V3(rx * math.sin(t) * math.cos(a), cy + ry * math.cos(t),
          rz * math.sin(t) * math.sin(a));
    },
    nor: (i, j) {
      final a = 2 * math.pi * i / nu, t = math.pi * j / nvT;
      return _V3(math.sin(t) * math.cos(a) / rx, math.cos(t) / ry,
              math.sin(t) * math.sin(a) / rz)
          .unit;
    },
    albedo: (j) => _kBodyAlb,
    mat: _kMatBody,
  ));

  // neck
  out.addAll(_grid(
    nu: 20,
    nv: 1,
    wrap: true,
    pos: (i, j) {
      final a = 2 * math.pi * i / 20;
      return _V3(0.24 * math.cos(a), -1.0 + 0.30 * j, 0.24 * math.sin(a));
    },
    nor: (i, j) {
      final a = 2 * math.pi * i / 20;
      return _V3(math.cos(a), 0, math.sin(a));
    },
    albedo: (j) => _kBodyAlb,
    mat: _kMatBody,
  ));

  // arms (capsules, curved slightly inward)
  for (final s in const <double>[-1.0, 1.0]) {
    final f = _Frame(_V3(s * 0.52, -0.87, 0), -s * 0.10);
    const double r = 0.14, len = 0.72;
    out.addAll(_grid(
      nu: 20,
      nv: 1,
      wrap: true,
      pos: (i, j) {
        final a = 2 * math.pi * i / 20;
        return f.p(_V3(r * math.cos(a), -len * j, r * math.sin(a)));
      },
      nor: (i, j) {
        final a = 2 * math.pi * i / 20;
        return f.d(_V3(math.cos(a), 0, math.sin(a)));
      },
      albedo: (j) => _kBodyAlb,
      mat: _kMatBody,
    ));
    out.addAll(_grid(
      nu: 20,
      nv: 4,
      wrap: true,
      pos: (i, j) {
        final a = 2 * math.pi * i / 20;
        final t = (j / 4) * math.pi / 2;
        return f.p(_V3(r * math.cos(t) * math.cos(a), r * math.sin(t),
            r * math.cos(t) * math.sin(a)));
      },
      nor: (i, j) {
        final a = 2 * math.pi * i / 20;
        final t = (j / 4) * math.pi / 2;
        return f.d(_V3(
            math.cos(t) * math.cos(a), math.sin(t), math.cos(t) * math.sin(a)));
      },
      albedo: (j) => _kBodyAlb,
      mat: _kMatBody,
    ));
  }
  return out;
}

/// Built once, shared by every widget instance.
class _Mesh {
  _Mesh._();
  static final _Mesh instance = _Mesh._();

  final List<_Poly> headShell = _buildHeadShell();
  final List<_Poly> earR = _buildEar(1.0);
  final List<_Poly> earL = _buildEar(-1.0);
  final List<_Poly> horns = <_Poly>[..._buildHorn(-1.0), ..._buildHorn(1.0)];
  final List<_Poly> body = _buildBody();
}

class _Draw {
  _Draw(this.path, this.color, this.z);
  final Path path;
  final Color color;
  final double z;
}

class _SynRuiBoRenderer {
  _SynRuiBoRenderer(
    this.size, {
    double rx = 0.05,
    double ry = 0.22,
    double rz = 0.14,
  })  : cam = _Cam(size),
        head = _Xf(_rotXYZ(rx, ry, rz), _kNeckPivot);

  final Size size;
  final _Cam cam;
  final _Xf head;
  final _Xf body = const _Xf(_kIdent, _V3(0, 0, 0));

  void paint(Canvas canvas, SynRuiBoFace face) {
    final m = _Mesh.instance;
    canvas.save();
    canvas.clipRect(Offset.zero & size);

    _paintRim(canvas);
    _drawPolys(canvas, m.earR, head); // far ear first
    _drawPolys(canvas, m.body, body);
    _paintHeadShadow(canvas);
    _drawPolys(canvas, m.headShell, head);
    _paintFrontCap(canvas);
    _drawPolys(canvas, m.horns, head);
    _drawPolys(canvas, m.earL, head); // near ear last
    _paintLipAndScreen(canvas, face);

    canvas.restore();
  }

  // ---- generic mesh drawing (cull + painter's sort + lighting) -------------

  void _drawPolys(Canvas canvas, List<_Poly> polys, _Xf xf) {
    final items = <_Draw>[];
    for (final poly in polys) {
      final n = poly.pts.length;
      double sx = 0.0, sy = 0.0, sz = 0.0;
      double nx = 0.0, ny = 0.0, nz = 0.0;
      final pr = <Offset>[];
      for (int k = 0; k < n; k++) {
        final p = xf.pos(poly.pts[k]);
        sx += p.x;
        sy += p.y;
        sz += p.z;
        final d = poly.nrm[k];
        nx += d.x;
        ny += d.y;
        nz += d.z;
        pr.add(cam.proj(p));
      }
      final c = _V3(sx / n, sy / n, sz / n);
      final nn = xf.dir(_V3(nx, ny, nz)).unit;
      final v = (const _V3(0, 0, _kCamDist) - c).unit;
      if (nn.dot(v) < -0.10) {
        continue;
      }
      items.add(_Draw(
        Path()..addPolygon(pr, true),
        _shade(poly.albedo, nn, v, poly.mat),
        c.z,
      ));
    }
    items.sort((a, b) => a.z.compareTo(b.z));

    final fill = Paint()..isAntiAlias = true;
    final seam = Paint()
      ..isAntiAlias = true
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = math.max(0.45, cam.scale * 0.007)
      ..strokeJoin = ui.StrokeJoin.round;
    for (final it in items) {
      fill.color = it.color;
      canvas.drawPath(it.path, fill);
      seam.color = it.color;
      canvas.drawPath(it.path, seam);
    }
  }

  Path _rrPath(double hw, double hh, double r, double off, double z, double cy) {
    final pts = <Offset>[];
    for (int i = 0; i < 52; i++) {
      pts.add(cam.proj(head.pos(_rrPoint(i, hw, hh, r, off, z, cy))));
    }
    return Path()..addPolygon(pts, true);
  }

  // ---- rim backlight (pops on a pitch-black AppBar) ------------------------

  void _paintRim(Canvas canvas) {
    final path = Path();
    for (final z in const <double>[-0.25, 0.25]) {
      path.addPath(_rrPath(_kHw, _kHh, _kR, _kBevel, z, 0.0), Offset.zero);
    }
    final b = path.getBounds();
    canvas.drawPath(
      path,
      Paint()
        ..isAntiAlias = true
        ..style = ui.PaintingStyle.stroke
        ..strokeJoin = ui.StrokeJoin.round
        ..strokeWidth = math.max(1.6, cam.scale * 0.05)
        ..shader = ui.Gradient.linear(
          b.topRight,
          b.bottomLeft,
          const <Color>[Color(0xE07A8294), Color(0xE03A3F4A)],
        ),
    );
  }

  void _paintHeadShadow(Canvas canvas) {
    final p = _rrPath(_kHw, _kHh, _kR, _kBevel, 0.0, -0.10);
    canvas.drawPath(
      p,
      Paint()
        ..color = const Color(0x99000000)
        ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, cam.scale * 0.06),
    );
  }
  
  void _paintFrontCap(Canvas canvas) {
    final path = _rrPath(_kHw, _kHh, _kR, 0.0, 0.47, 0.0);
    final n = head.dir(const _V3(0, 0, 1)).unit;
    final p = head.pos(const _V3(0, 0, 0.47));
    final v = (const _V3(0, 0, _kCamDist) - p).unit;
    canvas.drawPath(
      path,
      Paint()
        ..isAntiAlias = true
        ..color = _shade(_kBezelAlb, n, v, _kMatShell),
    );
    final b = path.getBounds();
    canvas.drawPath(
      path,
      Paint()
        ..isAntiAlias = true
        ..shader = ui.Gradient.linear(
          b.topLeft,
          b.bottomRight,
          const <Color>[Color(0x26FFFFFF), Color(0x00FFFFFF), Color(0x2E000000)],
          const <double>[0.0, 0.5, 1.0],
        ),
    );
  }

  // ---- lip groove + glass visor -------------------------------------------

  void _paintLipAndScreen(Canvas canvas, SynRuiBoFace face) {
    final outer = _rrPath(0.83, 0.64, 0.42, 0.0, 0.468, -0.04);
    final inner = _rrPath(0.79, 0.60, 0.38, 0.0, 0.468, -0.04);
    final ring = Path()
      ..fillType = ui.PathFillType.evenOdd
      ..addPath(outer, Offset.zero)
      ..addPath(inner, Offset.zero);
    canvas.drawPath(
      ring,
      Paint()
        ..isAntiAlias = true
        ..color = const Color(0xFF18191C),
    );

    final ob = outer.getBounds();
    canvas.drawPath(
      outer,
      Paint()
        ..isAntiAlias = true
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = math.max(0.7, cam.scale * 0.010)
        ..shader = ui.Gradient.linear(
          ob.topLeft,
          ob.bottomRight,
          const <Color>[Color(0xD0D3D8E2), Color(0x18D3D8E2)],
        ),
    );

    canvas.save();
    canvas.transform(_screenMatrix());
    const screen = Rect.fromLTRB(0, 0, 632, 480);
    final rr = RRect.fromRectAndRadius(screen, const Radius.circular(152));
    canvas.clipRRect(rr, doAntiAlias: true);
    _paintFace(canvas, face);
    // recessed glass edge shadow
    canvas.drawRRect(
      rr,
      Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 26
        ..color = const Color(0x77000000)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 9),
    );
    canvas.restore();
  }

  _V3 _planePt(double s, double t) =>
      _V3(-0.79 + s * 1.58 / 632.0, 0.56 - t * 1.20 / 480.0, 0.478);

  /// Texture space (632 x 480) -> screen: exact homography through the head
  /// rotation + perspective camera, packed in a column-major 4x4 matrix.
  Float64List _screenMatrix() {
    final m = Float64List(16);
    if (!kSynScreenPerspective) {
      final p0 = cam.proj(head.pos(_planePt(0, 0)));
      final p1 = cam.proj(head.pos(_planePt(632, 0)));
      final p2 = cam.proj(head.pos(_planePt(0, 480)));
      m[0] = (p1.dx - p0.dx) / 632.0;
      m[1] = (p1.dy - p0.dy) / 632.0;
      m[4] = (p2.dx - p0.dx) / 480.0;
      m[5] = (p2.dy - p0.dy) / 480.0;
      m[10] = 1.0;
      m[12] = p0.dx;
      m[13] = p0.dy;
      m[15] = 1.0;
      return m;
    }
    final o = head.pos(_planePt(0, 0));
    final u = head.dir(const _V3(1.58 / 632.0, 0, 0));
    final v = head.dir(const _V3(0, -1.20 / 480.0, 0));
    final sd = cam.scale * _kCamDist;
    final w0 = _kCamDist - o.z;
    final k = 1.0 / w0;
    m[0] = (cam.ox * -u.z + sd * u.x) * k;
    m[1] = (cam.oy * -u.z - sd * u.y) * k;
    m[3] = -u.z * k;
    m[4] = (cam.ox * -v.z + sd * v.x) * k;
    m[5] = (cam.oy * -v.z - sd * v.y) * k;
    m[7] = -v.z * k;
    m[10] = 1.0;
    m[12] = (cam.ox * w0 + sd * o.x) * k;
    m[13] = (cam.oy * w0 - sd * o.y) * k;
    m[15] = 1.0;
    return m;
  }

  // ---- LED visor (texture space 632 x 480) --------------------------------

  ui.Shader _ledShader(double cx, double cy, double r) => ui.Gradient.radial(
        Offset(cx, cy),
        r * 1.05,
        const <Color>[Color(0xFFFFEE55), Color(0xFFFFD51C), Color(0xFFF0A800)],
        const <double>[0.0, 0.6, 1.0],
        ui.TileMode.clamp,
        null,
        Offset(cx, cy - r * 0.15),
        2.0,
      );

  void _dots(Canvas c, Rect bb) {
    final pts = <Offset>[];
    for (double x = bb.left; x < bb.right; x += 10.0) {
      for (double y = bb.top; y < bb.bottom; y += 10.0) {
        pts.add(Offset(x, y));
      }
    }
    c.drawPoints(
      ui.PointMode.points,
      pts,
      Paint()
        ..isAntiAlias = true
        ..color = const Color(0x806E3E00)
        ..strokeWidth = 4.8
        ..strokeCap = ui.StrokeCap.round,
    );
  }

  /// glow bloom + gradient fill + dot-matrix grid clipped inside the shape
  void _lit(Canvas c, Path shape, Rect bb, ui.Shader fill) {
    c.save();
    c.drawPath(
      shape,
      Paint()
        ..color = const Color(0x55FFB400)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 42),
    );
    c.drawPath(
      shape,
      Paint()
        ..color = const Color(0xCCFFC410)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 17),
    );
    c.drawPath(
      shape,
      Paint()
        ..isAntiAlias = true
        ..shader = fill,
    );
    c.clipPath(shape, doAntiAlias: true);
    _dots(c, bb);
    c.restore();
  }

  void _paintFace(Canvas c, SynRuiBoFace face) {
    const rect = Rect.fromLTRB(0, 0, 632, 480);

    // pitch-black CRT glass with a soft top-left reflection
    c.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          const Offset(316, 240),
          400,
          const <Color>[Color(0xFF1E1B1A), Color(0xFF060505), Color(0xFF000000)],
          const <double>[0.0, 0.7, 1.0],
          ui.TileMode.clamp,
          null,
          const Offset(316, 150),
          10.0,
        ),
    );

    if (face == SynRuiBoFace.happy) {
      const eyes = <Offset>[Offset(170, 188), Offset(462, 188)];
      for (final e in eyes) {
        final path = Path()
          ..addOval(Rect.fromCircle(center: e, radius: 86));
        _lit(c, path, Rect.fromLTRB(e.dx - 90, e.dy - 90, e.dx + 90, e.dy + 90),
            _ledShader(e.dx, e.dy, 86));
      }
      final mouth = Path()
        ..moveTo(236, 276)
        ..quadraticBezierTo(316, 262, 396, 276)
        ..quadraticBezierTo(388, 348, 316, 348)
        ..quadraticBezierTo(244, 348, 236, 276)
        ..close();
      _lit(c, mouth, const Rect.fromLTRB(228, 255, 404, 352),
          _ledShader(316, 310, 80));
    } else {
      const double left = 133.0, top = 176.0, w = 340.0, h = 128.0;
      final shader = _ledShader(316, 240, 190);
      final body = Path()
        ..fillType = ui.PathFillType.evenOdd
        ..addRRect(RRect.fromLTRBR(
            left, top, left + w, top + h, const Radius.circular(26)))
        ..addRRect(RRect.fromLTRBR(left + 14, top + 14, left + w - 14,
            top + h - 14, const Radius.circular(13)));
      final term = Path()
        ..addRRect(RRect.fromLTRBR(left + w, top + 40, left + w + 26,
            top + h - 40, const Radius.circular(8)));
      const double gap = 14.0;
      const double inW = w - 56.0;
      const double bw = (inW - gap * (kSynBatteryBars - 1)) / kSynBatteryBars;
      final bars = Path();
      for (int i = 0; i < kSynBatteryBars; i++) {
        final x = left + 28 + i * (bw + gap);
        bars.addRRect(RRect.fromLTRBR(
            x, top + 28, x + bw, top + h - 28, const Radius.circular(6)));
      }
      const bb = Rect.fromLTRB(left, top, left + w + 26, top + h);
      _lit(c, body, bb, shader);
      _lit(c, term, bb, shader);
      _lit(c, bars, bb, shader);
    }
    
    c.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          const Offset(379.2, 288.0),
          const <Color>[Color(0x14FFFFFF), Color(0x00FFFFFF)],
          const <double>[0.0, 0.5],
        ),
    );
    final streak = Path()
      ..moveTo(48, 150)
      ..quadraticBezierTo(70, 70, 160, 48)
      ..quadraticBezierTo(90, 90, 62, 168)
      ..close();
    c.drawPath(streak, Paint()..color = const Color(0x14FFFFFF));
  }
}