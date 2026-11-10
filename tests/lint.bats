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

# --- The README's sample failure --------------------------------------------
# The README quotes the linter's wording, which upstream owns. A harness whose
# linter prints known lines stands in for the real one, on stderr as the real
# one does, and over two lines so a sample is never only its first.

SAMPLE=$'⚠ a: wrong\n✗ 1 problem(s)'
REWORDED=$'⚠ a: reworded\n✗ 1 problem(s)'

make_printing_harness() {
  # A harness whose linter prints $1 to stderr and exits $2.
  mkdir -p "$TMP/harness/bin"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "%s" >&2\nexit %s\n' "$1" "$2" \
    > "$TMP/harness/bin/validate-skills.sh"
  chmod +x "$TMP/harness/bin/validate-skills.sh"
}

make_readme() {
  printf '# x\n\n## What a failure looks like\n\nIntro.\n\n```\n%s\n```\n\n## Inputs\n\n```\nnot the sample\n```\n' "$1" \
    > "$TMP/README.md"
}

@test "readme sample: a sample matching the linter's output passes" {
  make_printing_harness "$SAMPLE" 1
  make_readme "$SAMPLE"
  README="$TMP/README.md" run "$REPO_ROOT/bin/check-readme-sample.sh" "$TMP/harness"
  [ "$status" -eq 0 ]
}

@test "readme sample: a relative harness path resolves from where it was given" {
  make_printing_harness "$SAMPLE" 1
  make_readme "$SAMPLE"
  cd "$TMP"
  README="$TMP/README.md" run "$REPO_ROOT/bin/check-readme-sample.sh" harness
  [ "$status" -eq 0 ]
}

@test "readme sample: reworded linter output fails and shows the difference" {
  make_printing_harness "$REWORDED" 1
  make_readme "$SAMPLE"
  README="$TMP/README.md" run "$REPO_ROOT/bin/check-readme-sample.sh" "$TMP/harness"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not what the pinned linter prints"*"reworded"* ]]
}

@test "readme sample: a linter that passes the bad fixtures is an error" {
  make_printing_harness "$SAMPLE" 0
  make_readme "$SAMPLE"
  README="$TMP/README.md" run "$REPO_ROOT/bin/check-readme-sample.sh" "$TMP/harness"
  [ "$status" -eq 1 ]
  [[ "$output" == *"passed tests/fixtures/bad"* ]]
}

@test "readme sample: a README with no sample is an error, not a match" {
  make_printing_harness "$SAMPLE" 1
  printf '# x\n\n## Inputs\n' > "$TMP/README.md"
  README="$TMP/README.md" run "$REPO_ROOT/bin/check-readme-sample.sh" "$TMP/harness"
  [ "$status" -eq 1 ]
  [[ "$output" == *"No sample failure found"* ]]
}

@test "readme sample: output quoted under a later heading is not the sample" {
  make_printing_harness "$SAMPLE" 1
  printf '# x\n\n## What a failure looks like\n\nNo block.\n\n## Inputs\n\n```\n%s\n```\n' "$SAMPLE" \
    > "$TMP/README.md"
  README="$TMP/README.md" run "$REPO_ROOT/bin/check-readme-sample.sh" "$TMP/harness"
  [ "$status" -eq 1 ]
  [[ "$output" == *"No sample failure found"* ]]
}

@test "readme sample: --write puts the linter's output in the sample and nowhere else" {
  make_printing_harness "$REWORDED" 1
  make_readme "$REWORDED"
  cp "$TMP/README.md" "$TMP/want.md"
  make_readme "$SAMPLE"
  README="$TMP/README.md" run "$REPO_ROOT/bin/check-readme-sample.sh" --write "$TMP/harness"
  [ "$status" -eq 0 ]
  run diff "$TMP/want.md" "$TMP/README.md"
  [ "$status" -eq 0 ]
}

@test "readme sample: --write refuses output carrying a code fence" {
  mkdir -p "$TMP/harness/bin"
  cat > "$TMP/harness/bin/validate-skills.sh" <<'SH'
#!/usr/bin/env bash
printf '%s\n' '⚠ a: wrong' '```' '# injected heading' >&2
exit 1
SH
  chmod +x "$TMP/harness/bin/validate-skills.sh"
  make_readme "$SAMPLE"
  cp "$TMP/README.md" "$TMP/want.md"
  README="$TMP/README.md" run "$REPO_ROOT/bin/check-readme-sample.sh" --write "$TMP/harness"
  [ "$status" -eq 1 ]
  cmp -s "$TMP/want.md" "$TMP/README.md"
  [[ "$output" == *"contains a code fence"* ]]
}

