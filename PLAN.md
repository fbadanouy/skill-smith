# Skill-Smith Upgrade Plan

> **Status (2026-07-14): Phases 1–5 applied** in one pass (iteration-2 eval run
> was skipped by user decision). Also added: posture-skill classification in
> /forge and eval case 4 (posture skill must stay tiny). The eval gate below is
> still owed: run the 4-case eval to validate the batch.

Based on a read of the three closest projects in the space (2026-07-10):

- **anthropics/skills → skill-creator** (`skills/skill-creator/SKILL.md`, 485 lines + `agents/{grader,comparator,analyzer}.md` + eval scripts) — the official meta-skill; its v2 added the eval loop.
- **obra/superpowers → writing-skills** (`skills/writing-skills/SKILL.md`, 689 lines + `testing-skills-with-subagents.md`, 384 lines) — the biggest community framework (40.9k stars); treats skill authoring as TDD.
- **metaskills/skill-builder** (273 lines) — small direct sibling; little we don't have.

Ground rule for every item: the pack's identity is 8 lean skills (~30-60 lines each).
Nothing below may double a skill's size. Port the *idea*, not the machinery.
Each phase ends with a re-run of the standing 3-case eval (evals.json) — the
change survives only if the eval doesn't regress.

---

## Phase 1 — Baseline-first forging (the biggest gap)

**Source:** superpowers `writing-skills` — "No skill without a failing test first.
If you didn't watch an agent fail without the skill, you don't know if the skill
teaches the right thing." Their RED-GREEN-REFACTOR maps: baseline run without
skill (RED) → write skill addressing the observed failures (GREEN) → close
loopholes (REFACTOR).

**Gap in skill-smith:** /forge interviews, drafts, then /temper tests — the
baseline check happens *after* the skill exists. Superpowers runs it *before*:
the observed baseline failures become the skill's content, and if the baseline
doesn't fail, you don't forge at all (dead weight caught at birth, not at
/appraise time).

**Changes:**
1. `/forge` — add a "watch it fail first" step between interview and draft:
   run (or ask the user to run) the task once with no skill in a clean context;
   record what went wrong verbatim. Baseline succeeds → stop, recommend no skill.
   The failures become the draft's rules — nothing in the body that doesn't
   answer an observed failure. (~6 lines)
2. `/temper` — the existing baseline-delta step stays as the *verification*
   twin of this; reference forge's baseline record as test #0 when it exists. (~2 lines)

## Phase 2 — Description discipline: never summarize the workflow

**Source:** superpowers SDO section, with an observed failure we should quote:
a description that summarized the workflow ("code review between tasks") made
agents follow the *description* instead of reading the body — the agent did one
review when the skill's body required two. Fixed by trigger-only description.
Also skill-creator: descriptions should be slightly "pushy" because Claude
under-triggers by default.

**Gap:** /forge and /sharpen say "Use when…" but never forbid workflow summaries
— and a workflow-summarizing description passes today's checks.

**Changes:**
1. `/forge` description spec + `/sharpen` — one rule with the why: the
   description says only *when to use*, never *how it works*; a workflow summary
   becomes a shortcut the agent follows instead of reading the body. (~3 lines each)
2. `/sharpen` — keep pushy-vs-bounded as a stated tension: broaden with
   trigger contexts (under-firing is the default), bound with "not for Y"
   boundaries, never with workflow detail. (~2 lines)
3. `/appraise` — add "workflow-in-description" to the weak-description finding. (~1 line)

## Phase 3 — Verdict machinery: rubric, evidence, and the unblind step

**Source:** skill-creator's three agents. Grader: every assertion graded with
`text / passed / evidence`, evidence quotes the output. Comparator: blind A/B
with a small content+structure rubric, decisive ("ties should be rare").
Analyzer: after the blind verdict, *unblind and read the transcripts* — explain
why the winner won, score instruction-following, and turn the loser's gaps into
specific edits.

**Gap:** /temper grades pass/fail but doesn't require quoted evidence; nothing
in the pack does the analyzer move (we did it by hand in iteration 1 — reading
the losing transcript is what surfaced the fabricated "9/9" and the wrong
lexical-overlap diagnosis).

