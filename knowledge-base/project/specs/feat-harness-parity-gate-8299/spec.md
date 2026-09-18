---
title: Cross-harness parity census for skill invocation forms
feature: feat-harness-parity-gate-8299
date: 2026-09-18
closes: 8299
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-09-18-cross-harness-parity-gate-brainstorm.md
status: draft
---

# Spec — Cross-harness parity census

## Problem Statement

Soleur ships one component tree to multiple agent harnesses, but nothing requires a
skill edit to consider a harness other than the author's own, and nothing detects a
forgotten one. A Claude-only `/soleur:trigger-cron` invocation form was written into a
plan and its `tasks.md` and passed **every** existing gate — markdown-lint, the
guard-contract lint, the infra lint, a seven-agent review panel, and
`plugin-component-test`'s 2,889 tests. The operator caught it by eye.

Harness-specific prose is invisible to every gate in the repository.

Measured 2026-09-18 against `origin/main`: of 98 skills, **38 contain an invocation
instruction** and only **12** name the Grok form. **Codex is named by zero markers and
zero skills.** The existing partial guard
(`plugins/soleur/test/devin-cloud-mode.test.ts:450`) asserts marker-block
byte-identity over a **hand-listed** `UNION` array — the population shape ADR-193 §5
forbids.

## Goals

- G1 A born-blocking census over the derived population of invocation-bearing skills.
- G2 Every member is QUALIFIED or EXEMPT; UNCLASSIFIED is RED. Floor = zero unclassified.
- G3 Replace the hand-listed `UNION` array with a content-derived population.
- G4 A coverage floor that REDs when the derived population *shrinks* (extractor blindness).
- G5 An auditable exemption ledger: dated, issue-linked, falsifiable reasons.

## Non-Goals

- NG1 **Mirror completeness** for the hand-ported trees (`.openhands/skills/` at 63/68
  agents, `.gemini/` at 1/68 agents + 3 skills). Deferred — see follow-up issue.
- NG2 **Migrating the ~105 `${CLAUDE_PLUGIN_ROOT:-…}` sites.** Owned by ADR-179 and
  open **#7453**. This work must not bless a `:-` form nor add `${GROK_PLUGIN_ROOT:-…}`
  as a second vector.
- NG3 **A new `AGENTS.rules.md` rule.** `cq-agents-md-tier-gate` classifies this as
  domain-scoped (single-file trigger: a SKILL.md edit) → the obligation belongs in the
  owning skills.
- NG4 **A single convergent rule bullet** across the skill-authoring skills. ADR-224 §1
  forbids an unqualified cross-harness rule; any bullet must be harness-qualified per skill.
- NG5 A runtime abstraction layer. `plugins/soleur/lib/harness.ts` already is the adapter.
- NG6 Rewriting the 34 unmarked skills' logic — only their invocation surface, and only
  where they are in the derived population.

## Functional Requirements

- **FR1** The gate derives its population by content from `plugins/soleur/skills/*/SKILL.md`,
  matching invocation-instruction forms (`Skill tool`, `skill: soleur:`, `/soleur:<name>`,
  `spawn_subagent`, `run_subagent`, `subagent_type`). Measured: 38 members on 2026-09-18.
- **FR2** Each member resolves to exactly one verdict: **QUALIFIED** (carries a harness
  marker block, OR names the required harness set's forms adjacently, OR cites
  `plugins/soleur/lib/harness.ts`), **EXEMPT** (a ledger row), or **UNCLASSIFIED**.
- **FR3** Any UNCLASSIFIED member fails the suite, naming each offending path.
- **FR4** The gate declares its **required harness set** explicitly as a constant. It does
  not infer the set from what the marker blocks happen to name today.
- **FR5** An exemption ledger, TSV, in the `.claude/hooks/devin-dispositions.tsv` shape
  (ADR-223 §5): one row per exemption, a closed disposition enum, and a **mandatory**
  reason plus evidence column. A row without a date, an issue link and a falsifiable
  reason is itself RED.
- **FR6** A coverage floor pins the derived population size in an inverted `.highwater`
  (the `scripts/lint-supabase-deprecated-endpoints.highwater` shape), with a header
  stating the direction is inverted. A **drop** fails.
- **FR7** The `UNION` array in `plugins/soleur/test/devin-cloud-mode.test.ts` is deleted
  and its coverage subsumed. Its `expect(marked.length).toBe(67)` pin is updated in the
  same change as the backfill.
- **FR8** Backfill the 26 unqualified members of the derived population.

## Technical Requirements

- **TR1** Host: `plugins/soleur/test/harness-parity.test.ts`. It auto-runs under
  `run_suite "plugins/soleur" bun test plugins/soleur/` (`scripts/test-all.sh:2634`) —
  **no `ci.yml` or `lefthook.yml` registration required**. Verify this rather than assume it.
- **TR2** Whole-tree census. Diff-scoping is forbidden: shallow `actions/checkout` breaks
  `git merge-base HEAD origin/main` (exit 128), yielding an empty changed set and a
  vacuous exit 0.
- **TR3** Born blocking. No advisory phase — advisory→blocking promotion has never once
  occurred in this repo. The ledger is the recorded escape hatch.
- **TR4** Floor mechanics per **ADR-193**: report via `printf >&2` + `exit 1` **directly**,
  never through a suite helper; increment the case counter **at the call site**, never
  inside `$( … )`. Fail on `0 checked`.
- **TR5** Anchoring per `cq-assert-anchor-not-bare-token`: anchor on `^\s*` or a call form
  a comment cannot produce. Line-based greps over markdown die on wrap — read the file,
  do not line-grep. Fenced-block instances resolve to ledger rows, not regex carve-outs.
- **TR6** **Mutation test** (TR6 is a gate on the gate): deleting the assertion body must
  turn the suite RED. A guard that passes with itself deleted pins nothing.
- **TR7** A positive control: a planted decoy skill fixture that must be detected, plus a
  corpus-wide zero assertion (the `redact-sentinel.test.sh` pattern).
- **TR8** The gate's own population query must not be duplicated in prose; the regex lives
  in exactly one constant.

## Acceptance Criteria

- [ ] `bun test plugins/soleur/test/harness-parity.test.ts` RED on today's tree (26 unclassified).
- [ ] After backfill + ledger: GREEN, with zero unclassified and every ledger row dated + issue-linked.
- [ ] Mutation test: assertion body deleted → suite RED (TR6).
- [ ] Planted decoy detected; corpus-wide zero holds (TR7).
- [ ] `0 checked` → RED (TR4).
- [ ] Population *shrink* → RED (FR6).
- [ ] `UNION` array gone from `devin-cloud-mode.test.ts`; its count pin updated in the same commit (FR7).
- [ ] No `${CLAUDE_PLUGIN_ROOT:-…}` or `${GROK_PLUGIN_ROOT:-…}` form introduced (NG2).
- [ ] `scripts/test-all.sh` full run green.

## Risks

| Risk | Mitigation |
| --- | --- |
| Requiring Codex REDs all 12 currently-qualified skills | Sequence the canonical marker-block edit *with* the gate; it is one edit propagated across 64 byte-identical copies |
| Trigger regex misses a real invocation shape | TR6 mutation test + TR7 decoy; Open Question 2 |
| `UNION` deletion desyncs `expect(marked.length).toBe(67)` | FR7 — same commit as the backfill |
| Ledger degrades into a rubber stamp | FR5 — mandatory dated, issue-linked, falsifiable reason; no bare "temporary" |
