-- =====================================================================
-- Plataforma de Cursos en Video - Schema MySQL
-- Versión: 1.0.0
-- Motor: MySQL 8.x (compatible con 5.7+ con ajustes menores)
-- Charset: utf8mb4 (soporte completo Unicode incluido emojis)
--
-- VALORES DE ESTE PROYECTO:
--   Base de datos: cursos_online
--   Usuario app:   admin_cursos_online
--   Password:      cursos1234   (CAMBIAR EN PRODUCCIÓN)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1) Crear base de datos
-- ---------------------------------------------------------------------
CREATE DATABASE IF NOT EXISTS cursos_online
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_unicode_ci;

USE cursos_online;

-- Asegura modo estricto para evitar inserciones silenciosamente truncadas
SET sql_mode = 'STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,NO_ZERO_DATE,ERROR_FOR_DIVISION_BY_ZERO,NO_ENGINE_SUBSTITUTION';


-- =====================================================================
-- TABLAS DE ADMINISTRACIÓN
-- =====================================================================

-- ---------------------------------------------------------------------
-- Roles (preparado para crecimiento: super_admin, editor, viewer, etc.)
-- ---------------------------------------------------------------------
CREATE TABLE roles (
    id              INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    slug            VARCHAR(50)  NOT NULL UNIQUE COMMENT 'Identificador único legible: super_admin, editor, etc.',
    name            VARCHAR(100) NOT NULL,
    description     VARCHAR(255) NULL,
    permissions     JSON NULL COMMENT 'Lista de permisos en formato JSON, ej: ["videos.create","codes.delete"]',
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- Administradores (los que crean videos y códigos)
-- ---------------------------------------------------------------------
CREATE TABLE admins (
    id              INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    role_id         INT UNSIGNED NOT NULL,
    name            VARCHAR(150) NOT NULL,
    email           VARCHAR(190) NOT NULL,
    password_hash   VARCHAR(255) NOT NULL COMMENT 'bcrypt/argon2 hash, NUNCA texto plano',
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    last_login_at   TIMESTAMP NULL,
    last_login_ip   VARCHAR(45) NULL,
    failed_attempts SMALLINT UNSIGNED NOT NULL DEFAULT 0,
    locked_until    TIMESTAMP NULL COMMENT 'Para bloqueo temporal tras X intentos fallidos',
    created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    deleted_at      TIMESTAMP NULL COMMENT 'Soft delete',
    CONSTRAINT fk_admins_role FOREIGN KEY (role_id) REFERENCES roles(id),
    UNIQUE KEY uniq_admin_email (email),
    KEY idx_admins_active (is_active, deleted_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- =====================================================================
-- CONTENIDO: CATEGORÍAS Y VIDEOS
-- =====================================================================

-- ---------------------------------------------------------------------
-- Categorías (tabla en vez de ENUM para extensibilidad)
-- ---------------------------------------------------------------------
CREATE TABLE categories (
    id              INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    slug            VARCHAR(100) NOT NULL UNIQUE COMMENT 'URL friendly: asesorias, educacion, etc.',
    name            VARCHAR(100) NOT NULL,
    description     TEXT NULL,
    icon            VARCHAR(255) NULL COMMENT 'Nombre de icono o URL',
    color_hex       VARCHAR(7) NULL COMMENT 'Color en formato #RRGGBB para UI',
    sort_order      INT NOT NULL DEFAULT 0,
    is_active       BOOLEAN NOT NULL DEFAULT TRUE,
    created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    deleted_at      TIMESTAMP NULL,
    KEY idx_categories_active (is_active, deleted_at, sort_order)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- Videos (metadata; el archivo vive en CDN externo)
-- ---------------------------------------------------------------------
CREATE TABLE videos (
    id                  INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    category_id         INT UNSIGNED NOT NULL,
    title               VARCHAR(255) NOT NULL,
    slug                VARCHAR(255) NOT NULL UNIQUE,
    description         TEXT NULL,
    -- CDN: nunca exponer cdn_url al frontend; se sirve a través de un endpoint con sesión válida
    cdn_provider        VARCHAR(50) NULL COMMENT 'bunny, cloudflare, vimeo, etc.',
    cdn_url             VARCHAR(1000) NOT NULL COMMENT 'URL real del video en el CDN',
    cdn_video_id        VARCHAR(255) NULL COMMENT 'ID del video en el CDN para signed URLs',
    thumbnail_url       VARCHAR(1000) NULL,
    preview_url         VARCHAR(1000) NULL COMMENT 'Trailer o clip corto público',
    duration_seconds    INT UNSIGNED NULL,
    instructor_name     VARCHAR(150) NULL,
    instructor_bio      TEXT NULL,
    -- Estado
    is_published        BOOLEAN NOT NULL DEFAULT FALSE,
    published_at        TIMESTAMP NULL,
    -- Metadata libre para crecer sin migrar (tags, requisitos, etc.)
    metadata            JSON NULL,
    -- Auditoría
    created_by          INT UNSIGNED NOT NULL,
    updated_by          INT UNSIGNED NULL,
    created_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    deleted_at          TIMESTAMP NULL,
    CONSTRAINT fk_videos_category   FOREIGN KEY (category_id) REFERENCES categories(id),
    CONSTRAINT fk_videos_created_by FOREIGN KEY (created_by) REFERENCES admins(id),
    CONSTRAINT fk_videos_updated_by FOREIGN KEY (updated_by) REFERENCES admins(id),
    KEY idx_videos_category   (category_id, is_published, deleted_at),
    KEY idx_videos_published  (is_published, published_at),
    FULLTEXT KEY ft_videos_search (title, description)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- =====================================================================
-- CÓDIGOS DE ACCESO
-- =====================================================================

-- ---------------------------------------------------------------------
-- Códigos de acceso
-- - valid_from / valid_until: ventana absoluta en la que el código existe
-- - duration_minutes: cuánto dura el acceso DESDE el primer uso (opcional)
-- - max_uses: cuántas veces total puede usarse el código
-- - max_uses_per_email: cuántas sesiones por correo
-- ---------------------------------------------------------------------
CREATE TABLE access_codes (
    id                      INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    code                    VARCHAR(64) NOT NULL UNIQUE COMMENT 'Código alfanumérico único entregado al usuario',
    label                   VARCHAR(150) NULL COMMENT 'Etiqueta interna del admin: "Promo abril", "Cliente X"',
    description             TEXT NULL,
    -- Ventana de validez absoluta
    valid_from              TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    valid_until             TIMESTAMP NOT NULL,
    -- Duración de la sesión tras el primer uso (NULL = solo aplica valid_until)
    duration_minutes        INT UNSIGNED NULL COMMENT 'Si se setea, la sesión expira X minutos después del primer acceso',
    -- Límites de uso
    max_uses                INT UNSIGNED NOT NULL DEFAULT 1 COMMENT 'Total de activaciones permitidas (0 = ilimitado)',
    current_uses            INT UNSIGNED NOT NULL DEFAULT 0,
    max_uses_per_email      INT UNSIGNED NOT NULL DEFAULT 1 COMMENT 'Cuántas sesiones simultáneas por correo (0 = ilimitado)',
    -- Restricciones opcionales
    allowed_email_domain    VARCHAR(150) NULL COMMENT 'Si se setea, solo correos @dominio pueden usarlo',
    -- Estado
    is_active               BOOLEAN NOT NULL DEFAULT TRUE,
    -- Auditoría
    created_by              INT UNSIGNED NOT NULL,
    updated_by              INT UNSIGNED NULL,
    created_at              TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at              TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    deleted_at              TIMESTAMP NULL,
    CONSTRAINT fk_codes_created_by FOREIGN KEY (created_by) REFERENCES admins(id),
    CONSTRAINT fk_codes_updated_by FOREIGN KEY (updated_by) REFERENCES admins(id),
    KEY idx_codes_active   (is_active, deleted_at, valid_from, valid_until),
    KEY idx_codes_validity (valid_until)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- Relación N:M: un código puede dar acceso a varios videos.
-- Si el código no tiene filas aquí, considerarlo inválido (decisión a nivel app).
-- ---------------------------------------------------------------------
CREATE TABLE access_code_videos (
    access_code_id  INT UNSIGNED NOT NULL,
    video_id        INT UNSIGNED NOT NULL,
    created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (access_code_id, video_id),
    CONSTRAINT fk_acv_code  FOREIGN KEY (access_code_id) REFERENCES access_codes(id) ON DELETE CASCADE,
    CONSTRAINT fk_acv_video FOREIGN KEY (video_id)       REFERENCES videos(id)       ON DELETE CASCADE,
    KEY idx_acv_video (video_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- =====================================================================
-- SESIONES DE USUARIO (PASAJEROS) Y ANALYTICS
-- =====================================================================

-- ---------------------------------------------------------------------
-- Sesión de acceso: cuando un usuario ingresa código + email,
-- se genera un session_token que el front usa en cada request.
-- ---------------------------------------------------------------------
CREATE TABLE access_sessions (
    id                  BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    access_code_id      INT UNSIGNED NOT NULL,
    email               VARCHAR(190) NOT NULL,
    session_token       CHAR(64) NOT NULL UNIQUE COMMENT 'Token aleatorio (ej: hex de 32 bytes)',
    ip_address          VARCHAR(45) NULL,
    user_agent          VARCHAR(500) NULL,
    started_at          TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expires_at          TIMESTAMP NOT NULL COMMENT 'MIN(code.valid_until, started_at + duration_minutes)',
    last_activity_at    TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    is_revoked          BOOLEAN NOT NULL DEFAULT FALSE COMMENT 'El admin puede revocar manualmente',
    revoked_at          TIMESTAMP NULL,
    revoked_by          INT UNSIGNED NULL,
    CONSTRAINT fk_sessions_code       FOREIGN KEY (access_code_id) REFERENCES access_codes(id),
    CONSTRAINT fk_sessions_revoked_by FOREIGN KEY (revoked_by)     REFERENCES admins(id),
    KEY idx_sessions_email   (email),
    KEY idx_sessions_expires (expires_at, is_revoked),
    KEY idx_sessions_code_email (access_code_id, email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- Vistas de video (una fila por reproducción/sesión-video)
-- Útil para analytics y para detectar abuso.
-- ---------------------------------------------------------------------
CREATE TABLE video_views (
    id                      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    session_id              BIGINT UNSIGNED NOT NULL,
    video_id                INT UNSIGNED NOT NULL,
    started_at              TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    last_position_seconds   INT UNSIGNED NOT NULL DEFAULT 0,
    watched_seconds         INT UNSIGNED NOT NULL DEFAULT 0 COMMENT 'Total acumulado real visto',
    completed               BOOLEAN NOT NULL DEFAULT FALSE,
    completed_at            TIMESTAMP NULL,
    updated_at              TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_views_session FOREIGN KEY (session_id) REFERENCES access_sessions(id) ON DELETE CASCADE,
    CONSTRAINT fk_views_video   FOREIGN KEY (video_id)   REFERENCES videos(id),
    UNIQUE KEY uniq_views_session_video (session_id, video_id),
    KEY idx_views_video (video_id, started_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- =====================================================================
-- INFRAESTRUCTURA TRANSVERSAL
-- =====================================================================

-- ---------------------------------------------------------------------
-- Auditoría de acciones del admin (qué se creó/editó/borró)
-- ---------------------------------------------------------------------
CREATE TABLE audit_logs (
    id              BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    admin_id        INT UNSIGNED NULL,
    action          VARCHAR(100) NOT NULL COMMENT 'video.create, code.delete, login, etc.',
    entity_type     VARCHAR(50) NULL COMMENT 'video, access_code, admin, etc.',
    entity_id       BIGINT UNSIGNED NULL,
    metadata        JSON NULL COMMENT 'Snapshot del cambio (antes/después)',
    ip_address      VARCHAR(45) NULL,
    user_agent      VARCHAR(500) NULL,
    created_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT fk_audit_admin FOREIGN KEY (admin_id) REFERENCES admins(id),
    KEY idx_audit_admin   (admin_id, created_at),
    KEY idx_audit_entity  (entity_type, entity_id),
    KEY idx_audit_created (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ---------------------------------------------------------------------
-- Configuración dinámica (para no tocar código por cambios menores)
-- ---------------------------------------------------------------------
CREATE TABLE settings (
    id              INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    key_name        VARCHAR(100) NOT NULL UNIQUE,
    value           TEXT NULL,
    value_type      ENUM('string','integer','boolean','json') NOT NULL DEFAULT 'string',
    description     VARCHAR(255) NULL,
    is_public       BOOLEAN NOT NULL DEFAULT FALSE COMMENT 'Si TRUE, el front puede leerlo sin autenticación',
    updated_by      INT UNSIGNED NULL,
    updated_at      TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT fk_settings_admin FOREIGN KEY (updated_by) REFERENCES admins(id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- =====================================================================
-- USUARIO DE APLICACIÓN
-- =====================================================================
-- Crea el usuario que el backend usará para conectarse a esta BD.
-- IMPORTANTE: 'cursos1234' es un password DE DESARROLLO. Cámbialo por
-- algo fuerte antes de exponer la app a internet.
-- ---------------------------------------------------------------------
CREATE USER IF NOT EXISTS 'admin_cursos_online'@'localhost' IDENTIFIED BY 'cursos1234';

GRANT SELECT, INSERT, UPDATE, DELETE, EXECUTE,
      CREATE, ALTER, DROP, INDEX, REFERENCES, CREATE VIEW, SHOW VIEW
ON cursos_online.* TO 'admin_cursos_online'@'localhost';

FLUSH PRIVILEGES;


-- =====================================================================
-- VISTAS ÚTILES (opcional pero conveniente)
-- =====================================================================

-- Vista: códigos activos con su estado de uso
CREATE OR REPLACE VIEW v_active_codes AS
SELECT
    c.id,
    c.code,
    c.label,
    c.valid_from,
    c.valid_until,
    c.duration_minutes,
    c.max_uses,
    c.current_uses,
    (c.max_uses = 0 OR c.current_uses < c.max_uses) AS has_uses_left,
    (NOW() BETWEEN c.valid_from AND c.valid_until)  AS is_within_window,
    c.is_active,
    c.created_at
FROM access_codes c
WHERE c.deleted_at IS NULL;

-- Vista: sesiones vivas
CREATE OR REPLACE VIEW v_live_sessions AS
SELECT
    s.id,
    s.email,
    s.access_code_id,
    c.code,
    s.started_at,
    s.expires_at,
    s.last_activity_at,
    TIMESTAMPDIFF(MINUTE, NOW(), s.expires_at) AS minutes_left
FROM access_sessions s
JOIN access_codes c ON c.id = s.access_code_id
WHERE s.is_revoked = FALSE
  AND s.expires_at > NOW();
