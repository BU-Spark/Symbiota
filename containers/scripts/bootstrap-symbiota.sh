#!/bin/bash
#
# Symbiota Bootstrap Script
#
# This script sets up a complete Symbiota installation from scratch, including:
# - Directory structure (code, config, data separation)
# - Database initialization with schema
# - Configuration file generation
# - Container environment setup
#
# Usage:
#   ./bootstrap-symbiota.sh [--non-interactive] [--install-dir /path]
#
# The script can be run standalone - it will handle cloning/copying Symbiota code.
#

set -e  # Exit on error
set -o pipefail  # Catch errors in pipes

SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# MySQL image used for bootstrap/verify temp containers.
# MUST match the runtime image (mysqlContainer/Dockerfile, docker-compose.*.yaml)
# so the data dir provisioned here opens cleanly at runtime without an upgrade.
MYSQL_IMAGE="mysql:8.0.42"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Flags
NON_INTERACTIVE=0
VERBOSE=0
TEST_RUN=0
INSTALL_DIR=""
RUNNING_FROM_REPO=0

# Configuration variables (will be populated by prompts)
SITE_NAME=""
SITE_URL=""
MYSQL_ROOT_PASSWORD=""
MYSQL_DATABASE="symbiota"
SYMBIOTA_READ_USER="symbreader"
SYMBIOTA_READ_PASSWORD=""
SYMBIOTA_WRITE_USER="symbwriter"
SYMBIOTA_WRITE_PASSWORD=""
ADMIN_PASSWORD=""
TIMEZONE="America/New_York"
HTTP_PORT=8080
MYSQL_PORT=33060

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --non-interactive)
            NON_INTERACTIVE=1
            shift
            ;;
        --install-dir)
            INSTALL_DIR="$2"
            shift 2
            ;;
        --test-run)
            TEST_RUN=1
            shift
            ;;
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        -h|--help)
            cat <<EOF
Symbiota Bootstrap Script v${SCRIPT_VERSION}

This script creates a complete Symbiota installation with proper separation of:
- Code (upgradeable via git)
- Config (instance-specific, survives upgrades)
- Data (MySQL, images/specimens, logs on separate storage)

Usage: $0 [OPTIONS]

Options:
  --install-dir PATH     Base directory for installation (default: prompt)
  --non-interactive      Run without prompts (use defaults - NOT RECOMMENDED)
  --test-run            After setup, test by starting containers
  -v, --verbose         Show detailed output
  -h, --help            Show this help message

Example:
  $0 --install-dir /opt/symbiota

Directory Structure Created:
  \$INSTALL_DIR/
    code/              Symbiota source code (can be upgraded)
    config/            Instance configuration files
    data/
      mysql/           Database storage
      content/         Images and specimen data
      logs/            Application logs

After installation:
  cd \$INSTALL_DIR/code/containers
  make dev-up

EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo ""
    echo -e "${BOLD}${CYAN}==>${NC}${BOLD} $1${NC}"
}

log_coffee() {
    echo -e "${CYAN}☕${NC} $1"
}

# Prompt function (respects non-interactive mode)
prompt() {
    local prompt_text="$1"
    local default_value="$2"
    local result

    if [ "$NON_INTERACTIVE" -eq 1 ]; then
        echo "$default_value"
        return
    fi

    if [ -n "$default_value" ]; then
        read -r -p "$(echo -e ${BOLD}${prompt_text}${NC}) [${default_value}]: " result
        echo "${result:-$default_value}"
    else
        read -r -p "$(echo -e ${BOLD}${prompt_text}${NC}): " result
        echo "$result"
    fi
}

prompt_password() {
    local prompt_text="$1"
    local default_value="$2"
    local result

    if [ "$NON_INTERACTIVE" -eq 1 ]; then
        echo "$default_value"
        return
    fi

    if [ -n "$default_value" ]; then
        read -r -s -p "$(echo -e ${BOLD}${prompt_text}${NC}) [${default_value}]: " result
        echo ""
        echo "${result:-$default_value}"
    else
        read -r -s -p "$(echo -e ${BOLD}${prompt_text}${NC}): " result
        echo ""
        echo "$result"
    fi
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Generate a random secret using openssl. Hard-fails if openssl is missing
# rather than silently falling back to a weak literal default password.
gen_secret() {
    if ! command_exists openssl; then
        log_error "openssl is required to generate secure database passwords but was not found."
        echo "Install openssl and re-run, or supply passwords interactively (do NOT use weak defaults)." >&2
        exit 1
    fi
    openssl rand -base64 12
}

# Check if we need sudo for docker
need_sudo_for_docker() {
    if ! docker ps >/dev/null 2>&1; then
        if sudo docker ps >/dev/null 2>&1; then
            return 0  # Need sudo
        fi
    fi
    return 1  # Don't need sudo
}

# Step 0: Prerequisites check
check_prerequisites() {
    log_step "Step 0: Checking prerequisites"

    local missing_deps=0

    # Check for Docker or Podman
    if command_exists docker; then
        CONTAINER_RUNTIME="docker"
        log_success "Docker found"

        # Check if we need sudo
        if need_sudo_for_docker; then
            log_warning "Docker requires sudo. You may be prompted for your password."
            DOCKER_CMD="sudo docker"
            COMPOSE_CMD="sudo docker-compose"
        else
            DOCKER_CMD="docker"
            COMPOSE_CMD="docker-compose"
        fi
    elif command_exists podman; then
        CONTAINER_RUNTIME="podman"
        DOCKER_CMD="podman"
        COMPOSE_CMD="podman-compose"
        log_success "Podman found"
    else
        log_error "Neither Docker nor Podman found"
        echo ""
        echo "Please install Docker first:"
        echo "  Ubuntu/Debian: sudo apt-get install docker.io docker-compose"
        echo "  Fedora/RHEL:   sudo dnf install docker docker-compose"
        echo "  macOS:         Download Docker Desktop from docker.com"
        echo ""
        echo "Then run this script again."
        missing_deps=1
    fi

    # Check for docker-compose or podman-compose
    if [ "$CONTAINER_RUNTIME" = "docker" ]; then
        if ! command_exists docker-compose && ! $DOCKER_CMD compose version >/dev/null 2>&1; then
            log_error "docker-compose not found"
            echo "Please install docker-compose and run this script again."
            missing_deps=1
        else
            # Prefer 'docker compose' over 'docker-compose'
            if $DOCKER_CMD compose version >/dev/null 2>&1; then
                COMPOSE_CMD="$DOCKER_CMD compose"
            fi
            log_success "docker-compose found"
        fi
    elif [ "$CONTAINER_RUNTIME" = "podman" ]; then
        if ! command_exists podman-compose; then
            log_error "podman-compose not found"
            echo "Please install podman-compose and run this script again."
            missing_deps=1
        else
            log_success "podman-compose found"
        fi
    fi

    # Check for git
    if ! command_exists git; then
        log_error "git not found"
        echo "Please install git and run this script again."
        missing_deps=1
    else
        log_success "git found"
    fi

    # Check for mysql client (for schema loading)
    if ! command_exists mysql; then
        log_warning "mysql client not found - will use docker exec instead"
    else
        log_success "mysql client found"
    fi

    # Detect OS for SELinux
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
            fedora|rhel|centos|almalinux|rocky)
                SELINUX_DETECTED=1
                SELINUX_FLAG=":z"
                log_info "SELinux-based system detected: $PRETTY_NAME"
                ;;
            *)
                SELINUX_DETECTED=0
                SELINUX_FLAG=""
                log_info "System detected: $PRETTY_NAME"
                ;;
        esac
    fi

    if [ $missing_deps -eq 1 ]; then
        echo ""
        log_error "Missing required dependencies. Please install them and run this script again."
        exit 1
    fi

    log_success "All prerequisites satisfied"
}

