# ISP CONFIG — servidor de sincronización (PHP 8 + SQLite)

API mínima que la APK usa para bajar zonas/APs y subir/bajar nodos con coordenadas.
Cero dependencias: solo PHP 8 con `pdo_sqlite`.

## 1. Instalar en otra PC (Windows)

1. **PHP**: baja el zip *x64* de <https://windows.php.net/download/> (por ejemplo
   `php-8.x.x-Win32-vs16-x64.zip`), descomprime en `C:\php`.
2. **Extensiones**: edita `C:\php\php.ini` y descomenta/agrega:
   ```ini
   extension=pdo_sqlite
   extension=sqlite3
   extension=filter
   ```
3. **PATH**: agrega `C:\php` al PATH del sistema (o copia `php.exe` junto a
   `server\iniciar.bat`, también funciona).
4. **Copia la carpeta `server/` completa** a esa PC (USB, git, lo que sea).
   La carpeta es autocontenida: `seed_data/nodos.db` trae tus 8 zonas y 259 APs.
5. **Arranca**: doble clic en `server\iniciar.bat`.
   - Si la BD no existe la siembra sola con tus 8 zonas + 259 APs.
   - Deja la ventana abierta: es el servidor (`Ctrl+C` la detiene).
6. **Firewall**: cuando Windows pregunte por `php.exe` → permite en *Red privada*.
7. **Prueba** desde el navegador de esa PC: `http://127.0.0.1:8080/health` debe
   responder `{"ok":true,...}`.

Con esto basta: la PC queda sirviendo en `http://<IP-de-la-PC>:8080`.

## 2. Alternativa: en WSL / Linux

```bash
sudo apt install php-cli php-sqlite3     # una vez
cd server && php scripts/seed.php        # crea data/isp.sqlite (8 zonas, 259 APs)
php -S 0.0.0.0:8080 -t public            # 0.0.0.0 para que el celular entre
```

`0.0.0.0` escucha en todas las interfaces; con `127.0.0.1` solo entra el PC.
`data/isp.sqlite` no se pisa si ya existe (borra para re-sembrar).
Comprueba:

```bash
curl http://127.0.0.1:8080/health      # {"ok":true,...}
curl http://127.0.0.1:8080/zones
curl "http://127.0.0.1:8080/aps?zona=1"
curl http://127.0.0.1:8080/nodes
```

Verificación completa (parsers reales de la APK):

```bash
dart run tool/verify_server.dart http://127.0.0.1:8080
```

## 3. Apuntar la APK

1. Consigue la IP de esa PC: `ipconfig` (Windows) o `hostname -I` (Linux). Ej: `192.168.1.50`.
2. Celular y PC en la **misma WiFi**.
3. En la APK: pestaña **Admin** → contraseña (la primera vez es `admin`, te obliga a cambiarla) →
   **Nube** → URL `http://192.168.1.50:8080` → *Activar sincronización* → **Probar conexión**.
4. Las zonas/APs bajan con el botón de recarga en *Zonas/APs*; los nodos con el botón ☁ en *Brújula*.

La APK trae `usesCleartextTraffic="true"`, así que el HTTP local funciona sin HTTPS.
`CLOUD_ENDPOINT` con `--dart-define` sigue sirviendo como valor por defecto de fábrica.

## 4. Escrituras con token (opcional, recomendado fuera de local)

```bash
export ISP_ADMIN_TOKEN="cambia-esto"     # Linux/macOS
setx ISP_ADMIN_TOKEN "cambia-esto"       # Windows (reabre la consola)
php -S 0.0.0.0:8080 -t public
```

Con eso, `POST/PUT/DELETE /nodes` exigen la cabecera `X-Admin-Token`. En la APK:
Admin → Nube → *Token de escritura*.

## 5. Subirlo a un servidor (más adelante)

- **Hosting PHP**: sube `server/` por FTP, apunta el dominio a `server/public/`,
  asegúrate de `AllowOverride All` (viene `.htaccess`), crea la BD con `seed.php`
  desde la consola del hosting.
- **VPS**: nginx/Apache + PHP-FPM con la raíz en `server/public`; el `data/`
  debe ser escribible por el usuario de PHP.

## Endpoints

| Método | Ruta | Uso |
|---|---|---|
| GET | `/health` | probar conexión desde la APK |
| GET | `/zones` | zonas (id, zona, network) |
| GET | `/aps?zona=1` | APs de una zona |
| GET | `/nodes` | nodos con coordenadas |
| POST/PUT | `/nodes` | crear/actualizar nodo (JSON) |
| DELETE | `/nodes?id=1` | borrar nodo |

Errores: `{"error":"..."}` con código HTTP; la APK nunca borra lo local si la
respuesta no es `200` con datos válidos.
