# Kiro harness pack — mechanics (v2.x lifecycle, with v3 deltas)

> Last verified: 2026-07-14 against kiro-cli **2.12.1**, docs snapshot 2026-07-14
> (local mirror: `harness/kiro/docs/`, refresh with `./pull-docs.sh`). Installed
> version newer? Re-pull + re-verify — /skill-appraise flags this pack stale on drift.

The whole story: cold start → assembled context → your first prompt → the turn cycle →
across turns. Every claim is grounded in `docs/cli/`. v3 changes are called out inline and
summarized at the end.

> One sentence to hold onto: **the default agent assembles a context from steering + skills +
> resources, then each turn runs prompt → hooks → model → tools (gated) → hooks → response →
> autosave.** Everything else is detail on those two ideas.

---

## 0. The cast (what the pieces are)

| Piece | What it is | Lives in |
|---|---|---|
| **Agent** | The profile that decides tools, permissions, and what context loads. There's always one — `kiro_default` unless you swap. | `.kiro/agents/*.json`, `~/.kiro/agents/*.json` |
| **Steering** | Always-on project knowledge (conventions, stack, structure). | `.kiro/steering/*.md`, `~/.kiro/steering/*.md` |
| **Skills** | On-demand procedures, loaded by description match. | `.kiro/skills/<n>/SKILL.md` (+`~`) |
| **Resources** | The agent's `resources` list — files/skills/KBs it pulls into context. | agent config field |
| **Hooks** | Commands fired at lifecycle/tool events. | agent `hooks` field (v2) |
| **MCP** | External tool servers. | `.kiro/settings/mcp.json` or agent `mcpServers` |
| **Knowledge base** | Semantically-indexed content, searched on demand. | configured in `resources` |
| **Session** | The persisted conversation, keyed by directory. | SQLite in `~/.kiro/` |

Two scopes everywhere: **workspace** (`.kiro/…`, shared via repo) and **global** (`~/.kiro/…`,
all projects). On conflict, **workspace wins**; for agents, local-first then global fallback.

---

## 1. Cold start → ready (before you type anything)

You run `kiro-cli` (optionally `--agent X`, else `chat.defaultAgent`, else `kiro_default`).
Kiro then assembles your starting context:

1. **Implicit context** — Kiro auto-includes your **working directory + OS** every session. No config.
2. **Agent selection** — the default agent **auto-loads steering AND skills from both scopes**.
   ⚠️ A **custom agent loads NOTHING by default** — its `resources` must explicitly wire
   `file://.kiro/steering/**/*.md` and `skill://.kiro/skills/**/SKILL.md`. (This is the #1
   cause of "my skills aren't accessed.")
   ⚠️ **Docs now contradict themselves here (2026-07 snapshot):** `steering.md:66` and
   `skills.md:68` still say custom agents load nothing, but `configuration-reference.md`
   ("Disabling default resource inheritance") says custom agents **inherit default
   resources (steering, skills, `AGENTS.md`) by default**, togglable via
   `chat.disableInheritingDefaultResources` (default `false` = inherit; built-in agents
   always inherit). On kiro-cli 2.12.1 the setting key is accepted but unset. Treat as
   **version-dependent**: verify on the installed version with `/context show` inside the
   custom agent before diagnosing wiring — and keep explicit `resources` wiring as the
   portable safe default.
3. **Steering loads fully** — foundational files (`product.md`, `tech.md`, `structure.md`) plus
   any custom steering. `AGENTS.md` is *always* included.
4. **Resources load** — `file://` entries loaded **into context at startup**; `skill://`
   entries load **metadata only** (name + description) at startup; `knowledgeBase` loads
   **nothing** until searched.
5. **Skills register** — Kiro reads every skill's name + description so it knows what *could*
   activate. Bodies stay on disk until needed.
6. **`agentSpawn` hook fires** (if defined) — its STDOUT is added to the agent's context.
7. **Persistence check** — if you've chatted in this directory before, you can
   `--resume` / `--resume-picker`; otherwise a fresh session starts.

**Context budget:** context files are capped at **75% of the model's window**; anything over is
auto-dropped. `file://` resources cost tokens *every request whether referenced or not* — which
is exactly why skills (on-demand) and knowledge bases (search-only) exist.

