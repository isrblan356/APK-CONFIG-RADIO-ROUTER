import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Abre la interfaz web (AirOS) del radio dentro de la misma app y se
/// autentica sola: AirOS pide HTTP Basic y aquí se responde con los
/// mismos usuario/clave que ya sirvieron por SSH. No hay que digitar nada.
class UbntWebViewPage extends StatelessWidget {
  const UbntWebViewPage({
    super.key,
    required this.url,
    required this.user,
    required this.password,
  });

  final String url;
  final String user;
  final String password;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Interfaz web · $url')),
      body: InAppWebView(
        initialUrlRequest: URLRequest(url: WebUri(url)),
        initialSettings: InAppWebViewSettings(
          javaScriptEnabled: true,
          useWideViewPort: true,
          loadWithOverviewMode: true,
        ),
        onReceivedHttpAuthRequest: (controller, challenge) async {
          // Mismos credenciales que SSH: usuario de Admin -> Radio y la
          // clave que autenticó en la detección.
          return HttpAuthResponse(
            username: user,
            password: password,
            action: HttpAuthResponseAction.PROCEED,
            permanentPersistence: false,
          );
        },
      ),
    );
  }
}
