# ADR-155 — Pause the ADR-100 dedicated-Inngest cutover at the pre-repoint operating point

- **Status:** Accepted
- **Date:** 2026-08-02
- **PR:** (this PR)
- **Issue:** #7144 (Resend inbound webhook 500s / dispatch outage)
- **Related:** [ADR-100](./ADR-100-inngest-dedicated-single-host-singleton-control-plane.md) (`status: adopting` —
  the cutover this ADR pauses), [ADR-030](./ADR-030-inngest-as-durable-trigger-layer.md) (the co-located
  operating point being returned to), [ADR-154](./ADR-154-repair-the-credential-channel-not-the-host.md)
  (same root-cause class, one day earlier: repair the credential channel, not the host),
  [ADR-096](./ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md) clause (f) (a mirror
  gate proves the image is readable by the PUSH credential, never that the host can PULL it),
  [ADR-088](./ADR-088-control-plane-installation-token-minter-for-private-ghcr-reads.md) arm-b (refuted for this consumer, below),
  [ADR-055](./ADR-055-resend-inbound-as-third-multi-source-ingress.md) (the release+500 contract that behaved
  correctly throughout)

## Context

On 2026-07-24, cutover step 2.4 (`b02870e1d`, #6348) repointed the web-platform container at the
dedicated Inngest host by hardcoding `-e INNGEST_BASE_URL=http://10.0.1.40:8288` in
`ci-deploy.sh`. On 2026-07-30T15:13:06Z that host was replaced. Its first boot reached
`ghcr-login-FAILED` at 15:13:59Z and `oci-pull-rc-1 "unauthorized"` at 15:14:01Z: the
`GHCR_READ_TOKEN` classic PAT was dead (401 against `api.github.com/user`). The bootstrap image
never pulled, `inngest-bootstrap.sh` never ran, `inngest-server` was never installed, and nothing
has ever bound `:8288` on that host.

Every `inngest.send()` therefore got `ECONNREFUSED 10.0.1.40:8288` for ~3 days
(17,531 fleet-wide connection-refused rows on 2026-08-01 alone), surfacing to a user-visible
surface as HTTP 500 on `/api/webhooks/resend-inbound` and a vendor auto-disable threat from Resend.

Three properties of that window matter more than the credential itself:

1. **The failure was invisible to our own monitoring.** `scheduled-inngest-health.yml` reported
   `success` every ~1–2h throughout, because `inngest-inventory.sh` probed `127.0.0.1:8288` —
   loopback on the *web* host — and so certified the surviving co-located server. The cutover moved
   the app's dependency and left the probe behind.
2. **Every no-SSH repair verb still acts on the web host.** `restart-inngest-server.yml` POSTs the
   deploy webhook, whose handler restarts the *local* `inngest-server.service` and then confirms via
   that same loopback probe. Dispatching it during this incident would have returned green having
   fixed nothing. The dedicated host has no restart verb and no health probe.
3. **The system was split-brain.** The co-located server remained alive and continued executing
   crons *into* the app, while all outbound sends pointed at the dead host. Probe mail kept being
   sent during an outage of the pipeline that probe exists to measure.

So the state on 2026-08-02 is not merely "the new host went down". A PREDECESSOR `soleur-inngest`
host **was** serving — it emitted `inngest-server.service` journald rows until
2026-07-30T15:12:37Z, 29 seconds before the current host was created — so the cutover did not ship
against a host that had never worked. It worked from 2026-07-24 until the 07-30 replacement, and
the replacement could not boot. The defect is therefore not "the target host is unviable"; it is
that the traffic moved to a host whose entire operational control plane never moved with it, so a
routine replacement failing became a silent multi-day outage instead of a paged one.

Note also that ADR-100 has never been `Accepted`; it is `status: adopting`, held there until a
Phase-4 soak verifies zero double-fire. That soak has not completed: the predecessor host served
for ~6 days before being replaced, which is short of the 7-day soak, and the replacement never
booted.

## Decision

**Pause ADR-100 at the pre-repoint operating point.** Revert cutover step 2.4 only — the app
dispatches to the co-located `inngest-server` (`http://host.docker.internal:8288`) — and leave the
dedicated host, its Terraform, its cloud-init, and the rest of ADR-100's target architecture
standing.

This is a pause, not a rollback of an accepted decision: there is no accepted decision to roll back,
and the target architecture is not what failed.

The generalisable finding, which is the actual root-cause class:

> **A cutover is not complete when the traffic moves. It is complete when the traffic, the
> monitoring, and the repair verbs move together.** ADR-100 moved one of the three, and the two that
> stayed behind are precisely what turned a boot failure into a silent three-day outage.

Accordingly the watchdog's probe target is now **derived** from the app's deployed
`INNGEST_BASE_URL` rather than being an independent literal (`inngest-inventory.sh`), with a parity
test mirroring the existing `cron-inngest-cron-watchdog` guard. This is deliberately fixed in the
same PR as the repoint and **is not made redundant by it**: after the repoint the loopback default
happens to point at the right server again, and that coincidence is exactly how the defect hides. A
fault that manifests only when the two sides disagree, and is repaired only when they disagree, is
repaired never.

### Completion criteria (so "paused" cannot drift into "forgotten")

The repoint returns only when **all four** hold:

1. The dedicated host boots and binds `:8288` from a cold `terraform apply` with **no GHCR
   dependency** on the cold-boot path.
2. `scheduled-inngest-health.yml` probes the **dedicated** host and has produced a real RED.
3. A no-SSH restart verb targets the dedicated host.
4. Only then, repoint — gated on 1–3.

### Expiry condition

`var.web_colocate_inngest` now defaults `false`, so a future recreate of web-1 would come up with no
co-located Inngest and silently recreate this outage. Do **not** flip that toggle as a workaround —
its own SOLEUR-DEBT block records that enabling it re-arms an unpinned root-executed OCI pull.
Treat a web-1 recreate as a blocking dependency on the completion criteria above.

## Alternatives Considered

**A — Complete the cutover forward (repair the credential, boot the dedicated host).** Rejected as
the incident fix. The designated credential path is not merely disabled but architecturally
incapable: `cron-ghcr-token-minter.ts` records in its own kill-switch comment that a GitHub App
installation token can `docker login` GHCR yet is denied `docker pull` on private repo-linked
`soleur-*` packages — reproduced live during this incident (token exchange HTTP 200, manifest pull
HTTP 403). The minter also writes to Doppler config `prd`, never `prd_terraform`, so it could not
have supplied `TF_VAR_ghcr_read_token` even had it worked. What remained was a browser+2FA PAT mint
(ADR-087 D1: no PAT-creation API) on the critical path of a vendor auto-disable clock, followed by
another first boot of the same cloud-init path that has already failed once, behind a
maintenance-window host-replace dispatch. Its *goal* survives as the completion criteria above.

**B — Chosen.** See Decision.

**C — Mirror the bootstrap image into the self-hosted zot registry so the host pulls without GHCR
credentials.** Rejected as the incident fix; **adopted as the completion path**, because it deletes
the credential dependency instead of renewing it, and the web host's `cloud-init.yml` already
carries a zot-first-with-GHCR-fallback arm for this exact ref. It cannot be the incident fix for
three independently sufficient reasons: (i) it edits `cloud-init-inngest.yml`, and `inngest-host.tf`
deliberately carries no `ignore_changes = [user_data]`, so that is a host **REPLACE** whose
replacement boots with no hcloud firewall until the next full apply; (ii) the dedicated host's
Doppler token is scoped to the isolated `soleur-inngest` project with no inheritance path to
`soleur/prd`, so it cannot read the zot pull credentials — those must be provisioned into
`soleur-inngest/prd` first; (iii) the bootstrap's zot mirror step is `docker tag` + `docker push`,
`continue-on-error: true`, and unsigned — unlike the web-platform and config-bundle mirrors which
use digest-preserving `crane copy` — so the mirrored manifest digest is not guaranteed to equal the
`@sha256:` that `cloud-init-inngest.yml` pins, nor guaranteed to exist. Making C safe requires
crane-ifying that mirror and making it blocking, first.

**D — Dispatch `restart-inngest-server.yml` as the cheap first remediation** (as the incident plan
originally recommended: "a `gh workflow run` is the fix in seconds"). **Rejected, and struck from
the plan.** It restarts the web host's already-healthy co-located unit, never touches 10.0.1.40, and
then confirms success through the same loopback probe. It would have reported green and closed the
incident with nothing fixed — the monitoring blind spot wearing a different hat.

## Consequences

- Dispatch is restored in one deploy cycle, using the component that is demonstrably serving.
- The `hcloud_server.inngest` replace hazard is not incurred: no Terraform, no `user_data` change.
- The `INNGEST_HOST_FALLBACK` ↔ `ci-deploy.sh` parity invariant is preserved by moving both write
  sites together; it is a parity guard between two sites, not a pin to `10.0.1.40`.
- The dedicated host remains provisioned and dark. Every other `10.0.1.40` reference in the repo
  legitimately describes it and is untouched.
- **ADR-088 arm-b is refuted for this consumer**, not paused: App installation tokens cannot pull
  these packages, so a GHCR read credential cannot be held this way at all. The follow-up is to
  retire GHCR from the dedicated-Inngest cold-boot path (finish ADR-096 for
  `soleur-inngest-bootstrap`), at which point the ADR-088 minter's on-Inngest bootstrap deadlock —
  the minter that would repair the credential needed to boot Inngest runs *on* Inngest — dissolves
  because nothing needs the minter. `GHCR_MINTER_DISABLED` stays `true` meanwhile; flipping it would
  produce a fresh 403 and a new false signal.
- Article 30 TOM (11)'s "pages within ~25.5h worst case" is falsified by this incident (≥26h,
  vendor-detected) and is corrected as part of the incident follow-up. An overstated Art. 32
  technical measure is a compliance exposure under Art. 5(2), not merely an ops gap.
