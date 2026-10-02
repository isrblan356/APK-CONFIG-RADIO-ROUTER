import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../../../core/config/app_config.dart';
import '../../../core/error/failures.dart';
import '../../../core/network/reachability.dart';
import '../../inventory/domain/inventory_repository.dart';
import '../domain/entities/ubnt_radio.dart';
import '../domain/repositories/ubnt_repository.dart';
import '../domain/template_builder.dart';

/// Implementación real SSH. Port fiel de final.php a dartssh2 (móvil).
///
/// Flujo original preservado:
/// 1. ubnt_is_alive(192.168.1.20) si no -> (192.168.20.1)
/// 2. espera ssh_init_wait, reintenta ssh_tries
/// 3. login con pass1, si falla reintenta con R1nku.2015 (líneas 221-231)
/// 4. /usr/www/status.cgi -> modelo + fwversion (+ XW/XM si M5, flag AC)
/// 5. fwupdate.bin por SCP -> /sbin/fwupdate -m
/// 6. template.cfg -> reemplazos CHANGESSID/80.50/80.1 -> /tmp/system.cfg
/// 7. ct -> /etc/persistent/ct, cfgmtd -w -p /etc/, reboot
class UbntRepositoryImpl implements UbntRepository {
  final Reachability reachability;
  final InventoryRepository inventory; // para resolver plantillas si se quiere
  UbntRepositoryImpl(this.reachability, this.inventory);

  // ---------- helpers SSH ----------

  Future<SSHClient?> _connect(String ip, String user, String pass) async {
    for (var i = 1; i <= AppConfig.sshTries; i++) {
      try {
        final socket = await SSHSocket.connect(ip, 22,
            timeout: const Duration(seconds: 5));
        final client = SSHClient(
          socket,
          username: user,
          onPasswordRequest: () => pass,
        );
        await client.authenticated;
        return client;
      } catch (_) {
        await Future.delayed(
            const Duration(seconds: AppConfig.sshTryWaitSec));
      }
    }
    return null;
  }

  Future<String> _exec(SSHClient c, String cmd) async {
    final out = await c.run(cmd);
    return utf8.decode(out, allowMalformed: true);
  }

  UbntRadio _parseStatus(String ip, String rawStatusCgi) {
    // status.cgi devuelve headers + JSON. Igual que:
    // preg_replace('/^Content-Type:.../', '', $output) en final.php
    var body = rawStatusCgi;
    final idx = body.indexOf('{');
    if (idx > 0) body = body.substring(idx);
    final j = json.decode(body.trim()) as Map<String, dynamic>;
    final host = j['host'] as Map<String, dynamic>;
    final fw = (host['fwversion'] ?? '').toString().trim();
    var model = '';
    if (host['devmodel'] != null) {
      model = host['devmodel'].toString().trim();
    } else if (host['hostname'] != null) {
      model = host['hostname'].toString().trim();
    }
    var isAc = false;
    if (model.contains('M5')) {
      final prefix = (host['fwprefix'] ?? 'XM').toString().trim();
      model = '$model $prefix';
    } else if (model.contains('5AC')) {
      isAc = true;
    }
    String duplex = '';
    try {
      final ifs = (j['interfaces'] as List);
      for (final e in ifs) {
        final m = e as Map<String, dynamic>;
        if (m['ifname'] == 'eth0') {
          final st = m['status'] as Map<String, dynamic>;
          duplex = '${st['speed']}/${(st['duplex'] as bool) ? 'FDX' : 'HDX'}';
        }
      }
    } catch (_) {}
    return UbntRadio(
        ip: ip, model: model, firmware: fw, isAc: isAc, lanSpeedDuplex: duplex);
  }

  Future<(UbntRadio, String workingPass)?> _detect() async {
    // 1) IP por defecto de fábrica
    if (await reachability.isUbntAlive(AppConfig.ubntDefaultIp)) {
      for (final pass in AppConfig.ubntKnownPasses) {
        final c = await _connect(
            AppConfig.ubntDefaultIp, AppConfig.ubntDefaultUser, pass);
        if (c == null) continue;
        try {
          final raw = await _exec(c, '/usr/www/status.cgi');
          final radio =
              _parseStatus(AppConfig.ubntDefaultIp, raw);
          c.close();
          return (radio, pass);
        } catch (_) {
          c.close();
        }
      }
    }
    // 2) IP ya configurada
    if (await reachability.isUbntAlive(AppConfig.ubntConfiguredIp)) {
      for (final pass in AppConfig.ubntKnownPasses) {
        final c = await _connect(
            AppConfig.ubntConfiguredIp, AppConfig.ubntDefaultUser, pass);
        if (c == null) continue;
        try {
          final raw = await _exec(c, '/usr/www/status.cgi');
          final radio =
              _parseStatus(AppConfig.ubntConfiguredIp, raw);
          c.close();
          return (radio, pass);
        } catch (_) {
          c.close();
        }
      }
    }
    return null;
  }

  @override
  Future<Either<Failure, UbntRadio>> detectAndIdentify() async {
    try {
      final found = await _detect();
      if (found == null) {
        return const Left(ConnectionFailure(
            'No responde 192.168.1.20 ni 192.168.20.1 por SSH/puerto 22-80. Verifica que el móvil esté conectado al radio.'));
      }
      return Right(found.$1);
    } catch (e) {
      return Left(DeviceFailure('Error identificando radio: $e'));
    }
  }

  String _assetTemplatePath(String model) =>
      'assets/templates/${model.trim()}/template.cfg';

