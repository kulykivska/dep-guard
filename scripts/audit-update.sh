#!/usr/bin/env bash
# Audit what changed between two versions of a third-party repository you run
# but do not maintain, before you upgrade.
#
#   audit-update.sh <repo-dir> <old-ref> <new-ref>
#
# Read-only: it never touches your working tree.
set -uo pipefail

repo=${1:?repo directory}
old=${2:?old ref}
new=${3:?new ref}
cd "$repo" || exit 1

code_globs=('*.py' '*.ts' '*.tsx' '*.js' '*.jsx' '*.rs' '*.go' '*.rb')

added() { git diff -U0 "$old" "$new" -- "${code_globs[@]}" | grep -E '^\+[^+]'; }

section() { printf '\n=== %s ===\n' "$1"; }

section "Dependency manifests"
git diff --stat "$old" "$new" -- '*package.json' '*.lock' '*requirements*.txt' \
  '*pyproject.toml' '*Cargo.toml' '*go.mod' || echo "none"

section "New outbound network call sites"
added | grep -inE 'httpx|requests\.(get|post|put|patch)|urlopen|aiohttp|fetch\(|axios|reqwest|net/http|WebSocket|socket\.(connect|create)' \
  || echo "none"

section "New hardcoded hosts"
added | grep -oE 'https?://[a-zA-Z0-9._-]+' | sort -u \
  | grep -vE '127\.0\.0\.1|localhost|schema|\.w3\.org|json-schema|docs\.' || echo "none"

section "New process execution / dynamic evaluation"
added | grep -inE 'subprocess|os\.system|popen|exec\(|eval\(|Command::new|child_process|spawn\(' \
  || echo "none"

section "New credential or environment access"
added | grep -inE 'os\.environ|process\.env|std::env|keyring|\.ssh/|\.aws/|token|secret|password' \
  || echo "none"

section "Known vulnerabilities in the new tree"
if command -v osv-scanner >/dev/null 2>&1; then
  osv-scanner scan source -r . 2>&1 | tail -40
else
  echo "osv-scanner not installed (brew install osv-scanner) - skipped."
fi
