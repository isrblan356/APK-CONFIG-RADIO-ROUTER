# ISP CONFIG — APK Flutter (Ubiquiti + TP-Link, 100% en el móvil)

Port limpio de tus scripts `backup_script/final.php` (radios) y `tplink/2new.sh` + `newchangepass.sh` (routers) a una APK offline-first con sync híbrido opcional.

## 1. Qué hace (misma lógica, sin PC)

| Antes (PC/WSL) | Ahora (APK) |
|---|---|
| `final.php`: detecta 192.168.1.20 (ubnt/ubnt) o 192.168.20.1, SSH, `status.cgi` → modelo + FW, sube `fwupdate.bin`, genera `system.cfg` desde `template.cfg` (CHANGESSID + 80.50→WAN + 80.1→GW), sube `ct` compliance, `cfgmtd + reboot`, o reset fábrica | `UbntPage`: elegir IP del radio (Auto 1.20 → **192.168.172.1 WiFi del radio** → 20.1, o forzar una) → Detectar → Firmware → Zona/AP (de `nodos.db` local) → Subir config + reboot / Reset. `lib/features/radio_ubiquiti/data/ubnt_repository_impl.dart` |
| `2new.sh` opción 1: router nuevo 192.168.0.1/admin → login cookie MD5+Base64+KEY, `StatusRpm.htm` (nuevo vs viejo), cambia pass admin, WPS off, DHCP off, UPnP off, remoto on, SSID, WPA2-PSK AES, LAN 192.168.20.2 | `TplinkPage` modo Nuevo: `TplinkRepositoryImpl.provisionNew()` misma secuencia GET |
| Opción 2: 192.168.20.2 → solo cambia clave WiFi + reboot | `TplinkPage` modo Existente: `changeWifiPass()` |
| `nodos/nodos.db` (zona/network + accesspoints/ssid) en PC | `assets/seed/nodos.db` + `sqflite` en el móvil. Se **instala sola en el primer arranque** (8 zonas + 259 APs reales). Zonas reales: Girardota 80., Medellín 50., Guarne 60., etc. |
| ¿Hacia dónde apunto la antena? GPS + brújula del celular | Tab **Brújula** (AR): cámara con marcador que indica Δ grados y distancia al nodo elegido; si no hay cámara/sensores, mira de brújula. Nodos **manuales** o **bajados de la nube**. `lib/features/ar_compass/` |

## 2. Todo instalado en el móvil (offline)

- `assets/templates/<modelo>/template.cfg` — copiados de tus `configs/` (4 modelos incluidos).
- `assets/templates/ct` — compliance (vacío en tu backup, se sube si existe).
- `assets/firmware/<modelo>/fwupdate.bin` — 5 incluidos (PowerBeam M5 400 XW, PowerBeam M5 300 XW, LiteBeam M5 XW, Rocket M5 XW — todos XW, el mismo bin aplica a cualquier M5 XW — y NanoBeam 5AC 16). Agrega más copiando tus `Firmware/*/fwupdate.bin` **y declarando la carpeta en `pubspec.yaml` (`assets:`)**.
- `assets/seed/nodos.db` — tu DB original completa (32KB).
- `sqflite` + `shared_preferences` — inventario y credenciales locales, sin internet.

> La APK funciona sin internet. Solo necesita WiFi/Ethernet-OTG hacia el radio/router (misma red 192.168.1.x / 192.168.0.x / 192.168.20.x).

## 3. Modo híbrido nube (opcional, apagado por defecto)

- 100% local por defecto. Para activarlo: pestaña **Admin → Nube** → URL del servidor
  (`http://IP-del-servidor:8080`) + *Activar sincronización* + **Probar conexión**.
  El valor de fábrica sigue pudiendo venir de `--dart-define=CLOUD_ENDPOINT=...`.
- **Servidor incluido**: `server/` (PHP 8 + SQLite, cero dependencias). Cópialo a otra
  PC, doble clic en `iniciar.bat` y listo (siembra solo las 8 zonas + 259 APs).
  Pasos completos en `server/README.md`; listo para copiar en
  `Downloads/ISP-CONFIG-servidor.zip`.
