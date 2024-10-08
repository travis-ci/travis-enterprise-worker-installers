#!/usr/bin/env bash
# shellcheck disable=SC2034

## Some environment setup
set -e
export DEBIAN_FRONTEND=noninteractive

##
DEFAULT_TRAVIS_BUILD_IMAGES=focal
DEFAULT_TRAVIS_WORKER_VERSION="v6.2.2"

DEFAULT_BIONIC_IMAGE=ci-ubuntu-1804:packer-1692713071-f03fa67b
DEFAULT_FOCAL_IMAGE=ci-ubuntu-2004:packer-1692701507-9586aaca
DEFAULT_JAMMY_IMAGE=''

DEFAULT_XENIAL_OPAL_IMAGE=ci-opal:packer-1596627727-fb48a890
DEFAULT_XENIAL_SARDONYX_IMAGE=ci-sardonyx:packer-1596621687-01d077a4

DEFAULT_BUILD_IMAGES=focal

UPDATE=false

## Handle Arguments

if [[ -z $1 ]]; then
  echo "No arguments provided, installing with"
  echo "default configuration values."
fi

while [ $# -gt 0 ]; do
  case "$1" in
    --update*)
      UPDATE=true
      ;;
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
    --travis_beta_build_images=*)
      TRAVIS_BETA_BUILD_IMAGES="${1#*=}"
      ;;
    --travis_bionic_build_images=*)
      TRAVIS_BIONIC_BUILD_IMAGES="${1#*=}"
      ;;
    --travis_build_images=*)
      TRAVIS_BUILD_IMAGES="${1#*=}"
      ;;
    --skip_docker_populate=*)
      SKIP_DOCKER_POPULATE="${1#*=}"
      ;;
    --airgap_directory=*)
      AIRGAP_DIRECTORY="${1#*=}"
      ;;
    *)

      printf "***************************************************************\\n"
      printf "* Installer version: v6.2.2-02                                *\\n"
      printf "***************************************************************\\n"
      printf "* Error: Invalid argument.                                    *\\n"
      printf "* Valid Arguments are:                                        *\\n"
      printf "*  --travis_worker_version=x.x.x                              *\\n"
      printf "*  --docker_version=x.x.x                                     *\\n"
      printf "*  --docker_storage_driver=\"<driver>\"                       *\\n"
      printf "*  --travis_enterprise_host=\"demo.enterprise.travis-ci.com\" *\\n"
      printf "*  --travis_enterprise_security_token=\"token123\"            *\\n"
      printf "*  --travis_enterprise_build_endpoint=\"build-api\"           *\\n"
      printf "*  --travis_queue_name=\"builds.focal\"                       *\\n"
      printf "*  --travis_beta_build_images=true (deprecated)               *\\n"
      printf "*  --travis_bionic_build_images=true (deprecated)             *\\n"
      printf "*  --travis_build_images=[trusty, xenial, bionic, focal]      *\\n"
      printf "*  --skip_docker_populate=true                                *\\n"
      printf "*  --airgap_directory=\"<directory>\                          *\\n"
      printf "*  --update  Update build images                              *\\n"
      printf "***************************************************************\\n"

      exit 1
  esac
  shift
done

if [[ -z $DOCKER_VERSION ]]; then
  export DOCKER_VERSION="18.06.1~ce~3-0~ubuntu"
else
  export DOCKER_VERSION
fi

if [[ -z $DOCKER_STORAGE_DRIVER ]]; then
  export DOCKER_STORAGE_DRIVER="overlay2"
else
  export DOCKER_STORAGE_DRIVER
fi

if [[ -z $TRAVIS_WORKER_VERSION ]]; then
  export TRAVIS_WORKER_VERSION="$DEFAULT_TRAVIS_WORKER_VERSION"
else
  export TRAVIS_WORKER_VERSION
fi

if [[ -z $TRAVIS_QUEUE_NAME ]]; then
  export TRAVIS_QUEUE_NAME="builds.$DEFAULT_BUILD_IMAGES"
else
  export TRAVIS_QUEUE_NAME
fi

if [[ -z $TRAVIS_BUILD_IMAGES ]]; then
  export BUILD_IMAGES=$DEFAULT_BUILD_IMAGES
else
  case "$TRAVIS_BUILD_IMAGES" in
    trusty|xenial|bionic|focal)
      export BUILD_IMAGES="$TRAVIS_BUILD_IMAGES"
      ;;
    *)
      export BUILD_IMAGES="$DEFAULT_TRAVIS_BUILD_IMAGES"
      ;;
  esac
    if [[ -z $TRAVIS_QUEUE_NAME ]]; then
      export TRAVIS_QUEUE_NAME="builds.$BUILD_IMAGES"
    else
      export TRAVIS_QUEUE_NAME
    fi
