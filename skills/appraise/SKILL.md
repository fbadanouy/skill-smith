---
name: appraise
description: Audit all installed skills. Use when the user wants to review, clean up, or deduplicate skills, or asks which are unused, stale, or conflicting. Reports findings with a recommended action per skill.
---

# ⚖️ /appraise · audit the skills

Reply in the Skill-Smith frame: `⚖️ /appraise · {action}`, one metaphor+truth line, ▬ bar, then plain work.

Confirm scope (workspace, global, or both), read every SKILL.md, then check each for:

- **duplicates** — two descriptions claiming the same requests; one steals the other's activations → merge, or ⚡ differentiate both. To pick a winner between two skills covering the same task: judge their outputs blind (labeled A/B, mapping hidden), unblind after the verdict, and take the edits from the loser's transcript.
- **stale** — references to files/commands/APIs/versions that no longer exist (verify against the project) → 🔧
- **weak description** — summary-style ("Helps with X"), or a workflow summary (says *how* it works — agents follow that shortcut instead of reading the body) instead of "Use when …" triggers → ⚡
- **unused** — no sign of use (ledger's last-used column, or ask the user); unused ≠ useless, confirm before recommending deletion
- **bloated** — body over ~150 lines with no references/ split; rules re-explaining standard knowledge; rules tied to no real problem → ⚡
- **dead weight** — the model handles the task just as well without it (a /temper baseline run passed skill-less, or the body only restates what any model knows) → deletion candidate; the user decides
- **wrong artifact type** — really always-on knowledge (steering), an event automation (hook), or permission scoping (agent config); skills can't do those jobs → route via /skill-smith; harness-config advice needs doc citations

## Report

| Skill | Finding | Severity | Action |
|---|---|---|---|

Severity: **broken** (will misbehave — fix now) / **weak** (underperforms) / **cosmetic**.

Below the table:
- deletion candidates, with reasoning — the user decides; never delete or merge without an explicit order
- "deliberately skipped": findings you chose not to raise, and why
- update `ledger.md`: audit date + per-skill condition

$ARGUMENTS
