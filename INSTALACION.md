# Instalación de la BD en tu VPS

Guía paso a paso para desplegar la base de datos `cursos_online` en una VPS donde MySQL ya está instalado y otro backend ya está corriendo. El objetivo es **no tocar nada de lo que ya funciona**.

## Datos del proyecto

| Concepto              | Valor                  |
|-----------------------|------------------------|
| Base de datos         | `cursos_online`        |
| Usuario MySQL (app)   | `admin_cursos_online`  |
| Password MySQL        | `cursos1234`           |
| Host                  | `localhost`            |
| Puerto                | `3306`                 |

> El password `cursos1234` es OK para desarrollo. Cámbialo por algo fuerte antes de exponer la app a internet.

## Resumen de archivos

| Archivo                  | Para qué sirve                                                |
|--------------------------|---------------------------------------------------------------|
| `00_reset.sql`           | Borra TODO. Úsalo solo para empezar de cero.                  |
| `01_schema.sql`          | Crea la BD, tablas, vistas y el usuario MySQL.                |
| `02_seed.sql`            | Inserta roles, admin inicial, categorías y settings.          |
| `03_queries_ejemplo.sql` | Queries de referencia para que el backend las use.            |

---

## 0. (Opcional) Limpiar lo que ya hayas corrido

Si te hiciste bolas y quieres empezar limpio:

```bash
sudo mysql -u root -p < ~/cursos-online-db/00_reset.sql
```

Eso elimina la BD `cursos_online` y el usuario `admin_cursos_online`. Después puedes seguir con el paso 1.

## 1. Subir los archivos al VPS

Desde tu máquina local:

```bash
scp 00_reset.sql 01_schema.sql 02_seed.sql 03_queries_ejemplo.sql usuario@TU_VPS:/home/usuario/cursos-online-db/
```

O directo en el VPS:

```bash
ssh usuario@TU_VPS
mkdir -p ~/cursos-online-db
# luego copia o crea los archivos ahí
```

## 2. Verificar la versión de MySQL

```bash
mysql --version
```

Recomendado MySQL 8.x. Funciona con 5.7+.

## 3. Ejecutar el schema (crea BD + tablas + usuario `admin_cursos_online`)

```bash
sudo mysql -u root -p < ~/cursos-online-db/01_schema.sql
```

Si no hay output, salió bien. Esto deja creado:
- La base de datos `cursos_online`
- Todas las tablas y vistas
- El usuario MySQL `admin_cursos_online@localhost` con permisos sobre esa BD

## 4. Generar el hash de contraseña del admin (de la APLICACIÓN)

Ojo: este paso NO es para el usuario MySQL. Es para el usuario administrador que va a entrar al panel de admin del frontend (la fila que se inserta en la tabla `admins`).

Genera un hash bcrypt real desde el VPS o tu máquina:

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

Copia el resultado y reemplaza esta línea de `02_seed.sql`:

```sql
'$2b$12$REPLACE_THIS_WITH_REAL_BCRYPT_HASH_BEFORE_PROD_USE.....'
```

También ajusta `admin@example.com` y el `name` con tus datos reales.

## 5. Ejecutar el seed

```bash
sudo mysql -u root -p < ~/cursos-online-db/02_seed.sql
```

## 6. Verificar que todo quedó bien

Conéctate con el usuario nuevo:

```bash
mysql -u admin_cursos_online -p cursos_online
# password: cursos1234
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

## 7. Configurar el backend

En el `.env` del nuevo backend:

```env
DB_HOST=localhost
DB_PORT=3306
DB_NAME=cursos_online
DB_USER=admin_cursos_online
DB_PASSWORD=cursos1234
DB_CONNECTION_LIMIT=10
```

Asegúrate de que el otro backend siga apuntando a su propia BD/usuario y este nuevo apunte solo a `cursos_online`.

## 8. Backup automático (recomendado antes de salir a producción)

Crea `/home/usuario/backups/backup-cursos.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail
TS=$(date +%Y%m%d-%H%M%S)
DEST=/home/usuario/backups/cursos
mkdir -p "$DEST"
mysqldump --single-transaction --quick --routines --triggers \
    -u admin_cursos_online -p"cursos1234" cursos_online \
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

> Cuando cambies el password del usuario MySQL, recuerda actualizar este script y el `.env` del backend.

## 9. Cambia los passwords antes de producción

- El password MySQL `cursos1234`: ejecuta en MySQL
  ```sql
  ALTER USER 'admin_cursos_online'@'localhost' IDENTIFIED BY 'NuevoPasswordFuerte';
  FLUSH PRIVILEGES;
  ```
- El password del admin de la aplicación: oblígalo desde el panel en el primer login.

---

## Troubleshooting

**`ERROR 1396 (HY000): Operation CREATE USER failed`**
El usuario ya existe. Corre primero `00_reset.sql` o ejecuta:
```sql
DROP USER 'admin_cursos_online'@'localhost';
```

**`ERROR 1071 (42000): Specified key was too long`**
MySQL 5.7 con configuración antigua. Solución: actualizar a MySQL 8 o asegurarte de tener `innodb_default_row_format=DYNAMIC` y `innodb_large_prefix=ON`.

**El backend no conecta**
- Verifica que conectes a `localhost` (el GRANT está limitado a localhost). Si tu backend corre en otra máquina, ejecuta:
  ```sql
  CREATE USER 'admin_cursos_online'@'IP_BACKEND' IDENTIFIED BY 'cursos1234';
  GRANT ALL PRIVILEGES ON cursos_online.* TO 'admin_cursos_online'@'IP_BACKEND';
  FLUSH PRIVILEGES;
  ```
- `SHOW GRANTS FOR 'admin_cursos_online'@'localhost';` para confirmar permisos.

**Coexistencia con el otro backend**
Cada backend usa su BD y su usuario. No hay conflicto. Solo verifica que `max_connections` alcance: `SHOW VARIABLES LIKE 'max_connections';`. Para dos backends pequeños, el default de 151 sobra.

---

## Próximos pasos sugeridos

- Implementar rate limiting en el endpoint de validación de códigos (evita brute-force).
- Servir los videos del CDN con **signed URLs** generadas por el backend solo para sesiones válidas.
- Cron en el backend que invalide sesiones expiradas y mande métricas.
- Cuando agregues cuentas de usuario, crear tabla `users` y opcionalmente vincular `access_sessions.user_id` (campo nullable, no rompe lo existente).
