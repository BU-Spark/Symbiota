# Symbiota Container Deployment

This directory contains Docker/Podman container configurations for running Symbiota in development and production environments.

## Features

- **Multi-platform support:** Works on ARM64 (Mac M-series) and AMD64 (Linux servers)
- **Development mode:** Live code editing with bind mounts
- **Production mode:** Optimized for deployment with systemd integration
- **Flexible runtime:** Use Docker or Podman interchangeably
- **Bootstrap script:** Automated complete installation (EXPERIMENTAL - see below)

## Bootstrap Installation (EXPERIMENTAL)

**WARNING: This is experimental and has not been fully tested. Use at your own risk.**

The `scripts/bootstrap-symbiota.sh` script provides a complete automated installation that:
- Creates proper separation of code, config, and data
- Initializes database with schema
- Generates all configuration files
- Sets up a ready-to-run Symbiota instance

**Status:** Work in progress. The script has been designed but requires real-world testing before production use.

**To try it (at your own risk):**
```bash
./scripts/bootstrap-symbiota.sh --help
# Read the help, then:
./scripts/bootstrap-symbiota.sh --install-dir /path/to/test
```

**For production use, stick with the manual Quick Start below until this is fully tested.**

> **Note on scripts:** `scripts/` contains `bootstrap-symbiota.sh` and `prepare-container-environment.sh`. `prepare-container-environment.sh` is a helper used by the experimental bootstrap flow and is **not** part of the manual Quick Start below — you do not need to run it for a normal local dev setup.

## Prerequisites

Before you begin you need:

- **A container runtime** — one of:
  - **Docker Desktop** (macOS/Windows): install, then **launch it once** so it
    initializes its VM and installs the `docker`/`docker compose` CLIs. On first
    launch it asks for your password (to install a privileged helper). Wait for
    the whale icon to stop animating before running `make` targets.
  - **Podman + podman-compose** (Linux): set `COMPOSE=podman-compose` in `.env`.
- **GNU Make** (`make --version`). Preinstalled on macOS; `apt install make` on Debian/Ubuntu.
- **git** with access to `BU-Spark/se-symbiota` and (for real config) `BU-Spark/se-symbiota-private`.
- **Disk/RAM:** allow ~3–4 GB for images (Ubuntu 22.04 + PHP 8.1, MySQL 8.0.42 / MariaDB 10.11) plus DB data.

**Apple Silicon (M-series) note:** the dev compose **builds images locally** from
`ubuntuContainer/` and `mysqlContainer/`, so there is no amd64-emulation penalty —
images build natively for arm64. (This differs from the production quay.io image flow.)

**Verify your runtime before continuing:**
```bash
docker info >/dev/null && echo "Docker daemon is up"
docker compose version
```

## Quick Start: Local Dev From Zero

This is the canonical, top-to-bottom path that produces a **running, styled, logged-in**
local stack (Symbiota app + DB + OCR middleware). Follow it in order. The shorter
"Development Environment" recipe further below is kept as a quick reference, but new
users should follow this section.

### 1. Get the code

Clone `se-symbiota` and check out the demo branch (a git worktree on that branch works):

```bash
git clone https://github.com/BU-Spark/se-symbiota.git
cd se-symbiota
git checkout v3.4.1-all-features
```

Also clone the two companion repos you will need later. Clone them as
**siblings of `se-symbiota`** (next to it, not inside it), so the relative paths
used later (`../../herbaria-ocr-middleware`, the overlay copy) line up:

```bash
# instance config overlay — check out the version-matched branch now
git clone --branch config-v3.4.1 https://github.com/BU-Spark/se-symbiota-private.git

# OCR service (default branch `main`)
git clone https://github.com/BU-Spark/herbaria-ocr-middleware.git
```

- `BU-Spark/se-symbiota-private` (branch `config-v3.4.1`) — instance config overlay (used in step 6).
- `BU-Spark/herbaria-ocr-middleware` (branch `main`) — the OCR service (used in step 7).

> Both repos are under the `BU-Spark` GitHub org and may be private; if a clone
> fails with a permission error, request access to `BU-Spark/se-symbiota-private`
> and `BU-Spark/herbaria-ocr-middleware` before continuing.

### 2. Configure the environment (`containers/.env`)

```bash
cd containers
cp .env.example .env
```

> **The `.env.example` defaults are correct for this layout** — `PROJECT_ROOT=..`,
> `CONFIG_DIR=../config`, `SCHEMA_SOURCE=../config/schema`. `containers/` lives
> directly at the repo root, so the code root is one level up (`..`); a plain
> `cp .env.example .env` needs **no path edits** for a standard local dev setup
> (finding B1 — fixed in `.env.example`).

