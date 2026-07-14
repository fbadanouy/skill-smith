---
name: skill-forge
description: Create a new agent skill. Use when the user wants a new skill or wants a repeated workflow turned into one. Interviews, writes SKILL.md to spec, hands to /skill-temper.
---

# ⚒️ /skill-forge · create a skill

Reply in the Skill-Smith frame: `⚒️ /skill-forge · {action}`, one metaphor+truth line, ▬ bar, then plain work.

## Step zero — is this even a skill?

Detect the platform (`.kiro/` → Kiro, `.codex/` or `AGENTS.md` → Codex, `.claude/` → Claude Code). If a harness pack exists (`harness/<platform>/` in the skill-smith repo or beside the skills dir), read its `primitives.md` and route: event-triggered → hook; tool/permission scoping → agent config; external service → MCP; always-on convention → steering/CLAUDE.md/AGENTS.md. Only an on-demand procedure is a skill. Not a skill → name the right primitive, ground the call in the pack (or official docs — never memory), and hand to 🪖 /skill-smith-fit.

## Interview first

- What task, concretely? Ask for one real, recent example. None exists → warn, offer a minimal draft.
- One coherent unit of work? "Query the DB" and "administer the DB" are two skills; three fragments that always co-load are one. Scope it like a single function.
- How often? needed constantly → belongs in steering, send back to /skill-smith. per-task → skill. rarely → leave it in docs.
- Personal (global skills dir) or team (workspace dir, committed)?
- What does failure look like? → becomes the /skill-temper test criteria.

## Check for duplicates

If an existing skill covers most of the request, stop and recommend /skill-sharpen on it instead.

## Classify the metal (what kind of skill is this?)

- **posture** — a behavioral contract the model *could* follow but won't by default ("argue with me", "be terse"). Highest leverage, smallest body: ~25 lines, no references/, no interview about formats. Don't forge a posture into a procedure.
- **procedure** — steps the model wouldn't infer. Gets the full treatment below.
- **reference** — facts it can't know (APIs, project specifics). Body stays thin; facts live in references/.

## Watch it fail first

Before drafting, run the task once with NO skill in a clean context (or ask the user to). Record what went wrong, verbatim. The baseline succeeds → stop; recommend no skill — a skill for a task the model already does is dead weight at birth. The observed failures become the draft's rules: nothing goes in the body that doesn't answer a failure you saw. Encode the generalizing rule each failure exposes, not the answer to that one case — the instance becomes a /skill-temper test, not a body rule.

## Draft, then get approval

Show the draft frontmatter (name + description) and a body outline BEFORE writing any file.
Nothing touches disk until the user approves. A terse request does not waive this.

## Write to spec

```
<name>/SKILL.md   (+ references/ for long detail, loaded only when pointed to
                   + scripts/ for deterministic steps)
```
- name: lowercase-hyphen, ≤64 chars, must equal the folder name. Prefer verb-first/gerund names (`writing-release-notes`, not `release-notes-helper`). Reference files get intention-revealing names (`api-errors.md`, never `reference.md`/`utils.md`).
- description: ≤1024 chars. It alone decides activation. Write "Use when …" with the exact words, error messages, and symptoms a user would actually type. Never a summary — and never a workflow summary: a description that says *how* the skill works becomes a shortcut the agent follows instead of reading the body (observed: "code review between tasks" in a description made agents do one review when the body required two). When to use only, never how. Quote it if it contains `:`.
- body: testable rules ("When X, do Y"), not advice-prose. Keep under ~150 lines; move overflow to references/, and say WHEN to load each ("Read references/errors.md if the API returns non-200") — except surprising gotchas: those stay in the body, because a surprise the agent doesn't anticipate never triggers a reference load. Don't re-explain things the model already knows — name them. Cut any rule you can't tie to a real problem. Add `$ARGUMENTS` if it takes input.
- facts: every factual claim about the project (a gotcha, an error shape, a command) needs an anchor — a file:line, a quote, or the real task it came from. No anchor → ask the user, don't write it. A guessed gotcha is worse than none.
- one default, not a menu: pick one tool/approach, mention alternatives in a word. Prescribe exact steps only where order matters or the operation is fragile; elsewhere state the goal and the why.
- deterministic work (validation, generation, format conversion) → a `scripts/` file the skill calls, not prose the model re-derives each run.

## Verify and record

Confirm the file loads (valid frontmatter, right folder), then hand to 🗡️ /skill-temper.
Add a row to `ledger.md`: name, date, purpose, trigger phrases.

$ARGUMENTS
