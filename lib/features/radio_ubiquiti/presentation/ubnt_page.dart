import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/config/app_settings.dart';
import '../../../core/di/providers.dart';
import '../../inventory/domain/entities.dart';
import '../domain/entities/ubnt_radio.dart';

/// Flujo: 1) Detectar radio 2) Elegir Zona/AP 3) Subir firmware+config o Reset.
/// Port del menú 1/2/3 de final.php.
class UbntPage extends ConsumerStatefulWidget {
  const UbntPage({super.key});
  @override
  ConsumerState<UbntPage> createState() => _UbntPageState();
}

class _UbntPageState extends ConsumerState<UbntPage> {
  UbntRadio? radio;
  String sshPass = 'ubnt';
  String ipChoice = 'auto'; // 'auto' o una IP fija (ej. 192.168.172.1)
  Zone? zone;
  AccessPoint? ap;
  String log = '';
  bool busy = false;

  // Inventario cacheado: sin FutureBuilder, así los rebuilds no reconsultan.
  List<Zone> zones = [];
  List<AccessPoint> aps = [];
  bool loadingZones = true;
  bool loadingAps = false;
  String? zonesError;

  void addLog(String s) => setState(() => log = '$log\n$s');

  @override
  void initState() {
    super.initState();
    _loadZones();
  }

  Future<void> _loadZones() async {
    setState(() {
      loadingZones = true;
      zonesError = null;
    });
    final r = await ref.read(inventoryProvider).zones();
    if (!mounted) return;
    setState(() {
      loadingZones = false;
      r.fold((f) {
        zonesError = f.message;
        zones = [];
      }, (list) {
        zones = list;
        if (zone != null && !zones.contains(zone)) {
          zone = null;
          ap = null;
        }
      });
    });
  }

  Future<void> _loadAps(Zone z) async {
    setState(() {
      loadingAps = true;
      aps = [];
      ap = null;
    });
    final r = await ref.read(inventoryProvider).aps(z.id.toString());
    if (!mounted) return;
    final err = r.fold<String?>((f) => f.message, (_) => null);
    final list = r.getOrElse(() => const <AccessPoint>[]);
    setState(() {
      loadingAps = false;
      aps = list;
    });
    if (err != null) addLog('ERROR APs: $err');
  }

