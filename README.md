# <p style="text-align:center">Mongodb Bosh Release</p>

## Contents

  * [Purpose](#purpose)
  * [What should the Release do](#what-should-the-release-do)
  * [Development](#development)
    + [Building](#building)
    + [Templating](#templating)
    + [Cluster authentication](#cluster-authentication)
    + [Users](#users)
    + [Upgrading MongoDB](#upgrading-mongodb)
    + [CI Pipeline](#ci-pipeline)
  * [Usage](#usage)
    + [Example manifests](#example-manifests)
    + [Debugging](#debugging)
    + [Scaling](#scaling)
      + [Adding shards](#adding-shards)
  * [Acceptance tests](#acceptance-tests)

## Purpose

This project is a [Mongodb](https://www.mongodb.com) [Bosh](http://bosh.io) release.
The blobs are the provided ones from the mongodb community and are not compiled anymore. So the release can now only be deployed on an ubuntu stemcell.

This version excludes the rocksdb engine, which is not supported anymore.

## What should the Release do

* Configure a standalone or a set of standalone servers
* Configure a replica set
* Configure a sharded cluster including config server and mongos
* Complete requirements for mongodb servers ([production notes](https://docs.mongodb.org/manual/administration/production-notes/))
* Install mongodb component (shell / tools / mongod)

## Development

This release uses [BPM](https://github.com/cloudfoundry/bpm-release) for process management. This means there is no need for control scripts or any pidfile handling. The `monit` file instead tracks a pidfile created and managed by BPM and the control script is replaced by the `bpm.yml` config file. See the [docs on migrating to BPM](https://bosh.io/docs/bpm/transitioning/) for a more detailed description of what each file does.

This release uses submodules. These can be cloned by running:
```sh
git submodule update --init --recursive
```

### Building

To build the release, you will need to sync the blobs from S3. Ensure you have valid AWS credentials in your environment for the `smarsh-bosh-release-blobs` bucket then run `bosh sync-blobs`. After syncing the blobs you can run `bosh create-release --force` to build a new release.
> Note: This will build a dev release which should **not** be used in production. Final releases are continuously built from master and published to the `smarsh-bosh-releases` S3 bucket.

### Templating

Since most of the jobs in this release are running `mongod` or `mongos`, a lot of the configuration is similar too. To avoid repetition, there is a shared [templates](templates/) directory which is symlinked into each of the relevant jobs.
> Note: Some editors (e.g. VSCode) will make the symlink look like it is a true subdirectory so be careful when editing any templates that the changes are relevant to all jobs using it.

### Cluster authentication

Components of the cluster authenticate with each other using [x509 membership authentication](https://docs.mongodb.com/manual/tutorial/configure-x509-member-authentication/). A shared CA is given to each VM which then issues itself a certificate from that CA. This allows for scaling up the cluster without having to add new certificates for members as only the CA is needed. The certificate for the CA can be given to clients that need to trust the cluster.

### Users

This release is capable of creating users within the cluster. This approach is encouraged to allow for the users to be properly source controlled and repeatably deployed. The `mongod`, `mongos` and `shardsvr` jobs are all capable of creating users by setting `users` job property in the following format.
```yaml
users:
- name: root
  password: ((root_password))
  roles:
  - { role: root, db: admin }
- name: monitoring
  password: ((monitoring_password))
  roles:
  - { role: clusterMonitor, db: admin }
  - { role: read, db: local
```

### Upgrading MongoDB

To upgrade the version of MongoDB, a new blob will need to be added. Download the new `TGZ` package of MongoDB from the [MongoDB download center](https://www.mongodb.com/download-center/community). To add this blob, run `bosh add-blob <path_to_tarball.tgz> mongodb/mongodb-linux-x86_64-<new_version>.tar.gz`. The old blob should then be removed with `bosh remove-blob mongodb/mongodb-linux-x86_64-<old_version>.tar.gz`. To upload the new blob to the blobstore, ensure you have valid AWS credentials in your environment for the `smarsh-bosh-release-blobs` bucket then run `bosh upload-blobs`. Commit and push the changes to `blobs.yml` and check the pipeline successfully built the new release.

### CI Pipeline

This release is continuously built from master on the Smarsh prod Concourse. The pipeline lives in [ci/pipeline.yml](ci/pipeline.yml).

## Usage

### Releases

Final releases for MongoDB are uploaded to the `smarsh-bosh-releases` S3 bucket. To use these releases, either download the relevant artifact from S3 and run `bosh upload-release <path_to_release.tgz>` or add the final release to Concourse to upload to the director. An example Concourse pipeline may look like:
```yaml
resources:
- name: mongodb_release
  type: s3
  source:
    regexp: mongodb/mongodb-(\d*.\d*.\d*).tgz
    bucket: smarsh-bosh-releases
    access_key_id: ((smarsh_bosh_releases_user.access_key_id))
    secret_access_key: ((smarsh_bosh_releases_user.secret_access_key))
- name: bpm_release
  type: bosh-io-release
  source:
    repository: cloudfoundry/bpm-release
...

jobs:
- name: deploy_mongodb
  serial: true
  plan:
  - get: mongodb_release
    trigger: true
  - get: bpm_release
  - get: mongodb_manifest_repo
    trigger: true
  - put: mongodb_deployment
    params:
      manifest: mongodb_manifest_repo/manifest.yml
      releases:
      - mongodb_minio/mongodb-*tgz
      - bpm_minio/bpm-*tgz
      vars:
        mongo_ca.private_key: |
          ((mongo_ca.private_key))
        etc.
```

### Example manifests

Two example manifests are provided for single replicaset or sharded deployment and can be found in the `manifests` directory. The manifest used for testing this release can be found in the [ci directory](ci/files/manifest.yml).

### Debugging

Logs for all mongo cluster jobs are available in the `/var/vcap/sys/log/<job>/` directory or via `bosh logs`. To investigate the cluster, shell scripts which are pre-authenticated against the cluster are provided with the relevant jobs (see below).
| Cluster type         | Run     |
| --------------- | ----------- |
| replicaset         | `/var/vcap/jobs/mongod/bin/mongo`    |
| sharded         | `/var/vcap/jobs/mongos/bin/mongo`    |

### Scaling

All datastore components of the cluster contain [pre-start scripts](https://bosh.io/docs/pre-start/) and [drain scripts](https://bosh.io/docs/drain/) that allow them to gracefully enter and leave the cluster. This should allow for zero-downtime scaling in and out of the cluster but this should be tested in a pre-production environment first. To expand the storage of a replicaset, increase the size of the disk allocated to the BOSH VMs.

#### Adding shards

To expand the storage of a sharded cluster, additional shards can be added. To add a new shard, a new instance group running `shardsvr` should be created and the BOSH links of the existing `shardsvr` instance grpups updated to use [explicit self links](https://bosh.io/docs/links/#self). An example [ops file](https://bosh.io/docs/cli-ops-files/) to add an additional, identical shard to the [sharded example manifest](manifests/manifest-shard.yml) can be found in [manifests/ops/add-additional-shard.yml](manifests/ops/add-additional-shard.yml).

## Acceptance tests

This release comes with an acceptance test errand for validating deployed clusters. See the [CI manfiest](ci/files/manifest.yml) for an example of how to configure this errand. You should include the following test suites for the relevant cluster types.
> Note: The acceptance tests for replicasets and sharding require a user with `root` privileges in each of the replicasets.

| Cluster type | Run |
| --------------- | ----------- |
| single instance | replicaset |
| replicaset | readwrite, replicaset |
| sharded (single shard) | readwrite, replicaset |
| sharded (multiple shards) | readwrite, replicaset, sharding |