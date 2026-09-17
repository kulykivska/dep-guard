# dep-guard

Every dependency update is a code change written by someone you have never
met, merged by a bot, on a Tuesday. dep-guard makes that change go through a
review it cannot skip.

Add three lines to a repo and every PR that touches a manifest or lock file
gets scanned automatically.

## Install

Copy `templates/caller-workflow.yml` into `.github/workflows/supply-chain.yml`:

```yaml
name: Supply chain
on:
  pull_request:
    paths: ['**/package.json', '**/requirements*.txt', '**/Cargo.toml', '**/*.lock']
  schedule: [{ cron: '30 6 * * 1' }]
permissions:
  actions: read
  contents: read
  security-events: write
  pull-requests: write
jobs:
  guard:
    uses: kulykivska/dep-guard/.github/workflows/supply-chain.yml@v1
```

Then add `templates/renovate.json` (or `templates/dependabot.yml`) so update
PRs actually get raised.

## What runs

| Layer | Question it answers | Tool |
|---|---|---|
| Vulnerabilities | Does anything in the tree have a published CVE? | OSV-Scanner, all ecosystems at once |
| Dependency review | What does *this diff* add, and under what license? | `actions/dependency-review-action` |
| Install hooks | Can anything execute code on `install`? Is anything unpinned? | `scripts/check-install-hooks.sh` |

The third layer is the one that matters most and the one nobody runs. A CVE
feed only knows about compromises that have already been published and
assigned an identifier. A package that quietly gained a `postinstall` script
in its latest release has no CVE and never will.

## Running it on someone else's app

For software you use but do not maintain, diff two releases before upgrading:

```bash
scripts/audit-update.sh ~/src/some-app v0.4.0 v0.5.0
```

It reports new outbound network calls, new hardcoded hosts, new process
execution, and new environment/credential access introduced between the two
versions.

## Inputs

| Input | Default | Meaning |
|---|---|---|
| `fail-on-severity` | `moderate` | Severity floor that fails the run |
| `deny-licenses` | AGPL/GPL-3.0/SSPL | Licenses rejected in new dependencies |
| `skip-license-check` | `false` | Set `true` on private repos without Dependency Review |
| `ref` | `v1` | dep-guard ref the scripts are loaded from |

## Notes

- Dependency Review needs Dependency Graph enabled. Public repos have it by
  default; private repos need GitHub Advanced Security or
  `skip-license-check: true`.
- Pushing workflow files needs the `workflow` OAuth scope:
  `gh auth refresh -s workflow`.

MIT.
