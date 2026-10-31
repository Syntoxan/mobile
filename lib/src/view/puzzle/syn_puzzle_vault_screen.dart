// SYNTOXAN — Cyber-Vault UI, playable puzzle adapter and offline puzzle player.
// PART 3 OF 3.
//
// Target path: lib/src/puzzle/syn_puzzle_vault_screen.dart
//
// Wiring (the screen is repository-injected, so it works with any DI setup):
//
//   final repo = SynPuzzleRepository(database);          // Part 2
//   Navigator.of(context).push(SynPuzzleVaultScreen.route(repo));
//
// What is inside
//   * SynLichessPuzzleAdapter  SynPuzzleRecord -> SynPlayablePuzzle (dartchess):
//                              start/initial positions, initialPly, player side,
//                              solution line, per-ply positions.
//   * SynPuzzleSession         move validation, opponent replies, alternate-mate
//                              acceptance, mistakes, solution playback.
//   * SynBoardView             self-contained interactive board (tap + drag,
//                              legal-move dots, promotion, last move, check).
//                              Lichess's internal Puzzle/Chessboard imports drift
//                              between releases, so the board does not depend on them.
//   * SynOfflinePuzzlePlayerScreen  3-stage hint button, prefetching "Next puzzle",
//                              repository.markSolved on completion.
//   * SynPuzzleVaultScreen     telemetry HUD, import/mount terminal, pack manager,
//                              filter & launch deck.
//
// Only imports: Flutter SDK, dartchess, Part 1, Part 2. No new packages.

import 'dart:async';

import 'package:dartchess/dartchess.dart' show Chess, Move, Position, Setup, Side;
import 'package:flutter/material.dart';

import 'syn_puzzle_importer.dart';
import 'syn_puzzle_repository.dart';

// ---------------------------------------------------------------------------
// Palette, typography, small helpers
// ---------------------------------------------------------------------------

class _C {
  const _C._();
  static const Color bg = Color(0xFF06080E);
  static const Color surface = Color(0xFF0B101C);
  static const Color surfaceHi = Color(0xFF121A2B);
  static const Color cyan = Color(0xFF3DFFDA);
  static const Color violet = Color(0xFFC7A4FF);
  static const Color line = Color(0xFF1C2740);
  static const Color text = Color(0xFFD7E4F2);
  static const Color dim = Color(0xFF7C8AA5);
  static const Color danger = Color(0xFFFF4D6D);
  static const Color amber = Color(0xFFFFC857);
}

Color _a(Color c, double opacity) {
  final o = opacity < 0 ? 0.0 : (opacity > 1 ? 1.0 : opacity);
  return c.withAlpha((o * 255).round());
}

TextStyle _mono(
  double size, {
  Color color = _C.text,
  FontWeight weight = FontWeight.w500,
  double spacing = 0.6,
  double? height,
}) =>
    TextStyle(
      fontFamily: 'monospace',
      fontFamilyFallback: const <String>['RobotoMono', 'Courier New', 'Courier'],
      fontSize: size,
      fontWeight: weight,
      letterSpacing: spacing,
      color: color,
      height: height,
    );

String _fmtBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(kb < 10 ? 1 : 0)} KB';
  final mb = kb / 1024;
  if (mb < 1024) return '${mb.toStringAsFixed(mb < 10 ? 1 : 0)} MB';
  return '${(mb / 1024).toStringAsFixed(2)} GB';
}

String _fmtInt(int n) {
  final s = n.abs().toString();
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return n < 0 ? '-$out' : out.toString();
}

// ---------------------------------------------------------------------------
// 45-degree chamfered shapes & cyber widgets
// ---------------------------------------------------------------------------

Path _chamferPath(
  Rect r,
  double chamfer, {
  bool tl = true,
  bool tr = false,
  bool br = true,
  bool bl = false,
}) {
  final half = r.shortestSide / 2;
  final c = chamfer > half ? half : chamfer;
  final p = Path()..moveTo(r.left + (tl ? c : 0), r.top);
  p.lineTo(r.right - (tr ? c : 0), r.top);
  if (tr) p.lineTo(r.right, r.top + c);
  p.lineTo(r.right, r.bottom - (br ? c : 0));
  if (br) p.lineTo(r.right - c, r.bottom);
  p.lineTo(r.left + (bl ? c : 0), r.bottom);
  if (bl) p.lineTo(r.left, r.bottom - c);
  p.lineTo(r.left, r.top + (tl ? c : 0));
  if (tl) p.lineTo(r.left + c, r.top);
  p.close();
  return p;
}

/// Rectangle with 45-degree cut corners (default: top-left and bottom-right).
class SynChamferBorder extends ShapeBorder {
  const SynChamferBorder({
    this.chamfer = 14,
    this.side = BorderSide.none,
    this.topLeft = true,
    this.topRight = false,
    this.bottomRight = true,
    this.bottomLeft = false,
  });

  final double chamfer;
  final BorderSide side;
  final bool topLeft;
  final bool topRight;
  final bool bottomRight;
  final bool bottomLeft;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => _chamferPath(
        rect.deflate(side.width),
        chamfer,
        tl: topLeft,
        tr: topRight,
        br: bottomRight,
        bl: bottomLeft,
      );

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      _chamferPath(rect, chamfer, tl: topLeft, tr: topRight, br: bottomRight, bl: bottomLeft);

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width == 0) return;
    final paint = side.toPaint()..strokeJoin = StrokeJoin.miter;
    canvas.drawPath(
      _chamferPath(
        rect.deflate(side.width / 2),
        chamfer,
        tl: topLeft,
        tr: topRight,
        br: bottomRight,
        bl: bottomLeft,
      ),
      paint,
    );
  }

  @override
  ShapeBorder scale(double t) => SynChamferBorder(
        chamfer: chamfer * t,
        side: side.scale(t),
        topLeft: topLeft,
        topRight: topRight,
        bottomRight: bottomRight,
        bottomLeft: bottomLeft,
      );

  @override
  bool operator ==(Object other) =>
      other is SynChamferBorder &&
      other.chamfer == chamfer &&
      other.side == side &&
      other.topLeft == topLeft &&
      other.topRight == topRight &&
      other.bottomRight == bottomRight &&
      other.bottomLeft == bottomLeft;

  @override
  int get hashCode => Object.hash(chamfer, side, topLeft, topRight, bottomRight, bottomLeft);
}

class _Card extends StatelessWidget {
  const _Card({
    required this.child,
    this.accent = _C.cyan,
    this.padding = const EdgeInsets.all(14),
    this.chamfer = 16,
    this.glow = true,
    this.fill,
    this.flip = false,
  });

  final Widget child;
  final Color accent;
  final EdgeInsetsGeometry padding;
  final double chamfer;
  final bool glow;
  final Color? fill;

  /// Cut the opposite pair of corners (top-right / bottom-left).
  final bool flip;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: ShapeDecoration(
        color: fill ?? _a(_C.surface, 0.92),
        shape: SynChamferBorder(
          chamfer: chamfer,
          topLeft: !flip,
          bottomRight: !flip,
          topRight: flip,
          bottomLeft: flip,
          side: BorderSide(color: _a(accent, 0.5), width: 1),
        ),
        shadows: glow ? <BoxShadow>[BoxShadow(color: _a(accent, 0.12), blurRadius: 20)] : null,
      ),
      child: child,
    );
  }
}

class _CyberButton extends StatelessWidget {
  const _CyberButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.accent = _C.cyan,
    this.filled = false,
    this.dense = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Color accent;
  final bool filled;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final color = enabled ? accent : _C.dim;
    final shape = SynChamferBorder(
      chamfer: dense ? 8 : 12,
      side: BorderSide(color: _a(color, enabled ? 0.9 : 0.35), width: 1.2),
    );
    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: ShapeDecoration(
            color: filled ? _a(color, 0.16) : _a(_C.surface, 0.9),
            shape: shape,
            shadows: enabled ? <BoxShadow>[BoxShadow(color: _a(color, 0.22), blurRadius: 14)] : null,
          ),
          child: InkWell(
            customBorder: shape,
            onTap: onPressed,
            splashColor: _a(color, 0.25),
            highlightColor: _a(color, 0.1),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: dense ? 12 : 16, vertical: dense ? 9 : 14),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  if (icon != null) ...<Widget>[
                    Icon(icon, size: dense ? 15 : 18, color: color),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _mono(dense ? 11 : 12.5, color: color, weight: FontWeight.w700, spacing: 1.2),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: ShapeDecoration(
        color: _a(color, 0.12),
        shape: SynChamferBorder(
          chamfer: 5,
          side: BorderSide(color: _a(color, 0.7), width: 1),
        ),
      ),
      child: Text(text, style: _mono(10, color: color, weight: FontWeight.w700, spacing: 1.1)),
    );
  }
}

