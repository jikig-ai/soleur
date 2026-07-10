---
title: A skill's `allowed-tools` is pre-approval, NOT a tool sandbox — never claim by-construction credential isolation from it
date: 2026-07-10
category: security-issues
module: plugins/soleur/skills
issue: 6260
pr: 6259
tags: [claude-code, skills, allowed-tools, credential-isolation, prompt-injection, defense-in-depth, adr-107]
---

# A skill's `allowed-tools` is pre-approval, not a tool sandbox

## Problem

The `/soleur:invoice` skill (#6260) was planned around a **false security premise**: that listing
only the 5 Stripe MCP tools in the SKILL.md `allowed-tools:` frontmatter meant the skill
*"physically cannot read `STRIPE_SECRET_KEY`/`.env`/`lib/stripe.ts`, regardless of any prose
instruction — a grep on a sentence is not the guard; the tool scope is."* The plan, the brainstorm,
AC4, and even the plan-time `architecture-strategist` all treated `allowed-tools` as a mechanical,
by-construction sandbox. ADR-106 (the invoice ADR) shipped that claim as its load-bearing decision.

At `/work` review time, `security-sentinel` (P1, "DO NOT MERGE as claimed") and
`architecture-strategist` (P2) independently flagged it, and `claude-code-guide` confirmed it against
the official docs.

## Root cause

Per the official Claude Code Skills spec (code.claude.com/docs/en/skills.md):

> "The `allowed-tools` field grants permission for the listed tools while the skill is active, so
> Claude can use them without prompting you for approval. **It does not restrict which tools are
> available: every tool remains callable, and your permission settings still govern tools that are
> not listed.**"

So `allowed-tools` is **pre-approval / prompt-suppression**, not a sandbox. `Bash`, `Read`, `Write`
stay callable. A prompt-injection payload in a tool-returned field (a Stripe customer name/memo)
could instruct the agent to `Read('./.env')` or `Bash('cat lib/stripe.ts')`; the only backstop is a
permission prompt — which is bypassed entirely if the operator has a blanket `Bash`/`Read` allow.

Related facts that shaped the fix:
- `disallowed-tools:` DOES remove tools from the pool — but the spec says the restriction **"clears
  when you send your next message,"** so it is per-turn only. Useless as persistent isolation for a
  multi-turn interactive skill, but load-bearing *within* a turn (it covers the poisoned-read →
  same-turn-exfil window).
- A **subagent's** `tools:` field is the only genuine allowlist that removes tools durably. A skill
  reaches it via `context: fork` — but a forked subagent cannot conduct the interactive typed-`yes`
  back-and-forth an approval-gated skill needs.
- The only cross-turn-durable, self-contained enforcement is a `deny` rule in a committed
  `.claude/settings.json` (`permissions.deny`).

## Solution (CTO-ruled, ADR-107)

Replace "by-construction isolation" with an honest **three-layer defense-in-depth** boundary, landing
the durable layers as **committed repo artifacts** (never an operator step — the operator is
non-technical):

1. **Minimal declared scope** — `allowed-tools` = only the intended MCP tools (a convention; widening
   it is a reviewable frontmatter diff).
2. **Per-turn removal** — `disallowed-tools: Bash Read Write Edit` in the SKILL.md frontmatter (covers
   the intra-turn injection window).
3. **Cross-turn deny** — `permissions.deny` in committed `.claude/settings.json` on the secret-file
   `Read` globs (`**/.env`, `**/.env.*`, `**/lib/stripe.ts`).

Plus a `components.test.ts` CI guard asserting layers 2–3 survive future edits. The residual (a
`Bash`-mediated secret read reachable only on operator prompt-approval) is accepted for a test-mode-only,
single-user-incident-threshold v1; the complete boundary (`context: fork`) is deferred.

## Key insight

**Tool-scope frontmatter on a skill is a convenience/pre-approval mechanism, not a security boundary.**
Any plan that claims "the skill can't do X because X isn't in `allowed-tools`" is asserting a guarantee
the platform does not provide. Real per-skill tool restriction requires a subagent boundary
(`context: fork` + `tools:`) or a durable `.claude/settings.json` `deny`. When a security claim rests
on a platform mechanism, **verify the mechanism against the official spec before building the plan on
it** — a plausible-sounding capability model is exactly the kind of premise multi-agent review + a
docs check catches, and that plan-time architecture review echoed rather than challenged.

## Session Errors

1. **Plan's core credential-isolation premise was false** (this learning). Recovery: security-sentinel
   + architecture-strategist + claude-code-guide confirmed; routed the binding fix to the `cto` agent
   (architecture/security-model decision → CTO, not operator); implemented the three-layer model in
   ADR-107 + SKILL.md + settings.json + a CI guard. **Prevention:** treat any plan claim that a
   frontmatter field enforces a security boundary as a precondition to verify against the platform
   spec; capture in skill-creator's reference so the next skill author does not repeat it.
2. **Plan-quoted budget headroom stale** — plan said ~70 free skill-description words; actual was
   2327/2327 (0) after sibling skills landed during the work-start rebase. Recovery: bumped the cap
   +39 per the established precedent. **Prevention:** already covered by "plan-quoted numbers are
   stale preconditions — re-measure at /work start" (existing rule); re-confirmed here.
3. **ADR ordinal collided twice** — plan said ADR-104 (taken by workstream attribution), renumbered to
   106 at the rebase, then #6283 landed ADR-106 (inngest) mid-review, forcing a second renumber to 107.
   Recovery: `git mv` + sweep all 6 citation sites. **Prevention:** already covered by the ship
   ordinal-collision gate + "ADR ordinal is provisional; re-verify against origin/main"; the fast-
   moving-main window extends through review, not just work-start — re-check after any mid-session rebase.
4. **Stale `model.likec4.json`** — the first commit changed `model.c4` but did not regenerate the
   committed compiled artifact (AC8 listed only the syntax/render tests, not the regen step). Recovery:
   `scripts/regenerate-c4-model.sh` + commit; the `c4-model-freshness.test.sh` gate then passed.
   **Prevention:** already-enforced by the freshness test + lefthook `c4-model-regenerate`; note that
   any `model.c4` edit must be paired with a JSON regen, and add the regen to C4-edit acceptance criteria.
5. **Push rejected non-fast-forward** after the work-start rebase. Recovery: `--force-with-lease` (own
   feature branch). One-off; expected after a history-rewriting rebase.
