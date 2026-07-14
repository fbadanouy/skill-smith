# Codex CLI harness pack — mechanics (lifecycle)

> Last verified: 2026-07-15 against codex-cli **0.144.1**, docs fetched 2026-07-15
> (local mirror: `harness/codex/docs/`, refresh with `./pull-docs.sh`; pulled from `learn.chatgpt.com/docs/*.md` —
> the docs serve **plain-markdown twins** at `<page-url>.md`, so a pull-script is trivial).
> Installed version newer? Re-pull + re-verify.

The whole story: cold start → assembled context → the turn cycle → across turns →
headless. Every claim is grounded in the Evidence section; anything not quoted there is
marked UNVERIFIED.

> One sentence to hold onto: **Codex concatenates an AGENTS.md instruction chain over a
> layered config.toml stack, then each turn runs prompt → hooks → model → tools (gated by
> sandbox + approval policy + rules) → hooks → response → session file.** Everything else
> is detail on those two ideas.

---

## 0. The cast (what the pieces are)

| Piece | What it is | Lives in |
|---|---|---|
| **AGENTS.md** | Always-on instructions, layered global → project → nested dirs. | `~/.codex/AGENTS.md`, `<dir>/AGENTS.md`, `<dir>/AGENTS.override.md` |
| **config.toml** | Model, sandbox, approvals, MCP, features, agents — a 6-level layer stack. | `~/.codex/config.toml`, `<repo>/.codex/config.toml`, `/etc/codex/config.toml` |
| **Profile** | A named config overlay selected with `--profile`. | `~/.codex/<name>.config.toml` |
| **Skill** | On-demand procedure (agentskills.io format), implicit or `$name` invocation. | `.agents/skills/<name>/SKILL.md` (repo), `~/.agents/skills`, `/etc/codex/skills`, bundled |
| **Custom prompt** | **DEPRECATED** slash-command macro (`/prompts:<name>`); use skills. | `~/.codex/prompts/*.md` |
| **Rules** | Starlark `prefix_rule()` execpolicy: allow/prompt/forbid commands outside the sandbox. | `~/.codex/rules/*.rules`, `<repo>/.codex/rules/` |
| **Hooks** | Scripts at lifecycle events (SessionStart…Stop), trust-reviewed by hash. | `~/.codex/hooks.json`, `<repo>/.codex/hooks.json`, inline `[hooks]` |
| **MCP** | External tool servers (stdio or streamable HTTP). | `[mcp_servers.<name>]` in config.toml |
| **Custom agent** | A named subagent role (model, instructions, sandbox override). | `~/.codex/agents/*.toml`, `<repo>/.codex/agents/*.toml` |
| **Session** | Persisted conversation, resumable/forkable. | `~/.codex/sessions/` (`session-*.jsonl`), `history.jsonl` |

Two scopes everywhere: **user** (`~/.codex`, `~/.agents`) and **project** (`<repo>/.codex`,
`<repo>/.agents`). Project layers load **only when the project is trusted**
(`[projects."<path>"] trust_level = "trusted"` in config.toml — observed in the local install).

---

## 1. Cold start → ready

You run `codex` (TUI) or `codex exec` (headless). Codex assembles:

1. **Config layer stack**, highest precedence first: CLI flags/`-c` → project
   `.codex/config.toml` (root→cwd, closest wins; **trusted projects only**) → profile file
   (`--profile name` → `~/.codex/name.config.toml`) → `~/.codex/config.toml` →
   `/etc/codex/config.toml` → built-in defaults.
2. **Instruction chain (AGENTS.md)** — built once per run. Global scope: `~/.codex/`
   `AGENTS.override.md` if present, else `AGENTS.md` (first non-empty only). Project scope:
   walk **project root down to cwd** (root = dir containing `.git` by default,
   `project_root_markers` configurable); per directory pick `AGENTS.override.md`, then
   `AGENTS.md`, then `project_doc_fallback_filenames` — at most one file per directory.
   Concatenated root-down; **files closer to cwd appear later and therefore override**.
   Empty files skipped; loading **stops at `project_doc_max_bytes` (32 KiB default)** —
   over-cap guidance is silently dropped. No cache: chain rebuilt every run.
