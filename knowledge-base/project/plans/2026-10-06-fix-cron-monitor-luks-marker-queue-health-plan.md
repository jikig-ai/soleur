---
title: "fix(ci): close the two live cron-monitor defects — LUKS marker Doppler flag + queue-health jq/probe (one-shot #9429/#9533 sweep)"
date: 2026-10-06
slug: cron-monitor-luks-marker-queue-health
branch: feat-one-shot-9429-9533-cron-monitor-sweep
issue: 9429
closes: [9429, 9533]
type: bug
lane: cross-domain
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- ack justification: every Doppler write-verb string below names an EXISTING run-block call being edited inside workflows-luks-verify.yml (the marker config + write token are already Terraform-managed from the #9352 apply); this plan prescribes no operator CLI/console step and provisions no new resource. See "Gate evaluations that resolved to not-applicable". -->

## Overview

Two confirmed live defects in scheduled cron monitors, fixed in one sweep PR:

1. **#9429** — `.github/workflows/workspaces-luks-verify.yml`, job `web2_marker`: `marker_args=(--no-interactive -p "$W2L_MARKER_PROJECT" -c "$W2L_MARKER_CONFIG")` (line ~1093) is expanded on `doppler secrets get`, `set`, AND `delete`. `--no-interactive` is a `secrets set`-only flag on the installed Doppler CLI (v3.76.6); `get`/`delete` reject it with `unknown flag: --no-interactive`. Every `marker_state()` call therefore faults → `emit query_failed marker_read` → a red run every day since #9352 merged (Oct 1 ~20:31 UTC; the job has never been green). Token scope/expiry is ruled out (config, service token, and secret-absence semantics verified against the live Doppler API).
2. **#9533** — `.github/workflows/scheduled-actions-queue-health.yml`: two `gh issue list --json number,title --jq --arg t ...` sites (lines ~130, ~178) — `gh --jq` takes one expression and does not forward `--arg`, so `gh` exits 1 (`unknown arguments`) and `set -euo pipefail` kills each issue-filing step. Separately, `scripts/actions-queue-health.sh` (~line 137) exits `UNKNOWN` whenever `total_count` exceeds the fetched in-progress page length — but `total_count` is a point-in-time snapshot that races the page contents, so a run completing between the count and the page fetch produces a false UNKNOWN (the Oct 5 saturation-window verdicts).

Scope note: `lane:` defaulted to `cross-domain` — no `spec.md` exists for this branch to carry a lane forward from (TR2 fail-closed default).

## Research Insights

### Premise Validation (Phase 0.6)

| Cited premise | Verified | Result |
|---|---|---|
| #9429, #9533, #9513, #9510, #9475 open | `gh issue view` | all five OPEN — none stale |
| PR #9554 "modifies BOTH target workflow files including the exact `--jq --arg` lines" | `gh pr diff 9554` (91 files, 0 hunks on either target) | **STALE** — #9554 touches `pr-quality-guards.yml`, `constraint-gates.yml`, scripts, and KB files only. It *mentions* `workspaces-luks-verify.yml` in a learnings/plan doc as a battery-arming path. No content overlap → no merge-conflict resolution needed on the target lines. |
| `marker_args` at ~line 1091 | read of file | present at :1093 — confirmed |
| `--jq --arg` at ~:130 and ~:178 | `grep -n` | exactly those two sites; self-close step at ~:204 uses single-expression `--jq '.[].number'` (correct as-is) |
| Truncation guard at `scripts/actions-queue-health.sh` ~:131-141 | read of file | confirmed at ~:137-140: `[ "${IP_TOTAL:-0}" -gt "$IP_RUN_COUNT" ]` |
| Test stub `--no-interactive` assertion ~:1668 | read of file | confirmed at :1670 — the `for need` loop requires the flag on **every** doppler call |
| Worktree `feat-one-shot-9372-web2-luks-closing-change` touches the luks workflow "in unrelated sections" | PR #9569 file list | currently planning-docs only (4 files); no workflow edits yet — low near-term collision, rebase awareness only |
| Token scope/expiry ruled out via live Doppler API | per pre-established diagnosis | trusted as ground truth; not re-derived |

### Property List (Phase 0.6b)

1. `marker_state()` can actually read the marker — `get`/`delete` receive only flags the CLI accepts.
2. The next Doppler read fault is self-describing in the run log (underlying CLI error, token-sanitized).
3. Both issue-filing steps in `scheduled-actions-queue-health.yml` survive to their `gh issue create/comment` calls.
4. `UNKNOWN` is returned only on genuine in-progress truncation (full page AND `total_count` beyond it).
5. Fail-closed semantics preserved end-to-end: unreadable marker aborts without touching the marker; genuine truncation still UNKNOWNs.

### Cut List (Phase 0.6b)

- Repo-wide `--jq --arg` lint/sentinel — **cut**: incidence is exactly 2 sites in 1 file (`grep -rn -- '--jq --arg'` confirms); the convention is already documented in-repo (`workspaces-luks-verify.yml:894`, `zot-mirror-connector-6416.sh:125`, learnings `2026-04-15` + `2026-03-04`); a per-file static assertion inside `scripts/actions-queue-health.test.sh` covers recurrence at a tenth the machinery.
- Retry-once on the in-progress page race — **cut** (chose the alternative the diagnosis offered): delivered concurrency is measured from the page itself, so using the actual page length is exact; a retry adds an API call and still races.
- #9513 stall-check alerting fix — **cut**: different file (`merge-queue-stall-check.yml`), different mechanism (executor visibility, not a filing-step defect); stays its own issue.
- #9510, #9475 — **cut**: unrelated files; remain open as their own issues.
- Oct 5 ~19–22Z cancellations — **not a defect** (operator-designated Actions-capacity saturation); nothing to fix.

### Repo patterns and file paths

- `.github/workflows/workspaces-luks-verify.yml:905-909` — the in-repo canonical fail-open dedupe shape: `if ! existing="$(gh issue list ... --json number,title 2>/dev/null | jq -r --arg t "$title" 'map(select(.title == $t)) | .[0].number // empty')"; then ::error:: ...; existing=""; fi`. Mirror this (not a bare repipe) at both queue-health filing steps.
- `apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh` — Guard-3 harness: extracts the `id: marker` run body into `marker.sh`, stubs `curl`/`doppler`/`jq`, runs a 54-scenario behavioral battery (`g3_battery`) plus `g3_mut` mutation rows. The doppler stub (:1660-1690) models the CLI's flag surface — it must be taught the real v3.76.6 surface or the defect is untestable.
- Mutation anchors that must NOT churn: row 3 anchors on `doppler secrets delete "$W2L_MARKER_NAME" --yes "${marker_args[@]}" >/dev/null \`; row 17a on the `|| { echo "::error::writing the marker failed."...` block; row 17d on the `state="$(marker_state)" || { echo "::error::could not read the marker (Doppler fault). ...` line. The prescribed edit shape keeps all three byte-identical (diagnostics go **inside** `marker_state`, `--no-interactive` moves to the `set` argv only, `marker_args` name retained for `-p`/`-c`).
- `scripts/actions-queue-health.test.sh` — stub-backed verdict suite; test 19 (line ~339) currently asserts truncation→UNKNOWN on a `total_count=150, page=1 row` fixture, which under the corrected predicate is a *non*-truncating partial page — the fixture must be reshaped, and the Oct-5 race shape (7 rows, total_count=8) needs a new must-not-UNKNOWN case.
- `scripts/actions-queue-health.sh` knobs: `MAX_IP_RUNS` (default 100) is validated as a non-negative integer (:101) — usable in tests via `PROBE_ENV`.
- Battery-arming note: `.github/workflows/**` arms `lint-orphan-*` batteries; `workspaces-luks-verify.yml` additionally arms `cf-tunnel-liveness-gate-mutations` (W7_EXPECTED member) and `.claude/hooks/grep-q-pipe-guard.test.sh` arms on edits to the luks test file — expect heavier CI and keep all new grep reads herestring- or count-shaped, never `| grep -q` early-exit readers.

### Institutional learnings applied

- `2026-04-15-gh-jq-does-not-forward-arg-to-jq.md` — canonical convention: `--json` then standalone `jq --arg`.
- `2026-03-04-gh-jq-does-not-support-arg-flag.md` — same class, earlier instance.
- `2026-09-19-every-guard-i-shipped-pinned-spelling-not-the-executed-program.md` — the doppler stub must model CLI *behavior* (refuse the flag on get/delete), not just assert its presence.
- `2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md` — test 19's fixture must exercise the real predicate boundary, not a degenerate shape that reds under any predicate.
- `2026-10-05-the-drain-was-born-broken-and-the-waiver-hid-it.md` — born-broken machinery class; #9429's job has never been green.
- `2026-10-05-a-reader-that-exits-early-flipped-three-suites-and-the-stub-had-to-read-too.md` — early-exit-reader / pipefail class relevant to the sibling sweep (#9554) and to any new grep reads added here.

### Related issues / PRs

- #9352 — introduced `web2_marker` (Oct 1); the flag defect shipped with it.
- #9372 / PR #9569 — web-2 luks closing-change worktree; planning-docs only today, may later touch other sections of the same workflow.
- #9554 — pipefail sweep; **no file overlap** (corrects the sweep note), but its grep-q-pipe-guard battery arms on our edited test file.
- #9217 — pipefail tracker referenced by #9554.
- #8450 — the runner under-assignment incident the queue-health probe exists to detect.
- #9513, #9510, #9475 — explicitly out of scope (untouched files); remain open.
- Run 37325222325 — the log carrying `probe-stderr: UNKNOWN: in-progress runs truncated (7 of 8 > MAX_IP_RUNS=100)`; ground truth for the race diagnosis.
- Run 36997080884 — first #9429 failure (2026-10-02 10:44 UTC).

### Mode notes

- Cloud-detect: `not-local:no-devin-env` → proceeds normally.
- No Task/subagent spawn tool exists in this harness: the Phase 1 research fan-out, Phase 1.5b functional-overlap check, Phase 3 SpecFlow, and Phase 4.5 scoped advisor consult were executed inline by the planning orchestrator. Community/functional overlap is a non-question for a surgical fix of two confirmed in-repo defects. Plan-review panel could not be spawned for the same reason; diff-level review is deferred to `soleur:review` at PR time (recorded as a degraded gate, not a skip-by-choice).
- No brainstorm exists for this branch; feature description was already detailed → idea refinement skipped (pipeline mode).

## Research Reconciliation — Spec vs. Codebase

| Spec/brief claim | Codebase reality | Plan response |
|---|---|---|
| "open PR #9554 modifies BOTH target workflow files — including the exact `--jq --arg` lines" | `gh pr diff 9554`: zero hunks on either target file; it changed `--search`→`--label` on `EXISTING=` lines in *other* workflows | No content conflict to resolve. Plan notes only the CI-arming interaction (edited workflow files arm lint-orphan/cf-tunnel/grep-q batteries on both PRs). |
| "the 'File probe-unavailable note on UNKNOWN' step misuses gh --jq --arg (one expression)" | TWO sites, not one: line ~130 (UNDER_ASSIGNED filing) has the identical defect | Both sites fixed in the same PR — the issue body's own "check for the same pattern elsewhere in the file" instruction confirms. |
| "test asserts the literal ` --no-interactive ` presence" | The stub *requires* the flag on every verb — it currently certifies the buggy shape | Stub updated to model real CLI semantics: required on `set`, refused on `get`/`delete`. |

## Open Code-Review Overlap

None — `gh issue list --label code-review --state open` bodies checked against all five planned file paths; zero matches.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly — these are internal CI monitors; the blast radius is an operator losing an alarm channel (LUKS soak certification stalls silently, or queue starvation goes unfiled) rather than a product defect.
- **If this leaks, the user's [data / workflow / money] is exposed via:** the marker write token (`DOPPLER_TOKEN_WORKSPACES_LUKS_MARKER`) reaching a run log — already defended by an env-only token contract, a token-shape guard, and the test suite's token-leak assertions; the new diagnostic print re-sanitizes defensively.
- **Brand-survival threshold:** none
- `threshold: none, reason: internal CI-monitor repair with no user-facing surface; the only credential in scope is an existing CI service token whose env-only handling contract is unchanged and additionally guarded by the new sanitized fault print.`

## Goals

1. `doppler secrets get`/`delete` in `web2_marker` receive only `-p`/`-c` (+`--yes` on delete); `--no-interactive` reaches `secrets set` alone.
2. A `marker_read` fault prints the sanitized Doppler CLI error to the run log while still failing closed (no set/delete touched).
3. Both `EXISTING=` dedupe queries in `scheduled-actions-queue-health.yml` repipe through standalone `jq --arg`, mirroring the fail-open shape at `workspaces-luks-verify.yml:905`.
4. The in-progress truncation guard UNKNOWNs only on genuine truncation (`IP_RUN_COUNT >= MAX_IP_RUNS && IP_TOTAL > IP_RUN_COUNT`).
5. Both test suites updated so each fix is pinned by a red-on-regression scenario.

## Non-Goals

- **#9513** (`merge-queue-stall-check.yml` red-run alerting) — untouched file; remains open as its own issue.
- **#9510** (infra destroy-first replace recovery gap) — unrelated surface; remains open.
- **#9475** (runtime-ceiling flake under contention) — unrelated surface; remains open.
- Oct 5 ~19–22Z run cancellations — operator-designated capacity saturation, not a defect.
- Queued-path `total_count` staleness in `actions-queue-health.sh` (last-page fetch computes `page` from a possibly-stale count; a stale-high count yields a gracefully-empty tail page, not a false UNKNOWN) — noted residual, not fixed here.
- Any repo-wide `--jq --arg` sentinel (Cut List rationale).
- Retry of the in-progress list fetch (Cut List rationale).
- Changing the Sentry heartbeat verdict mapping or the `UNDER_ASSIGNED`/`SATURATED`/`HEALTHY` thresholds.

## Implementation Phases

### Phase 1 — #9429: set-only flag + self-describing fault (test first)

1.1 **Update the doppler stub** (`apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh`, ~:1670). Split the `for need` loop: `-p soleur` and `-c prd_workspaces_luks_marker` stay required on every call; `--no-interactive` becomes verb-conditional — REQUIRED on `"secrets set"` (exit 64 `set missing --no-interactive` if absent) and REFUSED on `get`/`delete` (exit 64 `doppler stub: --no-interactive is a set-only flag (#9429)`). Run the suite: it must RED against the unmodified workflow (failing test first).

1.2 **Edit `.github/workflows/workspaces-luks-verify.yml`** (~:1093): `marker_args=(-p "$W2L_MARKER_PROJECT" -c "$W2L_MARKER_CONFIG")` with a comment that `--no-interactive` is a set-only flag on the installed Doppler CLI (v3.76.6) — applied at the `set` call site only so it cannot be "uniformed" back into the shared array. Change the set call to `doppler secrets set "$W2L_MARKER_NAME" --no-interactive "${marker_args[@]}"`. `get`, the read-back `get`, and `delete --yes` keep `"${marker_args[@]}"` unchanged (preserves g3_mut anchors 3/17a/17d byte-for-byte).

1.3 **Diagnosability** — inside `marker_state()`, on the fault arm (after the `Could not find requested secret` check, before `return 1`), print a sanitized copy of `out` to stderr:

```bash
# Self-describing fault (#9429): the run log names the CLI's own error. The literal
# substitution is safe — the token-shape guard above pins DOPPLER_TOKEN to [A-Za-z0-9._-];
# the sed is a defensive second net for any other dp.* token shape.
sed -E 's/dp\.[a-z]+\.[A-Za-z0-9._-]+/[REDACTED-TOKEN]/g' \
  <<<"${out//$DOPPLER_TOKEN/[REDACTED-DOPPLER-TOKEN]}" >&2
return 1
```

Stderr (not stdout): `state="$(marker_state)"` captures stdout only, so the diagnostic cannot corrupt the verdict path; the `after="$(marker_state)"` post-delete re-verify benefits identically. The caller's `|| { ::error::could not read the marker ... }` line stays byte-identical (17d anchor).

1.4 **New scenario**: `S55` — duplicate of S24's shape (`p_ok r_ok "$P" nz 0 0 same query_failed marker_read FIXTURE_DOPPLER_GET_FAIL=1`) with `G3_NEEDLE='unable to reach the API'` asserting the underlying error reached the run log; append `S55` to `G3_EXPECTED_IDS`. Add mutation row `17g` removing the diagnostic `sed` line → S55 reds (asserted via the mutation battery). The existing `g3_expect` token-leak check (`grep -q 'dp.st.fixture0token'`) covers sanitization on the same scenario.

### Phase 2 — #9533a: repipe both filing steps

2.1 In `.github/workflows/scheduled-actions-queue-health.yml`, replace both `EXISTING=$(gh issue list ... --jq --arg t ...)` sites (~:130 `File action-required on runner under-assignment`, ~:178 `File probe-unavailable note on UNKNOWN`) with the fail-open two-stage shape mirrored from `workspaces-luks-verify.yml:905`:

```bash
# `gh --jq` takes one expression and does not forward --arg (#9533); the title match is a
# standalone second-stage jq. Fail-open with a visible ::error:: — an unguarded pipefail
# abort on a transient gh fault would silence the one step that exists to file the alarm
# (same trade as workspaces-luks-verify.yml:905: a duplicate issue is recoverable, a
# missed filing is not; the self-close sweep drains dupes by label).
if ! EXISTING="$(gh issue list --repo "$GH_REPO" --state open -L 50 \
  --label "ci/actions-queue-health" --json number,title 2>/dev/null \
  | jq -r --arg t "$ISSUE_TITLE" 'map(select(.title == $t)) | .[0].number // empty')"; then
  echo "::error::dedupe query failed (gh issue list) — filing without dedupe; a duplicate is the deliberate trade against filing nothing."
  EXISTING=""
fi
```

2.2 Re-grep the file: zero `--jq --arg` must remain; the self-close `--jq '.[].number'` (single expression, no `--arg`) is correct and stays.

2.3 **Static pin** in `scripts/actions-queue-health.test.sh`: a "workflow hygiene" block asserting `grep -c -- '--jq --arg' .github/workflows/scheduled-actions-queue-health.yml` == 0 (herestring/`grep -c`, never `| grep -q` — the grep-q-pipe-guard battery arms on edited test files) and that both `File action-required` / `File probe-unavailable` step names still exist. Red row: reverting either site reds the count assertion.

### Phase 3 — #9533b: genuine-truncation predicate (test first)

3.1 **Reshape test 19** (`scripts/actions-queue-health.test.sh` ~:339): the current fixture (`total_count=150`, 1 row) is a *partial* page under the corrected predicate — it must become genuine truncation: a full page (100 run rows via the `inprogress`-style builder, or `PROBE_ENV="MAX_IP_RUNS=1"` with `total_count=2`/1 row if the implementer prefers knob-scaled economy) → still expects `2`/`UNKNOWN:`. Both boundary directions get coverage:

- **19 (revised)** genuine truncation: `IP_RUN_COUNT >= MAX_IP_RUNS && IP_TOTAL > IP_RUN_COUNT` → `UNKNOWN` rc2 (fail-closed preserved).
- **19b** the Oct-5 race shape: `total_count=8`, 7 rows → does NOT UNKNOWN → proceeds to a verdict (`HEALTHY` with `queued_count 0` + `jobs_for` on each of the 7 run ids).
- **19c** boundary must-pass: page exactly full AND `IP_TOTAL == IP_RUN_COUNT` (e.g. `MAX_IP_RUNS=2`, 2 rows, `total_count=2`) → proceeds (a full page whose count matches is complete, not truncated).

3.2 **Script fix** (`scripts/actions-queue-health.sh` ~:137):

```bash
# total_count is a point-in-time snapshot that races the page: a run completing between
# the count read and the page fetch shows IP_TOTAL > IP_RUN_COUNT with NO truncation
# (#9533 — Oct 5 verdicts were this race, not a truncated list). Only a FULL page can be
# truncated; delivered concurrency below is measured from the page itself either way.
if [ "$IP_RUN_COUNT" -ge "$MAX_IP_RUNS" ] 2>/dev/null && [ "${IP_TOTAL:-0}" -gt "$IP_RUN_COUNT" ] 2>/dev/null; then
  echo "UNKNOWN: in-progress runs truncated (page full at MAX_IP_RUNS=$MAX_IP_RUNS, total_count=$IP_TOTAL)" >&2
  exit 2
fi
```

### Phase 4 — verify

4.1 `bash scripts/actions-queue-health.test.sh` and `bash apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh` exit 0.
4.2 `grep -n 'no-interactive' .github/workflows/workspaces-luks-verify.yml` → exactly one hit, the `secrets set` line. `grep -c -- '--jq --arg' .github/workflows/scheduled-actions-queue-health.yml` → `0`.
4.3 `bash -n` on the two edited workflow `run:` bodies (the luks suite already extracts/bashes Guard 3's `marker.sh`; run the queue-health step bodies through `bash -n` after extraction, or rely on the workflow's YAML+shell review in CI).
4.4 PR body: `Closes #9429` and `Closes #9533` in the body (not title, per `wg-use-closes-n-in-pr-body-not-title`) + `## Changelog` section; note the #9554 sibling (different files, no conflict) and that #9513/#9510/#9475 stay open.

## Files to Edit

- `.github/workflows/workspaces-luks-verify.yml` — `marker_args` definition (~:1093), `secrets set` call site (~:1118), `marker_state()` fault arm (~:1099).
- `apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh` — doppler stub flag-surface model (~:1670), new scenario S55 + `G3_EXPECTED_IDS`, optional mutation row 17g.
- `.github/workflows/scheduled-actions-queue-health.yml` — both `EXISTING=` dedupe queries (~:130, ~:178) → fail-open two-stage jq.
- `scripts/actions-queue-health.sh` — truncation guard predicate + comment (~:137).
- `scripts/actions-queue-health.test.sh` — test 19 reshape, new 19b/19c, workflow-hygiene static block.

## Files to Create

None.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---|---|---|
| 1 | "Diagnose the Doppler marker read (token scope/expiry vs. marker missing), keep the fail-closed semantics intact" [#9429] | Phase 1 (items 1.2–1.3); diagnosis documented in Overview/Research Insights | mapped |
| 2 | "repipe through standalone jq per the ship-skill convention" [#9533] | Phase 2 (items 2.1–2.2) | mapped |
| 3 | "read why the probe itself returns UNKNOWN on most runs" [#9533] | Phase 3; the read is recorded in Research Insights (run 37325222325, count/page race) | mapped |
| 4 | "Lower priority, file under the same sweep if touched: #9513 … #9510 … #9475" | — | descoped — justification: none of the three files is touched by this fix; each stays its own open issue per the brief's own condition |
| 5 | "Yesterday's ~20 cancellations at 19-22Z were Actions-capacity saturation — NOT defects; do not fix those" | — | descoped — justification: operator-designated non-defect |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| Edit `workspaces-luks-verify.yml` marker args/calls | "Diagnose the Doppler marker read … keep the fail-closed semantics intact" | asked |
| Sanitized fault print in `marker_state()` | "SECONDARY DIAGNOSABILITY GAP (worth fixing in the same PR): marker_state() … never prints it on the fault path" | asked (brief text) |
| Edit `scheduled-actions-queue-health.yml` dedupe queries | "repipe through standalone jq per the ship-skill convention" | asked |
| Edit `actions-queue-health.sh` predicate | "read why the probe itself returns UNKNOWN on most runs" | asked |
| Edit `workspaces-luks-verify-workflow.test.sh` stub + S55 | — | inferred — justification: `cq-write-failing-tests-before` + the stub currently certifies the buggy flag shape; without modeling the real CLI surface the fix is untestable and recurs undetected |
| Edit `actions-queue-health.test.sh` (19/19b/19c + hygiene block) | "Check `scripts/actions-queue-health.test.sh` for coverage of this predicate and add a case for the off-by-one race" | asked (brief text) |
| Fail-open `if ! EXISTING=` wrapper (beyond bare repipe) | — | inferred — justification: identical silent-alarm class already remediated in-repo at `workspaces-luks-verify.yml:905`; an unguarded `pipefail` abort re-silences the step that exists to file |

### Split Assessment

- Subsystems touched: 3 — `.github`, `scripts`, `apps/web-platform`
- Planned files: 5 | Estimated changed lines: ~90–130
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] AC1: `grep -n 'no-interactive' .github/workflows/workspaces-luks-verify.yml` returns exactly one line, and it is the `doppler secrets set` call; `get`/`delete` call sites carry zero occurrences.
- [ ] AC2: `marker_state()` prints the sanitized CLI error on the fault arm; scenario S55 asserts `unable to reach the API` reaches the run log, and the suite's token-leak check (`dp.st.fixture0token`) stays green on that scenario.
- [ ] AC3: `grep -c -- '--jq --arg' .github/workflows/scheduled-actions-queue-health.yml` prints `0`; both filing steps use `--json number,title` piped to standalone `jq --arg`.
- [ ] AC4: `scripts/actions-queue-health.sh` UNKNOWNs only when `IP_RUN_COUNT >= MAX_IP_RUNS && IP_TOTAL > IP_RUN_COUNT`; test 19 (genuine truncation) expects UNKNOWN rc2 and 19b (7-of-8 race) expects a non-UNKNOWN verdict.
- [ ] AC5: `bash scripts/actions-queue-health.test.sh` exits 0; `bash apps/web-platform/infra/workspaces-luks-verify-workflow.test.sh` exits 0 including Guard-3 mutation battery.
- [ ] AC6: PR body carries `Closes #9429` and `Closes #9533` plus a `## Changelog` section; #9513/#9510/#9475 are named as remaining open issues.
- [ ] AC7: no `| grep -q` early-exit readers added anywhere in the diff (grep-q-pipe-guard arms on the edited test file); all new grep reads are herestring or `grep -c` count-shaped.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — CI/workflow-machinery bug fix. Mechanical UI-surface override checked: `## Files to Edit`/`## Files to Create` contain no path matching the UI-surface term list or `components/**/*.tsx`/`app/**/page.tsx`/`app/**/layout.tsx` globs → Product tier NONE, no UX gate.

## Observability

```yaml
liveness_signal:
  what: Sentry Crons check-ins (existing, unchanged) — monitor-slug workspaces-luks-verify-web2 (daily schedule arm) and scheduled-actions-queue-health (*/30 schedule + Inngest dispatch fallback); missed check-ins page via sentry_cron_monitor
  cadence: daily (luks) / every 30 min (queue-health)
  alert_target: Sentry crons missed-check-in + error status
  configured_in: .github/workflows/workspaces-luks-verify.yml, .github/workflows/scheduled-actions-queue-health.yml (uses: ./.github/actions/sentry-heartbeat)
error_reporting:
  destination: GitHub run-log ::error:: lines + auto-filed issues ([ci/luks-verify-web2], [ci/actions-queue-health]); Sentry heartbeat status=error on red/UNDER_ASSIGNED outcomes
  fail_loud: yes — every failure arm emits ::error:: and a non-zero outcome class; the repaired dedupe step degrades with a visible ::error:: rather than aborting silently
failure_modes:
  - mode: Doppler CLI rejects call args or API unreachable
    detection: marker_state() fault arm — now prints the sanitized CLI error (self-describing); outcome query_failed/marker_read; auto-filed [ci/luks-verify-web2] issue + error check-in on the scheduled arm
    alert_route: filed issue + Sentry crons error
  - mode: genuine in-progress truncation (page full + total_count beyond)
    detection: UNKNOWN rc2 from scripts/actions-queue-health.sh → File probe-unavailable note step files/updates the soft issue
    alert_route: [ci/actions-queue-health] issue (soft, no action-required) — heartbeat stays ok
  - mode: transient gh fault during dedupe
    detection: ::error::dedupe query failed breadcrumb; step continues to file
    alert_route: run log + possible duplicate issue drained by the self-close sweep
logs:
  where: GitHub Actions run logs (probe-stderr prefix on queue-health; ::error:: lines on both)
  retention: repo Actions default (~90 days)
discoverability_test:
  command: grep -c -- '--no-interactive' .github/workflows/workspaces-luks-verify.yml
  expected_output: "1"
```

## Guard Contract

### Guard 1 — marker read fails closed, and says why

**Property.** A Doppler fault while reading the soak marker aborts the run WITHOUT touching the marker (no `set`/`delete` reaches Doppler), reports `query_failed marker_read`, and the run log names the underlying CLI error — never the token.

**Assembly.** `marker_state()` and its two call sites in the `id: marker` step (the pre-judge read and the post-delete re-verify); the doppler stub in the Guard-3 sandbox is the enforcement surface, modeling the real v3.76.6 flag table (`--no-interactive` legal only on `secrets set`).

**Mutation matrix.**

| # | Mutation | Expected red |
|---|---|---|
| 1 | Restore `--no-interactive` on the `secrets get` argv | stub refuses (exit 64) → every green/not-live scenario reds (S01, S26, …) |
| 2 | `state="$(marker_state)" || state=absent` (fault reads as absent) — existing row 17d | S24, S45 red |
| 3 | Drop the sanitized-diagnostic `sed` print (new row 17g) | S55 reds (needle `unable to reach the API` missing) |
| 4 | Harness: print `out` UNSANITIZED on the fault arm | `g3_expect` token-leak check reds on S55/S24 shape (`dp.st.fixture0token` in run log) |
| 5 | Must-PASS (non-canonical): `secrets set` carries `--no-interactive` while `get`/`delete` carry `-p`/`-c`/`--yes` only | whole battery stays green — the repaired shape is the non-canonical input the contract explicitly permits |

**Anchor.** The stub's flag table is the anchor: it refuses (64) any argv shape the real CLI would reject, so a flag-surface weakening cannot pass with suite green.

### Guard 2 — UNKNOWN only on genuine truncation

**Property.** The probe exits UNKNOWN (rc2) on the in-progress list if and only if the returned page is full at `MAX_IP_RUNS` AND `total_count` exceeds it; a partial page with a stale snapshot count proceeds to a verdict.

**Assembly.** The single predicate in `scripts/actions-queue-health.sh` (~:137) + the stub's `status=in_progress&per_page=*` endpoint fixture + tests 19/19b/19c. `MAX_IP_RUNS` is the only tuning input and is validated numeric.

**Mutation matrix.**

| # | Mutation | Expected red |
|---|---|---|
| 1 | Revert to `IP_TOTAL > IP_RUN_COUNT` alone (drop the full-page conjunct) | 19b reds (7-of-8 race false-UNKNOWNs) |
| 2 | Keep only `IP_RUN_COUNT >= MAX_IP_RUNS` (drop the `total` conjunct) | 19c reds (exact-fill boundary false-UNKNOWNs) |
| 3 | Swallow truncation (`exit 0`/delete the guard) | 19 reds (genuine truncation passes silently) |
| 4 | Harness: fixture emits `total_count` LESS than the page row count (nonsense shape) | suite must not UNKNOWN — discriminates a guard that fires on any inequality |

**Anchor.** The predicate is measured against the fixture the stub serves, not the fixture the suite expects: the stub answers only exact endpoint strings and STUB-UNEXPECTEDs anything else, so a guard reading a different field/expression shape cannot borrow a pass.

## Test Scenarios

| Scenario | Type | Expected |
|---|---|---|
| Guard-3 battery on repaired marker.sh (S01–S55) | behavioral | all green incl. S55 fault-diagnostic needle |
| Stub flag-table: `--no-interactive` on get/delete | stub refusal | exit 64 (regression can't re-land silently) |
| Queue-health suite tests 19/19b/19c | verdict logic | UNKNOWN / HEALTHY / HEALTHY as tabulated |
| Workflow-hygiene block | static | 0 `--jq --arg` in queue-health workflow |
| g3_mut rows 3/17a/17d anchors after edit | anchor stability | mutations still land exactly once |

## Risks / Sharp Edges

- **Anchor fragility:** g3_mut rows anchor byte-exact strings (`delete … --yes "${marker_args[@]}" >/dev/null \`, the `|| { ::error::writing the marker failed.…` block, the `state="$(marker_state)" || {…}` line). Keep `marker_args` as the `-p`/`-c` array name and put `--no-interactive` literally on the `set` line; put diagnostics INSIDE `marker_state`. If an anchor must change, update the mutation row in the same commit.
- **YAML indentation:** the `run:` bodies are space-exact; an indentation slip parses as a different step or fails `bash -n`.
- **Fail-open trade:** the dedupe wrapper can file a duplicate on a transient gh fault — deliberate (mirrors :905); the self-close sweep drains same-label dupes.
- **`marker_state` stderr vs stdout:** diagnostics must go to `>&2` or they corrupt `state`.
- **Doppler flag scope is version-pinned:** v3.76.6 rejects `--no-interactive` on get/delete; if the CLI action's pinned SHA changes, re-verify the flag table (comment cites the version).
- **`bash -n` is not a runtime check:** the stub refusal is what pins the argv shape; syntax-check alone would pass the old bug.
- **Pipefail discipline:** no `| grep -q` readers in new code (AC7); the self-close step's existing `grep -c` style is the template.
- **Collision bookkeeping:** no content overlap with PR #9554 (verified) and PR #9569 (docs-only today); if #9569 lands workflow edits first, expect a routine rebase — the hunks are in different steps of the same file.

### Gate evaluations that resolved to not-applicable

- **IaC routing (2.8):** the literal Doppler write-verb string appears in plan text → evaluated → N/A: the call lives in versioned workflow code (the IaC-adjacent surface), the marker config + write token are already Terraform-managed from the #9352 apply, no new resource is provisioned, and no operator CLI/console step is prescribed.
- **Encryption posture (2.11):** no new persistent store or cross-component connection (the Doppler read/write edge predates this change).
- **ADR/C4 (2.10):** restores documented fail-closed semantics; no boundary/substrate/invariant changes — a competent engineer reading the ADRs would not be misled after this ships.
- **GDPR (2.7):** no regulated-data surface; none of the four expansion triggers fire (no new cron/workflow is created — existing monitors are repaired).
- **Skill description budget (1.8):** no `SKILL.md` `description:` edits anywhere in scope.
- **Network-outage checklist (1.4):** no trigger pattern in the feature description.
- **Advisor consult (4.5):** no subagent-spawn mechanism in this harness; the change is single-purpose mechanical work with a confirmed diagnosis.
