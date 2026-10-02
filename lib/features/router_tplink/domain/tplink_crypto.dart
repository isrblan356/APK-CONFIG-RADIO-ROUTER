import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

/// Port puro de `tplink/tplink.sh` (DES-ECB, key 478DA50BF9E3D2CF) a Dart.
///
/// decode: openssl enc -d -des-ecb -K key -nopad -> salta 16 bytes (md5) ->
///   quita NULs. encode: md5(binario) + input, pad %8 con ceros, cifra.
/// Más `applyConfigEdits`: los `sed` de downloadbackup.sh/newchangepass.sh.
class TplinkCrypto {
  static const desHexKey = '478DA50BF9E3D2CF';
  // Hashes que el firmware nuevo espera en lgn_opswd / lgn_pwd.
  static const oldPassHash = '21232f297a57a5a743894a0e4a801fc3'; // admin/admin
  static const newPassHash = '57a298a940e7713eb606c3b0d77a460a'; // admin/r1nku2015

  static Uint8List _keyBytes() {
    final hex = desHexKey;
    final out = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }

  static Uint8List _crypt(Uint8List data, bool encrypt) {
    final engine = DESedeEngine(); // se usa como DES simple con key de 8 bytes
    // PointyCastle: DES = DESede con k1=k2=k3. Construimos key de 24 bytes.
    final k8 = _keyBytes();
    final k24 = Uint8List(24);
    for (var i = 0; i < 24; i++) {
      k24[i] = k8[i % 8];
    }
    final cipher = ECBBlockCipher(engine)..init(!encrypt, KeyParameter(k24));
    assert(data.length % 8 == 0, 'DES-ECB nopad requiere múltiplo de 8');
    final out = Uint8List(data.length);
    for (var off = 0; off < data.length; off += 8) {
      cipher.processBlock(data, off, out, off);
    }
    // Nota: DESede(k,k,k) == DES(k) bit a bit. Compatible con openssl des-ecb.
    return out;
  }

  /// Decodifica config.bin -> texto (port de decode()).
  static String decode(Uint8List backupBin) {
    final decrypted = _crypt(backupBin, false);
    final withoutMd5 = decrypted.sublist(16);
    final noNuls = withoutMd5.where((b) => b != 0).toList();
    return utf8.decode(noNuls, allowMalformed: true);
  }

  /// Codifica texto -> config.bin listo para subir (port de encode()).
  static Uint8List encode(String configText) {
    // tplink.sh usa el archivo con CRLF (unix2dos). Lo normalizamos aquí
    // igual que `unix2dos -f` de newchangepass.sh.
    final normalized = configText.replaceAll('\r\n', '\n').replaceAll('\n', '\r\n');
    final body = Uint8List.fromList(utf8.encode(normalized));
    final digest = md5.convert(body).bytes;
    final combined = Uint8List(digest.length + body.length)
      ..setAll(0, digest)
      ..setAll(digest.length, body);
    // truncate -s %8 : pad con ceros a múltiplo de 8
    final paddedLen = ((combined.length + 7) ~/ 8) * 8;
    final padded = Uint8List(paddedLen)..setAll(0, combined);
    return _crypt(padded, true);
  }

  /// Aplica los sed de downloadbackup.sh. Devuelve texto editado.
  /// [lanBase] ej "192.168.20." -> lan_ip 192.168.20.2, dhcp 100-199, gw .2
  static String applyConfigEdits(String decoded,
      {required String ssid, required String wifiPass, required String lanBase}) {
    var lanIp = '${lanBase}2';
    String setLine(String text, String key, String value) {
      final re = RegExp('^$key.*', multiLine: true);
      if (re.hasMatch(text)) return text.replaceAll(re, '$key $value');
      return '$text\n$key $value';
    }

    var out = decoded;
    out = setLine(out, 'lan_ip', lanIp);
    out = setLine(out, 'dhcp_en', '0');
    out = setLine(out, 'dhcp_str', '${lanBase}100');
    out = setLine(out, 'dhcp_end', '${lanBase}199');
    out = setLine(out, 'dhcp_gw', lanIp);
    out = setLine(out, 'upnp_en', '0');
    out = setLine(out, 'rmt_en', '1');
    out = setLine(out, 'rmt_ip', '255.255.255.255');
    out = setLine(out, 'sec_bsc', '0');
    out = setLine(out, 'wlan_chnnl', '1');
    out = setLine(out, 'wlan_chanWidth', '1');
    out = setLine(out, 'wlan_rate', '59');
    out = setLine(out, 'wlan_mbssid_str', '1 $ssid');
    out = setLine(out, 'wlan_PskSecret', '1 $wifiPass');
    out = setLine(out, 'wlan_sec_changed', '1 1');
    out = setLine(out, 'wlan_wps_en', '0');
    out = setLine(out, 'lgn_ousr', 'admin');
    out = setLine(out, 'lgn_opswd', oldPassHash);
    out = setLine(out, 'lgn_pwd', newPassHash);
    out = setLine(out, 'igmp_en', '0');
    // quitar CR sueltos y normalizar a CRLF como unix2dos -f
    out = out.replaceAll('\r', '');
    return out;
  }
}
