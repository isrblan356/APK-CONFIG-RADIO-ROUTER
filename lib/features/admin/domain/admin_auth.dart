import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../../core/config/app_settings.dart';

/// Acceso al módulo Admin. Los datos viven en [AppSettings] (SharedPreferences):
///  - sin hash guardado: la primera clave es "admin" y obliga a cambiarla;
///  - después se guarda el SHA-256 hex de la contraseña;
///  - 5 intentos fallidos seguidos -> bloqueo de 5 minutos.
class AdminAuth {
  AdminAuth._();

  static const firstPass = 'admin';
  static const maxFails = 5;
  static const lockMinutes = 5;

  static String hash(String pass) =>
      sha256.convert(utf8.encode(pass.trim())).toString();

  /// Segundos que queda bloqueado (0 = sin bloqueo).
  static Duration get lockedFor {
    final until = AppSettings.instance.adminLockUntil;
    final left = until - DateTime.now().millisecondsSinceEpoch;
    if (left <= 0) return Duration.zero;
    return Duration(milliseconds: left);
  }

  static bool get locked => lockedFor != Duration.zero;

  /// true cuando todavía hay que imponer una contraseña nueva.
  static bool get mustChange {
    final s = AppSettings.instance;
    return s.adminHash.isEmpty || s.adminMustChange;
  }

  /// Devuelve null si el acceso es válido, o el motivo con el que rechazar.
  static Future<String?> unlock(String pass) async {
    final s = AppSettings.instance;
    if (locked) {
      return 'Bloqueado por intentos fallidos: '
          '${lockedFor.inMinutes + 1} min restantes';
    }
    if (s.adminHash.isEmpty) {
      if (pass.trim() != firstPass) return _fail();
      // Primer acceso: se obliga a elegir contraseña antes de entrar.
      await s.setAdminMustChange(true);
      return null;
    }
    if (hash(pass) != s.adminHash) return _fail();
    await s.setAdminFails(0);
    return null;
  }

  static Future<String?> _fail() async {
    final s = AppSettings.instance;
    final fails = s.adminFails + 1;
    await s.setAdminFails(fails);
    if (fails >= maxFails) {
      final until = DateTime.now()
          .add(const Duration(minutes: lockMinutes))
          .millisecondsSinceEpoch;
      await s.setAdminLockUntil(until);
      await s.setAdminFails(0);
      return 'Demasiados intentos: bloqueado $lockMinutes minutos.';
    }
    return 'Clave incorrecta (${maxFails - fails} intentos restantes).';
  }

  /// Cambia la contraseña. [actual] se pide salvo cuando viene del cambio
  /// obligatorio de primera vez (ahí [checkCurrent] es false).
  static Future<String?> changePassword({
    required String actual,
    required String nueva,
    required String confirmar,
    bool checkCurrent = true,
  }) async {
    final s = AppSettings.instance;
    final nuevaLimpia = nueva.trim();
    if (nuevaLimpia.length < 4) {
      return 'La nueva contraseña debe tener al menos 4 caracteres.';
    }
    if (nuevaLimpia != confirmar.trim()) {
      return 'La confirmación no coincide.';
    }
    if (checkCurrent) {
      if (s.adminHash.isEmpty) {
        if (actual.trim() != firstPass) return 'Clave actual incorrecta.';
      } else if (hash(actual) != s.adminHash) {
        return 'Clave actual incorrecta.';
      }
    }
    await s.setAdminHash(hash(nuevaLimpia));
    await s.setAdminMustChange(false);
    await s.setAdminFails(0);
    return null;
  }
}
