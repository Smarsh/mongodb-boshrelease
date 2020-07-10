#!/usr/bin/env bash

set -x
DIRPATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source ${DIRPATH}/VERSIONS

pushd ${DIRPATH}
  fly -t ${CONCOURSE_TARGET:-prodSmarsh} sp \
    -p ds-mongodb-bosh-release \
    -c pipeline.yml \
    -l settings.yml \
    -v bosh-release-name="$(bosh int ../config/final.yml --path /name)_${MONGODB_VERSION}"
popd
