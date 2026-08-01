---
title: "feat: production version-drift alerter — page when prod stops serving main"
issue: 7091
branch: feat-one-shot-7091-prod-version-drift-alert
date: 2026-08-01
type: enhancement
lane: cross-domain
brand_survival_threshold: aggregate pattern
requires_cpo_signoff: false
plan_version: 3
---

# feat: production version-drift alerter — page when prod stops serving main

> Spec lacks valid `lane:` (no `spec.md` exists for this branch) — defaulted to `cross-domain` (TR2 fail-closed).
>
> **v3** — revised after a 6-agent review panel (CTO, DHH, Kieran, code-simplicity,
> architecture-strategist, spec-flow). See `## Plan Review Revisions`. v3's core mechanism is
> **simpler** than v1's and strictly more correct.

## Overview

A red `Web Platform Release` run whose `deploy` job is **skipped** is a silent production
outage. There is no failed deploy step to classify — **the absence is the signal** — so prod
keeps serving the previous image indefinitely while `/health` returns 200 the entire time. On
2026-07-30 this left prod ~21h stale, discovered only incidentally by an unrelated PR's
post-merge verification.

This plan implements issue #7091's own **option 2**: a scheduled check asserting that production
is not missing any commit it should have, alerting only on staleness sustained beyond one release
cycle. Option 2 keys on the **outcome** ("prod is stale") rather than one **mechanism** of becoming
stale, so it also catches any future path where the deploy silently no-ops.

**Explicitly out of scope.** The release-outcome notifier's own defects are already fixed and
merged (#7137 bound `R_DEPLOY`; #7139 widened the email + Sentry-mirror `if:` conditions and added
`timeout-minutes: 2`). This plan does not re-implement, improve, or touch that job.

---

## Design Decision 1 — The invariant, as a single range query

**Prod is healthy iff it is missing no commit that would have triggered a deploy.**

```bash
PATHSPEC=(apps/web-platform/ plugins/soleur/
          ':(exclude)plugins/soleur/docs/' ':(exclude)plugins/soleur/test/')

missing=$(git log --first-parent --format='%H %ct' "${prod_sha}..origin/main" -- "${PATHSPEC[@]}")
rc=$?     # captured DIRECTLY — see the pipe trap below
#   rc != 0                          -> CHECK_ERROR (unknown/absent SHA, shallow clone)
#   rc == 0 and $missing empty       -> CLEAN
#   rc == 0 and non-empty            -> prod is behind; the LAST line's %ct is the staleness clock
```

**Use `git log --format`, not `git rev-list --format`.** Measured: `rev-list --format` interleaves a
bare `commit <sha>` header line before every entry, so a naive `tail -1` reads a header, not a
record. `git log --format` emits one clean `%H %ct` line per commit; `tail -1` is the oldest entry.
(Use `git rev-list --count` if only a count is wanted — but the clock needs the oldest record, so
one `git log` call serves both.)

**Capture `rc` directly from `git`, never through a pipe.** Measured on a bad revision:

```text
git log … deadbeef…..origin/main            -> rc=128   (correct)
git log … deadbeef…..origin/main | tail -1  -> rc=0     (masked — reads as CLEAN)
```

The piped form is how a broken checker silently reports "no drift".

This one query replaces the three separate mechanisms v1/v2 used (equality test, `merge-base
--is-ancestor` ancestry guard, and a newest-commit age clock), and is correct on every case each of
those got wrong:

| Case | Result | Why |
| --- | --- | --- |
| Steady state (live, verified) | `0` → **CLEAN** | prod has every qualifying commit |
| The 2026-07-30 incident (`prod=34654d7ab`) | `4` → **DRIFT** | four qualifying commits never reached prod |
| `workflow_dispatch`/`force_run` release, prod **ahead** (`b810cddde`) | `0` → **CLEAN** | range is empty when prod is ahead — no special case needed |
| prod serving a SHA not in main's history | `git` fails → **CHECK_ERROR** | `fatal: Invalid revision range` |
| Merge commits on `main` | correct | `--first-parent` (see below) |

**`--first-parent` is load-bearing, not decoration.** The repo has `allow_merge_commit: true` and
**35 merge commits** in `main`'s history (most recent 2026-07-11, `cbd6c948d`). Without
`--first-parent`, `git log`/`rev-list` history-simplification can resolve to a *feature-branch*
commit rather than the merge commit that actually triggered the release — a permanent, silent
disagreement with `check_changed`. Reproduced by review in a scratch repo; `--first-parent` fixes
it. On today's linear history it is a verified no-op, so it is free insurance.

**The clock is the OLDEST missing commit, not the newest.** This kills a hole that a newest-commit
clock has: if qualifying commits keep landing faster than the threshold while deploy is broken, a
newest-commit clock resets every time and **never escalates** while prod rots. Anchoring to the
oldest undeployed commit measures how long prod has *actually* been stale, and never resets.

The pathspec is a **named constant** with a **parity assertion** against
`jobs.release.with.path_filter` in the shipped workflow — keeping the classifier pure and
network-free, and moving drift detection to **CI time**
(`sentry-monitor-iac-parity.test.ts` precedent).

---

## Research Reconciliation — Spec vs. Codebase

The issue body's sketch is wrong in one load-bearing way; a reviewer-proposed alternative is wrong
in another. Both were falsified **empirically**, not by argument.

| Claim | Reality (verified 2026-08-01) | Response |
| --- | --- | --- |
| Compare `build_sha` to **main's HEAD** (issue body) | **FALSE — false-alarms continuously.** The release is path-filtered (`on.push.paths`; `path_filter: "apps/web-platform/ plugins/soleur/ :(exclude)plugins/soleur/docs/ :(exclude)plugins/soleur/test/"`). A `knowledge-base/`-only commit never deploys. Live proof: main HEAD `2579d2d70` is docs-only while prod correctly serves `b35736ded`. | Range query over the pathspec (Decision 1). |
| **CTO proposal:** use the published `web-v*` tag's target instead | **FALSE — would have missed the entire motivating incident.** `34654d7ab → web-v0.244.0` (the *stale* image); `3d9817134 → <no tag>`; `dc6dd1f70 → <no tag>`. The failed builds published no tag, so a tag-based checker compares prod to `34654d7ab` and reports **CLEAN**. The tag tracks "last successful release", not "what main says prod should run". | **Rejected on evidence.** |
| Plain equality is sufficient | **FALSE — confirmed false-positive class.** `workflow_dispatch` sets `force_run: true`, bypassing `check_changed` and deploying `github.sha` whatever it touches (`web-v0.247.5 → b810cddde`, a `.github/`-only commit). | Range query returns 0 when prod is ahead. |
| `git log -1 -- <pathspec>` is safe | **FALSE under merge topology.** 35 merge commits exist; `allow_merge_commit: true`. | `--first-parent`. |
| `/health` → 200, public, `build_sha` + `version` | **TRUE.** `{"status":"ok","version":"0.247.6","build_sha":"b35736ded…",…}` | Use as specified. |
| Use `/health`, not `/api/health` | **TRUE.** `/api/health` → `307 → /login`. | Use `/health`. |
| Compare on `build_sha`, not `version` | **TRUE.** Fixtured with a disagreeing cell. | Use `build_sha`. |

---

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — but the *absence* of this alarm
is what the 2026-07-30 incident already cost them: ~21h on a build missing every fix merged in that
window. A bug or security fix that merges but never reaches prod is indistinguishable, from the
user's side, from a fix never written. The worse failure mode is not "this alerts too often" but
"this goes quiet while prod is genuinely stale" — a green monitor over a broken system.

