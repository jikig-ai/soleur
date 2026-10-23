---
title: "fix: rehearsal skip monitor streak state must survive Actions cache eviction"
type: fix
date: 2026-10-23
slug: rehearsal-skip-monitor-streak-persistence
branch: feat-one-shot-rehearsal-skip-monitor-streak-cache
issue: none
pr: 10916
closes: none
related_issues: [10917, 10918, 8856, 7574, 7672]
lane: cross-domain
brand_survival_threshold: none
---

# fix: rehearsal skip monitor streak state must survive Actions cache eviction

## Overview

The daily rehearsal skip monitor (`.github/workflows/scheduled-rehearsal-skip-monitor.yml`) carries a
consecutive-TRANSIENT counter across runs. It persists that counter in the GitHub Actions cache, and its
"Assert the streak state round-trips" step exits non-zero when no prior generation is restored. That step
is red on most days (of the last 30 daily runs, the assert step was green on 4: 2026-09-27, 10-03, 10-17,
10-22).

This plan establishes the cause by measurement (Research Insights below), then moves the counter to a
workflow artifact, which the cache quota cannot evict, and rewrites the round-trip assertion so that a
broken round-trip still fails loudly. The over-cap release cache is a separate, production-affecting
problem and is tracked in #10917 rather than patched here.

Spec lane: no `spec.md` exists for this one-shot branch, so `lane:` defaulted to `cross-domain` (fail-closed
default per the plan skill).

## Enhancement Summary

**Deepened on:** 2026-10-23. **Agents/sources:** CTO (architecture ruling), learnings-researcher, plan-review
panel (DHH, Kieran, code-simplicity), SpecFlow analyzer, security-sentinel, Context7
(`actions/upload-artifact`), live `gh api` measurements, deepen-plan gates 4.6-4.12 (all pass).

### Key improvements from deepening
1. **Fork-safe selection (security P0).** Artifacts are repository-scoped, not ref-scoped; a fork PR run is
   listed with a fork-controlled `head_branch`. `fetch` now also requires `head_repository_id ==
   repository_id == $GITHUB_REPOSITORY_ID`, size at most 4096 bytes, exact member name `streak`, and never
   logs raw artifact content (workflow-command injection).
2. **No permanent wedge (SpecFlow P0).** A corrupt or poisoned newest artifact is discarded under
   `bootstrap=true` (restoring the reseed path the simplicity pass had cut); a failed LISTING is never masked.
3. **Re-run correctness.** Selection is by `workflow_run.id` below the current run, so a re-run of an older
   run reads its predecessor and cannot outrank a newer run's state; pagination added.
4. **Verdict-aware `seal`, upload gated on `seal`, `fetch` and the main ref; probe wrapped in `timeout 600`.**
5. Verified: `actions/upload-artifact` v4.4+ excludes hidden files by default (hence the non-hidden state
   path), a single-file `path` yields an archive member named by basename (`streak`), `overwrite: true`
   replaces the same-name artifact, `retention-days` maximum is 90 unless the repo setting differs.

### New considerations discovered
- The existing probe suite asserts the probe CLEARS the streak file on a real verdict
  (`t5-skip-persistence-bound-7510.test.sh` lines 215-227), which is why the clearing stays in the probe and
  `seal` normalises afterwards.
- The first reliable escalation will be filed under the real-skip alert title (pre-existing); follow-up issue
  #10918 filed.
- Residuals accepted and recorded under Dependencies and Risks (cancelled run, stale value after a red fetch
  day, no age bound).

## Research Reconciliation — Brief vs. Codebase and Measurement

| Brief / PR #10846 claim | Reality (measured 2026-10-23) | Plan response |
|---|---|---|
| "the cause of the eviction is not established" (PR #10846 body) | Established. Nine-tenths of the quota (9.6 of 10.23 GB) is `buildkit-blob-1-sha256:*` written by `reusable-release.yml` (`cache-to: type=gha,mode=min`); 8.68 GB of it was written on 2026-10-23 alone by 7 release exports. GitHub evicts least-recently-accessed first, so a 192-byte entry read once a day always loses. | Fix the carrier (artifact), file the release churn as #10917. |
| "about 12.3 GB in use" | `actions/cache/usage` returned 10,231,817,250 bytes (10.23 GB), 178 entries, today. The 12.3 GB figure was a transient peak before eviction; the cap is enforced by eviction, so usage hovers just over 10 GB. | Cite the current number; the conclusion (over cap) holds. |
| "whether this monitor's own per-run keys accumulate" | They do not. 2 entries / 391 bytes in total (runs #59 and #60 of today); every earlier generation was already evicted. | Rules out the self-inflicted-accumulation hypothesis. |
| "whether PR-ref caches or other workflows fill the quota" | Zero PR-ref caches: all 179 entries are `refs/heads/main`. Only the release export fills it. node-cache npm is 0.48 GB, codeql-trap 0.12 GB. | Rules out PR-ref fill. |
| "the assert step exits non-zero when RUN_NUMBER > 1 and no prior generation was restored" | True, but the cached payload is a 192-byte tarball of an EMPTY directory in the steady state: the probe `rm -f`s the streak file on every real (pass/fail) verdict, so the round-trip being asserted carries no information unless the previous run was TRANSIENT. | New design always stores an explicit numeric value (`0` when cleared), so absence is unambiguous loss. |
| "the job stops being red" | Today's two runs (#59, #60) also went red at `Report verdict`, because the probe legitimately returned `FAIL: 1 loud rehearsal skip(s) across 1 observed post-merge run(s)` (alert issue #8856 is open). That is a true positive from the just-merged relay, not a cache artefact. | Acceptance is stated on the conclusion of the assert step, not the job; the real FAIL stays red by design. |
| "the repo-wide artifact list is a usable store index" | `gh api repos/jikig-ai/soleur/actions/artifacts?per_page=N` returned `unexpected end of JSON input` twice from this repository. The exact-name filter (`?name=…`) works (246 `release-outputs-web-platform` rows returned). | Fetch uses the exact-name filter only; no prefix scan. |

## Research Insights

### Premise Validation

Checked: PR #10846 is MERGED (2026-10-23T10:28:56Z) and its body carries the "Known limitation (not
filed)" paragraph; #7574 and #7672 (the original streak-cache follow-through) are CLOSED; the alert issue
#8856 is OPEN; draft PR #10916 is OPEN. Cited paths all exist on `origin/main`: the workflow,
`scripts/followthroughs/t5-skip-persistence-bound-7510.sh` (counter at `T5_PROBE_STATE`, `_transient`,
`_clear_transient_streak`), `scripts/followthroughs/monitor-streak-cache-roundtrip-7574.sh`. ADR corpus grep
for the mechanism (artifact vs cache vs issue vs variable): no ADR rejects an artifact-based store; ADR-188
only names the workflow as the probe's carrier. The brief's "12.3 GB" is stale (10.23 GB now); the
conclusion is unchanged.

### Measurement (commands, read-only)

```bash
gh api repos/jikig-ai/soleur/actions/cache/usage
#   {"active_caches_size_in_bytes":10231817250,"active_caches_count":178}
gh api --paginate 'repos/jikig-ai/soleur/actions/caches?per_page=100' --jq '.actions_caches[]' > caches.jsonl   # 179 rows
jq -rs 'group_by(.ref) | ...'                      # by ref
jq -rs 'map(.prefix = (.key | sub("sha256:.*";"sha256:") ...)) | group_by(.prefix) | ...'   # by key prefix
```

| Group | Entries | Size |
|---|---|---|
| ref `refs/heads/main` | 179 | 10.23 GB (100%) |
| ref `refs/pull/*` | 0 | 0 |
| key `buildkit-blob-1-sha256:*` (gha BuildKit blobs) | 160 | 9.6 GB |
| key `index-web-platform-release-1-f921bd05#1530..#1536` | 7 | ~0 |
| key `node-cache-Linux-x64-npm-*` | 2 | 0.48 GB |
| key `codeql-trap-1-2.27.3-javascript-*` | 7 | 0.12 GB |
| key `rehearsal-skip-monitor-streak-<run_id>` | 2 | 391 bytes |

Created per day (blob entries): 2026-06-08 6 / 0.08 GB; 2026-10-09 7 / 0.83 GB; **2026-10-23 146 / 8.68 GB**.
No entry of any key was created on 2026-10-21 or 2026-10-22, although the monitor logged
`Cache saved with key: rehearsal-skip-monitor-streak-<run_id>` on both days and the next day's restore
logged `Cache not found for input keys: rehearsal-skip-monitor-streak-<id>, rehearsal-skip-monitor-streak-`.
Writer: `.github/workflows/reusable-release.yml:802-803` (`cache-from`/`cache-to: type=gha,mode=min,scope=web-platform-release`),
7 exports on 2026-10-23 (index #1530 to #1536), about 1.17 GB each (a ~776 MB layer and a ~394 MB layer
whose digest changes every release; the five largest blobs differ by under 0.1% in size). One export's
`sending cache export` step took 131.2 s (run 39939406502); the same job's import produced 8 `CACHED` steps,
so the cache is useful, but the export is dominated by a never-reused layer.

**Measured cause.** The release workflow's BuildKit gha cache export writes about 1.2 GB per release (7 on
2026-10-23), which keeps the repo permanently at the 10 GB cap and evicts, least-recently-accessed first,
every entry older than roughly a day. The monitor's entry is 192 bytes, read once per 24 h, so it is always
the eviction candidate. The monitor's own per-run keys do not accumulate and PR refs do not participate.
Three of the four green assert days (09-27 Sunday, 10-03 and 10-17 Saturday) are weekend days, when release
volume is lowest, and the fourth (10-22) followed 10-21, which had the fewest release runs of its week (4
`version-bump-and-release` and 13 `web-platform-release` runs). This is a correlation read from run counts,
not proven per day: the evicted entries themselves are gone and cannot be listed.