# Step 1: Determine installation directory
determine_install_dir() {
    log_step "Step 1: Determine installation directory"

    # Check if we're running from within a Symbiota repo
    if [ -f "$SCRIPT_DIR/../../config/symbini_template.php" ]; then
        RUNNING_FROM_REPO=1
        log_info "Detected: Running from within Symbiota repository"
    fi

    if [ -z "$INSTALL_DIR" ]; then
        echo ""
        echo "Where would you like to install Symbiota?"
        echo "This will create subdirectories: code/, config/, data/"
        echo ""
        INSTALL_DIR=$(prompt "Installation directory" "/opt/symbiota")
    fi

    # Expand ~ if present
    INSTALL_DIR="${INSTALL_DIR/#\~/$HOME}"

    # Create absolute path
    INSTALL_DIR=$(realpath -m "$INSTALL_DIR")

    log_info "Installation directory: $INSTALL_DIR"

    # Check if directory exists and has content
    if [ -d "$INSTALL_DIR" ] && [ "$(ls -A "$INSTALL_DIR" 2>/dev/null)" ]; then
        log_warning "Directory $INSTALL_DIR already exists and is not empty"
        if [ "$NON_INTERACTIVE" -eq 0 ]; then
            read -r -p "Continue anyway? [y/N]: " response
            if [[ ! "$response" =~ ^[Yy]$ ]]; then
                log_error "Installation cancelled"
                exit 1
            fi
        fi
    fi

    # Define subdirectories
    CODE_DIR="$INSTALL_DIR/code"
    CONFIG_DIR="$INSTALL_DIR/config"
    DATA_DIR="$INSTALL_DIR/data"
    MYSQL_DATA_DIR="$DATA_DIR/mysql"
    CONTENT_DIR="$DATA_DIR/content"
    LOGS_DIR="$DATA_DIR/logs"
    CONTAINERS_DIR="$CODE_DIR/containers"

    log_success "Installation paths configured"
}

# Step 2: Create directory structure
create_directory_structure() {
    log_step "Step 2: Creating directory structure"

    mkdir -p "$CODE_DIR"
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$MYSQL_DATA_DIR"
    mkdir -p "$CONTENT_DIR"
    mkdir -p "$LOGS_DIR"

    log_success "Created: $CODE_DIR"
    log_success "Created: $CONFIG_DIR"
    log_success "Created: $DATA_DIR/mysql"
    log_success "Created: $DATA_DIR/content"
    log_success "Created: $DATA_DIR/logs"
}

# Step 3: Get Symbiota code
get_symbiota_code() {
    log_step "Step 3: Getting Symbiota code"

    if [ "$RUNNING_FROM_REPO" -eq 1 ]; then
        log_info "Copying Symbiota code from current repository..."
        REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

        # Use rsync if available, otherwise cp.
        # Both paths exclude .git so the (potentially huge) VCS history is not
        # copied into the deployed code tree.
        if command_exists rsync; then
            rsync -a --exclude='.git' "$REPO_ROOT/" "$CODE_DIR/"
        else
            # cp has no native exclude: copy everything except .git via a glob,
            # then prune any nested .git directories that slipped through.
            cp -r "$REPO_ROOT/." "$CODE_DIR/"
            find "$CODE_DIR" -name '.git' -maxdepth 2 -exec rm -rf {} + 2>/dev/null || true
        fi

        log_success "Copied Symbiota code to $CODE_DIR"
    else
        log_info "Cloning Symbiota repository..."
        log_coffee "This may take a minute - good time for coffee!"

        # Clone the main Symbiota repo
        git clone https://github.com/Symbiota/Symbiota.git "$CODE_DIR"

        log_success "Cloned Symbiota code to $CODE_DIR"
    fi
}

