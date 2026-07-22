---
name: loot
description: "End-of-session harvest. Use when the user says /loot, wants to loot the quest/session, capture what went wrong or what was learned before closing, or asks to save session learnings. Mines the session for corrections, frictions, errors, and uninferrable insights, and banks them as loot pieces in the inventory for the Skill-Smith to craft later."
---

# 💰 /loot · harvest the quest

Reply in the Skill-Smith frame: `💰 /loot · {action}`, one metaphor+truth line, ▬ bar, then plain work.

You harvest. You never craft. Loot goes to the inventory; the forge (🔥 /skill-smelt)
turns it into skills or armor later, with its own approval gate. Never write a
skill, steering line, hook, or CLAUDE.md edit from /loot.

## What counts as a drop (mine ONLY these four)

- **correction** — the user corrected you, and the correction was not derivable from the repo or docs
- **friction** — a loop that cost time: repeated retries, permission denials, tool failures, wrong paths, a missing env fact
- **error** — a real mistake you made: wrong assumption, broken change, misread convention
- **insight** — an uninferrable fact learned this session: env quirk, project convention ("we always X here"), a decision *with its reason*

Not a drop: anything a model infers on its own; ordinary task content; anything
already encoded in a skill, CLAUDE.md/AGENTS.md, or steering file — check the
existing gear before banking, and list rejects under "already banked".

## Pipeline

1. Mine the **whole** session, not the recent tail. If context was compacted,
   read the transcript for what fell off: Claude Code → newest `*.jsonl` in
   `~/.claude/projects/<cwd-key>/` (user messages + tool errors carry the
   signal); Kiro/Codex → their session logs under `~/.kiro` / `~/.codex`.
   Unreachable → loot what context holds and say so.
2. Dedup each candidate against existing gear (skills dirs, CLAUDE.md,
   AGENTS.md, steering). Already encoded → reject.
3. Present the haul — this is the gaming moment, keep it tight:

   | # | Type | Drop | Evidence | Suggested target |
   |---|------|------|----------|------------------|

   Evidence is a verbatim quote, error line, or diff — no evidence, no drop.
   The user keeps or discards each piece.
4. Bank each kept drop as one file in `.claude/skill-smith/inventory/`
   (project root; create the dir), named `YYYY-MM-DD-<slug>.md`:

   ```markdown
   ---
   date: YYYY-MM-DD
   project: <repo name>
   type: correction | friction | error | insight
   target: skill | armor | undecided
   status: unsmelted
   ---
   <the drop, 1–5 plain lines — enough for a cold reader to craft from>

   **Evidence:** <the verbatim quote or error>
   ```
5. Close with the count and the hook: `N drops banked. M pieces waiting in the
   inventory. When ready: 🔥 /skill-smelt inventory`.

## Rules

- Harvest-only. The inventory is the boundary; crafting is smelt's job.
- An empty haul is a good result — "clean quest, no drops", write nothing.
- Fast ritual: the whole thing should feel under a minute. Never block or
  guilt the user at session end.
- One drop per file. Related drops stay separate pieces; smelt groups them.

$ARGUMENTS
