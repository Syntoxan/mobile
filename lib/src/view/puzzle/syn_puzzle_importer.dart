// SYNTOXAN — Bring-Your-Own-Data (BYOD) offline puzzle importer. PART 1 OF 3.
//
// Target path: lib/src/puzzle/syn_puzzle_importer.dart
//
// Allowed imports only: dart:async/convert/io/isolate/typed_data, sqflite,
// path and dartchess (all already in the Lichess pubspec). Nothing new.
//
// Pipeline overview
//   1. SynFileFormatDetector  magic-byte sniffing, recursive gzip/zlib peeling,
//                             text classification (CSV/TSV, JSON/NDJSON, PGN, EPD/FEN).
//   2. SynSqliteIntrospector  alias-based schema discovery for external .db files.
//   3. SynParsers             streaming, allocation-light parsers -> SynRawPuzzle.
//   4. SynMoveNormalizer      SAN/UCI -> canonical Lichess UCI line (opponent setup
//                             move first), with convention auto-detection and
//                             synthesis of a legal setup move for player-first data.
//   5. SynPuzzleImporter      worker isolate (parse + normalize) -> main isolate
//                             (sqflite Batch, 2,500 rows per commit) with
//                             back-pressure and a Stream<SynImportProgress>.
//                             Also Direct Mount mode (zero-copy read-only mount / ATTACH).
//
// Note: Lichess ships its puzzle dump as .csv.zst. Zstandard cannot be decoded
// with dart:io, so .zst/.xz/.bz2/.zip are detected and rejected with a clear
// message (decompress once with `zstd -d`, or recompress to .gz).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dartchess/dartchess.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

// ---------------------------------------------------------------------------
// Constants & enums
// ---------------------------------------------------------------------------

const int kSynImportBatchSize = 2500;
const String kSynPuzzleTable = 'syn_offline_puzzles';
const int kSynDefaultRating = 1500;
const String kSynDefaultThemes = 'tactics';

/// Result of format sniffing.
enum SynPuzzleFormat {
  sqliteDb,
  gzipStream,
  zlibStream,
  csvOrTsv,
  jsonOrNdjson,
  pgnBook,
  epdOrFen,
  unsupportedCompression,
  unknown,
}

/// Which move in a puzzle line is the first one.
///  * [opponentSetupFirst]: Lichess standard, FEN is before the opponent's
///    setup move, moves[1] is the player's first solution move.
///  * [playerFirst]: FEN is the puzzle position, moves[0] is the player's move.
enum SynFirstMovePolicy { auto, opponentSetupFirst, playerFirst }

enum SynImportMode { batchIngestion, directMount }

enum SynImportPhase { sniffing, parsing, writing, indexing, finished, cancelled, failed }

class SynNormalizeException implements Exception {
  const SynNormalizeException(this.message);
  final String message;
  @override
  String toString() => 'SynNormalizeException: $message';
}

class SynImportException implements Exception {
  const SynImportException(this.message);
  final String message;
  @override
  String toString() => 'SynImportException: $message';
}

// ---------------------------------------------------------------------------
// Public data classes
// ---------------------------------------------------------------------------

/// A normalized puzzle row (moves are always space separated UCI, the first
/// move being the opponent's setup move, exactly like the Lichess dump).
class SynPuzzleRecord {
  const SynPuzzleRecord({
    required this.id,
    required this.fen,
    required this.moves,
    this.rating = kSynDefaultRating,
    this.themes = kSynDefaultThemes,
    this.solved = false,
  });

  factory SynPuzzleRecord.fromMap(Map<String, Object?> m) => SynPuzzleRecord(
        id: m['id']! as String,
        fen: m['fen']! as String,
        moves: m['moves']! as String,
        rating: (m['rating'] as num?)?.toInt() ?? kSynDefaultRating,
        themes: (m['themes'] as String?) ?? kSynDefaultThemes,
        solved: ((m['solved'] as num?)?.toInt() ?? 0) != 0,
      );

  final String id;
  final String fen;
  final String moves;
  final int rating;
  final String themes;
  final bool solved;

  List<String> get moveList => moves.split(' ');
  List<String> get themeList => themes.split(' ').where((t) => t.isNotEmpty).toList();

  Map<String, Object?> toMap() => <String, Object?>{
        'id': id,
        'fen': fen,
        'moves': moves,
        'rating': rating,
        'themes': themes,
        'solved': solved ? 1 : 0,
      };

  @override
  bool operator ==(Object other) => other is SynPuzzleRecord && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'SynPuzzleRecord($id, $rating, $themes, $moves)';
}

class SynImportOptions {
  const SynImportOptions({
    this.batchSize = kSynImportBatchSize,
    this.firstMovePolicy = SynFirstMovePolicy.auto,
    this.defaultRating = kSynDefaultRating,
    this.defaultThemes = kSynDefaultThemes,
    this.maxRecords,
    this.maxRecordedErrors = 50,
    this.synthesizeSetupMove = true,
    this.validateUciMoves = true,
    this.progressEveryRecords = 1000,
  });

  final int batchSize;
  final SynFirstMovePolicy firstMovePolicy;
  final int defaultRating;
  final String defaultThemes;
  final int? maxRecords;
  final int maxRecordedErrors;

  /// Player-first data is converted to Lichess format by retracting one legal
  /// opponent move from the puzzle position. Disable to skip such puzzles.
  final bool synthesizeSetupMove;

  /// When false and the source is already known-good Lichess UCI, rows are
  /// passed through without replaying them on a dartchess board (much faster
  /// for multi-million row dumps).
  final bool validateUciMoves;
  final int progressEveryRecords;
}

class SynImportProgress {
  const SynImportProgress({
    required this.phase,
    this.recordsParsed = 0,
    this.recordsInserted = 0,
    this.recordsSkipped = 0,
    this.duplicates = 0,
    this.bytesRead = 0,
    this.totalBytes = 0,
    this.totalRecords,
    this.message = '',
    this.result,
  });

  final SynImportPhase phase;
  final int recordsParsed;
  final int recordsInserted;
  final int recordsSkipped;
  final int duplicates;
  final int bytesRead;
  final int totalBytes;
  final int? totalRecords;
  final String message;

  /// Set on the terminal event (finished / cancelled / failed).
  final SynImportResult? result;

  bool get isTerminal =>
      phase == SynImportPhase.finished ||
      phase == SynImportPhase.cancelled ||
      phase == SynImportPhase.failed;

  /// 0..1 when computable, else null (indeterminate).
  double? get fraction {
    if (phase == SynImportPhase.finished) return 1;
    if (totalBytes > 0) return (bytesRead / totalBytes).clamp(0.0, 1.0).toDouble();
    final t = totalRecords;
    if (t != null && t > 0) return (recordsParsed / t).clamp(0.0, 1.0).toDouble();
    return null;
  }

  @override
  String toString() =>
      'SynImportProgress($phase parsed=$recordsParsed inserted=$recordsInserted '
      'skipped=$recordsSkipped dup=$duplicates ${message.isEmpty ? '' : message})';
}

class SynImportResult {
  const SynImportResult({
    required this.sourcePath,
    required this.format,
    required this.mode,
    this.recordsParsed = 0,
    this.recordsInserted = 0,
    this.recordsSkipped = 0,
    this.duplicates = 0,
    this.convertedFromSan = 0,
    this.convertedFromPlayerFirst = 0,
    this.elapsed = Duration.zero,
    this.errors = const <String>[],
    this.cancelled = false,
    this.failureMessage,
  });

  final String sourcePath;
  final SynPuzzleFormat format;
  final SynImportMode mode;
  final int recordsParsed;
  final int recordsInserted;
  final int recordsSkipped;
  final int duplicates;
  final int convertedFromSan;
  final int convertedFromPlayerFirst;
  final Duration elapsed;
  final List<String> errors;
  final bool cancelled;
  final String? failureMessage;

  bool get success => failureMessage == null && !cancelled;

  @override
  String toString() =>
      'SynImportResult(${success ? 'ok' : (cancelled ? 'cancelled' : 'failed: $failureMessage')}, '
      'format=${format.name}, parsed=$recordsParsed, inserted=$recordsInserted, '
      'dup=$duplicates, skipped=$recordsSkipped, san=$convertedFromSan, '
      'pf=$convertedFromPlayerFirst, ${elapsed.inMilliseconds}ms)';
}

/// Cooperative cancellation for [SynPuzzleImporter.importFile].
class SynCancelToken {
  bool _cancelled = false;
  final List<void Function()> _listeners = <void Function()>[];

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final l in List<void Function()>.of(_listeners)) {
      l();
    }
    _listeners.clear();
  }

  void _listen(void Function() cb) {
    if (_cancelled) {
      cb();
    } else {
      _listeners.add(cb);
    }
  }
}

/// A puzzle as parsed from a source, before move normalization.
class SynRawPuzzle {
  const SynRawPuzzle({
    required this.fen,
    required this.moves,
    this.id,
    this.rating,
    this.themes,
    this.conventionHint = SynFirstMovePolicy.auto,
    this.hintIsDefinitive = false,
  });

  final String? id;
  final String fen;
  final List<String> moves;
  final int? rating;
  final String? themes;
  final SynFirstMovePolicy conventionHint;

  /// True when the source format *defines* the convention (EPD `bm`, Lichess
  /// CSV header). False when the hint is only a prior for auto-detection.
  final bool hintIsDefinitive;
}

/// Collects skip statistics while parsing.
class SynParseContext {
  SynParseContext({this.maxErrors = 50});
  final int maxErrors;
  int skipped = 0;
  final List<String> errors = <String>[];

  void skip(String reason) {
    skipped++;
    if (errors.length < maxErrors) errors.add(reason);
  }
}

// ---------------------------------------------------------------------------
// Small shared helpers
// ---------------------------------------------------------------------------

String _q(String ident) => '"${ident.replaceAll('"', '""')}"';

int _asRating(Object? v, int fallback) {
  int? r;
  if (v is num) {
    r = v.round();
  } else if (v is String) {
    final t = v.trim();
    r = int.tryParse(t) ?? double.tryParse(t)?.round();
  }
  if (r == null) return fallback;
  return r < 0 ? 0 : (r > 4500 ? 4500 : r);
}

