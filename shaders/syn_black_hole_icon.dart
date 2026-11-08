// ============================================================================
//  syn_black_hole_icon.dart
//
//  SynBlackHoleIcon: animated GitHub Octocat badge drawn with a CustomPainter.
//  Drop-in replacement: SynBlackHoleIcon({super.key, this.size = 48, this.onTap})
//
//  Dependencies: dart:math, dart:ui, package:flutter/material.dart only.
//
//  Geometry: the official GitHub mark (24x24 grid) is parsed from its exact
//  SVG path data by a small pure-Dart SVG path parser (see _SvgPathParser).
//  The Octocat cavity is derived from the SAME path data (the cat outline is
//  the part of the contour between the two bottom points of the circle), so
//  ears, head and tentacle follow the official contour with zero deviation.
// ============================================================================

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Official GitHub mark, 24x24 grid (exact SVG path data).
// ---------------------------------------------------------------------------
const String _kMarkD =
    'M12 2C6.477 2 2 6.484 2 12.017c0 4.425 2.865 8.18 6.839 9.504.5.092.682-.217.682-.483 0-.237-.008-.868-.013-1.703-2.782.605-3.369-1.343-3.369-1.343-.454-1.158-1.11-1.466-1.11-1.466-.908-.62.069-.608.069-.608 1.003.07 1.53 1.032 1.53 1.032.892 1.53 2.341 1.088 2.91.832.092-.647.35-1.088.636-1.338-2.22-.253-4.555-1.113-4.555-4.951 0-1.093.39-1.988 1.029-2.688-.103-.253-.446-1.272.098-2.65 0 0 .84-.27 2.75 1.026A9.564 9.564 0 0112 6.844c.85.004 1.705.115 2.504.337 1.909-1.296 2.747-1.027 2.747-1.027.546 1.379.202 2.398.1 2.651.64.7 1.028 1.595 1.028 2.688 0 3.848-2.339 4.695-4.566 4.943.359.309.678.92.678 1.855 0 1.338-.012 2.419-.012 2.747 0 .268.18.58.688.482A10.019 10.019 0 0022 12.017C22 6.484 17.522 2 12 2z';

// ---------------------------------------------------------------------------
// Palette
// ---------------------------------------------------------------------------
const Color _kCyan = Color(0xFF00FFFF);
const Color _kViolet = Color(0xFF7B4FD6);
const Color _kOrange = Color(0xFFFF8A4C);
const Color _kVoid = Color(0xFF04050A);
const Color _kIce = Color(0xFFCFFFFF);
const Color _kWhite = Color(0xFFFFFFFF);
const double _kTau = math.pi * 2;

Color _a(Color c, double alpha) =>
    c.withAlpha((alpha.clamp(0.0, 1.0) * 255).round());

/// Rotation of [a] radians about [c], as a 4x4 matrix (for gradient shaders).
Matrix4 _rotAbout(double a, Offset c) {
  final cs = math.cos(a);
  final sn = math.sin(a);
  final tx = c.dx - cs * c.dx + sn * c.dy;
  final ty = c.dy - sn * c.dx - cs * c.dy;
  return Matrix4(
    cs, sn, 0, 0, //
    -sn, cs, 0, 0, //
    0, 0, 1, 0, //
    tx, ty, 0, 1,
  );
}

// ===========================================================================
//  Public widget
// ===========================================================================
class SynBlackHoleIcon extends StatefulWidget {
  const SynBlackHoleIcon({super.key, this.size = 48, this.onTap});

  /// Edge length of the square badge in logical pixels.
  final double size;

  /// Optional tap callback. When non-null, a cyan shockwave plays on tap.
  /// (When null no gesture recognizer is attached, so parent taps still work.)
  final VoidCallback? onTap;

  @override
  State<SynBlackHoleIcon> createState() => _SynBlackHoleIconState();
}

