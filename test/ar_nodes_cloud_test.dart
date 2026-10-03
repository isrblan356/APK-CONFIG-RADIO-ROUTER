import 'package:flutter_test/flutter_test.dart';
import 'package:wisp_configurator/features/ar_compass/data/ar_nodes_cloud.dart';
import 'package:wisp_configurator/features/ar_compass/data/ar_node_sync.dart';
import 'package:wisp_configurator/features/ar_compass/domain/ar_node.dart';

void main() {
  group('parse /nodes', () {
    test('envoltorio + alias de claves', () {
      final nodes = ArNodesCloud.parse('{"nodes":['
          '{"id":1,"nombre":"Girardota AP12","lat":6.32,"lng":-75.43,"zona":"Girardota"},'
          '{"id":2,"name":"Medellín Norte","latitude":"6.25","longitude":"-75.56"}]}');
      expect(nodes, hasLength(2));
      expect(nodes[0].nombre, 'Girardota AP12');
      expect(nodes[0].remotoId, 1);
      expect(nodes[0].origen, 'nube');
      expect(nodes[1].lat, closeTo(6.25, 1e-9));
    });

    test('array suelto, coma decimal y altitud', () {
      final nodes = ArNodesCloud
          .parse('[{"nombre":"AP","lat":"-33,45","lng":"-70,66","alt":720}]');
      expect(nodes.single.lat, closeTo(-33.45, 1e-9));
      expect(nodes.single.lng, closeTo(-70.66, 1e-9));
      expect(nodes.single.alt, 720);
      expect(nodes.single.localId, 0);
    });

    test('descarta filas sin nombre, sin coordenadas o fuera de rango', () {
      final nodes = ArNodesCloud.parse('[{"nombre":"x"},'
          '{"lat":6.1,"lng":-75.1},{"nombre":"y","lat":120,"lng":0},'
          '{"nombre":"z","lat":6.1,"lng":-75.1}]');
      expect(nodes, hasLength(1));
      expect(nodes.single.nombre, 'z');
    });

    test('JSON roto o vacío = sin nodos', () {
      expect(ArNodesCloud.parse('no es json'), isEmpty);
      expect(ArNodesCloud.parse('{"nodes":[]}'), isEmpty);
      expect(ArNodesCloud.parse('{"error":"x"}'), isEmpty);
    });
  });

  group('plan de sync', () {
    const manual = ArNode(nombre: 'Manual', lat: 1, lng: 2, origen: 'manual');
    const nube1 =
        ArNode(nombre: 'Nube A', lat: 3, lng: 4, remotoId: 1, origen: 'nube');
    const nube2 =
        ArNode(nombre: 'Nube B', lat: 5, lng: 6, remotoId: 2, origen: 'nube');

    test('respuesta vacía conserva todo (nunca borra por error)', () {
      final plan = ArNodeSync.plan(const [manual, nube1], const []);
      expect(plan.conservar, containsAll([manual, nube1]));
      expect(plan.insertar, isEmpty);
    });

    test('los manuales sobreviven y la nube se reemplaza completa', () {
      final plan = ArNodeSync.plan(const [manual, nube1], const [nube2]);
      expect(plan.conservar, [manual]);
      expect(plan.insertar, [nube2]);
    });
  });
}
