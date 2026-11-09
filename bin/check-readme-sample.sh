#!/usr/bin/env bash
#
# Check that the README's sample failure is what the pinned linter prints.
#
# The README quotes the linter's output on tests/fixtures/bad, but the wording
# is upstream's: a harness bump can change it and nothing here would notice.
# This runs the linter and compares, so the bump's own checks go red instead.
#
# Usage:
#   ./bin/check-readme-sample.sh <harness-dir>          # fail on a difference
#   ./bin/check-readme-sample.sh --write <harness-dir>  # rewrite the sample
#
# --write rewrites a reworded sample only. A finding added, dropped or
# renamed upstream is a change to what this action enforces, which a person
# describes: --write leaves the README alone and exits 2.
#
# Env:
#   README  the file holding the sample (default README.md beside this repo)

set -euo pipefail

WRITE=0
[ "${1:-}" = "--write" ] && { WRITE=1; shift; }
harness="${1:?usage: check-readme-sample.sh [--write] <harness-dir>}"
[ -d "$harness" ] || { echo "::error::No such harness directory: $harness"; exit 1; }
harness="$(cd "$harness" && pwd)"
cd "$(dirname "${BASH_SOURCE[0]}")/.."
readme="${README:-README.md}"

# The sample is the first fenced block under its heading, before the next one.
# A function, so the substitution below stays on one line: kcov reports the
# first line of a multi-line one as never run. The kcov-ignore markers keep
# the awk source out of a report that measures bash.
sample_of() {
    awk '
        # kcov-ignore-start
        /^## What a failure looks like/ { f = 1; next }
        f && /^## / { exit }
        f && /^```/ { if (b) exit; b = 1; next }
        b { print }
    ' "$1"
    # kcov-ignore-end
}

expected=$(sample_of "$readme")
[ -n "$expected" ] || { echo "::error::No sample failure found in $readme"; exit 1; }

# The bad fixtures exist to fail, so a zero exit is an error of its own.
set +e
actual=$(./bin/run-lint.sh "$harness" tests/fixtures/bad 2>&1)
status=$?
set -e
[ "$status" -ne 0 ] || { echo "::error::The linter passed tests/fixtures/bad"; exit 1; }

if [ "$expected" = "$actual" ]; then
    echo "The sample failure in $readme matches the pinned linter."
    exit 0
fi

if [ "$WRITE" -eq 0 ]; then
    echo "::error::The sample failure in $readme is not what the pinned linter prints"
    diff <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") || true
    exit 1
fi

# A fence inside the output would end the block early and turn the rest of it
# into README markup, so output carrying one is never written.
if printf '%s\n' "$actual" | grep -q '^```'; then
    echo "::error::The linter's output contains a code fence; not writing it into $readme"
    exit 1
fi

# A finding is what precedes a line's first colon (`⚠ mismatched`); the
# summary line has none, so its whole text is its key.
if [ "$(printf '%s\n' "$expected" | cut -d: -f1)" != "$(printf '%s\n' "$actual" | cut -d: -f1)" ]; then
    echo "::error::The linter's findings changed, not only their wording; update the sample in $readme by hand"
    diff <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") || true
    exit 2
fi

# Through temp files, because `sed -i` differs between BSD and GNU, and
# copied back rather than moved, so the README keeps its own mode.
sample=$(mktemp)
out=$(mktemp)
trap 'rm -f "$sample" "$out"' EXIT
printf '%s\n' "$actual" > "$sample"
awk -v sample="$sample" '
    # kcov-ignore-start
    /^## What a failure looks like/ { f = 1 }
    f && !done && /^```/ {
        if (!b) { b = 1; print; while ((getline line < sample) > 0) print line; next }
        b = 0; done = 1
    }
    b { next }
    { print }
' "$readme" > "$out"
# kcov-ignore-end
cat "$out" > "$readme"
echo "Rewrote the sample failure in $readme from the pinned linter."
