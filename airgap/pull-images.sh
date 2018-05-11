#!/usr/bin/env bash


## Some environment setup
set -e
export DEBIAN_FRONTEND=noninteractive

export TRAVIS_WORKER_VERSION="v3.5.0"

download_docker() {
  wget "https://apt.dockerproject.org/repo/pool/main/d/docker-engine/docker-engine_17.05.0~ce-0~ubuntu-xenial_amd64.deb"
}

download_docker

download_apt_packages() {
	sudo apt-get update
	sudo apt-get -d -o dir::cache=`pwd` -o Debug::NoLocking=1 install --download-only -y libltdl7 \
		aufs-tools \
		apt-transport-https \
		ca-certificates \
		curl \
		software-properties-common \
		jq
}

download_apt_packages

zip_apt_packages() {
  tar -zcvf system-packages.tar.gz -C archives .
}

zip_apt_packages

prepare_images_folder() {
  mkdir -p docker_images
}

prepare_images_folder

pull_travis_worker() {
  sudo docker pull travisci/worker:$TRAVIS_WORKER_VERSION
  sudo docker save travisci/worker:$TRAVIS_WORKER_VERSION -o docker_images/travis-worker.tar
}

pull_travis_worker

pull_trusty_build_images() {
  echo "Installing Ubuntu Trusty build images"
  image_mappings_json=$(curl https://raw.githubusercontent.com/travis-infrastructure/terraform-config/master/aws-production-2/generated-language-mapping.json)

  docker_images=$(echo "$image_mappings_json" | jq -r "[.[]] | unique | .[]")

  for docker_image in $docker_images; do
    image_filename=$(echo $docker_image | sed 's/travisci\///')
    sudo docker pull "$docker_image"
    sudo docker save "$docker_image" -o docker_images/"$image_filename".tar
  done

}

pull_trusty_build_images
