#!/bin/bash

set -e

# Set a default JAVA_TOOL_OPTIONS if it hasn't already been specified in .travis.yml
export JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS:--Xmx4096m}"

if [[ -z "${SONAR_TOKEN:-}" ]]; then
  echo "SonarCloud token not present in the environment. Aborting."
  exit 1
fi

echo "======================================"
echo "Running SonarQube Analysis"
echo "======================================"

if [[ "$TRAVIS_PULL_REQUEST" != "false" ]]; then
  ./gradlew sonarqube -i -Dsonar.pullrequest.key="$TRAVIS_PULL_REQUEST"
else
  version=$(git describe --tags --match "v[0-9]*" --abbrev=0 HEAD || echo "0")
  version=${version/v/}
  echo "Creating a new analysis for version ${version}"
  ./gradlew sonarqube -i -Dsonar.projectVersion="${version}"
fi
