# skill-lint

**A structural linter for Claude Code skills.**

A skill that is broken structurally does not error — it goes quiet. The wrong
`name:` makes it unaddressable, an empty `description:` means it never fires,
and two skills sharing a leaf name silently shadow each other because skills
install **flat** into `~/.claude/skills/` and share one namespace. All of that
is invisible at install time and confusing later.

This action lints a skills tree for the four invariants that catch it:

| Check | Why it is not cosmetic |
|---|---|
| frontmatter `name:` matches the folder | A mismatch makes the skill unaddressable |
| `description:` is non-empty | The description is the whole trigger — an empty one never fires |
| a `## Procedure` or `## Step N` section | Without steps it is an essay, not a skill |
| a `## When to STOP` section | This is what stops a skill firing on work it should decline |
| leaf names unique across groups | Skills install flat; a duplicate silently shadows another |

Every problem is reported, not just the first, and the job fails if any skill
fails.

## Use it in CI

```yaml
jobs:
  skill-lint:
    runs-on: ubuntu-latest
    timeout-minutes: 5
    steps:
      - uses: actions/checkout@v4
      - uses: damson/skill-lint@v1
        with:
          path: skills          # your skills directory
```

That is the whole integration. No API key — the checks are structural.

## Run it locally

The linter itself lives in
[agent-config-harness](https://github.com/damson/agent-config-harness), where it
is tested; this action is a pinned wrapper around it, so the two can never
drift. Locally, run it from the source:

```bash
git clone --depth 1 https://github.com/damson/agent-config-harness
./agent-config-harness/bin/validate-skills.sh path/to/skills
```

## What a failure looks like

```
⚠ mismatched: frontmatter name is 'some-other-name' — it must match the folder name
⚠ no-stop: no '## When to STOP' section
✗ 2 problem(s) across 2 skill(s) in tests/fixtures/bad
```

## Inputs

| Input | Default | Meaning |
|---|---|---|
| `path` | `skills` | Directory holding the skills to lint |
| `harness-ref` | pinned commit | The exact linter version this action runs |
| `token` | — | Read token for the harness repo; only needed while it is private |

This repo's own CI lints a known-good fixture tree **and asserts a known-bad
tree fails** — a linter whose failure mode is untested is decoration.
