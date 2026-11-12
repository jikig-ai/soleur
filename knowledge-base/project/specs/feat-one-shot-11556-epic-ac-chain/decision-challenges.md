---
branch: feat-one-shot-11556-epic-ac-chain
issue: 11556
plan: knowledge-base/project/plans/2026-11-12-ci-epic-11556-ac-chain-followthrough-plan.md
created: 2026-11-12
---

# Decision Challenges — feat-one-shot-11556-epic-ac-chain

Headless run note: this session runs inside the Devin subagent harness where
the planning seat has no nested-subagent spawn capability, so the remaining
unruled `technical` rows below are carried as `pending - assumed:` defaults
for the parent orchestrator to carry through ONE batched
`soleur:engineering:cto` spawn and rewrite to `Ruled by CTO agent, <date>:`
cells before work/ship — the `technical-ruling-gate.sh --branch` pattern
recorded for this harness in #12446. Rows citing `2026-11-11` are binding
rulings carried verbatim from the archived sibling record
`knowledge-base/project/specs/archive/20261111-210708-feat-one-shot-12626-webplat-monitor-timeout/decision-challenges.md`,
not re-ruled.

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Close threshold for the scheduled-run confirmation probe (≥N green post-merge `soleur-ai[bot]` runs) | technical | pending - assumed: N=2 — covers the 00Z+06Z slots on the first post-merge day; 1 run would prove a single slot only, 4 would delay the tracker's close to day two with no added signal about the fix holding |
| Scheduled-vs-manual run discriminator | technical | pending - assumed: `actor.login == "soleur-ai[bot]"` — verified on live runs (cron dispatches `43275349911`/`43270980378`/`43073594297` vs manual `deruelle` dispatch `43295978800`); cadence-timestamp matching alone would misclassify a manual dispatch at a cadence hour |
| `cancelled` scheduled runs in the probe sample | technical | pending - assumed: excluded (neither PASS nor FAIL) — a cancel is not regression evidence; the monitor's own missed-check-in Sentry watchdog owns the "run never happened" arm |
| Probe asserts the three `test-webplat-mutations (*)` legs per run vs trusting the run-level conclusion | technical | pending - assumed: probe asserts legs itself — the EXPECTED_LEGS census already guards missing legs at run level, but the per-run `jobs` read is one bounded API call and keeps the tracker verdict self-contained (leg-silently-dropped is the failure shape the probe exists to see) |
| The deferred `--rows` row-split of `approval-guard1-mutation` folds into the classifier follow-up issue vs a second issue | technical | Ruled by CTO agent, 2026-11-11: confirm fold-in — binding carry of archived ruling "`--rows` deferred to the named follow-up" (decision-challenges 20261111-210708 row on whole-battery-per-leg); the classifier follow-up IS the named follow-up, so the lever lands in the same issue rather than a second tracker |
| Probe test suite shape (fake-`gh` fixture suite vs other harness) | taste | Convention applied, no fork: `ci-push-dedupe-soak-9512.test.sh` precedent pins the fake-`gh` fixture + injected-clock + exit-contract pattern for follow-through probes under `scripts/followthroughs/` |
| Brand-survival threshold `none` | taste | Ruled by CTO agent, 2026-11-11: confirm `none` — binding carry of the archived ruling on the same threshold question for this epic family: internal CI machinery only, worst case degraded internal signal, not user-visible behavior |
| Scope-check: `test-all.sh` `run_suite` registration and runbook Measured-history rows as `inferred` items | taste | Convention applied, no fork: `lint-orphan-test-suites.sh` reds CI on an unregistered `.test.sh` (enforcement contract), and `ci-test-scripts-sharding.md` "Measured history" is the repo's record home for measured rankings — both classified `inferred` with justification in the plan's Plan-Item Provenance table |
