# Tasks: remove cron-gh-pages-cert-state and its Sentry monitor

Plan: `knowledge-base/project/plans/2026-09-30-chore-remove-obsolete-gh-pages-cert-state-cron-and-sentry-monitor-plan.md`
Two PRs (Sentry two-PR rule, #8630). This file covers PR A (this branch); PR B lives on tracker #9304.

## Phase 0: Preconditions (PR A)

- [ ] 0.1 `git grep -n "cron-gh-pages-cert-state\|cronGhPagesCertState\|CertState" -- ':!knowledge-base' ':!tests/scripts/fixtures'`; confirm the hit set equals the plan's Files lists.
- [ ] 0.2 `grep -n 'from "' apps/web-platform/server/inngest/functions/cron-gh-pages-cert-reissue.ts apps/web-platform/server/cert-reissue-marker.ts`; confirm no import of a deleted module.
- [ ] 0.3 Run the baseline set from `apps/web-platform` with `./node_modules/.bin/vitest run`: function-registry-count, execution-placement, routine-metadata-parity, cron-inngest-cron-watchdog, oneshot-4650-monitor-close, sentry-monitor-iac-parity, sentry-cron-monitor-routing-parity, cron-safe-commit-parity, cron-shared. Record green.
- [ ] 0.4 Note the soak probe's current `RETIRED_IDS` (`scripts/followthroughs/inngest-soak-6178.sh`) for the Phase 6 subtraction.

## Phase 1: Tests first (RED)

- [ ] 1.1 `function-registry-count.test.ts`: count 70 -> 69 with a changelog comment; add the TEMPORARY `scheduled-gh-pages-cert-state` entry to `NON_INNGEST_MONITORS` citing #9304.
- [ ] 1.2 `cron-inngest-cron-watchdog.test.ts`: repoint the "two regressed monitors" assertion and the `manualTriggerEventFor` case; substitute another live cron id (e.g. `cron-oauth-probe`) for the deleted id in the MISSING/streak fixtures.
- [ ] 1.3 `oneshot-4650-monitor-close.test.ts`: `TARGET_SLUGS` and the two partial-registry fixtures to two functions.
- [ ] 1.4 Run the Phase 0.3 set; `function-registry-count` (a) MUST be RED (70 entries vs 69). The lockstep guards (b)/(e), `execution-placement` Guard 1 and `routine-metadata-parity` stay green until one wiring row is removed alone; Phase 2 removes all together.

## Phase 2: Delete and unwire (GREEN)

- [ ] 2.1 Delete `apps/web-platform/server/inngest/functions/cron-gh-pages-cert-state.ts` and `apps/web-platform/test/server/inngest/cron-gh-pages-cert-state.test.ts`.
- [ ] 2.2 `route.ts`: remove the import and the `functions` array entry (69 left).
- [ ] 2.3 `cron-manifest.ts`, `execution-placement.ts`, `routine-metadata.ts`: remove the three rows.
- [ ] 2.4 `oneshot-4650-monitor-close.ts`: `TARGET_FN_IDS` to two entries and rewrite its comment.
- [ ] 2.5 Comment-only: `cron-supabase-disk-io.ts` and its test point at a surviving sibling.
- [ ] 2.6 Re-run the Phase 0.3 set: all green; `tsc --noEmit` from `apps/web-platform` clean.

## Phase 3: Sentry route-off

- [ ] 3.1 `cron-monitor-alerts.tf`: remove `sentry_cron_monitor.scheduled_gh_pages_cert_state.id` from `monitor_ids`; add `scheduled_gh_pages_cert_state = "disabled, producer deleted; monitor deleted in follow-up (#9304)"` to `cron_monitor_alert_unrouted`.
- [ ] 3.2 `cron-monitors.tf`: comment-only rewrite of the resource's block (producer gone, monitor stays one PR for the two-PR rule); every attribute unchanged.
- [ ] 3.3 `terraform fmt -check` and `terraform validate` in `apps/web-platform/infra/sentry` if the toolchain is present; never plan or apply locally.
- [ ] 3.4 Run `sentry-cron-monitor-routing-parity` and `sentry-monitor-iac-parity`.

## Phase 4: alert-reference.json

- [ ] 4.1 Push the branch; wait for the `plan_pr` alert-reference gate; download `sentry-alert-reference-expected-<run>`; commit it as `alert-reference.json`; confirm the diff removes exactly one detector id and the gate is green.

## Phase 5: Records

- [ ] 5.1 ADR-194: short dated addendum (via `soleur:architecture`): deleted early, monitor follows in PR B (#9304), #7799 conditions do not apply.
- [ ] 5.2 `model.c4`: rewrite the one `api -> cloudflare` clause naming the removed detector cron; run `bash scripts/regenerate-c4-model.sh`.
- [ ] 5.3 Runbook `gh-pages-cert-renewal.md`: drop the deleted path from `applies_to`; one line at the "manual-trigger-only" spot.
- [ ] 5.4 Run `bash plugins/soleur/test/c4-count-parity.test.sh`, `c4-code-syntax` and `c4-render` tests, `npx markdownlint-cli2` on touched markdown.

## Phase 6: Ship PR A

- [ ] 6.1 PR body first line states the production effect (deploy plus one in-place Sentry alert update, zero destroys); include `Ref #9304` and `Closes #7711` (comment on #7711 first); commit the plan, tasks and `decision-challenges.md`.
- [ ] 6.2 After merge (`soleur:postmerge`): `apply-sentry-infra.yml` green; wait for the release deploy; dispatch read-only `cutover-inngest.yml -f op=registry-probe` with a watch armed; `comm -23` the population file against the result minus the retired minter id; post the result as a comment on #9304.
- [ ] 6.3 Confirm the watchdog's next tick shows no defect for the manifest.

## Phase 7: PR B (tracker #9304, separate branch)

- [ ] 7.1 Delete the monitor and its comment block in `cron-monitors.tf`; delete the unrouted entry; remove the temporary `NON_INNGEST_MONITORS` entry.
- [ ] 7.2 Count ledgers: `infra/sentry/README.md` (two `60` -> 59), `scripts/sentry-monitors-audit.sh` addendum line, `model.c4` (`Of 59 cron monitors, 16 ... and 43 from webapp` plus the ungated `44 Inngest-substrate` phrase -> 43), regenerate `model.likec4.json`.
- [ ] 7.3 Conditional: `RETIRED_IDS` + a test row in `inngest-soak-6178.sh` / `.test.sh` if #9304's comment names a missing population id; mirror #9071's test row `C0e`; that suite runs longer than two minutes, so run it in the background; land before `SOAK_STALE` (2026-10-06).
- [ ] 7.4 Art. 30 register: append the dated supersession note under the 2026-05-19 sentence; run `bash scripts/lint-legal-registers.sh`.
- [ ] 7.5 The PR plan must show exactly 1 delete; commit BODY carries a line-anchored `[ack-destroy]`; PR body `Closes #9304`.
- [ ] 7.6 Post-merge: `apply-sentry-infra.yml` green; next `scheduled-terraform-drift.yml` sentry leg exits 0.