Review the remaining values in `.env` (ports, MySQL creds) and adjust only if they
conflict with your machine; the path variables above are already right.

> **`CONFIG_DIR` vs `CONFIG_OVERLAY_DIR` (finding B3):** these are **two distinct
> variables**, not duplicates. `CONFIG_DIR` is a host path the **prod** build passes
> as a Docker `--build-arg` (Makefile `prod-build`); `CONFIG_OVERLAY_DIR` is the
> runtime bind-mount source for `/config-overlay` in the **prod** compose, consumed
> by `entrypoint.sh`. In **dev** you rely on neither: the dev image runs `apache2ctl`
> directly and has no entrypoint that reads `/config-overlay` (finding D4), so that
> mount is a harmless no-op. Your dev config and overlay files live in the
> bind-mounted code tree (`PROJECT_ROOT`) — see step 3.

### 3. Create the required config files (REQUIRED before `make dev-up`)

The repo ships only `config/dbconnection_template.php` and `config/symbini_template.php`
(the non-template versions are git-ignored). The dev image bind-mounts the code as-is
and does **not** generate these for you, so you **must create them first** or the app
will throw PHP errors at runtime and never connect to the DB (finding D1):

```bash
cp ../config/dbconnection_template.php ../config/dbconnection.php
cp ../config/symbini_template.php     ../config/symbini.php
```

Edit `../config/dbconnection.php` so it points at the dev DB container:

```
host     = symbiota-db
database = symbiota
username = symbiota-user
password = symbiota-pass
port     = 3306
```

(Alternatively, take these files from the `se-symbiota-private` overlay — see step 6.)

> **Why this is required in dev but not prod (finding D4):** the dev image entrypoint
> is `apache2ctl -D FOREGROUND` and never runs `entrypoint.sh`. The config-overlay +
> critical-file verification mechanism (`entrypoint.sh`, documented in
> `se-symbiota-private` `containers/CONFIG_OVERLAY.md`) runs **only in the production
> image** (`Dockerfile.prod`). So in dev, all config must already exist in the
> bind-mounted tree — there is no safety check to catch a missing file.

### 4. Build and start the app + DB

```bash
make dev-up
```

This builds and starts:
- `symbiota-web-dev` — PHP 8.1 / Apache, http://localhost:8080
- `symbiota-db-dev` — MySQL 8.0.42, localhost:33060

> **macOS caveat (finding C6):** `make` runs `prepare-compose`, which uses GNU
> `sed -i` syntax. This only fires when `CONTENT_DIR` or `LOGS_DIR` is set in `.env`
> (both empty by default, so a basic run is unaffected). On macOS/BSD, `sed -i`
> requires an argument (`sed -i ''`), so if you set those data-dir variables on a
> Mac the target will error. Leave `CONTENT_DIR`/`LOGS_DIR` empty unless you are on
> Linux.

### 5. Load data (simplest path: import a provided DB dump)

The stock MySQL 8 container can load a provided dump that carries reference data plus
an `admin` user (0 specimens).

> **Where to get `dump.sql`:** this dump is **not** in any repo (it is not publicly
> redistributable, and the real specimen dataset lives on the BU SCC, not in git).
> Ask a current team member / project maintainer for the shared `dump.sql`, and ask
> them for the `admin` account's password at the same time — that password ships
> *inside the dump* (it sets up the `admin` user) and is what you use to log in at
> step 8. Save the file as `containers/dump.sql` (or adjust the path in the command
> below) before running the import.
>
> **If you cannot obtain the dump,** skip this shortcut and build the schema from
> scratch via the from-scratch path described just below (`docs/INSTALL.md`), heeding
> the MariaDB-vs-MySQL 8 caveat — note the audit found the shipped MySQL 8 container's
> own patches do not apply cleanly and a MariaDB 10.11 DB was required to load the
> reference/geothesaurus data.

```bash
docker exec -i symbiota-db-dev mysql -uroot -ppassword \
  -e "CREATE DATABASE IF NOT EXISTS symbiota"
docker exec -i symbiota-db-dev mysql -uroot -ppassword symbiota < dump.sql
```

If instead you build the schema from scratch, see `docs/INSTALL.md` and note the
caveats it documents: the MariaDB-vs-MySQL 8 patch behavior, the geothesaurus import
needing the correct working directory, the orphaned custom-feature patches, and the
3.4 patch.

### 6. Apply the config overlay (complete + version-matched)

