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
    --docker_storage_driver=*)
      DOCKER_STORAGE_DRIVER="${1#*=}"
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
    --travis_legacy_build_images=*)
      TRAVIS_LEGACY_BUILD_IMAGES="${1#*=}"
      ;;
    --skip_docker_populate=*)
      SKIP_DOCKER_POPULATE="${1#*=}"
      ;;
    --airgap_directory=*)
      AIRGAP_DIRECTORY="${1#*=}"
      ;;
    *)

      printf "**************************************************************\\n"
      printf "* Error: Invalid argument.                                   *\\n"
      printf "* Valid Arguments are:                                       *\\n"
      printf "*  --travis_worker_version=x.x.x                             *\\n"
      printf "*  --docker_version=x.x.x                                    *\\n"
      printf "*  --docker_storage_driver=\"<driver>\"                        *\\n"
      printf "*  --travis_enterprise_host=\"demo.enterprise.travis-ci.com\"  *\\n"
      printf "*  --travis_enterprise_security_token=\"token123\"             *\\n"
      printf "*  --travis_enterprise_build_endpoint=\"build-api\"            *\\n"
      printf "*  --travis_queue_name=\"builds.linux\"                        *\\n"
      printf "*  --travis_legacy_build_images=true                         *\\n"
      printf "*  --skip_docker_populate=true                               *\\n"
      printf "*  --airgap_directory=\"<directory>\"                          *\\n"
      printf "**************************************************************\\n"

      exit 1
  esac
  shift
done

if [[ ! -n $DOCKER_VERSION ]]; then
  export DOCKER_VERSION="17.12.0~ce-0~ubuntu"
else
  export DOCKER_VERSION
fi

if [[ ! -n $DOCKER_STORAGE_DRIVER ]]; then
  export DOCKER_STORAGE_DRIVER="overlay2"
else
  export DOCKER_STORAGE_DRIVER
fi

if [[ ! -n $TRAVIS_WORKER_VERSION ]]; then
  export TRAVIS_WORKER_VERSION="v3.5.0"
else
  export TRAVIS_WORKER_VERSION
fi

if [[ ! -n $TRAVIS_LEGACY_BUILD_IMAGES ]]; then
  export BUILD_IMAGES='trusty'
else
  export BUILD_IMAGES='precise'

  # Precise workers listen to the builds.linux by default
  # We only set that though if the user didn't specify a different queue name
  if [[ ! -n $TRAVIS_QUEUE_NAME ]]; then
    export TRAVIS_QUEUE_NAME='builds.linux'
  fi
fi

if [[ ! -n $TRAVIS_QUEUE_NAME ]]; then
  export TRAVIS_QUEUE_NAME='builds.trusty'
else
  export TRAVIS_QUEUE_NAME
fi

if [[ ! -n $TRAVIS_ENTERPRISE_BUILD_ENDPOINT ]]; then
  export TRAVIS_ENTERPRISE_BUILD_ENDPOINT="__build__"
else
  export TRAVIS_ENTERPRISE_BUILD_ENDPOINT
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

require_minimum_disk_space() {
  local root_disk_space=""
  root_disk_space="$(df -k / | tail -1 | awk '{print $2}')"
  # 40593708 == 40GB
  if [[ $((root_disk_space)) -lt 40593708 ]]; then
    echo "You need at least 40GB of total disk space for the root file system"
    exit 1
  fi
}

require_minimum_disk_space

install_packages() {
  # This is necessary because usually package sources are not up to date yet when this script runs.
  apt-get update

  apt-get install -y
    apt-get install -y apt-transport-https \
    ca-certificates \
    curl \
    software-properties-common \
    jq
}

## Install and setup Docker
install_docker() {
  : "${DOCKER_CONFIG_FILE:=/etc/default/docker}"

  if [[ ! -f $DOCKER_APT_FILE ]]; then
    curl -fsSL 'https://download.docker.com/linux/ubuntu/gpg' | apt-key add -
    add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
  fi

  apt-get update

  if ! docker version &>/dev/null; then
    apt-get install -y docker-ce=$DOCKER_VERSION
  fi
}

setup_docker() {
  jq -n '{"storage-driver": $driver, "icc": false, "log-driver": "journald"}' --arg driver $DOCKER_STORAGE_DRIVER > /etc/docker/daemon.json
  systemctl restart docker
  sleep 2 # a short pause to ensure the docker daemon starts
}

