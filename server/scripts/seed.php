<?php
declare(strict_types=1);

/**
 * Crea data/isp.sqlite con el esquema del servidor y copia zonas + APs desde
 * el nodos.db real que trae la carpeta (server/seed_data/nodos.db).
 *
 * Uso:  php scripts/seed.php  [ruta/al/nodos.db]
 * No pisa una base ya existente (borra data/isp.sqlite si quieres re-sembrar).
 */

$root = dirname(__DIR__);                 // .../wisp_configurator/server
$src = $argv[1] ?? null;
if ($src === null) {
    // Portátil: primero la copia que viaja con esta carpeta; si estás dentro
    // del repo completo, se usa la original assets/seed/nodos.db.
    $bundled = $root . '/seed_data/nodos.db';
    $repo = $root . '/../assets/seed/nodos.db';
    $src = is_file($bundled) ? $bundled : $repo;
}
$out = $root . '/data/isp.sqlite';

if (!is_file($src)) {
    fwrite(STDERR, "no existe la fuente: $src\n");
    exit(1);
}
if (is_file($out)) {
    fwrite(STDOUT, "ya existe $out (borra para re-sembrar)\n");
    exit(0);
}

@mkdir($root . '/data', 0775, true);

$pdo = new PDO('sqlite:' . $out, null, null, [
    PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
]);

$pdo->exec('CREATE TABLE IF NOT EXISTS zona(
    id INTEGER PRIMARY KEY AUTOINCREMENT, zona TEXT, network TEXT)');
$pdo->exec('CREATE TABLE IF NOT EXISTS accesspoints(
    idzona TEXT, idnodo INTEGER, nodo TEXT, ssid TEXT)');
$pdo->exec('CREATE TABLE IF NOT EXISTS nodes(
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    clave TEXT UNIQUE,
    nombre TEXT NOT NULL,
    lat REAL NOT NULL,
    lng REAL NOT NULL,
    alt REAL,
    zona TEXT NOT NULL DEFAULT \'\',
    creado TEXT NOT NULL DEFAULT (datetime(\'now\')))');

$pdo->exec("ATTACH DATABASE '" . str_replace("'", "''", realpath($src)) . "' AS seed");
$pdo->exec('INSERT INTO zona(id, zona, network) SELECT id, zona, network FROM seed.zona');
$pdo->exec('INSERT INTO accesspoints(idzona, idnodo, nodo, ssid)
            SELECT idzona, idnodo, nodo, ssid FROM seed.accesspoints');
$pdo->exec('DETACH DATABASE seed');

$zonas = (int) $pdo->query('SELECT COUNT(*) FROM zona')->fetchColumn();
$aps = (int) $pdo->query('SELECT COUNT(*) FROM accesspoints')->fetchColumn();

fwrite(STDOUT, "OK $out — zonas=$zonas aps=$aps nodes=0\n");
