#!/usr/bin/env bash


## Some environment setup
set -e
export DEBIAN_FRONTEND=noninteractive

export TRAVIS_WORKER_VERSION="v3.5.0"

prepare_work_directory() {
  mkdir workdir
}

prepare_work_directory

cd workdir

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
