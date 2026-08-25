# Tasks — #7674 inngest host not serving, and G3.7 latch blindness

Derived from
`knowledge-base/project/plans/2026-08-25-fix-inngest-host-not-serving-and-latch-gate-blindness-plan.md`.

**Standing constraints for every task below**
- Do **NOT** dispatch `op=arm`, under any diagnosis.
- Do **NOT** edit `apps/web-platform/infra/cloud-init-inngest.yml`, including comments.
- Do **NOT** dispatch a host replace — it reboots into the same `rolled-back` flag and destroys the
  standing diagnostic evidence.
- Pull diagnostics from Better Stack; never SSH, and never route a diagnostic through a person.
- Run `bash scripts/test-all.sh --capacity` before any full battery (last measured:
  `CAPACITY_CONTENDED`, 4 sibling runs).

## Phase 0 — Preconditions (re-measure; the plan's numbers rot)

- [ ] 0.1 Re-run the probe query and confirm `server_active`, `cutover_flag`, and `boot_id` still
      match the plan's measured table.
- [ ] 0.2 Re-run G3.7's exact query at 7d/30d/365d and confirm the row count is still 0.
- [ ] 0.3 Re-measure the flip-FSM emit cadence (`--grep noop-rolled-back`, bucketed per minute).
      Phase 6's rate-limit target and Phase 1's window both depend on it.
- [ ] 0.4 Confirm `inngest-cutover-flip` is still in `vector.toml`'s Source-4 allowlist **and** that
      rows are still arriving. The liveness witness is dead on arrival if either is false — this is
      the exact failure recorded in the 2026-07-08 allowlist learning.
- [ ] 0.5 Re-read `scripts/cutover-inngest.sh` around G3.6/G3.7 and the decider's extraction contract
      before editing.

## Phase 1 — G3.7: distinguish "clear" from "cannot tell"

- [ ] 1.1 Write the failing decision-table tests first, covering the full `(L, H)` cross-product
      including both non-decimal arms.
- [ ] 1.2 Add the liveness reader as a function at column 0 outside the `arm)` body, with exactly one
      call site.
- [ ] 1.3 Validate both counts with an explicit `^[0-9]+$` predicate; never reach a comparison via
      bash arithmetic coercion.
- [ ] 1.4 Add the `silent` outcome to `flush_latch_decide`, preserving its signature and column-0
      closing brace (the harness extracts it by `awk` range).
- [ ] 1.5 Keep the single positive-allowlist chokepoint; add no `exit 1` inside any case arm.
- [ ] 1.6 Rewrite the gate comment to state that `clear` is a **weak** verdict while the
      retention question is unresolved, and that the on-host latch remains the authority.
- [ ] 1.7 Add ordering assertions (G3.6 < G3.7 < first prod write) and the two-call-site assertion.
- [ ] 1.8 Confirm the existing "no literal off-host read path inside `arm)`" assertion stays green.
- [ ] 1.9 Re-measure and raise the anti-deletion floor by **running** the suite; never copy a
      remembered figure.

## Phase 2 — Give the probe marker a consumer

- [ ] 2.1 Write failing tests for the four verdicts: healthy, stopped-by-brake, not-serving,
      probe-unavailable.
- [ ] 2.2 Implement the reader, selecting on the host field — never a bare payload substring, because
      the probe script is the shared renderer for the dedicated host and web-1.
- [ ] 2.3 Ensure a missing probe row classifies as `probe-unavailable`, never as healthy.
- [ ] 2.4 Carry `cutover_flag` into the alert message so the cause travels with the alarm.
- [ ] 2.5 Register the workflow and confirm it is scheduled.

## Phase 3 — `inngest-volume-recut` apply_target (destructive, gated, inert)

- [ ] 3.1 Write the guard suite first: enum↔job binding, reviewer-set non-emptiness, confirm-literal
      distinctness — each with its mutation row.
- [ ] 3.2 Add the enum option **and** its guarded job in the same change (an option with no job is a
      silent no-op that nothing lints for).
- [ ] 3.3 Declare `environment: inngest-cutover` — reuse the already-provisioned environment; do not
      mint a new one (an unprovisioned environment auto-approves silently).
- [ ] 3.4 Add the typed confirm literal, distinct from every existing literal, plus the
      `expected_volume_id` numeric pin. Label both as typo-guards, not the authorization.