3. **Skills register (metadata only)** — Codex scans `.agents/skills` in every dir from cwd
   up to repo root, plus `~/.agents/skills`, `/etc/codex/skills`, and system-bundled skills.
   The initial in-context skill list is capped at **2% of the context window (or 8,000
   chars)**; descriptions get shortened first, then skills get dropped with a warning.
   Bodies stay on disk until a skill activates. ⚠️ Local install also has populated
   `~/.codex/skills/` (incl. `.system/` bundled skills: skill-creator, skill-installer,
   openai-docs…) — the docs table doesn't list that path. Treat `~/.codex/skills` as an
   additional scanned location **observed on 0.144.1, not in fetched docs**.
4. **Custom prompts** (deprecated) — top-level `.md` files in `~/.codex/prompts/` become
   `/prompts:<name>` slash commands. Local-only, explicit-invocation-only.
5. **Rules load** — `rules/*.rules` under every active config layer; project rules only if
   trusted. TUI "always allow" decisions are persisted into `~/.codex/rules/default.rules`.
6. **Hooks load** — `hooks.json` and/or inline `[hooks]` next to every active config layer,
   plus plugin-bundled hooks. All matching sources **merge** (higher layers don't replace
   lower ones). ⚠️ Non-managed hooks are **skipped until you review + trust them in
   `/hooks`**; trust is recorded against the hook's hash, so any edit re-quarantines it.
7. **MCP servers start** — `[mcp_servers.*]` (stdio: `command/args/env`; HTTP: `url` +
   bearer/OAuth). `required = true` makes startup fail if the server can't initialize.
8. **Sandbox + approvals arm** — defaults: version-controlled folder → `workspace-write` +
   `on-request` ("Auto"); non-VCS folder → `read-only`. Codex may hold `read-only` until you
   trust the directory. `SessionStart` hook fires (matcher: `startup|resume|clear|compact`);
   its stdout / `additionalContext` is added as developer context.

```
codex
  ├─ config stack: flags > project .codex/ (trusted) > profile > ~/.codex > /etc/codex > defaults
  ├─ AGENTS.md chain: global → repo-root → … → cwd   (32 KiB cap, closest-wins)
  ├─ skills → name+description registered (≤2% ctx list)  bodies on demand
  ├─ rules  → prefix_rule policy compiled
  ├─ hooks  → merged from all layers, trust-gated
  ├─ MCP    → servers launched
  └─ SessionStart hook → stdout appended as developer context
            ▼
      [ READY — prompt shown ]
```

---

## 2. The turn cycle

```
You submit prompt
  ├─(1) UserPromptSubmit hook — stdout → developer context; {"decision":"block"} or
  │     exit 2 + stderr ⇒ prompt blocked
  ├─(2) Model reads instruction chain + prompt, plans tool calls
  ├─(3) For each shell command / apply_patch / MCP call:
  │        sandbox check ── inside boundary? run without asking
  │        rules (execpolicy) ── prefix_rule allow / prompt / forbidden
  │        │                     (most restrictive wins; bash -lc scripts split
  │        │                      per-command when safely parseable)
  │        PreToolUse hook ── deny (reason→model), allow+updatedInput (rewrite), or context
  │        approval gate ── approval_policy untrusted / on-request / never / granular;
  │        │               PermissionRequest hook may allow/deny (any deny wins);
  │        │               approvals_reviewer = user | auto_review (reviewer agent)
  │        tool executes  (inside OS sandbox: Seatbelt / bwrap+seccomp / Windows)
  │        PostToolUse hook ── context, or decision:block ⇒ tool result REPLACED by feedback
  ├─(4) Skill activation: explicit ($name, /skills) or implicit (description match)
  │     ⇒ full SKILL.md loads now
  ├─(5) Model writes response
  ├─(6) Stop hook ── {"decision":"block","reason":…} ⇒ reason becomes a NEW user prompt
  │     (autonomy loop); continue:false wins over continuation
  └─(7) Session persisted (~/.codex/sessions). Overflow ⇒ compaction
        (PreCompact/PostCompact hooks fire, matcher manual|auto; PreCompact
        continue:false cancels compaction)
```

Key consequences:
- **Two independent gates.** The sandbox is the *technical* boundary (filesystem +
  network); the approval policy is the *when-to-ask* policy. `workspace-write` still keeps
  **`.git/`, `.agents/`, `.codex/` read-only inside writable roots** — this is why `git
  commit` can prompt even in "Auto" mode. Escape hatch for specific commands: rules, not a
  broader sandbox.