# Step 4: Collect configuration
collect_configuration() {
    log_step "Step 4: Collecting configuration"

    echo ""
    echo "Let's configure your Symbiota instance..."
    echo ""

    # Site configuration
    SITE_NAME=$(prompt "Site name" "My Symbiota Portal")
    SITE_URL=$(prompt "Site URL (without trailing slash)" "http://localhost:${HTTP_PORT:-8080}")

    # Timezone
    echo ""
    echo "Common timezones: America/New_York, America/Chicago, America/Denver,"
    echo "                  America/Los_Angeles, America/Phoenix, UTC"
    TIMEZONE=$(prompt "Timezone" "$TIMEZONE")

    # Port configuration
    echo ""
    HTTP_PORT=$(prompt "HTTP port for web interface" "8080")
    MYSQL_PORT=$(prompt "MySQL port" "33060")

    # Database configuration
    echo ""
    log_info "Database configuration:"
    MYSQL_ROOT_PASSWORD=$(prompt_password "MySQL root password" "$(gen_secret)")
    MYSQL_DATABASE=$(prompt "MySQL database name" "symbiota")

    SYMBIOTA_READ_USER=$(prompt "Read-only database user" "symbreader")
    SYMBIOTA_READ_PASSWORD=$(prompt_password "Read-only user password" "$(gen_secret)")

    SYMBIOTA_WRITE_USER=$(prompt "Read-write database user" "symbwriter")
    SYMBIOTA_WRITE_PASSWORD=$(prompt_password "Read-write user password" "$(gen_secret)")

    # Admin password
    echo ""
    log_warning "The default Symbiota admin account is username: admin, password: admin"
    ADMIN_PASSWORD=$(prompt_password "New admin password (leave empty to keep default)" "")
    if [ -z "$ADMIN_PASSWORD" ]; then
        echo ""
        log_warning "############################################################"
        log_warning "# SECURITY RISK: admin/admin will remain the login.        #"
        log_warning "# Anyone who can reach this portal can take it over.        #"
        log_warning "# Set ADMIN_PASSWORD now, or change it IMMEDIATELY after    #"
        log_warning "# first login. DO NOT expose this instance publicly first.  #"
        log_warning "############################################################"
        echo ""
    fi

    log_success "Configuration collected"
}

# Step 5: Copy template files to config directory
copy_template_files() {
    log_step "Step 5: Copying template files"

    # Find all template files and copy them
    cd "$CODE_DIR"

    local template_count=0
    while IFS= read -r -d '' template_file; do
        # Remove _template suffix to get destination name
        local dest_file=$(echo "$template_file" | sed 's/_template//')
        local dest_name=$(basename "$dest_file")

        cp "$template_file" "$CONFIG_DIR/$dest_name"
        template_count=$((template_count + 1))

        if [ "$VERBOSE" -eq 1 ]; then
            log_info "Copied: $dest_name"
        fi
    done < <(find config -maxdepth 1 -name '*_template*' -type f -print0)

    log_success "Copied $template_count template files to $CONFIG_DIR"
}

# Step 6: Update configuration files
update_configuration_files() {
    log_step "Step 6: Updating configuration files"

    # Update symbini.php
    local symbini_file="$CONFIG_DIR/symbini.php"
    if [ -f "$symbini_file" ]; then
        # Update site name
        sed -i "s/\$DEFAULT_TITLE = '.*'/\$DEFAULT_TITLE = '$SITE_NAME'/" "$symbini_file"

        # Update domain/base URL
        sed -i "s#\$DOMAIN = '.*'#\$DOMAIN = '$SITE_URL'#" "$symbini_file"

        # Update timezone
        sed -i "s#\$TIMEZONE = '.*'#\$TIMEZONE = '$TIMEZONE'#" "$symbini_file" || \
        sed -i "s#date_default_timezone_set('.*')#date_default_timezone_set('$TIMEZONE')#" "$symbini_file"

        log_success "Updated symbini.php"
    else
        log_warning "symbini.php not found - skipping"
    fi

    # Update dbconnection.php
    local dbconn_file="$CONFIG_DIR/dbconnection.php"
    if [ -f "$dbconn_file" ]; then
        sed -i "s/\$GLOBALS\['readonly'\] = '.*'/\$GLOBALS['readonly'] = '$SYMBIOTA_READ_USER'/" "$dbconn_file"
        sed -i "s/\$GLOBALS\['username'\] = '.*'/\$GLOBALS['username'] = '$SYMBIOTA_WRITE_USER'/" "$dbconn_file"
        sed -i "s/\$GLOBALS\['password'\] = '.*'/\$GLOBALS['password'] = '$SYMBIOTA_WRITE_PASSWORD'/" "$dbconn_file"
        sed -i "s/\$GLOBALS\['readonlypwd'\] = '.*'/\$GLOBALS['readonlypwd'] = '$SYMBIOTA_READ_PASSWORD'/" "$dbconn_file"
        sed -i "s/\$GLOBALS\['db'\] = '.*'/\$GLOBALS['db'] = '$MYSQL_DATABASE'/" "$dbconn_file"

        # Database host should be symbiota-db (docker container name) or symbiota-db-dev
        sed -i "s/\$GLOBALS\['host'\] = '.*'/\$GLOBALS['host'] = 'symbiota-db-dev'/" "$dbconn_file"

        log_success "Updated dbconnection.php"
    else
        log_warning "dbconnection.php not found - skipping"
    fi
}

