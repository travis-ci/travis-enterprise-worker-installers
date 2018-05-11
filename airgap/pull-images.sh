#!/usr/bin/env bash


## Some environment setup
set -e
export DEBIAN_FRONTEND=noninteractive

wget https://apt.dockerproject.org/repo/pool/main/d/docker-engine/docker-engine_17.05.0~ce-0~ubuntu-trusty_amd64.deb
sudo apt-get update
sudo apt-get install --download-only libsystemd-journal0 \ 
	libltdl7 \
	aufs-tools \
	apt-transport-https \
	ca-certificates \
	curl \
	software-properties-common \
	jq

