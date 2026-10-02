import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/di/providers.dart';
import '../domain/entities/tplink.dart';

/// Flujo TP-Link: opción 1 (router nuevo 192.168.0.1/admin, full provision)
/// u opción 2 (192.168.20.2, solo clave). Port de 2new.sh.
class TplinkPage extends ConsumerStatefulWidget {
  const TplinkPage({super.key});
  @override
  ConsumerState<TplinkPage> createState() => _TplinkPageState();
}

class _TplinkPageState extends ConsumerState<TplinkPage> {
  TplinkInfo? session;
  bool isNew = true;
  final ssidC = TextEditingController();
  final passC = TextEditingController();
  String log = '';
  bool busy = false;
  void addLog(String s) => setState(() => log = '$log\n$s');

  @override
  void dispose() {
    ssidC.dispose();
    passC.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(tplinkRepoProvider);
    final hist = ref.watch(historyProvider);
    Future<void> saveHist(bool ok, String d) => hist.add('tplink', d, ok);
    return Scaffold(
      appBar: AppBar(title: const Text('Router TP-Link')),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('Nuevo 192.168.0.1'), icon: Icon(Icons.add_box)),
            ButtonSegment(value: false, label: Text('Existente .20.2'), icon: Icon(Icons.edit)),
          ],
          selected: {isNew},
          onSelectionChanged: (v) => setState(() { isNew = v.first; session = null; }),
        ),
        const SizedBox(height: 8),
        ElevatedButton.icon(
          onPressed: busy
              ? null
              : () async {
                  setState(() { busy = true; log = ''; });
                  final r = await repo.connect(isNewRouter: isNew);
                  r.fold((f) => addLog('ERROR: ${f.message}'), (s) {
                    setState(() => session = s);
                    addLog('${s.gen == TplinkGen.modern ? "Moderno" : "Viejo"} HW:${s.hw} FW:${s.fw} LAN:${s.lanIp} SSID:${s.ssid} MAC:${s.wanMac}');
                    if (!isNew) passC.text = '';
                  });
                  setState(() => busy = false);
                },
          icon: const Icon(Icons.link),
          label: Text(isNew ? 'Conectar a 192.168.0.1' : 'Conectar a 192.168.20.2'),
        ),
        if (session != null) ...[
          const Divider(),
          if (isNew)
            TextField(controller: ssidC, decoration: const InputDecoration(labelText: 'Nuevo SSID WiFi')),
          TextField(
              controller: passC,
              decoration: InputDecoration(
                  labelText: isNew ? 'Clave WiFi (8+ chars)' : 'Nueva clave para "${session!.ssid}"')),
          const SizedBox(height: 8),
          if (isNew)
            FilledButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      setState(() => busy = true);
                      final r = await repo.provisionNew(
                          session!,
                          TplinkProvision(option: 1, ssid: ssidC.text.trim(), wifiPass: passC.text),
                          addLog);
                      var ok = false;
                      r.fold((f) => addLog('ERROR: ${f.message}'), (_) {
                        addLog('Router aprovisionado OK.');
                        ok = true;
                      });
                      await saveHist(ok, 'provision ${session!.ip} ssid=${ssidC.text.trim()}');
                      setState(() => busy = false);
                    },
              icon: const Icon(Icons.router),
              label: const Text('Aprovisionar nuevo (WPS/DHCP/UPnP off, remoto on, LAN .20.2)'),
            ),
          if (!isNew)
            FilledButton.icon(
              onPressed: busy
                  ? null
                  : () async {
                      setState(() => busy = true);
                      final r = await repo.changeWifiPass(session!, passC.text, addLog);
                      var ok = false;
                      r.fold((f) => addLog('ERROR: ${f.message}'),
                          (_) { addLog('Clave cambiada + reboot OK.'); ok = true; });
                      await saveHist(ok, 'clave ${session!.ip} ssid=${session!.ssid}');
                      setState(() => busy = false);
                    },
              icon: const Icon(Icons.key),
              label: const Text('Cambiar clave + reiniciar'),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: (busy || !isNew)
                ? null
                : () async {
                    // Plan B: vía config.bin (downloadbackup.sh). Útil si el
                    // firmware bloquea los GETs sueltos o es modelo raro.
                    setState(() => busy = true);
                    final r = await repo.uploadEditedConfig(session!,
                        ssidC.text.trim(), passC.text, '192.168.20.', addLog);
                    var ok = false;
                    r.fold((f) => addLog('ERROR: ${f.message}'),
                        (_) { addLog('Backup/restore OK.'); ok = true; });
                    await saveHist(ok, 'backup-restore ${session!.ip}');
                    setState(() => busy = false);
                  },
            icon: const Icon(Icons.backup),
            label: const Text('Plan B: vía config.bin (backup/restore)'),
          ),
        ],
        const Divider(),
        const Text('Log:', style: TextStyle(fontWeight: FontWeight.bold)),
        Container(
            padding: const EdgeInsets.all(8),
            color: Colors.black87,
            child: Text(log.isEmpty ? '(sin actividad)' : log,
                style: const TextStyle(color: Colors.greenAccent, fontFamily: 'monospace'))),
      ]),
    );
  }
}
