import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisp_configurator/core/config/app_settings.dart';
import 'package:wisp_configurator/features/admin/domain/admin_auth.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.init();
  });

  test('hash de admin es el SHA-256 conocido', () {
    expect(
      AdminAuth.hash('admin'),
      '8c6976e5b5410415bde908bd4dee15dfb167a9c873fc4bb8a81f6f2ab448a918',
    );
  });

  test('primer acceso: admin/admin y cambio obligatorio', () async {
    expect(AdminAuth.mustChange, isTrue);
    expect(await AdminAuth.unlock('otra'), isNotNull); // rechaza
    expect(await AdminAuth.unlock('admin'), isNull); // entra
    expect(AdminAuth.mustChange, isTrue); // pero aún debe cambiarla
    expect(AppSettings.instance.adminFails, 0);
  });

  test('cambio de contraseña y login posterior', () async {
    expect(await AdminAuth.unlock('admin'), isNull);
    expect(
      await AdminAuth.changePassword(
        actual: 'x',
        nueva: 'nueva123',
        confirmar: 'nueva123',
        checkCurrent: false,
      ),
      isNull,
    );
    expect(AdminAuth.mustChange, isFalse);
    expect(AppSettings.instance.adminHash, AdminAuth.hash('nueva123'));

    expect(await AdminAuth.unlock('nueva123'), isNull);
    expect(await AdminAuth.unlock('admin'), isNotNull);
  });

  test('valida longitud y confirmación', () async {
    expect(
      await AdminAuth.changePassword(
          actual: '', nueva: 'abc', confirmar: 'abc', checkCurrent: false),
      contains('4 caracteres'),
    );
    expect(
      await AdminAuth.changePassword(
          actual: '', nueva: 'nueva123', confirmar: 'otra', checkCurrent: false),
      contains('confirmación'),
    );
  });

  test('5 intentos fallidos bloquean 5 minutos', () async {
    await AppSettings.instance.setAdminHash(AdminAuth.hash('secreta'));

    String? last;
    for (var i = 0; i < AdminAuth.maxFails; i++) {
      last = await AdminAuth.unlock('mala');
      expect(last, isNotNull);
    }
    expect(last, contains('bloqueado'));
    expect(AdminAuth.locked, isTrue);
    // Incluso con la correcta ya no entra.
    expect(await AdminAuth.unlock('secreta'), contains('Bloqueado'));
    expect(AdminAuth.lockedFor.inMinutes, greaterThanOrEqualTo(4));
  });

  test('contraseña actual mal presentada no cambia nada', () async {
    await AppSettings.instance.setAdminHash(AdminAuth.hash('secreta'));
    expect(
      await AdminAuth.changePassword(
          actual: 'mala', nueva: 'otra1234', confirmar: 'otra1234'),
      contains('actual'),
    );
    expect(AppSettings.instance.adminHash, AdminAuth.hash('secreta'));
  });
}
