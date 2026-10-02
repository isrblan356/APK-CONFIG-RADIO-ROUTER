# WISP Configurador — APK Flutter (Ubiquiti + TP-Link, 100% en el móvil)

Port limpio de tus scripts `backup_script/final.php` (radios) y `tplink/2new.sh` + `newchangepass.sh` (routers) a una APK offline-first con sync híbrido opcional.

## 1. Qué hace (misma lógica, sin PC)

| Antes (PC/WSL) | Ahora (APK) |
|---|---|
| `final.php`: detecta 192.168.1.20 (ubnt/ubnt) o 192.168.20.1, SSH, `status.cgi` → modelo + FW, sube `fwupdate.bin`, genera `system.cfg` desde `template.cfg` (CHANGESSID + 80.50→WAN + 80.1→GW), sube `ct` compliance, `cfgmtd + reboot`, o reset fábrica | `UbntPage`: Detectar → Firmware → Zona/AP (de `nodos.db` local) → Subir config + reboot / Reset. `lib/features/radio_ubiquiti/data/ubnt_repository_impl.dart` |
| `2new.sh` opción 1: router nuevo 192.168.0.1/admin → login cookie MD5+Base64+KEY, `StatusRpm.htm` (nuevo vs viejo), cambia pass admin, WPS off, DHCP off, UPnP off, remoto on, SSID, WPA2-PSK AES, LAN 192.168.20.2 | `TplinkPage` modo Nuevo: `TplinkRepositoryImpl.provisionNew()` misma secuencia GET |
| Opción 2: 192.168.20.2 → solo cambia clave WiFi + reboot | `TplinkPage` modo Existente: `changeWifiPass()` |
| `nodos/nodos.db` (zona/network + accesspoints/ssid) en PC | `assets/seed/nodos.db` + `sqflite` en el móvil. Se **instala sola en el primer arranque** (8 zonas + 259 APs reales). Zonas reales: Girardota 80., Medellín 50., Guarne 60., etc. |

## 2. Todo instalado en el móvil (offline)

- `assets/templates/<modelo>/template.cfg` — copiados de tus `configs/` (4 modelos incluidos).
- `assets/templates/ct` — compliance (vacío en tu backup, se sube si existe).
- `assets/firmware/<modelo>/fwupdate.bin` — 2 incluidos (PowerBeam M5 400 XW 7.4MB + NanoBeam 5AC 16 9.7MB). Agrega más copiando tus `Firmware/*/fwupdate.bin`.
- `assets/seed/nodos.db` — tu DB original completa (32KB).
- `sqflite` + `shared_preferences` — inventario y credenciales locales, sin internet.

> La APK funciona sin internet. Solo necesita WiFi/Ethernet-OTG hacia el radio/router (misma red 192.168.1.x / 192.168.0.x / 192.168.20.x).

## 3. Modo híbrido nube (opcional, apagado por defecto)

- `AppConfig.cloudEnabledDefault = false` + `CLOUD_ENDPOINT = ''` → 100% local.
- Para activar: `InventoryLocal(cloud, cloudEnabled: true)` + `--dart-define=CLOUD_ENDPOINT=https://tu-api`.
- Contrato: `GET /zones` → `[{"id":1,"zona":"Girardota","network":"192.168.80."}]` y `GET /aps?zona=1` → `[{"idzona":"1","idnodo":1,"nodo":"La Palma - AP1","ssid":"rinku_ap1_lapalma"}]`. Acepta envoltorios (`{"zones":[...]}`, `{"data":[...]}`) y alias en inglés (`name`/`network`/`zoneId`): ver `lib/features/inventory/data/cloud_payload.dart`.
- La sync **nunca borra lo local**: solo reemplaza si la nube devolvió datos válidos; si algo falla, sigues con la DB del móvil.

## 4. Compilar la APK

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
# pásala por USB/WhatsApp/Drive e instálala.

# Con nube:
flutter build apk --release --dart-define=CLOUD_ENDPOINT=https://tu-api.com
```

### Permisos Android
Ver `android/AndroidManifest.snippet.xml`: `INTERNET` (sockets locales SSH/HTTP), `ACCESS_WIFI_STATE`, `ACCESS_FINE_LOCATION` (requerido por Android 10+ para ver SSID), `usesCleartextTraffic=true` (los TP-Link y AirOS usan HTTP, no HTTPS). Fusiona el snippet en tu `AndroidManifest.xml` generado por `flutter create`.

## 5. Uso en campo

1. Conecta el móvil al radio (WiFi o OTG-Ethernet, IP del móvil en 192.168.1.x).
2. Tab Zonas: verifica Zona/AP y WAN esperada (`.50` / GW `.1`).
3. Tab Radio: **1 Detectar** → elige pass SSH → elige Zona/AP → **3 Subir config**. O Reset si es necesario.
4. Conecta al router: Nuevo → únete a su WiFi de fábrica → **Conectar 192.168.0.1** → SSID+clave → **Aprovisionar**. Existente → WiFi del cliente → **Conectar .20.2** → nueva clave → reboot.

## 6. Arquitectura limpia (30 años, sin atajos)

```
lib/
  main.dart            # DI Riverpod
  app.dart             # Tabs
  core/config/app_config.dart      # todas las IPs/passes/FW en un solo lugar
  core/error/failures.dart         # Either<Failure, T> en vez de throws
  core/network/reachability.dart   # socket TCP (Android no permite ICMP sin root)
  features/radio_ubiquiti/  domain/entities + repositories / data/ubnt_repository_impl / presentation/ubnt_page
  features/router_tplink/   domain/entities / data/tplink_repository_impl / presentation/tplink_page
  features/inventory/       domain + data/inventory_local (sqflite) + presentation/zones_page
test/ubnt_template_test.dart  # regla CHANGESSID/WAN/GW
```

Principios: una sola responsabilidad por clase, repositorios con contrato testeable, UI tonta (solo llama casos de uso), sin credenciales hardcodeadas fuera de `AppConfig`, offline-first con nube como plugin.

## 7. Límites conocidos

- SSH en AirOS viejo: si `dartssh2` falla con un modelo XM muy antiguo, activa `sshInitWait` mayor en `AppConfig` (algunos XW tardan 30s).
- TP-Link WR840N v1 (muy viejo): usa Basic Auth sin KEY — ya soportado como `TplinkGen.old`.
- `tplink.sh` (encode/decode `config.bin`) no se portó: era fallback binario; la vía HTTP GET cubre el 100% de tus casos `2new.sh`. Si lo necesitas, pide el port.
- APK con 2 firmwares = ~25MB. Con los 15 modelos = ~150MB (límite Play 200MB, mejor descarga bajo demanda desde nube).
