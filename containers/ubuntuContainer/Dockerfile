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
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# Copy Apache site configuration
COPY 002-symbiota.conf /etc/apache2/sites-available/002-symbiota.conf

# Enable Symbiota site and disable default
RUN a2dissite 000-default.conf && \
    a2ensite 002-symbiota.conf && \
    a2enmod rewrite

# Set Apache environment variables
ENV APACHE_RUN_DIR=/var/run/apache2 \
    APACHE_LOG_DIR=/var/log/apache2 \
    APACHE_LOCK_DIR=/var/lock/apache2 \
    APACHE_RUN_USER=www-data \
    APACHE_RUN_GROUP=www-data \
    APACHE_PID_FILE=/var/run/apache2/apache2.pid

# Create required directories
RUN mkdir -p $APACHE_RUN_DIR $APACHE_LOCK_DIR $APACHE_LOG_DIR

# Expose HTTP port
EXPOSE 80

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
    CMD curl -f http://localhost/ || exit 1

# Start Apache in foreground (binary is apache2ctl on Ubuntu)
ENTRYPOINT ["/usr/sbin/apache2ctl", "-D", "FOREGROUND"]