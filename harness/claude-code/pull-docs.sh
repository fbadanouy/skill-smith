#!/usr/bin/env bash
#
# pull-docs.sh — mirror the Claude Code docs into ./docs as plain Markdown.
#
# code.claude.com publishes an llms.txt index and a plain-Markdown twin of every
# docs page at the same URL + ".md". Re-run anytime to refresh, then re-verify
# mechanics.md against the new snapshot (citations are page.md:line — lines shift
# on refresh, that's the point).
#
# macOS-native: curl + grep + sed only. Usage: ./pull-docs.sh [--list]
#
set -euo pipefail

BASE="https://code.claude.com"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$SCRIPT_DIR/docs"
DRY=0
[ "${1:-}" = "--list" ] && DRY=1

echo "Fetching index from $BASE/docs/llms.txt ..."
urls=$(curl -fsSL "$BASE/docs/llms.txt" \
  | grep -oE 'https://code\.claude\.com/docs/en/[a-zA-Z0-9/_-]+\.md' \
  | grep -vE '/agent-sdk/|/release-notes' \
  | sort -u)

total=$(printf '%s\n' "$urls" | grep -c . || true)
echo "Found $total doc pages (agent-sdk + release-notes excluded)."
[ "$DRY" -eq 1 ] || mkdir -p "$OUT"

ok=0; fail=0
while IFS= read -r u; do
  [ -z "$u" ] && continue
  rel="${u#"$BASE"/docs/en/}"               # e.g. sub-agents.md or nested/page.md
  dest="$OUT/${rel//\//_}"                  # flatten nesting: a/b.md -> a_b.md
  if [ "$DRY" -eq 1 ]; then echo "  $u -> docs/${rel//\//_}"; ok=$((ok+1)); continue; fi
  if curl -fsSL "$u" -o "$dest"; then ok=$((ok+1)); else fail=$((fail+1)); echo "  FAIL: $u" >&2; fi
done <<< "$urls"

echo "Done. $ok fetched, $fail failed, into $OUT"