extract_aux_tools_archive() {
  mkdir -p /tmp/aux_tools
  tar -xf $AIRGAP_DIRECTORY/aux_tools.tar.gz -C /tmp/aux_tools
  echo "Extracted files"
}

# Installs the travis-tfw-combined-env commandline tool
download_travis_tfw_combined_env() {
  curl -fsSL 'https://raw.githubusercontent.com/travis-ci/terraform-config/4f1d7c45de878140b17535cb7443f1e9bf88ddf2/assets/tfw/usr/local/bin/travis-tfw-combined-env' > /usr/local/bin/travis-combined-env
  chmod +x /usr/local/bin/travis-combined-env
}

install_travis_tfw_combined_env_from_airgap() {
  cp /tmp/aux_tools/travis-combined-env /usr/local/bin/travis-combined-env
  chmod +x /usr/local/bin/travis-combined-env
}

# Installs the wrapper script for running travis-worker
download_travis_worker_wrapper() {
  curl -fsSL 'https://raw.githubusercontent.com/travis-ci/terraform-config/d75b070cbd9fa882a482463e498492a5a2c96a6f/assets/travis-worker/travis-worker-wrapper' > /usr/local/bin/travis-worker-wrapper
  chmod +x /usr/local/bin/travis-worker-wrapper
}

install_travis_worker_wrapper_from_airgap() {
  cp /tmp/aux_tools/travis-worker-wrapper /usr/local/bin/travis-worker-wrapper
  chmod +x /usr/local/bin/travis-worker-wrapper
}

# Installs the systemd service file for travis-worker
install_travis_user() {
  if ! id -u 'travis' > /dev/null 2>&1; then
    adduser \
    --system \
    --shell /bin/false \
    --gecos 'Service user for running travis-worker' \
    --group \
    --disabled-password \
    --no-create-home \
    travis

    #travis needs to be in the docker group to execute docker
    usermod -aG docker travis
  fi
}

download_travis_worker_service_file() {
  curl -fsSL 'https://raw.githubusercontent.com/travis-ci/terraform-config/master/assets/travis-worker/travis-worker.service' > /etc/systemd/system/multi-user.target.wants/travis-worker.service
}

install_travis_worker_file_from_airgap() {
  cp /tmp/aux_tools/travis-worker.service /etc/systemd/system/multi-user.target.wants/travis-worker.service
}

configure_travis_worker_service() {
  mkdir -p /var/tmp/travis-run.d/
  chown -R travis:travis /var/tmp/travis-run.d/
  mkdir -p /etc/systemd/system/travis-worker.service.d
  echo "[Service]" > /etc/systemd/system/travis-worker.service.d/env.conf
  echo "Environment=\"TRAVIS_WORKER_SELF_IMAGE=travisci/worker:$TRAVIS_WORKER_VERSION\"" >> /etc/systemd/system/travis-worker.service.d/env.conf
  systemctl daemon-reload
}

# Pulls down the travis-worker image
install_travis_worker() {
  docker pull travisci/worker:$TRAVIS_WORKER_VERSION
}

pull_precise_build_images() {
  echo "Installing Ubuntu Precise build images"
  # pick the languages you are interested in
  langs='android erlang go haskell jvm node-js perl php python ruby'
  declare -a lang_mappings=('clojure:jvm' 'scala:jvm' 'groovy:jvm' 'java:jvm' 'elixir:erlang' 'node_js:node-js')
  tag=latest
  for lang in $langs; do
    docker pull quay.io/travisci/travis-"$lang":"$tag"
    docker tag quay.io/travisci/travis-"$lang":"$tag" travis:"$lang"
  done

  # tag travis:ruby as travis:default
  docker tag travis:ruby travis:default

  for lang_map in "${lang_mappings[@]}"; do
    map=$(echo "$lang_map"|cut -d':' -f 1)
    lang=$(echo "$lang_map"|cut -d':' -f 2)

    docker tag quay.io/travisci/travis-"$lang":"$tag" travis:"$map"
  done
}

download_language_mapping() {
  curl -fsSL 'https://raw.githubusercontent.com/travis-infrastructure/terraform-config/master/aws-production-2/generated-language-mapping.json' > /tmp/generated-language-mapping.json
}

