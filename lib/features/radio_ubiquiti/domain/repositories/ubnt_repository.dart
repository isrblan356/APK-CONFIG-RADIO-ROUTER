import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../entities/ubnt_radio.dart';

/// Casos de uso puros. La UI solo habla con estos, nunca con SSH directo.
abstract class UbntRepository {
  /// Detecta radio en 192.168.1.20 (ubnt/ubnt) o 192.168.20.1 (pass config).
  /// Port de las líneas 161-173 de final.php.
  Future<Either<Failure, UbntRadio>> detectAndIdentify();

  /// Sube firmware si la versión no coincide (port ubnt_update_firmware).
  Future<Either<Failure, void>> updateFirmwareIfNeeded(UbntRadio radio, String sshPass, void Function(String) onLog);

  /// Genera system.cfg desde template.cfg reemplazando SSID + IPs
  /// (port líneas 387-393 de final.php) y lo sube + compliance + reboot.
  Future<Either<Failure, void>> uploadConfigAndApply(UbntProvisionParams params, void Function(String) onLog);

  /// Resetea a fábrica (port ubnt_reset_defaults).
  Future<Either<Failure, void>> factoryReset(String ip, String sshPass);
}
