#!/bin/bash
set -e

# Symbiota Container Entrypoint
# Overlays instance-specific configuration at runtime before starting Apache

echo "========================================="
echo "Symbiota Container Starting"
echo "========================================="

# Configuration overlay directory (mounted from host)
CONFIG_OVERLAY_DIR="/config-overlay"

# Symbiota installation directory
SYMBIOTA_DIR="/var/www/html/symbiota"

# Check if config overlay directory exists and is not empty
if [ -d "$CONFIG_OVERLAY_DIR" ] && [ "$(ls -A $CONFIG_OVERLAY_DIR)" ]; then
    echo "Config overlay found at $CONFIG_OVERLAY_DIR"
    echo "Overlaying configuration onto $SYMBIOTA_DIR..."

    # Copy config overlay, preserving structure and overwriting existing files.
    # This overlays:
    #   - config/dbconnection.php (database credentials)
    #   - config/symbini.php (main config)
    #   - content/* (site content and skin)
    #   - includes/* (custom headers)
    #   - header.php, footer.php, leftmenu.php, index.php (root customizations)
    #
    # The overlay directory is a whole git checkout of the private config repo,
    # not just that payload. Everything it contains lands in the Apache
    # DocumentRoot and is served. Before these excludes, that published:
    #   GET /.env                        -> 200, MYSQL_ROOT_PASSWORD + rw/ro
    #   GET /containers/.env.int         -> 200, same
    #   GET /containers/docker-compose.yaml -> 200
    # on both int and alpha. (Cloudflare Access happened to gate both
    # hostnames, so it was not publicly reachable -- but the credentials were
    # sitting in the web root behind a single control.)
    #
    # `.env` is NOT needed here: it is sourced further down from
    # $CONFIG_OVERLAY_DIR/.env, which compose mounts as its own file. Excluding
    # it from the rsync does not affect environment loading.
    #
    # Deliberately NOT excluding *.sql -- config/schema/**.sql is legitimate
    # overlay payload and Symbiota's schema manager reads it.
    rsync -a \
        --exclude='.git' \
        --exclude='.github' \
        --exclude='.gitignore' \
        --exclude='.env' \
        --exclude='.env.*' \
        --exclude='containers/' \
        --exclude='docker/' \
        --exclude='scripts/' \
        --exclude='*.md' \
        "$CONFIG_OVERLAY_DIR"/ "$SYMBIOTA_DIR/"

    # Avoid recursively chowning bind-mounted runtime data under rootless Podman.
    # Host-mounted data directories should be owned by the service account on the host.
    for path in \
        "$SYMBIOTA_DIR/config" \
        "$SYMBIOTA_DIR/content/lang" \
        "$SYMBIOTA_DIR/includes" \
        "$SYMBIOTA_DIR/header.php" \
        "$SYMBIOTA_DIR/footer.php" \
        "$SYMBIOTA_DIR/index.php" \
        "$SYMBIOTA_DIR/leftmenu.php"
    do
        if [ -e "$path" ]; then
            chown -R www-data:www-data "$path" || true
        fi
    done

    for path in \
        "$SYMBIOTA_DIR/temp" \
        "$SYMBIOTA_DIR/content/imglib" \
        "$SYMBIOTA_DIR/content/logs"
    do
        if [ -e "$path" ] && [ ! -w "$path" ]; then
            echo "WARNING: Runtime data path is not writable by container: $path"
        fi
    done

    echo "Configuration overlay complete"
    echo ""
    echo "Files overlaid:"
    find "$CONFIG_OVERLAY_DIR" -type f ! -path '*/.git/*' | sed "s|$CONFIG_OVERLAY_DIR|  -|"
    echo ""
else
    echo "WARNING: No config overlay found at $CONFIG_OVERLAY_DIR"
    echo "Container will start with default/generic configuration"
    echo "This is expected for development, but NOT for production"
    echo ""
fi

# Verify critical files exist
CRITICAL_FILES=(
    "$SYMBIOTA_DIR/config/dbconnection.php"
    "$SYMBIOTA_DIR/config/symbini.php"
)

echo "Verifying critical files..."
for file in "${CRITICAL_FILES[@]}"; do
    if [ -f "$file" ]; then
        echo "  ✓ $file"
    else
        echo "  ✗ MISSING: $file"
        echo "ERROR: Critical configuration file missing!"
        echo "Cannot start without proper configuration."
        exit 1
    fi
done
echo ""

echo "Loading environment variables..."
# Source .env file if mounted in config overlay
# This allows deployer to place .env anywhere and mount it here
ENV_FILE="$CONFIG_OVERLAY_DIR/.env"
if [ -f "$ENV_FILE" ]; then
    echo "  ✓ Loading environment from $ENV_FILE"
    set -a  # Export all variables
    source "$ENV_FILE"
    set +a
else
    echo "  ℹ No .env file found in config overlay (optional)"
fi
echo ""

echo "Configuring Apache logging to stdout..."
# Redirect Apache error log to stdout so podman logs can capture it
ln -sf /proc/self/fd/1 /var/log/apache2/error.log
ln -sf /proc/self/fd/1 /var/log/apache2/access.log

echo "Starting Apache..."
echo "========================================="
echo ""

# Start Apache in foreground
exec apache2ctl -D FOREGROUND
