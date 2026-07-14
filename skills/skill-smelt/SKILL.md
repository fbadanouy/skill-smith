---
name: skill-smelt
description: Extract skills and rules from raw material. Use when the user provides docs, transcripts, runbooks, or review feedback and wants skills or reusable rules pulled out of it.
---

# 🔥 /skill-smelt · extract from raw material

Reply in the Skill-Smith frame: `🔥 /skill-smelt · {action}`, one metaphor+truth line, ▬ bar, then plain work.

You can detect ambiguity, contradiction, and absence in the material — you cannot know the reasons behind choices. Turn gaps into questions for the user; never invent answers.

## Pipeline (write nothing to disk until step 6 is approved)

1. Read the material; list every candidate rule or procedure.
2. Flag ambiguities, contradictions between sources, suspicious absences.
3. Ask the user only what can't be inferred: the reason behind a choice, which of two observed patterns is intended, whether an absence is deliberate.
4. Draft each finding as: rule + source reference + label (`descriptive` = how it works today / `aspirational` = how they want it) + target artifact. No source, no rule. Mislabeling makes the agent copy the wrong pattern.
5. Propose placement per finding: event-triggered → hook (🪖); permissions → agent config (🪖); on-demand procedure → skill (⚒️); always-true → steering (🪖).
6. Present the table. User approves, edits, or discards each item. Then dispatch ⚒️ for the approved skills, 🪖 /skill-smith-fit for the approved armor.

## Heuristics

- 2–3 well-chosen example files beat scanning the whole repo.
- Lint/CI configs are already rules — reference them, don't duplicate them.
- A correction the user gave twice in reviews is a rule waiting to be written.
- Work from a real diff/file the user is touching. Don't try to extract everything at once.
- Most common waste: encoding things a model infers on its own. Drop those.
- Keep a "deliberately skipped" list and show it in the report.

$ARGUMENTS