@test "readme sample: --write leaves a dropped finding for a person, exit 2" {
  make_printing_harness "✗ 0 problem(s)" 1
  make_readme "$SAMPLE"
  cp "$TMP/README.md" "$TMP/want.md"
  README="$TMP/README.md" run "$REPO_ROOT/bin/check-readme-sample.sh" --write "$TMP/harness"
  [ "$status" -eq 2 ]
  cmp -s "$TMP/want.md" "$TMP/README.md"
  [[ "$output" == *"findings changed, not only their wording"* ]]
}

@test "readme sample: --write leaves a renamed finding for a person, exit 2" {
  make_printing_harness $'⚠ b: wrong\n✗ 1 problem(s)' 1
  make_readme "$SAMPLE"
  cp "$TMP/README.md" "$TMP/want.md"
  README="$TMP/README.md" run "$REPO_ROOT/bin/check-readme-sample.sh" --write "$TMP/harness"
  [ "$status" -eq 2 ]
  cmp -s "$TMP/want.md" "$TMP/README.md"
}

@test "readme sample: --write keeps the README's file mode" {
  make_printing_harness "$REWORDED" 1
  make_readme "$SAMPLE"
  chmod 0644 "$TMP/README.md"
  README="$TMP/README.md" run "$REPO_ROOT/bin/check-readme-sample.sh" --write "$TMP/harness"
  [ "$status" -eq 0 ]
  [ "$(ls -l "$TMP/README.md" | cut -c1-10)" = "-rw-r--r--" ]
}

@test "readme sample: --write leaves a matching README byte for byte" {
  make_printing_harness "$SAMPLE" 1
  make_readme "$SAMPLE"
  cp "$TMP/README.md" "$TMP/want.md"
  README="$TMP/README.md" run "$REPO_ROOT/bin/check-readme-sample.sh" --write "$TMP/harness"
  [ "$status" -eq 0 ]
  run cmp "$TMP/want.md" "$TMP/README.md"
  [ "$status" -eq 0 ]
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
  # $3, when given, is the upstream's tags listing as the API returns it; the
  # stub applies the script's own --jq filter to it with the real jq, so the
  # selection is exercised and not assumed. Without it the lookup fails, as it
  # does for an upstream that cannot be read.
  local tag="$1" sha="$2"
  [ -n "${3:-}" ] && printf '%s' "$3" > "$TMP/tags.json"
  mkdir -p "$TMP/bin"
  cat > "$TMP/bin/gh" <<EOF
#!/usr/bin/env bash
filter=""; prev=""
for a in "\$@"; do [ "\$prev" = "--jq" ] && filter="\$a"; prev="\$a"; done
case "\$*" in
  *releases/latest*) printf '%s\n' "$tag" ;;
  *commits/*)        printf '%s\n' "$sha" ;;
  *repos/*/tags*)    [ -f "$TMP/tags.json" ] || exit 1; jq -r "\$filter" "$TMP/tags.json" ;;
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
  printf '%s\n' "$output" | grep -qF "Nothing to do"
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

@test "bump: a move inside one major version is reported as such" {
  make_action_file "1111111111111111111111111111111111111111"
  # The floating v1 and another commit's v2.0.0 sit beside the pin's own
  # v1.7.1; only the full tag on the pinned commit decides.
  make_gh "v1.8.0" "2222222222222222222222222222222222222222" \
    '[{"name":"v2.0.0","commit":{"sha":"3333333333333333333333333333333333333333"}},{"name":"v1","commit":{"sha":"1111111111111111111111111111111111111111"}},{"name":"v1.7.1","commit":{"sha":"1111111111111111111111111111111111111111"}}]'
  run env PATH="$TMP/bin:$PATH" ACTION_FILE="$TMP/action.yml" GITHUB_OUTPUT="$TMP/out" \
    "$REPO_ROOT/bin/bump-harness-pin.sh"
  [ "$status" -eq 0 ]
  grep -qx "same_major=true" "$TMP/out"
}