class _SynBlackHoleIconState extends State<SynBlackHoleIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final Stopwatch _clock = Stopwatch()..start();

  double? _tapAt; // seconds on _clock when the last tap happened
  Offset? _tapPos; // local tap position
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce) {
      _reduceMotion = true;
      _controller.stop();
      _controller.value = 0.125; // a nicely lit still frame
    } else {
      _reduceMotion = false;
      if (!_controller.isAnimating) {
        _controller.repeat();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTapDown(TapDownDetails details) {
    if (_reduceMotion) return;
    setState(() {
      _tapAt = _clock.elapsedMicroseconds / 1e6;
      _tapPos = details.localPosition;
    });
  }

  @override
  Widget build(BuildContext context) {
    final geo = _Geo.of(widget.size);

    final Widget icon = SizedBox(
      width: widget.size,
      height: widget.size,
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.square(widget.size),
          isComplex: true,
          willChange: true,
          painter: _SynBlackHolePainter(
            controller: _controller,
            clock: _clock,
            geo: geo,
            tapAt: _tapAt,
            tapPos: _tapPos,
          ),
        ),
      ),
    );

    if (widget.onTap == null) return icon;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: _handleTapDown,
        onTap: widget.onTap,
        child: icon,
      ),
    );
  }
}

// ===========================================================================
//  Pure-Dart SVG path parser
//  Supports: M m L l H h V v C c S s A a Z z (with implicit command repeats,
//  compact numbers like ".5.092" and compact arc flags like "0 0112 6.844").
//  Points are emitted as: dx + gridX * scale, dy + gridY * scale.
// ===========================================================================
class _SvgPathParser {
  _SvgPathParser(
    this._d,
    this._path, {
    this.scale = 1.0,
    this.dx = 0.0,
    this.dy = 0.0,
  });

  final String _d;
  final Path _path;
  final double scale;
  final double dx;
  final double dy;

  int _i = 0;
  double _x = 0, _y = 0; // current point (grid space)
  double _startX = 0, _startY = 0; // current sub-path start (grid space)
  double _ctrlX = 0, _ctrlY = 0; // last cubic control point (grid space)
  bool _prevCubic = false;

  double _px(double gx) => dx + gx * scale;
  double _py(double gy) => dy + gy * scale;

