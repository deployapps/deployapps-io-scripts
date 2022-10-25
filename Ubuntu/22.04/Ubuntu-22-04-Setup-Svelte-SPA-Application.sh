#!/bin/bash
#Check Root User or Not
if [ "$(id -nu)" != "root" ]; then
  echo -e '\033[31m Run this script as root user, you can switch to root user by running command sudo su \033[0m '
  exit 1
fi
# Configuration BEGIN
export SWAP_MEMORY_SIZE=2G
export NODEJS_VERSION="16.x"
export PRIMARY_DOMAIN="example.org"

# Config END

# Get Input From User
read -e -p "Enter SWAP Memory:" -i "2G" SWAP_MEMORY_SIZE

read -e -p "Enter Domain Name:" -i "$PRIMARY_DOMAIN" PRIMARY_DOMAIN

# Update Repository
apt update -y
export LC_ALL=en_US.UTF-8
export LANG=en_US.UTF-8

# Setup Swap Memory
if [ ! -f /swapfile ]; then
  fallocate -l $SWAP_MEMORY_SIZE /swapfile
  chmod 600 /swapfile
  mkswap /swapfile
  swapon /swapfile
  echo '/swapfile none swap sw 0 0' | tee -a /etc/fstab
  sysctl vm.swappiness=20
  echo 'vm.swappiness=20' | tee -a /etc/sysctl.conf
  sysctl vm.vfs_cache_pressure=40
  echo 'vm.vfs_cache_pressure=40' | tee -a /etc/sysctl.conf
fi
# Install Common Software
apt-get install software-properties-common vim htop tree curl zip unzip git -y

# Install Nginx
apt-get install -y nginx
ufw allow 'Nginx Full'
systemctl restart nginx.service
systemctl enable nginx.service

# Install NodeJS
curl -sL "https://deb.nodesource.com/setup_${NODEJS_VERSION}" | bash -
apt-get install -y nodejs

# Install Certbot
apt-get install -y certbot python3-certbot-nginx
# Project and Application Dir
PROJECT_ROOT_DIR="/var/www/${PRIMARY_DOMAIN}"
APPLICATION_CURRENT_DIRECTORY="${PROJECT_ROOT_DIR}/current"
APPLICATION_WEB_ROOT_DIRECTORY="${APPLICATION_CURRENT_DIRECTORY}/build"
mkdir -p "${PROJECT_ROOT_DIR}"

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

    index index.html;

    charset utf-8;

    location / {
        try_files \$uri \$uri/ \$uri.html /index.html;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    error_page 404 /index.html;

    location ~ /\.(?!well-known).* {
        deny all;
    }
}
EOL
# Restart Services
systemctl restart nginx.service


# Enable Free SSL

echo "To Enable Free SSL you can run following command"
echo "sudo certbot --nginx -d ${PRIMARY_DOMAIN} -d www.${PRIMARY_DOMAIN}"