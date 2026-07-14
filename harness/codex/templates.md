# Codex CLI harness pack — templates (armor scaffolds)

> Drafted 2026-07-15. Shapes verified against `mechanics.md` (same snapshot,
> codex-cli 0.144.1 + docs fetched 2026-07-15). Skill *content* discipline belongs to
> /skill-forge and the agentskills.io spec; these are the harness-shaped containers.

## AGENTS.md — always-on instructions

Global (`~/.codex/AGENTS.md`) — cross-repo working agreements only:

```markdown
## Working agreements

- Always run `npm test` after modifying JavaScript files.
- Prefer `pnpm` when installing dependencies.
- Ask for confirmation before adding new production dependencies.
```

Repo root (`<repo>/AGENTS.md`) — project norms; inherits the global file:

```markdown
# AGENTS.md

## Repository expectations

- Run `npm run lint` before opening a pull request.
- Document public utilities in `docs/` when you change behavior.

## Delegation

- For codebase exploration, delegate to parallel subagents and return summaries.
```

Subtree override (`services/payments/AGENTS.override.md`) — **replaces** any sibling
`AGENTS.md` for that directory; loads only when cwd is at/below it:

```markdown
## Payments service rules

- Use `make test-payments` instead of `npm test`.
- Never rotate API keys without notifying the security channel.
```

Budget rule: the whole chain (global + every dir file) stops loading at
`project_doc_max_bytes` (32 KiB default). Runbooks and long guides go in skills, not here.

## Skill (`.agents/skills/<name>/SKILL.md`) — on-demand procedure

```
.agents/skills/db-migration/
  SKILL.md          # required: frontmatter + instructions
  scripts/          # optional executable code
  references/       # optional docs loaded on demand
  agents/openai.yaml  # optional: invocation policy, UI metadata, tool deps
```

```markdown
---
name: db-migration
description: Use when creating, reviewing, or rolling back a database migration.
  Covers naming, safety checks, and the rollback procedure. Trigger words:
  migration, schema change, rollback.
---

1. Generate the migration with `scripts/new_migration.sh <name>`.
2. Name columns in snake_case; every migration must have a `down`.
3. Run `make db-test` before proposing the change.
```

Description = trigger, and it may be **shortened** to fit the 2%-of-context skills list —
put the key use case and trigger words in the first sentence.

Explicit-only skill (the replacement for a deprecated custom prompt) —
`agents/openai.yaml`:

```yaml
policy:
  allow_implicit_invocation: false
```

Invoke with `$db-migration` or `/skills`. Repo skills ship via git; personal ones go in
`~/.agents/skills/`; disable one without deleting:

```toml
# config.toml
[[skills.config]]
path = "/path/to/skill/SKILL.md"
enabled = false
```

## Custom prompt (`~/.codex/prompts/<name>.md`) — DEPRECATED, legacy only

```markdown
---
description: Prep a branch, commit, and open a draft PR
argument-hint: [FILES=<paths>] [PR_TITLE="<title>"]
---

Create a branch named `dev/<feature_name>` for this work.
If files are specified, stage them first: $FILES.
Open a draft PR. Use $PR_TITLE when supplied.
```

Invoked as `/prompts:draftpr FILES="src/a.ts" PR_TITLE="…"`. `$1`–`$9`, `$ARGUMENTS`,
`$NAMED` placeholders; `$$` = literal `$`. Top-level files only; local home dir only.
For new work, build a skill instead.

## Profile (`~/.codex/<name>.config.toml`) — sandbox/approval/model preset

Top-level keys, own file, selected with `--profile <name>` (NOT a `[profiles.x]` table —
dead since 0.134):

```toml
# ~/.codex/full_auto.config.toml
approval_policy = "on-request"
sandbox_mode    = "workspace-write"
```

```toml
# ~/.codex/deep-review.config.toml
model = "gpt-5.5"
model_reasoning_effort = "xhigh"
approval_policy = "on-request"
```

```shell
codex --profile full_auto
codex exec --profile deep-review "review this change"
```

Base sandbox/approval keys (user or trusted-project `config.toml`):

```toml
approval_policy = "on-request"     # untrusted | on-request | never | { granular = {...} }
sandbox_mode    = "workspace-write" # read-only | workspace-write | danger-full-access
approvals_reviewer = "user"        # or "auto_review"

[sandbox_workspace_write]
network_access = false             # opt in deliberately
writable_roots = []                # extra writable dirs beyond the workspace
```

## MCP server (`[mcp_servers.<name>]` in config.toml)

stdio:

```toml
[mcp_servers.context7]
command = "npx"
args = ["-y", "@upstash/context7-mcp"]
env_vars = ["LOCAL_TOKEN"]

[mcp_servers.context7.env]
MY_ENV_VAR = "MY_ENV_VALUE"
```