  /// Parses the whole string into the path. Returns the final current point
  /// in grid (un-scaled) coordinates.
  Offset parse() {
    var cmd = '';
    while (true) {
      _skipSeparators();
      if (_i >= _d.length) break;

      final ch = _d[_i];
      if (_isCommand(ch)) {
        cmd = ch;
        _i++;
      } else if (cmd.isEmpty) {
        throw FormatException('SVG path must start with a command', _d, _i);
      }

      var cubic = false;
      switch (cmd) {
        case 'M':
        case 'm':
          {
            final rel = cmd == 'm';
            final nx = _num() + (rel ? _x : 0.0);
            final ny = _num() + (rel ? _y : 0.0);
            _x = nx;
            _y = ny;
            _startX = nx;
            _startY = ny;
            _path.moveTo(_px(nx), _py(ny));
            cmd = rel ? 'l' : 'L'; // implicit line-to for extra pairs
            break;
          }
        case 'L':
        case 'l':
          {
            final rel = cmd == 'l';
            final nx = _num() + (rel ? _x : 0.0);
            final ny = _num() + (rel ? _y : 0.0);
            _lineTo(nx, ny);
            break;
          }
        case 'H':
        case 'h':
          {
            final nx = _num() + (cmd == 'h' ? _x : 0.0);
            _lineTo(nx, _y);
            break;
          }
        case 'V':
        case 'v':
          {
            final ny = _num() + (cmd == 'v' ? _y : 0.0);
            _lineTo(_x, ny);
            break;
          }
        case 'C':
        case 'c':
          {
            final rel = cmd == 'c';
            final bx = rel ? _x : 0.0;
            final by = rel ? _y : 0.0;
            final x1 = _num() + bx;
            final y1 = _num() + by;
            final x2 = _num() + bx;
            final y2 = _num() + by;
            final nx = _num() + bx;
            final ny = _num() + by;
            _path.cubicTo(
              _px(x1), _py(y1), //
              _px(x2), _py(y2), //
              _px(nx), _py(ny),
            );
            _ctrlX = x2;
            _ctrlY = y2;
            _x = nx;
            _y = ny;
            cubic = true;
            break;
          }
        case 'S':
        case 's':
          {
            final rel = cmd == 's';
            final bx = rel ? _x : 0.0;
            final by = rel ? _y : 0.0;
            final x1 = _prevCubic ? 2 * _x - _ctrlX : _x;
            final y1 = _prevCubic ? 2 * _y - _ctrlY : _y;
            final x2 = _num() + bx;
            final y2 = _num() + by;
            final nx = _num() + bx;
            final ny = _num() + by;
            _path.cubicTo(
              _px(x1), _py(y1), //
              _px(x2), _py(y2), //
              _px(nx), _py(ny),
            );
            _ctrlX = x2;
            _ctrlY = y2;
            _x = nx;
            _y = ny;
            cubic = true;
            break;
          }
        case 'A':
        case 'a':
          {
            final rel = cmd == 'a';
            final rx = _num().abs();
            final ry = _num().abs();
            final rot = _num();
            final large = _flag();
            final sweep = _flag();
            final nx = _num() + (rel ? _x : 0.0);
            final ny = _num() + (rel ? _y : 0.0);
            if (rx == 0 || ry == 0) {
              _lineTo(nx, ny);
            } else {
              _path.arcToPoint(
                Offset(_px(nx), _py(ny)),
                radius: Radius.elliptical(rx * scale, ry * scale),
                rotation: rot,
                largeArc: large,
                clockwise: sweep,
              );
              _x = nx;
              _y = ny;
            }
            break;
          }
        case 'Z':
        case 'z':
          {
            _path.close();
            _x = _startX;
            _y = _startY;
            cmd = '';
            break;
          }
        default:
          throw FormatException('Unsupported SVG path command "$cmd"', _d, _i);
      }
      _prevCubic = cubic;
    }
    return Offset(_x, _y);
  }

  void _lineTo(double nx, double ny) {
    _path.lineTo(_px(nx), _py(ny));
    _x = nx;
    _y = ny;
  }

  static bool _isCommand(String ch) => 'MmLlHhVvCcSsQqTtAaZz'.contains(ch);

  void _skipSeparators() {
    while (_i < _d.length) {
      final u = _d.codeUnitAt(_i);
      if (u == 0x20 || u == 0x2C || u == 0x09 || u == 0x0A || u == 0x0D) {
        _i++;
      } else {
        break;
      }
    }
  }

  double _num() {
    _skipSeparators();
    final start = _i;
    if (_i < _d.length && (_d[_i] == '-' || _d[_i] == '+')) _i++;
    var seenDot = false;
    while (_i < _d.length) {
      final u = _d.codeUnitAt(_i);
      if (u >= 0x30 && u <= 0x39) {
        _i++;
      } else if (u == 0x2E && !seenDot) {
        seenDot = true;
        _i++;
      } else {
        break;
      }
    }
    if (_i < _d.length && (_d[_i] == 'e' || _d[_i] == 'E')) {
      var j = _i + 1;
      if (j < _d.length && (_d[j] == '-' || _d[j] == '+')) j++;
      if (j < _d.length &&
          _d.codeUnitAt(j) >= 0x30 &&
          _d.codeUnitAt(j) <= 0x39) {
        while (j < _d.length &&
            _d.codeUnitAt(j) >= 0x30 &&
            _d.codeUnitAt(j) <= 0x39) {
          j++;
        }
        _i = j;
      }
    }
    return double.parse(_d.substring(start, _i));
  }

  /// Arc flags are single characters ('0' or '1') and may be glued to the
  /// number that follows them, e.g. "0 0112 6.844".
  bool _flag() {
    _skipSeparators();
    if (_i >= _d.length) {
      throw FormatException('Missing arc flag', _d, _i);
    }
    final c = _d[_i++];
    if (c != '0' && c != '1') {
      throw FormatException('Invalid arc flag "$c"', _d, _i - 1);
    }
    return c == '1';
  }
}

