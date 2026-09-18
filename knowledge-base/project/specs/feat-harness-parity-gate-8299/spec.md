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

Measured 2026-09-18 against `origin/main`: of 98 skills, **46 contain an invocation
instruction** and only **12** name the Grok form. **Codex is named by zero markers and
zero skills.** The existing partial guard
(`plugins/soleur/test/devin-cloud-mode.test.ts:450`) asserts marker-block
byte-identity over a **hand-listed** `UNION` array — the population shape ADR-193 §5
forbids.

## Goals

- G1 A born-blocking census over **all 98** tracked skills, population directory-derived.
- G2 Every skill resolves to QUALIFIED / AUTO-EXEMPT / UNCLASSIFIED. UNCLASSIFIED must be 0.
- G3 Replace the hand-listed `UNION` array with a derived population (ADR-193 §5).
- G4 Floors that catch extractor blindness: a qualified-count floor (grows only) and an
  **auto-exempt ceiling** (shrinks only), so a newly added skill is RED-by-default.
- G5 An auditable exemption ledger: dated, issue-linked, falsifiable reasons.

## Non-Goals

- NG1 **Mirror completeness** for the hand-ported trees (`.openhands/skills/` at 63/68
  agents, `.gemini/` at 1/68 agents + 3 skills). Deferred to **#8306**.
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

- **FR1** The gate's **population is every tracked `plugins/soleur/skills/*/SKILL.md`**
  (`git ls-files`-derived; **98** on 2026-09-18). The population involves no regex, so an
  incomplete trigger pattern can never shrink it. A separate **trigger pattern** decides only
  whether a block is *required*: `Skill tool`, `skill: soleur:`, `/soleur:<name>`, `$soleur:`,
  `Task tool`, `Agent tool`, `invokeSkill`, `spawnAgent`, `formatSkillInvocation`,
  `spawn_subagent`, `run_subagent`, `subagent_type`. Measured 2026-09-18: **46** trigger-bearing
  (a narrower 6-alternative pattern found only 38 — the 8-skill gap is why the pattern is
  widened here), **12** qualified, **34** unclassified, **52** auto-exempt. 46 + 52 = 98.
- **FR2** Each skill resolves to exactly one of three verdicts: **QUALIFIED** (carries the
  `harness-invoke` block, instantiated for its own skill name), **AUTO-EXEMPT** (no block AND
  no trigger — derived, needs no ledger row, so the ledger stays load-bearing), or
  **UNCLASSIFIED** (no block BUT has a trigger) → RED unless a ledger row covers it.
- **FR3** Any UNCLASSIFIED member fails the suite, naming each offending path.
- **FR4** The **required harness set** is imported from a new runtime
  `SUPPORTED_HARNESSES` in `plugins/soleur/lib/harness.ts` (today a type-only union at `:22`),
  with `Harness` derived from it. The set is single-sourced, so adding a harness widens the
  requirement and REDs until skills are updated — ADR-193 §5 applied to the harness axis.
  It is NOT inferred from what the blocks happen to name today (no block names Codex).
- **FR5** An exemption ledger, TSV, in the `.claude/hooks/devin-dispositions.tsv` shape
  (ADR-223 §5): one row per exemption, a closed disposition enum, and a **mandatory**
  reason plus evidence column. A row without a date, an issue link and a falsifiable
  reason is itself RED.
- **FR6** Three floors, all in the separate file of TR4b, each with its ratchet direction in a
  header (the `scripts/lint-supabase-deprecated-endpoints.highwater` inverted-header shape):
  (a) `POPULATION` — exact tracked-SKILL.md count; any change fails until deliberately moved;
  (b) `QUALIFIED_FLOOR` — ratchets **up** only;
  (c) `AUTO_EXEMPT_CEILING` — ratchets **down** only, so a newly added skill with no block and
  no trigger raises auto-exempt past the ceiling and lands RED, forcing classification.
  Plus `UNCLASSIFIED == 0` unconditionally, and a **trigger-count floor** pinning the
  measured 46 so a regression in the trigger pattern itself (which would silently move skills
  into auto-exempt) fails rather than passes.
- **FR7** The hand-listed 20-name `UNION` array in
  `plugins/soleur/test/devin-cloud-mode.test.ts:~466` is deleted (it is the ADR-193 §5
  anti-pattern) and its "every union member is marked" assertion re-expressed against a
  derived population. **Measured correction:** its sibling `expect(marked.length).toBe(67)`
  does **not** move — `MARKER_START`/`MARKER_END` are the literal `soleur-cloud-mode` comments,
  so a `grok-harness-invoke` block is invisible to that census (64 skills + 3 devin shims = 67,
  re-derived). An earlier draft of this spec claimed the pin moves; it does not.
- **FR8** Backfill the **34** unclassified skills with the `grok-harness-invoke` block,
  instantiated for each skill's own name, and normalise `one-shot`'s drifted copy
  ("a subset **of these steps**" → "a subset") so the template holds across all 46.
