#!/usr/bin/env bash
# Skill Smith installer — copies the pack into a harness's skills directory.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_SRC="$REPO_DIR/skills"

echo "⚒️  SKILL SMITH — choose your forge"
echo
echo "  1) Kiro CLI      — workspace   (./.kiro/skills/)"
echo "  2) Kiro CLI      — global      (~/.kiro/skills/)"
echo "  3) Claude Code   — project     (./.claude/skills/)"
echo "  4) Claude Code   — personal    (~/.claude/skills/)"
echo "  5) Custom path"
echo
read -rp "Forge [1-5]: " choice

case "$choice" in
  1) DEST="./.kiro/skills" ;;
  2) DEST="$HOME/.kiro/skills" ;;
  3) DEST="./.claude/skills" ;;
  4) DEST="$HOME/.claude/skills" ;;
  5) read -rp "Path: " DEST ;;
  *) echo "The Smith does not know that forge."; exit 1 ;;
esac

mkdir -p "$DEST"
count=0
for skill in "$SKILLS_SRC"/*/; do
  name="$(basename "$skill")"
  if [ -d "$DEST/$name" ]; then
    read -rp "  $name already hangs in this armory. Reforge (overwrite)? [y/N] " ow
    [[ "$ow" =~ ^[Yy]$ ]] || { echo "  skipped $name"; continue; }
    rm -rf "$DEST/$name"
  fi
  cp -R "$skill" "$DEST/$name"
  count=$((count+1))
  echo "  🔥 forged into armory: $name"
done

echo
echo "The Smith delivered $count blade(s) to $DEST"
echo "Summon with: /skill-smith"
