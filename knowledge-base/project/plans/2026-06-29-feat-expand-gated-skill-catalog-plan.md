---
title: "feat: expand gated-skill catalog with golden sets for more classifier surfaces"
type: feat
date: 2026-06-29
issue: 5704
branch: feat-expand-gated-skill-catalog
worktree: .worktrees/feat-expand-gated-skill-catalog
pr: 5719
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
brainstorm: knowledge-base/project/brainstorms/2026-06-29-expand-gated-skill-catalog-brainstorm.md
spec: knowledge-base/project/specs/feat-expand-gated-skill-catalog/spec.md
governing_adr: ADR-069-validation-gated-classifier-skill-edits
deferred: 5722
---

# feat: expand gated-skill catalog with golden sets for more classifier surfaces ✨

## Overview

Bring two more **single-token, LLM-applied** classifier surfaces under the eval-harness validation
gate (ADR-069; shipped #5701/#5702, merged 2026-06-29) via the additive-target recipe:

1. **brainstorm lane-inference** — `procedural | single-domain | cross-domain`
   (`plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md` §Lane Inference table).
2. **incident brand_survival_threshold** — `none | single-user incident | aggregate pattern`
   (`plugins/soleur/skills/incident/SKILL.md` §Phase 1 — Classification criteria).

Delivered as **one PR, two commits** (lane-inference, then incident-threshold). `Ref #5704`;
#5704 is closed automatically after merge. pdr-* multi-label gating stays deferred (#5722).

**Scope correction (plan-review):** the brainstorm's second surface was skill-security-scan;
Kieran + spec-flow proved it is a **deterministic** scanner (`run-scan.sh` aggregates verdicts via
`jq`, not an LLM), so its prose is documentation of a rule pipeline, not an LLM-applied rubric — a
dishonest projection target. Operator approved replacing it with incident brand_survival_threshold,
whose Phase 1 criteria block IS the LLM-applied decision rule (same honest shape as lane-inference /
go-routing). Both chosen surfaces emit one label the model reasons to from prose.

## Premise Validation

- **#5704 trigger fired:** #5702 (CLOSED) closed by #5701 (MERGED 2026-06-29T15:36Z); gate live on
  go-routing + ticket-triage. Verified live.
- **Mechanism verified against installed code** (not the README, which undersells touch points): read
  `gated-skills.json`, `gen-skill-prompt.cjs` (`TARGET_CONFIG`), `eval-gate.cjs` (`TARGET_RESOURCES`),
  `extract-block.cjs`, `parse-label.cjs`, `promptfooconfig.go-routing.yaml`, `extract-block.test.sh`,
  `eval-gate.test.sh`, `run-scan.sh`, incident/SKILL.md Phase 1.
- **ADR-069:** no clause limits the gate to two surfaces; the recipe is its designed extension path.
  This plan applies ADR-069 — no new ADR (see §Architecture Decision). #5703 (deferred CI
  projection-integrity backstop) is out of scope.
- **Multi-word label `single-user incident` is parser-safe:** `parse-label.cjs extractLabel` matches
  the full label via exact-match (tier 1) and a word-boundary regex whose boundary class
  (`[^A-Za-z0-9-]`) treats the internal space as literal (tier 2). No parser change needed; the render
  wrapper must instruct "respond with ONLY one of: none | single-user incident | aggregate pattern".

## Research Reconciliation — Spec vs. Codebase

| Spec/brainstorm claim | Codebase reality | Plan response |
|---|---|---|
| "no new code / no new assert script" | True for asserts + `models.generated.json`. But adding a target edits **THREE hardcoded per-target maps**: `gen-skill-prompt.cjs TARGET_CONFIG` (render+enumPath), `eval-gate.cjs TARGET_RESOURCES` (tasks+enumPath — **the gate itself**), and the `extract-block.test.sh` round-trip loop. | FR-A3/A4/A5 below. Plus a **registry-coverage consistency test** so a missed map fails CI (closes the silent-gap class). |
| skill-security-scan is a "genuine LLM judgment" (CTO) | `run-scan.sh:110-116` computes the verdict with `jq` over per-category YAML/regex rule files — deterministic, not LLM. §Verdict semantics is the aggregation rule only; detection criteria live in external rule files. | Surface replaced with incident brand_survival_threshold (operator-approved). |
| golden set + prompts + config + registry row is the additive unit; AC4 round-trip covers it | `extract-block.test.sh` loop is **hardcoded** (`for target in go-routing ticket-triage` + filename ternary) — a new target gets NO round-trip coverage. | Data-drive the loop from `gated-skills.json` (read `target` + `projected_prompt_path`) so future surfaces need no test edit. |
| baseline prompt is "added" with the skill prompt | Only the skill arm is generated; baseline is hand-authored (label-set only). | Baseline hand-written; skill generated. |