Consequence for the fix: deleting caches by hand would not help (the next day's release churn refills the
quota within hours), so no cache cleanup is part of this change and none needs operator authorization.

### Property List (Phase 0.6b)

1. A scheduled run can tell "the previous generation's streak was restored" from "it was not".
2. A run that cannot prove it restored a numeric prior streak goes red (never green-by-default), except an
   explicit, auditable bootstrap run.
3. A lost, expired, malformed or unreadable store is never read as a first run or as a zero streak.
4. The stored value is always an explicit number (`0` when cleared), so absence is distinguishable from
   "cleared".
5. The persistence layer is not evictable by unrelated workflows' cache churn.
6. The probe still runs, and the alert issue is still filed, when the state step fails.

### Cut List (Phase 0.6b)

| Mechanism | Property it buys | Verdict |
|---|---|---|
| Cache hygiene (prune workflow, one-off cache deletion, smaller release export) as the monitor fix | 5 | Cut from this change. Hand deletion is refilled within a day; the release export is production-affecting and its reuse profile is unmeasured. Filed as #10917. |
| State issue / repo variable / run-history derivation | 5 | Cut (CTO ruling, `decision-challenges.md` row 1). Issue state is mutable by triage; a variable needs an App token plus Doppler for one integer; the counter lives inside the probe, so run history cannot reconstruct it. |
| Legacy-cache fallback during migration | 1 | Cut. It would re-introduce the evictable store as a silent second source. |
| `RUN_NUMBER > 1` first-run test | 2 | Replaced by the explicit `bootstrap` input (the first scheduled run after merge has `run_number` far above 1, a guaranteed false red). |
| Compatible `streak state: matched-key=` log line for the retired follow-through | none | Cut; the follow-through script is deleted instead (its tracker #7672 closed 2026-10-02). |
| Age-based hard failure | 2 | Cut (CTO): consecutive runs can be 2 days apart under scheduler load, and no consumer reads an age warning either. |

### Institutional learnings applied

- `2026-08-17-the-artifact-that-proves-a-refusal-happened-could-not-be-written.md`: no `|| true` and no
  `continue-on-error` on the state write; the job timeout (15 min) exceeds the sum of internal waits.
- `2026-07-30-the-guard-i-wrote-for-the-failure-path-could-not-run-on-the-failure-path.md`: every state step
  carries an explicit status function (`!cancelled()`), never the implicit `success()`.
- `2026-07-18-gh-pages-cert-reissue-restore-failloud-and-onfailure-paging.md` and
  `2026-07-16-the-fix-for-an-inert-monitor-shipped-a-probe-that-could-never-fire.md`: an empty read must be
  distinguished from a FAILED read; "no artifact" (HTTP 200, empty list) and "listing failed" are separate
  branches with separate exits.
- `2026-03-05-github-output-newline-injection-sanitization.md`: values written to `$GITHUB_OUTPUT` are
  validated tokens (digits, ids, ISO timestamps) emitted with `printf '%s\n'`.
- `2026-03-20-lint-scripts-break-on-extract-refactor.md`: extracting logic out of the workflow moves strings
  that lints grep; the lint sweep in AC3 covers it.
- `2026-07-15-a-guard-that-never-ran-has-more-than-one-reason-and-indexof-block-scoping-swallows-siblings.md`
  and `2026-05-15-red-tests-for-extractors-must-use-covered-code-path.md`: the wiring section parses the YAML
  (PyYAML) and asserts structure, with a pristine-run property count so a checker that stops reporting is
  not read as "all clear".

### Related issues and PRs

#10846 (merged; the relay PR that recorded the limitation), #10916 (this draft PR), #10917 (new: release
BuildKit export churn), #8856 (open alert issue for the real FAIL verdict), #7574 / #7672 (closed: original
counter and its cache-round-trip follow-through).

## Plan Review Revisions (2026-10-23)

Panel: DHH, Kieran, code-simplicity (threshold `none`, so the 3-agent baseline; the CTO had already ruled on
the architecture). Applied as mechanical: Kieran P1 1-5 (verdict-aware `seal`, `mkdir` of the state
directory, string/number run-id comparison and null-safe `head_branch`, upload gated on `seal`, strict
shape regex without whitespace tolerance), P2 6-9 (`set -u` defaults and listing-to-file, single-member zip
check, `STREAK_FILE` equality across five places, dispatch-counting note in Phase 5.0); simplicity cuts
(wiring suite folded into the one test file with five properties and fewer mutation rows, the
instrument-self-test/`NPROPS`/shuffle ceremony dropped, `value`/`source_*` outputs and the 3-day age warning
dropped, ADR shortened and written `accepted`). The bootstrap "discard malformed" branch was cut in this pass
and restored by the deepen-plan SpecFlow P0 (`decision-challenges.md`, rows "Deepen-plan (SpecFlow P0)" and
the simplification row): without it a poisoned newest artifact wedges the monitor red with no in-band
recovery. Not
applied, recorded in `decision-challenges.md`: DHH's proposal to drop the `bootstrap` input (the CTO ruled it
in), and DHH's proposal to make the probe write `0` instead of a separate `seal` (the upload gating needs a
separate step outcome, and `seal` also catches a lost TRANSIENT increment, which the probe's silent write
cannot report).

