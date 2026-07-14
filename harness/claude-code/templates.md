# Claude Code harness pack — templates (armor scaffolds)

> Verified 2026-07-15 against claude-code **2.1.209**; shapes grounded in
> `mechanics.md` (same snapshot). Skills are NOT here — SKILL.md belongs to
> /skill-forge and the agentskills.io spec; these are the armor pieces.

## CLAUDE.md section (project root `CLAUDE.md` or `.claude/CLAUDE.md`)

Fact-shaped, verifiable, under ~200 lines total. Concatenated with ancestor /
user / managed files — don't contradict them.

```markdown
# <Project>

## Commands
- Build: `npm run build`   Test: `npm test`   Lint: `npm run lint`

## Conventions
- <Rule, concrete enough to verify>. Reason: <why>.
- API handlers live in `src/api/handlers/`.

## Claude-specific
@docs/git-instructions.md   <!-- imports expand at launch, max 4 hops -->
```

If the repo already has `AGENTS.md`: first line `@AGENTS.md`, then append
Claude-specific content (or `ln -s AGENTS.md CLAUDE.md`).

## Path-scoped rule (`.claude/rules/<topic>.md`) — default for domain rules

```markdown
---
paths:
  - "src/api/**/*.{ts,tsx}"
---

# API development rules

- All endpoints must include input validation
- Use the standard error response format
```

No `paths:` → loads at launch like CLAUDE.md. Pick the narrowest scope that
works — that's your bloat control.

## Hook (settings.json shape, with matcher)

State trigger and action plainly first:

```
When: Claude edits or writes any file
Do:   run the project linter on it; block nothing (report only)
```

In `~/.claude/settings.json`, `.claude/settings.json`, or
`.claude/settings.local.json`:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/lint.sh",
            "args": [],
            "timeout": 60
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          { "type": "command", "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/check-done.sh", "args": [] }
        ]
      }
    ]
  }
}
```

Matcher rules (the gotchas): exact string(s) `Edit|Write` for plain names;
any other character ⇒ **unanchored JS regex** — anchor `^Edit$` for whole-string;
MCP tools need `mcp__server__.*` (bare `mcp__server` matches nothing); `Stop`,
`UserPromptSubmit` etc. take no matcher (silently ignored). Set `args: []` to
force exec form when the command is a path placeholder.

Blocking script contract: read JSON on **stdin**, block with **exit 2 +
stderr** (exit 1 does NOT block), or exit 0 + JSON on stdout for structured
decisions — never both:

```bash
#!/bin/bash
command=$(jq -r '.tool_input.command' < /dev/stdin)
if [[ "$command" == *"rm -rf"* ]]; then
  echo "Blocked: destructive command" >&2
  exit 2
fi
exit 0
```

Stop-hook autonomy loop (exit 0 + JSON; check `stop_hook_active` in input to
avoid loops — hard cap 8 continuations):

```json
{ "decision": "block", "reason": "Tests haven't been run yet. Run npm test first." }
```

## Subagent (`.claude/agents/<name>.md`) — start restrictive

Identity = the `name` field (not the filename). Only `name` + `description`
required. Explore/Plan skip CLAUDE.md; every custom agent loads it.

```markdown
---
name: db-reader
description: Execute read-only database queries. Use when the user asks to inspect data, check row counts, or debug query results.
tools: Bash, Read, Grep, Glob
model: haiku
permissionMode: default
memory: project
skills:
  - db-conventions
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "${CLAUDE_PROJECT_DIR}/.claude/hooks/validate-readonly-query.sh"
          args: []
---

You are a read-only database analyst. Run SELECT queries only; never modify
data. Report findings with the exact query used. Update your agent memory
with schema facts you discover.
```

`tools:` is the allowlist (omit `Agent` → can't spawn subagents; omit the
field entirely → inherits all tools). `skills:` preloads FULL skill content at
startup. Frontmatter `Stop` hooks auto-convert to `SubagentStop`.

## Permission rules block (any settings scope; arrays merge across scopes)

```json
{
  "permissions": {
    "allow": [
      "Bash(npm run test *)",
      "Bash(git status)",
      "Bash(git diff *)",
      "Read(~/.zshrc)"
    ],
    "ask": [
      "Bash(git push *)"
    ],
    "deny": [
      "Read(./.env)",
      "Read(./.env.*)",
      "Read(./secrets/**)",
      "Bash(curl *)",
      "WebFetch"
    ],
    "additionalDirectories": ["../shared-lib"],
    "defaultMode": "default"
  }
}
```

Syntax reminders: deny > ask > allow, first match, specificity irrelevant —
no allow-holes through a deny (invert: broad allow + PreToolUse blocking hook).
`Bash(ls *)` ≠ `Bash(ls*)` (word boundary). File paths are gitignore-style:
`//abs/path`, `~/home`, `/relative-to-settings-source`, bare = cwd-relative.
Compound Bash commands must match per-subcommand. Project `allow` rules are
inert until workspace trust is accepted (and always inert in `-p` mode).

## `.mcp.json` entry (project scope — committed, approval-gated)

```json
{
  "mcpServers": {
    "github": {
      "type": "http",
      "url": "https://api.githubcopilot.com/mcp/",
      "headers": { "Authorization": "Bearer ${GITHUB_TOKEN}" }
    },
    "db": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@bytebase/dbhub", "--dsn", "${DATABASE_URL:-postgres://localhost/dev}"],
      "env": {}
    }
  }
}
```

`${VAR}` / `${VAR:-default}` expand in `command`/`args`/`env`/`url`/`headers`.
Personal servers: `claude mcp add --scope user ...` (lands in `~/.claude.json`,
NOT in the repo). Permission/hook references use `mcp__github__*` names.
Subagent-only server: put the same entry object under the agent's
`mcpServers:` frontmatter instead — keeps its tool descriptions out of the
main context.

## Output style (`.claude/output-styles/<name>.md`)

```markdown
---
name: Diagrams first
description: Lead every explanation with a diagram
keep-coding-instructions: true
---

When explaining code or architecture, start with a Mermaid diagram, then prose.
```

Activate via `/config` → Output style, or `"outputStyle": "Diagrams first"` in
settings. Takes effect after `/clear` or restart.

## Rule form (CLAUDE.md lines, review criteria)

One trigger + verdict, tagged descriptive/aspirational, evidence-anchored:

```markdown
**[descriptive]** **When** generating a DB migration, name columns in
`snake_case`. ← *PR #431, #455 (reviewer flagged camelCase)*
```

If the rule is load-bearing ("never", "always before commit"), don't leave it
here — mirror it as a deny rule or hook. CLAUDE.md is guidance, not enforcement.
