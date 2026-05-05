# Instalación de la BD en tu VPS

Guía paso a paso para desplegar la base de datos `cursos_online` en una VPS donde MySQL ya está instalado y otro backend ya está corriendo. El objetivo es **no tocar nada de lo que ya funciona**.

## Resumen rápido

1. Subir los `.sql` al VPS.
2. Crear la base de datos y un usuario MySQL **dedicado** (separado del que usa el otro backend).
3. Ejecutar `01_schema.sql` y luego `02_seed.sql`.
4. Verificar tablas y reemplazar el hash del admin inicial.
5. Configurar las variables de entorno del nuevo backend.
6. Hacer backup automatizado.

---

## 1. Subir los archivos al VPS

Desde tu máquina local:

```bash
scp 01_schema.sql 02_seed.sql 03_queries_ejemplo.sql usuario@TU_VPS:/home/usuario/cursos-online-db/
```

O si prefieres clonar desde un repo:

```bash
ssh usuario@TU_VPS
mkdir -p ~/cursos-online-db && cd ~/cursos-online-db
# git clone ... o subir manualmente
```

## 2. Verificar la versión de MySQL

```bash
mysql --version
```

Recomendado MySQL 8.x. Si tienes 5.7, el schema funciona pero quita o ajusta los `JSON` si tu versión los rechaza (5.7+ los soporta).

## 3. Conectar a MySQL como root (o usuario con privilegios)

```bash
sudo mysql -u root -p
```

Si tu MySQL usa `auth_socket` para root, basta con `sudo mysql`.

## 4. Crear un usuario dedicado para esta aplicación

**No reutilices el usuario del otro backend.** Aislar usuarios y permisos por base de datos es básico para seguridad y debugging.

Dentro del prompt de MySQL:

```sql
-- Reemplaza la contraseña por una fuerte (usa un gestor de contraseñas)
CREATE USER 'cursos_app'@'localhost' IDENTIFIED BY 'CAMBIA_ESTO_POR_UNA_CONTRASEÑA_FUERTE';

-- Estos privilegios alcanzan para que el backend funcione (CRUD + DDL básico para migraciones)
-- Si quieres ser más estricto, quita ALTER/CREATE/DROP/INDEX y aplícalos manualmente cuando hagas migraciones
GRANT SELECT, INSERT, UPDATE, DELETE, EXECUTE,
      CREATE, ALTER, DROP, INDEX, REFERENCES, CREATE VIEW, SHOW VIEW
ON cursos_online.* TO 'cursos_app'@'localhost';

FLUSH PRIVILEGES;
EXIT;
```

> Si tu backend corre en otra máquina, cambia `'localhost'` por la IP correspondiente o `'%'` y restringe por firewall.

## 5. Ejecutar el schema

```bash
mysql -u root -p < ~/cursos-online-db/01_schema.sql
```

Esto crea la BD `cursos_online` y todas las tablas. Si todo va bien, no verás output (silencio = éxito).

## 6. Generar el hash de contraseña del admin

Antes de correr el seed, genera un hash bcrypt real para el primer admin. Desde el VPS o tu máquina:

**Node.js:**
```bash
node -e "console.log(require('bcrypt').hashSync('TuPasswordReal', 12))"
```

**PHP:**
```bash
php -r "echo password_hash('TuPasswordReal', PASSWORD_BCRYPT, ['cost'=>12]).PHP_EOL;"
```

**Python:**
```bash
python3 -c "import bcrypt; print(bcrypt.hashpw(b'TuPasswordReal', bcrypt.gensalt(12)).decode())"
```

Copia el resultado y reemplaza la línea correspondiente en `02_seed.sql`:

```sql
'$2b$12$REPLACE_THIS_WITH_REAL_BCRYPT_HASH_BEFORE_PROD_USE.....'
```

También cambia `admin@example.com` por tu correo real y el `name`.

## 7. Ejecutar el seed

```bash
mysql -u root -p < ~/cursos-online-db/02_seed.sql
```

## 8. Verificar que todo quedó bien

```bash
mysql -u cursos_app -p cursos_online
```

Una vez dentro:

```sql
SHOW TABLES;
-- Debes ver: access_code_videos, access_codes, access_sessions, admins,
--            audit_logs, categories, roles, settings, video_views, videos

SELECT slug, name FROM categories;
SELECT slug, name FROM roles;
SELECT id, name, email FROM admins;

-- Probar las vistas
SELECT * FROM v_active_codes;
SELECT * FROM v_live_sessions;

EXIT;
```

## 9. Configurar el backend

En el `.env` (o como manejes config) del nuevo backend:

```env
DB_HOST=localhost
DB_PORT=3306
DB_NAME=cursos_online
DB_USER=cursos_app
DB_PASSWORD=la_contraseña_que_pusiste_en_el_paso_4
DB_CONNECTION_LIMIT=10
```

Asegúrate de que **el otro backend siga apuntando a su propia BD/usuario** y este nuevo apunte solo a `cursos_online`.

## 10. Backup automático (recomendado antes de salir a producción)

Crea `/home/usuario/backups/backup-cursos.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
TS=$(date +%Y%m%d-%H%M%S)
DEST=/home/usuario/backups/cursos
mkdir -p "$DEST"
mysqldump --single-transaction --quick --routines --triggers \
    -u cursos_app -p"TU_PASSWORD" cursos_online \
    | gzip > "$DEST/cursos_online-$TS.sql.gz"
# Conservar solo últimos 14 días
find "$DEST" -name "cursos_online-*.sql.gz" -mtime +14 -delete
```

```bash
chmod +x /home/usuario/backups/backup-cursos.sh
crontab -e
# Añadir (backup diario a las 03:30):
30 3 * * * /home/usuario/backups/backup-cursos.sh >> /home/usuario/backups/backup.log 2>&1
```

## 11. Cambia la contraseña del admin tras el primer login

El backend debería forzar un cambio de contraseña en el primer acceso del admin. Como mínimo, hazlo manualmente desde el panel apenas esté listo.

---

## Troubleshooting

**`ERROR 1396 (HY000): Operation CREATE USER failed`**
El usuario ya existe. Bórralo con `DROP USER 'cursos_app'@'localhost';` y vuelve a crearlo, o usa `ALTER USER` para cambiar la contraseña.

**`ERROR 1071 (42000): Specified key was too long`**
Estás en MySQL 5.7 con `innodb_large_prefix` desactivado. Solución: actualizar a MySQL 8 o agregar `ROW_FORMAT=DYNAMIC` y `innodb_large_prefix=ON`.

**El backend no conecta**
- Verifica que el usuario fue creado para el host correcto (`localhost` vs IP).
- Verifica que el firewall del VPS permita el puerto 3306 solo en localhost (recomendado).
- `SHOW GRANTS FOR 'cursos_app'@'localhost';` para confirmar permisos.

**Coexistencia con el otro backend**
Como cada backend usa su propia BD y su propio usuario, no hay conflicto. Solo asegúrate de que MySQL tenga `max_connections` suficientes (`SHOW VARIABLES LIKE 'max_connections';`). Para dos backends pequeños, el default de 151 sobra.

---

## Próximos pasos sugeridos

- Implementar rate limiting a nivel app sobre el endpoint de validación de códigos (evita brute-force).
- Servir los videos del CDN con **signed URLs** (Bunny, CloudFront, etc.) generadas por el backend solo para sesiones válidas.
- Añadir un cron en el backend que invalide sesiones expiradas y mande métricas.
- Cuando agregues cuentas de usuario, crear tabla `users` y opcionalmente vincular `access_sessions.user_id` (campo nullable, no rompe lo existente).
