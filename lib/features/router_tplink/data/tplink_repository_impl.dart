import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:dartz/dartz.dart';
import 'package:http/http.dart' as http;
import '../../../core/config/app_settings.dart';
import '../../../core/error/failures.dart';
import '../domain/entities/tplink.dart';
import '../domain/tplink_crypto.dart';

abstract class TplinkRepository {
  Future<Either<Failure, TplinkInfo>> connect({required bool isNewRouter});
  Future<Either<Failure, TplinkInfo>> getInfo(TplinkInfo session);
  Future<Either<Failure, void>> provisionNew(TplinkInfo session, TplinkProvision p, void Function(String) log);
  Future<Either<Failure, void>> changeWifiPass(TplinkInfo session, String newPass, void Function(String) log);
  /// Vía backup config.bin (port de downloadbackup.sh): descarga, decodifica
  /// con DES-ECB, edita SSID/clave/LAN, recifra y sube. Funciona aunque el
  /// router bloquee los GETs individuales de provisionNew.
  Future<Either<Failure, String>> downloadDecodedConfig(TplinkInfo session);
  Future<Either<Failure, void>> uploadEditedConfig(
      TplinkInfo session, String ssid, String wifiPass, String lanBase, void Function(String) log);
}

/// Port fiel de 2new.sh / newchangepass.sh a Dart con paquete http.
///
/// Login moderno TP-Link:
///   md5(pass) -> base64("admin:md5") -> urlencode -> cookie Authorization
///   GET http://IP/userRpm/LoginRpm.htm?Save=Save (x4) -> extrae KEY del HTML
///   GET http://IP/KEY/userRpm/StatusRpm.htm con cookie+referer
/// Si no hay "System Up Time" -> es viejo: Basic Auth admin:pass sin KEY.
class TplinkRepositoryImpl implements TplinkRepository {
  final http.Client client;
  TplinkRepositoryImpl(this.client);

  String _md5(String s) => md5.convert(utf8.encode(s)).toString();

  String _authCookie(String pass) {
    final h = _md5(pass);
    final b64 = base64.encode(utf8.encode('admin:$h'));
    // rawurlencode("Basic <b64>")
    return Uri.encodeComponent('Basic $b64');
  }

  Future<String> _loginKey(String ip, String cookie) async {
    final url = Uri.parse('http://$ip/userRpm/LoginRpm.htm?Save=Save');
    String key = '';
    // Los .sh lo intentan 4 veces (la cookie se "pega" en el router).
    for (var i = 0; i < 4; i++) {
      final r = await client.get(url, headers: {'Cookie': 'Authorization=$cookie'});
      final m = RegExp(r'/([A-Za-z0-9]{8,})/').firstMatch(r.body);
      if (m != null) key = m.group(1)!;
    }
    return key;
  }

  TplinkInfo _parseStatus(String ip, TplinkGen gen, String key, String html) {
    // Los .sh hacen: split </SCRIPT> y ';', buscan var ... status / lanPara / wlanPara / wanPara.
    // Aquí regex equivalentes, más robusto en móvil.
    // statusPara: la posición 6=fw, 7=hw en la mayoría de firmwares (ver .sh cut -f6/-f7)
    final statusLine = RegExp(r'var\s+statusPara\s*=\s*new\s+Array\(([^)]+)\)').firstMatch(html);
    String fw = '', hw = '';
    if (statusLine != null) {
      final parts = (statusLine.group(1) ?? '').split(',');
      String clean(int i) => i < parts.length ? parts[i].replaceAll('"', '').trim() : '';
      // En tus scripts: f6=firmware, f7=hardware (1-indexed en cut).
      fw = clean(5);
      hw = clean(6);
    }
    final lanM = RegExp(r'var\s+lanPara\s*=\s*new\s+Array\(([^)]+)\)').firstMatch(html);
    var lanIp = '';
    if (lanM != null) {
      final parts = (lanM.group(1) ?? '').split(',');
      if (parts.length > 1) lanIp = parts[1].replaceAll('"', '').trim();
    }
    final wlanM = RegExp(r'var\s+wlanPara\s*=\s*new\s+Array\(([^)]+)\)').firstMatch(html);
    var ssid = '';
    if (wlanM != null) {
      final parts = (wlanM.group(1) ?? '').split(',');
      if (parts.length > 1) ssid = parts[1].replaceAll('"', '').trim();
    }
    final wanM = RegExp(r'var\s+wanPara\s*=\s*new\s+Array\(([^)]+)\)').firstMatch(html);
    var mac = '';
    if (wanM != null) {
      final parts = (wanM.group(1) ?? '').split(',');
      if (parts.length > 1) mac = parts[1].replaceAll('"', '').trim();
    }
    return TplinkInfo(ip: ip, gen: gen, key: key, hw: hw, fw: fw, lanIp: lanIp, ssid: ssid, wanMac: mac);
  }

