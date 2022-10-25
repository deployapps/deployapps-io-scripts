#!/bin/bash
#Check Root User or Not
if [ "$(id -nu)" != "root" ]; then
  echo -e '\033[31m Run this script as root user, you can switch to root user by running command sudo su \033[0m '
  exit 1
fi

# Setup LEMP
bash <(curl -Ls https://raw.githubusercontent.com/deployapps/deployapps-io-scripts/main/Ubuntu/22.04/Ubuntu-22-04-Setup-LEMP-Server.sh)

# Install Laravel
export COMPOSER_ALLOW_SUPERUSER=1
PROJECT_ROOT_DIR="/var/www/${PRIMARY_DOMAIN}"
APPLICATION_CURRENT_DIRECTORY="${PROJECT_ROOT_DIR}/current"
APPLICATION_WEB_ROOT_DIRECTORY="${APPLICATION_CURRENT_DIRECTORY}/public"
mkdir -p "${PROJECT_ROOT_DIR}"
composer create-project --prefer-dist --no-dev laravel/laravel "${APPLICATION_CURRENT_DIRECTORY}" 9.x

#Move Storage Folder and Link
mv "${APPLICATION_CURRENT_DIRECTORY}/storage" "${PROJECT_ROOT_DIR}/"
ln -s "${PROJECT_ROOT_DIR}/storage" "${APPLICATION_CURRENT_DIRECTORY}/"
#Move .env Folder and Link
mv "${APPLICATION_CURRENT_DIRECTORY}/.env" "${PROJECT_ROOT_DIR}/"
ln -s "${PROJECT_ROOT_DIR}/.env" "${APPLICATION_CURRENT_DIRECTORY}/"

# Update .env Config
sed -i "s/^\(DB_DATABASE\s*=\s*\).*\$/\1$DB_DATABASE/" "${PROJECT_ROOT_DIR}/.env"
sed -i "s/^\(DB_USERNAME\s*=\s*\).*\$/\1$DB_USERNAME/" "${PROJECT_ROOT_DIR}/.env"
sed -i "s/^\(DB_PASSWORD\s*=\s*\).*\$/\1$DB_PASSWORD/" "${PROJECT_ROOT_DIR}/.env"

CACHE_QUEUE_SESSION_DRIVER="redis"
sed -i "s/^\(CACHE_DRIVER\s*=\s*\).*\$/\1$CACHE_QUEUE_SESSION_DRIVER/" "${PROJECT_ROOT_DIR}/.env"
sed -i "s/^\(QUEUE_CONNECTION\s*=\s*\).*\$/\1$CACHE_QUEUE_SESSION_DRIVER/" "${PROJECT_ROOT_DIR}/.env"
sed -i "s/^\(SESSION_DRIVER\s*=\s*\).*\$/\1$CACHE_QUEUE_SESSION_DRIVER/" "${PROJECT_ROOT_DIR}/.env"

# Change Ownership to www-data
chown -R www-data:www-data "${PROJECT_ROOT_DIR}"

# Create VirtualHost
if [ -f "/etc/nginx/sites-enabled/default" ]; then
  mv /etc/nginx/sites-enabled/default /root/nginx-default-config.bak
fi
cat >"/etc/nginx/conf.d/${PRIMARY_DOMAIN}.conf" <<EOL
server {
    listen 80;
    listen [::]:80;
    server_name ${PRIMARY_DOMAIN};
    root ${APPLICATION_WEB_ROOT_DIRECTORY};

    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";

    index index.php;

    charset utf-8;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    error_page 404 /index.php;

    location ~ \.php$ {
        fastcgi_pass unix:/var/run/php/php8.1-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }
}
EOL
