# The MySQL option

With `--db=mysql`, Studio still serves PHP; only the database runs in Docker.

## What the installer does

1. Creates the Studio site without starting it. At this point the folder has WordPress and the
   SQLite drop-in, but no `wp-config.php` and no database yet.
2. Copies `templates/docker-compose.yml` to the site folder and fills in the values below, then
   runs `docker compose up -d --wait`.

   | Setting | Value |
   |---|---|
   | Compose project | `<slug>-studio` (volume `<slug>-studio_mysql-data`) |
   | Container | `<slug>-studio-mysql` |
   | Image | `mysql:8.4` (`MYSQL_IMAGE` at the top of `install.sh`) |
   | Host/port | `127.0.0.1:<port>`, first free port from 3381 or `--db-port` |
   | Database | `wordpress` (Studio forces `DB_NAME` to `wordpress`) |
   | User/pass | `wp` / `wp` (root: `root`) |

3. Removes the SQLite pieces: `wp-content/db.php`, `wp-content/database/` and
   `wp-content/mu-plugins/sqlite-database-integration/`. Studio puts SQLite back on start while
   **any** of them exist, and leaves a site on MySQL only when all are gone and `wp-config.php`
   exists.
4. Creates `wp-config.php` with `studio wp config create`, pointing at the container.
5. Starts the site. Studio installs WordPress into the empty MySQL database on this first start.
   (The installer runs `studio wp core install` itself if that ever doesn't happen.)

Multisite, if chosen, is converted after this, the same way as on SQLite.

## Running it alongside other Docker stacks

Compose identifies a stack by its **project name**, not its folder. Two compose files with the
same `name:` are treated as one project: starting one replaces the other's container and shares
its volume. The installer keeps these three unique per site by building them from the site slug:

- `name:` (the project, which also names the volume)
- `container_name:`
- the host port

## Day to day

Run these in the site folder:

```bash
docker compose up -d      # start the database (it also restarts with Docker)
docker compose stop       # stop it
docker compose down -v    # remove the container and delete the data
```

`studio delete` moves the site folder, including `docker-compose.yml`, to the trash. To remove the
database after that, name the project: `docker compose -p <slug>-studio down -v`.

Start the database before `studio start`. To import a dump, relax `sql_mode`, because WordPress
uses zero dates:

```bash
docker compose exec -T mysql mysql -uwp -pwp --init-command="SET SESSION sql_mode='NO_ENGINE_SUBSTITUTION'" wordpress < dump.sql
```

`docker-compose.yml` sits in the site root, which Studio serves. It only holds the local
`wp` / `wp` login, but don't put real credentials in it.
