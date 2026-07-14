# SKILL-SMITH

![The Skill-Smith at work](skill-smith.gif)

```
═══════════════════════════════════════════════════════════
  THE FORGE
═══════════════════════════════════════════════════════════
  A dark room. Coals breathe orange. An anvil, a ledger,
  seven hammers on the wall. The SMITH does not look up.

  "State your business."

  > _
═══════════════════════════════════════════════════════════
```

A portable pack of [Agent Skills](https://agentskills.io) that makes,
tests, and maintains **other skills**. Works in any harness that speaks
the standard — Kiro CLI, Claude Code, etc.

## COMMANDS

```
  ⚒️  /forge      create a new skill
  🔥  /smelt      extract skills from raw docs / transcripts
  ⚡  /sharpen    fix activation, cut bloat
  🔧  /repair     fix wrong behavior, dead references
  🗡️  /temper     test it: loads, activates, behaves
  ⚖️  /appraise   audit all skills: duplicates, stale, unused
  🛡️  /armory     character sheet: what's equipped

  🧙  /skill-smith   talk to the SMITH — it picks the
                     commands and the order for you
```

## SAMPLE PLAY

```
  > /skill-smith my pr-review skill backfired

  🔧 /repair · trace the fault
  "The blade bit its wielder — a skill did the wrong
   thing, and we find the exact line that told it to."
  ▬▬▬▬▬▬▬▬▬▬▬▬▬▬
  Plan: /repair → /temper. Paste the prompt that
  triggered it and what the agent did.
```

Every reply, same shape: glyph, one line of forge-talk + plain truth,
a bar, then the actual work in plain engineering.

## HOUSE RULES

```
  ✦ no duplicate skills — the one you own gets sharpened
  ✦ nothing ships untested — /forge and /repair end in /temper
  ✦ no anchor, no rule — every claim cites a file, a quote,
    or the failure it came from. no citation → it's a question
  ✦ drafts before disk — the SMITH shows the blade before
    it is forged. nothing is written until you approve
  ✦ the ledger records every change — the forge remembers
  ✦ harness config (steering, CLAUDE.md, hooks) → the SMITH
    fetches the provider's docs and cites them. never guesses.
```

## ENTER THE FORGE

```
  $ ./install.sh          # picks your harness, copies skills/

  or by hand:
  $ cp -R skills/* .kiro/skills/       # Kiro CLI
  $ cp -R skills/* .claude/skills/     # Claude Code

  then summon:
  > /skill-smith
```

```
═══════════════════════════════════════════════════════════
  The SMITH nods once. The coals flare.

  EXITS: [skills/]  [install.sh]  [ledger]
═══════════════════════════════════════════════════════════
```
