#!/usr/bin/env bash
# Prints the latest stable Talos Linux release on stdout (e.g. 1.14.6): the
# highest vX.Y.Z GitHub release that is neither a draft nor a pre-release
# (patches of older minors are published after newer ones, so /latest is not
# used). Runs in the upstream-watch reusable workflow.
set -euo pipefail
v=$(curl -fsSL -A 'openimages.cloud-watch' 'https://api.github.com/repos/siderolabs/talos/releases?per_page=50' \
  | jq -r '.[] | select(.draft == false and .prerelease == false) | .tag_name' \
  | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -1)
[[ -n "$v" ]] || { echo "::error::no stable Talos release found" >&2; exit 1; }
printf '%s\n' "${v#v}"
