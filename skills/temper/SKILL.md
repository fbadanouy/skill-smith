---
name: temper
description: Test a skill until it holds. Use after creating, sharpening, or repairing a skill, or when the user wants to test, validate, or eval one. Checks it loads, activates correctly, and behaves. Reports pass/fail per test.
---

# 🗡️ /temper · test the skill

Reply in the Skill-Smith frame: `🗡️ /temper · {action}`, one metaphor+truth line, ▬ bar, then plain work.

Parsing ≠ activating ≠ behaving. Test all three, in order.

## 1 — it loads

Valid YAML frontmatter. name = folder name, lowercase-hyphen, ≤64 chars. description ≤1024. Every file the body references exists. No dead paths or commands.

## 2 — it activates

Activation is probabilistic; one test proves nothing.
- 3–5 positive prompts: real phrasings that must trigger it (get them from the user or the original request).
- 2–3 near-miss prompts: adjacent requests that must NOT trigger it.
Run each as cleanly as possible (fresh context, only the skill names + descriptions visible, ask: "which skill, if any, handles this?"). Run each prompt 2–3× and score a trigger rate — pass at a clear majority, not a single lucky hit. If the harness has a headless/non-interactive mode, prefer a real run over the simulated judge (fetch the provider's docs for the command; never guess it).
Positive prompt silent → description too narrow → ⚡ /sharpen. Near-miss triggers → too broad → ⚡ /sharpen.

## 3 — it behaves

Per scenario (from the original request, the failure that caused a /repair, or /forge's watch-it-fail baseline record — that failure is always test #0):
1. Write the pass criterion BEFORE running: "given <input>, the agent does <observable behavior>". No grading by feel.
2. Run the skill against the scenario for real. For a discipline skill (a rule with a compliance cost the agent might rationalize away), don't test with an academic prompt — use a pressure scenario combining deadline + sunk cost + "just this once"; it passes only if the agent complies while citing the skill.
3. Run the same scenario once WITHOUT the skill (clean context). If the baseline passes too, the skill is dead weight for that scenario — it earns its keep only where it passes and the baseline fails. Report the delta.
4. On failure, read the run transcript, not just the output: did the agent ignore an instruction (ambiguous → 🔧), never load it (activation → ⚡), or invent content (missing anchor)? Record: error / root cause / correct approach / lesson. Re-run after the fix.

## Verdict

Table: test · expected · actual · PASS/FAIL · evidence. Evidence quotes the output — no PASS on benefit of the doubt (a "Summary" heading over one vague sentence is a FAIL). Ship only on all-pass. Record in `ledger.md`.
Three fix-and-retest cycles failing on the same defect → recommend delete-and-recreate (🔥 then ⚒️).

$ARGUMENTS
