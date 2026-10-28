#!/bin/bash
# Creates the default Maven repositories in Artifactory OSS:
#   libs-release-local, libs-snapshot-local, maven-remote, libs-release, libs-snapshot
# Same result as the UI "Quick Setup" -> Maven. (The public repository REST API is Pro-only,
# so this calls the endpoint the setup wizard uses.)
#
# Usage: ARTIFACTORY_USERNAME=admin ARTIFACTORY_PASSWORD=<password> ./create-maven-repos.sh [http://<server-ip>:8082]
set -e
URL=${1:-http://localhost:8082}
curl -sf -u "$ARTIFACTORY_USERNAME:$ARTIFACTORY_PASSWORD" -X POST \
  -H 'Content-Type: application/json' -H 'X-Requested-With: XMLHttpRequest' \
  "$URL/artifactory/ui/onboarding/createDefaultRepos" \
  -d '{"repoTypeList":["Maven"],"fromOnboarding":true}'
echo
curl -sf -u "$ARTIFACTORY_USERNAME:$ARTIFACTORY_PASSWORD" "$URL/artifactory/api/repositories" | grep '"key"'
