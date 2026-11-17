---
title: "fix(ci): #9323 soak probe escape arm pends forever on merge-queue merges — fall back to the merge_group run on the merge commit"
type: fix
date: 2026-11-09
slug: fix-9323-probe-merge-queue-pending
branch: feat-one-shot-12478-merge-group-escape-evidence
issue: 12478
closes: 12478
priority: high
domain: engineering
lane: cross-domain
brand_survival_threshold: none
requires_cpo_signoff: false
---

# fix(ci): #9323 soak probe escape arm pends forever on merge-queue merges — fall back to the merge_group run on the merge commit

## Overview

`scripts/followthroughs/pr-battery-gate-saving-9323.sh` (the ADR-262 soak probe for #9323) cannot converge: escape arm (b) reads the `ci.yml` `push` run on each qualifying PR's merge commit, but PRs merged via the **merge queue** produce `merge_group` runs on that commit and — measured on all three current pendings — zero `push` runs, so they sit in `pending` permanently and the sweeper leaves #9323 open forever (`pending > 0` → `NOT YET`, exit 2). The fix falls back to the `merge_group` CI run on the same commit and applies the **same** gated `test-scripts*` jobs classifier — a red `merge_group` run on a gated leg is equivalent escape evidence, because the queue ran the full battery on the exact commit that landed (ADR-276 already names `merge_group` "the full-battery authority"). This is the merged-via-queue sibling of #12360's `open`/`dropped` pending re-scope.

Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed). No `spec.md` exists for this branch; the value is the fail-closed default, not a carried-forward one.

## Problem Statement / Motivation

Issue #12478, measured 2026-11-09 and re-verified live at plan time:

| PR | Merge commit | `event=push&head_sha=` runs | `event=merge_group&head_sha=` runs |
|---|---|---|---|
| #12445 | `c0612a80f5117b0baaec76fd29ab6c3d68debc27` | 0 | `42532979741` completed/**failure** — only `lint-bot-statuses` failed (verified via `runs/42532979741/jobs`: non-gated job, would classify `unrelated`) |
| #12376 | `161b8fb0fc062bb08bc11d3d9a3e44b641b55fad` | 0 | `42493927928` completed/success |
| #12330 | `089b193122af1af34c0864d7ba3a4a7a5e5b2d14` | 0 | `42472568357` completed/success |

The probe's NOT YET line is `3 qualifying PR(s) have no completed push run on their merge commit`. None ever will: a queue-merged PR's merge commit carries `merge_group` runs, not `push` runs attributable to it. The realized-saving arm is healthy (`mean_runner_min=298.2` vs `required_saving=20`, `evidenced_runs=21/40`); only the escape arm's evidence lookup is pointed at an event that never fires for this merge class. Same absorbing-state class as the open-PR pending fixed by #12360 (`057f1e5acc`) — this is the merged-via-queue variant.

## Proposed Solution

**Arm A — merge_group fallback (assumed pending CTO confirm; see `decision-challenges.md`).** In `_pbg_w_esc`, when the `push`-run read for a merged PR's `merge_commit_sha` yields no conclusive verdict — the runs list is empty, or the newest run is not yet complete / inconclusive — issue one additional read against `runs?event=merge_group&head_sha=$sha` and apply the **identical** conclusion→bucket classification: `success` → `ok`; `failure|timed_out|startup_failure|action_required` → the same jobs-read classifier (escape iff a failed job matches the gated `test-scripts*` family, `unrelated` when every failure is outside it, `pending` when the jobs read cannot be established); anything else → `pending`. The classification logic is extracted/shared so there is one classifier, not a second enumeration that can drift — the same `test-scripts*` prefix the examine arm derives at `scripts/followthroughs/pr-battery-gate-saving-9323.sh:283`.

