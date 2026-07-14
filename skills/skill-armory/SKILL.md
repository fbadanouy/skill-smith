---
name: skill-armory
description: Show the agent's character sheet. Use when the user asks what skills are available, equipped, installed, or loaded, wants an inventory of their agent setup, or asks to see the armory or ledger.
---

# 🛡️ /skill-armory · character sheet

Reply in the Skill-Smith frame: `🛡️ /skill-armory · {action}`, one metaphor+truth line, ▬ bar, then the sheet. Read-only — change nothing.

## Gather

1. **Skills**: list every skill folder in the workspace dir and global dir (`.kiro/skills/` + `~/.kiro/skills/`, or `.claude/skills/` + `~/.claude/skills/` — detect the harness by which dirs exist). Read frontmatter only. Sum the description lengths — every equipped skill's name+description rides in context on every turn, so EQUIPPED has a standing weight too; report the total.
2. **Always-loaded files**: steering / CLAUDE.md / AGENTS.md present, with line counts. Advising on their content requires the harness pack (`harness/<platform>/`) or the provider's docs (see /skill-smith).
5. **Harness pack**: if `harness/<platform>/` exists (skill-smith repo or beside the skills dir), note it and its "last verified" line.
3. **Ledger**: read `ledger.md` if present (created dates, last used, condition).
4. **Loaded vs not**: default agents load all skills; custom agents only load what their config lists — if a custom agent config exists, check it and flag skills it silently misses.

## Render

```
═══════════════════════════════════════════
  CHARACTER SHEET — <project/agent>
  Class: <harness>      Forge: <skills dir>
  Harness: <pack + last-verified date, or "bare — no pack fitted">
═══════════════════════════════════════════
  WORN (always loaded)               weight
  ─ <file>                           <lines>

  EQUIPPED (loads on demand)
  ─ <skill>  «use when: …»           condition: <from ledger, else "untested">

  ON THE RACK (installed, not loaded)
  ─ <skill>  ⚠ <why it isn't loading>

  EMPTY SLOTS (gaps)
  ─ <recurring manual task with no skill — max 2–3>
═══════════════════════════════════════════
```

Two skills with overlapping triggers → mark both ⚔.
A description that summarizes the skill's workflow (how, not when) → mark ⚠ "shortcut description".
Close with one line: the single most useful next command (e.g. "3 skills untested — /skill-temper before you trust them.").

$ARGUMENTS