class _NeonBar extends StatefulWidget {
  const _NeonBar({this.value, this.height = 9});

  /// 0..1, or null for an indeterminate sweep.
  final double? value;
  final double height;

  @override
  State<_NeonBar> createState() => _NeonBarState();
}

class _NeonBarState extends State<_NeonBar> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _NeonBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.value == null) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: AnimatedBuilder(
        animation: _c,
        builder: (BuildContext context, Widget? child) =>
            CustomPaint(painter: _BarPainter(widget.value, _c.value)),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  _BarPainter(this.value, this.phase);
  final double? value;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final r = Offset.zero & size;
    final track = _chamferPath(r, size.height / 2, tl: true, tr: false, br: true, bl: false);
    canvas.drawPath(track, Paint()..color = _a(_C.line, 0.95));
    canvas.save();
    canvas.clipPath(track);
    final shader = const LinearGradient(colors: <Color>[_C.cyan, _C.violet]).createShader(r);
    final fill = Paint()..shader = shader;
    final v = value;
    if (v != null) {
      final w = size.width * (v < 0 ? 0.0 : (v > 1 ? 1.0 : v));
      canvas.drawRect(Rect.fromLTWH(0, 0, w, size.height), fill);
    } else {
      final w = size.width * 0.3;
      final x = (size.width + w) * phase - w;
      canvas.drawRect(Rect.fromLTWH(x, 0, w, size.height), fill);
    }
    final tick = Paint()
      ..color = _a(_C.bg, 0.7)
      ..strokeWidth = 1.2;
    for (var i = 1; i < 10; i++) {
      final x = size.width * i / 10;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), tick);
    }
    canvas.restore();
    canvas.drawPath(
      track,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = _a(_C.cyan, 0.35),
    );
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) => old.value != value || old.phase != phase;
}

class _BackdropPainter extends CustomPainter {
  const _BackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _C.bg);
    void glow(Offset c, double radius, Color color) {
      canvas.drawCircle(
        c,
        radius,
        Paint()
          ..shader = RadialGradient(colors: <Color>[_a(color, 0.16), _a(color, 0)])
              .createShader(Rect.fromCircle(center: c, radius: radius)),
      );
    }

    glow(Offset(size.width * 0.05, size.height * 0.02), size.width * 0.9, _C.violet);
    glow(Offset(size.width * 0.98, size.height * 0.98), size.width * 0.95, _C.cyan);
    final grid = Paint()
      ..color = _a(_C.cyan, 0.04)
      ..strokeWidth = 1;
    const step = 28.0;
    for (var x = 0.0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = 0.0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
  }

  @override
  bool shouldRepaint(covariant _BackdropPainter old) => false;
}

class _Telemetry extends StatelessWidget {
  const _Telemetry(this.label, this.value, {this.color = _C.cyan});
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(label, style: _mono(9.5, color: _C.dim, weight: FontWeight.w700, spacing: 1.6)),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: _mono(15, color: color, weight: FontWeight.w700, spacing: 0.4),
        ),
      ],
    );
  }
}