- **Network is off by default** in `workspace-write`; opt in with
  `[sandbox_workspace_write] network_access = true`, optionally constrained by
  `[features.network_proxy]` domain rules (`deny` beats `allow`; `*.x.com` ≠ apex).
- **Rules ≠ hooks.** Rules are a declarative command-prefix policy engine (`forbidden` >
  `prompt` > `allow`, full compound-command splitting via tree-sitter); hooks are arbitrary
  scripts with JSON I/O. Rules are the cheap, auditable path for command policy.
- **Hook interception is incomplete**: `PreToolUse`/`PostToolUse` cover Bash, `apply_patch`
  (matcher aliases `Edit`/`Write`), and MCP tools — **not** unified_exec-rich shell paths,
  WebSearch, or other native tools. Hooks are guardrails, not an enforcement boundary; the
  sandbox + rules are.
- **Skills stay cheap** via progressive disclosure — but the description *is* the trigger,
  and it may be **shortened** to fit the 2% budget, so front-load trigger words.
- **`allow_implicit_invocation: false`** (in a skill's `agents/openai.yaml`) makes a skill
  explicit-only — the replacement for the deprecated custom-prompt behavior.

---

## 3. Across turns (memory & continuity)

- **Persistence:** sessions live under `~/.codex/` (observed: `sessions/2026/…`,
  `history.jsonl`); the AGENTS.md doc calls them `session-*.jsonl`. Transcript history is
  tunable: `[history] persistence = "none"`, `max_bytes` caps + compacts the file.
- **Resume:** `codex resume` (picker), `--last`, or a session id/name; also
  `codex fork` (branch a previous session), `archive` / `unarchive` / `delete`.
  Headless: `codex exec resume --last "<prompt>"` or `codex exec resume <SESSION_ID>`.
- **Compaction:** manual or automatic (`PreCompact`/`PostCompact` matcher values are
  `manual`/`auto`; `SessionStart` can fire with source `compact`). No docs page found for
  a `/compact` command — UNVERIFIED beyond the hook triggers.
- **Feeding context, by lifetime/cost:** AGENTS.md = every turn, capped at 32 KiB total —
  keep it lean; skills = on demand, right place for anything long; MCP `instructions`
  field = server-wide guidance (first 512 chars should be self-contained); `notify` /
  hooks = side-channel, not context.

---

## 4. Subagents & parallelism

- Built-in agents: **`default`** (general), **`worker`** (implementation), **`explorer`**
  (read-heavy). Enabled by default; triggered by direct request *or* when AGENTS.md/skill
  instructions ask for delegation.
- **Custom agents**: one TOML file per agent in `~/.codex/agents/` (personal) or
  `.codex/agents/` (project). Required: `name`, `description`, `developer_instructions`.
  Optional: `model`, `model_reasoning_effort`, `sandbox_mode`, `mcp_servers`,
  `skills.config`, `nickname_candidates` — **unset fields inherit from the parent
  session**. The `name` field, not the filename, is the identity; a custom agent named
  like a built-in (`explorer`) overrides it.
- Global knobs under `[agents]`: `max_threads` (default **6** concurrent),
  `max_depth` (default **1** — children can't spawn grandchildren), `job_max_runtime_seconds`.
- Subagents **inherit the parent sandbox/permission mode**, unless the custom agent file
  pins its own `sandbox_mode` (e.g. a read-only reviewer).
- Hook coverage: `SubagentStart` (inject context into the subagent, can't block) and
  `SubagentStop` (can bounce the subagent back with `decision:"block"`).
- Batch fan-out: `spawn_agents_on_csv` (experimental) — one worker per CSV row, each must
  call `report_agent_job_result` once; results exported to CSV.

---

## 5. Headless / automation (`codex exec`)

- `codex exec "<prompt>"` — **read-only sandbox by default** (stricter than the TUI's Auto
  preset!). Escalate deliberately: `--sandbox workspace-write` (or `danger-full-access` in
  an externally isolated runner). `--full-auto` is deprecated-with-warning.
- **stdout = final agent message only; progress streams to stderr** — pipe-friendly.
  `--json` switches stdout to a JSONL event stream (`thread.started`, `turn.completed`,
  `item.*`…). `-o/--output-last-message <file>` saves the final message;
  `--output-schema <schema.json>` forces the final response into a JSON Schema.
- stdin: piped stdin + prompt arg = prompt is the instruction, stdin appended as context;
  `codex exec -` = stdin **is** the prompt.
- **Must run inside a git repo** unless `--skip-git-repo-check`. `--ephemeral` skips
  session persistence. `--ignore-user-config` skips `~/.codex/config.toml`;
  `--ignore-rules` skips `.rules` files; `--dangerously-bypass-hook-trust` runs untrusted
  hooks (CI only, after vetting).
- Auth: reuses CLI login; in CI set **`CODEX_API_KEY`** inline per-invocation (exec-only
  variable; never job-level env alongside untrusted code). GitHub Actions: prefer
  `openai/codex-action` (proxy-based key isolation).
- If an MCP server has `required = true` and fails init, `codex exec` errors out instead
  of running degraded.

---

## 6. Config reference traps (the ones that bite)

1. **Profiles are separate files.** Since 0.134, `--profile x` loads
   `~/.codex/x.config.toml` with **top-level keys**; `[profiles.x]` tables in config.toml
   and the `profile = "x"` selector are **no longer read**. Old-style profiles silently do
   nothing.
2. **`-c` values are TOML, not JSON** — `codex -c model='"gpt-5.4"'` (note the inner
   quotes); an unparseable value degrades to a literal string without erroring. Use
   `--strict-config` to catch unknown keys.
3. **Project config can't smuggle sensitive keys.** In `.codex/config.toml`, Codex ignores
   (with a startup warning): `openai_base_url`, `chatgpt_base_url`, `model_provider`,
   `model_providers`, `notify`, `profile`, `profiles`, `otel`, and more. And the whole
   project layer only loads when trusted.
4. **Hooks need trust.** A freshly added or *edited* hook is skipped until re-trusted via
   `/hooks` (hash-pinned). "My hook doesn't fire" usually = untrusted, not misconfigured.
   Also: one layer with both `hooks.json` and inline `[hooks]` → both load + warning.
5. **AGENTS.md silently truncates at 32 KiB** (`project_doc_max_bytes`) — the chain just
   stops adding files. Nested `AGENTS.override.md` completely replaces its sibling
   `AGENTS.md` for that directory.
6. **Skills location split:** docs say repo `.agents/skills` + `~/.agents/skills`; the
   installed 0.144.1 also uses `~/.codex/skills/`. Same-`name` skills are **not merged** —
   both appear in selectors. Disable without deleting via `[[skills.config]] path/enabled`.
7. **`codex exec` defaults to read-only** while interactive `codex` in a trusted repo
   defaults to workspace-write — scripts that "worked in the TUI" stall headless without
   `--sandbox workspace-write`.
8. **`rules` decisions apply to commands *outside the sandbox*** and the most restrictive
   matching rule wins; pattern is an exact argv **prefix** (`gh pr view` doesn't match
   `gh pr --repo x view`). Compound `bash -lc "a && b"` is split per-command only when the
   script is plain words + safe operators; anything fancier is matched as one opaque
   `["bash","-lc",…]` invocation.
9. **CLI vs cloud:** everything above is Codex CLI/IDE (OS sandbox, config.toml). Codex
   cloud runs in OpenAI-managed containers with a two-phase model — networked setup, then
   an offline-by-default agent phase; cloud secrets vanish before the agent phase. Don't
   assume config.toml semantics there.

---

## Sources READ to write this doc

All `learn.chatgpt.com/docs/...` pages were fetched 2026-07-15 as their `.md` twins
(append `.md` to the page URL → `text/markdown`; `developers.openai.com/codex/*` 308-redirects
there). Local snapshot: `harness/codex/docs/`. Repo `docs/` files at
`github.com/openai/codex` are now 3-line stubs pointing at the site.

| Source | What it grounded |
|---|---|
| `docs/agent-configuration/agents-md` | discovery chain, override files, merge order, 32 KiB cap, fallbacks, CODEX_HOME |
| `docs/config-file/config-basic` | layer precedence, trust gating, approval/sandbox keys, web_search, features table |
| `docs/config-file/config-advanced` | profiles (file-based), `-c` TOML parsing, project-config denied keys, providers, notify, history, project_root_markers |
| `docs/build-skills` | skill anatomy, progressive disclosure, 2%/8000-char budget, locations table, `$skill-creator`, `[[skills.config]]`, openai.yaml |
| `docs/custom-prompts` | deprecation, `~/.codex/prompts`, `/prompts:<name>`, placeholders |
| `docs/agent-configuration/rules` | prefix_rule fields, restrictive-wins, bash -lc splitting, `codex execpolicy check`, Starlark |
| `docs/hooks` | all events, matchers, JSON I/O, trust review, block/continue semantics, plugin hooks |
| `docs/sandboxing` | sandbox vs approvals split, modes, approvals_reviewer, bwrap prerequisites |
| `docs/agent-approvals-security` | protected paths, network_access/proxy, defaults per VCS, combination table, cloud two-phase, OS enforcement |
| `docs/non-interactive-mode` | exec defaults, stdout/stderr split, --json, --output-schema, CODEX_API_KEY, exec resume, git check |
| `docs/extend/mcp` | mcp_servers fields (stdio/HTTP), approval modes, required, instructions field |
| `docs/agent-configuration/subagents` | built-in agents, custom agent TOML schema, [agents] knobs, inheritance, CSV fan-out |
| `codex --help`, `codex exec --help`, `codex resume --help` (local 0.144.1) | flags, sandbox values, resume/fork/archive, --ephemeral, --ignore-rules |
| `~/.codex/` (local install, read-only) | config.toml shape (trust_level, mcp_servers tool approval), rules/default.rules, skills dirs incl. `.system`, sessions/history files |

## Evidence — verbatim quotes (the receipts)

AGENTS.md (all from https://learn.chatgpt.com/docs/agent-configuration/agents-md.md; line = local snapshot `docs/codex_agent-configuration_agents-md.md`):
- :7 — "Codex builds an instruction chain when it starts (once per run; in the TUI this usually means once per launched session)."
- :9 — "Codex reads `AGENTS.override.md` if it exists. Otherwise, Codex reads `AGENTS.md`. Codex uses only the first non-empty file at this level."
- :10 — "Starting at the project root (typically the Git root), Codex walks down to your current working directory. … In each directory along the path, it checks for `AGENTS.override.md`, then `AGENTS.md`, then any fallback names in `project_doc_fallback_filenames`. Codex includes at most one file per directory."
- :11 — "Codex concatenates files from the root down, joining them with blank lines. Files closer to your current directory override earlier guidance because they appear later in the combined prompt."
- :13 — "Codex skips empty files and stops adding files once the combined size reaches the limit defined by `project_doc_max_bytes` (32 KiB by default)."

Config layers (https://learn.chatgpt.com/docs/config-file/config-basic.md → `docs/codex_config-file_config-basic.md`):
- :19-26 — "Codex resolves values in this order (highest precedence first): 1. CLI flags and `--config` overrides 2. Project config files: `.codex/config.toml` … (closest wins; trusted projects only) 3. Profile files selected with `--profile profile-name` (`~/.codex/profile-name.config.toml`) 4. User config: `~/.codex/config.toml` 5. System config (if present): `/etc/codex/config.toml` on Unix 6. Built-in defaults"
- :30 — "If you mark a project as untrusted, Codex skips project-scoped `.codex/` layers, including project-local config, hooks, and rules."

Profiles trap (https://learn.chatgpt.com/docs/config-file/config-advanced.md → `docs/codex_config-file_config-advanced.md`):
- :35-37 — "In Codex 0.134.0 and later, `--profile` no longer reads `[profiles.profile-name]` from `config.toml`, and the top-level `profile = \"profile-name\"` selector is no longer supported."
- :65 — "If the value can't be parsed as TOML, Codex treats it as a string."
- :99-102 — "Codex ignores the following keys in project-local `.codex/config.toml` and prints a startup warning when it sees them: `openai_base_url`, `chatgpt_base_url`, `apps_mcp_product_sku`, `model_provider`, `model_providers`, `notify`, `profile`, `profiles`, …"

Skills (https://learn.chatgpt.com/docs/build-skills.md → `docs/codex_build-skills.md`):
- :20 — "Skills use **progressive disclosure** … Codex starts with each skill's name, description, and file path. Codex loads the full `SKILL.md` instructions only when it decides to use a skill."
- :22 — "this list uses at most 2% of the model's context window, or 8,000 characters when the context window is unknown. If many skills are installed, Codex shortens skill descriptions first."
- :71-72 — "**Explicit invocation:** … run `/skills` or type `$` to mention a skill. 2. **Implicit invocation:** Codex can choose a skill when your task matches the skill `description`."
- :105 — "Codex reads skills from repository, user, admin, and system locations. For repositories, Codex scans `.agents/skills` in every directory from your current working directory up to the repository root. If two skills share the same `name`, Codex doesn't merge them"
- :112-113 — "`USER` | `$HOME/.agents/skills` … `ADMIN` | `/etc/codex/skills`"
- :185 — "`allow_implicit_invocation` (default: `true`): When `false`, Codex won't implicitly invoke the skill based on user prompt; explicit `$skill` invocation still works."

Custom prompts deprecated (https://learn.chatgpt.com/docs/custom-prompts.md → `docs/codex_custom-prompts.md`):
- :3 — "Custom prompts are deprecated. Use skills for reusable instructions that Codex can invoke explicitly or implicitly."
- :8 — "Custom prompts require explicit invocation and live in your local Codex home directory (for example, `~/.codex`), so they're not shared through your repository."
- :60 — "Codex scans only the top-level Markdown files in that folder"

Rules (https://learn.chatgpt.com/docs/agent-configuration/rules.md → `docs/codex_agent-configuration_rules.md`):
- :3 — "Use rules to control which commands Codex can run outside the sandbox." / :5 — "Rules are experimental and may change."
- :58 — "Codex applies the most restrictive decision when more than one rule matches (`forbidden` > `prompt` > `allow`)."
- :42 — "When you add a command to the allow list in the TUI, Codex writes to the user layer at `~/.codex/rules/default.rules`"
- :93 — "Even if you allow `pattern=[\"git\", \"add\"]`, Codex won't auto allow `git add . && rm -rf /`, because the `rm -rf /` portion is evaluated separately"

Hooks (https://learn.chatgpt.com/docs/hooks.md → `docs/codex_hooks.md`):
- :18-21 — "`PreToolUse`, `PermissionRequest`, `PostToolUse`, `PreCompact`, `PostCompact`, `UserPromptSubmit`, `SubagentStop`, and `Stop` run at turn scope. `SessionStart` and `SubagentStart` run at thread or subagent-start scope."
- :58-60 — "Before a non-managed command hook can run, Codex requires you to review and trust the exact hook definition. Codex records trust against the hook's current hash, so new or changed hooks are marked for review and skipped until trusted."
- :166-168 — "Only `type: \"command\"` handlers run today. `prompt` and `agent` handlers are parsed but skipped." (and :165 — async "aren't supported yet")
- :447-448 — "This doesn't intercept all shell calls yet, only the simple ones. … Similarly, this doesn't intercept `WebSearch` or other non-shell, non-MCP tool calls."
- :777-779 — "For this event [Stop], `decision: \"block\"` doesn't reject the turn. Instead, it tells Codex to continue and automatically creates a new continuation prompt that acts as a new user prompt, using your `reason` as that prompt text."
- :577-579 — "If multiple matching hooks return decisions, any `deny` wins." (PermissionRequest)
- :629-631 — "For this event [PostToolUse], `decision: \"block\"` doesn't undo the completed Bash command. Instead, Codex records the feedback, replaces the tool result with that feedback, and continues the model from the hook-provided message."

Sandbox & approvals (https://learn.chatgpt.com/docs/agent-approvals-security.md → `docs/codex_agent-approvals-security.md`, and sandboxing.md):
- approvals:9 — "By default, the agent runs with network access turned off."
- approvals:179-183 — "`<writable_root>/.git` is protected as read-only … `<writable_root>/.agents` is protected as read-only when it exists as a directory. `<writable_root>/.codex` is protected as read-only when it exists as a directory."
- approvals:165-167 — "Version-controlled folders: `Auto` (workspace write + on-request approvals) — Non-version-controlled folders: `read-only`"
- approvals:24 — "**Codex cloud**: Runs in isolated OpenAI-managed containers … setup runs before the agent phase and can access the network …, then the agent phase runs offline by default … Secrets configured for cloud environments are available only during setup and are removed before the agent phase starts."
- sandboxing:13-15 — "Sandboxing and approvals are different controls that work together. The sandbox defines technical boundaries. The approval policy decides when the agent must stop and ask before crossing them."
- config-advanced:332-337 — "In workspace-write mode, some environments keep `.git/` and `.codex/` read-only even when the rest of the workspace is writable. This is why commands like `git commit` may still require approval"

Headless (https://learn.chatgpt.com/docs/non-interactive-mode.md → `docs/codex_non-interactive-mode.md`):
- :51 — "By default, `codex exec` runs in a read-only sandbox."
- :25 — "Codex streams progress to `stderr` and prints only the final agent message to `stdout`."
- :72 — "When you enable `--json`, `stdout` becomes a JSON Lines (JSONL) stream"
- :145 — "`CODEX_API_KEY` is only supported in `codex exec`."
- :174-177 — "`codex exec resume --last \"fix the race conditions you found\"` … You can also target a specific session ID with `codex exec resume <SESSION_ID>`."
- :181 — "Codex requires commands to run inside a Git repository to prevent destructive changes. Override this check with `codex exec --skip-git-repo-check`"
- :62 — "If you configure an enabled MCP server with `required = true` and it fails to initialize, `codex exec` exits with an error"

MCP (https://learn.chatgpt.com/docs/extend/mcp.md → `docs/codex_extend_mcp.md`):
- :34 — "Codex stores MCP configuration in `config.toml` … you can also scope MCP servers to a project with `.codex/config.toml` (trusted projects only)."
- :129-132 — "`default_tools_approval_mode` … Supported values are `auto`, `prompt`, `writes`, and `approve`. The `writes` mode prompts for tools that aren't marked read-only."
- :30 — "use `instructions` for cross-tool workflows … Keep the first 512 characters self-contained"

Subagents (https://learn.chatgpt.com/docs/agent-configuration/subagents.md → `docs/codex_agent-configuration_subagents.md`):
- :234-238 — "Codex ships with built-in agents: `default`: general-purpose fallback agent. `worker`: execution-focused agent … `explorer`: read-heavy codebase exploration agent."
- :240-241 — "add standalone TOML files under `~/.codex/agents/` for personal agents or `.codex/agents/` for project-scoped agents."
- :249-257 — "Every standalone custom agent file must define: `name`, `description`, `developer_instructions`. Optional fields such as … `model`, `model_reasoning_effort`, `sandbox_mode`, `mcp_servers`, and `skills.config` inherit from the parent session when you omit them."
- :272-273 — "`agents.max_threads` defaults to `6` … `agents.max_depth` defaults to `1`, which lets the root thread spawn direct children but prevents those children from spawning deeper descendants."
- :211 — "Subagents inherit your current sandbox policy."

CLI help (local, `codex --help` / `codex exec --help`, codex-cli 0.144.1):
- "`-p, --profile <CONFIG_PROFILE_V2>` Layer $CODEX_HOME/<name>.config.toml on top of the base user config"
- "`-s, --sandbox` [possible values: read-only, workspace-write, danger-full-access]"
- "`resume` Resume a previous interactive session (picker by default; use --last …)" / "`fork` Fork a previous interactive session" / "`--ephemeral` Run without persisting session files to disk" / "`--ignore-rules` Do not load user or project execpolicy `.rules` files"

.md doc twins (verified by curl 2026-07-15):
- `https://learn.chatgpt.com/codex/<page>.md` → 308 → `/docs/<page>.md` → `HTTP/2 200`, `content-type: text/markdown; charset=utf-8`. Same for `developers.openai.com/codex/guides/agents-md.md` (308 → learn.chatgpt.com). Pull-script: append `.md`, follow redirects.

## Still unread (ranked)

- `docs/config-file/config-reference` — the full key list (frequently linked; the single most valuable next pull)
- `docs/permissions` — beta named permission profiles (`:read-only`, `[permissions.<name>]`, `default_permissions`)
- `docs/sandboxing/auto-review` — reviewer-agent lifecycle for `approvals_reviewer = "auto_review"`
- `docs/developer-commands?surface=cli` — flag-level reference for every subcommand
- `docs/build-plugins` — plugin packaging (skills + MCP + hooks distribution)
- `docs/enterprise/managed-configuration` — `requirements.toml` admin enforcement
- `docs/customization/memories` (experimental `features.memories`), `docs/extend/record-and-replay`
- Cloud pages (`docs/cloud/*`) — internet access, environments (out of scope for CLI pack)
