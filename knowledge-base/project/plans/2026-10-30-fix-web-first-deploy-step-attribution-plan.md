---
title: "fix: web-first-deploy probe reads aged job logs (UNKNOWN STEP) as zero-line and trips standing CANNOT ESTABLISH"
type: fix
date: 2026-10-30
slug: web-first-deploy-step-attribution
branch: feat-one-shot-11600-job-log-step-attribution
issue: 11600
closes: 11600
priority: p2-medium
domain: engineering
lane: cross-domain
brand_survival_threshold: none
---

# fix: web-first-deploy probe reads aged job logs (UNKNOWN STEP) as zero-line and trips standing CANNOT ESTABLISH

## Overview

GitHub stops attributing job-log lines to named steps a few weeks after a job completes: `gh run view --job <id> --log` returns the whole log under the synthetic label `UNKNOWN STEP` while the content itself survives. The standing first-deploy watchdog enrolled on #11583 anchors its trail parse on the step-name column (`scripts/followthroughs/web-first-deploy-10585.sh:260`, `index($2, step) == 1`), so every aged `web_host_replace`/`web_host_create` job in its 30-day population window reads as a success with zero parseable trail lines and the probe takes its drift tripwire (exit 3) on each daily sweep — blind to the genuinely-overdue first deploy it exists to catch. The fix adapts the `##[group]Run` region-slice technique already proven in `scripts/followthroughs/git-data-boot-poll-8178.sh`: when the step-name anchor yields nothing, slice the trail step's output region by runner group headers stamped at or after the step's `started_at` from the jobs API (with the UTF-8 BOM strip gh requires), apply the existing emitted-vs-echoed filter to that region, and keep the tripwire for a trail that is absent even after recovery. Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed).

## Problem Statement / Motivation

Measured 2026-10-30 on #11583's own population (issue body evidence table):

| Run | Job | Date | web job | Step attribution | Trail content present |
|---|---|---|---|---|---|
| 37518962216 | 112459070354 | 10-06 | web_host_replace failure | `UNKNOWN STEP` only | yes (pointer line) |
| 37519267492 | 112460111156 | 10-06 | web_host_replace **success** | `UNKNOWN STEP` only | yes (pointer + `fresh_boot_ready` web-2) |
| 37678331159 | 112987533384 | 10-07 | web_host_replace **success** | `UNKNOWN STEP` only | yes (pointer + `fresh_boot_ready` web-2) |
| 40720815376 | 122930901233 | 10-28 | web_host_replace success | full step names | yes (111 parsed lines) |

The attribution boundary lies between 10-07 and 10-27. `gh run list` iterates newest-first, so the probe clears the 10-28 run then deterministically exits 3 on run 37678331159's unreadable-but-proven trail — every daily sweep until the aged runs leave the 30-day window (~Nov 6). While tripped, Step 1 aborts before Step 3, so a genuinely overdue first deploy (the exit-5 incident shape this arm exists for) cannot surface: the watchdog is blind exactly when its alert matters. Supersession cannot rescue it either — the tripwire fires on the aged job's unreadable trail *before* the newer 10-28 boot can supersede it.

Root defect: `web-first-deploy-10585.sh` Step 1 derives trail lines solely from `index($2, step) == 1` — a column GitHub stops populating ~2-3 weeks after completion. The countermeasure exists in-repo: `git-data-boot-poll-8178.sh` hit the identical platform behavior and slices each step's output region by the runner's `##[group]Run` headers anchored on the step's `started_at` from the jobs API, with a mandatory UTF-8 BOM strip (measured on job 106093730126: 14 of 15 section headers BOM-prefixed).

## Proposed Solution

Adapt the 8178 region-derivation to the 10585 probe as a *recovery path* behind the existing named-step anchor:

