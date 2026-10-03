import 'dart:math' as math;

/// Cálculos puros de geodesia y brújula (sin Flutter) -> testeables.
class Geo {
  Geo._();

  static const earthRadiusM = 6371008.8;

  static double _rad(double d) => d * math.pi / 180.0;
  static double _deg(double r) => r * 180.0 / math.pi;

  /// Distancia en metros entre dos puntos (haversine).
  static double distanceM(
      double lat1, double lon1, double lat2, double lon2) {
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    return 2 * earthRadiusM * math.asin(math.min(1, math.sqrt(a)));
  }

  /// Acimut al punto: 0° = norte, gira en sentido horario.
  static double bearing(double lat1, double lon1, double lat2, double lon2) {
    final p1 = _rad(lat1);
    final p2 = _rad(lat2);
    final dLon = _rad(lon2 - lon1);
    final y = math.sin(dLon) * math.cos(p2);
    final x = math.cos(p1) * math.sin(p2) -
        math.sin(p1) * math.cos(p2) * math.cos(dLon);
    return normalize360(_deg(math.atan2(y, x)));
  }

  static double normalize360(double d) {
    var v = d % 360.0;
    if (v < 0) v += 360.0;
    return v;
  }

  /// Diferencia "destino - rumbo" en [-180, 180).
  /// Negativo = el destino queda a la izquierda.
  static double delta(double target, double heading) {
    final d = normalize360(target - heading);
    return d >= 180 ? d - 360 : d;
  }

  /// Rumbo de la vista de la cámara a partir del acelerómetro (gravedad) y
  /// el magnetómetro, en el marco del dispositivo (x derecha, y arriba,
  /// z hacia el usuario = fuera de la pantalla). La cámara mira en -z.
  ///
  /// Teléfono acostado (plano): -z apunta al cielo, así que se usa el borde
  /// superior (+y), que sí está en el plano horizontal.
  /// Devuelve null si los sensores no tienen señal.
  static double? headingFromSensors({
    required double ax,
    required double ay,
    required double az,
    required double mx,
    required double my,
    required double mz,
  }) {
    final up = _unit(ax, ay, az);
    if (up == null) return null;
    // Este = M x up (quita el componente vertical de M), Norte = up x Este.
    final e = _cross(mx, my, mz, up.$1, up.$2, up.$3);
    final east = _unit(e.$1, e.$2, e.$3);
    if (east == null) return null;
    final n = _cross(up.$1, up.$2, up.$3, east.$1, east.$2, east.$3);
    final north = _unit(n.$1, n.$2, n.$3);
    if (north == null) return null;

    // f = -z (vista de la cámara); proyectada al plano horizontal.
    final vx = -east.$3;
    final vy = -north.$3;
    final viewLen = math.sqrt(vx * vx + vy * vy);
    if (viewLen >= 0.35) return normalize360(_deg(math.atan2(vx, vy)));

    // Casi acostado: gana el borde superior (+y).
    final tx = east.$2;
    final ty = north.$2;
    if (math.sqrt(tx * tx + ty * ty) < 1e-6) return null;
    return normalize360(_deg(math.atan2(tx, ty)));
  }

  /// Distancia en metros o texto corto ("1.2 km").
  static String formatDistance(double m) {
    if (!m.isFinite) return '—';
    if (m < 1000) return '${m.round()} m';
    return '${(m / 1000).toStringAsFixed(2)} km';
  }

  /// Punto cardinal corto: N, NE, E...
  static String compassPoint(double deg) {
    const pts = ['N', 'NE', 'E', 'SE', 'S', 'SO', 'O', 'NO'];
    return pts[(normalize360(deg) / 45).round() % 8];
  }

  static (double, double, double)? _unit(double x, double y, double z) {
    final l = math.sqrt(x * x + y * y + z * z);
    if (l < 1e-9) return null;
    return (x / l, y / l, z / l);
  }

  static (double, double, double) _cross(
      double ax, double ay, double az, double bx, double by, double bz) {
    return (ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx);
  }
}
