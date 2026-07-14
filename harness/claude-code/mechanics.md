# Claude Code harness pack — mechanics (v2.1.x lifecycle)

> Last verified: 2026-07-15 against claude-code **2.1.209** (local install), docs fetched
> 2026-07-15 from `https://code.claude.com/docs/en/` (local mirror: `harness/claude-code/docs/`, refresh with `./pull-docs.sh` — every docs
> page serves a **plain-markdown twin** at `<url>.md`, `content-type: text/markdown`, so a
> pull-script is one `curl` per page). Installed version newer? Re-pull + re-verify.

The whole story: cold start → assembled context → the turn cycle → across turns → headless.
Every claim is grounded in the mirrored docs; citations are `page.md:line` (snapshot) — the
live page is the same URL minus `.md` line numbers.

> One sentence to hold onto: **Claude Code loads the CLAUDE.md chain + skill *descriptions*
> at startup, then each turn runs prompt → hooks → model → tools (hook-gated, then
> permission-gated) → hooks → response; skills' full bodies load only when invoked.**
> Everything else is detail on those two ideas.

---

## 0. The cast (what the pieces are)

| Piece | What it is | Lives in |
|---|---|---|
| **CLAUDE.md** | Always-on instructions, loaded every session. | `./CLAUDE.md` or `./.claude/CLAUDE.md`, `~/.claude/CLAUDE.md`, managed policy path, `CLAUDE.local.md` |
| **Rules** | Topic-split CLAUDE.md; optional `paths:` frontmatter scopes them to file globs. | `.claude/rules/*.md`, `~/.claude/rules/` |
| **Auto memory** | Notes Claude writes itself; `MEMORY.md` index loaded each session. | `~/.claude/projects/<project>/memory/` |
| **Skills** | On-demand procedures, doubling as slash commands (`/name`). Custom commands merged into skills. | `.claude/skills/<name>/SKILL.md`, `~/.claude/skills/`, legacy `.claude/commands/*.md` |
| **Settings** | Permissions, hooks, env, model, plugins. JSON, hierarchical. | `~/.claude/settings.json`, `.claude/settings.json`, `.claude/settings.local.json`, managed |
| **Hooks** | Shell commands / HTTP / MCP tools / prompts fired at lifecycle events. | `hooks` key in any settings file; skill/agent frontmatter; plugin `hooks/hooks.json` |
| **Subagents** | Markdown+frontmatter specialists with own context, tools, model. | `.claude/agents/*.md`, `~/.claude/agents/`, `--agents` JSON, plugins |
| **MCP** | External tool servers (stdio/http/sse/ws). | `.mcp.json` (project), `~/.claude.json` (local & user scope) |
| **Output styles** | System-prompt replacement/addition (role, tone, format). Still current. | `~/.claude/output-styles/`, `.claude/output-styles/`, `outputStyle` setting |
| **Plugins** | Distribution wrapper bundling skills + agents + hooks + MCP, namespaced `plugin:name`. | marketplaces, `--plugin-dir` |

Everything here is the **Claude Code CLI** (also VS Code/JetBrains extensions — same settings
precedence, `settings.md:670`). claude.ai web chat has its own skills/connectors surface and
does not read your `.claude/` tree; web *sessions* of Claude Code are gated by org admin
settings (`permissions.md:445`).

---

## 1. Cold start → ready (before you type anything)

You run `claude`. Claude Code assembles the starting context:

1. **Settings resolve** — managed > CLI args > `.claude/settings.local.json` >
   `.claude/settings.json` > `~/.claude/settings.json`. Scalars override; **arrays
   (e.g. `permissions.allow`) concatenate and dedupe across scopes** (`settings.md:686`).
2. **Workspace trust gate** — a project's `permissions.allow` rules, `additionalDirectories`,
   and project-skill `allowed-tools` apply **only after you accept the trust dialog**
   (`permissions.md:466`, `skills.md:375`). `deny`/`ask` rules always apply.
