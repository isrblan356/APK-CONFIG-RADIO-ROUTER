import 'package:shared_preferences/shared_preferences.dart';

import 'app_config.dart';

/// Configuración editable por el módulo Admin, persistida en el móvil.
///
/// Fábrica = valores de [AppConfig]. Cada setter guarda en SharedPreferences
/// y cada getter lee allí; si nadie llamó a [init] (tests / scripts puros)
/// se usan los defaults de fábrica, así nunca revienta.
///
/// Se inicializa en main() antes de runApp:
///   await AppSettings.instance.init();
class AppSettings {
  AppSettings._();
  static final AppSettings instance = AppSettings._();

  SharedPreferences? _p;

  Future<void> init() async {
    try {
      _p = await SharedPreferences.getInstance();
    } catch (_) {
      _p = null; // sin preferencias = modo fábrica
    }
  }

  /// ¿Se cargaron las preferencias? (false en tests puros)
  bool get ready => _p != null;

  String _s(String k, String d) => _p?.getString(k) ?? d;
  bool _b(String k, bool d) => _p?.getBool(k) ?? d;
  int _i(String k, int d) => _p?.getInt(k) ?? d;

  Future<bool> _setS(String k, String v) async =>
      _p?.setString(k, v) ?? Future.value(false);
  Future<bool> _setB(String k, bool v) async =>
      _p?.setBool(k, v) ?? Future.value(false);
  Future<bool> _setI(String k, int v) async =>
      _p?.setInt(k, v) ?? Future.value(false);

  // ---------- Ubiquiti (final.php) ----------

  String get ubntDefaultIp => _s('ubntDefaultIp', AppConfig.ubntDefaultIp);
  String get ubntWifiIp => _s('ubntWifiIp', AppConfig.ubntWifiIp);
  String get ubntConfiguredIp =>
      _s('ubntConfiguredIp', AppConfig.ubntConfiguredIp);
  String get ubntUser => _s('ubntUser', AppConfig.ubntDefaultUser);

  /// Claves SSH probadas en orden (se guardan separadas por coma).
  /// Se limpian espacios y comillas para que " 'clave' " no falle.
  List<String> get ubntPasses {
    final raw = _s('ubntPasses', AppConfig.ubntKnownPasses.join(','));
    return raw
        .split(',')
        .map((e) {
          var v = e.trim();
          while (v.length >= 2 &&
              ((v.startsWith('"') && v.endsWith('"')) ||
                  (v.startsWith("'") && v.endsWith("'")))) {
            v = v.substring(1, v.length - 1).trim();
          }
          return v;
        })
        .where((e) => e.isNotEmpty)
        .toList();
  }

  /// Orden de sondeo del modo Auto: fábrica → WiFi del radio → ya configurada.
  List<String> get ubntCandidateIps =>
      [ubntDefaultIp, ubntWifiIp, ubntConfiguredIp];

  /// Firmware objetivo (se usan igual que fwM/fwAC de fábrica).
  String get fwM => _s('fwM', AppConfig.fwM);
  String get fwAC => _s('fwAC', AppConfig.fwAC);
  String fwTarget(bool isAc) => isAc ? fwAC : fwM;

  // ---------- IP final del equipo (el "network 50" de final.php) ----------

  /// Sufijo WAN: $newwan = $newnetwork.'50'
  String get wanSuffix => _s('wanSuffix', '50');
  String wanIp(String network) => network.endsWith('.') || network.isEmpty
      ? '$network$wanSuffix'
      : '$network.$wanSuffix';

  /// Sufijo de puerta de enlace: $newgateway = $newnetwork.'1'
  String get gwSuffix => _s('gwSuffix', '1');
  String gatewayIp(String network) => network.endsWith('.') || network.isEmpty
      ? '$network$gwSuffix'
      : '$network.$gwSuffix';

  // ---------- TP-Link ----------