String _asThemes(Object? v, String fallback) {
  final String s;
  if (v is List) {
    s = v.map((e) => e.toString()).join(' ');
  } else {
    s = v?.toString() ?? '';
  }
  final cleaned = s.replaceAll(RegExp(r'[,;|]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  return cleaned.isEmpty ? fallback : cleaned;
}

class SynIds {
  const SynIds._();

  /// 64-bit FNV-1a, rendered as 16 hex chars.
  static String fnvHex(String s) {
    var h = 0xcbf29ce484222325;
    for (final u in utf8.encode(s)) {
      h ^= u;
      h = h * 0x100000001b3;
    }
    final hi = (h >> 32) & 0xFFFFFFFF;
    final lo = h & 0xFFFFFFFF;
    return hi.toRadixString(16).padLeft(8, '0') + lo.toRadixString(16).padLeft(8, '0');
  }

  static String derive(String fen, String moves) => 'syn_${fnvHex('$fen|$moves').substring(0, 12)}';
}

/// Alias tables for dynamic column / key discovery.
class SynColumnAliases {
  const SynColumnAliases._();

  static const List<String> id = <String>['id', 'puzzle_id', 'puzzleid', 'rowid'];
  static const List<String> fen = <String>['fen', 'position', 'board'];
  static const List<String> moves = <String>['moves', 'solution', 'line', 'uci', 'pv'];
  static const List<String> rating = <String>['rating', 'elo', 'difficulty'];
  static const List<String> themes = <String>['themes', 'tags', 'category', 'motif'];

  static String normKey(String s) => s.toLowerCase().replaceAll(RegExp(r'[\s_\-]'), '');

  /// Returns the original spelling of the first alias (by alias priority)
  /// present in [names], or null.
  static String? pick(Iterable<String> names, List<String> aliases) {
    final byKey = <String, String>{};
    for (final n in names) {
      byKey.putIfAbsent(normKey(n), () => n);
    }
    for (final a in aliases) {
      final hit = byKey[normKey(a)];
      if (hit != null) return hit;
    }
    return null;
  }
}

/// Move-list tokenizer shared by every text parser.
class SynMoveTokens {
  const SynMoveTokens._();

  static const Set<String> _results = <String>{'1-0', '0-1', '1/2-1/2', '*', '½-½'};

  static List<String> tokenize(String s) {
    final out = <String>[];
    for (var t in s.split(RegExp(r'[\s,;]+'))) {
      t = t.trim();
      if (t.isEmpty) continue;
      t = t.replaceFirst(RegExp(r'^\d+\.{1,3}'), '');
      if (t.isEmpty || t == '...' || t == '..') continue;
      if (_results.contains(t) || t.startsWith(r'$')) continue;
      out.add(t);
    }
    return out;
  }

  static List<String> fromObject(Object? o) {
    if (o == null) return const <String>[];
    if (o is List) {
      return <String>[for (final e in o) ...tokenize(e.toString())];
    }
    return tokenize(o.toString());
  }
}

// ---------------------------------------------------------------------------
// FEN grid utilities (own tiny implementation, independent of dartchess API drift)
// ---------------------------------------------------------------------------

class _FenGrid {
  _FenGrid._(this._cells);

  static const String files = 'abcdefgh';
  final List<List<String>> _cells; // _cells[7 - rank][file], '' = empty

  static _FenGrid? parse(String boardField) {
    final rows = boardField.split('/');
    if (rows.length != 8) return null;
    final cells = <List<String>>[];
    for (final row in rows) {
      final out = <String>[];
      for (final ch in row.split('')) {
        final d = int.tryParse(ch);
        if (d != null) {
          if (d < 1 || d > 8) return null;
          for (var i = 0; i < d; i++) {
            out.add('');
          }
        } else if ('prnbqkPRNBQK'.contains(ch)) {
          out.add(ch);
        } else {
          return null;
        }
      }
      if (out.length != 8) return null;
      cells.add(out);
    }
    return _FenGrid._(cells);
  }

  _FenGrid copy() => _FenGrid._(<List<String>>[for (final r in _cells) List<String>.of(r)]);

  String at(int file, int rank) => _cells[7 - rank][file];

  void put(int file, int rank, String piece) => _cells[7 - rank][file] = piece;

  String toBoardField() {
    final rows = <String>[];
    for (final row in _cells) {
      final sb = StringBuffer();
      var empty = 0;
      for (final c in row) {
        if (c.isEmpty) {
          empty++;
        } else {
          if (empty > 0) sb.write(empty);
          empty = 0;
          sb.write(c);
        }
      }
      if (empty > 0) sb.write(empty);
      rows.add(sb.toString());
    }
    return rows.join('/');
  }

  static String square(int file, int rank) => '${files[file]}${rank + 1}';
}

class SynFenTools {
  const SynFenTools._();

  /// Pads a 1..6 field FEN/EPD prefix to a complete 6 field FEN. Null if invalid.
  static String? complete(String fen) {
    final f = fen.trim().split(RegExp(r'\s+'));
    if (f.isEmpty || f.first.isEmpty) return null;
    if (_FenGrid.parse(f[0]) == null) return null;
    final turn = f.length > 1 ? f[1] : 'w';
    if (turn != 'w' && turn != 'b') return null;
    final castling = f.length > 2 ? f[2] : '-';
    final ep = f.length > 3 ? f[3] : '-';
    final half = f.length > 4 && int.tryParse(f[4]) != null ? f[4] : '0';
    final full = f.length > 5 && (int.tryParse(f[5]) ?? 0) > 0 ? f[5] : '1';
    return '${f[0]} $turn $castling $ep $half $full';
  }

  /// White minus black material in pawn units.
  static int materialBalance(String fen) {
    const values = <String, int>{'p': 1, 'n': 3, 'b': 3, 'r': 5, 'q': 9};
    var total = 0;
    for (final ch in fen.split(' ').first.split('')) {
      final v = values[ch.toLowerCase()];
      if (v == null) continue;
      total += ch == ch.toUpperCase() ? v : -v;
    }
    return total;
  }
}

// ---------------------------------------------------------------------------
// 1. Magic-byte header sniffer
// ---------------------------------------------------------------------------

class SynFormatDetection {
  const SynFormatDetection({
    required this.path,
    required this.layers,
    required this.payload,
    required this.extension,
    this.unsupportedReason,
  });

  final String path;

  /// Compression layers, outermost first (gzipStream / zlibStream only).
  final List<SynPuzzleFormat> layers;

  /// Format of the innermost payload.
  final SynPuzzleFormat payload;

  /// Extension with compression suffixes stripped, lower-case, no dot.
  final String extension;
  final String? unsupportedReason;

  bool get isSqlite => payload == SynPuzzleFormat.sqliteDb;

  bool get isSupported =>
      unsupportedReason == null &&
      payload != SynPuzzleFormat.unknown &&
      payload != SynPuzzleFormat.unsupportedCompression;

  /// Outermost visible format (gzip/zlib if wrapped).
  SynPuzzleFormat get outer => layers.isEmpty ? payload : layers.first;

  @override
  String toString() =>
      'SynFormatDetection(${layers.map((l) => l.name).join('>')}${layers.isEmpty ? '' : '>'}${payload.name}'
      '${unsupportedReason == null ? '' : ', $unsupportedReason'})';
}

enum _MagicKind { sqlite, gzip, zlib, unsupported, text }

class _Magic {
  const _Magic(this.kind, [this.reason]);
  final _MagicKind kind;
  final String? reason;
}

class SynFileFormatDetector {
  const SynFileFormatDetector._();

  /// "SQLite format 3\0"
  static const List<int> sqliteMagic = <int>[
    0x53, 0x51, 0x4C, 0x69, 0x74, 0x65, 0x20, 0x66, //
    0x6F, 0x72, 0x6D, 0x61, 0x74, 0x20, 0x33, 0x00,
  ];

  static const int maxLayers = 4;
  static const int textSniffBytes = 64 * 1024;

  static final RegExp _pgnTagRe = RegExp(r'^\[[A-Za-z]\w*\s+"(?:[^"\\]|\\.)*"\s*\]\s*$');
  static final RegExp _fenAtStartRe =
      RegExp(r'^\s*[prnbqkPRNBQK1-8]{1,8}(?:/[prnbqkPRNBQK1-8]{1,8}){7}\s+[wb]\b');
  static final RegExp _fenAnywhereRe =
      RegExp(r'[prnbqkPRNBQK1-8]{1,8}(?:/[prnbqkPRNBQK1-8]{1,8}){7}\s+[wb]\s');
  static final RegExp _epdOpcodeRe = RegExp(r'\s(?:bm|am|pv|id|acd|ce)\s');

  /// Sniffs [path]: reads the first 16 bytes BEFORE trusting the extension,
  /// peels gzip/zlib layers (re-sniffing the inner payload each time), then
  /// classifies text payloads.
  static Future<SynFormatDetection> detect(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      throw FileSystemException('Puzzle source not found', path);
    }
    final ext = effectiveExtension(path);
    final layers = <SynPuzzleFormat>[];

    SynFormatDetection unsupported(String reason, [SynPuzzleFormat f = SynPuzzleFormat.unsupportedCompression]) =>
        SynFormatDetection(
          path: path,
          layers: List<SynPuzzleFormat>.unmodifiable(layers),
          payload: f,
          extension: ext,
          unsupportedReason: reason,
        );

    try {
      for (var depth = 0; depth <= maxLayers; depth++) {
        final Uint8List head =
            depth == 0 ? await _readHeadRaf(file, 16) : await _readHead(openDecoded(path, layers), 16);
        if (head.isEmpty) {
          return unsupported(depth == 0 ? 'File is empty' : 'Compressed payload is empty', SynPuzzleFormat.unknown);
        }
        final magic = classifyMagic(head);
        if (magic.kind == _MagicKind.sqlite) {
          return SynFormatDetection(
            path: path,
            layers: List<SynPuzzleFormat>.unmodifiable(layers),
            payload: SynPuzzleFormat.sqliteDb,
            extension: ext,
          );
        }
        if (magic.kind == _MagicKind.gzip) {
          layers.add(SynPuzzleFormat.gzipStream);
          continue;
        }
        if (magic.kind == _MagicKind.zlib) {
          layers.add(SynPuzzleFormat.zlibStream);
          continue;
        }
        if (magic.kind == _MagicKind.unsupported) {
          return unsupported(magic.reason ?? 'Unsupported container');
        }
        final sample = await _readHead(openDecoded(path, layers), textSniffBytes);
        final text = utf8.decode(sample, allowMalformed: true);
        final payload = classifyText(text, ext);
        return SynFormatDetection(
          path: path,
          layers: List<SynPuzzleFormat>.unmodifiable(layers),
          payload: payload,
          extension: ext,
          unsupportedReason: payload == SynPuzzleFormat.unknown ? 'Could not classify text payload' : null,
        );
      }
      return unsupported('More than $maxLayers nested compression layers', SynPuzzleFormat.unknown);
    } on FormatException catch (e) {
      return unsupported('Corrupt compressed stream: ${e.message}', SynPuzzleFormat.unknown);
    } on FileSystemException catch (e) {
      return unsupported('I/O error while sniffing: ${e.message}', SynPuzzleFormat.unknown);
    }
  }

  /// Opens [path] and pipes it through every layer in [layers].
  static Stream<List<int>> openDecoded(
    String path,
    List<SynPuzzleFormat> layers, {
    void Function(int bytes)? onBytes,
  }) {
    Stream<List<int>> s = File(path).openRead();
    if (onBytes != null) {
      s = s.map((List<int> c) {
        onBytes(c.length);
        return c;
      });
    }
    for (final layer in layers) {
      s = layer == SynPuzzleFormat.gzipStream ? s.transform(gzip.decoder) : s.transform(zlib.decoder);
    }
    return s;
  }

  static _Magic classifyMagic(Uint8List h) {
    bool starts(List<int> m) {
      if (h.length < m.length) return false;
      for (var i = 0; i < m.length; i++) {
        if (h[i] != m[i]) return false;
      }
      return true;
    }

    if (h.length >= 16 && starts(sqliteMagic)) return const _Magic(_MagicKind.sqlite);
    if (starts(const <int>[0x1F, 0x8B])) return const _Magic(_MagicKind.gzip);
    if (h.length >= 2 && h[0] == 0x78 && (h[1] == 0x01 || h[1] == 0x9C || h[1] == 0xDA || h[1] == 0x5E)) {
      if (((h[0] << 8) | h[1]) % 31 == 0) return const _Magic(_MagicKind.zlib);
    }
    if (starts(const <int>[0x28, 0xB5, 0x2F, 0xFD])) {
      return const _Magic(
        _MagicKind.unsupported,
        'Zstandard (.zst) cannot be decoded without extra packages. Run `zstd -d` first, or recompress as .gz.',
      );
    }
    if (starts(const <int>[0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00])) {
      return const _Magic(_MagicKind.unsupported, 'XZ archives are not supported. Recompress as .gz.');
    }
    if (starts(const <int>[0x42, 0x5A, 0x68])) {
      return const _Magic(_MagicKind.unsupported, 'BZip2 archives are not supported. Recompress as .gz.');
    }
    if (starts(const <int>[0x50, 0x4B, 0x03, 0x04])) {
      return const _Magic(_MagicKind.unsupported, 'ZIP archives are not supported. Extract first or use .gz.');
    }
    if (starts(const <int>[0x37, 0x7A, 0xBC, 0xAF])) {
      return const _Magic(_MagicKind.unsupported, '7z archives are not supported. Extract first or use .gz.');
    }
    if (starts(const <int>[0xFF, 0xFE]) || starts(const <int>[0xFE, 0xFF])) {
      return const _Magic(_MagicKind.unsupported, 'UTF-16 text is not supported. Re-save as UTF-8.');
    }
    return const _Magic(_MagicKind.text);
  }

  /// Classifies a decoded text sample. [ext] is lower-case without a dot.
  static SynPuzzleFormat classifyText(String sample, String ext) {
    var text = sample;
    if (text.startsWith('\uFEFF')) text = text.substring(1);
    final lines = <String>[];
    for (final l in const LineSplitter().convert(text)) {
      final t = l.trim();
      if (t.isEmpty) continue;
      lines.add(t);
      if (lines.length >= 40) break;
    }
    if (lines.isEmpty) return SynPuzzleFormat.unknown;

    if (ext == 'pgn' || lines.any(_pgnTagRe.hasMatch)) {
      if (lines.any(_pgnTagRe.hasMatch)) return SynPuzzleFormat.pgnBook;
    }
    final first = lines.first;
    if (first.startsWith('{') || first.startsWith('[')) return SynPuzzleFormat.jsonOrNdjson;

    var epdVotes = 0;
    var csvVotes = 0;
    for (final line in lines) {
      if (line.startsWith('#') || line.startsWith('//')) continue;
      final atStart = _fenAtStartRe.hasMatch(line);
      final delim = line.contains(',') || line.contains('\t');
      if (atStart) {
        if (line.contains('|') || line.contains(';') || _epdOpcodeRe.hasMatch(line)) {
          epdVotes += 2;
        } else if (delim) {
          csvVotes++;
        } else {
          epdVotes++;
        }
      } else if (_fenAnywhereRe.hasMatch(line) && delim) {
        csvVotes += 2;
      }
    }
    final head = first.toLowerCase();
    if (!head.contains('/') && head.contains('fen') && RegExp(r'[,\t;]').hasMatch(head)) csvVotes += 3;
    if (csvVotes > epdVotes) return SynPuzzleFormat.csvOrTsv;
    if (epdVotes > 0) return SynPuzzleFormat.epdOrFen;

    switch (ext) {
      case 'csv':
      case 'tsv':
        return SynPuzzleFormat.csvOrTsv;
      case 'json':
      case 'jsonl':
      case 'ndjson':
      case 'synpuz':
      case 'synpack':
        return SynPuzzleFormat.jsonOrNdjson;
      case 'pgn':
        return SynPuzzleFormat.pgnBook;
      case 'epd':
      case 'fen':
      case 'txt':
        return SynPuzzleFormat.epdOrFen;
    }
    return SynPuzzleFormat.unknown;
  }

  static String effectiveExtension(String path) {
    var name = p.basename(path).toLowerCase();
    const wrappers = <String>['.gz', '.gzip', '.zlib', '.zz', '.z'];
    var changed = true;
    while (changed) {
      changed = false;
      for (final w in wrappers) {
        if (name.endsWith(w) && name.length > w.length) {
          name = name.substring(0, name.length - w.length);
          changed = true;
        }
      }
    }
    final e = p.extension(name);
    return e.isEmpty ? '' : e.substring(1);
  }

  static Future<Uint8List> _readHeadRaf(File file, int n) async {
    final raf = await file.open();
    try {
      return await raf.read(n);
    } finally {
      await raf.close();
    }
  }

  static Future<Uint8List> _readHead(Stream<List<int>> s, int n) async {
    final b = BytesBuilder();
    await for (final chunk in s) {
      b.add(chunk);
      if (b.length >= n) break;
    }
    final all = b.takeBytes();
    return all.length > n ? Uint8List.sublistView(all, 0, n) : all;
  }
}

// ---------------------------------------------------------------------------
// 2. Dynamic SQLite schema introspection
// ---------------------------------------------------------------------------

class SynSqliteSchema {
  const SynSqliteSchema({
    required this.tableName,
    required this.fenColumn,
    required this.movesColumn,
    this.idColumn,
    this.ratingColumn,
    this.themesColumn,
    this.hasRowId = true,
    this.rowCount = 0,
  });

  factory SynSqliteSchema.fromJson(Map<String, Object?> j) => SynSqliteSchema(
        tableName: j['table']! as String,
        fenColumn: j['fen']! as String,
        movesColumn: j['moves']! as String,
        idColumn: j['id'] as String?,
        ratingColumn: j['rating'] as String?,
        themesColumn: j['themes'] as String?,
        hasRowId: (j['hasRowId'] as bool?) ?? true,
        rowCount: (j['rowCount'] as num?)?.toInt() ?? 0,
      );

  final String tableName;
  final String fenColumn;
  final String movesColumn;

  /// Null when no real id column exists (ids are then derived from content).
  final String? idColumn;
  final String? ratingColumn;
  final String? themesColumn;
  final bool hasRowId;
  final int rowCount;

  Map<String, Object?> toJson() => <String, Object?>{
        'table': tableName,
        'fen': fenColumn,
        'moves': movesColumn,
        'id': idColumn,
        'rating': ratingColumn,
        'themes': themesColumn,
        'hasRowId': hasRowId,
        'rowCount': rowCount,
      };

  /// SELECT list with stable aliases (__rid, __id, __fen, __moves, __rating, __themes).
  String selectList() {
    String col(String? c) => c == null ? 'NULL' : _q(c);
    return '${hasRowId ? 'rowid AS __rid, ' : ''}'
        '${col(idColumn)} AS __id, ${_q(fenColumn)} AS __fen, ${_q(movesColumn)} AS __moves, '
        '${col(ratingColumn)} AS __rating, ${col(themesColumn)} AS __themes';
  }

  @override
  String toString() => 'SynSqliteSchema($tableName fen=$fenColumn moves=$movesColumn id=$idColumn '
      'rating=$ratingColumn themes=$themesColumn rows=$rowCount rowid=$hasRowId)';
}

class SynSqliteIntrospector {
  const SynSqliteIntrospector._();

  static Future<List<String>> listTables(DatabaseExecutor db) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
    );
    return <String>[for (final r in rows) r['name']! as String];
  }

  /// Scans every user table, auto-maps columns through [SynColumnAliases] and
  /// returns the best candidate (largest row count). Null if no table has both
  /// a FEN-like and a moves-like column. Never hardcodes a table name.
  static Future<SynSqliteSchema?> discover(DatabaseExecutor db, {String? preferredTable}) async {
    SynSqliteSchema? best;
    for (final table in await listTables(db)) {
      if (preferredTable != null && table != preferredTable) continue;
      final info = await db.rawQuery('PRAGMA table_info(${_q(table)})');
      final names = <String>[for (final r in info) r['name']! as String];
      final fen = SynColumnAliases.pick(names, SynColumnAliases.fen);
      final moves = SynColumnAliases.pick(names, SynColumnAliases.moves);
      if (fen == null || moves == null || fen == moves) continue;

      // 'rowid' in the alias list is a pseudo column, never a real id here.
      var id = SynColumnAliases.pick(names, SynColumnAliases.id);
      if (id != null && SynColumnAliases.normKey(id) == 'rowid' && !names.contains(id)) id = null;
      final rating = SynColumnAliases.pick(names, SynColumnAliases.rating);
      final themes = SynColumnAliases.pick(names, SynColumnAliases.themes);

      var hasRowId = true;
      try {
        await db.rawQuery('SELECT rowid FROM ${_q(table)} LIMIT 1');
      } on DatabaseException {
        hasRowId = false; // WITHOUT ROWID table
      }
      final count = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM ${_q(table)}')) ?? 0;
      final candidate = SynSqliteSchema(
        tableName: table,
        fenColumn: fen,
        movesColumn: moves,
        idColumn: id,
        ratingColumn: rating,
        themesColumn: themes,
        hasRowId: hasRowId,
        rowCount: count,
      );
      if (best == null || candidate.rowCount > best.rowCount) best = candidate;
    }
    return best;
  }
}

