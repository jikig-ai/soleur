# Tasks — #8562 inngest bootstrap pull → latched, retrying provision unit (delivered dark)

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

Plan (deepened 2026-09-28): `knowledge-base/project/plans/2026-09-28-fix-inngest-bootstrap-pull-retrying-unit-plan.md`

Hard constraints for the whole run:

- No production writes. That means no tag push, no workflow dispatch, no `terraform apply` and no
  host replace.
- Do not touch `inngest-bootstrap.sh`, `vector.toml`, any other `cp` carrier, `inngest.tf`,
  `inngest-host.tf`, `sentry/**`, `variables.tf`, `zot-registry.tf`, `cloud-init-registry.yml` or
  `.github/workflows/*`.

## 1. Setup

- [ ] 1.1 Bump `BASELINE_DECLARED_PROBES` from 34 to 35 in
  `plugins/soleur/test/preflight-discoverability-test.test.ts`, with a PLACEMENT/TRUTH/NO SUBSTITUTE
  comment for this plan. Make this the first commit of the work phase.
- [ ] 1.2 Pre-move inventory (plan Phase 1.1–1.3).
  - [ ] 1.2.1 Classify `runcmd` items as stays or moves.
  - [ ] 1.2.2 Build the cross-item state census table: every variable, env var, `/run` file and
    shell option, with its old and new source. Confirm nothing deletes `/etc/default/inngest-doppler`
    or `/etc/default/soleur-zot-read`.
  - [ ] 1.2.3 Grep every consumer of the moved side effects and stage names, and confirm their
    meaning is unchanged under retry. Any "host done?" reader keys on `bootstrap-done`.
- [ ] 1.3 Derive `TimeoutStartSec` from the steps' built-in bounds, plus a margin for the
  unbounded steps (plan Phase 1.4; expect about 45 min). Record the arithmetic. Cross-check against
  Better Stack history if the credentials are available.

## 2. Guards and harness first (RED)

- [ ] 2.1 Create `apps/web-platform/infra/cloud-init-inngest-provision-unit.test.sh`. It renders
  through Terraform's own pipeline and asserts ≤ 32,768 B plus the `#cloud-config` header.
- [ ] 2.2 Encode the static rows: Guards 1, 5, 6 and 8, plus the static detectors of Guards 2, 3
  and 4.
  - The parsers are section-aware for units.
  - The pull and latch checks normalize alternate spellings.
  - Rows are reported by ID (`G<n>-r<m>`), and only executed rows are counted. Total: 59 rows
    (51 RED, 8 must-PASS).
- [ ] 2.3 Build the runtime harness.
  - [ ] 2.3.1 Stubs: `docker` (normalizing like G4), `doppler`, `timeout`, `sleep`, `systemctl`,
    `sync`, phone-home, `soleur-boot-emit`, `inngest-redact.sh`, and a fake `inngest-bootstrap.sh`.
  - [ ] 2.3.2 Tier A: reuse and extend the G4 fixture-root path-rewrite table, asserting every
    pair matches. Run under `dash -u` with `env -i`, using a fixture built by **executing** the
    rendered `:753` printf. It never skips.
    - Scenarios: C0, T1–T5, T7, T8, T14, T16, T17.
    - Assert exact return codes. rc 2 or 127 is an instrument fault.
  - [ ] 2.3.3 Tier B: systemd 255 as PID 1 in the pinned `ubuntu:24.04` container
    (`--privileged --cgroupns=private --cgroup-parent=docker.slice`, tmpfs `/run`, `/run/lock`
    and `/tmp`). Mask resolved and getty, and poll `is-system-running`.
    - Scenarios T6, T9–T12, T15 in one logged run.
    - Only named skips.
- [ ] 2.4 Add `systemd-analyze verify` over the extracted `.service` and `.timer`.

## 3. Core implementation (`cloud-init-inngest.yml`)

- [ ] 3.1 Add `write_files` entries for `/usr/local/bin/soleur-inngest-provision` (0755), the
  `.service` (0644, no `[Install]`, `StateDirectory=`, `UMask=0022`, derived `TimeoutStartSec`) and
  the `.timer` (0644, `OnBootSec=90s`).
- [ ] 3.2 Move the zot login, the isolation check and the pull → extract → bootstrap → health
  block into the script. Carry the load-bearing comments with them, and keep the `%%{` and `$${`
  escapes.
