# Decision Challenges — feat-one-shot-8036-retire-host-ghcr-read-path

Persisted by `plan-review` running headless (pipeline mode, no TTY). `ship` Phase 6 renders these
into the PR body and files an `action-required` issue. Each entry is surfaced, never auto-applied.

Plan: `knowledge-base/project/plans/2026-09-23-fix-retire-host-ghcr-read-path-plan.md`
Operator ruling being challenged: the 1c ruling on #8036, 2026-09-22.

---

## DC-1 — Ship as TWO PRs instead of one

**Class:** user-challenge
**Raised by:** `soleur:engineering:cto` (named-panel devex seat)

**The operator's stated direction is the default.** The 2026-09-22 ruling says *"The follow-up PR
removes the prelude `docker login ghcr.io`, `refetch_ghcr_and_relogin` and the GHCR leg of
`_ghcr_pull_or_recover`, and deletes the stale `ghcr.io` entry from the home docker config"* —
singular, one PR.

**What the reviewer proposes instead.** Split:

- **PR-A — signal-parity reconciliation.** `issue-alerts.tf` (drop the one `ghcr-fallback`
  condition), `alert-reference.json`, `zot-soak-6122.sh` + `.test.sh` (floor `5`→`4`),
  `sentry-zot-mirror-fallback-alert-op-contract.test.ts`, `tests/scripts/test-sentry-alert-live-fidelity.sh`,
  `scheduled-zot-restart-loop.yml`, `variables.tf`, `zot-registry-revert.md`. No host behavior change.
- **PR-B — the script surgery.** `ci-deploy.sh`, `ci-deploy.test.sh`, the new probe, the ADR
  amendments + `model.c4`, the probe one-leggings, the alert-capture re-pin.

**Why it is not merely taste.** The plan's own AC-Q4 already states the constraint as a *commit*
ordering rule ("the soak floor move … land in a commit before the emitter is deleted"), which is a PR
boundary described in a weaker form. And the split resolves a genuine chicken-and-egg the single-PR
shape cannot: `## Files to Edit` prescribes re-pinning `scripts/sentry-alert-live-fidelity.sh`'s
committed capture **after the apply**, but the apply is fired *by merging that same PR*. Split, the
re-pin lands at the head of PR-B.

**Cost of not splitting.** The reviewer's judgement: PR-B's `ci-deploy.sh` diff is the only part where
a mistake costs a release, and in a single PR it arrives diluted by ~15 prose edits across 8 files.
The merge click would also authorize a script push **and** a Sentry apply together rather than one.

**Trade-off in the other direction.** Two PRs is two review cycles, two merges and two applies for a
change the operator scoped as one follow-up; the parity half is operationally inert (ADR-096's
2026-09-22 amendment records the soak is *not enrolled* in the sweeper), so the split buys
reviewability rather than safety.

**Default if unanswered:** ship as ONE PR per the ruling, and resolve the re-pin chicken-and-egg
in-scope by moving the capture re-pin to a post-merge step of the same PR's follow-through.

---

## DC-2 — Absorb `cosign-verify-live-8037.sh` and execute its overdue retirement clause

**Class:** user-challenge (scope addition beyond the 1c ruling)
**Raised by:** `soleur:engineering:cto` (named-panel devex seat)

**Measured facts, not opinion:**

- #8037 is CLOSED/COMPLETED (closed 2026-09-22), yet `scripts/followthroughs/cosign-verify-live-8037.sh`
  carries `# RETIREMENT: when #8037 closes, delete this file and its .test.sh, drop its run_suite line
  in scripts/test-all.sh, and remove the directive from the issue body.` **That clause has fired and
  has not been executed** — the file, its `.test.sh`, its `run_suite` line and the issue-body directive
  are all still live.
- The plan routes its worst failure mode (the sweep clipping the zot auths entry → silent
  `IMAGE_VERIFY_FAIL: result=verify_failed` under `IMAGE_VERIFY_MODE=warn`) to that probe — i.e. to a
  probe on a closed tracker, which the sweeper evaluates only inside its closed-set lookback.

**What the reviewer proposes.** Have `ghcr-read-retired-8036.sh` absorb the cosign-verdict leg AND
delete `cosign-verify-live-8037.sh` + `.test.sh` + the `scripts/test-all.sh` `run_suite` line + the
#8037 directive and label. Net file count goes `-1` instead of `+1`, and the stale retirement clause is
discharged by the PR best positioned to do it.