// ---------------------------------------------------------------------------
// 3. Streaming parsers
// ---------------------------------------------------------------------------

class SynParsers {
  const SynParsers._();

  static final RegExp _fenCellRe =
      RegExp(r'^\s*[prnbqkPRNBQK1-8]{1,8}(?:/[prnbqkPRNBQK1-8]{1,8}){7}(?:\s|$)');
  static final RegExp _pgnTagRe = RegExp(r'^\[([A-Za-z]\w*)\s+"((?:[^"\\]|\\.)*)"\s*\]\s*$');
  static final RegExp _epdRe = RegExp(r'^(\S+)\s+([wb])\s+(\S+)\s+(\S+)\s*(.*)$');

  static Stream<SynRawPuzzle> parse(
    SynPuzzleFormat format,
    Stream<List<int>> bytes,
    SynParseContext ctx,
    String extension,
  ) {
    switch (format) {
      case SynPuzzleFormat.csvOrTsv:
        return parseCsv(bytes, ctx, extension);
      case SynPuzzleFormat.jsonOrNdjson:
        return parseJson(bytes, ctx);
      case SynPuzzleFormat.pgnBook:
        return parsePgn(bytes, ctx);
      case SynPuzzleFormat.epdOrFen:
        return parseEpdOrFen(bytes, ctx);
      default:
        throw SynImportException('No text parser for ${format.name}');
    }
  }

  static Stream<String> _lines(Stream<List<int>> bytes) =>
      bytes.transform(const Utf8Decoder(allowMalformed: true)).transform(const LineSplitter());

  static (SynFirstMovePolicy, bool) _hintFromString(String? s) {
    if (s == null) return (SynFirstMovePolicy.auto, false);
    final l = s.toLowerCase();
    if (l.contains('player')) return (SynFirstMovePolicy.playerFirst, true);
    if (l.contains('lichess') || l.contains('standard') || l.contains('opponent')) {
      return (SynFirstMovePolicy.opponentSetupFirst, true);
    }
    return (SynFirstMovePolicy.auto, false);
  }

  // ----- CSV / TSV --------------------------------------------------------

  static List<String> splitDelimited(String line, String delimiter) {
    final out = <String>[];
    final cur = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final c = line[i];
      if (inQuotes) {
        if (c == '"') {
          if (i + 1 < line.length && line[i + 1] == '"') {
            cur.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          cur.write(c);
        }
      } else if (c == '"' && cur.isEmpty) {
        inQuotes = true;
      } else if (c == delimiter) {
        out.add(cur.toString());
        cur.clear();
      } else {
        cur.write(c);
      }
    }
    out.add(cur.toString());
    return out;
  }

