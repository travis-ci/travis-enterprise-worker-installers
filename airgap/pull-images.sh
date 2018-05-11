#!/usr/bin/env bash


## Some environment setup
set -e
export DEBIAN_FRONTEND=noninteractive

wget "https://apt.dockerproject.org/repo/pool/main/d/docker-engine/docker-engine_17.05.0~ce-0~ubuntu-xenial_amd64.deb"

sudo apt-get update
sudo apt-get -d -o dir::cache=`pwd` -o Debug::NoLocking=1 install --download-only -y libltdl7 \
	aufs-tools \
	apt-transport-https \
	ca-certificates \
	curl \
	software-properties-common \
	jq

