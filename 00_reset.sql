-- =====================================================================
-- RESET / LIMPIEZA — usa SOLO si quieres borrar todo y empezar de cero
-- Ejecutar como root: sudo mysql -u root -p < 00_reset.sql
-- ¡CUIDADO! Esto elimina TODA la base de datos cursos_online.
-- =====================================================================

DROP DATABASE IF EXISTS cursos_online;
DROP USER IF EXISTS 'admin_cursos_online'@'localhost';
DROP USER IF EXISTS 'cursos_app'@'localhost';
FLUSH PRIVILEGES;
