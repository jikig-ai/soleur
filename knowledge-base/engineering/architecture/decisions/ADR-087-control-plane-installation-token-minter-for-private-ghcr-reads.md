---
adr: ADR-087
title: "Control-plane installation-token minter for private-GHCR reads (supersedes ADR-086 D1)"
status: active
date: 2026-07-05
supersedes: "ADR-086 D1 (credential-provisioning choice only; ADR-086 Design B′ verifier topology is untouched)"
---

# ADR-087: Control-plane installation-token minter for private-GHCR reads

## Context

#6005 makes the running-host cosign image-verify passable against the now-PRIVATE
`soleur-web-platform` + `soleur-inngest-bootstrap` GHCR packages. The host needs a
`read:packages` credential to (a) `docker pull` and (b) let the cosign container fetch the
OCI-attached `.sig` (ADR-086 Design B′). **ADR-086 Design B′ — the `--network host`
ephemeral verifier topology — is settled and untouched here.** This ADR concerns ONLY how
that credential is PROVISIONED and minted.

**ADR-086 D1** chose a scoped, read-only, machine-account **fine-grained PAT**, published to
Doppler `soleur/prd` via `ghcr-read-credential.tf` and consumed by the host via `docker
login`. security-sentinel affirmed the PAT as security-superior to a GitHub-App-installation-
token path because minting an App installation token on the host drags the org-wide-**WRITE**
App private key (already in Doppler `prd`, `github-app.tf:55`; manifest grants
`administration/contents/secrets/actions: write`, `github-app-manifest.json:18-30`) into host
memory — a ~2-order-of-magnitude larger blast radius than a single-package read token.

**The constraint that inverts D1:** Soleur is becoming a **multi-tenant WEB product
(Concierge) for non-technical users**. GitHub exposes **no API to create a PAT** (fine-grained
or classic — browser + login + 2FA only, deliberately). So PAT provisioning is fundamentally
un-automatable AND un-delegable → a hard blocker for zero-touch tenant onboarding. D1
optimized for a single operator's blast radius; that trade-off inverts when provisioning must
be zero-touch for every future tenant.

Confirmed against the worktree: both consumption points read the SAME two Doppler secrets and
`docker login` — running host (`ci-deploy.sh:561-563`) and cold-boot
(`soleur-host-bootstrap.sh:181-184`). The credential plumbing is therefore
**credential-source-agnostic**: only *who writes the value* changes, not the consumers.

## Considered Options

- **A — on-host App-installation-token mint.** Host mints a `packages:read`-scoped token from
  the Doppler-stored App key (RS256 JWT → `POST /app/installations/{id}/access_tokens`) before
  `docker login`. Token at rest = read-only, 1h. Cost: the org-wide-WRITE App key lands in
  tenant-host memory at every deploy, and — decisively — a **cold-boot host cannot mint without
  the App key**, forcing that key onto every fresh tenant host.
- **B — control-plane installation-token minter (CHOSEN).** A platform-owned Inngest function
  mints the scoped 1h `packages:read` token and writes it to Doppler `soleur/prd`; hosts read
  it unchanged. App key stays on the control plane.
- **C — revert to public.** Delete the whole credential subsystem; re-expose the built Next.js
  artifact + baked host-bootstrap scripts on public GHCR. Operator/CPO already confirmed
  keep-private (ADR-086 Context).

## Decision

**Strategy B — a control-plane installation-token minter — shipped as a STAGED HYBRID: the
ADR-086 D1 PAT is the interim single-operator bootstrap that #6005 (PR #6011) ships now; the
minter replaces it in a distinct follow-up, gated to land BEFORE any tenant host pulls a
private package.**

