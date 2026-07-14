#!/usr/bin/env bash
#
# clone-kiro-docs.sh — mirror the Kiro documentation into ./docs as plain Markdown.
#
# Kiro publishes a plain-Markdown twin of every docs page at the same path + ".md"
# (e.g. /docs/steering -> /docs/steering.md). This enumerates every /docs/ URL from
# the sitemap and mirrors the .md twins locally, preserving the path tree.
#
# macOS-native: uses only curl, grep, sed (all preinstalled). No deps.
# Cost: ~1.6 MB, a few hundred GET requests. Re-run anytime to refresh.
#
# Mirrors the CLI docs only (/docs/cli/*) — the contract the skill-smith grounds itself in.
#
# Usage:  ./clone-kiro-docs.sh            # clone the CLI docs from https://kiro.dev
#         ./clone-kiro-docs.sh --list     # dry run: list target files, download nothing
#         BASE_URL=https://kiro.dev ./clone-kiro-docs.sh
#
set -euo pipefail

BASE="${BASE_URL:-https://kiro.dev}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT="$SCRIPT_DIR/docs"
DRY=0
[ "${1:-}" = "--list" ] && DRY=1

FILTER="/docs/cli(/|\$)"
echo "Scope: /docs/cli only"

echo "Fetching sitemap from $BASE/sitemap.xml ..."
urls=$(curl -fsSL "$BASE/sitemap.xml" \
  | grep -oE '<loc>[^<]+</loc>' \
  | sed -E 's#</?loc>##g' \
  | grep -E "$FILTER" \
  | sort -u)

total=$(printf '%s\n' "$urls" | grep -c . || true)
echo "Found $total doc URLs."
[ "$DRY" -eq 1 ] || mkdir -p "$OUT"

ok=0; fail=0; n=0
# carriage-return progress only when stdout is a terminal (keeps logs clean)
[ -t 1 ] && ISTTY=1 || ISTTY=0
while IFS= read -r u; do
  [ -z "$u" ] && continue
  path="/${u#*://*/}"        # strip scheme+host -> /docs/...
  path="${path%/}"           # strip trailing slash
  [ "$path" = "" ] && path="/docs"
  mdurl="$BASE$path.md"

  rel="${path#/docs}"; rel="${rel#/}"
  [ -z "$rel" ] && rel="index"
  dest="$OUT/$rel.md"

  if [ "$DRY" -eq 1 ]; then
    echo "  $mdurl  ->  docs/$rel.md"
    ok=$((ok+1))
    continue
  fi

  n=$((n+1))
  if [ "$ISTTY" -eq 1 ]; then
    printf '\r\033[K  [ %2d/%d ] %s' "$n" "$total" "$rel"
  fi

  mkdir -p "$(dirname "$dest")"
  if curl -fsSL "$mdurl" -o "$dest"; then
    ok=$((ok+1))
  else
    fail=$((fail+1)); printf '\r\033[K' ; echo "  FAIL: $mdurl" >&2
  fi
done <<< "$urls"
[ "$ISTTY" -eq 1 ] && [ "$DRY" -eq 0 ] && printf '\r\033[K'   # clear the progress line

echo ""
if [ "$DRY" -eq 1 ]; then
  echo "Dry run: $ok files would be written to $OUT"
else
  size=$(du -sh "$OUT" 2>/dev/null | cut -f1)
  echo "Done. Downloaded $ok files (${size}) to $OUT"
  if [ "$fail" -gt 0 ]; then echo "Failed: $fail"; fi
fi
exit 0
