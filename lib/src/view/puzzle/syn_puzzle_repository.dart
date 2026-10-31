// SYNTOXAN — Offline puzzle repository, native bridge wrapper and tactical
// hint engine. PART 2 OF 3.
//
// Target path: lib/src/puzzle/syn_puzzle_repository.dart
//
// Depends only on Part 1 (syn_puzzle_importer.dart), sqflite, path, dartchess
// and the Flutter SDK's services library (MethodChannel). No new packages.
//
// Storage model
//   syn_puzzle_packs     one row per imported/mounted pack (metadata + counts)
//   syn_mounted_solved   (pack_id, puzzle_id) progress for EVERY pack, including
//                        read-only Direct-Mounted .db files that we can never write to
//   syn_offline_puzzles  Part 1 table; gains a nullable pack_id column (added by
//                        ALTER TABLE) so Batch-Ingested rows belong to a pack
//
// schema_json is a small JSON envelope:
//   {"schema": <SynSqliteSchema json | null>, "ownsFile": bool, "rowLo": int?, "rowHi": int?}

import 'dart:convert';
import 'dart:io';

import 'package:dartchess/dartchess.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'syn_puzzle_importer.dart';

const String kSynPacksTable = 'syn_puzzle_packs';
const String kSynSolvedTable = 'syn_mounted_solved';
const String _kIngestedPathPrefix = 'table:';

const int _kProbeWidth = 16; // random rowids tested per round
const int _kProbeRounds = 3;
const int _kScanPageSize = 32;
const int _kScanMaxPages = 40;

String _qi(String ident) => '"${ident.replaceAll('"', '""')}"';