Symbiota's homepage and global theme come from instance overlay files that are
**git-ignored** in the public repo. You must copy the **complete** overlay set from
`se-symbiota-private` branch `config-v3.4.1` into the code tree — applying only the
4 root files, or a **version-mismatched** set, yields an **unstyled site with no
obvious error** (findings D2 and D5).

In step 1 you already cloned `se-symbiota-private` on branch `config-v3.4.1` as a
sibling of `se-symbiota`. (If you skipped it, clone it now:
`git clone --branch config-v3.4.1 https://github.com/BU-Spark/se-symbiota-private.git`.)
Copy the overlay into the bind-mounted code root — i.e. the directory `PROJECT_ROOT`
points to, which is the repo root `..`:

```bash
# from the containers/ directory; ../../se-symbiota-private is the sibling clone
# Back up the dev config/dbconnection.php from step 3 first — the overlay may carry
# its own deployment-oriented config/ that would otherwise overwrite it:
cp ../config/dbconnection.php ../config/dbconnection.php.bak
cp -r ../../se-symbiota-private/* ..
```

Then **restore the dev `config/dbconnection.php` you created in step 3** (the overlay
may carry its own deployment-oriented `config/`, which would point at the wrong DB):

```bash
cp ../config/dbconnection.php.bak ../config/dbconnection.php   # restore the backup you made above
```

If you did not back it up, re-create it from the template and re-enter the same five
values from step 3 (`cp ../config/dbconnection_template.php ../config/dbconnection.php`,
then edit). Forgetting this leaves the wrong DB settings in place and the app fails
silently — there is no dev safety check (finding D4):

```
host     = symbiota-db
database = symbiota
username = symbiota-user
password = symbiota-pass
port     = 3306
```

> **For dev, the inline commands above are the whole overlay step — you do not need
> `CONFIG_OVERLAY.md`.** That doc in `se-symbiota-private` describes the **production**
> image flow (quay.io image, `/config-overlay` bind mount, `docker-compose.prod.yaml`)
> and explicitly redirects back here for dev, so following it on the dev path leads in
> a circle. Treat it as prod-only reference.

The git-ignored files that must be provided are:

- Root: `index.php`, `header.php`, `footer.php`, `leftmenu.php`
- `includes/`: `includes/head.php`, `includes/header.php`, `includes/footer.php`, `includes/leftmenu.php`

`includes/head.php` is what emits the global theme `<link>`s (`header.css`/`main.css`/
`customizations.css`); pages `include_once` it and **silently continue** if it is
missing, so a missing `includes/head.php` produces an unstyled page with no error.
Copy the overlay into the bind-mounted code root (the directory `PROJECT_ROOT` points
to), and **preserve the dev `config/dbconnection.php`** you created in step 3.

> Without these root files, `http://localhost:8080/` renders a bare Apache
> "Index of /" directory listing instead of the homepage (inner modules like
> `/collections/` have their own `index.php` and work regardless).

### 7. Start the OCR middleware and bridge the networks

The dev compose defines **only** `symbiota` + `symbiota-db` — there is **no OCR
service** in it (finding C1). The middleware runs from its own repo and must be
network-bridged onto the app stack. The app stack declares `symbiota-network` with
`driver: bridge`, so Compose names it `containers_symbiota-network` (project-prefixed).

```bash
# 1. Create the shared network the middleware compose expects.
#    REQUIRED FIRST: the middleware compose declares this network as `external`, so
#    it must already exist or `docker compose up -d` (step 2) fails immediately with
#    "network symbiota-network declared as external, but could not be found".
docker network create symbiota-network

# 2. Start the middleware (see herbaria-ocr-middleware/README.md)
cd ../../herbaria-ocr-middleware/docker
docker compose up -d

# 3. Bridge the OCR container onto the APP network with the alias the web
#    container resolves (http://ocr_middleware:8000/)
docker network connect --alias ocr_middleware containers_symbiota-network <ocr container>
```

Replace `<ocr container>` with the running middleware container name. Find the
container name with `docker ps` — it is typically `docker-ocr_middleware-1`. The
web container then reaches the middleware at `http://ocr_middleware:8000/`.

### 8. Verify and log in

All of these should return HTTP 200:
- http://localhost:8080/ — styled home page
- http://localhost:8080/collections/
- http://localhost:8080/sitemap.php
- http://localhost:8000/docs — OCR middleware API docs

Then log in at http://localhost:8080/profile/index.php as user **`admin`** with the
password that ships in the provided dump. (If instead you built the schema **from
scratch** at step 5 rather than loading a dump, the from-scratch DDL seeds
`admin` / `admin` — see `docs/INSTALL.md` — and you should change it immediately
after first login.) **End state: a working, styled, logged-in portal.**

---

## Quick Start

### Development Environment

