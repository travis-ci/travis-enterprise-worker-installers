#!/bin/bash
set -eux

# functions
configure_travis_worker() {
TRAVIS_WORKER_CONFIG_FILE_PATH="/var/snap/travis-worker/common/worker.env"

cat >> $TRAVIS_WORKER_CONFIG_FILE_PATH<<- EOM
export TRAVIS_ENTERPRISE_SECURITY_TOKEN="${TRAVIS_ENTERPRISE_SECURITY_TOKEN}"
export TRAVIS_ENTERPRISE_BUILD_ENDPOINT="${TRAVIS_ENTERPRISE_BUILD_ENDPOINT}"
export TRAVIS_BUILD_IMAGES="${TRAVIS_BUILD_IMAGES}"
export TRAVIS_WORKER_QUEUE_NAME="${TRAVIS_WORKER_QUEUE_NAME}"
export TRAVIS_ENTERPRISE_HOST="${TRAVIS_ENTERPRISE_HOST}"
export BUILD_API_URI="https://${TRAVIS_ENTERPRISE_HOST:-localhost}/${TRAVIS_ENTERPRISE_BUILD_ENDPOINT:-__build__}/script"
export AMQP_URI="amqp://travis:${TRAVIS_ENTERPRISE_SECURITY_TOKEN:-travis}@${TRAVIS_ENTERPRISE_HOST:-localhost}/travis"
export TRAVIS_WORKER_BUILD_API_INSECURE_SKIP_VERIFY='true'
export POOL_SIZE='40'
export PROVIDER_NAME='lxd'
export TRAVIS_WORKER_PROVIDER_NAME=lxd
export SILENCE_METRICS="true"
export QUEUE_NAME="${TRAVIS_WORKER_QUEUE_NAME}"
export TRAVIS_WORKER_LXD_CPUS=2
export TRAVIS_WORKER_LXD_CPUS_BURST=true
export TRAVIS_WORKER_LXD_DOCKER_POOL=data
export TRAVIS_WORKER_LXD_IMAGE=travis-image
export TRAVIS_WORKER_LXD_NETWORK=1Gbit
export TRAVIS_WORKER_LXD_NETWORK_STATIC=true
export TRAVIS_WORKER_LXD_NETWORK_DNS=8.8.8.8,8.8.4.4,1.1.1.1,1.0.0.1
export TRAVIS_WORKER_LXD_DISK=20GB
export TRAVIS_WORKER_DEBUG=true
export EXEC_CMD="chmod 700 /home/travis/build.sh && ls -la /home/travis/build.sh && bash /home/travis/build.sh"
EOM

TRAVIS_WORKER_STARTUP_FILE_PATH="/etc/systemd/system/travis-worker.service"

cat >> $TRAVIS_WORKER_STARTUP_FILE_PATH<<- EOM
[Unit]
Launches travis-worker on the system's startup

[Service]
Type=simple
ExecStart=/snap/bin/lxd sql global "DELETE from storage_volumes where name like '%-docker'" && /snap/bin/travis-worker

[Install]
WantedBy=multi-user.target
EOM

echo "Enabling travis-worker for systemctl"
chmod 644 $TRAVIS_WORKER_STARTUP_FILE_PATH
systemctl enable travis-worker.service
}

help_me() {
      printf "**************************************************************\\n"
      printf "* Error: Invalid argument.                                   *\\n"
      printf "* Valid Arguments are:                                       *\\n"
      printf "*  --travis_enterprise_security_token= REQUIRED - a string   *\\n"
      printf "*  --travis_enterprise_host= REQUIRED - i.e. ext-dev.travis-ci-enterprise.com *\\n"
      printf "*  --travis_worker_queue_name= default is \"builds.bionic\"           *\\n"
      printf "*  --travis_build_images= default is \"focal\". Allowed values are: [\"focal\", \"bionic\"] *\\n"
      printf "*  --travis_enterprise_build_endpoint= default is \"__build__\"           *\\n"
      printf "*  --travis_build_images_arch= default is \"amd64\". Allowed values are: [\"amd64\", \"s390x\", \"arm64\", \"ppc64le\"] *\\n"
      printf "*  --travis_storage_for_instances= default is blank. If blank it uses the default host storage. You can define your storage typing i.e. /dev/nvm0n1p4  *\\n"
      printf "*  --travis_storage_for_data= default is blank. If blank it uses the default host storage. You can define your storage typing i.e. /dev/nvm0n1p4          *\\n"
      printf "*  --travis_network_ipv4_address= a value used for a lxc container. Default is 192.168.0.1/24 *\\n"
      printf "*  --travis_network_ipv6_address= a value used for a lxc container. Default is none. Takes effect if ipv6 is enabled on all interfaces on the host. *\\n"
      printf "**************************************************************\\n"
}