  static String _guessDelimiter(String line, String ext) {
    if (ext == 'tsv') return '\t';
    var best = ',';
    var bestCount = -1;
    for (final d in const <String>[',', '\t', ';']) {
      final n = d.allMatches(line).length;
      if (n > bestCount) {
        best = d;
        bestCount = n;
      }
    }
    return best;
  }

  static Stream<SynRawPuzzle> parseCsv(Stream<List<int>> bytes, SynParseContext ctx, String ext) async* {
    String? delimiter;
    _CsvColumns? cols;
    var first = true;
    await for (final raw in _lines(bytes)) {
      var line = raw;
      if (first) {
        first = false;
        if (line.startsWith('\uFEFF')) line = line.substring(1);
      }
      if (line.trim().isEmpty || line.startsWith('#')) continue;
      delimiter ??= _guessDelimiter(line, ext);
      final cells = splitDelimited(line, delimiter);
      if (cols == null) {
        final header = _CsvColumns.fromHeader(cells);
        if (header != null) {
          cols = header;
          continue;
        }
        cols = _CsvColumns.positional(cells);
        if (cols == null) {
          ctx.skip('CSV: first row has neither a header nor a FEN cell');
          continue;
        }
      }
      final c = cols;
      final need = c.fen > c.moves ? c.fen : c.moves;
      if (cells.length <= need) {
        ctx.skip('CSV: short row (${cells.length} cells)');
        continue;
      }
      final fen = cells[c.fen].trim();
      final moves = SynMoveTokens.tokenize(cells[c.moves]);
      if (fen.isEmpty || moves.isEmpty) {
        ctx.skip('CSV: empty FEN or moves');
        continue;
      }
      String? at(int? i) => (i != null && i < cells.length) ? cells[i].trim() : null;
      yield SynRawPuzzle(
        id: at(c.id),
        fen: fen,
        moves: moves,
        rating: c.rating == null ? null : _asRating(at(c.rating), -1) < 0 ? null : _asRating(at(c.rating), 0),
        themes: at(c.themes),
        conventionHint: c.lichessHeader ? SynFirstMovePolicy.opponentSetupFirst : SynFirstMovePolicy.auto,
        hintIsDefinitive: c.lichessHeader,
      );
    }
  }

  // ----- JSON / NDJSON / .synpuz / .synpack ------------------------------

  /// Incrementally splits a JSON text into top-level values without ever
  /// holding more than one element in memory:
  ///  * `[ {...}, {...} ]`  -> each element of the top-level array
  ///  * `{...}\n{...}`      -> each top-level object (NDJSON / JSONL / wrapper)
  static Stream<String> splitJsonElements(Stream<String> chunks) async* {
    final buf = StringBuffer();
    var depth = 0;
    var inString = false;
    var escape = false;
    var inArray = false;
    var collecting = false;
    await for (final chunk in chunks) {
      for (var i = 0; i < chunk.length; i++) {
        final c = chunk.codeUnitAt(i);
        if (inString) {
          if (collecting) buf.writeCharCode(c);
          if (escape) {
            escape = false;
          } else if (c == 0x5C) {
            escape = true;
          } else if (c == 0x22) {
            inString = false;
          }
          continue;
        }
        if (c == 0x22) {
          inString = true;
          if (collecting) buf.writeCharCode(c);
          continue;
        }
        if (c == 0x7B || c == 0x5B) {
          // '{' or '['
          if (!inArray && !collecting && depth == 0 && c == 0x5B) {
            inArray = true;
            depth = 1;
            continue;
          }
          if (!collecting) {
            collecting = true;
            buf.clear();
          }
          buf.writeCharCode(c);
          depth++;
          continue;
        }
        if (c == 0x7D || c == 0x5D) {
          // '}' or ']'
          if (collecting) {
            buf.writeCharCode(c);
            depth--;
            if (depth == (inArray ? 1 : 0)) {
              yield buf.toString();
              buf.clear();
              collecting = false;
            }
          } else if (inArray && c == 0x5D && depth == 1) {
            depth = 0;
            inArray = false;
          }
          continue;
        }
        if (collecting) buf.writeCharCode(c);
      }
    }
  }

  static Stream<SynRawPuzzle> parseJson(Stream<List<int>> bytes, SynParseContext ctx) async* {
    final chunks = bytes.transform(const Utf8Decoder(allowMalformed: true));
    await for (final element in splitJsonElements(chunks)) {
      final Object? decoded;
      try {
        decoded = jsonDecode(element);
      } on FormatException catch (e) {
        ctx.skip('JSON: ${e.message}');
        continue;
      }
      yield* Stream<SynRawPuzzle>.fromIterable(_rawFromJson(decoded, ctx));
    }
  }

  static Iterable<SynRawPuzzle> _rawFromJson(Object? v, SynParseContext ctx) sync* {
    if (v is Map) {
      final keys = <String>[for (final k in v.keys) k.toString()];
      final fenKey = SynColumnAliases.pick(keys, SynColumnAliases.fen);
      if (fenKey != null) {
        final raw = _rawFromMap(v, keys, fenKey, ctx);
        if (raw != null) yield raw;
        return;
      }
      var found = false;
      for (final k in keys) {
        if (const <String>['puzzles', 'data', 'items', 'records', 'rows', 'results'].contains(k.toLowerCase())) {
          final inner = v[k];
          if (inner is List) {
            found = true;
            for (final e in inner) {
              yield* _rawFromJson(e, ctx);
            }
          }
        }
      }
      if (!found) ctx.skip('JSON: object without a FEN field');
    } else if (v is List) {
      final cells = <String>[for (final e in v) e is List ? '' : (e?.toString() ?? '')];
      final fenIdx = cells.indexWhere(_fenCellRe.hasMatch);
      if (fenIdx < 0 || fenIdx + 1 >= v.length) {
        ctx.skip('JSON: array without FEN + moves');
        return;
      }
      final moves = SynMoveTokens.fromObject(v[fenIdx + 1]);
      if (moves.isEmpty) {
        ctx.skip('JSON: array with empty moves');
        return;
      }
      yield SynRawPuzzle(
        id: fenIdx > 0 ? cells[fenIdx - 1] : null,
        fen: cells[fenIdx],
        moves: moves,
        rating: fenIdx + 2 < v.length && _asRating(v[fenIdx + 2], -1) >= 0 ? _asRating(v[fenIdx + 2], 0) : null,
        themes: fenIdx + 3 < v.length ? _asThemes(v[fenIdx + 3], '') : null,
      );
    } else {
      ctx.skip('JSON: unsupported top-level value');
    }
  }

  static SynRawPuzzle? _rawFromMap(Map v, List<String> keys, String fenKey, SynParseContext ctx) {
    final movesKey = SynColumnAliases.pick(keys, SynColumnAliases.moves);
    if (movesKey == null) {
      ctx.skip('JSON: record without moves');
      return null;
    }
    final moves = SynMoveTokens.fromObject(v[movesKey]);
    final fen = v[fenKey]?.toString().trim() ?? '';
    if (fen.isEmpty || moves.isEmpty) {
      ctx.skip('JSON: empty FEN or moves');
      return null;
    }
    final idKey = SynColumnAliases.pick(keys, SynColumnAliases.id);
    final ratingKey = SynColumnAliases.pick(keys, SynColumnAliases.rating);
    final themesKey = SynColumnAliases.pick(keys, SynColumnAliases.themes);
    final convKey = SynColumnAliases.pick(keys, const <String>['convention', 'firstMovePolicy']);
    final hint = _hintFromString(convKey == null ? null : v[convKey]?.toString());
    final rawRating = ratingKey == null ? null : v[ratingKey];
    return SynRawPuzzle(
      id: idKey == null ? null : v[idKey]?.toString(),
      fen: fen,
      moves: moves,
      rating: rawRating != null && _asRating(rawRating, -1) >= 0 ? _asRating(rawRating, 0) : null,
      themes: themesKey == null ? null : _asThemes(v[themesKey], ''),
      conventionHint: hint.$1,
      hintIsDefinitive: hint.$2,
    );
  }

  // ----- PGN ---------------------------------------------------------------

  /// Removes {comments}, ;line comments, (variations) from raw movetext.
  static String stripPgnMovetext(String text) {
    final out = StringBuffer();
    var inBrace = false;
    var inLine = false;
    var paren = 0;
    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (inLine) {
        if (c == '\n') {
          inLine = false;
          out.write(' ');
        }
        continue;
      }
      if (inBrace) {
        if (c == '}') {
          inBrace = false;
          out.write(' ');
        }
        continue;
      }
      if (c == '{') {
        inBrace = true;
        continue;
      }
      if (c == ';') {
        inLine = true;
        continue;
      }
      if (c == '(') {
        paren++;
        continue;
      }
      if (c == ')') {
        if (paren > 0) paren--;
        out.write(' ');
        continue;
      }
      if (paren > 0) continue;
      out.write(c);
    }
    return out.toString();
  }

  static Stream<SynRawPuzzle> parsePgn(Stream<List<int>> bytes, SynParseContext ctx) async* {
    var headers = <String, String>{};
    final moveBuf = StringBuffer();
    var inMoves = false;
    var first = true;

    SynRawPuzzle? flush() {
      final h = headers;
      final text = moveBuf.toString();
      headers = <String, String>{};
      moveBuf.clear();
      inMoves = false;
      if (h.isEmpty && text.trim().isEmpty) return null;
      final fen = h['FEN'];
      if (fen == null || fen.trim().isEmpty) {
        ctx.skip('PGN: game without [FEN] header');
        return null;
      }
      final moves = SynMoveTokens.tokenize(stripPgnMovetext(text));
      if (moves.isEmpty) {
        ctx.skip('PGN: no mainline moves');
        return null;
      }
      String? tag(List<String> names) {
        for (final n in names) {
          final v = h[n];
          if (v != null && v.trim().isNotEmpty) return v.trim();
        }
        return null;
      }

      final rating = tag(const <String>['PuzzleRating', 'Rating', 'Elo', 'Difficulty']);
      final hint = _hintFromString(tag(const <String>['Convention']));
      return SynRawPuzzle(
        id: tag(const <String>['PuzzleId', 'PuzzleID', 'Id', 'ID']),
        fen: fen.trim(),
        moves: moves,
        rating: rating != null && _asRating(rating, -1) >= 0 ? _asRating(rating, 0) : null,
        themes: tag(const <String>['Themes', 'Theme', 'Motif', 'Tags']),
        conventionHint: hint.$2 ? hint.$1 : SynFirstMovePolicy.playerFirst,
        hintIsDefinitive: hint.$2,
      );
    }

    await for (final raw in _lines(bytes)) {
      var line = raw;
      if (first) {
        first = false;
        if (line.startsWith('\uFEFF')) line = line.substring(1);
      }
      if (line.startsWith('%')) continue;
      final m = _pgnTagRe.firstMatch(line.trim());
      if (m != null) {
        if (inMoves) {
          final r = flush();
          if (r != null) yield r;
        }
        headers[m[1]!] = m[2]!.replaceAll(r'\"', '"').replaceAll(r'\\', r'\');
        continue;
      }
      if (line.trim().isEmpty) continue;
      inMoves = true;
      moveBuf.writeln(line);
    }
    final last = flush();
    if (last != null) yield last;
  }

  // ----- EPD / FEN | moves -------------------------------------------------

  static String _unquote(String s) {
    final t = s.trim();
    if (t.length >= 2 && t.startsWith('"') && t.endsWith('"')) return t.substring(1, t.length - 1);
    return t;
  }

  static Map<String, String> _parseEpdOps(String rest) {
    final ops = <String, String>{};
    final cur = StringBuffer();
    var inQuotes = false;
    void commit() {
      final s = cur.toString().trim();
      cur.clear();
      if (s.isEmpty) return;
      final sp = s.indexOf(RegExp(r'\s'));
      final op = (sp < 0 ? s : s.substring(0, sp)).toLowerCase();
      final arg = sp < 0 ? '' : s.substring(sp + 1).trim();
      ops.putIfAbsent(op, () => arg);
    }

    for (final ch in rest.split('')) {
      if (ch == '"') {
        inQuotes = !inQuotes;
        cur.write(ch);
      } else if (ch == ';' && !inQuotes) {
        commit();
      } else {
        cur.write(ch);
      }
    }
    commit();
    return ops;
  }

  static Stream<SynRawPuzzle> parseEpdOrFen(Stream<List<int>> bytes, SynParseContext ctx) async* {
    var first = true;
    await for (final rawLine in _lines(bytes)) {
      var line = rawLine;
      if (first) {
        first = false;
        if (line.startsWith('\uFEFF')) line = line.substring(1);
      }
      final t = line.trim();
      if (t.isEmpty || t.startsWith('#') || t.startsWith('//')) continue;

      if (t.contains('|')) {
        // FEN | moves | rating | themes | id
        final cells = t.split('|').map((c) => c.trim()).toList();
        if (cells.length < 2 || !_fenCellRe.hasMatch(cells[0])) {
          ctx.skip('FEN list: malformed line');
          continue;
        }
        final moves = SynMoveTokens.tokenize(cells[1]);
        if (moves.isEmpty) {
          ctx.skip('FEN list: no moves');
          continue;
        }
        yield SynRawPuzzle(
          id: cells.length > 4 && cells[4].isNotEmpty ? cells[4] : null,
          fen: cells[0],
          moves: moves,
          rating: cells.length > 2 && _asRating(cells[2], -1) >= 0 ? _asRating(cells[2], 0) : null,
          themes: cells.length > 3 && cells[3].isNotEmpty ? cells[3] : null,
        );
        continue;
      }

      final m = _epdRe.firstMatch(t);
      if (m == null || !_fenCellRe.hasMatch(t)) {
        ctx.skip('EPD: malformed line');
        continue;
      }
      final ops = _parseEpdOps(m[5] ?? '');
      final pv = ops['pv'];
      final bm = ops['bm'];
      final String movesText;
      if (pv != null && pv.isNotEmpty) {
        movesText = pv;
      } else if (bm != null && bm.isNotEmpty) {
        movesText = bm.split(RegExp(r'\s+')).first; // first best move
      } else {
        ctx.skip('EPD: no bm/pv opcode');
        continue;
      }
      final moves = SynMoveTokens.tokenize(movesText);
      if (moves.isEmpty) {
        ctx.skip('EPD: empty move list');
        continue;
      }
      final fen = '${m[1]} ${m[2]} ${m[3]} ${m[4]} ${ops['hmvc'] ?? '0'} ${ops['fmvn'] ?? '1'}';
      final ratingText = ops['rating'] ?? ops['elo'];
      final themeText = ops['themes'] ?? ops['theme'] ?? ops['ct'];
      final idText = ops['id'];
      yield SynRawPuzzle(
        id: idText == null ? null : _unquote(idText),
        fen: fen,
        moves: moves,
        rating: ratingText != null && _asRating(ratingText, -1) >= 0 ? _asRating(ratingText, 0) : null,
        themes: themeText == null ? null : _unquote(themeText),
        // EPD bm/pv always starts with the side to move: the player.
        conventionHint: SynFirstMovePolicy.playerFirst,
        hintIsDefinitive: true,
      );
    }
  }
}