3. **CLAUDE.md chain loads in full** — Claude Code walks **up** the directory tree from cwd,
   loading every `CLAUDE.md`/`CLAUDE.local.md` on the way, plus `~/.claude/CLAUDE.md` and the
   managed-policy file. All files are **concatenated** (root-most first, cwd-most last;
   `CLAUDE.local.md` after `CLAUDE.md` at each level) (`memory.md:149-151`). `@path` imports
   expand at launch, max 4 hops (`memory.md:97`). HTML comments are stripped (`memory.md:157`).
   Subdirectory CLAUDE.md files load **lazily** when Claude reads files there (`memory.md:153`).
   ⚠️ Claude Code reads `CLAUDE.md`, **not** `AGENTS.md` — import or symlink it (`memory.md:127`).
4. **Rules load** — `.claude/rules/*.md` without `paths:` load at launch; with `paths:` they
   load when Claude works with matching files (`memory.md:193,197`). User rules load before
   project rules (`memory.md:257`).
5. **Auto memory loads** — first 200 lines / 25KB of `MEMORY.md` (`memory.md:374`); topic
   files stay on disk. CLAUDE.md, by contrast, loads in full regardless of length (`memory.md:376`).
6. **Skills register as metadata** — a listing of every skill **name + description** enters
   context; full bodies stay on disk. The listing budget is **1% of the context window**;
   overflow drops descriptions of least-used skills first (`skills.md:853`). Each entry's
   description+`when_to_use` is capped at 1,536 chars (`skills.md:234`).
7. **Subagents & MCP register** — agents from `.claude/agents/` (+ user/plugin/managed);
   MCP servers from `.mcp.json` + `~/.claude.json` connect (project-scoped `.mcp.json`
   servers require a one-time approval — `mcp.md:375`).
8. **`SessionStart` hooks fire** (matcher: `startup`/`resume`/`clear`/`compact`) — stdout /
   `additionalContext` is added to Claude's context; can persist env vars via
   `CLAUDE_ENV_FILE`, set the session title, or `reloadSkills` after installing skills
   (`hooks.md:909-1006`).

**Key placement fact:** CLAUDE.md content is **"delivered as a user message after the system
prompt, not as part of the system prompt itself"** — guidance, not enforcement
(`memory.md:398`). Output styles are the thing that edits the system prompt (`output-styles.md:98`),
and they're read once at session start (change → `/clear` or restart, `settings.md:165`).

```
claude
  ├─ settings: managed > CLI > local > project > user  (arrays merge)
  ├─ trust gate: project allow-rules held until dialog accepted
  ├─ CLAUDE.md chain → FULL text in context (ancestors + user + managed + local)
  ├─ rules: unscoped → now;  paths:-scoped → lazy on file match
  ├─ auto memory: MEMORY.md (first 200 lines / 25KB)
  ├─ skills → name+description listing only (1% budget)
  ├─ agents + MCP register;  .mcp.json needs one-time approval
  └─ SessionStart hooks → stdout/additionalContext appended
            ▼
      [ READY — prompt shown ]
```

---

## 2. The turn cycle (what happens on each prompt)

```
You submit prompt (or /skill-name → skill body expands into the prompt)
  │
  ├─(1) UserPromptSubmit hook  → exit 2 or {"decision":"block"} REJECTS the prompt;
  │      stdout / additionalContext is added as context   (30s default timeout)
  │
  ├─(2) Model reads context + prompt, plans tool calls
  │
  ├─(3) For each tool call:
  │        PreToolUse hooks (matcher = tool name; optional `if` = permission-rule syntax)
  │           exit 2 or permissionDecision:"deny" ⇒ BLOCK, stderr/reason → model
  │           (a blocking hook wins even over an allow rule — permissions.md:359)
  │        permission gate: deny → ask → allow, first match wins; unmatched → prompt you
  │           (per the active permission mode: default/acceptEdits/plan/auto/dontAsk/bypass)
  │        tool executes
  │        PostToolUse / PostToolUseFailure hooks (tool already ran; exit 2 just
  │           shows stderr to Claude)
  │
  ├─(4) Skill invocation (by you via /name, or by Claude via the Skill tool when the
  │      description matches): FULL rendered SKILL.md enters the conversation now,
  │      !`cmd` dynamic-context lines already executed and inlined
  │
  ├─(5) Model writes response
  │
  ├─(6) Stop hook fires → {"decision":"block","reason":...} forces Claude to KEEP GOING
  │      (autonomy loop; capped at 8 consecutive blocks — hooks.md:2142)
  │
  └─(7) Transcript auto-persists (~/.claude/projects/<project>/<session>.jsonl);
        on overflow → auto-compaction
```

