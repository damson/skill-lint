#!/usr/bin/env bash
#
# Fetch the harness at an exact commit into a target directory.
#
# Usage: fetch-harness.sh <ref> <dest-dir> [repo-url]
#
# The ref is pinned by the caller so a harness change cannot silently change
# what the action enforces. The repo-url override exists for the tests, which
# fetch from a local fixture remote instead of the network.
set -euo pipefail

ref="${1:?usage: fetch-harness.sh <ref> <dest-dir> [repo-url]}"
dest="${2:?usage: fetch-harness.sh <ref> <dest-dir> [repo-url]}"
repo="${3:-https://github.com/damson/agent-config-harness}"

rm -rf "$dest"
git init -q "$dest"
git -C "$dest" fetch -q --depth 1 "$repo" "$ref"
git -C "$dest" checkout -q FETCH_HEAD
