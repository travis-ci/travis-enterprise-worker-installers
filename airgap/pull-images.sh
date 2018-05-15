#!/usr/bin/env bash


## Some environment setup
set -e
export DEBIAN_FRONTEND=noninteractive

export TRAVIS_WORKER_VERSION="v3.5.0"

prepare_work_directory() {
  mkdir -p workdir
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

download_auxiliary_tools() {
  curl -fsSL 'https://raw.githubusercontent.com/travis-ci/terraform-config/4f1d7c45de878140b17535cb7443f1e9bf88ddf2/assets/tfw/usr/local/bin/travis-tfw-combined-env' > travis-combined-env
  curl -fsSL 'https://raw.githubusercontent.com/travis-ci/terraform-config/d75b070cbd9fa882a482463e498492a5a2c96a6f/assets/travis-worker/travis-worker-wrapper' > travis-worker-wrapper
  curl -fsSL 'https://raw.githubusercontent.com/travis-ci/terraform-config/master/assets/travis-worker/travis-worker.service' > travis-worker.service
  curl -fsSL 'https://raw.githubusercontent.com/travis-infrastructure/terraform-config/master/aws-production-2/generated-language-mapping.json' > generated-language-mapping.json

  tar -cvzf aux_tools.tar.gz travis-combined-env travis-worker-wrapper travis-worker.service generated-language-mapping.json
}

download_auxiliary_tools
mv aux_tools.tar.gz ../aux_tools.tar.gz
mv docker_images ../docker_images
cd ..
rm -rf workdir
echo "Pulling images and dependencies finished"
echo "Plase copy aux_tools.tar.gz and docker_images/ over to the worker machine"
