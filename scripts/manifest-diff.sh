#!/usr/bin/env bash
# Print a markdown summary of what a diff does to dependency manifests.
# Usage: manifest-diff.sh <base-ref> <head-ref>
set -uo pipefail

base=${1:?base ref}
head=${2:?head ref}
max_lines=200

for ref in "$base" "$head"; do
  if ! git rev-parse --verify --quiet "$ref^{commit}" >/dev/null; then
    # Silence here would read as "nothing changed", which is the one wrong
    # answer a supply-chain check can give.
    echo "::error::Cannot resolve ref '$ref'. A shallow clone needs fetch-depth: 0."
    exit 1
  fi
done

manifests=(
  '*package.json' '*requirements*.txt' '*pyproject.toml'
  '*Cargo.toml' '*go.mod' '*Gemfile' '*composer.json'
)

echo "## Dependency changes"
echo
diff=$(git diff --no-color "$base...$head" -- "${manifests[@]}")
if [ -z "$diff" ]; then
  echo "_No manifest changes in this diff._"
  exit 0
fi

# Fence with a marker the diff itself cannot contain, so a crafted branch
# cannot break out of the code block and inject markdown into the summary.
lines=$(echo "$diff" | grep -E '^(diff --git|[-+][^-+])')
echo '````diff'
echo "$lines" | head -"$max_lines"
echo '````'
total=$(echo "$lines" | wc -l | tr -d ' ')
if [ "$total" -gt "$max_lines" ]; then
  echo
  echo "_Truncated: showing $max_lines of $total changed lines._"
fi
echo
echo "Every added line is code that will run on a developer machine and in CI."