```
kiro-cli
  │
  ├─ implicit: cwd + OS
  ├─ agent: kiro_default (or --agent)
  │     ├─ default agent → auto-loads steering + skills
  │     └─ custom agent  → loads ONLY what resources[] lists
  ├─ steering .md  → full text in context  (always-on)
  ├─ resources file:// → full text;  skill:// → metadata only;  KB → nothing yet
  ├─ skills → name+description registered
  └─ agentSpawn hook → STDOUT appended
            ▼
      [ READY — prompt shown ]
```

---

## 2. The turn cycle (what happens on each prompt)

```
You submit prompt
  │
  ├─(1) userPromptSubmit hook   → STDOUT added to context   [v2: cannot block]
  │
  ├─(2) Model reads assembled context + prompt, plans tool calls
  │
  ├─(3) For each tool the model wants:
  │        preToolUse hook (matcher) ── exit 2 ⇒ BLOCK, STDERR→model
  │        permission gate: in allowedTools? → run silently
  │                         else            → prompt YOU (y/n)
  │        tool executes
  │        postToolUse hook (matcher)  → e.g. format, lint, audit
  │
  ├─(4) Skill activation: if a request matches a skill's description (or you typed
  │     /skill-name), its FULL body loads on demand now
  │
  ├─(5) Model writes its response
  │
  ├─(6) stop hook fires → may return {"decision":"block","reason":...} to
  │     force the agent to KEEP GOING (feedback loop: "tests not run yet")
  │
  └─(7) Session auto-saved to SQLite (every turn). If the window overflows →
        automatic compaction (summarize old msgs, spawn a new session)
```

Key consequences:
- **Permissions are per-tool-call at runtime.** `allowedTools` = pre-approved (no prompt);
  `toolsSettings.allowedPaths`/`allowedCommands` scope *how* a tool may run. **Defaults:** `read`,
  `grep`, `glob` are trusted in the cwd and `report` is trusted; `shell`, `write`, `aws` ask.
  Approving a shell command at runtime offers trust *tiers* (full `git pull --rebase` → partial
  `git pull *` → base `git *` → entire tool `*`), persisted as regex in the agent's
  `allowedCommands`. Everything else asks.
- **`stop` hooks enable autonomy loops** — a script can inspect the response and bounce the
  agent back ("you haven't run the tests") instead of letting it stop.
- **Skills stay cheap** because only their description sits in context until matched. A bad
  description = never matched = "skill doesn't work." The description *is* the trigger.

---

## 3. Across turns (memory & continuity)

- **Auto-save:** every turn → SQLite (`~/.kiro/`), keyed **per directory**. Session = a UUID.
- **Resume:** `--resume` (latest), `--resume-picker`, `--resume-id <id>`; in-chat `/chat new`,
  `/chat resume`, `/chat save|load <path>`, or `save-via-script`/`load-via-script` (e.g. git notes).
- **Compaction:** `/compact` (manual) or automatic on overflow — summarizes older messages,
  keeps recent ones, and starts a *new* session (the original is still resumable).
- **Three ways to feed context, by lifetime/cost:**
  | Approach | Cost | Persists | Use for |
  |---|---|---|---|
  | Agent `resources` (`file://`) | always-on tokens | across sessions | essential standards/configs |
  | Skills | on demand | across sessions | large guides, specialized procedures |
  | Session context (`/context add`) | always-on, this session | current session only | temp files |
  | Knowledge base | only when searched | across sessions | big codebases/docs |

---

## 4. Where each primitive fits the lifecycle (one-liners)

- **Steering** → loaded at startup, shapes *every* turn. Conventions, stack, structure. Plain `.md`.
- **Skills** → registered at startup (metadata), body loads mid-turn on description match.
- **Resources** → the agent's manifest of what to load (`file://` now, `skill://` metadata, KB lazy).
- **Hooks** → fire at the lifecycle edges (spawn / prompt / pre-tool / post-tool / stop).
- **Custom agent** → the controller: which tools exist, what's pre-approved, what context loads.
- **MCP** → adds external tools the agent can call (gated by the same permission flow).
- **Knowledge base** → escape hatch for content too big for the window; searched, not loaded.

---

## 5. Built-in agents & the tool roster