class _StatusStrip extends StatelessWidget {
  const _StatusStrip(this.text, this.color);
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: ShapeDecoration(
        color: _a(color, 0.1),
        shape: SynChamferBorder(
          chamfer: 10,
          topRight: true,
          bottomLeft: true,
          topLeft: false,
          bottomRight: false,
          side: BorderSide(color: _a(color, 0.65), width: 1),
        ),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: _mono(12, color: color, weight: FontWeight.w700, spacing: 1.6),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Board geometry helpers (own FEN reader: no dependency on dartchess Board API)
// ---------------------------------------------------------------------------

String _sqName(int idx) => '${'abcdefgh'[idx % 8]}${idx ~/ 8 + 1}';

int _sqIdx(String name) => (name.codeUnitAt(1) - 49) * 8 + (name.codeUnitAt(0) - 97);

/// 64 cells, index = rank * 8 + file (a1 = 0), '' for empty, FEN letters otherwise.
List<String> _cellsFromFen(String fen) {
  final cells = List<String>.filled(64, '');
  final rows = fen.split(' ').first.split('/');
  for (var r = 0; r < 8 && r < rows.length; r++) {
    final rank = 7 - r;
    var file = 0;
    for (final ch in rows[r].split('')) {
      final d = int.tryParse(ch);
      if (d != null) {
        file += d;
      } else {
        if (file < 8) cells[rank * 8 + file] = ch;
        file++;
      }
    }
  }
  return cells;
}

bool _isWhitePiece(String p) => p == p.toUpperCase();

/// Standard UCI (e1g1) -> dartchess move (king-takes-rook for castling).
String _toEngineUci(Position pos, String uci) {
  if (uci.length != 4) return uci;
  final cells = _cellsFromFen(pos.fen);
  final from = _sqIdx(uci.substring(0, 2));
  final to = _sqIdx(uci.substring(2, 4));
  final piece = cells[from];
  if ((piece == 'K' || piece == 'k') && from ~/ 8 == to ~/ 8 && ((to % 8) - (from % 8)).abs() == 2) {
    final rookFile = (to % 8) > (from % 8) ? 7 : 0;
    return '${uci.substring(0, 2)}${_sqName((from ~/ 8) * 8 + rookFile)}';
  }
  return uci;
}

Move? _parseUci(Position pos, String uci) => Move.parse(_toEngineUci(pos, uci));

bool _isLegalUci(Position pos, String uci) {
  try {
    final m = _parseUci(pos, uci);
    return m != null && pos.isLegal(m);
  } catch (_) {
    return false;
  }
}

const Map<String, String> _pieceNames = <String, String>{
  'p': 'pawn',
  'n': 'knight',
  'b': 'bishop',
  'r': 'rook',
  'q': 'queen',
  'k': 'king',
};

// ---------------------------------------------------------------------------
// 1. Lichess puzzle adapter
// ---------------------------------------------------------------------------

class SynPuzzleAdaptException implements Exception {
  const SynPuzzleAdaptException(this.message);
  final String message;
  @override
  String toString() => 'SynPuzzleAdaptException: $message';
}

/// A puzzle prepared for play. Field names mirror Lichess's Puzzle model
/// (`initialPly`, `solution`) so mapping to the native class is a one-liner.
class SynPlayablePuzzle {
  const SynPlayablePuzzle({
    required this.record,
    required this.line,
    required this.positions,
    required this.playerSide,
    required this.initialPly,
  });

  final SynPuzzleRecord record;

  /// Full UCI line: [setup move, player, opponent, player, ...].
  final List<String> line;

  /// positions[k] = position after k plies of [line] (positions[0] = FEN before the setup move).
  final List<Position> positions;
  final Side playerSide;

  /// Ply count of the position the player starts from (after the setup move).
  final int initialPly;

  String get setupMove => line.first;

  /// Moves after the setup move: player, opponent, player, ...
  List<String> get solution => line.sublist(1);

  /// Only the player's moves.
  List<String> get playerMoves => <String>[for (var i = 1; i < line.length; i += 2) line[i]];

  Position get startPosition => positions.first;
  Position get initialPosition => positions[1];
  String get initialFen => positions[1].fen;
}

class SynLichessPuzzleAdapter {
  const SynLichessPuzzleAdapter._();

  /// Parses [record.fen] with dartchess, replays the whole line (validating every
  /// move), and derives initialPly, the player side and the solution.
  static SynPlayablePuzzle adapt(SynPuzzleRecord record) {
    final line = record.moveList;
    if (line.length < 2) {
      throw const SynPuzzleAdaptException('A puzzle needs a setup move and at least one solution move');
    }
    final start = _startPosition(record.fen);
    final positions = <Position>[start];
    var pos = start;
    for (var i = 0; i < line.length; i++) {
      final Move? move;
      try {
        move = _parseUci(pos, line[i]);
      } catch (e) {
        throw SynPuzzleAdaptException('Unparseable move "${line[i]}" at ply ${i + 1}: $e');
      }
      if (move == null || !pos.isLegal(move)) {
        throw SynPuzzleAdaptException('Illegal move "${line[i]}" at ply ${i + 1}');
      }
      pos = pos.play(move);
      positions.add(pos);
    }
    final fields = start.fen.split(' ');
    final fullmove = fields.length > 5 ? (int.tryParse(fields[5]) ?? 1) : 1;
    final startPly = (fullmove - 1) * 2 + (start.turn == Side.white ? 0 : 1);
    return SynPlayablePuzzle(
      record: record,
      line: line,
      positions: positions,
      playerSide: positions[1].turn,
      initialPly: startPly + 1,
    );
  }

  static Position _startPosition(String fen) {
    try {
      return Chess.fromSetup(Setup.parseFen(fen));
    } catch (e) {
      throw SynPuzzleAdaptException('Invalid puzzle FEN "$fen": $e');
    }
  }
}

// ---------------------------------------------------------------------------
// Puzzle session (game logic)
// ---------------------------------------------------------------------------

enum SynPuzzlePhase { playerTurn, opponentTurn, solved, revealing, revealed }

enum SynMoveOutcome { ignored, illegal, correct, solved, wrong }

class SynPuzzleSession extends ChangeNotifier {
  SynPuzzleSession(this.puzzle) : _lastMove = puzzle.setupMove;

  static const Duration opponentDelay = Duration(milliseconds: 450);
  static const Duration flashDuration = Duration(milliseconds: 700);
  static const Duration revealDelay = Duration(milliseconds: 600);

  final SynPlayablePuzzle puzzle;

  int _cursor = 1; // index in puzzle.line of the next move to be played
  Position? _override; // board shown after an accepted alternate mate
  SynPuzzlePhase _phase = SynPuzzlePhase.playerTurn;
  String? _lastMove;
  int _mistakes = 0;
  ({int from, int to})? _flash;
  Timer? _timer;
  Timer? _flashTimer;
  bool _disposed = false;
  Position? _cellsPos;
  List<String> _cells = const <String>[];

  SynPuzzlePhase get phase => _phase;
  int get mistakes => _mistakes;
  int get cursor => _cursor;
  bool get isPlayerTurn => _phase == SynPuzzlePhase.playerTurn;
  bool get isSolved => _phase == SynPuzzlePhase.solved;
  bool get isFinished => _phase == SynPuzzlePhase.solved || _phase == SynPuzzlePhase.revealed;
  ({int from, int to})? get wrongFlash => _flash;

  Position get position => _override ?? puzzle.positions[_cursor];

  List<String> get cells {
    final pos = position;
    if (!identical(pos, _cellsPos)) {
      _cells = _cellsFromFen(pos.fen);
      _cellsPos = pos;
    }
    return _cells;
  }

  String? get expectedUci => _cursor < puzzle.line.length ? puzzle.line[_cursor] : null;
  int? get lastFrom => _lastMove == null ? null : _sqIdx(_lastMove!.substring(0, 2));
  int? get lastTo => _lastMove == null ? null : _sqIdx(_lastMove!.substring(2, 4));

  int? get checkSquare {
    final pos = position;
    if (!pos.isCheck) return null;
    final idx = cells.indexOf(pos.turn == Side.white ? 'K' : 'k');
    return idx < 0 ? null : idx;
  }

  bool ownsPiece(int idx) {
    final p = cells[idx];
    if (p.isEmpty) return false;
    return _isWhitePiece(p) == (puzzle.playerSide == Side.white);
  }

  /// Legal destinations for the piece on [from] (castling is offered on the king's destination square).
  Set<int> legalTargets(int from) {
    final pos = position;
    final piece = cells[from];
    if (piece.isEmpty) return const <int>{};
    final lower = piece.toLowerCase();
    final fromName = _sqName(from);
    final out = <int>{};
    for (var t = 0; t < 64; t++) {
      if (t == from) continue;
      final target = cells[t];
      if (lower == 'k' &&
          target.isNotEmpty &&
          target.toLowerCase() == 'r' &&
          _isWhitePiece(target) == _isWhitePiece(piece)) {
        continue; // castling is expressed as the king's two-square move
      }
      final promo = lower == 'p' && (t ~/ 8 == 7 || t ~/ 8 == 0) ? 'q' : '';
      if (_isLegalUci(pos, '$fromName${_sqName(t)}$promo')) out.add(t);
    }
    return out;
  }

  bool needsPromotion(int from, int to) {
    final piece = cells[from];
    if (piece.toLowerCase() != 'p') return false;
    if (to ~/ 8 != 7 && to ~/ 8 != 0) return false;
    return _isLegalUci(position, '${_sqName(from)}${_sqName(to)}q');
  }

  /// [uci] is standard UCI typed by the player (promotion letter lower-case).
  SynMoveOutcome tryMove(String uci) {
    if (_phase != SynPuzzlePhase.playerTurn) return SynMoveOutcome.ignored;
    final pos = position;
    final Move? move;
    try {
      move = _parseUci(pos, uci);
    } catch (_) {
      return SynMoveOutcome.illegal;
    }
    if (move == null || !pos.isLegal(move)) return SynMoveOutcome.illegal;

    if (uci == puzzle.line[_cursor]) {
      _cursor++;
      _override = null;
      _lastMove = uci;
      _flash = null;
      if (_cursor >= puzzle.line.length) {
        _phase = SynPuzzlePhase.solved;
        _notify();
        return SynMoveOutcome.solved;
      }
      _phase = SynPuzzlePhase.opponentTurn;
      _notify();
      _later(opponentDelay, _playOpponent);
      return SynMoveOutcome.correct;
    }

    // Lichess rule: any checkmating move solves the puzzle.
    final after = pos.play(move);
    if (after.isCheckmate) {
      _override = after;
      _lastMove = uci;
      _flash = null;
      _phase = SynPuzzlePhase.solved;
      _notify();
      return SynMoveOutcome.solved;
    }

    _mistakes++;
    _flash = (from: _sqIdx(uci.substring(0, 2)), to: _sqIdx(uci.substring(2, 4)));
    _notify();
    _flashTimer?.cancel();
    _flashTimer = Timer(flashDuration, () {
      if (_disposed) return;
      _flash = null;
      _notify();
    });
    return SynMoveOutcome.wrong;
  }

  void _playOpponent() {
    final uci = puzzle.line[_cursor];
    _cursor++;
    _lastMove = uci;
    _phase = _cursor >= puzzle.line.length ? SynPuzzlePhase.solved : SynPuzzlePhase.playerTurn;
    _notify();
  }

  /// Plays the remaining line (not counted as a solve).
  void revealSolution() {
    if (isFinished || _phase == SynPuzzlePhase.revealing) return;
    _timer?.cancel();
    _override = null;
    _flash = null;
    _phase = SynPuzzlePhase.revealing;
    _notify();
    _stepReveal();
  }

  void _stepReveal() {
    if (_cursor >= puzzle.line.length) {
      _phase = SynPuzzlePhase.revealed;
      _notify();
      return;
    }
    _later(revealDelay, () {
      _lastMove = puzzle.line[_cursor];
      _cursor++;
      _notify();
      _stepReveal();
    });
  }

  void _later(Duration d, void Function() f) {
    _timer?.cancel();
    _timer = Timer(d, () {
      if (!_disposed) f();
    });
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _flashTimer?.cancel();
    super.dispose();
  }
}

// ---------------------------------------------------------------------------
// Board widget
// ---------------------------------------------------------------------------

class _Glyphs {
  const _Glyphs._();

  static const Map<String, String> glyph = <String, String>{
    'k': '\u265A',
    'q': '\u265B',
    'r': '\u265C',
    'b': '\u265D',
    'n': '\u265E',
    'p': '\u265F',
  };

  static const Color whiteFill = Color(0xFFEFFFFC);
  static const Color whiteLine = Color(0xFF0A1E26);
  static const Color blackFill = Color(0xFF1C1238);
  static const Color blackLine = _C.violet;

  static final Map<String, List<TextPainter>> _cache = <String, List<TextPainter>>{};
  static double _cachedSize = -1;

  /// [outline, fill] painters, cached per piece and font size.
  static List<TextPainter> of(String piece, double fontSize) {
    if (fontSize != _cachedSize) {
      _cache.clear();
      _cachedSize = fontSize;
    }
    return _cache.putIfAbsent(piece, () => _build(piece, fontSize));
  }

  static List<TextPainter> _build(String piece, double fs) {
    final white = _isWhitePiece(piece);
    final text = '${glyph[piece.toLowerCase()]!}\uFE0E'; // VS15: force text, never emoji
    const fallback = <String>[
      'Noto Sans Symbols 2',
      'Noto Sans Symbols',
      'DejaVu Sans',
      'Segoe UI Symbol',
      'Arial Unicode MS',
    ];
    final base = TextStyle(fontSize: fs, height: 1.0, fontFamilyFallback: fallback);
    TextPainter make(TextStyle s) =>
        TextPainter(text: TextSpan(text: text, style: s), textDirection: TextDirection.ltr)..layout();
    final outline = make(base.copyWith(
      foreground: Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = fs * 0.07
        ..strokeJoin = StrokeJoin.round
        ..color = white ? whiteLine : blackLine,
    ));
    final fill = make(base.copyWith(color: white ? whiteFill : blackFill));
    return <TextPainter>[outline, fill];
  }
}

class _BoardPainter extends CustomPainter {
  _BoardPainter({
    required this.cells,
    required this.whiteBottom,
    required this.targets,
    required this.flash,
    this.selected,
    this.lastFrom,
    this.lastTo,
    this.checkSquare,
    this.hintFrom,
    this.hintTo,
    this.dragFrom,
    this.dragPos,
  });

  final List<String> cells;
  final bool whiteBottom;
  final Set<int> targets;
  final Set<int> flash;
  final int? selected;
  final int? lastFrom;
  final int? lastTo;
  final int? checkSquare;
  final int? hintFrom;
  final int? hintTo;
  final int? dragFrom;
  final Offset? dragPos;

  Rect _rect(int idx, double cell) {
    final file = idx % 8;
    final rank = idx ~/ 8;
    final col = whiteBottom ? file : 7 - file;
    final row = whiteBottom ? 7 - rank : rank;
    return Rect.fromLTWH(col * cell, row * cell, cell, cell);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / 8;
    final dark = Paint()..color = const Color(0xFF0B1224);
    final light = Paint()..color = const Color(0xFF18223A);

    for (var idx = 0; idx < 64; idx++) {
      final r = _rect(idx, cell);
      canvas.drawRect(r, ((idx % 8) + (idx ~/ 8)) % 2 == 0 ? dark : light);
    }

    void tint(int? idx, Color color, double opacity) {
      if (idx == null) return;
      canvas.drawRect(_rect(idx, cell), Paint()..color = _a(color, opacity));
    }

    tint(lastFrom, _C.violet, 0.26);
    tint(lastTo, _C.violet, 0.36);
    for (final f in flash) {
      tint(f, _C.danger, 0.5);
    }
    if (selected != null) {
      tint(selected, _C.cyan, 0.3);
      canvas.drawRect(
        _rect(selected!, cell).deflate(1),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = _a(_C.cyan, 0.9),
      );
    }
    if (checkSquare != null) {
      final r = _rect(checkSquare!, cell);
      canvas.drawRect(
        r,
        Paint()
          ..shader = RadialGradient(colors: <Color>[_a(_C.danger, 0.85), _a(_C.danger, 0)])
              .createShader(Rect.fromCircle(center: r.center, radius: cell * 0.75)),
      );
    }

    // Coordinates.
    final coord = _mono(cell * 0.2, color: _a(_C.dim, 0.75), weight: FontWeight.w700, spacing: 0);
    for (var i = 0; i < 8; i++) {
      final fileIdx = whiteBottom ? i : 7 - i;
      final rankIdx = whiteBottom ? 7 - i : i;
      final f = TextPainter(
        text: TextSpan(text: 'abcdefgh'[fileIdx], style: coord),
        textDirection: TextDirection.ltr,
      )..layout();
      f.paint(canvas, Offset(i * cell + cell - f.width - 2, size.height - f.height - 1));
      final r = TextPainter(
        text: TextSpan(text: '${rankIdx + 1}', style: coord),
        textDirection: TextDirection.ltr,
      )..layout();
      r.paint(canvas, Offset(2, i * cell + 1));
    }

    // Hint rings.
    void ring(int? idx, Color color) {
      if (idx == null) return;
      final r = _rect(idx, cell).deflate(cell * 0.06);
      canvas.drawRect(
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = _a(color, 0.95)
          ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 2),
      );
    }

    ring(hintFrom, _C.violet);
    ring(hintTo, _C.cyan);

    // Pieces.
    final fontSize = cell * 0.82;
    void piece(String p, Offset center, double scale) {
      final painters = _Glyphs.of(p, fontSize);
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.scale(scale);
      for (final tp in painters) {
        tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
      }
      canvas.restore();
    }

    for (var idx = 0; idx < 64; idx++) {
      final p = cells[idx];
      if (p.isEmpty || idx == dragFrom) continue;
      piece(p, _rect(idx, cell).center, 1);
    }

    // Legal move markers.
    for (final t in targets) {
      final r = _rect(t, cell);
      if (cells[t].isNotEmpty) {
        canvas.drawCircle(
          r.center,
          cell * 0.45,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = cell * 0.07
            ..color = _a(_C.cyan, 0.8),
        );
      } else {
        canvas.drawCircle(r.center, cell * 0.14, Paint()..color = _a(_C.cyan, 0.6));
      }
    }

    if (dragFrom != null && dragPos != null && cells[dragFrom!].isNotEmpty) {
      piece(cells[dragFrom!], dragPos!, 1.18);
    }
  }

  @override
  bool shouldRepaint(covariant _BoardPainter old) => true;
}

class SynBoardView extends StatefulWidget {
  const SynBoardView({
    super.key,
    required this.session,
    required this.pickPromotion,
    this.hintFrom,
    this.hintTo,
  });

