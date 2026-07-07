---
date: 2026-07-06
topic: registry-oidc-migration
status: brainstorm-complete
lane: cross-domain
brand_survival_threshold: single-user incident
references:
  - "#6073"  # escalation: can App token pull GHCR (this brainstorm's entry point)
  - "#6031"  # the GHCR installation-token minter (superseded approach)
---

# Brainstorm — Migrate container registry off GHCR to a control-plane-mintable substrate (self-hosted zot on Hetzner, R2-backed)

## What We're Building

Move the platform's container images (`soleur-web-platform`, `soleur-inngest-bootstrap`) off
GitHub Container Registry (`ghcr.io`) onto a **self-hosted [zot](https://zotregistry.dev)
registry running in-datacenter on Hetzner, backed by Cloudflare R2 storage**. zot's built-in
OIDC bearer-token workload auth lets a booting Hetzner host pull images with a **short-lived,
control-plane-minted credential** — no user PAT, true zero-touch. The existing Inngest minter
(`cron-ghcr-token-minter.ts`, currently disabled) is re-pointed to mint zot JWTs instead of
GHCR tokens. The cosign keyless-signing chain is preserved unchanged.

## Why This Approach

**The trigger (verified fact, not a hypothesis):** A GitHub App installation token **cannot
`docker pull` private, repo-linked GHCR packages** — `docker login` succeeds but `docker pull`
returns `denied`. This is a **confirmed GitHub platform limitation**, stated on the record by
GitHub staff in community discussion
[#171423](https://github.com/orgs/community/discussions/171423) ("GHCR does not yet accept
GitHub App installation tokens for authentication"). No fix has shipped; last staff response
Aug 2025; still broken per May 2026 user reports. Our own live test (2026-07-05, in
`decision-challenges.md`) reproduced it exactly.

**Consequences that collapsed the original option space (#6073 a/b/c/d):**
- **(b) "find a GHCR config that works"** — does not exist; platform-level, not misconfiguration.
- **(d) "escalate to GitHub support to find the path"** — the path is already publicly answered;
  a ticket only registers interest / asks for a timeline, blocks nothing. **Downgraded to
  optional/informational.**
- **(c) internal packages** — reduces isolation AND doesn't fix App-token auth (GHCR refuses
  App tokens regardless of package visibility). Rejected.
- **(a) machine-account PAT** — works today but GitHub has **no PAT-minting API** (classic or
  fine-grained), so "auto-rotate" needs browser scripting → can never be zero-touch. This is
  precisely why migration is the correct answer, not a nice-to-have.

**Why zot-on-Hetzner-R2 over the alternatives:**
- **The OIDC reframe:** a booting Hetzner VM has *no native workload-identity issuer* (unlike
  AWS IMDS / GCP metadata / K8s kubelet). So "OIDC federation" registries (ECR/GAR/CF-OIDC) would
  force us to *build our own IdP* in the control plane. Since we route through the control plane
  anyway, OIDC's "no stored secret" benefit collapses into the pattern we already run:
  control-plane mints a short-lived credential into Doppler, host reads it at cloud-init. The
  real decision is therefore *which registry accepts a control-plane-minted bearer token* — and
  zot validates one **natively** (`config-bearer-oidc-workload.json`), with **no bespoke auth
  code** (the fatal risk of the R2+Worker option, which requires hand-implementing the Docker
  registry token protocol on the supply-chain path).
- **Restricted-egress firewall (ADR-052 / #5046):** hosts have no live Fulcio/Rekor egress. An
  **in-datacenter** registry on the same Hetzner private network is trivially reachable, needs no
  new public allowlist entry, has the fastest pulls, and **zero egress cost** (R2). A public
  managed registry (Quay) needs a new egress allowlist + pays egress — against the firewall posture.
- **Tightest ADR-088 reuse:** the minter, IaC pattern, and Doppler wiring were all sound; only
  GHCR's refusal broke them. zot is the substrate that resurrects the original design verbatim.

## Key Decisions

| # | Decision | Rationale |
|---|----------|-----------|
| 1 | Migrate OFF GHCR (do not wait for GitHub) | Limitation is platform-level, confirmed public, no ETA — out of our control |
| 2 | **Self-hosted zot, R2-backed, in-datacenter on Hetzner** | Native OIDC bearer auth (no bespoke code) + firewall/egress fit + minter reuse |
| 3 | Reuse the existing Inngest minter — swap token endpoint to zot | `cron-ghcr-token-minter.ts` re-pointed; architecture unchanged |
| 4 | Preserve cosign chain unchanged | Signing identity = GitHub Actions OIDC, registry-agnostic; `.sig` is an OCI artifact zot stores |
| 5 | **Do NOT escalate to GitHub support as a blocker** | Answer is already public; at most an optional informational ticket |
| 6 | Keep the interim classic PAT live until zot pull is validated end-to-end | No credential gap; do not revoke early (repeat of the 2026-07-05 self-inflicted incident) |
| 7 | Rotate the exposed PAT (per incident note) | It was overwritten/exposed during the 2026-07-05 minter misfire |

## Open Questions

- **zot HA / boot-time SPOF:** a single zot instance gating host boot is the top risk. Resolve
  at plan time: run 2 instances behind the internal LB, and/or a pull-through cache, and/or keep
  the interim GHCR PAT as a documented break-glass fallback until zot HA is proven.
- **R2 as zot storage backend:** confirm zot's S3-compatible driver works against R2 (endpoint,
  auth, multipart) — plan-time spike.
- **zot token-issuer trust model:** exact JWT claims/audience zot validates, and how the minter
  signs them (control-plane keypair → zot's configured JWKS/HMAC). Security-review at plan time.
- **cosign `.sig` fetch from zot:** verify the offline verifier fetches signatures from the new
  registry host with the minted credential (docker config reuse).
- **Cutover sequencing:** dual-push (GHCR + zot) during migration, then flip pull sites, then
  retire GHCR — vs. hard flip. Plan-time.

## User-Brand Impact

- **Artifact:** the container-image pull path for Hetzner host boot/deploy (the credential the
  host uses to `docker pull` platform images).
- **Vector:** a botched registry cutover or a broken minted-token path silently fails host boot
  or deploy — a single tenant's app fails to come up or update, with the failure surfacing only
  as a stalled deploy. A weakened registry-auth path (bespoke/untested) is a supply-chain trust
  breach surface.
- **Threshold:** `single-user incident`.

## Domain Assessments

**Assessed:** Marketing (n/a), Engineering (assessed), Operations (assessed), Product (n/a),
Legal (n/a), Sales (n/a), Finance (assessed — vendor cost), Support (n/a).

This is a pure supply-chain / infra credential migration with **no user-facing, product, legal,
or data-residency surface**, so the CPO/CLO/CTO triad was scoped to its Engineering + Operations
+ Finance dimensions via targeted specialists rather than a full 8-leader fan-out. `USER_BRAND_CRITICAL`
remains set (fail-safe); the `user-impact-reviewer` at PR review is the load-bearing gate.

### Engineering

**Summary:** OIDC-per-se buys nothing on Hetzner (no native identity issuer); the correct
mechanism is a control-plane-minted bearer token against a registry that accepts it. zot
(self-hosted, R2-backed) is the tightest ADR-088 reuse with native bearer auth — no bespoke
auth code. Ranked #1 of six candidates; R2+Worker #2 (rejected for bespoke-auth risk), Quay
managed fallback.

### Operations

**Summary:** In-datacenter placement satisfies the restricted-egress firewall (ADR-052/#5046)
with no new public allowlist entry and zero egress. Ops cost = running/patching zot + R2 bucket;
boot-time SPOF is the operational risk to mitigate (HA / pull-through cache / PAT break-glass).

### Finance

**Summary:** $0 new vendor (already on Cloudflare + R2 + Hetzner). Marginal cost ≈ €4/mo Hetzner
CAX11 for the zot host + ~$0.015/GB-mo R2 storage, **zero egress**. Beats every AWS/GCP OIDC
option (which add egress + a new cloud footprint) and Quay ($15/mo + egress).

## Capability Gaps

None blocking. All primitives exist: Inngest minter (needs re-point), Doppler wiring, Cloudflare
R2 (already used), Hetzner host provisioning (Terraform), cosign chain (registry-agnostic).
Evidence: blast-radius map enumerated every build/push/pull/credential site with file:line (see
spec Technical Requirements).