**If this leaks, the user's data / workflow / money is exposed via:** nothing. The workflow reads a
public unauthenticated endpoint (status, version, build SHA only) and public git metadata.

**Brand-survival threshold:** `aggregate pattern` — the failure mode is collective and
availability-shaped, not a per-user data incident. No personal data is read, written, or
transmitted. The severe sub-case (a security patch stranded off prod) is recorded in Risks and
motivates Decision 3's fail-loud discipline, not a threshold change.

---

## Design Decision 2 — Sustained-ness: stateless clock, threshold 195 min

**Alert only when `count > 0` AND `now − oldest_missing_commit.committer_date > 195 min`.**

*Why stateless:* this repo measured GHA `schedule:` dispatch jitter at **median 80–134 min late,
max 339 min** (`knowledge-base/project/learnings/2026-06-02-sentry-cron-margin-must-absorb-gha-dispatch-jitter.md`).
Any duration inferred from "N consecutive ticks" measures an interval that is not the interval. A
commit timestamp is immutable and readable in a single sample, so jitter can only **delay
detection** — never cause a false positive. The repo *does* support cross-run state (open-issue
`createdAt`); this plan uses an issue as the **dedupe/delivery channel**, not as the clock.

*Why 195.* The threshold must exceed the longest *legitimate* commit→deployed latency. `deploy` is
gated by a serial chain (measured from the shipped YAML):

| Job | `timeout-minutes` | `needs` |
| --- | --- | --- |
| `await-ci` | 60 | — |
| `migrate` | 30 | `[release, await-ci]` |
| `verify-migrations` | 15 | `migrate` |
| `deploy` | 90 | `[release, migrate, verify-migrations, verify-doppler-secrets, await-ci]` |
| **serial sum** | **195** | |

(`verify-doppler-secrets`, 10 min, is parallel and not additive.) 195 is the **sum of the
pipeline's own declared ceilings on the serial critical path** — a principled bound, not a guess.
Empirically ~4× the observed worst case (last 20 runs on `main`: p50 13–14 min, max 50 min
end-to-end).

Part B asserts `THRESHOLD_MIN >= sum(await-ci, migrate, verify-migrations, deploy)` read from the
shipped YAML — a **safe-direction** assertion: a timeout *increase* fails the suite.

**Known gap:** the `release` job declares no `timeout-minutes` (defaults 360), so the strictly
provable bound is 555. Pre-existing pipeline weakness; a follow-up issue is filed (Deferred Items).
195 remains far above every observed run, and the residual false positive self-heals on
recovery.

---

## Design Decision 3 — Three verdicts; never let "unknown" read as "clean"

| Verdict | Exit | Alerts? | Meaning |
| --- | --- | --- | --- |
| `CLEAN` | 0 | no | `count == 0` — prod has every qualifying commit (equal or ahead) |
| `DRIFT_PENDING` | 0 | no (logged) | `count > 0`, age ≤ threshold — a release is legitimately in flight |
| `DRIFT_SUSTAINED` | 1 | **yes** | `count > 0`, age > threshold — prod is stale |
| `CHECK_ERROR(reason)` | 2 | **yes** | cannot evaluate — unreachable after retries, malformed `build_sha`, `git rev-list` failure. A free-text `reason` carries the detail v1 spent four exit codes on. |
| *(any other exit)* | — | **yes** | abnormal abort — fails loud by allowlist, never checked in `ok` |

Shell discipline, per learnings this repo has already paid for:

- `set -uo pipefail`; every expansion guarded `${VAR:-}`, **with the guard's default leaning toward
  the alerting branch**.
- **Capture `rc` directly from `git`/`curl`, never through a pipe.** Demonstrated live while
  writing this plan: `git rev-list <bad-sha>..origin/main | head -2; echo $?` reports **0** because
  `head` supplied the status while `git` printed `fatal: Invalid revision range`. This is the exact
  trap `2026-07-02-gha-run-default-shell-has-pipefail-guard-grep-substitutions.md` documents, and
  it would turn a broken check into a silent CLEAN.
- `jq -r .build_sha` emits the literal string `null` for both `{}` and `{"build_sha":null}`
  (measured), empty for `{"build_sha":""}`, and a parse error for non-JSON. All four are validated
  to 40-hex before use.
- **curl is retried 3× with backoff inside the run** before `CHECK_ERROR`, so a single blip cannot
  open an issue.

---

## Design Decision 4 — GitHub Actions `schedule:`, not Inngest (ADR-033 gate-override)

`.claude/hooks/new-scheduled-cron-prefer-inngest.sh` blocks a new `schedule:` workflow without an
override marker. This workflow takes it on grounds *stronger* than the existing precedents: Inngest
cron functions execute **as code baked into whatever image is currently running**. An
Inngest-dispatched staleness check running from a stale image judges its own staleness using the
stale build's own logic, and has no independent view of `origin/main`. GHA gives fresh git history
via `actions/checkout` and an ephemeral runner independent of the host under test. (ADR-033's own
scope note additionally sanctions GHA for credential-light infra crons.)

---

## Design Decision 5 — Alert routing and its wiring

Three layers, reusing `scheduled-zot-restart-loop.yml`'s idiom verbatim:

1. **Resend email** to `ops@jikigai.com` via `./.github/actions/notify-ops-email`, **gated to
   first-detection only** (see below).
2. **Durable deduped GitHub issue** — title-search create-or-comment. Load-bearing, not redundant:
   #7095 showed an email-only alert fire three times across three days while prod stayed down.
   `action-required` is what `operator-digest` harvests.
3. **Sentry Crons heartbeat** via `./.github/actions/sentry-heartbeat`, `if: always()`,
   `continue-on-error: true` — the *liveness* layer ("did the monitor run at all").

**Wiring rules — each closes a specific reviewed defect:**

- **Alert-step conditions are stated in full, never `!cancelled()` alone.** `!cancelled()` is true
  for success *and* failure, so alone it would fire the email and issue on **every healthy tick**:

  ```yaml
  # drift alert steps
  if: ${{ !cancelled() && steps.check.outputs.exit_code == '1' }}
  # check-error alert steps
  if: ${{ !cancelled() && steps.check.outputs.exit_code == '2' }}
  # close-on-recovery step
  if: ${{ !cancelled() && steps.check.outputs.exit_code == '0' }}
  ```

