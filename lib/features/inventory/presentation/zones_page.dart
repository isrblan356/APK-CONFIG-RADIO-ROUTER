import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/di/providers.dart';
import '../domain/entities.dart';

/// Selector Zona -> AP. Equivale al menú a1/b1 de final.php
/// pero con la DB ya dentro del móvil (assets/seed/nodos.db).
class ZonesPage extends ConsumerStatefulWidget {
  const ZonesPage({super.key});
  @override
  ConsumerState<ZonesPage> createState() => _ZonesPageState();
}

class _ZonesPageState extends ConsumerState<ZonesPage> {
  List<Zone> zones = [];
  final Map<int, List<AccessPoint>> apsByZone = {};
  final Map<int, String> apsError = {};
  final Set<int> loadingAps = {};
  String? error;
  bool loading = true;
  bool syncing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    final r = await ref.read(inventoryProvider).zones();
    if (!mounted) return;
    setState(() {
      loading = false;
      r.fold((f) {
        error = f.message;
        zones = [];
      }, (z) => zones = z);
    });
  }

  Future<void> _loadAps(Zone z) async {
    if (apsByZone.containsKey(z.id) || loadingAps.contains(z.id)) return;
    setState(() => loadingAps.add(z.id));
    final r = await ref.read(inventoryProvider).aps(z.id.toString());
    if (!mounted) return;
    setState(() {
      loadingAps.remove(z.id);
      r.fold((f) {
        apsError[z.id] = f.message;
        apsByZone[z.id] = [];
      }, (list) {
        apsError.remove(z.id);
        apsByZone[z.id] = list;
      });
    });
  }

  Future<void> _sync() async {
    setState(() => syncing = true);
    final r = await ref.read(inventoryProvider).syncFromCloud();
    if (!mounted) return;
    setState(() => syncing = false);
    apsByZone.clear();
    apsError.clear();
    r.fold((f) => snack(f.message),
        (_) => snack('Nube sincronizada. Inventario actualizado.'));
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Zonas / APs (offline)')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: loading
            ? ListView(children: const [
                SizedBox(height: 160),
                Center(child: CircularProgressIndicator()),
              ])
            : error != null
                ? ListView(children: [
                    const SizedBox(height: 120),
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(children: [
                        const Icon(Icons.cloud_off, size: 48),
                        const SizedBox(height: 8),
                        Text('Error: $error', textAlign: TextAlign.center),
                        const SizedBox(height: 8),
                        FilledButton(
                            onPressed: _load,
                            child: const Text('Reintentar')),
                      ]),
                    ),
                  ])
                : ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: zones.length,
                    itemBuilder: (_, i) {
                      final z = zones[i];
                      return ExpansionTile(
                        onExpansionChanged: (open) {
                          if (open) _loadAps(z);
                        },
                        title: Text('${z.id} - ${z.name}'),
                        subtitle: Text('Red ${z.network}0/24 · WAN .50 GW .1'),
                        children: [_apSection(z)],
                      );
                    },
                  ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: syncing ? null : _sync,
        label: Text(syncing ? 'Sincronizando...' : 'Sync nube'),
        icon: syncing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.cloud_sync),
      ),
    );
  }

  Widget _apSection(Zone z) {
    if (loadingAps.contains(z.id)) {
      return const ListTile(
          leading: SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2)),
          title: Text('Cargando APs...'));
    }
    final err = apsError[z.id];
    if (err != null) {
      return ListTile(
          leading: const Icon(Icons.error, color: Colors.red),
          title: Text('Error: $err'));
    }
    final list = apsByZone[z.id] ?? const <AccessPoint>[];
    if (list.isEmpty) {
      return const ListTile(
          leading: Icon(Icons.cell_tower),
          title: Text('Sin APs en esta zona'),
          subtitle: Text('Usa "Sync nube" o importa nodos.db'));
    }
    return Column(
      children: list
          .map((a) => ListTile(
                dense: true,
                leading: const Icon(Icons.cell_tower),
                title: Text(a.name),
                subtitle: Text('SSID: ${a.ssid} · WAN: ${z.network}50'),
                trailing: Text('#${a.nodeId}'),
              ))
          .toList(),
    );
  }
}
