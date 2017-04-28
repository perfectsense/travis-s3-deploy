# Travis S3 Deploy Script

This script is used by [Travis CI](https://travis-ci.com/) to continuously deploy artifacts to an S3 bucket.

When Travis builds a push to your project (not a pull request), any files matching `target/*.{war,jar,zip}` will be uploaded to your S3 bucket with the prefix `$DEPLOY_BUCKET_PREFIX/builds/deploy/$BRANCH/$BUILD_NUMBER/`. Pull requests will upload the same files with a prefix of `$DEPLOY_BUCKET_PREFIX/builds/pull-request/$PULL_REQUEST_NUMBER/`.

For example, the 36th push to the `master` branch will result in the following files being created in your `exampleco-ops` bucket:

```
exampleco/builds/deploy/master/36/exampleco-1.0-SNAPSHOT.war
exampleco/builds/deploy/master/36/exampleco-1.0-SNAPSHOT.zip
```

When the 15th pull request is created, the following files will be uploaded into your bucket:
```
exampleco/builds/pull-request/15/exampleco-1.0-SNAPSHOT.war
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
    - DEPLOY_BUCKET=exampleco-builds
    - DEPLOY_BUCKET_PREFIX=exampleco # optional if using a shared deployment bucket
    - DEPLOY_BRANCHES=develop\|release # optional - all branches defined in "branches" above is the default

script:
  - mvn -Plibrary verify

after_success:
  - git clone https://github.com/perfectsense/travis-s3-deploy.git && travis-s3-deploy/deploy.sh
```

Note that any of the above environment variables can be set in Travis, and do not need to be included in your .travis.yml. `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` should always be set to your S3 bucket credentials as environment variables in Travis, not this file.


