# Tasks: #7884 health monitor keyword import + live Better Stack inventory reconcile

Plan: `knowledge-base/project/plans/2026-09-15-fix-health-monitor-supabase-keyword-import-plan.md`

## Phase 0: Preconditions

- [x] 0.0 Merge `origin/main` into the branch (PR #8215's post-mortem landed after branch point)
- [x] 0.1 Re-read live monitor 4226366 + monitor/heartbeat lists (READONLY token); stop the monitor half if gone or not `status`
- [x] 0.2 Keyword probe (merge gate), per the plan's credential rules: xtrace refusal, write token via `doppler secrets get` into a variable, `curl --disable --noproxy '*' --proto '=https' --max-redirs 0 -H @-`; checked orphan sweep of `soleur-probe-7884-*`; one `soleur-probe-7884-<run-id>` keyword monitor; `up` reading; PATCH to never-matching keyword; `down` reading; trap delete + 404; record in PR body; apply the decision rule
- [x] 0.3 Targeted read-only plan for `betteruptime_monitor.app_health` (dummy ssh key var, `-lockfile=readonly`); require `1 to import, 0 to add, 1 to change, 0 to destroy`, no `-/+`, limited diff
- [x] 0.4 ADR-222 ordinal probe across all `origin/*` refs (repeat before merge)

## Phase 1: Monitor import + keyword

- [x] 1.1 RED: `apps/web-platform/test/server/health-keyword-monitor-contract.test.ts` — Guard 1 rows 1-11, H1-H5, `EXPECTED_BRANCH` constant from 0.2, per-row rule ids, `loadInfraTf` (reworked at review: rows 1-21 + H1-H2, see test file)
- [x] 1.2 `variables.tf` `adopt_app_health_monitor`; tftest override `false`; gated `import {}` + `betteruptime_monitor.app_health` in `uptime-alerts.tf`
- [x] 1.3 `-target=betteruptime_monitor.app_health` in the per-merge apply job
- [x] 1.4 Rewrite `uptime-alerts.tf` quota header and #7884 bullet; repoint the apex "10 monitors" sentence
- [x] 1.5 GREEN: fmt, validate, `terraform test`, contract test, target-parity, canonicalizer + mutation, seo-config-rules test

## Phase 2: Reconcile

- [x] 2.1 RED: Guard 2 rows 1-19 + marker-key property + H1-H6 in `heartbeat-live-reconcile.test.ts`; update the "no logtail declared" `seen` list; DI seam for `reconcileMonitors`
- [x] 2.2 Lib: `resolveInfraVariables`, exact `for_each`/`count` resolution, discriminated violation union, `reconcileMonitors`, `findUnmanagedHeartbeats`, `null`/`""` keyword equality
- [x] 2.2.1 Script: monitors arm (always runs), numeric id + url validation, per-arm host/port/path pin, seen-URL set + 50-page cap, sanitizer additions (bidi/invisible, 200-char cap, `%22`), quoted-last vendor fields, `resource=` inserted before vendor text, INVENTORY marker, markers before code combine
- [x] 2.3 RED: `plugins/soleur/test/heartbeat-reconcile-issue-step.test.sh` (Guard 3 W1-W7, H1-H2; python `yaml.safe_load` + `gh` stub)
- [x] 2.3.1 Workflow (existing steps): `has_mismatch` output + gates (rc 2, or rc 1 with mismatches), fail-closed lookup, whole-token escalation key (keyless escalates), decode list, `infra-drift` label, untrusted-data framing + re-read-before-act remedy, subject precedence, random heredoc delimiter, failure-triggered email/Sentry; actionlint + `bash -n`
- [x] 2.4 Local read-only live run; paste output (no `${each.key}`, `matched=` has 4226366, INVENTORY, zero unmanaged)

## Phase 3: Records

- [x] 3.1 ADR-222 via `/soleur:architecture` (pager contract + declared-or-reported rule; H-F likely-abort + removal; residuals incl. 5xx/429 suspension; `adopting` on status branch)
- [x] 3.2 ADR-117 amendment (exact resolution, tf-var override names as a limit, `resource=` field, one-time re-escalation)
- [x] 3.3 ADR-204 Residual gap + Consequences
- [x] 3.4 ADR-149 INVENTORY pointer
- [x] 3.5 Runbook `app-database-readiness-alarm.md` (no SSH; service-role-key cause; H-F remedy; post-mortem link)
- [x] 3.6 C4 edges; `scripts/regenerate-c4-model.sh`; freshness + count-parity tests
- [x] 3.7 Prose sweep of heartbeats-only descriptions (ADR-141, sentry cron-monitors.tf, function-registry-count test)
- [x] 3.8 Post-mortem Action Items: update the #7884 row status

## Phase 4: Issue housekeeping

- [x] 4.1 SKIPPED — paused vendor alert already modeled in fixtures; see session-state.md (File the undeclared Logs alert issue (`Output utilization high`))
- [x] 4.2 Close #8140 as duplicate of #6645 with comments on both
- [x] 4.3 N/A keyword branch (Status branch only: keyword follow-up issue (`Phase 4: Validate + Scale`, `priority/p1-high`))
- [x] 4.4 CONVERTED to postmerge follow-up PR (filing gate: 32 lines / 3 files inside inline threshold) (File the import-block removal follow-up (`priority/p2-medium`, `Post-MVP / Later`, precondition AC17))

## Phase 5: Ship-time checks

- [ ] 5.1 PR body: `Ref #7884`; Phase 0.2/0.3/2.4 outputs; decision challenges rendered
- [ ] 5.2 Post-merge: AC17 apply + read-back (≥360 s, `last_checked_at`), AC18 reconcile run, AC19 comment on #7884 (do not close)
- [ ] 5.3 Post-AC17: open the import-block removal PR (delete the `app_health` `import {}` block, `adopt_app_health_monitor` and the tftest override) with `Closes #7884` in the body; #7884 closes when it merges
