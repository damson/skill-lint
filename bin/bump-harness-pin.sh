#!/usr/bin/env bash
#
# Move `harness-ref` in action.yml to the upstream's latest release.
#
# The pin is the whole point of this action: consumers get the linter at a
# commit somebody reviewed, and an upstream change cannot alter what their build
# enforces. The cost is that a pin goes stale in silence, because a stale pin
# and a current one behave identically until you compare them. Mine sat three
# weeks and five upstream releases behind.
#
# So this compares them on a schedule and leaves the decision alone: it rewrites
# the file and says what changed, including whether the move stays inside one
# major version. Opening the pull request, and deciding whether it may merge
# unattended, are the workflow's job.
#
# Outputs (to $GITHUB_OUTPUT): current, latest, tag, changed, and same_major
# when the pin moved.
#
# Usage:
#   ./bin/bump-harness-pin.sh            # rewrite action.yml if the pin moved
#   ./bin/bump-harness-pin.sh --dry-run  # say what would change, touch nothing
#
# Env:
#   HARNESS_REPO  upstream, owner/repo (default damson/agent-config-harness)
#   ACTION_FILE   the file holding the pin (default action.yml beside this repo)
#
# Requires: gh (authenticated), git.

set -euo pipefail

HARNESS_REPO="${HARNESS_REPO:-damson/agent-config-harness}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ACTION_FILE="${ACTION_FILE:-$SCRIPT_DIR/../action.yml}"
DRY_RUN=0
[ "${1:-}" = "--dry-run" ] && DRY_RUN=1

command -v gh >/dev/null || { echo "gh is required" >&2; exit 1; }
[ -f "$ACTION_FILE" ] || { echo "No such action file: $ACTION_FILE" >&2; exit 1; }

# The release's tag, then the commit that tag names. Reading `target_commitish`
# instead would hand back a branch name on a release cut from a branch, and a
# branch name as a pin is not a pin.
tag=$(gh api "repos/$HARNESS_REPO/releases/latest" --jq .tag_name) || {
    echo "Could not read the latest release of $HARNESS_REPO" >&2; exit 1; }
[ -n "$tag" ] || { echo "No latest release for $HARNESS_REPO" >&2; exit 1; }

latest=$(gh api "repos/$HARNESS_REPO/commits/$tag" --jq .sha) || {
    echo "Could not resolve $tag to a commit" >&2; exit 1; }

# A short sha, a tag, or an API error message must never reach the file: the
# pin's whole value is that it names one immutable commit.
if ! printf '%s' "$latest" | grep -qE '^[0-9a-f]{40}$'; then
    echo "Refusing to pin something that is not a full commit sha: $latest" >&2
    exit 1
fi

current=$(grep -oE '^    default: [0-9a-f]{40}$' "$ACTION_FILE" | awk '{print $2}' | head -1)
[ -n "$current" ] || { echo "No pinned commit found in $ACTION_FILE" >&2; exit 1; }

emit() {
    [ -n "${GITHUB_OUTPUT:-}" ] || return 0
    printf '%s=%s\n' "$1" "$2" >> "$GITHUB_OUTPUT"
}

emit current "$current"
emit latest "$latest"
emit tag "$tag"

if [ "$current" = "$latest" ]; then
    echo "Already pinned to $tag ($current). Nothing to do."
    emit changed false
    exit 0
fi

echo "Pin moves: $current -> $latest ($tag)"
emit changed true

# Whether the move stays inside one major version, which is half of what lets
# the workflow merge it unattended. The current pin's tag is looked up rather
# than remembered, and only a full release tag counts: the floating major tag
# and a pre-release share the commit or the number without being the release.
# A pin on no such tag, or a lookup that fails, counts as a new major, so the
# unknown case always reaches a person.
current_tag=$(gh api "repos/$HARNESS_REPO/tags" --paginate --jq ".[] | select(.commit.sha == \"$current\") | .name | select(test(\"^v?[0-9]+[.][0-9]+[.][0-9]+$\"))" 2>/dev/null | head -1) || current_tag=""
major_of() { printf '%s\n' "$1" | grep -oE '^v?[0-9]+' | tr -d v || true; }
current_major=$(major_of "$current_tag")
if [ -n "$current_major" ] && [ "$current_major" = "$(major_of "$tag")" ]; then
    echo "Same major version: ${current_tag} -> ${tag}."
    emit same_major true
else
    echo "Not provably the same major version: ${current_tag:-no tag} -> ${tag}. A person reviews this one."
    emit same_major false
fi

if [ "$DRY_RUN" -eq 1 ]; then
    exit 0
fi

# Through a temp file and `mv`: `sed -i` wants a mandatory empty argument on BSD
# and refuses one on GNU, and this runs on both.
tmp=$(mktemp)
sed "s|^    default: $current\$|    default: $latest|" "$ACTION_FILE" > "$tmp"
mv "$tmp" "$ACTION_FILE"

grep -q "default: $latest" "$ACTION_FILE" || {
    echo "The rewrite did not take; leaving the file alone was safer" >&2; exit 1; }
echo "Rewrote $(basename "$ACTION_FILE")."
