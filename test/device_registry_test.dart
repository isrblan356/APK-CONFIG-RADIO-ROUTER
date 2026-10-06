import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisp_configurator/core/config/app_config.dart';
import 'package:wisp_configurator/core/config/app_settings.dart';
import 'package:wisp_configurator/core/config/device_registry.dart';

/// Cliente que solo registra el último POST /dispositivos.
class RegistraPost extends Fake implements http.Client {
  String? url;
  Map<String, dynamic>? json;
  bool lanzar = false;

  @override
  Future<http.Response> post(Uri url,
      {Map<String, String>? headers, Object? body, Encoding? encoding}) async {
    if (lanzar) {
      throw http.ClientException('sin red');
    }
    this.url = url.toString();
    json = jsonDecode(body.toString()) as Map<String, dynamic>;
    return http.Response('{"ok":true}', 200);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.init();
  });

  group('DeviceRegistry', () {
    test('reporta id estable, SO y versión al servidor', () async {
      await AppSettings.instance.setCloudEndpoint('http://srv.test');
      final c = RegistraPost();
      await DeviceRegistry.reportar(c);
      expect(c.url, 'http://srv.test/dispositivos');
      final id = c.json!['id'] as String;
      expect(id.length, 16);
      expect(id, matches(RegExp(r'^[0-9a-f]{16}$')));
      expect(c.json!['version'], AppConfig.appVersion);
      expect(c.json!['so'], isNotEmpty);

      // Segundo sync: mismo id (identidad estable del equipo).
      final c2 = RegistraPost();
      await DeviceRegistry.reportar(c2);
      expect(c2.json!['id'], id);
    });

    test('sin endpoint no hace ninguna petición', () async {
      await AppSettings.instance.setCloudEndpoint('');
      final c = RegistraPost();
      await DeviceRegistry.reportar(c);
      expect(c.url, isNull);
    });

    test('si el servidor falla no rompe nada (best-effort)', () async {
      await AppSettings.instance.setCloudEndpoint('http://srv.test');
      final c = RegistraPost()..lanzar = true;
      await expectLater(DeviceRegistry.reportar(c), completes);
    });
  });
}