> **For new users:** follow "Quick Start: Local Dev From Zero" above instead — this
> shorter recipe omits required steps (config files, overlay, OCR). It is kept only
> as a quick command reference.

1. **Configure environment:**
   ```bash
   cp .env.example .env
   # The .env.example path defaults (PROJECT_ROOT=.. , CONFIG_DIR=../config ,
   # SCHEMA_SOURCE=../config/schema) are already correct for this repo layout.
   ```

2. **Create required config files** (the app errors at runtime without them):
   ```bash
   cp ../config/dbconnection_template.php ../config/dbconnection.php
   cp ../config/symbini_template.php     ../config/symbini.php
   # then edit dbconnection.php (host=symbiota-db, db=symbiota, user=symbiota-user, pass=symbiota-pass, port=3306)
   ```

3. **Start containers:**
   ```bash
   make dev-up
   ```

4. **Access Symbiota:**
   - Web interface: http://localhost:8080 (or port from .env)
   - Database: localhost:33060
   - Note: until the config overlay is applied, `http://localhost:8080/` shows a
     bare Apache directory listing (see "Quick Start: Local Dev From Zero" step 6).

5. **View logs:**
   ```bash
   make logs
   ```

6. **Stop containers:**
   ```bash
   make dev-down
   ```

### Production Deployment (Ubuntu 22.04 Server)

1. **Deploy code to server:**
   ```bash
   # On server
   sudo mkdir -p /opt/symbiota
   # Copy code to /opt/symbiota
   ```

2. **Create .env file:**
   ```bash
   cd /opt/symbiota/containers
   cp .env.example .env
   # Edit .env with production settings
   ```

3. **Install systemd service:**
   ```bash
   sudo cp systemd/symbiota.service /etc/systemd/system/
   sudo systemctl daemon-reload
   sudo systemctl enable symbiota
   sudo systemctl start symbiota
   ```

4. **Check status:**
   ```bash
   sudo systemctl status symbiota
   sudo journalctl -u symbiota -f
   ```

## Configuration

### Environment Variables (.env)

> **Note:** values below mirror the real `.env.example`, whose path defaults are
> already correct for this repo layout (`PROJECT_ROOT=..`, `CONFIG_DIR=../config`,
> `SCHEMA_SOURCE=../config/schema`) — finding B1 is fixed in the file, so no manual
> correction is needed.

```bash
# Paths (defaults from .env.example — correct for this layout)
PROJECT_ROOT=..               # Path to Symbiota code (one level up)
CONFIG_DIR=../config          # Path to instance config files
SCHEMA_SOURCE=../config/schema # Path to database schemas/backups

# MySQL (note the HYPHEN in the username, matching .env.example)
MYSQL_ROOT_PASSWORD=password
MYSQL_DATABASE=symbiota
MYSQL_USER=symbiota-user
MYSQL_PASSWORD=symbiota-pass

# Ports (HOST:CONTAINER mapping)
# Format: "HOST_PORT:CONTAINER_PORT"
# - Left side: External port on your host machine (set in .env)
# - Right side: Internal port inside container (hardcoded in compose file)
#
# Development: services exposed for debugging
HTTP_PORT=8080                # Web interface - host port for http://localhost:8080
MYSQL_PORT=33060             # Database - host port for MySQL client connections
#
# OCR: there is NO OCR_PORT in .env.example. The OCR service is configured via
#   OCR_HOST=ocr_middleware       # service hostname on the Docker network (underscore)
#   OCR_PORT_INTERNAL=8000        # internal port the middleware listens on
# The OCR middleware is not part of the dev compose — see the OCR step in
# "Quick Start: Local Dev From Zero" for how to run and bridge it.
#
# Production: Only HTTP_PORT exposed; MySQL/OCR internal-only for security

# MySQL Data Storage
MYSQL_DATA_DIR=mysql-data   # Default: Docker volume
# For separate filesystem: MYSQL_DATA_DIR=/mnt/data/mysql
```

**Using a separate filesystem for database:**
If your database should be on a separate mounted filesystem:
```bash
# In .env
MYSQL_DATA_DIR=/mnt/data/mysql

# Ensure directory exists and has correct permissions
sudo mkdir -p /mnt/data/mysql
sudo chown -R 999:999 /mnt/data/mysql  # MySQL container runs as UID 999
```

### Config File Overlay

Symbiota requires instance-specific config files (from `se-symbiota-private`). For the
**dev** path, the self-contained overlay commands are in "Quick Start: Local Dev From
Zero" step 6 — follow those. `se-symbiota-private` `containers/CONFIG_OVERLAY.md`
documents the **production** image flow only (and redirects back here for dev), so do
not follow it for a local dev setup. There are two approaches:

