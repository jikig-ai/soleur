---
title: "feat: scheduled watcher records first qualifying live-verify CI PASS as flip evidence"
date: 2026-06-18
type: feat
branch: feat-one-shot-live-verify-pass-watch
lane: cross-domain
status: draft
brand_survival_threshold: none
---

# feat: Scheduled watcher records the first qualifying live-verify CI PASS on the flip-tracker issue

## Enhancement Summary

**Deepened on:** 2026-06-18
**Sections enhanced:** Premise Validation, Implementation Phases (2-3), Scheduled-Work Precedent (new), Research Insights (new)

### Key Improvements
1. **ADR-033 / Phase-4.4 scheduled-work precedent decided + documented** — GH Actions cron is the
   correct substrate here (not Inngest) because the work is purely repo/CI-scoped (`github.token`, no app
   context/secrets/Sentry). This matches the established off-convention repo-scoped-CI-cron family
   (`cla-evidence-timestamp.yml`, `kb-drift-walker.yml`, `rule-audit.yml`, `secret-scan.yml`, …) and is
   the explicit ADR-033 carve-out, not a dodge.
2. **Cron PreToolUse hook mechanical note** — `.claude/hooks/new-scheduled-cron-prefer-inngest.sh` fires
   ONLY on `scheduled-*.yml` filenames; the spec'd `live-verify-pass-watch.yml` is outside that glob, so
   the hook allows it (no override marker needed). The plan keeps the spec'd filename.
3. **Implementation hardening** — `gh run list --status completed` interplay, `jq -c` line-iteration for
   newest-first scan, `printf`+`--body-file` (not heredoc) for the comment body, `GH_PAGER=cat` to keep
   `gh` non-interactive in CI.

### New Considerations Discovered
- The whole feature rests on a stale premise: issue 5463 is CLOSED (see Premise Validation). The deepened
  plan does not "fix" this in code — it surfaces it as AC0 + a post-merge operator reopen (AC12).
- Live-verified: PR #5519 MERGED, issue #5463 CLOSED, checkout pin `34e114876…` is the real 40-char
  dominant pin (63 uses), `web-platform-release.yml:617` is the `continue-on-error: true` line.

## Overview

Add a deterministic (NO claude-code-action / no LLM) daily GitHub Actions watcher that scans recent
`web-platform-release.yml` runs for the FIRST run whose `live-verify` job actually executed the harness
(step `Run live-verify harness (report-only)` not `skipped`) and emitted `RESULT: PASS` in the job log,
then records that PASS once — as a comment carrying run URL + head SHA + the RESULT line + a sentinel — on
the flip-tracker issue **5463** (the report-only -> blocking live-verify deploy-gate flip).

