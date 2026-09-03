#!/usr/bin/env bats
#
# The action's two scripts, tested against local fixtures — no network.
# Each failure-path test exists because the check has been seen to fail:
# break the input, watch red, fix.

setup() {
  TMP="$(mktemp -d)"
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
}

teardown() {
  rm -rf "$TMP"
}

make_fixture_remote() {
  # A local harness-shaped repo with a lint script that reports its inputs.
  git init -q "$TMP/remote"
  mkdir -p "$TMP/remote/bin"
  cat > "$TMP/remote/bin/validate-skills.sh" <<'SH'
#!/usr/bin/env bash
echo "linted: $1"
SH
  chmod +x "$TMP/remote/bin/validate-skills.sh"
  git -C "$TMP/remote" add -A
  git -C "$TMP/remote" -c user.email=t@t -c user.name=t commit -qm fixture
  FIXTURE_SHA="$(git -C "$TMP/remote" rev-parse HEAD)"
}

@test "fetch-harness checks out the exact requested commit" {
  make_fixture_remote
  run "$REPO_ROOT/bin/fetch-harness.sh" "$FIXTURE_SHA" "$TMP/dest" "$TMP/remote"
  [ "$status" -eq 0 ]
  [ -x "$TMP/dest/bin/validate-skills.sh" ]
  [ "$(git -C "$TMP/dest" rev-parse HEAD)" = "$FIXTURE_SHA" ]
}

@test "fetch-harness fails loudly on a ref the remote does not have" {
  make_fixture_remote
  run "$REPO_ROOT/bin/fetch-harness.sh" \
    0000000000000000000000000000000000000000 "$TMP/dest" "$TMP/remote"
  [ "$status" -ne 0 ]
}

@test "fetch-harness replaces a stale destination instead of appending" {
  make_fixture_remote
  mkdir -p "$TMP/dest"
  touch "$TMP/dest/stale-file"
  run "$REPO_ROOT/bin/fetch-harness.sh" "$FIXTURE_SHA" "$TMP/dest" "$TMP/remote"
  [ "$status" -eq 0 ]
  [ ! -e "$TMP/dest/stale-file" ]
}

@test "the default harness-ref in action.yml is what fetch-harness receives" {
  # The action wires inputs.harness-ref straight through; assert the default
  # parses out of action.yml as a full 40-char SHA so a truncated edit fails.
  ref="$(awk '/harness-ref:/{f=1} f && /default:/{print $2; exit}' "$REPO_ROOT/action.yml")"
  [[ "$ref" =~ ^[0-9a-f]{40}$ ]]
}

@test "run-lint hands the harness linter the skills path" {
  make_fixture_remote
  "$REPO_ROOT/bin/fetch-harness.sh" "$FIXTURE_SHA" "$TMP/dest" "$TMP/remote"
  mkdir -p "$TMP/skills"
  run "$REPO_ROOT/bin/run-lint.sh" "$TMP/dest" "$TMP/skills"
  [ "$status" -eq 0 ]
  [[ "$output" == *"linted: $TMP/skills"* ]]
}

@test "run-lint refuses a missing skills directory with a readable error" {
  make_fixture_remote
  "$REPO_ROOT/bin/fetch-harness.sh" "$FIXTURE_SHA" "$TMP/dest" "$TMP/remote"
  run "$REPO_ROOT/bin/run-lint.sh" "$TMP/dest" "$TMP/no-such-dir"
  [ "$status" -ne 0 ]
  [[ "$output" == *"No such directory"* ]]
}

@test "run-lint propagates the linter's failure exit code" {
  make_fixture_remote
  cat > "$TMP/remote/bin/validate-skills.sh" <<'SH'
#!/usr/bin/env bash
echo "problems found"
exit 1
SH
  git -C "$TMP/remote" add -A
  git -C "$TMP/remote" -c user.email=t@t -c user.name=t commit -qm fail-fixture
  sha="$(git -C "$TMP/remote" rev-parse HEAD)"
  "$REPO_ROOT/bin/fetch-harness.sh" "$sha" "$TMP/dest" "$TMP/remote"
  mkdir -p "$TMP/skills"
  run "$REPO_ROOT/bin/run-lint.sh" "$TMP/dest" "$TMP/skills"
  [ "$status" -eq 1 ]
}
