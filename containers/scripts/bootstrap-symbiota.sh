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
        "3.0/patches/db_schema_patch-3.1.sql"
        "3.0/patches/db_schema_patch-3.2.sql"
        "3.0/patches/db_schema_patch-3.3.sql"
        "3.0/patches/db_schema_patch-3.4.sql"
        "1.0/patches/db_schema_patch-batch-core.sql"
        "1.0/patches/db_schema_patch-image-batching.sql"
        "1.0/patches/db_schema_patch-batch-ingestion.sql"
        "1.0/patches/db_schema_patch-ai-transcription.sql"
        "1.0/patches/db_schema_patch-quick-entry.sql"
        "1.0/patches/db_schema_patch-portal-mysql57-compat.sql"
    )

    for schema_file in "${schema_files[@]}"; do
        local full_path="$schema_dir/$schema_file"
        if [ -f "$full_path" ]; then
            log_info "Loading: $schema_file"
            $DOCKER_CMD exec -i symbiota-mysql-bootstrap mysql -u root -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE" < "$full_path"
        else
            log_warning "Schema file not found: $schema_file"
        fi
    done

    log_success "Database schema loaded"

    # Change default admin password if provided
    if [ -n "$ADMIN_PASSWORD" ]; then
        log_info "Updating admin password..."
        local hashed_password=$(echo -n "$ADMIN_PASSWORD" | md5sum | cut -d' ' -f1)

        $DOCKER_CMD exec symbiota-mysql-bootstrap mysql -u root -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE" <<EOSQL
UPDATE users SET password = '$hashed_password' WHERE username = 'admin';
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

    # Wait briefly for MySQL
    sleep 5

    # Check for key tables
    local table_count=$($DOCKER_CMD exec symbiota-mysql-verify mysql -u root -p"$MYSQL_ROOT_PASSWORD" "$MYSQL_DATABASE" -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = '$MYSQL_DATABASE';" 2>/dev/null || echo "0")

    $COMPOSE_CMD -f "$temp_compose" down >/dev/null 2>&1
    rm -f "$temp_compose"

    if [ "$table_count" -gt 50 ]; then
        log_success "Database schema verified ($table_count tables loaded)"
    else
        log_warning "Database may not be fully initialized (only $table_count tables found)"
    fi
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
