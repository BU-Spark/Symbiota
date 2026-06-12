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

    # Copy config overlay, preserving structure and overwriting existing files
    # Exclude .git directory to reduce noise and improve performance
    # This overlays:
    #   - config/dbconnection.php (database credentials)
    #   - config/symbini.php (main config)
    #   - content/* (site content and skin)
    #   - includes/* (custom headers)
    #   - header.php, footer.php, leftmenu.php, index.php (root customizations)
    rsync -a --exclude='.git' "$CONFIG_OVERLAY_DIR"/ "$SYMBIOTA_DIR/"

    # Ensure proper ownership
    chown -R www-data:www-data "$SYMBIOTA_DIR"

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
# Redirect Apache error log to stdout so podman/docker logs can capture it.
ln -sf /proc/self/fd/1 /var/log/apache2/error.log
ln -sf /proc/self/fd/1 /var/log/apache2/access.log
# Ensure the unprivileged user can write the log targets / run dirs.
chown -h www-data:www-data /var/log/apache2/error.log /var/log/apache2/access.log 2>/dev/null || true
chown -R www-data:www-data /var/run/apache2 /var/lock/apache2 /var/log/apache2 2>/dev/null || true

echo "Starting Apache as the unprivileged www-data user..."
echo "========================================="
echo ""

# All the steps above (config overlay, chown, log symlinks) require root.
# Now drop privileges so the Apache MASTER process does NOT run as root.
# Apache listens on 8080 (a non-privileged port; see ports.conf / 002-symbiota.conf),
# which www-data is allowed to bind. We keep PID 1 by exec-ing setpriv, which
# itself execs apache2ctl, so signal handling / clean shutdown still work.
#
# Prefer setpriv (util-linux, installed in the image); fall back to gosu if
# present; if neither exists, warn and start as root rather than fail to boot.
if command -v setpriv >/dev/null 2>&1; then
    exec setpriv --reuid=www-data --regid=www-data --init-groups apache2ctl -D FOREGROUND
elif command -v gosu >/dev/null 2>&1; then
    exec gosu www-data apache2ctl -D FOREGROUND
else
    echo "WARNING: neither setpriv nor gosu found; starting Apache as root (master will be root)."
    exec apache2ctl -D FOREGROUND
fi