## Architecture decision recorded earlier in review

The gate path (`eval-gate.cjs --target`) — NOT the measurement config (`promptfooconfig.*.yaml`) — is
what ADR-069 protects. The original ACs asserted only the measurement path, so the gate would have
shipped **dormant** (registered via `--check`, dies fail-closed on `--target`) with every AC green.
The revised ACs exercise the gate path (`--dry-run --target`).

## Implementation (one PR, two commits)

Each surface follows the same recipe. Steps are in **dependency order** (the generator reads the
registry, so the registry row precedes prompt generation):

1. **Enum** — `enums/<target>.json` (the closed label set).
2. **Source sentinels** — wrap the **classifier rule block only** in the source file with
   `<!-- eval-gate:block:<target>:start -->` / `:end`. Pin the span to the decision rule; exclude
   adjacent meta-prose (see per-surface spans below). Do not alter headings/tables read by heading.
3. **`gen-skill-prompt.cjs TARGET_CONFIG`** — add an entry (`enumPath` + a `render()` wrapper mirroring
   go-routing: instruction header → block → "respond with ONLY one of {tokens}" → `{{input}}`).
4. **`gated-skills.json`** — add the row (`source_file`, `block_id`, markers, `target`,
   `projected_prompt_path: prompts/<target>-skill.txt`).
5. **Prompts** — hand-write `prompts/<target>-baseline.txt` (labels only); generate
   `prompts/<target>-skill.txt` via `node scripts/gen-skill-prompt.cjs <target>`.
6. **Golden set** — `tasks/<target>.jsonl`, ~6–8 **synthesized** tasks (`cq-test-fixtures-synthesized-only`):
   ≥1 per label + adversarial cross-label cases (see per-surface notes).
7. **Config** — `promptfooconfig.<target>.yaml` mirroring go-routing (providers, two prompts,
   `defaultTest.vars.enum: file://enums/<target>.json`, two shared asserts, `tests: file://tasks/<target>.jsonl`).
8. **`eval-gate.cjs TARGET_RESOURCES`** — add `{tasks, enumPath}` so the gate path resolves.
9. **Opt-in run** — `bash scripts/gen-models.sh` then
   `npx promptfoo eval -c promptfooconfig.<target>.yaml --repeat 3`; capture the baseline-vs-skill delta.

**Commit 1 — lane-inference.** Source: `brainstorm-domain-config.md` §Lane Inference. Sentinel span:
the rule (table + fail-closed default) — **exclude** the USER_BRAND_CRITICAL×lane composition
paragraph (input-flag orchestration, NOT inferable from a feature description → not token-classifiable),
the "Carry-forward contract" (provenance), and "Stability" (enum-freeze) meta paragraphs. enum =
`["procedural","single-domain","cross-domain"]`. Golden adversarial cases: a description carrying BOTH
a cross-domain trigger (`audit`/`security`/…) and a procedural trigger (`scaffold`/`lint-fix`/…) →
asserts documented precedence (`procedural`/`single-domain` both require "no cross-domain trigger").
**Expect a muted delta** (deterministic keyword scan) — frame value as **regression detection**, not
arm uplift.

**Commit 2 — incident-threshold.** Source: `incident/SKILL.md` §Phase 1 — Classification, the 3-tier
criteria block (the `none` / `single-user incident` / `aggregate pattern` bullets + their intro) —
**exclude** the advisory-output example and the "Confirm advisory / override" prompt below it. enum =
`["none","single-user incident","aggregate pattern"]`. Golden adversarial cases: an internal-tooling
incident with no user surface (→ `none`) vs a single credential-exposure (→ `single-user incident`) vs
a systemic multi-tenant breach (→ `aggregate pattern`), plus a borderline single-vs-aggregate case.
**Genuine LLM-applied rubric → expect a meaningful delta.**

