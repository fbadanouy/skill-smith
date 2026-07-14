# Claude Code harness pack — primitives (which artifact type?)

> Last verified: 2026-07-15 against claude-code **2.1.209**, docs fetched 2026-07-15.
> Mechanics + wiring traps: `mechanics.md` (receipts live there).

Resolve this BEFORE writing anything. The wrong artifact type is the root cause of
most `.claude/` mess.

## The routing tree (ask in order — first match wins)

Order matters: earlier primitives can *contain* later ones, and "always-on
knowledge" is the catch-all, not the default.

1. **"When EVENT happens, DO something — always"?** (format on save, block a
   command, keep going until tests pass, load env on cd) → **Hook** (in
   `settings.json`, or scoped inside a skill/agent frontmatter)
2. **Grant, forbid, or force-confirm a TOOL/path/domain — enforced, not asked
   nicely?** → **Permission rules** (`permissions.allow/ask/deny`), plus a
   **permission mode** for the session baseline
3. **An isolated SPECIALIST — own context window, own tools/model/prompt, or
   just "keep this noise out of my conversation"?** → **Subagent**
   (`.claude/agents/*.md`)
4. **Connect an EXTERNAL tool / service / API?** → **MCP server** (`.mcp.json`)
5. **A PROCEDURE for a specific task type, loaded only when relevant — or a
   command a human types?** ("our DB migration runbook", `/deploy`) → **Skill**
   (`.claude/skills/<name>/SKILL.md`; slash commands ARE skills now)
6. **A different VOICE/ROLE for every response** (not project knowledge)?
   → **Output style**
7. **Otherwise — always-true background knowledge/convention?** → **CLAUDE.md**
   (or a `paths:`-scoped rule in `.claude/rules/` if it only matters near
   certain files)
8. **Shipping any of the above to other repos/teams?** → wrap it in a **Plugin**

### The determinism test (the edge that trips people)

The moment you catch yourself writing a CLAUDE.md line like *"always run X after
Y"* or *"never touch Z,"* that **"always/never" wants a hook or a deny rule** —
CLAUDE.md is delivered as a plain user message the model *may* follow
(`memory.md:398`); hooks and permission rules are enforced by the client
regardless of what the model decides (`permissions.md:40`, `memory.md:407`).
The model will eventually forget; the hook won't. Corollary inside hooks: the
`if:` filter is best-effort and fails open — a hard boundary belongs in
permission rules, with the hook as the flexible layer on top (`hooks.md:342`).

### Skill vs subagent (the second-most-common fork)

A skill is *knowledge injected into the current conversation*; a subagent is
*identity + isolation + tool scope*. A skill's `allowed-tools` can only
pre-approve, never restrict (`skills.md:373`) — if the requirement includes
"can ONLY use read tools" or "keep its output out of my context," it's a
subagent. The two compose: `context: fork` runs a skill *in* a subagent; a
subagent's `skills:` field preloads skill bodies into its context.

## The one-question test (CLAUDE.md vs skill, the most common fork)

> "Should this apply on *every* turn in this project, or only when a specific
> task calls for it?"

- **Every turn, project-wide** → **CLAUDE.md** (fact-shaped, short)
- **Only near certain files** → **rule with `paths:`** (`.claude/rules/`)
- **Only for a task type / on demand** → **Skill** (procedure-shaped, can be long)
- **In reaction to an event** → **Hook**

The docs' own heuristic: create a skill "when a section of CLAUDE.md has grown
into a procedure rather than a fact" (`skills.md:11`).

## CLAUDE.md & rules — always-on context

Loaded in full every session (ancestors of cwd + `~/.claude/CLAUDE.md` +
managed + `CLAUDE.local.md`). Use for: build/test commands, conventions,
architecture facts, "respond in language X" behavior. Keep each file under
~200 lines (`memory.md:81`); split domain rules into `paths:`-scoped
`.claude/rules/*.md` so they load only near matching files — that's the bloat
control. Not enforcement — pair critical rules with a hook or deny rule.

## Skill — on-demand capability + command surface

A directory with `SKILL.md` (frontmatter + instructions) plus optional
scripts/references. Description sits in context; body loads on `/name` or when
Claude matches the description. Distinctive Claude Code powers:
- `disable-model-invocation: true` → human-only trigger (deploy, commit)
- `user-invocable: false` → Claude-only background knowledge
- `` !`cmd` `` dynamic context — command output inlined *before* Claude reads it
- `$ARGUMENTS` / `$0..$n` argument substitution
- `context: fork` + `agent:` → run in an isolated subagent
- `allowed-tools` → pre-approve tools while active (grant, not restrict)