  String get tplinkNewIp => _s('tplinkNewIp', AppConfig.tplinkNewIp);
  String get tplinkNewPass => _s('tplinkNewPass', AppConfig.tplinkNewPass);
  String get tplinkConfiguredIp =>
      _s('tplinkConfiguredIp', AppConfig.tplinkConfiguredIp);
  String get tplinkConfiguredPass =>
      _s('tplinkConfiguredPass', AppConfig.tplinkConfiguredPass);
  String get tplinkTargetLanIp =>
      _s('tplinkTargetLanIp', AppConfig.tplinkTargetLanIp);

  // ---------- Nube ----------

  bool get cloudEnabled => _b('cloudEnabled', AppConfig.cloudEnabledDefault);
  String get cloudEndpoint => _s('cloudEndpoint', AppConfig.cloudEndpoint);
  String get cloudToken => _s('cloudToken', '');
  Uri? get cloudUri {
    final raw = cloudEndpoint.replaceAll(RegExp(r'/+$'), '');
    if (raw.isEmpty) return null;
    return Uri.tryParse(raw);
  }

  // ---------- Módulo Admin ----------

  /// SHA-256 hex de la contraseña. Vacío = primera vez (admin/admin).
  String get adminHash => _s('adminHash', '');
  /// true mientras la contraseña siga siendo la de fábrica (cambio obligatorio).
  bool get adminMustChange => _b('adminMustChange', true);
  int get adminFails => _i('adminFails', 0);
  /// Epoch (ms) hasta el que está bloqueado el acceso por intentos fallidos.
  int get adminLockUntil => _i('adminLockUntil', 0);

  // ---------- Escrituras ----------

  Future<bool> setUbntDefaultIp(String v) => _setS('ubntDefaultIp', v);
  Future<bool> setUbntWifiIp(String v) => _setS('ubntWifiIp', v);
  Future<bool> setUbntConfiguredIp(String v) => _setS('ubntConfiguredIp', v);
  Future<bool> setUbntUser(String v) => _setS('ubntUser', v);
  Future<bool> setUbntPasses(List<String> v) =>
      _setS('ubntPasses', v.join(','));
  Future<bool> setFwM(String v) => _setS('fwM', v);
  Future<bool> setFwAC(String v) => _setS('fwAC', v);
  Future<bool> setWanSuffix(String v) => _setS('wanSuffix', v);
  Future<bool> setGwSuffix(String v) => _setS('gwSuffix', v);
  Future<bool> setTplinkNewIp(String v) => _setS('tplinkNewIp', v);
  Future<bool> setTplinkNewPass(String v) => _setS('tplinkNewPass', v);
  Future<bool> setTplinkConfiguredIp(String v) =>
      _setS('tplinkConfiguredIp', v);
  Future<bool> setTplinkConfiguredPass(String v) =>
      _setS('tplinkConfiguredPass', v);
  Future<bool> setTplinkTargetLanIp(String v) =>
      _setS('tplinkTargetLanIp', v);
  Future<bool> setCloudEnabled(bool v) => _setB('cloudEnabled', v);
  Future<bool> setCloudEndpoint(String v) => _setS('cloudEndpoint', v);
  Future<bool> setCloudToken(String v) => _setS('cloudToken', v);
  Future<bool> setAdminHash(String v) => _setS('adminHash', v);
  Future<bool> setAdminMustChange(bool v) => _setB('adminMustChange', v);
  Future<bool> setAdminFails(int v) => _setI('adminFails', v);
  Future<bool> setAdminLockUntil(int v) => _setI('adminLockUntil', v);

  /// Todo a valores de fábrica (menos la contraseña ya cambiada).
  Future<void> resetConfig() async {
    const keys = [
      'ubntDefaultIp',
      'ubntWifiIp',
      'ubntConfiguredIp',
      'ubntUser',
      'ubntPasses',
      'fwM',
      'fwAC',
      'wanSuffix',
      'gwSuffix',
      'tplinkNewIp',
      'tplinkNewPass',
      'tplinkConfiguredIp',
      'tplinkConfiguredPass',
      'tplinkTargetLanIp',
      'cloudEnabled',
      'cloudEndpoint',
      'cloudToken',
    ];
    for (final k in keys) {
      await _p?.remove(k);
    }
  }
}
