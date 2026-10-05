<?php
declare(strict_types=1);

/**
 * ISP CONFIG — API de sincronización (PHP + SQLite, cero dependencias).
 *
 * Contrato (el mismo que lee la APK):
 *   GET    /health          -> {"ok":true,"app":"isp-config"}
 *   GET    /zones           -> [{"id":1,"zona":"Girardota","network":"192.168.80."}]
 *   GET    /aps?zona=1      -> [{"idzona":"1","idnodo":1,"nodo":"...","ssid":"..."}]
 *   GET    /nodes           -> [{"id":1,"nombre":"...","lat":..,"lng":..,"alt":..,"zona":"..."}]
 *   POST   /nodes           -> crea/actualiza (JSON: nombre,lat,lng[,alt,zona,clave])
 *   PUT    /nodes           -> igual que POST (acepta "id" en el cuerpo)
 *   DELETE /nodes?id=N      -> borra
 *
 * Escrituras: si existe la variable de entorno ISP_ADMIN_TOKEN se exige la
 * cabecera X-Admin-Token (la APK guarda ese token en Admin -> Nube).
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

function db(): PDO
{
    static $pdo = null;
    if ($pdo !== null) {
        return $pdo;
    }
    $file = dirname(__DIR__) . '/data/isp.sqlite';
    if (!is_file($file)) {
        fail(500, 'sin base de datos: ejecuta  php scripts/seed.php');
    }
    $pdo = new PDO('sqlite:' . $file, null, null, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    ]);
    $pdo->exec('PRAGMA busy_timeout=3000');
    return $pdo;
}

function rows(string $sql, array $args = []): array
{
    $st = db()->prepare($sql);
    $st->execute($args);
    return $st->fetchAll();
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

// ---------- ruta (soporta / y subcarpeta tipo /api) ----------

$uri = parse_url($_SERVER['REQUEST_URI'] ?? '/', PHP_URL_PATH) ?: '/';
$base = rtrim(str_replace('\\', '/', dirname($_SERVER['SCRIPT_NAME'] ?? '/')), '/');
if ($base !== '' && $base !== '/' && str_starts_with($uri, $base)) {
    $uri = (string) substr($uri, strlen($base));
}
$path = rtrim($uri, '/') ?: '/';
$method = strtoupper($_SERVER['REQUEST_METHOD'] ?? 'GET');

// ---------- enrutamiento ----------

if ($method === 'GET' && $path === '/health') {
    out(['ok' => true, 'app' => 'isp-config', 'version' => 1]);
}

if ($method === 'GET' && $path === '/zones') {
    out(rows('SELECT id, zona, network FROM zona ORDER BY id'));
}

if ($method === 'GET' && $path === '/aps') {
    $zona = (string) ($_GET['zona'] ?? '');
    if ($zona === '') {
        fail(422, 'falta el parámetro zona');
    }
    out(rows(
        'SELECT idzona, idnodo, nodo, ssid FROM accesspoints WHERE idzona = ? ORDER BY idnodo',
        [$zona]
    ));
}

if ($path === '/nodes') {
    if ($method === 'GET') {
        out(rows('SELECT id, nombre, lat, lng, alt, zona FROM nodes ORDER BY nombre'));
    }

    requireToken();
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
        $clave = trim((string) ($d['clave'] ?? ''));
        $id = (int) ($d['id'] ?? 0);

        if ($clave !== '') {
            // El mismo dispositivo re-sube su nodo: se actualiza, no se duplica.
            db()->prepare(
                'INSERT INTO nodes(clave, nombre, lat, lng, alt, zona) VALUES(?,?,?,?,?,?)
                 ON CONFLICT(clave) DO UPDATE SET
                   nombre=excluded.nombre, lat=excluded.lat, lng=excluded.lng,
                   alt=excluded.alt, zona=excluded.zona'
            )->execute([$clave, $nombre, $lat, $lng, $alt, $zona]);
            $row = rows('SELECT id, nombre, lat, lng, alt, zona FROM nodes WHERE clave = ?', [$clave]);
        } elseif ($id > 0) {
            db()->prepare(
                'UPDATE nodes SET nombre=?, lat=?, lng=?, alt=?, zona=? WHERE id=?'
            )->execute([$nombre, $lat, $lng, $alt, $zona, $id]);
            $row = rows('SELECT id, nombre, lat, lng, alt, zona FROM nodes WHERE id = ?', [$id]);
        } else {
            db()->prepare(
                'INSERT INTO nodes(nombre, lat, lng, alt, zona) VALUES(?,?,?,?,?)'
            )->execute([$nombre, $lat, $lng, $alt, $zona]);
            $nid = (int) db()->lastInsertId();
            $row = rows('SELECT id, nombre, lat, lng, alt, zona FROM nodes WHERE id = ?', [$nid]);
        }
        if (!$row) {
            fail(404, 'nodo no encontrado');
        }
        out($row[0], 201);
    }

    fail(405, 'método no permitido');
}

fail(404, 'ruta no encontrada: ' . $method . ' ' . $path);
