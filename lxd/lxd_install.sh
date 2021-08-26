#!/bin/bash
set -eux

# functions
configure_travis_worker() {
TRAVIS_WORKER_CONFIG_FILE_PATH="/etc/environment"

cat >> $TRAVIS_WORKER_CONFIG_FILE_PATH<<- EOM
TRAVIS_ENTERPRISE_SECURITY_TOKEN="${TRAVIS_ENTERPRISE_SECURITY_TOKEN}"
TRAVIS_ENTERPRISE_BUILD_ENDPOINT="${TRAVIS_ENTERPRISE_BUILD_ENDPOINT}"
TRAVIS_BUILD_IMAGES="${TRAVIS_BUILD_IMAGES}"
TRAVIS_QUEUE_NAME="${TRAVIS_QUEUE_NAME}"
TRAVIS_ENTERPRISE_HOST="${TRAVIS_ENTERPRISE_HOST}"
BUILD_API_URI="https://${TRAVIS_ENTERPRISE_HOST:-localhost}/${TRAVIS_ENTERPRISE_BUILD_ENDPOINT:-__build__}/script"
TRAVIS_WORKER_DOCKER_NATIVE="true"
AMQP_URI="amqp://travis:${TRAVIS_ENTERPRISE_SECURITY_TOKEN:-travis}@${TRAVIS_ENTERPRISE_HOST:-localhost}/travis"
TRAVIS_WORKER_DOCKER_NATIVE="true"
TRAVIS_WORKER_BUILD_API_INSECURE_SKIP_VERIFY='true'
POOL_SIZE='2'
PROVIDER_NAME='docker'
TRAVIS_WORKER_DOCKER_ENDPOINT='unix:///var/run/docker.sock'
SILENCE_METRICS="true"
TRAVIS_WORKER_DOCKER_BINDS="/sys/fs/cgroup:/sys/fs/cgroup"
TRAVIS_WORKER_DOCKER_SECURITY_OPT="seccomp=unconfined"
TRAVIS_WORKER_DOCKER_TMPFS_MAP="/run:rw,nosuid,nodev,exec,noatime,size=65536k+/run/lock:rw,nosuid,nodev,exec,noatime,size=65536k"
QUEUE_NAME="${TRAVIS_QUEUE_NAME}"
EOM
}


# consts
TRAVIS_LXD_INSTALL_SCRIPT_IMAGE_URL=https://travis-lxc-images.s3.us-east-2.amazonaws.com

declare -A TRAVIS_LXD_INSTALL_SCRIPT_IMAGES_MAP=( ["amd64-focal"]="travis-ci-ubuntu-2004-1603734892-1fb6ced8.tar.gz"
                                                  ["amd64-bionic"]="travis-ci-ubuntu-1804-1603455600-7957c7a9.tar.gz"
                                                  ["s390x-focal"]="ubuntu-20.04-full-1591083354.tar.gz"
                                                  ["s390x-bionic"]="ubuntu-18.04-full-1591342433.tar.gz"
                                                  ["arm64-focal"]="ubuntu-20.04-full-1604305461.tar.gz"
                                                  ["arm64-bionic"]="ubuntu-18.04-full-1604302660.tar.gz"
                                                  ["ppc64le-focal"]="ubuntu-20.04-full-1619708185.tar.gz"
                                                  ["ppc64le-bionic"]="ubuntu-18.04-full-1617839338.tar.gz" )



# variables
#TRAVIS_LXD_INSTALL_SCRIPT_TZ="${TRAVIS_LXD_INSTALL_SCRIPT_TZ:-Europe/London}" # set your time zone
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
      ;;
    --travis_build_images_arch=*)
      TRAVIS_BUILD_IMAGES_ARCH="${1#*=}"
  esac
  shift
done


# travis-worker config
#TRAVIS_ENTERPRISE_SECURITY_TOKEN="H3Tve2EbLECL2u3VQ_9qkSE5OhTD8fsSBaxD6Fne1SHcxha93E2_gwsBe7W7yc_1"
TRAVIS_ENTERPRISE_HOST="${TRAVIS_ENTERPRISE_HOST}" # ext-dev.travis-ci-enterprise.com
TRAVIS_ENTERPRISE_BUILD_ENDPOINT="${TRAVIS_ENTERPRISE_BUILD_ENDPOINT:-__build__}"
TRAVIS_QUEUE_NAME="${TRAVIS_QUEUE_NAME:-builds.bionic}"
TRAVIS_BUILD_IMAGES="${TRAVIS_BUILD_IMAGES:-focal}"
TRAVIS_BUILD_IMAGES_ARCH="${TRAVIS_BUILD_IMAGES_ARCH:-amd64}"




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
apt-get install zfsutils-linux curl -y

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
mkdir -p /etc/default
configure_travis_worker

# receive the image name based on architecture and distro
image_file="${TRAVIS_LXD_INSTALL_SCRIPT_IMAGE_DIR}/${TRAVIS_LXD_INSTALL_SCRIPT_IMAGES_MAP}[${TRAVIS_BUILD_IMAGES_ARCH}-${TRAVIS_BUILD_IMAGES}]"

#mkfs
mkfs.ext4 -F /dev/nvme0n1p5
mkdir -p /mnt/data
echo "/dev/nvme0n1p5 /mnt/data ext4 errors=remount-ro 0 0" >> /etc/fstab
mount -a 2>/dev/null
rm -rf /mnt/data/*

# downloading the image
if test -f $image_file; then
  echo 'nothing to do - the image is already downloaded'
else
  curl "${TRAVIS_LXD_INSTALL_SCRIPT_IMAGE_URL}/${TRAVIS_BUILD_IMAGES_ARCH}/${TRAVIS_LXD_INSTALL_SCRIPT_IMAGE}" --output $image_file
fi

# installing the image and set lxc config
lxc storage create instances zfs source=/dev/nvme0n1p4 volume.zfs.use_refquota=true
zfs set sync=disabled instances
zfs set atime=off instances


lxc storage create data dir source=/mnt/data

lxc network create lxdbr0 dns.mode=none ipv4.address=192.168.0.1/24 ipv4.dhcp=false ipv4.firewall=false
ipv6enabled=$(sysctl -a 2>/dev/null | grep "disable_ipv6 = 1" | wc -l)
if [ "$ipv6enabled" == 0 ]; then
  lxc network set lxdbr0 ipv6.dhcp true
  lxc network set lxdbr0 ipv6.address 2001:db8::1/64
  lxc network set lxdbr0 ipv6.nat true
else
  lxc network set lxdbr0 ipv6.address none
fi

lxc profile device add default eth0 nic nictype=bridged parent=lxdbr0 security.mac_filtering=true
lxc profile device add default root disk path=/ pool=instances

####
lxc image import $image_file --alias travis-image
lxc launch travis-image default


# Force reboot
shutdown -r 0