  final SynPuzzleSession session;

  /// Asks the user for a promotion piece: 'q', 'r', 'b' or 'n' (null = cancelled).
  final Future<String?> Function(Side side) pickPromotion;
  final int? hintFrom;
  final int? hintTo;

  @override
  State<SynBoardView> createState() => _SynBoardViewState();
}

class _SynBoardViewState extends State<SynBoardView> {
  int? _selected;
  Set<int> _targets = const <int>{};
  int? _dragFrom;
  Offset? _dragPos;
  double _cell = 1;

  bool get _whiteBottom => widget.session.puzzle.playerSide == Side.white;

  int? _squareAt(Offset p) {
    if (p.dx < 0 || p.dy < 0 || p.dx >= _cell * 8 || p.dy >= _cell * 8) return null;
    final col = (p.dx / _cell).floor();
    final row = (p.dy / _cell).floor();
    final file = _whiteBottom ? col : 7 - col;
    final rank = _whiteBottom ? 7 - row : row;
    return rank * 8 + file;
  }

  void _select(int? idx) {
    setState(() {
      _selected = idx;
      _targets = idx == null ? const <int>{} : widget.session.legalTargets(idx);
    });
  }

  bool get _canInteract => widget.session.isPlayerTurn;

  Future<void> _attempt(int from, int to) async {
    final s = widget.session;
    var uci = '${_sqName(from)}${_sqName(to)}';
    if (s.needsPromotion(from, to)) {
      final choice = await widget.pickPromotion(s.puzzle.playerSide);
      if (choice == null || !mounted) {
        _select(null);
        return;
      }
      uci += choice;
    }
    _select(null);
    s.tryMove(uci);
  }

  void _onTap(Offset p) {
    if (!_canInteract) return;
    final idx = _squareAt(p);
    if (idx == null) return;
    final s = widget.session;
    final sel = _selected;
    if (sel != null && _targets.contains(idx)) {
      _attempt(sel, idx);
    } else if (s.ownsPiece(idx) && idx != sel) {
      _select(idx);
    } else {
      _select(null);
    }
  }

  void _onPanStart(Offset p) {
    if (!_canInteract) return;
    final idx = _squareAt(p);
    if (idx == null || !widget.session.ownsPiece(idx)) return;
    _select(idx);
    setState(() {
      _dragFrom = idx;
      _dragPos = p;
    });
  }