Key consequences:
- **Permissions are enforced by the client, not the model** (`permissions.md:40`). Rule =
  `Tool` or `Tool(specifier)`. Resolution: **"deny, then ask, then allow. The first match in
  that order determines the outcome, and rule specificity doesn't change the order"**
  (`permissions.md:33`) — so a broad deny can't carry narrow allow exceptions. Denies from
  *any* scope beat allows from any other (`permissions.md:460`).
- **A bare-name deny removes the tool from Claude's context entirely**; a scoped deny
  (`Bash(rm *)`) leaves the tool visible and blocks matching calls (`permissions.md:37`).
- **Bash rules are shell-operator-aware**: compound commands split on `&&`,`||`,`;`,`|`,`|&`,
  `&`, newlines and each subcommand must match independently (`permissions.md:173`). Wrappers
  `timeout`/`time`/`nice`/`nohup`/`stdbuf`/bare-`xargs` are stripped before matching; env
  runners (`npx`, `docker exec`, `devbox run`) are NOT (`permissions.md:180-184`).
- **Skills stay cheap** because only the description sits in context until invoked. Malformed
  frontmatter YAML → body loads with empty metadata, `/name` still works but Claude has no
  description to auto-match against (`skills.md:842`). Skill dirs are live-watched; edits
  apply mid-session (`skills.md:134`).
- **A skill's `allowed-tools` pre-approves, it does not restrict** — every tool stays
  callable; `disallowed-tools` is the restricting field and clears on your next message
  (`skills.md:373,388`).
- **Once loaded, a skill body stays in context for the rest of the session** and is not
  re-read on later turns (`skills.md:363`) — write standing instructions, not one-shot steps.
- **`Stop` hooks enable autonomy loops** — check `stop_hook_active` to avoid infinite loops;
  Claude Code force-ends after 8 consecutive blocks (`hooks.md:2142`). `/goal` is the built-in
  shortcut for this pattern (`hooks.md:2136`).

---

## 3. Across turns (memory & continuity)

- **Resume:** `claude --continue` (latest in this directory), `claude --resume [id]`,
  in-session `/resume`. Session lookup is scoped to the project directory and its worktrees
  (`headless.md:263`).
- **Compaction:** `/compact` or automatic on overflow. What survives: **project-root CLAUDE.md
  is re-read from disk and re-injected; nested CLAUDE.md files are not** (they reload on next
  file access) (`memory.md:427`). Invoked skills are re-attached — most recent invocation of
  each, first 5,000 tokens, shared 25,000-token budget, most-recent-first, older skills can be
  dropped entirely (`skills.md:367`). Conversation-only instructions are what dies — promote
  them to CLAUDE.md.
- **Auto memory** accumulates across sessions per git repo (worktrees share it); plain
  markdown, audit with `/memory` (`memory.md:346,370`).
- **Settings hot-reload:** edits to `permissions`, `hooks`, etc. apply to the running session;
  `model` and `outputStyle` need restart/`/clear` (`settings.md:161-166`). The `ConfigChange`
  hook fires on each change and can even block it (`hooks.md:689`).
- **Four ways to feed context, by lifetime/cost:**

  | Approach | Cost | Loads | Use for |
  |---|---|---|---|
  | CLAUDE.md / unscoped rules | every session, every turn | at launch, in full | conventions, build commands, "always X" facts |
  | `paths:`-scoped rules | only near matching files | lazy | domain rules (e.g. `src/api/**`) |
  | Skills | description always; body on invoke | on demand | procedures, checklists, bundled scripts |
  | Subagent | zero in main context | isolated window | high-volume exploration, tool-scoped roles |

