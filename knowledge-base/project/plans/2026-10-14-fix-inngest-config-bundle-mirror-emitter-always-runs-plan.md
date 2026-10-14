---
title: "fix: build-inngest-config-bundle mirror emitter must run when the zot bridge fails"
date: 2026-10-14
slug: fix-inngest-config-bundle-mirror-emitter-always-runs
branch: feat-one-shot-7243-inngest-bundle-emitter-always-runs
issue: 7243
epic: 10205
lane: single-domain
type: fix
---

# fix: build-inngest-config-bundle mirror emitter must run when the zot bridge fails

## Enhancement Summary

**Deepened on:** 2026-10-14
**Sections enhanced:** 3 (Research Insights, Risks and Precedent Diff, Verification Evidence)
**Method:** proportionate to a ~50-line workflow fix. The plan-review panel (DHH, Kieran, code-simplicity) and two CTO rulings had already run, so the deepen pass ran every mandatory halt gate plus a live shell-semantics prototype, and did not re-fan-out the full agent roster (cost control; no new risk surface would be reached by it).

### Key Improvements

1. Mandatory gates 4.6 (User-Brand Impact), 4.7 (Observability), 4.8 (PAT-shape), 4.11 (Guard Contract via `scripts/lint-guard-contract.py`) and 4.12 (Scope Check) all pass; 4.9 (UI), 4.10 (encryption), 4.5 (network) and 4.55 (downtime) do not trigger.
2. The load-bearing shell semantics of the proposed step body were executed, not reasoned (see Verification Evidence).
3. A precedent diff against the two sibling `zot_mirror` steps is recorded.

### New Considerations Discovered

- Errexit is suppressed for the whole command group on the left of `||`, so the install group must be `&&`-chained; a `;`-separated group would swallow a failed `curl`. Measured below.
- The first-draft suite placement under `apps/web-platform/infra/` would have fired a production infra apply and a release on merge; resolved by CTO ruling R2.

## Overview

`.github/workflows/build-inngest-config-bundle.yml` gates its GHCR-to-zot copy step on the bridge
step's outcome (`if: steps.zot_bridge.outcome == 'success'`). When the Cloudflare-tunnel bridge
soft-fails, the copy step is skipped, the job stays green, and nothing is emitted: no step output,
no `::warning::`, no summary row. A bridge that fails on every dispatch is indistinguishable from
one that works. This is the #6416 defect, already fixed in `reusable-release.yml` and in
`build-inngest-bootstrap-image.yml`, and never swept into this workflow.

The fix keeps the step (and its future-proof id), drops the bridge gate, hands the bridge result to
the script as the `BRIDGE_OUTCOME` env var, and branches inside the script so a failed bridge or a
failed copy reaches one emitter. The step keeps `continue-on-error: true`: GHCR is authoritative
(D-ZOT) and this workflow has no mirror-only mode, so the zot copy is never the deliverable. The
run stays green, just no longer silent. A new suite extracts and executes the real step body.

No host impact. `cloud-init-registry.yml` and every Terraform root are untouched. Ref #7243, part of
epic #10205 (the PR body uses `Ref #7243`, never `Closes`).

## Premise Validation (Phase 0.6)

- #7243 is OPEN; epic #10205 is OPEN and lists the item unchecked (line 16 of its body).
- `git show origin/main:.github/workflows/build-inngest-config-bundle.yml` still carries the gate on
  the mirror step (verified by reading the worktree copy, which equals origin/main for this file).
- The reference pattern exists: `reusable-release.yml` step `zot_mirror` (gate `docker_build`,
  `BRIDGE_OUTCOME` env, `== 'failure'` branch) and `build-inngest-bootstrap-image.yml` step
  `zot_mirror` (no `if:`, `BRIDGE_OUTCOME` env, `!= "success"` branch into `degraded bridge_down`).
- Open draft PR 10257 edits the same workflow file but only the comment block in the crane copy
  step, not the `zot_bridge` / emitter step. Expect a trivial rebase.
- ADR corpus check: the mechanism (branch inside the step on an env-passed outcome) is the recorded
  conclusion of ADR-096 (amended) / ADR-166 and the #6416 learning, not a rejected alternative.
  No new architectural decision is made.
