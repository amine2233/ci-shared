#!/usr/bin/env bash
# Called by semantic-release (@semantic-release/exec successCmd) AFTER the
# release is published. Moves the short version tags so consumers can pin a
# major (e.g. `@1`) or minor (e.g. `@1.2`) and keep getting updates.
#
# Usage: post-release.sh <next version>

function log_info() {
  >&2 echo -e "[\\e[1;94mINFO\\e[0m] $*"
}

function log_error() {
  >&2 echo -e "[\\e[1;91mERROR\\e[0m] $*"
}

# check number of arguments
if [[ "$#" -lt 1 ]]; then
  log_error "Missing arguments"
  log_error "Usage: $0 <next version>"
  exit 1
fi

nextVer=$1
minorVer=${nextVer%.[0-9]*}        # 1.2.3 -> 1.2
majorVer=${nextVer%.[0-9]*.[0-9]*} # 1.2.3 -> 1

log_info "Creating minor version tag alias \\e[33;1m${minorVer}\\e[0m from $nextVer..."
git tag --force -a "$minorVer" "$nextVer" -m "Minor version alias (targets $nextVer)"

log_info "Creating major version tag alias \\e[33;1m${majorVer}\\e[0m from $nextVer..."
git tag --force -a "$majorVer" "$nextVer" -m "Major version alias (targets $nextVer)"

log_info "Pushing tags to origin..."
git push --force origin "$minorVer" "$majorVer"
