---
feature: feat-one-shot-9399-review-panel-risk-tier
lane: cross-domain
brand_survival_threshold: none
refs: [9399, 9412, 9339]
plan: knowledge-base/project/plans/2026-10-01-chore-review-panel-risk-tier-targeted-seats-plan.md
status: draft
created: 2026-10-01
---

# Spec — Scale review panel to risk tier; targeted seats for fix commits

## Problem Statement

PR #9339 (2026-10-01): a small disk-leak fix drew an 11-seat review panel because its plan declared
`single-user incident`, then fix commits introduced new defects that cost further rounds and ~8 CI
cycles. The panel is composed on one axis (diff-shape class); there is no risk axis, the
brand-survival threshold that drives panel size is never recorded as a challengeable decision, fix
commits get no seat-level re-review, and cross-seat duplicate findings are deduplicated implicitly,
not auditable.

## Goals

- **G1** — The plan's `brand_survival_threshold` is written as an explicit, challengeable decision
  (`**Threshold decision (challengeable):**` line in `## User-Brand Impact`), routed per ADR-084:
  surfaced at the existing post-plan-review gate when attached; appended to
  `decision-challenges.md` when headless and the declared value is `single-user incident` or
  `aggregate pattern`.
- **G2** — `soleur:review` resolves a *risk tier* (the 3-value `brand_survival_threshold` enum) from
  the PR body, else the linked plan, else `none` — with a fail-closed clamp: undeclared +
  `SENSITIVE_PATH_RE` match → `single-user incident`. Seats scale per the tier table; review never
  spawns below the declared tier and reports over-declaration as a `mismatch` note.
- **G3** — After the first full panel, fix-commit batches are reviewed by targeted seats resolved by
  `plugins/soleur/skills/review/scripts/fix-round-seats.sh` (reporting-seat union + path map +
  conditional seats), report-only against the fix diff, capped at two rounds before escalation to
  the full class panel, followed by exactly one verification pass.
- **G4** — Cross-seat findings are deduplicated into an emitted ledger (finding → canonical defect →
  reporting seats → fix commit) *before* any fix dispatch; the summary reports `dedup: N → M`.
- **G5** — Every review run reports seats spawned versus tier (announce line + `### Review Agents
  Used` line + `Reviewed-Risk-Tier:` git trailer via `emit-review-trailer.sh --risk-tier`).

## Non-Goals

- **NG1** — No consumer for `Reviewed-Risk-Tier:` in ship/preflight (ADR-127: record now, gate later
  if ever).
- **NG2** — Wiring `resolve-pr-parallel`'s comment-driven fixes into the fix round — deferred to
  #9412 with re-evaluation criteria.
- **NG3** — A new low/medium/high tier vocabulary — the `brand_survival_threshold` enum is the
  carrier.
- **NG4** — Model-tier changes for any seat (ADR-053/ADR-110 pins untouched).
- **NG5** — Changing the `deep review`/`full review` override — it always forces the full set.

## Functional Requirements

- **FR1** — `references/risk-tier-and-fix-rounds.md` (new) is the normative contract: tier
  resolution order, seat-scaling table, announce/report formats, fix-round contract, dedup ledger
  spec. `review/SKILL.md` carries pointer lines only (net ≤ +184 B; byte ceiling binding).
- **FR2** — `fix-round-seats.sh` prints the resolved seat set (deduped, floor-ordered), exit 0 on
  valid input, exit 2 on usage error; a source-touching fix diff never resolves empty (code-quality
  floor + `unmapped-paths:` stderr note).
- **FR3** — `review.workflow.js` `CLASSIFY_SCHEMA` carries `brandThreshold` (enum incl.
  `undeclared`); `user-impact` conditional fires on `single-user incident` or `aggregate pattern`;
  `SKEPTICS=3` at `aggregate pattern`; `report` gains `riskTier`/`seatsSpawned`/`mergedGroups`.
- **FR4** — `emit-review-trailer.sh --risk-tier <enum>` validates against the 3-token resolved enum and emits
  a parseable `Reviewed-Risk-Tier:` trailer line; the flag is optional (absent ≠ fabricated).
- **FR5** — `plan-issue-templates.md` carries the `**Threshold decision (challengeable):**` line in
  all three `## User-Brand Impact` blocks plus the ADR-084 routing comment; `plan/SKILL.md` Phase
  2.6 gets a ≤ +14 B surgical pointer.
- **FR6** — `one-shot` Step 5 runs `soleur:review <PR> --fix-round` after resolver-agent commits.
- **FR7** — ADR-267 (provisional ordinal; #264 claimed by a sibling branch) records the decision;
  `model.c4`'s `platform.plugin.review` description stops claiming a fixed 8-seat panel.
- **FR8** — Guards: `fix-round-seats.test.sh` (Guard-1 matrix), `emit-review-trailer.test.sh` rows
  (Guard-2), `plugins/soleur/test/review-tier-parity.test.ts` (Guard 3 — reference table ↔ workflow
  gating ↔ script map arms, three-way).

## Constraints

- Lifecycle SKILL.md byte ceilings (merge-base anchored, this PR cannot raise): plan +14 B,
  review +184 B, one-shot +856 B. Normative prose lives in `references/`.
- `fix-round-seats.sh` must be POSIX/macOS-portable (no `timeout`, `sed -i`, `readlink -f`,
  `stat -c`, `date -d`).
- `discoverability_test.command` must contain no shell metacharacters (preflight Check 10).
