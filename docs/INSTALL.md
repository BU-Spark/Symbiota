# Installing Symbiota

## REQUIREMENTS
GIT Client - not required, though recommend for installation and updating source code

### Web Server
Apache HTTP Server (2.x or better) - other PHP-enabled web servers will work, though the code has been well-tested using Apache HTTP Server and Nginx.

### PHP
PHP 8.2 or higher is recommended for the best performance, security, and feature support. The minimum requirement is PHP 8.1, but using older versions may cause security and performance issues over time. When third party authentication is enabled, PHP 8.2 or above is required.

Required extensions:
- mbstring
- openssl

```ini
extension=curl
extension=exif
extension=gd
extension=mysqli
extension=zip
```

Optional: Pear package [Image_Barcode2](https://pear.php.net/package/Image_Barcode2) – enables barcodes on specimen labels

Optional: Install Pear [Mail](https://pear.php.net/package/Mail/redirected) for SMTP mail support

Optional: Install pecl package [Imagick](https://pecl.php.net/package/imagick) alternative library for image processing.

Recommended configuration adjustments: 
```ini
; Maximum allowed size for uploaded files.
; https://php.net/upload-max-filesize
upload_max_filesize = 100M

; How many GET/POST/COOKIE input variables may be accepted
max_input_vars = 2000

; Maximum amount of memory a script may consume
; https://php.net/memory-limit
memory_limit = 256M

; Maximum size of POST data that PHP will accept.
; Its value may be 0 to disable the limit. It is ignored if POST data reading
; is disabled through enable_post_data_reading.
; https://php.net/post-max-size
post_max_size = 100M
```

### Database
MariaDB (v10.3+) or MySQL (v8.0+) - Development and testing performed using MariaDB. If you are using Oracle MySQL instead, please [report any issues](https://github.com/Symbiota/Symbiota/issues/new).

Recommended Settings:
```sql
SET GLOBAL sql_mode = 'STRICT_TRANS_TABLES,ERROR_FOR_DIVISION_BY_ZERO,NO_AUTO_CREATE_USER,NO_ENGINE_SUBSTITUTION';
```

## INSTRUCTIONS

### STEP 1: Download Symbiota code

```
git clone https://github.com/Symbiota/Symbiota.git
```

or [Download Source Files From Latest Release](https://github.com/Symbiota/Symbiota/releases)

### STEP 2: Run setup script

Run /config/setup.bash (e.g. sudo bash setup.bash)

This script will attempt to:

Find all `_template.*` files and copy them to a new file at the same location without the `_template` suffix.

<!-- Output from: tree --prune --matchdirs -P '*_template.*' -I 'vendor' Symbiota -->
```
Symbiota
├── collections
│   ├── editor
│   │   └── includes
│   │       └── config
│   │           ├── occurVarColl1_template.php
│   │           ├── occurVarDefault_template.php
│   │           └── occurVarGenObsDefault_template.php
│   └── specprocessor
│       └── standalone_scripts
│           ├── ImageBatchConf_template.php
│           └── ImageBatchConnectionFactory_template.php
├── config
│   ├── auth_config_template.php
│   ├── dbconnection_template.php
│   └── symbini_template.php
├── content
│   ├── collections
│   │   └── reports
│   │       └── labeljson_template.php
│   └── lang
│       ├── index.es_template.php
│       └── misc
│           ├── aboutproject.en_template.php
│           └── aboutproject.es_template.php
├── docs
│   └── pull_request_template.md
├── includes
│   ├── citationcollection_template.php
│   ├── citationdataset_template.php
│   ├── citationgbif_template.php
│   ├── citationportal_template.php
│   ├── footer_template.php
│   ├── header_template.php
│   ├── head_template.php
│   ├── minimalheader_template.php
│   └── usagepolicy_template.php
├── index_template.php
└── misc
    ├── aboutproject_template.php
    ├── contacts_template.php
    ├── generalsimple_template.php
    ├── general_template.php
    └── partners_template.php
```

Then set ACL permissions on folders that need to be writable by the web server.
```
Symbiota
├── api
│   └── storage
│       └── framework
└── content
    ├── collections
    ├── collicon
    ├── dwca
    └── geolocate
```

### STEP 3: Configure the Symbiota Portal
Symbiota initialization configuration

Modify variables within 
<!-- Output from: tree --prune --matchdirs -P 'symbini.php' -I 'vendor' Symbiota -->
```
Symbiota
└── config
    └── symbini.php
```
to match your project environment. See instructions within configuration file.
<!-- TODO (Logan) Add mininum required symbini variables here -->

### STEP 4: Install and configure Symbiota database schema
<!-- 1. Create new database (e.g. CREATE SCHEMA symbdb CHARACTER SET utf8 COLLATE utf8_general_ci) -->

<!-- 2. Create read-only and read/write users for Symbiota database -->
Run sql to create database and create read and write users. Make sure to change passwords and database name as needed.

* Note make sure to run this sql as the root user or a user with proper permissions.
```sql
-- Create new database
CREATE SCHEMA symbdb CHARACTER SET utf8 COLLATE utf8_general_ci

-- Create read-only and read/write users for Symbiota database
CREATE USER 'symbreader'@'localhost' IDENTIFIED BY 'password1';
CREATE USER 'symbwriter'@'localhost' IDENTIFIED BY 'password2';
GRANT SELECT,EXECUTE ON `symbdb`.* TO `symbreader`@localhost;
GRANT SELECT,UPDATE,INSERT,DELETE,EXECUTE ON `symbdb`.* TO `symbwriter`@localhost;
```

Then modify `dbconnection.php` with read-only and read/write logins, passwords, and database name to the values you chose.
* Note - If running a php version prior to 8.1 you must add the following
```php
mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT)
```

<!-- Output: tree --prune --matchdirs -P 'dbconnection.php' -I 'vendor' Symbiota  -->
```
Symbiota
└── config
    └── dbconnection.php
```

Note - If your php version lower than 8.1 you must add this line to `dbconnection.php` in the `getCon` function.
```php
mysqli_report(MYSQLI_REPORT_ERROR | MYSQLI_REPORT_STRICT)
```

Lastly, install database schema and schema patch files.

> **Simplest path for newcomers (containerized dev stack):** building the schema
> from scratch (below) hits several caveats on the shipped MySQL 8 container (see
> the boxes in Method 2). If a database dump is available, loading it into the
> stock container is far simpler and is the recommended path. See
> [`containers/README.md`](../containers/README.md) for the dump-loading flow
> (the provided dump carries reference data plus an `admin` user). Use the
> from-scratch build documented here only when no dump is available.

#### Method 1: Web Browser Schema Manager
Navigate to `<SymbiotaServer>/admin/schemamanager.php`.

Selecting Sitemap from site menu will automatically forward to installer if database schema is missing.

Follow the prompts provided by the database schema assistant

#### Method 2: MySQL Command Line
Run the following sql source files in order from top to bottom. The base schema
must be applied first, then each versioned patch in ascending order, then the
custom-feature patches.

<!-- Output: tree --prune --matchdirs -P '*_patch-*|db_schema-*' -I 'vendor' Symbiota -->
```
Symbiota
└── config
    └── schema
        ├── 3.0
        │   ├── db_schema-3.0.sql              # base schema (apply first)
        │   └── patches
        │       ├── db_schema_patch-3.1.sql
        │       ├── db_schema_patch-3.2.sql
        │       ├── db_schema_patch-3.3.sql
        │       └── db_schema_patch-3.4.sql    # required on a v3.4.x checkout
        └── 1.0
            └── patches                        # custom-feature patches (apply last)
                ├── db_schema_patch-batch-core.sql          # creates the shared `batch` table (apply FIRST, before any feature below)
                ├── db_schema_patch-image-batching.sql      # creates batch_XREF, batch_user, images_barcode (FK to batch)
                ├── db_schema_patch-batch-ingestion.sql     # batch ingestion support
                ├── db_schema_patch-ai-transcription.sql    # creates ocr_results (ML transcription); FK_ocr_results_batch references batch
                ├── db_schema_patch-quick-entry.sql         # quick-entry support
                └── db_schema_patch-portal-mysql57-compat.sql  # portal compat fixes (REQUIRED on MySQL 5.7 / STRICT mode)
```

> **Apply order for the custom-feature patches.** Apply
> `db_schema_patch-batch-core.sql` **FIRST** — it creates the shared `batch`
> table. After that, the four feature patches
> (`image-batching`, `batch-ingestion`, `ai-transcription`, `quick-entry`) can be
> applied in any order, because each one's foreign keys to `batch` are satisfied
> by batch-core. In other words, each feature is now applyable as
> **(batch-core + that feature)** — you no longer have to apply image-batching
> before ai-transcription. These patches are idempotent: they use
> `CREATE TABLE IF NOT EXISTS`, guarded `ADD COLUMN`, and no `DROP TABLE`, so
> re-running them will not wipe existing data.
>
> Finally, on **MySQL 5.7 or any server running with `STRICT_TRANS_TABLES`**,
> apply `db_schema_patch-portal-mysql57-compat.sql` **after** patch 3.4 — it makes
> the `omoccurdeterminations.dateLastModified` and `mediametadata.created_at`/
> `updated_at` timestamp columns explicitly NULL-able. (Harmless on MySQL 8, but
> required on 5.7.)

> **Do not skip patch 3.4 or the custom-feature patches.** On a `v3.4.x`
> checkout, `db_schema_patch-3.4.sql` is required (it adds the `mediametadata`
> table, etc.). The custom-feature patches under `config/schema/1.0/patches/`
> create the ML/batch tables this fork depends on (`batch`, `ocr_results`,
> `batch_XREF`, and related). If you omit them the portal will start but those
> features silently have no backing tables.

**Concrete commands.** Apply the files in order. To avoid hardcoding names you can
glob the versioned patches (the `*` expansion sorts `3.1` → `3.4`), but apply the
base schema first and the `1.0` custom patches last. Run these as the database
root user (or a user with sufficient privileges).

> **Database name — `symbdb` vs `symbiota`.** The local-server commands below use
> `symbdb` (matching the `CREATE SCHEMA symbdb` / GRANT block above). The
> containerized dev stack in `containers/README.md` instead uses **`symbiota`**
> (`MYSQL_DATABASE=symbiota`). Whichever you pick, the database name **must match the
> one in your `dbconnection.php`**, or the app connects to an empty/absent schema. If
> you are following the containerized dev path, replace `symbdb` with `symbiota` in
> every command below.

Running directly against a local MySQL/MariaDB server:
```bash
# IMPORTANT (E3): run from config/schema/3.0/ so the base schema's relative
# `SOURCE data/geothesaurus.sql;` resolves and the geothesaurus seed loads.
cd config/schema/3.0

mysql -u root -p symbdb < db_schema-3.0.sql
for f in patches/db_schema_patch-3.*.sql; do
  echo "Applying $f"
  mysql -u root -p symbdb < "$f"
done
# Custom-feature patches (apply after the 3.x patches). batch-core MUST be first
# (it creates the shared `batch` table that the feature patches FK to); the rest
# may be applied in any order. Each feature is applyable as (batch-core + feature).
# The portal-mysql57-compat patch is applied last and is required on MySQL 5.7 /
# STRICT mode (harmless on MySQL 8).
for f in ../1.0/patches/db_schema_patch-{batch-core,image-batching,batch-ingestion,ai-transcription,quick-entry,portal-mysql57-compat}.sql; do
  echo "Applying $f"
  mysql -u root -p symbdb < "$f"
done
```

Running against the containerized dev database (service `symbiota-db-dev`),
schema mounted at `/source` inside the container:
```bash
# Run these commands from the repo root (the directory containing config/,
# containers/, docs/, etc.). The `< config/schema/...` redirects below are
# resolved by your host shell relative to the current directory, so if you are
# still inside containers/ after `make dev-up` you will get
# "No such file or directory" for every file. cd to the repo root first:
cd "$(git rev-parse --show-toplevel)"   # or: cd /path/to/se-symbiota-worktree

# The base schema's relative include only resolves from its own directory, so
# set the container working directory with -w (E3):
docker exec -i -w /source/3.0 symbiota-db-dev \
  mysql -uroot -ppassword symbiota < config/schema/3.0/db_schema-3.0.sql
for f in config/schema/3.0/patches/db_schema_patch-3.*.sql; do
  docker exec -i -w /source/3.0 symbiota-db-dev mysql -uroot -ppassword symbiota < "$f"
done
# batch-core MUST be applied first (it creates the shared `batch` table the
# feature patches FK to); the remaining feature patches may be applied in any
# order. The portal-mysql57-compat patch is required on MySQL 5.7 / STRICT mode
# (harmless on MySQL 8).
for f in config/schema/1.0/patches/db_schema_patch-{batch-core,image-batching,batch-ingestion,ai-transcription,quick-entry,portal-mysql57-compat}.sql; do
  docker exec -i symbiota-db-dev mysql -uroot -ppassword symbiota < "$f"
done
```
Why both `-w /source/3.0` **and** the `< config/schema/...` redirect appear above:
the `-w` flag sets the *container's* working directory so the schema file's internal
`SOURCE data/geothesaurus.sql;` resolves inside the container (E3); the `<` redirect
is resolved by your *host* shell (which is why you must run from the repo root). They
serve two different layers and are both required.

Adjust the database name (`symbdb`/`symbiota`) and credentials to match what you
configured in `dbconnection.php` and your container's `.env`.

> **Caveat (E1) — MySQL 8 vs MariaDB.** These patches were authored and tested on
> **MariaDB** (see the Database requirement above). On the MySQL 8 container that
> this stack ships, patch 3.1 fails: it does `SET FOREIGN_KEY_CHECKS=0;` then
> `ALTER TABLE omoccurrences DROP INDEX Index_collid, ...`, but MySQL 8 still
> refuses to drop an index backing a foreign key even with that flag
> (`Cannot drop index 'Index_collid': needed in a foreign key constraint`), and
> the later patches report knock-on errors. MariaDB allows it. For a from-scratch
> build, use **MariaDB (10.11 works)** as the database engine; otherwise load a
> provided MySQL 8 dump instead of building from scratch (see the note at the top
> of this step and `containers/README.md`).
>
> **How to actually run MariaDB 10.11 for the from-scratch path.** The dev stack's
> `make dev-up` brings up a **MySQL 8** database container (`symbiota-db-dev`),
> which hits the failure above. There is no Makefile target or Compose override
> for MariaDB, so run it by hand. First bring the dev stack up once
> (`make dev-up`) so the app container and its network exist, then **stop the
> stock MySQL 8 container and start a MariaDB 10.11 container in its place**, on
> the same Docker network and ports the app expects:
>
> ```bash
> # Remove the compose-managed MySQL 8 db so the name/port are free.
> docker stop symbiota-db-dev && docker rm symbiota-db-dev
>
> # Start MariaDB 10.11 under the same container name, on the app's network,
> # with the same creds and host port the dev stack uses.
> docker run --name symbiota-db-dev \
>   --network containers_symbiota-network \
>   -e MARIADB_ROOT_PASSWORD=password \
>   -e MARIADB_DATABASE=symbiota \
>   -e MARIADB_USER=symbiota-user \
>   -e MARIADB_PASSWORD=symbiota-pass \
>   -p 33060:3306 \
>   -d mariadb:10.11
> ```
>
> Reusing the name `symbiota-db-dev` means the `docker exec ... symbiota-db-dev`
> import commands above work unchanged, and the web container still resolves the
> DB host `symbiota-db` on `containers_symbiota-network`. (Confirm the network
> name with `docker network ls`; Compose prefixes it with the project dir, so it
> is `containers_symbiota-network` for this `containers/` layout.)
>
> **Important:** this MariaDB container is **not** managed by Compose, so
> `make dev-down` will **not** stop it — stop it explicitly with
> `docker stop symbiota-db-dev`. To return to the stock MySQL 8 container later,
> remove this one (`docker stop symbiota-db-dev && docker rm symbiota-db-dev`)
> and run `make dev-up` again.

> **Caveat (E2) — `schemaversion` is not proof of completeness.** Patches `3.2`,
> `3.3`, and `3.4` `INSERT` their row into `schemaversion` **before** running their
> own `ALTER`/`CREATE` statements. Because the client stops at the first error, such
> a patch can record its version (e.g. `3.4`) while leaving later DDL unapplied.
> Observed: a DB showing version `3.4` whose `mediametadata` table (created near the
> end of `db_schema_patch-3.4.sql`) does not actually exist. Do not treat those
> `schemaversion` rows as confirmation a patch fully applied — verify the expected
> tables exist (e.g. `SHOW TABLES LIKE 'mediametadata';`). (`db_schema_patch-3.1.sql`
> has been corrected to record its version **last**, so a `3.1` row *is* trustworthy;
> the same fix should be applied to 3.2–3.4.)

`NOTE: At this point you should have an operational "out of the box" Symbiota portal.`

### STEP 5: Customize

#### Homepage
Modify index.php. This is your home page or landing page which will need introductory text, graphics, etc.

#### Layout
Layout - Within the /includes directory, the header.php and footer.php files are used by all pages to establish uniform layout.

<!-- Output: tree --prune --matchdirs -P 'header.php|footer.php' -I 'vendor' Symbiota -->
```
Symbiota
└── includes
    ├── footer.php - determines the content of the global page footer and menu navigation.
    └── header.php - determines the content of the global page header
```

#### Css Styles
Files for style control - Within the css/symbiota folder there are two files you can modify to change the appearance of the portal:
<!-- Output: tree --prune --matchdirs -P 'variables.css|customizations.css' -I 'vendor' Symbiota -->
```
Symbiota
└── css
    └── symbiota
        ├── customizations.css - Add css selectors to override Symbiota default styling
        └── variables.css - Set global values used across the portal
```
NOTE: Do not modify any other css files as these files may be overwritten in future updates

#### Customize language tags

Override existing language tags or create new tags by modifying the override files in content/lang/templates/

Example: modify content/lang/templates/header.es.override.php to replace the default values used when browsing the portal in Spanish.

#### Misc configurations and recommendations
Modify usagepolicy.php as needed

Install robots.txt file within root directory - The robots.txt file is a standard method used by websites to indicate to visiting web crawlers and other web robots which portions of the website they are allowed to visit and under what conditions. A robots.txt template can be found within the /includes directory. This file should be moved into the domain's root directory, which may or may not be the Symbiota root directory. The file paths listed within the file should be adjusted to match the portal installation path (e.g., start with $CLIENT_ROOT). See links below for more information:

https://developers.google.com/search/docs/crawling-indexing/robots/create-robots-txt
https://en.wikipedia.org/wiki/Robots.txt

Refer to the [third party authentication instructions](https://github.com/Symbiota/Symbiota/blob/master/docs/third_party_auth_setup.md) for specifics about third party authentication setup.

## DATA

Data - The general layers of data within Symbiota are: user, taxonomic, occurrence (specimen), images, checklist, identification key, and taxon profile (common names, text descriptions, etc).
While user interfaces have been developed for web management for most of these data layers, some table tables still need to be managed via the backend (e.g. loaded by hand).

### User and permissions
A default administrative user has been installed with following login: username = admin; password: admin.

> **Note:** The `admin` / `admin` default above applies **only** to a schema built from scratch via this web Schema Manager path (the from-scratch DDL seeds that account). It does **not** necessarily apply to the containerized dump-load path documented in `containers/README.md` (step 8): a provided DB dump ships its own admin user, and that user's password may differ from `admin`. If you loaded a provided dump and `admin` does not work, check the dump's accompanying documentation or ask the team member who provided it.

It is highly recommended that you change the password, or better yet, create a new admin user, assign admin rights, and then delete default admin user.
A management control panel for User Permissions is available within Data Management Panel on the sitemap page.

### Occurrence (Specimen) Data
SuperAdmins can create new collection instances via the Data Management pane within sitemap. 
Within the collection's data management menu, one can provide admin and edit access to new users, add/edit occurrences, batch load data, etc.

### Taxonomic Thesaurus
Taxon names are stored within the 'taxa' table.
Taxonomic hierarchy and placement definitions are controlled in the 'taxstatus' table.
A recursive data relationship within the 'taxstatus' table defines the taxonomic hierarchy.
While multiple taxonomic thesauri can be defined, one of the thesauri needs to function as the central taxonomic authority.
Names must be added in order from upper taxonomic levels to lower (e.g. kingdom, class, order).
Accepted names must be loaded before non-accepted names.
  1. Names can be added one-by-one using taxonomic management tools (see sitemap.php)
  2. Names can be imported from taxonomic authorities (e.g., Catalog of Life, WoRMS, etc.) based on occurrence data loaded into the system.
     This is the recommended method since it will focus on only relevant taxonomic groups. First, load an occurrence dataset (see step 2 above), 
     then from the Collection Data Management menu, select Data Cleaning Tools => Analyze taxonomic names...
  3. Batch Loader - Multiple names can be loaded from a flat, tab-delimited text file. See instructions on the batch loader for loading multiple names from a flat file.
  4. Look in /config/schema/data/ folder to find taxonomic thesaurus data that may serve as a base for your taxonomic thesaurus.

### Futher Assistance
See <https://symbiota.org> for tutorials and more information on how load and manage data 

## UPDATES

Please read the [UPDATE.md](UPDATE.md) file for instructions on how to update Symbiota.