- Capability claims verified by reading: `web-platform-release.yml` excludes `plugins/soleur/test/**` and fires on `apps/web-platform/**`; `apply-web-platform-infra.yml` fires on `apps/web-platform/infra/**`; `test-all.sh` registers `plugins/soleur/test/*.test.sh` through `SUITE_GLOBS`; the precedent suite carries an `AFFECTED_*` declaration in `scripts/lib/test-affected-paths.sh` and rows in both shard manifests.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue / brief) | Reality | Plan response |
|---|---|---|
| "Gate it on `steps.docker_build.outcome == 'success'` instead" | `docker_build` has no `if:` and no `continue-on-error`, so a failed build already fails the job and the implicit `success()` skips the mirror. The gate is symmetry with `zot_bridge` and `reusable-release.yml`, not a needed guard. A step `if:` with no status function gets an implicit `success()` prepended, so the bridge's own `continue-on-error: true` is part of the property. | Keep the `docker_build` gate as the issue says (CTO ruling F2) and assert the bridge's `continue-on-error` in the guard. |
| "Emit a `::warning::` + a step-summary row" | The mirror step has no `id`, so no output can be read by a consumer today. | Add `id: zot_mirror` and write `mirror_status` / `mirror_reason` outputs, matching both siblings. |
| "The test executes the real block" | Sibling `inngest-bootstrap-mirror-only.test.sh` executes only the extracted `degraded()`; `reusable-release-zot-mirror-retry.test.sh` executes the whole extracted body under PATH stubs. | Follow the second: run the whole body under `bash -eo pipefail` (the runner's default shell) with stubbed `curl`, `sha256sum`, `sudo`, `crane`, `sleep`. |
| Suite location: the nearest family precedent lives in `apps/web-platform/infra/` | Merging any new file under `apps/web-platform/infra/**` fires `apply-web-platform-infra.yml` (a push-triggered production Terraform apply, expected no-op) and `web-platform-release.yml` (`apps/web-platform/**`). `plugins/soleur/test/**` is excluded from the release paths and is where the whole-body precedent lives. | Place the suite at `plugins/soleur/test/inngest-config-bundle-mirror.test.sh` (CTO ruling R2). Merging this PR then fires neither the infra apply nor a release. |
| Plan-review round 1 (DHH + code-simplicity, advisory) | The first draft also added an ERR trap, a post-copy digest parity check, a digest-summary row, a 14-row battery, 13 arms and a runbook sentence. None serves a property in the Property List; the brief names a narrow fix. | CTO ruling R1: trim to the brief; the cut items go to ONE tracking issue at ship time. |

## Research Insights

**Property List (Phase 0.6b)**

1. P1: When the bridge step ends in any state other than `success`, the mirror step still runs and emits a degrade signal (annotation, summary line, outputs) readable without opening a log.
2. P2: A failed crane install or a persistently failed `crane copy` emits the same signal rather than a bare red step.
3. P3: Neither of the above turns the run red; the GHCR publish stays the deliverable.
4. P4: A future edit that re-gates the step on the bridge, drops the bridge's `continue-on-error`, or breaks the branch is caught by a test that runs the real step body.

**Cut List (Phase 0.6b and plan-review round 1)**

| Mechanism | Property | Verdict |
|---|---|---|
| Slack notification step (the bootstrap workflow has one) | none: the issue's proposed fix asks for `::warning::` + a summary row | Cut. A dispatch-only, reviewer-gated run is watched by the dispatching operator. |
| ERR-trap backstop, digest parity check (`crane digest` vs `DIGEST`), `zot mirror` row on the HARD-6 digest step, automated zot backfill, runbook sentence | none in P1-P4 | Cut (CTO ruling R1). One tracking issue is filed at ship time listing all four with the re-evaluation trigger. Condition from the ruling: every fallible command before the emitter is `\|\| degraded`-routed, shown in Phase 1. |
| Per-stage crane install reasons (`crane_download` / `crane_verify` / `crane_extract`) | none | Collapsed to one `crane_install` route; the `sha256sum -c` stderr stays unredirected so a mismatch is in the step log. |
| `mirror_only` mode, cosign, blob validation, token preflight | none | Cut. Not in the ask. |
| Remediation text copied from the bootstrap workflow (`mirror_only`, re-dispatch) | none | Cut. Both claims are false here (no `mirror_only`; `VERSION` is a monotonic signed field). |

**Value-proposition measurement (Phase 0.6c):** no cost or performance saving is claimed.

**Institutional learnings applied** (`knowledge-base/project/learnings/`)

- `2026-07-15-guard-gate-and-probe-must-pin-the-thing-they-name.md`: read `outcome` never
  `conclusion` on a `continue-on-error` step; anchor log greps on an interpolated runtime value.
- `2026-07-30-the-step-that-could-not-report-and-the-guard-that-worked-in-one-scan-mode.md`:
  run blocks execute under `bash -eo pipefail {0}`; write outputs before any failing exit; run the
  suite under that same shell so a bare non-zero command aborts as it would in CI.
- `workflow-issues/smoke-test-workflow-steps-with-real-binary-shim-20260929.md`: extract the `run:`
  body with a YAML parser and run under a PATH shim; capture the real binary with `command -v`
  BEFORE prepending the shim directory so a shim cannot recurse into itself.
- `2026-10-06-a-line-anchored-extractor-cannot-see-a-prefixed-assignment.md`: keep captures in
  `VAR=$(cmd) || {...}` form, and floor operands on contiguous lines above the `if`
  (guard-vacuity-floor).
- `2026-09-18-local-composite-action-needs-checkout-continue-on-error-masks-it.md`: the same
  masking class; the test asserts the always-run emitter, not only the success branch.
- `2026-10-09-committed-ci-weights-are-not-local-costs.md`: regenerate the shard manifests with
  `--incremental` only; a wholesale regeneration rebalanced ten unrelated suites.
- `2026-05-11-pre-run-assertion-mock-stdout-trace-pollution.md`: stubs log to a file, never stdout.
- `2026-06-29-review-rate-limit-fallback-and-wallclock-exact-assertion-flake.md`: no
  `grep | head` under `-o pipefail`; no exact wall-clock assertions (the C.9 flake class).
- Pattern references: `plugins/soleur/test/reusable-release-zot-mirror-retry.test.sh` (whole-body
  execution under stubs) and `apps/web-platform/infra/inngest-bootstrap-mirror-only.test.sh`
  (YAML-parsed structural leg, `code_of` comment stripping, sentinel for return-vs-exit).

**Related:** #6416 (original defect), #7242 / ADR-166 (name only measured causes), epic #10205,
draft PR 10257 (same file, different step).

## Open Code-Review Overlap

Queried open `code-review` issues against every planned path. One match:

- #8800 (test fixture: census sandbox shares inodes/symlinks with live repo) touches `scripts/lib/test-affected-paths.sh`. Acknowledge: a fixture-isolation hazard in a different suite; this plan only appends one declaration array there, and the Phase 4 census run uses the repo's own invocation.

No match for the bundle workflow, the new suite, or either manifest.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing user-facing. This is a CI workflow
  for an operator-dispatched, reviewer-gated bundle publish that has never run in production. The
  worst realistic regression is that the zot copy stays silent when it fails, which is today's state.
- **If this leaks, the user's data / workflow / money is exposed via:** no vector. The change adds
  no secret, no credential read, and no new egress; it only reads a step outcome and writes
  annotations and a job summary.
- **Brand-survival threshold:** `none`
- **Threshold decision (challengeable):** `none` and not `aggregate pattern` because the artifact is
  a dark-safe convenience copy that no user-facing path or host reads (GHCR-direct is authoritative),
  and the workflow has zero recorded runs.

*Scope-out override:* `threshold: none, reason: the touched paths are a dispatch-only CI workflow and an infra test suite that no end-user request path executes and that handle no user data.`

## Files to Edit

- `.github/workflows/build-inngest-config-bundle.yml`: the mirror step (id, env, script). The gate expression changes from the bridge to `docker_build`.
- `scripts/lib/test-affected-paths.sh`: append `AFFECTED_PLUGINS_SOLEUR_TEST_INNGEST_CONFIG_BUNDLE_MIRROR_TEST_SH_PATHS` (the workflow, the suite, this file), mirroring the precedent block for `reusable-release-zot-mirror-retry.test.sh`. This is the consumer that makes a workflow-only diff select the suite (`scripts/test-all.sh` sources it). Add it only if the census (`scripts/lint-orphan-test-suites.sh`) reports the suite unclassified or the affected-selection dry run does not select the suite for a workflow-only diff.
- `scripts/suite-durations.tsv` and `scripts/suite-shard-legs.tsv`: one row each for the new suite via `python3 scripts/regenerate-shard-manifest.py --incremental --write`; keep only the new suite's rows (a wholesale regeneration rebalanced ten unrelated suites in an earlier PR).

## Files to Create

- `plugins/soleur/test/inngest-config-bundle-mirror.test.sh`: the guard (structural leg parsed as YAML, behavioural leg executing the real extracted body, small mutation battery on scratch copies).
- `knowledge-base/project/specs/feat-one-shot-7243-inngest-bundle-emitter-always-runs/tasks.md` (and the already-created `decision-challenges.md`).

Glob verification: `git ls-files` returns `.github/workflows/build-inngest-config-bundle.yml`, `scripts/lib/test-affected-paths.sh`, `scripts/suite-durations.tsv`, `scripts/suite-shard-legs.tsv` and the precedent `plugins/soleur/test/reusable-release-zot-mirror-retry.test.sh`.
Not touched: `cloud-init-registry.yml`, any `.tf`, `.github/workflows/infra-validation.yml`, anything under `apps/web-platform/`, `inngest-bootstrap-mirror-only.test.sh` (its crane-pin parity leg greps the `CRANE_SHA256=` assignment in the bundle workflow; that line stays verbatim).

**Does merging THIS alone mutate production?** No. Verified from the trigger paths: `web-platform-release.yml` fires on `apps/web-platform/**` and `plugins/soleur/**` minus `docs/` and `test/`; `apply-web-platform-infra.yml` fires on `apps/web-platform/infra/**`; the diff touches neither (the bundle workflow is `workflow_dispatch`-only and has zero recorded runs). The PR body's first line states this. `deploy-arm.sh find --wait <sha>` is still run at ship and is expected to report that no deploy arm applies; that verdict, not an assumed deploy, is what gets recorded.

## Implementation Phases

### Phase 0 - RED first (cq-write-failing-tests-before)

1. Write `inngest-config-bundle-mirror.test.sh` against the UNCHANGED workflow. Run it and capture the failing verdict lines; they go in the PR body as the pre-fix evidence (the independent anchor for the assertion floor, see Guard Contract).
2. Expected RED on origin/main's workflow: the gate still references the bridge, no `BRIDGE_OUTCOME` env, no step id, and the bridge-failure arm executes crane instead of degrading.

### Phase 1 - The step

```yaml
- name: Mirror bundle GHCR->zot (crane, digest-preserving)
  id: zot_mirror
  if: steps.docker_build.outcome == 'success'
  continue-on-error: true
  env:
    DIGEST: ${{ steps.docker_build.outputs.digest }}      # unchanged (plumbed, unused today)
    BRIDGE_OUTCOME: ${{ steps.zot_bridge.outcome }}       # outcome, never conclusion
  run: |
    set -euo pipefail
    degraded() {
      local reason="$1" rc="$2" detail="${3:-}"
      echo "mirror_status=degraded" >> "$GITHUB_OUTPUT"
      echo "mirror_reason=${reason}" >> "$GITHUB_OUTPUT"
      echo "::warning::zot mirror degraded for ... (reason=, rc=, detail) - GHCR is authoritative, the zot copy is absent, no automated backfill exists"
      echo "- zot mirror degraded (reason=..., rc=...); GHCR bundle is published" >> "$GITHUB_STEP_SUMMARY"   # prose bullet, not a table row
      exit 0
    }
    if [[ "${BRIDGE_OUTCOME:-}" != "success" ]]; then
      degraded bridge_down n/a "zot_bridge outcome=${BRIDGE_OUTCOME:-<unset>}; copy not attempted"
    fi
    retry() {...unchanged...}
    # every fallible command below is routed; && chaining inside the group, because errexit is
    # suppressed for a group on the left of ||
    { curl ... && echo "${CRANE_SHA256}  /tmp/crane.tgz" | sha256sum -c - \
        && sudo tar -xzf /tmp/crane.tgz -C /usr/local/bin crane && rm -f /tmp/crane.tgz; } \
      || degraded crane_install "$?" "crane fetch, checksum or extract failed on the runner"
    retry crane copy "${IMAGE}:v${VERSION}" "${ZOT}:v${VERSION}" || degraded copy "$?"
    echo "mirror_status=ok" >> "$GITHUB_OUTPUT"
```

Rules for the edit:

- `!= "success"`, not `== 'failure'`: fail-safe on `skipped`, `cancelled` and unset values (CTO ruling F3). Under this step's gate `skipped` is unreachable; the wider test is deliberate.
- `degraded` exits (not returns), so nothing falls through to `mirror_status=ok`.
- The `::warning::` and `mirror_status=degraded` literals appear exactly once, in `degraded()`, on single lines, and never in a comment (the Observability probe counts raw text).
- Names only the measured (ADR-166): the bridge detail states the observed outcome and that the copy was not attempted; it asserts no cause. The `crane_install` message names "checksum or fetch" and leaves the `sha256sum -c` stderr unredirected so a mismatch is in the step log.
- The warning never mentions `mirror_only` or a re-dispatch and never claims hosts pull only from zot.
- `${BRIDGE_OUTCOME}` interpolated into an annotation is a GitHub-controlled enum, so no CR/LF strip is needed; the plan notes this so a reviewer does not add one.
- Keep `CRANE_VERSION` / `CRANE_SHA256` lines byte-identical (parity leg in the sibling suite).
- Comment block states the #6416 reason and that a sibling step cannot fix it (outputs are namespaced by step id), with a pointer to the suite.
- The workflow cannot be dispatched pre-merge (it must exist on the default branch, and the signing job waits on a required reviewer); the suite is the verification. Syntax check with `actionlint` for the YAML and `bash -n` on the extracted body, never `bash -n` on the YAML.

### Phase 2 - The suite

Modelled on `reusable-release-zot-mirror-retry.test.sh` (extractor, stubs) and `inngest-bootstrap-mirror-only.test.sh` (YAML-parsed structural leg, comment-stripped `code_of`, sentinel for return-vs-exit):

- **Structural leg** (python3 + pyyaml, TSV verdicts): step exists by name; id `zot_mirror`; `if` is absent or exactly `steps.docker_build.outcome == 'success'`, and no `if:` anywhere in the job (steps or job level) references `steps.zot_bridge`; `continue-on-error` true on the bridge and the mirror; every step that `uses:` the bridge action has `continue-on-error: true`; env `BRIDGE_OUTCOME` equals `${{ steps.zot_bridge.outcome }}`; mirror step index greater than bridge index; `degraded()` defined once.
- **Behavioural leg**: extract the body by step name (`index()`, not a regex), `bash -n` it, run under `bash -eo pipefail` in a subshell with a stub dir first on PATH. Capture real binaries with `command -v` before prepending. Export `IMAGE`, `VERSION`, `DIGEST`, `GITHUB_OUTPUT`, `GITHUB_STEP_SUMMARY` (the body is `set -u`); an unset bridge value uses `env -u BRIDGE_OUTCOME`, not an empty assignment. Stub contracts replayed: `curl` and `sudo` exit by knob and log to a file; `sha256sum` reads stdin (`cat >/dev/null`) before exiting, because a stub that does not read lets `echo` hit SIGPIPE (141) under `pipefail` and manufacture a degrade; `crane` has separate knobs and counters per subcommand (`STUB_CRANE_COPY_FAIL_N`), logs to a file, never stdout; `sleep` is a no-op. Arms:
  1. bridge `success`, stubs ok: exit 0, `mirror_status=ok`, no `::warning::`, crane copy called once with the expected source and `127.0.0.1:5000/...` destination.
  2. bridge `failure`: exit 0, `mirror_status=degraded`, `mirror_reason=bridge_down`, one `::warning::` line, one summary line, crane never called.
  3. Loop: bridge `skipped`, empty string, and unset (`env -u`): each degrades as in arm 2.
  4. crane copy fails every time: `reason=copy`, crane copy called exactly 3 times, exit 0.
  5. crane copy fails twice then succeeds: `mirror_status=ok` after 3 calls.
  6. `sha256sum` fails: `reason=crane_install`, crane never called, `sudo` never called.
  7. Sentinel appended after the body never prints on any degrade arm (exit-vs-return).
  Log greps anchor on interpolated runtime values (`reason=bridge_down`, the digest string), use here-strings, never `printf | grep -q`, and avoid `grep | head` under `pipefail`.
- **Mutation battery** (the Guard Contract matrix): python edits applied to scratch copies of the workflow, each asserted to differ from the canonical copy (`! cmp -s`) BEFORE the evaluator runs, so a drifted pattern cannot become a silent no-op; the same evaluator runs on each mutant (expects RED) and on the two must-pass variants (expects GREEN). A single tight `MIN_ASSERTIONS` floor derived from a green run, in a guard-vacuity-floor-compatible shape.
- Hermetic: `REPO_ROOT` from `BASH_SOURCE`; `mktemp -d` scratch with an owning `EXIT INT TERM HUP` trap placed BEFORE any `source test-helpers.sh` (lint-trap-tempfile-ownership); no fixed `/tmp` names, no network, no docker; no wall-clock assertions. Target runtime a few seconds, measured.

### Phase 3 - Wiring

1. Regenerate the manifests incrementally; keep only the new suite's rows.
2. Run `bash scripts/lint-orphan-test-suites.sh` once the suite is tracked (commit it first); add the `AFFECTED_...` array only if the census or the affected-selection dry run requires it, and re-run both.
3. With only the bundle workflow staged, confirm `bash scripts/test-all.sh --affected --affected-scope=staged` selects the new suite (cite the line that selected it in the PR body).

### Phase 4 - Verify before push

Paste the pass lines into the PR body:

- the new suite; `plugins/soleur/test/reusable-release-zot-mirror-retry.test.sh` (sibling untouched); `apps/web-platform/infra/inngest-bootstrap-mirror-only.test.sh` (crane-pin parity still passes).
- `.claude/hooks/grep-q-pipe-guard.test.sh`, `plugins/soleur/test/fixture-relative-assert.test.sh`, the fixture-dir-operand-assert suite, `guard-vacuity-floor`, `lint-trap-tempfile-ownership` and `lint-shell-capture-exit` with `--baseline`, all against the new `*.test.sh`; `bash scripts/lint-orphan-test-suites.sh`.
- `BASELINE_DECLARED_PROBES` in `plugins/soleur/test/preflight-discoverability-test.test.ts` is 66 on origin/main at plan time and this plan declares no `credentials_required`, so it stays 66. Re-check against `origin/main` immediately before the final push; another merged plan may have moved it, and a plan declaring `credentials_required` owns its own bump.
- `actionlint` on the edited workflow; the Observability probe (below) printing `1` on the post-change tree; markdownlint on the plan and `tasks.md`.

### Phase 5 - Ship (per the operator brief)

Deferral tracking: file ONE GitHub issue listing the cut hardening items (digest parity check with a `digest_unset` guard, ERR-trap backstop, `zot mirror` row on the digest summary step, automated zot backfill of the bundle). What: none exist for `soleur-inngest-config`. Why deferred: GHCR is authoritative and the workflow has never run. Re-evaluate when the ADR-135 pull channel resolves the bundle through zot or the workflow gains a mirror-only mode. Milestone from `knowledge-base/product/roadmap.md`.

PR body: first line "Merging this alone does not mutate production" with the trigger-path evidence; `Ref #7243`; a `## Changelog` section; the pre-fix RED evidence; the plan cited by its archived path once archived. Rebase onto `origin/main`, never merge main; once armed in the merge queue push no syncs. Known flake: `scripts/test-all-orphan-log-retention` C.9 can dequeue the PR: read the failing step, re-arm ONCE; a second dequeue means stop and report the run URL. Run `compound` before `ship`. From a detached `origin/main` worktree run `bash plugins/soleur/scripts/deploy-arm.sh find --wait <full-sha>` then `served <full-sha>` (wrap in Monitor or re-run if it exceeds the tool timeout) and record the verdicts. Process census and kill go through `plugins/soleur/scripts/lib/proc.sh`; use `/usr/bin/grep -a`; use `$SECONDS`, not `/usr/bin/time`. After merge, tick the #7243 checkbox in epic #10205 and re-read the epic body to verify it.

## Risks and Precedent Diff (Phase 4.4)

Pattern-bound behaviour: the bridge-outcome branch plus `degraded()` emitter. Two sibling precedents exist in the repo.

| Aspect | `reusable-release.yml` `zot_mirror` | `build-inngest-bootstrap-image.yml` `zot_mirror` | This plan (`build-inngest-config-bundle.yml`) |
|---|---|---|---|
| Step gate | `if: steps.docker_build.outcome == 'success'` | none (implicit `success()`) | `if: steps.docker_build.outcome == 'success'` (issue's proposal; symmetry only) |
| Bridge test | `== 'failure'` (bridge can be `skipped` there) | `!= "success"` | `!= "success"` (bridge cannot be `skipped` under the same gate; wider test is fail-safe) |
| `continue-on-error` on mirror | removed (release-blocking, ADR-096 amended) | none; `degraded()` exits 1 under `mirror_only` | kept: GHCR is authoritative and there is no mirror-only mode |
| `degraded()` exit | non-zero (blocks the release) | 0 on build path, 1 under `mirror_only` | 0 always |
| Unrouted-failure backstop | n/a | ERR trap to `degraded unrouted` | none (cut, CTO R1); every fallible command is `\|\| degraded`-routed instead |
| Remediation text | release-specific | `mirror_only` backfill command | none; states that no automated backfill exists |

Risks and mitigations:

- Risk: a future edit re-gates the step on the bridge. Mitigation: structural leg plus mutation rows 1 and 3.
- Risk: the bridge loses `continue-on-error`, so `success()` flips false and the mirror is skipped again. Mitigation: asserted structurally (mutation row 2).
- Risk: a `set -u` abort inside the body (for example an unset `IMAGE`) bypasses `degraded()`. Mitigation: `continue-on-error: true` keeps the run green and the step shows red in the log; the inputs are set by the job-level `env:` and `inputs.version`, so this is not reachable on a normal dispatch.
- Risk: the suite is not selected for a workflow-only diff. Mitigation: Phase 3.3 dry run and the `AFFECTED_*` declaration.

## Verification Evidence (Phase 4 gates, run live)

```text
4.6  User-Brand Impact heading count: 1 (threshold none, scope-out line present)
4.7  five required observability field keys: 1 each; no "ssh " in any command
4.8  PAT-shape sweep: none
4.11 python3 scripts/lint-guard-contract.py <plan>: scanned 1 plan file(s), 1 with a Guard Contract, 1 guard entry (rc=0)
4.12 unfenced "## Scope Check" count: 1; "Recommendation:" present; no unmapped row, no BLOCKED marker
Probe pre-change: grep -cF mirror_status=degraded .github/workflows/build-inngest-config-bundle.yml -> 0 (must print 1 after the change)
Issue/PR states: #7243 OPEN, #10205 OPEN, #10257 OPEN (draft), #8800 OPEN, #6416 CLOSED, #7242 CLOSED
ADR files present: ADR-096, ADR-135, ADR-166
```

Prototype of the proposed body skeleton (`bash -eo pipefail`, stubs as env knobs), results:

```text
bridge success, all ok      -> mirror_status=ok            rc=0
bridge failure              -> DEGRADED reason=bridge_down rc=0
bridge unset (env -u)       -> DEGRADED reason=bridge_down rc=0
sha256sum stub fails        -> DEGRADED reason=crane_install rc=0
tar stub fails              -> DEGRADED reason=crane_install rc=0
crane copy fails 3x         -> DEGRADED reason=copy        rc=0
sha stub that ignores stdin, 5 runs -> mirror_status=ok every time (SIGPIPE not reproduced; the suite's stub still reads stdin to rule it out)
```

## Guard Contract

### Guard 1 - bridge-failure emitter reachability (suite `inngest-config-bundle-mirror.test.sh`)

**Property.** Whenever the bundle workflow reaches the mirror step after a successful image build, the step runs and, if the bridge did not succeed, emits a degrade signal and exits 0 without falling through to `mirror_status=ok`.

**Assembly.** The property quantifies over every site that can prevent the step from running or from emitting: (a) the mirror step's own `if:`; (b) every other step-level and job-level `if:` that reads `steps.zot_bridge` (the chokepoint is "any expression referencing the bridge step"; the suite scans ALL steps and the job, not only the mirror); (c) every step that `uses:` the bridge action, each of which must carry `continue-on-error: true`, because an implicit `success()` is prepended to any `if:` without a status function, so a bridge failure that is not soft-failed flips `success()` false and skips the mirror; (d) the `env:` wiring of `BRIDGE_OUTCOME` (outcome, not conclusion); (e) step ORDER (mirror after bridge); (f) the run body: the bridge branch, the two `|| degraded` routes (install group, copy), `degraded()`'s single definition and its `exit`; (g) selection: the `AFFECTED_*` declaration and shard manifests that make the suite run when only the workflow changes.

**Mutation matrix:**

| # | Mutation | Property served | Expected |
|---|---|---|---|
| 1 | Re-add `if: steps.zot_bridge.outcome == 'success'` to the mirror step | P1, P4 | RED (structural gate scan) |
| 2 | Remove `continue-on-error: true` from the bridge step | P1, P3 | RED |
| 3 | Add a second step after the mirror with `if: steps.zot_bridge.outcome == 'success'` (a second member after a compliant first) | P4 | RED |
| 4 | Switch env to `${{ steps.zot_bridge.conclusion }}` | P1 | RED |
| 5 | Delete the `BRIDGE_OUTCOME` branch from the run body (the crane stub succeeds, so only the branch can degrade) | P1 | RED (arm 2) |
| 6 | Change `degraded()`'s `exit 0` to `return 0` | P3 | RED (sentinel) |
| 7 | Move the mirror step BEFORE the bridge step (a REORDER, not a delete: the outcome is empty at that point) | P1 | RED (order assertion) |
| 8 | Rename the step so the extractor finds nothing (the guard's own dispatch) | P4 | RED ("0 steps extracted", never a silent pass) |
| 9 | Drop `\|\| degraded copy` from the crane copy line | P2 | RED (arm 4) |

**Harness rows.** RED: point the suite's extractor at a wrong step name (a suite edit, not a workflow edit) and confirm the suite fails on the empty body rather than passing with zero arms. Must-PASS non-canonical: (i) the mirror step with NO `if:` (the bootstrap workflow's shape, which the contract permits); (ii) the canonical workflow with every comment reworded and the env keys reordered. A guard that rejects everything cannot pass these two.

**Anchor.** The only stored value is the assertion-count floor, and one diff can edit both it and the suite, so the independent anchor is the Phase 0 pre-fix evidence: the suite run against origin/main's unfixed workflow, recorded in the PR body, shows exactly which checks fail without the fix.

**Own-remediation check.** The new step comment and warning text must not contain the literal gate expression `steps.zot_bridge.outcome == 'success'` outside a quoted explanation in a comment; the suite strips comments before scanning code, and mutation 1 confirms a real `if:` is caught while the explanatory comment is not.

## Observability

```yaml
liveness_signal:
  what: "mirror_status output (ok or degraded) plus a job-summary line and a ::warning:: annotation on every run that reaches the mirror step; absence of the step means the image build did not succeed"
  cadence: "per workflow_dispatch run (dispatch-only, operator-triggered, reviewer-gated)"
  alert_target: "the workflow run page annotations and job summary seen by the dispatching operator; no pager (the workflow has no schedule)"
  configured_in: ".github/workflows/build-inngest-config-bundle.yml (mirror step, degraded())"

error_reporting:
  destination: "GitHub Actions workflow-run log (observability layer 6: workflow run log, ::warning:: annotation); no Sentry (CI runner, not server code)"
  fail_loud: "::warning::zot mirror degraded for <zot ref> (reason=<stage> rc=<n>) in the run annotations plus the same line in GITHUB_STEP_SUMMARY"

failure_modes:
  - mode: "CF-tunnel bridge soft-fails (the #6416 case)"
    detection: "BRIDGE_OUTCOME != success branch emits reason=bridge_down; layer 6 workflow run log ::warning:: and job summary"
    alert_route: "operator reading the run page of the dispatch they triggered"
  - mode: "crane download, checksum or extract fails on the runner"
    detection: "reason=crane_install; layer 6 workflow run log ::warning:: plus the unredirected sha256sum stderr in the step log"
    alert_route: "same run page"
  - mode: "crane copy fails after 3 attempts"
    detection: "reason=copy after the bounded retry; layer 6 workflow run log ::warning::"
    alert_route: "same run page"
  - mode: "a future edit re-gates the step on the bridge"
    detection: "inngest-config-bundle-mirror.test.sh structural leg, selected by the AFFECTED declaration and run in the CI scripts shard; CI check name"
    alert_route: "PR check failure"

logs:
  where: "GitHub Actions run log and job summary for build-inngest-config-bundle"
  retention: "GitHub default (90 days for logs; summaries live with the run)"

discoverability_test:
  command: grep -cF mirror_status=degraded .github/workflows/build-inngest-config-bundle.yml
  expected_output: "1"
```

The workflow is dispatch-only and has never run, so there is no runtime state to read unauthenticated; the probe pins that the single emitter exists in the file, and the behavioural suite pins that it executes. It prints `0` on the pre-change tree and must print `1` on the post-change tree (run it as an AC, not assumed). No `credentials_required` is declared, so `BASELINE_DECLARED_PROBES` is unchanged.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "drop the `steps.zot_bridge.outcome == 'success'` gate on the emitter step (line ~132)" | Phase 1; Files to Edit entry 1 | mapped |
| 2 | "Pass BRIDGE_OUTCOME as an env var and branch inside the step so the emitter always runs (same pattern as the zot_mirror step in .github/workflows/reusable-release.yml)" | Phase 1 | mapped |
| 3 | "Add a test that executes the real block (extracts and runs the actual step script, not a copy)" | Phase 2; Files to Create entry 1 | mapped |
| 4 | "No host impact; do not touch cloud-init-registry.yml" | Not-touched list; trigger-path evidence | mapped |
| 5 | "PR body uses `Ref #7243` (not Closes) and includes a ## Changelog section" | Phase 5 | mapped |
| 6 | "re-check BASELINE_DECLARED_PROBES against origin/main before the final push" | Phase 4 | mapped |
| 7 | "On any new/edited *.test.sh run .claude/hooks/grep-q-pipe-guard.test.sh, fixture-relative-assert, ..." | Phase 4 | mapped |
| 8 | "Run compound before ship, and ship to a verified production state" | Phase 5 | mapped |
| 9 | "After merge, tick the #7243 checkbox in epic #10205" | Phase 5 | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Rewrite mirror step | "drop the `steps.zot_bridge.outcome == 'success'` gate" | asked |
| `id: zot_mirror`, `mirror_status` / `mirror_reason` outputs | "so the emitter always runs (same pattern as the zot_mirror step ...)" | asked (the pattern includes the id and outputs) |
| `\|\| degraded` routes for the install group and the copy | "branch inside the step so the emitter always runs" | inferred: a failed copy or install must reach the same emitter or a red step stays unexplained; the issue's step 3 asks for "a failed bridge (or a failed copy)" and the CTO's R1 condition requires every fallible command before the emitter to be routed |
| New suite in `plugins/soleur/test/` | "Add a test that executes the real block" | asked (placement is CTO ruling R2) |
| Small mutation battery inside the suite | "a test that executes the real block" | inferred: Phase 2.12 requires a Guard Contract for a deliverable that is a guard; the battery is how the matrix is executed |
| `AFFECTED_*` array and manifest rows | "Add a test" | inferred: without a selection edge a PR editing only the workflow skips its own guard, and the shard manifests carry a row per registered suite |
| One tracking issue for the cut items | none | inferred: a deferral without a tracking issue is invisible (plan Phase 6 checklist); one issue, no code |

### Split Assessment

- Subsystems touched: 2 (`.github/workflows`, `plugins/soleur/test` plus `scripts/` registration)
- Planned files: 6 | Estimated changed lines: ~280 (suite ~190, step ~50, registration ~40)
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] The mirror step has `id: zot_mirror`, `if: steps.docker_build.outcome == 'success'`, `continue-on-error: true`, and no `if:` anywhere in the workflow reads `steps.zot_bridge`.
- [ ] `BRIDGE_OUTCOME: ${{ steps.zot_bridge.outcome }}` is in the step env and the script degrades on any value other than `success` (`failure`, `skipped`, empty, unset).
- [ ] On every degrade the step writes `mirror_status=degraded`, `mirror_reason=<stage>`, one `::warning::` and one summary line, and exits 0; on success it writes `mirror_status=ok`. The crane install group and the copy are each `|| degraded`-routed.
- [ ] The warning text contains neither `mirror_only` nor a re-dispatch instruction (checked by reading the diff, not by a suite arm).
- [ ] `plugins/soleur/test/inngest-config-bundle-mirror.test.sh` extracts the step body from the workflow by name, runs it under `bash -eo pipefail` with stubs, arms 1-7 pass, its mutation battery reports every matrix row RED (each mutant asserted different from canonical) and both must-pass variants GREEN.
- [ ] The PR body contains the suite run against the unfixed workflow showing the expected failures (pre-fix RED evidence).
- [ ] `scripts/lint-orphan-test-suites.sh` passes with the suite tracked; with only the bundle workflow staged, `scripts/test-all.sh --affected --affected-scope=staged` selects the suite; both manifests carry one new row each and no other suite's row changed (`git diff origin/main...HEAD -- scripts/suite-durations.tsv scripts/suite-shard-legs.tsv` shows additions of that suite only).
- [ ] `reusable-release-zot-mirror-retry.test.sh` and `inngest-bootstrap-mirror-only.test.sh` still pass; the `CRANE_SHA256=` assignment in the bundle workflow is unchanged.
- [ ] Phase 4 hook suites and lints are green for the new `*.test.sh`; `BASELINE_DECLARED_PROBES` re-checked against `origin/main` and unchanged unless a merged plan moved it.
- [ ] `grep -cF mirror_status=degraded .github/workflows/build-inngest-config-bundle.yml` prints `1` on the post-change tree.
- [ ] `git diff --name-only origin/main...HEAD` lists no `.tf`, no `cloud-init-registry.yml`, no path under `apps/web-platform/`, and no `infra-validation.yml`; its only files outside `knowledge-base/` are the bundle workflow, the new suite, `scripts/lib/test-affected-paths.sh` (if needed) and the two manifests (files the pipeline itself writes, such as the generated KB index and session state, are in the allowed set).
- [ ] PR body: first line states merging alone does not mutate production, `Ref #7243`, `## Changelog`, plan cited by archived path once archived. After merge the `deploy-arm.sh find --wait` / `served` verdicts are recorded, the tracking issue exists, and the #7243 checkbox in #10205 is ticked and re-read.

## Domain Review

**Domains relevant:** none

No cross-domain implications detected: CI-workflow and test change with no user-facing, legal, financial or marketing surface. Mechanical UI-surface override: no path in the Files lists matches the UI-surface term list. Architecture gate (Phase 2.10): no architectural decision is made (the pattern is the existing ADR-096 / ADR-166 conclusion), so no ADR or C4 edit; no monitors, heartbeats, cron workflows or secrets are added, so the C4 count-parity gate is unaffected. Encryption posture (Phase 2.11): no new store or connection. GDPR gate (Phase 2.7): no regulated-data surface. Named-panel reviewers: the CTO was consulted twice (rulings in `decision-challenges.md`); CPO, CMO and UX leads were not activated.

## Test Scenarios

- Given the bridge soft-failed, when the mirror step runs, then it degrades with `bridge_down`, crane is never invoked, and the run stays green (integration).
- Given the bridge `skipped`, empty or unset, when the step runs, then it degrades the same way (integration).
- Given crane copy fails twice then succeeds, then `mirror_status=ok` after 3 attempts (integration).
- Given crane copy fails 3 times, then `reason=copy`, 3 attempts, exit 0 (integration).
- Given a bad checksum, then `reason=crane_install` and no extraction (integration).
- Given a PR re-adds the bridge gate, then the structural leg is RED (unit).
- Given only the workflow file changes, then the affected selection includes the suite (integration, Phase 3).
- Regression: the #6416 shape (skipped step emits nothing) is asserted by arm 2 plus mutation 1.

## Sharp Edges

- A step `if:` without a status function gets an implicit `success()`; the bridge's `continue-on-error: true` is therefore load-bearing and is asserted, not assumed.
- The default `run:` shell is `bash -eo pipefail`. Errexit is suppressed for a command group on the left of `||`, so the install group is `&&`-chained; a `;`-separated group would swallow a failed `curl`.
- `outcome`, never `conclusion`: `continue-on-error` forces `conclusion` to `success`.
- Keep the literal `mirror_status=degraded` out of comments, or the Observability probe count changes.
- A `sha256sum` stub that does not read stdin gives the `echo | sha256sum` pipe a SIGPIPE under `pipefail` and manufactures a degrade on the success arm.
- Plan checklist lines never use the word that trips the incident-review gate.
- Draft PR 10257 edits a comment block in the crane copy step of the same file: rebase, do not merge, and re-read the step before the final push.
- The placement ruling is load-bearing: a file added under `apps/web-platform/infra/` would fire a production infra apply and a release on merge.
