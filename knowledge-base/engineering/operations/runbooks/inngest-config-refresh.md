# Runbook: shipping a host-script change through the Inngest config-refresh channel

**TL;DR:** Edit the host-executed `*.sh` → merge to main → run the
[`build-inngest-config-bundle`](../../../../.github/workflows/build-inngest-config-bundle.yml)
workflow (keyless-signs + dual-publishes, emits `IMAGE@DIGEST`) → promote the digest through
Terraform → the host's config-refresh timer pulls, verifies, and applies it in-place. Confirm
off-box with [`scripts/betterstack-query.sh`](../../../../../scripts/betterstack-query.sh). No host
login, no host replace (ADR-133, #6780).

## ⚠️ CHANNEL-LIVE PRECONDITION (HARD-11) — check this FIRST

**The channel is DORMANT until the host-side consumer bake rides the #6178 cutover (PR #6348).**
Before trusting any step below, assert the channel is live off-box:

```bash
doppler run -p soleur -c prd_terraform -- \
  scripts/betterstack-query.sh --since 48h --grep SOLEUR_INFRA_PULL_APPLIED --limit 1
```

- **No `SOLEUR_INFRA_PULL_APPLIED` line returned ⇒ the channel is NOT live.** Promoting a pointer
  now is a no-op the host never reads — you would believe a fix shipped when it silently did not.
  Stop: the host-side timer + verify+apply script + pointer admission arrive with the #6178 cutover.
- **A fresh line returned ⇒ the channel is live**; proceed.

The [`inngest-config-drift`](../../../../.github/workflows/inngest-config-drift.yml) comparator
(dispatched by `cron-inngest-config-drift`) enforces the same gate mechanically: it returns
`PENDING` (green) while no pointer is promoted, and alarms only once a promoted pointer diverges
from the applied digest.

## Ship a host-script change

1. **Edit** the host-executed script under `apps/web-platform/infra/`. If it is a NEW member of the
   refresh-set, add its path to
   [`inngest-config-refresh-set.txt`](../../../../apps/web-platform/infra/inngest-config-refresh-set.txt)
   — and confirm it is already an inngest-host dest in `infra-config-install.sh` `DEST_SPEC` (the
   channel reuses that root helper; it never widens the dest set — HARD-1). Merge to main.

2. **Build + sign + publish.** Trigger the producer workflow at the next monotonic version (it MUST
   exceed the current applied version / baked floor — HARD-9):

   ```bash
   gh workflow run build-inngest-config-bundle.yml -f version=<N+1>
   ```

   The run is held for reviewer approval (the `inngest-config-signing` environment — HARD-7), then
   `cosign sign-blob`s the manifest (VERSION is a signed field — HARD-2) and dual-publishes to GHCR +
   zot. Its job summary prints `IMAGE@DIGEST`.

3. **Promote the pointer (separate principal — HARD-6).** Set the published digest as the value of
   `TF_VAR_inngest_config_digest` in Doppler `soleur/prd_terraform`, then let the
   [`apply-web-platform-infra`](../../../../.github/workflows/apply-web-platform-infra.yml) pipeline
   reconcile `inngest-config-digest.tf`. Terraform is the writer, so no standing CI token can write
   the isolated `soleur-inngest/prd`. The signing run and this promotion are distinct jobs.

4. **Confirm off-box** (no host login):

   ```bash
   doppler run -p soleur -c prd_terraform -- \
     scripts/betterstack-query.sh --since 1h --grep SOLEUR_INFRA_PULL_APPLIED --limit 1
   ```

   A `SOLEUR_INFRA_PULL_APPLIED version=<N+1> sha256=<digest> verify=ok` line within the timer window
   is the applied-and-verified signal. A `SOLEUR_INFRA_PULL_VERIFY_FAIL` line means the host rejected
   the bundle and kept last-known-good (fail-closed — HARD-10); read the reason and re-cut.

## Batching & promotion cadence

The producer version is monotonic, not per-commit: batch several host-script edits into one bundle
and promote once. Promotion (step 3) is the single mutable control input — the cosign signature, the
per-file sha256 manifest, and the monotonic version bound its authority, so a mis-promotion is caught
(rejected, not silently applied). Keep the absence-heartbeat grace window ≥ the timer cadence so a
skipped promotion does not read as a dead timer.

## Signing rotation (keyless — ADR-133 / ADR-087)

Signing is air-gapped keyless cosign: there is no private key to custody. To rotate the trust anchor,
follow the ADR-087 trusted-root re-capture recipe (re-capture `cosign-trusted-root.json` under the
pinned verifier container; the staleness gate `cosign-trusted-root-staleness.test.sh` tracks it), and
update the host verify identity regexp to the config-bundle workflow. There is no key-overlap dance.

**Static-key fallback residual (Option B, ADR-133):** if the host offline `verify-blob` proves
impractical at the cutover Phase-0 probe and the static-key fallback is adopted instead, note that
static keys have no revocation — a leaked signing key requires an emergency `inngest-host-replace`
with a freshly baked public key. That residual does not apply to the chosen keyless path.

## Failure modes → where they surface (all off-box)

| Mode | Detection | Signal |
|---|---|---|
| bad/missing signature | host `cosign verify-blob` non-zero | `SOLEUR_INFRA_PULL_VERIFY_FAIL` |
| version rollback/replay | monotonic gate reject (version read only from signed bytes) | `SOLEUR_INFRA_PULL_VERIFY_FAIL` |
| manifest sha mismatch | per-file sha256 compare fail | `SOLEUR_INFRA_PULL_VERIFY_FAIL` |
| dead timer (silent) | Better Stack absence-heartbeat (no APPLIED marker in window) | absence alarm |
| stale re-baked floor (#6594) | `inngest-config-drift` comparator: applied digest ≠ promoted pointer; the boot-floor marker is distinguishable (`version=floor`) so it cannot mask a stuck delta | drift alarm |
| Better Stack query outage | `inngest-config-drift` executor distinguishes a query failure from a dead timer | `QUERY_UNAVAILABLE` (attributed to the instrument, not the host) |

**Trust residual (fail-open direction).** The drift comparator treats the `SOLEUR_INFRA_PULL_APPLIED`
marker as **observability, not authority for the digest**. The promoted pointer digest is public, so a
compromised host — or anything able to inject a journald/Vector log line — can emit a forged
`SOLEUR_INFRA_PULL_APPLIED … sha256=<current-public-pointer>` and mask a stuck/hostile scheduler as
`OK`. This is inherent to off-box monitoring: a green comparator is **not** cryptographic proof of a
current host. Integrity comes from the host-side signed-bundle `cosign verify-blob` + monotonic-version
gate (which the marker only reports on), never from the marker. All non-adversarial paths fail closed
(empty/unparseable marker → drift alarm; query outage → `QUERY_UNAVAILABLE`).