**Shared (one commit, either):** add a **registry-coverage consistency test** (extend
`eval-gate.test.sh` or a small new test) asserting every `gated-skills.json` target appears in BOTH
`TARGET_CONFIG` (gen-skill-prompt.cjs) and `TARGET_RESOURCES` (eval-gate.cjs). Data-drive the
`extract-block.test.sh` round-trip loop from the registry (`target` + `projected_prompt_path`) so it
covers both new targets (and all future ones) without per-surface edits.

## Files to Create

Under `plugins/soleur/skills/eval-harness/`: `enums/lane.json`, `enums/incident-threshold.json`,
`tasks/lane-inference.jsonl`, `tasks/incident-threshold.jsonl`,
`prompts/lane-inference-{baseline,skill}.txt`, `prompts/incident-threshold-{baseline,skill}.txt`
(skill arms generated), `promptfooconfig.lane-inference.yaml`,
`promptfooconfig.incident-threshold.yaml`.

## Files to Edit

- `plugins/soleur/skills/eval-harness/gated-skills.json` — two new rows.
- `plugins/soleur/skills/eval-harness/scripts/gen-skill-prompt.cjs` — two `TARGET_CONFIG` entries.
- `plugins/soleur/skills/eval-harness/scripts/eval-gate.cjs` — two `TARGET_RESOURCES` entries.
- `plugins/soleur/skills/eval-harness/test/extract-block.test.sh` — data-drive the round-trip loop.
- `plugins/soleur/skills/eval-harness/test/eval-gate.test.sh` — add registry-coverage consistency test.
- `plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md` — lane sentinels.
- `plugins/soleur/skills/incident/SKILL.md` — incident-threshold sentinels.

## Acceptance Criteria (Pre-merge)

- AC1: `gated-skills.json` has **4** rows; each new row's `source_file` exists and carries both
  sentinel markers — `git grep -c "eval-gate:block:lane-inference" -- '**/brainstorm-domain-config.md'`
  == 2 and `git grep -c "eval-gate:block:incident-threshold" -- '**/incident/SKILL.md'` == 2.
- AC2: `node scripts/eval-gate.cjs --check <source>` prints `gated:true` with the right `target`/`block_id`
  for both source files. (Note: `--check` is a registry-wiring proxy; block extractability is asserted by AC4/AC5.)
- AC3 (**gate path — the load-bearing AC**): `node scripts/eval-gate.cjs --dry-run --target lane-inference --repeat 5`
  and `--target incident-threshold --repeat 5` each print a valid skill-arm call estimate and exit 0
  (NO API). This fails if `TARGET_RESOURCES` is missing — i.e. it proves the gate is actually wired.
- AC4: registry-coverage consistency test green — every registry target ∈ `keys(TARGET_CONFIG)` ∩ `keys(TARGET_RESOURCES)`.
- AC5: `bash scripts/test-all.sh` green, including the data-driven round-trip asserting each committed
  `prompts/<target>-skill.txt` == freshly generated (stale projection fails CI).
- AC6: `npx promptfoo validate config -c promptfooconfig.<target>.yaml` passes for both (no API).
- AC7: PR body records BOTH opt-in deltas (lane: muted → regression-detection framing; incident:
  meaningful) + the API-call count + spend disclosure (`hr-autonomous-loop-skill-api-budget-disclosure`).
- AC8: `git diff` on each source file shows only the two inserted sentinel comment lines (headings,
  tables, and criteria bullets otherwise unchanged).
- AC9: PR body uses `Ref #5704` (NOT `Closes/Fixes`) — guard: `gh pr view <PR> --json body --jq .body | grep -iqv 'clos.*#5704\|fix.*#5704'`.

### Post-merge (automated, by the merging agent — not operator)
- AC10: after the PR merges, run `gh issue close 5704` (closure gated on both commits landing; #5722
  stays open). This is an agent-runnable `gh` call per the never-defer-operator stance — not a checklist item.

## User-Brand Impact

**If this lands broken, the user experiences:** a weak golden set lets a future edit to the
lane-inference or incident-threshold rule prose regress undetected; an agent then mis-classifies a
real case — e.g. incident-threshold grades a real single-user credential exposure as `none`, so the
PIR / Art. 33 notification path is never triggered; or lane mis-sizing drops a domain leader so a
user-impact gate never fires. **A dormant gate (the TARGET_RESOURCES P0) is this exact failure mode**
shipping green — which is why AC3 exercises the gate path.

