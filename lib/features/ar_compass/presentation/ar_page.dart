import 'dart:async';
import 'dart:math' as math;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';
import '../../../core/di/providers.dart';
import '../domain/ar_node.dart';
import '../domain/geo.dart';
import 'nodes_sheet.dart';

/// Módulo AR / brújula: con la cámara (o una mira simple) indica hacia dónde
/// apuntar la antena y a qué distancia está el nodo elegido.
///
/// Sensores: acelerómetro + magnetómetro -> rumbo (Geo.headingFromSensors).
/// Posición: GPS (geolocator) con respaldo de posición manual.
/// Nodos: locales (ArNodeStore) + sync opcional con la nube.
class ArPage extends ConsumerStatefulWidget {
  const ArPage({super.key});
  @override
  ConsumerState<ArPage> createState() => _ArPageState();
}

class _ArPageState extends ConsumerState<ArPage> {
  // Cámara
  CameraController? _cam;
  String _camMsg = '';

  // Sensores
  double? _heading;
  double? _ax, _ay, _az, _mx, _my, _mz;
  DateTime _lastHeading = DateTime.fromMillisecondsSinceEpoch(0);

  // Posición
  Position? _pos;
  (double, double)? _manualPos;
  String _msg = '';

  // Nodos
  List<ArNode> _nodes = [];
  ArNode? _target;

  StreamSubscription<AccelerometerEvent>? _accSub;
  StreamSubscription<MagnetometerEvent>? _magSub;
  StreamSubscription<Position>? _posSub;

