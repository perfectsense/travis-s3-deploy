# Travis S3 Deploy Script

This script is used by [Travis CI](https://travis-ci.com/) in combination with [Travis CI Artifacts Uploader](https://github.com/travis-ci/artifacts) to continuously deploy artifacts to an S3 bucket.

When Travis builds a branch matching `$DEPLOY_BRANCHES` (master, develop, and release by default), any files matching `target/*.{war,jar,zip}` will be uploaded to your S3 bucket with the prefix `$DEPLOY_TARGET_PREFIX/builds/deploy/$BRANCH/$BUILD_NUMBER/`. Pull requests will upload .zip files only with a prefix of `$DEPLOY_TARGET_PREFIX/builds/pull-request/$PULL_REQUEST_NUMBER/`.

For example, the 36th push to the `master` branch will result in the following files being created in your `exampleco-builds` bucket:

```
exampleco/builds/deploy/master/36/exampleco-1.0-SNAPSHOT.war
exampleco/builds/deploy/master/36/exampleco-1.0-SNAPSHOT.zip
```

When the 15th pull request is created, only this file will be uploaded into your bucket:
```
exampleco/builds/pull-request/15/exampleco-1.0-SNAPSHOT.zip
```

## Usage

Your .travis.yml should look something like this:

```yaml
language: java

jdk:
  - oraclejdk8

install: true

branches:
  only:
    - develop
    - master
    - release

env:
  global:
    - DEPLOY_TARGET_PREFIX=exampleco # optional if using a shared deployment bucket
    - DEPLOY_BRANCHES=master\|develop\|release # optional - master / develop / release is the default
    - ARTIFACTS_BUCKET=exampleco-builds

script:
  - mvn -Plibrary verify

after_success:
  - git clone https://github.com/perfectsense/travis-s3-deploy.git && travis-s3-deploy/deploy.sh
```

`ARTIFACTS_KEY` and `ARTIFACTS_SECRET` should be set to your S3 bucket credentials as environment variables in travis.


