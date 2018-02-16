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

if [[ ! -n $TRAVIS_WORKER_VERSION ]]; then
  export TRAVIS_WORKER_VERSION="v3.5.0"
else
  export TRAVIS_WORKER_VERSION
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

install_packages() {
  apt-get install -y
    apt-get install -y apt-transport-https \
    ca-certificates \
    curl \
    software-properties-common \
    jq
}

install_packages

## Install and setup Docker
docker_setup() {
  : "${DOCKER_CONFIG_FILE:=/etc/default/docker}"

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

# Installs the travis-tfw-combined-env commandline tool
install_travis_tfw_combined_env() {
  curl -fsSL 'https://raw.githubusercontent.com/travis-ci/terraform-config/master/assets/tfw/usr/local/bin/travis-tfw-combined-env' > /usr/local/bin/travis-combined-env
  chmod +x /usr/local/bin/travis-combined-env
}

install_travis_tfw_combined_env

# Installs the wrapper script for running travis-worker
install_travis_worker_wrapper() {
  curl -fsSL 'https://raw.githubusercontent.com/travis-ci/terraform-config/master/assets/travis-worker/travis-worker-wrapper' > /usr/local/bin/travis-worker-wrapper
  chmod +x /usr/local/bin/travis-worker-wrapper
}

install_travis_worker_wrapper

# Installs the systemd service file for travis-worker
install_travis_worker_service_file() {
  if ! id -u 'travis' > /dev/null 2>&1; then
    adduser \
    --system \
    --shell /bin/false \
    --gecos 'Service user for running travis-worker' \
    --group \
    --disabled-password \
    --no-create-home \
    travis
  fi

  curl -fsSL 'https://raw.githubusercontent.com/travis-ci/terraform-config/master/assets/travis-worker/travis-worker.service' > /etc/systemd/system/multi-user.target.wants/travis-worker.service
  systemctl daemon-reload
}

install_travis_worker_service_file

# Pulls down the travis-worker image
install_travis_worker() {
  docker pull travisci/worker:$TRAVIS_WORKER_VERSION
  echo "TRAVIS_WORKER_SELF_IMAGE=travisci/worker:$TRAVIS_WORKER_VERSION" >> /etc/environment
  source /etc/environment
}

install_travis_worker

pull_build_images() {
  image_mappings_json=$(curl https://raw.githubusercontent.com/travis-infrastructure/terraform-config/master/aws-production-2/generated-language-mapping.json)

  docker_images=$(echo "$image_mappings_json" | jq -r "[.[]] | unique | .[]")

  for docker_image in $docker_images; do
    docker pull "$docker_image"

    langs=$(echo "$image_mappings_json" | jq -r "to_entries | map(select(.value | contains(\"$docker_image\"))) | .[] .key")

    for lang in $langs; do
      docker tag $docker_image travis:$lang
    done
  done

  declare -a lang_mappings=('clojure:jvm' 'scala:jvm' 'groovy:jvm' 'java:jvm' 'elixir:erlang' 'node-js:node_js')

  for lang_map in "${lang_mappings[@]}"; do
    map=$(echo $lang_map|cut -d':' -f 1)
    lang=$(echo $lang_map|cut -d':' -f 2)

    docker tag travis:$lang travis:$map
  done
}

if [[ ! -n $SKIP_DOCKER_POPULATE ]]; then
  docker_populate_images
fi