  /// FOV horizontal aproximado para posicionar el marcador en la imagen.
  static const _fovDeg = 60.0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    _initSensors();
    _loadNodes();
    await _initLocation();
    await _initCamera();
  }

  @override
  void dispose() {
    _accSub?.cancel();
    _magSub?.cancel();
    _posSub?.cancel();
    _cam?.dispose();
    super.dispose();
  }

  // ---------- datos ----------

  Future<void> _loadNodes() async {
    try {
      final list = await ref.read(arNodeStoreProvider).list();
      if (!mounted) return;
      setState(() {
        _nodes = list;
        if (_target != null && !list.contains(_target)) _target = null;
        _autoTarget();
      });
    } catch (e) {
      if (mounted) setState(() => _msg = 'Nodos: $e');
    }
  }

  (double, double)? get _here => _pos != null
      ? (_pos!.latitude, _pos!.longitude)
      : _manualPos;

  double? get _distToTarget {
    final h = _here;
    final t = _target;
    if (h == null || t == null) return null;
    return Geo.distanceM(h.$1, h.$2, t.lat, t.lng);
  }

  double? get _bearingToTarget {
    final h = _here;
    final t = _target;
    if (h == null || t == null) return null;
    return Geo.bearing(h.$1, h.$2, t.lat, t.lng);
  }

  void _autoTarget() {
    if (_target != null || _nodes.isEmpty) return;
    final h = _here;
    if (h == null) {
      _target = _nodes.first;
      return;
    }
    ArNode? best;
    double? bestD;
    for (final n in _nodes) {
      final d = Geo.distanceM(h.$1, h.$2, n.lat, n.lng);
      if (bestD == null || d < bestD) {
        bestD = d;
        best = n;
      }
    }
    _target = best;
  }

  // ---------- sensores ----------

  void _initSensors() {
    const period = Duration(milliseconds: 80);
    _accSub =
        accelerometerEventStream(samplingPeriod: period).listen((e) {
      _ax = e.x;
      _ay = e.y;
      _az = e.z;
      _recomputeHeading();
    });
    _magSub = magnetometerEventStream(samplingPeriod: period).listen((e) {
      _mx = e.x;
      _my = e.y;
      _mz = e.z;
      _recomputeHeading();
    });
  }

  void _recomputeHeading() {
    if (_ax == null || _ay == null || _az == null) return;
    if (_mx == null || _my == null || _mz == null) return;
    final h = Geo.headingFromSensors(
      ax: _ax!, ay: _ay!, az: _az!, mx: _mx!, my: _my!, mz: _mz!,
    );
    if (h == null) return;
    final now = DateTime.now();
    final prev = _heading;
    if (prev != null &&
        Geo.delta(h, prev).abs() < 0.5 &&
        now.difference(_lastHeading).inMilliseconds < 400) {
      return; // sin cambios: evita repintar a 12 Hz
    }
    _lastHeading = now;
    if (!mounted) return;
    setState(() => _heading = h);
  }

  // ---------- ubicación ----------

  Future<void> _initLocation() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        setState(() => _msg = 'Ubicación apagada: puedes usar posición manual.');
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        setState(() => _msg = 'Sin permiso de ubicación: usa posición manual.');
        return;
      }
      const settings =
          LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 5);
      _posSub = Geolocator.getPositionStream(locationSettings: settings)
          .listen((p) {
        if (!mounted) return;
        setState(() => _pos = p);
        _autoTarget();
        setState(() {});
      });
      final p =
          await Geolocator.getCurrentPosition(locationSettings: settings);
      if (!mounted) return;
      setState(() {
        _pos = p;
        _autoTarget();
      });
    } catch (e) {
      if (mounted) setState(() => _msg = 'Ubicación: $e');
    }
  }

  Future<void> _askManualPos() async {
    final lat = TextEditingController(
        text: _manualPos?.$1.toStringAsFixed(6) ?? _pos?.latitude.toStringAsFixed(6) ?? '');
    final lng = TextEditingController(
        text: _manualPos?.$2.toStringAsFixed(6) ?? _pos?.longitude.toStringAsFixed(6) ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Posición manual'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
              controller: lat,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Latitud')),
          TextField(
              controller: lng,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Longitud')),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Usar')),
        ],
      ),
    );
    final la = double.tryParse(lat.text.trim().replaceAll(',', '.'));
    final lo = double.tryParse(lng.text.trim().replaceAll(',', '.'));
    lat.dispose();
    lng.dispose();
    if (ok != true || la == null || lo == null) return;
    if (!mounted) return;
    setState(() {
      _manualPos = (la, lo);
      _pos = null;
      _autoTarget();
      _msg = 'Posición manual activa.';
    });
  }

  // ---------- cámara ----------

  Future<void> _initCamera() async {
    try {
      final st = await Permission.camera.request();
      if (!st.isGranted) {
        setState(() => _camMsg = 'Sin permiso de cámara: se usa la mira.');
        return;
      }
      final cams = await availableCameras();
      if (cams.isEmpty) {
        setState(() => _camMsg = 'Sin cámaras: se usa la mira.');
        return;
      }
      CameraDescription desc;
      try {
        desc = cams.firstWhere((c) => c.lensDirection == CameraLensDirection.back);
      } catch (_) {
        desc = cams.first;
      }
      final cam = CameraController(desc, ResolutionPreset.medium,
          enableAudio: false);
      await cam.initialize();
      if (!mounted) {
        await cam.dispose();
        return;
      }
      setState(() => _cam = cam);
    } catch (e) {
      if (mounted) setState(() => _camMsg = 'Cámara no disponible: se usa la mira.');
    }
  }

  // ---------- UI ----------

  Future<void> _openNodes() async {
    await showNodesSheet(
      context: context,
      store: ref.read(arNodeStoreProvider),
      here: _here,
      selected: _target,
      onSelected: (n) => setState(() => _target = n),
      onChanged: _loadNodes,
    );
  }

  @override
  Widget build(BuildContext context) {
    final heading = _heading;
    final bearing = _bearingToTarget;
    final dist = _distToTarget;
    final delta = (heading != null && bearing != null)
        ? Geo.delta(bearing, heading)
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Apuntar antena'),
        actions: [
          IconButton(
            tooltip: 'Nodos',
            icon: Badge(
              isLabelVisible: _nodes.isNotEmpty,
              label: Text('${_nodes.length}'),
              child: const Icon(Icons.place),
            ),
            onPressed: _openNodes,
          ),
        ],
      ),
      body: Column(children: [
        _readout(heading: heading, bearing: bearing, delta: delta, dist: dist),
        if (_msg.isNotEmpty || _camMsg.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              [_camMsg, _msg].where((s) => s.isNotEmpty).join(' · '),
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
        Expanded(
          child: _cam != null
              ? _cameraView(context, delta)
              : _miraView(context, delta),
        ),
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(children: [
            Expanded(
              child: FilledButton.tonalIcon(
                icon: const Icon(Icons.list_alt),
                label: Text('Nodos (${_nodes.length})'),
                onPressed: _openNodes,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.my_location),
                label: const Text('Posición'),
                onPressed: _askManualPos,
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  Widget _readout({
    required double? heading,
    required double? bearing,
    required double? delta,
    required double? dist,
  }) {
    final h = heading;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Wrap(spacing: 6, runSpacing: 6, children: [
        _chip('Rumbo', h == null ? '—' : '${h.round()}° ${Geo.compassPoint(h)}'),
        _chip('Nodo', bearing == null ? '—' : '${bearing.round()}°'),
        _chip(
          'Δ',
          delta == null ? '—' : '${delta.abs().round()}° ${delta < 0 ? 'izq' : 'der'}',
          color: delta == null
              ? null
              : (delta.abs() <= 3
                  ? Colors.green
                  : (delta.abs() <= 15 ? Colors.orange : Colors.red)),
        ),
        _chip('Dist', dist == null ? '—' : Geo.formatDistance(dist)),
      ]),
    );
  }

  Widget _chip(String label, String value, {Color? color}) {
    final style = color == null
        ? null
        : TextStyle(color: color, fontWeight: FontWeight.bold);
    return Chip(
      visualDensity: VisualDensity.compact,
      label: Text('$label: $value', style: style),
    );
  }

  /// Vista con cámara: marcador superpuesto según el Δ angular.
  Widget _cameraView(BuildContext context, double? delta) {
    final cam = _cam!;
    if (!cam.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      final h = box.maxHeight;
      return Stack(fit: StackFit.expand, children: [
        Center(
          child: AspectRatio(
            aspectRatio: cam.value.aspectRatio,
            child: CameraPreview(cam),
          ),
        ),
        if (delta == null)
          Center(child: _hint(_target == null ? 'Sin nodo objetivo' : 'Sin rumbo')),
        if (delta != null && delta.abs() <= _fovDeg / 2)
          Positioned(
            left: (w / 2 + (delta / (_fovDeg / 2)) * (w / 2) - 84)
                .clamp(8.0, math.max(8.0, w - 176)),
            top: h * 0.28,
            child: _marker(context, delta),
          ),
        if (delta != null && delta.abs() > _fovDeg / 2)
          Positioned(
            left: delta < 0 ? 8 : null,
            right: delta > 0 ? 8 : null,
            top: h * 0.30,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(
                  delta < 0 ? Icons.arrow_back : Icons.arrow_forward,
                  color: Colors.amber,
                  size: 18,
                ),
                const SizedBox(width: 6),
                Text('Gira ${delta.abs().round()}°',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ]),
            ),
          ),
      ]);
    });
  }

  Widget _marker(BuildContext context, double delta) {
    final t = _target;
    final dist = _distToTarget;
    return Container(
      width: 168,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: delta.abs() <= 3 ? Colors.green : Colors.amber, width: 2),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Text(
          t?.nombre ?? '',
          style: const TextStyle(
              color: Colors.white, fontWeight: FontWeight.bold),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          dist == null ? '—' : Geo.formatDistance(dist),
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        Text(
          '${delta.abs().round()}° ${delta < 0 ? 'izq' : 'der'}',
          style: TextStyle(
              color: delta.abs() <= 3 ? Colors.greenAccent : Colors.amber,
              fontSize: 16,
              fontWeight: FontWeight.bold),
        ),
        const Icon(Icons.arrow_drop_down, color: Colors.white, size: 20),
      ]),
    );
  }

  Widget _hint(String s) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
            color: Colors.black54, borderRadius: BorderRadius.circular(20)),
        child: Text(s,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold)),
      );

  /// Respaldo sin cámara: mira de brújula con la flecha del nodo.
  Widget _miraView(BuildContext context, double? delta) {
    final h = _heading;
    return Container(
      color: Colors.black87,
      alignment: Alignment.center,
      child: LayoutBuilder(builder: (context, box) {
        final size = math.min(box.maxWidth, box.maxHeight) - 32;
        return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          SizedBox(
            width: size,
            height: size,
            child: CustomPaint(
              painter: _CompassPainter(
                heading: h ?? 0,
                delta: delta,
                hasSensor: h != null,
                hasTarget: _target != null,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            h == null
                ? 'Esperando brújula…'
                : 'Rumbo ${h.round()}° ${Geo.compassPoint(h)}'
                    '${delta == null ? '' : '  ·  nodo a ${delta.abs().round()}° ${delta < 0 ? 'izq' : 'der'}'}',
            style: const TextStyle(color: Colors.white70),
          ),
        ]);
      }),
    );
  }
}

