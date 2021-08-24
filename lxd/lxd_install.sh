#!/bin/sh
set -eux


#travis-worker configuration

if [[ ! -v TRAVIS_ENTERPRISE_SECURITY_TOKEN ]]; then
 echo 'please set TRAVIS_ENTERPRISE_SECURITY_TOKEN'
 exit 1
fi

if [[ ! -v TRAVIS_ENTERPRISE_BUILD_ENDPOINT ]]; then
 echo 'please set TRAVIS_ENTERPRISE_BUILD_ENDPOINT'
 exit 1
fi

if [[ ! -v TRAVIS_QUEUE_NAME ]]; then
 echo 'please set TRAVIS_QUEUE_NAME'
 exit 1
fi


if [[ ! -v TRAVIS_BUILD_IMAGES ]]; then
 echo 'please set TRAVIS_BUILD_IMAGES'
 exit 1
fi

export TRAVIS_ENTERPRISE_SECURITY_TOKEN
export TRAVIS_ENTERPRISE_BUILD_ENDPOINT
export TRAVIS_QUEUE_NAME
export TRAVIS_BUILD_IMAGES

#/travis-worker configuration


# consts
TRAVIS_LXD_INSTALL_SCRIPT_IMAGE_URL=https://travis-lxc-images.s3.us-east-2.amazonaws.com

# variables
TRAVIS_LXD_INSTALL_SCRIPT_TZ="${TRAVIS_LXD_INSTALL_SCRIPT_TZ:-Europe/London}" # set your time zone
TRAViS_LXD_INSTALL_SCRIPT_ARCH="${TRAViS_LXD_INSTALL_SCRIPT_ARCH:-amd64}"
TRAVIS_LXD_INSTALL_SCRIPT_IMAGE="${TRAVIS_LXD_INSTALL_SCRIPT_IMAGE:-travis-ci-ubuntu-2004-1603734892-1fb6ced8.tar.gz}"
TRAVIS_LXD_INSTALL_SCRIPT_IMAGE_DIR="${TRAVIS_LXD_INSTALL_SCRIPT_IMAGE_DIR:-.}"

ln -snf /usr/share/zoneinfo/$TRAVIS_LXD_INSTALL_SCRIPT_TZ /etc/localtime && echo $TRAVIS_LXD_INSTALL_SCRIPT_TZ > /etc/timezone

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

image_file="${TRAVIS_LXD_INSTALL_SCRIPT_IMAGE_DIR}/${TRAViS_LXD_INSTALL_SCRIPT_ARCH}-${TRAVIS_LXD_INSTALL_SCRIPT_IMAGE}"

# downloading the image
if test -f $image_file; then
  echo 'nothing to do - the image is already downloaded'
else
  curl "${TRAVIS_LXD_INSTALL_SCRIPT_IMAGE_URL}/${TRAViS_LXD_INSTALL_SCRIPT_ARCH}/${TRAVIS_LXD_INSTALL_SCRIPT_IMAGE}" --output $image_file
fi



# installing the image

lxc image import $image_file --alias travis-image
mkdir -p /containers
lxc storage create default dir source=/containers
lxc profile device add default root disk path=/ pool=default
lxc network create br-c1
lxc launch travis-image travis-container
lxc config device add travis-container eth0 nic nictype=bridged parent=br-c1 name=eth0
#lxc delete -f travis-container

