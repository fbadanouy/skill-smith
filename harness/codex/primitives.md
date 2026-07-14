# Codex CLI harness pack — primitives (which artifact type?)

> Last verified: 2026-07-15 against codex-cli **0.144.1**. Mechanics + wiring traps:
> `mechanics.md`. Every capability claimed here is quoted in `mechanics.md` Evidence.

Resolve this BEFORE writing anything. The wrong artifact type is the root cause of most
`.codex/` + `.agents/` mess.

## The routing tree (ask in order — first match wins)

1. **"When EVENT happens, run a COMMAND automatically"?** (log prompts, block a command
   pattern via script, keep-going check on stop) → **Hook** (`hooks.json` / `[hooks]`)
2. **Allow / prompt / forbid a specific COMMAND outside the sandbox?** ("never `git push
   --force`", "always allow `docker ps`") → **Rules** (`.rules` `prefix_rule`) — cheaper
   and more auditable than a PreToolUse hook for pure command policy
3. **A reusable PERMISSION/SANDBOX/MODEL posture?** ("my CI posture", "deep-review
   settings") → **config.toml + profile file** (`~/.codex/<name>.config.toml`)
4. **A bounded ROLE with its own model/instructions/sandbox for delegated work?**
   ("read-only reviewer", "browser debugger") → **Custom agent** (`.codex/agents/*.toml`)
5. **Connect an EXTERNAL tool / service / API?** → **MCP server** (`[mcp_servers.<name>]`)
6. **A multi-step PROCEDURE for a specific task type, loaded only when relevant?**
   ("DB migration runbook", "PR-review checklist") → **Skill** (`.agents/skills/<n>/SKILL.md`)
7. **Otherwise — always-true background knowledge/convention?** → **AGENTS.md**

### The determinism test

A rule in AGENTS.md saying *"always run X after Y"* is guidance the model may forget. If
it must happen **every time on an event**, it's a Hook (deterministic script) or a Rule
(deterministic command policy). Caveat specific to Codex: hooks only intercept Bash,
`apply_patch`, and MCP calls — "not … `WebSearch` or other non-shell, non-MCP tool calls"
— so a hook is a guardrail, not a boundary. Hard boundaries = sandbox mode + rules.

### Skill vs custom prompt (the Codex-specific fork)

**Custom prompts are deprecated** ("Custom prompts are deprecated. Use skills"). The old
split, for reading legacy setups:

| | Custom prompt (`~/.codex/prompts/*.md`) | Skill (`.agents/skills/<n>/SKILL.md`) |
|---|---|---|
| Invocation | **explicit only** — `/prompts:<name>` | explicit (`$name`, `/skills`) **and implicit** (description match) |
| Sharing | local home dir only, not in the repo | checked into the repo, plugin-distributable |
| Payload | one markdown file + `$1`/`$ARGUMENTS`/`$NAMED` expansion | directory: instructions + `scripts/` + `references/` + `assets/` |
| New work | don't create | default. Want explicit-only prompt behavior? `agents/openai.yaml` → `policy.allow_implicit_invocation: false` |

### Skill vs AGENTS.md (the most common fork)

> "Should this apply on *every* turn, or only when a specific task calls for it?"

- **Every turn, project-wide** → AGENTS.md. But the whole chain is capped at **32 KiB**
  and rides every session — keep it to conventions, not runbooks.
- **Only when a task needs it** → Skill. Costs one name+description line until it
  activates (and even the list of descriptions is budgeted at 2% of context / 8,000 chars,
  with descriptions shortened first — front-load trigger words).
- **Scoped to a subtree** → nested `AGENTS.md` in that directory (loads only when cwd is
  at/below it), or `AGENTS.override.md` to *replace* broader guidance there.

### Skill vs custom agent

A skill is *knowledge*; a custom agent is *identity + model + sandbox scope for delegated
work*. A skill cannot restrict tools or change sandbox mode. "Reviewer that can't write"
→ custom agent with `sandbox_mode = "read-only"`. Note the Codex twist: custom agents are
**subagent roles** (spawned for delegation), not top-level session presets — for "start my
whole session locked down", use a **profile** instead.

## AGENTS.md — always-on instructions

Layered: `~/.codex/AGENTS.md` (global) → repo root → nested dirs down to cwd; closest
file wins by appearing last; `AGENTS.override.md` replaces its sibling. Use for: build/test
commands, conventions, working agreements ("run `npm run lint` before a PR"), delegation
policy ("use subagents for exploration"). Skills/AGENTS.md instructions can trigger
subagent delegation, so this is also where standing orchestration policy lives.

## Skill — on-demand capability

Directory with `SKILL.md` (frontmatter `name` + `description` required) plus optional
`scripts/`, `references/`, `assets/`, `agents/openai.yaml` (UI metadata, invocation
policy, tool dependencies). agentskills.io standard — portable across harnesses. Scaffold
with `$skill-creator`; install curated ones with `$skill-installer`; disable without
deleting via `[[skills.config]]`. Distribution beyond one repo → package as a plugin.

## config.toml profile — permission/sandbox/model posture

A named overlay file `~/.codex/<name>.config.toml` with top-level keys, selected with
`--profile <name>` (works for `codex` and `codex exec`). Use for: sandbox+approval
presets (`full_auto`, `readonly_quiet`), per-task model/reasoning bundles. Trap: since
0.134 it must be a **separate file** — `[profiles.x]` tables are dead. Project-scoped
overrides go in `<repo>/.codex/config.toml` (trusted projects only; provider/notify keys
ignored there).

## Rules — command policy outside the sandbox

Starlark `prefix_rule(pattern=[…], decision="allow|prompt|forbidden")` in
`~/.codex/rules/*.rules` or `<repo>/.codex/rules/` (trusted). Most restrictive decision
wins; safe `bash -lc` chains are split per-command so allow-listing `git add` can't
smuggle `rm -rf /`. Test with `codex execpolicy check --pretty --rules <file> -- <cmd>`.
Experimental — expect drift.

## Hook — event-triggered automation

`hooks.json` next to any active config layer, or inline `[hooks]` in config.toml. Events:
`SessionStart`, `UserPromptSubmit` (can block), `PreToolUse` (deny / rewrite via
`updatedInput`), `PermissionRequest` (auto-allow/deny approvals; any deny wins),
`PostToolUse` (feedback replaces tool result), `PreCompact`/`PostCompact`,
`SubagentStart`/`SubagentStop`, `Stop` (`decision:"block"` → reason becomes a new user
prompt = autonomy loop). Only `type:"command"` handlers run today; JSON in on stdin, JSON
out on stdout; exit 2 + stderr = block/feedback. **Trust gate:** new/changed non-managed
hooks are skipped until reviewed in `/hooks`. So yes — Codex has a real hook system; its
gap is coverage (shell/apply_patch/MCP only), not existence.

## Custom agent — delegated role

One TOML per agent (`~/.codex/agents/` or `.codex/agents/`): `name`, `description`,
`developer_instructions` required; `model`, `model_reasoning_effort`, `sandbox_mode`,
`mcp_servers`, `skills.config` optional (inherit from parent when omitted). Built-ins:
`default`, `worker`, `explorer` (a custom agent with the same name overrides). Fan-out
knobs: `[agents] max_threads` (6), `max_depth` (1). Batch mode: `spawn_agents_on_csv`.

## MCP server — external tools

`[mcp_servers.<name>]` in config.toml (user-level, or project `.codex/config.toml` in
trusted repos). stdio (`command`/`args`/`env`) or streamable HTTP (`url` + bearer/OAuth;
`codex mcp login <name>`). Per-server/per-tool approval: `default_tools_approval_mode =
"auto"|"prompt"|"writes"|"approve"`, `tools.<tool>.approval_mode`; `enabled_tools`/
`disabled_tools`; `required = true` to fail startup instead of degrading. Shared with the
ChatGPT desktop app and IDE extension.

## Notifications — the "after the turn" side channel

Not automation-grade, but often what people actually want: `notify = ["python3", "…"]`
runs an external program on `agent-turn-complete` with a JSON payload;
`tui.notifications` for in-terminal alerts. For anything decision-making, use hooks.

## Gaps (stated plainly)

- **No steering-style inclusion modes.** AGENTS.md has no glob-conditional loading —
  scoping is by directory nesting only. Domain rules for `*.tsx` etc. → a skill or a
  nested AGENTS.md, not a fileMatch mode.
- **No native spec workflow.** Nothing like Kiro's `/spec` (requirements → design →
  tasks) in the fetched CLI docs. Closest: a skill that encodes your spec procedure, or
  Codex cloud tasks (different product surface).
- **No knowledge base / semantic index primitive.** Big-corpus grounding → an MCP server
  (docs MCP, Context7) or skill `references/`.
- **Hook handler types `prompt` and `agent` are parsed but skipped** — command scripts
  only, today. Async hooks likewise not yet supported.

## Worked routing examples

| You want… | Artifact | Why |
|---|---|---|
| "Always run `npm test` after JS changes" (as convention) | AGENTS.md (global or repo) | working agreement, every turn |
| "…and actually enforce it before Codex stops" | Hook (`Stop`, `decision:"block"` when tests unrun) | deterministic, event-driven |
| "Payments dir has stricter rules than the repo" | Nested `AGENTS.override.md` in `services/payments/` | directory-scoped replacement |
| "Our DB migration runbook with helper scripts" | Skill | on-demand, carries `scripts/` |
| "A `/draftpr`-style macro" | Skill with `allow_implicit_invocation: false` | prompts are deprecated |
| "Never let it `git push --force`" | Rules (`prefix_rule` `forbidden`) | command policy, restrictive-wins |
| "A locked-down posture for demos: read-only, never ask" | Profile (`~/.codex/demo.config.toml`) | reusable sandbox+approval preset |
| "Read-only reviewer subagent on a cheap model" | Custom agent (`sandbox_mode = "read-only"`, `model = …`) | role + scope for delegation |
| "Let the agent query Figma / our issue tracker" | MCP server | external service |
| "Block prompts containing API keys" | Hook (`UserPromptSubmit`, block shape) | pre-model gate |
| "Auto-approve harmless approvals in CI, deny the rest" | Hook (`PermissionRequest`) or `approval_policy = { granular = … }` | approval-flow automation |
| "Desktop toast when a turn finishes" | `notify` in config.toml | side channel, not context |
| "Nightly triage job in CI" | `codex exec --json` + profile | headless, machine-readable |