**Changes:**
1. `/temper` verdict table — require evidence per PASS/FAIL that quotes the
   output; no benefit of the doubt (a "Summary" heading with one vague sentence
   is a FAIL). (~3 lines)
2. `/temper` — add the analyzer step for failures: read the run transcript, not
   just the output; classify whether the agent ignored an instruction (ambiguous
   → 🔧), never saw it (activation → ⚡), or invented content (missing anchor
   rule). (~4 lines)
3. `/appraise` — for A/B comparisons between two skills covering the same task,
   point at the blind-comparison pattern: judge labeled outputs first, unblind
   second, edits from the loser's transcript. (~3 lines)

## Phase 4 — Repair: match the form to the failure

**Source:** superpowers' "Match the Form to the Failure" table — the form that
bulletproofs one failure type backfires on another. Skips-a-rule-under-pressure
→ prohibition + rationalization table + red flags. Wrong-shaped output →
positive recipe (prohibitions measurably *increased* the unwanted content in
their wording tests). Omitted element → required slot in a template. Condition-
dependent → conditional on an observable predicate. Plus: no nuance clauses
("don't X unless it matters" reopens the negotiation).

**Gap:** /repair classifies the defect well (5 classes) but prescribes one fix
shape for all of them: rewrite as "When X, do Y". For discipline-type failures
that recur, it has nothing.

**Changes:**
1. `/repair` — after classifying the defect, pick the fix *form* by failure
   type (condensed 4-row table). (~6 lines)
2. `/repair` — for a rule an agent knowingly skipped: capture the
   rationalization verbatim and add its explicit counter to the skill — the
   rationalization-table move, one line at a time, not the full apparatus. (~3 lines)
3. `/temper` — for discipline skills only, test with a pressure scenario
   (deadline + sunk cost + "just this once"), not an academic prompt; the
   skill passes only if the agent complies while citing it. (~4 lines)

## Phase 5 — Craft nits (cheap, do last)

**Sources:** superpowers SDO + skill-builder conventions.

1. `/forge` — prefer gerund/verb-first names (`writing-release-notes` not
   `release-notes-helper`); intention-revealing reference filenames
   (`api-errors.md`, never `reference.md`/`utils.md`). (~2 lines)
2. `/forge` — description keyword coverage: include the error messages and
   symptoms a user would actually paste, not just task nouns. (~1 line)
3. `/armory` — note skills whose description summarizes workflow (Phase 2
   finding) as ⚠ on the sheet. (~1 line)

---

## Deliberately skipped (so nobody re-proposes them)

| Candidate | Why skipped |
|---|---|
| skill-creator's eval-viewer (HTML review UI, generate_review.py) | Heavy tooling; the pack has no scripts and its value is portability. Human review happens in chat. |
| benchmark.json / aggregate_benchmark.py machinery | Same. The ledger + eval table carry the signal at our scale. |
| run_loop.py automated description optimization (60/40 train/test, 5 iterations) | kiro-skill-smith has the method documented; the generic pack keeps the lite version (run prompts 2-3×, majority). |
| persuasion-principles.md (Cialdini framing) | Interesting, but the rationalization-counter move in Phase 4 is the actionable core. |
| Flowcharts / graphviz conventions | Superpowers-specific taste; adds deps and weight. |
| Gerund renames of the existing 8 skills | The seven strikes are the brand (forge, smelt, temper…). Naming guidance applies to skills the smith *makes*, not to itself. |

## Sequencing and gate

Order: 1 → 2 → 3 → 4 → 5. One phase per session; after each, re-run the 3-case
eval (fresh sessions, blind grading, assertions in evals.json) plus one new case
per phase probing the change itself — e.g. Phase 1 adds: "make me a skill for
writing haiku about git commits" (a task the model does fine bare; correct
output = the smith *refuses to forge* and says why). Ledger records each phase
as a /sharpen entry.

Also applies to kiro-skill-smith (not in scope here): Phase 1 baseline-first and
Phase 4 form-matching port cleanly; its description-optimization flow already
covers Phase 2's method but not the never-summarize-workflow rule — worth adding.