## Hook — event-triggered enforcement/automation

Fires at lifecycle edges (`SessionStart`, `UserPromptSubmit`, `PreToolUse`,
`PostToolUse`, `Stop`, `SubagentStop`, `PreCompact`, `SessionEnd`, ~30 total).
Five handler types: `command`, `http`, `mcp_tool`, `prompt`, `agent`. Use for
*reactions and gates*, not knowledge: lint after edits, block `rm -rf`, inject
git context at session start, refuse to stop until tests ran. Exit 2 blocks
(where blockable); exit 1 does NOT. Scope options: settings file (always),
skill/agent frontmatter (only while that component is active).

## Permission rules — the hard boundary

`Tool` or `Tool(specifier)` strings in `permissions.allow/ask/deny`; resolution
deny > ask > allow, first match, specificity irrelevant. Use for: pre-approving
safe commands (kill the prompts), fencing secrets (`Read(./.env)` deny),
blocking domains/tools. Session baseline via modes: `default`, `acceptEdits`,
`plan`, `auto`, `dontAsk`, `bypassPermissions`. Remember: project allow rules
wait on workspace trust; a deny anywhere beats an allow everywhere.

## Subagent — isolation + role scope

Markdown + frontmatter in `.claude/agents/`. Use for:
- **Context economy** — high-volume search/tests/logs stay in the subagent's
  window; only the summary returns
- **Tool/permission scoping** — `tools:` allowlist, `permissionMode`, PreToolUse
  hooks in frontmatter (e.g. read-only DB role)
- **Cheap/parallel work** — `model: haiku`, background by default, nested spawns
- **Cross-session specialist memory** — `memory: project`
Not for: quick targeted edits or work needing your conversation context (use a
fork or stay in the main thread).

## MCP server — external tools

`.mcp.json` (project, committed, approval-gated) or `~/.claude.json`
(local/user scope). Use when the capability lives *outside* Claude Code and
speaks MCP — issue trackers, databases, browsers. Tools arrive as
`mcp__server__tool`, gated by the same permission flow. To keep a chatty
server's tool descriptions out of the main context, declare it inline in a
subagent's `mcpServers:` instead (`sub-agents.md:420`).

## Output style — voice, not knowledge

Modifies the system prompt itself (role/tone/format); optionally drops the
built-in software-engineering instructions. Use for "always answer with a
diagram" or non-coding personas — never for project conventions (that's
CLAUDE.md). Applied at session start; changes need `/clear`.

## Plugin — distribution, not a new capability

A directory (optionally with `.claude-plugin/plugin.json`) bundling skills,
agents, hooks, MCP servers, output styles under a `plugin:component` namespace.
Route here only when the need is *sharing/versioning across repos or teams*;
for one project, standalone `.claude/` is leaner (`plugins.md:15-38`).

## Worked routing examples

| You want… | Artifact | Why |
|---|---|---|
| "Always use our error-handling pattern" | CLAUDE.md | universal fact, every turn |
| "API rules, but only under `src/api/`" | Rule with `paths:` | scoped, loads lazily |
| "Our DB migration runbook" | Skill | procedure, on-demand, can bundle scripts |
| "`/deploy` that only a human can trigger" | Skill + `disable-model-invocation: true` | command surface, human-gated |
| "Run prettier on every file Claude edits" | Hook (`PostToolUse`, matcher `Edit\|Write`) | deterministic, on an event |
| "Claude must never read `.env`" | Permission deny `Read(./.env)` | hard boundary, client-enforced |
| "Stop prompting me for `npm test`" | Permission allow `Bash(npm test *)` | pre-approval |
| "Don't let it stop before tests pass" | `Stop` hook (`decision: block`) | autonomy loop |
| "Review PRs without flooding my context" | Subagent (read-only tools) | isolation + tool scope |
| "A read-only DB analyst role" | Subagent + PreToolUse hook | role + runtime validation |
| "Let Claude query our Jira" | MCP server | external service |
| "Answers as tutor with quizzes" | Output style | voice/role, every response |
| "Ship our review toolkit to 12 repos" | Plugin | distribution wrapper |
| "Remember that staging DB is `pg-stg-3`" | CLAUDE.md (or let auto memory catch it) | fact, every session |
