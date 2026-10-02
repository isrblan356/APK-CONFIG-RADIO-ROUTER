import 'package:equatable/equatable.dart';

enum TplinkGen { old, modern }

/// Info leída de StatusRpm.htm (port del parsing con sed/grep de los .sh).
class TplinkInfo extends Equatable {
  final String ip;
  final TplinkGen gen;
  final String key; // token de sesión en routers modernos (IP/KEY/...)
  final String hw; // SYS_HW
  final String fw; // SYS_FW
  final String lanIp;
  final String ssid;
  final String wanMac;

  const TplinkInfo({
    required this.ip,
    required this.gen,
    required this.key,
    this.hw = '',
    this.fw = '',
    this.lanIp = '',
    this.ssid = '',
    this.wanMac = '',
  });

  String get baseUrl =>
      gen == TplinkGen.modern ? 'http://$ip/$key' : 'http://$ip';

  @override
  List<Object> get props => [ip, gen, key, hw, fw, lanIp, ssid, wanMac];
}

class TplinkProvision extends Equatable {
  /// option 1 = router nuevo/reset (full), 2 = solo cambio de clave
  final int option;
  final String ssid;
  final String wifiPass; // >= 8 chars
  const TplinkProvision({required this.option, required this.ssid, required this.wifiPass});
  @override
  List<Object> get props => [option, ssid, wifiPass];
}
