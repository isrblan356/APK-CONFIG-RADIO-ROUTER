-- Seed exportado de backup_script/nodos/nodos.db (8 zonas reales).
-- La app lo precarga en sqflite del móvil. Todo queda instalado local.
INSERT INTO zona(id,zona,network) VALUES
(1,'Girardota','192.168.80.'),
(2,'Amagá','192.168.100.'),
(3,'Sur Oeste','192.168.100.'),
(4,'Caldas','192.168.100.'),
(5,'Medellín','192.168.50.'),
(6,'Guarne','192.168.60.'),
(7,'Angelópolis','192.168.100.'),
(8,'Barbosa','192.168.80.');
-- Los APs se sincronizan desde nube o se importan con tu nodos.db original.
-- Copia backup_script/nodos/nodos.db a assets/seed/nodos.db si quieres precarga total.
