#!/bin/sh
# Xcode Cloud runs this right after cloning. The Xcode project isn't committed (it's
# generated from project.yml), so generate it here before Xcode Cloud looks for it.
set -e

cd "$CI_PRIMARY_REPOSITORY_PATH"

if ! command -v xcodegen >/dev/null 2>&1; then
  brew install xcodegen
fi

# Signing team and a unique build number for every cloud build (TestFlight needs one).
{
  [ -n "$CI_TEAM_ID" ] && echo "DEVELOPMENT_TEAM = $CI_TEAM_ID"
  [ -n "$CI_BUILD_NUMBER" ] && echo "CURRENT_PROJECT_VERSION = $CI_BUILD_NUMBER"
} > Config/Local.xcconfig || true

xcodegen generate