@test "bump: a new major version is not a regular bump" {
  make_action_file "1111111111111111111111111111111111111111"
  make_gh "v2.0.0" "2222222222222222222222222222222222222222" '[{"name":"v1.7.1","commit":{"sha":"1111111111111111111111111111111111111111"}}]'
  run env PATH="$TMP/bin:$PATH" ACTION_FILE="$TMP/action.yml" GITHUB_OUTPUT="$TMP/out" \
    "$REPO_ROOT/bin/bump-harness-pin.sh"
  [ "$status" -eq 0 ]
  grep -qx "same_major=false" "$TMP/out"
}

@test "bump: release tags of two majors on the pin are an unknown" {
  make_action_file "1111111111111111111111111111111111111111"
  make_gh "v1.8.0" "2222222222222222222222222222222222222222" \
    '[{"name":"v1.7.1","commit":{"sha":"1111111111111111111111111111111111111111"}},{"name":"v2.0.0","commit":{"sha":"1111111111111111111111111111111111111111"}}]'
  run env PATH="$TMP/bin:$PATH" ACTION_FILE="$TMP/action.yml" GITHUB_OUTPUT="$TMP/out" \
    "$REPO_ROOT/bin/bump-harness-pin.sh"
  [ "$status" -eq 0 ]
  grep -qx "same_major=false" "$TMP/out"
}

@test "bump: a pin on only a floating or pre-release tag is not the same major" {
  # v1 and v1.8.0-rc.1 carry a major number without being a release; a pin
  # that sits on nothing else is an unknown, which a person reviews.
  make_action_file "1111111111111111111111111111111111111111"
  make_gh "v1.8.0" "2222222222222222222222222222222222222222" '[{"name":"v1","commit":{"sha":"1111111111111111111111111111111111111111"}},{"name":"v1.8.0-rc.1","commit":{"sha":"1111111111111111111111111111111111111111"}}]'
  run env PATH="$TMP/bin:$PATH" ACTION_FILE="$TMP/action.yml" GITHUB_OUTPUT="$TMP/out" \
    "$REPO_ROOT/bin/bump-harness-pin.sh"
  [ "$status" -eq 0 ]
  grep -qx "same_major=false" "$TMP/out"
}

@test "bump: a pin whose tag cannot be found counts as a new major" {
  # The unknown case has to reach a person: a pin on no tag, or a tags lookup
  # that fails, is never taken as the same major. It still bumps.
  make_action_file "1111111111111111111111111111111111111111"
  make_gh "v1.8.0" "2222222222222222222222222222222222222222"
  run env PATH="$TMP/bin:$PATH" ACTION_FILE="$TMP/action.yml" GITHUB_OUTPUT="$TMP/out" \
    "$REPO_ROOT/bin/bump-harness-pin.sh"
  [ "$status" -eq 0 ]
  grep -q "default: 2222222222222222222222222222222222222222" "$TMP/action.yml"
  grep -qx "same_major=false" "$TMP/out"
}

