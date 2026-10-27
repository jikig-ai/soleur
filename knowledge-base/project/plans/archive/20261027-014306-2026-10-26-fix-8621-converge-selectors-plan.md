---
title: "fix: converge the two affected-test selectors — fold TEST_GROUP=affected into --affected"
type: fix
date: 2026-10-26
slug: fix-8621-converge-selectors
branch: feat-one-shot-8621-converge-selectors
issue: 8621
closes: 8621
priority: p2-medium
domain: engineering
lane: cross-domain
brand_survival_threshold: none
---

# fix: converge the two affected-test selectors — fold TEST_GROUP=affected into --affected

## Overview

`main` carried two independent affected-suite selectors: `bash scripts/test-all.sh --affected`
(#8322, declared-edge index + always-on ratchet floor + degraded-full ladder) and
`TEST_GROUP=affected bash scripts/test-all.sh` (#8591, chokepoint heuristic — argv-path
containment, content references, test-name stems, grep-based census backstop). #8621 asked for
evidence-driven convergence, with ship's gate semantics (affected+ratchets default, `--full`
lever) load-bearing either way.

The measurement ran FIRST (the issue's own handle): per-diff, `--print-selection --paths=P`
receipts vs the `TEST_GROUP=affected` decline set on the same pathset, over a 19-diff corpus
(16 real `origin/main` squash-merged PRs + 3 synthesized pathsets). Result — recorded in
`knowledge-base/project/specs/feat-one-shot-8621-converge-selectors/measurements.md`: the
heuristic declined **49–355 suites per diff that the declared index selected**, including
always-on ratchets its grep backstop could not classify (132 distinct missed labels), and
300+ on the three runner/index diffs where the declared gate correctly degrades to full.
Misses land — the issue's fold criterion.

**Convergence shipped:** the declared index is the single selector. `TEST_GROUP=affected` is
kept as a parse-time compat alias of `--affected` (the refusal bodies and skill prose
prescribe the spelling); the heuristic machinery (`_suite_affected`, `_aff_stem`,
`_AFFECT_PATTERNS`/`_AFFECT_STEMS`, the chokepoint decline branch, the exempt-labels case,
the TEST_GROUP=affected untracked append) is removed. The alias arms `_AFFECTED` at the
`_aff_group_req` site, is refused under `--affected`/`--full` combinations exactly as the
distinct selector was, then normalises to `all` before any consumer can observe the group
value — an alias run is byte-identical to `--affected` (proven: `--print-selection` output
`cmp`-equal under both spellings).

## Problem Statement / Motivation

Two selectors answering the same question with different verdicts is worse than one:
whichever a prescribed substitute run declines silently shapes the coverage a refused agent
gets. The heuristic was designed as a fail-safe over-selector, but the corpus shows it is
also an UNDER-selector — declining always-on ratchet suites its grep census cannot recognise
(the class the backstop exists to protect) and carrying no runner-changed degradation.

## Proposed Solution

Fold (issue criterion 2):

1. `scripts/test-all.sh`: alias arming at the `_aff_group_req` site (`TEST_GROUP=affected`
   sets `_AFFECTED=1` + `_TG_AFFECTED_ALIAS`), ambiguity refusal narrowed to
   `--affected`/`--full` (tracked by a new `_AFFECTED_FLAG`, since print arms also raise
   `_AFFECTED_REQ`), then `TEST_GROUP` normalises to `all`. All heuristic machinery removed;
   `want_*` disjuncts, the subagent/sibling refusal `!= "affected"` conjuncts, the
   whole-tree untracked append for the group, and the epilogue note all re-expressed in
   terms of `_AFFECTED`/`_TG_AFFECTED_ALIAS`. Banner and `--help` updated.
2. `scripts/test-all-group-affected.test.sh` rewritten as the alias-contract suite:
   structural pins (validation, arming, normalisation ordering, removal sentinels,
   always-on floor, refusal substitute naming, deprecation note) + functional arms
   (byte-identical `--print-selection`, edge-suite declines on irrelevant diff / selects
   on subject diff, combo rc=2s, sandbox refusal exemptions).
3. Pins updated: `test-all-affected.test.sh` (k2 banner, k4 help, sc8/sc9 comments),
   `test-all-weight-drift.test.sh` (mutation anchor for the re-shaped arming conjunct),
   `test-all-orphan-log-retention.test.sh` + `scripts/lib/test-relevance-paths.sh`
   (stale comments), `collision-precheck.test.sh` (message wording — the lead-gate span
   stays `TEST_GROUP=affected`-free by construction).
4. Skill prose in `work`/`review`/`ship` SKILL.md + `risk-tier-and-fix-rounds.md` updated:
   the spelling is documented as the deprecated alias, never a distinct selector. The
   literal `TEST_GROUP=affected bash scripts/test-all.sh` remains in the spawned-agent
   carve-outs (still a working spelling) — outside the lead-gate span
   collision-precheck forbids.

## Test Scenarios

- `scripts/test-all-group-affected.test.sh` — the rewritten alias suite.
- `scripts/test-all-affected.test.sh` — the declared selector's mutation suite (banner/help
  pin updates only).
