import 'package:flutter_test/flutter_test.dart';
import 'package:wisp_configurator/features/inventory/data/cloud_payload.dart';
import 'package:wisp_configurator/features/inventory/domain/entities.dart';

// Contrato de la nube (README §3) + tolerancia a formatos del backend.
void main() {
  test('parseZones acepta array plano con claves en español o ingles', () {
    const body = '''
    [
      {"id": 1, "zona": "Girardota", "network": "192.168.80."},
      {"id": "5", "name": "Medellín", "net": "192.168.50.0"}
    ]''';
    final zones = CloudPayload.parseZones(body);
    expect(zones.length, 2);
    expect(zones[0], const Zone(id: 1, name: 'Girardota', network: '192.168.80.'));
    expect(zones[1], const Zone(id: 5, name: 'Medellín', network: '192.168.50.'));
  });

  test('parseZones acepta envoltorio {"zones":[...]}', () {
    const body = '{"zones": [{"id": 2, "zona": "Amagá", "network": "192.168.100."}]}';
    final zones = CloudPayload.parseZones(body);
    expect(zones.single.name, 'Amagá');
    expect(zones.single.network, '192.168.100.');
  });

  test('parseZones ignora filas incompletas y JSON inválido', () {
    expect(CloudPayload.parseZones('no-es-json'), isEmpty);
    expect(CloudPayload.parseZones('{"algo": 1}'), isEmpty);
    expect(
        CloudPayload.parseZones(
            '[{"id": 3}, {"zona": "x", "network": "192.168.1."}, {"id": 4, "zona": "", "network": "192.168.1."}]'),
        isEmpty);
  });

  test('parseAps usa zoneIdFallback cuando la fila no trae idzona', () {
    const body =
        '[{"idnodo":1,"nodo":"La Palma - AP1","ssid":"rinku_ap1_lapalma"},{"id":2,"name":"La Palma - AP2","ssid":"rinku_ap2_lapalma"}]';
    final aps = CloudPayload.parseAps(body, zoneIdFallback: '1');
    expect(aps.length, 2);
    expect(aps[0],
        const AccessPoint(zoneId: '1', nodeId: 1, name: 'La Palma - AP1', ssid: 'rinku_ap1_lapalma'));
    expect(aps[1].nodeId, 2);
  });

  test('parseAps conserva idzona propio y descarta filas sin zona', () {
    const body = '''
    [
      {"idzona": "7", "idnodo": 9, "nodo": "Nodo X", "ssid": "red_x"},
      {"idnodo": 10, "nodo": "Sin zona", "ssid": "red_y"}
    ]''';
    final aps = CloudPayload.parseAps(body);
    expect(aps.length, 1);
    expect(aps.single.zoneId, '7');
    expect(CloudPayload.parseAps('[{"nodo":"x","ssid":"y"}]'), isEmpty);
  });

  test('parseAps deduplica filas repetidas', () {
    const body =
        '[{"idzona":"1","idnodo":1,"nodo":"AP1","ssid":"s"},{"idzona":"1","idnodo":1,"nodo":"AP1","ssid":"s"}]';
    expect(CloudPayload.parseAps(body).length, 1);
  });

  test('networkBase devuelve base tipo 192.168.80.', () {
    expect(CloudPayload.networkBase('192.168.80.'), '192.168.80.');
    expect(CloudPayload.networkBase('192.168.80.0'), '192.168.80.');
    expect(CloudPayload.networkBase(' 192.168.50 '), '192.168.50.');
    expect(CloudPayload.networkBase(''), '');
  });
}
