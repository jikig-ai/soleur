# Tasks — fix: web-first-deploy probe reads aged job logs (UNKNOWN STEP) as zero-line

Plan: `knowledge-base/project/plans/2026-10-30-fix-web-first-deploy-step-attribution-plan.md`
Issue: #11600 (Closes) | Tracker: #11583 | Precedent: `git-data-boot-poll-8178.sh` (#8262)

## Phase 1 — Fixture RED (write failing cases first)

- [x] 1.1 In `scripts/followthroughs/web-first-deploy-10585.test.sh`, extend `job()` (line ~133) to emit `"started_at"`/`"completed_at"` on the trail step object (new optional arg; existing call sites default to a real timestamp so recovery-capable fixtures carry it; `-` when absent).
- [x] 1.2 Add UNKNOWN STEP fixture builders: `GH_LOG_BOM=$'\357\273\277'`; `ul()` (`printf '%s\tUNKNOWN STEP\t%s%s %s\n'` — the `git-data-boot-poll-8178.test.sh:142` idiom) + `usrc()` (ANSI-echo variant); `ulog()` document builder emitting the faithful shape — bare `Set up job` first section, BOM'd prelude section stamped before the trail step's `started_at`, BOM'd trail-step `##[group]Run` at `started_at`, payload lines, BOM'd next-step `##[group]Run` header bounding the region.
- [x] 1.3 Add failing cases per plan Test Scenarios: A (success UNKNOWN STEP → accounted exit 2), B (same + no marker, boot >2d → exit 5), C (emitted pointer + ANSI-echoed ready only → no obligation), D (region with zero trail lines, and no-header variant → exit 3), F (no `started_at` in jobs API → exit 3), G (failure conclusion + pointer+ready → obligation enrolls), supersession pair (aged UNKNOWN STEP + newer named boot → newest wins), last-section EOF-region must-PASS.
- [x] 1.4 Run `bash scripts/followthroughs/web-first-deploy-10585.test.sh` — new cases RED; pre-existing cases still green.
- [x] 1.5 Commit: `test(followthroughs): RED — UNKNOWN STEP fixtures for web-first-deploy-10585`

## Phase 2 — Probe recovery implementation

- [x] 2.1 Extend the jobs `--jq` (`web-first-deploy-10585.sh:239-240`) to a 4th TSV field, the trail step's `started_at` (`// "-"`); `read -r jid jcon jstep jstart`.
- [x] 2.2 After `log=` fetch: `log=${log//$'\r'/}; log=${log//$'\357\273\277'/}` (global forms, 8178 verbatim).
- [x] 2.3 Extract the emit-filter (ts strip + ESC drop + `ts\tcontent` emit) into one shared awk path consumed by both the named-step rows (`$3` of `index($2, step) == 1` lines) and recovered region lines.
- [x] 2.4 Recovery: when `trail` empty AND `jstart` matches `^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}`, run the 8178 region awk (`git-data-boot-poll-8178.sh:204-207` verbatim, `ps=${jstart:0:19}`); feed the region through the shared emit-filter.
- [x] 2.5 Keep the `jcon == "success" && -z "$trail"` tripwire, now evaluated post-recovery; keep `zero parseable` in the message, append the recovery cause.
- [x] 2.6 Update the header comment: Step-1 description + RESIDUALS (attribution expiry, `##[group]Run` title collision, `started_at`/header skew) and exit-semantics wording.
- [x] 2.7 Re-run the suite — all cases green incl. pre-existing 7b/7c; bump the anti-vacuity floor (`< 30`) to the new baseline.
- [x] 2.8 Commit: `fix(followthroughs): recover trail from UNKNOWN STEP job logs via started_at region slice (#11600)`

## Phase 3 — Docs + follow-up issue

- [x] 3.1 `knowledge-base/engineering/operations/runbooks/followthrough-convention.md`: sharp-edge note — gh drops step-name attribution ~2-3 wk post-completion; `--log` probes must anchor on `##[group]Run` regions keyed on the step's jobs-API `started_at` + the global BOM strip; cite this fix and #8262.
- [x] 3.2 File the follow-up issue: same `UNKNOWN STEP` exposure in `scripts/followthroughs/web-fresh-boot-zot-8651.sh` and `scripts/followthroughs/git-data-rehearsal-evidence.sh` (what/where/re-eval criteria; labels consistent with #11600 e.g. `domain/engineering`, `type/bug`, `priority/p3-low` — verify labels exist first).
- [x] 3.3 Commit docs: `docs(followthroughs): record gh step-attribution expiry countermeasure`

## Phase 4 — Verification + ship inputs

- [x] 4.1 `bash scripts/followthroughs/web-first-deploy-10585.test.sh` — 0 failures; every driven path exits in {5,2,3,78} (SEEN_RCS sweep).
- [x] 4.2 Run the mutation spot-checks from the plan's Guard Contract (BOM single-strip, dropped `ts >= ps` gate, recovery deleted) — each reddens.
- [x] 4.3 `python3 scripts/lint-guard-contract.py knowledge-base/project/plans/2026-10-30-fix-web-first-deploy-step-attribution-plan.md` clean; markdownlint clean on plan + tasks.
- [ ] 4.4 AC-7 post-merge (observational): first post-merge daily sweep on #11583 exits 2/5 — record the measured verdict in the PR/issue trail; not a PR-blocking gate.
- [x] 4.5 PR body reminder: `Closes #11600`; name the filed sibling-exposure issue.
