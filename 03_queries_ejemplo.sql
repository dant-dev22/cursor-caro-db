-- =====================================================================
-- Queries de ejemplo / referencia para el backend
-- =====================================================================

USE cursos_online;

-- ---------------------------------------------------------------------
-- 1) Validar código + email cuando un usuario quiere acceder
-- ---------------------------------------------------------------------
-- Reemplaza :code y :email con parámetros preparados (NUNCA concatenar)
SELECT
    c.id,
    c.code,
    c.duration_minutes,
    c.valid_until,
    c.max_uses,
    c.current_uses,
    c.max_uses_per_email,
    c.allowed_email_domain,
    (
        SELECT COUNT(*) FROM access_sessions s
        WHERE s.access_code_id = c.id AND s.email = :email AND s.is_revoked = FALSE
    ) AS uses_for_this_email
FROM access_codes c
WHERE c.code = :code
  AND c.is_active = TRUE
  AND c.deleted_at IS NULL
  AND NOW() BETWEEN c.valid_from AND c.valid_until
  AND (c.max_uses = 0 OR c.current_uses < c.max_uses);

-- ---------------------------------------------------------------------
-- 2) Crear sesión de acceso (transacción recomendada)
-- ---------------------------------------------------------------------
START TRANSACTION;

INSERT INTO access_sessions (
    access_code_id, email, session_token, ip_address, user_agent, expires_at
) VALUES (
    :access_code_id,
    :email,
    :session_token,            -- generar en backend: crypto.randomBytes(32).toString('hex')
    :ip,
    :user_agent,
    LEAST(
        (SELECT valid_until FROM access_codes WHERE id = :access_code_id),
        DATE_ADD(NOW(), INTERVAL COALESCE(
            (SELECT duration_minutes FROM access_codes WHERE id = :access_code_id),
            (SELECT CAST(value AS UNSIGNED) FROM settings WHERE key_name = 'default_session_minutes')
        ) MINUTE)
    )
);

UPDATE access_codes
SET current_uses = current_uses + 1
WHERE id = :access_code_id;

COMMIT;

-- ---------------------------------------------------------------------
-- 3) Validar token de sesión en cada request del front
-- ---------------------------------------------------------------------
SELECT s.id, s.email, s.access_code_id, s.expires_at
FROM access_sessions s
WHERE s.session_token = :token
  AND s.is_revoked = FALSE
  AND s.expires_at > NOW();

-- ---------------------------------------------------------------------
-- 4) Listar videos accesibles para una sesión activa
-- ---------------------------------------------------------------------
SELECT v.id, v.title, v.slug, v.thumbnail_url, v.duration_seconds, c.name AS category
FROM access_sessions s
JOIN access_code_videos acv ON acv.access_code_id = s.access_code_id
JOIN videos v               ON v.id = acv.video_id AND v.deleted_at IS NULL AND v.is_published = TRUE
JOIN categories c           ON c.id = v.category_id
WHERE s.session_token = :token
  AND s.is_revoked = FALSE
  AND s.expires_at > NOW();

-- ---------------------------------------------------------------------
-- 5) Obtener URL del CDN solo si la sesión tiene acceso al video
-- ---------------------------------------------------------------------
SELECT v.cdn_url, v.cdn_provider, v.cdn_video_id
FROM access_sessions s
JOIN access_code_videos acv ON acv.access_code_id = s.access_code_id
JOIN videos v               ON v.id = acv.video_id
WHERE s.session_token = :token
  AND s.is_revoked = FALSE
  AND s.expires_at > NOW()
  AND v.id = :video_id
  AND v.is_published = TRUE
  AND v.deleted_at IS NULL;

-- ---------------------------------------------------------------------
-- 6) Registrar/actualizar progreso de visualización (UPSERT)
-- Aprovecha el UNIQUE KEY (session_id, video_id)
-- ---------------------------------------------------------------------
INSERT INTO video_views (session_id, video_id, last_position_seconds, watched_seconds)
VALUES (:session_id, :video_id, :position, :watched)
ON DUPLICATE KEY UPDATE
    last_position_seconds = VALUES(last_position_seconds),
    watched_seconds       = GREATEST(watched_seconds, VALUES(watched_seconds)),
    updated_at            = NOW();

-- ---------------------------------------------------------------------
-- 7) Admin: estadísticas rápidas
-- ---------------------------------------------------------------------
-- Sesiones activas
SELECT COUNT(*) AS active_sessions FROM v_live_sessions;

-- Top 10 videos más vistos en últimos 30 días
SELECT v.title, COUNT(*) AS views, AVG(vv.watched_seconds) AS avg_watched
FROM video_views vv
JOIN videos v ON v.id = vv.video_id
WHERE vv.started_at > DATE_SUB(NOW(), INTERVAL 30 DAY)
GROUP BY v.id, v.title
ORDER BY views DESC
LIMIT 10;

-- Códigos por vencer en los próximos 7 días
SELECT code, label, valid_until
FROM access_codes
WHERE deleted_at IS NULL AND is_active = TRUE
  AND valid_until BETWEEN NOW() AND DATE_ADD(NOW(), INTERVAL 7 DAY);

-- ---------------------------------------------------------------------
-- 8) Limpieza periódica (correr con cron diario)
-- ---------------------------------------------------------------------
-- Marcar como revocadas las sesiones expiradas hace más de 30 días (opcional)
UPDATE access_sessions
SET is_revoked = TRUE, revoked_at = NOW()
WHERE expires_at < DATE_SUB(NOW(), INTERVAL 30 DAY)
  AND is_revoked = FALSE;
