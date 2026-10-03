import 'package:flutter_test/flutter_test.dart';
import 'package:wisp_configurator/features/ar_compass/domain/geo.dart';

void main() {
  group('distancia', () {
    test('mismo punto = 0', () {
      expect(Geo.distanceM(6.2, -75.5, 6.2, -75.5), 0);
    });

    test('un grado de latitud ~111.2 km', () {
      final d = Geo.distanceM(6, -75, 7, -75);
      expect(d, closeTo(111195, 2));
    });

    test('formato corto', () {
      expect(Geo.formatDistance(950), '950 m');
      expect(Geo.formatDistance(1234), '1.23 km');
      expect(Geo.formatDistance(double.nan), '—');
    });
  });

  group('acimut', () {
    test('al norte 0°, este 90°, sur 180°, oeste 270°', () {
      expect(Geo.bearing(0, 0, 1, 0), closeTo(0, 0.001));
      expect(Geo.bearing(0, 0, 0, 1), closeTo(90, 0.001));
      expect(Geo.bearing(0, 0, -1, 0), closeTo(180, 0.001));
      expect(Geo.bearing(0, 0, 0, -1), closeTo(270, 0.001));
    });

    test('delta queda en [-180, 180)', () {
      expect(Geo.delta(350, 10), -20);
      expect(Geo.delta(10, 350), 20);
      expect(Geo.delta(0, 0), 0);
      expect(Geo.delta(180, 0), -180);
      expect(Geo.delta(0, 180), -180);
    });

    test('punto cardinal', () {
      expect(Geo.compassPoint(0), 'N');
      expect(Geo.compassPoint(90), 'E');
      expect(Geo.compassPoint(200), 'S');
      expect(Geo.compassPoint(316), 'NO');
    });
  });

  group('rumbo desde sensores', () {
    // Marco del dispositivo: x derecha, y arriba (borde superior), z fuera de
    // la pantalla (hacia el usuario). La cámara mira en -z.
    double? flat({required double mx, required double my, required double mz}) =>
        Geo.headingFromSensors(
            ax: 0, ay: 0, az: 9.81, mx: mx, my: my, mz: mz);

    test('teléfono acostado: usa el borde superior (+y)', () {
      expect(flat(mx: 0, my: 25, mz: 0), closeTo(0, 0.01)); // arriba al norte
      expect(flat(mx: -25, my: 0, mz: 0), closeTo(90, 0.01)); // arriba al este
      expect(flat(mx: 0, my: -25, mz: 0), closeTo(180, 0.01)); // al sur
      expect(flat(mx: 25, my: 0, mz: 0), closeTo(270, 0.01)); // al oeste
    });

    test('teléfono erguido: usa la dirección de la cámara (-z)', () {
      // Mirando al norte: pantalla hacia el sur, z hacia el usuario (sur).
      final alNorte = Geo.headingFromSensors(
          ax: 0, ay: 9.81, az: 0, mx: 0, my: 0, mz: -25);
      expect(alNorte, closeTo(0, 0.01));

      // Mirando al este: -z = este.
      final alEste = Geo.headingFromSensors(
          ax: 0, ay: 9.81, az: 0, mx: -25, my: 0, mz: 0);
      expect(alEste, closeTo(90, 0.01));
    });

    test('sin campo magnético no devuelve nada', () {
      expect(flat(mx: 0, my: 0, mz: 0), isNull);
      expect(
          Geo.headingFromSensors(
              ax: 0, ay: 0, az: 0, mx: 0, my: 10, mz: 0),
          isNull);
    });
  });
}
