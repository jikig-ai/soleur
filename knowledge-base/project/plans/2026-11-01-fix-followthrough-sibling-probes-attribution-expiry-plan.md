---
title: "fix: port UNKNOWN STEP attribution-expiry recovery to the two sibling step-anchored followthrough probes (#11607, closes #11609)"
type: fix
date: 2026-11-01
slug: followthrough-sibling-probes-attribution-expiry
branch: feat-one-shot-11607-11609-11583-sibling-probes
issue: 11607
closes: [11607, 11609]
priority: p3-low
domain: engineering
lane: cross-domain
brand_survival_threshold: none
---

# fix: port UNKNOWN STEP attribution-expiry recovery to sibling step-anchored probes (#11607, #11609)

## Overview

GitHub drops step-name attribution on completed job logs roughly two to three weeks after a run finishes: every log line returns under field 2 `UNKNOWN STEP` while the content survives intact. PR #11603 (squash 26ec69c3) fixed this exposure in `scripts/followthroughs/web-first-deploy-10585.sh` by recovering the step's output region on the runner's `##[group]Run` headers, opened by the first header stamped at or after the step's `started_at` from the jobs API. Two sibling probes anchor their log parses on the same `index($2, step)` step-name column and carry the same exposure: `web-fresh-boot-zot-8651.sh` and `git-data-rehearsal-evidence.sh`. This plan ports the merged fix shape to both, documents each probe's lookback-window conclusion per issue #11607's re-evaluation criteria, adds attribution-expired fixtures to both probe suites using the `GH_LOG_BOM`/`ul()`/`ulog()` idiom proven in `web-first-deploy-10585.test.sh`, and discharges the decision-challenge recorded in #11609 by closing it in the PR body. Issue #11583 is a permanently-open standing watchdog carried as context only — no `Closes` line. Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed).

## Problem Statement / Motivation

**`web-fresh-boot-zot-8651.sh` (silent "no run" misread).** The probe iterates the newest 40 `apply-web-platform-infra.yml` dispatch runs and grades the newest `web_host_replace`/`web_host_create` job's trail step for web-2 (`web-fresh-boot-zot-8651.sh:48-86`). Its only log reader is `awk -F'\t' -v step="$STEP" 'index($2, step) == 1 { … }'` (`:58`). On an attribution-expired log the named anchor yields an empty trail, the web-2 pointer gate (`:60`) fails, the loop `continue`s — and a proven zot-served boot falls through to `exit 2 "NOT YET: no web_host_replace/web_host_create run for web-2 in the last 40 dispatches"`: a real run misread as absent, indistinguishable from "the replace never happened."

**`git-data-rehearsal-evidence.sh` (mixed counterfeit readings, including false-healthy).** The owner-run collector anchors five step prefixes across five run slots through three `index($2, st) == 1` awk sites (`:202` `lcount`, `:206` `lfirst`, `:485` `refs_msgs`). On an attribution-expired log every count reads 0 and every first-match reads empty, and the downstream renderings differ per field: the Finalizer `lcount` pair reads `0`/`0` → `unwound="no"` → the block prints `finalizer ran yes (unwound no)` — the FALSE-HEALTHY shape, certifying a clean unwind the collector never measured; the replication-probe `lcount` prints `not seen`; `host_ts`/`proof_verdict`/`refs` degrade to `UNREAD`/NOT-CONFIRMED tokens. The block would certify a rehearsal with readings it never made — the exact inversion of the collector's own contract ("a failed read and a zero count are different facts, and this script never prints a zero for a read that did not run", `:43-44`).

## Re-evaluation — per-probe lookback windows (issue #11607's gate)

The issue requires each probe's population window be checked against the ~2-3 week attribution boundary BEFORE porting. Verified 2026-11-01:

**`web-fresh-boot-zot-8651.sh` — window SPANS the boundary; live exposure currently dormant, latent exposure total.** Population = the newest `web_host_replace`/`web_host_create` job inside the newest 40 workflow_dispatch runs of `apply-web-platform-infra.yml` — no `--created` filter, no age bound: the probe iterates newest-first until a web-2 pointer grades or the list exhausts. Host replaces are rare by design (only a replace realizes the zot fix), so the newest web-2 run is routinely older than the ~2-3 week boundary — the window spans it whenever the probe runs. Live posture: its tracker #8651 closed 2026-09-30 and the 14-day closed-lookback retired the probe ~2026-10-14 (verified: `gh issue list --label follow-through` body grep returns no open or recently-closed tracker naming the script), so no sweep currently executes it. Latent posture: on any re-open, re-enrollment, or manual run, the newest web-2 run is already inside the expired window — the recovery is the only way the probe can ever grade that run again. **Conclusion: port warranted.** The dormancy sharpens rather than removes the case: a re-enrolled probe would misread a proven boot on its very first sweep, in the silent-exit-2 shape a sweeper verdict cannot distinguish from "never ran".

**`git-data-rehearsal-evidence.sh` — window SPANS the boundary by construction.** The collector is owner-run (never sweeper-enrolled; its own header forbids it) and takes the graded run ids as arguments — `--flip`, `--rollback`, `--exit`, `--refs`, `--proof-before`, `--rotate`. The "lookback" is whatever runs the owner names: unbounded in age. The Level-2 sequence (refs gate → deletion → exit proof) and the CPO review of the printed evidence block happen days-to-weeks after the rehearsal runs complete, so a first collection lagging the runs — or a re-verification at sign-off — is exactly when the logs cross the boundary. On expiry the block counterfeits the readings named above, including the false-healthy `unwound no`. **Conclusion: port warranted** — and the collector's failed-read-≠-zero contract makes the recovery semantically load-bearing, not cosmetic.

**Census check (so "two siblings" is a claim, not an assumption):** `grep -rn 'index($2' scripts/followthroughs/*.sh` returns exactly the three sites — the already-fixed `web-first-deploy-10585.sh:296`, `web-fresh-boot-zot-8651.sh:58`, and `git-data-rehearsal-evidence.sh:202,206,485`. The other `--log` consumers (`bearer-curl-s4-first-runs-9905.sh` etc.) read steps from the jobs JSON API (`.jobs[].steps[].name`), which is unaffected by log-column attribution expiry. No third sibling exists.

