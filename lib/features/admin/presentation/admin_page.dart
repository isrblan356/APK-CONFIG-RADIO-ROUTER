import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../../../core/config/app_settings.dart';
import '../domain/admin_auth.dart';

/// Pestaña Admin: login técnico + editor de toda la configuración.
/// Todo se persiste al escribir (AppSettings -> SharedPreferences).
class AdminPage extends StatefulWidget {
  const AdminPage({super.key});
  @override
  State<AdminPage> createState() => _AdminPageState();
}

class _AdminPageState extends State<AdminPage> {
  final _passCtrl = TextEditingController();
  final _actualCtrl = TextEditingController();
  final _nuevaCtrl = TextEditingController();
  final _confCtrl = TextEditingController();

  bool unlocked = false;
  bool pendingChange = false;
  String? loginMsg;
  String? changeMsg;
  String? probarMsg;
  bool busy = false;
  int _gen = 0; // cambia al restablecer, para repintar los campos

  @override
  void dispose() {
    _passCtrl.dispose();
    _actualCtrl.dispose();
    _nuevaCtrl.dispose();
    _confCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------- login

  Future<void> _entrar() async {
    final r = await AdminAuth.unlock(_passCtrl.text);
    if (r != null) {
      setState(() => loginMsg = r);
      return;
    }
    _passCtrl.clear();
    setState(() {
      unlocked = true;
      pendingChange = AdminAuth.mustChange;
      loginMsg = null;
      changeMsg = null;
    });
  }

  Widget _login() {
    final bloqueo = AdminAuth.lockedFor;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.admin_panel_settings,
                  size: 56, color: Colors.indigo),
              const SizedBox(height: 8),
              const Text('Administración',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              Text(
                AdminAuth.mustChange && !AdminAuth.locked
                    ? 'Primera vez: entra con "admin" y elige tu contraseña.'
                    : 'Solo para el técnico.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _passCtrl,
                obscureText: true,
                enabled: !busy && bloqueo == Duration.zero,
                onSubmitted: (_) => _entrar(),
                decoration: const InputDecoration(
                  labelText: 'Contraseña',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed:
                      (busy || bloqueo != Duration.zero) ? null : _entrar,
                  child: const Text('Entrar'),
                ),
              ),
              if (bloqueo != Duration.zero)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'Bloqueado ${bloqueo.inMinutes + 1} min por intentos fallidos.',
                    style: const TextStyle(color: Colors.red),
                  ),
                )
              else if (loginMsg != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(loginMsg!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.red)),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------- cambio de contraseña

  Future<void> _guardarPass({required bool forced}) async {
    final r = await AdminAuth.changePassword(
      actual: _actualCtrl.text,
      nueva: _nuevaCtrl.text,
      confirmar: _confCtrl.text,
      checkCurrent: !forced,
    );
    if (r != null) {
      setState(() => changeMsg = r);
      return;
    }
    _actualCtrl.clear();
    _nuevaCtrl.clear();
    _confCtrl.clear();
    setState(() {
      pendingChange = false;
      changeMsg = null;
    });
  }

