---
branch: feat-one-shot-11556-epic-ac-chain
issue: 11556
plan: knowledge-base/project/plans/2026-11-12-ci-epic-11556-ac-chain-followthrough-plan.md
created: 2026-11-12
---

# Decision Challenges — feat-one-shot-11556-epic-ac-chain

Headless run note: this session runs inside the Devin subagent harness where
the planning seat has no nested-subagent spawn capability, so the four
`technical` rows below were carried as `pending - assumed:` defaults and then
ruled by ONE batched `soleur:engineering:cto` spawn from the parent
orchestrator — the `technical-ruling-gate.sh --branch` pattern recorded for
this harness in #12446. Rows citing `2026-11-11` are binding rulings carried
verbatim from the archived sibling record
`knowledge-base/project/specs/archive/20261111-210708-feat-one-shot-12626-webplat-monitor-timeout/decision-challenges.md`,
not re-ruled.

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Close threshold for the scheduled-run confirmation probe (≥N green post-merge `soleur-ai[bot]` runs) | technical | Ruled by CTO agent, 2026-11-12: N=2 — the tracker closes only after ≥2 completed post-merge `soleur-ai[bot]`-dispatched `main-health-monitor.yml` runs are all green - stricter option at bounded cost; cadence verified `0 */6 * * *` (`cron-main-health-monitor.ts:117`) so N=2 covers the 00Z+06Z slots of the first post-merge day and closes within ~30h; N=1 cannot distinguish "fix holds" from one lucky slot given the immediately-preceding scheduled datapoint failed on pre-merge code; N=4 defers to day two with no added signal; exit-2 NOT-YET keeps the tracker open rather than false-closing |
| Scheduled-vs-manual run discriminator | technical | Ruled by CTO agent, 2026-11-12: discriminate on `actor.login == "soleur-ai[bot]"`, not cadence-timestamp matching - verified on the live run stream (all cron dispatches carry `soleur-ai[bot]`, both manual dispatches carry `deruelle` incl. off-cadence `42893885901`); timestamp matching misclassifies BOTH directions (bot re-dispatches at 17:30/17:35Z off-cadence would false-negative out; a manual dispatch at a cadence hour would false-positive in); the actor IS the dispatch path's identity (`cron-main-health-monitor.ts:76` mints the installation token) |
| `cancelled` scheduled runs in the probe sample | technical | Ruled by CTO agent, 2026-11-12: exclude `conclusion == "cancelled"` scheduled runs — neither PASS nor FAIL evidence - a cancel is an operational event (concurrency-group supersession, human cancel), not evidence about the mutation-leg fix; verified present in this stream (`43270980378`, `43270254272`); the "run never happened" arm is separately owned by `sentry_cron_monitor.main_health_monitor` (`infra/sentry/cron-monitors.tf:781`, checkin margin 125min); a cancel storm leaves <2 qualifying runs → exit 2 NOT-YET, fail-safe |
| Probe asserts the three `test-webplat-mutations (*)` legs per run vs trusting the run-level conclusion | technical | Ruled by CTO agent, 2026-11-12: probe asserts the three `test-webplat-mutations (*)` jobs per sampled run via the `jobs` API — does not trust run-level conclusion - a future diff could remove a mut leg from the matrix AND `EXPECTED_LEGS` consistently, yielding a green run that never executed the battery; the jobs JSON is the convention's established "ran" evidence (`runbooks/followthrough-convention.md`); one bounded API call on ≤2 qualifying runs keeps the verdict self-contained and auditable |
| The deferred `--rows` row-split of `approval-guard1-mutation` folds into the classifier follow-up issue vs a second issue | technical | Ruled by CTO agent, 2026-11-11: confirm fold-in — binding carry of archived ruling "`--rows` deferred to the named follow-up" (decision-challenges 20261111-210708 row on whole-battery-per-leg); the classifier follow-up IS the named follow-up, so the lever lands in the same issue rather than a second tracker |
| Probe test suite shape (fake-`gh` fixture suite vs other harness) | taste | Convention applied, no fork: `ci-push-dedupe-soak-9512.test.sh` precedent pins the fake-`gh` fixture + injected-clock + exit-contract pattern for follow-through probes under `scripts/followthroughs/` |
| Brand-survival threshold `none` | taste | Ruled by CTO agent, 2026-11-11: confirm `none` — binding carry of the archived ruling on the same threshold question for this epic family: internal CI machinery only, worst case degraded internal signal, not user-visible behavior |
| Scope-check: `test-all.sh` `run_suite` registration and runbook Measured-history rows as `inferred` items | taste | Convention applied, no fork: `lint-orphan-test-suites.sh` reds CI on an unregistered `.test.sh` (enforcement contract), and `ci-test-scripts-sharding.md` "Measured history" is the repo's record home for measured rankings — both classified `inferred` with justification in the plan's Plan-Item Provenance table |