**Minting mechanism.** A platform-owned Inngest function RS256-signs a JWT with the
Doppler-stored App key → `POST /app/installations/{id}/access_tokens` with body
`{"permissions":{"packages":"read"}}` → a 1h, `packages:read`-only installation token. It
writes the token to Doppler `soleur/prd` as `GHCR_READ_TOKEN` and sets `GHCR_READ_USER` to the
installation-token login convention (`x-access-token`). **No consumer changes** — `ci-deploy.sh`
and `soleur-host-bootstrap.sh` keep reading those two keys; only who writes the value + the
username value change. The `doppler_secret` resources stay declared-existence with
`ignore_changes = [value]` (the minter owns value churn; terraform does not clobber it).

**Prerequisite:** add `packages: read` to the App manifest (absent today) → one org-owner
re-consent, NOT per-user.

**TTL / refresh model (1h hard TTL):** a scheduled floor **every ~20 min (≤ TTL/3)** so Doppler
always holds a valid token and the model survives one missed tick (≤40 min old vs 60 min TTL),
PLUS an **event-driven mint on a provision/deploy event** for maximal freshness at the moment a
host is provisioned or a deploy fires.

**Cold-boot handling (the decisive constraint):** the fresh host reads `GHCR_READ_TOKEN` from
Doppler `prd` at boot — exactly what `soleur-host-bootstrap.sh:181-184` already does. Because
the scheduled minter keeps Doppler continuously holding a valid <TTL token, the fresh host
always finds a live credential with **zero new boot code**, and the App key **never touches the
fresh host**. The boot path depends only on Doppler (already read), not on the minter endpoint
being reachable at boot. This is why B beats A: A *forces* the org-wide-WRITE App key onto every
fresh host.

**Control-plane placement:** **not required on the single-host bootstrap** (web-1 is
simultaneously control plane and only workload; the App key is *already* co-resident in web-1's
app-container Doppler env powering the existing App-installation webhook flow, so running the
minter there adds zero marginal blast radius). It becomes a **HARD GATE before the first real
tenant host exists** (#5274 cutover and beyond): the minter MUST then run on a control-plane
surface tenant hosts cannot read the App key from, distributing only the scoped 1h read token.
Record this as a gate, not a nicety.

## Consequences

- #6011 ships now (WARN-only verify), unblocked, with the PAT as the interim bootstrap. The
  migration to the minter is a localized change to credential *acquisition*, not a re-plumb.
- **#6031** tracks "replace machine-account read PAT with control-plane App-installation-token
  minter", sequenced with #5274 and gated to land before any tenant host pulls a private
  package. (#6023 remains the separate WARN→ENFORCE flip.)
- The interim PAT still requires a one-time operator browser mint + Doppler `prd_terraform`
  write before #6011 merges (the un-automatable step this ADR retires for the multi-tenant
  future).

## Cost Impacts

None new. The Inngest minter reuses the existing App key + Inngest runtime + Doppler. No paid
tier. The scheduled mint is ~72 API calls/day (every 20 min) — negligible against GitHub App
rate limits.

## NFR Impacts

- **NFR-014 (secrets/credential handling):** improved — the standing credential becomes a 1h
  read-only token instead of a ≤1yr PAT, and (post-placement-separation) the App key leaves
  tenant hosts entirely.
- Removes the silent-expiry SPOF of a ≤1yr PAT (the proactive-expiry alarm tracked in #6023
  becomes moot once the minter lands — a 1h token that fails to refresh pages via the existing
  pull-failure event within one deploy).

## Principle Alignment

- Reinforces **AP-007 (exhaust automation before manual steps)** — the minter makes credential
  provisioning zero-touch, retiring the un-automatable PAT mint for tenants.
- Refines **AP-016** (the `hr-github-app-auth-not-pat` exception): the PAT exception is now
  explicitly INTERIM/single-operator; the App-installation-token path is the multi-tenant
  target, aligning back toward `hr-github-app-auth-not-pat` for the standing credential.
- Cross-references ADR-086 (verifier topology — unchanged) and ADR-082 (fresh-web-2 boot).