  Future<http.Response> _get(TplinkInfo s, String passOrCookie, String path) {
    final url = Uri.parse('${s.baseUrl}$path');
    if (s.gen == TplinkGen.modern) {
      final cookie = _authCookie(passOrCookie);
      return client.get(url, headers: {
        'Cookie': 'Authorization=$cookie',
        'Referer': s.baseUrl,
      });
    } else {
      final basic = base64.encode(utf8.encode('admin:$passOrCookie'));
      return client.get(url, headers: {
        'Authorization': 'Basic $basic',
        'Referer': s.baseUrl,
      });
    }
  }

  @override
  Future<Either<Failure, TplinkInfo>> connect({required bool isNewRouter}) async {
    try {
      final ip = isNewRouter
          ? AppSettings.instance.tplinkNewIp
          : AppSettings.instance.tplinkConfiguredIp;
      final pass = isNewRouter
          ? AppSettings.instance.tplinkNewPass
          : AppSettings.instance.tplinkConfiguredPass;
      final cookie = _authCookie(pass);
      final key = await _loginKey(ip, cookie);

      // Intento moderno
      if (key.isNotEmpty) {
        final url = Uri.parse('http://$ip/$key/userRpm/StatusRpm.htm');
        final r = await client.get(url, headers: {
          'Cookie': 'Authorization=$cookie',
          'Referer': 'http://$ip/$key',
        });
        if (r.body.contains('System Up Time')) {
          return Right(_parseStatus(ip, TplinkGen.modern, key, r.body));
        }
      }
      // Fallback viejo (Basic Auth sin KEY)
      final basic = base64.encode(utf8.encode('admin:$pass'));
      final rOld = await client.get(
        Uri.parse('http://$ip/userRpm/StatusRpm.htm'),
        headers: {'Authorization': 'Basic $basic', 'Referer': 'http://$ip'},
      );
      if (rOld.body.contains('System Up Time')) {
        return Right(_parseStatus(ip, TplinkGen.old, '', rOld.body));
      }
      return Left(ConnectionFailure(
          'No se conectó al TP-Link. Verifica IP (${AppSettings.instance.tplinkNewIp} nuevo / '
          '${AppSettings.instance.tplinkConfiguredIp} configurado) y que el móvil esté en su WiFi.'));
    } catch (e) {
      return Left(DeviceFailure('Error conectando TP-Link: $e'));
    }
  }

  @override
  Future<Either<Failure, TplinkInfo>> getInfo(TplinkInfo session) async {
    // connect() ya trae el status; se expone por simetría limpia.
    return Right(session);
  }

  Future<String> _getWithSession(TplinkInfo s, String pass, String path) async {
    final res = await _get(s, pass, path);
    return res.body;
  }

