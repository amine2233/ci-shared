#!/usr/bin/env bash
# Called by semantic-release (@semantic-release/exec prepareCmd) BEFORE the
# release commit. Two things, committed by @semantic-release/git (.releaserc.json):
#   1. Pin EVERY `amine2233/ci-shared/...@<ref>` in files under examples/ to the
#      new version, so the copy-paste snippets always reference the release
#      (handles @main, @1, @1.2, @1.2.3, ... alike).
#   2. Bump the same refs in README.md from the current version to the new one.
#
# Usage: bumpversion.sh <current version> <next version> <release type>

function log_info() {
  >&2 echo -e "[\\e[1;94mINFO\\e[0m] $*"
}

function log_error() {
  >&2 echo -e "[\\e[1;91mERROR\\e[0m] $*"
}

# check number of arguments
if [[ "$#" -le 2 ]]; then
  log_error "Missing arguments"
  log_error "Usage: $0 <current version> <next version> <release type>"
  exit 1
fi

curVer=$1
nextVer=$2
relType=$3

# 1. Pin all examples to the freshly released version (runs on every release,
#    including the first, so `@main` placeholders become a real pinned ref).
log_info "Pinning examples to \\e[33;1m${nextVer}\\e[0m..."
while IFS= read -r f; do
  [[ -f "$f" ]] || continue
  # amine2233/ci-shared/<path>@<any ref> -> @<nextVer>
  sed -i.bak -E "s#(amine2233/ci-shared[^[:space:]\"']*@)[A-Za-z0-9._/-]+#\1${nextVer}#g" "$f"
  rm -f "$f.bak"
  log_info "  updated ${f}"
done < <(find examples -type f 2>/dev/null | sort)

# 2. Bump the current version refs in the README (skipped on the first release).
if [[ -n "$curVer" ]]; then
  log_info "Bump README refs from \\e[33;1m${curVer}\\e[0m to \\e[33;1m${nextVer}\\e[0m (release type: $relType)..."
  curVerEsc=$(printf '%s' "$curVer" | sed 's/\./\\./g')
  sed -i.bak -E "s#(amine2233/ci-shared[^[:space:]\"']*@)${curVerEsc}([^[:alnum:].]|\$)#\1${nextVer}\2#g" README.md
  rm -f README.md.bak
else
  log_info "First release (\\e[33;1m${nextVer}\\e[0m): examples pinned; README left untouched."
fi
