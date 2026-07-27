---
title: "Context-governance instrument fixes (Claude-5 context-engineering audit)"
date: 2026-07-27
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-07-27-context-engineering-claude5-audit-brainstorm.md
branch: feat-context-engineering-audit
pr: 7006
---

# Spec — Context-governance instrument fixes

## Problem Statement

Anthropic's Claude-5 context-engineering guidance prescribes a rules diet Soleur already
ran (36% of rules retired, discoverability litmus landed 2026-04-23). The audit found no
warrant for a further deletion campaign, but did find that **the instruments governing
context are misreporting**, in the same direction — they understate real footprint and
overstate coverage:

1. `session-rules-loader.sh:247` computes its total-rule denominator with the glob
   `AGENTS*.md`, which matches the index *and* the bodies, double-counting every rule.
   The session stamp reads `(101 of 202 rules)` — apparently 50% — when 100% of the
   corpus is loaded.
2. Consequently nobody has observed that progressive disclosure is **8.7% effective**:
   70% of PRs are multi-class and load all three sidecars (43.5 KB), because Soleur's own
   inflow gates put a `.md` in nearly every code PR.
3. `scripts/lint-agents-rule-budget.py` gates `B_ALWAYS` on `AGENTS.md + AGENTS.core.md`
   only (22,900 B), which is **53% of the 43,513 B** actually injected in the fail-open
   case. The governance ceiling protects a figure that is not the real one.
4. The skill-description budget is **exceeded by 27.6%** (2,296 words against an enforced
   1,800 cap) with no gate having fired.
5. `scripts/rule-prune.sh:167` exempts only `[hook-enforced]`/`[skill-enforced]` rules
   from retirement proposals — **not `[compliance-tier]`** — so the quarterly pruner can
   propose retiring a rule cited by the Art. 30 register or the published DPD.
6. `knowledge-base/legal/article-30-register.md:417` cites `hr-block-pr-ready-on-undeferred-operator-steps`,
   which does not exist (real id is `wg-`). A register citation is already dangling.

## Goals

- Make every context-governance instrument report a true number.
- Surface the real progressive-disclosure effectiveness so future decisions rest on it.
- Close two latent compliance defects found incidentally.
- Restore the skill-description budget to within its enforced cap.

## Non-Goals

- **No rule deletions.** Explicitly out of scope (brainstorm decision; #6794 forbids
  pruning on `rules_unused_over_8w`).
- **No change to the class axis or sidecar split.** Deferred until the fixed instrument
  has produced observations.
- **No softening of any `[compliance-tier]` or `**Why:** #NNNN` rule.**
- **No adoption of auto-memory.** `hr-never-write-to-claude-code-memory-claude` stands.
- Fixing the 11 shipped plugin files that reference root-only governance paths — separate
  issue (see FR6 note).

## Functional Requirements

**FR1 — Loader denominator counts rules once.**
`session-rules-loader.sh:247` must count rule bodies only, excluding the `AGENTS.md`
index. Change the glob from `AGENTS*.md` to the three body sidecars. After the fix, a
fail-open session must stamp `(101 of 101 rules)`.

**FR2 — Stamp reports byte footprint, not just rule count.**
The stamp must additionally report loaded bytes against total corpus bytes, e.g.
`43513/43513 B`. Rule count alone cannot express that a docs-only session loads 62% of
the bytes; bytes are the quantity the harness cost scales with.

**FR3 — Budget gate measures the real fail-open footprint.**
`lint-agents-rule-budget.py` must report `B_FAILOPEN` (all four files, frontmatter-stripped)
alongside the existing `B_ALWAYS`. `B_ALWAYS` keeps its 20,000/23,000 thresholds as the
hard gate; `B_FAILOPEN` is reported for visibility this iteration and **must not** gate —
introducing a second blocking ceiling at 43.5 KB would immediately REJECT and wedge the
repo. Thresholding it is a follow-up decision, not this PR's.

**FR4 — Skill-description budget restored under cap.**
Reduce total skill `description:` frontmatter from 2,296 words to ≤1,800 (−496 minimum).
Trim the longest descriptions first (`flag-delete` 260 ch, `model-launch-review` 251,
`reproduce-bug` 248, `community` 242, `trigger-cron` 239). Each trimmed description must
retain its disambiguating trigger terms — these are the routing surface, and over-trimming
causes mis-routing. Per `cq-skill-description-budget-headroom`.

**FR5 — `rule-prune.sh` exempts compliance-tier rules.**
Add `[compliance-tier]` to the exemption predicate at `scripts/rule-prune.sh:167`, so the
pruner can never propose retiring a rule whose id is cited by a legal artifact.

**FR6 — Dangling register citation corrected.**
`article-30-register.md:417`: `hr-block-pr-ready-on-undeferred-operator-steps` →
`wg-block-pr-ready-on-undeferred-operator-steps`. Verify the corrected id resolves against
`AGENTS.md` before commit.

## Technical Requirements

**TR1 — Regression test for FR1/FR2.**
Extend `.claude/hooks/session-rules-loader.test.sh`: assert the stamp's `N of M` has
`M == 101` and that `M` equals the body-sidecar rule count computed independently. This
test must fail against the current implementation before the fix (per `cq-write-failing-tests-before`).

**TR2 — Class-share measurement is reproducible.**
Land the 80-PR classification as a script so the 8.7%-effective figure can be re-measured
rather than re-derived by hand. It must consume the loader's own `DOCS_RE`/`CODE_RE`/`INFRA_RE`
rather than copying them, so the two cannot drift.

**TR3 — No behaviour change to class selection.**
FR1–FR3 are reporting-only. The set of rules loaded for any given changeset must be
byte-identical before and after. Assert by diffing loader output across the three class
paths on fixed inputs.

**TR4 — Budget lint stays green.**
`python3 scripts/lint-agents-rule-budget.py` must not regress from `[WARN]` to `[REJECT]`.
Current headroom is 100 B; no FR here adds sidecar bytes.

**TR5 — Rule-id integrity preserved.**
`scripts/lint-rule-ids.py` must exit 0. FR6 changes a citation in a legal document, not a
rule id; `cq-rule-ids-are-immutable` is unaffected.

## Acceptance Criteria

- [ ] Fail-open session stamps `(101 of 101 rules)` plus a byte figure.
- [ ] `session-rules-loader.test.sh` covers the denominator; fails pre-fix, passes post-fix.
- [ ] `lint-agents-rule-budget.py` reports both `B_ALWAYS` and `B_FAILOPEN`; verdict still `[WARN]`.
- [ ] Skill descriptions total ≤1,800 words.
- [ ] `rule-prune.sh --dry-run` proposes zero `[compliance-tier]` rules.
- [ ] `article-30-register.md:417` cites a rule id that exists in `AGENTS.md`.
- [ ] Loader output byte-identical across all three class paths (TR3).
- [ ] Zero rules added, deleted, or reworded.
