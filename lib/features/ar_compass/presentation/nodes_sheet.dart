import 'package:flutter/material.dart';
import '../data/ar_node_store.dart';
import '../domain/ar_node.dart';
import '../domain/geo.dart';

/// Hoja modal con los nodos: lista por distancia, alta manual, borrado y
/// sync con la nube. Devuelve vía callback el nodo elegido como objetivo.
Future<void> showNodesSheet({
  required BuildContext context,
  required ArNodeStore store,
  required (double, double)? here,
  required ArNode? selected,
  required void Function(ArNode node) onSelected,
  required VoidCallback onChanged,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => NodesSheet(
      store: store,
      here: here,
      selected: selected,
      onSelected: onSelected,
      onChanged: onChanged,
    ),
  );
}

class NodesSheet extends StatefulWidget {
  const NodesSheet({
    super.key,
    required this.store,
    required this.here,
    required this.selected,
    required this.onSelected,
    required this.onChanged,
  });

  final ArNodeStore store;
  final (double, double)? here;
  final ArNode? selected;
  final void Function(ArNode node) onSelected;
  final VoidCallback onChanged;

  @override
  State<NodesSheet> createState() => _NodesSheetState();
}

class _NodesSheetState extends State<NodesSheet> {
  List<ArNode> _nodes = [];
  bool _busy = false;
  String _msg = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _busy = true);
    try {
      final list = await widget.store.list();
      if (!mounted) return;
      setState(() => _nodes = list);
    } catch (e) {
      if (mounted) setState(() => _msg = 'Error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  double? _distTo(ArNode n) {
    final h = widget.here;
    if (h == null) return null;
    return Geo.distanceM(h.$1, h.$2, n.lat, n.lng);
  }

  double? _bearingTo(ArNode n) {
    final h = widget.here;
    if (h == null) return null;
    return Geo.bearing(h.$1, h.$2, n.lat, n.lng);
  }

  Future<void> _sync() async {
    setState(() => _busy = true);
    final r = await widget.store.syncFromCloud();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _msg = r.fold((f) => f.message, (ok) => ok);
    });
    await _load();
    widget.onChanged();
  }

  Future<void> _add() async {
    final created = await showDialog<ArNode>(
      context: context,
      builder: (_) => _AddNodeDialog(here: widget.here),
    );
    if (created == null) return;
    setState(() => _busy = true);
    try {
      await widget.store.addManual(
        nombre: created.nombre,
        lat: created.lat,
        lng: created.lng,
        alt: created.alt,
        zona: created.zona,
      );
      await _load();
      widget.onChanged();
    } catch (e) {
      setState(() => _msg = 'No se pudo guardar: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(ArNode n) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('¿Borrar nodo?'),
        content: Text('${n.nombre}\n${n.lat}, ${n.lng}'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Borrar')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.store.remove(n.localId);
    await _load();
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final here = widget.here;
    final sorted = List<ArNode>.of(_nodes);
    if (here != null) {
      sorted.sort((a, b) {
        final da = _distTo(a) ?? 0, db = _distTo(b) ?? 0;
        return da.compareTo(db);
      });
    } else {
      sorted.sort((a, b) => a.nombre.toLowerCase().compareTo(b.nombre.toLowerCase()));
    }

    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
            child: Row(children: [
              Text('Nodos (${_nodes.length})',
                  style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              IconButton(
                tooltip: 'Agregar manual',
                icon: const Icon(Icons.add),
                onPressed: _busy ? null : _add,
              ),
              IconButton(
                tooltip: 'Sincronizar con la nube',
                icon: const Icon(Icons.cloud_sync),
                onPressed: _busy ? null : _sync,
              ),
            ]),
          ),
          if (here == null)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('Sin posición: se lista alfabéticamente.',
                  style: TextStyle(fontSize: 12)),
            ),
          if (_msg.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(_msg, style: const TextStyle(fontSize: 12)),
            ),
          if (_busy) const LinearProgressIndicator(),
          Expanded(
            child: _nodes.isEmpty
                ? const Center(
                    child: Text(
                        'Sin nodos. Toca + para agregar uno manual\no el nube para bajarlos del servidor.',
                        textAlign: TextAlign.center))
                : ListView.builder(
                    itemCount: sorted.length,
                    itemBuilder: (c, i) {
                      final n = sorted[i];
                      final d = _distTo(n);
                      final b = _bearingTo(n);
                      final sub = <String>[
                        if (d != null) Geo.formatDistance(d),
                        if (b != null)
                          '${b.round()}° ${Geo.compassPoint(b)}',
                        if (n.zona.isNotEmpty) n.zona,
                        n.origen == 'nube' ? 'nube' : 'manual',
                      ].join(' · ');
                      return ListTile(
                        selected: n == widget.selected,
                        leading: Icon(
                          n.origen == 'nube' ? Icons.cloud : Icons.place,
                          color: n == widget.selected
                              ? Theme.of(context).colorScheme.primary
                              : null,
                        ),
                        title: Text(n.nombre),
                        subtitle:
                            Text(sub.isEmpty ? '${n.lat}, ${n.lng}' : sub),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: _busy ? null : () => _remove(n),
                        ),
                        onTap: () {
                          widget.onSelected(n);
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
          ),
        ]),
      ),
    );
  }
}