  @override
  Future<Either<Failure, void>> provisionNew(
      TplinkInfo s, TplinkProvision p, void Function(String) log) async {
    try {
      if (p.wifiPass.length < 8) {
        return const Left(ValidationFailure('La clave WiFi debe tener 8+ caracteres.'));
      }
      // Pass actual de sesión: si es IP nueva es admin, si no la configurada.
      final sessionPass = s.ip == AppSettings.instance.tplinkNewIp
          ? AppSettings.instance.tplinkNewPass
          : AppSettings.instance.tplinkConfiguredPass;
      // Pass con la que queda el router al terminar (editable en Admin).
      final np = AppSettings.instance.tplinkConfiguredPass;
      final npEnc = Uri.encodeComponent(base64.encode(utf8.encode(np)));
      final adminEnc = Uri.encodeComponent(base64.encode(utf8.encode('admin')));

      // 1) Cambiar password admin (port líneas 254-260 de 2new.sh)
      log('Cambiando password admin...');
      if (s.gen == TplinkGen.old) {
        await _getWithSession(s, sessionPass,
            '/userRpm/ChangeLoginPwdRpm.htm?oldname=admin&oldpassword=admin'
            '&newname=admin&newpassword=$np&newpassword2=$np&Save=Save');
      } else {
        // Hashes en base64 que espera el firmware nuevo (admin -> actual).
        await _getWithSession(s, sessionPass,
            '/userRpm/ChangeLoginPwdRpm.htm?oldname=admin&oldpassword=$adminEnc'
            '&newname=admin&newpassword=$npEnc&newpassword2=$npEnc&Save=Save');
      }

      // A partir de aquí el pass es np. Reconstruimos sesión con nueva KEY.
      final newCookie = _authCookie(np);
      var newKey = s.key;
      if (s.gen == TplinkGen.modern) {
        newKey = await _loginKey(s.ip, newCookie);
        if (newKey.isEmpty) newKey = s.key;
      }
      final ns = TplinkInfo(
          ip: s.ip, gen: s.gen, key: newKey,
          hw: s.hw, fw: s.fw, lanIp: s.lanIp, ssid: s.ssid, wanMac: s.wanMac);
      final ssidEnc = Uri.encodeComponent(p.ssid);
      final passEnc = Uri.encodeComponent(p.wifiPass);

      Future<void> call(String label, String path) async {
        log(label);
        await _get(ns, np, path);
      }

      // Secuencia exacta de 2new.sh: WPS off, DHCP off, UPNP off, remote-mgmt on,
      // SSID, WPA2-PSK/AES, LAN 192.168.20.2
      await call('Deshabilitando WPS...', '/userRpm/WpsCfgRpm.htm?DisWps=Disable+WPS');
      await call('Deshabilitando DHCP...',
          '/userRpm/LanDhcpServerRpm.htm?dhcpserver=0&ip1=192.168.0.100&ip2=192.168.0.199&Lease=120&gateway=192.168.0.1&domain=&dnsserver=0.0.0.0&dnsserver2=0.0.0.0&Save=Save');
      await call('Deshabilitando UPnP...',
          '/userRpm/UpnpCfgRpm.htm?upnpenb=Disable&Upnpdisable=Disable');
      await call('Habilitando gestión remota...',
          '/userRpm/ManageControlRpm.htm?port=80&ip=255.255.255.255&Save=Save');
      await call('Creando SSID ${p.ssid}...',
          '/userRpm/WlanNetworkRpm.htm?ssid1=$ssidEnc&ssid2=TP-LINK_GUEST_DBC6&ssid3=TP-LINK_DBC6_3&ssid4=TP-LINK_DBC6_4&region=101&band=0&mode=5&chanWidth=1&channel=1&rate=59&ap=1&broadcast=2&brlssid=&brlbssid=&addrType=1&keytype=1&wepindex=1&authtype=1&keytext=&Save=Save');
      await call('Clave WiFi...',
          '/userRpm/WlanSecurityRpm.htm?secType=3&pskSecOpt=2&pskCipher=3&pskSecret=$passEnc&interval=0&wpaSecOpt=3&wpaCipher=1&intervalWpa=0&wepSecOpt=3&keytype=1&keynum=1&key1=&length1=0&key2=&length2=0&key3=&length3=0&key4=&length4=0&Save=Save');
      await call('LAN -> ${AppSettings.instance.tplinkTargetLanIp} (reinicia el router)...',
          '/userRpm/NetworkCfgRpm.htm?lantype=0&lanip=${AppSettings.instance.tplinkTargetLanIp}&lanmask=2&inputMask=255.255.255.0&langw=0.0.0.0&igmpEn=0&Save=Save&igmpChanged=0');

      log('Listo. El router reiniciará y quedará en ${AppSettings.instance.tplinkTargetLanIp}.');
      return const Right(null);
    } catch (e) {
      return Left(DeviceFailure('Error aprovisionando TP-Link: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> changeWifiPass(
      TplinkInfo s, String newPass, void Function(String) log) async {
    try {
      if (newPass.length < 8) {
        return const Left(ValidationFailure('La clave debe tener 8+ caracteres.'));
      }
      final sessionPass = s.ip == AppSettings.instance.tplinkNewIp
          ? AppSettings.instance.tplinkNewPass
          : AppSettings.instance.tplinkConfiguredPass;
      final enc = Uri.encodeComponent(newPass);
      log('Cambiando clave de "${s.ssid}"...');
      await _get(s, sessionPass,
          '/userRpm/WlanSecurityRpm.htm?secType=3&pskSecOpt=2&pskCipher=3&pskSecret=$enc&interval=0&wpaSecOpt=3&wpaCipher=1&intervalWpa=0&wepSecOpt=3&keytype=1&keynum=1&key1=&length1=0&key2=&length2=0&key3=&length3=0&key4=&length4=0&Save=Save');
      log('Reiniciando...');
      await _get(s, sessionPass, '/userRpm/SysRebootRpm.htm?Reboot=Reboot');
      return const Right(null);
    } catch (e) {
      return Left(DeviceFailure('Error cambiando clave: $e'));
    }
  }

  String _sessionPass(TplinkInfo s) => s.ip == AppSettings.instance.tplinkNewIp
      ? AppSettings.instance.tplinkNewPass
      : AppSettings.instance.tplinkConfiguredPass;

  @override
  Future<Either<Failure, String>> downloadDecodedConfig(TplinkInfo s) async {
    try {
      final pass = _sessionPass(s);
      final cookie = _authCookie(pass);
      final ref = s.baseUrl;
      http.Response dl;
      if (s.gen == TplinkGen.modern) {
        dl = await client.get(Uri.parse('${s.baseUrl}/userRpm/config.bin'),
            headers: {'Cookie': 'Authorization=$cookie', 'Referer': ref});
      } else {
        final basic = base64.encode(utf8.encode('admin:$pass'));
        dl = await client.get(Uri.parse('${s.baseUrl}/userRpm/config.bin'),
            headers: {'Authorization': 'Basic $basic', 'Referer': ref});
      }
      if (dl.bodyBytes.length < 24) {
        return const Left(DeviceFailure('config.bin vacío o no autorizado.'));
      }
      return Right(TplinkCrypto.decode(Uint8List.fromList(dl.bodyBytes)));
    } catch (e) {
      return Left(DeviceFailure('Error descargando config.bin: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> uploadEditedConfig(TplinkInfo s, String ssid,
      String wifiPass, String lanBase, void Function(String) log) async {
    try {
      if (wifiPass.length < 8) {
        return const Left(ValidationFailure('La clave debe tener 8+ caracteres.'));
      }
      log('Descargando config.bin...');
      final dec = await downloadDecodedConfig(s);
      return await dec.fold(
        (f) async => Left(f),
        (text) async {
          log('Editando (SSID=$ssid LAN=${lanBase}2)...');
          final edited = TplinkCrypto.applyConfigEdits(text,
              ssid: ssid, wifiPass: wifiPass, lanBase: lanBase);
          final bin = TplinkCrypto.encode(edited);
          final pass = _sessionPass(s);
          final cookie = _authCookie(pass);
          final ref = '${s.baseUrl}/userRpm/BakNRestoreRpm.htm';
          final upUrl = Uri.parse('${s.baseUrl}/incoming/RouterBakCfgUpload.cfg');
          final req = http.MultipartRequest('POST', upUrl)
            ..fields['name'] = 'filename'
            ..files.add(http.MultipartFile.fromBytes('filename', bin,
                filename: 'config.bin'));
          if (s.gen == TplinkGen.modern) {
            req.headers['Cookie'] = 'Authorization=$cookie';
          } else {
            req.headers['Authorization'] =
                'Basic ${base64.encode(utf8.encode('admin:$pass'))}';
          }
          req.headers['Referer'] = ref;
          log('Subiendo config.bin (${bin.length} bytes)...');
          final streamed = await client.send(req);
          await streamed.stream.bytesToString();
          await _get(s, pass, '/userRpm/ConfUpdateTemp.htm');
          log('Config aplicada. El router reiniciará.');
          return const Right(null);
        },
      );
    } catch (e) {
      return Left(DeviceFailure('Error en backup/restore: $e'));
    }
  }
}
