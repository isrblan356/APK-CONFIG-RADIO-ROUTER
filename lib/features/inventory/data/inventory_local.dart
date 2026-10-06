import 'dart:async';
import 'dart:io';
import 'package:dartz/dartz.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';
import '../../../core/config/app_config.dart';
import '../../../core/config/device_registry.dart';
import '../../../core/error/failures.dart';
import '../domain/entities.dart';
import '../domain/inventory_repository.dart';
import 'cloud_payload.dart';

/// Inventario local (port de nodos/nodos.db). La DB vive en el móvil.
///
/// Primer arranque: se copia assets/seed/nodos.db (8 zonas + 259 APs reales)
/// al directorio de bases de datos de Android. Si el asset falta, se crea el
/// esquema con zonas mínimas (modo desarrollo/test).
/// Si CLOUD_ENDPOINT está definido y cloudEnabled, se sincroniza desde nube.
class InventoryLocal implements InventoryRepository {
  static const seedAsset = 'assets/seed/nodos.db';

  final http.Client cloud;
  final bool cloudEnabled;
  final String endpoint;
  Database? _db;

  InventoryLocal(this.cloud,
      {this.cloudEnabled = AppConfig.cloudEnabledDefault, String? endpoint})
      : endpoint = endpoint ?? AppConfig.cloudEndpoint;

  Future<void> _installSeed(String path) async {
    if (await File(path).exists()) return;
    try {
      final data = await rootBundle.load(seedAsset);
      await File(path).writeAsBytes(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
          flush: true);
    } catch (_) {
      // Sin asset (tests / build sin seed): _ensureSchema crea esquema + zonas mínimas.
    }
  }

  Future<void> _insertFallbackZones(DatabaseExecutor db) async {
    const fallback = [
      ['Girardota', '192.168.80.'],
      ['Medellín', '192.168.50.'],
      ['Guarne', '192.168.60.'],
      ['Caldas', '192.168.100.'],
    ];
    for (final z in fallback) {
      await db.insert('zona', {'zona': z[0], 'network': z[1]});
    }
  }

  Future<Database> _open() async {
    if (_db != null) return _db!;
    final dir = await getDatabasesPath();
    final path = p.join(dir, 'nodos.db');
    await _installSeed(path);
    Database db;
    try {
      // Sin version: así sqflite no ejecuta onCreate sobre el seed copiado
      // (que ya trae sus propias tablas) y el control queda en _ensureSchema.
      db = await openDatabase(path);
    } catch (_) {
      // Archivo corrupto/incompatible: se rehace desde el seed (una sola vez).
      try {
        await File(path).delete();
      } catch (_) {
        // Si no se pudo borrar, el siguiente open lanza y zones() reporta error.
      }
      await _installSeed(path);
      db = await openDatabase(path);
    }
    await _ensureSchema(db);
    _db = db;
    return db;
  }

  Future<void> _ensureSchema(Database db) async {
    final rows = await db
        .rawQuery("SELECT name FROM sqlite_master WHERE type = 'table'");
    final tables =
        rows.map((r) => (r['name'] ?? '').toString()).toSet();
    if (!tables.contains('zona')) {
      await db.execute(
          'CREATE TABLE zona(id INTEGER PRIMARY KEY AUTOINCREMENT, zona TEXT, network TEXT)');
    }
    if (!tables.contains('accesspoints')) {
      await db.execute(
          'CREATE TABLE accesspoints(idzona TEXT, idnodo INTEGER, nodo TEXT, ssid TEXT)');
    }
    final count = await db.rawQuery('SELECT COUNT(*) AS n FROM zona');
    if ((Sqflite.firstIntValue(count) ?? 0) == 0) {
      await _insertFallbackZones(db);
    }
  }

  // Solo para tests / precarga manual.
  Future<void> seedZone(Zone z) async {
    final db = await _open();
    await db.insert('zona', {'id': z.id, 'zona': z.name, 'network': z.network},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<Either<Failure, List<Zone>>> zones() async {
    try {
      final db = await _open();
      final rows = await db.query('zona', orderBy: 'id');
      return Right(rows
          .map((r) => Zone(
              id: (r['id'] as int),
              name: (r['zona'] ?? '').toString(),
              network: (r['network'] ?? '').toString()))
          .toList());
    } catch (e) {
      return Left(CacheFailure('No se pudo leer zonas: $e'));
    }
  }

  @override
  Future<Either<Failure, List<AccessPoint>>> aps(String zoneId) async {
    try {
      final db = await _open();
      final rows = await db.query('accesspoints',
          where: 'idzona = ?', whereArgs: [zoneId], orderBy: 'idnodo');
      return Right(rows
          .map((r) => AccessPoint(
              zoneId: (r['idzona'] ?? '').toString(),
              nodeId: (r['idnodo'] as int? ?? 0),
              name: (r['nodo'] ?? '').toString(),
              ssid: (r['ssid'] ?? '').toString()))
          .toList());
    } catch (e) {
      return Left(CacheFailure('No se pudo leer APs: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> syncFromCloud() async {
    if (!cloudEnabled || endpoint.isEmpty) {
      return const Right(null); // 100% local, nada que hacer
    }
    unawaited(DeviceRegistry.reportar(cloud)); // quién sincroniza (best-effort)
    final ep = endpoint.replaceAll(RegExp(r'/+$'), '');
    try {
      final zRes = await cloud.get(Uri.parse('$ep/zones'));
      if (zRes.statusCode != 200) {
        return Left(
            ConnectionFailure('Nube /zones respondió ${zRes.statusCode}'));
      }
      final zones = CloudPayload.parseZones(zRes.body);
      // Sin zonas válidas no se toca nada: nunca se borra lo local por error.
      if (zones.isEmpty) return const Right(null);

      final apsByZone = <String, List<AccessPoint>>{};
      for (final z in zones) {
        try {
          final aRes = await cloud.get(Uri.parse('$ep/aps?zona=${z.id}'));
          if (aRes.statusCode != 200) continue;
          final aps =
              CloudPayload.parseAps(aRes.body, zoneIdFallback: z.id.toString());
          if (aps.isNotEmpty) apsByZone[z.id.toString()] = aps;
        } catch (_) {
          // Zona sin APs de la nube: conserva los locales.
        }
      }

      final db = await _open();
      await db.transaction((txn) async {
        await txn.delete('zona');
        for (final z in zones) {
          await txn.insert('zona',
              {'id': z.id, 'zona': z.name, 'network': z.network},
              conflictAlgorithm: ConflictAlgorithm.replace);
        }
        // APs: solo se reemplazan las zonas que vinieron completas.
        for (final e in apsByZone.entries) {
          await txn.delete('accesspoints',
              where: 'idzona = ?', whereArgs: [e.key]);
          for (final a in e.value) {
            await txn.insert('accesspoints', {
              'idzona': a.zoneId,
              'idnodo': a.nodeId,
              'nodo': a.name,
              'ssid': a.ssid
            });
          }
        }
        // Limpieza de zonas eliminadas solo si TODAS llegaron con APs:
        // así un fallo parcial nunca deja huérfanos... ni borra datos buenos.
        if (apsByZone.length == zones.length) {
          final keep = zones.map((z) => z.id.toString()).toList();
          await txn.delete(
              'accesspoints',
              where:
                  'idzona NOT IN (${List.filled(keep.length, '?').join(',')})',
              whereArgs: keep);
        }
      });
      return const Right(null);
    } catch (e) {
      return Left(ConnectionFailure('Sync nube falló (sigo offline): $e'));
    }
  }
}
