#!/bin/bash


# locale
echo "Setting locale..."
LOCALE_VALUE="en_AU.UTF-8"
echo ">>> locale-gen..."
locale-gen ${LOCALE_VALUE}
cat /etc/default/locale
source /etc/default/locale
echo ">>> update-locale..."
update-locale ${LOCALE_VALUE}
echo ">>> hack /etc/ssh/ssh_config..."
sed -e '/SendEnv/ s/^#*/#/' -i /etc/ssh/ssh_config


echo "Creating folders..."
mkdir /mnt/nobackup
mkdir /mnt/photos
mkdir /mnt/images
mkdir -p /home/photosadmin/uploads
mv /docker-compose.yaml /home/photosadmin/docker-compose.yaml
# chmod 777 -R /data


echo "Creating stack..."
cd /data/config
docker-compose up --no-start
echo "Starting stack..."
docker-compose up --detach


echo "Setup Immich complete - you can access the dashboard at http://$(hostname -I)"