fi

if [[ -z $TRAVIS_ENTERPRISE_BUILD_ENDPOINT ]]; then
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


get_latest_image() {
  repo=$1
  curl -s "https://hub.docker.com/v2/namespaces/travisci/repositories/$repo/tags?page_size=1" | grep -o '"name": *"[^"]*' | grep -o '[^"]*$'
}

get_default_image() {
  case "$1" in
    ci-ubuntu-1804*)
      echo "$DEFAULT_BIONIC_IMAGE"
      ;;
    ci-ubuntu-2004*)
      echo "$DEFAULT_FOCAL_IMAGE"
      ;;
    ci-ubuntu-2204*)
      echo "$DEFAULT_JAMMY_IMAGE"
      ;;
    ci-opal*)
      echo "$DEFAULT_XENIAL_OPAL_IMAGE"
      ;;
    ci-sardonyx*)
      echo "$DEFAULT_XENIAL_SARDONYX_IMAGE"
      ;;
  esac
}


get_image() {
  repo=$1
  local image
  image=$(get_latest_image "$repo")
  if [[ -z $image ]]; then
    image=$(get_default_image "$repo")
  fi
  echo "$image"
}

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
    apt-get update
    apt-get install -y ca-certificates curl
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc
    # shellcheck source=/dev/null
    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null
  fi

  apt-get update

  if ! docker version &>/dev/null; then
     sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  fi
}

setup_docker() {
  jq -n '{"storage-driver": $driver, "icc": false, "log-driver": "journald"}' --arg driver $DOCKER_STORAGE_DRIVER > /etc/docker/daemon.json
  systemctl restart docker
  sleep 2 # a short pause to ensure the docker daemon starts
}

create_aux_tools_dir() {
  mkdir -p /tmp/aux_tools
}

extract_aux_tools_archive() {
  mkdir -p /tmp/aux_tools
  tar -xf "$AIRGAP_DIRECTORY/aux_tools.tar.gz" -C /tmp/aux_tools
  echo "Extracted files"
}

# Installs the travis-tfw-combined-env commandline tool
download_travis_tfw_combined_env() {
  curl -fsSL 'https://raw.githubusercontent.com/travis-ci/travis-enterprise-worker-installers/master/tools/travis-combined-env' > /usr/local/bin/travis-combined-env
  chmod +x /usr/local/bin/travis-combined-env
}

install_travis_tfw_combined_env_from_airgap() {
  cp /tmp/aux_tools/travis-combined-env /usr/local/bin/travis-combined-env
  chmod +x /usr/local/bin/travis-combined-env
}

# Installs the wrapper script for running travis-worker
download_travis_worker_wrapper() {
  curl -fsSL 'https://raw.githubusercontent.com/travis-ci/travis-enterprise-worker-installers/master/tools/travis-worker-wrapper' > /usr/local/bin/travis-worker-wrapper
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
  curl -fsSL 'https://raw.githubusercontent.com/travis-ci/travis-enterprise-worker-installers/master/tools/travis-worker.service' > /etc/systemd/system/travis-worker.service
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
  systemctl enable travis-worker
}

# Pulls down the travis-worker image
install_travis_worker() {
  docker pull travisci/worker:$TRAVIS_WORKER_VERSION
}

download_language_mapping() {
  curl -fsSL 'https://raw.githubusercontent.com/travis-ci/travis-enterprise-worker-installers/master/tools/generated-language-mapping.json' > /tmp/aux_tools/generated-language-mapping.json
}

install_language_mapping_from_airgap() {
  tar -xzf "$AIRGAP_DIRECTORY/aux_tools.tar.gz" generated-language-mapping.json > /tmp/generated-language-mapping.json
  cat /tmp/generated-language-mapping.json
}