The watcher **records evidence and notifies only**. It never flips the gate. The flip ships separately by
an operator/agent once notified, as a distinct later deploy, per `wg-dark-launch-deploy-gates` ("never
validate a gate change with the same deploy it gates").

Authoritative PASS signal = the `RESULT: PASS` line in the live-verify job LOG, NOT the step conclusion
(the harness step is `continue-on-error: true`, so its conclusion is `success` even on a FAIL/CANT-RUN
result — confirmed at `.github/workflows/web-platform-release.yml:617`).

Deliverables: `scripts/watch-live-verify-pass.sh` + `.github/workflows/live-verify-pass-watch.yml` +
`scripts/watch-live-verify-pass.test.sh` (RED-first), wired into `scripts/test-all.sh`'s `scripts` shard.

## Premise Validation (Phase 0.6 — STALE PREMISE FOUND, must read)

Checked every artifact the feature description cites by reference:

- **Issue 5463 — CITED AS OPEN, IS ACTUALLY CLOSED.** `gh issue view 5463` returns
  `state: CLOSED, stateReason: COMPLETED, closedAt: 2026-06-18T00:45:49Z`,
  `closedByPullRequestsReferences: [PR #5519]`. The feature description calls it "the open flip-tracker
  issue." It is not open.
- **PR #5519 did NOT ship the flip and explicitly disclaims closing 5463.** Title:
  `fix(live-verify): classify server-side send rejections as CANT-RUN, not FAIL`. Body verbatim:
  *"**Prerequisite for the #5463 report-only->blocking flip — this PR does NOT close #5463 and does NOT
  change the gate's `continue-on-error`/topology**."* So 5463 was **auto-closed by accident** (a `Closes/
  Fixes #5463` reference leaked into the PR/commit metadata despite the body's disclaimer), not because
  the flip shipped.
- **The flip has NOT shipped — gate is still report-only.** `web-platform-release.yml:617` still has
  `continue-on-error: true` on the harness step and NO job lists `live-verify` in `needs:`. The
  re-evaluation criteria in 5463's body ("Flip to blocking after the gate is observed emitting a correct
  PASS on >=1 real ... PR merge") are still unmet. There are currently **0** comments carrying the
  `live-verify-pass-watch:recorded` sentinel.
- **No `RESULT: PASS` observed yet.** The most recent `web-platform-release.yml` run's `live-verify` step
  is `skipped` (that merge touched no trigger-path surface) — exactly the SKIPPED case the watcher skips.

**Consequence for this plan (load-bearing):** The watcher's spec'd guard `(a) if state != OPEN -> exit 0`
means that against the CURRENT closed state, the watcher would record nothing on every run — a permanent
cheap no-op. That is the *self-disable contract working as designed AFTER the flip ships*, but here it
fires BEFORE the flip ships because of the accidental close. **The plan keeps the `state != OPEN -> exit 0`
guard exactly as specified** (it is correct and is the self-disable mechanism), but the operator MUST be
told: to make this watcher useful, **issue 5463 has to be REOPENED** (the flip genuinely has not happened).
This is surfaced as the top item of Acceptance Criteria and the Sharp Edges, and is the reason this plan
cannot silently "just build to spec" — building to spec is correct; the *environment* the spec assumed
(5463 open) is stale. Surfaced here per Phase 0.6 rather than planning against the stale premise.

## Research Reconciliation — Spec vs. Codebase

| Spec/description claim | Reality (verified) | Plan response |
|---|---|---|
| Issue 5463 is the "open" flip-tracker | CLOSED (COMPLETED) by accidental link from PR #5519 | Build watcher exactly to spec; AC1 + Sharp Edge instruct operator to REOPEN 5463; watcher's `state != OPEN -> exit 0` guard handles closed gracefully |
| Flip ships separately, watcher only records | Gate still report-only (`continue-on-error: true`, no `needs:`); flip unshipped | No change — confirms watcher must NOT flip; it only records + notifies |
| Harness step conclusion not a reliable PASS signal | Confirmed: step is `continue-on-error: true` at `web-platform-release.yml:617`; conclusion `success` even on skip/fail | Parse `RESULT: PASS` from job LOG, never trust conclusion |
| Job name ~`live-verify`, step name ~`Run live-verify harness` | Exact live names: job `live-verify`, step `Run live-verify harness (report-only)` | Substring match `live-verify` (job) + `Run live-verify harness` (step) — both match exact names |
| `gh run view --json jobs` gives jobs/steps + a job db id for `--log` | Confirmed: `jobs[]` carries `databaseId`, `name`, `steps[].name`, `steps[].conclusion`; `gh run view --job <dbId> --log` fetches one job log | Use as spec'd |
| Register test in `infra-validation.yml` only if convention | `scripts/*.test.sh` are wired into `scripts/test-all.sh` `scripts` shard (`run_suite` lines 122-124), NOT infra-validation (that file is for `apps/web-platform/infra/*.test.sh`) | Register in `scripts/test-all.sh` `scripts` shard; do NOT touch infra-validation.yml |
| `actions/checkout` pin from a sibling workflow | Dominant repo pin (63 uses incl. sibling `scheduled-realtime-probe.yml`): `34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1` | Pin checkout to `34e114876…` |

## User-Brand Impact

**If this lands broken, the user experiences:** nothing user-facing — this is a CI/ops watcher with no
runtime surface. The worst internal failure is a missed or duplicated evidence comment on a GitHub issue
the operator reads; the flip remains a deliberate human/agent step regardless.

**If this leaks, the user's data is exposed via:** no user data is touched. The watcher reads only CI run
metadata + the live-verify job log (already redacted at source by `redact-stdin.ts` per
`web-platform-release.yml`). It must never echo a full run log (`hr-never-run-commands-with-unbounded-output`);
it bounds every log read with `grep -m1`.

**Brand-survival threshold:** none — internal CI tooling, no user-facing artifact, no regulated-data
surface. (Threshold none + no sensitive-path touch -> no CPO sign-off required;
reason: a daily ops watcher that posts at most one GitHub issue comment and flips nothing has no single-user
blast radius.)

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC0 (operator pre-req surfaced):** The PR body states plainly that issue **5463 is currently CLOSED
      (accidental auto-close by PR #5519, which disclaims closing it) and must be REOPENED for the watcher
      to do anything** — the flip has not shipped (gate still `continue-on-error: true`). Use `Ref #5463`
      in the PR body, NOT `Closes #5463` (the watcher does not resolve the flip).
- [ ] **AC1 (RED first):** `scripts/watch-live-verify-pass.test.sh` is committed BEFORE the implementation
      in history (or in the same commit with the test demonstrably failing against an absent SUT first),
      and asserts cases (a)-(e) below. It runs with no network (mocks `gh` via PATH shim).
- [ ] **AC2:** `scripts/watch-live-verify-pass.sh` exists, is `chmod +x`, starts with `set -uo pipefail`
      (NOT `set -e`), and `bash -n scripts/watch-live-verify-pass.sh` parses clean.
- [ ] **AC3 (issue closed):** when mocked `gh issue view 5463` returns `state=CLOSED`, the script makes
      ZERO `gh issue comment` calls and exits 0. (`grep -c "issue comment" <captured gh args>` == 0.)
- [ ] **AC4 (idempotent record-once):** when mocked issue 5463 is OPEN but already has a comment containing
      `live-verify-pass-watch:recorded`, the script makes ZERO new `gh issue comment` calls, echoes
      "already recorded", exits 0.
- [ ] **AC5 (PASS recorded):** when issue 5463 is OPEN, no sentinel present, and a completed run's
      `live-verify` job has step `Run live-verify harness (report-only)` with conclusion != skipped AND its
      job log's first `RESULT:` match is `RESULT: PASS`, the script makes EXACTLY ONE `gh issue comment 5463`
      whose body contains: the run URL, the head SHA, the `RESULT: PASS` line, the
      `/soleur:one-shot 5463 (must merge as a separate, later deploy)` unblock line, AND the HTML-comment
      sentinel `<!-- live-verify-pass-watch:recorded run=<id> -->`. Exits 0.
- [ ] **AC6 (FAIL ignored):** when the qualifying run's first `RESULT:` match is `RESULT: FAIL`, ZERO
      `gh issue comment` calls; echoes "no qualifying live-verify PASS observed yet"; exits 0.
- [ ] **AC7 (all skipped):** when every scanned run's harness step is `skipped` (or absent), ZERO
      `gh issue comment` calls; exits 0.
- [ ] **AC8 (bounded log read):** the script never pipes a full `gh run view --log` to stdout — every log
      read is `grep -m1 -oE 'RESULT: (PASS|FAIL|CANT-RUN[^[:space:]]*)'` (verified by
      `grep -n "run view --job" scripts/watch-live-verify-pass.sh` showing a `grep -m1` on the same line/pipe;
      no bare `gh run view --log` echo).
- [ ] **AC9 (workflow shape):** `.github/workflows/live-verify-pass-watch.yml` exists with
      `on: { schedule: [{cron: "23 8 * * *"}], workflow_dispatch: {} }`,
      `permissions: { issues: write, actions: read, contents: read }`, one `ubuntu-latest` job that runs
      `actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5` then
      `bash scripts/watch-live-verify-pass.sh` with env `GH_TOKEN: ${{ github.token }}` and
      `GH_REPO: ${{ github.repository }}`. NO `claude-code-action`/`anthropics/` reference appears.
      `actionlint .github/workflows/live-verify-pass-watch.yml` passes (and embedded `run:` shell checked
      via `bash -n` on the extracted snippet, never `bash -n` on the .yml).
- [ ] **AC10 (self-disable contract documented):** the workflow header comment documents that once issue
      5463 closes (after the flip ships), the daily run early-exits as a cheap no-op, and the flip PR should
      DELETE this workflow + `scripts/watch-live-verify-pass.sh` + `scripts/watch-live-verify-pass.test.sh`
      + its `test-all.sh` line.
- [ ] **AC11 (CI wiring):** `scripts/test-all.sh` gains a `run_suite "scripts/watch-live-verify-pass" bash
      scripts/watch-live-verify-pass.test.sh` line inside the `scripts` shard block, and
      `bash scripts/watch-live-verify-pass.test.sh` exits 0 with all assertions passing.

### Post-merge (operator)

- [ ] **AC12:** Operator **reopens issue 5463** (`gh issue reopen 5463`) so the watcher can begin recording.
      Automation: feasible (`gh issue reopen 5463` via Bash), but it is a deliberate decision to re-arm the
      flip tracker, so it is left as an explicit operator action in the ship report rather than auto-run by
      this PR. After reopen, the next daily fire (or a `workflow_dispatch`) begins scanning.

## Implementation Phases

### Phase 0 — Preconditions (grep-verify before writing)

1. Confirm the live job/step names are unchanged: `gh run list --workflow=web-platform-release.yml
   --limit 1 --status completed --json databaseId --jq '.[0].databaseId'` then
   `gh run view <id> --json jobs --jq '.jobs[] | select(.name=="live-verify") | .steps[].name'` shows
   `Run live-verify harness (report-only)`. (Already verified at plan time; re-confirm at /work.)
2. Confirm test wiring target: `grep -n 'run_suite "scripts/sentry-issue"' scripts/test-all.sh` locates the
   `scripts` shard block to append into.

### Phase 1 — RED: `scripts/watch-live-verify-pass.test.sh`

Write the test FIRST, modeled on `scripts/sentry-issue.test.sh` (PATH-prepended mock that logs every
invocation to a temp file, subshell isolation, `check()` helper counting PASS/FAIL, exit non-zero on any
FAIL). Mock **`gh`** (not curl) via a `$mock_dir/gh` shim that dispatches on `$*`:

- `issue view 5463 ... state ...` -> emit fixture JSON `{"state":"<OPEN|CLOSED>"}` (toggled by an env var
  e.g. `MOCK_ISSUE_STATE`).
- `issue view 5463 ... comments ...` (sentinel scan) -> emit fixture comment bodies; include
  `live-verify-pass-watch:recorded` iff `MOCK_SENTINEL_PRESENT=1`.
- `run list --workflow=web-platform-release.yml ...` -> emit fixture array of completed runs
  `[{databaseId,headSha,url,status}]`.
- `run view <id> --json jobs` -> emit fixture jobs with a `live-verify` job whose
  `Run live-verify harness (report-only)` step conclusion is toggled (`skipped` vs `success`) and whose job
  `databaseId` is fixed.
- `run view --job <dbId> --log` -> emit a fixture multi-line log whose RESULT line is toggled by
  `MOCK_RESULT` (`PASS`/`FAIL`/none).
- `issue comment 5463 ...` -> append `$*` (and capture `--body-file` contents) to `$mock_dir/comment_args`
  so assertions can count calls and inspect body.

Assertions (map 1:1 to AC3-AC8):
(a) CLOSED -> `comment_args` empty, rc 0.
(b) OPEN + sentinel -> `comment_args` empty, rc 0, stdout contains "already recorded".
(c) OPEN + no sentinel + harness step `success` + log `RESULT: PASS` -> exactly one comment; body contains
    run url + sentinel `live-verify-pass-watch:recorded run=`.
(d) same as (c) but log `RESULT: FAIL` -> `comment_args` empty, rc 0.
(e) OPEN + no sentinel + all harness steps `skipped` -> `comment_args` empty, rc 0.

No network: the shim is the only `gh`; the SUT inherits `GH_TOKEN`/`GH_REPO` from the test env (dummy
values) and never calls the real CLI.

### Phase 2 — GREEN: `scripts/watch-live-verify-pass.sh`

`#!/usr/bin/env bash` + `set -uo pipefail` (NOT `-e`; matches the "harness must finish recording even on
non-zero subcommand" rationale used in `web-platform-release.yml` and `scheduled-realtime-probe.yml`).
`ISSUE=5463`, `SENTINEL="live-verify-pass-watch:recorded"`.

Logic (exactly the spec'd a-e):
- (a) `state=$(gh issue view "$ISSUE" --json state --jq .state)`; if `state != OPEN` -> echo "issue $ISSUE
  is $state — nothing to record (self-disable)"; exit 0.
- (b) if `gh issue view "$ISSUE" --json comments --jq '.comments[].body'` contains `$SENTINEL` -> echo
  "already recorded"; exit 0.
- (c) `gh run list --workflow=web-platform-release.yml --limit 25 --status completed --json
  databaseId,headSha,url,status` -> iterate newest-first. For each run:
  `gh run view <id> --json jobs` -> select job whose name contains `live-verify` -> read its
  `Run live-verify harness` step conclusion; if `skipped`/absent -> continue. Else capture that job's
  `databaseId` and read ONLY that job log, bounded:
  `line=$(gh run view --job "<jobDbId>" --log 2>/dev/null | grep -m1 -oE 'RESULT: (PASS|FAIL|CANT-RUN[^[:space:]]*)' || true)`.
  If `line == "RESULT: PASS"` -> capture run id/url/headSha + line; `break`. (FAIL/CANT-RUN -> do not record,
  continue to the next-older run; per spec the single purpose is to capture the FIRST PASS — a non-PASS
  qualifying run does not stop the scan.) Parse JSON with `jq` (present in ubuntu-latest + in the mocks).
- (d) if PASS captured -> write a `mktemp` body file (built with `printf`, not heredoc, to avoid
  leading-whitespace code-block traps — mirrors `scheduled-realtime-probe.yml`) containing run URL, head SHA,
  the RESULT line, the unblock line `flip is now unblocked — run /soleur:one-shot 5463 (must merge as a
  separate, later deploy)`, and `<!-- live-verify-pass-watch:recorded run=<id> -->`. Then
  `gh issue comment "$ISSUE" --body-file "$tmp"`. If `GITHUB_STEP_SUMMARY` is set, append one line. exit 0.
- (e) else echo "no qualifying live-verify PASS observed yet"; exit 0.

Bounding: every log read uses `grep -m1`; never `echo`/`cat` a full log (`hr-never-run-commands-with-unbounded-output`,
AC8).

### Phase 3 — Workflow `.github/workflows/live-verify-pass-watch.yml`

Plain scheduled workflow (NO claude-code-action). Header comment documents the SELF-DISABLE contract +
deletion instruction (AC10). `on: schedule (cron "23 8 * * *") + workflow_dispatch: {}`. `permissions:
{issues: write, actions: read, contents: read}`. `concurrency: { group: live-verify-pass-watch,
cancel-in-progress: false }` (mirrors sibling). One `ubuntu-latest` job, `timeout-minutes: 10`:
`actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4.3.1` then a `run: bash
scripts/watch-live-verify-pass.sh` step with `env: { GH_TOKEN: ${{ github.token }}, GH_REPO: ${{
github.repository }} }`. Do NOT auto-run the flip; the workflow only invokes the watcher.

### Phase 4 — CI wiring `scripts/test-all.sh`

Append inside the `scripts` shard block (next to `run_suite "scripts/sentry-issue" ...`):
`run_suite "scripts/watch-live-verify-pass" bash scripts/watch-live-verify-pass.test.sh`.

## Files to Create

- `scripts/watch-live-verify-pass.sh` (chmod +x)
- `scripts/watch-live-verify-pass.test.sh`
- `.github/workflows/live-verify-pass-watch.yml`

## Files to Edit

- `scripts/test-all.sh` — add one `run_suite` line in the `scripts` shard.

## Open Code-Review Overlap

None — no open `code-review`-labeled issue touches `scripts/watch-live-verify-pass.*`,
`.github/workflows/live-verify-pass-watch.yml`, or `scripts/test-all.sh` (new files; test-all.sh edit is
a single additive `run_suite` line).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — internal CI/ops tooling change. No user-facing surface (no
`components/**`, `app/**/page.tsx`, or other UI-surface path in Files to Create/Edit), so the Product/UX
gate is skipped. No regulated-data surface (the watcher reads CI metadata + an already-redacted job log),
so the GDPR gate (Phase 2.7) is skipped. No new server/host/secret/vendor/persistent-runtime process (a
scheduled GH Actions workflow using the built-in `github.token` is not new infrastructure provisioning), so
the IaC routing gate (Phase 2.8) is skipped. No architectural decision (a single-purpose evidence-recorder
that flips nothing changes no ownership/trust/substrate boundary and is not surprising to find undocumented
in the ADR corpus — ADR-033's "Inngest > GH Actions cron" preference concerns recurring application workers,
not a one-shot CI-metadata watcher whose self-disable contract is the whole point), so the ADR/C4 gate
(Phase 2.10) is skipped.

## Observability

```yaml
liveness_signal:
  what: "Daily scheduled run of live-verify-pass-watch.yml visible in the Actions tab; each run prints exactly one of: 'issue 5463 is <state>...', 'already recorded', the PASS-recorded summary line, or 'no qualifying live-verify PASS observed yet'."
  cadence: "daily (cron 23 8 * * *) + on-demand workflow_dispatch"
  alert_target: "none — best-effort evidence recorder; a missed daily run self-heals on the next fire, and the operator-facing signal is the issue comment itself"
  configured_in: ".github/workflows/live-verify-pass-watch.yml"
error_reporting:
  destination: "GitHub Actions run log (the step prints its terminal state); a gh subcommand failure surfaces as a non-zero subcommand inside set -uo pipefail (not -e) so the script continues and exits 0 best-effort"
  fail_loud: "the recorded PASS comment on issue 5463 is the loud, durable signal; the $GITHUB_STEP_SUMMARY line is the in-run signal"
failure_modes:
  - mode: "gh run list / run view API transient failure"
    detection: "empty/garbled JSON -> jq yields nothing -> loop finds no qualifying PASS"
    alert_route: "none (next daily run retries); never blocks anything"
  - mode: "issue 5463 closed (post-flip OR the current accidental close)"
    detection: "state != OPEN guard"
    alert_route: "run-log echo 'issue 5463 is CLOSED — nothing to record'; this is the intended self-disable"
  - mode: "duplicate-record race (two runs overlap)"
    detection: "sentinel scan in guard (b) + concurrency group cancel-in-progress:false serializes"
    alert_route: "second run echoes 'already recorded', no second comment"
logs:
  where: "GitHub Actions run logs for live-verify-pass-watch.yml (Actions UI, no SSH)"
  retention: "GitHub default Actions log retention (90 days)"
discoverability_test:
  command: "gh workflow run live-verify-pass-watch.yml && gh run list --workflow=live-verify-pass-watch.yml --limit 1"
  expected_output: "a run appears; its log prints one of the four terminal states; if a PASS was recorded, gh issue view 5463 --json comments shows the sentinel comment"
```

## Scheduled-Work Precedent (deepen Phase 4.4 — Inngest vs GH Actions cron)

ADR-033 makes Inngest the canonical substrate for scheduled work (43 `cron-*.ts` functions exist). The
deepen-plan 4.4 carve-out: *GH Actions cron is acceptable when (a) the work is purely git/repo-scoped (no
app context, no app secrets, no Sentry integration) AND (b) the work could not benefit from `step.run`
memoization / Inngest replay.*

**This watcher is squarely in the carve-out:**
- Reads only GitHub CI run metadata + one already-redacted job log; writes one GitHub issue comment.
- Auth is the built-in `github.token` — NO app context, NO Doppler/app secret, NO Sentry.
- A single-shot scan with at most one idempotent comment gets no value from Inngest `step.run` replay.
- It mirrors the existing off-convention repo-scoped-CI-cron family of GH Actions workflows:
  `cla-evidence-timestamp.yml`, `kb-drift-walker.yml`, `rule-audit.yml`, `rule-metrics-aggregate.yml`,
  `secret-scan.yml`, `gdpr-gate-self-test.yml`, `codeql-to-issues.yml` — none of which are Inngest. The
  feature description's closest anchor, `scheduled-realtime-probe.yml`, is itself a GH Actions cron.

**Filename decision:** keep the spec'd `live-verify-pass-watch.yml`. The PreToolUse hook
`.claude/hooks/new-scheduled-cron-prefer-inngest.sh` fires ONLY on the `scheduled-*.yml` glob (verified at
its `case "$file_path"` guard), so this filename is allowed without an override marker. Renaming to
`scheduled-*` purely to opt into a hook that would then demand a `<!-- gate-override -->` marker is more
ceremony than this explicit prose justification. The decision is recorded here so reviewers see the
carve-out reasoning rather than suspecting an off-convention dodge.

## Research Insights

**Implementation details (hardening over the spec):**
- Set `GH_PAGER=cat` (or `--no-pager` where supported) at the top of the script so `gh` never blocks on a
  pager in CI. `GH_TOKEN`/`GH_REPO` come from the workflow `env:`.
- `gh run list --workflow=web-platform-release.yml --limit 25 --status completed --json
  databaseId,headSha,url,status` already filters to completed runs (the spec's "completed only"); no
  client-side status filter needed. Iterate newest-first with `jq -c '.[]'` (one compact JSON object per
  line) and a `while IFS= read -r run; do ... done` loop — avoids word-splitting on URLs/SHAs.
- Select the live-verify job + harness step with `jq`:
  `gh run view "$run_id" --json jobs --jq '.jobs[] | select(.name | contains("live-verify")) | {db: .databaseId, conc: (.steps[] | select(.name | contains("Run live-verify harness")) | .conclusion)}'`.
  A `skipped` or absent `conc` -> `continue`.
- Bounded log read (the load-bearing `hr-never-run-commands-with-unbounded-output` line):
  `gh run view --job "$job_db" --log 2>/dev/null | grep -m1 -oE 'RESULT: (PASS|FAIL|CANT-RUN[^[:space:]]*)' || true`.
  `grep -m1` stops reading at the first match; the full log is never echoed.
- Build the comment body with `printf` into a `mktemp` file and pass `--body-file` (mirrors
  `scheduled-realtime-probe.yml`'s `BODY_FILE` pattern — avoids heredoc leading-whitespace code-block
  traps and shell-quoting hazards in the RESULT line).
- `set -uo pipefail` (NOT `-e`): a transient `gh` API failure mid-scan must not abort the script before it
  can exit 0 best-effort (same rationale the release workflow documents with `set +e` around its harness).

**Bash-strict-mode edge (deepen quality check):** the script uses NO numeric `[[ -gt ]]`/`$(( ))` on
external values, so the `set -e` numeric-crash class does not apply; string compares (`[ "$state" !=
"OPEN" ]`, `case`/`contains`) are safe under `set -uo pipefail`.

**Test-mock edge (deepen quality check):** the `gh` PATH-shim must dispatch on `$*` substring (e.g.,
`*"issue view"*"--json state"*`, `*"run view --job"*`, `*"issue comment"*`) and emit valid JSON for the
`--json`/`--jq` forms. Because the SUT may call `--jq` itself, the simplest robust mock emits the already
`--jq`-projected value the SUT expects for each call shape (the sentinel test in `scripts/sentry-issue.test.sh`
mocks at the transport layer the same way). Capture `issue comment` invocations (including `--body-file`
contents) to a temp file so AC5/AC6/AC7 can count calls and inspect the body.

## Test Scenarios

Covered by `scripts/watch-live-verify-pass.test.sh` cases (a)-(e) mapped to AC3-AC8 above. All deterministic,
no network, `gh` fully mocked via PATH shim.

## Sharp Edges

- **STALE PREMISE — issue 5463 is CLOSED, not open.** It was auto-closed by PR #5519 (a prerequisite fix
  that explicitly says it does NOT close 5463). The flip has NOT shipped (gate still report-only). The
  watcher is correct as built, but it records nothing until an operator **reopens 5463** (`gh issue reopen
  5463`). Surfaced in AC0 + AC12. Do NOT "fix" this by removing the `state != OPEN -> exit 0` guard — that
  guard is the self-disable contract and must stay.
- A plan whose `## User-Brand Impact` section is empty or placeholder-only will fail `deepen-plan` Phase 4.6
  — this one is filled (threshold: none, with a non-empty reason).
- The harness step is `continue-on-error: true`, so its conclusion is `success` even on FAIL/CANT-RUN/skip.
  Never gate on conclusion — only on the `RESULT: PASS` log line. (The watcher checks conclusion ONLY to
  distinguish `skipped` from "ran"; the PASS verdict comes from the log.)
- `gh run view --job <dbId> --log` can be large; the read MUST be bounded with `grep -m1` and never echoed
  in full (`hr-never-run-commands-with-unbounded-output`).
- Register the test in `scripts/test-all.sh` `scripts` shard, NOT `infra-validation.yml` —
  `infra-validation.yml` is scoped to `apps/web-platform/infra/*.test.sh`; repo-root `scripts/*.test.sh` run
  via `test-all.sh run_suite`.
- The PR uses `Ref #5463`, not `Closes #5463` — the watcher does not resolve the flip; closing 5463 is the
  flip PR's job (and that PR should also delete this workflow + scripts).

## Components Invoked

soleur:plan (this skill), soleur:deepen-plan (next).