// ===========================================================================
//  Cached, pixel-space geometry for a given icon size
// ===========================================================================
class _Geo {
  _Geo(this.size) {
    k = size / 48.0;
    s = size * 0.73 / 24.0; // px per grid unit
    ox = (size - 24 * s) / 2;
    oy = (size - 24 * s) / 2 + size * 0.012;

    vault = RRect.fromRectAndRadius(
      Offset.zero & Size.square(size),
      Radius.circular(size * 0.22),
    );

    // 1) The exact official mark (white C-shaped body with Octocat cut-out).
    mark = Path()..fillType = PathFillType.evenOdd;
    _SvgPathParser(_kMarkD, mark, scale: s, dx: ox, dy: oy).parse();
    markBounds = mark.getBounds();

    // 2) Split the very same data into: head (circle, left/top), cat outline
    //    (relative curves up to the final arc) and tail (circle, right/top).
    const headEnd = '6.839 9.504';
    final iHead = _kMarkD.indexOf(headEnd) + headEnd.length;
    final iTail = _kMarkD.indexOf('A10.019');
    final headD = _kMarkD.substring(0, iHead);
    final catRel = _kMarkD.substring(iHead, iTail);
    final tailD = _kMarkD.substring(iTail, _kMarkD.length - 1); // drop 'z'
    final headCurves = headD.substring(headD.indexOf('C'));

    final p1 = _SvgPathParser(headD, Path()).parse(); // bottom-left foot
    final catD = 'M${p1.dx} ${p1.dy}c$catRel';

    // Open cat outline: ears, head, tentacle, body (exact contour).
    outline = Path();
    final p2 = _SvgPathParser(catD, outline, scale: s, dx: ox, dy: oy).parse();

    // Closed cat cavity: outline + the circle arc across the bottom opening.
    cavity = Path();
    _SvgPathParser(catD, cavity, scale: s, dx: ox, dy: oy).parse();
    cavity.arcToPoint(
      Offset(ox + p1.dx * s, oy + p1.dy * s),
      radius: Radius.circular(10.019 * s),
      clockwise: true,
    );
    cavity.close();
    cavityBounds = cavity.getBounds();

    // Outer circular rim of the mark (exact arcs/curves, open at the bottom).
    rim = Path();
    final rimD = 'M${p2.dx} ${p2.dy}$tailD$headCurves';
    _SvgPathParser(rimD, rim, scale: s, dx: ox, dy: oy).parse();

    center = Offset(ox + 12.0 * s, oy + 12.017 * s);
    radius = 10.0 * s;

    // 3) Hex / circuit grid (pixel space), plus pulsing circuit nodes.
    hex = Path();
    final nodeList = <Offset>[];
    final phaseList = <double>[];
    const hr = 1.25; // hex circumradius in grid units
    final hw = math.sqrt(3.0) * hr;
    for (var row = -1; row <= 10; row++) {
      final cy = 4.4 + row * 1.5 * hr;
      for (var col = -1; col <= 9; col++) {
        final cx = 3.6 + col * hw + (row.isOdd ? hw / 2 : 0.0);
        for (var v = 0; v < 6; v++) {
          final ang = math.pi / 180.0 * (60.0 * v + 30.0);
          final px = ox + (cx + hr * math.cos(ang)) * s;
          final py = oy + (cy + hr * math.sin(ang)) * s;
          if (v == 0) {
            hex.moveTo(px, py);
          } else {
            hex.lineTo(px, py);
          }
        }
        hex.close();
        if ((row * 5 + col * 3) % 6 == 0) {
          final n = Offset(ox + cx * s, oy + cy * s);
          if (cavity.contains(n)) {
            nodeList.add(n);
            phaseList.add(((row * 7 + col * 3) % 10) / 10.0);
          }
        }
      }
    }
    nodes = nodeList;
    nodePhase = phaseList;
  }

  static final Map<double, _Geo> _cache = <double, _Geo>{};

