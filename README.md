# skill-lint

[![ci](https://github.com/damson/skill-lint/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/damson/skill-lint/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/github/license/damson/skill-lint)](LICENSE)
[![Coverage](https://codecov.io/gh/damson/skill-lint/graph/badge.svg)](https://codecov.io/gh/damson/skill-lint)

**A friendly structural linter for Claude Code skills.**

Hi! 👋 If you write [skills](https://code.claude.com/docs/en/skills) for Claude
Code, or maintain a whole marketplace of them, this little action has your
back. Point it at your skills folder and it tells you, plainly and all at once,
whether every skill is wired up to actually fire.

## Why you might want this

Here's the sneaky thing about skills: a structurally broken one doesn't error;
it just goes quiet. The wrong `name:` makes it unaddressable, an empty
`description:` means it never triggers, and two skills sharing a leaf name
silently shadow each other, because skills install **flat** into
`~/.claude/skills/` and share one namespace. None of that is visible at install
time, and all of it is confusing later, usually right when you're wondering
why your carefully-written skill never seems to run.

skill-lint checks the five invariants that catch it:

| Check | Why it is not cosmetic |
|---|---|
| frontmatter `name:` matches the folder | A mismatch makes the skill unaddressable |
| `description:` is non-empty | The description is the whole trigger: an empty one never fires |
| a `## Procedure` or `## Step N` section | Without steps it is an essay, not a skill |
| a `## When to STOP` section | This is what stops a skill firing on work it should decline |
| leaf names unique across groups | Skills install flat; a duplicate silently shadows another |

Every problem is reported, not just the first: one run hands you the whole
to-do list instead of a fix-rerun-fix loop. The job fails if any skill fails.

## Get started in 30 seconds

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

That's the whole integration. No API key, no config file, nothing to install:
the checks are structural.

## Run it on your machine

The linter itself lives in
[agent-config-harness](https://github.com/damson/agent-config-harness), where it
is developed and tested; this action is a pinned wrapper around it, so the two
can never drift. To run the same checks locally:

```bash
git clone --depth 1 https://github.com/damson/agent-config-harness
./agent-config-harness/bin/validate-skills.sh path/to/skills
```

## What a failure looks like

No cryptic exit codes: each finding says what's wrong and what to do about it:

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

No token, ever: the harness is public and the fetch is anonymous.

## A linter that tests itself

This repo's own CI lints a known-good fixture tree **and asserts a known-bad
tree fails**. A linter whose failure mode is untested is decoration. If you
add a check, add the fixture that proves it can fail.

The plumbing has its own bats suite too (fetching the pinned linter, wiring
the paths, propagating failures, all against local fixtures, no network):

```bash
bats tests/
```

## Contributing

Found a structural failure mode we don't catch? Something in the output that
confused you? Please open an issue: confusing output is a bug here, not a
you-problem. Pull requests are very welcome: check logic belongs upstream in
[agent-config-harness](https://github.com/damson/agent-config-harness), while
the action wrapper, fixtures and docs live right here.

## License

[MIT](LICENSE): use it, fork it, ship it. If it saves you from a silently
shadowed skill, we'd love to hear about it.
