import 'package:dartz/dartz.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../../../core/config/app_config.dart';
import '../../../core/error/failures.dart';
import '../domain/ar_node.dart';
import 'ar_node_sync.dart';
import 'ar_nodes_cloud.dart';

/// Nodos con coordenadas, guardados en el móvil (DB propia ar_nodes.db).
/// CRUD local + sync opcional desde GET $endpoint/nodes.
///
/// [factory], [dbPath] y [endpoint] son inyectables para poder probar sin
/// emulador ni depender del String.fromEnvironment.
class ArNodeStore {
  final http.Client cloud;
  final bool cloudEnabled;
  final String endpoint;
  final DatabaseFactory? factory;
  final String? dbPath;

  Database? _db;

  ArNodeStore(
    this.cloud, {
    this.cloudEnabled = AppConfig.cloudEnabledDefault,
    String? endpoint,
    this.factory,
    this.dbPath,
  }) : endpoint = endpoint ?? AppConfig.cloudEndpoint;

  Future<Database> _open() async {
    if (_db != null) return _db!;
    final path = dbPath ?? p.join(await getDatabasesPath(), 'ar_nodes.db');
    final db = await (factory ?? databaseFactory).openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) => db.execute('CREATE TABLE ar_nodes('
            'local_id INTEGER PRIMARY KEY AUTOINCREMENT,'
            'remoto_id INTEGER,'
            'nombre TEXT NOT NULL,'
            'lat REAL NOT NULL,'
            'lng REAL NOT NULL,'
            'alt REAL,'
            "zona TEXT, origen TEXT NOT NULL DEFAULT 'manual')"),
      ),
    );
    _db = db;
    return db;
  }

  ArNode _row(Map<String, Object?> r) => ArNode(
        localId: (r['local_id'] as num?)?.toInt() ?? 0,
        remotoId: (r['remoto_id'] as num?)?.toInt(),
        nombre: (r['nombre'] ?? '').toString(),
        lat: (r['lat'] as num?)?.toDouble() ?? 0,
        lng: (r['lng'] as num?)?.toDouble() ?? 0,
        alt: (r['alt'] as num?)?.toDouble(),
        zona: (r['zona'] ?? '').toString(),
        origen: (r['origen'] ?? 'manual').toString(),
      );

  Future<List<ArNode>> list() async {
    final db = await _open();
    final rows = await db.query('ar_nodes', orderBy: 'nombre COLLATE NOCASE');
    return rows.map(_row).toList();
  }

  Future<int> addManual({
    required String nombre,
    required double lat,
    required double lng,
    double? alt,
    String zona = '',
  }) async {
    final db = await _open();
    return db.insert('ar_nodes', {
      'nombre': nombre,
      'lat': lat,
      'lng': lng,
      'alt': alt,
      'zona': zona,
      'origen': 'manual',
    });
  }

  Future<void> remove(int localId) async {
    final db = await _open();
    await db.delete('ar_nodes', where: 'local_id = ?', whereArgs: [localId]);
  }

  /// Descarga /nodes y reemplaza solo los de origen nube.
  /// Nunca borra nodos manuales; respuesta vacía = no se toca nada.
  Future<Either<Failure, String>> syncFromCloud() async {
    if (!cloudEnabled || endpoint.isEmpty) {
      return const Right('Nube no configurada: quedan solo los nodos locales.');
    }
    final ep = endpoint.replaceAll(RegExp(r'/+$'), '');
    try {
      final res = await cloud.get(Uri.parse('$ep/nodes'));
      if (res.statusCode != 200) {
        return Left(ConnectionFailure('Nube /nodes respondió ${res.statusCode}'));
      }
      final nube = ArNodesCloud.parse(res.body);
      // Sin nodos válidos no se toca nada: nunca se borra lo local por error.
      if (nube.isEmpty) {
        return const Right('Nube sin nodos válidos: no se modificó nada.');
      }
      final local = await list();
      final plan = ArNodeSync.plan(local, nube);
      final db = await _open();
      await db.transaction((txn) async {
        await txn.delete('ar_nodes', where: "origen = 'nube'");
        for (final n in plan.insertar) {
          await txn.insert('ar_nodes', {
            'remoto_id': n.remotoId,
            'nombre': n.nombre,
            'lat': n.lat,
            'lng': n.lng,
            'alt': n.alt,
            'zona': n.zona,
            'origen': 'nube',
          });
        }
      });
      final manuales =
          plan.conservar.where((n) => n.origen == 'manual').length;
      return Right('${nube.length} nodos desde la nube '
          '($manuales manuales conservados)');
    } catch (e) {
      return Left(ConnectionFailure('Sync nube falló (sigo offline): $e'));
    }
  }
}