## Problem Statement

The probe `scripts/followthroughs/t5-skip-persistence-bound-7510.sh` escalates a run of consecutive
TRANSIENT verdicts to FAIL at `T5_TRANSIENT_ESCALATE_AFTER` (3). The count lives in a file
(`T5_PROBE_STATE`) that the carrier must persist. The carrier persists it in the Actions cache, an
evictable store shared with the release pipeline, so the counter resets to zero daily and the escalation can
never fire; the assertion step added to detect exactly this (#7574) is therefore red on most days, and a red
that fires on a fully healthy day teaches everyone to ignore it, which is the original fail-open one level
up.

## Proposed Solution

Persist the streak in a **workflow artifact** named `rehearsal-skip-monitor-streak` (CTO ruling, 2026-10-23;
artifacts are outside the 10 GB cache quota and carry an explicit `retention-days`). One new script holds the
decision logic so it is testable without a hosted runner; the workflow shrinks to wiring.

### Script: `scripts/monitor-streak-state.sh` (new)

Subcommands (all start with the repo's xtrace credential refusal, #7797, and `set -uo pipefail`):

| Subcommand | Reads | Does |
|---|---|---|
| `fetch` | `GH_TOKEN`, `GITHUB_REPOSITORY`, `GITHUB_REPOSITORY_ID`, `GITHUB_RUN_ID`, `GITHUB_REF_NAME`, `GITHUB_ACTOR`, `STREAK_ARTIFACT_NAME`, `STREAK_BRANCH`, `STREAK_FILE`, `BOOTSTRAP`, `GITHUB_OUTPUT` (all read as `${X:-}` or `${X:?}` under `set -u`) | (1) `mkdir -p "$(dirname "$STREAK_FILE")"`. (2) List: `gh api --paginate "repos/$REPO/actions/artifacts?name=$NAME&per_page=100"` to a temp FILE (pagination: ~90 daily artifacts plus dispatch and spam rows can exceed one page), check the `gh` rc, then `jq -s '[.[].artifacts[]]'` and require an array (never read `$?` through a pipe). (3) Select with `jq --arg`/`--argjson` (never interpolation), all fail-closed: `.expired == false`; `(.size_in_bytes // 1e9) <= 4096`; `(.workflow_run.head_branch // "") == $STREAK_BRANCH`; `(.workflow_run.head_repository_id // 0) == (.workflow_run.repository_id // -1)` and `(.workflow_run.repository_id // -1) == $GITHUB_REPOSITORY_ID` (artifacts are repository-scoped, not ref-scoped: a FORK pull_request run lists under this repository with a fork-controlled `head_branch`, even `main`, but its `head_repository_id` is the fork's); `(.workflow_run.id // 0) < $GITHUB_RUN_ID` as NUMBERS (the API returns a JSON number; this both excludes the run's own earlier attempt and makes a re-run of an OLDER run read its predecessor, not a newer run's state); newest by `workflow_run.id` (monotonic with schedule order, unlike `created_at`, which a re-run's overwrite would advance). (4) Validate the artifact id with `^[0-9]+$` before it enters a URL; download `…/artifacts/<id>/zip` to a temp file under `timeout 60` with stderr to a temp file (print only the exit code); require `unzip -Z1` output to be EXACTLY the line `streak` (rejects `../streak`, `streak/`, multi-member archives); read with `unzip -p … streak \| head -c 32` (never extract to disk); strip a trailing newline; validate with bash `[[ $v =~ ^[0-9]{1,6}$ ]]` (not `grep -E`, which passes `1\nabc`; the 6-digit cap only keeps shell arithmetic from overflowing); force base 10 (`$((10#$v))`). (5) Write `$STREAK_FILE`, emit ONLY `matched=true\|false` to `$GITHUB_OUTPUT`, print the source run id to the log. A non-`STREAK_BRANCH` ref (a feature-branch dispatch) prints `::notice::` that state is read from `main` and NOT written. A bootstrap run prints `::notice::bootstrap by ${GITHUB_ACTOR}`. The log NEVER carries the raw artifact value, member name or `unzip`/`gh` stderr (a line beginning `::stop-commands::`, `::add-mask::` or `::error::` is interpreted by the runner): on a malformed value it prints the length and `printf '%s' "$v" \| LC_ALL=C tr -c '[:alnum:]' '?' \| head -c 16`. |
| `seal` | `STREAK_FILE`, `VERDICT` (from `steps.probe.outputs.verdict`) | After the probe. For `pass`/`fail`/`broken`: a missing or empty file (the probe cleared it) becomes `0`. For `transient`: the probe MUST have written a numeric value of at least 1 — a missing, empty, non-numeric or zero file exits 1 (`_transient` writes with `2>/dev/null \|\| true`, so a lost increment would otherwise be sealed as `0` and silently reset the streak). Any other verdict exits 1. |
| `assert` | `MATCHED`, `BOOTSTRAP`, `STREAK_FILE` (`${X:-}` defaults) | Exit 1 unless `MATCHED == true` or `BOOTSTRAP == true` (literal string; unset, `false`, `1`, `True` are all "not bootstrap"); also exits 1 if the sealed file is not numeric. Prints `streak state: restored=<matched> value=<n>`. |

`fetch` outcome table (the contract the unit suite pins):

| Situation | `BOOTSTRAP` != true | `BOOTSTRAP` == true |
|---|---|---|
| listing call fails, or response is not JSON with an `artifacts` array | exit 1 (`::error::`) | exit 1 (a bootstrap never masks an unreadable store) |
| no eligible artifact (none, all expired, all on other branches, only runs at or after this run's id) | `matched=false`, exit 0 (the assert step turns it red) | `matched=false`, exit 0 |
| eligible artifact, download or `unzip` fails, member list is not exactly `streak`, or value malformed (non-numeric, empty, over 6 digits, embedded space or newline) | exit 1 | `::warning::` (sanitized), discard it, `matched=false`, exit 0 (the documented reseed path: a poisoned or corrupt NEWEST artifact must never wedge the monitor red with no recovery; the upload then writes a fresh, newer artifact) |
| eligible artifact, valid | `matched=true` | `matched=true` (value honoured) |

Listing failures are never masked by `bootstrap`. No age-based warning or failure: consecutive runs can be 2 days apart under scheduler load, a red daily job
already carries the loud signal, and plan review (DHH, code-simplicity) found no consumer for a warning.

### Workflow: `.github/workflows/scheduled-rehearsal-skip-monitor.yml` (edit)

- `on.workflow_dispatch.inputs.bootstrap`: boolean, default `false`, description states it permits "no prior
  streak" exactly once. Scheduled runs cannot set it (the env expression is
  `github.event_name == 'workflow_dispatch' && inputs.bootstrap`).
- Workflow-level `env`: `STREAK_ARTIFACT_NAME: rehearsal-skip-monitor-streak`, `STREAK_BRANCH: main` (single
  source for the script and the upload step).
- Step order: `checkout` > `fetch` (id `fetch`, replaces `actions/cache/restore`) > `probe` (unchanged
  contract; `T5_PROBE_STATE` moves to `${{ runner.temp }}/monitor-state/streak`, a NON-hidden absolute path:
  `actions/upload-artifact` v4.4+ excludes dot-directories by default, and `.monitor-state` is one) > `seal`
  > `assert` (replaces "Assert the streak state round-trips"; keep the step name so history is searchable) >
  `upload` (`actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02 # v4.6.2`, the pin used by 20
  `uses:` sites across 12 workflows, 40-char SHA verified; `name: ${{ env.STREAK_ARTIFACT_NAME }}`, `path: ${{ runner.temp }}/monitor-state/streak`,
  `retention-days: 90`, `if-no-files-found: error`, `overwrite: true`; condition
  `!cancelled() && github.ref == format('refs/heads/{0}', env.STREAK_BRANCH) && steps.fetch.outcome == 'success' && steps.seal.outcome == 'success'`
  so neither an unreadable store, an unsealable (non-numeric or lost-increment) file, nor a non-main dispatch
  (whose artifact `fetch` would never read, silently dropping its increment) is ever published) > alert issue
  (unchanged) > report verdict (unchanged). The alert and report steps depend only on
  `steps.probe.outputs.verdict`, so a failed fetch or upload cannot suppress them.
- The probe invocation is wrapped in `timeout 600` so a hang becomes rc 124, which the existing
  `case` maps to `broken` and the alert step files (otherwise the 15-minute job timeout cancels `seal`,
  `upload`, the alert and the report, leaving a red job with no issue and no counter advance; plan deepening
  found this adjacent fail-open).
- `STREAK_FILE` (`${{ runner.temp }}/monitor-state/streak`) is set per step, in five places (probe as
  `T5_PROBE_STATE`, fetch, seal, assert, and the upload `path`), because `runner.*` is not available in
  workflow- or job-level `env`; the probe step and `fetch` both `mkdir -p` its directory (the old
  `mkdir -p .monitor-state` is removed with the cache steps). The wiring checks assert all five are equal.
- `seal` receives `VERDICT: ${{ steps.probe.outputs.verdict }}`.
- `fetch`, `seal`, `assert` and the probe all carry `if: ${{ !cancelled() }}`; no `continue-on-error` and no
  `|| true` anywhere on the state path. `permissions` stays `contents: read`, `issues: write`,
  `actions: read` (listing and download need `actions: read`; the upload uses the runtime token).
- Header comments rewritten: the long "ROLLING WRITE KEY + PREFIX RESTORE" rationale is replaced by the
  measured eviction cause and the artifact contract, including the runbook sentence "to reseed after a lapse
  or a poisoned artifact: dispatch with `bootstrap=true`".
- `overwrite: true` is safe: it only replaces the SAME run's earlier attempt (a re-run), never a prior day's
  state; `fetch` excludes the current `GITHUB_RUN_ID` so an attempt-2 read cannot double-count attempt 1.

### Retire `scripts/followthroughs/monitor-streak-cache-roundtrip-7574.sh`

Its anchor (`streak state: matched-key=` in the run log) no longer exists, its tracker #7672 closed on
2026-10-02, and nothing enrolls it. Delete it and its row in
`scripts/lint-shell-trace-credential-refusal.baseline.txt`. The one remaining mention
(`scripts/followthroughs/git-data-boot-poll-8178.sh:62`, "used to reach its PASS") is already past tense.

### Probe header (comment-only edit)

`scripts/followthroughs/t5-skip-persistence-bound-7510.sh` lines 84-89 say the workflow "restores/saves"
the file; reword to "the workflow fetches it from, and uploads it to, a workflow artifact". No behaviour
change, so the probe's own suite is unaffected.

## Implementation Phases

### Phase 1: Tests first (RED)

1.1 ONE suite, `scripts/monitor-streak-state.test.sh` (plan review folded the separate wiring suite into
it: one `run_suite` line and one shard row). Section A drives the script: fake `gh` on `PATH` serving
fixture JSON/zip (zip built with `python3 -I -m zipfile` or `zip`; fixture run ids and artifact ids are JSON
NUMBERS, as GitHub returns them, so the string/number comparison is exercised), real `unzip`/`jq`; cases under
Test Scenarios. Section B parses the workflow with PyYAML (bare key `on` loads as boolean `True`) and asserts
five structured properties plus the mutation rows applied to a sandbox copy (pattern of
`plugins/soleur/test/merge-queue-cla-workflow-wiring.test.sh`). The suite keeps an exact assertion-count
floor (own-dispatch guard) and an append-only failure ledger; fixtures are synthesized only
(`cq-test-fixtures-synthesized-only`). The ceremony copied from sibling suites (instrument self-test,
`NPROPS`, shuffle variants) is deliberately NOT carried over.
1.2 Register with one `run_suite` line in `scripts/test-all.sh` (explicit; `scripts/*.test.sh` is covered by
no glob) next to the existing `scripts/followthroughs/t5-skip-persistence-bound-7510` line, then regenerate
the shard manifests: `python3 scripts/regenerate-shard-manifest.py --incremental --write` (updates
`scripts/suite-shard-legs.tsv` and `scripts/suite-durations.tsv`; the `.n` siblings are checked into the
tree, so confirm with `git status` whether the generator touches them and commit exactly what it writes).
Confirm the suite is RED (script absent / workflow still cache-based).

### Phase 2: Script (GREEN)

2.1 Write `scripts/monitor-streak-state.sh` to the outcome table above. `chmod +x`; xtrace refusal first;
run `python3 -I scripts/lint-shell-trace-credential-refusal.py scripts/monitor-streak-state.sh` and
`shellcheck`.
2.2 Unit suite green, including the end-to-end chain row (restored `2` reaches the REAL probe, which with a
broken `gh` escalates: `consecutive transient runs: 3/3`, exit 1).

### Phase 3: Workflow

3.1 Edit the workflow as specified. 3.2 Run `actionlint`, `python3 scripts/lint-workflow-step-env-refs.py`,
`python3 scripts/lint-workflow-issue-write-scope.py`, `python3 scripts/lint-gh-argv-arg.py`,
`bash scripts/alarm-issue-filing-guard.test.sh`, `bash scripts/lint-orphan-test-suites.sh`. 3.3 Section B of the
suite (wiring) green with every mutation row RED.

### Phase 4: Retire, document, record

4.1 Delete the follow-through script and its baseline row; `grep -rn monitor-streak-cache-roundtrip` returns
only the archived plans/specs and the past-tense comment. 4.2 Probe header comment edit. 4.3 ADR (below).
4.4 Open the PR body from `decision-challenges.md` (ship renders it) and reference #10917 as `Ref #10917`
(no closing keyword: the follow-up stays open).

### Phase 5: Post-merge verification (agent-run, no human step)

5.0 All dispatches use `--ref main` (a non-main dispatch reads main's state but writes nothing). Read the stored value first (the last run's artifact); dispatch only while it is `0`: the streak counts
consecutive TRANSIENT RUNS, not days, so each dispatch counts like a scheduled run and two dispatches on a
streak of 2 would escalate it.
5.1 Dispatch once with `bootstrap=true`: `gh workflow run scheduled-rehearsal-skip-monitor.yml --ref main -f bootstrap=true`,
arm a Monitor watch on THAT run id (the concurrency group drops an older pending dispatch, so assert the dispatched run itself concluded, not merely that a dispatch was accepted), assert the `fetch`, `assert` and `upload` steps
concluded `success`, and list the artifact unauthenticated:
`curl -s 'https://api.github.com/repos/jikig-ai/soleur/actions/artifacts?name=rehearsal-skip-monitor-streak&per_page=1' | jq -r '.artifacts[0].expired'` prints `false`.
5.2 Dispatch again with `bootstrap=false`: the `Assert the streak state round-trips` step must conclude
`success` and the log must show `restored=true`. This is the only proof that the `GITHUB_TOKEN` listing and
download work from a hosted runner (verified locally with a user token only), and it is a gate for calling
the fix done. Both dispatches may add a comment to the open alert issue #8856, as every daily run already does.
5.3 If 5.2 shows the listing is unreadable under `GITHUB_TOKEN`, the fallback inside this same design is the
repo's existing App-token mint (`./.github/actions/mint-infra-app-token`) for the two read calls; do not fall
back to the cache.

## Files to Edit

- `.github/workflows/scheduled-rehearsal-skip-monitor.yml`
- `scripts/test-all.sh` (one `run_suite` line)
- `scripts/suite-shard-legs.tsv`, `scripts/suite-durations.tsv` (regenerated rows; and the `.n` siblings only if the generator writes them)
- `scripts/lint-shell-trace-credential-refusal.baseline.txt` (remove the deleted script's row)
- `scripts/followthroughs/t5-skip-persistence-bound-7510.sh` (comment only)
- `knowledge-base/engineering/architecture/decisions/ADR-188-a-transient-environment-decline-is-reachable-under-ci.md` (one-line carrier-note pointer to the new ADR)

## Files to Create

- `scripts/monitor-streak-state.sh`
- `scripts/monitor-streak-state.test.sh`
- `knowledge-base/engineering/architecture/decisions/ADR-296-persist-the-rehearsal-skip-monitor-streak-in-a-workflow-artifact.md` (ordinal provisional: highest on `origin/main` is 295; re-verify at ship)
- `knowledge-base/project/specs/feat-one-shot-rehearsal-skip-monitor-streak-cache/tasks.md`

## Files to Delete

- `scripts/followthroughs/monitor-streak-cache-roundtrip-7574.sh`

## Open Code-Review Overlap

Checked the open `code-review` issues against every planned path. No match for the workflow, the probe,
the retired follow-through script, or the baseline file. Three touch registration files only:

- #8659 (test suites replacing the composed EXIT trap): Acknowledge. Different concern; this change adds
  one suite that uses their own `mktemp -d` plus an owning `trap`, so it does not worsen #8659.
- #7942 (mutation batteries named `*.mutation.sh` that run in no gate): Acknowledge. Not applicable; the new
  suite embeds its mutation rows and is registered with `run_suite`.
- #8881 (shard K=6 to K=7 rebalance review): Acknowledge. The shard files are touched only through the
  generator's incremental mode.

## Architecture Decision (ADR/C4)

Detection fires: this swaps the persistence layer of a safety-critical counter and changes the carrier note
of ADR-188 (a "substrate or integration pattern" change).

### ADR

Create ADR-296 via `soleur:architecture create` (provisional ordinal; the ship ADR-ordinal gate re-verifies
against `origin/main`): "Persist the rehearsal-skip monitor streak in a workflow artifact, not the Actions
cache". Decision: a correctness-critical cross-run counter must live in a store its own writers cannot evict;
the Actions cache is an eviction-by-design store. Alternatives Considered table: cache hygiene (A), state
issue (C), repo variable (D), run-history derivation (E), each with the rejection reason from the CTO ruling.
Amend ADR-188's "Carrier note" with a one-line pointer (task in Phase 4, not a follow-up).

### C4 views

No C4 impact. All three model files were checked (`model.c4` 1001 lines, `views.c4` 132, `spec.c4` 54): the
only relevant element is the existing `github` system (its description and the CI/`github ->` edges), which
already models Actions workflows and the REST API. Actors: no new external human actor. Systems: no new
vendor or store (Actions artifacts are internal to the `github` system). Data stores: none added to any
container. Actor-surface relationships: unchanged. A grep for `artifact`, `cache`, `rehearsal` and
`skip-monitor` across the three files found no mention of this monitor or of the Actions cache, so no
element description is falsified. `bash plugins/soleur/test/c4-count-parity.test.sh` returns 13 passed,
0 failed on this tree; no workflow is added or removed, so no embedded cardinality moves (re-run at the end
of Phase 4).

### Sequencing

The ADR describes the target state and ships in this PR (status `accepted`, short form: Context, Decision, Alternatives table,
with AC9 named as the evidence; if AC9 fails the ADR is amended rather than flipped).

## Guard Contract

### Guard 1 — Streak-store round-trip (fetch, seal, assert)

**Property.** A scheduled run that cannot prove it restored a numeric prior streak from the artifact store
goes red, and no run ever uploads anything but an explicit numeric value.

**Assembly.** Chokepoints, all required: (1) the single decision function in `scripts/monitor-streak-state.sh`
(`fetch` is the ONLY path that can produce `matched=true`: one jq selection, one download, one validation);
(2) `seal` is the ONLY path that creates the file that is uploaded when the probe cleared it; (3) `assert` is
the ONLY consumer of `MATCHED`/`BOOTSTRAP`; (4) the workflow wiring that invokes those three in order with
`!cancelled()` and the upload step with `if-no-files-found: error`, no `continue-on-error`, and a path
identical to the probe's `T5_PROBE_STATE`; (5) the three exit classes of `fetch` (listing failure, download or
shape failure, malformed value). More than one chokepoint exists on purpose: the unit suite pins (1)-(3) and
(5), the wiring section of the same suite pins (4).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | `fetch` treats a listing failure as "no eligible artifact" (`gh api … \|\| true` or ignoring the rc) | RED: unit case "listing exits 1" expects exit 1 and no `matched=false` line |
| 2 | `assert` accepts any non-empty `BOOTSTRAP` (`-n`) instead of the literal `true` | RED: cases `BOOTSTRAP=false`, `1`, `True`, `yes`, unset all expect exit 1 |
| 3 | `fetch` drops the `head_branch` filter, or the `head_repository_id == repository_id` equality | RED: (a) decoy on `feature/x`, (b) decoy with `head_branch=main` but a different `head_repository_id` and a newer timestamp, (c) a null `workflow_run`, (d) `size_in_bytes` over 4096 — each with a higher value, newest by time, must be ignored |
| 4 | `fetch` stops at the first artifact, or sorts by `created_at` instead of `workflow_run.id` (second, newer eligible member after a compliant first) | RED: two eligible artifacts, older listed first, newest run id must win; and a re-uploaded OLDER run's artifact with a later `created_at` must not outrank a newer run's |
| 5 | `fetch` drops the `workflow_run.id < $GITHUB_RUN_ID` bound, or compares the JSON-number id to the string `$GITHUB_RUN_ID` (never matches) | RED: an artifact with the current run id, and one with a HIGHER run id (a re-run of an older run), must not be restored; numeric fixture ids |
| 6 | `seal` writes `0` for a missing file regardless of `VERDICT` (a lost TRANSIENT increment reads as a cleared streak) | RED: `VERDICT=transient` with a missing/empty/`0` file exits 1; `VERDICT=pass` with a missing file seals `0` |
| 7 | `fetch` accepts leading zeros as octal (`$((v+1))`-style) or skips the numeric shape check | RED: `08`, `007`, `abc`, empty, `12 34`, 7-digit values |
| 8 | The guard's own dispatch: `assert` (or `seal`, or `fetch`) subcommand unrecognized or a no-op exiting 0 | RED: the suite requires an exact assertion-count floor and at least one case per subcommand |

Harness rows: (a) edit the SUITE: change the fake `gh` to return an empty list for the "valid artifact" case;
the suite must go RED on the case that expected `matched=true` (proves the fixtures are consumed, not
bypassed). (b) must-PASS inputs that are NOT the canonical: a valid artifact whose value carries a trailing
newline, and a listing that includes extra unrelated fields and unknown artifacts; both must restore. The
suite's exit status reads an append-only failure ledger, not `fails == 0` alone.

**Anchor.** The guard compares presence and shape, not a stored value against the thing it protects, so no
anchor is needed for integrity. The residual (a user with write access can upload a decoy artifact on `main`)
is residual and bounded: the selection admits only same-repository artifacts from branch `main` with size at most 4096 bytes and a numeric payload, so a decoy needs write access to this repository. Plan deepening (security review) corrected an earlier claim that this equals the cache's exposure: caches are ref-scoped, artifacts are not, and a FORK pull_request run lists under this repository with a fork-controlled `head_branch`; the `head_repository_id` equality is what excludes it.

### Guard 2 — Workflow wiring section

**Property.** The workflow wires the state path in the only order and with the only status functions that
keep the assertion un-skippable and the store non-evictable.

**Assembly.** Every `steps[*]` entry of `jobs.monitor`, the `on.workflow_dispatch.inputs` block, the
workflow-level `env`, the `permissions` block, and the probe's `T5_PROBE_STATE` env; the suite derives step
order from the parsed YAML (not text), derives the upload path and name from the workflow itself and compares
them to the probe env and to `env.STREAK_ARTIFACT_NAME`. Single chokepoint: the parsed document; no grep.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Re-introduce an `actions/cache/restore` or `actions/cache/save` step | RED: property "no evictable store" |
| 2 | Move `assert` after `upload` (reorder, not delete) | RED: order property |
| 3 | Remove `!cancelled()` from `assert`, `seal` or `fetch` (after a compliant first) | RED: status-function property, reported per step |
| 4 | Point the probe at `.monitor-state/streak` (hidden directory) while the upload path stays | RED: path-equality and non-hidden properties |
| 5 | Make `bootstrap` default `true`, or drop the `github.event_name == 'workflow_dispatch'` guard | RED: bootstrap property (a scheduled run must be able to reach `BOOTSTRAP=true` in no way) |
| 6 | Drop `steps.seal.outcome == 'success'`, the fetch condition, or the `github.ref == refs/heads/<STREAK_BRANCH>` condition from the upload `if:`, or add `continue-on-error: true` / `if-no-files-found: warn` to it | RED: upload-gating property |
| 6b | Remove `timeout 600` from the probe invocation | RED: probe-bounded property |
| 7 | Delete the `upload` step | RED: the suite requires exactly the expected number of property lines, and the order property fails |

Properties (parsed YAML, five plus the equality check): no `actions/cache`; step order
fetch < probe < seal < assert < upload; `!cancelled()` on each of those steps (reported per step); the five
`STREAK_FILE` occurrences are equal and have no hidden path segment; upload gating and strictness (above)
plus the `bootstrap` input shape. Harness rows: the pristine workflow must report exactly the expected number
of property lines, all green (a checker that stops reporting is not "all clear"), and a must-PASS variant
(comments added, an unrelated step inserted after `report`) stays green.

**Anchor.** None needed; the suite compares the workflow to itself and to the script, both in the same diff,
which proves consistency, not integrity. Integrity comes from CODEOWNERS review of `.github/workflows/`.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing. This is internal CI telemetry; a broken
  monitor means the platform team is either paged by a false red or not paged when the rehearsal suite's
  skips persist (the operator's alert issue #8856 is the artifact that would be missing).
- **If this leaks, the user's data is exposed via:** no user data is involved. The stored artifact is a single
  integer in a public repository.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** an internal scheduled monitor with no user data, no auth, no money
  and no customer-visible surface; the worst case is a delayed internal alert, not a user incident.

`threshold: none, reason: neither .github/workflows/scheduled-rehearsal-skip-monitor.yml nor scripts/ matches the sensitive-path regex (preflight Check 6), and the change touches no user data.`

## Observability

```yaml
liveness_signal:
  what: the monitor's own daily run, plus the unexpired artifact rehearsal-skip-monitor-streak (one new artifact per run)
  cadence: daily at 06:00 UTC (hosted start 10:45-13:15 UTC in practice)
  alert_target: red GitHub Actions run (assert/fetch/upload step) plus the alert issue filed by the existing "Open or update the alert issue" step on fail/broken verdicts
  configured_in: .github/workflows/scheduled-rehearsal-skip-monitor.yml
error_reporting:
  destination: GitHub Actions run annotations (::error::) and the open alert issue; no Sentry (repo-scoped GitHub-API work, see the workflow header)
  fail_loud: "::error::the streak store returned no prior generation" or "::error::artifact listing failed" and a non-zero step conclusion
failure_modes:
  - mode: artifact listing unreadable (API error, non-JSON body, token scope)
    detection: fetch exits 1 with ::error:: (distinct from "no artifact"); upload is skipped so a stale store is not overwritten with a reset value
    alert_route: red run on the daily schedule
  - mode: no eligible prior artifact (retention lapse, first run, store deleted)
    detection: assert exits 1 on a scheduled run; the same run uploads, so the next day self-heals
    alert_route: red run (once)
  - mode: malformed stored value
    detection: fetch exits 1; reseed via a bootstrap dispatch
    alert_route: red run until reseeded
  - mode: upload fails
    detection: upload step red (if-no-files-found error, no continue-on-error)
    alert_route: red run
  - mode: scheduled workflow disabled by GitHub after 60 days of repo inactivity, or never fires
    detection: not detectable from inside the monitor; tracked in #10917 (dead-man's-switch option)
    alert_route: none today (accepted, recorded)
  - mode: cancelled run
    detection: upload skipped, prior artifact stays; the counter can under-count by one
    alert_route: none (accepted, documented in the workflow header)
logs:
  where: GitHub Actions run logs for scheduled-rehearsal-skip-monitor (steps fetch, assert, upload)
  retention: 90 days (repository default); the artifact itself 90 days
discoverability_test:
  command: curl -s 'https://api.github.com/repos/jikig-ai/soleur/actions/artifacts?name=rehearsal-skip-monitor-streak&per_page=1' | jq -r '.artifacts[0].expired'
  expected_output: false or null
```

(`null` is the pre-first-upload state; after the Phase 5.1 bootstrap dispatch the literal is `false`. The
post-merge acceptance criteria assert `false` exactly.)

## Encryption Posture

```yaml
at_rest:
  - store: GitHub Actions artifact rehearsal-skip-monitor-streak (one integer, 0 to 3)
    mechanism: plaintext-exception
    evidence: scripts/monitor-streak-state.sh (writes only a validated 1 to 6 digit decimal)
    defends_against: nothing is claimed; confidentiality is not a property of this store
    does_not_defend: any authenticated GitHub user can download the artifact from this public repository; a user with write access to this repository can upload a decoy named identically from a run on the default branch (fork pull_request runs are excluded by the head_repository_id equality, artifacts being repository-scoped rather than ref-scoped)
    disclosed_as: not-publicly-claimed
    live_verification: unavailable:GitHub does not expose per-artifact encryption state
in_transit:
  - connection: runner -> api.github.com (artifact listing and zip download via gh)
    enforced_at: scripts/monitor-streak-state.sh (gh api over HTTPS)
    tls: HTTPS, TLS 1.2 or newer as negotiated by gh
    cert_verification: on
    does_not_defend: a compromised runner or a leaked GITHUB_TOKEN
    disclosed_as: not-publicly-claimed
exception:
  justification: the stored value is a non-secret failure counter in a public repository; encrypting it adds no defence
  tracking_issue: "#10916"
  reevaluate_when: the stored payload ever carries anything other than a decimal counter
  expires_on: 2027-01-20
```

## Domain Review

**Domains relevant:** engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** The CTO agent ruled on the store (artifact), the scope (release cache churn to #10917), the
first-run discriminator (`bootstrap` input), the fail-loud contract (hard exit 1, self-heal by upload) and the
fail-closed edges (concurrency, failed upload, ordering against the alert step, failed-run artifacts accepted,
cancelled-run under-count accepted, decoy bounded by branch filter). Product, marketing, legal, finance,
operations, sales and support: no implications (internal CI monitor). No user-facing surface, so no UX gate.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "First establish the actual cause of the over-cap and eviction by measurement" | Research Insights: Measurement, measured cause | mapped |
| 2 | "do not assume it" | Research Reconciliation rows (self-accumulation and PR-ref hypotheses measured and ruled out) | mapped |
| 3 | "fix it so the streak state persists reliably and the job stops being red" | Proposed Solution (artifact store), Phases 2-3, AC5-AC10 | mapped |
| 4 | "Consider whether the streak state needs the Actions cache at all (for example a durable store such as an issue comment, a repo variable, or a committed/artifact-based record) versus fixing cache hygiene" | `decision-challenges.md` row 1, Cut List | mapped |
| 5 | "the fix must keep the monitor's fail-loud property (a broken round-trip must still surface, not pass vacuously)" | Guard Contract 1 and 2, `assert`, AC4 | mapped |
| 6 | "Related workflow-level test or lint expectations for this workflow must be updated in the same change." | Wiring suite, unit suite, lint sweep (Phase 3.2), baseline row, registration | mapped |
| 7 | "if cache cleanup is part of the fix, plan it as an operator-authorized step, not something you do now" | No cache cleanup is part of the fix (steady-state churn refills the quota); none planned | descoped — justification: measured that hand deletion is refilled within a day and the artifact store no longer depends on the quota |
| 8 | "this limitation was recorded in the body of the just-merged rehearsal skip-probe relay PR ... where it was deferred and no issue was filed" | Follow-up issue #10917 for the release export churn; PR body references it | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Artifact store + `fetch`/`seal`/`assert` script | "persists reliably" and "an artifact-based record" | asked |
| Wiring + unit suites, lint sweep | "Related workflow-level test or lint expectations ... must be updated" | asked |
| `bootstrap` dispatch input | — | inferred — justification: the CTO ruled `RUN_NUMBER > 1` would fire a guaranteed false red on the first scheduled run after merge, and the migration needs an auditable first-run path |
| ADR-296 and the ADR-188 pointer | — | inferred — justification: plan gate 2.10 (a persistence-layer change for a safety-critical counter is a plan deliverable) and CTO ruling row 6 |
| Delete `monitor-streak-cache-roundtrip-7574.sh` and its baseline row | — | inferred — justification: its log anchor is removed by this change; keeping it would leave a probe that can only report FAIL or TRANSIENT |
| Comment-only edit of the probe header | — | inferred — justification: the header states the workflow "restores/saves" the file and would be false after this change |
| Filing #10917 | "where it was deferred and no issue was filed" | asked |
| Filing #10918 (escalation FAIL mislabelled by the alert step) | "where it was deferred and no issue was filed" | inferred — justification: the fix makes the escalation reachable for the first time, and the pre-existing alert title would mislabel it; deferral without a tracking issue is invisible |
| Post-merge double dispatch (Phase 5) | "stops being red" | asked |
| `timeout 600` around the probe | — | inferred — justification: deepening (SpecFlow) found that a hung probe is cancelled by the 15-minute job timeout with no verdict, no alert and no counter advance; one token turns it into the existing `broken` path |
| Fork-safe artifact selection (`head_repository_id`, repository id, size bound) and sanitized logging | — | inferred — justification: deepening (security review, P0) found artifacts are repository-scoped, so a fork PR run could plant a decoy that resets or forces the streak |

### Split Assessment

- Subsystems touched: 3 — `.github/workflows`, `scripts`, `knowledge-base`
- Planned files: 10 | Estimated changed lines: about 620 after plan review and deepening (script about 160, one suite about 280, workflow net about 90, short ADR about 40, registration and baseline about 30)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR. Under every threshold; production-code lines (workflow plus script) are about 210, and a split would land an artifact store without its guard.

## Acceptance Criteria

### Pre-merge (PR)

- [x] AC1: `grep -c 'actions/cache' .github/workflows/scheduled-rehearsal-skip-monitor.yml` prints `0`; the suite's wiring section reports the "no evictable store" property green.
- [x] AC2: `bash scripts/monitor-streak-state.test.sh` (script cases and wiring section) exits 0; each mutation row in Guard Contract 1 and 2 turns its guarding case RED when applied to a sandbox copy (the suites run the rows themselves).
- [x] AC3: `actionlint .github/workflows/scheduled-rehearsal-skip-monitor.yml`, `python3 scripts/lint-workflow-step-env-refs.py`, `python3 scripts/lint-workflow-issue-write-scope.py`, `python3 scripts/lint-gh-argv-arg.py`, `python3 -I scripts/lint-shell-trace-credential-refusal.py scripts/monitor-streak-state.sh`, `bash scripts/alarm-issue-filing-guard.test.sh`, `bash scripts/lint-orphan-test-suites.sh`, `shellcheck` on the new shell files, and `bash plugins/soleur/test/c4-count-parity.test.sh` all pass.
- [x] AC4: the unit suite's end-to-end chain row passes: a restored value `2` reaches the real probe (broken `gh`), which prints `consecutive transient runs: 3/3` and exits 1; with no restored state the same probe exits 2 at `1/3`.
- [x] AC5: `fetch` against a fake listing that fails returns exit 1 and never writes `matched=false` (the unreadable-store versus empty-store distinction is pinned).
- [x] AC6: `grep -rn 'monitor-streak-cache-roundtrip' --include='*' . | grep -v 'knowledge-base/project/\(plans\|specs\)/archive'` shows only the past-tense comment in `git-data-boot-poll-8178.sh`; the baseline row is gone.
- [ ] AC7: ADR-296 exists (ordinal re-verified against `origin/main`), ADR-188's carrier note points to it, and `decision-challenges.md` is rendered into the PR body; #10917 is referenced with `Ref`, not `Closes`.

### Post-merge (agent-run, Phase 5)

- [ ] AC8: the `bootstrap=true` dispatch run has `fetch`, `assert` and `upload` concluded `success`, and `curl -s 'https://api.github.com/repos/jikig-ai/soleur/actions/artifacts?name=rehearsal-skip-monitor-streak&per_page=1' | jq -r '.artifacts[0].expired'` prints `false`.
- [ ] AC9: the following `bootstrap=false` dispatch run has the `Assert the streak state round-trips` step concluded `success` and its log contains `restored=true`.
- [ ] AC10: the next scheduled run (06:00 UTC, observed through `gh run view <id> --json jobs`) has the assert step concluded `success`. The job as a whole can still be red because of a legitimate probe FAIL (alert issue #8856); that is outside this fix and is not an acceptance condition.

## Test Scenarios

Pyramid layer labels: `unit` unless stated. Fixtures are synthesized; the fake `gh` is on `PATH` and records its argv so the suite also asserts the exact endpoint (`?name=`, no repo-wide listing).

| # | Given | Then |
|---|---|---|
| T1 | empty artifact list | `matched=false`, exit 0 |
| T2 | only expired artifacts | `matched=false`, exit 0 |
| T3 | only artifacts whose `head_branch` is not `main` | `matched=false` |
| T4 | only artifacts with run id equal to or higher than `GITHUB_RUN_ID` | `matched=false` |
| T5 | two eligible artifacts, older listed first; and an older run's re-uploaded artifact with a later `created_at` | highest `workflow_run.id` below the current run wins, value read from it |
| T6 | newest artifact is a decoy on another branch with a larger value | decoy ignored |
| T7 | value `3`, `0`, `12`, `3\n` | `matched=true`, file holds the base-10 value |
| T8 | value `08`, `007` | restored as `8`, `7` (never octal) |
| T9 | value `abc`, empty, `1 2`, `1234567`, `-1`, `  4 `; also a zip with two members | exit 1, both `BOOTSTRAP` values |
| T10 | listing returns exit 1 / HTML / `{}` | exit 1, both `BOOTSTRAP` values |
| T10b | decoys: other branch; `head_branch=main` with a different `head_repository_id`; null `workflow_run`; `size_in_bytes` 5000; each newer and larger than the real artifact | all ignored, real artifact restored |
| T10c | zip members `../streak`, `streak/`, `streak\nx`; value `::error::x`; value `1\nabc` | exit 1; the captured log contains no `::error::x` and no raw member name |
| T11 | download exits 1, or the zip lacks member `streak` | exit 1, both `BOOTSTRAP` values |
| T13 | `seal`: `VERDICT=pass` with file missing / empty / `5` / `x`; `VERDICT=transient` with file missing / empty / `0` / `2`; `VERDICT=weird` | `0` / `0` / `5` / exit 1; exit 1 / exit 1 / exit 1 / `2`; exit 1 |
| T14 | `assert` with `MATCHED` true / false / unset and `BOOTSTRAP` true / false / `1` / `True` / unset | pass only for `MATCHED=true` or `BOOTSTRAP=true` (literal) |
| T15 | end-to-end chain (above, AC4); integration | restored value feeds the real probe |
| T16 | wiring section on the pristine workflow | exactly the expected number of property lines, all green |
| T17 | wiring section, each Guard 2 mutation row | the named property is RED |
| T18 | hosted dispatch pair (Phase 5); e2e, pyramid-justified: the `GITHUB_TOKEN` artifacts API is reachable only from a hosted run | AC8 and AC9 |

Regression: the 2026-10-19 to 2026-10-21 red runs (#55 to #57) are the reproduction of "Cache not found"
followed by the red assert; T1/T14 reproduce that input and now require an explicit `BOOTSTRAP`.

## Alternative Approaches Considered

| Approach | Verdict | Why |
|---|---|---|
| A. Cache hygiene (shrink the release export, prune workflow, hand deletion) | Rejected for the monitor; tracked as #10917 | Leaves a correctness-critical counter on an evictable store; hand deletion is refilled within a day; the release pipeline is production-affecting and its reuse profile is unmeasured. |
| C. State issue (body or comment marker) | Rejected | Issue state is mutable and closable by triage; adds tracker noise. |
| D. Repo Actions variable | Rejected | `GITHUB_TOKEN` cannot write variables; needs an App token via Doppler for one integer. |
| E. Derive the streak from run history | Rejected | The counter lives inside the probe; conclusions do not encode `transient` versus `pass`. |
| Keep the cache and just stop asserting | Rejected | It would restore the original fail-open: the escalation could never fire and nothing would say so. |

## Dependencies and Risks

- **GITHUB_TOKEN listing is unproven from a hosted runner.** Verified locally with a user token and
  unauthenticated `curl`; Phase 5.2 is the proof, with an App-token fallback inside the same design (5.3).
- **Repo-wide artifact listing fails locally** (`unexpected end of JSON input`); the design never uses it. If
  the exact-name listing ever started failing the same way, `fetch` exits 1 (loud), not 0.
- **Hidden-directory exclusion.** `actions/upload-artifact` v4.4+ skips dot-directories by default; the state
  directory is therefore `${RUNNER_TEMP}/monitor-state`, and the wiring section fails any hidden path segment.
- **Retention.** 90 days exceeds the 60-day scheduled-workflow auto-disable; org policy can cap retention
  lower, so Phase 5.1 reads `expires_at` from the listing and records it in the PR.
- **Cancelled run under-counts by one and can skip its alert** (upload and alert are `!cancelled()`-gated); the next daily run re-detects a real FAIL, so this self-heals. Accepted and documented in the workflow header.
- **A red fetch day leaves the stored value stale** (upload is skipped when fetch fails): if the verdict that day was a clearing `pass`, the store keeps its old `N`, and a later TRANSIENT then reads `N+1`. Needs a red fetch day AND a nonzero stored value AND a later transient; accepted, recorded in the header.
- **No age bound:** after the scheduler is auto-disabled for 60 days and re-enabled, a stored `2` plus one transient escalates. Accepted (the CTO ruled no age-based failure); a `bootstrap` dispatch resets.
- **The first reliable escalation is mislabelled by the existing alert step:** the probe's "unable to reach a verdict for N consecutive runs" FAIL files under the title for real skips. Pre-existing and out of scope here; tracked as #10918.
- **A real FAIL keeps the job red** (open alert issue #8856); intentional and outside this fix.
- **The release export churn remains** until #10917 lands; the other caches (npm, CodeQL) continue to be
  evicted daily.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits
  the threshold will fail `deepen-plan` Phase 4.6; this one declares `none` with the scope-out bullet.
- Do not add a legacy-cache fallback "just for the migration": it re-creates the evictable store as a silent
  second source of truth.
- The wiring section must read the parsed YAML; a grep of workflow text is how the previous guards in this repo
  went vacuous.
- `overwrite: true` only touches the same run's earlier attempt. Do not "fix" a stale-state worry by widening
  the exclusion to prior days.

## References

- Workflow: `.github/workflows/scheduled-rehearsal-skip-monitor.yml`; probe: `scripts/followthroughs/t5-skip-persistence-bound-7510.sh`
- Artifact list/download precedent: `.github/workflows/web-platform-release.yml` (list, `expired` check, `…/zip`, `unzip -p`); upload pin and `overwrite: true` precedent: `.github/workflows/reusable-release.yml:1893`, `.github/workflows/weakness-miner.yml:70`; `retention-days: 90` precedent: `.github/workflows/git-data-rung2-rehearsal.yml:881`
- Test precedents: `scripts/followthroughs/t5-skip-persistence-bound-7510.test.sh`, `plugins/soleur/test/merge-queue-cla-workflow-wiring.test.sh`
- ADR-188 (carrier note), PR #10846, issues #7574, #7672, #8856, #10917