/// Diálogo de alta manual: nombre + latitud + longitud (+ alt/zona).
class _AddNodeDialog extends StatefulWidget {
  const _AddNodeDialog({required this.here});
  final (double, double)? here;

  @override
  State<_AddNodeDialog> createState() => _AddNodeDialogState();
}

class _AddNodeDialogState extends State<_AddNodeDialog> {
  final _form = GlobalKey<FormState>();
  final _nombre = TextEditingController();
  final _lat = TextEditingController();
  final _lng = TextEditingController();
  final _alt = TextEditingController();
  final _zona = TextEditingController();

  @override
  void dispose() {
    _nombre.dispose();
    _lat.dispose();
    _lng.dispose();
    _alt.dispose();
    _zona.dispose();
    super.dispose();
  }

  static double? _parse(String s) =>
      double.tryParse(s.trim().replaceAll(',', '.'));

  String? _coord(String v, double min, double max, String label) {
    final n = _parse(v);
    if (n == null) return 'Inválida';
    if (n < min || n > max) return '$label entre $min y $max';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nodo manual'),
      content: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            TextFormField(
              controller: _nombre,
              decoration: const InputDecoration(labelText: 'Nombre'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Requerido' : null,
            ),
            TextFormField(
              controller: _lat,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Latitud', hintText: '6.123456'),
              validator: (v) => _coord(v ?? '', -90, 90, 'Latitud'),
            ),
            TextFormField(
              controller: _lng,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                  labelText: 'Longitud', hintText: '-75.536000'),
              validator: (v) => _coord(v ?? '', -180, 180, 'Longitud'),
            ),
            TextFormField(
              controller: _alt,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration:
                  const InputDecoration(labelText: 'Altitud m (opcional)'),
              validator: (v) =>
                  (v ?? '').trim().isEmpty || _parse(v!) != null
                      ? null
                      : 'Número',
            ),
            TextFormField(
              controller: _zona,
              decoration:
                  const InputDecoration(labelText: 'Zona (opcional)'),
            ),
            if (widget.here != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.my_location, size: 16),
                  label: const Text('Usar mi posición'),
                  onPressed: () {
                    _lat.text = widget.here!.$1.toStringAsFixed(6);
                    _lng.text = widget.here!.$2.toStringAsFixed(6);
                  },
                ),
              ),
          ]),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar')),
        FilledButton(
          onPressed: () {
            if (!(_form.currentState?.validate() ?? false)) return;
            Navigator.pop(
              context,
              ArNode(
                nombre: _nombre.text.trim(),
                lat: _parse(_lat.text)!,
                lng: _parse(_lng.text)!,
                alt: _parse(_alt.text),
                zona: _zona.text.trim(),
              ),
            );
          },
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