---

## 4. Where each primitive fits the lifecycle (one-liners)

- **CLAUDE.md / rules** → loaded at startup (or lazily by path), shape every turn. Guidance only.
- **Skills** → metadata at startup, body mid-turn on invocation; also the `/command` surface.
- **Hooks** → fire at the edges (SessionStart / UserPromptSubmit / PreToolUse / PostToolUse /
  Stop / SubagentStart/Stop / PreCompact / SessionEnd + ~20 more, `hooks.md:33-64`). Enforcement.
- **Permissions** → gate every tool call at runtime; deny > ask > allow.
- **Subagents** → spawned mid-turn (Agent tool, `@agent-name`, or auto by description);
  isolated context; only the summary returns.
- **MCP** → external tools registered at startup, gated by the same permission flow
  (`mcp__server__tool` names).
- **Output styles** → applied to the system prompt at session start.
- **Plugins** → distribution: everything above, namespaced, installed from marketplaces.

---

## 5. Subagents (the parallelism & isolation layer)

- **Built-ins:** `Explore` (read-only search), `Plan` (plan-mode research), `general-purpose`
  (all tools). **Explore and Plan skip your CLAUDE.md and git status**; every other built-in
  and custom subagent loads the full memory hierarchy (`sub-agents.md:33,837`). If a rule must
  reach Explore, restate it in the delegation prompt (`sub-agents.md:844`).
