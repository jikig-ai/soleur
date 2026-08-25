# Tasks — #7674 inngest host not serving, and G3.7 latch blindness

Derived from
`knowledge-base/project/plans/2026-08-25-fix-inngest-host-not-serving-and-latch-gate-blindness-plan.md`.

**Standing constraints for every task below**
- Do **NOT** dispatch `op=arm`, under any diagnosis.
- Do **NOT** edit `apps/web-platform/infra/cloud-init-inngest.yml`, including comments.
- Do **NOT** dispatch a host replace — it reboots into the same `rolled-back` flag and destroys the
  standing diagnostic evidence.
- Do **NOT** close #7674. The PR body uses `Tracks #7674`, never `Closes` — closing it would enrol
  the Phase 4 probe on a closed issue, which is the exact silent no-op this work retires.
- Pull diagnostics from Better Stack; never SSH, and never route a diagnostic through a person.
- Run `bash scripts/test-all.sh --capacity` before any full battery (last measured:
  `CAPACITY_CONTENDED`, 4 sibling runs).

## Phase 0 — Preconditions (re-measure; the plan's numbers rot)

- [ ] 0.1 Re-run the probe query and confirm `server_active`, `cutover_flag`, and `boot_id` still
      match the plan's measured table.
- [ ] 0.2 Re-run G3.7's exact query at 7d/30d/365d and confirm the row count is still 0.
- [ ] 0.3 Re-measure the flip-FSM emit cadence (`--grep noop-rolled-back`, bucketed per minute).
      Phase 1's 15-minute window depends on it.
- [ ] 0.4 Confirm `inngest-cutover-flip` is still in `vector.toml`'s Source-4 allowlist **and** that
      rows are still arriving. The liveness witness is dead on arrival if either is false — this is
      the exact failure recorded in the 2026-07-08 allowlist learning.
- [ ] 0.5 Re-read `scripts/cutover-inngest.sh` around G3.6/G3.7 and the decider's extraction contract
      before editing.

## Phase 1 — G3.7: distinguish "clear" from "cannot tell"

- [ ] 1.1 Write the failing decision-table tests first, covering the full `(L, H)` cross-product
      including both non-decimal arms.
- [ ] 1.2 **Extract** the liveness reader from `confirm_flip_state` (which already runs
      `betterstack-query.sh --grep inngest-cutover-flip`) into a named helper at column 0 outside the
      `arm)` body, called from both sites, invoked **before** the gate line. Do not author a third
      reader.
- [ ] 1.2a Count rows on the **tag**, never on an enumerated set of `reason` values. The catch-all
      arm emits `noop-unset`, and that is the arm that fires in the very state G3.7 gates (a genuine
      first arm). Enumerating `{noop-rolled-back, noop-done, noop-aborted}` would read H=0 on a
      healthy host and refuse every legitimate arm.
- [ ] 1.2b Filter on `host_name`. `vector.toml` states all hosts multiplex into one Logs source with
      `host_name` as the sole discriminator, so the existing reader's "scoped by the table" comment
      is false — inheriting it would count web-1's rows as the dedicated host's liveness.
- [ ] 1.3 Validate both counts with an explicit `^[0-9]+$` predicate; never reach a comparison via
      bash arithmetic coercion.
- [ ] 1.4 Add the `silent` outcome to `flush_latch_decide`, preserving its signature and column-0
      closing brace (the harness extracts it by `awk` range).
- [ ] 1.5 Keep the single positive-allowlist chokepoint; add no `exit 1` inside any case arm.
- [ ] 1.5a **Extend the existing per-arm-exit assertion to cover `silent)`.** It currently greps
      `(clear|latched|unreadable))` and is blind to a new arm, so without this the no-per-arm-exit
      contract is unenforced for exactly the arm being added.
- [ ] 1.5b Route a non-decimal `H` to `unreadable`, never to `silent` — a non-decimal count is
      produced only by a query failure, and routing it to `silent` prints the host-dark remediation
      for a credential fault.
- [ ] 1.6 Size the liveness window at **15 minutes** — it must tolerate both today's ~35 s cadence and
      any future rate-limit, which the follow-up issue constrains to stay under 15 minutes.
- [ ] 1.7 Rewrite the gate comment to state that `clear` is a **weak** verdict while the retention
      question is unresolved, and that the on-host latch remains the authority.
- [ ] 1.8 Add ordering assertions (G3.6 < liveness reader < G3.7 < first prod write) and the
      call-site-count assertions.
- [ ] 1.9 Confirm the existing arm-body assertion stays green. Note what it actually checks:
      `! grep -qE 'deploy-status' "$ARM_FILE"` — it forbids `deploy-status`, **not**
      `betterstack-query.sh`. Do not write an AC claiming it guards the off-host read path; it does
      not, and such an AC passes vacuously forever.
- [ ] 1.9a Correct the three false claims that currently ship to operators in
      `scripts/cutover-inngest.sh`: the G3.6 `::error::` "let the host re-render its ExecStart"; the
      G3.7 `::error::` "the latch is cleared only by recutting … via the inngest-host-replace
      window"; and the reader comment claiming a `host_name` filter "would add nothing".
- [ ] 1.10 Re-measure and raise the anti-deletion floor by **running** the suite; never copy a
      remembered figure.

## Phase 2 — Probe consumer, as an arm on the existing watchdog

