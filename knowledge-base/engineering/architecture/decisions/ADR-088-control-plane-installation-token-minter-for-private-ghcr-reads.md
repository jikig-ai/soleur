---
title: "Control-plane installation-token minter for private-GHCR reads (supersedes ADR-087 D1)"
status: superseded
superseded_by: "#6122 (migrate off GHCR to self-hosted zot + control-plane-minted OIDC bearer)"
date: 2026-07-05
supersedes: "ADR-087 D1 (credential-provisioning choice only; ADR-087 Design B′ verifier topology is untouched)"
---

# ADR-088: Control-plane installation-token minter for private-GHCR reads

> **SUPERSEDED (2026-07-06, #6122).** This ADR's chosen mechanism — a control-plane minter
> issuing **GitHub App installation tokens** for private-GHCR `docker pull` — was proven
> **infeasible**: a GitHub App installation token can `docker login ghcr.io` but `docker pull`
> returns `denied`. This is a **confirmed GitHub platform limitation** (GitHub staff on record,
> [community discussion #171423](https://github.com/orgs/community/discussions/171423)), not a
> misconfiguration — only a user classic PAT (browser-only creation, no mint API) or the Actions
> `GITHUB_TOKEN` pull private GHCR. GHCR therefore cannot deliver a zero-touch machine identity.
> The zero-touch **goal** of this ADR is retained and carried forward by **#6122** (migrate the
> registry off GHCR to self-hosted **zot** on Hetzner/R2, which validates a control-plane-signed
> OIDC bearer natively — the minter/IaC/Doppler wiring here is reused, only the registry substrate
> changes). See `knowledge-base/project/learnings/2026-07-06-ghcr-app-token-cannot-pull-and-oidc-needs-native-identity-source.md`
> and the #6122 brainstorm/spec. The interim machine-account classic PAT stays live until the zot
> pull path is validated end-to-end (do NOT revoke early). ADR-087 (the deploy-time verifier
> topology) is unaffected.
>
> **Factual note (#6400):** the `login-ok / pull-deny` split documented above is the exact
> failure class that a login-outcome-gated deploy recovery cannot catch — a credential that
> `docker login`s but cannot `docker pull` bypasses any recover-on-login-failure gate. The
> **normative** recovery contract (re-fetch + relogin + retry the pull once on a pull auth-denial,
> not only a login failure) is homed in **[ADR-096](./ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md)**
> (which owns the interim GHCR break-glass path); this ADR stays `superseded` and carries only
> the factual "why," not a current-governing MUST.

## Context

#6005 makes the running-host cosign image-verify passable against the now-PRIVATE
`soleur-web-platform` + `soleur-inngest-bootstrap` GHCR packages. The host needs a
`read:packages` credential to (a) `docker pull` and (b) let the cosign container fetch the
OCI-attached `.sig` (ADR-087 Design B′). **ADR-087 Design B′ — the `--network host`
ephemeral verifier topology — is settled and untouched here.** This ADR concerns ONLY how
that credential is PROVISIONED and minted.

**ADR-087 D1** chose a scoped, read-only, machine-account **fine-grained PAT**, published to
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
  keep-private (ADR-087 Context).

## Decision

**Strategy B — a control-plane installation-token minter — shipped as a STAGED HYBRID: the
ADR-087 D1 PAT is the interim single-operator bootstrap that #6005 (PR #6011) ships now; the
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
- Cross-references ADR-087 (verifier topology — unchanged) and ADR-082 (fresh-web-2 boot).

## Amendment — #6031 minter implementation (2026-07-05)

The minter (Strategy B) is **IMPLEMENTED** in #6031 (`cron-ghcr-token-minter.ts`,
`ghcr-minter-doppler-token.tf`, the App-manifest `packages: read` grant, and the
five/six-registry Inngest lockstep), pending the live cutover (org re-consent → first
mint verified → PAT revoked). Status stays `active`; it flips to "minter live" once the
Phase-6 cutover acceptance (a real deploy + fresh-host boot authenticating with the minted
token) passes.

### Phase-0 empirical gate (R1) — PASS

GHCR accepting App **installation** tokens for `docker pull` was the plan-defining risk. It is
proven by the repo's own production CI: `reusable-release.yml` pushes the `soleur-*` images with
the Actions `GITHUB_TOKEN` (itself an App installation token), and `apply-web-platform-infra.yml`
`docker login`s + pulls the **private** `soleur-web-platform` package with the same token
(`packages:read` job scope). The mechanism is valid for this org+packages; residual package↔repo
linkage for the *Soleur* app's own installation is Phase-5/6 provisioning config, not a reversal.

### Doppler write-token injection (CTO ruling, 2026-07-05)

The `prd_ghcr` throwaway config bounds the write token's **at-rest** blast radius (an isolated
leak grants write to one config, never a prd-wide read of `GITHUB_APP_PRIVATE_KEY`). But the
write token is surfaced into the minter runtime as a plain `prd` secret
(`GHCR_MINTER_DOPPLER_TOKEN`), landing in web-1's container via the **existing** single
`--config prd` env-file path — **not** a second `--config prd_ghcr` cloud-init download. A second
host-side download was rejected: it would distribute a control-plane-only WRITE credential onto
every fresh **tenant** host (the exact escalation the #5274 separation exists to prevent) and add
fail-closed risk to the cold-boot critical path for a credential tenant hosts never use. The
runtime isolation of the write token buys nothing today anyway — the org-wide-WRITE App key is
already co-resident in the same `prd` container env.

**CPO sign-off (threshold `single-user incident`, `requires_cpo_signoff`):** `prd` gains a
write credential readable by every `prd` principal (CI, terraform runner, the app
process). **Accepted** because those principals already read the co-resident org-wide-WRITE
`GITHUB_APP_PRIVATE_KEY` (a strictly larger capability), and true control-plane-only injection is
deferred to the #5274 gate below.

### Config-inheritance fallback (post-merge, 2026-07-05) — prd-scoped write token

The dedicated `prd_ghcr` config (which would have bounded the write token's **at-rest** scope to
one config) **could not be created**: `terraform apply` returned `Doppler Error: Your workplace
does not have access to config inheritance` — Doppler branch configs are a paid-tier feature this
workspace's plan lacks. Per the plan's pre-declared **Phase 2.2 / R2 fallback**, the write token is
`prd`-**scoped** (`doppler_service_token.ghcr_minter`, `config = "prd"`, `access = "read/write"`)
and the minter writes `GHCR_READ_TOKEN`/`GHCR_READ_USER` **directly into `prd`** — where the
consumers already read them, so the cross-config reference flip is eliminated entirely (`#6011`'s
`ignore_changes=[value]` keeps terraform from clobbering the runtime churn).

**security-sentinel sign-off:** a `prd`-scoped read/write token can read AND write every `prd`
secret at rest — a strictly larger at-rest surface than the (unavailable) `prd_ghcr`-scoped token.
**Accepted** on the same basis as the CPO sign-off above: per the runtime analysis, the dominant
capability (`GITHUB_APP_PRIVATE_KEY`, org-wide WRITE) is already co-resident in the same `prd`
container env, so the token's wider *at-rest* scope is the only delta, and the #5274
control-plane-separation gate (below) already mandates relocating both credentials off `prd`. The
fallback does not enlarge that gate's scope — the two relocation items are unchanged.

### HARD GATE — control-plane separation before the first tenant host (#5274)

When the first real tenant host is provisioned, the minter MUST run on a control-plane surface
tenant hosts cannot read from, distributing only the scoped 1h read token. That cutover MUST
relocate **BOTH** control-plane-resident credentials off the shared/tenant `prd` env:
1. **`GITHUB_APP_PRIVATE_KEY`** — org-wide WRITE (already a `prd` landmine pre-#6031).
2. **`GHCR_MINTER_DOPPLER_TOKEN`** — the Doppler write token this PR newly co-locates in `prd`.

Recorded here (a committed artifact) rather than as a #5274 issue comment so neither item can be
silently dropped at cutover.

### Manifest permission widening

`packages: read` on the App is a **per-installation standing grant** on the SHARED App: every
consenting installation grants it, so a `GITHUB_APP_PRIVATE_KEY` leak post-multi-tenant reads
every consenting tenant's packages. (The minted *token* remains 1h/single-install/read-only; the
App *permission set* is what widens.) CPO-accepted as the prerequisite for zero-touch onboarding.

### Amendment — baked-token staleness vs. minter TTL (#6090 recurrence, 2026-07-13)

A minted read token is short-lived (1h) and rotated into `GHCR_READ_TOKEN` frequently, but a
fresh Hetzner host **bakes** the value present at `user_data` render time into
`/etc/default/soleur-ghcr-read`. On a warm standby that is created and then deployed-to minutes-
to-hours later (e.g. a `web-2-recreate` followed by a release fan-out), the baked snapshot can go
**stale-but-present** by deploy time. The consuming login paths originally re-fetched from Doppler
**only when the baked value was EMPTY** — never when a present-but-expired token made `docker
login` *fail*. Result (web-2 fsn1 warm standby, 2026-07-13): a non-fatal baked-login failure →
anonymous private pull → registry 401 → Sentry `image pull failed (auth_denied)` → the standby
never served.

Consequence for this decision: consumers of the minted read token MUST treat a baked value as a
cache that can expire, and re-fetch the CURRENT Doppler value + retry `docker login` on a login
**FAILURE**, not only on EMPTY. Implemented (fail-open) in both login sites:
`apps/web-platform/infra/ci-deploy.sh` (`ghcr_prelude_and_login`, the deploy path that actually
failed) and `apps/web-platform/infra/cloud-init.yml` (the seed-pull `ghcr_login` block, the boot-
path variant of the same class). No change to the minter, the token TTL, or the App permission
set — this is a consumer-side staleness-tolerance note only.