- Contrato: `GET /zones` → `[{"id":1,"zona":"Girardota","network":"192.168.80."}]` y `GET /aps?zona=1` → `[{"idzona":"1","idnodo":1,"nodo":"La Palma - AP1","ssid":"rinku_ap1_lapalma"}]`. Acepta envoltorios (`{"zones":[...]}`, `{"data":[...]}`) y alias en inglés (`name`/`network`/`zoneId`): ver `lib/features/inventory/data/cloud_payload.dart`.
- Contrato de nodos con coordenadas (tab Brújula): `GET /nodes` → `[{"id":1,"nombre":"Girardota AP12","lat":6.3201,"lng":-75.4382,"alt":1500,"zona":"Girardota"}]`. Acepta `{"nodes":[...]}`, alias (`name`/`latitude`/`longitude`/`lon`) y coma decimal. Ver `lib/features/ar_compass/data/ar_nodes_cloud.dart`. Los manuales se **suben** con `POST /nodes` (clave estable `d<id>`, upsert: repetir no duplica).
- La sync **nunca borra lo local**: solo reemplaza si la nube devolvió datos válidos; si algo falla, sigues con la DB del móvil. En el módulo Brújula solo se reemplazan los nodos de origen `nube`: los **manuales jamás se borran** (y los que subiste no vuelven duplicados).

## 4. Compilar la APK

### Opción A — GitHub Actions (recomendada, no instala nada en tu PC)

Cada push a `main` corre `.github/workflows/build-apk.yml`:
`flutter pub get` → `flutter analyze` → `flutter test` → `flutter build apk --release`.

1. En el repo, pestaña **Actions** → workflow *build-apk*.
2. Cuando quedó verde, baja el artifact **`isp-config-apk`** (un `.zip` con `app-release.apk`).
3. Pásalo por USB/WhatsApp/Drive e instálalo.

Build manual sin subir código: Actions → *Run workflow* (botón "Run workflow").

### Opción B — Local (Flutter + Android Studio)

```bash
# 1. Instala Flutter 3.22+ y Android Studio (SDK + Build-Tools)
flutter doctor

# 2. Dentro de wisp_configurator/
flutter pub get

# 3. (Opcional) agrega más firmwares:
# copy "..\backup_script\Firmware\LiteBeam M5 XW\fwupdate.bin" "assets\firmware\LiteBeam M5 XW\fwupdate.bin"
# ...y declara la subcarpeta en pubspec.yaml (Flutter NO embebe subcarpetas
#    que no estén listadas en `assets:`):

# 4. Análisis estático + tests (regla template + parser de nube)
flutter analyze
flutter test

# 5. APK release instalada en el móvil
flutter build apk --release
# sale en: build\app\outputs\flutter-apk\app-release.apk

# Con nube:
flutter build apk --release --dart-define=CLOUD_ENDPOINT=https://tu-api.com
```

### Permisos Android
Ya van fusionados en `android/app/src/main/AndroidManifest.xml` (`INTERNET`, `ACCESS_NETWORK_STATE`, `ACCESS_WIFI_STATE`, `CHANGE_WIFI_STATE`, `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`, `CAMERA` + `usesCleartextTraffic=true`, porque TP-Link y AirOS hablan HTTP). `android/AndroidManifest.snippet.xml` queda como referencia si regeneras el proyecto con `flutter create`.

### Troubleshooting de build
- **`flutter test` falla con "Una directiva de Control de aplicaciones bloqueó este archivo"**: es Windows **Smart App Control** bloqueando `impellerc.exe` / `flutter_tester.exe` (van sin firma). Desactívalo en Seguridad de Windows → Control de aplicaciones y navegador → Smart App Control (decisión única, no reversible sin reinstalar). Mientras esté activo, `flutter analyze` sí funciona y es la verificación que se usa.
- **`Building native assets for package:objective_c failed` / `"C:\Users\..." no se reconoce`**: no metas `path_provider` en `pubspec.yaml`. Arrastra `objective_c`, cuyo hook nativo compila rutas con `cmd` sin comillas y rompe en directorios con espacios (ver comentario en `pubspec.yaml`).

