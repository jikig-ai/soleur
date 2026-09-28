# Tasks — #8562 inngest bootstrap pull → latched, retrying provision unit (delivered dark)

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

Plan: `knowledge-base/project/plans/2026-09-28-fix-inngest-bootstrap-pull-retrying-unit-plan.md`

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
  - [ ] 1.2.1 Classify `runcmd` items `:686`–`:1823` as stays or moves.
  - [ ] 1.2.2 Build the cross-item state census table: every variable, env var, `/run` file and
    shell option, with its old and new source. Confirm nothing deletes `/etc/default/inngest-doppler`
    or `/etc/default/soleur-zot-read`.
  - [ ] 1.2.3 Grep every consumer of the moved side effects and stage names, and confirm their
    meaning is unchanged under retry.
- [ ] 1.3 Derive `TimeoutStartSec` from a read-only Better Stack query (plan Phase 1.4). Fall back
  to 30 min, and record which applied.

## 2. Guards first (RED)

- [ ] 2.1 Create `apps/web-platform/infra/cloud-init-inngest-provision-unit.test.sh`. It renders
  through Terraform's own pipeline and asserts ≤ 32,768 B plus the `#cloud-config` header.
- [ ] 2.2 Encode the static rows of Guards 1, 5 and 6, and the static detectors of Guards 2, 3
  and 4. Confirm they go RED on current `main`.
- [ ] 2.3 Build the runtime harness.
  - [ ] 2.3.1 Stubs: `docker`, `doppler`, `timeout`, `mountpoint`, phone-home, `soleur-boot-emit`,
    and a fake `inngest-bootstrap.sh`.
  - [ ] 2.3.2 Tier A (`sh -u`, `env -i` plus fixture keys): T1–T5, T7, T8, T13.
  - [ ] 2.3.3 Tier B (systemd 255 as PID 1, rendered unit and timer, `sh -u` drop-in): T6, T9–T12.
    Named skips only.
- [ ] 2.4 Add `systemd-analyze verify` over the extracted `.service` and `.timer`.

## 3. Core implementation (`cloud-init-inngest.yml`)

- [ ] 3.1 Add `write_files` entries for `/usr/local/bin/soleur-inngest-provision` (0755), the
  `.service` (0644) and the `.timer` (0644).
- [ ] 3.2 Move the zot login, the isolation check and the pull → extract → bootstrap → health block
  into the script. Carry the load-bearing comments with them, and keep the `%%{` and `$${` escapes.
- [ ] 3.3 Apply the script deltas:
  - one combined EXIT trap at the top, with `set +e` in its body;
  - `trap 'exit 143' TERM INT`;
  - delete the moved `trap cleanup EXIT` and `trap - EXIT` lines;
  - an attempt counter in `StateDirectory`;
  - a `docker rm -f` pre-clean;
  - an `attempt=N` field on the fatal emits;
  - a `mountpoint -q /mnt/data` precondition;
  - an empty latch after `boot_rc -eq 0`;
  - a final `exit 0`;
  - the literal `DOPPLER_PROJECT=soleur-inngest` stays in the bootstrap `env` list.
- [ ] 3.4 Replace the moved `runcmd` items with `daemon-reload`, `enable` (timer, no `--now`),
  `start --no-block` (service) and the `provision-unit-armed` phone-home. The NIC wait stays where
  it is.
- [ ] 3.5 Fix template prose the move falsifies ("ends the boot", "whole runcmd",
  "once-per-instance").
- [ ] 3.6 Check the bump-bot invariant: exactly 2 pinned refs remain.

## 4. Existing suites (re-point, never weaken)

- [ ] 4.1 `cloud-init-inngest-zot-pull-mutation.test.sh`: re-point NIC-G1 and G4. Record
  before/after row counts.
- [ ] 4.2 `cloud-init-inngest-bootstrap.test.sh`: whitespace anchors only.
- [ ] 4.3 `inngest-host.test.sh` §9/§9b: change the source location only.
- [ ] 4.4 Run the remaining suites and fix anchors only where they go red: `inngest-redis-luks`,
  `inngest-boot-emitter`, `inngest-nic-wait`, `inngest-bootstrap-mirror-only`, `journald-config`,
  and the loopback suite.
- [ ] 4.5 Run `inngest-userdata-budget.sh` and record the byte count.
- [ ] 4.6 Run `mint-inngest-bootstrap-tag.sh --dry-run` and record `noop`.

## 5. Architecture record, runbooks, follow-through

- [ ] 5.1 Write the ADR-256 draft (status `adopting`; re-verify the ordinal at ship).
- [ ] 5.2 Add dated notes to ADR-115 and ADR-096.
- [ ] 5.3 Update the `model.c4` `inngest -> sentry` prose, regenerate `model.likec4.json`, and run
  the C4 syntax, render and count-parity tests.
- [ ] 5.4 Add a "Provision unit (#8562)" section to `inngest-server.md`. It has no SSH, latch-delete
  or `systemctl` step, and says to run `op=resume` after `bootstrap-done`. Sweep the inngest half of
  `zot-registry-revert.md`.
- [ ] 5.5 Write `scripts/followthroughs/inngest-provision-unit-8562.sh`, printing
  `verdict=PASS|FAIL|TRANSIENT`, and fixture-test it like the 8539 twin.

## 6. Ship

- [ ] 6.1 PR body:
  - `Ref #8562`, not `Closes`;
  - the merge-consequence verdict;
  - the pending-delta side effect;
  - the `web-v*` release disclosure;
  - the census table;
  - evidence of a green Tier B run;
  - `decision-challenges.md` rendered in.
- [ ] 6.2 The squash commit body carries a `[skip-web-platform-apply]` line. After merge, verify
  the `apply` job reads `skipped`, the mint made no tag, and no registry dispatch ran.
- [ ] 6.3 Add the follow-through directive and label to #8562, file the forced-race rehearsal
  issue, and add the SOLEUR-DEBT and Vector note to #6780.
