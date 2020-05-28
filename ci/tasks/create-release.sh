#!/usr/bin/env bash

set -euo pipefail

if [[ $(echo $TERM | grep -v xterm) ]]; then
  export TERM=xterm
fi

SHELL=/bin/bash
ROOT_DIR=$(pwd)
USE_PIPELINE=0

ROOT_PATH=${PWD}
DEV_RELEASE_DIR=${ROOT_PATH}/s3-dev-release/kafka-dev-release.tgz
BOSH_RELEASE_VERSION=$(cat ../version/version)
INPUT_DIR=git-bosh-release
OUTPUT_DIR=create-release
PROMOTED_REPO=${INPUT_DIR}-pr

BOLD=$(tput bold)
RED=$(tput setaf 1)
GREEN=$(tput setaf 2)
YELLOW=$(tput setaf 3)
MAGENTA=$(tput setaf 5)
RESET=$(tput sgr0)


[[ ${USE_PIPELINE} -ne 0 ]] && pushd ./${INPUT_DIR}

VERSION_FILE="${ROOT_DIR}/VERSIONS"

KAFKA_VERSION=${KAFKA_VERSION:?required}


if [[ ! -d ../${DEV_RELEASE_DIR} ]] ; then 
  tarBallFile=./kafka-dev-release.tgz
else
  tarBallFile=../${DEV_RELEASE_DIR}/kafka-dev-release.tgz
fi


printf "\n${BOLD}${GREEN}Create final release${RESET}\n"

git config --global user.email "ci@localhost"
git config --global user.name "CI Bot"

popd

pushd ./${INPUT_DIR}
tag_name="v${VERSION}"

tag_annotation="Final release ${VERSION} tagged via concourse"

git tag -a "${tag_name}" -m "${tag_annotation}"
popd

git clone ./${INPUT_DIR} $PROMOTED_REPO

pushd $PROMOTED_REPO
git status

git checkout master
git status

cat > config/final.yml <<EOF
---
blobstore:
provider: s3
options:
  bucket_name: smarsh-bosh-release-blobs
  region: eu-west-2
name: kafka
EOF

cat > config/private.yml <<EOF
---
blobstore:
provider: s3
options:
  credentials_source: env_or_profile
EOF

echo bosh finalize-release --version $VERSION $DEV_RELEASE_PATH
echo bosh create-release --final --name kafka --version=${VERSION} --timestamp-version --tarball ${tarBallFile}

git add -A
git status

git commit -m "Adding final release $VERSION via concourse"
popd


[[ $USE_PIPELINE -ne 0 ]] && popd

###
