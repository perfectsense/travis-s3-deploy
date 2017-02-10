#!/bin/bash

set -e -u

# See: https://github.com/travis-ci/artifacts for usage

if [[ -z "${DEPLOY_TARGET_PREFIX:-}" ]]
then
    DEPLOY_TARGET_PREFIX=""
fi

if [[ -z "${DEPLOY_BRANCHES:-}" ]]
then
    DEPLOY_BRANCHES=master\|develop\|release
fi

if [[ "$TRAVIS_PULL_REQUEST" != "false" ]]
then
    export ARTIFACTS_PATHS=$(ls $TRAVIS_BUILD_DIR/target/*.zip | tr "\n" ":" | sed s/:$//)
    TARGET_PATH=pull-request/$TRAVIS_PULL_REQUEST

elif [[ "$TRAVIS_BRANCH" =~ $DEPLOY_BRANCHES ]]
then
    export ARTIFACTS_PATHS=$(ls $TRAVIS_BUILD_DIR/target/*.{jar,war,zip} 2>/dev/null | tr "\n" ":" | sed s/:$//)
    TARGET_PATH=deploy/$TRAVIS_BRANCH/$TRAVIS_BUILD_NUMBER

else
    echo "Not deploying."
    exit

fi

export ARTIFACTS_WORKING_DIR=$TRAVIS_BUILD_DIR/target
export ARTIFACTS_TARGET_PATHS=$DEPLOY_TARGET_PREFIX/builds/$TARGET_PATH

curl -sL https://raw.githubusercontent.com/travis-ci/artifacts/master/install | bash

~/bin/artifacts --debug upload