  static _Geo of(double size) {
    final hit = _cache[size];
    if (hit != null) return hit;
    if (_cache.length >= 12) {
      _cache.remove(_cache.keys.first);
    }
    final geo = _Geo(size);
    _cache[size] = geo;
    return geo;
  }

  final double size;
  late final double k; // size / 48, for crisp detail scaling
  late final double s; // pixels per 24-grid unit
  late final double ox;
  late final double oy;

  late final RRect vault;
  late final Path mark;
  late final Rect markBounds;
  late final Path outline;
  late final Path cavity;
  late final Rect cavityBounds;
  late final Path rim;
  late final Offset center;
  late final double radius;
  late final Path hex;
  late final List<Offset> nodes;
  late final List<double> nodePhase;

  /// Grid coordinate -> pixel coordinate.
  Offset at(double gx, double gy) => Offset(ox + gx * s, oy + gy * s);
}

// ===========================================================================
//  Painter
// ===========================================================================
class _SynBlackHolePainter extends CustomPainter {
  _SynBlackHolePainter({
    required this.controller,
    required this.clock,
    required this.geo,
    required this.tapAt,
    required this.tapPos,
  }) : super(repaint: controller);

  final AnimationController controller;
  final Stopwatch clock;
  final _Geo geo;
  final double? tapAt;
  final Offset? tapPos;

  @override
  void paint(Canvas canvas, Size size) {
    final g = geo;
    final t = controller.value; // 0..1, loops every 6 s
    final breathe = 0.5 + 0.5 * math.sin(_kTau * t - math.pi / 2);
    final spin = _kTau * t;

    _paintAura(canvas, g, breathe);
    _paintVault(canvas, g);
    _paintHalo(canvas, g, spin, breathe);
    _paintChrome(canvas, g, t);
    _paintRim(canvas, g, spin);
    _paintSatellites(canvas, g, t);
    _paintVoid(canvas, g, t, breathe);
    _paintShockwave(canvas, g);
  }

