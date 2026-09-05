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

@test "coverage workflow: both long-lived branches are measured on push" {
  # Codecov diffs a pull request against a report for its BASE commit. develop
  # is the base of every feature pull request; main is the base of the release,
  # and with no report there the release reads a bare figure with no delta, on
  # the one pull request whose subject is how far the release moves it.
  local measured
  measured=$(push_branches)
  [ -n "$measured" ]
  printf '%s\n' "$measured" | tr ',' '\n' | grep -qx develop
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

@test "coverage workflow: a superseded push to a long-lived branch is not cancelled" {
  # cancel-in-progress on a push to develop or main takes the base upload with
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