class _CsvColumns {
  const _CsvColumns({
    required this.fen,
    required this.moves,
    this.id,
    this.rating,
    this.themes,
    this.lichessHeader = false,
  });

  final int fen;
  final int moves;
  final int? id;
  final int? rating;
  final int? themes;
  final bool lichessHeader;

  static _CsvColumns? fromHeader(List<String> cells) {
    final names = <String>[for (final c in cells) c.trim()];
    if (names.any(SynParsers._fenCellRe.hasMatch)) return null; // data row, not a header
    final fenName = SynColumnAliases.pick(names, SynColumnAliases.fen);
    final movesName = SynColumnAliases.pick(names, SynColumnAliases.moves);
    if (fenName == null || movesName == null) return null;
    int? idx(String? n) => n == null ? null : names.indexOf(n);
    final keys = names.map(SynColumnAliases.normKey).toSet();
    return _CsvColumns(
      fen: names.indexOf(fenName),
      moves: names.indexOf(movesName),
      id: idx(SynColumnAliases.pick(names, SynColumnAliases.id)),
      rating: idx(SynColumnAliases.pick(names, SynColumnAliases.rating)),
      themes: idx(SynColumnAliases.pick(names, SynColumnAliases.themes)),
      lichessHeader: keys.containsAll(const <String>['puzzleid', 'fen', 'moves']),
    );
  }

  static _CsvColumns? positional(List<String> cells) {
    final i = cells.indexWhere(SynParsers._fenCellRe.hasMatch);
    if (i < 0 || i + 1 >= cells.length) return null;
    final lichessShape = i == 1 && cells.length >= 8; // PuzzleId,FEN,Moves,Rating,RD,Pop,Plays,Themes,...
    return _CsvColumns(
      fen: i,
      moves: i + 1,
      id: i > 0 ? 0 : null,
      rating: i + 2 < cells.length ? i + 2 : null,
      themes: lichessShape ? 7 : (i + 3 < cells.length ? i + 3 : null),
    );
  }
}

// ---------------------------------------------------------------------------
// 4. SAN -> UCI normalizer + move-convention handling (dartchess)
// ---------------------------------------------------------------------------

class SynNormalizedPuzzle {
  const SynNormalizedPuzzle({
    required this.fen,
    required this.uciMoves,
    this.convertedFromSan = false,
    this.convertedFromPlayerFirst = false,
    this.note,
  });

  /// FEN of the position BEFORE the opponent's setup move (Lichess format).
  final String fen;

  /// Space separated UCI, first move = opponent setup move.
  final String uciMoves;
  final bool convertedFromSan;
  final bool convertedFromPlayerFirst;
  final String? note;
}

class _PlayedLine {
  _PlayedLine(this.start, this.positions, this.uci, this.sanInput);
  final Position start;

  /// positions[i] is the position after move i.
  final List<Position> positions;
  final List<String> uci;
  final bool sanInput;
  Position get end => positions.last;
}

class SynMoveNormalizer {
  const SynMoveNormalizer._();

  static final RegExp _uciRe = RegExp(r'^[a-hA-H][1-8][a-hA-H][1-8][qrbnQRBN]?$');

  static bool looksLikeUci(String token) => _uciRe.hasMatch(token);

  /// Convenience: SAN (or UCI) move list from [fen] to canonical UCI list.
  static List<String> sanToUci(String fen, List<String> moves) {
    final full = SynFenTools.complete(fen);
    if (full == null) throw SynNormalizeException('Invalid FEN: "$fen"');
    return _playLine(full, moves).uci;
  }

  /// Normalizes a puzzle to Lichess format:
  ///  * SAN/UCI mix -> UCI
  ///  * player-first -> opponent-setup-first (by retracting a legal opponent move)
  static SynNormalizedPuzzle normalize({
    required String fen,
    required List<String> moves,
    SynFirstMovePolicy policy = SynFirstMovePolicy.auto,
    SynFirstMovePolicy prior = SynFirstMovePolicy.auto,
    bool synthesizeSetupMove = true,
    bool skipValidation = false,
  }) {
    final full = SynFenTools.complete(fen);
    if (full == null) throw SynNormalizeException('Invalid FEN: "$fen"');
    final tokens = <String>[for (final m in moves) _cleanToken(m)]..removeWhere((t) => t.isEmpty);
    if (tokens.isEmpty) throw const SynNormalizeException('Empty move list');

    if (skipValidation && policy == SynFirstMovePolicy.opponentSetupFirst && tokens.every(_uciRe.hasMatch)) {
      if (tokens.length < 2) throw const SynNormalizeException('Needs a setup move and a solution move');
      return SynNormalizedPuzzle(fen: full, uciMoves: tokens.map((t) => t.toLowerCase()).join(' '));
    }

    final line = _playLine(full, tokens);
    var effective = policy;
    String? note;
    if (effective == SynFirstMovePolicy.auto) {
      final verdict = _detectConvention(line, prior);
      effective = verdict.policy;
      note = verdict.reason;
    }

    if (effective == SynFirstMovePolicy.opponentSetupFirst) {
      if (line.uci.length < 2) {
        throw const SynNormalizeException('Opponent-first line needs at least 2 moves');
      }
      return SynNormalizedPuzzle(
        fen: full,
        uciMoves: line.uci.join(' '),
        convertedFromSan: line.sanInput,
        note: note,
      );
    }

    if (!synthesizeSetupMove) {
      throw const SynNormalizeException('Player-first puzzle and setup-move synthesis is disabled');
    }
    final synth = _SetupSynthesizer.synthesize(full);
    if (synth == null) {
      throw const SynNormalizeException('Could not synthesize an opponent setup move for this position');
    }
    return SynNormalizedPuzzle(
      fen: synth.fen,
      uciMoves: '${synth.uci} ${line.uci.join(' ')}',
      convertedFromSan: line.sanInput,
      convertedFromPlayerFirst: true,
      note: note,
    );
  }

  static String _cleanToken(String t) {
    var s = t.trim();
    s = s.replaceFirst(RegExp(r'^\d+\.+'), '');
    s = s.replaceAll(RegExp(r'[!?]+$'), '');
    s = s.replaceAll('e.p.', '').replaceAll('×', 'x');
    s = s.replaceAll('0-0-0', 'O-O-O').replaceAll('0-0', 'O-O');
    return s.trim();
  }

  static Position _startPosition(String fen) {
    try {
      return Chess.fromSetup(Setup.parseFen(fen));
    } catch (e) {
      throw SynNormalizeException('Illegal start position "$fen": $e');
    }
  }

  static _PlayedLine _playLine(String fen, List<String> rawTokens) {
    final start = _startPosition(fen);
    var pos = start;
    final positions = <Position>[];
    final uci = <String>[];
    var sanInput = false;
    for (var i = 0; i < rawTokens.length; i++) {
      final tok = _cleanToken(rawTokens[i]);
      if (tok.isEmpty) continue;
      Move? move;
      if (_uciRe.hasMatch(tok)) {
        move = Move.parse(_toEngineUci(pos, tok.toLowerCase()));
      } else {
        sanInput = true;
        move = pos.parseSan(tok);
      }
      if (move == null || !pos.isLegal(move)) {
        throw SynNormalizeException('Illegal or unparseable move "$tok" at ply ${i + 1}');
      }
      uci.add(_toStandardUci(pos, move.uci));
      pos = pos.play(move);
      positions.add(pos);
    }
    if (uci.isEmpty) throw const SynNormalizeException('No playable moves');
    return _PlayedLine(start, positions, uci, sanInput);
  }

  /// Standard UCI castling (e1g1) -> dartchess king-takes-rook (e1h1).
  static String _toEngineUci(Position pos, String uci) {
    if (uci.length != 4) return uci;
    final grid = _FenGrid.parse(pos.fen.split(' ').first);
    if (grid == null) return uci;
    final ff = _FenGrid.files.indexOf(uci[0]);
    final fr = int.parse(uci[1]) - 1;
    final tf = _FenGrid.files.indexOf(uci[2]);
    final tr = int.parse(uci[3]) - 1;
    final piece = grid.at(ff, fr);
    if ((piece == 'K' || piece == 'k') && fr == tr && (tf - ff).abs() == 2) {
      return '${uci.substring(0, 2)}${_FenGrid.square(tf > ff ? 7 : 0, fr)}';
    }
    return uci;
  }

