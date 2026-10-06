/// Configuración central. Todo queda instalado en el móvil (offline-first).
/// El modo nube es opcional y solo sincroniza inventario/logs.
class AppConfig {
  // --- Ubiquiti (port de final.php) ---
  static const ubntDefaultIp = '192.168.1.20';
  static const ubntConfiguredIp = '192.168.20.1';
  // IP del radio cuando el móvil está en el WiFi que emite el propio radio
  // (SSID de fábrica): ahí el equipo escucha en 192.168.172.1/24.
  static const ubntWifiIp = '192.168.172.1';
  // Orden de sondeo del modo Auto: fábrica -> WiFi del radio -> ya configurado.
  static const ubntCandidateIps = [ubntDefaultIp, ubntWifiIp, ubntConfiguredIp];
  static const ubntDefaultUser = 'ubnt';
  static const ubntDefaultPass = 'ubnt';
  static const ubntKnownPasses = ['ubnt', 'r1nku.2015', 'R1nku.2015'];
  static const sshInitWaitSec = 10;
  static const sshTries = 5;
  static const sshTryWaitSec = 10;
  static const fwM = 'v6.3.2';
  static const fwAC = 'v8.7.4';

  // Plantilla: IP base del template original.
  // Se reemplaza igual que en final.php:
  // 192.168.80.50 -> <network>50 (WAN), 192.168.80.1 -> <network>1 (gateway)
  static const templateWanPlaceholder = '192.168.80.50';
  static const templateGwPlaceholder = '192.168.80.1';

  // --- TP-Link (port de 2new.sh / newchangepass.sh) ---
  static const tplinkNewIp = '192.168.0.1';
  static const tplinkNewPass = 'admin';
  static const tplinkConfiguredIp = '192.168.20.2';
  static const tplinkConfiguredPass = 'r1nku2015';
  static const tplinkTargetLanIp = '192.168.20.2';
  // MD5 precalculados usados por el firmware TP-Link nuevo:
  // admin/admin -> 21232f297a57a5a743894a0e4a801fc3
  // admin/r1nku2015 -> 57a298a940e7713eb606c3b0d77a460a
  static const tplinkOldPassHash = '21232f297a57a5a743894a0e4a801fc3';
  static const tplinkNewPassHash = '57a298a940e7713eb606c3b0d77a460a';

  // --- Nube híbrida (opcional, desactivada por defecto = 100% local) ---
  static const cloudEnabledDefault = false;
  // Pon aquí tu endpoint si quieres respaldo. Si está vacío, no se sincroniza.
  static const cloudEndpoint = String.fromEnvironment('CLOUD_ENDPOINT', defaultValue: '');

  // --- Identidad de la APK (reportada al servidor en cada sync) ---
  // Mantener sincronizado con `version:` de pubspec.yaml.
  static const appVersion = '1.1.6';
}
