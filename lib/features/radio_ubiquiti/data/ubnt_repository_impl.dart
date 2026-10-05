import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dartssh2/dartssh2.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../../../core/config/app_config.dart';
import '../../../core/config/app_settings.dart';
import '../../../core/error/failures.dart';
import '../../../core/network/reachability.dart';
import '../../inventory/domain/inventory_repository.dart';
import '../domain/entities/ubnt_radio.dart';
import '../domain/repositories/ubnt_repository.dart';
import '../domain/template_builder.dart';

/// Implementación real SSH. Port fiel de final.php a dartssh2 (móvil).
///
/// Flujo original preservado:
/// 1. ubnt_is_alive por candidatas: 192.168.1.20 (fábrica),
///    192.168.172.1 (WiFi del radio) y 192.168.20.1 (ya configurada)
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

  Future<SSHClient?> _connect(String ip, String user, String pass,
      {void Function(String)? onLog}) async {
    final log = onLog ?? ((_) {});
    for (var i = 1; i <= AppConfig.sshTries; i++) {
      try {
        final socket = await SSHSocket.connect(ip, 22,
            timeout: const Duration(seconds: 5));
        final client = SSHClient(
          socket,
          username: user,
          onPasswordRequest: () => pass,
          // AirOS a veces solo ofrece keyboard-interactive (misma clave).
          onUserInfoRequest: (req) =>
              List<String>.filled(req.prompts.length, pass),
        );
        await client.authenticated;
        return client;
      } on SSHAuthError catch (e) {
        // El servidor rechazó: repetir la misma clave no cambia nada.
        log('$ip: servidor rechazó la autenticación ($e)');
        return null;
      } catch (e) {
        log('$ip: intento $i/${AppConfig.sshTries}: $e');
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

  Future<(UbntRadio, String workingPass)?> _detect(
      String ip, void Function(String) log) async {
    if (!await reachability.isUbntAlive(ip)) {
      log('$ip: sin respuesta en los puertos 22/80');
      return null;
    }
    log('$ip: equipo responde, probando claves SSH...');
    for (final pass in AppSettings.instance.ubntPasses) {
      log('$ip: clave "$pass"...');
      final c =
          await _connect(ip, AppSettings.instance.ubntUser, pass, onLog: log);
      if (c == null) {
        log('$ip: clave "$pass" no sirvió (arriba está el motivo)');
        continue;
      }
      try {
        final raw = await _exec(c, '/usr/www/status.cgi');
        final radio = _parseStatus(ip, raw);
        c.close();
        log('$ip: OK con "$pass" (${radio.model} ${radio.firmware})');
        return (radio, pass);
      } catch (e) {
        log('$ip: status.cgi falló: $e');
        c.close();
      }
    }
    log('$ip: ninguna clave funcionó');
    return null;
  }

  @override
  Future<Either<Failure, UbntRadio>> detectAndIdentify(
      {String? ip, void Function(String)? onLog}) async {
    final log = onLog ?? ((_) {});
    try {
      final passes = AppSettings.instance.ubntPasses;
      if (passes.isEmpty) {
        return const Left(ValidationFailure(
            'No hay claves guardadas. Ve a Admin -> Radio y escribe al menos '
            'una contraseña para probar.'));
      }
      log('Usuario SSH: "${AppSettings.instance.ubntUser}" · '
          '${passes.length} clave(s) a probar');
      // Sin IP explícita: fábrica -> WiFi del radio (172.1) -> configurada.
      final targets = (ip == null || ip.isEmpty)
          ? AppSettings.instance.ubntCandidateIps
          : <String>[ip];
      for (final t in targets) {
        log('Probando $t ...');
        final found = await _detect(t, log);
        if (found != null) return Right(found.$1);
      }
      return Left(ConnectionFailure(
          'No responde ${targets.join(' ni ')} por SSH/puerto 22-80. '
          'Verifica que el móvil tenga IP 192.168.172.x en el WiFi del radio '
          '(WiFi del radio = 192.168.172.1) o cableado a su LAN.'));
    } catch (e) {
      return Left(DeviceFailure('Error identificando radio: $e'));
    }
  }

  @override
  Future<Either<Failure, String>> diagnose({String? ip}) async {
    final target = (ip == null || ip.isEmpty)
        ? AppSettings.instance.ubntWifiIp
        : ip;
    final b = StringBuffer('Diagnóstico de red hacia $target\n');

    // 1) ¿Tiene el móvil IP? (si no, nada va a funcionar)
    try {
      final ifs = await NetworkInterface.list(
          includeLoopback: false, type: InternetAddressType.IPv4);
      if (ifs.isEmpty) {
        b.writeln('- El móvil NO tiene ninguna IP: reconecta el WiFi '
            '(sin IP no hay ruta al radio).');
      }
      for (final i in ifs) {
        for (final a in i.addresses) {
          b.writeln('- Interfaz ${i.name}: ${a.address}');
        }
      }
    } catch (e) {
      b.writeln('- No se pudieron leer las interfaces: $e');
    }

    // 2) puertos del equipo
    final p22 = await reachability.isTcpOpen(target, 22,
        timeout: const Duration(seconds: 3));
    final p80 = await reachability.isTcpOpen(target, 80,
        timeout: const Duration(seconds: 3));
    b.writeln('- Puerto 22 (SSH): ${p22 ? 'ABIERTO' : 'cerrado'}');
    b.writeln('- Puerto 80 (HTTP): ${p80 ? 'ABIERTO' : 'cerrado'}');

    // 3) si el 80 abre, un GET para confirmar que es equipo de verdad
    if (p80) {
      try {
        final c = HttpClient()..connectionTimeout = const Duration(seconds: 3);
        final req = await c.getUrl(Uri.parse('http://$target/'));
        final res =
            await req.close().timeout(const Duration(seconds: 4));
        b.writeln('- HTTP / -> ${res.statusCode} '
            '(200 o 401 = equipo vivo y hablando)');
        await res.drain<void>();
        c.close(force: true);
      } catch (e) {
        b.writeln('- HTTP / -> sin respuesta ($e)');
      }
    }

    // 4) conclusión accionable
    if (!p22 && !p80) {
      b.writeln('Conclusión: $target no responde en absoluto. '
          'Revisa que el móvil tenga IP 192.168.172.x y que el WiFi al que '
          'te conectaste sea el del radio (no el de tu casa).');
    } else if (!p22 && p80) {
      b.writeln('Conclusión: el equipo responde pero el SSH está CERRADO. '
          'En AirOS: System -> Services -> SSH Server = Enabled, y vuelve a '
          'probar 1. Detectar.');
    } else {
      b.writeln('Conclusión: hay camino al equipo. Dale a 1. Detectar y '
          'revisa el log (clave que usa, modelo y firmware).');
    }
    return Right(b.toString());
  }

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
      final target = AppSettings.instance.fwTarget(radio.isAc);
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
      final client = await _connect(
          radio.ip, AppSettings.instance.ubntUser, sshPass);
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
        onLog('Config aplicada, reiniciando... espera a ${AppSettings.instance.ubntConfiguredIp}');
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
          await _connect(ip, AppSettings.instance.ubntUser, sshPass);
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
