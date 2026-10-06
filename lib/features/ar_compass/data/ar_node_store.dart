import 'dart:async';
import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../../../core/config/app_config.dart';
import '../../../core/config/device_registry.dart';
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
  /// X-Admin-Token para escribir en el servidor (vacío = sin token).
  final String token;
  final DatabaseFactory? factory;
  final String? dbPath;

  Database? _db;

  ArNodeStore(
    this.cloud, {
    this.cloudEnabled = AppConfig.cloudEnabledDefault,
    String? endpoint,
    this.token = '',
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
    unawaited(DeviceRegistry.reportar(cloud)); // quién sincroniza (best-effort)
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
      // Los que subí yo (manual + remoto_id) no deben volver como "nube":
      // el servidor los devuelve porque los creó, pero aquí ya existen.
      final mios = local
          .where((n) => n.origen == 'manual' && n.remotoId != null)
          .map((n) => n.remotoId)
          .toSet();
      final nuevos = nube
          .where((n) => n.remotoId == null || !mios.contains(n.remotoId))
          .toList();
      if (nuevos.isEmpty) {
        return const Right(
            'Los nodos de la nube ya están en el móvil: nada que bajar.');
      }
      final plan = ArNodeSync.plan(local, nuevos);
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
      return Right('${nuevos.length} nodos desde la nube '
          '($manuales manuales conservados)');
    } catch (e) {
      return Left(ConnectionFailure('Sync nube falló (sigo offline): $e'));
    }
  }

  /// Sube los nodos manuales con clave estable `d<local_id>` (el servidor hace
  /// upsert, así que repetir no duplica) y guarda el id que devuelve.
  Future<Either<Failure, String>> pushToCloud() async {
    if (!cloudEnabled || endpoint.isEmpty) {
      return const Right('Nube no configurada: nada subió.');
    }
    unawaited(DeviceRegistry.reportar(cloud)); // quién sincroniza (best-effort)
    final ep = endpoint.replaceAll(RegExp(r'/+$'), '');
    final db = await _open();
    final rows =
        await db.query('ar_nodes', where: "origen = 'manual'", orderBy: 'local_id');
    if (rows.isEmpty) return const Right('No hay nodos manuales para subir.');

    final headers = <String, String>{
      'Content-Type': 'application/json',
      if (token.isNotEmpty) 'X-Admin-Token': token,
    };
    var ok = 0;
    for (final r in rows) {
      final body = jsonEncode({
        'clave': 'd${r['local_id']}',
        'nombre': r['nombre'],
        'lat': r['lat'],
        'lng': r['lng'],
        'alt': r['alt'],
        'zona': r['zona'] ?? '',
      });
      try {
        final res = await cloud.post(Uri.parse('$ep/nodes'),
            headers: headers, body: body);
        if (res.statusCode != 200 && res.statusCode != 201) {
          return Left(ConnectionFailure(
              'POST /nodes respondió ${res.statusCode}: ${res.body}'));
        }
        Object? decoded;
        try {
          decoded = jsonDecode(res.body);
        } catch (_) {
          decoded = null;
        }
        if (decoded is Map && decoded['id'] is num) {
          await db.update(
            'ar_nodes',
            {'remoto_id': (decoded['id'] as num).toInt()},
            where: 'local_id = ?',
            whereArgs: [r['local_id']],
          );
        }
        ok++;
      } catch (e) {
        return Left(ConnectionFailure('Subida falló tras $ok nodos: $e'));
      }
    }
    return Right('$ok nodos subidos al servidor.');
  }
}
