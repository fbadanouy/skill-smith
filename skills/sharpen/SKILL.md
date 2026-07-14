---
name: sharpen
description: Fix a skill's activation and cut bloat. Use when a skill never activates, fires at the wrong times, or its body is bloated or vague.
---

# ⚡ /sharpen · fix activation, cut bloat

Reply in the Skill-Smith frame: `⚡ /sharpen · {action}`, one metaphor+truth line, ▬ bar, then plain work.

## First: confirm it loads at all

A description can't fire if the harness never saw it. Before rewriting anything:
valid frontmatter (an unquoted `:` silently drops it), folder name = name, and —
if a custom/restricted agent is in play — the skill is actually wired into that
agent's config (fetch the provider's docs for how; never guess). Read the current
description and quote it in your diagnosis; if the user's phrasings already
appear in it, the problem is loading or routing, not wording.

## The description (fixes 80% of activation problems)

The description alone decides when the skill loads.
- Get 3–5 exact phrasings the user typed when they expected it to fire.
- Rewrite as "Use when …" covering those intents. Generalize — don't paste the phrasings in verbatim; keyword-stuffing overfits the exact wordings you tested and misses the next one. Replace any summary-style description ("Helps with X").
- The description says *when*, never *how*: strip any workflow summary — agents follow the description's shortcut instead of reading the body (a description saying "review between tasks" produced one review where the body required two). Broaden with trigger contexts, bound with "not for Y", never with process detail.
- Fires when it shouldn't → add distinguishing boundaries to this skill AND the sibling it collides with ("for X; not for Y — that's <sibling>").
- ≤1024 chars; quote if it contains `:`.

## The body

- Over ~150 lines → move detail into references/ files.
- Per rule ask: would this have prevented a real problem? No → delete it.
- Paragraphs re-explaining standard knowledge → replace with the concept's name; keep only project-specific facts, each with its source.
- Advice-prose → testable rules ("When X, do Y").

## Finish

Re-check frontmatter (name format, folder match, valid YAML). Hand to 🗡️ /temper: must fire on the user's phrasings and stay quiet on 2 near-miss prompts. Update `ledger.md`. Report what was deleted and why.

$ARGUMENTS
