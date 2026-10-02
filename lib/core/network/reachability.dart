import 'dart:io';
import 'package:http/http.dart' as http;

/// Contrato mínimo para probar alcance sin depender de ping ICMP
/// (Android no permite ICMP sin root). Equivale a `ubnt_is_alive()` de final.php
/// pero con socket TCP al puerto 22/80 en vez de fsockopen.
abstract class Reachability {
  Future<bool> isTcpOpen(String ip, int port, {Duration timeout = const Duration(seconds: 2)});
  Future<bool> isUbntAlive(String ip);
}

class ReachabilityImpl implements Reachability {
  @override
  Future<bool> isTcpOpen(String ip, int port, {Duration timeout = const Duration(seconds: 2)}) async {
    try {
      final s = await Socket.connect(ip, port, timeout: timeout);
      s.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> isUbntAlive(String ip) async {
    // final.php: fsockopen($ip,22) -> true incluso con ECONNREFUSED (111).
    // Aquí: si abre 22 o 80, hay equipo. Suficiente para móvil.
    if (await isTcpOpen(ip, 22)) return true;
    return isTcpOpen(ip, 80);
  }
}

/// Chequeo HTTP liviano para TP-Link (equivale a `nc -z IP 80` de los .sh).
class TplinkReachability {
  final http.Client client;
  TplinkReachability(this.client);
  Future<bool> isWebUp(String ip) async {
    try {
      final r = await client.get(Uri.parse('http://$ip/')).timeout(const Duration(seconds: 3));
      return r.statusCode < 500;
    } catch (_) {
      // Algunos firmwares cierran "/" pero abren userRpm -> probamos puerto.
      try {
        final s = await Socket.connect(ip, 80, timeout: const Duration(seconds: 2));
        s.destroy();
        return true;
      } catch (_) {
        return false;
      }
    }
  }
}