@test "bump: --dry-run says what would move and touches nothing" {
  local old="1111111111111111111111111111111111111111"
  make_action_file "$old"
  make_gh "v1.5.0" "2222222222222222222222222222222222222222"
  run env PATH="$TMP/bin:$PATH" ACTION_FILE="$TMP/action.yml" \
    "$REPO_ROOT/bin/bump-harness-pin.sh" --dry-run
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF "Pin moves"
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
  printf '%s\n' "$output" | grep -qF "not a full commit sha"
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

@test "bump: a release whose tag resolves to no commit is an error" {
  # The release lookup answers and the commit lookup does not: a tag deleted
  # or not yet replicated. Pinning nothing is the only safe outcome.
  make_action_file "1111111111111111111111111111111111111111"
  mkdir -p "$TMP/bin"
  printf '#!/usr/bin/env bash\ncase "$*" in *releases/latest*) echo v9.9.9 ;; *) exit 1 ;; esac\n' \
    > "$TMP/bin/gh"
  chmod +x "$TMP/bin/gh"
  run env PATH="$TMP/bin:$PATH" ACTION_FILE="$TMP/action.yml" \
    "$REPO_ROOT/bin/bump-harness-pin.sh"
  [ "$status" -eq 1 ]
  grep -q "default: 1111111111111111111111111111111111111111" "$TMP/action.yml"
  [[ "$output" == *"Could not resolve v9.9.9 to a commit"* ]]
}

@test "bump: a rewrite that did not take is reported, not announced" {
  # A sed whose pattern matches nothing exits 0 and leaves the old pin, so
  # the script checks the file rather than sed's status. A stand-in that
  # copies its input unchanged is that sed.
  make_action_file "1111111111111111111111111111111111111111"
  make_gh "v9.9.9" "2222222222222222222222222222222222222222"
  printf '#!/usr/bin/env bash\ncat "$2"\n' > "$TMP/bin/sed"
  chmod +x "$TMP/bin/sed"
  run env PATH="$TMP/bin:$PATH" ACTION_FILE="$TMP/action.yml" \
    "$REPO_ROOT/bin/bump-harness-pin.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"did not take"* ]]
}

@test "bump workflow: the pull request is opened by a person and gated on a real change" {
  # Four failures this pins. A pull request GitHub attributes to Actions
  # raises no checks, and a pin bump with no checks is the one change nobody
  # can review. A workflow that pushes on every run turns a quiet no-op into a
  # daily empty pull request. A force-push erases a person's fix to the bump
  # on the next run. A bump that leaves the README sample behind fails its
  # own pull request. And a bump that changes a finding has to open anyway,
  # or nobody is asked to describe it. What the open and auto-merge steps do
  # is tested by running them, below.
  local wf="$REPO_ROOT/.github/workflows/harness-pin.yml"
  run python3 -c "
import sys, yaml
steps = yaml.safe_load(open(sys.argv[1]))['jobs']['bump']['steps']
named = {s.get('name'): s for s in steps}
checkout = [s for s in steps if str(s.get('uses','')).startswith('actions/checkout')][0]
bad = []
if 'PIN_BUMP_TOKEN' not in str(checkout.get('with', {})):
    bad.append('checkout pushes with the default token')
if checkout.get('with', {}).get('ref') != 'main':
    bad.append('the bump is cut from a branch other than the trunk')
opener = named['Open the pull request']
if 'PIN_BUMP_TOKEN' not in str(opener.get('env', {})):
    bad.append('the PR is opened with the default token')
if '--force' in str(opener.get('run', '')):
    bad.append('the PR branch is force-pushed over whatever a person added to it')
run_text = str(opener.get('run', ''))
if run_text.count('--base main') != run_text.count('gh pr list') + run_text.count('gh pr create'):
    bad.append('the bump pull request does not target the trunk')
if opener.get('id') != 'open':
    bad.append('the open step has no id, so whether it opened anything reaches nothing')
if 'README.md' not in str(opener.get('run', '')):
    bad.append('the rewritten README sample is not committed')
rewrite = named['Rewrite the README\x27s sample failure at the new pin']
if rewrite.get('id') != 'readme':
    bad.append('the README step has no id, so its findings verdict reaches nothing')
auto = named.get('Let a regular bump merge itself once CI passes', {})
want = 'success() && steps.open.outputs.created == \x27true\x27 && steps.bump.outputs.same_major == \x27true\x27 && steps.readme.outputs.findings_unchanged == \x27true\x27'
if str(auto.get('if', '')) != want:
    bad.append('auto-merge is not gated on exactly: ' + want)
for step in (opener, auto):
    text = str(step.get('run', ''))
    if text.count('gh pr list') != text.count('--limit 1000'):
        bad.append(step.get('name') + ' lists pull requests within the default page of 30')
if '-eq 2' not in str(rewrite.get('run', '')):
    bad.append('a changed finding stops the bump instead of opening it for a person')
for n in ('Run the suite at the new pin', 'Rewrite the README\x27s sample failure at the new pin', 'Open the pull request'):
    cond = str(named[n].get('if', ''))
    if 'changed' not in cond or 'success()' not in cond:
        bad.append(n + ' is not gated on success() and a real change')
if bad:
    print('; '.join(bad)); sys.exit(1)
" "$wf"
  [ "$status" -eq 0 ]
}

# --- The bump workflow's open and auto-merge steps, run --------------------
# These steps decide whether anything merges into main with no person
# involved, so they are run rather than read: each test extracts a step's
# shell from the workflow and runs it against a gh and a git that answer from
# fixtures and log what they were asked to do. gh applies the step's own
# --jq filter with the real jq, so the selections are exercised too.

BUMP_SHA="4444444444444444444444444444444444444444"

step_script() {
  python3 -c "
import sys, yaml
steps = yaml.safe_load(open(sys.argv[1]))['jobs']['bump']['steps']
print([s for s in steps if s.get('name') == sys.argv[2]][0]['run'])
" "$REPO_ROOT/.github/workflows/harness-pin.yml" "$1" > "$TMP/step.sh"
}

make_workflow_tools() {
  # Fixtures, each optional: open.json and closed.json answer gh pr list by
  # --state, rules.json answers the rules endpoint, branch_sha is the bump
  # branch's commit on origin (absent: the branch does not exist).
  mkdir -p "$TMP/wfbin"
  cat > "$TMP/wfbin/gh" <<EOF
#!/usr/bin/env bash
printf 'gh %s\n' "\$*" >> "$TMP/calls.log"
filter=""; prev=""
for a in "\$@"; do [ "\$prev" = "--jq" ] && filter="\$a"; prev="\$a"; done
answer() { [ -f "\$1" ] || { echo '[]' > "\$1"; }; jq -r "\$filter" "\$1"; }
case "\$*" in
  "pr list"*"--state open"*)   answer "$TMP/open.json" ;;
  "pr list"*"--state closed"*) answer "$TMP/closed.json" ;;
  "api"*"rules/branches/main"*) answer "$TMP/rules.json" ;;
  "pr create"*) echo "https://github.com/damson/skill-lint/pull/99" ;;
  "pr merge"*|"pr comment"*) : ;;
  *) echo "unexpected gh call: \$*" >&2; exit 1 ;;
