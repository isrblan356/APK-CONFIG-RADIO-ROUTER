import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;

import 'app_config.dart';
import 'app_settings.dart';

/// Reporta al servidor qué equipos tienen la APK instalada.
///
/// La APK solo *sincroniza*: en cada sync avisa quién es (id estable del
/// equipo, modelo, SO y versión). El servidor lo guarda con su IP y lo lista
/// en el panel (**Dispositivos**), donde se le asigna un técnico con su IP.
///
/// Siempre best-effort: timeout de 2 s y nunca lanza — si el servidor no
/// responde, el sync continúa igual que antes.
class DeviceRegistry {
  DeviceRegistry._();

  static String _id = '';

  /// Id estable de este equipo: hex de 64 bits, generado una vez y guardado
  /// en SharedPreferences.
  static Future<String> _deviceId() async {
    if (_id.isNotEmpty) return _id;
    var id = AppSettings.instance.deviceId;
    if (id.isEmpty) {
      final r = Random.secure();
      final hex = List.generate(16, (_) => r.nextInt(16));
      const digits = '0123456789abcdef';
      id = hex.map((i) => digits[i]).join();
      await AppSettings.instance.setDeviceId(id);
    }
    _id = id;
    return _id;
  }

  /// Envia/actualiza la ficha de este equipo en el servidor (`POST /dispositivos`).
  static Future<void> reportar(http.Client cliente) async {
    try {
      final base =
          AppSettings.instance.cloudEndpoint.replaceAll(RegExp(r'/+$'), '');
      if (base.isEmpty) return;
      final id = await _deviceId();
      if (id.isEmpty) return;
      final res = await cliente
          .post(
            Uri.parse('$base/dispositivos'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'id': id,
              // dart:io no expone el modelo de fábrica sin plugin; con el SO
              // detallado + IP + id corto el equipo se identifica bien.
              'modelo': Platform.operatingSystemVersion,
              'so': Platform.operatingSystem,
              'version': AppConfig.appVersion,
            }),
          )
          .timeout(const Duration(seconds: 2));
      if (res.statusCode != 200) {
        // El servidor no aceptó la ficha: no rompe el sync.
        return;
      }
    } catch (_) {
      // Sin conexión o timeout: el sync sigue como hasta ahora.
    }
  }
}