# reading from script's arguments
while [ $# -gt 0 ]; do
  case "$1" in
    --travis_enterprise_security_token=*)
      TRAVIS_ENTERPRISE_SECURITY_TOKEN="${1#*=}"
      ;;
    --travis_enterprise_build_endpoint=*)
      TRAVIS_ENTERPRISE_BUILD_ENDPOINT="${1#*=}"
      ;;
    --travis_worker_queue_name=*)
      TRAVIS_worker_QUEUE_NAME="${1#*=}"
      ;;
    --travis_build_images=*)
      TRAVIS_BUILD_IMAGES="${1#*=}"
      ;;
    --travis_enterprise_host=*)
      TRAVIS_ENTERPRISE_HOST="${1#*=}"
      ;;
    --travis_build_images_arch=*)
      TRAVIS_BUILD_IMAGES_ARCH="${1#*=}"
      ;;
    --travis_storage_for_instances=*)
      TRAVIS_STORAGE_FOR_INSTANCES="${1#*=}"
      ;;
    --travis_storage_for_data=*)
      TRAVIS_STORAGE_FOR_DATA="${1#*=}"
      ;;
    --travis_network_ipv4_address=*)
      TRAVIS_NETWORK_IPV4_ADDRESS="${1#*=}"
      ;;
    --travis_network_ipv6_address=*)
      TRAVIS_NETWORK_IPV6_ADDRESS="${1#*=}"
      ;;
      *)
      help_me
      exit 1
  esac
  shift
done

if [[ ! -v TRAVIS_ENTERPRISE_SECURITY_TOKEN ]]; then
 help_me
 exit 1
fi

if [[ ! -v TRAVIS_ENTERPRISE_HOST ]]; then
 help_me
 exit 1
fi




# consts
TRAVIS_LXD_INSTALL_SCRIPT_IMAGE_URL=https://travis-lxc-images.s3.us-east-2.amazonaws.com
declare -A TRAVIS_LXD_INSTALL_SCRIPT_IMAGES_MAP=(["amd64-focal"]="travis-ci-ubuntu-2004-1603734892-1fb6ced8.tar.gz"
                                                  ["amd64-bionic"]="travis-ci-ubuntu-1804-1603455600-7957c7a9.tar.gz"
                                                  ["s390x-focal"]="ubuntu-20.04-full-1591083354.tar.gz"
                                                  ["s390x-bionic"]="ubuntu-18.04-full-1591342433.tar.gz"
                                                  ["arm64-focal"]="ubuntu-20.04-full-1604305461.tar.gz"
                                                  ["arm64-bionic"]="ubuntu-18.04-full-1604302660.tar.gz"
                                                  ["ppc64le-focal"]="ubuntu-20.04-full-1619708185.tar.gz"
                                                  ["ppc64le-bionic"]="ubuntu-18.04-full-1617839338.tar.gz")

# variables
TRAVIS_LXD_INSTALL_SCRIPT_IMAGE="${TRAVIS_LXD_INSTALL_SCRIPT_IMAGE:-travis-ci-ubuntu-2004-1603734892-1fb6ced8.tar.gz}"
TRAVIS_LXD_INSTALL_SCRIPT_IMAGE_DIR="${TRAVIS_LXD_INSTALL_SCRIPT_IMAGE_DIR:-.}"

echo $TRAVIS_BUILD_IMAGES_ARCH

# travis-worker and lxd instance config
TRAVIS_ENTERPRISE_HOST="${TRAVIS_ENTERPRISE_HOST}"
TRAVIS_ENTERPRISE_BUILD_ENDPOINT="${TRAVIS_ENTERPRISE_BUILD_ENDPOINT:-__build__}"
TRAVIS_WORKER_QUEUE_NAME="${TRAVIS_WORKER_QUEUE_NAME:-builds.bionic}"
TRAVIS_BUILD_IMAGES="${TRAVIS_BUILD_IMAGES:-focal}"
TRAVIS_BUILD_IMAGES_ARCH="${TRAVIS_BUILD_IMAGES_ARCH:-amd64}"
TRAVIS_NETWORK_IPV4_ADDRESS="${TRAVIS_NETWORK_IPV4_ADDRESS:-192.168.0.1/24}"

