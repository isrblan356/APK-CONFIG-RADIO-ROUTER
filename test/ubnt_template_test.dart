import 'package:flutter_test/flutter_test.dart';
import 'package:wisp_configurator/features/radio_ubiquiti/domain/template_builder.dart';
import 'package:wisp_configurator/features/radio_ubiquiti/domain/entities/ubnt_radio.dart';
import 'package:wisp_configurator/features/router_tplink/domain/tplink_crypto.dart';

// Regla crítica de final.php 387-393 + roundtrip de tplink.sh.
void main() {
  test('UbntTemplateBuilder reemplaza SSID, WAN y gateway', () {
    const b = UbntTemplateBuilder();
    const template = 'ssid=CHANGESSID\nwan=192.168.80.50\ngw=192.168.80.1\n';
    const params = UbntProvisionParams(
      radioIp: '192.168.1.20',
      ssid: 'rinku_ap1_lapalma',
      network: '192.168.80.',
    );
    final out = b.build(template, params);
    expect(out, contains('rinku_ap1_lapalma'));
    expect(out, isNot(contains('CHANGESSID')));

    const params2 = UbntProvisionParams(
      radioIp: '192.168.1.20',
      ssid: 'x',
      network: '192.168.50.',
    );
    final out2 = b.build(template, params2);
    expect(out2, contains('192.168.50.50'));
    expect(out2, contains('192.168.50.1'));
  });

  test('TplinkCrypto encode->decode roundtrip (port tplink.sh)', () {
    const sample =
        'lan_ip 192.168.0.1\ndhcp_en 1\nwlan_mbssid_str 1 TP-LINK_X\nwlan_PskSecret 1 viejaclave\n';
    final bin = TplinkCrypto.encode(sample);
    expect(bin.length % 8, 0);
    final back = TplinkCrypto.decode(bin);
    expect(back, contains('lan_ip 192.168.0.1'));
    expect(back, contains('TP-LINK_X'));
  });

  test('TplinkCrypto.applyConfigEdits replica los sed de downloadbackup.sh', () {
    const decoded =
        'lan_ip 192.168.0.1\ndhcp_en 1\nwlan_mbssid_str 1 VIEJO\nwlan_PskSecret 1 vieja1234\nlgn_pwd xxx\n';
    final out = TplinkCrypto.applyConfigEdits(decoded,
        ssid: 'MiRed', wifiPass: 'nueva1234', lanBase: '192.168.20.');
    expect(out, contains('lan_ip 192.168.20.2'));
    expect(out, contains('dhcp_en 0'));
    expect(out, contains('wlan_mbssid_str 1 MiRed'));
    expect(out, contains('wlan_PskSecret 1 nueva1234'));
    expect(out, contains('rmt_en 1'));
    expect(out, contains('wlan_wps_en 0'));
    expect(out, contains(TplinkCrypto.newPassHash));
  });
}
