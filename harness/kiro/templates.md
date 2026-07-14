# Kiro harness pack — templates (armor scaffolds)

> Salvaged 2026-07-14 from the old kiro-skill-smith. Shapes verified against
> `mechanics.md` (same snapshot). Skills are NOT here — blades belong to
> /skill-forge and the agentskills.io spec; these are the armor pieces.

## Steering — always-on (`.kiro/steering/<topic>.md`)

```markdown
# <Topic> conventions

<Rule>. Reason: <why>.
<Rule>. Reason: <why>.

## Examples
- Preferred: <snippet>
- Avoid: <snippet>  — because <reason>
```

## Steering — conditional (glob-scoped; default for domain-specific rules)

```markdown
---
inclusion: fileMatch
fileMatchPattern: "**/*.tsx"
---

# React component conventions

<Rules that only matter when editing components.>
```

## Steering — manual (on-demand; heavy content that must NOT ride every turn)

```markdown
---
inclusion: manual
---

# Incident runbook

<Reference it in chat when needed.>
```

Pick the narrowest inclusion that works — always-on steering costs tokens every
turn whether used or not. Rule of thumb: 3–5 steering docs in active scope.

## Agent hook (event-triggered automation)

State trigger and action plainly first:

```
When: a file matching src/schema/*.ts is saved
Do:   regenerate TypeScript types and run the type-check, report failures
```

v2 shape — lives in an agent's `hooks` field; matchers use **internal** tool
names (`fs_write`/`fs_read`/`execute_bash`/`use_aws`):

```json
"hooks": {
  "postToolUse": [{ "matcher": "fs_write", "command": "prettier --write \"$KIRO_TOOL_PATH\"" }],
  "stop":        [{ "command": "npm test" }]
}
```

v3: the same hook becomes a standalone `.kiro/hooks/<name>.json` with a
versioned schema (PascalCase triggers, e.g. `PostToolUse`/`Stop`) that applies
across all agents. See `mechanics.md` §8.

## Custom agent (`.kiro/agents/<name>.json`) — start restrictive

Wiring traps live in `mechanics.md` §1 and §5: resource loading is
version-dependent (verify with `/context show`), `allowedTools ⊆ tools`,
MCP needs all three keys. Keep explicit `resources` wiring as the portable
safe default:

```json
{
  "name": "be",
  "description": "Backend role — Rails + maintenance scripts only.",
  "prompt": "You work on the Rails app and the maintenance-scripts repo.",
  "tools": ["read", "grep", "glob", "write", "shell"],
  "allowedTools": ["read", "grep", "glob"],
  "resources": [
    "file://.kiro/steering/**/*.md",
    "skill://.kiro/skills/**/SKILL.md"
  ]
}
```

## Rule form (steering lines, spec criteria)

One trigger + verdict, tagged descriptive/aspirational, evidence-anchored:

```markdown
**[descriptive]** **When** generating a DB migration, the agent shall name
columns in `snake_case`. ← *PR #431, #455 (reviewer flagged camelCase)*
```

## Spec (feature build — `/spec` in v3)

```
.kiro/specs/<name>/
  requirements.md  → what we're building and acceptance criteria
  design.md        → architecture, data flow, decisions
  tasks.md         → ordered, checkable implementation steps
```