**If this leaks:** n/a — synthesized fixtures + config only; no user data, credential, auth, or
external-write surface (`cq-test-fixtures-synthesized-only`).

**Brand-survival threshold:** single-user incident (carried from brainstorm). Vector is second-order
(this PR gates *future edits*); held rather than downgraded because the incident-threshold surface
guards the GDPR-notification classification path. **Scope-out (user-impact-reviewer FINDING 1):** the
lane gate covers only the *breadth* decision (the keyword table). The `USER_BRAND_CRITICAL → forced
CPO+CLO+CTO triad` composition — the mechanism that actually fires the user-impact gate on a
brand-critical feature — is deliberately OUTSIDE the gated span, because it is driven by an input flag
(not the feature description) and so cannot be golden-set through a single-token lane classifier. It is
protected by the unconditional override in `brainstorm-domain-config.md` §User-Brand-Critical Tag
Processing + brainstorm Phase 0.1, NOT by this gate. **CPO sign-off:** carried from brainstorm framing;
`user-impact-reviewer` at PR-review is the load-bearing gate.

## Domain Review

**Domains relevant:** Engineering (carry-forward).

### Engineering (CTO) — carry-forward + plan-review correction
**Status:** reviewed. lane-inference + (originally) skill-security-scan as single-token fits; plan-review
corrected the second surface to incident-threshold (skill-security-scan is deterministic, not
prose-projectable). One PR, two commits. Lane delta muted (regression-detection framing). No capability gaps.

### Product/UX Gate
**Tier:** none — no UI-surface file (all `.json`/`.jsonl`/`.yaml`/`.txt`/`.cjs`/`.sh` + markdown sentinels).

## Observability

Phase 2.9 trigger fires (edits `eval-gate.cjs` + `gen-skill-prompt.cjs` under `plugins/*/scripts/`).
The surfaces are **build-time pure functions** (a projection generator + a gate orchestrator run at
dev/CI time), not a runtime service: **liveness** = the AC3 gate-path dry-run + AC4 consistency test +
AC5 round-trip, all on every CI run; **fail-loud** = CI job exit code (red on the PR); **discoverability**
= `bash plugins/soleur/skills/eval-harness/scripts/test-all.sh` (no `ssh`, no Sentry — no production
runtime path exists).

## Architecture Decision (ADR/C4)

No new architectural decision — applies ADR-069's designed extension path; no new substrate, ownership,
or trust boundary. **C4:** the C4 model scopes the web-platform product; this change touches only
`plugins/soleur/skills/**` plugin tooling (zero `apps/web-platform/**`), adds no external system/actor/
data-store, so there is no product-C4 element or relationship to add. No `.c4` edit.

## Compliance dispositions

- **GDPR (2.7):** trigger (b) (single-user-incident threshold) fires, but zero regulated-data surface —
  no schema/migration/auth/API/`.sql`; golden inputs are synthesized fixtures, not operator-session
  data. No-op; recorded, not run on an empty surface.
- **IaC (2.8):** no new infrastructure; the opt-in run uses the existing `ANTHROPIC_API_KEY`. Skip.

## Sharp Edges

- Adding a target edits **three** hardcoded maps (TARGET_CONFIG, TARGET_RESOURCES, + the test loop
  until data-driven). The README's "additive recipe" implies data-only — it isn't. AC3 (gate-path
  dry-run) + AC4 (consistency test) are what stop a surface shipping with a dormant gate.
- The classifier prose must BE the decision rule the LLM applies (lane table; incident Phase 1
  criteria). A surface whose real classifier is deterministic (skill-security-scan) or external is NOT
  a valid gate target — projecting its prose measures the LLM reconstructing rules it was never given.
- Sentinels must wrap the rule block only; exclude provenance/policy meta (lane Carry-forward/Stability;
  incident advisory-output + confirm prompt). `extract-block.cjs` is pure indexOf/slice — it will
  faithfully project whatever sits between the markers.
- A plan whose `## User-Brand Impact` is empty/placeholder fails deepen-plan Phase 4.6 — this one is filled.
