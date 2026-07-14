#!/usr/bin/env bash
#
# pull-docs.sh — mirror the Codex docs into ./docs as plain Markdown.
#
# learn.chatgpt.com publishes an llms.txt index; every docs page serves a
# plain-Markdown twin at the page URL + ".md" (developers.openai.com/codex/*
# 308-redirects there — hence curl -L). Re-run anytime, then re-verify
# mechanics.md against the new snapshot.
#
# Files are flattened as codex_<slug-with-underscores>.md to match the
# citation names used in mechanics.md.
#
# macOS-native: curl + grep + sed only. Usage: ./pull-docs.sh [--list]
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$SCRIPT_DIR/docs"
DRY=0
[ "${1:-}" = "--list" ] && DRY=1

echo "Fetching index from https://learn.chatgpt.com/docs/llms.txt ..."
urls=$(curl -fsSL "https://learn.chatgpt.com/docs/llms.txt" \
  | grep -oE 'https://[a-z.]+/(docs|codex)/[a-zA-Z0-9/_?=-]+' \
  | grep -vE '/cloud/|/changelog' \
  | sort -u)

total=$(printf '%s\n' "$urls" | grep -c . || true)
echo "Found $total doc pages (cloud + changelog excluded)."
[ "$DRY" -eq 1 ] || mkdir -p "$OUT"

ok=0; fail=0
while IFS= read -r u; do
  [ -z "$u" ] && continue
  slug="${u#*//*/}"                          # docs/agent-configuration/rules
  slug="${slug#docs/}"; slug="${slug#codex/}"
  slug="${slug%%\?*}"                        # drop ?surface=cli style params
  dest="$OUT/codex_${slug//\//_}.md"
  if [ "$DRY" -eq 1 ]; then echo "  $u.md -> docs/codex_${slug//\//_}.md"; ok=$((ok+1)); continue; fi
  if curl -fsSL -L "$u.md" -o "$dest"; then ok=$((ok+1)); else fail=$((fail+1)); echo "  FAIL: $u.md" >&2; fi
done <<< "$urls"

echo "Done. $ok fetched, $fail failed, into $OUT"