The fork (Arm A fallback vs Arm B `queued`/`no-push-run` bucket like `unrelated`) is a technical fork recorded in `decision-challenges.md` as `pending - assumed:` — no subagent spawn was available in the planning seat (sequential-fallback, disclosed). The assumed ruling is **Arm A**: Arm B drops real escape evidence the `merge_group` run already provides (the issue's own assessment: "weaker, it drops real escape evidence"), and ADR-276's title already declares `merge_group` the full-battery authority. If the parent's batched technical-ruling gate rules Arm B instead, the diff re-scopes to the smaller `queued` bucket — Phase 1 step 1 carries the re-verify instruction.

## Technical Considerations

- **API budget.** `need_min` (:406) models 2 reads per qualifying run in the escape check (`pulls/N` meta + push-run list) plus one `MAX_RUNS` of Stage-A listing prefetch = `3 * MAX_RUNS`. The mg read fires only on the inconclusive-push arm — worst case every qualifying PR is queue-merged → +1 read/PR. Bump the model to `4 * MAX_RUNS` and update the comment; the red-mg jobs read rides the same "rare, only on red runs" carve-out the red-push jobs read already uses.
- **`head_sha` needs the full 40-char SHA.** Measured at plan time: `event=merge_group&head_sha=c0612a80f5` (10-char prefix) returns an empty list while the full SHA returns the run. `merge_commit_sha` from `pulls/N` is already full-length — safe by construction, but the fixture writer must not truncate it either.
- **The mg query must be ci.yml-scoped and queue-scoped.** `actions/workflows/ci.yml/runs?event=merge_group&head_sha=<sha>` — the same repo idiom as `ci.yml`'s push-dedupe proof (:221-223) and `ci-draft-light-soak-9728.sh:262`. Select `.workflow_runs[0]` (newest), mirroring the push arm exactly; a still-running or cancelled run concludes `pending` (absence of conclusive evidence is NOT YET, never "no escape"). Multiple mg runs can exist on one landed sha (retried groups) — newest wins, same as the push arm.
- **Only `ci.yml` is evidence.** The unfiltered `actions/runs?head_sha=` list on `c0612a80f5` shows SEVEN workflows' merge_group runs (CLA synthetics, sentry infra, tenant integration, secret-scan, vendor-pin-verify, PR guards) — the workflow-scoped query already isolates ci.yml; do not widen it.
- **The `via_mg` note line.** `ok` rows print no detail; to keep queue merges visible (the useful instinct inside option B) a `via_mg` counter feeds a note line — `note: N qualifying PR(s) verified via merge_group run(s) on their merge commit (queue merges carry no push run)` — reported, never counted in `escapes`/`pending`. Zero extra reads: the arm already knows which event produced the `ok`.
- **Worker contract unchanged.** The mg read goes through the same `api()` deadline primitive inside the same worker; rows still flow only through `_w_row`; `cut`/`fail` semantics and the `pending`-never-`ok` rule are unchanged.
- **Header/docs honesty.** The header's arm-(b) description (:9-13), the `_pbg_w_esc` doc comment (:319-326), the `need_min` comment (:401-406), and the pending NOT YET line (:602) must all name both events — a comment claiming "push run" alone would misdescribe the evidence path post-fix.
- **Bash strict-mode.** New reads follow the established `rc=0; out="$(api ...)" || rc=$?; (( rc == 46 )) && cut; (( rc != 0 )) || [ -z "$out" ] && fail` shape — never bare `$( )` under `set -uo pipefail`.
- **`Ref`/`Closes` split.** `Closes #12478` (this defect is fixed by the diff); `Ref #9323` (stays open until the soak PASSES on its own terms); `Ref #12360` (the sibling re-scope).

## Research Insights

**Relevant file paths**

- `scripts/followthroughs/pr-battery-gate-saving-9323.sh` — `_pbg_w_esc` escape worker :319-372 (meta read :329, open/dropped buckets :333-334, push-run read :336, conclusion case :340-371, unrelated/pending rows :346-367); verdict aggregation + note lines :578-602; `test-scripts*` gated prefix :283; `need_min` API model :397-408; header exit vocabulary :67-84.
- `scripts/followthroughs/pr-battery-gate-saving-9323.test.sh` — registered suite (`scripts/test-all.sh:7094`, shard leg `suite-shard-legs.tsv:443`, duration `suite-durations.tsv:442`); fake `gh` endpoint case :53 (`runs?event=push*` → `push-<sha>.json`); `build_fx` writes per-PR push fixtures :109; `requests.log` read-contract assertions (open PR issues no push read, green run issues no jobs read).
- `.github/workflows/ci.yml` — `merge_group:` trigger :33; push-dedupe identical-SHA mg proof jq :221-223 (the established `event=merge_group&head_sha=` + `gh-readonly-queue/main/` + same-repo filter idiom).
- `scripts/followthroughs/ci-draft-light-soak-9728.sh:262-264` — sibling soak probe already issuing the `event=merge_group` runs query through the same `api()` primitive.
- `scripts/followthroughs/zot-mirror-connector-6416.sh:95-107` — `event=push` pin is load-bearing there (push-arm vs workflow_run-arm disambiguation, #5806/ADR-217): a DIFFERENT surface, not the same defect — it scans `branch=main` runs, which still exist.
- `.github/workflows/web-platform-release.yml:540` — `resolve-target`'s `?event=push&head_sha=` pin, same deliberate-arm-disambiguation class; unaffected (main still receives push runs: latest `42605214262` on `5990a567b3aa` 2026-11-09T10:58Z).
- ADR-262 (`knowledge-base/engineering/architecture/decisions/ADR-262-pr-ci-path-gates-the-self-test-mutation-batteries.md`) — R1 escape definition :86-95; closing pointer :142 records ADR-270's merge-queue enforcement and ADR-276's "merge_group is the full-battery authority" reversal.
- Issue #9323 — the `<!-- soleur:followthrough script=… earliest=2026-10-09T00:00:00Z secrets=GH_TOKEN -->` directive (:63-67) — unchanged by this fix.

**Premise Validation (Phase 0.6).** Checked and held: #12478 OPEN (state verified); the three cited merge commits re-verified live — `event=push&head_sha=<full-sha>` = 0 runs on all three AND `event=merge_group&head_sha=<full-sha>` returns the CI run (`42532979741` failure / `42493927928` success / `42472568357` success); #12445's failed mg run's jobs = `lint-bot-statuses` only (non-gated — the `unrelated` bucket applies, matching the issue's read); #12360 CLOSED (precedent shipped, `open`/`dropped` buckets live in `_pbg_w_esc`); #9323 OPEN with the directive intact; script + `.test.sh` + suite registration all present; ADR-262 present. One correction vs the issue's framing, verified not refuting: push runs on main DO still exist for other commits (e.g. `42605214262`) — the gap is specifically that a queue-merged PR's `merge_commit_sha` carries `merge_group` runs, and `push` runs that exist on main SHAs don't cover every landed commit. Collision precheck: PR #12483 is THIS branch's own auto-created draft (self-hit); live `test-all.sh` pids belong to sibling worktree `feat-one-shot-9729-s4-evidence-rerun` (foreign, informational — different issue, different files, no overlap).

**Property List (Phase 0.6b).** (P1) the probe converges for merge-queue-merged qualifying PRs — `pending` drains when conclusive CI evidence exists on the merge commit; (P2) escape evidence is preserved — a red gated `test-scripts*` leg on the merge commit still FAILs the soak regardless of which event carried it; (P3) the gated-family check stays single-sourced — no second job-name enumeration that can drift; (P4) API-budget honesty — `need_min` models the added read's worst case; (P5) zero extra reads on arms that already conclude (conclusive push run, `open`, `dropped`) — the mg read fires only on the inconclusive arm.

**Cut List (Phase 0.6b).** Arm B (`queued`/`no-push-run` bucket reported like `unrelated`) — covers P1 but abandons P2: a queue-merged PR whose mg run reds a gated leg would be reported as "queued", losing the escape the evidence already contains. Cut pending the CTO confirm (assumed ruling A; the diff implements A). No new machinery is proposed anywhere: no new env knobs, no new probe file, no sweeper contract change, no tracker-directive change.

**Institutional learnings applied**

- `knowledge-base/project/specs/archive/20261108-160216-feat-one-shot-12360-ci-lever-threads/decision-challenges.md` — the `| Item | Class | Ruling |` + `pending - assumed:` convention this branch's decision-challenges.md mirrors; the `open`/`dropped` bucket precedent this defect class follows.
- `knowledge-base/project/learnings/workflow-patterns/2026-11-08-parallelizing-a-serial-gate-changes-its-resource-bound-not-just-its-speed.md` — every new read rides `api()`'s deadline contract inside the same worker; never a new fetch primitive.
- The 2026-11-08 classifier ruling (PR #12439, `a2fe028227`) — red-run escape iff ≥1 failed job is a gated `test-scripts*` leg; the same classifier, event-agnostic, is what the mg arm must reuse rather than re-enumerate.
- Guard-vacuity corpus (`2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md`) — the mutation matrix carries must-RED rows in both directions (red-gated mg = escape AND red-unrelated mg = not escape), a second-member row, a dispatch row (no mg read on a conclusive push arm), and must-PASS rows.
- `hr-no-dashboard-eyeball-pull-data-yourself` — every run/sha/jobs claim in this plan comes from `gh api` output quoted above, never console eyeballs or memory.

**External research:** skipped — repo-internal CI machinery with two in-repo precedents for the exact query (push-dedupe, ci-draft-light-soak). The GitHub API behaviour that matters (full-sha `head_sha`, `merge_group` event filter, empty-list semantics) was verified empirically at plan time, which is authoritative over docs.

**Functional overlap check (1.5b, sequential).** No new capability invented: the mg runs query already exists in-repo (`ci.yml:221-223`, `ci-draft-light-soak-9728.sh:262`); the change is a fallback inside the existing worker. Sibling consumers of `event=push&head_sha=` were audited — `zot-mirror` and `web-platform-release.yml resolve-target` are different surfaces (deliberate arm disambiguation on `branch=main`/`workflow_run`, where push runs still exist), not the same defect.

**Research Reconciliation — Spec vs. Codebase.** No `spec.md` exists for this branch. One issue-framing nuance corrected against live API reads (push runs on main still exist — see Premise Validation); no spec fiction to inherit.

## Implementation Phases

### Phase 1 — Probe: merge_group fallback in `_pbg_w_esc`

1. **Ruling re-verify (one check, cheap).** `decision-challenges.md` records `pending - assumed: Arm A`. If the parent's batched technical-ruling gate already re-ruled, read the record: Arm A → proceed; Arm B → re-scope to the `queued`/`no-push-run` bucket (add the bucket row + counter + note, skip the classifier path — a strictly smaller diff in the same worker); anything else → implement the record.
2. **Shared classifier.** Extract the conclusion→bucket logic currently inlined in the `failure|timed_out|startup_failure|action_required` case arm (jobs read + gated `test-scripts*` classification + `unrelated`/`pending` rows) so BOTH the push path and the mg path call the ONE classifier — parameterize the event name into the row detail (`push` / `merge_group`) so note lines name the evidence source. No second `test-scripts` enumeration.
3. **Fallback arm.** In the catch-all arm (currently `*) _w_row "$rf" "pending"` at :370), first issue `api "repos/$REPO/actions/workflows/ci.yml/runs?event=merge_group&head_sha=$sha" --jq '"\(.workflow_runs[0].id // "") \(.workflow_runs[0].conclusion // "")"'` through the same `api()` contract with `cut`/`fail` rows mirroring the push read; then feed `rid`/`concl` through the shared classifier. Empty list or non-conclusive conclusion → `pending` (unchanged semantics: absence of conclusive evidence is NOT YET).
4. **Counters + notes.** `via_mg` count for `ok` rows sourced from merge_group; note line beside the existing `dropped`/`open`/`unrelated` notes (:598-600); `unrelated` note wording event-agnostic (or parameterized `push`/`merge_group`). Pending NOT YET line updated to name both events (e.g. `no completed push or merge_group run on their merge commit`).
5. **`need_min` bump.** `3 * MAX_RUNS` → `4 * MAX_RUNS` (:406) + comment update (pull + push + mg + prefetch = 4 per qualifying run worst case; mg jobs read rides the same red-only rare carve-out).
6. **Header + doc comments.** Arm-(b) description (:9-13), `_pbg_w_esc` doc comment (:319-326), and the qualifying-PR-state comment (:567-577) updated to name merge_group; RETIREMENT block (:82-84) swept — no instruction falsified.
7. **Suite.** `bash scripts/followthroughs/pr-battery-gate-saving-9323.test.sh` exits 0 with the new fixture cases below.
8. **Optional live re-verdict** (only if GH_TOKEN is present and time allows): `PBG_UNBOUNDED=1 bash scripts/followthroughs/pr-battery-gate-saving-9323.sh` — whatever it computes is reported, not edited. Do NOT post to #9323 (that verdict is the sweeper's next-run business; a stale FAIL comment may precede it and self-clears).

### Phase 2 — Fixture coverage (`.test.sh`)

1. Fake `gh` route: `repos/*/actions/workflows/ci.yml/runs?event=merge_group*head_sha=*` → `mg-<sha>.json` (add to the endpoint `case`; absent file = read failure, mirroring `push-` semantics).
2. `build_fx` unchanged (writes conclusive push fixtures); per-case overrides write `{"workflow_runs":[]}` push fixtures + `mg-<sha>.json` (mirroring the `b6`/`d3` override idiom).
3. Cases (the Guard Contract matrix rows): absent-push + green-mg → `ok`/PASS (the #12376 shape — was pending); absent-push + red-mg gated failure → `escape`/FAIL; absent-push + red-mg non-gated-only → `unrelated`/not-escape (the #12445 shape); absent-push + absent-mg → still `pending`/NOT YET; absent-push + red-mg + jobs-read-fail → `pending`; absent-push + incomplete-mg (`in_progress`/cancelled) → `pending`; second-member — two queue-merged PRs, first mg-green second mg-red-gated → escape still fires on the second.
4. Read-contract assertions via `requests.log`: conclusive (green or red) push arm issues NO `event=merge_group` read; an open PR issues neither push nor mg read; an absent push arm issues exactly one mg read per merged pending PR.
5. `via_mg` note-line assertion (count + wording).

### Phase 3 — Ship

1. `knowledge-base/project/specs/feat-one-shot-12478-merge-group-escape-evidence/{decision-challenges.md,tasks.md}` committed.
2. PR body: `Closes #12478`, `Ref #9323`, `Ref #12360` — never `Closes`/`Fixes`/`Resolves` for the trackers.

## Files to Edit

- `scripts/followthroughs/pr-battery-gate-saving-9323.sh` — `_pbg_w_esc` merge_group fallback + shared classifier + `via_mg` counter/note + `need_min` model + header/doc comments.
- `scripts/followthroughs/pr-battery-gate-saving-9323.test.sh` — fake-gh `merge_group` route + the matrix-row fixtures + read-contract assertions.

## Files to Create

- `knowledge-base/project/specs/feat-one-shot-12478-merge-group-escape-evidence/decision-challenges.md`
- `knowledge-base/project/specs/feat-one-shot-12478-merge-group-escape-evidence/tasks.md`

## User-Brand Impact

- **If this lands broken, the user experiences:** a wrong verdict on a public tracker — either the soak still cannot conclude (harmless but unresolved) or, worse, a false `ok`/`unrelated` classification lets a real gated-battery escape pass uncounted, weakening the ADR-262 evidence base that future CI-cost decisions rest on; all of it surfaces as GitHub issue comments on already-public engineering issues.
- **If this leaks, the user's [data / workflow / money] is exposed via:** no user data in scope — the probe reads public Actions run/jobs metadata via `GH_TOKEN` and writes only issue comments through the existing sweeper; the reachable user-visible surface is the `publicReader`-modeled issue-comment channel.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** blast radius is CI-verdict comments correctable by a follow-up comment; no user data, no production serving surface, no money path — the failure mode is a misreported soak, not a breach.

*Scope-out override:* `threshold: none, reason: every touched path is repo-internal CI measurement machinery (scripts/followthroughs soak probe + its test); the only externally visible artifact is issue comments on already-public engineering issues`.

## Observability

(The Phase 2.9 detection list does not reach repo-root `scripts/`; included anyway because the deliverable IS an observability probe — the escape arm is the measurement — and its own liveness is worth declaring, mirroring the sibling plan's convention.)

```yaml
liveness_signal:
  what: scheduled-followthrough-sweeper runs pr-battery-gate-saving-9323.sh and posts its verdict line to #9323
  cadence: sweeper schedule (per-issue earliest= directive; probe wall-capped at 300 s under the sweeper)
  alert_target: issue #9323 comments (FAIL posts verbatim); main-side red is separately paged by notify-main-failure
  configured_in: .github/workflows/scheduled-followthrough-sweeper.yml + the <!-- soleur:followthrough script=… --> directive on issue #9323

error_reporting:
  destination: probe stdout captured by the sweeper → posted to the tracker issue; local runs post via operator gh
  fail_loud: exit 1 FAIL verdict line; exit 3 CANNOT ESTABLISH (retried by the sweeper); exit 2 NOT YET

failure_modes:
  - mode: merge-queue-merged PR pends forever (the defect this fixes)
    detection: NOT YET line "no completed push run on their merge commit" persists across sweeps while mg runs exist — visible in the verdict comment itself
    alert_route: #9323 comment via the sweeper (this plan is the fix)
  - mode: mg runs query API failure or malformed body
    detection: `fail`/`cut` worker rows → CANNOT ESTABLISH (exit 3) or budget NOT YET — never a silent `ok`
    alert_route: #9323 comment via the sweeper's next sweep
  - mode: red mg run's jobs read cannot be established
    detection: `pending` bucket with the jobs-read detail — reported, never folded to ok
    alert_route: #9323 comment via the sweeper's next sweep

logs:
  where: sweeper run logs (GH Actions) + #9323 comment trail + the probe's own note lines (dropped/open/unrelated/via_mg counters)
  retention: GH Actions retention for logs; issue comments are permanent

discoverability_test:
  command: bash scripts/followthroughs/pr-battery-gate-saving-9323.sh
  expected_output: CANNOT ESTABLISH
```

## Guard Contract

### Guard 1 — PBG escape arm treats a completed merge_group run on the merge commit as equivalent evidence to a completed push run

**Property.** A merged qualifying PR whose `merge_commit_sha` carries no completed `push` run is classified by the `merge_group` ci.yml run on that commit with the identical conclusion→bucket mapping — a red run escapes iff ≥1 failed job is in the gated `test-scripts*` family — and an arm with no conclusive run of either event stays `pending`, never `ok`.

**Assembly.** Every code path that turns a merge-commit CI read into an escape verdict: `_pbg_w_esc` in `scripts/followthroughs/pr-battery-gate-saving-9323.sh` is the sole producer of `escape`/`ok`/`unrelated`/`pending` row prefixes — the conclusion `case` at :340-371 is the one chokepoint every merged PR's verdict flows through — and the parent's aggregation at :582-596 is the only consumer. The mg read lands inside the same worker's catch-all arm (a sibling-site check would leave the chokepoint's inconclusive branch unguarded); the gated-family set stays the single `test-scripts*` prefix the examine arm derives at :283 — shared, not re-enumerated.

**Mutation matrix:**

| # | Mutation (fixture or edit) | Expected |
|---|---|---|
| 1 | Absent push run + mg run red on `test-scripts (x/7)` | `escape` row; `escapes=1` — the fallback must fire (must-RED: without it the fixture reads NOT YET forever, the shipped defect) |
| 2 | Absent push run + mg run red on non-gated jobs only (`lint-bot-statuses`) | `unrelated` row; `escapes=0` — the same classifier, event-agnostic (the #12445 shape) |
| 3 | Absent push run + TWO merged PRs — first mg-green, second mg-red-gated | escape fires on the SECOND member — a check that concludes on the first compliant member is the defect itself |
| 4 | Guard's own dispatch: conclusive push run present (green or red) | requests.log shows NO `event=merge_group` read — the fallback must not fire on an already-conclusive arm (vacuous-dispatch row: a fallback that always reads doubles the escape-arm API cost) |
| 5 | Absent push run + mg runs list empty / run `in_progress` / cancelled | `pending` — no conclusive evidence of either event is NOT YET, never `ok` (anti-vacuity: the fallback cannot conclude "no escape" on no evidence) |
| 6 | Absent push run + red mg run whose `jobs` read fails/empty | `pending` — mirrors the red-push jobs-read rule (:349); unreadable evidence is never `ok` |
| 7 | Harness row: open qualifying PR beside a queue-merged pending one | requests.log shows NO push read AND NO mg read for the open PR; the merged one still pends/NOT YETs — the `open` bucket's zero-extra-reads contract survives the new arm |
| 8 | Must-PASS (non-canonical): absent push + mg `success` | `ok` + `via_mg` counted on the note line — proves the fallback admits non-canonical green evidence rather than rejecting everything |

**Anchor.** The fixtures pin the run lists, conclusions and job-name sets; weakening the property requires editing both `pr-battery-gate-saving-9323.sh` and its `.test.sh` in the same diff — no stored outside value is consulted, the suite registration (`test-all.sh:7094`) runs the check on every battery, and the `requests.log` assertions pin the read contract the API budget is modeled on.

## Architecture Decision (ADR/C4)

### ADR

- **No new ADR and no amendment required.** The architectural ruling this change implements is already recorded: ADR-276's title and ADR-262's closing pointer (:142) both name `merge_group` the full-battery authority under the ADR-270 merge-queue enforcement. This plan aligns the probe's evidence lookup with the recorded architecture — a bug fix on an existing surface, not a decision change. ADR-262 R1's escape definition is unchanged (a gated-battery break surfacing on the landed commit); the probe now looks where the authority actually is for queue merges.
- If the parent's batched ruling gate picks **Arm B** instead, no ADR edit either — the `queued` bucket is a reporting-shape choice inside the probe, not a recorded-architecture divergence.

### C4 views

**No C4 impact**, established by reading all three model files (`model.c4`, `views.c4`, `spec.c4`) and enumerating this plan's external surface: (a) external human actors — none new (verdict comments reach the already-modeled `publicReader` publication surface via the existing sweeper/`founder -> github` filing edges); (b) external systems/vendors — none new (the GitHub Actions reads go through the existing `github` system element; workflow internals are not modeled elements at any view depth); (c) containers/data-stores — none (the probe is a committed script, not a store); (d) actor↔surface access relationships — none change (the sweeper reads GitHub through already-modeled CI machinery). A future engineer reading the ADRs + C4 after this ships would not be misled: the soak machinery is unchanged in shape — one evidence source added inside an existing probe arm.

### Sequencing

No sequencing constraint — code, test, and the `decision-challenges.md`/`tasks.md` artifacts land in one PR.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "For a merged qualifying PR whose merge commit has no completed `push` run, fall back to the `merge_group` CI run(s) on that commit and apply the same gated `test-scripts*` jobs check (a red `merge_group` run on a gated job is equivalent escape evidence — the queue ran the full battery on the exact commit that landed)" [#12478 Suggested fix] | Phase 1 steps 2-6 + Guard Contract matrix | mapped |
| 2 | "Alternative: bucket queue-merged PRs as a distinct `queued`/`no-push-run` class reported in the note line, like `unrelated` — weaker, it drops real escape evidence the merge_group run already provides." [#12478] | `via_mg` note line (Phase 1 step 4) preserves the visibility instinct; the evidence-dropping bucket itself is the fork's losing arm | descoped — justification: the issue itself assesses the bucket as weaker (drops real escape evidence); the fork is recorded `pending - assumed: Arm A` in decision-challenges.md and re-verified at Phase 1 step 1 |
| 3 | "the sweeper leaves #9323 open forever at merge-queue volume" (consequence to remedy — the probe must converge) [#12478 Consequence] | whole plan; AC2/AC5 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `pr-battery-gate-saving-9323.sh` mg fallback + shared classifier | "fall back to the `merge_group` CI run(s) on that commit and apply the same gated `test-scripts*` jobs check" | asked |
| `pr-battery-gate-saving-9323.test.sh` fixtures + read-contract assertions | "apply the same gated `test-scripts*` jobs check" (a classification change without mutation coverage is the vacuous-guard class) | inferred — justification: every guard change carries its test battery per the repo's guard contract and the probe's own registered suite |
| `via_mg` note line + counter | "bucket queue-merged PRs as a distinct `queued`/`no-push-run` class reported in the note line" | inferred — justification: preserves option B's visibility instinct (queue merges reported on the note line) without its evidence loss; zero extra reads |
| `need_min` bump to `4 * MAX_RUNS` | — | inferred — justification: the +1-read worst case (all qualifying PRs queue-merged) must stay inside the sweeper's ~1000-req/hr quota floor or the probe starves through a different door |
| header/doc comment updates (:9-13, :319-326, :401-406, :567-577, :602) | — | inferred — justification: the comment block is the file's contract documentation; left stale it would claim push-only evidence and misdescribe the arm |
| `decision-challenges.md` / `tasks.md` | — | inferred — justification: the one-shot pipeline contract requires the `\| Item \| Class \| Ruling \|` persistence and the work-phase task breakdown |

### Split Assessment

- Subsystems touched: 2 — `scripts/`, `knowledge-base/` (no `.github/`, `apps/`, or `plugins/` file changes)
- Planned files: 4 (2 edit + 2 create) | Estimated changed lines: ~120
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines — under all three
- Recommendation: single PR

## Acceptance Criteria

- [ ] AC1: In `_pbg_w_esc`, a merged qualifying PR whose `merge_commit_sha` has no completed ci.yml `push` run triggers exactly one `runs?event=merge_group&head_sha=$sha` read through the existing `api()` contract, and its newest run's conclusion flows through the SAME classifier as a push run — one shared classification path, no second `test-scripts` enumeration.
- [ ] AC2: `bash scripts/followthroughs/pr-battery-gate-saving-9323.test.sh` exits 0, including new fixtures covering Guard Contract rows 1-8 (absent-push+green-mg PASS; absent-push+red-gated-mg ESCAPE; absent-push+red-nongated-mg unrelated; absent both → pending; mg-jobs-fail → pending; incomplete/cancelled mg → pending; second-member escape).
- [ ] AC3 (read contract): a fixture with a conclusive push run issues NO `event=merge_group` read (verified via `requests.log`); an `open` PR issues neither push nor mg read; an absent-push merged PR issues exactly one mg read.
- [ ] AC4: A queue-merged qualifying PR with a `success` mg run contributes `via_mg` to the new note line (`N qualifying PR(s) verified via merge_group run(s)…`), exits the `pending` bucket, and the probe can reach PASS.
- [ ] AC5: `need_min` is updated to `4 * MAX_RUNS` with the comment modeling pull + push + mg + prefetch; header/doc comments (:9-13, :319-326, :401-406, :567-577) name merge_group where they describe escape evidence; the pending NOT YET line names both events.
- [ ] AC6: `bash -n` clean on both scripts; the `set -uo pipefail` contract holds (every new read carries the `rc`/`cut`/`fail` guard shape); no change to the exit-code vocabulary (0/1/2/3/78).
- [ ] AC7: `knowledge-base/project/specs/feat-one-shot-12478-merge-group-escape-evidence/{decision-challenges.md,tasks.md}` committed; `decision-challenges.md` carries the fork as a `## Decision Classes` row (`pending - assumed:` or `Ruled by CTO agent` if the batched gate lands it).
- [ ] AC8: PR body carries `Closes #12478` and `Ref #9323` / `Ref #12360`; no `Closes`/`Fixes`/`Resolves` keyword aimed at #9323.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change. Product/UX gate: NONE — no user-facing surface, no `components/**/*.tsx` / `app/**/page.tsx` / `app/**/layout.tsx` in either Files list; the mechanical UI-surface override does not fire.

## Test Scenarios

- Given a merged qualifying PR with an absent push run and a `success` merge_group run on its merge commit, when `_pbg_w_esc` classifies it, then the row is `ok` (sourced from mg), `via_mg` increments, and the probe exits 0 PASS — regression for the shipped defect (unit — `.test.sh` fixture; matrix rows 1/8).
- Given an absent push run and a mg run red on a `test-scripts*` leg, then `escape` and the verdict FAILs honestly (unit; matrix row 1).
- Given an absent push run and a mg run red only on `lint-bot-statuses`, then the unrelated-family row, `escapes` stays 0 (unit; matrix row 2 — the live #12445 shape).
- Given two queue-merged PRs where the first is mg-green and the second mg-red-gated, then the escape fires on the second member (unit; matrix row 3).
- Given a conclusive push run (green or red), then NO `event=merge_group` read appears in `requests.log` (unit; matrix row 4 — API-budget/dispatch invariant).
- Given an absent push run with an empty/in_progress/cancelled mg arm or a failed jobs read on a red mg run, then `pending` — never `ok` (unit; matrix rows 5-6).
- Given an open qualifying PR beside a queue-merged pending one, then requests.log shows no push read and no mg read for the open PR while the merged one still NOT YETs (unit; matrix row 7 — the #12360 zero-extra-reads contract).
- Given the full suite, when `bash scripts/followthroughs/pr-battery-gate-saving-9323.test.sh` runs, then exit 0 (integration — registered suite, `test-all.sh:7094`).

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` (200 issues) searched against both Files-to-Edit paths: zero matches.

## Context

- Live evidence (all `gh api` reads 2026-11-09): `c0612a80f5117b0baaec76fd29ab6c3d68debc27` → 0 push runs, mg run `42532979741` completed/failure whose only failed job is `lint-bot-statuses`; `161b8fb0fc062bb08bc11d3d9a3e44b641b55fad` → 0 push runs, mg `42493927928` success; `089b193122af1af34c0864d7ba3a4a7a5e5b2d14` → 0 push runs, mg `42472568357` success. A 10-char `head_sha` prefix returns an EMPTY merge_group list while the full SHA returns the run — fixtures and code must always use the full `merge_commit_sha`.
- Issue #12478's own measurement: `3 qualifying PR(s) have no completed push run on their merge commit`; `mean_runner_min=298.2` vs `required_saving=20`, `evidenced_runs=21/40` — only the escape arm fails to conclude.
- Precedents: #12360/`057f1e5acc` (`open`/`dropped` buckets — the absorbing-state sibling); PR #12439/`a2fe028227` (the 2026-11-08 job-scoped classifier this change reuses); `ci.yml:221-223` + `ci-draft-light-soak-9728.sh:262` (the in-repo `event=merge_group&head_sha=` query idiom).

## Non-Goals

- No `queued`/`no-push-run` bucket as a substitute for evidence (Arm B — the losing fork arm; visibility is preserved via `via_mg`, not by dropping classification).
- No changes to `zot-mirror-connector-6416.sh` or `web-platform-release.yml resolve-target` — different surfaces with deliberate `event=push` pins on `branch=main`/`workflow_run` arms where push runs still exist.
- No change to `ci.yml`, the sweeper workflow, the tracker directive, `MIN_RUNS`/`MAX_RUNS`/`PAGE_CAP`/`EXAMINE_CAP`/`ART_READ_CAP`/`REQUIRED_SAVING_MIN` tuning, or the exit-code vocabulary.
- No verdict comment posted to #9323 by the implementation (the sweeper's next run posts the honest verdict).

## Risks

- **CTO re-ruling to Arm B.** Mitigated: `decision-challenges.md` carries the pending-assumed row; Phase 1 step 1 re-verifies before implementing; Arm B is a strict sub-diff in the same worker.
- **Mg-run selection ambiguity** (multiple mg runs on one sha — retried groups). Mitigated: newest-first `.workflow_runs[0]` mirrors the push arm; a non-conclusive newest run is `pending`, honest.
- **API shape drift** (`head_sha` search staleness — the 2026-09-24 release-workflow precedent showed the filtered search can return `[]` transiently). Mitigated: a `fail` row on transport failure → CANNOT ESTABLISH (retried), an empty list → `pending` (NOT YET) — neither can silently `ok`; the probe errs toward more evidence, never less.
- **A red mg run that postdates a green push run on the same sha** (re-run red). Not reachable under the read order: a conclusive push arm never issues the mg read — the push verdict stands, matching today's semantics.

## Enhancement Summary

**Deepened on:** 2026-11-09
**Mode:** sequential-fallback (no subagent spawn available in the planning seat; research/learnings were folded in inline during plan construction rather than by fan-out — disclosed)
**Sections enhanced:** Research Insights (premise re-verification against live API), Guard Contract (matrix rows derived from the live #12445/#12376/#12330 shapes), Acceptance Criteria (read-contract assertions AC3), Context (verbatim `gh api` evidence)

### Gate results (all halt gates passed)

- §4.6 User-Brand Impact — present, threshold `none` + scope-out reason
- §4.7 Observability — 5-field schema present; `discoverability_test` = `bash <probe>` → `CANNOT ESTABLISH` (unauthenticated, <15s, literal)
- §4.8 PAT-shaped variable sweep — clean
- §4.9 UI-wireframe — N/A (no UI-surface files)
- §4.10 Encryption Posture — N/A (no persistent store / new connection)
- §4.11 Guard Contract — `lint-guard-contract.py` PASS (1 guard entry, 8 matrix rows)
- §4.12 Scope Check — 1 unfenced section, all asks mapped/justified
- §4.13 Task Design — N/A (no new autonomous-task surface)

### Key Improvements

1. **Premise re-verified live, not from the issue text:** all three cited merge commits probed directly — 0 push runs AND the `merge_group` runs located by full-SHA `head_sha`; #12445's failed run's jobs enumerated (`lint-bot-statuses` only → `unrelated` under the existing classifier).
2. **API-shape gotcha surfaced at plan time:** a 10-char `head_sha` prefix returns an empty `merge_group` list while the full SHA returns the run — the plan pins "always the full `merge_commit_sha`" into both code and fixtures.
3. **Sibling-surface audit:** `zot-mirror` and `web-platform-release.yml resolve-target` verified to be different, deliberately-pinned `event=push` surfaces — not the same defect; scoped out explicitly.
4. **API-budget honesty:** `need_min` modeled to `4 * MAX_RUNS` for the new worst case (+1 mg read per qualifying run).

### New considerations discovered

- Seven workflows (not just ci.yml) run `merge_group` on a landed sha — the fallback MUST stay workflow-scoped (`workflows/ci.yml/runs`), matching the existing push-arm scope.
- Push runs on main still exist for other commits (e.g. `42605214262` on `5990a567b3aa`) — the gap is specifically that queue-merged `merge_commit_sha`s carry `merge_group` runs; the issue's "never a push run" reads true at the merge-commit level, not the main-push level.
- Multiple `merge_group` runs can exist per PR across retry attempts — but only the run sharing the landed `merge_commit_sha` is evidence, which the `head_sha=` filter enforces structurally.

## References

- Issue: #12478 (this fix); trackers #9323 (soak, ADR-262), #12360 (open/dropped sibling)
- ADRs: ADR-262 (gate + R1 escape definition), ADR-270 (merge-queue enforcement), ADR-276 (`merge_group` = full-battery authority)
- Prior probe work: `057f1e5acc` (#12360 bounded-parallel + open-PR re-scope), `a2fe028227` (#12439 job-scoped escape classifier), `80b7656773` (#11767 realized-skip soak arm)