Streamable HTTP + approval scoping:

```toml
[mcp_servers.figma]
url = "https://mcp.figma.com/mcp"
bearer_token_env_var = "FIGMA_OAUTH_TOKEN"

[mcp_servers.chrome_devtools]
url = "http://localhost:3000/mcp"
enabled_tools = ["open", "screenshot"]
default_tools_approval_mode = "prompt"   # auto | prompt | writes | approve
required = false                          # true ⇒ startup fails if server can't init

[mcp_servers.chrome_devtools.tools.open]
approval_mode = "approve"
```

OAuth servers: `codex mcp login <server-name>`.

## Rules (`~/.codex/rules/<name>.rules` or `<repo>/.codex/rules/`)

```python
# Forbid force-pushes outright; allow read-only docker; prompt for gh pr view.
prefix_rule(
    pattern = ["git", "push", "--force"],
    decision = "forbidden",
    justification = "Use --force-with-lease after review.",
)
prefix_rule(pattern = ["docker", ["ps", "images"]], decision = "allow")
prefix_rule(
    pattern = ["gh", "pr", "view"],
    decision = "prompt",
    match = ["gh pr view 7888"],
    not_match = ["gh pr --repo openai/codex view 7888"],  # prefix must be exact
)
```

Test before trusting: `codex execpolicy check --pretty --rules <file> -- <command>`.
Restart Codex after editing. (Experimental surface — re-verify on upgrade.)

## Hooks (`~/.codex/hooks.json` or `<repo>/.codex/hooks.json`)

State trigger and action plainly first:

```
When: the model proposes a Bash command          Do: run the policy script; exit 2 blocks
When: the turn stops                              Do: check tests ran; bounce back if not
```

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "/usr/bin/python3 \"$(git rev-parse --show-toplevel)/.codex/hooks/pre_tool_use_policy.py\"",
            "timeout": 30,
            "statusMessage": "Checking Bash command"
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "/usr/bin/python3 \"$(git rev-parse --show-toplevel)/.codex/hooks/stop_continue.py\""
          }
        ]
      }
    ]
  }
}
```

Handler contract: JSON on stdin; block a PreToolUse call with
`{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"…"}}`
(or exit 2 + stderr); keep the agent going from Stop with
`{"decision":"block","reason":"Run one more pass over the failing tests."}` — the reason
becomes a new user prompt. `Stop`/`SubagentStop` require JSON stdout on exit 0.
Matchers: tool names for `Pre/PostToolUse`/`PermissionRequest` (`Bash`, `apply_patch`
aka `Edit|Write`, `mcp__server__tool`); `startup|resume|clear|compact` for `SessionStart`;
`manual|auto` for `Pre/PostCompact`. Only `type:"command"` runs today.
⚠️ After adding or editing: open `/hooks` and trust the hook, or it silently never fires.
Prefer git-root-resolved absolute paths — Codex may start from a subdirectory.

Inline TOML equivalent (pick ONE representation per layer):

```toml
[[hooks.PreToolUse]]
matcher = "^Bash$"

[[hooks.PreToolUse.hooks]]
type = "command"
command = '/usr/bin/python3 "$(git rev-parse --show-toplevel)/.codex/hooks/pre_tool_use_policy.py"'
timeout = 30
```

## Custom agent (`.codex/agents/<name>.toml`) — start restrictive

```toml
name = "reviewer"
description = "PR reviewer focused on correctness, security, and missing tests."
model = "gpt-5.4"
model_reasoning_effort = "high"
sandbox_mode = "read-only"
developer_instructions = """
Review code like an owner.
Prioritize correctness, security, behavior regressions, and missing test coverage.
Lead with concrete findings; avoid style-only comments unless they hide a real bug.
"""
```

`name`/`description`/`developer_instructions` required; omitted fields (model, sandbox,
MCP, skills) inherit from the parent session. A custom agent may embed its own
`[mcp_servers.*]` tables and `[[skills.config]]` entries. Global caps in project config:

```toml
[agents]
max_threads = 6   # concurrent open agent threads (default 6)
max_depth = 1     # children can't spawn grandchildren (default 1 — keep it)
```

## Headless invocation (CI scaffold)

```bash
# read-only by default; escalate deliberately
codex exec --profile ci --sandbox workspace-write \
  --json -o last-message.txt \
  "run the test suite, fix the smallest thing that makes it pass"

# two-stage pipeline
codex exec "review this branch for race conditions"
codex exec resume --last "fix the race conditions you found"
```

`CODEX_API_KEY=<key>` inline per-invocation only; `--ephemeral` to skip session files;
`--skip-git-repo-check` outside a repo; `--output-schema schema.json` for structured
final output.