**Built-in agents** (cannot be edited — `slash-commands.md:180`). Switch via `/agent swap`,
`Shift+Tab` (plan ⇄ execute), or the listed command:

| Agent | Command | What it is |
|---|---|---|
| `kiro_default` | (default) | normal chat/execution agent; auto-loads steering + skills |
| `kiro_planner` | `/plan` | **read-only** planner: structured requirements Q&A → codebase research → task-breakdown plan → on approval, **hands the plan to the execution agent**. Cannot write, run non-read-only shell, or use MCP. |
| `kiro_help` | `/help` | doc-grounded Q&A; can create `.kiro/` files. In the terminal UI `/help` is a searchable command panel and Guide supersedes it. |
| Guide | `/guide` | terminal-UI agent grounded in **indexed docs** via the `introspect` tool (hybrid semantic + BM25), so answers match your *installed version*; can create agents/prompts/steering. |
| Spec (v3) | `/spec` | built-in spec-driven agent (requirements → design → tasks → exec). |

The Plan agent's read-only-then-handoff is the built-in plan/execute split; the v3 Spec agent is its
more structured, file-producing successor. Note Guide's relevance to *us*: it solves the exact
problem this pack does — grounding in indexed docs instead of model memory.

**Built-in tool roster** — the canonical names + aliases that hook `matcher`s and
`toolsSettings`/`allowedTools` keys must reference (`reference/built-in-tools.md`):

| Tool | Aliases | Default permission |
|---|---|---|
| `read` | `fs_read`, `fsRead` | trusted in cwd |
| `glob` | — | trusted in cwd |
| `grep` | — | trusted in cwd |
| `write` | `fs_write`, `fsWrite` | asks |
| `shell` | `execute_bash`, `execute_cmd` | asks |
| `aws` | `use_aws` | asks |
| `web_search`, `web_fetch` | — | asks (trusted/blocked regex configurable) |
| `subagent` | `use_subagent` | default agent only — custom agents must add it |
| `code` | — | trusted in workspace |
| `tool_search` | — | always allowed (read-only) |
| `report` | — | trusted |
| `knowledge`, `thinking`, `todo`, `goal`, `session`, `introspect`, `delegate` | — | internal / experimental |

⚠️ Alias split that bites SMITH output: **hook matchers use the internal names**
(`fs_read`, `fs_write`, `execute_bash`, `use_aws`), while the `tools`/`allowedTools` fields accept
the short names (`read`, `write`, `shell`, `aws`). Emit the right form for the right field.

**Agent-authoring invariants** (from `custom-agents/troubleshooting.md` — the SMITH must enforce):
- A tool in `allowedTools` **must also be in `tools`** — listing it only in `allowedTools` still prompts.
- **MCP access needs all three** (miss one → the agent *silently* has no access): `"includeMcpJson": true`
  (grounded: `mcp.md:95`) **AND** the `@server/tool` name in `tools` **AND** the same name in `allowedTools`
  (grounded: `troubleshooting.md:128`). Tool names must match the `settings/mcp.json` server keys exactly,
  `@`-prefixed.
- **`deniedCommands` (and `allowedCommands`) regex is full-match** — Kiro anchors each pattern with `\A`/`\z`,
  so it matches the *entire* command string, not a substring. A command that takes arguments needs a `.*`
  suffix: `dd if=/dev/zero` is only caught by `"dd if=/dev.*"`, not `"dd if/dev"`; `"git push.*"`, not
  `"git push"`. (grounded: `configuration-reference.md:827` shows the `.*` form; full-anchor behavior
  source-corroborated — rommelporras audit-playbook.)
- Filename (sans `.json`) must equal the agent name; **local `.kiro/agents/` beats global `~/.kiro/agents/`**.
- Validate with `/agent schema` (structure) and `kiro-cli agent validate <path>` before trusting a config.
- An empty or typo'd `tools` array → `/tools` shows nothing → the agent looks capability-less.

## 6. Parallelism, autonomy & context economy

