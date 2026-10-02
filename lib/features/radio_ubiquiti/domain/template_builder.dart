import '../../core/config/app_config.dart';
import 'entities/ubnt_radio.dart';

/// Builder puro (sin Flutter, testeable). Regla exacta de final.php 387-393.
class UbntTemplateBuilder {
  const UbntTemplateBuilder();

  String build(String templateRaw, UbntProvisionParams p) {
    return templateRaw
        .replaceAll('CHANGESSID', p.ssid)
        .replaceAll(AppConfig.templateGwPlaceholder, p.newGateway)
        .replaceAll(AppConfig.templateWanPlaceholder, p.newWan);
  }
}