# Step 7: Set up file permissions
setup_permissions() {
    log_step "Step 7: Setting up file permissions"

    # Writable directories (relative to CODE_DIR)
    local writable_dirs=(
        "temp"
        "api/storage/framework"
        "api/storage/logs"
    )

    cd "$CODE_DIR"
    for dir in "${writable_dirs[@]}"; do
        if [ -d "$dir" ]; then
            chmod -R 770 "$dir" 2>/dev/null || log_warning "Could not set permissions on $dir"
            if [ "$VERBOSE" -eq 1 ]; then
                log_info "Set permissions: $dir"
            fi
        else
            mkdir -p "$dir"
            chmod -R 770 "$dir"
            if [ "$VERBOSE" -eq 1 ]; then
                log_info "Created and set permissions: $dir"
            fi
        fi
    done

    # Data directories: least-privilege instead of world-writable 777.
    # Content/logs are written by the www-data process (owner/group): 770.
    # MySQL data dir is owned/used only by the mysqld user: 750.
    # chown to the container runtime uids so the tighter modes still grant access
    # (www-data=33 in the app image, mysql=999 in the db image). Only valid under
    # rootful docker, where host uids map 1:1 into the container. Under rootless
    # podman host uid 33 != container www-data (subuid offset), so chowning here is
    # wrong/ineffective — that path relies on the container entrypoint's in-namespace
    # chown instead. Also needs root to chown to another uid; if not, warn (the dirs
    # stay owner-only and non-root Apache/mysqld will be locked out — run as root).
    if [ "$CONTAINER_RUNTIME" = "docker" ]; then
        if [ "$(id -u)" -ne 0 ]; then
            log_warning "Not running as root: cannot chown data dirs to container uids; run bootstrap as root or www-data (33)/mysqld (999) will be locked out."
        fi
        chown -R 33:33 "$CONTENT_DIR" 2>/dev/null || log_warning "Could not chown content directory to www-data (33)"
        chown -R 33:33 "$LOGS_DIR" 2>/dev/null || log_warning "Could not chown logs directory to www-data (33)"
        chown -R 999:999 "$MYSQL_DATA_DIR" 2>/dev/null || log_warning "Could not chown MySQL data directory to mysql (999)"
        # CODE_DIR writable subdirs (temp, api storage) are 770 too — chown to
        # www-data or the container's PHP/API process can't write them (temp files,
        # Laravel storage/framework cache), unlike the old world-writable 777.
        for wd in temp api/storage/framework api/storage/logs; do
            [ -d "$CODE_DIR/$wd" ] && { chown -R 33:33 "$CODE_DIR/$wd" 2>/dev/null || log_warning "Could not chown $wd to www-data (33)"; }
        done
    else
        log_info "Rootless podman: skipping host-side chown (container entrypoint handles ownership in-namespace)."
    fi
    chmod -R 770 "$CONTENT_DIR" 2>/dev/null || log_warning "Could not set permissions on content directory"
    chmod -R 770 "$LOGS_DIR" 2>/dev/null || log_warning "Could not set permissions on logs directory"
    chmod -R 750 "$MYSQL_DATA_DIR" 2>/dev/null || log_warning "Could not set permissions on MySQL data directory"

    log_success "File permissions configured"
}

# Step 8: Create .env file
create_env_file() {
    log_step "Step 8: Creating container environment file"

    local env_file="$CONTAINERS_DIR/.env"

    # Calculate relative paths from containers/ directory
    local rel_project_root=".."
    local rel_config_dir="../../config"
    local rel_content_dir="../../data/content"
    local rel_logs_dir="../../data/logs"
    local rel_mysql_data="../../data/mysql"

    cat > "$env_file" <<EOF
# Symbiota Container Configuration
# Generated by bootstrap-symbiota.sh on $(date)
# Installation directory: $INSTALL_DIR

# ==============================================================================
# PATH CONFIGURATION
# ==============================================================================

# Path to Symbiota code (relative to containers/ directory)
PROJECT_ROOT=$rel_project_root

# Path to Symbiota data directories (relative to containers/ directory)
SYMBIOTA_DATA=$rel_content_dir
CONTENT_DIR=$rel_content_dir
LOGS_DIR=$rel_logs_dir

# Path to instance-specific config files
CONFIG_DIR=$rel_config_dir

# Path to database schema files (for reference)
SCHEMA_SOURCE=$rel_project_root/config/schema

# ==============================================================================
# MYSQL CONFIGURATION
# ==============================================================================

MYSQL_ROOT_PASSWORD=$MYSQL_ROOT_PASSWORD
MYSQL_DATABASE=$MYSQL_DATABASE
MYSQL_USER=$SYMBIOTA_WRITE_USER
MYSQL_PASSWORD=$SYMBIOTA_WRITE_PASSWORD

# Additional database users
SYMBIOTA_READ_USER=$SYMBIOTA_READ_USER
SYMBIOTA_READ_PASSWORD=$SYMBIOTA_READ_PASSWORD
SYMBIOTA_WRITE_USER=$SYMBIOTA_WRITE_USER
SYMBIOTA_WRITE_PASSWORD=$SYMBIOTA_WRITE_PASSWORD

# MySQL data directory (relative to containers/ directory)
MYSQL_DATA_DIR=$rel_mysql_data

# ==============================================================================
# PORT CONFIGURATION
# ==============================================================================

HTTP_PORT=$HTTP_PORT
MYSQL_PORT=$MYSQL_PORT

# ==============================================================================
# COMPOSE CONFIGURATION
# ==============================================================================

# Which compose file to use
COMPOSE_FILE=docker-compose.dev.yaml

# Container runtime
COMPOSE=$COMPOSE_CMD

# SELinux volume flags (for Fedora/RHEL/CentOS/Alma Linux)
SELINUX_FLAG=$SELINUX_FLAG

# ==============================================================================
# APPLICATION CONFIGURATION
# ==============================================================================

# Timezone
TIMEZONE=$TIMEZONE

# Site configuration
SITE_NAME=$SITE_NAME
SITE_URL=$SITE_URL

EOF

    chmod 600 "$env_file"
    log_success "Created .env file with complete configuration"
}

