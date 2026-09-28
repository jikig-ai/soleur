---
title: "feat: resolve the registry host's write-shaped lever set (ADR-172 amendment, alarm-dispatched inventory, END restart sample)"
date: 2026-09-28
slug: feat-registry-write-levers-resolved
branch: feat-one-shot-7377-registry-levers
issue: 7377
closes: 7377
type: feat
lane: single-domain
domain: engineering
priority: p2
brand_survival_threshold: none
---

# feat: resolve the registry host's write-shaped lever set (#7377)

## Overview

#7377 exists so that closing #7278 did not silently close the gap it named: the registry host
had a read-only inventory lever but no `restart`, `push-config` or `reclaim`, and all three were
recorded in ADR-172 §3 as "blocked on a provisioning event". It carries four acceptance items:

1. `push-config` exists, or a recorded decision that it will not.
2. `zot_restarts_at_end` carries a real value, so `restart_during_sweep` can fire in production.
3. The label dispatch route has a producer, or the route is removed.
4. A live at-rest posture probe replaces the issue-state proxy in `registry-luks-blocker-6929.sh`.

It also names a non-acceptance defect: `marker_schema` has no consumer.

This plan resolves all four plus the `marker_schema` defect in one PR. It changes **no host
config**: nothing under `cloud-init-registry.yml`, `zot-registry.tf`, `ci-deploy.sh` or
`apply-web-platform-infra.yml` is touched, so the merge fires no registry or web host replace
(a separate agent owns the #8714 5.3b-iii registry replace).

**ADR decision (explicit): amend ADR-172; no new ADR.** The actuation model for a registry config
change (merge to `main`, then a volume-preserving `registry-host-replace`) was already *decided*
in the ADR-169 amendment of 2026-08-16 (#7555) and in `hr-prod-host-config-change-immutable-redeploy`.
What is stale is ADR-172 §3's claim that the three levers are "blocked on a provisioning event".
The amendment records the resolution against that blocked set and flips ADR-172 `adopting →
accepted`. A new ADR would be warranted only if this plan chose an in-place or host-pull lever,
and it does not.

## Research Insights

Research came from the pre-run Phase-B research note (§4, #7377) and was **re-measured** in this
session against `origin/main` @ `fff36b6172` before being written here. Nothing below is copied
unmeasured.

### Premise Validation (Phase 0.6)

| Claim | Measured | Holds? |
|---|---|---|
| The blocking condition (the LUKS recut had never fired) has cleared | run `31437037877` (Apply web-platform infra, 2026-08-10T22:08Z): job `registry_luks_recut` = **success** (the run's overall conclusion is failure because a later `registry_store_restore` job failed). #7287 closed 2026-08-12T20:39Z; #7340 closed 2026-08-13T18:46Z | yes |
| The store is LUKS today | `SOLEUR_ZOT_DISK` row 2026-09-28T07:15:02Z: `store_luks=yes store_mount_src=/dev/mapper/registry pcent=14 zot_restarts=0 boot_id=5639cc07-…` | yes |
| `push-config` already exists as merge → volume-preserving replace | ADR-169 §"Amendment 2026-08-16 (#7555)"; `registry-host-replace-dispatch.yml` fired the replace 5 times: 2026-08-16 (`31978045577`, manual re-fire), 09-17 (`35215010502`, manual re-fire), 09-18 (`35352234356`, push), 09-20 (`35488805309`, push), 09-22 (`35671580537`, push). Each ran preflight → dispatch → poll-to-conclusion green. Current boot's `store_mount_devid=scsi-0HC_Volume_106585109` equals `store_expected_devid` (the volume was preserved) | yes |
| No zot user holds `delete` | `cloud-init-registry.yml` `accessControl`: pull `["read"]`, push `["read","create","update"]` | yes |
| GC already reclaims hourly | `cloud-init-registry.yml`: `"gc": true, "gcDelay": "1h", "gcInterval": "1h"`, retention block present | yes |
| The label route has no producer | `grep` for any `--label`/`add-label` of `registry-zot-inventory` outside the listener: **0**. `gh label list --search registry-zot` returns only `ci/zot-restart-loop`, `ci/zot-telemetry-silent`, `ci/registry-private-nic`: the label **does not exist** in the repo | yes |
| The label route has never fired | `registry-zot-inventory-dispatch.yml` has **3540** runs; runs with status success / failure / cancelled: **0 / 0 / 0**. Every run is a skipped `issues` event (it wakes on every label applied anywhere in the repo) | yes |
| A `github.token` label cannot trigger it anyway | GitHub Actions docs, "Triggering a workflow from a workflow": events raised with `GITHUB_TOKEN` do not start new runs, **except** `workflow_dispatch` and `repository_dispatch`. The restart-loop alarm files with `GH_TOKEN: ${{ github.token }}` (`scheduled-zot-restart-loop.yml`, FIRE step). So a label producer inside that alarm would be structurally dead, while a direct `gh workflow run` from it is allowed | yes |
| `zot_restarts_at_end` is always `unknown` | `scripts/zot-inventory.sh` reads `ZOT_RESTARTS_AT_END` from env only; no production caller sets it; the enumerate step's own comment in `registry-zot-inventory.yml` says so ("PASSED BUT NOT YET CONSUMED … Tracked in #7377") | yes |
| `marker_schema` has no consumer | `grep -rn marker_schema scripts .github tests` → only the emitter (`zot-inventory.sh` `MARKER_FIELDS`) and two test fixtures | yes |
| The live at-rest probe exists | `scripts/followthroughs/registry-luks-live-8386.sh` grades `store_luks=`; `logtail_exploration_alert.registry_store_not_luks` is declared and targeted in `apply-web-platform-infra.yml`; the ledger registry row reads `live_verification: available` | yes |
| `registry-luks-blocker-6929.sh` is orphaned | its tracker #7340 is closed, so the sweeper (`--state open`) never runs it; the script's own header says moving onto the live signal "is #7377's open checkbox". References: ADR-172 §"Status flip condition" only (plus point-in-time plans/specs) | yes |
| ADR-172's flip condition passed | #7339 closed 2026-08-10T18:40Z; `registry-zot-inventory.yml` run 2026-08-10T11:05Z `workflow_dispatch` = success, and that workflow is green only after `zot-inventory-assert-marker.sh` reads the marker back with `enumeration_complete=true`. The same run also proves runner egress, which ADR-172's "Bad" section named as the reason it stayed `adopting` | yes |

Stale in the pre-run research: nothing material. One refinement: the research cited run
`31437037877` as "the recut ran"; the measurement shows the run's *overall* conclusion is failure
(`registry_store_restore` failed) while `registry_luks_recut` succeeded. The ADR text says
"the recut job succeeded", not "the run succeeded".

### Property List (Phase 0.6b)

- P1. A reader of ADR-172 learns the true state of `restart` / `push-config` / `reclaim`: which exist, in what form, and which will not be built and why.
- P2. When the restart-loop alarm opens a new non-OOM tracker, the read-only store inventory runs without anyone dispatching it.
- P3. No workflow listens for a trigger that nothing can produce.
- P4. The durable `SOLEUR_ZOT_INVENTORY` marker records whether zot restarted during the sweep.
- P5. A marker from a future schema is not certified by a reader written for schema 1.
- P6. No follow-through probe survives whose tracker is closed and whose question is already answered by a live probe.

### Cut List (Phase 0.6b)

- A label **producer** for the inventory route → P2 → cut: a direct `gh workflow run` from the alarm buys P2 with no label, no second workflow and no App token.
- An in-place `push-config` / `restart` lever (SSH, agent, host-pull) → P1 → cut: merge → volume-preserving replace already buys config delivery (ADR-169 amendment); an in-place lever violates `hr-prod-host-config-change-immutable-redeploy` and `hr-no-ssh-fallback-in-runbooks`.
- A `reclaim` lever (a `delete` grant) → P1 → cut now: `pcent=14`, hourly GC. If it is ever needed it is itself a push-config and rides the replace path; the ADR records the re-evaluation trigger.
- A new marker field for the END boot id → P4 → cut: the verdict `restart_during_sweep` already carries the fact; adding a field would force a `marker_schema` bump for no reader.
- Rewriting `registry-luks-blocker-6929.sh` onto `store_luks=` → P6 → cut: `registry-luks-live-8386.sh` already is that probe; the old file is deleted, not ported.

### Relevant files

- `.github/workflows/registry-zot-inventory-dispatch.yml`: the label route (3,811 B).
- `.github/workflows/scheduled-zot-restart-loop.yml`: the alarm; FIRE step "Open or comment recurrence issue (FIRE)". Top-level `permissions: contents: read, issues: write`.
- `.github/workflows/scheduled-inngest-health.yml` "Auto-dispatch inngest restart (failure)": in-repo precedent for an alarm dispatching a recovery workflow with `actions: write` and a fail-soft dispatch that records what happened.
- `scripts/zot-restart-loop-alarm.sh`: the non-OOM arm's `CAUSE` begins with the fixed literal `non-OOM crash-loop — `; the attacker-influenced log tail only ever follows that prefix. The OOM arms are fixed strings with no tail.
- `scripts/zot-inventory.sh`, `scripts/zot-disk-sample.sh` (tested sampler with exit contract 0/2/3/4/64), `scripts/zot-inventory-assert-marker.sh`.
- Tests: `tests/scripts/test-zot-inventory.sh`, `tests/scripts/test-zot-inventory-assert-marker.sh`, `apps/web-platform/infra/registry-zot-inventory-workflow-guard.test.sh` (parsed-YAML guard, `MIN_ASSERTIONS=52` floor), `apps/web-platform/test/server/watchdog-workflow-idempotence.test.ts` (executes the alarm's step bytes against a PATH-stubbed `gh`).
- `.github/workflows/infra-validation.yml` `pull_request.paths` lists the dispatch workflow.

### Institutional learnings applied

- `2026-08-10-the-lever-had-never-run-and-every-guard-was-satisfied-by-its-own-comment.md`: a route with no live execution is not a route. Measured here: 0 non-skipped runs in 3540.
- `2026-08-13-every-guard-i-shipped-was-satisfiable-by-a-guard-that-asserts-nothing.md`: every new guard gets must-PASS rows and a harness-mutation row (see Guard Contract).
- AP-022 / ADR-170: `zot-inventory.sh` never enables errexit; every new `rc` read must stay reachable.

### Constraints

- `apply-web-platform-infra.yml` is at 489,121 B vs a 490,000 B cap: **not touched**.
- Machine is CPU-contended: run targeted suites only; CI's required `test` is the full gate.

## Research Reconciliation — Spec vs. Codebase

| Claim (issue body / research) | Reality | Plan response |
|---|---|---|
| "All three need a change to a cloud-init-written file → re-run → host replace, which is fatal before the recut" | The recut job succeeded 2026-08-10; five volume-preserving replaces since | ADR amendment records the blocker as cleared |
| "`push-config` … unlocks the other two" | It exists as merge → replace (ADR-169 amendment) | Recorded as realized; no new lever |
| "`reclaim` needs a `delete` grant" | Still true; no reclaim pressure (`pcent=14`) | Not built; re-evaluation trigger recorded |
| "The label dispatch route has no producer" | And cannot have one from `github.token`; the label does not exist | Route deleted; alarm dispatches directly |
| "`zot_restarts_at_end` ships `unknown`" | True | Enumerator takes its own END sample |
| "A live at-rest probe replaces the issue-state proxy" | The live probe shipped with #8386/#8408 | Proxy deleted, pointer recorded in ADR |

## Plan Review Revisions (applied)

One architecture-strategist pass (with the sharp-edges catalogue) ran on the first draft. Applied:

- R1. `scripts/followthroughs/zot-inventory-marker-7278.sh` is orphaned the same way (tracker #7339 closed) and passed on any schema: **deleted**, with its line removed from `scripts/lint-shell-trace-credential-refusal.baseline.txt` and the comment in `zot-disk-sample.sh` updated. `zot-log-channel-7440.sh` keeps its historical mention: it is on the same baseline and editing it would trigger that lint's drawdown rule for an unrelated script.
- R2. The END sample could re-read the START row: the heartbeat is 5-minutely and the measured sweep took **104 s** (run of 2026-08-10: enumerate step 11:08:03Z → 11:09:47Z). The enumerator now re-polls until a row newer than `ZOT_DISK_SAMPLE_AT` lands (bounded, 360 s; poll 30 s) and otherwise leaves `unknown`.
- R3. The sampler runs under an `env -i` **allow-list** (PATH, HOME, LC_ALL, TMPDIR, `BETTERSTACK_QUERY_*`), not an `env -u` deny-list: the step's `DOPPLER_TOKEN` would have leaked through the deny-list. The external `timeout` is dropped (`betterstack-query.sh` caps curl at 60 s; the wait loop bounds the rest).
- R4. Guard 2 M2 is killed by the **equal-count, different-boot** row (a 15640 → 0 row also fires on the count clause). Guard 3's ordering property is "the schema verdict precedes the `enumeration_incomplete` arm", not "precedes `observed`".
- R5. The FIRE body's fallback text still names `gh workflow run registry-zot-inventory.yml`; the guard and the discoverability command therefore match the anchored `if gh workflow run …` line, not the bare string.
- R6. `zot-restart-loop-alarm.sh`'s non-OOM `CAUSE` "NEXT: dispatch …" clause is reworded to say the alarm dispatches it (no fixture pins that text; `zot-restart-loop-alarm.test.sh` 59/59).
- R7. Acceptance Criteria split into pre-merge and post-merge; a legal sweep for the ADR status flip is recorded (0 hits).
- Kept (taste): the job-level end-sample step in `registry-zot-inventory.yml` stays. It feeds the #7339 comment and the job warning and runs after emit; the enumerator's sample is the one that reaches the durable marker. The dedicated `ZOT_INVENTORY_END_SAMPLE_CMD` seam is kept over the sampler's `ZOT_DISK_SAMPLE_QUERY_CMD`: the suite runs a copy of the enumerator from a scratch dir, and the sampler's own parsing is already covered by `tests/scripts/test-zot-disk-sample.sh`.
- Noted, not changed: the inventory workflow still comments its result on #7339, which is closed. The new tracker comment carries the run link, so the operator reaches the result from the tracker.

## Implementation Phases

### Phase 1: tests first (RED)

1.1 `apps/web-platform/test/server/watchdog-workflow-idempotence.test.ts`: new `describe`
"the restart-loop FIRE step dispatches the read-only inventory once per new non-OOM tracker (#7377)".
Extend the `gh` stub to accept `issue create` (print a URL), `issue comment` and `label create`
(log only). Execute the FIRE step's `run:` bytes:
- no open tracker + non-OOM `CAUSE` → log contains `workflow run registry-zot-inventory.yml` with `--ref main` and `-f action=inventory`, and a comment saying it was dispatched;
- open tracker exists (repeat run in the slot) → no `workflow run`;
- no open tracker + OOM `CAUSE` → issue created, no `workflow run`;
- no open tracker + non-OOM + dispatch fails (`STUB_DISPATCH_FAIL=1`) → step exits 0, issue was created, a comment says the dispatch FAILED;
- a `CAUSE` whose tail (not prefix) contains `non-OOM crash-loop` behind an OOM prefix → no dispatch (prefix anchoring).
Also assert the workflow's `permissions` include `actions: write`.

1.2 `apps/web-platform/infra/registry-zot-inventory-workflow-guard.test.sh`: replace the
dispatch-route assertions (the file-exists check, `dispatch_guard_two_clause`, the dispatch
registration-push check and the `dispatch_wf_path` infra-paths check) with:
- `registry-zot-inventory-dispatch.yml` does not exist;
- no workflow under `.github/workflows/` combines an `issues` trigger with a job `if:` naming the `registry-zot-inventory` label (parsed YAML, both `on:` spellings; floor: the scanned workflow count is ≥ 50 so an empty glob cannot pass);
- `scheduled-zot-restart-loop.yml` declares `actions: write` and its FIRE step's `run:` carries a non-comment `gh workflow run registry-zot-inventory.yml` line;
- `infra-validation.yml` `pull_request.paths` includes `.github/workflows/scheduled-zot-restart-loop.yml` and no longer lists the deleted file;
- mutation arm: a scratch copy of the workflow set with a synthetic label-listener re-added must flip the "no label route" probe to `no`.
Re-set `MIN_ASSERTIONS` to the new count.

1.3 `tests/scripts/test-zot-inventory.sh`: END-sample rows, all via a new seam
`ZOT_INVENTORY_END_SAMPLE_CMD` pointing at a fixture script, with `ZOT_RESTARTS_AT_END=`
emptied and `BETTERSTACK_QUERY_HOST` set:
- sampler prints the same boot and the same count → `zot_restarts_at_end=15640`, no straddle, outcome `ok`;
- same boot, higher count → `zot_restarts_at_end=15641`, `reason=restart_during_sweep`, rc 1;
- different boot, count `0` (a replace mid-sweep; `0` equals nothing useful) → `reason=restart_during_sweep`;
- sampler exits 2 (transport) → `zot_restarts_at_end=unknown`, outcome `ok` (a missing END sample never fails the sweep);
- sampler prints a non-numeric count → `unknown`;
- `BETTERSTACK_QUERY_HOST` unset → the sampler is **not** invoked (fixture writes a sentinel file; assert absent) and the value is `unknown`;
- a caller-supplied `ZOT_RESTARTS_AT_END` wins (sampler not invoked);
- the sampler is invoked **without** `ZOT_PULL_TOKEN` / `BETTERSTACK_LOGS_TOKEN` in its environment (fixture dumps its env names; assert neither sentinel name appears).

1.4 `tests/scripts/test-zot-inventory-assert-marker.sh`: rows
- a `run_id` row with `marker_schema=2 … enumeration_complete=true` → `outcome=unknown reason=marker_schema_unsupported`, exit 3;
- a row with no `marker_schema` field → same;
- `marker_schema=1` (existing pass row) still → `observed`, exit 0 (must-PASS);
- `marker_schema=10` must not satisfy a `marker_schema=1` match (anchoring).

### Phase 2: implementation (GREEN)

2.1 Delete `.github/workflows/registry-zot-inventory-dispatch.yml`.

2.2 `scheduled-zot-restart-loop.yml`: add `actions: write` to top-level `permissions` with a
one-line reason. In the FIRE step's new-issue arm only: capture the created issue URL; if
`CAUSE` starts with the fixed literal `non-OOM crash-loop — `, run
`gh workflow run registry-zot-inventory.yml --repo "$GH_REPO" --ref main -f action=inventory`
fail-soft, then comment on the new issue with either "dispatched" (plus the Actions link) or
"dispatch FAILED" plus a `::warning::`. Rewrite the issue-body paragraph that tells the operator
to run the dispatch and that says the levers "still need a provisioning event (#7377)".

2.3 `infra-validation.yml`: replace the deleted path with
`.github/workflows/scheduled-zot-restart-loop.yml` in `pull_request.paths`; update the #7278
comment.

2.4 `scripts/zot-inventory.sh`: after the enumeration loop, before the completeness/verdict
block, add `take_end_sample()` (revised per R2/R3):
- skipped when `ZOT_RESTARTS_AT_END` was supplied, or when `BETTERSTACK_QUERY_HOST` is unset (printing why to stderr);
- runs `${ZOT_INVENTORY_END_SAMPLE_CMD:-<script dir>/zot-disk-sample.sh} --since 30m --limit 50` under an `env -i` allow-list, re-polling every `ZOT_INVENTORY_END_SAMPLE_POLL_S` (30) until the row's `sample_at` is newer than `ZOT_DISK_SAMPLE_AT`, for at most `ZOT_INVENTORY_END_SAMPLE_WAIT_S` (360);
- reads `zot_restarts` and `boot_id` (sanitized like the START boot); a non-numeric count leaves `unknown`; a boot id that differs from the START boot (both known) sets `END_BOOT_CHANGED=1`;
- the `restart_during_sweep` arm fires on (both counts numeric and different) OR `END_BOOT_CHANGED=1`.
Update the header ENV CONTRACT and the egress statement (a third destination: the Better Stack
**query** endpoint, read-only, reached only through `betterstack-query.sh`, which pins it).

2.5 `registry-zot-inventory.yml`: rewrite the "PASSED BUT NOT YET CONSUMED" env-contract comment
to say the script now takes its own END sample from those variables. No step or `env:` change.

2.6 `scripts/zot-inventory-assert-marker.sh`: add `readonly EXPECTED_MARKER_SCHEMA=1`. In
`poll_once`, count `run_id` rows lacking `(^| )marker_schema=1( |$)` as `SCHEMA_OTHER_ROWS`, and
count `MARKER_ROWS` only over rows carrying it. After the poll loop and before the `observed`
verdict: if `SCHEMA_OTHER_ROWS ≥ 1` and `MARKER_ROWS == 0`, emit `unknown marker_schema_unsupported`
(exit 3), placed before the `transport` / `channel_dark` / `enumeration_incomplete` arms.
Document the reason code in the header's OUTCOMES table.

2.7 Delete `scripts/followthroughs/registry-luks-blocker-6929.sh` and (R1)
`scripts/followthroughs/zot-inventory-marker-7278.sh`; drop the latter's baseline line.

2.8 (R6) Reword the non-OOM `CAUSE` next-action clause in `scripts/zot-restart-loop-alarm.sh`.

### Phase 3: ADR and C4

3.1 ADR-172: `Status: accepted`; append `## Amendment 2026-09-28 — the blocked write set is
resolved, not built (#7377)` with Context / Decision (push-config realized as merge → replace;
restart will not be built; reclaim will not be built now, re-evaluate when `pcent ≥ 70` holds
for 24 h, and it would ship as a push-config through the replace path) / Options considered
(A in-place push, B host-side pull agent, C merge-to-replace [chosen], D keep "blocked") /
Consequences; update §3 with an appended superseded note (body left as written, same convention
as §8); update "Enforced by" (the dispatch-only guard now also asserts no label route and the
alarm dispatch), the egress-confinement wording, and "Status flip condition" (flip met 2026-08-10
by the #7339 marker; the #7340 enrolment and its probe are retired, pointer to
`registry-luks-live-8386.sh`). The recorded cosign config drift stays recorded, now noted as
deliverable through push-config.

3.2 C4 `model.c4`: the `github -> zotRegistry` edge's INVENTORY clause gains how the sweep is
fired (manual `workflow_dispatch`, or the restart-loop alarm on a new non-OOM tracker) and that
it now reads one `SOLEUR_ZOT_DISK` END sample through `betterstack-query.sh`. The lefthook hook
regenerates `model.likec4.json`.

### Phase 4: verify

Targeted only: `bash tests/scripts/test-zot-inventory.sh`, `bash tests/scripts/test-zot-inventory-assert-marker.sh`,
`bash apps/web-platform/infra/registry-zot-inventory-workflow-guard.test.sh`,
`npx vitest run test/server/watchdog-workflow-idempotence.test.ts` (in `apps/web-platform`),
`bash scripts/zot-restart-loop-alarm.test.sh` (unchanged script; confirms no fixture relied on
the body text), `actionlint` on the two edited workflows, C4 tests
(`c4-code-syntax`, `c4-render`, `plugins/soleur/test/c4-count-parity.test.sh`).

## Files to Edit

- `.github/workflows/scheduled-zot-restart-loop.yml`
- `.github/workflows/infra-validation.yml`
- `.github/workflows/registry-zot-inventory.yml` (comment only)
- `scripts/zot-inventory.sh`
- `scripts/zot-inventory-assert-marker.sh`
- `tests/scripts/test-zot-inventory.sh`
- `tests/scripts/test-zot-inventory-assert-marker.sh`
- `apps/web-platform/infra/registry-zot-inventory-workflow-guard.test.sh`
- `apps/web-platform/test/server/watchdog-workflow-idempotence.test.ts`
- `knowledge-base/engineering/architecture/decisions/ADR-172-ci-side-observability-emission-and-read-only-registry-inventory.md`
- `knowledge-base/engineering/architecture/diagrams/model.c4` (+ regenerated `model.likec4.json`)
- `scripts/zot-restart-loop-alarm.sh` (one `CAUSE` clause, R6)
- `scripts/zot-disk-sample.sh` (comment only, R1)
- `scripts/lint-shell-trace-credential-refusal.baseline.txt` (drop the deleted probe, R1)

## Files to Delete

- `.github/workflows/registry-zot-inventory-dispatch.yml`
- `scripts/followthroughs/registry-luks-blocker-6929.sh`
- `scripts/followthroughs/zot-inventory-marker-7278.sh` (R1)

## Files to Create

None.

## Open Code-Review Overlap

None. Checked the open `code-review` issues (300) for `scheduled-zot-restart-loop.yml`,
`registry-zot-inventory`, `zot-inventory.sh`, `zot-inventory-assert-marker`, `ADR-172`,
`registry-luks-blocker-6929` and `watchdog-workflow-idempotence`: 0 matches.

## Architecture Decision (ADR/C4)

### ADR

Amend **ADR-172** (not a new ADR): the blocked write set is resolved, not built; status
`adopting → accepted`. Rationale in the Overview. No new ordinal is claimed.

### C4 views

Checked all three model files. External actors / systems / relationships touched: GitHub Actions
(`github`) → zot registry (`zotRegistry`, inventory traversal: trigger source changes), GitHub →
Better Stack (`betterstack`, already described as polling `SOLEUR_ZOT_DISK`; the END sample is
one more read on the same edge, no text change needed), GitHub → public reader (restart-loop
issue publication: unchanged; the new comment carries only a fixed sentence and a run link).
The web-server dispatch clock edge (`api -> github`) is unchanged. One edit: the
`github -> zotRegistry` INVENTORY clause. `c4-count-parity` is run because no counted population
(workflows with heartbeats, monitors) changes; the deleted workflow posts no heartbeat.

### Sequencing

The decision is true on merge; no soak gate.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing directly. The worst case is the restart-loop alarm's FIRE step failing after it opens its tracker (mitigated: the dispatch is fail-soft and runs after `gh issue create`), or an inventory run marking a sweep `partial` on a spurious straddle. Neither touches the pull path, deploys or user data.
- **If this leaks, the user's data is exposed via:** no new vector. The inventory is read-only with pull credentials (ADR-172 §4/§5); the END sampler runs with the pull and ingest tokens removed from its environment; the new issue comment contains a fixed sentence and a run URL, no log content.
- **Brand-survival threshold:** `none`

`threshold: none, reason: the touched apps/web-platform/infra/ path is a CI guard test and infra-validation.yml only gains a path filter; neither changes what any user-facing host runs.`

## Observability

```yaml
liveness_signal:
  what: "the scheduled-zot-restart-loop Sentry cron monitor (unchanged) plus, per FIRE, a comment on the [ci/zot-restart-loop] tracker naming the dispatched inventory run or its failure"
  cadence: "hourly alarm; one inventory dispatch per new non-OOM tracker"
  alert_target: "the existing [ci/zot-restart-loop] GitHub issue (action-required label) and the Sentry cron monitor"
  configured_in: ".github/workflows/scheduled-zot-restart-loop.yml (FIRE step); apps/web-platform/infra/sentry/cron-monitors.tf"

error_reporting:
  destination: "GitHub issue comment on the tracker + ::warning:: annotation in the alarm run; for the END sample, the enumerator's stderr in the registry-zot-inventory run log and zot_restarts_at_end=unknown in the SOLEUR_ZOT_INVENTORY marker in Better Stack"
  fail_loud: "a tracker comment saying the inventory dispatch FAILED; zot_restarts_at_end=unknown in the durable marker"

failure_modes:
  - mode: "gh workflow run registry-zot-inventory.yml is refused (permissions, API outage)"
    detection: "the FIRE step's else-arm writes a 'dispatch FAILED' comment on the tracker it just opened and a ::warning::"
    alert_route: "the tracker issue (action-required)"
  - mode: "END sample query fails, returns no row, or no heartbeat newer than the START row lands within 360 s"
    detection: "the marker ships zot_restarts_at_end=unknown; stderr names the sampler exit code or the stale START timestamp"
    alert_route: "the registry-zot-inventory run log (linked from the tracker comment) and the SOLEUR_ZOT_INVENTORY row in Better Stack"
  - mode: "a zot restart or host replace during the sweep"
    detection: "reason=restart_during_sweep in the durable marker (was unreachable before this change)"
    alert_route: "the SOLEUR_ZOT_INVENTORY row (outcome=partial) and the run's ::warning::, reached from the tracker comment's run link"
  - mode: "a future marker_schema is read by the v1 readback gate"
    detection: "zot-inventory-assert-marker.sh verdict unknown/marker_schema_unsupported, exit 3, reds the run"
    alert_route: "the registry-zot-inventory run conclusion"

logs:
  where: "GitHub Actions run logs for scheduled-zot-restart-loop and registry-zot-inventory; SOLEUR_ZOT_INVENTORY rows in Better Stack source 2457081"
  retention: "Actions logs 90 days; Better Stack per plan retention"

discoverability_test:
  command: "grep -cE '^ *if gh workflow run registry-zot-inventory[.]yml' .github/workflows/scheduled-zot-restart-loop.yml"
  expected_output: "1"
```

## Guard Contract

### Guard 1 — no inventory route that nothing can fire, and the alarm dispatches it

**Property.** The only automatic producer of a `registry-zot-inventory.yml` run is a
`workflow_dispatch` issued by the restart-loop alarm when it opens a new non-OOM tracker, and no
workflow waits on a label-triggered path to that run.

**Assembly.** Every file under `.github/workflows/*.yml` (the label listener could be re-added in
any of them, not just the deleted filename); the alarm's FIRE step `run:` body (the only place
the dispatch is issued); the alarm workflow's top-level `permissions` (the dispatch dies without
`actions: write`); `infra-validation.yml` `pull_request.paths` (without it an edit to the alarm
skips this suite).

**Mutation matrix.**

| # | Mutation | Expected RED |
|---|---|---|
| M1 | Re-add a workflow with `on: issues: [labeled]` and `if: github.event.label.name == 'registry-zot-inventory'` under a **different** filename | guard "no label route" (scratch-copy mutation arm) |
| M2 | Remove `actions: write` from the alarm's permissions | guard permissions assertion + vitest permissions assertion |
| M3 | Move the dispatch from the new-issue arm to before the `EXISTING` lookup (dispatches on every repeat run) | vitest "open tracker exists → no workflow run" |
| M4 | Change the prefix test to a substring test (`*"non-OOM crash-loop"*`) | vitest "OOM prefix with non-OOM text in the tail → no dispatch" |
| M5 | Let a dispatch failure `exit 1` the step | vitest "dispatch fails → step exits 0 and comments FAILED" |
| M6 | Comment out the `gh workflow run` line | guard "non-comment dispatch line" + vitest "dispatched" row |
| M7 | Drop the alarm path from `infra-validation.yml` paths | guard infra-paths assertion |

**Harness rows.** (H1) Point the guard's workflow scan at an empty directory: the scanned-count
floor (≥ 50) must red it. (H2) must-PASS: a workflow with an `issues: [labeled]` trigger for a
*different* label (the real `inngest-watchdog-restart-dispatch.yml`) must not trip the
"no label route" probe. (H3) must-PASS: an OOM cause with no open tracker still creates the issue.

**Anchor.** Not a stored-value comparison; the guard reads live workflow bytes.

### Guard 2 — the END restart sample reaches the durable marker

**Property.** When a production caller can query Better Stack, the marker's
`zot_restarts_at_end` is the newest heartbeat's count taken after enumeration, and any restart or
boot change between START and END makes the marker say `restart_during_sweep`.

**Assembly.** `take_end_sample()` in `zot-inventory.sh` (the single writer of
`ZOT_RESTARTS_AT_END_V` after the env read) and the `restart_during_sweep` arm (the single
reader). The `sweep_deadline_exceeded` early exit precedes the sample by design and is out of the
property.

**Mutation matrix.**

| # | Mutation | Expected RED |
|---|---|---|
| M1 | Delete the `take_end_sample` call | "same boot, higher count → restart_during_sweep" |
| M2 | Drop the boot-change clause from the verdict | "different boot, EQUAL count → restart_during_sweep" (measured: 1 red) |
| M2b | Accept the first sampled row regardless of `sample_at` | "only the START row available → unknown", "re-poll until newer" (measured: 3 red) |
| M3 | Let a sampler failure set `zot_restarts_at_end=0` instead of `unknown` | "sampler exits 2 → unknown" |
| M4 | Replace `env -i` (allow-list) with `env` | "sampler env contains no token names", incl. `DOPPLER_TOKEN` (measured: 5 red) |
| M5 | Invoke the sampler even when `ZOT_RESTARTS_AT_END` is supplied | "caller-supplied value wins (sentinel absent)" |

**Harness rows.** (H1) Make the fixture sampler ignore its input and always print the START
values: the "higher count" row must red. (H2) must-PASS: same boot, same count → outcome `ok`,
`zot_restarts_at_end=15640`.

**Anchor.** Not a stored-value comparison.

### Guard 3 — the readback refuses an unknown marker schema

**Property.** `zot-inventory-assert-marker.sh` returns `observed` only for a row that carries
exactly `marker_schema=1`.

**Assembly.** `poll_once` (the only place rows are classified) and the post-loop verdict chain.

**Mutation matrix.**

| # | Mutation | Expected RED |
|---|---|---|
| M1 | Count `MARKER_ROWS` over all run rows again | "`marker_schema=2` → unknown/marker_schema_unsupported" |
| M2 | Match `marker_schema=1` unanchored | "`marker_schema=10` → unsupported" |
| M3 | Place the schema verdict after the `enumeration_incomplete` arm | a schema-2 row would report exit 1 `marker_absent`; row "`marker_schema=2` → exit 3" reds |

**Harness rows.** (H1) must-PASS: the existing `marker_schema=1` row stays `observed`, exit 0.
(H2) a row missing the field must red, not pass.

**Anchor.** `EXPECTED_MARKER_SCHEMA` and the emitter's `MARKER_SCHEMA` are two literals; a bump
of the emitter without the reader reds Guard 3's pass row through the cross-script test
(`test-zot-inventory-assert-marker.sh` builds its fixture with `marker_schema=1`). Parity between
the two literals is asserted in `test-zot-inventory-assert-marker.sh` by reading the emitter's
`readonly MARKER_SCHEMA=` line.

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed
**Legal sweep for the ADR-172 status flip:** `grep -rln 'ADR-172|registry-zot-inventory|SOLEUR_ZOT_INVENTORY|registry-luks-blocker' knowledge-base/legal` → 0 files. The Art. 30 register's mention of `scheduled-zot-restart-loop` concerns the log-tail publication, which this change does not alter (the new comment carries fixed text and URLs only).
**Assessment:** CI, scripts, ADR and C4 only; no host config, no Terraform, no new credential,
no new egress beyond one read through an existing pinned query script. The only new privilege is
`actions: write` on the alarm job, the same grant `scheduled-inngest-health.yml` holds for the
same purpose. Legal, Marketing, Product, Finance, Sales, Operations, Support: no implications
(no user-facing surface, no data processing change, no cost).

## Test Scenarios

See Phase 1 (1.1-1.4). Every row is written and observed RED before its implementation.

## Sharp Edges

- The FIRE step runs under `bash -eo pipefail`; the dispatch must be an `if gh workflow run …; then … else … fi` so a refusal cannot abort the step after the tracker exists.
- `CAUSE` carries an attacker-influenced tail; only a **prefix** match is safe.
- `doppler run --only-secrets` passes the ambient environment through, which is how `BETTERSTACK_QUERY_*` reaches the enumerator; the END sampler strips the injected secrets before it runs.
- A plan whose `## User-Brand Impact` section is empty, contains only placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] AC1: `.github/workflows/registry-zot-inventory-dispatch.yml` is deleted and the guard asserts no workflow listens for the `registry-zot-inventory` label.
- [ ] AC2: `scheduled-zot-restart-loop.yml` holds `actions: write` and its FIRE step dispatches `registry-zot-inventory.yml` exactly once per new non-OOM tracker, fail-soft, with a tracker comment recording the outcome (vitest rows in 1.1 green).
- [ ] AC3: `zot-inventory.sh` takes its own END sample from a heartbeat newer than the START row; the `restart_during_sweep` arm is reachable from a production-shaped environment (rows in 1.3 green).
- [ ] AC4: `zot-inventory-assert-marker.sh` refuses a non-v1 `marker_schema` (rows in 1.4 green).
- [ ] AC5: both orphaned follow-through probes are deleted; `git grep -n 'registry-luks-blocker-6929\|zot-inventory-marker-7278' -- ':!knowledge-base/project/'` returns only ADR-172's historical mentions and the untouched comment in `zot-log-channel-7440.sh`.
- [ ] AC6: ADR-172 reads `Status: accepted` and carries the 2026-09-28 amendment with the push-config / restart / reclaim decisions and options considered.
- [ ] AC7: `model.c4` inventory clause names both triggers; `c4-render` and `c4-count-parity` green.
- [ ] AC8: no diff under `apps/web-platform/infra/cloud-init-registry.yml`, `zot-registry.tf`, `ci-deploy.sh` or `.github/workflows/apply-web-platform-infra.yml` (`git diff --name-only origin/main...HEAD`).
- [ ] AC10: PR body carries `Closes #7377`.

### Post-merge (executor: `gh workflow run registry-zot-inventory.yml -f action=inventory`, run by this pipeline after merge)

- [ ] AC9: only after confirming no `registry-host-replace` run is in progress, one dispatch on `main` produces a `SOLEUR_ZOT_INVENTORY` marker whose `zot_restarts_at_end` is numeric AND whose run log shows the END row's `sample_at` later than the START row's.