- [ ] 2.1 Write failing tests for the four verdicts: healthy, stopped-by-brake, not-serving,
      probe-unavailable.
- [ ] 2.2 Add the arm to `.github/workflows/scheduled-inngest-health.yml`. Do **not** create a new
      scheduled workflow — `.claude/hooks/new-scheduled-cron-prefer-inngest.sh` would deny it, and
      the existing watchdog already provides the `*/15` cadence, issue dedup, and Sentry check-in.
- [ ] 2.3 Wire the arm into the **no-restart** verdict family (alongside `functions_query_degraded`,
      `pool_pressure`, `probe_unavailable`) with its own issue class. The workflow auto-dispatches
      `restart-inngest-server.yml` on the default failure path; a dedicated-host arm on that path
      would fight the standing brake every 15 minutes with a restart that is LB-routed to the wrong
      host and cannot fix the condition.
- [ ] 2.4 Select on the host field — never a bare payload substring. The probe script is the shared
      renderer for the dedicated host and web-1, and web-1 legitimately reports
      `cutover_flag=unknown`.
- [ ] 2.5 Ensure a missing probe row classifies as `probe-unavailable`, never as healthy.
- [ ] 2.6 Carry `cutover_flag` into the alert message so the cause travels with the alarm.
- [ ] 2.7 Add the three `BETTERSTACK_QUERY_*` secrets to the workflow env, and a Sentry cron monitor
      so the reader's own silence is detectable.

## Phase 4 — Follow-through

- [ ] 4.1 Commit `scripts/followthroughs/inngest-host-not-serving-7674.sh` as mode `100755` (asserted
      against the git index) **before** touching any issue body — the directive gate refuses a
      `script=` that is not an existing executable.
- [ ] 4.2 Assert the exit criterion **positively**: `server_active=active` **and** `http_code=200`.
      No absence arm.
- [ ] 4.3 Use `set -uo pipefail` without `-e`; avoid the banned `${VAR:?}` form; name required env
      literally (the sweeper runs probes under `env -i`).
- [ ] 4.4 Set `earliest=` to reflect that the durable-serving criterion is deferred to the cutover
      window, so the probe returns TRANSIENT rather than commenting daily.
- [ ] 4.5 Remove the stale follow-through directive from **both** #7462 and #7228 — it is dual-hosted
      on two closed issues. Retire; do not re-point. Leave the predecessor file on disk.
- [ ] 4.6 Add the directive for the successor probe to #7674, **and add the `follow-through` label** —
      verified 2026-08-25 that #7674 carries only `priority/p1-high`, `type/chore`,
      `domain/engineering`. The sweeper lists `--label follow-through`, so without the label the
      directive is inert no matter how well-formed the probe is.

## Phase 5 — Corrections

- [ ] 5.1 Runbook: correct the G3.6 remediation — clearing `INNGEST_DIAGNOSTIC_BOOT` cannot re-render
      a running host's ExecStart (the flag is consumed at first boot only).
- [ ] 5.2 Runbook: correct the G3.7 remediation — a host replace re-attaches the volume, it does not
      recut it. Point at the deferred recut target.
- [ ] 5.3 Runbook: add the new failure mode — inactive because a standing `rollback` flag stopped the
      unit — with the one-row discriminator and the `inactive` ≠ `failed` note.
- [ ] 5.4 ADR-100 addendum: record replace-only code delivery to the dedicated host.
- [ ] 5.5 ADR-100 addendum: separate "host dark" from "query finds nothing"; the July attribution
      does not generalise.
- [ ] 5.6 ADR-100: record the G3.7 two-signal design and the re-rejection of the webhook alternative.

## Phase 8 — Split-out issues (file, do not build)

- [ ] 8.1 File the `inngest-volume-recut` issue, carrying the complete Phase 3 design — five guard
      layers including the pre-flight "host is dark" refusal, the naming rationale, and Guards 2
      and 3.
- [ ] 8.2 File the flip-FSM emit rate-limit issue, carrying the measured ~2,450 rows/day burn and the
      constraint that any rate-limit must keep the terminal-arm cadence under 15 minutes and must
      not become transition-only.
- [ ] 8.3 File the `/mnt/data` plaintext encryption-exception issue (expires 2026-11-30).

## Phase 7 — Verification

- [ ] 7.1 `bash apps/web-platform/infra/cutover-inngest-workflow.test.sh`, then again under `LC_ALL=C`.
- [ ] 7.2 `bash apps/web-platform/infra/run-registered-suites.sh` — zero failures, zero unaccounted.
      (No assertion floor exists; the gate is `failed > 0 || UNACCOUNTED > 0`.)
- [ ] 7.3 `python3 scripts/lint-shell-capture-exit.py --baseline scripts/lint-shell-capture-exit.baseline.txt`
- [ ] 7.4 `bash scripts/lint-workflows.sh` (only a hang is failure).
- [ ] 7.5 Assert `cloud-init-inngest.yml` is absent from `git diff --name-only origin/main...HEAD`.
- [ ] 7.6 Run each **new-behavior** acceptance criterion against the pre-fix tree and confirm it
      FAILS there. The regression guards are expected to pass both before and after — do not treat
      their passing as evidence the change worked.
- [ ] 7.7 Surface `decision-challenges.md` (UC-1 webhook substitution, UC-2 design-vs-build,
      UC-3 none-of-three-delivered-in-full) in the PR body.