  /// dartchess king-takes-rook (e1h1) -> standard UCI castling (e1g1).
  static String _toStandardUci(Position posBefore, String uci) {
    if (uci.length != 4) return uci;
    final grid = _FenGrid.parse(posBefore.fen.split(' ').first);
    if (grid == null) return uci;
    final ff = _FenGrid.files.indexOf(uci[0]);
    final fr = int.parse(uci[1]) - 1;
    final tf = _FenGrid.files.indexOf(uci[2]);
    final tr = int.parse(uci[3]) - 1;
    final piece = grid.at(ff, fr);
    final target = grid.at(tf, tr);
    if ((piece == 'K' && target == 'R') || (piece == 'k' && target == 'r')) {
      return '${uci.substring(0, 2)}${_FenGrid.square(tf > ff ? 6 : 2, fr)}';
    }
    return uci;
  }

  /// Decides whether move[0] is the opponent's setup move (Lichess) or the
  /// player's first move. Evidence is scored:
  ///  * parity: Lichess lines end on the player's move => even length;
  ///    player-first lines end on the player's move => odd length
  ///  * a final checkmate is delivered by the player (boosts parity)
  ///  * material swing for the hypothesised player
  ///  * source prior
  /// Ties fall back to the Lichess standard.
  static ({SynFirstMovePolicy policy, String reason}) _detectConvention(
    _PlayedLine line,
    SynFirstMovePolicy prior,
  ) {
    final n = line.uci.length;
    if (n == 1) {
      return (policy: SynFirstMovePolicy.playerFirst, reason: 'single-move line cannot contain a setup move');
    }
    var std = 0;
    var pf = 0;
    final why = <String>[];

    if (n.isEven) {
      std += 2;
      why.add('even length');
    } else {
      pf += 2;
      why.add('odd length');
    }
    if (line.end.isCheckmate) {
      if (n.isEven) {
        std += 4;
      } else {
        pf += 4;
      }
      why.add('ends in mate');
    }

    final stmSign = line.start.turn == Side.white ? 1 : -1;
    final m0 = SynFenTools.materialBalance(line.start.fen);
    final m1 = SynFenTools.materialBalance(line.positions.first.fen);
    final mEnd = SynFenTools.materialBalance(line.end.fen);
    final gainPf = stmSign * (mEnd - m0); // player = side to move in FEN
    final gainStd = -stmSign * (mEnd - m1); // player = the other side, after setup
    if (gainPf - gainStd >= 2) {
      pf += 2;
      why.add('material favours first mover');
    } else if (gainStd - gainPf >= 2) {
      std += 2;
      why.add('material favours second mover');
    }

    if (prior == SynFirstMovePolicy.playerFirst) {
      pf += 3;
      why.add('source prior');
    } else if (prior == SynFirstMovePolicy.opponentSetupFirst) {
      std += 3;
      why.add('source prior');
    }

    final policy = pf > std ? SynFirstMovePolicy.playerFirst : SynFirstMovePolicy.opponentSetupFirst;
    return (policy: policy, reason: 'auto: ${why.join(', ')} (std=$std pf=$pf)');
  }
}

/// Builds a legal "opponent setup move" for player-first puzzles by
/// retracting one quiet opponent move, then verifying with dartchess that the
/// forward move is legal and reproduces the original board exactly.
class _SetupSynthesizer {
  static const List<List<int>> _knight = <List<int>>[
    [1, 2], [2, 1], [2, -1], [1, -2], [-1, -2], [-2, -1], [-2, 1], [-1, 2], //
  ];
  static const List<List<int>> _diag = <List<int>>[
    [1, 1], [1, -1], [-1, 1], [-1, -1], //
  ];
  static const List<List<int>> _orth = <List<int>>[
    [1, 0], [-1, 0], [0, 1], [0, -1], //
  ];

  static ({String fen, String uci})? synthesize(String fullFen) {
    final f = fullFen.split(' ');
    final grid = _FenGrid.parse(f[0]);
    if (grid == null) return null;
    final playerIsWhite = f[1] == 'w';
    final oppWhite = !playerIsWhite;
    final castling = f[2];
    final ep = f[3];
    final fullmove = int.tryParse(f[5]) ?? 1;
    final pFull = oppWhite ? fullmove : (fullmove > 1 ? fullmove - 1 : 1);
    final oppTurn = oppWhite ? 'w' : 'b';

    // An en-passant target pins down the exact last move: a double pawn push.
    if (ep != '-' && ep.length == 2) {
      final file = _FenGrid.files.indexOf(ep[0]);
      if (file < 0) return null;
      final destRank = oppWhite ? 3 : 4;
      final srcRank = oppWhite ? 1 : 6;
      final pawn = oppWhite ? 'P' : 'p';
      if (grid.at(file, destRank) != pawn || grid.at(file, srcRank).isNotEmpty) return null;
      final next = grid.copy()
        ..put(file, destRank, '')
        ..put(file, srcRank, pawn);
      final candidate = '${next.toBoardField()} $oppTurn $castling - 0 $pFull';
      final uci = '${_FenGrid.square(file, srcRank)}${_FenGrid.square(file, destRank)}';
      return _verify(candidate, uci, f[0]) ? (fen: candidate, uci: uci) : null;
    }

    final oppHasRights =
        castling != '-' && RegExp(oppWhite ? '[KQA-H]' : '[kqa-h]').hasMatch(castling);

    for (final kind in const <String>['n', 'b', 'q', 'r', 'p', 'k']) {
      if ((kind == 'k' || kind == 'r') && oppHasRights) continue;
      for (var rank = 0; rank < 8; rank++) {
        for (var file = 0; file < 8; file++) {
          final piece = grid.at(file, rank);
          if (piece.isEmpty || piece.toLowerCase() != kind) continue;
          if ((piece == piece.toUpperCase()) != oppWhite) continue;
          for (final src in _sources(grid, kind, file, rank, oppWhite)) {
            final next = grid.copy()
              ..put(file, rank, '')
              ..put(src[0], src[1], piece);
            final candidate = '${next.toBoardField()} $oppTurn $castling - 0 $pFull';
            final uci = '${_FenGrid.square(src[0], src[1])}${_FenGrid.square(file, rank)}';
            if (_verify(candidate, uci, f[0])) return (fen: candidate, uci: uci);
          }
        }
      }
    }
    return null;
  }

  static List<List<int>> _sources(_FenGrid g, String kind, int file, int rank, bool oppWhite) {
    final out = <List<int>>[];
    bool inside(int f, int r) => f >= 0 && f < 8 && r >= 0 && r < 8;
    if (kind == 'n' || kind == 'k') {
      final steps = kind == 'n' ? _knight : <List<int>>[..._orth, ..._diag];
      for (final s in steps) {
        final f = file + s[0];
        final r = rank + s[1];
        if (inside(f, r) && g.at(f, r).isEmpty) out.add(<int>[f, r]);
      }
    } else if (kind == 'p') {
      final r = oppWhite ? rank - 1 : rank + 1;
      final valid = oppWhite ? r >= 1 : r <= 6;
      if (valid && inside(file, r) && g.at(file, r).isEmpty) out.add(<int>[file, r]);
    } else {
      final dirs = kind == 'b'
          ? _diag
          : kind == 'r'
              ? _orth
              : <List<int>>[..._orth, ..._diag];
      for (final d in dirs) {
        var f = file + d[0];
        var r = rank + d[1];
        while (inside(f, r) && g.at(f, r).isEmpty) {
          out.add(<int>[f, r]);
          f += d[0];
          r += d[1];
        }
      }
    }
    return out;
  }

  static bool _verify(String candidateFen, String uci, String targetBoard) {
    try {
      final pos = Chess.fromSetup(Setup.parseFen(candidateFen));
      final move = Move.parse(uci);
      if (move == null || !pos.isLegal(move)) return false;
      return pos.play(move).fen.split(' ').first == targetBoard;
    } catch (_) {
      return false;
    }
  }
}

// ---------------------------------------------------------------------------
// Row finalization (shared by the worker isolate and the SQLite page workers)
// ---------------------------------------------------------------------------

class _NormalizeStats {
  int sanConverted = 0;
  int playerFirstConverted = 0;
  int unnormalizable = 0;
}

List<Object?> _finalizeRow(SynRawPuzzle raw, SynImportOptions o, _NormalizeStats stats) {
  final policy = o.firstMovePolicy != SynFirstMovePolicy.auto
      ? o.firstMovePolicy
      : (raw.hintIsDefinitive ? raw.conventionHint : SynFirstMovePolicy.auto);
  final n = SynMoveNormalizer.normalize(
    fen: raw.fen,
    moves: raw.moves,
    policy: policy,
    prior: raw.conventionHint,
    synthesizeSetupMove: o.synthesizeSetupMove,
    skipValidation: !o.validateUciMoves,
  );
  if (n.convertedFromSan) stats.sanConverted++;
  if (n.convertedFromPlayerFirst) stats.playerFirstConverted++;
  final rawId = raw.id?.trim();
  final id = (rawId != null && rawId.isNotEmpty) ? rawId : SynIds.derive(n.fen, n.uciMoves);
  return <Object?>[
    id,
    n.fen,
    n.uciMoves,
    _asRating(raw.rating, o.defaultRating),
    _asThemes(raw.themes, o.defaultThemes),
  ];
}

class _PageResult {
  _PageResult(this.rows, this.skipped, this.san, this.pf, this.errors);
  final List<List<Object?>> rows;
  final int skipped;
  final int san;
  final int pf;
  final List<String> errors;
}

/// Runs in a short-lived isolate (see [_normalizeInIsolate]).
_PageResult _normalizeRows(List<List<Object?>> rows, SynImportOptions o, SynFirstMovePolicy prior) {
  final out = <List<Object?>>[];
  final stats = _NormalizeStats();
  final errors = <String>[];
  var skipped = 0;
  for (final r in rows) {
    final fen = r[1]?.toString().trim() ?? '';
    final moves = SynMoveTokens.fromObject(r[2]);
    if (fen.isEmpty || moves.isEmpty) {
      skipped++;
      if (errors.length < o.maxRecordedErrors) errors.add('SQLite: empty FEN or moves');
      continue;
    }
    try {
      out.add(_finalizeRow(
        SynRawPuzzle(
          id: r[0]?.toString(),
          fen: fen,
          moves: moves,
          rating: r[3] == null ? null : _asRating(r[3], 0),
          themes: r[4]?.toString(),
          conventionHint: prior,
        ),
        o,
        stats,
      ));
    } on SynNormalizeException catch (e) {
      skipped++;
      if (errors.length < o.maxRecordedErrors) errors.add(e.message);
    }
  }
  return _PageResult(out, skipped, stats.sanConverted, stats.playerFirstConverted, errors);
}

Future<_PageResult> _normalizeInIsolate(List<List<Object?>> rows, SynImportOptions o, SynFirstMovePolicy prior) =>
    Isolate.run(() => _normalizeRows(rows, o, prior));

// ---------------------------------------------------------------------------
// Worker isolate for text sources (parse + normalize, back-pressured)
// ---------------------------------------------------------------------------

