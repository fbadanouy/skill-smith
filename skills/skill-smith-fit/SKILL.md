---
name: skill-smith-fit
description: "Forge a harness artifact: steering file, CLAUDE.md/AGENTS.md section, hook, agent config, or MCP wiring. Use when the user wants always-on rules or conventions, event-triggered automation, tool/permission scoping, a custom agent role, or platform config — or when /skill-forge's step zero found the request isn't a skill. Not for on-demand task procedures — that's /skill-forge."
---

# 🪖 /skill-smith-fit · fit the harness

Reply in the Skill-Smith frame: `🪖 /skill-smith-fit · {action}`, one metaphor+truth line, ▬ bar, then plain work.

Blades are portable; armor is measured to the wearer. Every move here is
grounded in the platform's pack — nothing about a harness comes from memory.

## Measure the wearer

Detect the platform (`.kiro/` → Kiro, `.codex/` or `AGENTS.md` → Codex, `.claude/` → Claude Code).
Read `harness/<platform>/mechanics.md` + `primitives.md` (skill-smith repo or beside the skills dir).
No pack → fetch the provider's current docs and cite `file:line` for every claim; offer to note that a pack is missing. Never advise from memory.

## Route the piece (primitives.md decides; first match wins)

- "when EVENT, always run X" → **hook** — "always" is the tell: steering is guidance the model may forget; a hook is a mechanism that can't
- restrict/pre-approve tools, permissions, a bounded role → **agent config**
- external tool/service/API → **MCP wiring**
- always-true convention or knowledge, every turn → **steering / CLAUDE.md / AGENTS.md**
- on-demand task procedure → not armor; send to ⚒️ /skill-forge

## Interview

- The need, concretely — one real example where its absence hurt. None exists → warn, offer nothing or a minimal draft.
- Narrowest scope that works: conditional/glob steering beats always-on; workspace vs global; per-agent vs all-agents. Always-on context costs tokens every turn whether used or not.
- What does failure look like? → becomes the verification criteria.

## Watch it fail bare

Before drafting, exercise the platform once WITHOUT the artifact. It already behaves right → stop; armor over healthy skin is dead weight. The observed failure becomes the artifact's reason — every rule written pairs with why.

## Draft, then get approval

Scaffold from `harness/<platform>/templates.md` when present. Show the full artifact + exact target path BEFORE touching disk. A terse request does not waive this. Facts need anchors (file:line, quote, or the real failure); no anchor → a question for the user, never written text.

## Wire it, prove it

Run the pack's wiring checklist (Kiro: `mechanics.md` §5 invariants — `allowedTools ⊆ tools`, hook matchers use internal tool names, MCP's three keys, resource loading is version-dependent → verify with `/context show`). Then prove the piece with the platform's own inspection: the hook fires once on a real event, the agent lists its tools, the steering shows in context. No inspection run → report it as unverified, never as done.
Record in `ledger.md`: piece, platform, date, reason.

$ARGUMENTS