  // -------------------------------------------------------------------------
  // 1) Ambient aura + obsidian squircle vault
  // -------------------------------------------------------------------------
  void _paintAura(Canvas canvas, _Geo g, double breathe) {
    final sigma = g.size * (0.10 + 0.04 * breathe);
    canvas.drawRRect(
      g.vault.inflate(g.size * 0.01),
      Paint()
        ..color = _a(_kCyan, 0.20 + 0.22 * breathe)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma),
    );
    canvas.drawRRect(
      g.vault.shift(Offset(g.size * 0.035, g.size * 0.05)),
      Paint()
        ..color = _a(_kViolet, 0.40 - 0.18 * breathe)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, sigma * 1.15),
    );
  }

  void _paintVault(Canvas canvas, _Geo g) {
    final s = g.size;

    // Deep obsidian body.
    canvas.drawRRect(
      g.vault,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(s * 0.5, s * 0.40),
          s * 0.80,
          const [Color(0xFF0D0E15), Color(0xFF050508)],
          const [0.0, 1.0],
        ),
    );

    // Soft glass gloss on the upper half.
    canvas.save();
    canvas.clipRRect(g.vault);
    canvas.drawRect(
      Rect.fromLTWH(0, 0, s, s * 0.55),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, s * 0.55),
          [_a(_kWhite, 0.07), _a(_kWhite, 0.0)],
        ),
    );
    canvas.restore();

    // Glassmorphic inner borders (visible on both light and dark surfaces).
    final bw = math.max(0.6, g.k);
    canvas.drawRRect(
      g.vault.deflate(bw / 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = bw
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(s, s),
          [_a(_kWhite, 0.34), _a(_kWhite, 0.06), _a(_kViolet, 0.32)],
          const [0.0, 0.55, 1.0],
        ),
    );
    canvas.drawRRect(
      g.vault.deflate(bw * 2.4),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = bw * 0.6
        ..color = _a(_kWhite, 0.05),
    );
  }

  // -------------------------------------------------------------------------
  // 2) Plasma halo, liquid chrome body, plasma rim, orbiting satellites
  // -------------------------------------------------------------------------
  ui.Gradient _plasma(_Geo g, double spin, double alpha) {
    return ui.Gradient.sweep(
      g.center,
      [
        _a(_kCyan, alpha),
        _a(_kViolet, alpha),
        _a(_kOrange, alpha),
        _a(_kCyan, alpha),
      ],
      const [0.0, 0.36, 0.70, 1.0],
      TileMode.clamp,
      0.0,
      _kTau,
      _rotAbout(spin, g.center).storage,
    );
  }

  void _paintHalo(Canvas canvas, _Geo g, double spin, double breathe) {
    canvas.drawPath(
      g.rim,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = g.s * 2.2
        ..shader = _plasma(g, spin, 0.55 + 0.35 * breathe)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, g.s * 1.3),
    );
  }

  void _paintChrome(Canvas canvas, _Geo g, double t) {
    final b = g.markBounds;

    // Titanium-white to silver-cyan base.
    canvas.drawPath(
      g.mark,
      Paint()
        ..shader = ui.Gradient.linear(
          b.topLeft,
          b.bottomRight,
          const [Color(0xFFFFFFFF), Color(0xFFE2F6FF), Color(0xFF9AD9EA)],
          const [0.0, 0.52, 1.0],
        ),
    );

    // Liquid reflections that glide diagonally across the metal.
    final d = b.bottomRight - b.topLeft;
    Offset along(double u) => b.topLeft + d * u;
    final c0 = -0.60 + 2.20 * t;

    const cool = Color(0xFF5FB7D6);
    canvas.drawPath(
      g.mark,
      Paint()
        ..shader = ui.Gradient.linear(
          along(c0 - 0.46),
          along(c0 - 0.08),
          [_a(cool, 0.0), _a(cool, 0.38), _a(cool, 0.0)],
          const [0.0, 0.5, 1.0],
        ),
    );
    canvas.drawPath(
      g.mark,
      Paint()
        ..shader = ui.Gradient.linear(
          along(c0 - 0.14),
          along(c0 + 0.14),
          [_a(_kWhite, 0.0), _a(_kWhite, 0.95), _a(_kWhite, 0.0)],
          const [0.0, 0.5, 1.0],
        ),
    );
  }

  void _paintRim(Canvas canvas, _Geo g, double spin) {
    canvas.drawPath(
      g.rim,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = g.s * 0.6
        ..strokeCap = StrokeCap.butt
        ..shader = _plasma(g, spin, 1.0),
    );
  }

  void _paintSatellites(Canvas canvas, _Geo g, double t) {
    final orbit = g.radius + g.s * 1.25;
    _spark(canvas, g, orbit, _kTau * t - math.pi / 2, 1.0, _kCyan);
    _spark(canvas, g, orbit, -_kTau * 2 * t + math.pi * 0.35, -1.0, _kOrange);
  }

  void _spark(
    Canvas canvas,
    _Geo g,
    double orbit,
    double angle,
    double dir,
    Color color,
  ) {
    final r = math.max(0.7, g.size * 0.016);

    // Fading comet tail.
    for (var i = 5; i >= 1; i--) {
      final a = angle - dir * i * 0.075;
      final f = 1 - i / 6;
      canvas.drawCircle(
        g.center + Offset(math.cos(a), math.sin(a)) * orbit,
        r * (0.35 + 0.55 * f),
        Paint()..color = _a(color, 0.38 * f),
      );
    }

    final p = g.center + Offset(math.cos(angle), math.sin(angle)) * orbit;
    canvas.drawCircle(
      p,
      r * 2.6,
      Paint()
        ..color = _a(color, 0.55)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, r * 1.6),
    );
    canvas.drawCircle(p, r, Paint()..color = _a(_kWhite, 0.95));
  }

  // -------------------------------------------------------------------------
  // 3) + 4) Octocat void: cyber grid, laser scanline, contour glow, eyes
  // -------------------------------------------------------------------------
  void _paintVoid(Canvas canvas, _Geo g, double t, double breathe) {
    canvas.drawPath(g.cavity, Paint()..color = _kVoid);

    canvas.save();
    canvas.clipPath(g.cavity);

    final b = g.cavityBounds;

    // Subtle violet depth glow.
    canvas.drawRect(
      b.inflate(g.s),
      Paint()
        ..shader = ui.Gradient.radial(
          g.at(12.0, 12.2),
          g.s * 9.0,
          [_a(_kViolet, 0.16 + 0.06 * breathe), _a(_kViolet, 0.0)],
        ),
    );

    // Laser state (two down/up sweeps per 6 s loop, eased at both ends).
    final phase = 2 * _kTau * t;
    final p = 0.5 - 0.5 * math.cos(phase);
    final down = math.sin(phase) >= 0;
    final y = b.top + b.height * p;
    final band = g.size * 0.16;

    // Faint hex grid.
    final gridW = math.max(0.35, 0.5 * g.k);
    canvas.drawPath(
      g.hex,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = gridW
        ..color = _a(_kCyan, 0.11 + 0.05 * breathe),
    );

    // Grid brightens where the laser passes.
    canvas.drawPath(
      g.hex,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = gridW * 1.5
        ..shader = ui.Gradient.linear(
          Offset(0, y - band),
          Offset(0, y + band),
          [_a(_kCyan, 0.0), _a(_kCyan, 0.75), _a(_kCyan, 0.0)],
          const [0.0, 0.5, 1.0],
        ),
    );

    // Circuit nodes: gentle pulse + flash near the laser.
    final nodePaint = Paint();
    final nodeR = math.max(0.4, g.s * 0.16);
    for (var i = 0; i < g.nodes.length; i++) {
      final n = g.nodes[i];
      final pulse = 0.5 + 0.5 * math.sin(_kTau * (2 * t + g.nodePhase[i]));
      final dn = (n.dy - y) / (band * 0.6);
      final near = math.exp(-dn * dn);
      nodePaint.color = _a(_kCyan, 0.18 + 0.22 * pulse + 0.60 * near);
      canvas.drawCircle(n, nodeR, nodePaint);
    }

    // Holographic laser scanline with a soft trail.
    final trail = g.size * 0.30;
    final y0 = down ? y - trail : y;
    final y1 = down ? y : y + trail;
    canvas.drawRect(
      Rect.fromLTRB(b.left, y0, b.right, y1),
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, down ? y0 : y1),
          Offset(0, down ? y1 : y0),
          [_a(_kCyan, 0.0), _a(_kCyan, 0.30)],
        ),
    );
    final lw = math.max(0.7, g.k);
    canvas.drawRect(
      Rect.fromLTRB(b.left, y - lw * 1.5, b.right, y + lw * 1.5),
      Paint()
        ..color = _a(_kCyan, 0.55)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, lw * 1.8),
    );
    canvas.drawRect(
      Rect.fromLTRB(b.left, y - lw / 2, b.right, y + lw / 2),
      Paint()..color = _a(_kIce, 0.95),
    );

    // Razor-sharp inner rim along the exact Octocat contour.
    final rw = math.max(0.5, 0.8 * g.k);
    final pulse = 0.85 + 0.15 * math.sin(_kTau * 2 * t);
    canvas.drawPath(
      g.outline,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = rw * 4
        ..strokeJoin = StrokeJoin.round
        ..color = _a(_kCyan, 0.30 * pulse)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, rw * 1.6),
    );
    canvas.drawPath(
      g.outline,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = rw * 2
        ..strokeJoin = StrokeJoin.round
        ..color = _a(_kIce, 0.95),
    );

    _paintEyes(canvas, g);

    canvas.restore();
  }

  /// Eye openness: 1 = fully open, ~0 = closed.
  ///
  /// Runs on its own 10-second cycle driven by the wall clock, fully decoupled
  /// from the 6-second laser/rotation loop: the eyes stay open and perfectly
  /// still until 9.5 s, then blink once over ~0.5 s (quick close, slightly
  /// slower open, both eased) and rest again.
  double _eyeOpenness() {
    if (!controller.isAnimating) return 1.0;

    const cycle = 10.0;
    const blinkStart = 9.5;
    const blinkLen = 0.5;
    const closeEnd = 0.36; // fraction of the blink spent closing
    const minOpen = 0.03; // never a perfectly flat line

    final now = (clock.elapsedMicroseconds / 1e6) % cycle;
    if (now < blinkStart) return 1.0;

    final double u =
        ((now - blinkStart) / blinkLen).clamp(0.0, 1.0).toDouble();
    double ease(double x) => x * x * x * (x * (x * 6 - 15) + 10);

    final double lid = u < closeEnd
        ? ease(u / closeEnd)
        : 1.0 - ease((u - closeEnd) / (1.0 - closeEnd));
    return 1.0 - lid * (1.0 - minOpen);
  }

  void _paintEyes(Canvas canvas, _Geo g) {
    final open = _eyeOpenness();

    final ew = g.s * 1.0; // half width
    final eh = g.s * 0.52 * open; // half height
    final lidDrop = (1 - open) * g.s * 0.10; // upper lid pulls the eye down
    final bloomAlpha = 0.55 * (0.35 + 0.65 * open);

    for (final sign in const <double>[-1.0, 1.0]) {
      final c = g.at(12.0 + sign * 3.0, 10.8);
      canvas.save();
      canvas.translate(c.dx, c.dy);
      canvas.rotate(-sign * 0.2);
      canvas.translate(0, lidDrop);

      // Bloom.
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: ew * 3.0,
          height: math.max(g.s * 0.5, eh * 4.0),
        ),
        Paint()
          ..color = _a(_kCyan, bloomAlpha)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, g.s * 0.7),
      );
      // Slit body.
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: ew * 2.0,
          height: math.max(g.s * 0.14, eh * 2.0),
        ),
        Paint()..color = _kCyan,
      );
      // Hot core.
      canvas.drawOval(
        Rect.fromCenter(
          center: Offset.zero,
          width: ew * 1.2,
          height: math.max(g.s * 0.08, eh * 0.9),
        ),
        Paint()..color = _a(_kIce, 0.95 * open + 0.05),
      );
      canvas.restore();
    }
  }

  // -------------------------------------------------------------------------
  // 5) Tap shockwave
  // -------------------------------------------------------------------------
  void _paintShockwave(Canvas canvas, _Geo g) {
    final started = tapAt;
    if (started == null) return;

    final q = (clock.elapsedMicroseconds / 1e6 - started) / 0.9;
    if (q < 0 || q >= 1) return;

    final ease = 1 - (1 - q) * (1 - q) * (1 - q);
    final fade = (1 - q) * (1 - q);
    final c = tapPos ?? Offset(g.size / 2, g.size / 2);
    final maxR = g.size * 1.25;
    final r = maxR * ease;
    final w = g.size * (0.015 + 0.075 * (1 - q));

    canvas.save();
    canvas.clipRRect(g.vault);

    // Flash.
    canvas.drawRRect(g.vault, Paint()..color = _a(_kCyan, 0.20 * fade * fade));

    // Main ring: glow + crisp edge.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w * 2
        ..color = _a(_kCyan, 0.55 * fade)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, w),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.7, g.size * 0.022 * (1 - q))
        ..color = _a(_kIce, 0.95 * fade),
    );

    // Trailing violet ring.
    if (q > 0.1) {
      final q2 = (q - 0.1) / 0.9;
      final e2 = 1 - (1 - q2) * (1 - q2) * (1 - q2);
      canvas.drawCircle(
        c,
        maxR * 0.8 * e2,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(0.8, g.size * 0.05 * (1 - q2))
          ..color = _a(_kViolet, 0.6 * (1 - q2) * (1 - q2))
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, g.size * 0.02),
      );
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _SynBlackHolePainter old) =>
      old.geo != geo ||
      old.tapAt != tapAt ||
      old.tapPos != tapPos ||
      old.controller != controller;
}
