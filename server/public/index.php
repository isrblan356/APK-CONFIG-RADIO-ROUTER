<?php
declare(strict_types=1);

/**
 * ISP CONFIG — API de sincronización + panel web (PHP + SQLite, cero deps).
 *
 * Contrato para la APK (sin cambios respecto a v1.1):
 *   GET    /health          -> {"ok":true,"app":"isp-config"}
 *   GET    /zones           -> [{"id":1,"zona":"Girardota","network":"192.168.80."}]
 *   GET    /aps?zona=1      -> [{"idzona":"1","idnodo":1,"nodo":"...","ssid":"..."}]
 *   GET    /nodes           -> [{"id":1,"nombre":"...","lat":..,"lng":..,"alt":..,"zona":"..."}]
 *   POST   /nodes           -> crea/actualiza (JSON: nombre,lat,lng[,alt,zona,clave,notas])
 *   PUT    /nodes           -> igual que POST (acepta "id" en el cuerpo)
 *   DELETE /nodes?id=N      -> borra
 *
 * Rutas nuevas (panel web en /admin y futuras llamadas de la APK):
 *   GET|POST|PUT|DELETE /zones /aps /firmware /tecnicos   (CRUD)
 *   GET /tecnicos?ip=x        -> quién tiene esa IP
 *   GET|POST|DELETE /session  -> estado / login / logout  (panel web)
 *   POST /password            -> cambiar la contraseña del admin (sesión)
 *   GET /stats                -> conteos para el dashboard
 *
 * Escrituras: sesión del panel web (cookie) O cabecera X-Admin-Token
 * (variable de entorno ISP_ADMIN_TOKEN) — la APK usa la segunda.
 */

header('Content-Type: application/json; charset=utf-8');
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Methods: GET, POST, PUT, DELETE, OPTIONS');
header('Access-Control-Allow-Headers: Content-Type, X-Admin-Token');
if (($_SERVER['REQUEST_METHOD'] ?? '') === 'OPTIONS') {
    http_response_code(204);
    exit;
}

// ---------- helpers ----------

