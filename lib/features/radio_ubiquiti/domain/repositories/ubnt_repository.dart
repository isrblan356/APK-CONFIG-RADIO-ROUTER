import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../entities/ubnt_radio.dart';

/// Casos de uso puros. La UI solo habla con estos, nunca con SSH directo.
abstract class UbntRepository {
  /// Detecta la radio. Si [ip] viene, se sondea solo esa IP (ej.
  /// 192.168.172.1, la que usa el radio al estar el móvil en su WiFi);
  /// si es null, se recorren AppConfig.ubntCandidateIps en orden
  /// (1.20 fábrica, 172.1 WiFi del radio, 20.1 ya configurada).
  /// [onLog] recibe el avance en vivo (qué IP, puerto, clave) para el log.
  /// Port de las líneas 161-173 de final.php.
  Future<Either<Failure, UbntRadio>> detectAndIdentify(
      {String? ip, void Function(String)? onLog});

  /// Diagnóstico de campo en texto: IP local del móvil + puertos 22/80 y
  /// HTTP hacia [ip] (por defecto la IP del WiFi del radio). No configura
  /// nada: solo dice por qué no se detecta.
  Future<Either<Failure, String>> diagnose({String? ip});

  /// Sube firmware si la versión no coincide (port ubnt_update_firmware).
  Future<Either<Failure, void>> updateFirmwareIfNeeded(UbntRadio radio, String sshPass, void Function(String) onLog);

  /// Genera system.cfg desde template.cfg reemplazando SSID + IPs
  /// (port líneas 387-393 de final.php) y lo sube + compliance + reboot.
  Future<Either<Failure, void>> uploadConfigAndApply(UbntProvisionParams params, void Function(String) onLog);

  /// Resetea a fábrica (port ubnt_reset_defaults).
  Future<Either<Failure, void>> factoryReset(String ip, String sshPass);
}
