---
title: The Inngest send path gets TLS from a host-local stunnel terminator, a Terraform-minted pinned certificate in Doppler, and a Doppler-flagged data-driven flip
status: adopting
date: 2026-10-18
amends: none
supersedes: none
issue: 10136
related: [10136, 10205, 10382, 10405, 10479, 9139]
related_adrs: [ADR-100, ADR-140, ADR-118, ADR-241]
brand_survival_threshold: single-user incident
---

# ADR-292: The Inngest send path gets TLS from a host-local stunnel terminator, a Terraform-minted pinned certificate in Doppler, and a Doppler-flagged data-driven flip

## Status

**Adopting — 2026-10-18 (#10136).** The decision is true of the **template and the pipeline** at merge, not of production. Merging is inert for running traffic: the resolver's default output is still `http://10.0.1.40:8288`, the new Terraform resources are unreferenced by any running process, and the Inngest host is not replaced by the merge apply (`hcloud_server.inngest` is not in the per-merge `-target` list). The decision becomes true in production through three owner-gated acts, in this order: the single `inngest-host-replace` dispatch (due 2026-11-05), the flag write through `inngest-link-flip.yml` behind a canary, and a 48 hour soak.

The status flips to `accepted` in the later ledger-and-legal-wording PR, on two pieces of evidence: the handshake evidence (a verified request succeeds, the same request without the pinned CA fails with a certificate-verification error) and `scripts/followthroughs/inngest-tls-soak-10136.sh` exiting 0 (a gap-free `tls-health` series for 48 hours on one boot, the `legacy_8288` packet delta exactly zero, and the `tls_8443` delta at least 90 percent of the expected probe cadence). Until then no published document and no ledger value claims TLS on this link.

This ADR covers **leg 1 only** of the three legs the legal ruling names (the app-to-Inngest send path on `:8288`). Leg 2 (the Inngest server polling the app's `sdk_url` over plain HTTP) is a dated, tracked disposition to 2026-12-10. Leg 3 (step calls through Cloudflare, with the Cloudflare-to-origin hop plain while the zone is `flexible`) is blocked on #10479. Neither is solved here, and #10136 does not close with this PR.

## Context

The web-platform app talks to the dedicated Inngest host (`10.0.1.40`, ADR-100) over plain HTTP on the Hetzner private network. ADR-100's 2026-09-15 addendum recorded that as a conscious acceptance: "transport confidentiality on this link is accepted, not provided" (encryption-posture ledger row, exception tracked on #6897 and then #10136). That hop carries `INNGEST_EVENT_KEY` (in the `/e/<key>` path), the hashed signing key as a Bearer on run-list reads, and event payloads: user prompts and agent output. Any peer on `10.0.1.0/24` can read it.

The CTO and CLO rulings of 2026-10-18 on #10136 require TLS with certificate verification on this hop, live by 2026-11-12 (fallback 2026-11-19, CLO hard stop 2026-12-10). The owner go is recorded: build the PR, one Inngest host replace by 2026-11-05, and `INNGEST_SIGNING_KEY` rotation. ADR-140 makes encryption posture a design-time default enforced by a resolvable-evidence ledger, so a fix that cannot be evidenced at runtime does not count as one.

Constraints that shaped the decision, each verified against the code and not assumed:

- **Inngest v1.45.1 has no TLS flag.** `cmd/start/cmd.go` at that tag contains no `tls`, `ssl` or `cert` strings; the listener is plain HTTP and binds `--host 0.0.0.0`. A terminator has to sit in front of it.
- **The host has no inbound path and its code is replace-only** (ADR-100, addendum 2026-08-25). Every change to the template reaches the host only through a replace, which makes the scheduler unavailable for a bounded window and, while `INNGEST_CUTOVER_FLIP=done`, needs a human-approved `cutover-inngest.yml -f op=resume` afterwards.
- **`user_data` is nearly full.** Measured 2026-10-18: 30,916 B stored against the 32,768 B Hetzner cap (headroom 1,852 B), and the repo test budget leaves 1,384 B. Hetzner rejects an oversize `user_data` at replace time, which strands the host (2026-09-08).
- **The merge queue forbids sync pushes**, so a second PR that flips a URL constant cannot follow the first without breaking the "one PR" requirement.
- **`tls_self_signed_cert` computes its validity window at apply time**, so a committed PEM cannot exist before the first apply, and a committed generator would pass the private key through an agent session.
- **Container egress on the web hosts is default-drop**; only `10.0.1.40:8288` is allowed today, so `:8443` would be silently dropped without a new accept.

## Considered Options

- **Option A: `stunnel4` terminator on the Inngest host, cert minted by Terraform and delivered through Doppler, CA as a host file mounted into the containers, URL chosen per deploy by a Doppler flag (chosen).** Smallest config, one apt package, no per-connection fork, and the lowest `user_data` cost. Flip and rollback need a Doppler write and a redeploy, never a code merge.
- **Option B: nginx stream, socat or caddy as the terminator.** Larger configuration or package surface for the same function; the byte budget favours stunnel. Rejected (CTO D1).
- **Option C: native TLS in Inngest.** Does not exist at v1.45.1. Rejected on the facts.
- **Option D: bake the CA into the app image.** Rollback would need an image rebuild, and the host-side probes need the file on disk anyway. Rejected.
- **Option E: a committed public certificate (the `proxy-tls.tf` precedent) or a committed generator script.** The certificate's validity is computed at apply, so a committed copy cannot exist before the first apply; a generator would pass the private key through an agent session. Rejected (CTO D2).
- **Option F: a code-line URL flip in a second PR.** Violates "one PR" under a no-sync-push merge queue. Rejected.
- **Option G: bind Inngest to `127.0.0.1` now.** Needs a bootstrap-image rebuild and a second replace. Deferred to the next unrelated replace, tracked.
- **Option H: a Terraform-managed flag versus a hand-run Doppler write.** The flag is a Terraform-managed secret (`doppler_secret.inngest_link_tls`, count-gated off, outside the per-merge `-target` list), changed only by a Tier-B `apply_target` job. No existing narrow Doppler write credential for `soleur/prd` exists, so a hand-run write would have needed a new token (CTO G1).

## Decision

Adopt Option A, with these properties:

1. **Terminator.** `stunnel4` in its own unit `soleur-inngest-tls.service`, accepting `10.0.1.40:8443` and connecting to `127.0.0.1:8288`, TLS 1.2 or higher. The unit is **not a dependency of `inngest-server`** and the scheduler never waits on it. The key and certificate are fetched at start from Doppler project `soleur-inngest`/`prd` into a tmpfs `RuntimeDirectory`; the unit carries no `EnvironmentFile=`, so the Doppler token never reaches the network-facing process.
2. **One certificate resource, three Doppler copies.** A Terraform `tls_private_key` and `tls_self_signed_cert` (ECDSA P-256, 10 years, `CA:FALSE`, SAN `IP:10.0.1.40` only, `prevent_destroy`) feed `INNGEST_TLS_KEY` and `INNGEST_TLS_CERT` in `soleur-inngest/prd` and `INNGEST_TLS_CA` (base64 of the certificate) in `soleur/prd`. Drift between the copies is structurally impossible; runtime verification (a handshake with `--cacert`, and the host's `tls-health` row carrying the served and Terraform certificate fingerprints) replaces a committed-copy check. No template variable of `inngest-host.tf` may reference these resources, so a certificate change can never force-replace the host.
3. **CA as a host file.** `ci-deploy.sh` validates `INNGEST_TLS_CA` (at most 4 KiB, no private-key block, one or two certificate blocks, `CA:FALSE`, SAN exactly `IP:10.0.1.40`, server-auth only, not expired) and writes it atomically to `/etc/soleur/inngest-ca.pem` before every `docker run`. All three run sites mount it read-only and set `NODE_EXTRA_CA_CERTS`; `NODE_TLS_REJECT_UNAUTHORIZED` is pinned absent everywhere. The certificate becomes a trust anchor for all outbound TLS in the Node process, which is accepted because it is a non-CA, single-IP leaf that OpenSSL will not let issue anything.
4. **One chokepoint for the scheme.** `resolve_inngest_link` in `ci-deploy.sh` is the only place the Inngest base URL is chosen. The flag `INNGEST_LINK_TLS` is read from the `resolve_env_file` snapshot with the allowlist `^(1|pending:[0-9]{1,10})$` and a scope guard (`DOPPLER_PROJECT==soleur`, `DOPPLER_CONFIG==prd`). Absent resolves to `http://10.0.1.40:8288`; `1` resolves to `https://10.0.1.40:8443` and **fails closed**: with the flag on, a failed self-gate, an unreadable flag or an empty or invalid CA fails the deploy and the old container keeps serving, never a downgrade to http. `pending:<epoch>` is honoured only inside a 30-minute lease and lapses to http by itself. The tuple gate (`lib/docker-run-tuple.py`) accepts exactly the resolver expansion for `INNGEST_BASE_URL`.
5. **Flip and rollback are data, not code.** `inngest-link-flip.yml` (`action=flip|off`) applies `pending:<epoch>`, dispatches the canary-then-prod release, verifies a five-check canary layer (an https URL in `docker inspect`, an in-container fetch of the handed URL, a real in-container `inngest.send` of a synthetic event no function listens on, a CA-withheld negative control, a non-empty registry over https) and only then applies `1`. The 30-minute lease is the real rollback control; the failure/cancel off step is best-effort.
6. **The legacy listener stays, counted.** `:8288` stays open for the soak. Two named nftables counters in `table inet soleur_inngest` (`legacy_8288`, a verdict-less counting rule before the unchanged accept; and `tls_8443`, the positive control) are read with `nft list counter` and shipped every 5 minutes as the `tls-health` stage through the allowlisted phone-home path. The `8288/8289` accept and drop lines stay byte-identical. Physically closing `:8288` rides the next unrelated host replace (tracked).
7. **Soak.** `scripts/followthroughs/inngest-tls-soak-10136.sh` is the single chokepoint that decides pass or fail over every row of the window; its anchor (T and the baseline row) is read from trusted-author comments, not from the script.

## Consequences

**Easier.** Confidentiality and authentication of the send path become measurable: the handshake evidence and the soak counters are queryable through `scripts/betterstack-query.sh` without SSH. Flip and rollback are one dispatch each and need no merge. The same mechanism (a pinned certificate delivered as a host file) is reusable for the `sdk_url` leg once the web hosts have a listener.

**Harder or accepted.**

- While the flag is on, **a broken gate blocks ordinary releases** (the resolver fails the deploy rather than downgrade). Rollback is `inngest-link-flip.yml` with `action=off` plus a redeploy. The runbook says so.
- **The TLS key is in the server's process environment.** `inngest-server`, `vector` and the heartbeat run under `doppler run --config` without `--only-secrets`, so `INNGEST_TLS_KEY` reaches their environments. The marginal exposure is small because a process that can read that environment already holds the signing and event keys. Follow-up: `--only-secrets` or a split config at the next image bake (CTO F2).
- **The certificate has no rotation cron.** Ten years, alert under 90 days. A re-mint forces a redeploy of every web host (the CA file) and a host replace (the key and certificate fetch); the CA file may hold two certificates to make the overlap non-disruptive.
- **The replace is a bounded disruption of the sole scheduler** and needs the human-approved `op=resume` while the cutover flag is `done`. A failed replace waits for a fresh owner go.
- **Events sent during the window can be lost or fail.** Several send paths are pre-existing weak points that this work makes more reachable (the Stripe `invoice.payment_failed` route swallows a send failure with its dedup row already claimed; the dashboard send archives the draft on a failed enqueue; the reminder arm returns 502 on a timeout). They are tracked as separate follow-ups and one mapping is folded into this PR (timeouts and TLS causes map to the retryable 503 in `schedule-reminder`).
- **A sniffed `INNGEST_EVENT_KEY` stays valid after TLS.** TLS does not invalidate it; its rotation is a separate owner decision (tracked, due 2026-11-12).
- **Residual plaintext remains** on leg 2 until the dated step and on leg 3 until #10479.

## Cost Impacts

None. `stunnel4` is an apt package; the certificate, the three Doppler secrets and the flag add no paid service or tier change.

## NFR Impacts

Targets NFR-026 (Encryption In-Transit) for the Inngest leg. The register status is deliberately **not** changed here; it moves in the later ledger-and-legal-wording PR once the handshake and soak evidence exist. No impact on latency NFRs beyond one local TLS hop inside the private network.

## Principle Alignment

- AP-001 (Terraform-only infrastructure provisioning): Aligned. The certificate, the secrets, the flag and the host template are Terraform or cloud-init; the flip is a Tier-B `apply_target` job, not a hand-run write.
- AP-008 (Doppler for all secrets management): Aligned. Key and certificate travel only through Doppler; none is baked into `user_data` or committed.

## Related decisions

- **ADR-100** (dedicated single-host control plane). Its 2026-09-15 addendum recorded transport confidentiality on this link as "accepted, not provided". An addendum to ADR-100 points here: once the soak passes, this ADR supersedes that acceptance for the `:8288` send path only. ADR-100 stays `adopting` for its own reasons.
- **ADR-140** (encryption posture as a design-time default). The reason no ledger value or published wording changes in this PR: the posture is claimed only after resolvable evidence exists.
- **ADR-118** (a shared cert's SANs are the cluster roster). The precedent for Terraform-minted pinned certificates delivered through Doppler and pinned by the client. This certificate differs deliberately: one fixed SAN (`10.0.1.40`, no roster to track), and it is not count-gated, because ADR-118's gating existed to stop a proxy server from logging a silent fallback on mere presence of the material, and no process here reads it before the host replace.
- **ADR-241** (infra credential tiers). The flip job uses the existing Tier-B write credential under `infra-privileged` and is added to the D8 census; no new token is minted.
