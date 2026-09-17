# claude-guardrails

Blocking hooks for Claude Code. They run before a tool call, not after, so a
destructive command never executes and a secret never enters git history.

Every hook **fails open**: anything unexpected (unparsable input, no git repo,
missing python) allows the call through. A guard that wedges legitimate work
gets disabled, and a disabled guard protects nothing.

## What each hook blocks

| Hook | Trigger | Blocks |
|---|---|---|
| `guard-destructive-ops.sh` | any Bash call | destroying a Fly.io app, volume or postgres cluster; `scale count 0`; unsetting Fly secrets; `DROP`/`TRUNCATE` through a database client; force-push to main/master |
| `pre-commit-guard.sh` | `git commit` | AI attribution trailers in the message; secrets/PII in the staged diff |
| `pre-push-secrets-scan.sh` | `git push` | secrets/PII in the commits this push would actually send |
| `pre-push-gate.sh` | `git push` | any push that has not passed a review-and-fix pass |

`secrets_scan.py` is the shared scanner. It reports the category and the file
but never the matched value, so a secret does not get echoed into logs or a
transcript on its way to being blocked.

## Install

As a plugin (the three PreToolUse hooks, wired by `hooks/hooks.json`):

```bash
cp -r claude-guardrails ~/.claude/plugins/guardrails
```

`pre-push-gate.sh` is separate: it belongs in `~/.claude/scripts/` and is
registered as a PreToolUse hook in `settings.json`. It expects a
`pre-push-review` skill to exist; without one, adjust the message it prints.

## The allowlist

`hooks/secrets-allowlist.txt` here is a **generic baseline**: placeholders,
env-var indirection, reserved test domains, and patterns where a keyword
describes a field rather than holds a value (`password: z.string()`).

Project-specific entries, real fixture addresses, internal file names and your
own contact addresses belong in your local copy only. A public allowlist is a
map of what your scanner deliberately ignores.

## Known false positive

These hooks match on command text, so writing *about* a blocked command can
trip them. Documenting `scale count 0` in a file is enough to block the write that
creates the file. The guards fail closed in that one direction by design:
matching intent instead of text would mean running the command to find out.

## Platform note

`pre-push-gate.sh` parses the hook payload with `plutil`, which exists only on
macOS. The three plugin hooks use `python3` instead and are portable.

## Why PreToolUse and not a git hook

A git `pre-commit` hook runs after the agent has already decided to commit and
can be skipped with `--no-verify`. A PreToolUse hook sees the command as text
before anything runs, and exit code 2 sends the reason back to the agent, which
then has to deal with it rather than retry blindly.
