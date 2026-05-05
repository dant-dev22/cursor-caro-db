-- =====================================================================
-- Datos iniciales (seed) — Plataforma de Cursos en Video
-- Ejecutar DESPUÉS de 01_schema.sql
-- =====================================================================

USE cursos_online;

-- ---------------------------------------------------------------------
-- Roles
-- ---------------------------------------------------------------------
INSERT INTO roles (slug, name, description, permissions) VALUES
('super_admin', 'Super Administrador', 'Acceso total al sistema', JSON_ARRAY(
    'videos.create','videos.read','videos.update','videos.delete',
    'codes.create','codes.read','codes.update','codes.delete',
    'categories.manage','admins.manage','settings.manage','audit.read'
)),
('editor', 'Editor de contenido', 'Puede gestionar videos y códigos pero no admins', JSON_ARRAY(
    'videos.create','videos.read','videos.update','videos.delete',
    'codes.create','codes.read','codes.update','codes.delete',
    'categories.manage'
)),
('viewer', 'Solo lectura', 'Visualiza estadísticas sin editar', JSON_ARRAY(
    'videos.read','codes.read','audit.read'
));

-- ---------------------------------------------------------------------
-- Admin inicial
-- IMPORTANTE: Cambiar el hash. Ejemplo abajo es bcrypt de "ChangeMe123!"
-- Para generar un hash nuevo en Node.js:
--   require('bcrypt').hashSync('TuPasswordReal', 12)
-- En PHP: password_hash('TuPasswordReal', PASSWORD_BCRYPT, ['cost'=>12])
-- ---------------------------------------------------------------------
INSERT INTO admins (role_id, name, email, password_hash, is_active)
VALUES (
    (SELECT id FROM roles WHERE slug = 'super_admin'),
    'Administrador Principal',
    'admin@example.com',
    '$2b$12$REPLACE_THIS_WITH_REAL_BCRYPT_HASH_BEFORE_PROD_USE.....',
    TRUE
);

-- ---------------------------------------------------------------------
-- Categorías
-- ---------------------------------------------------------------------
INSERT INTO categories (slug, name, description, sort_order, is_active) VALUES
('asesorias',  'Asesorías',  'Sesiones de asesoría individual o grupal', 10, TRUE),
('educacion',  'Educación',  'Contenido educativo formal',                20, TRUE),
('talleres',   'Talleres',   'Talleres prácticos de corta duración',      30, TRUE),
('cursos',     'Cursos',     'Cursos completos estructurados',            40, TRUE),
('especiales', 'Especiales', 'Contenido especial o eventos únicos',       50, TRUE);

-- ---------------------------------------------------------------------
-- Settings iniciales
-- ---------------------------------------------------------------------
INSERT INTO settings (key_name, value, value_type, description, is_public) VALUES
('platform_name',           'Mi Plataforma de Cursos', 'string',  'Nombre visible de la plataforma',                  TRUE),
('default_session_minutes', '120',                     'integer', 'Minutos por defecto si código no define duración', FALSE),
('max_failed_login',        '5',                       'integer', 'Intentos fallidos antes de bloquear admin',        FALSE),
('lockout_minutes',         '15',                      'integer', 'Minutos de bloqueo tras superar el límite',        FALSE),
('cdn_default_provider',    'bunny',                   'string',  'Proveedor de CDN por defecto',                     FALSE),
('support_email',           'soporte@example.com',     'string',  'Correo de contacto para usuarios',                 TRUE);
