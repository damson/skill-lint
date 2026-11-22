#!/usr/bin/env bash
#
# Run the harness skill linter against a skills tree.
#
# Usage: run-lint.sh <harness-dir> <skills-path>
set -euo pipefail

harness="${1:?usage: run-lint.sh <harness-dir> <skills-path>}"
path="${2:?usage: run-lint.sh <harness-dir> <skills-path>}"

[ -d "$path" ] || { echo "::error::No such directory: $path"; exit 1; }
"$harness/bin/validate-skills.sh" "$path"