  @override
  Widget build(BuildContext context) {
    final ubnt = ref.watch(ubntRepoProvider);
    final hist = ref.watch(historyProvider);
    final canProvision =
        !busy && radio != null && zone != null && ap != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Radio Ubiquiti'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Recargar zonas',
            onPressed: busy || loadingZones ? null : _loadZones,
          )
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Wrap(spacing: 8, children: [
          ElevatedButton.icon(
            onPressed: busy
                ? null
                : () async {
                    setState(() {
                      busy = true;
                      log = '';
                    });
                    final r = await ubnt.detectAndIdentify(
                        ip: ipChoice == 'auto' ? null : ipChoice);
                    r.fold(
                      (f) => addLog('ERROR: ${f.message}'),
                      (rad) {
                        setState(() => radio = rad);
                        addLog(
                            'OK (${rad.model}) FW:${rad.firmware} IP:${rad.ip} LAN:${rad.lanSpeedDuplex}');
                        final fwObj = AppSettings.instance.fwTarget(rad.isAc);
                        if (rad.needsFirmwareUpdate(fwObj)) {
                          addLog('Aviso: firmware distinto al objetivo ($fwObj)');
                        }
                      },
                    );
                    setState(() => busy = false);
                  },
            icon: const Icon(Icons.search),
            label: const Text('1. Detectar radio'),
          ),
          ElevatedButton.icon(
            onPressed: (busy || radio == null)
                ? null
                : () async {
                    setState(() => busy = true);
                    await ubnt.updateFirmwareIfNeeded(radio!, sshPass, addLog);
                    setState(() => busy = false);
                  },
            icon: const Icon(Icons.system_update),
            label: const Text('2. Firmware'),
          ),
        ]),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          // initialValue + key: así el campo refleja cambios externos de estado
          // (value: quedó deprecado en Flutter 3.33+).
          key: ValueKey('ip-$ipChoice'),
          initialValue: ipChoice,
          items: [
            const DropdownMenuItem(
                value: 'auto', child: Text('Auto (fábrica → WiFi → config.)')),
            DropdownMenuItem(
                value: AppSettings.instance.ubntWifiIp,
                child: Text(
                    '${AppSettings.instance.ubntWifiIp} (WiFi del radio)')),
            DropdownMenuItem(
                value: AppSettings.instance.ubntDefaultIp,
                child: Text('${AppSettings.instance.ubntDefaultIp} (fábrica)')),
            DropdownMenuItem(
                value: AppSettings.instance.ubntConfiguredIp,
                child: Text(
                    '${AppSettings.instance.ubntConfiguredIp} (ya configurada)')),
          ],
          onChanged: (v) => setState(() => ipChoice = v ?? 'auto'),
          decoration: const InputDecoration(labelText: 'IP del radio (destino)'),
        ),
        DropdownButtonFormField<String>(
          key: ValueKey('ssh-$sshPass'),
          initialValue: sshPass,
          items: AppSettings.instance.ubntPasses
              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
              .toList(),
          onChanged: (v) =>
              setState(() => sshPass = v ?? AppSettings.instance.ubntUser),
          decoration: const InputDecoration(labelText: 'Clave SSH (prueba en orden)'),
        ),
        const Divider(),
        if (loadingZones)
          const Padding(
            padding: EdgeInsets.all(12),
            child: LinearProgressIndicator(),
          )
        else if (zonesError != null)
          Text('Error zonas: $zonesError')
        else
          DropdownButtonFormField<Zone>(
            key: ValueKey(zone),
            initialValue: zones.contains(zone) ? zone : null,
            items: zones
                .map((z) => DropdownMenuItem(
                    value: z, child: Text('${z.id} - ${z.name}')))
                .toList(),
            onChanged: (v) {
              setState(() => zone = v);
              if (v != null) _loadAps(v);
            },
            decoration: const InputDecoration(labelText: 'Zona (equivale a menú a1)'),
          ),
        if (zone != null)
          loadingAps
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: LinearProgressIndicator(),
                )
              : DropdownButtonFormField<AccessPoint>(
                  key: ValueKey(ap),
                  initialValue: aps.contains(ap) ? ap : null,
                  items: aps
                      .map((a) => DropdownMenuItem(
                          value: a,
                          child: Text('${a.nodeId} - ${a.name}')))
                      .toList(),
                  onChanged: (v) => setState(() => ap = v),
                  decoration:
                      const InputDecoration(labelText: 'AP destino (menú b1)'),
                ),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: !canProvision
                  ? null
                  : () async {
                      setState(() => busy = true);
                      final res = await ubnt.uploadConfigAndApply(
                        UbntProvisionParams(
                          radioIp: radio!.ip,
                          ssid: ap!.ssid,
                          network: zone!.network,
                          sshPass: sshPass,
                          wanSuffix: AppSettings.instance.wanSuffix,
                          gwSuffix: AppSettings.instance.gwSuffix,
                        ),
                        addLog,
                      );
                      res.fold(
                        (f) => addLog('ERROR: ${f.message}'),
                        (_) => addLog('COMPLETADO. LAN: ${radio!.lanSpeedDuplex}'),
                      );
                      await hist.add(
                          'ubnt',
                          'radio ${radio!.ip} ${radio!.model} -> ${ap!.ssid} '
                          '${AppSettings.instance.wanIp(zone!.network)}',
                          res.isRight());
                      setState(() => busy = false);
                    },
              icon: const Icon(Icons.upload),
              label: const Text('3. Subir config + reiniciar'),
            ),
          ),
        ]),
        TextButton.icon(
          onPressed: (busy || radio == null)
              ? null
              : () async {
                  setState(() => busy = true);
                  final r = await ubnt.factoryReset(radio!.ip, sshPass);
                  r.fold((f) => addLog('ERROR: ${f.message}'),
                      (_) => addLog('Reset enviado, reiniciando...'));
                  await hist.add('ubnt', 'reset ${radio!.ip}', r.isRight());
                  setState(() => busy = false);
                },
          icon: const Icon(Icons.restore),
          label: const Text('Reset a fábrica (opción 1 de final.php)'),
        ),
        const Divider(),
        const Text('Log:', style: TextStyle(fontWeight: FontWeight.bold)),
        Container(
          padding: const EdgeInsets.all(8),
          color: Colors.black87,
          child: Text(log.isEmpty ? '(sin actividad)' : log,
              style: const TextStyle(color: Colors.greenAccent, fontFamily: 'monospace')),
        ),
      ]),
    );
  }
}
