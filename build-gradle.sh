#!/bin/bash

set -e

# Set a default JAVA_TOOL_OPTIONS if it hasn't already been specified in .travis.yml
export JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS:--Xmx4096m}"

if [[ $(git rev-parse --is-shallow-repository) == "true" ]]
then
    git fetch --unshallow
fi

# TODO: this doesn't work for some merge commits
#if [ ! -z $TRAVIS_COMMIT_RANGE ]; then
#    if ! git diff --name-only $TRAVIS_COMMIT_RANGE | grep -qvE '(^ops|^docker)' ; then
#        echo "Commit range $TRAVIS_COMMIT_RANGE does not contain buildable project code; not running the CI build."
#        exit
#    fi
#fi

if [[ -z "$GRADLE_CACHE_USERNAME" || -z "$GRADLE_CACHE_PASSWORD" ]]; then
    echo "============================================================"
    echo "Set GRADLE_CACHE_USERNAME and GRADLE_CACHE_PASSWORD"
    echo "environment variables to take advantage of the build cache!"
    echo "============================================================"
fi

if [ -z "$TRAVIS_BUILD_NUMBER" ]; then
  if [[ "$DISABLE_BUILD_SCAN" == "true" ]]; then
      ./gradlew $GRADLE_PARAMS
   else
      ./gradlew $GRADLE_PARAMS --scan
   fi
else

    version=""
    if [[ "$TRAVIS_PULL_REQUEST" != "false" ]]; then
        version="PR$TRAVIS_PULL_REQUEST"

    elif [[ "$TRAVIS_TAG" =~ ^v[0-9]+\. ]]; then
        version=${TRAVIS_TAG/v/}

    else
        COMMIT_COUNT=$(git rev-list --count HEAD)
        COMMIT_SHA=$(git rev-parse --short=6 HEAD)

        version=$(git describe --tags --match "v[0-9]*" --abbrev=6 HEAD || echo v0-$COMMIT_COUNT-g$COMMIT_SHA)
        version=${version/v/}
        version+=+$TRAVIS_BUILD_NUMBER

    fi

    echo "======================================"
    echo "Building version ${version}"
    echo "======================================"

    if [[ "$DISABLE_BUILD_SCAN" == "true" ]]; then
        ./gradlew $GRADLE_PARAMS -Prelease="${version}"
     else
        ./gradlew $GRADLE_PARAMS -Prelease="${version}" --scan
     fi
fi