# Step 9: Initialize database with temporary container
initialize_database() {
    log_step "Step 9: Initializing database"

    log_coffee "Pulling MySQL image and creating database - grab a coffee, this takes a few minutes!"

    # Create a temporary docker-compose file for MySQL only
    local temp_compose="$CONTAINERS_DIR/.bootstrap-mysql.yaml"

    cat > "$temp_compose" <<EOF
services:
  mysql-bootstrap:
    image: $MYSQL_IMAGE
    container_name: symbiota-mysql-bootstrap
    environment:
      MYSQL_ROOT_PASSWORD: $MYSQL_ROOT_PASSWORD
      MYSQL_DATABASE: $MYSQL_DATABASE
    ports:
      - "33066:3306"
    volumes:
      - $MYSQL_DATA_DIR:/var/lib/mysql${SELINUX_FLAG}
      - $CODE_DIR/config/schema:/schema${SELINUX_FLAG}
    command: --sql_mode=""
EOF

    log_info "Starting temporary MySQL container..."
    cd "$CONTAINERS_DIR"
    $COMPOSE_CMD -f "$temp_compose" up -d

    # Wait for MySQL to be ready
    log_info "Waiting for MySQL to be ready..."
    local max_attempts=60
    local attempt=0

    while [ $attempt -lt $max_attempts ]; do
        if $DOCKER_CMD exec symbiota-mysql-bootstrap mysqladmin ping -h localhost -p"$MYSQL_ROOT_PASSWORD" --silent 2>/dev/null; then
            log_success "MySQL is ready"
            break
        fi
        attempt=$((attempt + 1))
        sleep 2
        echo -n "."
    done
    echo ""

    if [ $attempt -eq $max_attempts ]; then
        log_error "MySQL failed to start in time"
        $COMPOSE_CMD -f "$temp_compose" down
        rm -f "$temp_compose"
        exit 1
    fi

    # Create database users
    log_info "Creating database users..."

    $DOCKER_CMD exec symbiota-mysql-bootstrap mysql -u root -p"$MYSQL_ROOT_PASSWORD" <<EOSQL
CREATE USER IF NOT EXISTS '$SYMBIOTA_READ_USER'@'%' IDENTIFIED BY '$SYMBIOTA_READ_PASSWORD';
CREATE USER IF NOT EXISTS '$SYMBIOTA_WRITE_USER'@'%' IDENTIFIED BY '$SYMBIOTA_WRITE_PASSWORD';

GRANT SELECT, EXECUTE ON \`$MYSQL_DATABASE\`.* TO '$SYMBIOTA_READ_USER'@'%';
GRANT SELECT, INSERT, UPDATE, DELETE, EXECUTE ON \`$MYSQL_DATABASE\`.* TO '$SYMBIOTA_WRITE_USER'@'%';

FLUSH PRIVILEGES;
EOSQL

    log_success "Database users created"

    # Load schema files
    log_info "Loading database schema..."
    log_coffee "Loading schema files - another coffee break!"

    local schema_dir="$CODE_DIR/config/schema"
    # Apply in strict order: base schema, then core version patches, then the
    # feature patches. Each file is guarded by an `if [ -f ]` check below so a
    # missing file (e.g. patches still being authored on a parallel track)
    # warns instead of aborting the bootstrap.
    local schema_files=(
        "3.0/db_schema-3.0.sql"
        # db_schema-3.0.sql SOURCEs data/geothesaurus.sql itself, so that one must
        # NOT be listed here -- loading it twice is a duplicate-key error. The
        # bugfix companion is different: nothing sources it, so it needs its own
        # entry, and it must come straight after the base data it corrects.
        "3.0/data/geothesaurus_bugfix.sql"
        "3.0/patches/db_schema_patch-3.1.sql"
        "3.0/patches/db_schema_patch-3.2.sql"
        "3.0/patches/db_schema_patch-3.3.sql"
        "3.0/patches/db_schema_patch-3.4.sql"
        # MUST precede the feature patches below. schemaversion.versionnumber is
        # varchar(20), and three of those patches record names longer than that,
        # which INSERT IGNORE silently truncates. Widening first is what makes
        # their names record correctly; run it after them and they truncate again.
        "1.0/patches/db_schema_patch-schemaversion-width.sql"
        "1.0/patches/db_schema_patch-batch-core.sql"
        "1.0/patches/db_schema_patch-image-batching.sql"
        "1.0/patches/db_schema_patch-batch-ingestion.sql"
        "1.0/patches/db_schema_patch-ai-transcription.sql"
        "1.0/patches/db_schema_patch-quick-entry.sql"
        "1.0/patches/db_schema_patch-portal-mysql57-compat.sql"
    )

    # Upstream patches 3.1 and 3.2 deliberately contain statements that fail on a
    # database built from db_schema-3.0.sql. Their own comments say so:
    #   "Skip if 3.0 install: Table does not exist within db_schema-3.0, thus
    #    statement is expected to fail if this was not originally a 1.0 install"
    # They rename 1.0-era tables that a 3.0 install never had. There are exactly
    # three, all `ALTER TABLE ... RENAME TO`, all reported as ERROR 1146.
    #
    # These two files MUST be loaded with `--force`. Without it the mysql client
    # stops at the first error and silently discards the rest of the file -- and
    # in patch 3.2 the declared-optional statement is at line 276 of ~700, so
    # everything after it is lost, including `CREATE TABLE uploadkeyvaluetemp` at
    # line 629 which patch 3.3 then depends on. (Found exactly that way: 3.3
    # failed with "Table 'uploadkeyvaluetemp' doesn't exist".)
    #
    # `--force` alone would be unsafe, because it ignores EVERY error and turns a
    # genuine migration failure into a silent half-migration. So the two are
    # combined: --force to guarantee the whole file executes, then the collected
    # stderr is compared against this exact allowlist, and ANY error not on it
    # aborts the bootstrap. Only these three table names, only as ERROR 1146,
    # only in these two files.
    local expected_missing_tables="omoccurresource taxaprofilepubimagelink imageprojectlink"

    # Returns 0 only if every error line in $1 is an ERROR 1146 for a table on
    # the allowlist above.
    only_expected_1146_errors() {
        local errfile="$1" line tbl
        # No error lines at all -> nothing to forgive.
        grep -q '^ERROR ' "$errfile" || return 0
        while IFS= read -r line; do
            case "$line" in
                *"ERROR 1146"*) ;;
                *) return 1 ;;   # any other error is real
            esac
            # Extract the table name from "Table 'db.name' doesn't exist"
            tbl=$(printf '%s\n' "$line" | sed -n "s/.*Table '[^.]*\.\([^']*\)' doesn't exist.*/\1/p")
            [ -n "$tbl" ] || return 1
            case " $expected_missing_tables " in
                *" $tbl "*) ;;
                *) return 1 ;;
            esac
        done < <(grep '^ERROR ' "$errfile")
        return 0
    }

    for schema_file in "${schema_files[@]}"; do
        local full_path="$schema_dir/$schema_file"
        if [ -f "$full_path" ]; then
            log_info "Loading: $schema_file"
            # MySQL 8 refuses DROP INDEX on any index that backs a FK constraint
            # even when FOREIGN_KEY_CHECKS=0 (MariaDB and MySQL 5.7 allow it).
            # Patch 3.1 renames the three FK-backed indexes on omoccurrences, so
            # we drop those FKs first, load the patch (which re-adds equivalent
            # named indexes), then restore the FK constraints referencing the new
            # index names.  This block is a no-op on MariaDB/MySQL 5.7.
            # ponytail: targeted shim for known patch; remove if patch 3.1 is rewritten to handle this itself.
            if [ "$schema_file" = "3.0/patches/db_schema_patch-3.1.sql" ]; then
                log_info "Applying MySQL 8 FK compatibility shim for patch 3.1..."
                $DOCKER_CMD exec symbiota-mysql-bootstrap mysql -u root -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE" <<'EOSQL'
ALTER TABLE `omoccurrences`
  DROP FOREIGN KEY `FK_omoccurrences_collid`,
  DROP FOREIGN KEY `FK_omoccurrences_tid`,
  DROP FOREIGN KEY `FK_omoccurrences_uid`;
EOSQL
            fi
            # The base schema uses `SOURCE data/geothesaurus.sql`, which the mysql
            # client resolves relative to ITS OWN working directory, not the
            # script's location. Run it from the file's directory so that line
            # works. Without this the reference data silently never loads --
            # geographicthesaurus ends up empty and every geography lookup in the
            # portal comes back blank.
            # $CODE_DIR/config/schema is bind-mounted at /schema in the temp
            # container (see the compose file above), so the client's cwd can be
            # set to the file's own directory inside the container.
            local err_log
            err_log=$(mktemp)
            local load_rc=0

            # Upstream declares swap_wkt_coords with no routine characteristic.
            # MySQL refuses to create it when binary logging is on (ERROR 1418),
            # which is the default for MySQL 8, and the failure cascades: a later
            # UPDATE in the same file calls the function (ERROR 1305).
            #
            # The body only inspects and rebuilds its argument string -- no SQL,
            # same output for the same input -- so DETERMINISTIC and NO SQL are
            # both accurate. Injected with sed at load time, immediately after the
            # RETURNS clause, so upstream's function body is used byte-for-byte
            # and this file stays identical to upstream on disk. Editing the patch
            # in-tree would add divergence to carry through every future merge, and
            # transcribing the body by hand would risk changing its behaviour.
            #
            # The alternative -- log_bin_trust_function_creators=1 -- is what
            # MySQL's own error text suggests, but it weakens binlog safety for
            # every routine in the instance to fix one function. Declaring the
            # characteristic is the narrower change.
            local sed_fix='s/^\(CREATE FUNCTION `swap_wkt_coords`(str TEXT) RETURNS text\) *$/\1\n  DETERMINISTIC\n  NO SQL/'

            # --force ONLY for the two files with upstream-declared skips, so the
            # whole file still executes; the error allowlist below is what keeps
            # that safe. Every other file aborts on its first error as normal.
            local force_flag=""
            case "$schema_file" in
                3.0/patches/db_schema_patch-3.1.sql|3.0/patches/db_schema_patch-3.2.sql)
                    force_flag="--force" ;;
            esac

            if [ "$schema_file" = "3.0/patches/db_schema_patch-3.2.sql" ]; then
                sed "$sed_fix" "$full_path" \
                    | $DOCKER_CMD exec -i -w "/schema/$(dirname "$schema_file")" \
                        symbiota-mysql-bootstrap \
                        mysql -u root -p"$MYSQL_ROOT_PASSWORD" $force_flag "$MYSQL_DATABASE" \
                        2> "$err_log" || load_rc=$?
            else
                $DOCKER_CMD exec -i -w "/schema/$(dirname "$schema_file")" \
                    symbiota-mysql-bootstrap \
                    mysql -u root -p"$MYSQL_ROOT_PASSWORD" $force_flag "$MYSQL_DATABASE" \
                    < "$full_path" 2> "$err_log" || load_rc=$?
            fi

            # With --force, mysql exits 0 even when statements failed, so the
            # allowlist has to be checked on the error output regardless of exit
            # code -- not only when load_rc is non-zero.
            if [ -n "$force_flag" ] && grep -q '^ERROR ' "$err_log"; then
                if only_expected_1146_errors "$err_log"; then
                    log_warning "$schema_file: skipped upstream's declared 1.0-only statements"
                    grep '^ERROR ' "$err_log" | sed 's/^/    /'
                    load_rc=0
                else
                    load_rc=1
                fi
            fi

            if [ "$load_rc" -ne 0 ]; then
                log_error "Failed loading $schema_file:"
                sed 's/^/    /' "$err_log"
                rm -f "$err_log"
                return 1
            fi
            rm -f "$err_log"

            if [ "$schema_file" = "3.0/patches/db_schema_patch-3.1.sql" ]; then
                $DOCKER_CMD exec symbiota-mysql-bootstrap mysql -u root -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE" <<'EOSQL'
ALTER TABLE `omoccurrences`
  ADD CONSTRAINT `FK_omoccurrences_collid` FOREIGN KEY (`collid`) REFERENCES `omcollections` (`CollID`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `FK_omoccurrences_tid` FOREIGN KEY (`tidInterpreted`) REFERENCES `taxa` (`tid`) ON DELETE SET NULL ON UPDATE CASCADE,
  ADD CONSTRAINT `FK_omoccurrences_uid` FOREIGN KEY (`observerUid`) REFERENCES `users` (`uid`);
EOSQL
                log_info "FK constraints restored after patch 3.1"
            fi
        else
            log_warning "Schema file not found: $schema_file"
        fi
    done

    log_success "Database schema loaded"

    # Change default admin password if provided
    if [ -n "$ADMIN_PASSWORD" ]; then
        log_info "Updating admin password..."
        # ProfileManager.php verifies passwords only as bcrypt ($2y$) or the
        # legacy MySQL-PASSWORD format CONCAT('*', UPPER(SHA1(UNHEX(SHA1(...))))).
        # md5 matches neither and locks out the account silently.  Use MySQL's
        # own PASSWORD()-equivalent expression so no shell hashing is needed.
        # Hex-encode the password before embedding it in SQL so that shell
        # special chars ($, backticks) and SQL special chars (', \) in an
        # operator-chosen password cannot mangle the query or abort the run.
        # UNHEX(hex_of_pw) == password bytes, so SHA1 output is identical.
        # od is POSIX; xxd is not.
        _pw_hex=$(printf '%s' "$ADMIN_PASSWORD" | od -A n -t x1 | tr -d ' \n')
        $DOCKER_CMD exec symbiota-mysql-bootstrap mysql -u root -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE" <<EOSQL
UPDATE users SET password = CONCAT('*', UPPER(SHA1(UNHEX(SHA1(UNHEX('$_pw_hex')))))) WHERE username = 'admin';
EOSQL

        log_success "Admin password updated"
    else
        log_warning "Admin password not changed - default is username: admin, password: admin"
        log_warning "CHANGE THIS IMMEDIATELY in production!"
    fi

    # Stop and remove temporary container
    log_info "Cleaning up temporary container..."
    $COMPOSE_CMD -f "$temp_compose" down
    rm -f "$temp_compose"

    log_success "Database initialization complete"
}

# Step 10: Overlay config files onto code
overlay_config_files() {
    log_step "Step 10: Overlaying configuration onto code"

    # Copy config files from config dir to code dir
    cp -r "$CONFIG_DIR"/* "$CODE_DIR/config/"

    log_success "Configuration files overlaid onto code directory"
    log_info "Config location: $CONFIG_DIR"
    log_info "To update config: edit files in $CONFIG_DIR, then re-copy to $CODE_DIR/config/"
}

# Step 11: Verify database schema
verify_database_schema() {
    log_step "Step 11: Verifying database schema"

    # Start a temporary MySQL container to verify
    local temp_compose="$CONTAINERS_DIR/.bootstrap-verify.yaml"

    cat > "$temp_compose" <<EOF
services:
  mysql-verify:
    image: $MYSQL_IMAGE
    container_name: symbiota-mysql-verify
    environment:
      MYSQL_ROOT_PASSWORD: $MYSQL_ROOT_PASSWORD
      MYSQL_DATABASE: $MYSQL_DATABASE
    ports:
      - "33066:3306"
    volumes:
      - $MYSQL_DATA_DIR:/var/lib/mysql${SELINUX_FLAG}
EOF

    cd "$CONTAINERS_DIR"
    $COMPOSE_CMD -f "$temp_compose" up -d >/dev/null 2>&1

    # Tear the verify container and temp compose file down on EVERY exit path, not
    # just the happy one. This function runs under `set -e`, and the assignments
    # below are bare command substitutions -- if the DB is not answering yet, the
    # script dies mid-function and would otherwise leave a running container and a
    # stray .bootstrap-verify.yaml behind, with no diagnostic at all.
    # EXIT as well as RETURN, and this is not belt-and-braces: verified that a
    # RETURN trap does NOT fire when `set -e` aborts the script from inside a
    # function -- only EXIT does. A RETURN-only trap would have been silent in
    # exactly the case it was written for. Disarms itself so it runs once.
    verify_cleanup() {
        trap - EXIT RETURN
        $COMPOSE_CMD -f "$temp_compose" down >/dev/null 2>&1 || true
        rm -f "$temp_compose"
    }
    trap verify_cleanup EXIT RETURN

    # Wait for an AUTHENTICATED query, not a fixed sleep and not `mysqladmin ping`.
    # During the official image's init a temporary server already answers pings while
    # the root password has not been applied yet, so both a sleep and a ping can
    # return before the DB will accept credentials -- and every check below then
    # fails with "Access denied", which looks exactly like a broken schema.
    local ready=0 i
    for i in $(seq 1 60); do
        if $DOCKER_CMD exec symbiota-mysql-verify \
                mysql -u root -p"$MYSQL_ROOT_PASSWORD" -e "SELECT 1" >/dev/null 2>&1; then
            ready=1; break
        fi
        sleep 2
    done
    if [ "$ready" -ne 1 ]; then
        log_error "verify database never accepted a connection; cannot verify the schema"
        return 1
    fi

    # A table count alone is a weak check: it passed at 146 tables while the
    # geography reference data was empty and three feature patches had recorded
    # truncated names. Assert on the things that actually broke.
    vq() {
        $DOCKER_CMD exec symbiota-mysql-verify \
            mysql -u root -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE" -N -B \
            -e "$1" 2>/dev/null
    }

    local table_count geo_rows sv_width missing_tables recorded_versions
    table_count=$(vq "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$MYSQL_DATABASE';") || table_count=""
    : "${table_count:=0}"

    # Tables that must exist: upstream core, plus one per fork feature patch.
    local required="omoccurrences omcollections taxa users media schemaversion geographicthesaurus batch ocr_results"
    missing_tables=""
    for t in $required; do
        if [ "$(vq "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$MYSQL_DATABASE' AND table_name='$t';")" != "1" ]; then
            missing_tables="$missing_tables $t"
        fi
    done

    # Reference data: db_schema-3.0.sql SOURCEs this, and the SOURCE silently
    # no-ops if the client's cwd is wrong. An empty table here means every
    # geography lookup in the portal returns nothing.
    geo_rows=$(vq "SELECT COUNT(*) FROM geographicthesaurus;") || geo_rows=""
    : "${geo_rows:=0}"

    # schemaversion.versionnumber must be wide enough for the fork's descriptive
    # patch names. At varchar(20) three of them are silently truncated by
    # INSERT IGNORE, which permanently breaks "has this patch been applied?".
    sv_width=$(vq "SELECT CHARACTER_MAXIMUM_LENGTH FROM information_schema.columns WHERE table_schema='$MYSQL_DATABASE' AND table_name='schemaversion' AND column_name='versionnumber';") || sv_width=""
    : "${sv_width:=0}"

    # Full, untruncated feature-patch names.
    local required_versions="3.1 3.2 3.3 3.4 batch-core-patch image-batching-patch batch-ingestion-patch ai-transcription-patch quick-entry-patch portal-mysql57-compat-patch"
    local missing_versions=""
    for v in $required_versions; do
        if [ "$(vq "SELECT COUNT(*) FROM schemaversion WHERE versionnumber='$v';")" != "1" ]; then
            missing_versions="$missing_versions $v"
        fi
    done
    recorded_versions=$(vq "SELECT GROUP_CONCAT(versionnumber ORDER BY id) FROM schemaversion;") || recorded_versions=""

    # Teardown is handled by the RETURN trap above.

    local verify_failed=0
    [ "$table_count" -gt 50 ] || { log_error "Only $table_count tables found"; verify_failed=1; }
    [ -z "$missing_tables" ]  || { log_error "Missing required tables:$missing_tables"; verify_failed=1; }
    [ "$geo_rows" -gt 0 ]     || { log_error "geographicthesaurus is empty -- data/geothesaurus.sql did not load"; verify_failed=1; }
    [ "$sv_width" -ge 64 ]    || { log_error "schemaversion.versionnumber is varchar($sv_width); needs >= 64 or patch names truncate"; verify_failed=1; }
    [ -z "$missing_versions" ] || { log_error "Patch versions not recorded (or truncated):$missing_versions"; verify_failed=1; }

    if [ "$verify_failed" -ne 0 ]; then
        log_error "Database verification FAILED"
        log_error "  recorded schemaversion rows: ${recorded_versions:-<none>}"
        return 1
    fi

    log_success "Database schema verified: $table_count tables, $geo_rows geography rows, versionnumber varchar($sv_width)"
    log_success "All required patch versions recorded at full length"
}

# Step 12: Print final instructions
print_final_instructions() {
    echo ""
    echo "========================================================================"
    echo -e "  ${GREEN}${BOLD}Symbiota Installation Complete!${NC}"
    echo "========================================================================"
    echo ""
    log_success "Your Symbiota instance is ready to run"
    echo ""
    echo "Installation Summary:"
    echo "  Base directory:  $INSTALL_DIR"
    echo "  Code:            $CODE_DIR"
    echo "  Config:          $CONFIG_DIR"
    echo "  Data:            $DATA_DIR"
    echo ""
    echo "Database Configuration:"
    echo "  Database:        $MYSQL_DATABASE"
    echo "  Read user:       $SYMBIOTA_READ_USER"
    echo "  Write user:      $SYMBIOTA_WRITE_USER"
    echo "  Root password:   [saved in .env]"
    echo ""
    echo "Next Steps:"
    echo ""
    echo "1. Start your Symbiota instance:"
    echo "   cd $CONTAINERS_DIR"
    echo "   make dev-up"
    echo ""
    echo "2. Access your site:"
    echo "   URL: $SITE_URL"
    echo "   Admin user: admin"
    if [ -n "$ADMIN_PASSWORD" ]; then
        echo "   Admin pass: [the password you set]"
    else
        echo "   Admin pass: admin (CHANGE THIS!)"
    fi
    echo ""
    echo "3. View logs:"
    echo "   make logs"
    echo ""
    echo "4. Stop containers:"
    echo "   make dev-down"
    echo ""
    echo "Configuration Management:"
    echo "  - Edit config files in: $CONFIG_DIR"
    echo "  - After editing, copy to code: cp -r $CONFIG_DIR/* $CODE_DIR/config/"
    echo "  - Or use the overlay approach in your workflow"
    echo ""
    echo "Upgrade Workflow:"
    echo "  1. cd $CODE_DIR && git pull"
    echo "  2. Review and apply any new schema patches"
    echo "  3. Copy your config back: cp -r $CONFIG_DIR/* $CODE_DIR/config/"
    echo "  4. Restart containers: cd $CONTAINERS_DIR && make dev-down && make dev-up"
    echo ""
    echo "========================================================================"
    echo ""
}

# Optional: Test run
test_run() {
    if [ "$TEST_RUN" -eq 1 ]; then
        log_step "Test: Starting containers"

        cd "$CONTAINERS_DIR"
        make dev-up

        log_info "Waiting for services to start..."
        sleep 10

        log_info "Testing web interface..."
        if curl -f -s "http://localhost:$HTTP_PORT" >/dev/null; then
            log_success "Web interface is responding"
        else
            log_warning "Web interface not responding (may need more time)"
        fi

        log_info "Stopping containers..."
        make dev-down

        log_success "Test run complete"
    fi
}

# Main execution
main() {
    echo ""
    echo "========================================================================"
    echo "  Symbiota Bootstrap Script v${SCRIPT_VERSION}"
    echo "========================================================================"
    echo ""
    echo "This script will set up a complete Symbiota installation with:"
    echo "  - Proper code/config/data separation"
    echo "  - Initialized database with schema"
    echo "  - Container environment ready to run"
    echo ""

    check_prerequisites

    determine_install_dir
    create_directory_structure
    get_symbiota_code
    collect_configuration
    copy_template_files
    update_configuration_files
    setup_permissions
    create_env_file
    initialize_database
    overlay_config_files
    verify_database_schema
    test_run
    print_final_instructions
}

# Run main function
main
