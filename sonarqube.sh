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
./gradlew sonarqube -i
