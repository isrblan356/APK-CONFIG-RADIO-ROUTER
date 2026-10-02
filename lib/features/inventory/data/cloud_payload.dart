import 'dart:convert';
import '../domain/entities.dart';

/// Parser puro de la respuesta de la nube (sin Flutter, sin red) -> testeable.
///
/// Contrato mínimo (ver README §3):
///   GET $CLOUD_ENDPOINT/zones       -> [{"id":1,"zona":"Girardota","network":"192.168.80."}]
///   GET $CLOUD_ENDPOINT/aps?zona=1  -> [{"idzona":"1","idnodo":1,"nodo":"La Palma - AP1","ssid":"rinku_ap1_lapalma"}]
///
/// Tolera envoltorios ({"zones":[...]}, {"data":[...]}) y alias de claves,
/// porque el backend puede ser PHP, Firebase Functions o lo que sea.
class CloudPayload {
  CloudPayload._();

  static const zoneKeys = ['zones', 'data', 'items', 'rows'];
  static const apKeys = ['aps', 'accesspoints', 'data', 'items', 'rows'];

  static List<Map<String, dynamic>> rows(dynamic body, List<String> keys) {
    dynamic decoded;
    try {
      decoded = json.decode(body as String);
    } catch (_) {
      return const [];
    }
    if (decoded is List) return decoded.whereType<Map>().map(_map).toList();
    if (decoded is Map) {
      for (final k in keys) {
        final v = decoded[k];
        if (v is List) return v.whereType<Map>().map(_map).toList();
      }
    }
    return const [];
  }

  static Map<String, dynamic> _map(dynamic m) => Map<String, dynamic>.from(m);

  static int? _int(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v is int) return v;
      if (v is num) return v.toInt();
      final s = v?.toString().trim();
      if (s != null && s.isNotEmpty) {
        final n = int.tryParse(s);
        if (n != null) return n;
      }
    }
    return null;
  }

  static String _str(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  /// Normaliza a base de red tipo "192.168.80." (como tu nodos.db).
  static String networkBase(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return '';
    if (s.endsWith('.')) return s;
    if (s.endsWith('.0')) return s.substring(0, s.length - 1);
    return '$s.';
  }

  static List<Zone> parseZones(String body) {
    final out = <Zone>[];
    for (final r in rows(body, zoneKeys)) {
      final id = _int(r, ['id', 'idzona', 'zoneId', 'zone_id']);
      final name = _str(r, ['zona', 'name', 'zone', 'title']);
      final network = networkBase(_str(r, ['network', 'net', 'subnet']));
      if (id == null || name.isEmpty || network.isEmpty) continue;
      final z = Zone(id: id, name: name, network: network);
      if (!out.contains(z)) out.add(z);
    }
    return out;
  }

  static List<AccessPoint> parseAps(String body, {String? zoneIdFallback}) {
    final out = <AccessPoint>[];
    for (final r in rows(body, apKeys)) {
      // idzona solo puede venir como id: si viniera el nombre de la zona,
      // rompería el join con la tabla zona, así que se ignora y se usa el fallback.
      final zoneIdRaw =
          _str(r, ['idzona', 'zoneId', 'zone_id', 'idZone', 'id_zona']);
      final zoneId = zoneIdRaw.isNotEmpty ? zoneIdRaw : (zoneIdFallback ?? '');
      final nodeId = _int(r, ['idnodo', 'nodeId', 'id']) ?? 0;
      final name = _str(r, ['nodo', 'name', 'ap', 'hostname']);
      final ssid = _str(r, ['ssid', 'SSID']);
      if (zoneId.isEmpty || name.isEmpty || ssid.isEmpty) continue;
      final ap =
          AccessPoint(zoneId: zoneId, nodeId: nodeId, name: name, ssid: ssid);
      if (!out.contains(ap)) out.add(ap);
    }
    return out;
  }
}
