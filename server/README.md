# ISP CONFIG — servidor de sincronización (PHP 8 + SQLite)

API mínima que la APK usa para bajar zonas/APs y subir/bajar nodos con coordenadas.
Cero dependencias: solo PHP 8 con `pdo_sqlite`.

## 1. Instalar en otra PC (Windows)

**Una sola línea**: copia la carpeta del servidor a la PC destino (por ejemplo a
`C:\Users\PC\Pictures\ISP-CONFIG-servidor`), abre PowerShell ahí y pega:

```powershell
cd 'C:\Users\PC\Pictures\ISP-CONFIG-servidor'; .\instalar.bat
```

`instalar.bat` hace todo solo:

1. Busca PHP (PATH, junto al archivo, o `%ProgramFiles%\PHP`); si no lo encuentra
   lo instala con `winget` (PHP 8.3) — es portable, no toca el PHP del sistema.
2. Crea `php-isp-config.ini` con `pdo_sqlite` + `sqlite3` activos.
3. Siembra `data/isp.sqlite` con tus 8 zonas + 259 APs (solo la primera vez).
4. Arranca el servidor en `0.0.0.0:8080` en una ventana **minimizada**
   (`ISP CONFIG` — no la cierres, esa es la que sirve).
5. **Abre el navegador** en el panel web `http://localhost:8080/admin`.

**Panel web** (`/admin`): usuario `admin`, contraseña `admin` (cámbiala en
*Ajustes*). Ahí ves los **nodos con coordenadas**, **APs por zona**, **zonas**,
**firmware** y los **técnicos con su IP** (el buscador te dice si una IP está
libre o quién la tiene). Si no entraras con `admin`, borra `data\isp.sqlite` y
vuelve a ejecutar: se vuelve a sembrar con `admin`/`admin`.

**Firewall**: cuando Windows pregunte por `php.exe` → permite en *Red privada*.

**Detener**: cierra la ventana `ISP CONFIG` minimizada (o `Ctrl+C` ahí).

**Sin winget**: baja el zip *x64* de <https://windows.php.net/download/>,
descomprime en `C:\php` (o junto a este archivo) y vuelve a ejecutar
`instalar.bat`; si prefieres a mano: `extension=pdo_sqlite` y `extension=sqlite3`
en `php.ini` y arranca `iniciar.bat`.

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
| GET | `/stats` | conteos para el panel |
| GET | `/session` · POST · DELETE | sesión del panel (`admin`/`admin`) |
| POST | `/password` | cambiar contraseña (con sesión) |
| GET/POST/PUT/DELETE | `/tecnicos` | técnicos con su IP (`?ip=` → ¿libre?) |
| GET/POST/PUT/DELETE | `/firmware` | modelos/versiones de firmware |
| POST/PUT/DELETE | `/zones` | administrar zonas |
| GET | `/admin/` | panel web (HTML/JS/CSS) |

Errores: `{"error":"..."}` con código HTTP; la APK nunca borra lo local si la
respuesta no es `200` con datos válidos.