## Proposed Solution

Port the #11600 merged shape — step `started_at` for the parsed step, global BOM/CR strip, `##[group]Run` region-slice recovery behind the named anchor, shared emit-filter, tripwire evaluated post-recovery — to both probes, adapting where each script's shape differs.

### web-fresh-boot-zot-8651.sh — the close-to-verbatim port

1. **Extend the jobs jq** (`:51-53`) to emit three TSV fields for the first non-skipped `web_host_replace`/`web_host_create` job: `databaseId`, the trail step's `conclusion` (`// "absent"`), and the trail step's `startedAt` (`// "-"`). **Adaptation vs #11603:** this probe reads jobs embedded in `gh run view --json jobs` (camelCase `startedAt`), not the REST `gh api repos/…/jobs` the 10585 probe consumes (snake_case `started_at`) — same field, different spelling, extracted from the response already in hand (no new API call). `IFS=$'\t' read -r jid jstep jstart` (or equivalent).
2. **Designed absence first:** `jstep` in {`skipped`, `absent`} → `continue` — a plan_only create or a run predating the step keeps today's continue-on-no-pointer semantics. Recovery and the tripwire engage only for a step that ran.
3. **Normalize `$log` once post-fetch:** `log=${log//$'\r'/}; log=${log//$'\357\273\277'/}` (8178's global idiom — one mark per section).
4. **Shared emit-filter:** extract the content projection (strip leading `<ts> `, drop ANSI-first-char lines — the #9905 echoed-`run:`-source rule) into one awk `emit_content` consumed by BOTH the named-step path (`index($2, step) == 1 { print $3 }` piped in) and the recovered region — one chokepoint, never two copies.
5. **Recovery trigger = patternless named trail** (mirrors #11603 — partial attribution covered): when the named trail holds no `TRAIL_PATTERN` line (`web-host-(replace|create) web-[0-9]+ — fresh-host Sentry pointer|fresh-host boot reached fresh_boot_ready` — host-agnostic like 10585; the existing `${HOST_KEY}`-scoped pointer gate stays downstream) AND `jstart` matches the ISO-8601 shape, slice the region with the 8178 awk verbatim (reduce each line to field 3, `ts >= ${jstart:0:19}` opens, next `##[group]Run` header or EOF closes), feed it through `emit_content`, and replace `trail` with the recovered output only when it contains `TRAIL_PATTERN`; otherwise record `recovery_cause` (no `##[group]Run` header at/after `startedAt` / region held no emitted lines / region emitted no trail-pattern lines / no usable `startedAt`).
6. **Tripwire post-recovery:** `jcon == "success" && -z "$trail"` evaluated AFTER recovery → `echo "TRANSIENT: … <cause>" ; exit 3` — the probe's own CANNOT ESTABLISH word (`TRANSIENT:` prefix, per its exit vocabulary `:27`) with the `zero parseable`-class wording the class of check greps. Non-success jobs keep the `continue` posture (a failure job's unreadable trail is best-effort — the same residual 10585 accepts). Then the unchanged pointer gate and verdict ladder (`:60-86`) grade `trail` identically on either path.
7. **Header comment:** extend the EVIDENCE paragraph and exit-code doc with the attribution-expiry behavior, the recovery contract, and the carried residuals.

### git-data-rehearsal-evidence.sh — the adapted port

This collector differs structurally from both prior ports: it reads WHOLE-RUN logs (`gh run view <id> --attempt N --log` — multiple job sections per file, distinguished by field 1) into scratch FILES, anchors FIVE step prefixes across five slots through three shared awks, and its "tripwire" is the collector's own failed-read-≠-zero contract (UNREAD tokens), not a sweeper exit code.

1. **Normalize each fetched log once.** In `fetch_run` after the `-s` check (`:170`), strip `\r` and the exact three-byte BOM sequence file-wide — bash `${var//…/}` read-write or `sed -i 's/\r//g;s/\xef\xbb\xbf//g'`. **Never `tr -d '\357\273\277'`** — `tr` deletes the three bytes independently, corrupting other UTF-8 (`»`, `¿`) in log content. The per-line `gsub(/\357\273\277/, "", $3)` already inside the three awks stays — idempotent on normalized input, keeps each awk self-sufficient.
2. **New `step_region <slot> <prefix>` helper.** Reads `${WORK}/<slot>.json` for the first `.jobs[].steps[]` matching `startswith(prefix)` and returns three outcomes:
   - **rc 1 — step did not run:** prefix absent from the jobs JSON, or conclusion `skipped` → the caller reports the original zero/empty (legitimate absence — P3).
   - **rc 0 — region sliced:** `startedAt` present → slice the region on the normalized log with the 8178 awk verbatim, PRE-FILTERED to the step's own job (`awk -F'\t' -v jn "$1 == jn"` — a whole-run log carries sibling job sections, e.g. `cutover` vs `wipe`; the `--job`-scoped prior ports never needed this). Re-emit each region line re-attributed as `<job>\t<step-name>\t<ts> <content>` into `${WORK}/<slot>-<pfx-slug>.region.log` so the consumers' unchanged `index($2, st) == 1 && $3 ~ re` evaluation applies identically — the shared-filter property in this script's idiom (one anchored awk, no second parse grammar).
   - **rc 2 — degraded:** step ran but the region cannot be sliced (no `##[group]Run` header at/after `startedAt`, or an empty region).
3. **`lcount`/`lfirst` signature change** to `<slot> <prefix> <regex>` (log file and jobs JSON derived from the slot). Run the unchanged anchored awk on `${WORK}/<slot>.log`; on a zero/empty result call `step_region`: rc 0 → re-run the SAME awk on the region file and use that count/first (a region-measured zero is still a measured zero); rc 1 → report the original zero/empty; rc 2 → return 1 → the caller's existing `note_unread` arm. Call sites: Finalizer pair (`:261-262`), replication probe (`:275`), `host_ts` (`:302-306`, two calls), `proof_verdict` (`:441-442`).
4. **`refs_msgs` site (`:484-485`)** gets the same two-phase treatment via the identical mechanism — run the extraction awk on the named log, and on empty output retry on the `step_region` file (rc 2 feeds the existing `note_unread log-scan-refs` path via `refs_conf`'s failure arm).
5. **No verdict-path changes.** Every existing `note_unread`/`UNREAD` arm absorbs the rc-2 case, so an unrecoverable attribution-expired log surfaces `UNREAD(log-scan-flip)`, `UNREAD(exit-verdict-scan)`, `UNREAD(log-scan-refs)` etc. — never the false-healthy `unwound no` or the silent `not seen` a quiet zero prints today. `stepc`/`stepts` are untouched (jobs-JSON reads, immune to log-column expiry).
6. **Header comment:** extend the `index($2, …)` note (`:196-199`) with the attribution-expiry behavior and the recovery contract.

## Technical Considerations

- **`startedAt` spelling differs per reader.** `gh run view --json jobs` embeds camelCase `startedAt`/`completedAt`; the REST `gh api repos/…/jobs` returns snake_case. Both siblings consume the former — the plan pins `.startedAt` throughout their diffs, and the fixtures carry `startedAt` inside `jobs[].steps[]`. The 10585 `jobs_tsv` pattern (4-field `--jq` TSV) does not translate verbatim; the zot probe extends its existing `jq -r` pipeline instead.
- **Whole-run vs job-scoped logs.** The zot probe keeps `gh run view --job <jid> --log` (single job — identical to 10585). The rehearsal collector keeps `gh run view <id> --attempt N --log` (whole run): the region derivation is preceded by a field-1 job-name filter — the ONE new mechanism versus both prior ports, and it exists because sibling job sections share the file. Pinned assumption: field-1 job attribution survives step-name expiry (only field 2 goes `UNKNOWN STEP`); if it ever expires too, `step_region` returns rc 2 → UNREAD — still loud, never counterfeit.
- **Step-prefix uniqueness.** Across `git-data-cutover.yml`'s two jobs (`cutover`, `wipe`), each graded prefix (`Finalizer`, `Positive replication probe`, `Per-host git_data_store=`, `Host-side proof`, `Host-side refs assertion`) resolves to at most one running step per graded run — `wipe` is skipped on cutover-mode runs and its steps never reach the file the prefix selects. `step_region` takes the first match by prefix, documented as a residual if a future workflow reuses a prefix across jobs.
- **Conclusion-agnostic recovery (zot).** Recovery runs whenever the trail step ran, matching the probe's existing any-conclusion grading (a DARK `web_host_replace` failure job is the FAIL arm — its aged trail must recover identically).
- **Carried residuals (inherited from 8178/11603, stated not solved):** a `::group::` annotation title literally beginning `Run ` can false-bound a region; sub-second skew between the API `startedAt` and the header stamp can select an adjacent region — loud on paths that require evidence (TRANSIENT/UNREAD), silent-best-effort on paths that already accept absence.
- **Fixture fidelity (the 8178 suite's own scar tissue):** both suites' UNKNOWN STEP generators must reproduce gh's real document shape — a BARE `Set up job` first section, BOM'd `##[group]Run` headers on every later section, a prelude section stamped BEFORE the step's `startedAt` (the `ts >= ps` gate needs something to skip AND provides the second BOM that pins the global strip), payload lines, and a bounding next-step header. The rehearsal fixtures additionally model multi-job whole-run logs (two job sections in one `log-<id>.txt`).
- **Fixture deltas:** the zot suite's `job()` currently emits no `steps` array — it gains one (`startedAt`/`completedAt`/`conclusion` on the trail step; `startedAt: null` → `-` for the absent arm). The rehearsal suite's `run-<id>.json` fixtures already carry `steps[]` (consumed by `stepc`/`stepts`) — they gain `startedAt` only where recovery is exercised.
- **Exit vocabulary preserved.** The zot probe keeps {0,1,2,3,78} with `TRANSIENT:` on 3; the rehearsal collector keeps {0,3,64,78} with `UNREAD(<token>)` fields — no new verdict words, no sweep-contract change.
- NFR impacts: none — read-path changes to two read-only collectors; no credential, egress, or write surface changes (both scripts' xtrace refusals, credential scoping, and read-only postures are untouched).

## Files to Edit

- `scripts/followthroughs/web-fresh-boot-zot-8651.sh` — jobs jq gains step `conclusion`+`startedAt` (`:51-53`); designed-absence `continue`; BOM/CR strip after log fetch (`:55`); `emit_content` shared filter replacing the inline `grep -v $'^\e'` (`:58-59`); `##[group]Run` region-slice recovery block; post-recovery tripwire on success jobs; header comment (`:1-28`).
- `scripts/followthroughs/web-fresh-boot-zot-8651.test.sh` — `job()` gains a `steps` array with `startedAt`/`conclusion` (`:53-55`); `GH_LOG_BOM` + `ul()`/`ulog()` UNKNOWN STEP builders (idiom per `web-first-deploy-10585.test.sh:145-183`); new cases per Test Scenarios; `MIN_CASES` floor bump (`:101`).
- `scripts/followthroughs/git-data-rehearsal-evidence.sh` — `fetch_run` global BOM/CR normalization (`:170`); `step_region` helper (new, after `lfirst` ~`:207`); `lcount`/`lfirst` signature to `<slot> <prefix> <regex>` + two-phase named/region evaluation (`:201-207`); call-site updates (`:261-262,275,304,441-442`); `refs_msgs` two-phase (`:484-485`); header comment (`:196-199`).
- `scripts/followthroughs/git-data-rehearsal-evidence.test.sh` — `run-<id>.json` fixture builders gain `startedAt` on the anchored steps; UNKNOWN STEP `log-<id>.txt` builders (multi-job whole-run shape; `GH_LOG_BOM`-equivalent + region headers); new cases per Test Scenarios; floor bump.
- `knowledge-base/engineering/operations/runbooks/followthrough-convention.md` — extend the §"Sharp edges for `gh run view --log` probes" bullet (`:321-334`) so the countermeasure names all three consumers (10585 + both siblings) and notes the whole-run-log job-scoping variant.

## Files to Create

None.

## Open Code-Review Overlap

None — queried open `code-review` issues (2026-11-01, `--limit 200`) for `scripts/followthroughs/web-fresh-boot-zot-8651.sh`, `scripts/followthroughs/git-data-rehearsal-evidence.sh`, both `.test.sh` siblings, and `followthrough-convention.md`: zero bodies name them.

## User-Brand Impact

- **If this lands broken, the user experiences:** no direct end-user artifact — worst case is an ops-facing probe still misreading aged logs: the zot probe printing "no web-2 run" over a proven replace, or the rehearsal collector certifying `unwound no`/`not seen` readings it never made, degrading an internal evidence block a CPO review consumes.
- **If this leaks, the user's [data / workflow / money] is exposed via:** nothing new — both scripts read CI logs and jobs-API responses they already read; no new credential, store, egress, or write path.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** the blast radius is internal ops tooling and an owner-run evidence block; no user-facing page, customer data, or money path is touched, so the next tier up does not apply.

## Observability

The changed surfaces ARE observability tooling; each probe's own health signal is its verdict output.

```yaml
liveness_signal:
  what:            # the probes' verdict outputs — zot: sweeper verdict word on its tracker when enrolled; rehearsal: the printed evidence block's UNREAD token count
  cadence:         # zot: daily when enrolled (dormant since ~2026-10-14 — tracker #8651 closed >14d); rehearsal: owner-invoked
  alert_target:    # zot: tracker comment thread; rehearsal: the evidence block consumed by the CPO sign-off review
  configured_in:   # zot: issue #8651 `<!-- soleur:followthrough -->` directive (closed; retired); rehearsal: owner CLI invocation
error_reporting:
  destination:     # zot: tracker comment; rehearsal: UNREAD(<token>) block fields + stderr token lines
  fail_loud:       # a degraded channel names the recovery cause — zot exits 3 TRANSIENT with the cause; rehearsal prints UNREAD(...) never a counterfeited zero
failure_modes:
  - mode:          # attribution expiry (this fix's target)
    detection:     # recovered region grades by content; failed recovery = TRANSIENT cause / UNREAD token
    alert_route:   # tracker comment / evidence block
  - mode:          # designed absence (plan_only, skipped or never-added step)
    detection:     # continue / legitimate-zero path preserved — no false tripwire, no false UNREAD
    alert_route:   # n/a (not a failure)
  - mode:          # genuinely missing or failed evidence
    detection:     # unchanged verdict paths on measured content (exit 1/2 zot; NOT CONFIRMED/UNREAD rehearsal)
    alert_route:   # tracker comment / evidence block
logs:
  where:           # sweeper run log + tracker comments (zot); owner terminal + the saved evidence block (rehearsal)
  retention:       # GitHub Actions log retention; issue comments; the committed evidence block
discoverability_test:
  command:         grep -n 'startedAt' scripts/followthroughs/web-fresh-boot-zot-8651.sh scripts/followthroughs/git-data-rehearsal-evidence.sh
  expected_output: startedAt
```

## Guard Contract

The deliverable modifies assertion-based controls — both probes' log-parse pipelines and the fixture suites that drive them.

### Guard 1 — zot attribution-tolerant trail read + post-recovery degraded-channel tripwire

**Property.** For every non-skipped `web_host_replace`/`web_host_create` job in the scanned window, the probe either grades that job's trail-step output — by step-name attribution when present, else by the `##[group]Run` region keyed on the step's `startedAt` after the global BOM/CR strip — or, when the job concluded success and the step ran, exits `TRANSIENT` (3); it never reads an attribution-expired proven trail as "no run" and never tripwires a step that did not run.

**Assembly.** Two chokepoints: (a) the probe's single parse pipeline in `web-fresh-boot-zot-8651.sh:48-86` — jobs jq (now carrying step conclusion + `startedAt`), log normalization, named-step anchor, region-slice recovery, shared `emit_content`, the `${HOST_KEY}` pointer gate, the post-recovery tripwire — every trail line flows through it; (b) the suite's `gh` stub + `ul()`/`ulog()` UNKNOWN STEP document generator in `web-fresh-boot-zot-8651.test.sh` — every aged document the property is tested against flows through it.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Delete the region-slice recovery | RED — UNKNOWN STEP fixtures fall to the tripwire/continue instead of grading PASS/FAIL |
| 2 | Weaken the BOM strip to single-replacement (`${log/…/}`) | RED — the fixture's second BOM'd header keeps its mark; `^[0-9]` misses it; region empty (own-normalization row) |
| 3 | Drop the `ts >= ps` gate | RED — the prelude section stamped before `startedAt` is selected instead of the trail step's (order/lifetime row) |
| 4 | Consume the region around `emit_content` | RED — the ANSI-echoed pointer inside the region enrolls a boot that was never emitted |
| 5 | Evaluate the tripwire pre-recovery | RED — every recoverable UNKNOWN STEP fixture exits 3 instead of grading (own-dispatch row) |
| 6 | Remove the tripwire (unrecoverable success job → `continue`) | RED — a degraded channel reads NOT YET quietly |
| 7 | Gate recovery on `jcon == "success"` | RED — the failure-job DARK-trail fixture exits 2 instead of FAIL 1 (second-member/conclusion row) |
| 8 | Harness: `job()` stops emitting `steps[].startedAt` | RED — every recovery fixture takes the no-`startedAt` arm; the suite can never certify the path it exists for |
| 9 | Must-PASS non-canonical: trail step is the log's LAST section (no bounding header) | PASS — the EOF-terminated region still grades |
| 10 | Designed-absence must-PASS: trail step conclusion `skipped` (plan_only) | PASS — `continue`, no tripwire, NOT YET as today |

### Guard 2 — rehearsal per-(slot, step) re-attribution preserving failed-read ≠ zero

**Property.** For every (slot, step-prefix) log read, the collector produces the step's measured count/timestamp/message — by step-name attribution when present, else by that step's job-scoped `##[group]Run` region re-attributed through the identical anchored awks — or reports `UNREAD(<token>)`; a step that ran but cannot be sliced never counterfeits a measured zero, and a step that did not run never invents an UNREAD.

**Assembly.** (a) `fetch_run`'s one-time file normalization; (b) `step_region` + the three anchored awk sites (`lcount`, `lfirst`, the `refs_msgs` extraction) — every log-line match flows through the single `index($2, st) == 1 && $3 ~ re` chokepoint whether the input is the fetched log or a re-attributed region file; (c) the suite's `gh` shim + `log-<id>.txt` UNKNOWN STEP whole-run fixture shape.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Drop the `step_region` fallback (named-0 stays a silent 0) | RED — the attribution-expired Finalizer fixture prints `unwound no` instead of its true unwind line — the false-healthy shape this guard exists to kill |
| 2 | `step_region` slices without the field-1 job-name pre-filter | RED — the fixture carrying a same-named `##[group]Run` header in a sibling job's section opens the wrong region (second-member row) |
| 3 | Skip the global normalization (or single-strip) | RED — BOM'd headers miss `^[0-9]`; region empty → rc 2 UNREAD on a healthy-aged fixture (own-normalization row) |
| 4 | The rc-2 arm returns 0/empty instead of failure | RED — a degraded channel counterfeits a measured zero |
| 5 | `step_region` treats a `skipped` step as degraded (rc 2) | RED — the designed-absence fixture reads UNREAD where today it reads a legitimate zero |
| 6 | Region lines parsed by a second, divergent awk instead of re-attribution through the shared one | RED — the copy accepts a line the shared awk's anchored `~ re` would reject — a phantom count on a fixture carrying a near-miss decoy |
| 7 | Order/lifetime: drop the `ts >= ps` gate | RED — an earlier section stamped before `startedAt` is selected → region holds another step's lines → wrong count |
| 8 | Harness: `run-<id>.json` fixtures stop emitting `startedAt` on anchored steps | RED — all recovery cases take the did-not-run/unrecoverable arm; the suite cannot certify the path |
| 9 | Must-PASS non-canonical: a recovered region yields a genuine measured zero (step ran, emitted nothing matching) | PASS — 0 returned, no UNREAD — measured zero ≠ failed read, in the recovery direction too |

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "Same as #11600's merged fix: jobs-API `started_at` for the parsed step, global BOM/CR strip, `##[group]Run` region-slice recovery behind the named anchor, shared emit-filter, tripwire evaluated post-recovery." [issue #11607] | Proposed Solution §both probes; `web-fresh-boot-zot-8651.sh` + `git-data-rehearsal-evidence.sh` edits; AC-1..AC-7 | mapped |
| 2 | "Whether each probe's population window can actually span the attribution boundary (~2-3 wk) — a probe that only reads runs < 2 weeks old may never hit this in practice; check its lookback before porting." [issue #11607] | Re-evaluation section (both span conclusions + census); AC-11 | mapped |
| 3 | "The fixture idiom is in `web-first-deploy-10585.test.sh` (`GH_LOG_BOM`, `ul()`/`usrc()`/`ulog()`), itself modeled on `git-data-boot-poll-8178.test.sh`." [issue #11607] | Both `.test.sh` edits; AC-8 | mapped |
| 4 | "`scripts/followthroughs/web-fresh-boot-zot-8651.sh` — `index($2, …)` at its log parse (~line 58)" + "`scripts/followthroughs/git-data-rehearsal-evidence.sh` — `index($2, …)` at its log parse (~lines 196-200)" [issue #11607] | Both probe edits (anchors confirmed at `:58` and `:202,206,485` — the issue's `~196-200` understates the count, three sites) | mapped |
| 5 | "CLOSE #11609 — a decision-challenge recorded when these sibling fixes were deferred out of PR #11603 to #11607; this batch PR is its discharge — the PR body closes it (Closes #11609 on its own line). No code change for it." [batch brief] | AC-10; tasks phase 4 PR-body item | mapped |
| 6 | "#11583 is a PERMANENTLY-OPEN standing watchdog tracker for web-first-deploy-10585.sh — its body says "don't close it"; carry as CONTEXT ONLY, never a Closes #11583 line." [batch brief] | AC-10 negative clause; Overview | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `web-fresh-boot-zot-8651.sh` recovery + normalization + emit-filter + tripwire | asks 1, 4 (quoted above) | asked |
| `git-data-rehearsal-evidence.sh` normalization + `step_region` + two-phase awks | asks 1, 4 (quoted above) | asked |
| Both `.test.sh` UNKNOWN STEP fixture suites | ask 3 (quoted above) | asked |
| Re-evaluation section | ask 2 (quoted above) | asked |
| `job()`/`run-<id>.json` fixture `startedAt` gains | — | inferred — justification: the asked mechanism anchors the region "on the step's `started_at`"; the fixture must carry the field for the probe's own jq to select it (same inference the sibling plan recorded) |
| `followthrough-convention.md` bullet update | — | inferred — justification: the countermeasure bullet names which probes carry the adaptation; leaving it citing only `web-first-deploy-10585.sh` after two more conform misleads the next probe author about coverage |
| Job-name pre-filter inside `step_region` | — | inferred — justification: the rehearsal collector reads whole-run logs (multiple job sections per file) unlike both `--job`-scoped prior ports; without it a sibling job's `##[group]Run` header can open the wrong region — required by the asked mechanism's correctness on this consumer |
| `TRANSIENT:`-prefixed tripwire in the zot probe | ask 1 "tripwire evaluated post-recovery" | asked |

### Split Assessment

- Subsystems touched: 2 — `scripts`, `knowledge-base`
- Planned files: 5 | Estimated changed lines: ~450
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] AC-1: A faithful aged (`UNKNOWN STEP`) log on the newest web-2 `web_host_replace` SUCCESS job carrying emitted pointer + `stage=app_zot` + `zot_login=ok` + `fresh_boot_ready` exits 0 PASS through the recovered region — never falls through to `exit 2` "no run".
- [ ] AC-2: Aged `UNKNOWN STEP` logs carrying pointer + DARK, pointer + timeout, or pointer + `stage=app_ghcr_served` on the newest web-2 job exit 1 FAIL through recovery — the failure-job arms grade identically on either attribution mode.
- [ ] AC-3: A success-conclusion job whose trail step RAN but is unrecoverable — region holds no trail-pattern lines, no `##[group]Run` header at/after `startedAt`, or no `startedAt` — exits 3 with the `TRANSIENT:` prefix and a message naming the recovery cause; evaluated AFTER recovery.
- [ ] AC-4: A job whose trail step conclusion is `skipped` (plan_only create) or `absent` takes the designed-absence `continue` → exit 2 NOT YET — no new tripwire on a step that never ran; pre-existing absent-step runs behave identically.
- [ ] AC-5: A recovered region whose pointer/ready text appears only as ANSI-prefixed echoed `run:` source is not graded — the #9905 emitted-vs-echoed boundary holds inside regions (NOT YET mirror of the existing decoy case).
- [ ] AC-6: Attribution-expired rehearsal fixtures yield measured readings per slot: flip → `finalizer ran yes (unwound yes)` (or the fixture's true unwind state) + flag-write stamp step; rollback → `STORE probe=probe verdict=ok` `seen`; exit/proofbefore → `clear`/`store_not_empty` verdicts; refs → `REFS-CONFIRMED yes` — each via its job-scoped recovered region in a multi-job whole-run log.
- [ ] AC-7: A step that ran but cannot be recovered reads `UNREAD(<token>)` — never `unwound no`, never `not seen`, never a printed `0` for a failed read; a `skipped`/absent step keeps the pre-change legitimate-zero/absent reading.
- [ ] AC-8: Both suites' UNKNOWN STEP generators reproduce gh's real aged-document shape — `UNKNOWN STEP` in field 2, a bare first section, BOM'd `##[group]Run` headers on later sections, a prelude section stamped before `startedAt` the `ts >=` gate must skip, a bounding next-step header, and (rehearsal) multiple job sections in one whole-run log; at least one fixture per suite exercises emitted-vs-ANSI-echoed content inside a recovered region.
- [ ] AC-9: All pre-existing cases stay green in both suites; assertion floors (`MIN_CASES` in the zot suite, the rehearsal suite's floor) bump to the new baselines; `scripts/test-all.sh` rows for both suites green; `scripts/suite-durations.tsv` unchanged (no new row needed — additive cases inside existing floors).
- [ ] AC-10: The PR body carries `Closes #11607` and `Closes #11609`, each on its own line; the string `Closes #11583` appears nowhere in the PR title, body, or commit messages (#11583 referenced as plain context only, e.g. `Refs #11583` or unlinked mention).
- [ ] AC-11: The Re-evaluation conclusions (both windows span; zot currently dormant, exposure latent-total; rehearsal owner-invoked, span-by-construction) are restated in the PR body or posted as a comment on #11607, so the issue's lookback criterion is visibly answered, not just implemented.
- [ ] AC-12: `followthrough-convention.md` §"Sharp edges for `gh run view --log` probes" names all three consumers of the countermeasure and the whole-run-log job-scoping variant.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — internal tooling change on existing ops surfaces: the Engineering assessment question does not fire on porting an already-merged technique to sibling consumers of the same parse pattern; Product has no user-facing surface (no Files entry matches the UI-surface glob superset); Marketing/Sales/Support/Legal/Finance/Operations have no content, pipeline, document, budget, or vendor surface in this diff.

## Test Scenarios

All scenarios are `unit`-layer fixture cases in the two suites' PATH-stubbed/seam-stubbed harnesses.

**`web-fresh-boot-zot-8651.test.sh`:**

- Given an `UNKNOWN STEP` success-job log (faithful shape: bare head, BOM'd prelude before `startedAt`, BOM'd trail-step `##[group]Run` at `startedAt`, payload, bounding header) carrying pointer + zot origin + ready, when the probe runs, then it exits 0 PASS (AC-1).
- Given the same aged shape carrying pointer + `##[error]…booted DARK` on a failure job, when the probe runs, then exit 1 FAIL (AC-2, conclusion-agnostic recovery).
- Given a success job whose `UNKNOWN STEP` region holds zero trail-pattern lines — and a variant with no `##[group]Run` header at/after `startedAt` — when the probe runs, then both exit 3 `TRANSIENT:` naming the cause (AC-3).
- Given a success job whose jobs-JSON trail step lacks `startedAt` (`null` → `-`), when the probe runs, then exit 3 `TRANSIENT:` — unbounded is unmeasured (AC-3).
- Given a job whose trail step conclusion is `skipped`, when the probe runs, then `continue` → exit 2 NOT YET (AC-4, matrix row 10).
- Given an `UNKNOWN STEP` region containing only ANSI-echoed pointer/ready copies, when the probe runs, then no pointer is credited → NOT YET (AC-5, matrix row 4).
- Given the trail step as the log's LAST section (no bounding header), when the probe runs, then the EOF-terminated region still grades (matrix row 9).
- Property: every driven path exits in {0,1,2,3,78}; the `MIN_CASES` floor bumps to the new baseline.

**`git-data-rehearsal-evidence.test.sh`:**

- Given an attribution-expired flip `log-<id>.txt` (multi-job whole-run shape, UNKNOWN STEP field 2) whose `Finalizer` region emits the unwind-complete line, when the collector runs, then the block reads `finalizer ran yes (unwound yes)` — not `unwound no`, not UNREAD (AC-6).
- Given attribution-expired rollback/exit/refs logs, when the collector runs, then probe `seen`, verdict `clear`, `REFS-CONFIRMED yes` — each measured through the recovered region (AC-6).
- Given an attribution-expired log whose step's region cannot be sliced (no `##[group]Run` header at/after `startedAt`, or no `startedAt`), when the collector runs, then the field reads `UNREAD(<token>)` and exit 3 — never a silent zero or a false-healthy line (AC-7, matrix row 4).
- Given a step conclusion `skipped` (or a step absent from the jobs JSON), when the collector runs, then the pre-change legitimate-zero/absent reading is preserved — no invented UNREAD (AC-7, matrix row 5).
- Given a whole-run fixture carrying a same-prefixed `##[group]Run` header in a DIFFERENT job's section, when recovery runs, then the job-name pre-filter selects only the step's own job's region (AC-6, matrix row 2).
- Given a recovered region that genuinely emits zero matching lines, when the collector runs, then a measured 0 — no UNREAD (matrix row 9 must-PASS).
- Property: all pre-existing cases green; the suite's floor bumps to the new baseline.

## Success Metrics

- `bash scripts/followthroughs/web-fresh-boot-zot-8651.test.sh` and `bash scripts/followthroughs/git-data-rehearsal-evidence.test.sh` report 0 failures with the new UNKNOWN STEP cases; `scripts/test-all.sh` rows for both suites green.
- On merge, #11607 and #11609 close via the PR body; #11583 remains open.
- Post-merge live behavior: no sweep-visible change on the zot probe (dormant — its correctness now holds for any re-enrollment); the next owner run of the rehearsal collector against aged rehearsal logs produces real readings instead of counterfeit zeros/UNREAD spray.

## Dependencies & Risks

- **`startedAt` availability:** `gh run view --json jobs` returns `.jobs[].steps[].startedAt` (camelCase) — verified in the fixture shape; absent → the `// "-"` arm → designed-absence or degraded paths (loud where evidence is required).
- **Zot probe dormancy:** the probe's tracker retired ~2026-10-14 — the fix is latent-only until any re-enrollment. Alternative considered: retire (delete) the probe instead of fixing it — rejected: #11607 names it for the port, the script documents #8651's evidence contract, and a manual re-run would hit the expired window immediately.
- **Rehearsal port is the adapted arm:** whole-run logs, five slots, five prefixes, file-based consumers — the region derivation is verbatim but the delivery (job-scoped slice → re-attributed region file → shared awks) is this script's own shape; the extra mechanism is named in the diff, not hidden.
- **Carried residuals (inherited, stated):** `##[group]Run`/`::group::` title-collision false-bound; `startedAt`/header sub-second skew (loud on evidence-required paths, silent-best-effort elsewhere); field-1 job attribution assumed to survive expiry (fixture-pinned; worst case is rc-2 UNREAD — loud).
- **Transient log fetches** (the #11600 plan's phantom zero-line read class) are a separate, non-deterministic failure mode this fix does not claim to solve.
- **Fixture-fidelity risk (the 8178 scar):** a lone-BOM or prelude-less fixture leaves the global strip and the `ts >=` gate unpinned — the generator shape is an AC (AC-8), not a nicety.

## Research Insights

**Premise Validation (Phase 0.6).** Verified 2026-11-01: #11607 OPEN (`followthrough probes: two siblings share the UNKNOWN STEP attribution-expiry exposure (#11600 class)`); #11609 OPEN (decision-challenge for the deferral this PR discharges); #11583 OPEN standing watchdog whose body says "don't close it" — context only; #11600 CLOSED by PR #11603, MERGED as squash 26ec69c3, which `git merge-base --is-ancestor` confirms is on this branch. Both `index($2, …)` anchors verified in place: `web-fresh-boot-zot-8651.sh:58`, `git-data-rehearsal-evidence.sh:202,206,485`. The countermeasure runbook section exists at `followthrough-convention.md` §"Sharp edges for `gh run view --log` probes" (lines 319-334). Fixture idiom verified at `web-first-deploy-10585.test.sh:145-183` (`GH_LOG_BOM`, `ul()`, `ulog()`) and `git-data-boot-poll-8178.test.sh:122-197`. Collision precheck: PR #11786 is THIS branch's own auto-created draft (2026-11-01); the foreign `test-all.sh` process belongs to the unrelated `feat-one-shot-11771-ratchet-baseline` worktree. Nothing stale.

**Property List (Phase 0.6b).** (P1) An attribution-expired job log grades by its content on both siblings — never a silent empty/misread trail; (P2) a step that ran but cannot be recovered (no `started_at`, no `##[group]Run` header at/after it) reads CANNOT ESTABLISH/UNREAD — a degraded channel is measurable, never a quiet pass; (P3) a step that did not run (skipped, plan_only) keeps today's designed-absence semantics — no new tripwire on legitimate zeros; (P4) the emitted-vs-echoed (#9905 ANSI) boundary holds inside recovered regions via one shared filter path; (P5) the fixture suites pin all of the above against a faithful UNKNOWN STEP document shape (BOM per section, pre-`started_at` prelude, region bound); (P6) #11609 is discharged by the PR body; #11583 is never named by a `Closes` line; (P7) #11607's re-evaluation is honored: each probe's lookback conclusion is documented before the port.

**Cut List (Phase 0.6b).** The issue prescribes the merged #11600 fix shape verbatim (jobs-API `started_at`, global BOM/CR strip, `##[group]Run` region slice, shared emit-filter, post-recovery tripwire) — the mechanism is already on `origin/main` at `web-first-deploy-10585.sh` and `git-data-boot-poll-8178.sh:202-209`; no alternative mechanism was proposed or needed. Nothing cut. One scope boundary stated, not cut: `git-data-rehearsal-evidence.sh` is owner-run, not sweeper-enrolled, so its "tripwire" is the collector's own *failed-read ≠ zero* contract (UNREAD tokens), not an exit-3 sweep verdict — the port preserves that contract rather than grafting the 10585 exit vocabulary onto it.

**Relevant file paths.** `scripts/followthroughs/web-fresh-boot-zot-8651.sh:44-86` (run list → `gh run view --json jobs` → log fetch → `index($2, step)` trail parse `:58` → pointer gate `:60` → verdicts); `scripts/followthroughs/web-fresh-boot-zot-8651.test.sh` (`gh` stub `:28-42`, `job()`/`l()`/`src()` fixtures `:44-55`, `MIN_CASES` floor `:101`); `scripts/followthroughs/git-data-rehearsal-evidence.sh:154-175` (`fetch_run` — `gh run view --attempt N --log` writes `${WORK}/<slot>.log`, jobs JSON already fetched into `<slot>.json`), `:196-207` (`LOG_TS`/`lcount`/`lfirst` — the `index($2, st) == 1` anchor), `:261-262,275` (Finalizer/probe lcount calls), `:302-306` (`host_ts`→`lfirst`), `:437-447` (`proof_verdict`), `:474-495` (refs read), `:485` (refs_msgs awk); `scripts/followthroughs/git-data-rehearsal-evidence.test.sh` (`gh`/`curl`/`bsq` shims, `run-<id>.json` + `log-<id>.txt` fixtures); reference implementations `web-first-deploy-10585.sh:217-345` post-fix and `git-data-boot-poll-8178.sh:166-213`; `.github/workflows/git-data-cutover.yml` (jobs `cutover`/`wipe` — step prefixes unique per graded run); `knowledge-base/engineering/operations/runbooks/followthrough-convention.md:319-334`.

**Institutional learnings.** `2026-09-18-the-measured-facts-my-resume-brief-handed-me-were-the-defects.md` (the 8178 BOM/region story — a fixture without the BOM tested a shape gh never emits); `2026-09-27-a-log-line-is-evidence-about-the-step-that-printed-it.md` (attribute log lines to their `##[group]Run` step); `2026-10-10-a-log-scraping-probe-matched-the-script-it-echoed…md` (the #9905 echoed-source trap — the ANSI filter must apply inside recovered regions); `2026-10-15-dormant-followthrough-probe-is-not-a-standing-detector.md`; `followthrough-convention.md` §"Sharp edges for `gh run view --log` probes" (the countermeasure this plan ports); the archived plan `knowledge-base/project/plans/archive/20261030-120202-2026-10-30-fix-web-first-deploy-step-attribution-plan.md` (the sibling's Guard Contract, Scope Check and fixture-fidelity reasoning — this plan's structural template).

**Related issues/PRs.** #11607 (Closes — this batch), #11609 (Closes — decision-challenge discharge), #11583 (standing watchdog, context only, NEVER `Closes`), #11600 (closed by #11603 — the fix being ported), #11603 (merged reference diff 26ec69c3), #8178/#8262 (technique origin), #9905 (ANSI-echo trap), #8651 (zot probe's tracker — closed 2026-09-30, probe dormant), #8211 (rehearsal collector's CPO condition), #11431 (refs_assert arm), #7797 (xtrace refusal).

**Research decision (Phase 1.6).** External research skipped — the plan ports an in-repo, twice-merged technique onto sibling consumers of the same log shape; every behavioral fact is repo-measured. Community discovery: no uncovered stacks (bash/jq internal tooling). Functional-overlap agent spawn unavailable in this environment — skipped per the check's never-block clause.

**Research Reconciliation — Spec vs. Codebase.** No spec.md exists for this branch (one-shot pipeline entered at plan); all claims verified against the worktree (which carries 26ec69c3). Two claim refinements versus the issue's "same fix shape" phrasing: (a) `web-fresh-boot-zot-8651.sh` reads jobs via `gh run view --json jobs` (embedded, camelCase `startedAt`) — NOT the `gh api …/jobs` REST call the 10585 probe uses (snake_case `started_at`) — the extraction is adapted, not copied; (b) `git-data-rehearsal-evidence.sh` reads WHOLE-RUN logs (`gh run view <id> --attempt N --log`) into scratch files and anchors five distinct step prefixes across five slots — its recovery is a per-(slot, step-prefix) region re-attribution feeding the unchanged `lcount`/`lfirst`/refs awks, not a single-trail substitution. A third: the issue's `~lines 196-200` understates the rehearsal anchor count — `index($2, …)` sits at `:202,206,485` (three awk sites over five step prefixes).

**Mode note.** Headless/pipeline context (one-shot Task subagent, no TTY, no agent-spawn tool): idea-refinement, founder check, advisor consult, domain-leader and plan-review panels were adjudicated inline by the orchestrator — `Reviewed-Coverage: sequential-fallback`; decisions persisted to `knowledge-base/project/specs/feat-one-shot-11607-11609-11583-sibling-probes/decision-challenges.md`.

## References & Research

- Similar implementations: `scripts/followthroughs/web-first-deploy-10585.sh:217-345` (post-#11603 reference diff, squash 26ec69c3), `scripts/followthroughs/git-data-boot-poll-8178.sh:166-213` (technique origin); fixture idiom `web-first-deploy-10585.test.sh:145-183`, `git-data-boot-poll-8178.test.sh:122-197`
- Runbook: `knowledge-base/engineering/operations/runbooks/followthrough-convention.md` §"Sharp edges for `gh run view --log` probes" (`:319-334`)
- Precedent plan: `knowledge-base/project/plans/archive/20261030-120202-2026-10-30-fix-web-first-deploy-step-attribution-plan.md`
- Related issues: #11607 (Closes), #11609 (Closes), #11583 (context only — standing watchdog, never `Closes`), #11600, #10585, #8178, #9905, #8651, #8211, #11431, #7797
- Related PRs: #11603 (merged reference), #11786 (this branch's draft PR)