**The overlay is all-or-nothing and must be version-matched (finding D5).** The public
repo git-ignores the homepage/theme files; applying only some of them, or a
version-mismatched set (e.g. v3.2.4 onto v3.4.1), yields an **unstyled site with no
obvious error**. You must provide the **complete** set from the matching
`config-v3.4.1` overlay:

- Root: `index.php`, `header.php`, `footer.php`, `leftmenu.php`
- `includes/`: `includes/head.php`, `includes/header.php`, `includes/footer.php`, `includes/leftmenu.php`

`includes/head.php` emits the global theme `<link>`s; it is `include_once`'d and
**silently skipped if missing**, so its absence is the usual cause of an unstyled site.

> **Dev vs prod (finding D4):** only the **production** image runs `entrypoint.sh`,
> which performs the overlay copy + critical-file verification. The **dev** image
> entrypoint is `apache2ctl -D FOREGROUND` and skips this entirely, so in dev the
> overlay files must already exist in the bind-mounted code tree (the directory
> `PROJECT_ROOT` points to). There is no dev safety check for missing files.

**Option 1: Manual overlay (before starting containers)**
```bash
# Development: copy the overlay into the bind-mounted code root.
# This is the directory PROJECT_ROOT points to in your .env (here, the repo root,
# i.e. "..") — NOT an undefined "worktrees/container-dev/" path.
# ../../se-symbiota-private is the sibling clone on branch config-v3.4.1 (see step 1).
cp -r ../../se-symbiota-private/* ..

# Production
cp -r /path/to/config/* /opt/symbiota/
```
Preserve the dev `config/dbconnection.php` you created earlier when copying the overlay.

**Option 2: Bake into production image (recommended for immutable deploys)**
```bash
# Set CONFIG_DIR in .env
CONFIG_DIR=/path/to/se-symbiota-private

# Build will automatically include config
make prod-build
```

If `CONFIG_DIR` is set, config files are copied into the image at build time.

## Database Setup

1. **Import schema:**
   ```bash
   # Access database container
   make db-shell

   # Or manually:
   docker exec -it symbiota-db mysql -u root -p
   ```

2. **Create Symbiota users:**
   ```sql
   CREATE USER 'symbiota-r'@'%' IDENTIFIED BY 'symbiota-r-pass';
   GRANT SELECT ON symbiota.* TO 'symbiota-r'@'%';

   CREATE USER 'symbiota-rw'@'%' IDENTIFIED BY 'symbiota-rw-pass';
   GRANT SELECT, INSERT, UPDATE, DELETE ON symbiota.* TO 'symbiota-rw'@'%';

   FLUSH PRIVILEGES;
   ```

3. **Import backup (if available):**
   ```bash
   # From host
   docker exec -i symbiota-db mysql -u root -p<password> symbiota < backup.sql
   ```

## Makefile Commands

Run `make help` to see all available commands.

**Development:**
- `make dev-up` - Start development environment
- `make dev-down` - Stop development environment
- `make dev-build` - Rebuild containers

**Production:**
- `make prod-up` - Start production environment
- `make prod-down` - Stop production environment
- `make prod-build` - Rebuild containers

**Common:**
- `make logs` - View container logs
- `make shell` - Access web container shell
- `make db-shell` - Access database shell
- `make ps` - List running containers
- `make status` - Show detailed status

## Using Podman Instead of Docker

Set the `COMPOSE` variable:

```bash
# In .env
COMPOSE=podman-compose

# Or on command line
make dev-up COMPOSE=podman-compose
```

## Troubleshooting

### Containers won't start
```bash
make status          # Check container status
make logs            # View error messages
docker ps -a         # See all containers
```

### Permission errors (SELinux)
The compose files include `:z` flags for SELinux compatibility on Fedora/RHEL systems.

### Port already in use
Change `HTTP_PORT` and `MYSQL_PORT` in `.env`

### Database connection errors
1. Check database is running: `make ps`
2. Verify credentials in `.env` match Symbiota config files
3. Check network: `docker network inspect symbiota-network`

## Architecture

- **Web container:** Ubuntu 22.04 + PHP 8.1 + Apache + Tesseract OCR
- **Database container:** MySQL 8.0.42 (MySQL 5.7 cannot restore the shipped dumps; the dev audit also validated MariaDB 10.11)
- **Network:** Bridge network for container communication
- **Volumes:** Named volume for persistent database storage

## Next Steps

- Configure Xdebug for debugging (future enhancement)
- Add SSL/TLS support for production
- Configure automated backups
- Add monitoring/logging integration