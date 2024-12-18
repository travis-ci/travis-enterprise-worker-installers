#!/usr/bin/env bash

echo "Installing Ubuntu 18.04 (bionic) build images"

ubuntu1804=travisci/ci-ubuntu-2004:packer-1725882603-4e45eefd

docker pull $ubuntu1804

declare -a most_common_language_mappings=('default' 'go' 'jvm' 'node_js' 'php' 'python' 'ruby')
declare -a other_language_mappings=('haskell' 'erlang' 'perl')

for lang_map in "${most_common_language_mappings[@]}"; do
  docker tag $ubuntu1804 travis:"$lang_map"
done

for lang_map in "${other_language_mappings[@]}"; do
  docker tag $ubuntu1804 travis:"$lang_map"
done

declare -a lang_mappings=('clojure:jvm' 'scala:jvm' 'groovy:jvm' 'java:jvm' 'elixir:erlang' 'node-js:node_js')

for lang_map in "${lang_mappings[@]}"; do
  map=$(echo "$lang_map"|cut -d':' -f 1)
  lang=$(echo "$lang_map"|cut -d':' -f 2)

  docker tag travis:"$lang" travis:"$map"
done

