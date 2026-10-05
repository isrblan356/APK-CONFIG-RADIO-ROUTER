import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:wisp_configurator/core/config/app_settings.dart';
import 'package:wisp_configurator/features/radio_ubiquiti/domain/entities/ubnt_radio.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.instance.init();
  });

  group('AppSettings', () {
    test('arranca con los defaults de fábrica', () {
      final s = AppSettings.instance;
      expect(s.ready, isTrue);
      expect(s.ubntDefaultIp, '192.168.1.20');
      expect(s.ubntWifiIp, '192.168.172.1');
      expect(s.ubntConfiguredIp, '192.168.20.1');
      expect(s.ubntUser, 'ubnt');
      expect(s.ubntPasses, ['ubnt', 'r1nku.2015', 'R1nku.2015']);
      expect(s.ubntCandidateIps, ['192.168.1.20', '192.168.172.1', '192.168.20.1']);
      expect(s.fwTarget(true), 'v8.7.4');
      expect(s.fwTarget(false), 'v6.3.2');
      expect(s.wanSuffix, '50');
      expect(s.gwSuffix, '1');
      expect(s.cloudEnabled, isFalse);
      expect(s.adminHash, '');
      expect(s.adminMustChange, isTrue);
      expect(s.adminFails, 0);
      expect(s.adminLockUntil, 0);
    });

    test('el "network 50" de final.php se arma con sufijos editables', () {
      final s = AppSettings.instance;
      expect(s.wanIp('192.168.80.'), '192.168.80.50');
      expect(s.gatewayIp('192.168.80.'), '192.168.80.1');
      // Sin punto final igual queda bien formado.
      expect(s.wanIp('192.168.80'), '192.168.80.50');
      expect(s.gatewayIp('192.168.80'), '192.168.80.1');
    });

    test('setters persisten y los getters los leen', () async {
      final s = AppSettings.instance;
      await s.setWanSuffix('60');
      await s.setGwSuffix('5');
      await s.setUbntWifiIp('10.0.0.1');
      await s.setUbntUser('admin-radio');
      await s.setUbntPasses(['abc', 'def']);
      await s.setFwAC('v8.9.1');
      await s.setTplinkConfiguredPass('clave1234');
      await s.setCloudEnabled(true);
      await s.setCloudEndpoint('http://192.168.1.50:8080/');
      await s.setCloudToken('t0k3n');

      expect(s.wanIp('192.168.80.'), '192.168.80.60');
      expect(s.gatewayIp('192.168.80.'), '192.168.80.5');
      expect(s.ubntCandidateIps, ['192.168.1.20', '10.0.0.1', '192.168.20.1']);
      expect(s.ubntUser, 'admin-radio');
      expect(s.ubntPasses, ['abc', 'def']);
      expect(s.fwTarget(true), 'v8.9.1');
      expect(s.tplinkConfiguredPass, 'clave1234');
      expect(s.cloudEnabled, isTrue);
      expect(s.cloudUri.toString(), 'http://192.168.1.50:8080');
      expect(s.cloudToken, 't0k3n');
    });

    test('las claves se limpian de espacios y comillas en el CSV', () async {
      final s = AppSettings.instance;
      await s.setUbntPasses([' " ubnt " ', "' r1nku.2015 '", '  ', 'clave']);
      expect(s.ubntPasses, ['ubnt', 'r1nku.2015', 'clave']);
    });

    test('resetConfig vuelve a fábrica pero conserva la contraseña admin', () async {
      final s = AppSettings.instance;
      await s.setWanSuffix('60');
      await s.setCloudEndpoint('http://x');
      await s.setAdminHash('sha256-de-prueba');
      await s.setAdminMustChange(false);

      await s.resetConfig();

      expect(s.wanSuffix, '50');
      expect(s.cloudEndpoint, '');
      expect(s.adminHash, 'sha256-de-prueba');
      expect(s.adminMustChange, isFalse);
    });
  });

  group('UbntProvisionParams (sufijos de Admin)', () {
    const base = UbntProvisionParams(
      radioIp: '192.168.172.1',
      ssid: 'rinku_ap1',
      network: '192.168.80.',
    );

    test('por defecto replica final.php (50 y 1)', () {
      expect(base.newWan, '192.168.80.50');
      expect(base.newGateway, '192.168.80.1');
    });

    test('acepta sufijos editados desde Admin', () {
      const p = UbntProvisionParams(
        radioIp: '192.168.172.1',
        ssid: 'rinku_ap1',
        network: '192.168.80.',
        wanSuffix: '60',
        gwSuffix: '5',
      );
      expect(p.newWan, '192.168.80.60');
      expect(p.newGateway, '192.168.80.5');
    });
  });
}
