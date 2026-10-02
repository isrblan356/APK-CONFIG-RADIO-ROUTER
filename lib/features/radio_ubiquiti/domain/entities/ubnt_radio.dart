import 'package:equatable/equatable.dart';

/// Entidad de dominio: radio Ubiquiti. Refleja lo que final.php lee de status.cgi.
class UbntRadio extends Equatable {
  final String ip;
  final String model; // ej: "PowerBeam M5 400 XW", "NanoBeam 5AC 16"
  final String firmware; // ej: v6.3.2
  final bool isAc;
  final String lanSpeedDuplex;

  const UbntRadio({
    required this.ip,
    required this.model,
    required this.firmware,
    required this.isAc,
    this.lanSpeedDuplex = '',
  });

  bool get needsFirmwareUpdate =>
      isAc ? firmware != 'v8.7.4' : firmware != 'v6.3.2';

  @override
  List<Object> get props => [ip, model, firmware, isAc, lanSpeedDuplex];
}

/// Parámetros para aprovisionar (equivale a zona+nodo de nodos.db).
class UbntProvisionParams extends Equatable {
  final String radioIp;
  final String sshUser;
  final String sshPass;
  final String ssid; // SSID del AP elegido
  final String network; // ej: "192.168.80." (columna zona.network)
  const UbntProvisionParams({
    required this.radioIp,
    required this.ssid,
    required this.network,
    this.sshUser = 'ubnt',
    this.sshPass = 'ubnt',
  });

  String get newWan => '${network}50'; // igual que final.php: $newnetwork.'50'
  String get newGateway => '${network}1';

  @override
  List<Object> get props => [radioIp, sshUser, sshPass, ssid, network];
}
