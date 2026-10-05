import 'dart:convert';
import 'dart:io';

import 'package:wisp_configurator/features/ar_compass/data/ar_nodes_cloud.dart';
import 'package:wisp_configurator/features/inventory/data/cloud_payload.dart';

/// Verificación end-to-end del servidor PHP contra los parsers REALES de la
/// APK (los mismos que usa la app en producción).
///
/// Uso:
///   php -S 0.0.0.0:8080 -t server/public     (en otra terminal)
///   dart run tool/verify_server.dart [http://127.0.0.1:8080]
Future<void> main(List<String> args) async {
  final base = (args.isNotEmpty ? args.first : 'http://127.0.0.1:8080')
      .replaceFirst(RegExp(r'/$'), '');
  final client = HttpClient();
  client.connectionTimeout = const Duration(seconds: 5);
  var fails = 0;

  Future<void> check(String name, bool ok, String detail) async {
    stdout.writeln('${ok ? 'OK  ' : 'FALLA'}  $name — $detail');
    if (!ok) fails++;
  }

  Future<Map<String, Object?>> send(
    String method,
    String path, {
    Object? body,
  }) async {
    final req = await client.openUrl(method, Uri.parse(base + path));
    req.headers.contentType = ContentType.json;
    if (body != null) req.write(jsonEncode(body));
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      decoded = text;
    }
    return {
      'code': res.statusCode,
      'body': text,
      'json': decoded,
    };
  }

  try {
    // 1) salud
    final h = await send('GET', '/health');
    final ok = h['code'] == 200 &&
        (h['json'] is Map) &&
        (h['json'] as Map)['ok'] == true;
    await check('GET /health', ok, 'code=${h['code']} ${h['body']}');
    if (!ok) {
      stderr.writeln('\nEl servidor no responde en $base — ¿lo levantaste?');
      exit(1);
    }

    // 2) zonas con el parser real de la APK
    final z = await send('GET', '/zones');
    final zones = CloudPayload.parseZones(z['body'] as String);
    await check(
      'GET /zones -> CloudPayload.parseZones',
      z['code'] == 200 && zones.isNotEmpty,
      '${zones.length} zonas, primera=${zones.isEmpty ? "-" : zones.first.name}',
    );

    // 3) APs de la primera zona
    if (zones.isNotEmpty) {
      final a = await send('GET', '/aps?zona=${zones.first.id}');
      final aps = CloudPayload.parseAps(
        a['body'] as String,
        zoneIdFallback: '${zones.first.id}',
      );
      await check(
        'GET /aps?zona -> CloudPayload.parseAps',
        a['code'] == 200 && aps.isNotEmpty,
        '${aps.length} APs en "${zones.first.name}"',
      );
    }

    // 4) nodos (GET + parser de la brújula)
    final n0 = await send('GET', '/nodes');
    final before = ArNodesCloud.parse(n0['body'] as String);
    await check(
      'GET /nodes -> ArNodesCloud.parse',
      n0['code'] == 200,
      '${before.length} nodos en la nube',
    );

    // 5) alta con clave estable (mismo contrato que sube la APK)
    const clave = 'verify-tool';
    const nombre = 'Nodo de verificacion';
    final created = await send('POST', '/nodes', body: {
      'clave': clave,
      'nombre': nombre,
      'lat': 6.32,
      'lng': -75.43,
      'alt': 1500,
      'zona': zones.isEmpty ? '' : zones.first.name,
    });
    final row = created['json'] is Map ? created['json'] as Map : const {};
    final id = row['id'];
    await check(
      'POST /nodes (clave estable)',
      (created['code'] == 201 || created['code'] == 200) && id is int,
      'id=$id code=${created['code']}',
    );

    // 6) el mismo POST debe ACTUALIZAR (no duplicar)
    final again = await send('POST', '/nodes', body: {
      'clave': clave,
      'nombre': '$nombre v2',
      'lat': 6.33,
      'lng': -75.44,
    });
    final n1 = await send('GET', '/nodes');
    final rows = ArNodesCloud.parse(n1['body'] as String);
    final dupes = rows.where((r) => r.nombre.startsWith(nombre)).length;
    await check(
      'POST repetido actualiza (sin duplicar)',
      again['code'] == 201 && dupes == 1,
      'apariciones=$dupes code=${again['code']}',
    );

    // 7) borrado
    final del = await send('DELETE', '/nodes?id=$id');
    final n2 = await send('GET', '/nodes');
    final finalRows = ArNodesCloud.parse(n2['body'] as String);
    await check(
      'DELETE /nodes',
      del['code'] == 200 && !finalRows.any((r) => r.nombre.startsWith(nombre)),
      'quedan=${finalRows.length}',
    );

    // 8) validaciones
    final bad = await send('POST', '/nodes', body: {'nombre': ''});
    await check(
      'POST invalido responde 422',
      bad['code'] == 422,
      'code=${bad['code']}',
    );
    final noRoute = await send('GET', '/noexiste');
    await check(
      'ruta desconocida responde 404',
      noRoute['code'] == 404,
      'code=${noRoute['code']}',
    );
  } on SocketException catch (e) {
    stderr.writeln('SIN SERVIDOR: ${e.message} — corre php -S primero');
    exit(1);
  } finally {
    client.close(force: true);
  }

  stdout.writeln(fails == 0 ? '\nTODO OK' : '\n$fails verificaciones fallaron');
  exit(fails == 0 ? 0 : 1);
}