- **Subagents** (`subagent` tool): the main agent spawns up to **4 parallel subagents**, each with
  **isolated context**; they report back via an auto-included **`summary`** tool. Runtime quirks: cwd
  `fs_read` is auto-approved; a **non-interactive** subagent **fails fast** if a tool needs approval
  (add it to `trustedAgents` or trust the tool); each subagent session records its parent ID. The agent
  can wire subagents into a **task-graph DAG** (planned upfront, immutable mid-run) or a **review loop**
  (`target`/`trigger`/`max_iterations` — trigger ≥4 chars, capped at 10, no self/mutual loops) so a
  reviewer bounces work back until it passes. ⚠️ Included in the default agent; **custom orchestrators
  must add `subagent`** to `tools` (or `@builtin`) — same wire-it-in gotcha as skills/steering.
- ⚠️ **Hooks do NOT inherit into subagents.** Each agent (orchestrator and every specialist) defines its
  own `hooks` block; a subagent without one runs *unguarded*. So security hooks (`scan-secrets`,
  `bash-write-protect`, etc.) must be declared explicitly in **every** subagent JSON, not just the
  orchestrator — otherwise a subagent can write secrets or run blocked commands unchecked. This is the
  hook-side twin of the "custom agent loads nothing by default" trap (§1). (docs silent
  on inheritance; source-corroborated — rommelporras audit-playbook: *"hooks do not inherit — each agent
  defines its own hooks block."* Verify against your installed version before relying on it.)
- **`/spawn`**: *user*-driven parallel long-running sessions (vs. subagents, which are *agent*-driven).
- **Native autonomy — `/goal`**: a goal loop where the agent iterates (default 5, `--max N`) and
  **self-verifies before stopping**. The built-in cousin of the `stop`-hook feedback loop (§2).
- **Context economy:** `/compact` (summarize), `/rewind` (non-destructive fork at an earlier turn),
  `/tangent` (isolated side-thread), `/checkpoint` (shadow git repo, per-turn snapshots), and
  `tool_search` (load MCP tools on demand instead of shipping every definition each request).

## 7. Headless / automation (the SMITH's own runtime)

Kiro runs non-interactively — relevant because /skill-temper may *invoke* Kiro to test artifacts:
- `kiro-cli chat --no-interactive "<prompt>"`, authenticated by the **`KIRO_API_KEY`** env var (Pro+).
- No human to approve tools → pre-grant with `--trust-all-tools` or, better, `--trust-tools=read,grep`
  (least privilege).
- **Exit codes:** `0` success · `1` failure · `3` MCP startup failure (with `--require-mcp-startup`).
- Limits: must pass an initial prompt; no mid-session input; slash-command pickers unavailable.
- **`KIRO_HOME`** overrides the `~/.kiro` dir (global agents/skills/steering/sessions); sessions are
  a per-directory SQLite DB.

## 8. How it changes in v3.0

Most of the lifecycle is identical. The deltas, step by step:

**Startup / agents (changed):**
- Agent profiles become **Markdown with YAML frontmatter** (system prompt = body), or equivalent
  JSON. Self-contained & portable.
- `tools` now uses **category tags** (`read`/`write`/`shell`/`web`/`subagent`/`knowledge`/
  `todo_list`/`@mcp`/`@builtin`/`*`) instead of enumerating tools. New tools in a category are
  picked up automatically.
- **Trusted workspaces:** workspace agents load **only if the workspace is trusted**.
- A built-in **Spec agent** runs on the same engine (see below).

**Permissions (new model — replaces `allowedTools`/`toolsSettings`/trust flags):**
- Capability-based rules in `~/.kiro/settings/permissions.yaml` (user) and a **per-user,
  outside-the-repo** workspace file (`~/.kiro/workspace-roots/<hash>/permissions.yaml`) — so a
  cloned repo *cannot* inject trust.
- Rule = `capability` + optional `match`/`exclude` globs + `effect` (deny/ask/allow). Resolution
  is **deny > ask > allow**; unmatched defaults to **ask**. (2026-07 docs: in v3 agent
  profiles the inline permission list now nests under a `rules:` key — `permissions:
  rules: [...]` — older examples showed the list directly under `permissions:`.)
- A hardcoded **Kiro scope** always denies writes to settings/permission files and always asks
  for `.git/**`, `.kiro/agents/**`, `.kiro/hooks/**`.

**Hooks (restructured):**
- Move OUT of agent configs into **standalone `.kiro/hooks/<name>.json`** (versioned schema)
  that apply across all agents.
- New **`action.type: "agent"`** — injects a prompt into context (no subprocess), for lightweight
  guardrails — alongside `"command"`.
- Triggers renamed to PascalCase (`agentSpawn`→`SessionStart`, `stop`→`Stop`, etc.) and **new
  ones added**: `PreTaskExec`/`PostTaskExec` (around spec tasks), `PostFileDelete`, `Manual`.
- `UserPromptSubmit` **can now block** (exit 2). v2 embedded hooks still run; `kiro-cli agent
  migrate` auto-converts.

**Specs (now first-class in CLI):**
- `/spec new|<name>|run` drives a built-in **Spec agent**: Requirements → Design → Tasks →
  Execution, each phase writing `.kiro/specs/<name>/{requirements,design,tasks}.md`.
- Because Spec is a normal agent, your permissions/hooks/MCP apply to it too. `PreTaskExec`/
  `PostTaskExec` hooks fire around each task. Specs are portable across IDE and CLI.

**Smaller:**
- Steering: gains *optional* frontmatter metadata (still plain markdown otherwise).
- Skills: **unchanged.**
- MCP: inline in agent profile + `oauth`/`headers`/`disabledTools`/`autoApprove`.
- Removed: `aws_tool` (→ use MCP), supervised mode (→ permissions.yaml).

**Net effect for the lifecycle diagram:** §1 step 2 (agent format + tags + trust), §2 step 3's
permission gate (now `permissions.yaml`), and the hooks at every edge (now standalone, +2 spec
triggers). The prompt→model→tool→response→autosave spine is unchanged.

---

## Sources READ to write this doc

> Convention for every harness pack: list the exact files read, quote the
> load-bearing claims verbatim with `file:line`, and list what's still unread. If a claim
> here isn't backed by a quote below, treat it as unverified.

All paths are relative to `docs/` (the local CLI clone). Open the file at the cited line to verify.

| File | What it grounded |
|---|---|
| `cli/chat.md` | session start, `/context`, persistence, `/chat new` |
| `cli/chat/context.md` | implicit cwd+OS context, 75% cap, resource URI schemes, compaction |
| `cli/chat/session-management.md` | per-turn autosave, SQLite, per-directory keying, resume |
| `cli/steering.md` | steering load behavior, foundational files, custom-agent non-loading, AGENTS.md |
| `cli/skills.md` | discovery, auto vs slash activation, default vs custom loading, description=trigger |
| `cli/hooks.md` (v2) | events, exit-code blocking, stop block-decision loop |
| `cli/custom-agents.md` | what an agent controls (tools/permissions/context) |
| `cli/custom-agents/configuration-reference.md` | full field list, progressive skill load, read-only default |
| `cli/custom-agents/creating.md` | `/agent create`, file locations, precedence |
| `cli/mcp.md` | MCP config locations and shapes |
| `cli/v3/feature-overview.md` | the v2→v3 feature delta table, tags & capabilities refs |
| `cli/v3/agent-config.md` | v3 Markdown agent profile, tags, inline permissions/MCP |
| `cli/v3/permissions.md` | capability rules, deny>ask>allow, repo-can't-inject-trust |
| `cli/v3/hooks.md` | standalone hooks, agent action type, trigger mapping, migrate cmd |
| `cli/v3/specs.md` | built-in Spec agent, /spec workflow, spec task hooks |
| `cli/reference/built-in-tools.md` | full tool roster, aliases, default trust, subagent wiring |
| `cli/reference/slash-commands.md` | built-in agents, `/goal`, `/spawn`, skill slash commands |
| `cli/reference/cli-commands.md` | CLI flags, `KIRO_HOME`, `agent migrate`, session flags |
| `cli/reference/exit-codes.md` | process + hook exit codes |
| `cli/chat/permissions.md` | v2 runtime trust model + shell trust tiers |
| `cli/headless.md` | non-interactive automation, trust flags, `KIRO_API_KEY` |
| `cli/chat/planning-agent.md` | Plan agent: read-only plan → handoff workflow |
| `cli/chat/help-agent.md` | Help agent (`kiro_help`), legacy vs Guide |
| `cli/chat/guide.md` | Guide agent, `introspect`/indexed-docs grounding |
| `cli/chat/subagents.md` | subagent mechanics, DAG, review loops, `summary` tool |
| `cli/custom-agents/examples.md` | concrete agent configs (output models) |
| `cli/custom-agents/troubleshooting.md` | agent failure modes / authoring invariants |

## Evidence — verbatim quotes (the receipts)

Startup & steering:
- `cli/chat/context.md:38` — "Kiro automatically includes your working directory and operating system as context in every session. You don't need to configure this."
- `cli/steering.md:53` — "These foundation files are included in every interaction by default, forming the baseline of Kiro's project understanding."
- `cli/steering.md:66` — "When using custom agents, steering files are not automatically included. You must explicitly add them to the agent's `resources` configuration to load steering context."
- `cli/steering.md:80` — "AGENTS.md files are in markdown format, similar to Kiro steering files; however, AGENTS.md files are always included."

Skills (load + activation):
- `cli/skills.md:15` — "When you start a chat session, Kiro discovers available skills by reading their names and descriptions."
- `cli/skills.md:64` — "The default agent automatically loads skills from both locations. No configuration required."
- `cli/skills.md:68` — "Custom agents don't load skills by default. You need to explicitly add them to the agent's `resources` field:"
- `cli/skills.md:127` — "The `description` field determines when Kiro activates the skill. Include specific keywords and actions that match how you'd phrase requests."
- `cli/custom-agents/configuration-reference.md:368` — "Skills are progressively loaded — only metadata (name and description) is loaded at startup, with full content loaded on demand when the agent determines it's needed."

Context budget & turn cost:
- `cli/chat/context.md:70` — "Context files are limited to 75% of your model's context window. Files exceeding this limit are automatically dropped."
- `cli/custom-agents/configuration-reference.md:1072` — "By default, the Kiro CLI agent only has access to read-only tools. No write operations are permitted unless you explicitly enable them in `allowedTools` or approve them at runtime."

Hooks (v2):
- `cli/hooks.md:119` — "2: Block tool execution, return STDERR to LLM." (PreToolUse)
- `cli/hooks.md:181` — "When a stop hook returns `decision: \"block\"`, the `reason` is sent as a new user message to the LLM, continuing the conversation."

Persistence:
- `cli/chat/session-management.md:9` — "Kiro CLI automatically saves all chat sessions on every conversation turn. Sessions are stored per-directory in the database..."
- `cli/chat/session-management.md:177` — "Storage: SQLite database in `~/.kiro/`"
- `cli/chat/context.md:141` — "Compaction summarizes older messages while retaining recent ones, freeing up context window space."

Resource inheritance (2026-07 snapshot — the contradiction, quoted):
- `cli/steering.md:66` — "When using custom agents, steering files are not automatically included. You must explicitly add them to the agent's `resources` configuration to load steering context."
- `cli/skills.md:68` — "Custom agents don't load skills by default. You need to explicitly add them to the agent's `resources` field:"
- `cli/custom-agents/configuration-reference.md` (§ Disabling default resource inheritance) — "By default, custom agents inherit default resources (steering files, skills, and `AGENTS.md`) alongside their own configured resources. You can disable this behavior with the `chat.disableInheritingDefaultResources` CLI setting." … "Built-in agents always inherit default resources regardless of this setting."

v3 deltas:
- `cli/v3/feature-overview.md:24` — "| **Skills** | ✅ Available | Unchanged | None |"
- `cli/v3/agent-config.md:11` — "Agent profiles in v3 are self-contained and portable."
- `cli/v3/permissions.md:24` — "Effects resolve by restrictiveness: **deny > ask > allow**. A more permissive rule can never override a more restrictive one, regardless of which scope it comes from."
- `cli/v3/permissions.md:33` — "Workspace permissions are stored **per-user outside the repository** ... A cloned repo cannot inject permission rules. Trust is something you configure on your own machine."
- `cli/v3/permissions.md:80` — "**Always asks:** Writes to `.git/**`, `.kiro/agents/**`, `.kiro/hooks/**`, `.kiroignore`"
- `cli/v3/hooks.md:11` — "Hooks in v3 are standalone files with a versioned schema ... You define them once in `.kiro/hooks/` and they apply across all agents in the workspace."
- `cli/v3/hooks.md:13` — "Existing embedded hooks in agent configs still work during the transition. Run `kiro-cli agent migrate` to auto-convert them to the new format."
- `cli/v3/specs.md:11` — "The Spec agent is a built-in agent that runs alongside your custom agents on the unified engine."

Tools, agents, autonomy & headless:
- `cli/reference/slash-commands.md:180` — "Built-in agents (`kiro_default`, `kiro_help`, `kiro_planner`) cannot be edited"
- `cli/reference/built-in-tools.md:840` — "`read`, `grep`, and `glob` are trusted in the current working directory"
- `cli/reference/built-in-tools.md:841` — "`shell`, `write`, and `aws` prompt for permission by default, but can be configured to allow specific commands/paths/services"
- `cli/reference/built-in-tools.md:747` — "This tool is included in the default agent. For custom agents, you need to explicitly add `subagent` to your `tools` array or include it via the `@builtin` sigil."
- `cli/reference/built-in-tools.md:750` — "Spawn up to 4 subagents simultaneously for parallel task execution"
- `cli/reference/slash-commands.md:909` — "Start a goal-driven iterative loop where the agent works autonomously toward an objective and verifies completion before stopping."
- `cli/headless.md:29` — "Since there's no user to approve tool calls, use `--trust-all-tools` or `--trust-tools` to grant permissions upfront"
- `cli/reference/exit-codes.md:17` — "| 3 | MCP Startup Failure | MCP server failed to start (requires `--require-mcp-startup`) |"
- `cli/reference/cli-commands.md:817` — "`KIRO_HOME` | path | Override the `~/.kiro` directory used for global agents, prompts, skills, steering, settings, and sessions"

Agents & subagents:
- `cli/chat/planning-agent.md:144` — "The Plan agent operates in read-only mode to keep focus on planning."
- `cli/chat/planning-agent.md:140` — "Complete plan is passed to the execution agent"
- `cli/chat/guide.md:42` — "The Guide agent uses the **introspect** tool under the hood."
- `cli/chat/guide.md:48` — "Because answers come from documentation embedded at compile time rather than general model knowledge, they reflect the actual behavior of your installed Kiro CLI version."
- `cli/chat/subagents.md:30` — "If you're building a custom agent that will spawn subagents, include `subagent` in its `tools` array (or add it via the `@builtin` sigil). Without it, the agent can't delegate."
- `cli/chat/subagents.md:38` — "When finished, the subagent calls the built-in `summary` tool and returns its findings to the main agent"
- `cli/chat/subagents.md:52` — "Working directory reads are auto-approved."
- `cli/chat/subagents.md:53` — "Non-interactive subagents can't prompt for approvals. If `is_interactive` is false and a tool requires approval, the subagent fails fast rather than hang."
- `cli/chat/subagents.md:134` — "`max_iterations` must be at least 1 and is capped at 10, regardless of the value requested."
- `cli/custom-agents/troubleshooting.md:126` — "Ensure tools are listed in both tools and allowedTools arrays"

## Potential documents to explore (NOT yet read)

Ranked by relevance to the lifecycle / the SMITH. Each is in the local clone.

**High — ✅ DONE (read & folded into §5–§7):** `cli/reference/built-in-tools.md`,
`cli/reference/slash-commands.md`, `cli/reference/cli-commands.md`, `cli/reference/exit-codes.md`,
`cli/chat/permissions.md`, `cli/headless.md`.

**Medium — ✅ agent set DONE (folded into §5–§6):** `cli/chat/subagents.md`,
`cli/chat/planning-agent.md`, `cli/chat/help-agent.md`, `cli/chat/guide.md`,
`cli/custom-agents/examples.md`, `cli/custom-agents/troubleshooting.md`.

**Still unread:**
- `cli/chat/queue-steering.md` — mid-session steering injection
- `cli/models.md` — valid `model` IDs for agent configs
- `cli/reference/settings.md` — all settings keys (`chat.defaultAgent`, enable flags)

**Experimental (may change fast):**
- `cli/experimental/{delegate,knowledge-management,tangent-mode,thinking,todo-lists,checkpointing}.md`

**Lower / situational:**
- `cli/chat/{guide,effort,goal,responding,rewind,file-references,git-aware-selection,images,settings}.md`
- `cli/{acp,code-intelligence,terminal-ui,autocomplete}.md`
- `cli/mcp/` subpages (examples, security) if/when MCP authoring matters