- [ ] 3.3 Apply the script deltas:
  - the xtrace refusal (exit 78);
  - one combined EXIT trap at the top, with `set +e` in its body;
  - `trap` TERM/INT that kills `$child` and exits 143;
  - delete the moved `trap cleanup EXIT` and `trap - EXIT` lines;
  - run the pull and the bootstrap as `& wait`;
  - bs-token re-stage when the file is empty;
  - a counter that cannot wedge, in `StateDirectory`;
  - `rm -f` of the fixed `/tmp` staging paths;
  - `docker rm -f` pre-clean, then address the container by the ID `docker create` returns;
  - no read or write of `/run/soleur-inngest-doppler.ok`;
  - `attempt=N` and `iid=` fields on the emits;
  - the cutover-FSM quiesce (stop both timers, then wait a bounded time) before the bootstrap;
  - an empty latch plus `sync -f` after `boot_rc -eq 0`;
  - a final `exit 0`;
  - `provision_attempt_failed` to Sentry from the EXIT trap;
  - the literal `DOPPLER_PROJECT=soleur-inngest`;
  - **no** `mountpoint` precondition.
- [ ] 3.4 Replace the moved `runcmd` items with `daemon-reload`, `enable` (timer, no `--now`),
  `start --no-block` (service) and the `provision-unit-armed iid=…` phone-home. The NIC wait stays
  where it is.
- [ ] 3.5 Fix template prose the move falsifies ("ends the boot", "whole runcmd",
  "once-per-instance").
- [ ] 3.6 Check the bump-bot invariant: exactly 2 pinned refs remain.

## 4. Existing suites (re-point, never weaken)

- [ ] 4.1 `cloud-init-inngest-zot-pull-mutation.test.sh`: re-point NIC-G1 and G4. Record
  before/after row counts.
- [ ] 4.2 `cloud-init-inngest-bootstrap.test.sh`:
  - re-point Guard 4's slice from `runcmd` to the `write_files` script, and drop the sentinel
    fixture at `:1903`;
  - fix whitespace anchors only.
- [ ] 4.3 `inngest-host.test.sh` §9/§9b: change the source location only.
- [ ] 4.4 Run the remaining suites and fix anchors only where they go red: `inngest-redis-luks`,
  `inngest-boot-emitter`, `inngest-nic-wait`, `inngest-bootstrap-mirror-only`, `journald-config`,
  and the loopback suite.
- [ ] 4.5 Run `inngest-userdata-budget.sh` and record the byte count.
- [ ] 4.6 Run `mint-inngest-bootstrap-tag.sh --dry-run` and record `noop`.

## 5. Architecture record, runbooks, follow-through

- [ ] 5.1 Write the ADR-256 draft (status `adopting`; re-verify the ordinal at ship).
  - Cite ADR-142.
  - Record the singleton guarantee, the AOF-safety-under-kill argument, the FSM quiesce, and the
    arming residual.
- [ ] 5.2 Add dated notes to ADR-115, ADR-096 and ADR-100.
- [ ] 5.3 Update the `model.c4` `inngest -> sentry` prose, regenerate `model.likec4.json`, and run
  the C4 syntax, render and count-parity tests.
- [ ] 5.4 Add a `## Provision unit (#8562)` section to `inngest-server.md`.
  - Readings are keyed on `iid`.
  - Wait for `bootstrap-done` before replacing, and run `op=resume` after it.
  - A repeating `provision-fsm-busy` means read `inngest-host-state.sh`.
  - List the replace triggers.
  - No SSH, latch-delete or `systemctl` step.
  - Sweep the inngest half of `zot-registry-revert.md`.
- [ ] 5.5 Write `scripts/followthroughs/inngest-provision-unit-8562.sh`, anchored on
  `provision-unit-armed` plus `iid`.
  - It prints `verdict=PASS`, `verdict=FAIL`, `verdict=TRANSIENT reason=not-delivered` or
    `verdict=TRANSIENT reason=probe-fault` on **stdout**.
  - Fixture-test it like the 8539 twin.

## 6. Ship

- [ ] 6.1 PR body:
  - `Ref #8562`, not `Closes`;
  - the merge-consequence verdict, including the `web-v*` release disclosure;
  - the pending-delta side effect;
  - the census table;
  - the `TimeoutStartSec` arithmetic;
  - evidence of a green Tier B run;
  - `decision-challenges.md` rendered in.
- [ ] 6.2 The squash commit body carries a `[skip-web-platform-apply]` line. After merge, verify
  the `apply` job reads `skipped`, the mint made no tag, and no registry dispatch ran.
- [ ] 6.3 Tracking work:
  - add the follow-through directive and label to #8562;
  - file three follow-up issues: the forced-race rehearsal, a Sentry alert for non-pull provision
    failures, and an `op=resume` G-row that requires `bootstrap-done`;
  - add the SOLEUR-DEBT and Vector notes to #6780.
