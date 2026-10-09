# Runbook — the inngest provision forced-race rehearsal (#9175)

Boots the **production** `cloud-init-inngest.yml` once on a **throwaway** host, on demand, so
the #8539 private-NIC provisioning race is exercised deliberately instead of being
rediscovered at the next `inngest-host-replace`. Phase A births the host **without** its
private NIC (provisioning must fail in the expected arm), Phase B attaches the NIC
(provisioning must recover to `bootstrap-done`), then a control-plane reboot proves the
latch prevents a second provisioning run.

This is **not** the gate on the production host. The rehearsal *proves* the provision unit's
behavior; it changes nothing about prod. The host is destroyed when the run ends.

## Prerequisite — do not dispatch before this is true

The rehearsal boots the pinned `vinngest-v*` bootstrap image. The `DOPPLER_CONFIG`
parameterization (#9175's other half) reaches a host only after the image pipeline mints a
new `vinngest-v*` tag **and** the pin-bump PR lands. A dispatch before then exercises the
pre-parameterization bytes — `DOPPLER_CONFIG` is ignored, the literal `--config prd` runs —
and Phase A fails against a scratch config that exists but is never read.

Check the pin before dispatching:

```bash
grep -oE 'soleur-inngest-bootstrap:v[0-9.]+' \
  apps/web-platform/infra/cloud-init-inngest.yml
git tag --merged origin/main --list 'vinngest-v*' | sort -V | tail -1
```

The two versions must match, and the pinned tag must contain this PR's parameterization
(the post-merge mint).

## Dispatch

```bash
gh workflow run inngest-provision-rehearsal.yml --ref main \
  -f confirm=REHEARSE-INNGEST-PROVISION -f dry_run=true
```

**Pass `--ref main` explicitly** and start with `dry_run=true`: it renders and plans Phase
A, asserts the plan **creates only rehearsal addresses and destroys nothing**
(`scripts/inngest-provision-plan-shape.sh … additive`), and stops. Re-dispatch with
`dry_run=false` to spend a real host (a cpx22 in hel1 — roughly €4-class host-hour plus up
to ~90 minutes of wall clock).

Two human gates and nothing else: the `web-platform-infra-apply` environment approval on
the dispatch, and your review of the evidence artifact. There is no SSH anywhere in this
route; the rehearsal host is never logged into. The reboot leg is the Hetzner API.

## What a real run does

1. **Phase A (`nic_attached=false`)** — `terraform apply` births
   `soleur-inngest-rehearsal-<run_id>` with the deny-all firewall, two scratch volumes, the
   scratch Doppler environment `rehearsal_<runid>` (a *non-inheriting* root config in
   project `soleur-inngest` holding exactly five secrets), and **no private NIC**. The
   provision unit arms, its runcmd NIC wait exhausts (`private_nic_timeout`), and the unit
   retries bounded (`provision-attempt-start` … `provision-nic-ABSENT` …
   `provision-attempt-exit-1`).
2. **The phase-A evidence gate** — the workflow polls
   `scripts/followthroughs/inngest-provision-rehearsal-capture.sh --mode phase-a` until it
   sees `provision-unit-armed`, ≥2 `provision-attempt-start`, and a NIC-absent marker for
   the host — and **zero** `bootstrap-done`. The failure is *observed*, then healed; a
   missing observation halts the run (teardown still runs).
3. **Phase B (`nic_attached=true`)** — a second `terraform apply` whose plan the shape
   guard admits only when the delta is exactly `hcloud_server_network.rehearsal[0]`. The
   `99-soleur-private-fallback.network` file converges 10.0.1.60 via DHCP and the unit's
   next retry runs the full zot-login → pull → Doppler-isolation → bootstrap chain to
   `bootstrap-done` (capture `--mode phase-b`).
4. **Reboot leg** — `POST /v1/servers/<id>/actions/reboot`. Post-reboot evidence (capture
   `--mode post-reboot`) = the `SOLEUR_INNGEST_BS_TOKEN_RESTAGED ok=1` row re-emitted
   (proving the boot ran) **plus zero** provision markers after the reboot boundary — the
   latch held.
5. **Evidence** — `inngest-provision-rehearsal-evidence.env` uploaded as a workflow
   artifact. `terraform destroy` runs in a `needs:`-chained teardown job gated `always()`,
   followed by an in-workflow orphan assertion against the Hetzner API.

## The three artifacts, and what each one rules out

| Artifact | What it establishes |
|---|---|
| **Source-liveness anchor** — any Better Stack row from *any* host in the window | The instrument works. Without it, zero rows from the rehearsal host is ambiguous between "booted dark" and "query/credentials/source broken". A dead anchor reads TRANSIENT, never FAIL. |
| **The stage table for the host** (`provision-unit-armed` → `provision-attempt-start` → `private_nic_*` → `bootstrap-done`, all `iid=`-joined) | Each phase's required markers were observed, in order, for THIS boot — not asserted from `terraform apply` output. |
| **Post-reboot silence** — zero `provision-*`/`bootstrap-*` rows after the reboot boundary | The latch and the timer's `OnBootSec` re-entry refusal held; provisioning did not re-run. |

## Reading the outcome

The capture **script** is three-state; the workflow converts "deadline expired" into job
failure:

- **PASS (0)** — the phase's markers all observed (or, for post-reboot, the anchor present
  and provision markers absent). Evidence appended.