class _WorkerInit {
  const _WorkerInit({
    required this.out,
    required this.path,
    required this.layers,
    required this.payload,
    required this.extension,
    required this.options,
  });

  final SendPort out;
  final String path;
  final List<int> layers; // SynPuzzleFormat indices
  final int payload;
  final String extension;
  final SynImportOptions options;
}

Future<void> _synImportWorker(_WorkerInit init) async {
  final out = init.out;
  final control = ReceivePort();
  var credits = 2; // max un-acked batches in flight
  Completer<void>? waiter;
  control.listen((dynamic m) {
    if (m == 'ack') {
      credits++;
      final w = waiter;
      waiter = null;
      w?.complete();
    }
  });
  out.send(<String, Object?>{'t': 'ready', 'port': control.sendPort});

  final o = init.options;
  final ctx = SynParseContext(maxErrors: o.maxRecordedErrors);
  final stats = _NormalizeStats();
  var parsed = 0;
  var bytesRead = 0;

  Map<String, Object?> snap(String t, [Map<String, Object?> extra = const <String, Object?>{}]) =>
      <String, Object?>{
        't': t,
        'parsed': parsed,
        'skipped': ctx.skipped,
        'bytes': bytesRead,
        'san': stats.sanConverted,
        'pf': stats.playerFirstConverted,
        ...extra,
      };

  try {
    final layers = <SynPuzzleFormat>[for (final i in init.layers) SynPuzzleFormat.values[i]];
    final payload = SynPuzzleFormat.values[init.payload];
    final bytes = SynFileFormatDetector.openDecoded(init.path, layers, onBytes: (n) => bytesRead += n);
    var rows = <List<Object?>>[];
    var lastReport = 0;

    Future<void> flush() async {
      if (rows.isEmpty) return;
      while (credits <= 0) {
        waiter = Completer<void>();
        await waiter!.future;
      }
      credits--;
      out.send(snap('batch', <String, Object?>{'rows': rows}));
      rows = <List<Object?>>[];
    }

    await for (final raw in SynParsers.parse(payload, bytes, ctx, init.extension)) {
      parsed++;
      try {
        rows.add(_finalizeRow(raw, o, stats));
      } on SynNormalizeException catch (e) {
        stats.unnormalizable++;
        ctx.skip(e.message);
      }
      if (o.maxRecords != null && parsed >= o.maxRecords!) break;
      if (rows.length >= o.batchSize) await flush();
      if (parsed - lastReport >= o.progressEveryRecords) {
        lastReport = parsed;
        out.send(snap('progress'));
      }
    }
    await flush();
    out.send(snap('done', <String, Object?>{'errors': ctx.errors}));
  } catch (e, st) {
    out.send(snap('error', <String, Object?>{'message': '$e', 'stack': '$st'}));
  } finally {
    control.close();
  }
}

// ---------------------------------------------------------------------------
// 5. Importer (Batch Ingestion + Direct Mount)
// ---------------------------------------------------------------------------

class _Counters {
  int parsed = 0;
  int inserted = 0;
  int skipped = 0;
  int duplicates = 0;
  int san = 0;
  int pf = 0;
  int bytes = 0;
  List<String> errors = <String>[];
}

class SynPuzzleImporter {
  SynPuzzleImporter(this._db);

  final Database _db;

  static const String createTableSql = 'CREATE TABLE IF NOT EXISTS $kSynPuzzleTable ('
      'id TEXT PRIMARY KEY, '
      'fen TEXT NOT NULL, '
      'moves TEXT NOT NULL, '
      'rating INTEGER, '
      'themes TEXT, '
      'solved INTEGER DEFAULT 0)';

  Future<void> ensureSchema() => _db.execute(createTableSql);

  Future<void> _createIndexes() async {
    await _db.execute('CREATE INDEX IF NOT EXISTS idx_${kSynPuzzleTable}_rating ON $kSynPuzzleTable(rating)');
    await _db.execute('CREATE INDEX IF NOT EXISTS idx_${kSynPuzzleTable}_solved ON $kSynPuzzleTable(solved)');
  }

  Future<int> countOfflinePuzzles() async =>
      Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM $kSynPuzzleTable')) ?? 0;

  /// Convenience wrapper that drains [importFile] and returns the final result.
  Future<SynImportResult> importFileAndWait(
    String sourcePath, {
    SynImportOptions options = const SynImportOptions(),
    SynCancelToken? cancelToken,
    void Function(SynImportProgress progress)? onProgress,
  }) async {
    SynImportProgress? last;
    await for (final p in importFile(sourcePath, options: options, cancelToken: cancelToken)) {
      last = p;
      onProgress?.call(p);
    }
    final result = last?.result;
    if (result == null) {
      return SynImportResult(
        sourcePath: sourcePath,
        format: SynPuzzleFormat.unknown,
        mode: SynImportMode.batchIngestion,
        failureMessage: 'Import ended without a terminal event',
      );
    }
    return result;
  }

  /// Batch Ingestion Mode. Sniffs the file, then streams, normalizes and
  /// inserts puzzles into [kSynPuzzleTable] in chunked Batch transactions.
  /// The last emitted event always carries [SynImportProgress.result].
  Stream<SynImportProgress> importFile(
    String sourcePath, {
    SynImportOptions options = const SynImportOptions(),
    SynCancelToken? cancelToken,
  }) async* {
    final sw = Stopwatch()..start();
    yield const SynImportProgress(phase: SynImportPhase.sniffing, message: 'Inspecting file header');
    final SynFormatDetection detection;
    try {
      detection = await SynFileFormatDetector.detect(sourcePath);
    } catch (e) {
      yield _terminal(
        SynImportPhase.failed,
        _Counters(),
        SynImportResult(
          sourcePath: sourcePath,
          format: SynPuzzleFormat.unknown,
          mode: SynImportMode.batchIngestion,
          elapsed: sw.elapsed,
          failureMessage: '$e',
        ),
      );
      return;
    }
    if (!detection.isSupported) {
      yield _terminal(
        SynImportPhase.failed,
        _Counters(),
        SynImportResult(
          sourcePath: sourcePath,
          format: detection.payload,
          mode: SynImportMode.batchIngestion,
          elapsed: sw.elapsed,
          failureMessage: detection.unsupportedReason ?? 'Unsupported format',
        ),
      );
      return;
    }
    await ensureSchema();
    if (detection.isSqlite) {
      yield* _importSqlite(detection, options, cancelToken, sw);
    } else {
      yield* _importText(detection, options, cancelToken, sw);
    }
  }

  SynImportProgress _terminal(SynImportPhase phase, _Counters c, SynImportResult result) => SynImportProgress(
        phase: phase,
        recordsParsed: c.parsed,
        recordsInserted: c.inserted,
        recordsSkipped: c.skipped,
        duplicates: c.duplicates,
        bytesRead: c.bytes,
        message: result.failureMessage ?? (result.cancelled ? 'Cancelled' : 'Done'),
        result: result,
      );

  SynImportResult _result(
    SynFormatDetection d,
    _Counters c,
    Stopwatch sw, {
    bool cancelled = false,
    String? failure,
  }) =>
      SynImportResult(
        sourcePath: d.path,
        format: d.payload,
        mode: SynImportMode.batchIngestion,
        recordsParsed: c.parsed,
        recordsInserted: c.inserted,
        recordsSkipped: c.skipped,
        duplicates: c.duplicates,
        convertedFromSan: c.san,
        convertedFromPlayerFirst: c.pf,
        elapsed: sw.elapsed,
        errors: List<String>.unmodifiable(c.errors),
        cancelled: cancelled,
        failureMessage: failure,
      );