function out(array $data, int $code = 200): void
{
    http_response_code($code);
    echo json_encode($data, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

function fail(int $code, string $msg): void
{
    out(['error' => $msg], $code);
}

function body(): array
{
    $raw = file_get_contents('php://input') ?: '';
    if ($raw === '') {
        return [];
    }
    $d = json_decode($raw, true);
    return is_array($d) ? $d : [];
}

function startSession(): void
{
    if (session_status() === PHP_SESSION_NONE) {
        session_start([
            'cookie_httponly' => true,
            'cookie_samesite' => 'Lax',
        ]);
    }
}

function isLogged(): bool
{
    startSession();
    return ($_SESSION['admin'] ?? false) === true;
}

function db(): PDO
{
    static $pdo = null;
    if ($pdo !== null) {
        return $pdo;
    }
    $file = dirname(__DIR__) . '/data/isp.sqlite';
    $fresh = !is_file($file);
    $pdo = new PDO('sqlite:' . $file, null, null, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    ]);
    $pdo->exec('PRAGMA busy_timeout=3000');
    ensureSchema($pdo);
    if ($fresh) {
        seedIfPossible($pdo); // primera ejecución: copia zonas/APs del bundled
    }
    return $pdo;
}

function rows(string $sql, array $args = []): array
{
    $st = db()->prepare($sql);
    $st->execute($args);
    return $st->fetchAll();
}

function colExists(PDO $pdo, string $table, string $col): bool
{
    foreach ($pdo->query("PRAGMA table_info($table)") as $r) {
        if ($r['name'] === $col) {
            return true;
        }
    }
    return false;
}

function tableExists(PDO $pdo, string $table): bool
{
    $st = $pdo->prepare("SELECT name FROM sqlite_master WHERE type='table' AND name=?");
    $st->execute([$table]);
    return $st->fetch() !== false;
}

/**
 * Crea tablas nuevas y migra las viejas de forma idempotente:
 *  - accesspoints gana columna id (para editar/borrar desde la web)
 *  - nodes gana columna notas
 *  - nuevas: firmware, tecnicos (IP por técnico), ajustes (contraseña admin)
 */
function ensureSchema(PDO $pdo): void
{
    $pdo->exec("CREATE TABLE IF NOT EXISTS zona(
        id INTEGER PRIMARY KEY AUTOINCREMENT, zona TEXT NOT NULL, network TEXT NOT NULL DEFAULT '')");

    if (!tableExists($pdo, 'accesspoints')) {
        $pdo->exec("CREATE TABLE accesspoints(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            idzona TEXT NOT NULL, idnodo INTEGER, nodo TEXT NOT NULL DEFAULT '',
            ssid TEXT NOT NULL DEFAULT '')");
    } elseif (!colExists($pdo, 'accesspoints', 'id')) {
        $pdo->exec('ALTER TABLE accesspoints RENAME TO accesspoints_old');
        $pdo->exec("CREATE TABLE accesspoints(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            idzona TEXT NOT NULL, idnodo INTEGER, nodo TEXT NOT NULL DEFAULT '',
            ssid TEXT NOT NULL DEFAULT '')");
        $pdo->exec('INSERT INTO accesspoints(idzona, idnodo, nodo, ssid)
                    SELECT idzona, idnodo, nodo, ssid FROM accesspoints_old');
        $pdo->exec('DROP TABLE accesspoints_old');
    }

    $pdo->exec("CREATE TABLE IF NOT EXISTS nodes(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        clave TEXT UNIQUE,
        nombre TEXT NOT NULL,
        lat REAL NOT NULL,
        lng REAL NOT NULL,
        alt REAL,
        zona TEXT NOT NULL DEFAULT '',
        notas TEXT NOT NULL DEFAULT '',
        creado TEXT NOT NULL DEFAULT (datetime('now')))");
    if (!colExists($pdo, 'nodes', 'notas')) {
        $pdo->exec("ALTER TABLE nodes ADD COLUMN notas TEXT NOT NULL DEFAULT ''");
    }

    $pdo->exec("CREATE TABLE IF NOT EXISTS firmware(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        modelo TEXT NOT NULL UNIQUE,
        version TEXT NOT NULL DEFAULT '',
        notas TEXT NOT NULL DEFAULT '',
        creado TEXT NOT NULL DEFAULT (datetime('now')))");

    $pdo->exec("CREATE TABLE IF NOT EXISTS tecnicos(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        nombre TEXT NOT NULL UNIQUE,
        ip TEXT NOT NULL UNIQUE,
        notas TEXT NOT NULL DEFAULT '',
        activo INTEGER NOT NULL DEFAULT 1,
        creado TEXT NOT NULL DEFAULT (datetime('now')))");

    $pdo->exec("CREATE TABLE IF NOT EXISTS ajustes(k TEXT PRIMARY KEY, v TEXT NOT NULL)");

    // Contraseña inicial del panel: admin / admin (cámbiala en Ajustes).
    $st = $pdo->query("SELECT v FROM ajustes WHERE k='admin_hash'");
    if ($st->fetch() === false) {
        $ins = $pdo->prepare('INSERT INTO ajustes(k, v) VALUES(?, ?)');
        $ins->execute(['admin_hash', password_hash('admin', PASSWORD_DEFAULT)]);
    }
}

function seedIfPossible(PDO $pdo): void
{
    $root = dirname(__DIR__); // .../server
    $src = null;
    foreach ([$root . '/seed_data/nodos.db', $root . '/../assets/seed/nodos.db'] as $c) {
        if (is_file($c)) {
            $src = $c;
            break;
        }
    }
    if ($src === null) {
        return;
    }
    try {
        $pdo->exec("ATTACH DATABASE '" . str_replace("'", "''", $src) . "' AS seed");
        $pdo->exec('INSERT INTO zona(id, zona, network) SELECT id, zona, network FROM seed.zona');
        $pdo->exec('INSERT INTO accesspoints(idzona, idnodo, nodo, ssid)
                    SELECT idzona, idnodo, nodo, ssid FROM seed.accesspoints');
        $pdo->exec('DETACH DATABASE seed');
    } catch (Throwable $e) {
        // BD parcialmente sembrada: se ignora (no bloquea el arranque).
    }
}

function requireToken(): void
{
    $expected = getenv('ISP_ADMIN_TOKEN');
    if ($expected === false || $expected === '') {
        return; // sin token definido: escrituras abiertas (modo local)
    }
    if (($_SERVER['HTTP_X_ADMIN_TOKEN'] ?? '') !== $expected) {
        fail(401, 'token de administrador inválido');
    }
}

/** Escritura permitida si hay sesión del panel o token de la APK. */
function requireWrite(): void
{
    if (isLogged()) {
        return;
    }
    requireToken();
}

function requireSession(): void
{
    if (!isLogged()) {
        fail(401, 'sesión requerida (inicia sesión en el panel)');
    }
}

/** Lista de id's que existen en la tabla dada (para validar referencias). */
function validIds(string $table): array
{
    return array_map('intval', array_column(rows("SELECT id FROM $table"), 'id'));
}

// ---------- ruta (soporta / y subcarpeta tipo /api) ----------

$uri = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';
$base = rtrim(str_replace('\\', '/', dirname($_SERVER['SCRIPT_NAME'] ?? '/')), '/');
if ($base !== '' && $base !== '/' && str_starts_with($uri, $base)) {
    $uri = (string) substr($uri, strlen($base));
}
$path = rtrim($uri, '/') ?: '/';
$method = strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET');

// ---------- sesión del panel web ----------

if ($path === '/session') {
    if ($method === 'GET') {
        out(['logged' => isLogged(), 'user' => isLogged() ? 'admin' : null]);
    }
    if ($method === 'POST') {
        startSession();
        $d = body();
        $user = trim((string) ($d['user'] ?? ''));
        $pass = (string) ($d['pass'] ?? '');
        $st = db()->query("SELECT v FROM ajustes WHERE k='admin_hash'");
        $hash = (string) ($st->fetchColumn() ?: '');
        if ($user !== 'admin' || $hash === '' || !password_verify($pass, $hash)) {
            fail(401, 'usuario o contraseña incorrectos');
        }
        session_regenerate_id(true);
        $_SESSION['admin'] = true;
        out(['ok' => true, 'user' => 'admin']);
    }
    if ($method === 'DELETE') {
        startSession();
        $_SESSION = [];
        session_destroy();
        out(['ok' => true]);
    }
    fail(405, 'método no permitido');
}

if ($method === 'POST' && $path === '/password') {
    requireSession();
    $d = body();
    $actual = (string) ($d['actual'] ?? '');
    $nueva = (string) ($d['nueva'] ?? '');
    if (strlen($nueva) < 6) {
        fail(422, 'la contraseña nueva debe tener al menos 6 caracteres');
    }
    $st = db()->query("SELECT v FROM ajustes WHERE k='admin_hash'");
    $hash = (string) ($st->fetchColumn() ?: '');
    if (!password_verify($actual, $hash)) {
        fail(401, 'la contraseña actual no coincide');
    }
    db()->prepare("UPDATE ajustes SET v=? WHERE k='admin_hash'")
        ->execute([password_hash($nueva, PASSWORD_DEFAULT)]);
    out(['ok' => true]);
}

if ($method === 'GET' && $path === '/health') {
    out(['ok' => true, 'app' => 'isp-config', 'version' => 2]);
}

if ($method === 'GET' && $path === '/stats') {
    $c = static function (string $sql): int {
        return (int) db()->query($sql)->fetchColumn();
    };
    out([
        'zonas' => $c('SELECT COUNT(*) FROM zona'),
        'aps' => $c('SELECT COUNT(*) FROM accesspoints'),
        'nodes' => $c('SELECT COUNT(*) FROM nodes'),
        'firmware' => $c('SELECT COUNT(*) FROM firmware'),
        'tecnicos' => $c('SELECT COUNT(*) FROM tecnicos'),
        'tecnicos_activos' => $c('SELECT COUNT(*) FROM tecnicos WHERE activo=1'),
    ]);
}

// ---------- zonas ----------

if ($path === '/zones') {
    if ($method === 'GET') {
        out(rows('SELECT id, zona, network FROM zona ORDER BY id'));
    }
    requireWrite();
    $d = body();
    if ($method === 'DELETE') {
        $id = (int) ($_GET['id'] ?? $d['id'] ?? 0);
        if ($id <= 0) {
            fail(422, 'falta id');
        }
        $n = db()->prepare('DELETE FROM accesspoints WHERE idzona = ?');
        $n->execute([(string) $id]);
        $st = db()->prepare('DELETE FROM zona WHERE id = ?');
        $st->execute([$id]);
        out(['ok' => true, 'borrados' => $st->rowCount(), 'aps_borradas' => $n->rowCount()]);
    }
    if ($method === 'POST' || $method === 'PUT') {
        $zona = trim((string) ($d['zona'] ?? ''));
        $network = trim((string) ($d['network'] ?? ''));
        if ($zona === '') {
            fail(422, 'falta el nombre de la zona');
        }
        if ($network !== '' && !preg_match('/^[0-9]{1,3}(\.[0-9]{1,3}){1,3}\.?$/D', $network)) {
            fail(422, 'network debe ser tipo 192.168.80. (con punto final)');
        }
        $id = (int) ($d['id'] ?? 0);
        if ($id > 0) {
            db()->prepare('UPDATE zona SET zona=?, network=? WHERE id=?')
                ->execute([$zona, $network, $id]);
            $row = rows('SELECT id, zona, network FROM zona WHERE id=?', [$id]);
        } else {
            db()->prepare('INSERT INTO zona(zona, network) VALUES(?,?)')
                ->execute([$zona, $network]);
            $row = rows('SELECT id, zona, network FROM zona WHERE id=?',
                [(int) db()->lastInsertId()]);
        }
        if (!$row) {
            fail(404, 'zona no encontrada');
        }
        out($row[0], 201);
    }
    fail(405, 'método no permitido');
}

// ---------- APs ----------

if ($path === '/aps') {
    if ($method === 'GET') {
        $zona = (string) ($_GET['zona'] ?? '');
        $id = (int) ($_GET['id'] ?? 0);
        if ($id > 0) {
            $r = rows('SELECT id, idzona, idnodo, nodo, ssid FROM accesspoints WHERE id=?', [$id]);
            if (!$r) {
                fail(404, 'ap no encontrada');
            }
            out($r[0]);
        }
        if ($zona !== '') {
            out(rows(
                'SELECT id, idzona, idnodo, nodo, ssid FROM accesspoints
                 WHERE idzona = ? ORDER BY idnodo',
                [$zona]
            ));
        }
        out(rows('SELECT id, idzona, idnodo, nodo, ssid FROM accesspoints ORDER BY idzona, idnodo'));
    }
    requireWrite();
    $d = body();
    if ($method === 'DELETE') {
        $id = (int) ($_GET['id'] ?? $d['id'] ?? 0);
        if ($id <= 0) {
            fail(422, 'falta id');
        }
        $st = db()->prepare('DELETE FROM accesspoints WHERE id = ?');
        $st->execute([$id]);
        out(['ok' => true, 'borrados' => $st->rowCount()]);
    }
    if ($method === 'POST' || $method === 'PUT') {
        $idzona = trim((string) ($d['idzona'] ?? ''));
        $ssid = trim((string) ($d['ssid'] ?? ''));
        if ($idzona === '' || $ssid === '') {
            fail(422, 'se requiere idzona y ssid');
        }
        $idnodo = isset($d['idnodo']) && $d['idnodo'] !== '' ? (int) $d['idnodo'] : null;
        $nodo = trim((string) ($d['nodo'] ?? ''));
        $id = (int) ($d['id'] ?? 0);
        if ($id > 0) {
            db()->prepare('UPDATE accesspoints SET idzona=?, idnodo=?, nodo=?, ssid=? WHERE id=?')
                ->execute([$idzona, $idnodo, $nodo, $ssid, $id]);
            $row = rows('SELECT id, idzona, idnodo, nodo, ssid FROM accesspoints WHERE id=?', [$id]);
        } else {
            db()->prepare('INSERT INTO accesspoints(idzona, idnodo, nodo, ssid) VALUES(?,?,?,?)')
                ->execute([$idzona, $idnodo, $nodo, $ssid]);
            $row = rows('SELECT id, idzona, idnodo, nodo, ssid FROM accesspoints WHERE id=?',
                [(int) db()->lastInsertId()]);
        }
        if (!$row) {
            fail(404, 'ap no encontrada');
        }
        out($row[0], 201);
    }
    fail(405, 'método no permitido');
}

// ---------- nodos (mismo contrato de siempre + notas) ----------

if ($path === '/nodes') {
    if ($method === 'GET') {
        $zona = (string) ($_GET['zona'] ?? '');
        if ($zona !== '') {
            out(rows(
                'SELECT id, nombre, lat, lng, alt, zona, notas FROM nodes
                 WHERE zona = ? ORDER BY nombre',
                [$zona]
            ));
        }
        out(rows('SELECT id, nombre, lat, lng, alt, zona, notas FROM nodes ORDER BY nombre'));
    }

    requireWrite();
    $d = body();

    if ($method === 'DELETE') {
        $id = (int) ($_GET['id'] ?? $d['id'] ?? 0);
        if ($id <= 0) {
            fail(422, 'falta id');
        }
        $st = db()->prepare('DELETE FROM nodes WHERE id = ?');
        $st->execute([$id]);
        out(['ok' => true, 'borrados' => $st->rowCount()]);
    }

    if ($method === 'POST' || $method === 'PUT') {
        $nombre = trim((string) ($d['nombre'] ?? ''));
        $lat = isset($d['lat']) && is_numeric($d['lat']) ? (float) $d['lat'] : null;
        $lng = isset($d['lng']) && is_numeric($d['lng']) ? (float) $d['lng'] : null;
        if ($nombre === '' || $lat === null || $lng === null) {
            fail(422, 'se requiere nombre, lat y lng');
        }
        if (abs($lat) > 90 || abs($lng) > 180) {
            fail(422, 'coordenadas fuera de rango');
        }
        $alt = isset($d['alt']) && is_numeric($d['alt']) ? (float) $d['alt'] : null;
        $zona = trim((string) ($d['zona'] ?? ''));
        $notas = trim((string) ($d['notas'] ?? ''));
        $clave = trim((string) ($d['clave'] ?? ''));
        $id = (int) ($d['id'] ?? 0);

        if ($clave !== '') {
            // El mismo dispositivo re-sube su nodo: se actualiza, no se duplica.
            db()->prepare(
                'INSERT INTO nodes(clave, nombre, lat, lng, alt, zona, notas) VALUES(?,?,?,?,?,?,?)
                 ON CONFLICT(clave) DO UPDATE SET
                   nombre=excluded.nombre, lat=excluded.lat, lng=excluded.lng,
                   alt=excluded.alt, zona=excluded.zona, notas=excluded.notas'
            )->execute([$clave, $nombre, $lat, $lng, $alt, $zona, $notas]);
            $row = rows('SELECT id, nombre, lat, lng, alt, zona, notas FROM nodes WHERE clave = ?', [$clave]);
        } elseif ($id > 0) {
            db()->prepare(
                'UPDATE nodes SET nombre=?, lat=?, lng=?, alt=?, zona=?, notas=? WHERE id=?'
            )->execute([$nombre, $lat, $lng, $alt, $zona, $notas, $id]);
            $row = rows('SELECT id, nombre, lat, lng, alt, zona, notas FROM nodes WHERE id = ?', [$id]);
        } else {
            db()->prepare(
                'INSERT INTO nodes(nombre, lat, lng, alt, zona, notas) VALUES(?,?,?,?,?,?)'
            )->execute([$nombre, $lat, $lng, $alt, $zona, $notas]);
            $nid = (int) db()->lastInsertId();
            $row = rows('SELECT id, nombre, lat, lng, alt, zona, notas FROM nodes WHERE id = ?', [$nid]);
        }
        if (!$row) {
            fail(404, 'nodo no encontrado');
        }
        out($row[0], 201);
    }

    fail(405, 'método no permitido');
}

// ---------- firmware (catálogo de modelos/versions) ----------

if ($path === '/firmware') {
    if ($method === 'GET') {
        $q = trim((string) ($_GET['q'] ?? ''));
        if ($q !== '') {
            out(rows(
                'SELECT id, modelo, version, notas, creado FROM firmware
                 WHERE modelo LIKE ? OR version LIKE ? ORDER BY modelo',
                ["%$q%", "%$q%"]
            ));
        }
        out(rows('SELECT id, modelo, version, notas, creado FROM firmware ORDER BY modelo'));
    }
    requireWrite();
    $d = body();
    if ($method === 'DELETE') {
        $id = (int) ($_GET['id'] ?? $d['id'] ?? 0);
        if ($id <= 0) {
            fail(422, 'falta id');
        }
        $st = db()->prepare('DELETE FROM firmware WHERE id = ?');
        $st->execute([$id]);
        out(['ok' => true, 'borrados' => $st->rowCount()]);
    }
    if ($method === 'POST' || $method === 'PUT') {
        $modelo = trim((string) ($d['modelo'] ?? ''));
        $version = trim((string) ($d['version'] ?? ''));
        $notas = trim((string) ($d['notas'] ?? ''));
        if ($modelo === '') {
            fail(422, 'se requiere modelo');
        }
        $id = (int) ($d['id'] ?? 0);
        try {
            if ($id > 0) {
                db()->prepare('UPDATE firmware SET modelo=?, version=?, notas=? WHERE id=?')
                    ->execute([$modelo, $version, $notas, $id]);
                $row = rows('SELECT id, modelo, version, notas, creado FROM firmware WHERE id=?', [$id]);
            } else {
                db()->prepare('INSERT INTO firmware(modelo, version, notas) VALUES(?,?,?)')
                    ->execute([$modelo, $version, $notas]);
                $row = rows('SELECT id, modelo, version, notas, creado FROM firmware WHERE id=?',
                    [(int) db()->lastInsertId()]);
            }
        } catch (PDOException $e) {
            if (str_contains($e->getMessage(), 'UNIQUE')) {
                fail(409, 'ya existe un registro para ese modelo');
            }
            throw $e;
        }
        if (!$row) {
            fail(404, 'registro de firmware no encontrado');
        }
        out($row[0], 201);
    }
    fail(405, 'método no permitido');
}

// ---------- técnicos / IPs asignadas ----------

if ($path === '/tecnicos') {
    if ($method === 'GET') {
        $ip = trim((string) ($_GET['ip'] ?? ''));
        if ($ip !== '') {
            $r = rows('SELECT id, nombre, ip, notas, activo, creado FROM tecnicos WHERE ip = ?', [$ip]);
            out($r); // lista vacía = IP libre
        }
        $q = trim((string) ($_GET['q'] ?? ''));
        if ($q !== '') {
            out(rows(
                'SELECT id, nombre, ip, notas, activo, creado FROM tecnicos
                 WHERE nombre LIKE ? OR ip LIKE ? OR notas LIKE ? ORDER BY ip',
                ["%$q%", "%$q%", "%$q%"]
            ));
        }
        out(rows('SELECT id, nombre, ip, notas, activo, creado FROM tecnicos ORDER BY ip'));
    }
    requireWrite();
    $d = body();
    if ($method === 'DELETE') {
        $id = (int) ($_GET['id'] ?? $d['id'] ?? 0);
        if ($id <= 0) {
            fail(422, 'falta id');
        }
        $st = db()->prepare('DELETE FROM tecnicos WHERE id = ?');
        $st->execute([$id]);
        out(['ok' => true, 'borrados' => $st->rowCount()]);
    }
    if ($method === 'POST' || $method === 'PUT') {
        $nombre = trim((string) ($d['nombre'] ?? ''));
        $ip = trim((string) ($d['ip'] ?? ''));
        $notas = trim((string) ($d['notas'] ?? ''));
        $activo = (!empty($d['activo']) && $d['activo'] !== '0' && $d['activo'] !== 0) ? 1 : 0;
        if ($nombre === '' || $ip === '') {
            fail(422, 'se requiere nombre e ip');
        }
        if (filter_var($ip, FILTER_VALIDATE_IP) === false) {
            fail(422, "IP inválida: $ip");
        }
        $id = (int) ($d['id'] ?? 0);
        try {
            if ($id > 0) {
                db()->prepare('UPDATE tecnicos SET nombre=?, ip=?, notas=?, activo=? WHERE id=?')
                    ->execute([$nombre, $ip, $notas, $activo, $id]);
                $row = rows('SELECT id, nombre, ip, notas, activo FROM tecnicos WHERE id=?', [$id]);
            } else {
                db()->prepare('INSERT INTO tecnicos(nombre, ip, notas, activo) VALUES(?,?,?,?)')
                    ->execute([$nombre, $ip, $notas, $activo]);
                $row = rows('SELECT id, nombre, ip, notas, activo FROM tecnicos WHERE id=?',
                    [(int) db()->lastInsertId()]);
            }
        } catch (PDOException $e) {
            if (str_contains($e->getMessage(), 'UNIQUE')) {
                fail(409, 'esa IP o nombre ya está registrado (revoca antes la asignación)');
            }
            throw $e;
        }
        if (!$row) {
            fail(404, 'técnico no encontrado');
        }
        out($row[0], 201);
    }
    fail(405, 'método no permitido');
}

fail(404, 'ruta no encontrada: ' . $method . ' ' . $path);