- **FAIL (1)** — a *violation*: `bootstrap-done` while the NIC was absent (phase A), or any
  provision marker after the reboot boundary (post-reboot). These are the failure classes
  the route exists to find. The run halts; teardown still runs.
- **TRANSIENT (2)** — the instrument is dead, or a required marker hasn't arrived yet. The
  workflow keeps polling inside its deadline.
- **Step timeout** — the poll deadline expired: the expected rows never arrived. That is a
  rehearsal FAIL in substance (the workflow cannot distinguish "slow" from "never"); read
  the Better Stack rows for `soleur-inngest-rehearsal-<run_id>` before re-dispatching.

## After a PASS

1. Download the `inngest-provision-rehearsal-evidence-<run_id>` artifact.
2. Attach `inngest-provision-rehearsal-evidence.env` to **#9175** with the run URL and the
   verdict lines (`REHEARSAL_PHASE_A_OBSERVED`, `REHEARSAL_PHASE_B_RECOVERY`,
   `REHEARSAL_POST_REBOOT_LATCH` all `=PASS`).
3. Close #9175 — the issue stays open until this file exists on a real run, per ADR-084's
   single-shot-closure discipline (the PR that shipped this harness says `Ref #9175`,
   never `Closes #9175`).

## If teardown reports orphans

The `terraform destroy` in the teardown job acts only on state; a half-run can strand
objects. The teardown job asserts none remain and the `inngest-rehearsal-orphan-sweep` job
in `scheduled-terraform-drift.yml` sweeps the same label twice daily
(`app=soleur-inngest-provision-rehearsal`, plus `rehearsal_*` environments in
`soleur-inngest`). To recover: re-dispatch with `teardown_only=true`, or reclaim by API —
the filed issue prints the exact calls.

## Failure table

| Symptom in the run | Meaning | First read |
|---|---|---|
| Phase-A plan refused by plan-shape | A non-rehearsal or non-additive change would be applied | `::error::plan-shape` line names the address |
| Phase-B plan refused | The delta is not exactly the NIC attachment — the evidence claim would be false | same |
| `provision-env-MISSING` / `provision-attempt-exit-*` rows in phase A | The expected failure arrived through the wrong arm | Better Stack rows for the host; check `why=` |
| Phase-B times out after the attach | The NIC converged but zot/isolation/bootstrap failed | capture output's last `WAIT:` lines |
| Post-reboot TRANSIENT forever | The restage anchor never re-emitted — the boot ran or it did not; the capture cannot tell | Hetzner console log for the host |
| Orphan assertion fails in teardown | Objects leaked past `terraform destroy` | the printed `kind: name` list |