echo "Updating the OS"
apt-get update

echo "Setting iptables"
iptables -t nat -A POSTROUTING -s 192.168.0.0/24 ! -d 192.168.0.0/24 -j MASQUERADE
iptables -I FORWARD -s 192.168.0.0/24 -d 192.168.0.0/24 -j REJECT
iptables -I INPUT -s 192.168.0.0/24 -j REJECT
iptables -I INPUT -p udp -m udp -d 192.168.0.0/24 --dport 53 -j ACCEPT
iptables -I INPUT -p udp -m udp -s 192.168.0.0/24 --sport 53 -j ACCEPT

echo iptables-persistent iptables-persistent/autosave_v4 boolean true | debconf-set-selections
echo iptables-persistent iptables-persistent/autosave_v6 boolean true | debconf-set-selections

echo "Installing tools"
apt-get install zfsutils-linux curl cron iptables-persistent -y
export PATH=/snap/bin/:${PATH}

# downloading the image
echo "downloading the image"
image_file="${TRAVIS_LXD_INSTALL_SCRIPT_IMAGE_DIR}/${TRAVIS_LXD_INSTALL_SCRIPT_IMAGES_MAP[${TRAVIS_BUILD_IMAGES_ARCH}-${TRAVIS_BUILD_IMAGES}]}"

if test -f $image_file; then
  echo 'nothing to do - the image is already downloaded'
else
  curl "${TRAVIS_LXD_INSTALL_SCRIPT_IMAGE_URL}/${TRAVIS_BUILD_IMAGES_ARCH}/${TRAVIS_LXD_INSTALL_SCRIPT_IMAGE}" --output $image_file
fi

echo "Installing and setting up LXD"
apt-get remove --purge --yes lxd lxd-client liblxc1 lxcfs
snap install lxd
snap set lxd shiftfs.enable=true

# install travis worker binary
echo "Installing travis worker binary"
snap install travis-worker --edge
snap connect travis-worker:lxd lxd:lxd
ipv6disabled=$(sysctl -a 2>/dev/null | grep "disable_ipv6 = 1" | wc -l)
configure_travis_worker

if [[ ! -v TRAVIS_STORAGE_FOR_DATA ]]; then
  echo "Creating a directory for data"
  mkdir -p /mnt/data
else
  echo "Creating a partition for data"
  mkfs.ext4 -F $TRAVIS_STORAGE_FOR_DATA
  mkdir -p /mnt/data
  echo "$TRAVIS_STORAGE_FOR_DATA /mnt/data ext4 errors=remount-ro 0 0" >> /etc/fstab
  mount -a 2>/dev/null
  rm -rf /mnt/data/*
fi

echo "Creating a lxc storage for data"
lxc storage create data dir source=/mnt/data

# installing the image and set lxc config
echo "Creating lxc storage for instances"
if [[ ! -v TRAVIS_STORAGE_FOR_INSTANCES ]]; then
  mkdir -p /mnt/instances
  lxc storage create instances dir source=/mnt/instances
else
  lxc storage create instances zfs source=$TRAVIS_STORAGE_FOR_INSTANCES volume.zfs.use_refquota=true
  zfs set sync=disabled instances
  zfs set atime=off instances
fi

echo "configuring lxc network"
echo 1 > /proc/sys/net/ipv4/ip_forward
modprobe br_netfilter
echo br_netfilter > /etc/modules-load.d/br_netfilter.conf
echo 1 > /proc/sys/net/bridge/bridge-nf-call-iptables
lxc network create lxdbr0 dns.mode=none ipv4.address=$TRAVIS_NETWORK_IPV4_ADDRESS ipv4.dhcp=false ipv4.firewall=false
if [[ -v TRAVIS_NETWORK_IPV6_ADDRESS ]]; then # ipv6 not disabled
  lxc network set lxdbr0 ipv6.dhcp true
  lxc network set lxdbr0 ipv6.address $TRAVIS_NETWORK_IPV6_ADDRESS
  lxc network set lxdbr0 ipv6.nat true
else
  lxc network set lxdbr0 ipv6.address none
fi
lxc profile device add default eth0 nic nictype=bridged parent=lxdbr0 security.mac_filtering=true
lxc profile device add default root disk path=/ pool=instances

echo "Importing and starting image"
lxc image import $image_file --alias travis-image
lxc launch travis-image default

# Force reboot
echo "Rebooting the machine"
shutdown -r 0
