import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../domain/entities.dart';
import '../domain/history_repository.dart';

/// Bitácora local en el móvil (auditoría de campo, funciona offline).
class HistoryRepositoryImpl implements HistoryRepository {
  Database? _db;
  Future<Database> _open() async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    _db = await openDatabase(p.join(dir, 'oplog.db'), version: 1,
        onCreate: (db, v) => db.execute(
            'CREATE TABLE oplog(id INTEGER PRIMARY KEY AUTOINCREMENT, kind TEXT, detail TEXT, ok INTEGER, at INTEGER)'));
    return _db!;
  }

  @override
  Future<void> add(String kind, String detail, bool ok) async {
    final db = await _open();
    await db.insert('oplog', {
      'kind': kind,
      'detail': detail.substring(0, detail.length > 2000 ? 2000 : detail.length),
      'ok': ok ? 1 : 0,
      'at': DateTime.now().millisecondsSinceEpoch,
    });
  }

  @override
  Future<List<OpLog>> recent({int limit = 100}) async {
    final db = await _open();
    final rows = await db.query('oplog', orderBy: 'id DESC', limit: limit);
    return rows
        .map((r) => OpLog(
              id: r['id'] as int?,
              kind: (r['kind'] ?? '').toString(),
              detail: (r['detail'] ?? '').toString(),
              ok: (r['ok'] as int? ?? 0) == 1,
              at: DateTime.fromMillisecondsSinceEpoch((r['at'] as int? ?? 0)),
            ))
        .toList();
  }

  @override
  Future<void> clear() async {
    final db = await _open();
    await db.delete('oplog');
  }
}
