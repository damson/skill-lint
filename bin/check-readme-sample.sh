#!/usr/bin/env bash
#
# Check that the README's sample failure is what the pinned linter prints.
#
# The README quotes the linter's output on tests/fixtures/bad, but the wording
# is upstream's: a harness bump can change it and nothing here would notice.
# This runs the linter and compares, so the bump's own checks go red instead.
#
# Usage: check-readme-sample.sh <harness-dir>
#
# Env:
#   README  the file holding the sample (default README.md beside this repo)

set -euo pipefail

harness="${1:?usage: check-readme-sample.sh <harness-dir>}"
cd "$(dirname "${BASH_SOURCE[0]}")/.."
readme="${README:-README.md}"

# The first fenced block under the heading is the sample.
expected=$(awk '
    /^## What a failure looks like/ { f = 1; next }
    f && /^```/ { if (b) exit; b = 1; next }
    b { print }
' "$readme")
[ -n "$expected" ] || { echo "::error::No sample failure found in $readme"; exit 1; }

# The bad fixtures exist to fail, so a zero exit is an error of its own.
set +e
actual=$(./bin/run-lint.sh "$harness" tests/fixtures/bad 2>&1)
status=$?
set -e
[ "$status" -ne 0 ] || { echo "::error::The linter passed tests/fixtures/bad"; exit 1; }

if [ "$expected" != "$actual" ]; then
    echo "::error::The sample failure in $readme is not what the pinned linter prints"
    diff <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") || true
    exit 1
fi
echo "The sample failure in $readme matches the pinned linter."