- **FR9** Insertion anchor, measured per skill — **not** uniformly after frontmatter:
  **24 of 34** already carry a `soleur-cloud-mode` block first, so the new block goes strictly
  **after** its `<!-- soleur-cloud-mode:end -->`. Inserting *inside* it would break the
  non-greedy `[\s\S]*?` byte-identity assertion in `devin-cloud-mode.test.ts` for all 24.
  The **10** with no cloud-mode block anchor on frontmatter: `architecture`,
  `brainstorm-techniques`, `feature-tweet`, `frontend-anti-slop`, `harvest-debt`, `help`,
  `linear-fetch`, `resolve-debt`, `skill-creator`, `social-distribute`.
- **FR10** The block's text must not introduce a backticked path beginning `scripts/`,
  `references/` or `assets/`: `components.test.ts:238` asserts
  `body.match(/`(?:references|assets|scripts)\/[^`]+`/g)` is null per-skill. The canonical
  block's existing `plugins/soleur/lib/harness.ts` citation is safe.

## Technical Requirements

- **TR1** Host: `plugins/soleur/test/harness-parity.test.ts`. It auto-runs under
  `run_suite "plugins/soleur" bun test plugins/soleur/` (`scripts/test-all.sh:2634`) —
  **no `ci.yml` or `lefthook.yml` registration required**. Verify this rather than assume it.
- **TR2** Whole-tree census. Diff-scoping is forbidden: shallow `actions/checkout` breaks
  `git merge-base HEAD origin/main` (exit 128), yielding an empty changed set and a
  vacuous exit 0.
- **TR3** Born blocking. No advisory phase — advisory→blocking promotion has never once
  occurred in this repo. The ledger is the recorded escape hatch.
- **TR4** **ADR-193 applies in part only, and the part matters.** Its Decision 5 ("the
  population is DERIVED, never listed") binds and is load-bearing. Its Decision 1 mechanism
  (`printf >&2` + `exit 1` rather than the suite's own `fail`; counter incremented at the call
  site, not inside `$( … )`) does **not** bind: it is written for bash suites, its enforcing
  guard `scripts/guard-vacuity-floor.test.sh` enumerates tracked `*.test.sh`, and a bun test is
  outside that population entirely — there is no "suite's own verdict helper" to bypass when
  `expect()` *is* the reporting mechanism. Because the corpus guard therefore cannot police
  this suite's floor, TR6's mutation test is the substitute and is mandatory, not optional.
  Fail on `0 checked` still binds.
- **TR4b** Floors live in a committed data file **separate from the assertion**, per
  constitution L142 ("a declared number cannot catch its own reduction, so the assertion must
  be external to the declaration"), with an inverted-direction header naming which way each
  ratchets. Recorded caveat: the population denominator is `git ls-files`-derived, not
  credential-scoped, so the silent-narrowing failure L142 guards against is absent here — a
  narrowing is a visible file deletion. The separate file buys a visibly separate diff hunk on
  any weakening, not cryptographic integrity.
- **TR4c** Ledger parsing is strict and fail-closed per constitution L139/L140: a missing,
  unreadable or malformed ledger, or a row with an unrecognised disposition, is RED — never
  silently "zero exemptions" and never a swallowed `2>/dev/null || echo ""` empty set.
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

- [ ] `bun test plugins/soleur/test/harness-parity.test.ts` RED on today's tree (34 unclassified).
- [ ] After backfill + ledger: GREEN, with zero unclassified and every ledger row dated + issue-linked.
- [ ] Mutation test: assertion body deleted → suite RED (TR6).
- [ ] Planted decoy detected; corpus-wide zero holds (TR7).
- [ ] `0 checked` → RED (TR4).
- [ ] Auto-exempt *growth* past ceiling → RED; qualified *drop* below floor → RED; trigger-count
      *drop* → RED (FR6).
- [ ] `SKILL_DESCRIPTION_WORD_BUDGET` (2442, description-words only) unmoved — body lines are
      not measured, verified via `components.test.ts:156-160`.
- [ ] `devin-cloud-mode.test.ts` still green with `marked.length == 67` unchanged (FR7).
- [ ] `UNION` array gone from `devin-cloud-mode.test.ts`, its assertion re-expressed derived (FR7).
- [ ] No `${CLAUDE_PLUGIN_ROOT:-…}` or `${GROK_PLUGIN_ROOT:-…}` form introduced (NG2).
- [ ] `scripts/test-all.sh` full run green.

## Risks

| Risk | Mitigation |
| --- | --- |
| Requiring Codex REDs all 12 currently-qualified skills | Sequence the canonical marker-block edit *with* the gate; it is one edit propagated across 64 byte-identical copies |
| Trigger regex misses a real invocation shape | TR6 mutation test + TR7 decoy; Open Question 2 |
| Block inserted inside the cloud-mode block breaks byte-identity for 24 skills | FR9 — anchor strictly after `soleur-cloud-mode:end` |
| Deriving `Harness` from the new array drops `"unknown"` and breaks `detectHarness` | Keep `\| "unknown"`; the 5-member union stays type-identical for all 3 importers |
| Ledger degrades into a rubber stamp | FR5 — mandatory dated, issue-linked, falsifiable reason; no bare "temporary" |
