#!/usr/bin/env bash

## Some environment setup
set -e
export DEBIAN_FRONTEND=noninteractive

##

## Handle Arguments

if [[ ! -n $1 ]]; then
  echo "No arguments provided, installing with"
  echo "default configuration values."
fi

while [ $# -gt 0 ]; do
  case "$1" in
    --travis_worker_version=*)
      TRAVIS_WORKER_VERSION="${1#*=}"
      ;;
    --docker_version=*)
      DOCKER_VERSION="${1#*=}"
      ;;
    --aws=*)
      AWS="${1#*=}"
      ;;
    --travis_enterprise_host=*)
      TRAVIS_ENTERPRISE_HOST="${1#*=}"
      ;;
    --travis_enterprise_security_token=*)
      TRAVIS_ENTERPRISE_SECURITY_TOKEN="${1#*=}"
      ;;
    --travis_enterprise_build_endpoint=*)
      TRAVIS_ENTERPRISE_BUILD_ENDPOINT="${1#*=}"
      ;;
    --travis_queue_name=*)
      TRAVIS_QUEUE_NAME="${1#*=}"
      ;;
    --skip_docker_populate=*)
      SKIP_DOCKER_POPULATE="${1#*=}"
      ;;
    *)
      printf "*************************************************************\n"
      printf "* Error: Invalid argument.                                  *\n"
      printf "* Valid Arguments are:                                      *\n"
      printf "*  --travis_worker_version=x.x.x                            *\n"
      printf "*  --docker_version=x.x.x                                   *\n"
      printf "*  --aws=true                                               *\n"
      printf "*  --travis_enterprise_host="demo.enterprise.travis-ci.com" *\n"
      printf "*  --travis_enterprise_security_token="token123"            *\n"
      printf "*  --travis_enterprise_build_endpoint="build-api"           *\n"
      printf "*  --travis_queue_name="builds.linux"                       *\n"
      printf "*  --skip_docker_populate=true                              *\n"
      printf "*************************************************************\n"
      exit 1
  esac
  shift
done

if [[ ! -n $DOCKER_VERSION ]]; then
  export DOCKER_VERSION="17.12.0~ce-0~ubuntu"
else
  export DOCKER_VERSION
fi

## We only want to run as root
root_check() {
  if [[ $(whoami) != "root" ]]; then
    echo "This should only be run as root"
    exit 1
  fi
}

root_check
##

## Install and setup Docker
docker_setup() {

  : "${DOCKER_APT_FILE:=/etc/apt/sources.list.d/docker.list}"
  : "${DOCKER_CONFIG_FILE:=/etc/default/docker}"

  apt-get install -y apt-transport-https \
    ca-certificates \
    curl \
    software-properties-common

  if [[ ! -f $DOCKER_APT_FILE ]]; then
    curl -fsSL 'https://download.docker.com/linux/ubuntu/gpg' | apt-key add -
    add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
  fi

  apt-get update

  if ! docker version &>/dev/null; then
    apt-get install -y \
      "linux-image-extra-$(uname -r)" \
      docker-ce=$DOCKER_VERSION
  fi

  # use LXC, and disable inter-container communication
  if [[ ! $(grep icc $DOCKER_CONFIG_FILE) ]]; then
    echo 'DOCKER_OPTS="-H tcp://127.0.0.1:4243 -H unix:///var/run/docker.sock --icc=false '$DOCKER_MOUNT_POINT'"' >> $DOCKER_CONFIG_FILE
    systemctl restart docker
    sleep 2 # a short pause to ensure the docker daemon starts
  fi
}

docker_setup
