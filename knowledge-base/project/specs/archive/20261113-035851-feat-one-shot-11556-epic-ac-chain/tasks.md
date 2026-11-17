---
branch: feat-one-shot-11556-epic-ac-chain
issue: 11556
plan: knowledge-base/project/plans/2026-11-12-ci-epic-11556-ac-chain-followthrough-plan.md
created: 2026-11-12
---

# Tasks — ci: epic #11556 remaining AC chain follow-through

Plan: `knowledge-base/project/plans/2026-11-12-ci-epic-11556-ac-chain-followthrough-plan.md`

## Phase 1 — Scheduled-run confirmation probe + tracker (AC1, AC2)

- [x] 1.1 Write `scripts/followthroughs/main-health-monitor-mutations-12626.sh`
  - Header: property, CREDENTIAL POSTURE (`secrets=GH_TOKEN`), exit vocabulary (0 PASS / 1 FAIL / 2 NOT YET / 3 CANNOT ESTABLISH / 78 xtrace refusal), RETIREMENT list.
  - Read: `gh api "repos/{owner}/{repo}/actions/workflows/main-health-monitor.yml/runs?event=workflow_dispatch&per_page=30"` (GET — query embedded in URL, never `-f` flags which flip to POST).
  - Filter: `actor.login == "soleur-ai[bot]"`, `head_branch == "main"`, `created_at >= "2026-11-12T19:46:34Z"`, `conclusion` in `{success, failure}` (exclude `cancelled`/in-progress).
  - Per qualifying run: `gh api "repos/{owner}/{repo}/actions/runs/<id>/jobs?per_page=100"`; assert ≥3 jobs named `test-webplat-mutations (*)` all `conclusion == "success"`.
  - Exit: 0 when ≥2 qualifying runs all green; 1 on any failing/leg-incomplete run (print run id + leg); 2 while <2 qualifying runs; 3 on gh/parse failure.
- [x] 1.2 Write `scripts/followthroughs/main-health-monitor-mutations-12626.test.sh` — fake-`gh` fixture pattern per `ci-push-dedupe-soak-9512.test.sh`; drive every Guard-Contract mutation-matrix row (plan §Guard Contract, rows 1–8).
- [x] 1.3 Register in `scripts/test-all.sh`: `run_suite "scripts/followthroughs/main-health-monitor-mutations-12626" bash scripts/followthroughs/main-health-monitor-mutations-12626.test.sh` beside the sibling probe registrations (~lines 7171–7220).
- [x] 1.4 `python3 scripts/regenerate-shard-manifest.py --incremental --write` — place the new suite label + floor row in `scripts/suite-shard-legs.tsv` / `scripts/suite-durations.tsv`.
- [x] 1.5 Copy the probe into the MAIN checkout's `scripts/followthroughs/` (untracked — the directive gate resolves under `HOOK_CWD`), then `gh issue create` the tracker: title `ci: post-merge scheduled-run confirmation for test-webplat-mutations legs (#12626)`, label `follow-through`, body carrying the unfenced column-0 directive `<!-- soleur:followthrough script=scripts/followthroughs/main-health-monitor-mutations-12626.sh earliest=<filing ISO-8601> secrets=GH_TOKEN -->`.
- [x] 1.6 Record the tracker number; verify the directive-gate accepted it (no hook refusal in the `gh issue create` output).

## Phase 2 — Applicability-classifier follow-up issue (AC3)

- [x] 2.1 Write `knowledge-base/project/specs/feat-one-shot-11556-epic-ac-chain/classifier-issue-body.md` per the plan's Context sketch (in-job detect step modeled on `ci.yml:2137`; base-sourced classifier; `applicable != 'false'` step guard; fail-closed enumeration; v1 markdown-only allowlist; mutation-subject census gate for widening; pinned `if:`/`needs:` constraint; no aggregator change; `--rows` `approval-guard1-mutation` split as adjacent deferred lever; refs #11556, #12626, #9729).
- [x] 2.2 `gh issue create` with labels `type/chore`, `domain/engineering`, `meta/machinery`, `priority/p3-low` (verify each exists via `gh label list` first — substitute with a note if absent).
- [x] 2.3 Record the issue number; link it in tasks/plan close-out notes.

