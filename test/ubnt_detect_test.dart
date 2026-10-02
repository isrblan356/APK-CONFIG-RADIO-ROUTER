import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:wisp_configurator/core/config/app_config.dart';
import 'package:wisp_configurator/core/network/reachability.dart';
import 'package:wisp_configurator/features/inventory/domain/inventory_repository.dart';
import 'package:wisp_configurator/features/radio_ubiquiti/data/ubnt_repository_impl.dart';

/// Reachability falso: registra qué IPs se sondean y nunca encuentra equipo
/// (así detectAndIdentify nunca llega a abrir SSH).
class RecordingReachability implements Reachability {
  RecordingReachability({this.alive = false});
  final bool alive;
  final List<String> probed = [];

  @override
  Future<bool> isTcpOpen(String ip, int port,
      {Duration timeout = const Duration(seconds: 2)}) async => alive;

  @override
  Future<bool> isUbntAlive(String ip) async {
    probed.add(ip);
    return alive;
  }
}

class MockInventory extends Mock implements InventoryRepository {}

void main() {
  test('Auto sondea 1.20, 172.1 y 20.1 en ese orden', () async {
    final reach = RecordingReachability();
    final repo = UbntRepositoryImpl(reach, MockInventory());

    final res = await repo.detectAndIdentify();

    expect(res.isLeft(), true);
    expect(reach.probed, AppConfig.ubntCandidateIps);
    expect(reach.probed, ['192.168.1.20', '192.168.172.1', '192.168.20.1']);
    final msg = res.fold<String>((f) => f.message, (_) => '');
    expect(msg, contains('192.168.172.1'));
  });

  test('IP explicita 192.168.172.1: solo se sondea esa', () async {
    final reach = RecordingReachability();
    final repo = UbntRepositoryImpl(reach, MockInventory());

    final res = await repo.detectAndIdentify(ip: AppConfig.ubntWifiIp);

    expect(res.isLeft(), true);
    expect(reach.probed, ['192.168.172.1']);
  });
}
