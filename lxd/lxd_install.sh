#!/bin/bash
set -eux

# functions
dump_worker_config_file() {
cat > $TRAVIS_WORKER_CONFIG_FILE_PATH<<- EOM
TRAVIS_ENTERPRISE_SECURITY_TOKEN="${TRAVIS_ENTERPRISE_SECURITY_TOKEN}"
TRAVIS_ENTERPRISE_BUILD_ENDPOINT="${TRAVIS_ENTERPRISE_BUILD_ENDPOINT}"
TRAVIS_BUILD_IMAGES="${TRAVIS_BUILD_IMAGES}"
TRAVIS_QUEUE_NAME="${TRAVIS_QUEUE_NAME}"
EOM
}


# consts
TRAVIS_LXD_INSTALL_SCRIPT_IMAGE_URL=https://travis-lxc-images.s3.us-east-2.amazonaws.com
TRAVIS_WORKER_CONFIG_FILE_PATH="/var/snap/travis-worker/common/worker.env"
declare -A TRAVIS_LXD_INSTALL_SCRIPT_IMAGES_MAP=( ["amd64-focal"]="travis-ci-ubuntu-2004-1603734892-1fb6ced8.tar.gz" )



# variables
#TRAVIS_LXD_INSTALL_SCRIPT_TZ="${TRAVIS_LXD_INSTALL_SCRIPT_TZ:-Europe/London}" # set your time zone
TRAVIS_LXD_INSTALL_SCRIPT_ARCH="${TRAVIS_LXD_INSTALL_SCRIPT_ARCH:-amd64}"
TRAVIS_LXD_INSTALL_SCRIPT_DISTRO="${TRAVIS_LXD_INSTALL_SCRIPT_DISTRO:-focal}"
TRAVIS_LXD_INSTALL_SCRIPT_IMAGE="${TRAVIS_LXD_INSTALL_SCRIPT_IMAGE:-travis-ci-ubuntu-2004-1603734892-1fb6ced8.tar.gz}"
TRAVIS_LXD_INSTALL_SCRIPT_IMAGE_DIR="${TRAVIS_LXD_INSTALL_SCRIPT_IMAGE_DIR:-.}"

# reading from script's arguments
while [ $# -gt 0 ]; do
  case "$1" in
    --travis_enterprise_security_token=*)
      TRAVIS_ENTERPRISE_SECURITY_TOKEN="${1#*=}"
      ;;
    --travis_enterprise_build_endpoint=*)
      TRAVIS_ENTERPRISE_BUILD_ENDPOINT="${1#*=}"
      ;;
    --travis_queue_name=*)
      TRAVIS_QUEUE_NAME="${1#*=}"
      ;;
    --travis_build_images=*)
      TRAVIS_BUILD_IMAGES="${1#*=}"
      ;;
    --travis_enterprise_host=*)
      TRAVIS_ENTERPRISE_HOST="${1#*=}"
  esac
  shift
done


# travis-worker config
#TRAVIS_ENTERPRISE_SECURITY_TOKEN="H3Tve2EbLECL2u3VQ_9qkSE5OhTD8fsSBaxD6Fne1SHcxha93E2_gwsBe7W7yc_1"
TRAVIS_ENTERPRISE_HOST="${TRAVIS_ENTERPRISE_HOST}" # ext-dev.travis-ci-enterprise.com
TRAVIS_ENTERPRISE_BUILD_ENDPOINT="${TRAVIS_ENTERPRISE_BUILD_ENDPOINT:-__build__}"
TRAVIS_QUEUE_NAME="${TRAVIS_QUEUE_NAME:-builds.bionic}"
TRAVIS_BUILD_IMAGES="${TRAVIS_BUILD_IMAGES:-focal}"


TRAVIS_WORKER_HARD_TIMEOUT="90m"
TRAVIS_WORKER_DOCKER_PRIVILEGED="true"
TRAVIS_WORKER_DOCKER_CPUS=4



if [[ ! -v TRAVIS_ENTERPRISE_SECURITY_TOKEN ]]; then
 echo 'please set travis_enterprise_security_token'
 exit 1
fi

if [[ ! -v TRAVIS_ENTERPRISE_HOST ]]; then
 echo 'please set travis_enterprise_host'
 exit 1
fi

#ln -snf /usr/share/zoneinfo/$TRAVIS_LXD_INSTALL_SCRIPT_TZ /etc/localtime && echo $TRAVIS_LXD_INSTALL_SCRIPT_TZ > /etc/timezone

apt-get update

# basics tools install
apt-get install curl -y

## Install snapd but it does not make sense as if snapd not present it requires system to reboot to take effect.
#apt-get install snapd fail2ban htop iotop glances atop nmap jq -y

export PATH=/snap/bin/:${PATH}

## Install and setup LXD
apt-get remove --purge --yes lxd lxd-client liblxc1 lxcfs

snap install lxd
snap set lxd shiftfs.enable=true


# install travis worker binary
snap install travis-worker --edge
snap connect travis-worker:lxd lxd:lxd
dump_worker_config_file

# the user can use image name or just pass architecture and linux distro so TRAVIS_LXD_INSTALL_SCRIPT_IMAGES_MAP can resolve the image name
if [[ -v TRAVIS_LXD_INSTALL_SCRIPT_IMAGE ]]; then
  image_file="${TRAVIS_LXD_INSTALL_SCRIPT_IMAGE_DIR}/${TRAVIS_LXD_INSTALL_SCRIPT_IMAGE}"
else
  image_file="${TRAVIS_LXD_INSTALL_SCRIPT_IMAGE_DIR}/${TRAVIS_LXD_INSTALL_SCRIPT_IMAGES_MAP}[${TRAVIS_LXD_INSTALL_SCRIPT_ARCH}-${TRAVIS_LXD_INSTALL_SCRIPT_DISTRO}]"
fi

# downloading the image
if test -f $image_file; then
  echo 'nothing to do - the image is already downloaded'
else
  curl "${TRAVIS_LXD_INSTALL_SCRIPT_IMAGE_URL}/${TRAVIS_LXD_INSTALL_SCRIPT_IMAGE}" --output $image_file
fi



# installing the image

lxc image import $image_file --alias travis-image
mkdir -p /containers
lxc storage create default dir source=/containers
lxc profile device add default root disk path=/ pool=default
lxc network create br-c1
lxc launch travis-image travis-container

lxc config device add travis-container eth0 nic nictype=bridged parent=br-c1 name=eth0

snap restart travis-worker
