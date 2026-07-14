---
name: skill-repair
description: Fix a skill that misbehaved or references dead things. Use when a skill activated but did the wrong thing, gave bad guidance, or points at files/commands that no longer exist. Fixes only the broken section, hands to /skill-temper.
---

# 🔧 /skill-repair · fix wrong behavior

Reply in the Skill-Smith frame: `🔧 /skill-repair · {action}`, one metaphor+truth line, ▬ bar, then plain work.

## Get the failure, verbatim

The prompt that triggered it, what the skill made the agent do, what should have happened.
No reproduction → no repair; log it as a suspicion for ⚖️ /skill-appraise instead.

## Classify the defect (usually exactly one)

- **wrong activation** — fired on a request it wasn't meant for → hand to ⚡ /skill-sharpen
- **stale reference** — body points at files/commands/APIs that no longer exist; verify every factual claim against the current project
- **ambiguous rule** — readable two ways, agent picked the wrong one; rewrite as "When X, do Y" with the condition explicit
- **missing case** — correct for the common path, silent on this edge; add the narrowest rule that covers it
- **wish stated as fact** — describes how things *should* work, agent applied it as how they *do*; label or correct it

## Match the fix's form to the failure

The form that fixes one failure type backfires on another:

- agent **knowingly skipped a rule** under pressure → prohibition + an explicit counter for the exact excuse it used (capture the rationalization verbatim, add its one-line rebuttal to the skill)
- output had the **wrong shape** → positive recipe stating what the output IS, parts in order — prohibitions ("don't restate X") measurably *increase* the unwanted content here
- a required element was **omitted** → a required slot in the template, not a prose reminder near it
- behavior should **depend on a condition** → a conditional on an observable predicate ("if the brief exists, reference it"), never "don't X unless it matters" — nuance clauses reopen the negotiation

## Record, then fix

Four lines into the report and `ledger.md`:
```
error / root cause (defect class + exact lines) / correct approach / lesson
```
Edit only the broken section. Re-check frontmatter. If the broken content also lives in another file (steering, agent prompt), don't silently fix both copies — surface the mirror: one home, the other references it.

## Prove it

🗡️ /skill-temper with the original failing prompt as test #1 — the fix holds only if that exact failure is gone.
Same skill breaks a third time → recommend delete-and-recreate: 🔥 /skill-smelt the useful parts, ⚒️ /skill-forge fresh.

$ARGUMENTS
