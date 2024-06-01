#!/bin/bash -e


# functions
function error() {
    echo -e "\e[91m[ERROR] $1\e[39m"
}
function warn() {
    echo -e "\e[93m[WARNING] $1\e[39m"
}
function info() {
    echo -e "\e[36m[INFO] $1\e[39m"
}
function cleanup() {
    popd >/dev/null
    rm -rf $TEMP_FOLDER_PATH
}


TEMP_FOLDER_PATH=$(mktemp -d)
pushd $TEMP_FOLDER_PATH >/dev/null

echo '>>>> V2.6 <<<<<'

# prompts/args
DEFAULT_HOSTNAME='photos-1'
DEFAULT_PASSWORD='photosadmin'
DEFAULT_IPV4_CIDR='192.168.0.24/24'
DEFAULT_IPV4_GW='192.168.0.1'
DEFAULT_CONTAINER_ID=$(pvesh get /cluster/nextid)
read -p "Enter a hostname (${DEFAULT_HOSTNAME}) : " HOSTNAME
read -s -p "Enter a password (${DEFAULT_PASSWORD}) : " HOSTPASS
echo -e "\n"
read -p "Enter an IPv4 CIDR (${DEFAULT_IPV4_CIDR}) : " HOST_IP4_CIDR
read -p "Enter an IPv4 Gateway (${DEFAULT_IPV4_GW}) : " HOST_IP4_GATEWAY
read -p "Enter a container ID (${DEFAULT_CONTAINER_ID}) : " CONTAINER_ID
info "Using ContainerID: ${CONTAINER_ID}"
HOSTNAME="${HOSTNAME:-${DEFAULT_HOSTNAME}}"
HOSTPASS="${HOSTPASS:-${DEFAULT_PASSWORD}}"
HOST_IP4_CIDR="${HOST_IP4_CIDR:-${DEFAULT_IPV4_CIDR}}"
HOST_IP4_GATEWAY="${HOST_IP4_GATEWAY:-${DEFAULT_IPV4_GW}}"
export HOST_IP4_CIDR=${HOST_IP4_CIDR}
CONTAINER_OS_TYPE='ubuntu'
CONTAINER_OS_VERSION='20.04'  # higher are currently unsupported
CONTAINER_OS_STRING="${CONTAINER_OS_TYPE}-${CONTAINER_OS_VERSION}"
info "Using OS: ${CONTAINER_OS_STRING}"
CONTAINER_ARCH=$(dpkg --print-architecture)
TEMPLATE_STRING=$(pveam list cfs-ssd | grep $CONTAINER_OS_STRING | awk '{print $1}')
info "Using template: ${TEMPLATE_STRING}"


# storage location
STORAGE_LIST=( $(pvesm status -content rootdir | awk 'NR>1 {print $1}') )
if [ ${#STORAGE_LIST[@]} -eq 0 ]; then
    warn "'Container' needs to be selected for at least one storage location."
    die "Unable to detect valid storage location."
elif [ ${#STORAGE_LIST[@]} -eq 1 ]; then
    STORAGE=${STORAGE_LIST[0]}
else
    info "More than one storage locations detected."
    PS3=$"Which storage location would you like to use? "
    select storage_item in "${STORAGE_LIST[@]}"; do
        if [[ " ${STORAGE_LIST[*]} " =~ ${storage_item} ]]; then
            STORAGE=$storage_item
            break
        fi
        echo -en "\e[1A\e[K\e[1A"
    done
fi
info "Using '$STORAGE' for storage location."


# Create the container
info "Creating LXC container..."
pct create "${CONTAINER_ID}" "${TEMPLATE_STRING}" \
    -arch "${CONTAINER_ARCH}" \
    -cores 4 \
    -memory 4096 \
    -swap 4096 \
    -onboot 0 \
    -features nesting=1,keyctl=1 \
    -hostname "${HOSTNAME}" \
    -net0 name=eth0,bridge=vmbr0,gw=${HOST_IP4_GATEWAY},ip=${HOST_IP4_CIDR} \
    -ostype "${CONTAINER_OS_TYPE}" \
    -password ${HOSTPASS} \
    -storage "${STORAGE}" \
    --unprivileged 1 \
    || exit 1


# Resize the root volume
info "Resizing the root volume..."
pct resize "${CONTAINER_ID}" rootfs 20G


# Start container
info "Starting LXC container CONTAINER_ID=${CONTAINER_ID}..."
pct start "${CONTAINER_ID}" || exit 1
sleep 5
CONTAINER_STATUS=$(pct status $CONTAINER_ID)
info "Checking comtainer status CONTAINER_ID=${CONTAINER_ID} CONTAINER_STATUS=${CONTAINER_STATUS}"
if [ "${CONTAINER_STATUS}" != "status: running" ]; then
    error "Container ${CONTAINER_ID} is not running! status=${CONTAINER_STATUS}"
    exit 1
fi


# Setup OS
info "Fetching setup script..."
wget -qL https://raw.githubusercontent.com/noofny/proxmox_immich/master/setup_os.sh
info "Executing script..."
cat ./setup_os.sh
pct push "${CONTAINER_ID}" ./setup_os.sh /setup_os.sh -perms 755
pct exec "${CONTAINER_ID}" -- bash -c "/setup_os.sh"
pct reboot "${CONTAINER_ID}"


# Setup Docker
info "Fetching setup script..."
wget -qL https://raw.githubusercontent.com/noofny/proxmox_immich/master/setup_docker.sh
info "Executing script..."
cat ./setup_docker.sh
pct push "${CONTAINER_ID}" ./setup_docker.sh /setup_docker.sh -perms 755
pct exec "${CONTAINER_ID}" -- bash -c "/setup_docker.sh"
pct reboot "${CONTAINER_ID}"


# Setup Immich
info "Fetching setup script..."
wget -qL https://raw.githubusercontent.com/noofny/proxmox_immich/master/setup_immich.sh
wget -qL https://raw.githubusercontent.com/noofny/proxmox_immich/master/docker-compose.yaml
wget -qL https://raw.githubusercontent.com/noofny/proxmox_immich/master/hardware_accelleration.yaml
info "Executing script..."
cat ./setup_immich.sh
pct push "${CONTAINER_ID}" ./setup_immich.sh /setup_immich.sh -perms 755
pct push "${CONTAINER_ID}" ./docker-compose.yaml /docker-compose.yaml
pct push "${CONTAINER_ID}" ./hardware_accelleration.yaml /hardware_accelleration.yaml
pct exec "${CONTAINER_ID}" -- bash -c "/setup_immich.sh"
pct reboot "${CONTAINER_ID}"


# Done - reboot!
rm -rf ${TEMP_FOLDER_PATH}
info "Container and app setup - container will restart!"
pct reboot "${CONTAINER_ID}"