- **The label must be bootstrapped before use.** `gh issue create --label` hard-fails on an
  undefined label, and this repo has already been burned by exactly that
  (`scripts/seccomp-unenforced-alert.sh`, `scheduled-terraform-drift.yml`: "the verdict reached the
  email channel only; no action-required issue exists"). `ci/prod-version-drift` **does not exist
  yet**; `action-required`, `observability`, and `domain/engineering` were verified to exist. Every
  issue step is therefore preceded by:

  ```bash
  gh label create "ci/prod-version-drift" --repo "$GH_REPO" \
    --description "Standing alarm: production is serving a stale image" --color "B60205" 2>/dev/null || true
  ```

- **Close on recovery is an explicit step, not an aspiration.** On `exit_code == '0'`, search for
  the open tracking issue and `gh issue close` it with a recovery comment. Without this the issue
  never closes and the "one issue per episode" property is fiction.

- **Email is deduped to first detection.** The issue-lookup step emits
  `first_detection=true|false`; the email step is additionally gated on `first_detection == 'true'`.
  Otherwise a multi-hour outage re-sends the "synchronous push" email every 30 minutes.

- **The checker's exit code is DATA, not a job failure.** `out="$(bash scripts/…)"; rc=$?` written
  to `$GITHUB_OUTPUT`. Letting it `exit 1` the step would self-dark the liveness heartbeat.

- **The heartbeat's `ok` means "the monitor worked", not "prod is healthy" — and it accounts for
  delivery.** A detected drift is a *successful evaluation*; its surface is the issue and email.
  But if an alert was required and the email did not deliver, that IS a monitor failure (the
  release-outcome notifier's own lesson):

  ```yaml
  status: ${{ steps.check.outcome == 'success'
              && (steps.check.outputs.exit_code == '0'
                  || (steps.check.outputs.exit_code == '1' && steps.notify.outputs.delivered == '1'))
              && 'ok' || 'error' }}
  ```

  `steps.check.outcome` is the first conjunct per the #7138 lesson; the allowlist is the second
  line of defence (an absent output fails it to `error`).

**`CHECK_ERROR` gets a durable issue** — deliberately *unlike* `scheduled-zot-restart-loop.yml`'s
TRANSIENT class, which files none. Here an inability to evaluate means the drift signal is
**unobservable**, which is this repo's PRODUCER-SILENT class (which *does* file one). Copy-pasting
the TRANSIENT treatment would make a misconfiguration permanently silent — the exact defect class
this issue is about, one layer up. The 3× curl retry keeps this from being noisy.

---

## Files to Create

| Path | Purpose |
| --- | --- |
| `.github/workflows/scheduled-prod-version-drift.yml` | `*/30 * * * *` + `workflow_dispatch`; gate-override header; `fetch-depth: 0`; invoke checker; label bootstrap; drift / check-error / close-on-recovery steps; terminal heartbeat. |
| `scripts/prod-version-drift-check.sh` | Sourceable checker: pure `classify_drift()` + thin I/O `main()`. |
| `scripts/prod-version-drift-check.test.sh` | Structural suite — Part A fixtures, Part B wiring pins, Part C mutation battery, anti-vacuity floor. |

## Files to Edit

| Path | Change |
| --- | --- |
| `scripts/test-all.sh` | `run_suite "scripts/prod-version-drift-check" bash scripts/prod-version-drift-check.test.sh`. **Mandatory** — `scripts/lint-orphan-test-suites.sh` fails CI otherwise (`scripts/*.test.sh` is not auto-globbed). |
| `apps/web-platform/infra/sentry/cron-monitors.tf` | Add `sentry_cron_monitor "scheduled_prod_version_drift"` — `crontab = "*/30 * * * *"`, `checkin_margin_minutes = 30`, `max_runtime_minutes = 10`, `failure_issue_threshold = 1`, `recovery_threshold = 1`, `timezone = "UTC"`. |
| `knowledge-base/engineering/architecture/diagrams/model.c4` | Three corrections — see Architecture Decision. |
| `.github/workflows/web-platform-release.yml` | **Comments only** (2 lines): a forward-pointer at `with.path_filter` and at `deploy.timeout-minutes` noting that `scripts/prod-version-drift-check.sh` parity-asserts them, so an editor discovers the coupling at the source rather than via an unrelated red suite. No behaviour change; `.github/**` is outside the release path filter so this cannot trigger a release. |

All paths verified to exist (or, for the three new files, verified absent) at plan-write time.
`cron-monitors.tf` currently declares **51** `sentry_cron_monitor` resources
(`grep -c 'resource "sentry_cron_monitor"'`).

---

## Implementation Phases

**Phase 0 — Preconditions.** Re-run the Research Reconciliation validations; confirm
`jobs.release.with.path_filter` and the four `timeout-minutes`; confirm `python3 -c "import yaml"`;
read `scripts/inngest-liveness-classify.sh` + its test and `scheduled-zot-restart-loop.yml` as the
triple to mirror.

**Phase 1 — RED.** Write `scripts/prod-version-drift-check.test.sh` first
(`cq-write-failing-tests-before`). It must fail because the checker is absent, not vacuously.

**Phase 2 — GREEN: the checker.** `PATHSPEC` and `DRIFT_SUSTAINED_THRESHOLD_MIN=195` as documented
constants. `classify_drift()` pure: `(prod_json, curl_rc, missing_count, oldest_epoch, revlist_rc,
now_epoch)` → verdict + reason + exit code. `main()` does I/O only: curl with `--max-time` and 3×
backoff, then `git log --first-parent --format='%H %ct' "$prod_sha..origin/main" -- $PATHSPEC`
(**`log`, not `rev-list --format`** — the latter interleaves `commit <sha>` header lines) with `rc`
captured directly, **never through a pipe** (measured: `rc=128` direct vs `rc=0` piped). Emits
`DRIFT_VERDICT=`, `DRIFT_REASON=`, `DRIFT_DETAIL=`, `DRIFT_MISSING_COUNT=` for the workflow to parse.

**Phase 3 — The workflow.** Sibling conventions: gate-override marker at line 1 with the Decision 4
justification; `schedule` + bare `workflow_dispatch: {}`; `permissions: {contents: read, issues:
write}`; `concurrency: {group: scheduled-prod-version-drift, cancel-in-progress: false}`;
`runs-on: ubuntu-24.04`; **`timeout-minutes: 10`** (siblings pin 8/8/10; a loose timeout plus
`cancel-in-progress: false` would queue every subsequent tick behind a wedged run); SHA-pinned
`actions/checkout` with **`fetch-depth: 0`**; `strip_log_injection` before any `::error::`
interpolation; the five gated steps from Decision 5; terminal heartbeat.

**Phase 4 — Terraform monitor.** Add the resource with a header comment citing the
`margin == interval` rationale. Slug must equal the workflow's `monitor-slug`.

**Phase 5 — Register, C4, cross-reference comments.** `test-all.sh` registration; the three
`model.c4` corrections; the two forward-pointer comments in `web-platform-release.yml`.

**Phase 6 — Exit gate.** `bash scripts/test-all.sh scripts`,
`python3 scripts/lint-workflow-step-env-refs.py`, `bash scripts/lint-orphan-test-suites.sh`,
`python3 scripts/lint-encryption-posture.py --repo-sweep`, `actionlint`, `bash -n` on each extracted
`run:` body.

---

## Test Strategy

Bar set by `scripts/lint-workflow-step-env-refs.test.sh`: `set -uo pipefail` (no `-e`), `PASS`/`FAIL`
counters, `mktemp -d` + `trap … EXIT`, **assert on exit codes**, exit 1 if `FAIL > 0` **or** the
assertion count regresses below `MIN_ASSERTIONS`.

**On "execute the shipped artifact, not a copy":** this repo's dominant pattern is *not* YAML
extraction — it is factoring logic into a standalone `scripts/<name>.sh` that both the workflow and
the test invoke (`inngest-liveness-classify.sh`, `zot-restart-loop-alarm.sh`, `cron-artifact-age.sh`).
That satisfies the anti-drift intent more strongly because **there is no copy at all**. YAML
extraction is still required for what lives only in the YAML — the wiring — so the suite uses both.

### Part A — classifier fixtures (source the shipped script, drive `classify_drift`)

| # | Fixture | Expected |
| --- | --- | --- |
| A1 | `count == 0` | `CLEAN` / 0 |
| A2 | `count > 0`, oldest age = threshold − 1 | `DRIFT_PENDING` / 0 |
| A3 | `count > 0`, oldest age = threshold + 1 | `DRIFT_SUSTAINED` / 1 |
| A4 | **prod ahead** (`force_run` case) → `count == 0` | `CLEAN` / 0 |
| A5 | **`skip_deploy` dispatch** — prod deliberately behind, age > threshold | `DRIFT_SUSTAINED` (a *true* positive; the operator caused it — documented, auto-closes on next deploy) |
| A6 | **non-resetting clock:** newer qualifying commits land while the oldest stays > threshold | `DRIFT_SUSTAINED` — pins the perpetual-transient hole |
| A7 | **multi-commit push** where an earlier commit matches the pathspec but the push tip does not (so `check_changed` said `false` and deploy silently no-opped) | `DRIFT_SUSTAINED` — a genuine silent-no-op class this design catches |
| A8 | `git rev-list` fails (unknown prod SHA) | `CHECK_ERROR` / 2 |
| A9 | curl exhausted retries (rc 28) | `CHECK_ERROR` / 2, reason names the rc |
| A10 | curl rc 6 (DNS) | `CHECK_ERROR` / 2 |
| A11 | body `{}` → `jq` yields literal `null` | `CHECK_ERROR` / 2 |
| A12 | `build_sha: ""` | `CHECK_ERROR` / 2 |
| A13 | `build_sha` non-hex / wrong length | `CHECK_ERROR` / 2 |
| A14 | HTTP 200 with an HTML body | `CHECK_ERROR` / 2 |
| A15 | `oldest_epoch` unparseable | `CHECK_ERROR` / 2 |
| **A16** | **disagreeing cell:** `version` matches, `build_sha` differs, age > threshold | `DRIFT_SUSTAINED` — proves we key on `build_sha` |
| **A17** | **converse:** `version` differs, `build_sha` matches | `CLEAN` |

A16/A17 exist because *"whenever a comment argues 'we key on X, not Y', the fixture set must
contain a row where X and Y disagree"*.

### Part B — wiring pins (PyYAML extraction from the shipped workflow)

A hermetic unit test stays green after the workflow's call is deleted or relocated
(`2026-07-17-extract-inline-gate-test-must-pin-production-call-site.md`).

- **B1** The call to `scripts/prod-version-drift-check.sh` exists, in the expected job, **not**
  nested in a retry/poll loop.
- **B2** `actions/checkout` declares **`fetch-depth: 0`**. Not cosmetic: `origin/main` HEAD is
  frequently *not* a path-matching commit (it is not right now), so the range query needs full
  history on the *common* path — a shallow checkout puts the checker in permanent `CHECK_ERROR`.
- **B3** Each alert step's `if:` compared as a **whole normalised string**, asserting the
  `exit_code == '<n>'` conjunct is present — so neither a deleted disjunct nor a bare
  `!cancelled()` can ship.
- **B4** **No alert step is reachable when `exit_code` is `'0'`** — the anti-spam pin.
- **B5** `gh label create "ci/prod-version-drift"` appears **before** every `gh issue create` in the
  same step body.
- **B6** A close-on-recovery step exists and is gated on `exit_code == '0'`.
- **B7** Heartbeat `status:` — first conjunct is `steps.check.outcome == 'success'`, and the
  expression includes the `delivered == '1'` conjunct for the drift arm.
- **B8** Pathspec parity vs `jobs.release.with.path_filter`; the constant includes `--first-parent`.
- **B9** Threshold safety: `THRESHOLD_MIN >= sum(await-ci, migrate, verify-migrations, deploy)`.
- **B10** Monitor-slug parity vs `cron-monitors.tf`; job `timeout-minutes` ≤ the tick interval.
- Extraction selects steps by `id` with an **exactly-one cardinality assertion**, so a rename breaks
  loudly rather than silently extracting nothing.

Cross-step `env:` safety needs no bespoke assertion — `scripts/lint-workflow-step-env-refs.py`
already scans all workflows. Cited, not duplicated.

### Part C — mutation battery, by AXIS

Axes that catch sabotage **no unit fixture can see by construction**, plus the encoding bugs this
plan actually found. (v1's axes 1–3 were cut as entailed by the Part A fixtures they sat on.)

| Axis | Mutation | Must go red |
| --- | --- | --- |
| 1 | Delete the workflow's call-site | B1 |
| 2 | Replace the pathspec constant with main HEAD | B8 + the live false-alarm fixture |
| 3 | Drop `--first-parent` | B8 + a merge-topology fixture |
| 4 | Anchor the clock to the newest missing commit instead of the oldest | A6 |
| 5 | Replace an alert `if:` with a bare `!cancelled()` | B3 + B4 |
| 6 | Delete the `gh label create` bootstrap | B5 |
| 7 | Delete the close-on-recovery step | B6 |
| 8 | Flip the heartbeat `status:` first conjunct to the output value | B7 |
| 9 | Change `fetch-depth: 0` to `1` | B2 |
| 10 | Delete an assertion block | anti-vacuity floor |

Every mutation must **assert it landed** (`diff -q` / grep the mutated token) before its result is
scored, and the **unmutated control runs first and must be green** — a battery scored against a red
baseline is void.

---

## Observability

```yaml
liveness_signal:
  what: Sentry Crons check-in from ./.github/actions/sentry-heartbeat (monitor-slug scheduled-prod-version-drift)
  cadence: every 30 min (*/30 * * * *)
  alert_target: Sentry cron monitor failure_issue_threshold=1 -> Sentry issue -> sentry -> founder email route
  configured_in: apps/web-platform/infra/sentry/cron-monitors.tf + the workflow's terminal heartbeat step

error_reporting:
  destination: GitHub Actions run log (::error:: annotations, log-injection-stripped) + Resend email to ops@jikigai.com + a deduped action-required GitHub issue
  fail_loud: true — the heartbeat status is an allowlist (exit 0, or exit 1 with delivered=1; everything else including an absent output = error), so no unknown state can check in ok

failure_modes:
  - mode: prod serving a stale image (DRIFT_SUSTAINED, exit 1)
    detection: git rev-list range over the release pathspec + 195-min oldest-missing-commit clock
    alert_route: Resend email (first detection) + action-required GitHub issue (layer: Resend + GitHub Issues) — the operator-visible layer per hr-observability-layer-citation
  - mode: the check cannot be evaluated — prod unreachable after 3 retries, malformed build_sha, rev-list failure (CHECK_ERROR, exit 2)
    detection: same script, distinct exit code + free-text reason
    alert_route: Resend email + a SEPARATE action-required issue class + Sentry heartbeat `error` (layer: Sentry) — explicitly NOT collapsed into "no drift"
  - mode: the alert fires but the email does not deliver (revoked RESEND_API_KEY, Resend outage)
    detection: notify step emits delivered=0; the heartbeat's drift arm requires delivered == '1'
    alert_route: Sentry heartbeat `error` + ::error:: annotation (layer: Sentry)
  - mode: the checker never runs (workflow disabled, runner outage, schedule dropped)
    detection: Sentry cron monitor missed check-in, margin 30 == interval
    alert_route: Sentry issue -> founder (layer: Sentry). RESIDUAL EXPOSURE — see Risks (#7142)
  - mode: the checker runs but its step dies mid-way
    detection: heartbeat status's first conjunct is steps.check.outcome, and an absent exit_code output fails the allowlist
    alert_route: Sentry issue -> founder (layer: Sentry)
  - mode: shallow checkout silently breaks the range query
    detection: Part B assertion B2 at CI time; at runtime it surfaces as CHECK_ERROR, never CLEAN
    alert_route: CI red pre-merge (layer: GitHub Actions); post-merge via the CHECK_ERROR route

logs:
  where: GitHub Actions run log for scheduled-prod-version-drift (repo-visible, no SSH)
  retention: GitHub default workflow-log retention

discoverability_test:
  command: gh run list --workflow=scheduled-prod-version-drift.yml --limit 5 --json conclusion,createdAt && curl -fsS --max-time 10 https://app.soleur.ai/health | jq -r .build_sha
  expected_output: recent runs with conclusion success, and a 40-hex build_sha for which `git rev-list --first-parent --count <sha>..origin/main -- <pathspec>` is 0
```

No `ssh` appears in `discoverability_test.command`.

**Soak follow-through enrolment:** not applicable — no acceptance criterion is gated on a
post-deploy soak window.

---

## Infrastructure (IaC)

**Terraform changes.** One new `sentry_cron_monitor` in `apps/web-platform/infra/sentry/cron-monitors.tf`.
No new provider, version pin, variable, or secret — `RESEND_API_KEY` and the
`SENTRY_INGEST_DOMAIN`/`SENTRY_PROJECT_ID`/`SENTRY_PUBLIC_KEY` trio are already consumed by sibling
scheduled workflows.

**Apply path.** The Sentry root is auto-applied on push to `main` by `apply-sentry-infra.yml`, whose
`paths:` filter covers the whole `infra/sentry/**` tree and which has planned the **full root**
since #6589 — declaring the resource *is* applying it. **No operator step, no SSH, no dashboard
click.** Blast radius: one monitor; zero downtime.

**Margin sizing.** `checkin_margin_minutes = 30` for a `*/30` schedule follows the live
high-frequency GHA-fired precedent and its documented rationale in the same file: *"margin ==
interval MAXIMIZES jitter tolerance (a run up to one interval late still checks in — no false page
on GHA `schedule:` jitter), while a genuinely dark alarm still pages once the window closes"* —
applied to `scheduled_inngest_health` (`*/15`, margin 15) and `zot_restart_loop_alarm` (`*/30`,
margin 30). The 480-minute figure from PR #4772 governed the *twice-daily* cohort and is explicitly
marked superseded in-file. Residual risk noted in Risks.

**Distinctness / drift safeguards.** Sentry monitors are single-org (no dev/prd split). No
`lifecycle.ignore_changes` needed. No secret value enters `terraform.tfstate` (schedule metadata
only). Deletion is gated by `sentry-destroy-required` + `[ack-destroy]`; this plan only adds.

**Vendor-tier reality check.** `sentry_cron_monitor` is already used 51× in this file on the current
plan — no tier gate, no `count = var.*_paid_tier ? 1 : 0` guard needed.

**No duplication with existing uptime coverage** (verified): `uptime-monitors.tf` declares
`soleur_apex`, `soleur_www`, `soleur_changelog_deep`, `soleur_acme_probe` — all on `soleur.ai`
(marketing). **None covers `app.soleur.ai`**, so `CHECK_ERROR`-on-unreachable is not a competing
alert path.

---

## Encryption Posture

The Phase 2.11 detector fires because `## Files to Edit` includes a `\.tf$` path.

```yaml
at_rest:
  - store: no-store-introduced (the workflow is stateless between runs)
    mechanism: not-applicable-no-store — the checker holds no state; every run re-derives its verdict
               from a live HTTP read plus git history, and writes no file, table, bucket, volume, or cache
    evidence: the only .tf change adds a sentry_cron_monitor (schedule metadata only, no data plane);
              the resource TYPE already exists 51x in the same file, so lint-encryption-posture.py's
              R7 three-way resource-type partition is unchanged
    defends_against: nothing at rest, because nothing is written at rest
    does_not_defend: this row provides NO at-rest protection of any kind — if a future revision adds
                     caching of /health responses, a state file, or a results artifact, that store needs
                     its own posture row and this row must stop claiming statelessness
    disclosed_as: no disclosure required — no personal data and no persisted artifact exist to disclose
    live_verification: available — `gh run list --workflow=scheduled-prod-version-drift.yml` plus the
                       run log shows the full input/output surface; there is no store to introspect

in_transit:
  - connection: GitHub Actions runner -> https://app.soleur.ai/health
    tls: TLS 1.2+ via Cloudflare-proxied HTTPS (direct CF-proxied A record)
    cert_verification: on — plain curl, no -k/--insecure; the plan forbids adding one
    does_not_defend: does not defend against a compromised CF edge or a hostile response body; the
                     response is treated as untrusted input, validated to 40-hex, and log-injection-stripped
    disclosed_as: public unauthenticated endpoint; carries no personal data
  - connection: GitHub Actions runner -> api.resend.com
    tls: HTTPS via ./.github/actions/notify-ops-email
    cert_verification: on
    does_not_defend: does not defend against Resend-side compromise; alert content carries no personal data
    disclosed_as: already-disclosed Resend processing
  - connection: GitHub Actions runner -> Sentry cron check-in ingest
    tls: HTTPS via ./.github/actions/sentry-heartbeat
    cert_verification: on
    does_not_defend: does not defend against Sentry-side compromise; payload is a status enum only
    disclosed_as: already-disclosed Sentry processing (Art. 30 PA8, DE residency)
  - connection: GitHub Actions runner -> GitHub API (label bootstrap, issue dedupe/create/comment/close)
    tls: HTTPS via gh CLI with the job's scoped GITHUB_TOKEN (issues: write)
    cert_verification: on
    does_not_defend: does not defend against a compromised GITHUB_TOKEN, which could file or close
                     issues in this repo; scope is limited to issues:write and contents:read, so it
                     cannot push code or read secrets
    disclosed_as: first-party GitHub control plane, already covered by the repo's existing GitHub
                  processing; issue bodies carry only SHAs, counts, and run URLs — no personal data
```

No `plaintext-exception` and no `cert_verification: off`, so no `exception` block is required.

---

## Architecture Decision (ADR/C4)

### ADR

**No new ADR, and no amendment.** Reasoned against the gate's own test:

- The one divergence from a recorded ADR is GHA `schedule:` instead of Inngest (ADR-033). ADR-033
  supplies the sanctioned mechanism — the gate-override marker plus an in-workflow justification —
  and all three precedents (`scheduled-inngest-health.yml`, `scheduled-zot-restart-loop.yml`,
  `scheduled-cron-artifact-age.yml`) were verified to carry that marker **without** a dedicated ADR.
- The novel invariant is recorded where it is *enforceable*: a documented constant plus CI parity
  assertions — stronger than prose, which cannot go red.
- Independently corroborated by both the CTO and architecture-strategist advisories, and no
  `AP-NNN` principle in `principles-register.md` is violated (AP-001 and AP-005 are satisfied).

### C4 views

C4 **is** impacted. All three model files were read in full (`model.c4` 593 lines, `views.c4` 62,
`spec.c4` 54), not keyword-grepped. Enumeration:

| Category | Enumerated | Modelled? |
| --- | --- | --- |
| External human actor | `founder` (receives the page) | Yes — `sentry -> founder`, `betterstack -> founder` |
| External system | GitHub Actions (`github`) | Yes |
| External system | Sentry (`sentry`) | Yes — **`github -> sentry`'s description is falsified** |
| External system | Resend (`resend`) | Yes — **`github -> resend`'s description is falsified** |
| Container / data store | none new | n/a |
| Access relationship | CI reads prod's public `/health` to assert the served build SHA | **No — new edge required** |

Three `model.c4` edits, in scope:

1. **`github -> sentry`** — its description enumerates *"check-ins from 6 workflows — 3
   GHA-`schedule:`-fired … and 3 `workflow_dispatch`-only"* and *"Of 51 cron monitors, 7 check in
   from here and 44 from webapp."* A 4th GHA-`schedule:`-fired heartbeat falsifies every count
   (6→7, 3→4, 51→52, 7→8). The baseline 51 was re-verified by direct grep.
2. **`github -> resend`** — describes the release-outcome email as *"one of nine Resend emitters
   under `.github/`"*. This adds a tenth.
3. **New edge `github -> webapp`** — "Scheduled prod version-drift probe: reads the public
   unauthenticated `/health` and asserts prod is missing no commit matching the release path
   filter." Distinct from the existing `github -> webapp` edge (fix-constraints Stage B, Git Data
   API, ADR-074).

**`views.c4` needs no change:** no new *elements*, only edges between already-included elements plus
description corrections, so no `include` line is required for rendering. Run
`apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts` after editing.

---

## Domain Review

**Domains relevant:** Engineering

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Produced the two highest-value findings — the `force_run`/`workflow_dispatch`
false-positive class and the serial-chain threshold undercount — plus the `fetch-depth: 0`,
allowlist-not-denylist, and uptime-overlap checks, all folded in. Its tag-based alternative was
**rejected on evidence**. Concurs that no new ADR is warranted.

### Product/UX Gate

Not applicable. The mechanical UI-surface override was evaluated against `## Files to Create` and
`## Files to Edit`: no path matches `components/**/*.tsx`, `app/**/page.tsx`, `app/**/layout.tsx`,
or any UI-surface term. Product tier **NONE**.

Marketing, Sales, Finance, Legal, Support, Operations: not relevant — no pricing, contract, expense,
regulated-data, customer-facing, or vendor-account implication. No new recurring vendor expense
(~48 runner-minutes/day on an existing GitHub plan).

---

## GDPR / Compliance Gate

**Skipped — no regulated-data surface.** Evaluated against the canonical trigger regex (no schema,
migration, auth flow, API route, or `.sql` file) and all four expansion triggers: (a) no
LLM/external processing of operator-session data; (b) threshold is `aggregate pattern`; (c) reads
git metadata and a public health endpoint only; (d) no new artifact-distribution surface.

---

## Open Code-Review Overlap

Queried 62 open `code-review` issues against every planned path.

| Planned path | Matches |
| --- | --- |
| `scheduled-prod-version-drift`, `prod-version-drift`, `scripts/test-all.sh`, `cron-monitors.tf`, `sentry-heartbeat`, `notify-ops-email`, `/health` | None |
| `web-platform-release.yml` | **#3220** — "ci: postmerge verification of trigger-bearing migrations in prd" |

**Disposition for #3220 — Acknowledge.** It concerns post-merge verification of *database
migrations* carrying triggers. This plan touches `web-platform-release.yml` only to add two
comments. Different concern, no overlapping semantics. #3220 remains open.

---

## Acceptance Criteria

### Pre-merge (PR)

1. `bash scripts/prod-version-drift-check.test.sh` exits 0 with `Total` ≥ `MIN_ASSERTIONS`.
2. Part A covers all 17 fixtures, each asserting an **exit code**.
3. Part C: all 10 axes verified — each mutation asserted to have **landed** before scoring, control
   green first.
4. Axis 3: dropping `--first-parent` fails the merge-topology fixture.
5. Axis 4: anchoring the clock to the newest missing commit fails A6.
6. Axis 5: replacing an alert `if:` with a bare `!cancelled()` fails B3 **and** B4 — pinning that
   no alert can fire on a healthy tick.
7. Axis 6: deleting the `gh label create` bootstrap fails B5.
8. Axis 7: deleting the close-on-recovery step fails B6.
9. Axis 9: `fetch-depth: 1` fails B2.
10. `bash scripts/lint-orphan-test-suites.sh` exits 0.
11. `python3 scripts/lint-workflow-step-env-refs.py` exits 0 with the new workflow in scope.
12. `python3 scripts/lint-encryption-posture.py --repo-sweep` exits 0.
13. `actionlint` clean on the new workflow; each extracted `run:` body passes `bash -n`.
14. Line 1 carries `# <!-- gate-override: new-scheduled-cron-prefer-inngest -->` with a
    justification header.
15. `sentry-monitor-iac-parity.test.ts` passes (slug parity).
16. `c4-code-syntax.test.ts` + `c4-render.test.ts` pass after the `model.c4` edits.
17. The three historical cases are reproduced **as offline fixtures** (incident → DRIFT,
    `force_run` → CLEAN, steady state → CLEAN). *No live-network assertion appears in a pre-merge
    AC* — prod's state at CI time is not controllable, so a live check here would be flaky by
    construction.
18. `bash scripts/test-all.sh scripts` exits 0 — the gate's **own** invocation, not a
    hand-enumerated subset.

### Post-merge (all automated — no operator step)

19. `gh workflow run scheduled-prod-version-drift.yml`, then
    `gh run list --workflow=scheduled-prod-version-drift.yml --limit 1` shows
    `conclusion: success`, **and** the run log records a `DRIFT_VERDICT=` line. *(A new workflow
    cannot be dispatched until it exists on the default branch.)*
20. The Sentry monitor `scheduled-prod-version-drift` exists **and has received a check-in** —
    verified by API read, not dashboard eyeball (`hr-no-dashboard-eyeball-pull-data-yourself`).
    Asserting the resource exists is a *proxy*; asserting a check-in arrived is the invariant.
21. The alert path is exercised end-to-end **without waiting for a real outage**: dispatch the
    workflow once with an injected fixture SHA (an old commit) so it reaches `DRIFT_SUSTAINED`,
    confirm the label was created, the issue was filed, and the email delivered; then confirm the
    next clean run closes the issue. Asserting "the script exits 1" is a proxy; asserting the issue
    exists and then closes is the invariant.
22. `gh issue close 7091` after 19–21 pass.

**No step requires SSH, a dashboard click, a credential mint, or manual browser interaction.**

---

## Risks & Mitigations

| Risk | Mitigation |
| --- | --- |
| **Sentry's watch-the-watcher route pages only ONCE per sustained outage.** Per `model.c4`'s `sentry -> founder` note, the rule that routes cron-monitor failures is `New/ExistingHighPriorityIssueCondition` — first-seen or escalated-to, **not** recurrence: *"a repeat of an identical event is silent on this route"*. Tracked as **#7142**. So if the workflow goes dark, the founder is paged once and not again. | **Accepted and named**, not silently inherited. Partially mitigated because the two *primary* channels (email + issue) do not depend on Sentry — Sentry only covers "the workflow never ran". Adding a scoped `sentry_issue_alert` with `reappeared_event`/`regression_event` (mirroring `kb_sync_silent_failure`) is recorded as a Deferred Item; #7142 already tracks the general fix. |
| **`checkin_margin_minutes = 30` may false-page if GHA jitter exceeds one interval.** The cited jitter learning measured up to 339 min on a *twice-daily* cron. | Follows the live high-frequency precedent (`*/15`→15, `*/30`→30) and its in-file design comment; the 480 figure is marked superseded. High-frequency schedules are dispatched far more reliably than sparse ones. If false missed-check-in pages occur, widening the margin is a one-line Terraform change. |
| **The `release` job has no `timeout-minutes`** (defaults 360), so the strictly provable legitimate-latency bound is 555, not 195. | Pre-existing weakness, not introduced here. 195 is ~4× every observed run; the residual false positive self-heals on recovery. Follow-up issue filed (Deferred Items). |
| **`skip_deploy: true` dispatches produce a true-but-unwanted DRIFT.** | Correct behaviour — prod *is* deliberately stale. Documented in the script header and fixture A5; the issue auto-closes on the next deploy. |
| **The checker goes quiet while prod is genuinely stale.** | Five guards: Sentry cron monitor pages on a missed check-in; heartbeat status is an allowlist whose first conjunct is `steps.check.outcome`; the drift arm additionally requires `delivered == '1'`; `CHECK_ERROR` files a durable issue rather than being treated as transient; and `rc` is captured directly from `git`/`curl`, never through a pipe. |
| **Shallow checkout breaks the range query** on the common path (main HEAD is frequently not path-matching). | `fetch-depth: 0` mandatory, pinned by B2 and axis 9. At runtime it degrades to `CHECK_ERROR`, never `CLEAN`. |
| **A security fix stranded off prod.** | This plan is the detection. Latency drops from "until someone happens to ship something else" (21h observed) to ≤ ~3.75h. |
| **`/health` shape changes and `build_sha` disappears.** | `CHECK_ERROR`, not "no drift". Fixtures A11–A14. |
| **The release `path_filter` changes**, silently redefining "correct". | Parity assertion B8 fails in CI at the moment of divergence; a forward-pointer comment at the source site warns the editor first. |
| **Overlapping ticks racing to file duplicate issues.** | `concurrency: {group: …, cancel-in-progress: false}` **serializes** overlapping runs rather than racing them — verified as the same pattern in three sibling workflows. Stated explicitly rather than left implicit. |
| **An operator closes the tracking issue without fixing the drift.** | The next tick finds no open issue and files a new one. **Intentional** — closing without forward-deploying should reopen, since the condition is still true. |
| **Alert fatigue.** | Title-search dedupe (comment, don't refile) + explicit close-on-recovery; email gated to first detection only; 3× curl retry prevents blip-driven `CHECK_ERROR`. |
| **Log injection** from `/health` content into `::error::` annotations. | `strip_log_injection`, adopted verbatim from the sibling workflows. |

---

## Alternatives Considered

| Alternative | Verdict |
| --- | --- |
| **Issue #7091's option 1** — `workflow_run` notifier on `conclusion != success`. | **Rejected**, as the issue itself preferred. Keys on one *mechanism*, and is empirically noisy: **17 of the last 20** runs on `main` concluded `failure` (2 success, 1 cancelled) — a conclusion-based notifier would have paged 17 times for conditions that later self-resolved, while still missing any silent no-op. |
| **Compare to main HEAD** (issue body's sketch). | **Rejected — empirically falsified**; would false-alarm right now. |
| **Compare to the published `web-v*` tag's target** (CTO proposal). | **Rejected on evidence.** The 2026-07-30 failed builds published no tag, so a tag-based checker reports CLEAN and misses the motivating incident. |
| **Equality, or equality + `merge-base` ancestry** (v1/v2). | **Superseded.** The `rev-list` range subsumes both, handles merge topology via `--first-parent`, and removes a git call. |
| **Newest-missing-commit clock** (v2). | **Rejected.** Resets whenever a new qualifying commit lands, so a steady commit stream plus a broken deploy never escalates. Oldest-missing anchors correctly. |
| **Tick-counting** ("drift on N consecutive runs"). | **Rejected.** GHA jitter means the interval is not the interval; also slower and requires state. |
| **Open-issue `createdAt` as the clock.** | **Rejected as the clock, adopted as the channel.** |
| **In-flight-run suppression** — skip the alert while a release run for the missing commit is `queued`/`in_progress`. | **Deferred with a recorded trigger.** Would allow a tighter threshold, but adds a GitHub API dependency and another failure mode for a case not observed in 20 runs. Adopt if a false positive occurs. |
| **Runtime YAML parsing** of `path_filter` instead of constant + parity test. | **Rejected.** Keeps drift detection at CI time rather than 03:00 and preserves classifier purity. |
| **Better Stack heartbeat** instead of Sentry Crons. | **Rejected.** No sibling `scheduled-*.yml` pushes a pass/fail heartbeat to Better Stack. |
| **Seven-state verdict enum** (v1). | **Rejected after review.** Four states shared one alert path and one remediation; collapsed to `CHECK_ERROR(reason)`. |

---

## Deferred Items

Filed as issues rather than silently dropped (`wg-when-deferring-a-capability-create-a`):

1. **Bound the `release` job's runtime.** `web-platform-release.yml`'s `release` job declares no
   `timeout-minutes` (defaults 360), which forces this plan's threshold to be empirical-plus-margin
   rather than a strict declared bound. Out of scope because this plan deliberately does not change
   release behaviour. Re-evaluate on this plan's first false positive.
2. **Re-page on a sustained monitor outage (#7142).** Add a scoped `sentry_issue_alert` with
   `reappeared_event`/`regression_event` conditions so a dark drift-checker re-pages on a bounded
   cadence instead of once. #7142 already tracks the general repeat-suppression gap.
3. **Parity-test the C4 edge descriptions' embedded counts.** `model.c4`'s `github -> sentry` and
   `github -> resend` edges encode exact workflow/monitor counts in prose with no CI check, so every
   future scheduled-workflow addition silently stales them. Pre-existing convention gap.

---

## Plan Review Revisions (v1 → v3)

Six agents reviewed. Findings applied, and — importantly — three challenges **rejected on
evidence** rather than deferred to.

**Applied:**

| # | Source | Change |
| --- | --- | --- |
| R1 | CTO | Equality → recency. `workflow_dispatch`/`force_run` false-positive class fixed. |
| R2 | CTO | Threshold 90 → **195**, derived from the serial critical path's declared ceilings, not `deploy`'s timeout alone. |
| R3 | CTO | **`fetch-depth: 0`** promoted to a pinned invariant — the shallow-checkout failure is the *common* path. |
| R4 | CTO | Allowlist, not denylist, for the heartbeat status. |
| R5 | CTO | Verified no overlap with `uptime-monitors.tf`. Adopted the `scheduled-zot-restart-loop.yml` dedupe + `strip_log_injection` idiom and the stronger gate-override text. |
| R6 | **Kieran P0-1** | **`--first-parent`.** 35 merge commits exist on `main` and `allow_merge_commit: true`; without it the resolver can return a feature-branch commit and disagree with `check_changed` permanently. |
| R7 | **Kieran P0-2 + spec-flow** | **`gh label create` bootstrap.** `ci/prod-version-drift` does not exist; `gh issue create --label` hard-fails on it — a *documented* repo failure mode. Pinned by B5 + axis 6. |
| R8 | **spec-flow P0** | **Alert conditions stated in full.** A bare `!cancelled()` is true on success *and* failure, so as worded v2 would have emailed every 30 minutes forever. Pinned by B3 + B4 + axis 5. |
| R9 | **spec-flow P0** | **Explicit close-on-recovery step** (v2 asserted auto-close without specifying it). Pinned by B6 + axis 7. |
| R10 | **spec-flow P1** | **Email gated to first detection** — otherwise a multi-hour outage re-sends every tick. |
| R11 | **spec-flow P1** | **Heartbeat covers delivery** — `delivered == '1'` conjunct on the drift arm, so a revoked `RESEND_API_KEY` cannot check in `ok`. |
| R12 | **spec-flow P2** | **Clock anchored to the OLDEST missing commit.** A newest-commit clock resets on every new qualifying commit and never escalates while prod rots. Pinned by A6 + axis 4. |
| R13 | architecture P1-2 | #7142 repeat-suppression exposure named in Risks + Deferred, rather than silently inherited. |
| R14 | architecture P2-3 | Multi-commit-push silent-no-op added as fixture A7 — a real class this design catches. |
| R15 | architecture P2-7 | Job `timeout-minutes: 10` pinned explicitly; operator-closes-without-fixing behaviour documented as intentional. |
| R16 | architecture P2-4 | Two forward-pointer comments in `web-platform-release.yml` so the coupling is discoverable at the source. |
| R17 | Kieran P1-2 | Live-prod assertion removed from the pre-merge ACs (flaky by construction); moved to post-merge, where AC21 now exercises the alert path end-to-end. |
| R18 | Kieran/architecture P2 | Monitor count corrected **53 → 51**; failed-run count corrected **14 → 17 of 20**. |
| R19 | DHH + code-simplicity (**both panels, same scope → prefer delete**) | **7 verdict states → 3**; mutation axes refocused on sabotage no unit fixture can see; the separate `merge-base` call eliminated entirely by the range query. |

**Rejected, with evidence:**

| # | Challenge | Why rejected |
| --- | --- | --- |
| X1 | **CTO: replace the pathspec walk with the `web-v*` tag's target.** | Empirically falsified: the incident's failed builds published no tag, so a tag-based checker reports CLEAN and misses the outage this plan exists to catch. |
| X2 | **DHH + code-simplicity: cut the ancestry check entirely.** | Both were spawned before the CTO's `force_run` finding. Their concern is nonetheless *fully satisfied* in v3 — the `rev-list` range removed the `merge-base` call, the extra exit code, and the extra enum state, while still handling the case correctly. The cut landed; the capability stayed. |
| X3 | **Kieran: `checkin_margin_minutes` should follow the 480-minute GHA cohort.** | The 480 figure governed the *twice-daily* cohort and is marked **superseded in-file**. The live high-frequency GHA precedent is `margin == interval` with a documented rationale. Residual risk recorded in Risks with a one-line remedy. |

---

## Verification Ledger (deepen-plan pass, 2026-08-01)

Every absolute/negative claim in this plan was re-verified mechanically by command execution — not
by re-reading prose. **16/16 confirmed, 0 contradicted, 0 unverifiable.** Spot-check any of them
with the command in the right-hand column.

| Claim | Verdict | Command |
| --- | --- | --- |
| `/api/health` → 307 `/login` | confirms | `curl -sS -o /dev/null -w '%{http_code} %{redirect_url}' https://app.soleur.ai/api/health` |
| `/health` public, no auth, has `build_sha` + `version` | confirms | `curl -sS https://app.soleur.ai/health` |
| No existing workflow polls `/health` + compares `build_sha` on a schedule | confirms | `grep -rn build_sha .github/workflows/` (only the release job's own post-deploy gate) |
| `uptime-monitors.tf` has no `app.soleur.ai` monitor | confirms | all four `url` values are `soleur.ai`/`www.soleur.ai` |
| `scripts/*.test.sh` is not auto-globbed by `test-all.sh` | confirms | `test-all.sh` comment: *"`scripts/*.test.sh` is NOT covered by any glob here"* |
| `lint-orphan-test-suites.sh` fails CI on an unregistered suite | confirms | its loop + `exit 1` when `fails > 0` |
| `gh issue create --label <undefined>` hard-fails | confirms | `seccomp-unenforced-alert.sh`: *"HARD-FAILS on an unknown label"* |
| 3 labels exist; `ci/prod-version-drift` does not | confirms | `gh label list --limit 300` |
| `release` job declares no `timeout-minutes` | confirms | job block lines carry none (the 60 belongs to `await-ci`) |
| `.github/**` outside the release **push** path filter | confirms | `on.push.paths` lists only `apps/web-platform/**` + `plugins/soleur/**` |
| `jq -r .build_sha` → literal `null` for `{}` and `{"build_sha":null}` | confirms | both return `null`, exit 0 |
| 35 merge commits on `main`; `allow_merge_commit: true` | confirms | `git rev-list --merges --count origin/main`; `gh api repos/jikig-ai/soleur` |
| `cron-monitors.tf` declares 51 monitors | confirms | `grep -c 'resource "sentry_cron_monitor"'` |
| parity test auto-discovers workflows via `readdirSync` | confirms | `sentry-monitor-iac-parity.test.ts` `workflowHeartbeatSlugs()` |
| All 3 gate-override precedents carry the marker, none has an ADR | confirms | marker at line 1 of all three; zero ADR matches |
| bad-revision `git` returns 128; piped returns 0 | confirms | direct `rc=128`, `| head` `rc=0` |

Scoping note carried forward: the `.github/**` finding is about the **push** trigger only —
`workflow_dispatch` remains available on that workflow regardless of paths, which is exactly why the
`force_run` case in Decision 1 exists.

---

## Sharp Edges

- **A plan whose `## User-Brand Impact` section is empty or omits the threshold will fail
  `deepen-plan` Phase 4.6.**
- **Do not "simplify" to main HEAD, to equality, or to the release tag.** All three read as the
  obvious implementation; all three are falsified above with measurements. Axes 2 and 3 make two of
  them go red.
- **Do not drop `--first-parent`.** It is a no-op on today's linear history and load-bearing the
  moment a merge commit lands — 35 already have.
- **Do not anchor the staleness clock to the newest missing commit.** It resets forever under a
  steady commit stream and never escalates.
- **Never write a bare `!cancelled()` on an alert step.** It is true on success too; the verdict
  conjunct is what makes it an *alert* rather than a heartbeat-with-email.
- **`gh issue create --label` hard-fails on an undefined label.** Bootstrap first, always.
- **Do not add `continue-on-error:` to the checker step,** and do not let the checker `exit 1` the
  step. Exit code travels as **data** via `$GITHUB_OUTPUT`.
- **The heartbeat's `ok` means "the monitor worked", not "prod is healthy".** `DRIFT_SUSTAINED`
  checks in `ok` *provided the email delivered*; marking it `error` unconditionally would
  double-page and conflate "prod is stale" with "the checker is broken".
- **Capture `rc` directly from `git`/`curl`, never through a pipe.** Measured: `git log <bad>..main`
  returns **128**; the same command piped to `tail -1` returns **0** — a broken check reads as CLEAN.
- **Use `git log --format`, not `git rev-list --format`.** `rev-list --format` interleaves a bare
  `commit <sha>` line before every record, so `tail -1` returns a header rather than the oldest
  commit — the staleness clock would silently parse garbage. `rev-list --count` is fine for counting.
- **`fetch-depth: 0` is not optional.** `origin/main` HEAD is frequently not a path-matching commit.
- **`scripts/*.test.sh` is not auto-discovered** by `test-all.sh`. Registration is mandatory.
- **`jq -r .build_sha` prints the literal string `null`** for both `{}` and `{"build_sha":null}`.
- **The `sentry_cron_monitor` slug must match the workflow's `monitor-slug`,** or the monitor is
  permanently green over a dead alarm.
- **Declaring the Sentry resource IS applying it** (full-root plan since #6589). No separate apply
  step, and no dry run.
