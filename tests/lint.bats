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

# --- Watching the upstream pin ----------------------------------------------
# The pin is what makes this action trustworthy and what makes it rot: a stale
# pin behaves exactly like a current one. These cover the comparison, not the
# pull request it leads to.

make_action_file() {
  # An action.yml shaped like the real one, pinned to $1.
  printf 'inputs:\n  harness-ref:\n    description: x\n    required: false\n    default: %s\n' "$1" > "$TMP/action.yml"
}

# A `gh` that answers the two calls the script makes: the latest release's tag,
# and the commit that tag names.
make_gh() {
  local tag="$1" sha="$2"
  mkdir -p "$TMP/bin"
  cat > "$TMP/bin/gh" <<EOF
#!/usr/bin/env bash
case "\$*" in
  *releases/latest*) printf '%s\n' "$tag" ;;
  *commits/*)        printf '%s\n' "$sha" ;;
  *)                 exit 1 ;;
esac
EOF
  chmod +x "$TMP/bin/gh"
}

@test "bump: an unchanged pin is a quiet no-op, not a rewrite" {
  local sha="1111111111111111111111111111111111111111"
  make_action_file "$sha"
  make_gh "v9.9.9" "$sha"
  run env PATH="$TMP/bin:$PATH" ACTION_FILE="$TMP/action.yml" GITHUB_OUTPUT="$TMP/out" \
    "$REPO_ROOT/bin/bump-harness-pin.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Nothing to do"* ]]
  grep -q "changed=false" "$TMP/out"
  grep -q "default: $sha" "$TMP/action.yml"
}

@test "bump: a moved pin is rewritten and reported" {
  local old="1111111111111111111111111111111111111111"
  local new="2222222222222222222222222222222222222222"
  make_action_file "$old"
  make_gh "v1.5.0" "$new"
  run env PATH="$TMP/bin:$PATH" ACTION_FILE="$TMP/action.yml" GITHUB_OUTPUT="$TMP/out" \
    "$REPO_ROOT/bin/bump-harness-pin.sh"
  [ "$status" -eq 0 ]
  grep -q "default: $new" "$TMP/action.yml"
  grep -q "changed=true" "$TMP/out"
  grep -q "tag=v1.5.0" "$TMP/out"
}

@test "bump: --dry-run says what would move and touches nothing" {
  local old="1111111111111111111111111111111111111111"
  make_action_file "$old"
  make_gh "v1.5.0" "2222222222222222222222222222222222222222"
  run env PATH="$TMP/bin:$PATH" ACTION_FILE="$TMP/action.yml" \
    "$REPO_ROOT/bin/bump-harness-pin.sh" --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Pin moves"* ]]
  grep -q "default: $old" "$TMP/action.yml"
}

@test "bump: anything that is not a full commit sha is refused" {
  # The pin's whole value is naming one immutable commit. A tag, a short sha or
  # an API error string reaching the file would keep the shape and lose that.
  make_action_file "1111111111111111111111111111111111111111"
  make_gh "v1.5.0" "v1.5.0"
  run env PATH="$TMP/bin:$PATH" ACTION_FILE="$TMP/action.yml" \
    "$REPO_ROOT/bin/bump-harness-pin.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a full commit sha"* ]]
  grep -q "default: 1111111111111111111111111111111111111111" "$TMP/action.yml"
}

@test "bump: an upstream that cannot be read is an error, not a silent pass" {
  # The failure this prevents: the watcher reports success every night while
  # answering nothing, and the pin quietly ages.
  make_action_file "1111111111111111111111111111111111111111"
  mkdir -p "$TMP/bin"
  printf '#!/usr/bin/env bash\nexit 1\n' > "$TMP/bin/gh"
  chmod +x "$TMP/bin/gh"
  run env PATH="$TMP/bin:$PATH" ACTION_FILE="$TMP/action.yml" \
    "$REPO_ROOT/bin/bump-harness-pin.sh"
  [ "$status" -ne 0 ]
}

@test "bump workflow: the pull request is opened by a person and gated on a real change" {
  # Two failures this pins. A pull request GitHub attributes to Actions raises
  # no checks, and a pin bump with no checks is the one change nobody can
  # review. And a workflow that pushes on every run turns a quiet no-op into a
  # daily empty pull request.
  local wf="$REPO_ROOT/.github/workflows/harness-pin.yml"
  run python3 -c "
import sys, yaml
steps = yaml.safe_load(open(sys.argv[1]))['jobs']['bump']['steps']
named = {s.get('name'): s for s in steps}
checkout = [s for s in steps if str(s.get('uses','')).startswith('actions/checkout')][0]
bad = []
if 'PIN_BUMP_TOKEN' not in str(checkout.get('with', {})):
    bad.append('checkout pushes with the default token')
opener = named['Open or refresh the pull request']
if 'PIN_BUMP_TOKEN' not in str(opener.get('env', {})):
    bad.append('the PR is opened with the default token')
for n in ('Run the suite at the new pin', 'Open or refresh the pull request'):
    cond = str(named[n].get('if', ''))
    if 'changed' not in cond or 'success()' not in cond:
        bad.append(n + ' is not gated on success() and a real change')
if bad:
    print('; '.join(bad)); sys.exit(1)
" "$wf"
  [ "$status" -eq 0 ]
}