## Phase 3 — Lever-A re-rank + re-price (AC4, ask 7)

- [x] 3.1 Enumerate the most recent green `merge_group` `ci.yml` runs (`gh run list --workflow ci.yml --event merge_group --status success`); prefer post-`34634d7431` runs; take ≥5.
- [x] 3.2 Per run: `gh run download <id> -p 'suite-timings-scripts-*' -D <dir>` (and `-p 'suite-timings-scripts-heavy-*'`).
- [x] 3.3 `python3 scripts/regenerate-shard-manifest.py --timings-dir <d1> --timings-dir <d2> … --drift-report` (light); repeat `--group heavy`.
- [x] 3.4 If drift is material: re-run with `--write` to re-price `scripts/suite-shard-legs{,-heavy}.tsv` + `scripts/suite-durations{,-heavy}.tsv`.
- [x] 3.5 Reconcile `scripts/followthroughs/ci-push-dedupe-soak-9512` `185400` ms vs artifact-measured (`80676` ms observed) — regenerated table is authoritative; record both.
- [x] 3.6 Emit the fresh top-15 suite-time ranking (per-label median ms desc) + run ids into `knowledge-base/engineering/operations/runbooks/ci-test-scripts-sharding.md` "Measured history".

## Phase 4 — p90 + Lever-F measurement (AC5, AC6)

- [x] 4.1 `bash scripts/watch-wallclock-p90-11774.sh --dry-run` (GH_TOKEN required); capture the `test` rows for `pull_request` + `merge_group` and any breach/untracked findings.
- [x] 4.2 Record the measurement in the runbook "Measured history" (vs the 3246 s 2026-11-02 baseline and the 2026-11-06 report's 3624/3205 s).
- [x] 4.3 Comment on #11556: AC-chain status — scheduled-run enrollment, classifier issue #N, Lever-A re-rank, `test` p90 vs goals 1200 s/900 s, honest verdict (expected still >20 min; binding constraint = `test-scripts` leg skew, 2483 s on `43286327218`), 14-day criterion still gated.
- [x] 4.4 Note on #11563 (Lever F): measured leg figures — `approval-guard1-mutation` 1158–1493 s vs the ~30-min internal gate; `test` aggregate vs gate — raw numbers stated, gate call left to that issue's owner.

## Phase 5 — Tracker hygiene + close-out (AC7, AC8)

- [x] 5.1 `gh issue view` #12647, #12651 (verify OPEN, no action), #12269 (verify directive comment `earliest=2026-11-30T23:01:58Z` intact — do not touch), #12455/#12618 (confirm CLOSED; record the 18:00Z `43275349911` failure as pre-merge).
- [x] 5.2 `git status` — verify only the prescribed file set; commit all artifacts.

## Close-out (2026-11-12)

- Tracker: **#12716** (scheduled-run confirmation, `secrets=GH_TOKEN`); probe staged in bare-root overlay + `[main]` worktree for the HOOK_CWD gate.
- Classifier issue: **#12717** (in-job classifier + `approval-guard1 --rows` re-price).
- Re-price: 5 green merge_group runs (43308874521, 43286327218, 43278615612, 43185108804, 43138951876; 43275115845/43272862450 artifacts expired); `--write --allow-growth` (32 violations acked): 42 rows moved, +51.5% weight, legs 1761–1817s (spread 89s); `ci-push-dedupe-soak-9512` 185400→**81308**ms (median of 63170/69116/81308/81427/97965); heavy group zero drift, no write.
- p90 (2026-11-12T22:10Z, rolling-30): `test` 4343s PR / 2937s MQ vs goals 1200/900 — PR p90 breaches bound; sample still pre-#12654-dominated.
- #11556 commented (6837335240); 14-day criterion explicitly unverified.
- Re-price fallout (116ac789e2): `image-cve-public-claim-guard` demoted off ALWAYS_ON_SUITES (11,494 ms measured > 10 s cap; edge set = SURFACES verbatim); `test-all-affected-c` exempted at 794,024 ms over the 600 s corpus cap (#11679 tracker). Guards green: fast-tier-budget 9/9, corpus-weight-budget 14/14, always-on-ledger 14/14.