install_docker_images_from_airgap() {
  for filename in "$AIRGAP_DIRECTORY"/docker_images/*.tar; do
    docker load -i "$filename"
  done
}

pull_trusty_build_images() {
  echo "Installing Ubuntu 14.04 (trusty) build images"

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

pull_xenial_build_images() {
  echo "Installing Ubuntu 16.04 (xenial) build images"

  opal=$(get_image 'ci-opal')
  sardonyx=$(get_image 'ci-sardonyx')

  docker pull "$opal"
  docker pull "$sardonyx"

  declare -a most_common_language_mappings=('default' 'go' 'jvm' 'node_js' 'php' 'python' 'ruby')
  declare -a other_language_mappings=('haskell' 'erlang' 'perl')

  for lang_map in "${most_common_language_mappings[@]}"; do
    docker tag "$sardonyx" travis:"$lang_map"
  done

  for lang_map in "${other_language_mappings[@]}"; do
    docker tag "$opal" travis:"$lang_map"
  done

  declare -a lang_mappings=('clojure:jvm' 'scala:jvm' 'groovy:jvm' 'java:jvm' 'elixir:erlang' 'node-js:node_js')

  for lang_map in "${lang_mappings[@]}"; do
    map=$(echo "$lang_map"|cut -d':' -f 1)
    lang=$(echo "$lang_map"|cut -d':' -f 2)

    docker tag travis:"$lang" travis:"$map"
  done
}

pull_build_images() {
  ubuntu_images=$1
  image_name=$(echo "$ubuntu_images" | cut -d':' -f 1)

  echo "Installing $image_name build images"

  docker pull "$ubuntu_images"

  declare -a most_common_language_mappings=('default' 'go' 'jvm' 'node_js' 'php' 'python' 'ruby')
  declare -a other_language_mappings=('haskell' 'erlang' 'perl')

  for lang_map in "${most_common_language_mappings[@]}"; do
    docker tag "$ubuntu_images" travis:"$lang_map"
  done

  for lang_map in "${other_language_mappings[@]}"; do
    docker tag "$ubuntu_images" travis:"$lang_map"
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
  echo "export SILENCE_METRICS=\"true\"" >> $TRAVIS_WORKER_CONFIG

  if [[ -n $TRAVIS_QUEUE_NAME ]]; then
    echo "export QUEUE_NAME='$TRAVIS_QUEUE_NAME'" >> $TRAVIS_WORKER_CONFIG
  else
    echo "export QUEUE_NAME='builds.trusty'" >> $TRAVIS_WORKER_CONFIG
  fi

  if [[ $BUILD_IMAGES == 'bionic' || $BUILD_IMAGES == 'focal' ]]; then
    {
      echo "export TRAVIS_WORKER_DOCKER_BINDS=\"/sys/fs/cgroup:/sys/fs/cgroup\""
      echo "export TRAVIS_WORKER_DOCKER_SECURITY_OPT=\"seccomp=unconfined\""
      echo "export TRAVIS_WORKER_DOCKER_TMPFS_MAP=\"/run:rw,nosuid,nodev,exec,noatime,size=65536k+/run/lock:rw,nosuid,nodev,exec,noatime,size=65536k\""
    } >> $TRAVIS_WORKER_CONFIG
  fi
}


setup_images() {
  repo=$1
  image=$(get_image "$repo")
  pull_build_images travisci/"$repo":"$image"
}

drop_images() {
  repo=$1
  for i in $(docker images | grep "$repo" | tr -s ' ' | cut -f 3 -d' '); do
    docker rmi -f "$i"
  done
}

if [[ "$UPDATE" == "true" ]]; then
  if [[ -z $TRAVIS_BUILD_IMAGES ]]; then
    echo "travis_build_images parameter not provided using default: $DEFAULT_BUILD_IMAGES"
  fi
  drop_images 'ci-ubuntu'
  drop_images 'ci-opal'
  drop_images 'ci-sardonyx'
  if [[ $BUILD_IMAGES == 'xenial' ]]; then
    pull_xenial_build_images
  elif [[ $BUILD_IMAGES == 'bionic' ]]; then
    setup_images ci-ubuntu-1804
  elif [[ $BUILD_IMAGES == 'focal' ]]; then
    setup_images ci-ubuntu-2004
  elif [[ $BUILD_IMAGES == 'jammy' ]]; then
    setup_images ci-ubuntu-2204
  else
    download_language_mapping
    pull_trusty_build_images
  fi
else

  if [[ -z "$AIRGAP_DIRECTORY" ]]; then
    install_packages
    install_docker
    setup_docker
    create_aux_tools_dir
    download_travis_tfw_combined_env
    download_travis_worker_wrapper
    install_travis_user
    download_travis_worker_service_file
    configure_travis_worker_service
    install_travis_worker


    if [[ -z $SKIP_DOCKER_POPULATE ]]; then
      if [[ $BUILD_IMAGES == 'xenial' ]]; then
        pull_xenial_build_images
      elif [[ $BUILD_IMAGES == 'bionic' ]]; then
        setup_images ci-ubuntu-1804
      elif [[ $BUILD_IMAGES == 'focal' ]]; then
        setup_images ci-ubuntu-2004
      elif [[ $BUILD_IMAGES == 'jammy' ]]; then
        setup_images ci-ubuntu-2204
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
    create_aux_tools_dir
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

fi #UPDATE

## Give travis-worker a kick to ensure the
## latest config is picked up
if [[ $(pgrep travis-worker) ]]; then
  systemctl stop travis-worker
fi
systemctl start travis-worker

echo 'Installation complete.'
echo 'It is recommended to restart this host before it is used to run any jobs'