## 5. Uso en campo

1. Conecta el móvil al radio: por el **WiFi que emite el propio radio** (entonces el radio está en **192.168.172.1**, IP por defecto en su red de servicio) o por su LAN/OTG-Ethernet (192.168.1.20 de fábrica / 192.168.20.1 ya configurado).
2. Tab Zonas: verifica Zona/AP y WAN esperada (`.50` / GW `.1`).
3. Tab Radio: elige **IP del radio** (Auto = 1.20 → 172.1 → 20.1; o fija 192.168.172.1 si estás en su WiFi) → **1 Detectar** → elige pass SSH → elige Zona/AP → **3 Subir config**. O Reset si es necesario.
4. Conecta al router: Nuevo → únete a su WiFi de fábrica → **Conectar 192.168.0.1** → SSID+clave → **Aprovisionar**. Existente → WiFi del cliente → **Conectar .20.2** → nueva clave → reboot.
5. Tab **Brújula** (apuntar antena): permite cámara + ubicación → **Nodos** → `+` para cargar uno a mano (nombre, lat, lng) → ☁ sube los manuales al servidor y ☇ (nube) los baja → elige el nodo → gira el teléfono hasta que el marcador quede centrado (Δ ≤ 3° en verde). Sin GPS toca **Posición** y escribe tus coordenadas; sin cámara se ve la mira de brújula con flecha ámbar.
6. Tab **Admin** (solo técnico): primera vez entra con `admin` y **elige contraseña** (obligatoria, 5 intentos → bloqueo de 5 min). Ahí se edita todo: sufijo WAN/GW del *network 50*, IPs y claves del radio, firmware M/AC, IPs y claves del TP-Link, URL del servidor, token de escritura y la propia contraseña. **Fábrica** restaura la config (no la contraseña) y **Cerrar sesión** vuelve al login.

## 6. Arquitectura limpia (30 años, sin atajos)

```
lib/
  main.dart            # DI Riverpod + init de AppSettings
  app.dart             # Tabs
  core/config/app_config.dart      # valores de fábrica (const, son los defaults)
  core/config/app_settings.dart    # config editable/Admin persistida en prefs
  core/error/failures.dart         # Either<Failure, T> en vez de throws
  core/network/reachability.dart   # socket TCP (Android no permite ICMP sin root)
  features/radio_ubiquiti/  domain/entities + repositories / data/ubnt_repository_impl / presentation/ubnt_page
  features/router_tplink/   domain/entities / data/tplink_repository_impl / presentation/tplink_page
  features/inventory/       domain + data/inventory_local (sqflite) + presentation/zones_page
  features/ar_compass/      domain/geo (rumbo+distancia puros) + data/ar_node_store (sqflite) + presentation/ar_page
  features/admin/           domain/admin_auth (SHA-256 + bloqueo) + presentation/admin_page
server/                    # API PHP+SQLite para otra PC (iniciar.bat)
tool/verify_server.dart    # prueba el servidor con los parsers reales
test/ubnt_template_test.dart  # regla CHANGESSID/WAN/GW
test/geo_test.dart            # rumbo desde acelerómetro+magnetómetro
```

Principios: una sola responsabilidad por clase, repositorios con contrato testeable, UI tonta (solo llama casos de uso), sin credenciales hardcodeadas fuera de `AppConfig`, offline-first con nube como plugin.

## 7. Límites conocidos

- SSH en AirOS viejo: si `dartssh2` falla con un modelo XM muy antiguo, activa `sshInitWait` mayor en `AppConfig` (algunos XW tardan 30s).
- TP-Link WR840N v1 (muy viejo): usa Basic Auth sin KEY — ya soportado como `TplinkGen.old`.
- `tplink.sh` (encode/decode `config.bin`) no se portó: era fallback binario; la vía HTTP GET cubre el 100% de tus casos `2new.sh`. Si lo necesitas, pide el port.
- APK con 2 firmwares = ~25MB. Con los 15 modelos = ~150MB (límite Play 200MB, mejor descarga bajo demanda desde nube).