1. **Extend the jobs-API `--jq`** (`web-first-deploy-10585.sh:239-240`) to emit a 4th TSV field: the trail step's `started_at` (`// "-"` when absent). The step selector already uses `startswith("Surface fresh-host Sentry breadcrumb trail")`; reuse it for both fields. `read -r jid jcon jstep jstart`.
2. **Normalize `$log` once after fetch** — `log=${log//$'\r'/}; log=${log//$'\357\273\277'/}` (8178's exact bash idiom; the `//` global form is load-bearing — a real log carries one BOM per step section). Applied before BOTH parse paths; it also fixes a latent edge where the first line of a named-attributed section carries a BOM-prefixed timestamp into `ts_to_epoch`.
3. **Named parse first (unchanged semantics).** Extract the emit-filter (`sub(/^[^ ]+ /,"",line)` ts-strip + ESC-first-char drop + `printf "%s\t%s\n", ts, line`) into one shared awk filter so the named path and the recovery path consume through the same chokepoint — the #9905 ANSI-echo rule must never drift between two copies.
4. **Recovery:** when `trail` is empty AND `jstart` matches the ISO-8601 ts shape, slice the region with the 8178 awk verbatim: reduce each line to its third field, first `##[group]Run` header with `ts >= ${jstart:0:19}` opens the region, the next header (or EOF) closes it. Feed region lines through the SAME emit-filter → identical `ts\tcontent` rows for the downstream pointer/`fresh_boot_ready` parse, which changes not at all.
5. **Tripwire preserved verbatim** (`jcon == "success" && -z "$trail"` → exit 3), now evaluated *after* recovery: a success job whose recovered region holds no emitted trail-pattern lines — or whose log has no `##[group]Run` header at/after `started_at`, or no `started_at` at all — remains CANNOT ESTABLISH. The message keeps the literal `zero parseable lines` substring the suite's checks grep, optionally suffixed with the recovery cause (e.g. `attribution-expired log; no ##[group]Run header at/after <ts>`).
6. Recovery is **conclusion-agnostic**: it runs whenever the step ran (`jstart` present), matching existing semantics where any parsed trail contributes `BOOT_EPOCH` regardless of job conclusion — the 10-06 *failure* run's pointer must enroll identically.

## Technical Considerations

- **Why `started_at` and not the step name:** in an aged log every line's field-2 is `UNKNOWN STEP`; the runner's `##[group]Run` headers are the only per-step boundary left, and the jobs API is the only remaining source of which step owns which window. The API's `started_at` and the log header's stamp are both runner-sourced — 8178 measured them agreeing.
- **Mixed attribution is covered for free:** the recovery gate is `trail` empty, not "all fields UNKNOWN" — a partially-attributed log whose trail lines sit under `UNKNOWN STEP` recovers identically.
- **plan_only/skip short-circuit unchanged:** `jstep == "skipped"` still `continue`s before the log fetch, so designed absences never reach recovery (existing case 7c pins this).
- **Carried residuals (stated, accepted):** (a) a `::group::` annotation whose title literally begins `Run` followed by a space could false-bound a region — same residual 8178 accepts; (b) sub-second skew between API `started_at` and the header stamp could select the *next* step's region — on a success job that yields zero trail lines → CANNOT ESTABLISH (fails loud); on a failure job it silently contributes nothing, matching today's best-effort posture for non-success jobs; (c) `##[group]Run` inside-step echoes are filtered by the region's own header regex.
- **Fixture fidelity (the 8178 suite's own scar tissue):** the UNKNOWN STEP generator must reproduce gh's real document shape — a BARE `Set up job` first section (gh strips the BOM only from the head of the stream), a BOM'd section stamped BEFORE the trail step's `started_at` (so the `ts >= ps` gate has something to skip), the BOM'd trail-step `##[group]Run` at `started_at`, payload lines, and a BOM'd next-step header (so the region bound is exercised). A lone-section fixture leaves both the timestamp gate and the global-vs-single BOM strip unpinned — exactly the two mutations that made 8178's pre-fix suite green against a probe that could not read a real log.
- **`job()` fixture signature** gains the step's `started_at`/`completed_at` (the stub `gh` evaluates the probe's own `--jq`, so the new field needs no stub change — only fixtures that exercise recovery need real values; absent → `-` → recovery skipped → tripwire, which existing zero-trail cases already rely on).
- **Shell portability:** `log//` bash global replace and `sprintf("%c",27)` are already the probe's idioms; no new interpreter dependencies.
- NFR impacts: none — a read-path change to a daily sweep probe; no perf/security surface change (the probe's credential posture, `env -i` sweeper contract, xtrace refusal and never-0/never-1 trap are untouched).

## Files to Edit

- `scripts/followthroughs/web-first-deploy-10585.sh` — jobs `--jq` gains `started_at` (`web-first-deploy-10585.sh:239-240`); BOM+CR strip after log fetch (`:253-255`); shared emit-filter extraction; `##[group]Run` region-slice recovery block (new, adapting `git-data-boot-poll-8178.sh:202-209`); tripwire evaluated post-recovery (`:269-272`); header comment: Step-1 description, RESIDUALS, and the attribution-expiry note.
- `scripts/followthroughs/web-first-deploy-10585.test.sh` — `job()` emits `started_at`/`completed_at` for the trail step (`:133-136`); `GH_LOG_BOM` + `ul()`/`usrc()`/`ulog()` UNKNOWN STEP fixture builders (idiom per `git-data-boot-poll-8178.test.sh:122-197`); new cases below; anti-vacuity floor bump to match the new baseline.
- `knowledge-base/engineering/operations/runbooks/followthrough-convention.md` — sharp-edge note: gh drops step-name attribution ~2-3 wk post-completion (content survives under `UNKNOWN STEP`); `--log`-parsing probes must anchor on `##[group]Run` regions keyed on the step's jobs-API `started_at` + the global BOM strip; cites this fix and #8262/#8178.

## Files to Create

None. (One follow-up GitHub issue is filed during work — see Dependencies & Risks.)

## Open Code-Review Overlap

None — queried open `code-review` issues for `scripts/followthroughs/web-first-deploy-10585.sh`, `.test.sh`, `git-data-boot-poll-8178.sh`, and `followthrough-convention.md` (2026-10-30): zero bodies name them.

## User-Brand Impact

- **If this lands broken, the user experiences:** no direct user artifact — the worst case is the standing watchdog on #11583 still posting CANNOT ESTABLISH (or worse, reading a proven trail as empty), leaving an operator-facing tracker noisy while a real first-deploy outage goes unreported to the operator who runs the fleet.
- **If this leaks, the user's [data / workflow / money] is exposed via:** nothing new — the probe reads public-to-the-token CI logs it already reads; no new credential, store, or egress.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the blast radius is an internal standing monitor and its tracker issue; no user-facing page, data, or money path is touched, so the next tier up does not apply.

## Observability

The changed surface IS an observability probe; its own health is the sweeper verdict posted to the tracker.

```yaml
liveness_signal:
  what:            # the probe's daily verdict on tracker #11583 (exit-code → comment word)
  cadence:         # daily via scheduled-followthrough-sweeper.yml
  alert_target:    # issue comment on #11583 (operator inbox)
  configured_in:   # issue #11583 body `<!-- soleur:followthrough script=… -->` directive

error_reporting:
  destination:     # the same tracker comment — CANNOT ESTABLISH posts with the cause inline
  fail_loud:       # exit 3 message now names the recovery cause (no started_at / no ##[group]Run header at/after it / empty region)

failure_modes:
  - mode:          # attribution expiry (this fix's target)
    detection:     # recovered region or, on a success job, the post-recovery tripwire comment
    alert_route:   # tracker comment on #11583
  - mode:          # genuinely absent trail (the property the tripwire guards)
    detection:     # exit 3 "zero parseable lines" — same verdict as today, now reachable only after recovery fails
    alert_route:   # tracker comment on #11583
  - mode:          # genuinely overdue first deploy (the incident shape the probe exists for)
    detection:     # exit 5 ACTION REQUIRED naming host + boot ts + run URL + control_rows
    alert_route:   # tracker comment on #11583

logs:
  where:           # the scheduled-followthrough-sweeper workflow run log + the tracker comment trail
  retention:       # GitHub Actions log retention; tracker comments persist on the issue

discoverability_test:
  command:         grep -n 'started_at' scripts/followthroughs/web-first-deploy-10585.sh
  expected_output: started_at
```

## Guard Contract

The deliverable modifies an assertion-based control — the trail-read guard pair (extraction + zero-parseable tripwire) and the fixture suite that drives it.

### Guard 1 — attribution-tolerant trail read + zero-parseable tripwire

**Property.** For every completed `web_host_replace`/`web_host_create` job whose trail step ran (per the jobs API), the probe either recovers that step's emitted lines — by the step-name column when attributed, else by the `##[group]Run` region keyed on the step's `started_at` after the global BOM/CR strip — and grades them, or, for a success-conclusion job, exits CANNOT ESTABLISH; it never silently grades an unreadable trail as an empty population.

**Assembly.** Two chokepoints: (a) the probe's Step-1 parse pipeline in `web-first-deploy-10585.sh` — the jobs `--jq` step selector (now carrying `started_at`), the log normalization, the named-step anchor, the region-slice recovery, the shared emit-filter, and the post-recovery tripwire — every trail line flows through this one pipeline; (b) the fixture suite's `gh` stub + `ulog()` generator in `web-first-deploy-10585.test.sh` — every UNKNOWN STEP document the property is tested against flows through it.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Delete the region-slice recovery (empty trail goes straight to the tripwire) | RED — the UNKNOWN STEP enroll/overdue cases exit 3 instead of grading |
| 2 | Weaken the BOM strip to single-replacement (`${log/…/}` for `${log//…/}`) | RED — the fixture's second BOM'd section header keeps its mark; `^[0-9]` misses it; region empty (guard's own normalization) |
| 3 | Drop the `ts >= ps` gate (first `##[group]Run` header wins) | RED — the BOM'd prelude section stamped before `started_at` is selected instead of the trail step's (order/lifetime row) |
| 4 | Emit-filter only the named path (region lines consumed unfiltered) | RED — the ANSI-echoed-`fresh_boot_ready`-inside-region fixture enrolls a boot that was never emitted |
| 5 | Gate recovery on `jcon == "success"` | RED — the failure-job-with-pointer fixture loses the obligation the 10-06 run carries (second-member/conclusion-class row) |
| 6 | Remove the tripwire (post-recovery empty trail → continue) | RED — the genuinely-absent-trail fixtures exit 2 — a quiet pass on a broken channel (own-dispatch row) |
| 7 | Harness: `job()` stops emitting `started_at` | RED — every recovery fixture exits 3 "no started_at"; the suite can never certify the path it exists for |
| 8 | Harness: `ulog()` drops the earlier-BOM'd prelude section | Suite still passes BUT rows 2–3 lose their discriminating fixtures — flagged vacuity; the suite must keep the prelude (must-PASS constraint documented in the builder comment) |
| 9 | Must-PASS non-canonical input: trail step is the job's LAST section (region runs to EOF, no bounding header) | PASS — region recovery still grades the trail; pins that EOF is a valid region end |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "slice the step's output region by the runner's `##[group]Run` headers anchored on the trail step's `started_at` from the jobs API — exactly the region-derivation `git-data-boot-poll-8178.sh` documents at its awk block (including the mandatory BOM strip: gh emits a UTF-8 BOM before each section's timestamp)" [issue #11600] | Proposed Solution steps 2–4; `web-first-deploy-10585.sh` edits | mapped |
| 2 | "Then apply the existing ANSI-source filter + pointer/`fresh_boot_ready` parse to that region unchanged." [issue #11600] | Proposed Solution step 3 (shared emit-filter); AC-4 | mapped |
| 3 | "Keep the tripwire: a success job whose *recovered region* still holds no trail-pattern lines remains CANNOT ESTABLISH. `UNKNOWN STEP` with zero trail-pattern lines anywhere is the same verdict — a degraded channel, not a quiet pass." [issue #11600] | Proposed Solution step 5; AC-3; Guard Contract row 6 | mapped |
| 4 | "Probe grades aged `UNKNOWN STEP` jobs correctly (the 10-06/10-07 boots either enroll as obligations or are cleanly superseded — never a tripwire on attribution expiry alone)." [issue #11600] | AC-1, AC-2, AC-6; test cases A–B, G | mapped |
| 5 | "Fixture in `web-first-deploy-10585.test.sh`: a synthesized `UNKNOWN STEP` log (the 8178 test file already has the generator idiom — `printf '%s\tUNKNOWN STEP\t%s%s %s\n'`) covering emitted-vs-ANSI-echoed lines and the BOM." [issue #11600] | `.test.sh` edits (GH_LOG_BOM, ul/usrc/ulog builders); AC-2 | mapped |
| 6 | "Tripwire still fires when a success job's trail output is genuinely absent." [issue #11600] | AC-3; test case D | mapped |
| 7 | "First post-fix sweep on #11583 exits 2/5 by measurement, not 3 by unreadability." [issue #11600] | AC-7; Success Metrics | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Region-slice recovery + BOM strip in `web-first-deploy-10585.sh` | asks 1–2 (quoted above) | asked |
| Post-recovery tripwire retention | ask 3 (quoted above) | asked |
| UNKNOWN STEP fixture builders + new cases in `.test.sh` | ask 5 (quoted above) | asked |
| `job()` emits `started_at`/`completed_at` | — | inferred — justification: the ask's mechanism anchors the region "on the trail step's `started_at` from the jobs API"; the fixture must carry the field for the probe's own `--jq` to select it |
| `followthrough-convention.md` sharp-edge note | — | inferred — justification: the identical defect is latent in two sibling step-anchored probes and in every future `--log` probe; the convention doc is where probe authors inherit the countermeasure |
| Follow-up issue for sibling probes (`web-fresh-boot-zot-8651.sh`, `git-data-rehearsal-evidence.sh`) | — | inferred — justification: same exposure class outside #11600's declared scope; the deferral-tracking check requires a tracking issue, never an invisible deferral |
| Anti-vacuity floor bump in `.test.sh` | — | inferred — justification: a floor pinned at 30 while the suite grows past it becomes decorative; bump keeps it load-bearing |

### Split Assessment

- Subsystems touched: 2 — `scripts`, `knowledge-base`
- Planned files: 3 | Estimated changed lines: ~230
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] AC-1: A synthesized success-conclusion job whose log is fully `UNKNOWN STEP` — BOM'd `##[group]Run` headers, prelude section stamped before `started_at`, trail region carrying an emitted pointer + `fresh_boot_ready`, a bounding next-step header — is graded by its content (accounted→exit 2, overdue→exit 5), never exit 3 on attribution alone.
- [ ] AC-2: The fixture generator reproduces gh's real document shape: `UNKNOWN STEP` in field 2, the UTF-8 BOM on every section header after the first (bare `Set up job` first section), a pre-`started_at` section the timestamp gate must skip, and a next-step header bounding the region; at least one fixture exercises the emitted-vs-ANSI-echoed split inside the region.
- [ ] AC-3: The tripwire still fires — a success-conclusion job whose recovered region (or whole `UNKNOWN STEP` log) holds zero emitted trail-pattern lines exits 3 with a message containing `zero parseable`; a missing/invalid `started_at` on a success job also exits 3.
- [ ] AC-4: The recovered region passes through the same emitted-vs-echoed filter as the named path — an `UNKNOWN STEP` region whose `fresh_boot_ready`/pointer text appears only in ANSI-prefixed echoed `run:` source creates no obligation (exit 2 mirror of existing case 7).
- [ ] AC-5: Recovery is conclusion-agnostic — a failure-conclusion job's `UNKNOWN STEP` log carrying an emitted pointer + `fresh_boot_ready` enrolls the obligation identically to a named-attribution log.
- [ ] AC-6: A supersession pair — aged `UNKNOWN STEP` boot plus a newer named-attribution boot for the same key — keeps only the newest boot (mirrors the live 10-06/10-28 shape).
- [ ] AC-7: First post-merge sweep of `web-first-deploy-10585.sh` against #11583 exits 2 or 5 — measured by the sweeper's posted verdict, never 3-by-unreadability.
- [ ] AC-8: All pre-existing cases stay green (zero-parseable checks, plan_only skip, mutations 1–4, roster gate, credential/binary preflights, xtrace refusal) and every driven path still exits in {5,2,3,78}; the anti-vacuity floor is bumped to the new baseline.
- [ ] AC-9: `followthrough-convention.md` records the attribution-expiry behavior + the `##[group]Run`/`started_at`/BOM-strip countermeasure, and a follow-up issue naming `web-fresh-boot-zot-8651.sh` and `git-data-rehearsal-evidence.sh` is filed and linked.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — internal tooling change on an existing ops surface: the Engineering assessment question ("significant architectural decisions … beyond normal implementation") does not fire on adapting an already-merged technique to a second consumer of the same parse pattern; Product has no user-facing surface (no Files entry matches the UI-surface glob superset); Marketing/Sales/Support/Legal/Finance/Operations have no content, pipeline, document, budget, or vendor surface in this diff.

## Test Scenarios

All scenarios are `unit`-layer fixture cases in `web-first-deploy-10585.test.sh` (the suite's PATH-stubbed `gh`/`bsq` seams); AC-7 is a `integration`-layer live verification by the deployed sweeper.

- Given a success job whose log is `UNKNOWN STEP`-attributed with a valid `started_at` and a region carrying emitted pointer+`fresh_boot_ready`, when the probe runs with an accounting marker, then it exits 2 (case A; AC-1).
- Given the same log with no marker and a boot older than 2d, when the probe runs, then it exits 5 naming the host — the overdue arm through recovery (case B; AC-1).
- Given a failure-conclusion job's `UNKNOWN STEP` log carrying emitted pointer+ready, when the probe runs, then the obligation enrolls identically to named attribution (case G; AC-5).
- Given an `UNKNOWN STEP` region containing only ANSI-echoed pointer/ready copies beside one emitted pointer, when the probe runs, then no `fresh_boot_ready` is credited → no obligation (case C; AC-4).
- Given a success job whose `UNKNOWN STEP` log has a region with zero trail-pattern lines — and a second variant with no `##[group]Run` header at/after `started_at` — when the probe runs, then both exit 3 (case D; AC-3).
- Given a success job whose jobs-API step entry lacks `started_at` alongside an `UNKNOWN STEP` log, when the probe runs, then exit 3 — unbounded is unmeasured (case F; AC-3).
- Given an aged `UNKNOWN STEP` boot and a newer named-attribution boot for `web-2`, when the probe runs, then only the newest boot is owed — supersession across attribution modes (AC-6).
- Given the `ts >= started_at` prelude section and a next-step bounding header, when mutations delete the timestamp gate or single-strip the BOM, then the suite reddens (Guard matrix rows 2–3; AC-2).
- Given the trail step as the log's LAST section (no bounding header), when the probe runs, then the EOF-terminated region still grades (matrix row 9 must-PASS).
- Property: every driven path — recovered or not — exits in {5,2,3,78} (existing SEEN_RCS sweep extended to all new cases; AC-8).

## Success Metrics

- The next daily `scheduled-followthrough-sweeper` run after merge posts NOT YET (2) or ACTION REQUIRED (5) on #11583 — not CANNOT ESTABLISH (3) citing unparseable lines on the 10-06/10-07 jobs.
- `bash scripts/followthroughs/web-first-deploy-10585.test.sh` reports 0 failures with the new UNKNOWN STEP cases included.

## Dependencies & Risks

- **`started_at` availability:** the jobs API already returns `.steps[].started_at` (8178 consumes it for the poll step); absent → `-` → tripwire on success jobs (fails loud, never quiet).
- **Time pressure inverts:** the visible symptom self-resolves ~Nov 6 when the aged runs leave the 30-day window — the fix still matters because every future boot ages into the same window; the fixture is what proves it.
- **Carried residuals** (8178-accepted, restated in Technical Considerations): `##[group]Run` title collision; sub-second `started_at`/header skew selecting an adjacent region (loud on success, best-effort-silent on failure — same posture as today).
- **Sibling exposure:** `web-fresh-boot-zot-8651.sh` and `git-data-rehearsal-evidence.sh` anchor on the same step column (measured: `index($2, …)` at their log parses) — deferred to a follow-up issue filed during work, per the deferral-tracking check.
- **Transient log fetches** (the 10-30 dry-run's phantom zero-line read on run 40720815376) are a separate, non-deterministic failure mode this fix does not claim to solve; the tripwire remains the correct verdict for a fetch that returns nothing twice.

## Research Insights

**Premise Validation (Phase 0.6).** Verified 2026-10-30: #11600 OPEN (labels `priority/p2-medium,type/bug,domain/engineering,meta/machinery`); #11583 OPEN standing tracker with the `web-first-deploy-10585.sh` directive (`earliest=2026-10-30T02:15:57Z`); #10585 CLOSED as designed. All four cited paths exist on `origin/main`; the `index($2, step) == 1` anchor is at `web-first-deploy-10585.sh:260`; the 8178 countermeasure at `git-data-boot-poll-8178.sh:166-209` (BOM strip `:202-203`, region awk `:204-207`); the `printf '%s\tUNKNOWN STEP\t%s%s %s\n'` generator idiom at `git-data-boot-poll-8178.test.sh:142`. ADR-corpus grep on the mechanism (region-slicing gh job logs) returns no rejected-alternative conflict — the technique IS the repo's accepted approach (ADR-148 domain; #8262 shipped it). Collision precheck: PR #11603 is THIS branch's own auto-created draft (empty, 2026-10-30) — not a duplicate; foreign `test-all.sh` processes belong to the unrelated `feat-11556-required-check-time` worktree. Nothing stale.

**Property List (Phase 0.6b).** The asks reduce to: (P1) trail content of aged jobs is recovered and graded; (P2) a genuinely absent trail still trips CANNOT ESTABLISH — attribution expiry is never a quiet pass nor a false tripwire; (P3) the emitted-vs-echoed boundary holds inside recovered regions; (P4) the suite certifies all three against a faithful UNKNOWN STEP document shape (BOM, section ordering, bounds).

**Cut List (Phase 0.6b).** The issue proposes one mechanism — the 8178 region-slice — which buys P1 and is already on `origin/main` as the canonical implementation; no alternative mechanism was proposed or needed. Nothing cut: the tripwire (P2), the ANSI filter (P3), and the BOM strip are each the only mechanism covering their property. The convention-doc note and sibling-issue filing are provenance items, not mechanisms.

**Relevant file paths.** `scripts/followthroughs/web-first-deploy-10585.sh:239-272` (jobs `--jq` → log fetch → named-parse → tripwire); `:286-288` (pointer-key extraction over `trail`); `scripts/followthroughs/git-data-boot-poll-8178.sh:166-209` (the technique to adapt); `scripts/followthroughs/git-data-boot-poll-8178.test.sh:106-197` (`add_job` step-`started_at` emission, `GH_LOG_BOM`, `log_lines_at`, prelude/next-step builders, the "why the fixture carries the BOM" comment block); `scripts/followthroughs/web-first-deploy-10585.test.sh:56-77` (`gh` stub evaluating the probe's own `--jq`), `:114-139` (`l()`/`src()`/`job()` builders), `:347-371` (zero-parseable + plan_only cases that must not regress); `sweep-followthroughs.sh` rc→word map (5 ACTION REQUIRED / 2 NOT YET / 3 CANNOT ESTABLISH / TRANSIENT catch-all); `.github/workflows/apply-web-platform-infra.yml:5056,5474` (the trail step, `if: always()` on replace, `if: always() && plan_only != true` on create).

**Institutional learnings.** `2026-09-18-the-measured-facts-my-resume-brief-handed-me-were-the-defects.md` (the 8178 BOM/region story — a fixture without the BOM tested a shape gh never emits); `2026-09-27-a-log-line-is-evidence-about-the-step-that-printed-it.md` (attribute log lines to their `##[group]Run` step — the principle this fix mechanizes); `2026-10-10-a-log-scraping-probe-matched-the-script-it-echoed…md` (the #9905 echoed-source trap — why the ANSI filter must apply inside the region too); `2026-10-15-dormant-followthrough-probe-is-not-a-standing-detector.md` (a tripped watchdog is not a quiet one); `followthrough-convention.md` (notify-only vocabulary, never-0/never-1, `env -i` contract).

**Related issues/PRs.** #11600 (this fix), #11583 (standing tracker), #10585 (probe origin), #8178/#8262 (technique + its shipped proof), #9905 (ANSI-echo trap), #8743 (originating deploy defect), #6995 (conclusion ≠ boot verdict), #7797 (xtrace refusal). Sibling exposure: `web-fresh-boot-zot-8651.sh:58`, `git-data-rehearsal-evidence.sh:196-200` (both `index($2, …)`-anchored — follow-up issue).

**Research decision (Phase 1.6).** External research skipped — the fix adapts an in-repo, already-measured technique onto a second consumer of the same log shape; the issue body carries the platform-behavior measurement. Community/functional discovery: no uncovered stacks (bash/jq internal tooling); functional-overlap agent spawn unavailable in this environment — skipped per the check's never-block clause.

**Research Reconciliation — Spec vs. Codebase.** No spec.md exists for this branch (one-shot pipeline entered at plan); all claims above are verified against `origin/main` directly, per the Premise Validation note. One correction to inherited framing: the probe's own comment says the trail step is `if: always() && plan_only != true` — true for `web_host_create` (yml:5475); the `web_host_replace` leg is plain `if: always()` (yml:5057). Harmless — `jstep == "skipped"` handling covers both.

**Mode note.** Headless/pipeline context (plan-file-path arg, no TTY, no agent-spawn tool): idea-refinement, founder check, advisor consult, domain-leader and plan-review panels were adjudicated inline by the orchestrator — `Reviewed-Coverage: sequential-fallback`; decisions persisted to `knowledge-base/project/specs/feat-one-shot-11600-job-log-step-attribution/decision-challenges.md`.

## References & Research

- Similar implementation: `scripts/followthroughs/git-data-boot-poll-8178.sh:166-209` (region-slice + BOM strip), `git-data-boot-poll-8178.test.sh:106-197` (fixture idiom)
- Tracker/runbook: `knowledge-base/engineering/operations/runbooks/followthrough-convention.md`, issue #11583
- Related PRs: #8262 (8178 fix), #11603 (this branch's draft PR)
- Related issues: #11600 (Closes), #10585, #8178, #9905, #8743, #6995, #7797
