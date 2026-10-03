import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:wisp_configurator/features/ar_compass/data/ar_node_store.dart';

/// Cliente de nube controlable para los tests (misma técnica que mocktail).
class FakeClient extends Fake implements http.Client {
  FakeClient({this.body = '', this.status = 200});
  String body;
  int status;
  int calls = 0;

  @override
  Future<http.Response> get(Uri url, {Map<String, String>? headers}) async {
    calls++;
    return http.Response(body, status);
  }
}

void main() {
  late Directory dir;
  late String dbPath;

  setUpAll(sqfliteFfiInit);

  setUp(() {
    dir = Directory.systemTemp.createTempSync('wisp_arnodes');
    dbPath = p.join(dir.path, 'ar.db');
  });

  tearDown(() {
    try {
      dir.deleteSync(recursive: true);
    } catch (_) {}
  });

  ArNodeStore store(FakeClient client,
          {bool enabled = true, String ep = 'https://api.test'}) =>
      ArNodeStore(client,
          cloudEnabled: enabled,
          endpoint: ep,
          factory: databaseFactoryFfi,
          dbPath: dbPath);

  test('alta manual y listado', () async {
    final s = store(FakeClient());
    expect(await s.list(), isEmpty);
    final id = await s.addManual(
        nombre: 'AP prueba',
        lat: 6.2,
        lng: -75.5,
        alt: 1500,
        zona: 'Girardota');
    expect(id, greaterThan(0));
    final list = await s.list();
    expect(list.single.nombre, 'AP prueba');
    expect(list.single.origen, 'manual');
    expect(list.single.alt, 1500);
    await s.remove(list.single.localId);
    expect(await s.list(), isEmpty);
  });

  test('sync: baja la nube y conserva lo manual', () async {
    final client = FakeClient(body: jsonEncode({
      'nodes': [
        {'id': 7, 'nombre': 'Nube A', 'lat': 6.1, 'lng': -75.1}
      ]
    }));
    final s = store(client);
    await s.addManual(nombre: 'Manual', lat: 6.9, lng: -75.9);

    final r = await s.syncFromCloud();
    expect(r.isRight(), true);
    expect(r.getOrElse(() => ''), contains('1 nodos'));

    final list = await s.list();
    expect(list, hasLength(2));
    expect(list.map((e) => e.origen).toSet(), {'manual', 'nube'});
    expect(list.firstWhere((e) => e.origen == 'nube').remotoId, 7);
  });

  test('segundo sync reemplaza la nube y no toca los manuales', () async {
    final client = FakeClient(body: jsonEncode({
      'nodes': [
        {'id': 7, 'nombre': 'Nube A', 'lat': 6.1, 'lng': -75.1}
      ]
    }));
    final s = store(client);
    await s.addManual(nombre: 'Manual', lat: 6.9, lng: -75.9);
    await s.syncFromCloud();

    // Ahora el servidor manda otra lista (sin el id 7).
    client.body = jsonEncode({
      'nodes': [
        {'id': 8, 'nombre': 'Nube Nueva', 'lat': 6.3, 'lng': -75.2}
      ]
    });
    await s.syncFromCloud();

    final list = await s.list();
    expect(list, hasLength(2));
    expect(list.any((e) => e.remotoId == 7), isFalse);
    expect(list.firstWhere((e) => e.origen == 'nube').nombre, 'Nube Nueva');
    expect(list.where((e) => e.origen == 'manual'), hasLength(1));
  });

  test('respuesta vacía = no borra nada', () async {
    final client = FakeClient(body: '{"nodes":[]}');
    final s = store(client);
    await s.addManual(nombre: 'Manual', lat: 1, lng: 2);
    final r = await s.syncFromCloud();
    expect(r.getOrElse(() => ''), contains('no se modificó'));
    expect(await s.list(), hasLength(1));
    expect(client.calls, 1);
  });

  test('nube desactivada o sin endpoint: solo locales', () async {
    final s = store(FakeClient(), enabled: false);
    final r = await s.syncFromCloud();
    expect(r.isRight(), true);
    expect(r.getOrElse(() => ''), contains('Nube no configurada'));

    final s2 = store(FakeClient(), ep: '');
    expect((await s2.syncFromCloud()).getOrElse(() => ''),
        contains('Nube no configurada'));
  });

  test('respuesta 500 = error, sin tocar la base', () async {
    final s = store(FakeClient(body: 'boom', status: 500));
    await s.addManual(nombre: 'Manual', lat: 1, lng: 2);
    final r = await s.syncFromCloud();
    expect(r.isLeft(), true);
    expect(await s.list(), hasLength(1));
  });

  test('JSON roto = sin nodos válidos y no borra nada', () async {
    final s = store(FakeClient(body: 'no es json'));
    await s.addManual(nombre: 'Manual', lat: 1, lng: 2);
    final r = await s.syncFromCloud();
    expect(r.getOrElse(() => ''), contains('sin nodos'));
    expect(await s.list(), hasLength(1));
  });
}
