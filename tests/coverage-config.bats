#!/usr/bin/env bats
#
# The coverage workflow's wiring, not its output. These two claims are the
# kind that rot silently: nothing goes red when they stop holding, the badge
# just quietly describes a branch nobody measures and the release pull request
# quietly loses its delta. Asserting them is the only thing that notices.

setup() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
}

# The branch list from the workflow's `on: push:` block. Parsed rather than
# grepped for `branches:`, because `on:` is not the only block that has one.
push_branches() {
  awk '
    /^on:[[:space:]]*$/            { in_on = 1; next }
    in_on && /^[^[:space:]#]/      { in_on = 0 }
    in_on && /^[[:space:]]+push:/  { in_push = 1; next }
    in_push && /^[[:space:]]{2}[^[:space:]#]/ { in_push = 0 }
    in_push && /branches:/ {
      sub(/^[^[]*\[/, ""); sub(/\].*$/, ""); gsub(/[[:space:]]/, "")
      print; exit
    }
  ' "$REPO_ROOT/.github/workflows/coverage.yml"
}

@test "coverage workflow: the trunk is measured on push" {
  # Codecov diffs a pull request against a report for its BASE commit, and
  # every pull request targets main. With no report there, each one reads a
  # bare figure with no delta.
  local measured
  measured=$(push_branches)
  [ -n "$measured" ]
  printf '%s\n' "$measured" | tr ',' '\n' | grep -qx main
}

@test "coverage badge: the README names a branch the workflow measures" {
  # A badge pointing at an unmeasured branch renders "unknown", and nobody
  # notices, because the README is not what CI looks at. Pin the pair rather
  # than the literal branch: what matters is that the two agree.
  local branch measured
  branch=$(grep -oE 'codecov\.io/gh/[^)]*/branch/[a-zA-Z0-9._/-]+/graph' "$REPO_ROOT/README.md" \
    | head -1 | sed -E 's|.*/branch/([^/]+)/graph|\1|')
  [ -n "$branch" ]
  measured=$(push_branches)
  [ -n "$measured" ]
  printf '%s\n' "$measured" | tr ',' '\n' | grep -qx "$branch"
}

@test "coverage workflow: a superseded push to main is not cancelled" {
  # cancel-in-progress on a push to main takes the base upload with
  # it, and Codecov then has nothing to diff the next pull request against.
  # Superseding a pull request run is fine and is the point of the setting, so
  # the value has to be conditional rather than false.
  local value
  value=$(awk '
    /^concurrency:/                 { in_c = 1; next }
    in_c && /^[^[:space:]#]/        { in_c = 0 }
    in_c && /cancel-in-progress:/   { sub(/^[^:]*:[[:space:]]*/, ""); print; exit }
  ' "$REPO_ROOT/.github/workflows/coverage.yml")
  [ -n "$value" ]
  printf '%s' "$value" | grep -q "github.event_name == 'pull_request'"
}

@test "coverage workflow: kcov leaves out the regions bin/ marks" {
  # Without the flag the markers are inert comments, and every embedded awk
  # program reads as bash that never ran, a number no test can move.
  grep -q -- '--exclude-region=kcov-ignore-start:kcov-ignore-end' \
    "$REPO_ROOT/.github/workflows/coverage.yml"
}

@test "coverage markers: every region in bin/ opens before it closes, once" {
  # An unclosed start takes the rest of its file out of the report, and a
  # stray end does nothing, so both read as coverage that was never there.
  local f bad=""
  for f in "$REPO_ROOT"/bin/*.sh; do
    awk '
      /kcov-ignore-start/ { if (open) bad = 1; open = 1 }
      /kcov-ignore-end/   { if (!open) bad = 1; open = 0 }
      END { exit (bad || open) ? 1 : 0 }
    ' "$f" || bad="$bad $(basename "$f")"
  done
  [ -z "$bad" ]
}