  Widget _cambioPass({required bool forced}) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_reset, size: 48, color: Colors.indigo),
              const SizedBox(height: 8),
              Text(
                forced ? 'Elige tu contraseña' : 'Cambiar contraseña',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.bold),
              ),
              if (forced)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    'Es obligatorio cambiar la contraseña de fábrica antes de entrar.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.black54),
                  ),
                ),
              const SizedBox(height: 16),
              if (!forced)
                TextField(
                  controller: _actualCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                      labelText: 'Contraseña actual',
                      border: OutlineInputBorder()),
                ),
              if (!forced) const SizedBox(height: 12),
              TextField(
                controller: _nuevaCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                    labelText: 'Nueva contraseña (mínimo 4)',
                    border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _confCtrl,
                obscureText: true,
                onSubmitted: (_) => _guardarPass(forced: forced),
                decoration: const InputDecoration(
                    labelText: 'Confirmar contraseña',
                    border: OutlineInputBorder()),
              ),
              if (changeMsg != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(changeMsg!,
                      style: const TextStyle(color: Colors.red)),
                ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => _guardarPass(forced: forced),
                  child: Text(forced ? 'Guardar y entrar' : 'Guardar'),
                ),
              ),
              if (!forced)
                TextButton(
                  onPressed: () => setState(() {
                    pendingChange = false;
                    changeMsg = null;
                  }),
                  child: const Text('Cancelar'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------- editor

  Widget _seccion(String titulo, List<Widget> hijos) => Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(titulo,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 10),
              ...hijos,
            ],
          ),
        ),
      );

  Widget _tf(
    String keyName,
    String label,
    String? initial,
    void Function(String) on, {
    String? hint,
    int maxLines = 1,
    TextInputType? kb,
    List<TextInputFormatter>? fmt,
  }) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextFormField(
          key: ValueKey('$keyName-$_gen'),
          initialValue: initial,
          maxLines: maxLines,
          keyboardType: kb,
          inputFormatters: fmt,
          onChanged: on,
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            isDense: true,
            border: const OutlineInputBorder(),
          ),
        ),
      );

  static final _soloDigitos =
      [FilteringTextInputFormatter.digitsOnly];

  Future<void> _probarConexion() async {
    final s = AppSettings.instance;
    await s.setCloudEndpoint(s.cloudEndpoint.trim());
    final uri = s.cloudUri;
    if (uri == null) {
      setState(() => probarMsg = 'Pon una URL tipo http://192.168.1.50:8080');
      return;
    }
    setState(() {
      busy = true;
      probarMsg = null;
    });
    try {
      final base = uri.toString().replaceAll(RegExp(r'/+$'), '');
      final r = await http
          .get(Uri.parse('$base/health'))
          .timeout(const Duration(seconds: 6));
      final ok = r.statusCode == 200 && r.body.contains('"ok"');
      setState(() => probarMsg = ok
          ? 'Conectado: ${r.body}'
          : 'El servidor respondió ${r.statusCode}');
    } catch (e) {
      setState(() => probarMsg = 'Sin respuesta: $e');
    } finally {
      setState(() => busy = false);
    }
  }

  Future<void> _restablecer() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('¿Restablecer?'),
        content: const Text(
            'Vuelve a la configuración de fábrica (IPs, claves, firmware y nube). '
            'Tu contraseña de Admin NO cambia.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Restablecer')),
        ],
      ),
    );
    if (ok != true) return;
    await AppSettings.instance.resetConfig();
    setState(() {
      _gen++;
      probarMsg = null;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configuración de fábrica restaurada.')));
  }

  void _cerrarSesion() {
    setState(() {
      unlocked = false;
      pendingChange = false;
      loginMsg = null;
      changeMsg = null;
      _gen++;
    });
  }

  Widget _editor() {
    final s = AppSettings.instance;
    return ListView(
      padding: const EdgeInsets.only(top: 8, bottom: 24),
      children: [
        // IP final (el "network 50" de final.php)
        _seccion('IP final del equipo (el "network 50" de final.php)', [
          Row(children: [
            Expanded(
                child: _tf('wan', 'Sufijo WAN', s.wanSuffix,
                    (v) => setState(() => s.setWanSuffix(v)),
                    hint: '50', kb: TextInputType.number, fmt: _soloDigitos)),
            const SizedBox(width: 10),
            Expanded(
                child: _tf('gw', 'Sufijo gateway', s.gwSuffix,
                    (v) => setState(() => s.setGwSuffix(v)),
                    hint: '1', kb: TextInputType.number, fmt: _soloDigitos)),
          ]),
          Text(
            'Con la zona 192.168.80. queda: '
            'WAN ${s.wanIp('192.168.80.')} · GW ${s.gatewayIp('192.168.80.')}',
            style: const TextStyle(color: Colors.black54, fontSize: 13),
          ),
          const SizedBox(height: 8),
        ]),

        // Radio Ubiquiti
        _seccion('Radio Ubiquiti (SSH)', [
          _tf('ipf', 'IP de fábrica', s.ubntDefaultIp,
              (v) => s.setUbntDefaultIp(v)),
          _tf('ipw', 'IP en el WiFi del radio', s.ubntWifiIp,
              (v) => s.setUbntWifiIp(v)),
          _tf('ipc', 'IP ya configurada', s.ubntConfiguredIp,
              (v) => s.setUbntConfiguredIp(v)),
          _tf('user', 'Usuario SSH', s.ubntUser, (v) => s.setUbntUser(v)),
          _tf('passes', 'Claves SSH (se prueban en orden)',
              s.ubntPasses.join(', '),
              (v) => s.setUbntPasses(
                  v.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList()),
              hint: 'ubnt, r1nku.2015, R1nku.2015'),
          Row(children: [
            Expanded(
                child: _tf('fwm', 'Firmware objetivo M', s.fwM,
                    (v) => s.setFwM(v),
                    hint: 'v6.3.2')),
            const SizedBox(width: 10),
            Expanded(
                child: _tf('fwac', 'Firmware objetivo AC', s.fwAC,
                    (v) => s.setFwAC(v),
                    hint: 'v8.7.4')),
          ]),
        ]),

        // TP-Link
        _seccion('Router TP-Link', [
          Row(children: [
            Expanded(
                child: _tf('tnip', 'IP (nuevo)', s.tplinkNewIp,
                    (v) => s.setTplinkNewIp(v))),
            const SizedBox(width: 10),
            Expanded(
                child: _tf('tnpass', 'Clave (nuevo)', s.tplinkNewPass,
                    (v) => s.setTplinkNewPass(v))),
          ]),
          Row(children: [
            Expanded(
                child: _tf('tcip', 'IP (configurado)', s.tplinkConfiguredIp,
                    (v) => s.setTplinkConfiguredIp(v))),
            const SizedBox(width: 10),
            Expanded(
                child: _tf(
                    'tcpass', 'Clave (configurado)', s.tplinkConfiguredPass,
                    (v) => s.setTplinkConfiguredPass(v))),
          ]),
          _tf('lan', 'IP LAN final del router', s.tplinkTargetLanIp,
              (v) => s.setTplinkTargetLanIp(v),
              hint: '192.168.20.2'),
        ]),

        // Nube
        _seccion('Nube (servidor de sincronización)', [
          _tf('url', 'URL del servidor', s.cloudEndpoint,
              (v) => s.setCloudEndpoint(v),
              hint: 'http://192.168.1.50:8080', kb: TextInputType.url),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Activar sincronización'),
            subtitle: const Text(
                'Zonas/APs y nodos de la brújula se comparten con el servidor'),
            value: s.cloudEnabled,
            onChanged: (v) => setState(() => s.setCloudEnabled(v)),
          ),
          _tf('token', 'Token de escritura (opcional)', s.cloudToken,
              (v) => s.setCloudToken(v),
              hint: 'vacío = sin token'),
          Row(children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: busy ? null : _probarConexion,
                icon: const Icon(Icons.cloud_sync),
                label: const Text('Probar conexión'),
              ),
            ),
          ]),
          if (probarMsg != null)
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 6),
              child: Text(probarMsg!,
                  style: TextStyle(
                      color: probarMsg!.startsWith('Conectado')
                          ? Colors.green.shade700
                          : Colors.red)),
            ),
          const SizedBox(height: 6),
        ]),

        // Contraseña admin
        _seccion('Contraseña de Admin', [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TextField(
              controller: _actualCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Contraseña actual',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TextField(
              controller: _nuevaCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Nueva contraseña (mínimo 4)',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: TextField(
              controller: _confCtrl,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Confirmar nueva contraseña',
                isDense: true,
                border: OutlineInputBorder(),
              ),
            ),
          ),
          FilledButton.tonal(
            onPressed: () async {
              final r = await AdminAuth.changePassword(
                actual: _actualCtrl.text,
                nueva: _nuevaCtrl.text,
                confirmar: _confCtrl.text,
              );
              if (!mounted) return;
              if (r == null) {
                _actualCtrl.clear();
                _nuevaCtrl.clear();
                _confCtrl.clear();
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Contraseña actualizada.')));
              } else {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(r)));
              }
            },
            child: const Text('Cambiar contraseña'),
          ),
        ]),

        // Sesión
        _seccion('Sesión', [
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _cerrarSesion,
                icon: const Icon(Icons.logout),
                label: const Text('Cerrar sesión'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _restablecer,
                icon: const Icon(Icons.restart_alt),
                label: const Text('Fábrica'),
              ),
            ),
          ]),
          const SizedBox(height: 8),
        ]),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!unlocked) return Scaffold(appBar: AppBar(title: const Text('Admin')), body: _login());
    if (pendingChange) {
      return Scaffold(
          appBar: AppBar(title: const Text('Admin')), body: _cambioPass(forced: true));
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin'),
        actions: [
          IconButton(
            tooltip: 'Cerrar sesión',
            onPressed: _cerrarSesion,
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: _editor(),
    );
  }
}