- [ ] 3.5 Write `tests/scripts/lib/inngest-volume-recut-gate.sh`, scoped to the volume and its
      attachment, failing closed on any action against `hcloud_server.inngest` or any unrelated
      resource, and on an empty or non-numeric count.
- [ ] 3.6 Add the post-apply jq backstop reading the **saved** plan.
- [ ] 3.7 Add the job-level concurrency mutex.
- [ ] 3.8 Confirm the target ships inert — no auto-apply path reaches it.
- [ ] 3.9 Record in the workflow that the next target needing an input must split into a dedicated
      workflow (slot 8 of 10 is now spent).

## Phase 4 — Follow-through

- [ ] 4.1 Commit `scripts/followthroughs/inngest-host-not-serving-7674.sh` as mode `100755` (asserted
      against the git index) **before** touching any issue body — the directive gate refuses a
      `script=` that is not an existing executable.
- [ ] 4.2 Assert the exit criterion **positively**: `server_active=active` **and** `http_code=200`.
      No absence arm.
- [ ] 4.3 Use `set -uo pipefail` without `-e`; avoid the banned `${VAR:?}` form; name required env
      literally (the sweeper runs probes under `env -i`).
- [ ] 4.4 Set `earliest=` to reflect that step 4b is deferred to the cutover window, so the probe
      returns TRANSIENT rather than commenting daily.
- [ ] 4.5 Remove the stale follow-through directive from **both** #7462 and #7228 — it is dual-hosted
      on two closed issues. Retire; do not re-point. Leave the predecessor file on disk.
- [ ] 4.6 Add the directive for the successor probe to #7674, **and add the `follow-through` label** —
      verified 2026-08-25 that #7674 carries only `priority/p1-high`, `type/chore`,
      `domain/engineering`. The sweeper lists `--label follow-through`, so without the label the
      directive is inert no matter how well-formed the probe is.
      (Verified the same day: #7462 and #7228 each still carry exactly one `soleur:followthrough`
      directive, both pointing at the retired probe.)

## Phase 5 — Corrections

- [ ] 5.1 Runbook: correct the G3.6 remediation — clearing `INNGEST_DIAGNOSTIC_BOOT` cannot re-render
      a running host's ExecStart (the flag is consumed at first boot only).
- [ ] 5.2 Runbook: correct the G3.7 remediation — a host replace re-attaches the volume, it does not
      recut it. Point at the Phase 3 target.
- [ ] 5.3 Runbook: add the new failure mode — inactive because a standing `rollback` flag stopped the
      unit — with the one-row discriminator and the `inactive` ≠ `failed` note.
- [ ] 5.4 ADR-100 addendum: record replace-only code delivery to the dedicated host.
- [ ] 5.5 ADR-100 addendum: separate "host dark" from "query finds nothing"; the July attribution
      does not generalise.
- [ ] 5.6 ADR-100: record the G3.7 two-signal design and the re-rejection of the webhook alternative.

## Phase 6 — Flip FSM emit rate-limit (replace-coupled)

- [ ] 6.1 Rate-limit the terminal no-op arms only, to ~5 minutes.
- [ ] 6.2 Do **not** go transition-only — that destroys the liveness witness Phase 1 depends on.
- [ ] 6.3 State in the change that it takes effect on the next replace, and that Phase 1's window is
      sized for both cadences.

## Phase 7 — Verification

- [ ] 7.1 `bash apps/web-platform/infra/cutover-inngest-workflow.test.sh`, then again under `LC_ALL=C`.
- [ ] 7.2 `bash apps/web-platform/infra/run-registered-suites.sh` (floor 100, zero unaccounted).
- [ ] 7.3 `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt`
- [ ] 7.4 `bash scripts/lint-workflows.sh` (only a hang is failure).
- [ ] 7.5 Assert `cloud-init-inngest.yml` is absent from `git diff --name-only origin/main...HEAD`.
- [ ] 7.6 Run **every** acceptance criterion against the pre-fix tree and confirm each one FAILS
      there. An AC that passes before the change is vacuous.
- [ ] 7.7 File the tracking issue for the plaintext `/mnt/data` encryption exception.
- [ ] 7.8 Surface `decision-challenges.md` (UC-1: the webhook substitution) in the PR body.
