#!/bin/bash

set -e

# Set a default JAVA_TOOL_OPTIONS if it hasn't already been specified in .travis.yml
export JAVA_TOOL_OPTIONS="${JAVA_TOOL_OPTIONS:--Xmx4096m}"

if [[ -n "${SONAR_TOKEN:-}" ]]; then
  version=$(git describe --tags --match "v[0-9]*" --abbrev=0 HEAD || echo "0")
  version=${version/v/}
  
  echo "======================================"
  echo "Running SonarQube Analysis for version ${version}"
  echo "======================================"

  ./gradlew sonarqube -i -PsonarProjectVersion="${version}"
fi
