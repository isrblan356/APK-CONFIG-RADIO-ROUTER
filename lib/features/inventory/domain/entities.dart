import 'package:equatable/equatable.dart';

class Zone extends Equatable {
  final int id;
  final String name;
  final String network; // ej "192.168.80."
  const Zone({required this.id, required this.name, required this.network});
  @override
  List<Object> get props => [id, name, network];
}

class AccessPoint extends Equatable {
  final String zoneId;
  final int nodeId;
  final String name;
  final String ssid;
  const AccessPoint({required this.zoneId, required this.nodeId, required this.name, required this.ssid});
  @override
  List<Object> get props => [zoneId, nodeId, name, ssid];
}