**Why this is surfaced rather than applied.** Deleting another issue's probe and editing a closed
issue's body is scope the 1c ruling does not cover, and it makes this PR the owner of #8037's cleanup.

**What IS being applied in-scope regardless** (classified Mechanical — the gap is real and the plan
names it as its own worst arm): the new probe will grade the cosign-verdict leg alongside the
conjunction, so detection does not depend on a closed tracker's probe. The deletions stay out of scope
pending this answer.

**Default if unanswered:** keep `cosign-verify-live-8037.sh` in place; the new probe carries the
cosign leg; file the overdue retirement as its own issue rather than folding it in here.

---

## Challenges surfaced during implementation (`soleur:work`, 2026-09-23)

### DC-W1 — the plan contradicted itself on the sweep's scope, three ways

`## Technical Approach` derives, at length and from `webhook.service`'s own unit file, that the
sweep can cover the **deploy** config only: `/home` is under `ProtectHome=read-only` and absent
from `ReadWritePaths`, so a home write fails soft and would **silently never sweep**, while any
acceptance criterion graded on `home_ghcr_auth=none` would read `inline` forever and #8036 could
never close. `AC-F2` and `T-1c-4` agree with that.

Five other sites did not: the ASCII architecture diagram ("sweep ghcr.io auths from deploy + home
cfg"), the sentence introducing the sweep code ("removes the key from both"), Phase 2's function
map ("the two `_sweep_ghcr_auth` calls"), `## Files to Edit` ("its two calls"), `T-1c-2`'s fixture
("a deploy config and a home config each"), and Guard 1's assembly ("the two *writable* configs").

**Disposition: implemented the scope correction; corrected the six stale sites in the plan.** The
scope correction is the reasoned, measured section and the ACs follow it. `T-1c-2` now asserts the
home config is left **byte-identical**, which is the testable form of "observed, not swept" — a
stronger row than the one the stale prose asked for, because it would catch a future edit that
tried the unreachable write and failed soft.

### DC-W2 — `## Files to Edit` still prescribed a rename that Phase 2 had CUT

It said "Rename `GHCR_DOCKER_CONFIG` → `DEPLOY_DOCKER_CONFIG_FILE`", while Phase 2 and the
structural map both record the rename as cut at plan review (no property, 9 sites plus its test,
and an ADR clause that existed only because of the rename). **Disposition: honoured the CUT**, and
corrected `## Files to Edit`. The symbol's header comment is fixed instead, which is what actually
misleads.

### DC-W3 — Phase 1 and `## Test Scenarios` gave `T-1c-8` two different contracts

Phase 1 listed it as an untouched-config harness row; Test Scenarios gave it as the mode/ownership
row. **Disposition: `## Test Scenarios` wins** — the plan declares it the single source of truth
for the `T-1c-*` set, in the same paragraph that records an earlier draft carrying three different
contracts for these identifiers. The untouched-config cases Phase 1 named are covered by the
`#8036 1b` marker matrix (`credsstore` / `noghcr` / `absent` → `swept=no` / `swept=na`).

### DC-W4 — the suite's default zot-DARK mode modelled a state in which no deploy can succeed

Not a plan defect; a consequence the plan named (`ZOT_ACTIVE=0` becomes terminal) whose blast
radius on the test harness it did not size. Before 1c a zot-dark deploy fell through to GHCR, and
the suite's default mode relied on that: the GHCR mock serves every pull, so "a deploy ran" was
expressible without zot. After 1c a zot-dark deploy cannot complete, so **every** row that merely
needed a deploy to reach its subject was asserting against the failure path.

**Disposition: zot is armed by default in the harness**, with `MOCK_ZOT_DARK=1` as the explicit
opt-out for the rows that are *about* the dark gate. 38 rows moved; the taxonomy and the reason
for each is recorded in the PR body.

### DC-W5 — #7095's fail-open contract cannot hold, and the capability was already gone

`T-7095-6` pinned "a network-shaped Doppler read failure must still **complete** the deploy, on
the baked GHCR creds". That is unachievable after 1c: the same failing read degrades
`ZOT_REGISTRY_URL`, and there is no second registry to complete on.

**This is a real narrowing and is recorded as one rather than absorbed.** But the capability was
lost on **2026-07-29**, not here: completing "on the baked GHCR creds" required those creds to
work, and the GHCR read PAT has been revoked since then, so the live fleet has taken
`image_pull_failed` down this path for ~8 weeks. The row passed only because the suite's mock
serves GHCR pulls unconditionally — a fixture that outlived the thing it modelled.

**Disposition: the row is narrowed to what is still true and still worth pinning** — the prelude
must degrade *loudly without aborting*, proven positively by a downstream emission rather than by
an exit code. The residual, stated plainly: on a host whose Doppler is blipping, a deploy now
fails at the pull where before 2026-07-29 it would have completed.

### DC-W6 — a diagnostic specificity loss, repaid rather than accepted

`resolve_env_file`'s `doppler_unavailable` / `doppler_token_missing` / `doppler_fetch_failed`
terminal reasons are now unreachable through a full deploy, because the pull fails first. Left
alone, an operator would get a bare `image_pull_failed` for a credential problem.

**Disposition: the terminal `pull_failure_event` on the zot-dark arm carries `ZOT_GATE_STATUS`**,
and its matching `ZOT_GATE_DEGRADED: reason=<measured>` journald line names the same condition.
The re-pointed rows assert **both** — a row asserting only `image_pull_failed` would pass against
a version that reports a credential problem as a bare registry outage.

> **CORRECTION 2026-09-23 (#8600 review) — AS FIRST WRITTEN, THIS DISPOSITION WAS FALSE, AND THE
> REPAYMENT DID NOT EXIST.** The claim above was that interpolating `ZOT_GATE_STATUS` into
> `pull_failure_event`'s second argument made the cause reachable. It did not. That argument is
> `detail_raw`, and the function used it for **one thing only** — feeding the three classifiers
> (`_pull_result_is_auth_denied`, the `manifest unknown` regex, `_pull_result_is_transient`) —
> and then discarded it. The journald line emitted `ref`, `result` and `recovery_stage` and no
> detail; the Sentry payload carried `tags: {feature, op, pull_result, host_id, recovery_stage}`
> and `extra: {ref}` and no detail field. The status therefore reached **no sink at all**, and a
> `grep` of the emitter would have shown that at any point while this paragraph was being written.
> This is the "correct fix, false rationale" class, applied to a compensating control — the worst
> place for it, because the control is what licensed accepting the loss.
>
> Three further errors in the same paragraph, all now fixed in code:
>
> 1. **`ZOT_GATE_DEGRADED` did not always fire.** On the `no doppler binary / no DOPPLER_TOKEN`
>    arm with a non-empty `ZOT_REGISTRY_URL`, `zot_gate_and_login` returned `dark` and emitted
>    **nothing** — a now-terminal state with no cause on any layer. It emits on every dark return.
> 2. **One reason for two remediations.** `doppler_unavailable` and `doppler_token_missing` both
>    collapsed into `no_credential_source`, so "the image lost the doppler binary" and "the host's
>    token is gone" became indistinguishable without SSH. Split into `no_doppler_binary` /
>    `no_doppler_token`.
> 3. **The classifier is an undeclared contract.** Because the status is interpolated into the
>    string those three predicates read, a future value containing `timeout` would silently
>    retag every zot-dark failure as `pull_result=network`. Noted at the enum's definition site.
>
> **What the repayment actually is now:** `pull_failure_event` emits `zot_gate_status` as a
> journald field *and* a Sentry tag, so the join is available from Sentry alone. `T-1c-20`
> asserts every terminal pull failure carries a named status, with the failure count as the
> denominator so "zero untagged" cannot be satisfied by a run that never failed.

### DC-W7 — declined, carried forward: `cosign-verify-live-8037.sh` is not deleted here

Plan review proposed deleting it and executing its overdue `# RETIREMENT:` clause, since #8037 is
closed. **Declined as out of scope for the 1c ruling** (it is DC-2 in this file). The consequence
is handled rather than ignored: because the sweeper only evaluates a closed issue's probe inside
its closed-set lookback, the `verify_failed` detection that probe would have provided is carried
as **leg 3** of `ghcr-read-retired-8036.sh`, on an open tracker, needing no Terraform apply.