/// Miras: disco con marcas fijas que gira con el rumbo + flecha del nodo.
class _CompassPainter extends CustomPainter {
  _CompassPainter({
    required this.heading,
    required this.delta,
    required this.hasSensor,
    required this.hasTarget,
  });

  final double heading;
  final double? delta;
  final bool hasSensor;
  final bool hasTarget;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.shortestSide / 2 - 4;
    final rot = -heading * math.pi / 180;

    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.rotate(rot);
    canvas.drawCircle(
        Offset.zero,
        r,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.white54);
    for (var deg = 0; deg < 360; deg += 15) {
      final a = (deg - 90) * math.pi / 180;
      final major = deg % 45 == 0;
      final p1 = Offset(math.cos(a) * (r - (major ? 16 : 8)), math.sin(a) * (r - (major ? 16 : 8)));
      final p2 = Offset(math.cos(a) * r, math.sin(a) * r);
      canvas.drawLine(
          p1,
          p2,
          Paint()
            ..strokeWidth = major ? 2 : 1
            ..color = Colors.white70);
      if (deg % 90 == 0) {
        final label = const ['N', 'E', 'S', 'O'][deg ~/ 90];
        final tp = TextPainter(
          text: TextSpan(
            text: label,
            style: TextStyle(
              color: deg == 0 ? Colors.redAccent : Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        final pos = Offset(math.cos(a) * (r - 34), math.sin(a) * (r - 34));
        tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
      }
    }
    canvas.restore();

    // Referencia fija = borde superior del teléfono (donde está la cámara).
    canvas.save();
    canvas.translate(c.dx, c.dy);
    final tri = Path()
      ..moveTo(0, -r + 2)
      ..lineTo(-9, -r + 20)
      ..lineTo(9, -r + 20)
      ..close();
    canvas.drawPath(
        tri,
        Paint()
          ..color = hasSensor ? Colors.white : Colors.white30);

    if (hasTarget && delta != null) {
      canvas.save();
      canvas.rotate(delta! * math.pi / 180);
      final arrow = Path()
        ..moveTo(0, -r + 6)
        ..lineTo(-16, -r + 40)
        ..lineTo(0, -r + 32)
        ..lineTo(16, -r + 40)
        ..close();
      canvas.drawPath(arrow, Paint()..color = Colors.amber);
      canvas.drawLine(
          Offset.zero,
          Offset(0, -r + 44),
          Paint()
            ..strokeWidth = 3
            ..color = Colors.amber);
      canvas.restore();
    }
    canvas.restore();

    canvas.drawCircle(
        c,
        6,
        Paint()
          ..color = Colors.amber
          ..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(_CompassPainter old) =>
      old.heading != heading ||
      old.delta != delta ||
      old.hasSensor != hasSensor ||
      old.hasTarget != hasTarget;
}
