---
feature: operator velocity metrics in operator-digest
issue: 5986
epic: 5983
branch: feat-one-shot-5986-operator-velocity-metrics
lane: cross-domain
plan: knowledge-base/project/plans/2026-07-04-feat-operator-velocity-metrics-plan.md
---

# Tasks — operator velocity metrics in operator-digest

Derived from the finalized (post-review) plan. TDD: RED test → GREEN prose.

## Phase 0 — Preconditions

- [ ] 0.1 Confirm allowlist has no `git show`/`git cat-file`: `grep -o 'Bash([^)]*)' plugins/soleur/skills/operator-digest/assets/operator-digest.workflow.yml`.
- [ ] 0.2 Confirm §1 `--json` field list is `title,labels,mergedAt` (no `author`): `grep -n 'json title,labels,mergedAt' plugins/soleur/skills/operator-digest/SKILL.md`.
- [ ] 0.3 Re-read the digest register + read-failure guardrail so new prose reuses their framing.

## Phase 1 — RED (extend `plugins/soleur/test/operator-digest-skill.test.sh`)

- [ ] 1.1 Add cadence assertion (`cadence` + `recent weeks`/`typical`; NO exact multiplier).
- [ ] 1.2 Add cost-trend assertion (`run-rate` + `roughly \$`/`about \$`).
- [ ] 1.3 Add read-integrity assertion (cadence band + run-rate anchor both suppressed on read doubt / ambiguous cadence).
- [ ] 1.4 Add run-rate allowlist assertion (`only.*active` + `accruing`; NO denylist enumeration).
- [ ] 1.5 Add **command-anchored** per-contributor refute (grep the `gh pr list … --json` line, strip comments, FAIL if `author` in field list) + a "company-aggregate only" guard-line assertion worded so `--json`→`author` never appears in that order.
- [ ] 1.6 Add vanity-output guard assertion (forbids raw counts/percentages/arrows; mandates consequence-framing).
- [ ] 1.7 Run the test → NEW assertions fail, existing pass. Verify the refute passes GREEN against the guard prose (does not false-trip).

## Phase 2 — GREEN (edit `plugins/soleur/skills/operator-digest/SKILL.md`)

- [ ] 2.1 §1 cadence fold-in: qualitative band vs recent weeks, default "about the same" on doubt; suppress downward band on §1 read failure / 300-cap truncation / near-empty; consequence-framed; merge-count not code-size; graceful degradation with <few weeks history.
- [ ] 2.2 §2 cost-trend fold-in — direction line (primary) from the existing diff; a non-active status merely recorded in the diff is not an increase.
- [ ] 2.3 §2 coarse run-rate anchor (only when clean): fail-safe allowlist (only `active`/`accruing`-with-actual; unknown status excluded); normalize known annual rows; suppress anchor on ambiguous cadence; Recurring table only; one aggregate figure; ⚠️ on Read error; first-run "no cost trend yet".
- [ ] 2.4 Guard note under Scope guardrails: aggregate-only; "never add an `author` field to the §1 `gh pr list --json` list"; suppress-on-doubt; no vanity vocabulary.
- [ ] 2.5 Run the contract test → all GREEN.

## Phase 3 — Full suite + docs

- [ ] 3.1 `bash plugins/soleur/test/operator-digest-skill.test.sh` + siblings (`operator-digest-workflow.test.sh`, `digest-scrub.test.sh`, `operator-digest-provision.test.sh`) green.
- [ ] 3.2 `bun test plugins/soleur/test/components.test.ts` green (description unchanged → no budget bump).
- [ ] 3.3 Confirm no README component-count change.

## Phase 4 — Required dry-verify (behavioral gate, AC9)

- [ ] 4.1 Normal week / deferred-row-in-diff (no "cost up").
- [ ] 4.2 True-quiet vs partial-read (must differ; partial-read never "quieter").
- [ ] 4.3 300-cap truncation → neutral band.
- [ ] 4.4 Mixed monthly/annual/deferred ledger → anchor ballpark-correct or suppressed on ambiguity.
- [ ] 4.5 §2 Read error → ⚠️, anchor suppressed.

## Phase 5 — Record resolution + deferral

- [ ] 5.1 Mark OQ3 resolved in `knowledge-base/project/specs/feat-gstack-capability-adoption/spec.md` with a pointer to the plan's resolution table.
- [ ] 5.2 File the deferral tracking issue (true MoM cost trend + state-block baseline; `type/feature`, Post-MVP / Later) per the plan's Alternatives section.