- `plugins/soleur/test/fanout-suite-scope.test.sh` — arms 8c/8d run and pin the
  `TEST_GROUP=affected` substitute spelling (still valid via the alias).
- `plugins/soleur/test/collision-precheck.test.sh` — lead-gate span stays clean.
- `scripts/test-all-weight-drift.test.sh` — timing-log arming under the alias.

## Observability

- **metric_name:** `AFFECTED_SUMMARY` / `NOTE: TEST_GROUP=affected is a deprecated alias`
- **logs:** runner stdout/stderr; `AFFECTED_FALLBACK`, `AFFECTED_SELECTED` receipts
- **alerts:** none — local gate output
- **dashboard:** none
- **discoverability_test:** `TEST_GROUP=affected bash scripts/test-all.sh --print-selection --paths=<p>` matches `--affected` output byte-for-byte (suite arm B1).

## Guard Contract

### Guard 1 — the alias arms the declared-edge axis, never a second selector

**Property.** `TEST_GROUP=affected` produces exactly the `--affected` selection: arming
happens at `_aff_group_req`, normalisation to `all` happens after the ambiguity refusal
and before any consumer of `TEST_GROUP`, and no heuristic predicate survives anywhere in
the runner.

**Assembly.** The `_aff_group_req`/`_TG_AFFECTED_ALIAS` block in `scripts/test-all.sh`;
the ambiguity-refusal + normalisation pair; the deleted `_suite_affected`/`_aff_stem`/
`_AFFECT_PATTERNS` span; `run_suite`'s chokepoint (now `_aff_sel`-only).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `_aff_group_req` no longer arms `_AFFECTED` on `affected` | RED — suite A2 greps the arming block; B4 sandbox arm shows the run dispatching |
| 2 | Normalisation line deleted (TEST_GROUP=affected leaks downstream) | RED — B1 parity arm: `_affected_classify`'s group rung would force-select all, diverging from `--affected` output |
| 3 | Heuristic predicate resurrected (any of `_suite_affected`/`_aff_stem`/`_AFFECT_*`) | RED — A5 presence-grep sentinels |
| 4 | Ambiguity refusal widened to print arms (alias + --print-selection refused) | RED — B1/B3 arms require the compose-valid spellings |
| 5 | Combo refusal removed entirely | RED — B3 arms pin rc=2 for `+ --affected` and `+ --full` |
| 6 | Must-PASS non-canonical: positional `affected` + `--print-selection` | PASS — identical stdout to the flag spelling (B3) |

**Anchor.** Not applicable — the guard compares selection streams, not stored values.

### Guard 2 — the prescribed substitute still proceeds under both refusals

**Property.** `TEST_GROUP=affected` (and `--affected`) is exempt from the SOLEUR_SUBAGENT
and sibling-contention rc=4 refusals — the refusal text's prescribed substitute can never
be a dead end — while a genuine full-shaped ask is still refused.

**Assembly.** The subagent refusal at the post-parse site and the sibling refusal at the
post-derivation site in `scripts/test-all.sh`; both refusal bodies' substitute text; the
`sandbox` arms in `scripts/test-all-group-affected.test.sh` Part B4 and
`plugins/soleur/test/fanout-suite-scope.test.sh` Arm 8c/8d.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Alias not exempt under SOLEUR_SUBAGENT=1 (e.g. _AFFECTED armed too late) | RED — B4 arm: subagent + alias must dispatch (rc=0, fixture runs) |
| 2 | Alias not exempt under a measured sibling | RED — B4 arm: TC_SIBLING_RUN_COUNT=2 + alias must dispatch |
| 3 | Refusal text drops the `TEST_GROUP=affected` substitute spelling | RED — A7 structural pin + fanout Arm 8c/8d greps |
| 4 | Refusal stops firing on real full asks | RED — B4 arm: sibling + `--full` must exit 4 |
| 5 | Epilogue deprecation note removed (alias run reads as canonical) | RED — A8 pin keyed on `_TG_AFFECTED_ALIAS` |
| 6 | Must-PASS non-canonical: alias + `--affected-scope=staged` | PASS — staged scope composes (sc8 in test-all-affected.test.sh) |

**Anchor.** Not applicable — behaviour, not a stored value.