  /// One Batch commit (one transaction). Inserted rows are measured exactly via
  /// SQLite's total_changes() so ignored duplicates are not counted.
  Future<int> _writeBatch(List<List<Object?>> rows) async {
    if (rows.isEmpty) return 0;
    Future<int> totalChanges() async =>
        Sqflite.firstIntValue(await _db.rawQuery('SELECT total_changes()')) ?? 0;
    final before = await totalChanges();
    final batch = _db.batch();
    for (final r in rows) {
      batch.insert(
        kSynPuzzleTable,
        <String, Object?>{
          'id': r[0],
          'fen': r[1],
          'moves': r[2],
          'rating': r[3],
          'themes': r[4],
          'solved': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
    return (await totalChanges()) - before;
  }

  // ----- text sources: worker isolate ------------------------------------

  Stream<SynImportProgress> _importText(
    SynFormatDetection d,
    SynImportOptions o,
    SynCancelToken? token,
    Stopwatch sw,
  ) async* {
    final totalBytes = await File(d.path).length();
    final c = _Counters();
    final port = ReceivePort();
    Isolate? isolate;
    var finished = false;
    try {
      isolate = await Isolate.spawn<_WorkerInit>(
        _synImportWorker,
        _WorkerInit(
          out: port.sendPort,
          path: d.path,
          layers: <int>[for (final l in d.layers) l.index],
          payload: d.payload.index,
          extension: d.extension,
          options: o,
        ),
        onError: port.sendPort,
        onExit: port.sendPort,
      );
      final spawned = isolate;
      token?._listen(() => spawned.kill(priority: Isolate.immediate));

      SendPort? control;
      String? failure;
      yield SynImportProgress(
        phase: SynImportPhase.parsing,
        totalBytes: totalBytes,
        message: 'Parsing ${d.payload.name}',
      );

      void absorb(Map<dynamic, dynamic> msg) {
        c.parsed = msg['parsed'] as int? ?? c.parsed;
        c.skipped = msg['skipped'] as int? ?? c.skipped;
        c.bytes = msg['bytes'] as int? ?? c.bytes;
        c.san = msg['san'] as int? ?? c.san;
        c.pf = msg['pf'] as int? ?? c.pf;
      }

      SynImportProgress snapshot(SynImportPhase phase, String message) => SynImportProgress(
            phase: phase,
            recordsParsed: c.parsed,
            recordsInserted: c.inserted,
            recordsSkipped: c.skipped,
            duplicates: c.duplicates,
            bytesRead: c.bytes,
            totalBytes: totalBytes,
            message: message,
          );

      await for (final dynamic msg in port) {
        if (token?.isCancelled ?? false) break;
        if (msg is Map) {
          switch (msg['t']) {
            case 'ready':
              control = msg['port'] as SendPort?;
            case 'batch':
              absorb(msg);
              final rows = (msg['rows'] as List<dynamic>).cast<List<Object?>>();
              final inserted = await _writeBatch(rows);
              c.inserted += inserted;
              c.duplicates += rows.length - inserted;
              control?.send('ack');
              yield snapshot(SynImportPhase.writing, 'Writing batch');
            case 'progress':
              absorb(msg);
              yield snapshot(SynImportPhase.parsing, 'Parsing');
            case 'done':
              absorb(msg);
              c.errors = (msg['errors'] as List<dynamic>? ?? const <dynamic>[]).cast<String>().toList();
              finished = true;
            case 'error':
              absorb(msg);
              failure = msg['message'] as String? ?? 'Worker failed';
              finished = true;
          }
          if (finished) break;
        } else if (msg is List) {
          failure = 'Worker crashed: ${msg.isEmpty ? 'unknown' : msg.first}';
          break;
        } else if (msg == null) {
          if (!finished) failure = 'Worker exited unexpectedly';
          break;
        }
      }

      if (token?.isCancelled ?? false) {
        yield _terminal(SynImportPhase.cancelled, c, _result(d, c, sw, cancelled: true));
        return;
      }
      if (failure != null) {
        yield _terminal(SynImportPhase.failed, c, _result(d, c, sw, failure: failure));
        return;
      }
      yield snapshot(SynImportPhase.indexing, 'Building indexes');
      await _createIndexes();
      yield _terminal(SynImportPhase.finished, c, _result(d, c, sw));
    } catch (e) {
      yield _terminal(SynImportPhase.failed, c, _result(d, c, sw, failure: '$e'));
    } finally {
      port.close();
      isolate?.kill(priority: Isolate.immediate);
    }
  }

  // ----- external SQLite: keyset-paged ingestion --------------------------

  Stream<SynImportProgress> _importSqlite(
    SynFormatDetection d,
    SynImportOptions o,
    SynCancelToken? token,
    Stopwatch sw,
  ) async* {
    final c = _Counters();
    File? temp;
    Database? ext;
    try {
      var dbPath = d.path;
      if (d.layers.isNotEmpty) {
        temp = await _materializeSqlite(d);
        dbPath = temp.path;
      }
      ext = await openDatabase(dbPath, readOnly: true, singleInstance: false);
      final schema = await SynSqliteIntrospector.discover(ext);
      if (schema == null) {
        yield _terminal(
          SynImportPhase.failed,
          c,
          _result(d, c, sw, failure: 'No table with FEN and moves columns found'),
        );
        return;
      }
      final pageSize = o.batchSize;
      final table = _q(schema.tableName);
      int? lastRid;
      var offset = 0;
      yield SynImportProgress(
        phase: SynImportPhase.parsing,
        totalRecords: schema.rowCount,
        message: 'Reading ${schema.tableName}',
      );
      while (true) {
        if (token?.isCancelled ?? false) {
          yield _terminal(SynImportPhase.cancelled, c, _result(d, c, sw, cancelled: true));
          return;
        }
        final String sql;
        final List<Object?> args;
        if (schema.hasRowId) {
          final where = lastRid == null ? '' : ' WHERE rowid > ?';
          sql = 'SELECT ${schema.selectList()} FROM $table$where ORDER BY rowid LIMIT ?';
          args = <Object?>[if (lastRid != null) lastRid, pageSize];
        } else {
          sql = 'SELECT ${schema.selectList()} FROM $table LIMIT ? OFFSET ?';
          args = <Object?>[pageSize, offset];
        }
        final rows = await ext.rawQuery(sql, args);
        if (rows.isEmpty) break;
        if (schema.hasRowId) {
          lastRid = rows.last['__rid']! as int;
        } else {
          offset += rows.length;
        }
        final plain = <List<Object?>>[
          for (final r in rows) <Object?>[r['__id'], r['__fen'], r['__moves'], r['__rating'], r['__themes']],
        ];
        final page = await _normalizeInIsolate(plain, o, SynFirstMovePolicy.opponentSetupFirst);
        final inserted = await _writeBatch(page.rows);
        c.parsed += rows.length;
        c.skipped += page.skipped;
        c.san += page.san;
        c.pf += page.pf;
        c.inserted += inserted;
        c.duplicates += page.rows.length - inserted;
        for (final e in page.errors) {
          if (c.errors.length < o.maxRecordedErrors) c.errors.add(e);
        }
        yield SynImportProgress(
          phase: SynImportPhase.writing,
          recordsParsed: c.parsed,
          recordsInserted: c.inserted,
          recordsSkipped: c.skipped,
          duplicates: c.duplicates,
          totalRecords: schema.rowCount,
          message: 'Writing batch',
        );
        if (o.maxRecords != null && c.parsed >= o.maxRecords!) break;
        if (rows.length < pageSize) break;
      }
      yield SynImportProgress(
        phase: SynImportPhase.indexing,
        recordsParsed: c.parsed,
        recordsInserted: c.inserted,
        totalRecords: schema.rowCount,
        message: 'Building indexes',
      );
      await _createIndexes();
      yield _terminal(SynImportPhase.finished, c, _result(d, c, sw));
    } catch (e) {
      yield _terminal(SynImportPhase.failed, c, _result(d, c, sw, failure: '$e'));
    } finally {
      await ext?.close();
      if (temp != null && await temp.exists()) await temp.delete();
    }
  }

  Future<File> _materializeSqlite(SynFormatDetection d) async {
    final tmp = File(p.join(Directory.systemTemp.path, 'syn_${SynIds.fnvHex(d.path).substring(0, 12)}.db'));
    final sink = tmp.openWrite();
    try {
      await sink.addStream(SynFileFormatDetector.openDecoded(d.path, d.layers));
    } finally {
      await sink.close();
    }
    return tmp;
  }

  // ----- Direct Mount Mode ------------------------------------------------

  /// Zero-copy-ish mount of an external SQLite puzzle database. The file is
  /// copied once into app storage (a plain file copy, no parsing, so a 35 MB
  /// file mounts in well under 200 ms on flash storage) or used in place when
  /// [copyIntoAppStorage] is false. It is then opened read-only and queried
  /// on demand; no rows are ingested. gzip/zlib-wrapped databases are
  /// inflated into the mounts directory first.
  Future<SynMountedPuzzleDb> mountExternalDatabase(
    String sourcePath, {
    bool copyIntoAppStorage = true,
    String? mountsDirectory,
    SynImportOptions options = const SynImportOptions(),
  }) async {
    final detection = await SynFileFormatDetector.detect(sourcePath);
    if (!detection.isSqlite) {
      throw SynImportException(
        'Direct mount needs a SQLite database (detected: ${detection.payload.name}'
        '${detection.unsupportedReason == null ? '' : ', ${detection.unsupportedReason}'}).',
      );
    }
    var target = sourcePath;
    if (copyIntoAppStorage || detection.layers.isNotEmpty) {
      final dir = Directory(mountsDirectory ?? p.join(await getDatabasesPath(), 'syn_mounts'));
      await dir.create(recursive: true);
      final base = p.basenameWithoutExtension(sourcePath).replaceAll(RegExp(r'[^A-Za-z0-9_\-]'), '_');
      target = p.join(dir.path, '${SynIds.fnvHex(sourcePath).substring(0, 8)}_$base.db');
      if (detection.layers.isEmpty) {
        final src = File(sourcePath);
        final dst = File(target);
        final same = await dst.exists() && await dst.length() == await src.length();
        if (!same) await src.copy(target);
      } else {
        final sink = File(target).openWrite();
        try {
          await sink.addStream(SynFileFormatDetector.openDecoded(sourcePath, detection.layers));
        } finally {
          await sink.close();
        }
      }
    }
    return SynMountedPuzzleDb.open(target, options: options);
  }
}

/// A read-only, on-demand view over an external SQLite puzzle database.
class SynMountedPuzzleDb {
  SynMountedPuzzleDb._(this._db, this.schema, this.path, this.options);

  /// Opens (or re-opens, e.g. after an app restart) a mounted database.
  /// Pass a previously persisted [schema] to skip introspection.
  static Future<SynMountedPuzzleDb> open(
    String path, {
    SynSqliteSchema? schema,
    SynImportOptions options = const SynImportOptions(),
  }) async {
    final db = await openDatabase(path, readOnly: true, singleInstance: false);
    final s = schema ?? await SynSqliteIntrospector.discover(db);
    if (s == null) {
      await db.close();
      throw const SynImportException('No table with FEN and moves columns found in this database');
    }
    return SynMountedPuzzleDb._(db, s, path, options);
  }

  final Database _db;
  final SynSqliteSchema schema;
  final String path;
  final SynImportOptions options;

  Map<String, Object?> toJson() => <String, Object?>{'path': path, 'schema': schema.toJson()};

  Future<int> count() async =>
      Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM ${_q(schema.tableName)}')) ?? 0;

  Future<List<SynPuzzleRecord>> query({
    int? minRating,
    int? maxRating,
    String? theme,
    int limit = 50,
    int offset = 0,
    bool random = true,
  }) async {
    final where = <String>[];
    final args = <Object?>[];
    final rc = schema.ratingColumn;
    final tc = schema.themesColumn;
    if (rc != null && minRating != null) {
      where.add('${_q(rc)} >= ?');
      args.add(minRating);
    }
    if (rc != null && maxRating != null) {
      where.add('${_q(rc)} <= ?');
      args.add(maxRating);
    }
    if (tc != null && theme != null && theme.isNotEmpty) {
      where.add('${_q(tc)} LIKE ?');
      args.add('%$theme%');
    }
    final order = random ? 'ORDER BY RANDOM()' : (schema.hasRowId ? 'ORDER BY rowid' : '');
    final sql = 'SELECT ${schema.selectList()} FROM ${_q(schema.tableName)}'
        '${where.isEmpty ? '' : ' WHERE ${where.join(' AND ')}'} $order LIMIT ? OFFSET ?';
    args
      ..add(limit)
      ..add(offset);
    return _toRecords(await _db.rawQuery(sql, args));
  }

  Future<SynPuzzleRecord?> byId(String id) async {
    final String where;
    final Object arg;
    if (schema.idColumn != null) {
      where = '${_q(schema.idColumn!)} = ?';
      arg = id;
    } else if (schema.hasRowId && int.tryParse(id) != null) {
      where = 'rowid = ?';
      arg = int.parse(id);
    } else {
      return null;
    }
    final rows = await _db.rawQuery(
      'SELECT ${schema.selectList()} FROM ${_q(schema.tableName)} WHERE $where LIMIT 1',
      <Object?>[arg],
    );
    final list = _toRecords(rows);
    return list.isEmpty ? null : list.first;
  }

  /// Makes the mounted file queryable from [host] via `ATTACH DATABASE`,
  /// e.g. `SELECT ... FROM syn_ext.<table>`. [alias] must be a plain identifier.
  Future<void> attachTo(Database host, {String alias = 'syn_ext'}) async {
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(alias)) {
      throw ArgumentError.value(alias, 'alias', 'must be a plain SQL identifier');
    }
    await host.execute('ATTACH DATABASE ? AS $alias', <Object?>[path]);
  }

  Future<void> detachFrom(Database host, {String alias = 'syn_ext'}) async {
    if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(alias)) {
      throw ArgumentError.value(alias, 'alias', 'must be a plain SQL identifier');
    }
    await host.execute('DETACH DATABASE $alias');
  }

  Future<void> close() => _db.close();

  /// Rows are normalized lazily (SAN -> UCI, convention fix) so the puzzle
  /// controller always receives canonical Lichess lines. Unplayable rows are dropped.
  List<SynPuzzleRecord> _toRecords(List<Map<String, Object?>> rows) {
    final stats = _NormalizeStats();
    final out = <SynPuzzleRecord>[];
    for (final r in rows) {
      final fen = r['__fen']?.toString().trim() ?? '';
      final moves = SynMoveTokens.fromObject(r['__moves']);
      if (fen.isEmpty || moves.isEmpty) continue;
      try {
        final row = _finalizeRow(
          SynRawPuzzle(
            id: r['__id']?.toString(),
            fen: fen,
            moves: moves,
            rating: r['__rating'] == null ? null : _asRating(r['__rating'], 0),
            themes: r['__themes']?.toString(),
            conventionHint: SynFirstMovePolicy.opponentSetupFirst,
          ),
          options,
          stats,
        );
        out.add(SynPuzzleRecord(
          id: row[0]! as String,
          fen: row[1]! as String,
          moves: row[2]! as String,
          rating: row[3]! as int,
          themes: row[4]! as String,
        ));
      } on SynNormalizeException {
        continue;
      }
    }
    return out;
  }
}