esac
EOF
  cat > "$TMP/wfbin/git" <<EOF
#!/usr/bin/env bash
printf 'git %s\n' "\$*" >> "$TMP/calls.log"
case "\$*" in
  ls-remote*)
    [ -f "$TMP/branch_sha" ] || exit 2
    printf '%s\trefs/heads/chore/harness-pin-v1.8.0\n' "\$(cat "$TMP/branch_sha")" ;;
  *) : ;;
esac
EOF
  chmod +x "$TMP/wfbin/gh" "$TMP/wfbin/git"
  : > "$TMP/calls.log"
  : > "$TMP/out"
}

run_step() {
  run env PATH="$TMP/wfbin:$PATH" GITHUB_OUTPUT="$TMP/out" GITHUB_REPOSITORY=damson/skill-lint \
    GH_TOKEN=x TAG=v1.8.0 CURRENT=1111111111111111111111111111111111111111 LATEST="$BUMP_SHA" \
    SAME_MAJOR=true FINDINGS_UNCHANGED=true bash "$TMP/step.sh"
}

ALL_REQUIRED='[{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"tests","integration_id":15368},{"context":"good-tree-passes","integration_id":15368},{"context":"bad-tree-must-fail","integration_id":15368}]}}]'

@test "bump workflow, open: a new release opens one pull request from this repo" {
  make_workflow_tools
  step_script "Open the pull request"
  run_step
  [ "$status" -eq 0 ]
  grep -q '^git push -u origin chore/harness-pin-v1.8.0$' "$TMP/calls.log"
  grep -q '^gh pr create --base main --head chore/harness-pin-v1.8.0' "$TMP/calls.log"
  grep -qx 'created=true' "$TMP/out"
}

@test "bump workflow, open: an open pull request is left alone, body and hold included" {
  make_workflow_tools
  echo '[{"number":7,"isCrossRepository":false}]' > "$TMP/open.json"
  echo "$BUMP_SHA" > "$TMP/branch_sha"
  step_script "Open the pull request"
  run_step
  [ "$status" -eq 0 ]
  [ "$(grep -cE '^gh pr (create|edit|merge)|^git push' "$TMP/calls.log")" -eq 0 ]
  grep -qx 'created=false' "$TMP/out"
}

@test "bump workflow, open: a pull request closed unmerged declines the release for good" {
  make_workflow_tools
  echo '[{"number":7,"isCrossRepository":false,"mergedAt":null}]' > "$TMP/closed.json"
  echo "$BUMP_SHA" > "$TMP/branch_sha"
  step_script "Open the pull request"
  run_step
  [ "$status" -eq 0 ]
  [ "$(grep -cE '^gh pr (create|edit|merge)|^git push' "$TMP/calls.log")" -eq 0 ]
  grep -qx 'created=false' "$TMP/out"
}

@test "bump workflow, open: a fork's pull request of the same branch name is not the bump" {
  make_workflow_tools
  echo '[{"number":8,"isCrossRepository":true}]' > "$TMP/open.json"
  echo '[{"number":9,"isCrossRepository":true,"mergedAt":null}]' > "$TMP/closed.json"
  step_script "Open the pull request"
  run_step
  [ "$status" -eq 0 ]
  grep -q '^gh pr create --base main --head chore/harness-pin-v1.8.0' "$TMP/calls.log"
  grep -qx 'created=true' "$TMP/out"
}

