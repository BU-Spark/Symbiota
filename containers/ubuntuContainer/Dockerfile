# Symbiota Web Application Container
#
# This Dockerfile creates a production-ready Symbiota container with:
# - Ubuntu 22.04 base (matches current production deployment)
# - PHP 8.1 + Apache
# - Required PHP extensions
# - Tesseract OCR
# - Multi-architecture support (AMD64 + ARM64)

FROM ubuntu:22.04

# Build arguments for multi-arch support
ARG TARGETPLATFORM
ARG BUILDPLATFORM

# Disable interactive prompts during package installation
ARG DEBIAN_FRONTEND=noninteractive

# Set working directory
WORKDIR /home

# Install Apache, PHP, and system utilities (rsync required for config overlay)
RUN apt-get update && apt-get install -y \
    bash \
    apache2 \
    php \
    libapache2-mod-php \
    git \
    vim \
    unzip \
    curl \
    rsync \
    tesseract-ocr \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Enable required Apache modules
RUN a2enmod php8.1

# Install PHP extensions
RUN apt-get update && apt-get install -y \
    php-mysqli \
    php-gd \
    php-mbstring \
    php-zip \
    php-curl \
    php-exif \
    php-dom \
    util-linux \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copy Apache site configuration
COPY 002-symbiota.conf /etc/apache2/sites-available/002-symbiota.conf

# Enable Symbiota site and disable default. Listen on 8080 (non-privileged)
# so Apache can run as www-data instead of root (see ENTRYPOINT below).
RUN sed -ri 's/^Listen 80$/Listen 8080/' /etc/apache2/ports.conf && \
    a2dissite 000-default.conf && \
    a2ensite 002-symbiota.conf && \
    a2enmod rewrite

# Set Apache environment variables
ENV APACHE_RUN_DIR=/var/run/apache2 \
    APACHE_LOG_DIR=/var/log/apache2 \
    APACHE_LOCK_DIR=/var/lock/apache2 \
    APACHE_RUN_USER=www-data \
    APACHE_RUN_GROUP=www-data \
    APACHE_PID_FILE=/var/run/apache2/apache2.pid

# Create required directories and make them writable by the unprivileged user
RUN mkdir -p $APACHE_RUN_DIR $APACHE_LOCK_DIR $APACHE_LOG_DIR && \
    chown -R www-data:www-data $APACHE_RUN_DIR $APACHE_LOCK_DIR $APACHE_LOG_DIR

# Expose HTTP port (Apache listens on 8080 as the unprivileged www-data user)
EXPOSE 8080

# Optional: Bake instance-specific config into image (production only)
# Build argument to specify config directory
ARG CONFIG_DIR
# If CONFIG_DIR is set, copy config files into image
# Usage: docker build --build-arg CONFIG_DIR=/path/to/config .
RUN if [ -n "$CONFIG_DIR" ] && [ -d "$CONFIG_DIR" ]; then \
        echo "Baking config from $CONFIG_DIR into image..."; \
        cp -r "$CONFIG_DIR"/* /var/www/html/symbiota/; \
    else \
        echo "No config directory specified, skipping config bake-in"; \
    fi

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8080/ || exit 1

# Start Apache in foreground as the unprivileged www-data user.
# setpriv (util-linux) drops privileges while staying PID 1 for signal handling.
# www-data can bind 8080 (non-privileged); the master process is never root.
ENTRYPOINT ["setpriv", "--reuid=www-data", "--regid=www-data", "--init-groups", "/usr/sbin/apache2ctl", "-D", "FOREGROUND"]