- **Definition:** markdown + YAML frontmatter; only `name` and `description` required
  (`sub-agents.md:269`). Fields: `tools` (allowlist), `disallowedTools`, `model`
  (`sonnet|opus|haiku|fable|<full-id>|inherit`), `permissionMode`, `skills` (preloaded —
  **full content injected at startup**, `sub-agents.md:280`), `hooks`, `memory`
  (`user|project|local` persistent dir), `maxTurns`, `background`, `isolation: worktree`,
  `mcpServers` (inline servers stay out of the main conversation's context, `sub-agents.md:420`).
- **Identity is the `name` field, not the filename** (`sub-agents.md:273`); precedence
  managed > `--agents` flag > project > user > plugin (`sub-agents.md:161-166`).
- **Frontmatter `Stop` hooks convert to `SubagentStop`** at runtime (`sub-agents.md:621`).
  Parent-side, hook into `SubagentStart`/`SubagentStop` with the agent type as matcher.
- **The subagent's body replaces the Claude Code system prompt** when run with
  `claude --agent <name>` (`sub-agents.md:701`); as a subagent it gets its prompt + env
  details, not the full CC system prompt (`sub-agents.md:259`).
- Subagents run **in the background by default** (v2.1.198+); permission prompts surface in
  the main session (`sub-agents.md:736`). Nested spawning to depth 5; resume via `SendMessage`.
- Restrict with permission rules: `Agent` (deny all), `Agent(Explore)` (deny one)
  (`sub-agents.md:562-568`).

## 6. MCP (external tools)

Three scopes (`mcp.md:311-315`): **local** (default; `~/.claude.json` under the project's
path, private), **project** (`.mcp.json` at repo root, committed; needs one-time approval,
`mcp.md:375`), **user** (`~/.claude.json`, all projects). Duplicate names: local > project >
user; **the whole winning entry is used, fields are not merged** (`mcp.md:388`).
`.mcp.json` supports `${VAR}` / `${VAR:-default}` expansion in `command`/`args`/`env`/`url`/
`headers` (`mcp.md:400-411`). Add via `claude mcp add [--transport http|sse|stdio] [--scope ...]`;
stdio form needs `--` before the server command. Tool names surface as `mcp__<server>__<tool>`
for permissions and hook matchers alike.

## 7. Headless mode (`claude -p`) — the automation runtime

- `claude -p "<prompt>"` (alias `--print`) runs non-interactively; all CLI options work
  (`headless.md:11-23`). Piped stdin capped at 10MB (`headless.md:84`).
- **No human to approve tools** → pre-grant with `--allowedTools "Bash(git diff *),Read"`
  (permission-rule syntax, `headless.md:225`) or a `--permission-mode` (`dontAsk` for
  locked-down CI, `acceptEdits` for write-throughs, `headless.md:210`). Trust dialogs never
  appear in `-p`; un-trusted project allow rules stay ignored (`permissions.md:486`).
- **`--bare`** skips auto-discovery of hooks, skills, plugins, MCP, auto memory, and CLAUDE.md —
  "the recommended mode for scripted and SDK calls, and will become the default for `-p`"
  (`headless.md:35,58`). Feed context back explicitly: `--settings`, `--mcp-config`,
  `--agents`, `--append-system-prompt`.
- **Output:** `--output-format text|json|stream-json`; `json` includes `session_id`,
  `total_cost_usd`; `--json-schema` for structured output in `structured_output`
  (`headless.md:104-116`).
- **Continuity:** `--continue`, or capture `session_id` from JSON and `--resume "$id"` —
  same directory required (`headless.md:256-263`).
- `/skill-name` works inside the `-p` prompt string; terminal-only builtins (`/login`) don't
  (`headless.md:228`).

---

## 8. Config traps (the ones that bite)

1. **Exit code 1 does not block.** "Claude Code treats exit code 1 as a non-blocking error and
   proceeds with the action... If your hook is meant to enforce a policy, use `exit 2`"
   (`hooks.md:671`). And JSON output is only parsed on exit 0 — exit 2 ignores stdout JSON
   (`hooks.md:649-651`). Pick one signaling style per hook.
2. **Hook matchers are unanchored regexes once any special char appears.** `Edit.*` matches
   `NotebookEdit` too; anchor `^Edit$` for whole-string (`hooks.md:195-197`). Bare `mcp__memory`
   is exact-match chars only → compared as literal string → **matches no tool**; you need
   `mcp__memory__.*` (`hooks.md:265`). Hyphenated exact-match (`code-reviewer`) needs v2.1.195+.
3. **Matchers on matcher-less events are silently ignored** (`UserPromptSubmit`, `Stop`, ... —
   `hooks.md:251`), and a handler with `if:` set **never runs** on non-tool events (`hooks.md:325`).
   The `if` filter is best-effort and fails open on unparseable Bash — enforce with
   permissions, not `if` (`hooks.md:342`).
4. **Permission-rule path anchors:** `/path` is relative to the **settings source**, not the
   filesystem root — `Read(/secrets/**)` in user settings blocks `~/.claude/secrets/**`. Use
   `//` for absolute, `~/` for home (`permissions.md:258,270`).
5. **The space in `Bash(ls *)` matters:** it enforces a word boundary (`ls -la` yes, `lsof`
   no); `Bash(ls*)` matches both (`permissions.md:130`). Argument-constraining patterns like
   `Bash(curl http://github.com/ *)` are fragile — use WebFetch domain rules or a PreToolUse
   hook instead (`permissions.md:199-211`).
6. **deny > ask > allow with no specificity override** (`permissions.md:33-35`): you cannot
   punch an allow-hole through a broad deny. Invert: allow broad + PreToolUse hook to block
   specifics (`permissions.md:359`).
7. **Project allow rules are inert until workspace trust is accepted** (`permissions.md:466`);
   in `-p` mode they stay inert (`permissions.md:486`). Symptom: rules "don't work" in CI.
8. **CLAUDE.md is not enforcement.** It's a user message after the system prompt
   (`memory.md:398`). "Always run X" wants a hook; "never touch Y" wants a deny rule.
9. **`--add-dir` grants file access, not config discovery** — skills and agents ARE loaded
   from added dirs, but hooks/settings/CLAUDE.md are not (CLAUDE.md needs
   `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1`); `permissions.additionalDirectories`
   loads none of it (`permissions.md:374-386`).
10. **Skill/agent dirs that didn't exist at session start aren't watched** — creating the
    first `~/.claude/agents/` or a new top-level skills dir needs a restart
    (`skills.md:134`, `sub-agents.md:140,243`).
11. **`disableAllHooks` is all-or-nothing** and can't disable managed hooks from a lower scope
    (`hooks.md:591-593`).
12. **Skill name collisions:** enterprise > personal > project (**personal beats project** —
    inverted vs. what Kiro users expect), and any of them silently replaces a bundled skill of
    the same name (`skills.md:112`).

---

## Sources READ to write this doc

All files mirrored 2026-07-15 into `harness/claude-code/docs/` from `https://code.claude.com/docs/en/<page>.md`.
Open the snapshot at the cited line to verify; the live page is the same URL without `.md`.

| File (page) | What it grounded |
|---|---|
| `overview.md` | product framing (skimmed) |
| `memory.md` | CLAUDE.md hierarchy, imports, rules, auto memory, compaction survival, AGENTS.md |
| `skills.md` | discovery, locations/precedence, frontmatter, invocation control, lifecycle, listing budget, dynamic context |
| `slash-commands.md` | byte-identical to `skills.md` (commands merged into skills) |
| `permissions.md` | rule syntax, deny>ask>allow, modes, path anchors, Bash matching, trust, hook interaction |
| `settings.md` | scopes, file locations, precedence, array merge, hot reload, managed delivery, hook config keys |
| `hooks.md` | all events, matchers, handler types/fields, exit codes, JSON output, SessionStart/UserPromptSubmit/PreToolUse/Stop schemas |
| `hooks-guide.md` | fetched; not separately quoted (tutorial twin of hooks.md) |
| `sub-agents.md` | frontmatter fields, scopes, built-ins, what loads at startup, hooks, resume, forks (read to line 949) |
| `mcp.md` | scopes, `.mcp.json`, precedence, env expansion, `claude mcp add` |
| `output-styles.md` | built-ins, custom style file format, system-prompt mechanics |
| `headless.md` | `-p`, `--bare`, output formats, `--allowedTools`, continue/resume |
| `plugins.md` | plugin vs standalone, manifest, namespacing (skimmed) |
| `cli-reference.md`, `quickstart.md`, `common-workflows.md`, `iam.md` | fetched; skimmed only |

Local sanity check (read-only): `~/.claude/` contains `settings.json` (keys: model,
statusLine, enabledPlugins, extraKnownMarketplaces, effortLevel, theme),
`settings.local.json` (permissions), `skills/`, `projects/`, `plugins/` — matches the
documented layout. Installed CLI: `2.1.209`.

## Evidence — verbatim quotes (the receipts)

Base URL for all: `https://code.claude.com/docs/en/<page>` (append `.md` for the raw twin).

Startup & memory:
- `memory.md:149` — "Claude Code reads CLAUDE.md files by walking up the directory tree from your current working directory, checking each directory along the way for `CLAUDE.md` and `CLAUDE.local.md` files."
- `memory.md:151` — "All discovered files are concatenated into context rather than overriding each other."
- `memory.md:398` — "CLAUDE.md content is delivered as a user message after the system prompt, not as part of the system prompt itself."
- `memory.md:97` — "Imported files can recursively import other files, with a maximum depth of four hops."
- `memory.md:127` — "Claude Code reads `CLAUDE.md`, not `AGENTS.md`."
- `memory.md:81` — "target under 200 lines per CLAUDE.md file. Longer files consume more context and reduce adherence."
- `memory.md:193` — "Rules without [`paths` frontmatter] are loaded at launch with the same priority as `.claude/CLAUDE.md`."
- `memory.md:374` — "The first 200 lines of `MEMORY.md`, or the first 25KB, whichever comes first, are loaded at the start of every conversation."
- `memory.md:427` — "Project-root CLAUDE.md survives compaction: after `/compact`, Claude re-reads it from disk and re-injects it into the session. Nested CLAUDE.md files in subdirectories are not re-injected automatically."

Skills:
- `skills.md:16` — "**Custom commands have been merged into skills.** A file at `.claude/commands/deploy.md` and a skill at `.claude/skills/deploy/SKILL.md` both create `/deploy` and work the same way."
- `skills.md:112` — "When skills share the same name across levels, enterprise overrides personal, and personal overrides project. A skill at any of these levels also overrides a bundled skill with the same name."
- `skills.md:354` (table) — default: "Description always in context, full skill loads when invoked"; `disable-model-invocation: true`: "Description not in context, full skill loads when you invoke".
- `skills.md:363` — "When you or Claude invoke a skill, the rendered `SKILL.md` content enters the conversation as a single message and stays there for the rest of the session. Claude Code does not re-read the skill file on later turns."
- `skills.md:367` — "Claude Code re-attaches the most recent invocation of each skill after the summary, keeping the first 5,000 tokens of each. Re-attached skills share a combined budget of 25,000 tokens."
- `skills.md:373` — "The `allowed-tools` field grants permission for the listed tools while the skill is active... It does not restrict which tools are available."
- `skills.md:375` — "For skills checked into a project's `.claude/skills/` directory, `allowed-tools` takes effect after you accept the workspace trust dialog for that folder."
- `skills.md:853` — "The budget scales at 1% of the model's context window. When the listing overflows, Claude Code drops descriptions starting with the skills you invoke least."
- `skills.md:842` — "If the frontmatter YAML is malformed, Claude Code loads the skill body with empty metadata, so `/skill-name` still works but Claude has no `description` to match against."
- `skills.md:134` — "Claude Code watches skill directories for file changes... Creating a top-level skills directory that did not exist when the session started requires restarting Claude Code."

Permissions:
- `permissions.md:33` — "Rules are evaluated in order: deny, then ask, then allow. The first match in that order determines the outcome, and rule specificity doesn't change the order."
- `permissions.md:37` — "A bare tool name like `Bash` removes the tool from Claude's context entirely, so Claude never sees it."
- `permissions.md:40` — "Permission rules are enforced by Claude Code, not by the model."
- `permissions.md:130` — "The space before `*` matters: `Bash(ls *)` matches `ls -la` but not `lsof`, while `Bash(ls*)` matches both."
- `permissions.md:173` — "a rule like `Bash(safe-cmd *)` won't give it permission to run the command `safe-cmd && other-cmd`... A rule must match each subcommand independently."
- `permissions.md:258` — "The single leading slash anchors at the settings source, not the filesystem root. Use `//Users/alice/file` for absolute paths."
- `permissions.md:359` — "A hook that exits with code 2 stops the tool call before permission rules are evaluated, so the block applies even when an allow rule would otherwise let the call proceed."
- `permissions.md:458` — "If a tool is denied at any level, no other level can allow it."
- `permissions.md:466` — "`permissions.allow` rules and `permissions.additionalDirectories` entries in a project's `.claude/settings.json`... Claude Code applies them only after you accept the workspace trust dialog."
- `permissions.md:486` — "In [non-interactive mode] with `-p`, no dialog appears and the rules stay ignored."

Settings:
- `settings.md:686` — "When the same array-valued setting (such as ... `permissions.allow`) appears in multiple scopes, the arrays are **concatenated and deduplicated**, not replaced."
- `settings.md:121` — "**Other configuration** is stored in `~/.claude.json`. This file contains your OAuth session, MCP server configurations for user and local scopes, per-project state..."
- `settings.md:161` — "Claude Code watches your settings files and reloads them when they change... This includes `permissions`, `hooks`, and credential helpers."
- `settings.md:641-663` (precedence list) — "1. Managed settings ... Cannot be overridden by any other level, including command line arguments. 2. Command line arguments 3. Local project settings 4. Shared project settings 5. User settings"

Hooks:
- `hooks.md:649` — "JSON output is only processed on exit 0. For most events, stdout is written to the debug log but not shown in the transcript. The exceptions are `UserPromptSubmit`, `UserPromptExpansion`, and `SessionStart`, where stdout is added as context."
- `hooks.md:651` — "**Exit 2** means a blocking error. Claude Code ignores stdout and any JSON in it. Instead, stderr text is fed back to Claude as an error message."
- `hooks.md:671` — "Claude Code treats exit code 1 as a non-blocking error and proceeds with the action... If your hook is meant to enforce a policy, use `exit 2`."
- `hooks.md:195` — matcher containing any non-exact-match character is a "JavaScript regular expression, unanchored".
- `hooks.md:265` — "The `.*` is required: a matcher like `mcp__memory` ... is compared as an exact string and matches no tool."
- `hooks.md:251` — "`UserPromptSubmit`, ... `Stop`, ... don't support matchers and always fire on every occurrence. If you add a `matcher` field to these events, it is silently ignored."
- `hooks.md:314` — "All matching hooks run in parallel, and identical handlers are deduplicated automatically."
- `hooks.md:342` — "Because the `if` filter is best-effort, use the permission system rather than a hook to enforce a hard allow or deny."
- `hooks.md:2142` — "Claude Code overrides the hook and ends the turn after 8 consecutive blocks."
- `hooks.md:2208` — Stop decision: "`\"block\"` prevents Claude from stopping. Omit to allow Claude to stop."
- `hooks.md:174-181` (locations table) — hooks live in `~/.claude/settings.json`, `.claude/settings.json`, `.claude/settings.local.json`, managed policy, plugin `hooks/hooks.json`, and skill/agent frontmatter.
- `hooks.md:591` — "set `\"disableAllHooks\": true`... There is no way to disable an individual hook while keeping it in the configuration."

Subagents:
- `sub-agents.md:33` — "Explore and Plan skip your CLAUDE.md files and the parent session's git status... Every other built-in and custom subagent loads both."
- `sub-agents.md:269` — "Only `name` and `description` are required."
- `sub-agents.md:701` — "The subagent's system prompt replaces the default Claude Code system prompt entirely."
- `sub-agents.md:621` — "When the agent is invoked as a subagent, `Stop` hooks in frontmatter are automatically converted to `SubagentStop` events."
- `sub-agents.md:280` (skills field) — "The full skill content is injected, not only the description."

MCP:
- `mcp.md:375` — "Claude Code prompts for approval before using project-scoped servers from `.mcp.json` files."
- `mcp.md:388` — "Claude Code connects to it once, using the definition from the highest-precedence source. The entire server entry from that source is used; fields are not merged across scopes."

Output styles & headless:
- `output-styles.md:9` — "Output styles change how Claude responds, not what Claude knows. They modify the system prompt to set role, tone, and output format." (feature is current; deprecated piece is only the `/output-style` command, `output-styles.md:31`)
- `headless.md:35` — "Add `--bare` to reduce startup time by skipping auto-discovery of hooks, skills, plugins, MCP servers, auto memory, and CLAUDE.md."
- `headless.md:58` — "`--bare` is the recommended mode for scripted and SDK calls, and will become the default for `-p` in a future release."
- `headless.md:225` — "The `--allowedTools` flag uses permission rule syntax."

## Potential documents to explore (NOT yet read)

- `sub-agents.md:950-1154` — tail of the subagents page (agent teams cross-refs)
- `context-window`, `how-claude-code-works` — the official context-assembly visualization (would strengthen §1/§3)
- `permission-modes` — per-mode detail (only the summary table in `permissions.md` was read)
- `sandboxing` — OS-level Bash isolation (complements deny rules)
- `plugins-reference`, `plugin-marketplaces` — full plugin schemas
- `cli-reference` full flag list; `env-vars`; `commands` (built-in command roster)
- `settings.md:198-575` — the full available-settings table (only scopes/precedence/hooks sections read)
- `hooks-guide.md` — worked examples (redundant with `hooks.md` for claims, useful for recipes)
- `agent-sdk/*` — Python/TS SDK surface (out of scope for CLI pack)
- `statusline`, `worktrees`, `agent-teams`, `scheduled-tasks` — adjacent features, unquoted here
