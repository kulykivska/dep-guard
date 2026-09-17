#!/usr/bin/env bash
# Fail when a dependency can execute code at install time without an explicit
# allowlist, or when a version range lets the installed code change silently.
#
# Those are the two mechanics behind nearly every real-world package
# compromise: a postinstall hook that runs on `install`, and a floating range
# that picks up the poisoned release automatically.
set -uo pipefail

# Advisory mode reports every finding but exits 0. It exists for rolling this
# check onto a repo that already has a backlog: a check that is red from day
# one teaches everyone to ignore it. Clean the backlog, then turn it off.
advisory=${DEP_GUARD_ADVISORY:-false}

status=0
warn() { printf '::warning file=%s::%s\n' "$1" "$2"; status=1; }
fail() { printf '::error file=%s::%s\n' "$1" "$2"; status=1; }

# --- Node: lifecycle scripts -------------------------------------------------
# Bun and pnpm refuse to run install hooks unless the package is listed in
# trustedDependencies / onlyBuiltDependencies. npm runs them for everything,
# so there the allowlist is "every dependency you have".
read_allowlist() {
  python3 - "$1" <<'PY'
import json, sys
try:
    with open(sys.argv[1]) as fh:
        data = json.load(fh)
except (OSError, ValueError) as exc:
    print(f"ERROR {exc}")
    sys.exit(1)
if not isinstance(data, dict):
    print("ERROR manifest is not a JSON object")
    sys.exit(1)
keys = ("trustedDependencies", "onlyBuiltDependencies")
print(" ".join(n for k in keys for n in (data.get(k) or [])))
PY
}

while IFS= read -r pkg; do
  [ -n "$pkg" ] || continue
  if ! trusted=$(read_allowlist "$pkg"); then
    # An unreadable manifest is a finding, not a silent "nothing to allow".
    fail "$pkg" "Could not parse manifest, so its install hooks were NOT checked: ${trusted#ERROR }"
    continue
  fi
  if [ -n "$trusted" ]; then
    echo "$pkg: packages allowed to run install hooks: $trusted"
  else
    echo "$pkg: no package is allowed to run install hooks."
  fi

  if [ -f "$(dirname "$pkg")/package-lock.json" ]; then
    warn "$pkg" "npm runs postinstall for every dependency. Prefer bun/pnpm, or set ignore-scripts=true in .npmrc."
  fi
done < <(git ls-files '*package.json' | grep -v node_modules)

# --- Python: sdists execute setup.py at install time -------------------------
while IFS= read -r req; do
  [ -n "$req" ] || continue
  echo "--- $req"
  if grep -nE '^[^#]*(git|hg|svn)\+' "$req"; then
    warn "$req" "VCS dependency without a commit pin resolves to whatever that branch holds today."
  fi
  if grep -nE '^[^#]*--(find-links|index-url|extra-index-url)' "$req"; then
    warn "$req" "Third-party package index: its operator can serve any code under a trusted name."
  fi
  # Per line, so one pinned requirement cannot mask an unpinned neighbour.
  unpinned=$(grep -nE '^[a-zA-Z0-9_.-]+(\[[^]]*\])?[[:space:]]*(>=|>|~=|!=|$)' "$req" | grep -v '==' || true)
  if [ -n "$unpinned" ]; then
    # Cap the listing: on a large requirements file the count is the signal.
    echo "$unpinned" | head -10
    count=$(echo "$unpinned" | wc -l | tr -d ' ')
    [ "$count" -gt 10 ] && echo "  ... and $((count - 10)) more"
    warn "$req" "Unpinned requirements: the same command installs different code tomorrow."
  fi
done < <(git ls-files '*requirements*.txt')

# --- Lock files: their absence is the finding --------------------------------
if git ls-files '*requirements*.txt' '*pyproject.toml' | grep -q . \
   && ! git ls-files '*uv.lock' '*poetry.lock' '*requirements*.lock' | grep -q .; then
  echo "::warning::Python dependencies have no lock file. Add uv.lock or pip-compile output to make builds reproducible."
  status=1
fi

if [ "$status" -ne 0 ] && [ "$advisory" != "false" ]; then
  echo "::notice::dep-guard is in advisory mode: the findings above do not fail this run."
  exit 0
fi
exit $status
