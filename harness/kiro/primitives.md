# Kiro harness pack — primitives (which artifact type?)

> Last verified: 2026-07-14 against kiro-cli **2.12.1**. Mechanics + wiring traps:
> `mechanics.md`.

Resolve this BEFORE writing anything. The wrong artifact type is the root cause
of most `.kiro/` mess.

## The routing tree (ask in order — first match wins)

Order matters: earlier primitives can *contain* later ones, and "always-on
knowledge" is the catch-all, not the default.

1. **"When EVENT happens, run a COMMAND automatically"?** (format on save, audit
   or block a command, run tests on stop) → **Agent Hook**
2. **Restrict/pre-approve TOOLS, set PERMISSIONS, or define a bounded ROLE?**
   ("this role may only touch `db/**`", "no-prompt for read + git status") →
   **Custom Agent**
3. **Connect an EXTERNAL tool / service / API?** → **MCP server**
4. **A multi-step PROCEDURE for a specific task type, loaded only when relevant?**
   ("our DB migration runbook", "our PR-review checklist") → **Skill**
5. **A multi-step feature build** (requirements → design → tasks) → **Spec**
6. **Otherwise — always-true background knowledge/convention?** → **Steering**

### The determinism test (the edge that trips people)

The moment you catch yourself writing a steering rule like *"always run X after
Y,"* that **"always" wants a HOOK** — steering is guidance the model *may* follow;
a hook is a mechanism that *always* runs. The model will eventually forget; the
hook won't.

### Skill vs Custom Agent

A skill is *knowledge*; an agent is *identity + tool/permission scope*. A skill
**cannot** restrict tools. If the requirement includes "can only touch X" or
"don't prompt for Y," it's an agent, not a skill. (Wiring an agent correctly is
its own trap — see `mechanics.md` §0–§5.)

## The one-question test (steering vs skill, the most common fork)

> "Should this knowledge apply on *every* turn in this project, or only when a
> specific task calls for it?"

- **Every turn, project-wide** → **Steering** (`.kiro/steering/*.md`)
- **Only when a task needs it** → **Skill** (`.kiro/skills/<name>/SKILL.md`)
- **In response to an event** (file saved, etc.) → **Agent Hook**
- **A multi-step feature build** (requirements → design → tasks) → **Spec**

## Steering — always-on project context

Markdown in `.kiro/steering/`. Loaded as persistent context so Kiro follows your
conventions without being re-told. Use for:
- Code style, naming, import ordering, architecture decisions
- Security guidelines (auth requirements, validation rules, sanitization)
- Project structure and domain/business rules
- "Always respond in language X" type behavior rules

Inclusion modes (pick the narrowest that works — this is your bloat control):
- **Always** — loaded every interaction. Reserve for genuinely universal rules.
- **Conditional** — loaded only when editing files matching a glob (e.g. React
  rules only when touching `*.tsx`). Default for domain-specific guidance.
- **Manual** — loaded only when referenced in chat; surfaces as a slash command.
  Best for specialized workflows, troubleshooting guides, heavy docs.

Rule of thumb: 3–5 steering docs in active scope per task. More than that and
you're probably bloating context.

## Skill — on-demand capability

A directory with `SKILL.md` (YAML frontmatter + instructions) plus optional
`references/`, `scripts/`, and assets. Loads only when the `description` matches
the task. Use for:
- Specialized procedures: database backup/restore/migration, deployment steps
- Domain capabilities that shouldn't burn context when irrelevant
  (a Terraform skill is dead weight while you write React)
- Team/organization workflows that span workspaces
- Anything that benefits from bundled scripts or reference files

Key difference from steering: steering is *always-on Markdown*; a skill is a
*portable, reusable package* that loads on demand and can carry executable code.

## Custom Agent — identity + tool/permission scope

A `.kiro/agents/<name>.json` (v3: md+frontmatter) bundling `{prompt + scoped
tools + wired steering + wired skills + hooks}` into a named role. Use for:
- **Tool/permission scoping** — "this role may not touch `prod/**`", or
  pre-approve only `read` + `git status`.
- **Context isolation** in a large multi-domain repo — a `fe` agent loads only
  frontend skills/steering, a `be` agent only backend, so neither bloats the other.
- **A clean-room skill test harness** — an agent that wires *only* the skill under
  test plus a read tool, to confirm it loads and activates.

The trap: a custom agent **loads nothing by default** — you must wire `resources`
(`file://` steering + `skill://` skills) and `tools`/`subagent`. For a solo
contractor, don't create agents just to "organize" — the default agent + a few
skills is leaner and trap-free. (Wiring contract: `mechanics.md` §0–§5.)

## MCP server — external tools

A `.kiro/settings/mcp.json` entry or an agent `mcpServers` block that connects an
external tool/service/API (a database client, an issue tracker, a browser). Use
when the capability lives *outside* Kiro and needs a running server, not when it's
knowledge or a procedure. MCP tools are referenced as `@server/tool`.

## Agent Hook — event-triggered automation

Runs an agent action when something happens (file save, manual trigger, etc.).
Use for repetitive reactions: regenerate types on schema save, run lint-fix on
save, update a changelog. Not for knowledge — for *reactions*. The decisive test:
does it need to happen **deterministically on an event**, not just "when the model
remembers"? Then it's a hook. (v2: lives in an agent's `hooks` field; v3:
standalone `.kiro/hooks/<n>.json` — see `mechanics.md` §8.)

## Spec — structured feature build

Spec-driven development: a feature is broken into requirements → design → tasks,
and Kiro executes against them. Use when building a feature big enough that you
want the intent captured and tracked, not a one-off edit.

## Worked routing examples

| You want… | Artifact | Why |
|---|---|---|
| "Always use our error-handling pattern" | Steering (always) | universal, every turn |
| "React rules, but only in component files" | Steering (conditional) | scoped to `*.tsx` |
| "Our DB migration runbook" | Skill | specialized, on-demand, has scripts |
| "Review PRs for security" | Skill | task-triggered expertise |
| "Run tests when I save a test file" | Hook | event reaction |
| "Build the checkout feature" | Spec | multi-step, intent worth tracking |
| "A backend role that can't touch the frontend tree" | Custom Agent | tool/permission scope + context isolation |
| "Let the agent query our Jira" | MCP server | external service, needs a running server |
| "Lint-fix every file the agent writes" | Hook (`postToolUse` `fs_write`) | deterministic, on an event |
| "Translate all answers to Spanish" | Steering (always) | behavior rule, every turn |