install_language_mapping_from_airgap() {
  tar -xzf $AIRGAP_DIRECTORY/aux_tools.tar.gz generated-language-mapping.json > /tmp/generated-language-mapping.json
  cat /tmp/generated-language-mapping.json
}

install_docker_images_from_airgap() {
  for filename in $AIRGAP_DIRECTORY/docker_images/*.tar; do
    docker load -i $filename
  done
}

pull_trusty_build_images() {
  echo "Installing Ubuntu Trusty build images"

  image_mappings_json=$(cat /tmp/aux_tools/generated-language-mapping.json)

  docker_images=$(echo "$image_mappings_json" | jq -r "[.[]] | unique | .[]")

  for docker_image in $docker_images; do
    docker pull "$docker_image"

    langs=$(echo "$image_mappings_json" | jq -r "to_entries | map(select(.value | contains(\"$docker_image\"))) | .[] .key")

    for lang in $langs; do
      docker tag "$docker_image" travis:"$lang"
    done
  done

  declare -a lang_mappings=('clojure:jvm' 'scala:jvm' 'groovy:jvm' 'java:jvm' 'elixir:erlang' 'node-js:node_js')

  for lang_map in "${lang_mappings[@]}"; do
    map=$(echo "$lang_map"|cut -d':' -f 1)
    lang=$(echo "$lang_map"|cut -d':' -f 2)

    docker tag travis:"$lang" travis:"$map"
  done
}

configure_travis_worker() {
  TRAVIS_WORKER_CONFIG="/etc/default/travis-worker"

  # Trusty images don't seem to like SSH
  # shellcheck disable=SC2129
  echo "export TRAVIS_WORKER_DOCKER_NATIVE=\"true\"" >> $TRAVIS_WORKER_CONFIG
  echo "export AMQP_URI=\"amqp://travis:${TRAVIS_ENTERPRISE_SECURITY_TOKEN:-travis}@${TRAVIS_ENTERPRISE_HOST:-localhost}/travis\"" >> $TRAVIS_WORKER_CONFIG
  echo "export BUILD_API_URI=\"https://${TRAVIS_ENTERPRISE_HOST:-localhost}/${TRAVIS_ENTERPRISE_BUILD_ENDPOINT:-__build__}/script\"" >> $TRAVIS_WORKER_CONFIG
  echo "export TRAVIS_WORKER_BUILD_API_INSECURE_SKIP_VERIFY='true'" >> $TRAVIS_WORKER_CONFIG
  echo "export POOL_SIZE='2'" >> $TRAVIS_WORKER_CONFIG
  echo "export PROVIDER_NAME='docker'" >> $TRAVIS_WORKER_CONFIG
  echo "export TRAVIS_WORKER_DOCKER_ENDPOINT='unix:///var/run/docker.sock'" >> $TRAVIS_WORKER_CONFIG

  if [[ -n $TRAVIS_QUEUE_NAME ]]; then
    echo "export QUEUE_NAME='$TRAVIS_QUEUE_NAME'" >> $TRAVIS_WORKER_CONFIG
  else
    echo "export QUEUE_NAME='builds.trusty'" >> $TRAVIS_WORKER_CONFIG
  fi
}

if [[ ! -n AIRGAP_DIRECTORY ]]; then
  install_packages
  install_docker
  setup_docker
  download_travis_tfw_combined_env
  download_travis_worker_wrapper
  install_travis_user
  download_travis_worker_service_file
  configure_travis_worker_service 
  install_travis_worker

  
  if [[ ! -n $SKIP_DOCKER_POPULATE ]]; then
    if [[ $BUILD_IMAGES == 'precise' ]]; then
      pull_precise_build_images
    else
      download_language_mapping
      pull_trusty_build_images
    fi
  else
    echo "Skip populating build images"
  fi

  configure_travis_worker
else
  setup_docker
  extract_aux_tools_archive
  install_travis_tfw_combined_env_from_airgap
  install_travis_worker_wrapper_from_airgap
  install_travis_user
  install_travis_worker_file_from_airgap 
  configure_travis_worker_service 
  install_language_mapping_from_airgap
  install_docker_images_from_airgap
  pull_trusty_build_images
  configure_travis_worker
fi


## Give travis-worker a kick to ensure the
## latest config is picked up
if [[ $(pgrep travis-worker) ]]; then
  systemctl stop travis-worker
fi
systemctl start travis-worker

echo 'Installation complete.'
echo 'It is recommended to restart this host before it is used to run any jobs'
