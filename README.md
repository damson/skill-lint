# skill-lint

[![ci](https://github.com/damson/skill-lint/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/damson/skill-lint/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/github/license/damson/skill-lint)](LICENSE)
[![Coverage](https://codecov.io/gh/damson/skill-lint/branch/main/graph/badge.svg)](https://codecov.io/gh/damson/skill-lint/branch/main)

**A friendly structural linter for Claude Code skills.**

Hi! 👋 If you write [skills](https://code.claude.com/docs/en/skills) for Claude
Code, or maintain a whole marketplace of them, this little action has your
back. Point it at your skills folder and it tells you, plainly and all at once,
whether every skill is wired up to actually fire.

## Why you might want this

Here's the sneaky thing about skills: a structurally broken one doesn't error;
it just goes quiet. A `name:` that doesn't match its folder quietly changes the
command you have to type. An empty `description:` hands your trigger to
whatever the first line of the body happens to say. Two personal skills sharing
a leaf name resolve by priority, and the loser simply isn't there. None of that
is visible at install time, and all of it is confusing later, usually right
when you're wondering why your carefully-written skill never seems to run.

skill-lint checks the five invariants that catch it:

| Check | Why it is not cosmetic |
|---|---|
| frontmatter `name:` matches the folder | `name:` is optional and **overrides** the folder. A mismatch means the skill answers to a name the directory never shows you |
| `description:` is non-empty | Omit it and Claude Code falls back to the first non-empty line of the body. The trigger doesn't vanish, it just stops being one anybody chose |
| a `## Procedure` or `## Step N` section | Without steps it is an essay, not a skill |
| a `## When to STOP` section | This is what stops a skill firing on work it should decline |
| leaf names unique across groups | Personal and project skills share one flat namespace and resolve by priority, so the loser is simply absent. Plugin skills are namespaced `plugin:skill` and don't collide |

Every problem is reported, not just the first: one run hands you the whole
to-do list instead of a fix-rerun-fix loop. The job fails if any skill fails.

None of these five stops a skill loading. That is the point: Claude Code is
forgiving here, and every one of these defects leaves you with a skill that
runs under a name you didn't choose, triggers on text you didn't write, or
isn't the one that won. Those are harder to notice than a crash, which is why
they're worth a linter. See the
[skills documentation](https://code.claude.com/docs/en/skills) for the
resolution rules.

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
| `harness-ref` | pinned commit | The exact linter version this action runs. A daily job compares it with the upstream's latest release and opens a pull request when it moves, having run this suite at the new pin first |

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