  /// Genera system.cfg aplicando los 3 reemplazos de final.php.
  /// [templateRaw] es el contenido de template.cfg embarcado en la APK.
  /// Delegado al builder puro para que sea testeable sin Flutter.
  String buildSystemCfg(String templateRaw, UbntProvisionParams p) =>
      const UbntTemplateBuilder().build(templateRaw, p);

  Future<String> _loadTemplate(String model) async {
    // Los templates están embarcados en assets/templates/<modelo>/template.cfg
    // copiados desde backup_script/configs/. Si el modelo exacto no existe,
    // se intenta fallback a PowerBeam M5 400 XW (el más común en tu red).
    const fallbacks = [
      'PowerBeam M5 400 XW',
      'PowerBeam M5 300 XW',
      'LiteBeam M5 XW',
      'NanoBeam 5AC 16',
    ];
    final candidates = [model.trim(), ...fallbacks];
    for (final m in candidates) {
      try {
        return await rootBundle
            .loadString('assets/templates/$m/template.cfg');
      } catch (_) {}
    }
    throw Exception('Sin template para modelo "$model". Agrega assets/templates/$model/template.cfg');
  }

  @override
  Future<Either<Failure, void>> updateFirmwareIfNeeded(
      UbntRadio radio, String sshPass, void Function(String) onLog) async {
    try {
      final target = radio.isAc ? AppConfig.fwAC : AppConfig.fwM;
      if (radio.firmware == target) {
        onLog('Firmware ya en $target, se omite subida.');
        return const Right(null);
      }
      onLog('Firmware actual ${radio.firmware}, se subirá a $target...');
      // En móvil el .bin va en assets/firmware/<modelo>/fwupdate.bin.
      // Se carga a memoria y se sube por SFTP a /tmp/fwupdate.bin.
      final fwAsset = 'assets/firmware/${radio.model}/fwupdate.bin';
      late Uint8List bytes;
      try {
        final data = await rootBundle.load(fwAsset);
        bytes = data.buffer.asUint8List();
      } catch (_) {
        return Left(DeviceFailure(
            'Falta $fwAsset en la APK. Copia Firmware/${radio.model}/fwupdate.bin a assets/firmware/'));
      }
      final client = await _connect(radio.ip, AppConfig.ubntDefaultUser, sshPass);
      if (client == null) {
        return const Left(AuthFailure('No se pudo conectar por SSH para firmware.'));
      }
      try {
        final sftp = await client.sftp();
        final f = await sftp.open('/tmp/fwupdate.bin',
            mode: SftpFileOpenMode.create |
                SftpFileOpenMode.truncate |
                SftpFileOpenMode.write);
        await f.writeBytes(bytes);
        await f.close();
        await _exec(client, '/sbin/fwupdate -m');
        onLog('Firmware subido, esperando reinicio...');
        await Future.delayed(
            const Duration(seconds: AppConfig.sshInitWaitSec + 20));
      } finally {
        client.close();
      }
      return const Right(null);
    } catch (e) {
      return Left(DeviceFailure('Fallo subiendo firmware: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> uploadConfigAndApply(
      UbntProvisionParams params, void Function(String) onLog) async {
    try {
      final client = await _connect(
          params.radioIp, params.sshUser, params.sshPass);
      if (client == null) {
        return const Left(AuthFailure('SSH falló. Prueba passes ubnt / r1nku.2015 / R1nku.2015'));
      }
      try {
        final raw = await _exec(client, '/usr/www/status.cgi');
        final radio = _parseStatus(params.radioIp, raw);
        onLog('Modelo: ${radio.model} FW:${radio.firmware}');

        final template = await _loadTemplate(radio.model);
        final systemCfg = buildSystemCfg(template, params);

        final sftp = await client.sftp();
        // /tmp/system.cfg
        var f = await sftp.open('/tmp/system.cfg',
            mode: SftpFileOpenMode.create |
                SftpFileOpenMode.truncate |
                SftpFileOpenMode.write);
        await f.writeBytes(Uint8List.fromList(utf8.encode(systemCfg)));
        await f.close();
        onLog('system.cfg subido (SSID=${params.ssid} WAN=${params.newWan} GW=${params.newGateway})');

        // compliance ct -> /etc/persistent/ct (ubnt_upload_m5_compliance)
        try {
          final ct = await rootBundle.load('assets/templates/ct');
          final ctBytes = ct.buffer.asUint8List();
          final ctf = await sftp.open('/etc/persistent/ct',
              mode: SftpFileOpenMode.create |
                  SftpFileOpenMode.truncate |
                  SftpFileOpenMode.write);
          await ctf.writeBytes(ctBytes);
          await ctf.close();
          onLog('Compliance subido.');
        } catch (_) {
          onLog('Aviso: sin archivo ct en assets (no crítico en AC).');
        }

        await _exec(client, 'cfgmtd -w -p /etc/');
        await _exec(client, 'reboot');
        onLog('Config aplicada, reiniciando... espera a ${AppConfig.ubntConfiguredIp}');
      } finally {
        client.close();
      }
      return const Right(null);
    } catch (e) {
      return Left(DeviceFailure('Error aplicando config: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> factoryReset(String ip, String sshPass) async {
    try {
      final client =
          await _connect(ip, AppConfig.ubntDefaultUser, sshPass);
      if (client == null) return const Left(AuthFailure('SSH falló para reset.'));
      try {
        // Port de ubnt_reset_defaults()
        await _exec(client, 'cp /usr/etc/system.cfg /tmp/system.cfg');
        await _exec(client, 'save');
        await _exec(client, 'cfgmtd -w -p /etc/');
        await _exec(client, 'reboot');
      } finally {
        client.close();
      }
      return const Right(null);
    } catch (e) {
      return Left(DeviceFailure('Error en reset: $e'));
    }
  }
}