@test "bump workflow, open: an existing bump branch keeps a person's commits" {
  make_workflow_tools
  echo "$BUMP_SHA" > "$TMP/branch_sha"
  step_script "Open the pull request"
  run_step
  [ "$status" -eq 0 ]
  [ "$(grep -cE '^git (push|commit|checkout)' "$TMP/calls.log")" -eq 0 ]
  grep -q '^gh pr create' "$TMP/calls.log"
}

@test "bump workflow, auto-merge: armed on this repo's pull request, bound to the branch's commit" {
  make_workflow_tools
  echo "$BUMP_SHA" > "$TMP/branch_sha"
  echo "[{\"number\":8,\"isCrossRepository\":true,\"headRefOid\":\"$BUMP_SHA\"},{\"number\":7,\"isCrossRepository\":false,\"headRefOid\":\"$BUMP_SHA\"}]" > "$TMP/open.json"
  echo "$ALL_REQUIRED" > "$TMP/rules.json"
  step_script "Let a regular bump merge itself once CI passes"
  run_step
  [ "$status" -eq 0 ]
  grep -qx "gh pr merge 7 --auto --squash --match-head-commit $BUMP_SHA" "$TMP/calls.log"
}

@test "bump workflow, auto-merge: not armed when main requires none of the checks" {
  make_workflow_tools
  echo "$BUMP_SHA" > "$TMP/branch_sha"
  echo "[{\"number\":7,\"isCrossRepository\":false,\"headRefOid\":\"$BUMP_SHA\"}]" > "$TMP/open.json"
  echo '[]' > "$TMP/rules.json"
  step_script "Let a regular bump merge itself once CI passes"
  run_step
  [ "$status" -eq 0 ]
  [ "$(grep -cE '^gh pr merge' "$TMP/calls.log")" -eq 0 ]
  grep -q '^gh pr comment 7' "$TMP/calls.log"
}

@test "bump workflow, auto-merge: not armed when main requires only some of the checks" {
  make_workflow_tools
  echo "$BUMP_SHA" > "$TMP/branch_sha"
  echo "[{\"number\":7,\"isCrossRepository\":false,\"headRefOid\":\"$BUMP_SHA\"}]" > "$TMP/open.json"
  echo '[{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"tests"}]}}]' > "$TMP/rules.json"
  step_script "Let a regular bump merge itself once CI passes"
  run_step
  [ "$status" -eq 0 ]
  [ "$(grep -cE '^gh pr merge' "$TMP/calls.log")" -eq 0 ]
}

@test "bump workflow, auto-merge: not armed when the checks are not bound to GitHub Actions" {
  # An unbound required check is satisfied by a status any token can post.
  make_workflow_tools
  echo "$BUMP_SHA" > "$TMP/branch_sha"
  echo "[{\"number\":7,\"isCrossRepository\":false,\"headRefOid\":\"$BUMP_SHA\"}]" > "$TMP/open.json"
  echo '[{"type":"required_status_checks","parameters":{"required_status_checks":[{"context":"tests"},{"context":"good-tree-passes"},{"context":"bad-tree-must-fail"}]}}]' > "$TMP/rules.json"
  step_script "Let a regular bump merge itself once CI passes"
  run_step
  [ "$status" -eq 0 ]
  [ "$(grep -cE '^gh pr merge' "$TMP/calls.log")" -eq 0 ]
}

@test "bump workflow, auto-merge: never a fork's pull request, nor one at another commit" {
  make_workflow_tools
  echo "$BUMP_SHA" > "$TMP/branch_sha"
  echo "[{\"number\":8,\"isCrossRepository\":true,\"headRefOid\":\"$BUMP_SHA\"},{\"number\":7,\"isCrossRepository\":false,\"headRefOid\":\"5555555555555555555555555555555555555555\"}]" > "$TMP/open.json"
  echo "$ALL_REQUIRED" > "$TMP/rules.json"
  step_script "Let a regular bump merge itself once CI passes"
  run_step
  [ "$status" -eq 1 ]
  [ "$(grep -cE '^gh pr merge' "$TMP/calls.log")" -eq 0 ]
}