  void _onPanEnd() {
    final from = _dragFrom;
    final pos = _dragPos;
    setState(() {
      _dragFrom = null;
      _dragPos = null;
    });
    if (from == null || pos == null) return;
    final to = _squareAt(pos);
    if (to != null && to != from && _targets.contains(to)) {
      _attempt(from, to);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.session,
      builder: (BuildContext context, Widget? child) {
        final s = widget.session;
        if (!s.isPlayerTurn && _selected != null) {
          // The position moved on (opponent reply, solve, reveal): drop stale selection.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _selected != null && !widget.session.isPlayerTurn) _select(null);
          });
        }
        final flash = s.wrongFlash;
        return AspectRatio(
          aspectRatio: 1,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints box) {
              _cell = box.maxWidth / 8;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: (TapUpDetails d) => _onTap(d.localPosition),
                onPanStart: (DragStartDetails d) => _onPanStart(d.localPosition),
                onPanUpdate: (DragUpdateDetails d) {
                  if (_dragFrom != null) setState(() => _dragPos = d.localPosition);
                },
                onPanEnd: (DragEndDetails d) => _onPanEnd(),
                onPanCancel: _onPanEnd,
                child: CustomPaint(
                  size: Size.square(box.maxWidth),
                  painter: _BoardPainter(
                    cells: s.cells,
                    whiteBottom: _whiteBottom,
                    targets: _targets,
                    flash: flash == null ? const <int>{} : <int>{flash.from, flash.to},
                    selected: _selected,
                    lastFrom: s.lastFrom,
                    lastTo: s.lastTo,
                    checkSquare: s.checkSquare,
                    hintFrom: widget.hintFrom,
                    hintTo: widget.hintTo,
                    dragFrom: _dragFrom,
                    dragPos: _dragPos,
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// 2. Offline puzzle player
// ---------------------------------------------------------------------------

class SynOfflinePuzzlePlayerScreen extends StatefulWidget {
  const SynOfflinePuzzlePlayerScreen({
    super.key,
    required this.repository,
    required this.pack,
    this.initialPuzzle,
    this.minRating,
    this.maxRating,
    this.theme,
  });

  final SynPuzzleRepository repository;
  final SynPuzzlePack pack;

  /// Optional first puzzle; otherwise one is fetched with the filters below.
  final SynPuzzleRecord? initialPuzzle;
  final int? minRating;
  final int? maxRating;
  final String? theme;

  @override
  State<SynOfflinePuzzlePlayerScreen> createState() => _SynOfflinePuzzlePlayerScreenState();
}

class _SynOfflinePuzzlePlayerScreenState extends State<SynOfflinePuzzlePlayerScreen> {
  late SynPuzzlePack _pack = widget.pack;
  SynPuzzleSession? _session;
  bool _loading = true;
  bool _exhausted = false;
  bool _replaySolved = false;
  String? _error;
  int _hintLevel = 0;
  int _maxHint = 0;
  int _lastCursor = 1;
  bool _marked = false;
  int _ticket = 0;
  int _solvedThisRun = 0;
  final Set<String> _seen = <String>{};
  Future<SynPuzzleRecord?>? _prefetched;

  @override
  void initState() {
    super.initState();
    _loadNext(first: widget.initialPuzzle);
  }

  @override
  void dispose() {
    _ticket++;
    final s = _session;
    s?.removeListener(_onSession);
    s?.dispose();
    super.dispose();
  }

  // ----- loading -------------------------------------------------------------

  Future<SynPuzzleRecord?> _fetch() => widget.repository.getNextPuzzle(
        packId: _pack.packId,
        minRating: widget.minRating,
        maxRating: widget.maxRating,
        theme: widget.theme,
        includeSolved: _replaySolved,
      );

  /// Warm the next puzzle while the player thinks, so "NEXT" is instant.
  void _prefetch() {
    _prefetched = _fetch().then<SynPuzzleRecord?>((SynPuzzleRecord? v) => v, onError: (Object _) => null);
  }

  Future<void> _loadNext({SynPuzzleRecord? first}) async {
    final ticket = ++_ticket;
    setState(() {
      _loading = true;
      _error = null;
      _exhausted = false;
    });
    try {
      SynPuzzleRecord? rec = first;
      if (rec == null) {
        final pre = _prefetched;
        _prefetched = null;
        rec = pre != null ? await pre : null;
        rec ??= await _fetch();
      }
      for (var i = 0; i < 4 && rec != null && _seen.contains(rec.id); i++) {
        rec = await _fetch();
      }
      SynPlayablePuzzle? playable;
      for (var i = 0; i < 5 && rec != null && playable == null; i++) {
        try {
          playable = SynLichessPuzzleAdapter.adapt(rec);
        } on SynPuzzleAdaptException {
          rec = await _fetch();
        }
      }
      if (!mounted || ticket != _ticket) return;
      if (rec == null) {
        _swapSession(null);
        setState(() {
          _loading = false;
          _exhausted = true;
        });
        return;
      }
      if (playable == null) {
        setState(() {
          _loading = false;
          _error = 'Could not find a playable puzzle in this pack';
        });
        return;
      }
      _seen.add(rec.id);
      _marked = false;
      _hintLevel = 0;
      _maxHint = 0;
      _lastCursor = 1;
      _swapSession(SynPuzzleSession(playable));
      _prefetch();
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted || ticket != _ticket) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  void _swapSession(SynPuzzleSession? next) {
    final old = _session;
    old?.removeListener(_onSession);
    old?.dispose();
    _session = next;
    next?.addListener(_onSession);
  }

  // ----- session events --------------------------------------------------------

  void _onSession() {
    final s = _session;
    if (s == null || !mounted) return;
    if (s.cursor != _lastCursor) {
      _lastCursor = s.cursor;
      _hintLevel = 0; // fresh progressive hints for every step
    }
    setState(() {});
    if (s.isSolved && !_marked) {
      _marked = true;
      _handleSolved(s);
    }
  }

  Future<void> _handleSolved(SynPuzzleSession s) async {
    try {
      await widget.repository.markSolved(_pack.packId, s.puzzle.record.id);
      final packs = await widget.repository.listPacks();
      if (!mounted) return;
      for (final p in packs) {
        if (p.packId == _pack.packId) {
          setState(() {
            _pack = p;
            _solvedThisRun++;
          });
          break;
        }
      }
    } catch (e) {
      if (mounted) setState(() => _error = 'Could not save progress: $e');
    }
  }

  // ----- hints ---------------------------------------------------------------

  void _hint() {
    final s = _session;
    if (s == null || !s.isPlayerTurn) return;
    setState(() {
      _hintLevel = _hintLevel < 3 ? _hintLevel + 1 : 3;
      if (_hintLevel > _maxHint) _maxHint = _hintLevel;
    });
  }

  String? _hintText() {
    final s = _session;
    if (s == null || _hintLevel == 0 || s.isFinished) return null;
    final record = s.puzzle.record;
    if (s.cursor == 1) return SynTacticalHintEngine.hint(record, level: _hintLevel);
    // Later steps: motif hint from the engine, piece/target for the *current* step.
    var text = SynTacticalHintEngine.hint(record, level: 1);
    final exp = s.expectedUci;
    if (exp != null && _hintLevel >= 2) {
      final name = _pieceNames[s.cells[_sqIdx(exp.substring(0, 2))].toLowerCase()];
      if (name != null) {
        text += _hintLevel >= 3 ? ' Move your $name and aim for ${exp.substring(2, 4)}.' : ' Move your $name.';
      }
    }
    return text;
  }

  int? get _hintFromIdx {
    final s = _session;
    final exp = s?.expectedUci;
    if (s == null || exp == null || !s.isPlayerTurn || _hintLevel < 2) return null;
    return _sqIdx(exp.substring(0, 2));
  }

  int? get _hintToIdx {
    final s = _session;
    final exp = s?.expectedUci;
    if (s == null || exp == null || !s.isPlayerTurn || _hintLevel < 3) return null;
    return _sqIdx(exp.substring(2, 4));
  }

  // ----- promotion ----------------------------------------------------------

  Future<String?> _pickPromotion(Side side) {
    final white = side == Side.white;
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (BuildContext ctx) => Padding(
        padding: const EdgeInsets.all(14),
        child: _Card(
          accent: _C.violet,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('PROMOTE TO', style: _mono(12, color: _C.violet, weight: FontWeight.w700, spacing: 2)),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  for (final code in const <String>['q', 'r', 'b', 'n'])
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: InkWell(
                          onTap: () => Navigator.of(ctx).pop(code),
                          child: Container(
                            height: 64,
                            alignment: Alignment.center,
                            decoration: ShapeDecoration(
                              color: _a(_C.surfaceHi, 0.9),
                              shape: SynChamferBorder(
                                chamfer: 9,
                                side: BorderSide(color: _a(_C.cyan, 0.6), width: 1),
                              ),
                            ),
                            child: Text(
                              '${_Glyphs.glyph[code]!}\uFE0E',
                              style: TextStyle(
                                fontSize: 40,
                                height: 1,
                                color: white ? _Glyphs.whiteFill : _C.violet,
                                fontFamilyFallback: const <String>[
                                  'Noto Sans Symbols 2',
                                  'Noto Sans Symbols',
                                  'DejaVu Sans',
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ----- UI -----------------------------------------------------------------

  ({String text, Color color}) _status(SynPuzzleSession s) {
    final side = s.puzzle.playerSide == Side.white ? 'WHITE' : 'BLACK';
    if (s.wrongFlash != null) return (text: 'INCORRECT — TRY AGAIN', color: _C.danger);
    switch (s.phase) {
      case SynPuzzlePhase.playerTurn:
        return (text: 'YOUR MOVE — $side TO PLAY', color: _C.cyan);
      case SynPuzzlePhase.opponentTurn:
        return (text: 'OPPONENT RESPONDS…', color: _C.violet);
      case SynPuzzlePhase.solved:
        return s.mistakes == 0
            ? (text: _maxHint == 0 ? 'SOLVED — FLAWLESS' : 'SOLVED — CLEAN (HINT L$_maxHint)', color: _C.cyan)
            : (text: 'SOLVED — ${s.mistakes} MISTAKE${s.mistakes == 1 ? '' : 'S'}', color: _C.amber);
      case SynPuzzlePhase.revealing:
        return (text: 'SOLUTION PLAYBACK…', color: _C.violet);
      case SynPuzzlePhase.revealed:
        return (text: 'SOLUTION SHOWN — NOT COUNTED', color: _C.amber);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      body: Stack(
        children: <Widget>[
          const Positioned.fill(child: RepaintBoundary(child: CustomPaint(painter: _BackdropPainter()))),
          SafeArea(
            child: Column(
              children: <Widget>[
                _topBar(),
                Expanded(child: _body()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _topBar() {
    final record = _session?.puzzle.record;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 14, 0),
      child: Row(
        children: <Widget>[
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: _C.cyan),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('OFFLINE PUZZLE', style: _mono(14, color: _C.cyan, weight: FontWeight.w800, spacing: 2)),
                Text(
                  '${_pack.name} · ${_fmtInt(_pack.solvedCount)}/${_fmtInt(_pack.totalCount)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _mono(10.5, color: _C.dim, spacing: 0.8),
                ),
              ],
            ),
          ),
          if (record != null) _Badge('RATING ${record.rating}', _C.violet),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading && _session == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text('LOADING PUZZLE…', style: _mono(12, color: _C.cyan, spacing: 2)),
              const SizedBox(height: 14),
              const _NeonBar(),
            ],
          ),
        ),
      );
    }
    if (_error != null && _session == null) return _messageCard('ERROR', _error!, retry: true);
    if (_exhausted) {
      return _messageCard(
        'NO MORE PUZZLES',
        _replaySolved
            ? 'Nothing matches the current filter in this pack.'
            : 'Every puzzle matching the filter is solved. Replay solved ones or change the filter.',
        replay: !_replaySolved,
      );
    }
    final s = _session;
    if (s == null) return const SizedBox.shrink();
    final status = _status(s);
    final record = s.puzzle.record;
    final width = MediaQuery.of(context).size.width;
    final shownThemes = s.isFinished ? record.themeList : const <String>[];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      child: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: width > 560 ? 520 : width),
          child: Column(
            children: <Widget>[
              _StatusStrip(status.text, status.color),
              const SizedBox(height: 12),
              _Card(
                padding: const EdgeInsets.all(6),
                chamfer: 18,
                accent: status.color,
                child: ClipPath(
                  clipper: const ShapeBorderClipper(shape: SynChamferBorder(chamfer: 14)),
                  child: SynBoardView(
                    session: s,
                    pickPromotion: _pickPromotion,
                    hintFrom: _hintFromIdx,
                    hintTo: _hintToIdx,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _hintPanel(s),
              const SizedBox(height: 12),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _CyberButton(
                      label: _hintLevel >= 3 ? 'HINT 3/3' : 'HINT ${_hintLevel + 1}/3',
                      icon: Icons.lightbulb_outline,
                      accent: _C.amber,
                      dense: true,
                      onPressed: s.isPlayerTurn && _hintLevel < 3 ? _hint : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _CyberButton(
                      label: 'SOLUTION',
                      icon: Icons.visibility_outlined,
                      accent: _C.violet,
                      dense: true,
                      onPressed: s.isFinished || s.phase == SynPuzzlePhase.revealing ? null : s.revealSolution,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _CyberButton(
                      label: 'NEXT',
                      icon: Icons.skip_next,
                      filled: s.isFinished,
                      dense: true,
                      onPressed: _loading ? null : () => _loadNext(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _Card(
                accent: _C.violet,
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(child: _Telemetry('PUZZLE', record.id, color: _C.text)),
                        Expanded(child: _Telemetry('PLIES', '${s.puzzle.line.length - 1}', color: _C.text)),
                        Expanded(child: _Telemetry('SOLVED RUN', '$_solvedThisRun')),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text('THEMES', style: _mono(9.5, color: _C.dim, weight: FontWeight.w700, spacing: 1.6)),
                    const SizedBox(height: 6),
                    if (shownThemes.isEmpty)
                      Text('CLASSIFIED UNTIL SOLVED', style: _mono(11, color: _C.dim, spacing: 1.2))
                    else
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: <Widget>[for (final t in shownThemes) _Badge(t, _C.cyan)],
                      ),
                  ],
                ),
              ),
              if (_error != null) ...<Widget>[
                const SizedBox(height: 10),
                Text(_error!, style: _mono(11, color: _C.danger, spacing: 0.4)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _hintPanel(SynPuzzleSession s) {
    final text = _hintText();
    return _Card(
      accent: _C.amber,
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Column(
            children: <Widget>[
              for (var i = 3; i >= 1; i--)
                Container(
                  width: 10,
                  height: 16,
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: ShapeDecoration(
                    color: _hintLevel >= i ? _C.amber : _a(_C.line, 0.9),
                    shape: const SynChamferBorder(chamfer: 3),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _hintLevel == 0 ? 'HINT MATRIX' : 'HINT MATRIX · LEVEL $_hintLevel/3',
                  style: _mono(10, color: _C.amber, weight: FontWeight.w700, spacing: 1.6),
                ),
                const SizedBox(height: 6),
                Text(
                  text ??
                      (s.isFinished
                          ? 'Puzzle complete.'
                          : 'Level 1 reveals the tactical motif, level 2 the piece to move, level 3 the target square.'),
                  style: _mono(12.5, color: text == null ? _C.dim : _C.text, spacing: 0.2, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _messageCard(String title, String body, {bool retry = false, bool replay = false}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: _Card(
          accent: retry ? _C.danger : _C.violet,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: _mono(14, color: retry ? _C.danger : _C.violet, weight: FontWeight.w800, spacing: 2)),
              const SizedBox(height: 10),
              Text(body, style: _mono(12.5, color: _C.text, height: 1.45, spacing: 0.2)),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  if (retry)
                    Expanded(child: _CyberButton(label: 'RETRY', dense: true, onPressed: () => _loadNext())),
                  if (replay)
                    Expanded(
                      child: _CyberButton(
                        label: 'REPLAY SOLVED',
                        dense: true,
                        accent: _C.violet,
                        onPressed: () {
                          _replaySolved = true;
                          _seen.clear();
                          _loadNext();
                        },
                      ),
                    ),
                  if (retry || replay) const SizedBox(width: 8),
                  Expanded(
                    child: _CyberButton(
                      label: 'BACK',
                      dense: true,
                      accent: _C.dim,
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 3. Cyber-vault management screen
// ---------------------------------------------------------------------------

class SynPuzzleVaultScreen extends StatefulWidget {
  const SynPuzzleVaultScreen({super.key, required this.repository});

  final SynPuzzleRepository repository;

  static Route<void> route(SynPuzzleRepository repository) =>
      MaterialPageRoute<void>(builder: (_) => SynPuzzleVaultScreen(repository: repository));

  @override
  State<SynPuzzleVaultScreen> createState() => _SynPuzzleVaultScreenState();
}

class _SynPuzzleVaultScreenState extends State<SynPuzzleVaultScreen> {
  static const List<String> _themes = <String>[
    'ALL',
    'mateIn1',
    'mateIn2',
    'mateIn3',
    'fork',
    'pin',
    'skewer',
    'endgame',
    'sacrifice',
  ];
  static const double _ratingMin = 600;
  static const double _ratingMax = 2800;

  List<SynPuzzlePack> _packs = const <SynPuzzlePack>[];
  bool _loading = true;
  String? _error;

  SynImportMode? _forceMode; // null = auto
  bool _importing = false;
  SynCancelToken? _cancel;
  SynPackImportProgress? _progress;
  final List<String> _terminal = <String>[];
  SynPackStage? _lastStage;
  String _lastMessage = '';

  String _theme = 'ALL';
  RangeValues _rating = const RangeValues(_ratingMin, _ratingMax);

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _cancel?.cancel();
    super.dispose();
  }

  SynPuzzlePack? get _active {
    for (final p in _packs) {
      if (p.isActive) return p;
    }
    return null;
  }

  Future<void> _refresh() async {
    try {
      final packs = await widget.repository.listPacks();
      if (!mounted) return;
      setState(() {
        _packs = packs;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$e';
      });
    }
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
    await _refresh();
  }

  // ----- import / mount -----------------------------------------------------

  void _log(String line) {
    if (_terminal.isNotEmpty && _terminal.last == line) return;
    _terminal.add(line);
    if (_terminal.length > 60) _terminal.removeAt(0);
  }

  void _absorb(SynPackImportProgress e) {
    _progress = e;
    if (e.stage != _lastStage) {
      _lastStage = e.stage;
      _log('[${e.stage.name.toUpperCase()}] ${e.message}');
      _lastMessage = e.message;
    } else if (e.message.isNotEmpty && e.message != _lastMessage) {
      _lastMessage = e.message;
      _log('> ${e.message}');
    }
    if (e.stage == SynPackStage.done) {
      final pack = e.pack;
      _log('OK  ${pack == null ? 'done' : '${pack.name} · ${_fmtInt(pack.totalCount)} puzzles ready'}');
    } else if (e.stage == SynPackStage.failed) {
      _log('ERR ${e.error ?? e.message}');
    } else if (e.stage == SynPackStage.cancelled) {
      _log('ERR ${e.message.isEmpty ? 'cancelled' : e.message}');
    }
  }

  Future<void> _runImport() async {
    if (_importing) return;
    final token = SynCancelToken();
    setState(() {
      _importing = true;
      _cancel = token;
      _progress = null;
      _lastStage = null;
      _lastMessage = '';
      _error = null;
      _terminal
        ..clear()
        ..add('> opening system file picker…');
    });
    try {
      await for (final e in widget.repository.pickAndImport(forceMode: _forceMode, cancelToken: token)) {
        if (!mounted) continue;
        setState(() => _absorb(e));
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) {
        setState(() {
          _importing = false;
          _cancel = null;
        });
      }
      await _refresh();
    }
  }

  void _dismissTerminal() {
    setState(() {
      _progress = null;
      _terminal.clear();
    });
  }

  // ----- pack actions -------------------------------------------------------

  Future<bool> _confirm(String title, String body, String action, {bool danger = false}) async {
    final accent = danger ? _C.danger : _C.cyan;
    final result = await showDialog<bool>(
      context: context,
      builder: (BuildContext ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(20),
        child: _Card(
          accent: accent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(title, style: _mono(14, color: accent, weight: FontWeight.w800, spacing: 1.6)),
              const SizedBox(height: 10),
              Text(body, style: _mono(12.5, color: _C.text, height: 1.45, spacing: 0.2)),
              const SizedBox(height: 16),
              Row(
                children: <Widget>[
                  Expanded(
                    child: _CyberButton(
                      label: 'CANCEL',
                      dense: true,
                      accent: _C.dim,
                      onPressed: () => Navigator.of(ctx).pop(false),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _CyberButton(
                      label: action,
                      dense: true,
                      accent: accent,
                      filled: true,
                      onPressed: () => Navigator.of(ctx).pop(true),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    return result ?? false;
  }

  Future<void> _activate(SynPuzzlePack pack) async {
    if (pack.isActive) return;
    await _guard(() async {
      await widget.repository.setActivePack(pack.packId);
    });
  }

  Future<void> _reset(SynPuzzlePack pack) async {
    final ok = await _confirm(
      'RESET PROGRESS',
      'Clear solved progress for "${pack.name}"? The puzzles themselves stay.',
      'RESET',
    );
    if (!ok) return;
    await _guard(() => widget.repository.resetProgress(pack.packId));
  }

  Future<void> _delete(SynPuzzlePack pack) async {
    final ok = await _confirm(
      'DELETE PACK',
      'Remove "${pack.name}" and its backing file/rows from this device? This cannot be undone.',
      'DELETE',
      danger: true,
    );
    if (!ok) return;
    await _guard(() => widget.repository.deletePack(pack.packId));
  }

  Future<void> _launch() async {
    final pack = _active;
    if (pack == null) return;
    final lo = _rating.start.round();
    final hi = _rating.end.round();
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SynOfflinePuzzlePlayerScreen(
          repository: widget.repository,
          pack: pack,
          minRating: lo <= _ratingMin ? null : lo,
          maxRating: hi >= _ratingMax ? null : hi,
          theme: _theme == 'ALL' ? null : _theme,
        ),
      ),
    );
    await _refresh();
  }

  // ----- build ----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _C.bg,
      body: Stack(
        children: <Widget>[
          const Positioned.fill(child: RepaintBoundary(child: CustomPaint(painter: _BackdropPainter()))),
          SafeArea(
            child: RefreshIndicator(
              color: _C.cyan,
              backgroundColor: _C.surface,
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 32),
                children: <Widget>[
                  _header(),
                  const SizedBox(height: 14),
                  _hud(),
                  const SizedBox(height: 16),
                  _sectionTitle('01 // INGEST'),
                  const SizedBox(height: 8),
                  _importSection(),
                  const SizedBox(height: 18),
                  _sectionTitle('02 // INSTALLED PACKS'),
                  const SizedBox(height: 8),
                  ..._packSection(),
                  const SizedBox(height: 18),
                  _sectionTitle('03 // FILTER & LAUNCH'),
                  const SizedBox(height: 8),
                  _launchDeck(),
                  if (_error != null) ...<Widget>[
                    const SizedBox(height: 14),
                    _Card(
                      accent: _C.danger,
                      child: Text('ERR ${_error!}', style: _mono(11.5, color: _C.danger, height: 1.4, spacing: 0.2)),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Row(
      children: <Widget>[
        if (Navigator.of(context).canPop())
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_ios_new, size: 18, color: _C.cyan),
          ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('SYNTOXAN // VAULT', style: _mono(11, color: _C.violet, weight: FontWeight.w700, spacing: 3)),
              const SizedBox(height: 2),
              Text('PUZZLE VAULT', style: _mono(24, color: _C.cyan, weight: FontWeight.w800, spacing: 2)),
              Text('OFFLINE · BYOD · CC0', style: _mono(10, color: _C.dim, spacing: 2.2)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sectionTitle(String text) {
    return Row(
      children: <Widget>[
        Container(width: 8, height: 8, color: _C.cyan),
        const SizedBox(width: 8),
        Text(text, style: _mono(11, color: _C.text, weight: FontWeight.w700, spacing: 2.4)),
        const SizedBox(width: 10),
        Expanded(child: Container(height: 1, color: _a(_C.cyan, 0.2))),
      ],
    );
  }

  Widget _hud() {
    var total = 0;
    var bytes = 0;
    for (final p in _packs) {
      total += p.totalCount;
      bytes += p.sizeBytes;
    }
    final active = _active;
    final progress = active?.progress ?? 0.0;
    return _Card(
      accent: _C.cyan,
      chamfer: 20,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: _Telemetry('INDEXED PUZZLES', _loading ? '…' : _fmtInt(total))),
              Expanded(child: _Telemetry('PACKS', '${_packs.length}', color: _C.violet)),
              Expanded(child: _Telemetry('STORAGE', _fmtBytes(bytes), color: _C.text)),
            ],
          ),
          const SizedBox(height: 14),
          _Telemetry('ACTIVE PACK', active?.name ?? 'NONE', color: active == null ? _C.dim : _C.violet),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Text('SOLVED', style: _mono(9.5, color: _C.dim, weight: FontWeight.w700, spacing: 1.6)),
              const Spacer(),
              Text(
                active == null
                    ? '— / —'
                    : '${_fmtInt(active.solvedCount)} / ${_fmtInt(active.totalCount)}  ·  ${(progress * 100).toStringAsFixed(1)}%',
                style: _mono(11, color: _C.cyan, weight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _NeonBar(value: progress),
        ],
      ),
    );
  }

  Widget _importSection() {
    final modeText = switch (_forceMode) {
      null => '.db files mount instantly · text files are parsed and ingested',
      SynImportMode.directMount => 'SQLite only · zero-copy · read-only · progress kept separately',
      SynImportMode.batchIngestion => 'parse and copy every puzzle into syn_offline_puzzles',
    };
    final progress = _progress;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            _modeSegment('AUTO', null),
            const SizedBox(width: 6),
            _modeSegment('DIRECT MOUNT', SynImportMode.directMount),
            const SizedBox(width: 6),
            _modeSegment('BATCH INGEST', SynImportMode.batchIngestion),
          ],
        ),
        const SizedBox(height: 8),
        Text(modeText, style: _mono(10.5, color: _C.dim, height: 1.4, spacing: 0.3)),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: _CyberButton(
            label: 'IMPORT / MOUNT PUZZLE FILE',
            icon: Icons.upload_file,
            filled: true,
            onPressed: _importing ? null : _runImport,
          ),
        ),
        if (_importing || progress != null || _terminal.isNotEmpty) ...<Widget>[
          const SizedBox(height: 12),
          _terminalPanel(progress),
        ],
      ],
    );
  }

  Widget _modeSegment(String label, SynImportMode? mode) {
    final selected = _forceMode == mode;
    final color = selected ? _C.cyan : _C.dim;
    final shape = SynChamferBorder(
      chamfer: 8,
      side: BorderSide(color: _a(color, selected ? 0.95 : 0.4), width: 1.1),
    );
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: ShapeDecoration(color: selected ? _a(_C.cyan, 0.14) : _a(_C.surface, 0.8), shape: shape),
          child: InkWell(
            customBorder: shape,
            onTap: _importing ? null : () => setState(() => _forceMode = mode),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 11),
              child: Center(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _mono(10, color: color, weight: FontWeight.w700, spacing: 0.9),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _terminalPanel(SynPackImportProgress? progress) {
    final stage = progress?.stage;
    final import = progress?.import;
    final terminal = progress?.isTerminal ?? false;
    final failed = stage == SynPackStage.failed || stage == SynPackStage.cancelled;
    final accent = failed ? _C.danger : (stage == SynPackStage.done ? _C.cyan : _C.violet);
    final canCancel = stage == SynPackStage.ingesting && !terminal;
    final lines = _terminal.length > 9 ? _terminal.sublist(_terminal.length - 9) : _terminal;

    return _Card(
      accent: accent,
      flip: true,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text('TERMINAL', style: _mono(10, color: _C.dim, weight: FontWeight.w700, spacing: 2)),
              const Spacer(),
              _Badge(stage == null ? 'WAITING' : stage.name.toUpperCase(), accent),
            ],
          ),
          const SizedBox(height: 10),
          _NeonBar(value: terminal ? (failed ? (import?.fraction ?? 0) : 1) : progress?.fraction),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(child: _Telemetry('PARSED', _fmtInt(import?.recordsParsed ?? 0), color: _C.text)),
              Expanded(child: _Telemetry('INSERTED', _fmtInt(import?.recordsInserted ?? 0))),
              Expanded(child: _Telemetry('SKIPPED', _fmtInt(import?.recordsSkipped ?? 0), color: _C.amber)),
              Expanded(child: _Telemetry('DUP', _fmtInt(import?.duplicates ?? 0), color: _C.violet)),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: _a(Colors.black, 0.45), border: Border.all(color: _a(_C.line, 0.9))),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                for (final l in lines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      l,
                      style: _mono(
                        10.5,
                        color: l.startsWith('ERR')
                            ? _C.danger
                            : (l.startsWith('OK') ? _C.cyan : _a(_C.cyan, 0.7)),
                        spacing: 0.2,
                        height: 1.3,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: _CyberButton(
                  label: 'CANCEL',
                  icon: Icons.cancel_outlined,
                  dense: true,
                  accent: _C.danger,
                  onPressed: canCancel ? () => _cancel?.cancel() : null,
                ),
              ),
              if (terminal) ...<Widget>[
                const SizedBox(width: 8),
                Expanded(
                  child: _CyberButton(
                    label: 'DISMISS',
                    icon: Icons.close,
                    dense: true,
                    accent: _C.dim,
                    onPressed: _dismissTerminal,
                  ),
                ),
              ],
            ],
          ),
          if (!terminal && !canCancel) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              'Cancel is available while a text file is being ingested.',
              style: _mono(9.5, color: _C.dim, spacing: 0.3),
            ),
          ],
        ],
      ),
    );
  }

  // ----- packs ----------------------------------------------------------------

  List<Widget> _packSection() {
    if (_loading) {
      return <Widget>[const Padding(padding: EdgeInsets.all(16), child: _NeonBar())];
    }
    if (_packs.isEmpty) {
      return <Widget>[
        _Card(
          accent: _C.violet,
          child: Text(
            'NO PACKS INSTALLED\nImport a Lichess puzzle .db, CSV/TSV, JSON/NDJSON, PGN, EPD or a .gz of any of them.',
            style: _mono(12, color: _C.dim, height: 1.5, spacing: 0.3),
          ),
        ),
      ];
    }
    return <Widget>[
      for (final p in _packs) ...<Widget>[
        _packCard(p),
        const SizedBox(height: 10),
      ],
    ];
  }

  String _formatLabel(String format) {
    switch (format) {
      case 'sqliteDb':
        return 'SQLITE';
      case 'csvOrTsv':
        return 'CSV/TSV';
      case 'jsonOrNdjson':
        return 'JSON';
      case 'pgnBook':
        return 'PGN';
      case 'epdOrFen':
        return 'EPD/FEN';
      default:
        return format.toUpperCase();
    }
  }

  Widget _packCard(SynPuzzlePack pack) {
    final accent = pack.isActive ? _C.cyan : _C.violet;
    return _Card(
      accent: accent,
      glow: pack.isActive,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _activate(pack),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 2, 12, 8),
                  child: _NeonRadio(selected: pack.isActive),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      pack.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: _mono(14, color: _C.text, weight: FontWeight.w700, spacing: 0.3),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: <Widget>[
                        _Badge(pack.isMounted ? 'DIRECT MOUNT' : 'INGESTED', pack.isMounted ? _C.violet : _C.cyan),
                        _Badge(_formatLabel(pack.format), _C.amber),
                        if (pack.isActive) const _Badge('ACTIVE', _C.cyan),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: _Telemetry('SOLVED / TOTAL', '${_fmtInt(pack.solvedCount)} / ${_fmtInt(pack.totalCount)}', color: _C.text),
              ),
              Expanded(child: _Telemetry('SIZE', _fmtBytes(pack.sizeBytes), color: _C.text)),
            ],
          ),
          const SizedBox(height: 8),
          _NeonBar(value: pack.progress, height: 6),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              _CyberButton(
                label: 'RESET',
                icon: Icons.restart_alt,
                dense: true,
                accent: _C.amber,
                onPressed: pack.solvedCount == 0 ? null : () => _reset(pack),
              ),
              const SizedBox(width: 8),
              _CyberButton(
                label: 'DELETE',
                icon: Icons.delete_outline,
                dense: true,
                accent: _C.danger,
                onPressed: _importing ? null : () => _delete(pack),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ----- filter & launch ---------------------------------------------------

  Widget _launchDeck() {
    final active = _active;
    final lo = _rating.start.round();
    final hi = _rating.end.round();
    return _Card(
      accent: _C.violet,
      chamfer: 20,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text('THEME', style: _mono(9.5, color: _C.dim, weight: FontWeight.w700, spacing: 1.6)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final t in _themes) _chip(t),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              Text('RATING', style: _mono(9.5, color: _C.dim, weight: FontWeight.w700, spacing: 1.6)),
              const Spacer(),
              Text('$lo — $hi', style: _mono(13, color: _C.cyan, weight: FontWeight.w700)),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              activeTrackColor: _C.cyan,
              inactiveTrackColor: _C.line,
              thumbColor: _C.violet,
              overlayColor: _a(_C.violet, 0.2),
              activeTickMarkColor: Colors.transparent,
              inactiveTickMarkColor: Colors.transparent,
              rangeThumbShape: const RoundRangeSliderThumbShape(enabledThumbRadius: 8),
              valueIndicatorColor: _C.surfaceHi,
              valueIndicatorTextStyle: _mono(11, color: _C.cyan),
            ),
            child: RangeSlider(
              values: _rating,
              min: _ratingMin,
              max: _ratingMax,
              divisions: 44,
              labels: RangeLabels('$lo', '$hi'),
              onChanged: (RangeValues v) => setState(() => _rating = v),
            ),
          ),
          Text(
            'FILTER  ${_theme == 'ALL' ? 'ANY THEME' : _theme}  ·  ${lo <= _ratingMin ? 'MIN' : lo} – ${hi >= _ratingMax ? 'MAX' : hi}',
            style: _mono(10.5, color: _C.dim, spacing: 0.6),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: _CyberButton(
              label: 'LAUNCH OFFLINE PUZZLES',
              icon: Icons.play_arrow,
              filled: true,
              accent: _C.cyan,
              onPressed: active == null || _importing ? null : _launch,
            ),
          ),
          if (active == null) ...<Widget>[
            const SizedBox(height: 8),
            Text('Select an active pack to launch.', style: _mono(10.5, color: _C.dim, spacing: 0.3)),
          ],
        ],
      ),
    );
  }

  Widget _chip(String label) {
    final selected = _theme == label;
    final color = selected ? _C.cyan : _C.dim;
    final shape = SynChamferBorder(
      chamfer: 7,
      side: BorderSide(color: _a(color, selected ? 0.95 : 0.45), width: 1),
    );
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: ShapeDecoration(color: selected ? _a(_C.cyan, 0.14) : _a(_C.surface, 0.8), shape: shape),
        child: InkWell(
          customBorder: shape,
          onTap: () => setState(() => _theme = label),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(label, style: _mono(11, color: color, weight: FontWeight.w700, spacing: 0.8)),
          ),
        ),
      ),
    );
  }
}

class _NeonRadio extends StatelessWidget {
  const _NeonRadio({required this.selected});
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = selected ? _C.cyan : _C.dim;
    return Semantics(
      inMutuallyExclusiveGroup: true,
      checked: selected,
      label: 'Active pack',
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 1.6),
          boxShadow: selected ? <BoxShadow>[BoxShadow(color: _a(_C.cyan, 0.45), blurRadius: 10)] : null,
        ),
        child: selected
            ? Center(
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: _C.cyan),
                ),
              )
            : null,
      ),
    );
  }
}
