---
title: "Tasks — SWE-2 Flash on the Devin harness (docs + routing)"
plan: knowledge-base/project/plans/archive/20261105-120831-2026-11-05-feat-swe2-flash-devin-tiering-plan.md
date: 2026-11-05
---

# Tasks

## Phase 1 — Edits

- [x] 1.1 `plugins/soleur/devin/INSTRUCTIONS.md` §Domain agents: rewrite spawn guidance —
      profile rule on tool surface (explore iff no exec/git/`gh`/arbitrary-fetch; else
      general), model semantics (explore→router default; general→parent),
      `agent.subagent_model: "swe-2-flash-medium"` opt-in with all caveats (user-scope,
      new sessions, org-allowlist ignore→team default, no in-session label, promo
      2026-11-30 + re-verify suffix, Free-plan SWE-1.6, local-only), corrected alias
      claim (aliases resolve on model-selection surfaces, not run_subagent args),
      parent-scoped guidance, preserve :241-252 contract + sequential-fallback para.
- [x] 1.2 §Devin-specific considerations :320: extend bullet with model-inheritance
      dimension (keep #8471 carve-out).
- [x] 1.3 §Polling: name `subagent_general` for exit-coded poll loops (state-of-fact
      phrasing, avoid banned phrase class).
- [x] 1.4 `lib/harness.ts`: devin `spawnAgent`/`formatAgentSpawn`/`pollInstructions`
      emit the profile rule; drop unconditional "Inherit the session model"; keep
      registry id out of the `agent`-arg guidance.
- [x] 1.5 ADR-110: addendum `## Addendum — 2026-11-05 (Devin harness / SWE-2 Flash)`
      before `## Alternatives considered`.
- [x] 1.6 `model-launch-review/SKILL.md`: Devin freshness row 7 + collateral (lines
      ~17/18, 26, 53 "2–6"→"2–7", 57, 168); description edit gated on word-budget
      measurement; `README.md` mirror line; `audit-models.sh` header comment.
- [x] 1.7 `plugins/soleur/AGENTS.md`: Devin-mapping note — rule-form (shipped
      amended at review): all five researchers stay `subagent_general` on exec/MCP
      duties; ad-hoc read-only explores may use `subagent_explore` +
      `agent.subagent_model`; `model: haiku` inert on Devin.

## Phase 2 — Pin + verify

- [x] 2.1 New/extended phrase-pin suite: distinctive routing phrases +
      `agent.subagent_model` + negative pin on stale alias sentence + sequential-
      fallback contract pin; re-pin `devin-harness.test.ts`/`harness.test.ts` strings.
- [x] 2.2 Run: devin-harness, devin-cloud-mode, devin-plugin, pr-merge-poll,
      invocation-axis, model-launch-review, harness-model-map, harness, harness-tool-map,
      devin-matcher-parity, c4-count-parity.
- [x] 2.3 Commit + push; PR body: threshold line + decision sentence + lead with
      verified wins (profile routing, false-claim fix), Flash as opt-in.