int _intOr(Object? v, int fallback) {
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

String _themesOr(Object? v, String fallback) {
  final String s = v is List ? v.map((e) => e.toString()).join(' ') : (v?.toString() ?? '');
  final cleaned = s.replaceAll(RegExp(r'[,;|]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  return cleaned.isEmpty ? fallback : cleaned;
}

// ---------------------------------------------------------------------------
// Dart side of the native storage bridge
// ---------------------------------------------------------------------------

class SynPickedFile {
  const SynPickedFile({required this.path, required this.name, required this.size});

  /// Absolute path of the app-private copy (filesDir/syn_puzzles/...).
  final String path;

  /// Original display name chosen by the user.
  final String name;
  final int size;

  @override
  String toString() => 'SynPickedFile($name, $size bytes, $path)';
}

class SynFileBridgeException implements Exception {
  const SynFileBridgeException(this.code, this.message);
  final String code;
  final String message;
  @override
  String toString() => 'SynFileBridgeException($code): $message';
}

class SynFileBridge {
  SynFileBridge({MethodChannel? channel}) : _channel = channel ?? const MethodChannel(channelName);

  static const String channelName = 'syntoxan/file_bridge';
  final MethodChannel _channel;

  /// Opens the system picker and copies the chosen document into app-private
  /// storage. Returns null when the user cancels.
  Future<SynPickedFile?> pickPuzzleFile() async {
    if (!Platform.isAndroid) {
      throw const SynFileBridgeException('UNSUPPORTED', 'The SYNTOXAN file bridge is Android-only');
    }
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('pickPuzzleFile');
      if (res == null) return null;
      final path = res['path'] as String?;
      if (path == null || path.isEmpty) {
        throw const SynFileBridgeException('BAD_RESPONSE', 'Bridge returned no file path');
      }
      final name = (res['name'] as String?) ?? p.basename(path);
      final size = (res['size'] as num?)?.toInt() ?? await File(path).length();
      return SynPickedFile(path: path, name: name, size: size);
    } on PlatformException catch (e) {
      throw SynFileBridgeException(e.code, e.message ?? e.code);
    } on MissingPluginException {
      throw const SynFileBridgeException('UNSUPPORTED', 'file_bridge channel is not registered in MainActivity');
    }
  }

  /// Deletes a file previously returned by [pickPuzzleFile]. True when the file
  /// is gone; false when refused (outside the sandbox directory) or on failure.
  Future<bool> deleteCopiedFile(String path) async {
    if (!Platform.isAndroid) return false;
    try {
      return (await _channel.invokeMethod<bool>('deleteCopiedFile', <String, Object?>{'path': path})) ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

class SynRepositoryException implements Exception {
  const SynRepositoryException(this.message);
  final String message;
  @override
  String toString() => 'SynRepositoryException: $message';
}

class SynPuzzlePack {
  const SynPuzzlePack({
    required this.packId,
    required this.name,
    required this.path,
    required this.format,
    required this.mode,
    required this.totalCount,
    required this.solvedCount,
    required this.sizeBytes,
    required this.isActive,
    required this.createdAt,
    this.schema,
    this.ownsFile = true,
    this.rowLo,
    this.rowHi,
  });

  factory SynPuzzlePack.fromRow(Map<String, Object?> r) {
    SynSqliteSchema? schema;
    var owns = true;
    int? lo;
    int? hi;
    final raw = r['schema_json'] as String?;
    if (raw != null && raw.isNotEmpty) {
      try {
        final d = jsonDecode(raw);
        if (d is Map<String, dynamic>) {
          final s = d['schema'];
          if (s is Map<String, dynamic>) schema = SynSqliteSchema.fromJson(s);
          owns = (d['ownsFile'] as bool?) ?? true;
          lo = (d['rowLo'] as num?)?.toInt();
          hi = (d['rowHi'] as num?)?.toInt();
        }
      } on FormatException {
        // Corrupt metadata: the pack stays listable (and deletable).
      }
    }
    final modeName = r['mode'] as String?;
    return SynPuzzlePack(
      packId: r['pack_id']! as String,
      name: (r['name'] as String?) ?? 'Puzzle pack',
      path: (r['path'] as String?) ?? '',
      format: (r['format'] as String?) ?? 'unknown',
      mode: SynImportMode.values.firstWhere(
        (m) => m.name == modeName,
        orElse: () => SynImportMode.batchIngestion,
      ),
      totalCount: (r['total_count'] as num?)?.toInt() ?? 0,
      solvedCount: (r['solved_count'] as num?)?.toInt() ?? 0,
      sizeBytes: (r['size_bytes'] as num?)?.toInt() ?? 0,
      isActive: ((r['is_active'] as num?)?.toInt() ?? 0) != 0,
      createdAt: DateTime.fromMillisecondsSinceEpoch((r['created_at'] as num?)?.toInt() ?? 0),
      schema: schema,
      ownsFile: owns,
      rowLo: lo,
      rowHi: hi,
    );
  }

  final String packId;
  final String name;

  /// File path for mounted packs; `table:syn_offline_puzzles` for ingested packs.
  final String path;
  final String format;
  final SynImportMode mode;
  final int totalCount;
  final int solvedCount;
  final int sizeBytes;
  final bool isActive;
  final DateTime createdAt;
  final SynSqliteSchema? schema;
  final bool ownsFile;
  final int? rowLo;
  final int? rowHi;

  bool get isMounted => mode == SynImportMode.directMount;
  int get unsolvedCount => totalCount > solvedCount ? totalCount - solvedCount : 0;
  double get progress => totalCount <= 0 ? 0 : (solvedCount / totalCount).clamp(0.0, 1.0).toDouble();

  String get schemaJson => jsonEncode(<String, Object?>{
        'schema': schema?.toJson(),
        'ownsFile': ownsFile,
        'rowLo': rowLo,
        'rowHi': rowHi,
      });

  Map<String, Object?> toRow() => <String, Object?>{
        'pack_id': packId,
        'name': name,
        'path': path,
        'format': format,
        'mode': mode.name,
        'schema_json': schemaJson,
        'total_count': totalCount,
        'solved_count': solvedCount,
        'size_bytes': sizeBytes,
        'is_active': isActive ? 1 : 0,
        'created_at': createdAt.millisecondsSinceEpoch,
      };

  SynPuzzlePack copyWith({int? solvedCount, bool? isActive}) => SynPuzzlePack(
        packId: packId,
        name: name,
        path: path,
        format: format,
        mode: mode,
        totalCount: totalCount,
        solvedCount: solvedCount ?? this.solvedCount,
        sizeBytes: sizeBytes,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt,
        schema: schema,
        ownsFile: ownsFile,
        rowLo: rowLo,
        rowHi: rowHi,
      );

  @override
  String toString() => 'SynPuzzlePack($packId "$name" ${mode.name} $solvedCount/$totalCount'
      '${isActive ? ' active' : ''})';
}

enum SynPackStage { picking, sniffing, mounting, ingesting, finalizing, done, failed, cancelled }

class SynPackImportProgress {
  const SynPackImportProgress({
    required this.stage,
    this.message = '',
    this.import,
    this.pack,
    this.error,
  });

  factory SynPackImportProgress.failed(String error) =>
      SynPackImportProgress(stage: SynPackStage.failed, message: error, error: error);

  final SynPackStage stage;
  final String message;

  /// Raw Part 1 progress while ingesting (null for mounts).
  final SynImportProgress? import;

  /// Set on the final `done` event.
  final SynPuzzlePack? pack;
  final String? error;

  bool get isTerminal =>
      stage == SynPackStage.done || stage == SynPackStage.failed || stage == SynPackStage.cancelled;
  bool get isSuccess => stage == SynPackStage.done;
  double? get fraction => isSuccess ? 1.0 : import?.fraction;

  @override
  String toString() => 'SynPackImportProgress($stage $message)';
}

// ---------------------------------------------------------------------------
// Tiny PRNG (xorshift64) — keeps us off dart:math, like Part 1
// ---------------------------------------------------------------------------

class _SynRng {
  _SynRng() : _s = (DateTime.now().microsecondsSinceEpoch ^ 0x9E3779B97F4A7C15) | 1;

  int _s;

  int _next() {
    var x = _s;
    x ^= x << 13;
    x ^= x >>> 7;
    x ^= x << 17;
    _s = x;
    return x;
  }

  /// Uniform-ish value in [0, max).
  int nextInt(int max) {
    if (max <= 1) return 0;
    return (_next() & 0x7FFFFFFFFFFFFFFF) % max;
  }
}

// ---------------------------------------------------------------------------
// Query helpers
// ---------------------------------------------------------------------------

class _Filter {
  const _Filter({this.minRating, this.maxRating, this.theme});

  final int? minRating;
  final int? maxRating;
  final String? theme;

  /// Filters are skipped (not failed) for columns the source table lacks.
  (List<String>, List<Object?>) clauses({required String? ratingCol, required String? themesCol}) {
    final c = <String>[];
    final a = <Object?>[];
    if (ratingCol != null && minRating != null) {
      c.add('${_qi(ratingCol)} >= ?');
      a.add(minRating);
    }
    if (ratingCol != null && maxRating != null) {
      c.add('${_qi(ratingCol)} <= ?');
      a.add(maxRating);
    }
    final t = theme?.trim();
    if (themesCol != null && t != null && t.isNotEmpty) {
      final escaped = t.replaceAll('\\', '\\\\').replaceAll('%', '\\%').replaceAll('_', '\\_');
      // Whole-token match: themes are space separated ("fork mateIn2 short").
      c.add("(' ' || ${_qi(themesCol)} || ' ') LIKE ? ESCAPE '\\'");
      a.add('% $escaped %');
    }
    return (c, a);
  }
}

class _PickPlan {
  const _PickPlan({
    required this.db,
    required this.table,
    required this.select,
    required this.baseClauses,
    required this.baseArgs,
    required this.ratingCol,
    required this.themesCol,
    required this.lo,
    required this.hi,
    required this.toRecord,
  });

  final Database db;
  final String table; // already quoted
  final String select; // must expose `rowid AS __rid`
  final List<String> baseClauses;
  final List<Object?> baseArgs;
  final String? ratingCol;
  final String? themesCol;
  final int lo;
  final int hi;
  final SynPuzzleRecord? Function(Map<String, Object?> row) toRecord;
}

/// Per-pack open resources for a Direct-Mounted database.
class _MountHandle {
  _MountHandle(this.mounted);

  final SynMountedPuzzleDb mounted;
  Future<Database>? _probeOpening;
  (int, int)? _bounds;
  Set<String>? _solved;

  /// Part 1's SynMountedPuzzleDb keeps its connection private, so rowid probes
  /// use a second read-only handle on the same file (cheap; read-only never contends).
  Future<Database> probe() =>
      _probeOpening ??= openDatabase(mounted.path, readOnly: true, singleInstance: false);

  Future<(int, int)> bounds(Database db, SynSqliteSchema s) async {
    final cached = _bounds;
    if (cached != null) return cached;
    final rows = await db.rawQuery('SELECT MIN(rowid) AS lo, MAX(rowid) AS hi FROM ${_qi(s.tableName)}');
    final lo = rows.isEmpty ? null : rows.first['lo'];
    final hi = rows.isEmpty ? null : rows.first['hi'];
    return _bounds = (lo is int && hi is int) ? (lo, hi) : (0, -1);
  }

  Future<Set<String>> solved(Database main, String packId) async {
    final cached = _solved;
    if (cached != null) return cached;
    final rows = await main.query(
      kSynSolvedTable,
      columns: <String>['puzzle_id'],
      where: 'pack_id = ?',
      whereArgs: <Object?>[packId],
    );
    return _solved = <String>{for (final r in rows) r['puzzle_id']! as String};
  }

  void markSolvedInMemory(String puzzleId) => _solved?.add(puzzleId);

  void resetSolvedInMemory() => _solved = <String>{};

  Future<void> close() async {
    try {
      final opening = _probeOpening;
      _probeOpening = null;
      if (opening != null) await (await opening).close();
    } catch (_) {
      // Closing is best effort.
    }
    try {
      await mounted.close();
    } catch (_) {
      // Closing is best effort.
    }
  }
}

// ---------------------------------------------------------------------------
// Repository
// ---------------------------------------------------------------------------

class SynPuzzleRepository {
  SynPuzzleRepository(
    this._db, {
    SynFileBridge? bridge,
    this.options = const SynImportOptions(),
  })  : _bridge = bridge ?? SynFileBridge(),
        _importer = SynPuzzleImporter(_db);

  final Database _db;
  final SynFileBridge _bridge;
  final SynPuzzleImporter _importer;
  final SynImportOptions options;

  final _SynRng _rng = _SynRng();
  final Map<String, _MountHandle> _mounts = <String, _MountHandle>{};
  Future<void>? _schemaReady;
  Map<String, SynPuzzlePack>? _packs;
  bool _busy = false;

  static const String _ingestSelect = 'rowid AS __rid, id, fen, moves, rating, themes';

  // ----- schema -----------------------------------------------------------

  Future<void> ensureSchema() {
    return _schemaReady ??= _createSchema().catchError((Object e, StackTrace s) {
      _schemaReady = null;
      Error.throwWithStackTrace(e, s);
    });
  }

  Future<void> _createSchema() async {
    await _importer.ensureSchema();
    await _db.execute(
      'CREATE TABLE IF NOT EXISTS $kSynPacksTable ('
      'pack_id TEXT PRIMARY KEY, name TEXT, path TEXT, format TEXT, mode TEXT, '
      'schema_json TEXT, total_count INTEGER, solved_count INTEGER, size_bytes INTEGER, '
      'is_active INTEGER, created_at INTEGER)',
    );
    await _db.execute(
      'CREATE TABLE IF NOT EXISTS $kSynSolvedTable ('
      'pack_id TEXT, puzzle_id TEXT, PRIMARY KEY (pack_id, puzzle_id))',
    );
    final cols = await _db.rawQuery('PRAGMA table_info($kSynPuzzleTable)');
    if (!cols.any((c) => c['name'] == 'pack_id')) {
      await _db.execute('ALTER TABLE $kSynPuzzleTable ADD COLUMN pack_id TEXT');
    }
    await _db.execute(
      'CREATE INDEX IF NOT EXISTS idx_syn_offline_puzzles_pack ON $kSynPuzzleTable(pack_id, rating)',
    );
  }

  Future<Map<String, SynPuzzlePack>> _loadPacks() async {
    await ensureSchema();
    final cached = _packs;
    if (cached != null) return cached;
    final rows = await _db.query(kSynPacksTable, orderBy: 'created_at DESC');
    final map = <String, SynPuzzlePack>{};
    for (final r in rows) {
      final pack = SynPuzzlePack.fromRow(r);
      map[pack.packId] = pack;
    }
    return _packs = map;
  }

  Future<SynPuzzlePack> _resolvePack(String? packId) async {
    final packs = await _loadPacks();
    if (packId != null) {
      final pack = packs[packId];
      if (pack == null) throw SynRepositoryException('Unknown puzzle pack: $packId');
      return pack;
    }
    for (final pack in packs.values) {
      if (pack.isActive) return pack;
    }
    throw const SynRepositoryException('No active puzzle pack. Import or mount one first.');
  }

  // ----- pack management API ----------------------------------------------

  Future<List<SynPuzzlePack>> listPacks() async => (await _loadPacks()).values.toList();

  Future<SynPuzzlePack?> activePack() async {
    for (final pack in (await _loadPacks()).values) {
      if (pack.isActive) return pack;
    }
    return null;
  }

  Future<SynPuzzlePack> setActivePack(String packId) async {
    final packs = await _loadPacks();
    if (!packs.containsKey(packId)) throw SynRepositoryException('Unknown puzzle pack: $packId');
    await _db.transaction((txn) async {
      await txn.rawUpdate(
        'UPDATE $kSynPacksTable SET is_active = 0 WHERE is_active != 0 AND pack_id != ?',
        <Object?>[packId],
      );
      await txn.rawUpdate(
        'UPDATE $kSynPacksTable SET is_active = 1 WHERE pack_id = ?',
        <Object?>[packId],
      );
    });
    _packs = null;
    return (await _loadPacks())[packId]!;
  }

  /// Records a solved puzzle. Returns true if it was newly solved (false when
  /// it was already marked). Works for read-only mounted packs because progress
  /// lives in our own database, never in the external file.
  Future<bool> markSolved(String packId, String puzzleId) async {
    final pack = (await _loadPacks())[packId];
    if (pack == null) throw SynRepositoryException('Unknown puzzle pack: $packId');
    final newly = await _db.transaction<bool>((txn) async {
      final existing = await txn.rawQuery(
        'SELECT 1 FROM $kSynSolvedTable WHERE pack_id = ? AND puzzle_id = ? LIMIT 1',
        <Object?>[packId, puzzleId],
      );
      if (existing.isNotEmpty) return false;
      await txn.insert(kSynSolvedTable, <String, Object?>{'pack_id': packId, 'puzzle_id': puzzleId});
      await txn.rawUpdate(
        'UPDATE $kSynPacksTable SET solved_count = solved_count + 1 WHERE pack_id = ?',
        <Object?>[packId],
      );
      if (!pack.isMounted) {
        await txn.rawUpdate(
          'UPDATE $kSynPuzzleTable SET solved = 1 WHERE id = ? AND pack_id = ?',
          <Object?>[puzzleId, packId],
        );
      }
      return true;
    });
    if (newly) {
      _packs?[packId] = pack.copyWith(solvedCount: pack.solvedCount + 1);
      _mounts[packId]?.markSolvedInMemory(puzzleId);
    }
    return newly;
  }

  /// Clears solved progress for a pack (puzzles themselves are untouched).
  Future<void> resetProgress(String packId) async {
    final pack = (await _loadPacks())[packId];
    if (pack == null) throw SynRepositoryException('Unknown puzzle pack: $packId');
    await _db.transaction((txn) async {
      await txn.delete(kSynSolvedTable, where: 'pack_id = ?', whereArgs: <Object?>[packId]);
      await txn.rawUpdate(
        'UPDATE $kSynPacksTable SET solved_count = 0 WHERE pack_id = ?',
        <Object?>[packId],
      );
      if (!pack.isMounted) {
        await txn.rawUpdate(
          'UPDATE $kSynPuzzleTable SET solved = 0 WHERE pack_id = ?',
          <Object?>[packId],
        );
      }
    });
    _packs?[packId] = pack.copyWith(solvedCount: 0);
    _mounts[packId]?.resetSolvedInMemory();
  }

  /// Removes a pack: closes its mount, deletes its rows / progress / backing
  /// file. If it was the active pack the newest remaining pack becomes active.
  Future<void> deletePack(String packId) async {
    final pack = (await _loadPacks())[packId];
    if (pack == null) return;
    final handle = _mounts.remove(packId);
    if (handle != null) await handle.close();
    await _db.transaction((txn) async {
      await txn.delete(kSynSolvedTable, where: 'pack_id = ?', whereArgs: <Object?>[packId]);
      if (!pack.isMounted) {
        await txn.delete(kSynPuzzleTable, where: 'pack_id = ?', whereArgs: <Object?>[packId]);
      }
      await txn.delete(kSynPacksTable, where: 'pack_id = ?', whereArgs: <Object?>[packId]);
    });
    _packs = null;
    await _deleteBackingFile(pack);
    if (pack.isActive) {
      final remaining = await _loadPacks();
      if (remaining.isNotEmpty) await setActivePack(remaining.values.first.packId);
    }
  }

  Future<void> _deleteBackingFile(SynPuzzlePack pack) async {
    if (!pack.isMounted || pack.path.isEmpty || pack.path.startsWith(_kIngestedPathPrefix)) return;
    var gone = false;
    try {
      gone = await _bridge.deleteCopiedFile(pack.path);
    } catch (_) {
      gone = false;
    }
    if (gone || !pack.ownsFile) return;
    try {
      for (final suffix in const <String>['', '-journal', '-wal', '-shm']) {
        final f = File('${pack.path}$suffix');
        if (await f.exists()) await f.delete();
      }
    } on FileSystemException {
      // Leave the orphan; the pack record is already gone.
    }
  }

  Future<void> _discardStaged(String path) async {
    try {
      await _bridge.deleteCopiedFile(path);
    } catch (_) {
      // Staging cleanup is best effort.
    }
  }

  String _newPackId(SynPickedFile file) =>
      'pk_${SynIds.fnvHex('${file.name}|${file.size}|${DateTime.now().microsecondsSinceEpoch}').substring(0, 12)}';

  Future<int> _maxRowId() async =>
      Sqflite.firstIntValue(await _db.rawQuery('SELECT COALESCE(MAX(rowid), 0) FROM $kSynPuzzleTable')) ?? 0;

  /// Opens the system picker through the native bridge, then imports/mounts the result.
  Stream<SynPackImportProgress> pickAndImport({
    SynImportMode? forceMode,
    SynImportOptions? importOptions,
    SynCancelToken? cancelToken,
    String? packName,
    bool activate = true,
  }) async* {
    if (_busy) {
      yield SynPackImportProgress.failed('Another import or mount is already running');
      return;
    }
    yield const SynPackImportProgress(stage: SynPackStage.picking, message: 'Waiting for file selection');
    final SynPickedFile? picked;
    try {
      picked = await _bridge.pickPuzzleFile();
    } on SynFileBridgeException catch (e) {
      yield SynPackImportProgress.failed(e.message);
      return;
    }
    if (picked == null) {
      yield const SynPackImportProgress(stage: SynPackStage.cancelled, message: 'No file selected');
      return;
    }
    yield* importOrMountPickedFile(
      picked,
      forceMode: forceMode,
      importOptions: importOptions,
      cancelToken: cancelToken,
      packName: packName,
      activate: activate,
    );
  }

  /// Registers a puzzle file already copied by the bridge.
  ///  * SQLite files default to Direct Mount (nothing is parsed or copied again).
  ///  * Text files (CSV/TSV, JSON/NDJSON, PGN, EPD/FEN, gzip/zlib wrapped) use
  ///    Batch Ingestion into syn_offline_puzzles.
  /// [forceMode] overrides the choice (e.g. batch-ingest a .db). Direct Mount of
  /// a non-SQLite file is rejected. The staged copy is deleted on failure and,
  /// for ingestion, after success.
  Stream<SynPackImportProgress> importOrMountPickedFile(
    SynPickedFile file, {
    SynImportMode? forceMode,
    SynImportOptions? importOptions,
    SynCancelToken? cancelToken,
    String? packName,
    bool activate = true,
  }) async* {
    final opts = importOptions ?? options;
    if (_busy) {
      await _discardStaged(file.path);
      yield SynPackImportProgress.failed('Another import or mount is already running');
      return;
    }
    _busy = true;
    var keepStaged = false; // true once the staged file became a pack's backing file
    try {
      await ensureSchema();
      yield SynPackImportProgress(stage: SynPackStage.sniffing, message: 'Inspecting ${file.name}');

      final SynFormatDetection detection = await SynFileFormatDetector.detect(file.path);
      if (!detection.isSupported) {
        await _discardStaged(file.path);
        yield SynPackImportProgress.failed(detection.unsupportedReason ?? 'Unsupported puzzle file');
        return;
      }
      final mode = forceMode ?? (detection.isSqlite ? SynImportMode.directMount : SynImportMode.batchIngestion);
      if (mode == SynImportMode.directMount && !detection.isSqlite) {
        await _discardStaged(file.path);
        yield SynPackImportProgress.failed(
          'Direct mount needs a SQLite database (detected ${detection.payload.name}). Use batch ingestion instead.',
        );
        return;
      }
      final displayName = (packName != null && packName.trim().isNotEmpty) ? packName.trim() : file.name;
      final shouldActivate = activate || (await activePack()) == null;

      if (mode == SynImportMode.directMount) {
        yield SynPackImportProgress(stage: SynPackStage.mounting, message: 'Mounting $displayName');
        SynMountedPuzzleDb? mounted;
        String? mountError;
        try {
          mounted = await _importer.mountExternalDatabase(file.path, copyIntoAppStorage: false, options: opts);
        } catch (e) {
          mountError = '$e';
        }
        if (mounted == null) {
          await _discardStaged(file.path);
          yield SynPackImportProgress.failed(mountError ?? 'Could not mount the database');
          return;
        }
        final mountedPath = mounted.path;
        if (mountedPath != file.path) {
          // gzip/zlib-wrapped database was inflated elsewhere: the staged copy is redundant.
          await _discardStaged(file.path);
        }
        final pack = SynPuzzlePack(
          packId: _newPackId(file),
          name: displayName,
          path: mountedPath,
          format: detection.payload.name,
          mode: SynImportMode.directMount,
          totalCount: mounted.schema.rowCount,
          solvedCount: 0,
          sizeBytes: await File(mountedPath).length(),
          isActive: false,
          createdAt: DateTime.now(),
          schema: mounted.schema,
          ownsFile: true,
        );
        try {
          await _db.insert(kSynPacksTable, pack.toRow());
        } catch (e) {
          await mounted.close();
          if (mountedPath == file.path) {
            await _discardStaged(file.path);
          } else {
            await _deleteBackingFile(pack);
          }
          yield SynPackImportProgress.failed('Could not register the pack: $e');
          return;
        }
        keepStaged = true;
        _mounts[pack.packId] = _MountHandle(mounted);
        _packs = null;
        if (shouldActivate) await setActivePack(pack.packId);
        final saved = (await _loadPacks())[pack.packId]!;
        yield SynPackImportProgress(
          stage: SynPackStage.done,
          message: 'Mounted ${saved.totalCount} puzzles',
          pack: saved,
        );
        return;
      }

      // ---- Batch Ingestion ----
      final lowWater = await _maxRowId();
      SynImportResult? result;
      await for (final progress in _importer.importFile(file.path, options: opts, cancelToken: cancelToken)) {
        if (progress.result != null) result = progress.result;
        yield SynPackImportProgress(
          stage: SynPackStage.ingesting,
          message: progress.message,
          import: progress,
        );
      }
      if (result == null || !result.success) {
        // Remove rows from the aborted run (they are still untagged).
        await _db.delete(
          kSynPuzzleTable,
          where: 'rowid > ? AND pack_id IS NULL',
          whereArgs: <Object?>[lowWater],
        );
        await _discardStaged(file.path);
        if (result != null && result.cancelled) {
          yield const SynPackImportProgress(stage: SynPackStage.cancelled, message: 'Import cancelled');
        } else {
          yield SynPackImportProgress.failed(result?.failureMessage ?? 'Import ended unexpectedly');
        }
        return;
      }

      yield const SynPackImportProgress(stage: SynPackStage.finalizing, message: 'Registering pack');
      final packId = _newPackId(file);
      await _db.update(
        kSynPuzzleTable,
        <String, Object?>{'pack_id': packId},
        where: 'rowid > ? AND pack_id IS NULL',
        whereArgs: <Object?>[lowWater],
      );
      final total = Sqflite.firstIntValue(await _db.rawQuery(
            'SELECT COUNT(*) FROM $kSynPuzzleTable WHERE pack_id = ?',
            <Object?>[packId],
          )) ??
          0;
      if (total == 0) {
        await _discardStaged(file.path);
        yield SynPackImportProgress.failed(
          'No new puzzles were added (${result.recordsSkipped} skipped, ${result.duplicates} already present)',
        );
        return;
      }
      final pack = SynPuzzlePack(
        packId: packId,
        name: displayName,
        path: '$_kIngestedPathPrefix$kSynPuzzleTable',
        format: detection.payload.name,
        mode: SynImportMode.batchIngestion,
        totalCount: total,
        solvedCount: 0,
        sizeBytes: file.size,
        isActive: false,
        createdAt: DateTime.now(),
        ownsFile: false,
        rowLo: lowWater + 1,
        rowHi: await _maxRowId(),
      );
      await _db.insert(kSynPacksTable, pack.toRow());
      await _discardStaged(file.path); // rows are in SQLite now; the staging copy is dead weight
      _packs = null;
      if (shouldActivate) await setActivePack(packId);
      final saved = (await _loadPacks())[packId]!;
      yield SynPackImportProgress(
        stage: SynPackStage.done,
        message: 'Imported $total puzzles (${result.recordsSkipped} skipped, ${result.duplicates} duplicates)',
        pack: saved,
      );
    } catch (e) {
      if (!keepStaged) await _discardStaged(file.path);
      yield SynPackImportProgress.failed('$e');
    } finally {
      _busy = false;
    }
  }

  // ----- puzzle selection ---------------------------------------------------

  /// Returns a random puzzle from [packId] (default: the active pack), or null
  /// when nothing matches (or the pack is fully solved and [includeSolved] is false).
  ///
  /// Mounted packs never use ORDER BY RANDOM() on the hot path:
  ///   1. rowid probes: 16 random rowids per round in one `rowid IN (...)` query
  ///      (O(log n) each), filters pushed into SQL, solved ids filtered in memory;
  ///   2. a forward rowid range scan from a random pivot (wraps around);
  ///   3. Part 1's SynMountedPuzzleDb.query(random: true) as the last resort.
  Future<SynPuzzleRecord?> getNextPuzzle({
    String? packId,
    int? minRating,
    int? maxRating,
    String? theme,
    bool includeSolved = false,
  }) async {
    final pack = await _resolvePack(packId);
    var lo = minRating;
    var hi = maxRating;
    if (lo != null && hi != null && lo > hi) {
      final t = lo;
      lo = hi;
      hi = t;
    }
    final filter = _Filter(minRating: lo, maxRating: hi, theme: theme);
    if (!includeSolved && pack.totalCount > 0 && pack.solvedCount >= pack.totalCount) return null;
    return pack.isMounted
        ? _nextFromMount(pack, filter, includeSolved)
        : _nextFromIngested(pack, filter, includeSolved);
  }

  Future<_MountHandle> _handleFor(SynPuzzlePack pack) async {
    final existing = _mounts[pack.packId];
    if (existing != null) return existing;
    final schema = pack.schema;
    if (schema == null) {
      throw SynRepositoryException('Pack "${pack.name}" has no schema metadata; remove and re-mount it');
    }
    if (!await File(pack.path).exists()) {
      throw SynRepositoryException('Backing file of "${pack.name}" is missing; remove and re-mount it');
    }
    final mounted = await SynMountedPuzzleDb.open(pack.path, schema: schema, options: options);
    return _mounts[pack.packId] = _MountHandle(mounted);
  }

  Future<SynPuzzleRecord?> _nextFromMount(SynPuzzlePack pack, _Filter filter, bool includeSolved) async {
    final schema = pack.schema;
    if (schema == null) throw SynRepositoryException('Pack "${pack.name}" has no schema metadata');
    final handle = await _handleFor(pack);
    final Set<String> solved = includeSolved ? const <String>{} : await handle.solved(_db, pack.packId);
    bool accept(SynPuzzleRecord r) => includeSolved || !solved.contains(r.id);

    if (schema.hasRowId && schema.rowCount > 0) {
      final probe = await handle.probe();
      final (lo, hi) = await handle.bounds(probe, schema);
      final plan = _PickPlan(
        db: probe,
        table: _qi(schema.tableName),
        select: schema.selectList(),
        baseClauses: const <String>[],
        baseArgs: const <Object?>[],
        ratingCol: schema.ratingColumn,
        themesCol: schema.themesColumn,
        lo: lo,
        hi: hi,
        toRecord: (row) => _mountedRowToRecord(row, schema),
      );
      final hit = await _pickRandom(plan, filter, accept);
      if (hit != null) return hit;
    }

    final candidates = await handle.mounted.query(
      minRating: filter.minRating,
      maxRating: filter.maxRating,
      theme: filter.theme,
      limit: 24,
      random: true,
    );
    for (final r in candidates) {
      if (accept(r)) return r;
    }
    return null;
  }

  Future<SynPuzzleRecord?> _nextFromIngested(SynPuzzlePack pack, _Filter filter, bool includeSolved) async {
    var lo = pack.rowLo;
    var hi = pack.rowHi;
    if (lo == null || hi == null) {
      final rows = await _db.rawQuery(
        'SELECT MIN(rowid) AS lo, MAX(rowid) AS hi FROM $kSynPuzzleTable WHERE pack_id = ?',
        <Object?>[pack.packId],
      );
      final a = rows.isEmpty ? null : rows.first['lo'];
      final b = rows.isEmpty ? null : rows.first['hi'];
      if (a is int && b is int) {
        lo = a;
        hi = b;
      }
    }
    final baseClauses = <String>['pack_id = ?', if (!includeSolved) 'solved = 0'];
    final baseArgs = <Object?>[pack.packId];

    if (lo != null && hi != null) {
      final plan = _PickPlan(
        db: _db,
        table: kSynPuzzleTable,
        select: _ingestSelect,
        baseClauses: baseClauses,
        baseArgs: baseArgs,
        ratingCol: 'rating',
        themesCol: 'themes',
        lo: lo,
        hi: hi,
        toRecord: _ingestedRowToRecord,
      );
      final hit = await _pickRandom(plan, filter, (_) => true);
      if (hit != null) return hit;
    }

    // Exact (but O(pack size)) last resort.
    final fc = filter.clauses(ratingCol: 'rating', themesCol: 'themes');
    final rows = await _db.rawQuery(
      'SELECT $_ingestSelect FROM $kSynPuzzleTable WHERE ${<String>[...baseClauses, ...fc.$1].join(' AND ')} '
      'ORDER BY RANDOM() LIMIT 1',
      <Object?>[...baseArgs, ...fc.$2],
    );
    for (final row in rows) {
      final rec = _ingestedRowToRecord(row);
      if (rec != null) return rec;
    }
    return null;
  }

  Future<SynPuzzleRecord?> _pickRandom(
    _PickPlan plan,
    _Filter filter,
    bool Function(SynPuzzleRecord) accept,
  ) async {
    final span = plan.hi - plan.lo + 1;
    if (span <= 0) return null;
    final fc = filter.clauses(ratingCol: plan.ratingCol, themesCol: plan.themesCol);
    final clauses = <String>[...plan.baseClauses, ...fc.$1];
    final args = <Object?>[...plan.baseArgs, ...fc.$2];

    String sql(List<String> pre, String suffix) {
      final all = <String>[...pre, ...clauses];
      return 'SELECT ${plan.select} FROM ${plan.table}'
          '${all.isEmpty ? '' : ' WHERE ${all.join(' AND ')}'}$suffix';
    }

    // Phase 1: random rowid probes.
    final width = span < _kProbeWidth ? span : _kProbeWidth;
    for (var round = 0; round < _kProbeRounds; round++) {
      final picks = <int>{};
      while (picks.length < width) {
        picks.add(plan.lo + _rng.nextInt(span));
      }
      final marks = List<String>.filled(picks.length, '?').join(',');
      final rows = await plan.db.rawQuery(
        sql(<String>['rowid IN ($marks)'], ''),
        <Object?>[...picks, ...args],
      );
      final hit = _firstAccepted(rows, plan.toRecord, accept);
      if (hit != null) return hit;
      if (span <= width) break; // every rowid has been tested
    }

    // Phase 2: indexed rowid range scan from a random pivot, wrapping around.
    final pivot = plan.lo + _rng.nextInt(span);
    var pagesLeft = _kScanMaxPages;
    for (var segment = 0; segment < 2; segment++) {
      var cursor = segment == 0 ? pivot : plan.lo;
      final limitExclusive = segment == 0 ? plan.hi + 1 : pivot;
      while (cursor < limitExclusive && pagesLeft > 0) {
        pagesLeft--;
        final rows = await plan.db.rawQuery(
          sql(<String>['rowid >= ? AND rowid < ?'], ' ORDER BY rowid LIMIT $_kScanPageSize'),
          <Object?>[cursor, limitExclusive, ...args],
        );
        if (rows.isEmpty) break;
        final hit = _firstAccepted(rows, plan.toRecord, accept);
        if (hit != null) return hit;
        final last = rows.last['__rid'];
        if (last is! int || rows.length < _kScanPageSize) break;
        cursor = last + 1;
      }
    }
    return null;
  }

  SynPuzzleRecord? _firstAccepted(
    List<Map<String, Object?>> rows,
    SynPuzzleRecord? Function(Map<String, Object?>) toRecord,
    bool Function(SynPuzzleRecord) accept,
  ) {
    if (rows.isEmpty) return null;
    final start = _rng.nextInt(rows.length);
    for (var i = 0; i < rows.length; i++) {
      final rec = toRecord(rows[(start + i) % rows.length]);
      if (rec != null && accept(rec)) return rec;
    }
    return null;
  }

  SynPuzzleRecord? _ingestedRowToRecord(Map<String, Object?> row) {
    try {
      return SynPuzzleRecord.fromMap(row);
    } catch (_) {
      return null;
    }
  }

  /// Raw external row -> canonical Lichess-format record (SAN->UCI, convention fix).
  SynPuzzleRecord? _mountedRowToRecord(Map<String, Object?> r, SynSqliteSchema schema) {
    final fen = r['__fen']?.toString().trim() ?? '';
    final moves = SynMoveTokens.fromObject(r['__moves']);
    if (fen.isEmpty || moves.isEmpty) return null;
    try {
      final n = SynMoveNormalizer.normalize(
        fen: fen,
        moves: moves,
        prior: SynFirstMovePolicy.opponentSetupFirst,
        synthesizeSetupMove: options.synthesizeSetupMove,
      );
      final rawId = schema.idColumn == null ? null : r['__id']?.toString().trim();
      return SynPuzzleRecord(
        id: (rawId != null && rawId.isNotEmpty) ? rawId : SynIds.derive(n.fen, n.uciMoves),
        fen: n.fen,
        moves: n.uciMoves,
        rating: _intOr(r['__rating'], options.defaultRating),
        themes: _themesOr(r['__themes'], options.defaultThemes),
      );
    } on SynNormalizeException {
      return null;
    }
  }

  /// Closes every open mounted database. Call when the repository is discarded.
  Future<void> dispose() async {
    final handles = _mounts.values.toList();
    _mounts.clear();
    for (final h in handles) {
      await h.close();
    }
  }
}

// ---------------------------------------------------------------------------
// Pure-Dart tactical hint engine
// ---------------------------------------------------------------------------

class _LineFacts {
  const _LineFacts({
    required this.player,
    required this.promotion,
    required this.mateAtEnd,
    required this.sacrifice,
    required this.netValue,
    required this.biggestWon,
    required this.firstPiece,
    required this.firstTarget,
  });

  final Side player;

  /// Best promotion piece in the player's line: q, r, n or b (null if none).
  final String? promotion;
  final bool mateAtEnd;
  final bool sacrifice;

  /// Opponent material lost minus player material lost over the solution line.
  final int netValue;

  /// Most valuable opponent piece type captured (q/r/b/n/p), if any.
  final String? biggestWon;
  final String firstPiece;
  final String firstTarget;

  String get sideName => player == Side.white ? 'White' : 'Black';
}

class SynTacticalHintEngine {
  const SynTacticalHintEngine._();

  static final RegExp _mateTheme = RegExp(r'^mateIn([1-5])$');
  static const List<String> _numberWords = <String>['one', 'two', 'three', 'four', 'five'];
  static const Map<String, int> _values = <String, int>{'p': 1, 'n': 3, 'b': 3, 'r': 5, 'q': 9};
  static const Map<String, String> _pieceNames = <String, String>{
    'p': 'pawn',
    'n': 'knight',
    'b': 'bishop',
    'r': 'rook',
    'q': 'queen',
    'k': 'king',
  };

  /// Hint text for [puzzle]. [level] 1 = tactical flavour only, 2 = also names
  /// the piece that moves first, 3 = also names its destination square.
  static String hint(SynPuzzleRecord puzzle, {int level = 1}) {
    final facts = _analyze(puzzle);
    var text = _baseHint(puzzle, facts);
    if (facts != null && level >= 2) {
      final piece = _pieceNames[facts.firstPiece];
      if (piece != null) {
        text += level >= 3
            ? ' Start with your $piece and aim for ${facts.firstTarget}.'
            : ' Start with your $piece.';
      }
    }
    return text;
  }

  // ----- hint wording -------------------------------------------------------

  static String _baseHint(SynPuzzleRecord puzzle, _LineFacts? facts) {
    final side = facts?.sideName ?? 'You';

    for (final theme in puzzle.themeList) {
      final m = _mateTheme.firstMatch(theme);
      if (m != null) return _mateHint(int.parse(m[1]!), puzzle.id, side);
    }
    if (facts == null) return _themeOrGeneric(puzzle, side);

    if (facts.mateAtEnd) {
      return _pick(<String>[
        '$side is heading for checkmate. Start with forcing moves — checks first, then threats.',
        'This line ends with the enemy king trapped. Which forcing move starts the net?',
      ], puzzle.id);
    }

    final promo = facts.promotion;
    if (promo != null) {
      switch (promo) {
        case 'q':
          return _pick(<String>[
            '$side is racing a pawn to the last rank — the new queen decides everything.',
            'A pawn on the brink is the key. Clear its path or drag the defenders away.',
          ], puzzle.id);
        case 'r':
          return 'Do not reach for the queen on reflex — a rook promotion is stronger here.';
        case 'n':
          return 'Promote, but not to a queen: a knight does something a queen cannot.';
        default:
          return 'Promote, but think twice before choosing a queen — a minor piece is the better answer.';
      }
    }

    if (facts.sacrifice) {
      return _pick(<String>[
        '$side must give something up first — the sacrifice pays back with interest.',
        'Material will dip before it returns. Find the offer your opponent cannot refuse.',
      ], puzzle.id);
    }

    if (facts.netValue > 0 && facts.biggestWon != null) {
      switch (facts.biggestWon) {
        case 'q':
          return _pick(<String>[
            'Their queen is not as safe as it looks — find the move that wins it.',
            'The enemy queen is the target. Look for a fork, a pin or a trap.',
          ], puzzle.id);
        case 'r':
          return _pick(<String>[
            'A rook is vulnerable. Look for a fork, pin or skewer that wins it.',
            'One of their rooks cannot be saved. Which move makes that unavoidable?',
          ], puzzle.id);
        case 'b':
        case 'n':
          return _pick(<String>[
            'A minor piece can be won by force. Which one is loose, pinned or trapped?',
            'Count their defenders: one of their knights or bishops is overloaded.',
          ], puzzle.id);
        default:
          return _pick(<String>[
            '$side wins a pawn — but only if the move order is exact.',
            'There is material to grab. Check what each capture leaves undefended.',
          ], puzzle.id);
      }
    }
    return _themeOrGeneric(puzzle, side);
  }

  static String _mateHint(int n, String id, String side) {
    final w = _numberWords[n - 1];
    final cap = '${w[0].toUpperCase()}${w.substring(1)}';
    final List<String> options;
    if (n == 1) {
      options = <String>[
        '$side has a checkmate in one. Scan every check — one of them leaves the king nowhere to run.',
        'The finish is a single move away. Which check seals every escape square?',
        'Mate in one is on the board. Count the checks and test each flight square.',
      ];
    } else if (n == 2) {
      options = <String>[
        'A forced mate in two. Begin with a forcing move that leaves only one reply.',
        'Two moves to checkmate. Find the check or threat that removes all of their choices.',
        '$side mates in two — drive the king toward the net that is already waiting.',
      ];
    } else {
      options = <String>[
        'A forced mate in $w. Think in checks and threats: every move must leave the defender one answer.',
        '$cap moves to checkmate. Which forcing move takes away the most room from the king?',
        'The king will not survive $w moves — hunt it with checks, and look for a quiet move that tightens the net.',
      ];
    }
    return _pick(options, id);
  }

  static const Map<String, String> _themeHints = <String, String>{
    'fork': 'Look for a single move that attacks two things at once.',
    'pin': 'A pinned piece cannot move freely — find what it is guarding.',
    'skewer': 'Attack the more valuable piece first and watch what stands behind it.',
    'discoveredAttack': 'Moving one piece can unleash another. What is hiding behind your piece?',
    'doubleCheck': 'Two checks at once — only a king move can answer.',
    'backRankMate': 'Their back rank is cramped. Can a rook or queen exploit it?',
    'hangingPiece': 'Something is undefended. Which piece has no protector?',
    'trappedPiece': 'A piece has almost no safe squares left — keep it that way.',
    'deflection': 'One defender has too many jobs. Pull it away.',
    'attraction': 'Lure a key piece onto a square where it can be hit.',
    'quietMove': 'The key move may not be a check or a capture. Look for a quiet move with a big threat.',
    'zugzwang': 'Sometimes the best move is the one that forces them to move.',
    'xRayAttack': 'Look through the first piece — what is behind it on the same line?',
    'interference': 'Cut the line between two defenders by landing a piece between them.',
    'clearance': 'Get your own piece out of the way and let the line open up.',
    'exposedKing': 'The enemy king has no cover. Bring more attackers.',
    'smotheredMate': 'A king boxed in by its own pieces is a gift for a knight.',
    'capturingDefender': 'Remove the guard, then take what it was guarding.',
    'intermezzo': 'Before the obvious recapture, is there an in-between move that hurts more?',
    'advancedPawn': 'That advanced pawn is closer to the goal than it looks.',
  };

  static String _themeOrGeneric(SynPuzzleRecord puzzle, String side) {
    for (final t in puzzle.themeList) {
      final h = _themeHints[t];
      if (h != null) return h;
    }
    return '$side to play: look at checks, captures and threats — in that order.';
  }

  static String _pick(List<String> options, String id) {
    final h = int.parse(SynIds.fnvHex(id).substring(8), radix: 16);
    return options[h % options.length];
  }

  // ----- line analysis ------------------------------------------------------

  /// Replays [puzzle] on a dartchess Position: plays the opponent's setup move
  /// (moves[0]) and then the player's solution line, comparing piece counts
  /// before and after. Null if the line cannot be replayed.
  static _LineFacts? _analyze(SynPuzzleRecord puzzle) {
    final moves = puzzle.moveList;
    if (moves.length < 2) return null;
    try {
      Position pos = Chess.fromSetup(Setup.parseFen(puzzle.fen));
      pos = pos.play(_toMove(pos, moves[0]));
      final player = pos.turn;
      final sign = player == Side.white ? 1 : -1;
      final startBoard = pos.fen.split(' ').first;
      final startBalance = sign * SynFenTools.materialBalance(pos.fen);
      final firstPiece = _pieceAt(pos.fen, moves[1].substring(0, 2)).toLowerCase();
      final firstTarget = moves[1].substring(2, 4);

      var minRelative = 0;
      var promoCount = 0;
      String? promotion;
      for (var i = 1; i < moves.length; i++) {
        final uci = moves[i];
        if (i.isOdd && uci.length == 5) {
          promoCount++;
          promotion = _betterPromotion(promotion, uci[4].toLowerCase());
        }
        pos = pos.play(_toMove(pos, uci));
        if (i.isEven) {
          final relative = sign * SynFenTools.materialBalance(pos.fen) - startBalance;
          if (relative < minRelative) minRelative = relative;
        }
      }
      final endRelative = sign * SynFenTools.materialBalance(pos.fen) - startBalance;
      final before = _count(startBoard);
      final after = _count(pos.fen.split(' ').first);
      final playerWhite = player == Side.white;

      int lost(bool white, String type) {
        final key = white ? type.toUpperCase() : type;
        final d = (before[key] ?? 0) - (after[key] ?? 0);
        return d < 0 ? 0 : d;
      }

      var oppLossValue = 0;
      var playerLossValue = 0;
      String? biggest;
      for (final type in const <String>['q', 'r', 'b', 'n', 'p']) {
        final oppLost = lost(!playerWhite, type);
        var myLost = lost(playerWhite, type);
        if (type == 'p') myLost = myLost > promoCount ? myLost - promoCount : 0; // promotions are not losses
        oppLossValue += oppLost * _values[type]!;
        playerLossValue += myLost * _values[type]!;
        if (oppLost > 0 && biggest == null) biggest = type; // q first => most valuable
      }
      final mate = pos.isCheckmate;
      return _LineFacts(
        player: player,
        promotion: promotion,
        mateAtEnd: mate,
        sacrifice: minRelative <= -2 && (endRelative > minRelative || mate),
        netValue: oppLossValue - playerLossValue,
        biggestWon: biggest,
        firstPiece: firstPiece,
        firstTarget: firstTarget,
      );
    } catch (_) {
      return null;
    }
  }

  static String? _betterPromotion(String? current, String next) {
    const order = 'qrnb';
    if (current == null) return next;
    final a = order.indexOf(current);
    final b = order.indexOf(next);
    if (b < 0) return current;
    if (a < 0) return next;
    return b < a ? next : current;
  }

  static Map<String, int> _count(String board) {
    final m = <String, int>{};
    for (final ch in board.split('')) {
      if ('pnbrqkPNBRQK'.contains(ch)) m[ch] = (m[ch] ?? 0) + 1;
    }
    return m;
  }

  /// FEN piece letter on [square] ('' if empty).
  static String _pieceAt(String fen, String square) {
    final rows = fen.split(' ').first.split('/');
    final row = 8 - int.parse(square[1]);
    final file = square.codeUnitAt(0) - 97;
    var col = 0;
    for (final ch in rows[row].split('')) {
      final d = int.tryParse(ch);
      if (d != null) {
        col += d;
        if (col > file) return '';
      } else {
        if (col == file) return ch;
        col++;
      }
    }
    return '';
  }

  /// Standard UCI (e1g1) -> dartchess move (king takes rook for castling).
  static Move _toMove(Position pos, String uci) {
    var u = uci.toLowerCase();
    if (u.length == 4) {
      final piece = _pieceAt(pos.fen, u.substring(0, 2));
      final fromFile = u.codeUnitAt(0) - 97;
      final toFile = u.codeUnitAt(2) - 97;
      if ((piece == 'K' || piece == 'k') && u[1] == u[3] && (toFile - fromFile).abs() == 2) {
        u = '${u.substring(0, 2)}${toFile > fromFile ? 'h' : 'a'}${u[1]}';
      }
    }
    final move = Move.parse(u);
    if (move == null) throw FormatException('Unparseable move "$uci"');
    return move;
  }
}
