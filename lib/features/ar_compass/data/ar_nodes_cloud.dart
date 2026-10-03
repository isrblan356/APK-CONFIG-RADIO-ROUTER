import 'dart:convert';
import '../domain/ar_node.dart';

/// Parser puro de la respuesta de la nube (sin Flutter, sin red) -> testeable.
///
/// Contrato:
///   GET $CLOUD_ENDPOINT/nodes ->
///   [{"id":1,"nombre":"Girardota AP12","lat":6.32,"lng":-75.43,
///     "alt":1500,"zona":"Girardota"}]
///
/// Tolera envoltorios ({"nodes":[...]}, {"data":[...]}) y alias de claves
/// (name/label, latitude/y, lon/longitude/x), igual que CloudPayload.
/// Las filas sin nombre o sin coordenadas válidas se descartan.
class ArNodesCloud {
  ArNodesCloud._();

  static const listKeys = ['nodes', 'nodos', 'data', 'items', 'rows'];

  static List<Map<String, dynamic>> rows(Object? body) {
    Object? decoded;
    try {
      decoded = json.decode(body as String);
    } catch (_) {
      return const []; // JSON roto = sin datos (nunca borra lo local)
    }
    if (decoded is List) return decoded.whereType<Map>().map(_map).toList();
    if (decoded is Map) {
      for (final k in listKeys) {
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
      final n = int.tryParse('${v ?? ''}'.trim());
      if (n != null) return n;
    }
    return null;
  }

  /// Latitud/lng pueden venir como número o texto (hasta con coma decimal).
  static double? _num(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v is num) return v.toDouble();
      final s = '${v ?? ''}'.trim().replaceAll(',', '.');
      if (s.isNotEmpty) {
        final n = double.tryParse(s);
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

  static List<ArNode> parse(String body) {
    final out = <ArNode>[];
    for (final r in rows(body)) {
      final nombre = _str(r, ['nombre', 'name', 'label', 'titulo', 'title']);
      final lat = _num(r, ['lat', 'latitude', 'y']);
      final lng = _num(r, ['lng', 'lon', 'long', 'longitude', 'x']);
      if (nombre.isEmpty || lat == null || lng == null) continue;
      if (lat.abs() > 90 || lng.abs() > 180) continue;
      final n = ArNode(
        remotoId: _int(r, ['id', 'idnodo', 'nodeId', 'node_id']),
        nombre: nombre,
        lat: lat,
        lng: lng,
        alt: _num(r, ['alt', 'altitud', 'altitude', 'elevation']),
        zona: _str(r, ['zona', 'zone']),
        origen: 'nube',
      );
      if (!out.contains(n)) out.add(n);
    }
    return out;
  }
}
