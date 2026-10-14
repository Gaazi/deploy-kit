#!/bin/bash
# Prepare checksums, package a tested release, or explicitly publish it from main.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source lib/kit-release.sh
ACTION="${1:-help}"; TAG="${2:-v$(cat VERSION)}"
kit_version_valid "$TAG" && [[ "$TAG" = v* ]] || { echo 'Use a stable version: vMAJOR.MINOR.PATCH.'; exit 1; }

# A prepare command changes local version/checksums only, never tags or remotes.
release_prepare() {
  printf '%s\n' "${TAG#v}" > VERSION
  kit_bundle_hash . > kit-files.sha256.next
  mv kit-files.sha256.next kit-files.sha256
  kit_bundle_valid . && kit_bundle_syntax .
  echo "Prepared $TAG. Review release notes, run tests, commit and push through your normal branch workflow."
}

# Build only committed, verified kit files with deterministic archive metadata.
release_package() {
  [ "$(cat VERSION)" = "${TAG#v}" ] || { echo 'TAG must match VERSION.'; return 1; }
  git diff --quiet && git diff --cached --quiet || { echo 'Commit release changes before packaging.'; return 1; }
  kit_bundle_valid . && kit_bundle_syntax . || return 1
  grep -qxF "## $TAG" RELEASE_NOTES.md || { echo 'Add release notes for this version first.'; return 1; }
  bash test.sh || return 1
  local files=()
  mapfile -t files < kit-files.list
  mkdir -p ".kit-release/$TAG"
  git archive --format=tar HEAD -- "${files[@]}" kit-files.sha256 | gzip -n > ".kit-release/$TAG/deploy-kit-$TAG.tar.gz"
  git show HEAD:RELEASE_NOTES.md > ".kit-release/$TAG/notes.md"
  echo "Package: .kit-release/$TAG/deploy-kit-$TAG.tar.gz"
}

# Publication requires a named version, clean main, remote sync, and passing tests.
release_publish() {
  [ "$#" -eq 1 ] || { echo 'Usage: bash release.sh publish vMAJOR.MINOR.PATCH'; return 1; }
  [ "$(git branch --show-current)" = main ] || { echo 'Publish only from main.'; return 1; }
  command -v gh >/dev/null || { echo 'GitHub CLI is required only for publishing.'; return 1; }
  git fetch origin main
  [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || { echo 'Push main before publishing.'; return 1; }
  release_package || return 1
  if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null; then
    [ "$(git rev-parse "$TAG^{commit}")" = "$(git rev-parse HEAD)" ] || { echo 'Tag exists at another commit; never move release tags.'; return 1; }
  else git tag -a "$TAG" -m "Deploy Kit $TAG"; fi
  git push origin "refs/tags/$TAG"
  gh release create "$TAG" ".kit-release/$TAG/deploy-kit-$TAG.tar.gz" --verify-tag \
    --title "Deploy Kit $TAG" --notes-file ".kit-release/$TAG/notes.md"
}

case "$ACTION" in
  prepare) release_prepare;;
  package) release_package;;
  publish) [ "$#" -eq 2 ] || { echo 'An explicit stable version is required.'; exit 1; }; release_publish "$TAG";;
  *) echo 'Usage: bash release.sh prepare vX.Y.Z | package vX.Y.Z | publish vX.Y.Z';;
esac
