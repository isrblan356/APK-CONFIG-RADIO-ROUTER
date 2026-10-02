import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/di/providers.dart';
import '../domain/entities.dart';

/// Bitácora de campo: cada detección/provision/reset queda registrada.
class HistoryPage extends ConsumerStatefulWidget {
  const HistoryPage({super.key});
  @override
  ConsumerState<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends ConsumerState<HistoryPage> {
  List<OpLog> items = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await ref.read(historyProvider).recent();
    if (!mounted) return;
    setState(() {
      items = list;
      loading = false;
    });
  }

  Future<void> _clear() async {
    await ref.read(historyProvider).clear();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Historial (en el móvil)'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualizar',
            onPressed: loading ? null : _load,
          ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Borrar todo',
            onPressed: items.isEmpty ? null : _clear,
          ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : items.isEmpty
              ? const Center(child: Text('Sin operaciones todavía.'))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    itemCount: items.length,
                    itemBuilder: (_, i) {
                      final e = items[i];
                      return ListTile(
                        leading: Icon(
                            e.ok ? Icons.check_circle : Icons.error,
                            color: e.ok ? Colors.green : Colors.red),
                        title: Text('[${e.kind}] ${e.detail}',
                            maxLines: 3, overflow: TextOverflow.ellipsis),
                        subtitle: Text(e.at.toLocal().toString()),
                      );
                    },
                  ),
                ),
    );
  }
}
