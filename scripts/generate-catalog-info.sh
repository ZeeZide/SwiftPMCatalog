#!/bin/bash

# fail on error
set -e

export IFS="
"

generateDirectory() {
  local name="$1"
  local old="$PWD"
  cd "${name}"
  local isFirst="yes"
  
  #echo
  #echo "GENERATE: ${name} in $PWD"
  
  echo -n "["

  for section in $(jq -r '.order[]' index.json); do
    local indexFile="$section/index.json"
    
    local image=$(jq -r '.image' "${indexFile}")
    local title=$(jq -r '.title' "${indexFile}")
    local suborder=$(jq '.order' "${indexFile}")
    
    if [[ "$isFirst" == "yes" ]]; then
      echo -n "{"
      isFirst="no"
    else
      echo -n ",{"
    fi
    echo "\"title\": \"${title}\","
    if [[ "${image}" != "null" ]]; then
      echo -n "\"image\":\"${image}\","
    fi
    echo -n "\"content\":"
    jq -c '.content' "${indexFile}"
    
    # subsections
    if [[ "$suborder" != "null" ]]; then
      echo -n ",\"subsections\":"
      generateDirectory "${section}"
    fi
    
    echo -n "}"
  done

  echo -n "]"
  cd "${old}"
}

echo "{"
echo "  \"comment\": \"Do not edit, autogenerated: $(date)\","
echo "  \"updated\": \"$(date -u +"%Y%m%dT%H%M%SZ")\","
echo -n "\"sidebar\":"
generateDirectory "sidebar"

echo -n ",\"snapshot-images\":"
jq -c . snapshot-images.json

echo -n ",\"icons\":"
jq -c . icons.json

echo "}"
