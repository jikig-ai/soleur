<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
---
title: "fix(supply-chain): make cosign image-verify PASSable in WARN against a signed PRIVATE GHCR image (GHCR auth + cosign 3.x offline trusted-root)"
issue: 6005
type: fix
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
date: 2026-07-04
branch: feat-one-shot-6005-cosign-verify-ghcr-auth-offline
---

# fix(supply-chain): make cosign image-verify PASSable in WARN against a signed PRIVATE GHCR image

> Closes #6005 on merge. ENFORCE-prep only — the `IMAGE_VERIFY_MODE` default `warn`→`enforce` flip stays OUT OF SCOPE (gated on this landing + a clean WARN soak). Do NOT flip ENFORCE here.

## Enhancement Summary

**Deepened on:** 2026-07-04. **Gates:** 4.6 User-Brand (PASS, `single-user incident`), 4.7 Observability (PASS), 4.8 PAT-shaped-var (PASS — naming avoids regex; the PAT is a deliberate, surfaced exception, see D1), 4.9 UI-wireframe (N/A — no UI surface). **Agents:** CTO (design), code-simplicity-reviewer, architecture-strategist, security-sentinel. **External research:** cosign 3.x offline flag set (Sigstore docs, v3 blog, some-natalie air-gap guide, cosign #4550) — see Sources.

**Security-sentinel folded (final pass):** (1) HIGH — the GHCR token must be fetched at boot via `doppler secrets get`, **never** `templatefile`-interpolated into cloud-init user-data (Hetzner-metadata + log leak); (2) HIGH — a CI **staleness gate** on the pinned `trusted_root.json` expiry (fail within N days) is required and must precede the ENFORCE flip; (3) **Design C** (host-side signature pre-fetch + `cosign verify --network none`) is the preferred egress resolution — removes both the egress question and the credential-into-container mount; (4) D1 PAT affirmed as the security-*superior* choice (the App path forces the org-wide-write App private key onto the host); (5) temp-config hardening (`mktemp -d 0700` + trap) + stderr scrub before Sentry.

**Key improvements over v1:**
1. **Design coherence (code-simplicity P0):** v1 mixed `--network host` (which makes online verify work, since host egress is unrestricted — `cron-egress-nftables.sh:21`) with offline+trusted-root (redundant under `--network host`). Resolved to a single coherent **Design B** (sandboxed cosign container + narrow ghcr.io allowlist + offline verify), under which offline+trusted-root IS load-bearing. Design A recorded as the rejected alternative.
2. **New D0 — keep-private vs. revert-to-public:** the entire credential subsystem exists only because the package flipped private; v1 never surfaced the decision. Added with evidence it's deliberate + an explicit operator/CPO sign-off requirement.
3. **Circular-trust fix (architecture H1):** `trusted_root.json` is delivered via cloud-init `write_files`, NOT baked into the image-under-verification.
4. **Mechanism pinned (architecture H2):** the login-before-pull AND SENTRY_*-before-verify both require ONE new early Doppler fetch (the existing download runs after verify) — v1 described the fixes without the mechanism.
5. **Credential scope widened (architecture H4):** `soleur-inngest-bootstrap` is ALSO private → the credential must cover both packages or the fresh boot stays fail-closed at `cloud-init.yml:511`.
6. **C4 correctness (architecture H3):** the `hetzner → sigstore` verify edge is FALSIFIED (no live sigstore call under offline+pinned-root) — a required correction, not optional.
7. **Honest ADR rationale + discoverability (architecture M3):** PAT driver reframed to fresh-boot t=0 availability (+ counter-cost recorded); ADR owns pull+verify; `principles-register.md` AP-row pointer for the hr-github-app-auth-not-pat exception.
8. **YAGNI cuts:** dropped the standalone refresh script (→ a comment) and the Dockerfile `COPY`.

## Overview

The supply-chain image-signing + WARN-mode deploy-path verify shipped earlier (the "#5933 Item 4" work; running-host half in ci-deploy.sh, keyless signing in `reusable-release.yml`, dual-path amendment recorded in ADR-082). The WARN verify is safe (never blocks a deploy) but live validation on 2026-07-04 (dispatched release web-v0.188.1, run 28705048144, signing SUCCEEDED) found it will not actually PASS on the real host. This plan makes it PASSable — authenticated against the now-**private** GHCR package and verifying fully **offline** with the cosign 3.x non-deprecated flag set — while remaining in WARN.

Grounding research this session surfaced that the fix is **materially larger than the issue's two-bullet framing** ("both in ci-deploy.sh"). Three root problems, only one of which is a lone `--offline` flag swap:

1. **No GHCR credential exists anywhere in the repo.** The host `docker pull` (`ci-deploy.sh:909` app, `:1366` inngest, plus the fresh-boot pulls in `cloud-init.yml`) is an **anonymous** pull that worked only while the package was public. There is no `docker login`, no `~/.docker/` provisioning, and no `read:packages` token in Doppler (Explore-agent sweep, confirmed against `variables.tf`, `cloud-init.yml`, git history). So the cosign container has no host credential to "inherit" — the issue's premise that the host has credentials the container doesn't inherit is **false**; the credential must be *created*. This also means the **host pull itself is now fail-closed** for any uncached private tag (every deploy pulls a new tag; a fresh web-2 boot per #5274 cannot come up at all) — a higher-severity break than the WARN verify.
2. **The cosign container's egress is firewall-blocked.** `verify_image_signature` runs `docker run --rm <cosign> verify …` on the **default docker0 bridge**, so it is subject to the `SOLEUR-EGRESS`/`DOCKER-USER` container firewall (`cron-egress-nftables.sh`). Neither `ghcr.io` nor the sigstore hosts are in `cron-egress-allowlist.txt`. On the real host the cosign container cannot reach GHCR to fetch the attached signature bundle at all (the live-validation UNAUTHORIZED was observed off-host, where GHCR is reachable and auth failed first).
3. **`--offline` alone does not give true offline verify in cosign 3.x, and is deprecated.** `--offline` only suppresses the online Rekor fallback. cosign still fetches its **trust root** (Fulcio CA, Rekor/CT keys) from the TUF CDN by default — also firewall-blocked. True offline verify requires a **locally-pinned `trusted_root.json`** via `--trusted-root`, plus `--offline=true --new-bundle-format=false` (the non-deprecated flag set for the existing OCI-attached signature format). `--offline` is deprecated in v3.1.1 (removed in v4).

A fourth, adjacent defect: **the WARN telemetry is currently dark.** `verify_image_signature` runs at `ci-deploy.sh:916`, **before** the Doppler env download at `:992` that sets `SENTRY_*`. Only `DOPPLER_TOKEN` is in the ambient webhook env (`cloud-init.yml:312`). So `cosign_verify_event`'s Sentry POST is skipped at verify time — meaning the ENFORCE-flip soak gate ("no `verify_result` failures in Sentry over a soak") is **blind**. Fixing verify without fixing this ships a feature whose success signal never reaches the dashboard the flip depends on.

The honest, minimal-coherent fix therefore provisions ONE GHCR read credential (Doppler + host `docker login`, fixing the host pull AND the cosign container via a mounted config), ships a pinned `trusted_root.json`, reworks the cosign invocation to the 3.x offline flag set with the credential + trusted-root mounted and a resolved egress path, makes the WARN telemetry actually reach Sentry, and corrects the C4 `ghcr` element description. It extends **ADR-082**.

## Research Reconciliation — Issue Premise vs. Codebase Reality

| Issue #6005 claim | Codebase reality (verified this session) | Plan response |
|---|---|---|
| "does NOT inherit the **host's docker/ghcr credentials**" — implies the host HAS credentials | No `docker login` / `config.json` / Doppler `read:packages` token anywhere (`ci-deploy.sh`, `cloud-init.yml`, `variables.tf`, git history). Host pull is **anonymous**. | Credential must be **provisioned**, not inherited. Add Doppler `GHCR_READ_*` + host `docker login` (IaC). |
| "Fix … in **ci-deploy.sh**" (both fixes) | The credential + login must live in Terraform/cloud-init per `hr-all-infrastructure-provisioning-servers` and `hr-fresh-host-provisioning-reachable-from-terraform-apply` (fresh web-2 must be authed before its first pull). Only the flag/mount edits belong in ci-deploy.sh. | Split: IaC (credential, login, baked trusted-root) + ci-deploy.sh (flags, mounts, egress, telemetry ordering). |
| "`docker run … cosign verify` does not inherit creds → UNAUTHORIZED fetching the signature" | True off-host. On the **real** host the cosign container is also **egress-blocked** from ghcr.io (docker0 → SOLEUR-EGRESS); failure mode there is connection-drop, not UNAUTHORIZED. | Resolve egress (Decision D3) in addition to auth. |
| "Rework to `--bundle` + `--trusted-root`" (offline flag) | The signature is a **registry-attached** OCI referrer, not a local bundle file — the non-deprecated offline path here is `--offline=true --new-bundle-format=false --trusted-root <local>`, with a **pinned trusted_root.json shipped to the host** (not `--bundle <file>`). | Ship + mount `trusted_root.json`; use the 3.x offline flag set. |
| C4 `ghcr` says "Public GHCR" | `model.c4:238-240` describes it as "Public GHCR registry"; package is `visibility: private`. | Correct the description + the "no registry auth" code comment (`ci-deploy.sh:500-501`). |
| (implicit) WARN verify is observable during soak | Verify runs before `SENTRY_*` load (`:916` vs `:992`) → Sentry event dark. | Make telemetry reach Sentry at verify time (Phase 4). |

## User-Brand Impact

**If this lands broken, the user experiences:** a stalled or failed deploy (running host can't pull a new private tag → new version never ships; old container keeps serving) or, on the fresh-host path (#5274 web-2), a host that cannot boot its app container at all → lost HA/scale headroom during an incident window. A misconfigured `trusted_root`/auth that is NOT caught by WARN would, if ENFORCE were ever flipped on top of it, fail-close every deploy — which is exactly why ENFORCE stays out of scope here.

**If this leaks, the user's data / workflow / money is exposed via:** the GHCR read credential (`read:packages`, single package) landing in the deploy env / `/home/deploy/.docker/config.json` / Doppler `prd`. A broad or long-lived token here widens the blast radius of a host compromise. Mitigation: least-privilege scope (single package, read-only), machine/bot-account or App-installation ownership (Decision D1), and no token in argv/logs (mirror the existing `doppler secrets download` env-file discipline).

**Brand-survival threshold:** single-user incident.

> `requires_cpo_signoff: true` — CPO sign-off required at plan time before `/work` begins (supply-chain + deploy-availability change). `user-impact-reviewer` will be invoked at review time.

## Decisions (open items routed to deepen-plan / domain review)

- **D0 — Keep the package PRIVATE, or revert to PUBLIC? (decide FIRST — gates ~40-50% of this plan).** The entire credential subsystem (D1, D5, Phase 1, the Doppler secret, the host `docker login`, half of Phase 3) exists ONLY because the package flipped public→private. Reverting to public restores the prior known-good anonymous-pull path and deletes that whole subsystem for free. **Evidence that private is DELIBERATE (not incidental):** (a) issue #6005 itself asks to correct the C4 to say "private" and frames the whole task around private auth; (b) ADR-082's dual-path amendment assumes the private posture; (c) a private app image avoids exposing the built Next.js artifact + baked host-bootstrap scripts/hooks (`ADR-080`) publicly — a real supply-chain hardening. **Recommendation:** keep private (the security posture is intentional and the artifact should not be public), but this MUST be an explicit operator/CPO sign-off, not a silent assumption — if private was an accidental flip, go public and delete D1/D5/Phase 1 entirely. Surfaced per code-simplicity review (deepen-plan).
- **D1 — Credential type & ownership.** A single `read:packages` credential scoped to the one package. **Verified cost table (deepen-plan):**

  | | App installation token | fine-grained PAT (machine account) |
  |---|---|---|
  | Manifest change | **YES** — `github-app-manifest.json:18` `default_permissions` has NO `packages` key; adding `packages: read` triggers an installation **re-consent** (operator GitHub UI, #4173 three-plane-drift class) | none |
  | Host-side mint | **NEW bash machinery** — `ci-deploy.sh` does NOT currently mint an App installation token (its `openssl` at `:152` is HMAC webhook-signing; the `jwt` refs at `:1102+` are the canary bundle-decode, not App JWT). Would need RS256 JWT + token-exchange in bash, pre-verify (App PEM is in Doppler `prd` via `github-app.tf` but not in the ambient webhook env until the `:992` download). | none — static Doppler secret used directly in `docker login --password-stdin` |
  | `hr-github-app-auth-not-pat` | satisfies literally | **read-only GHCR pull, not a GitHub *write*** — the rule's scope (per deepen-plan Phase 4.8) is "infra-time GitHub **writes**"; a machine-account PAT mitigates the per-operator/handoff concern the rule targets |
  | Expiry | none (App tokens auto-refresh) | fine-grained PAT max 1yr (or no-expiry with warning) → rotation follow-through needed |

  **Scope (H4 — BOTH packages are private):** the credential must cover **both** `soleur-web-platform` AND `soleur-inngest-bootstrap` (`gh api` this session confirmed BOTH `visibility: private`). The fresh boot pulls web-platform at `cloud-init.yml:381`/`:466`/`:578` AND inngest-bootstrap at `:511` — a single-package credential leaves the fresh boot fail-closed at `:511`. Scope the fine-grained PAT to both packages (or org-level `read:packages` if the flip is org-wide). The cosign image (`ci-deploy.sh:40` `ghcr.io/sigstore/cosign`) is public — no concern.

  **Recommendation:** scoped fine-grained PAT (`read:packages`, the two jikig-ai packages) on a **machine/bot account**, recorded in the ADR-082 amendment as a **deliberate, narrow, read-only exception** to `hr-github-app-auth-not-pat`. **security-sentinel AFFIRMED D1 as the security-SUPERIOR choice (not just convenient):** the App path is strictly *worse* for credential-at-rest — minting an installation token on the host requires bringing the App **private key** (already in Doppler `prd`, `github-app.tf:55`) into host memory, and that key can mint tokens for EVERY App permission (contents/PRs/issues writes) → a host compromise during the mint window exposes an org-wide *write*-capable key; the fine-grained PAT exposes a single-package *read-only* token (~2-order-of-magnitude smaller blast radius). Also App `packages:read` is per-*repository* (grants all packages the installation sees), broader than a per-package PAT. Record this **security** rationale in the ADR, not only the fresh-boot-t=0 convenience. **Counter-cost:** a ≤1yr PAT is a worse secret-at-rest than a 1hr installation token AND expires silently → the M2 expiry alarm + rotation follow-through are mandatory; verify machine-account 2FA + org SSO-authorization at mint (else 401 after the next SSO cycle). Route to `security-sentinel` + `infra-security` for the final call. A user-account PAT (person-dependency) is the anti-pattern to avoid. Note: deepen-plan Phase 4.8 did NOT halt (the `GHCR_READ_TOKEN` / `TF_VAR_ghcr_read_token` naming avoids the PAT-shaped regex) — the exception is deliberate and surfaced here, not smuggled past the gate; it must ALSO be discoverable via a `principles-register.md` pointer (M3b).
- **D2 — Scope: include the host pull fix.** CONFIRMED IN SCOPE. One `docker login ghcr.io` writing `/home/deploy/.docker/config.json` fixes both the host pull (`:909`, `:1366`, fresh-boot) and the cosign container (mount that config). Cosign-container-only would ship a still-broken fail-closed pull.
- **D3 — Egress + verify design: COHERENT choice (Design C preferred, Design B fallback).** The plan v1 incoherently mixed two designs (code-simplicity-reviewer P0): it chose `--network host` (which, because **host egress is unrestricted** — the SOLEUR-EGRESS firewall is `iifname docker0`-scoped ONLY, `cron-egress-nftables.sh:21`) would let cosign reach sigstore and make plain **online** verify work, making the offline+trusted-root machinery redundant. The two coherent designs:
  - **Design A (rejected): `--network host` + online verify.** Simplest for WARN-pass (drop `--offline`, no trusted-root). REJECTED because: (1) it reverses ADR-082's deliberate offline posture (which exists precisely because #5046 blocks sigstore from containers); (2) `--network host` exposes host-**loopback** services (inngest `:8288`/`:3000`, redis, the webhook) to the cosign container — the real cost is loopback exposure, not egress (architecture-strategist M1); (3) it couples deploy-time verify to sigstore CDN uptime — a CDN outage would fail-close every deploy once ENFORCE flips.
  - **Design C (PREFERRED — security-sentinel): host-side signature pre-fetch + `cosign verify --network none`.** Because the trusted root is local, the ONLY reason the cosign container needs a network is to fetch the registry-attached signature manifest. Fetch it **on the host** (already authenticated after the Phase-3 `docker login`) — e.g. `cosign download signature` / `oras` / `cosign save` to a local OCI layout or bundle file — then run `cosign verify … --network none` against the local artifact. This eliminates BOTH the egress question AND the credential mount into the cosign container (no `config.json` ever enters it; zero container network — strictest posture). Route to `infra-security` as the preferred D3 resolution; if impractical with the `--new-bundle-format=false` registry-attached format, fall back to Design B.
  - **Design B (fallback): sandboxed cosign container + narrow `ghcr.io` allowlist + offline verify.** Keep the cosign `docker run` on docker0 (sandboxed, no `--network host`); add **only** `ghcr.io` to `cron-egress-allowlist.txt`; verify offline (`--offline=true --new-bundle-format=false --trusted-root=<local>`) so sigstore/TUF stay blocked. Under Design B the offline+trusted-root IS load-bearing (the sandboxed container genuinely cannot reach sigstore), resolving the v1 contradiction. Cost: the shared allowlist widens the *app* container's egress by one read-only registry host. Do NOT pick a `--network host` variant (loopback exposure) nor sigstore in any allowlist.
- **D4 — trusted_root.json provenance (RESOLVED: cloud-init `write_files`, NOT baked — circular-trust fix).** **Commit `trusted_root.json` to the repo** (reviewable/diffable) and deliver it to the host **via cloud-init `write_files` (a separate channel from the image under verification)**, rendered from the committed repo file. Do **NOT** `COPY` it into the deploy image (architecture-strategist H1): the deploy image is the artifact being verified — sourcing the trust anchor from the thing you're verifying is circular, and the fresh web-2 boot (#5274) has no previously-verified image to bake from, so it needs cloud-init regardless. Do NOT `cosign initialize` at build (reaches TUF CDN → non-hermetic). **Staleness detection is REQUIRED (security-sentinel HIGH #2), not a calendar reminder:** add a **CI gate that parses the pinned root's expiry/`validFor` timestamps and FAILs when they fall within N days (e.g. 60)** — a stale root is WARN noise now but fail-closes every deploy once ENFORCE flips, so this gate MUST land before the ENFORCE follow-up. **Capture integrity (security-sentinel #5):** record the `sha256` of the committed `trusted_root.json` in its header + the ADR (guards TOFU on the `cosign initialize` capture); note in the provenance header that pinning **disables TUF revocation propagation** — a compromised-then-rotated sigstore key stays trusted until a human refreshes (the honest trade-off of an air-gapped root). Rotation recipe: a one-line comment in the committed JSON (no standalone refresh script — YAGNI). ADR-082 must state the trust-root provenance is the committed repo via TF-rendered cloud-init, NEVER the image under verification.
- **D5 — credential minting automation.** `automation-status: UNVERIFIED — /work MUST run a Playwright attempt before any operator handoff.` Fine-grained PAT / machine-account creation is a GitHub dashboard flow under an authenticated session — presumptively Playwright-automatable until a real attempt reaches a named human gate (password sudo-mode / 2FA). Per `hr-block-pr-ready-on-undeferred-operator-steps` + the never-defer-operator-actions memory, wire the value into Doppler via TF and confirm in-session; do not defer as a checklist bullet.

## Implementation Phases

### Phase 0 — Preconditions (verify before coding)
- [ ] Confirm cosign v3.1.1 offline flag set against the **pinned cosign container** (not docs alone): `docker run --rm $COSIGN_IMAGE verify --help` and confirm `--offline`, `--trusted-root`, `--new-bundle-format` are all recognized; capture output into the plan/spec (CLI-verification gate #2566). Confirm `--offline` still runs (deprecated-not-removed) as a fallback.
- [ ] Generate `trusted_root.json` for the sigstore public-good instance on a connected machine (`cosign initialize`; grab `~/.sigstore/root/tuf-repo-cdn.sigstore.dev/targets/trusted_root.json`) and confirm a local offline verify of the **already-signed** web-v0.188.1 digest succeeds with `--offline=true --new-bundle-format=false --trusted-root <file>` + the existing identity-regexp/OIDC-issuer + a valid GHCR credential. This is the load-bearing end-to-end probe — do it before writing the shell.
- [ ] Confirm the signing identity regexp (`COSIGN_IDENTITY_REGEXP`, `ci-deploy.sh:41`) still matches the signature on the live digest (no drift since #5933).
- [ ] Confirm `DOPPLER_TOKEN` is in the ambient env at verify time (it is — `cloud-init.yml:312` `/etc/default/webhook-deploy`) so a pre-verify `doppler secrets get` for the GHCR token + `SENTRY_*` is feasible.
- [ ] **(H4) Enumerate EVERY `jikig-ai` GHCR package the fresh + running host pulls and confirm each visibility.** Confirmed this session: `soleur-web-platform` AND `soleur-inngest-bootstrap` are BOTH private (`cloud-init.yml` pulls at `:381`/`:466`/`:511`/`:578`; `ci-deploy.sh:909`/`:1366`). The credential must cover both; a single-package token leaves the fresh boot fail-closed at the inngest pull (`:511`).

### Phase 1 — Credential provisioning (IaC)
- [ ] Mint the scoped `read:packages` credential (Decision D1, covering BOTH packages / org-level) — `/work` attempts Playwright first (D5), else routes to the named human gate reached.
- [ ] **Ordered credential runbook (L1 — two distinct Doppler locations, do not conflate):** (1) mint → (2) write the value into Doppler `prd_terraform` (the TF runner's `TF_VAR` source) → (3) verify present → (4) merge the `*.tf` edit (which triggers `apply-web-platform-infra.yml`); the apply's `doppler_secret` resources then propagate it to Doppler `soleur/dev` + `soleur/prd` (where the host reads it). If step 2 is skipped, the auto-apply fails resolving all root vars before `-target` pruning. `TF_VAR_ghcr_read_token` has **no default** (`hr-tf-variable-no-operator-mint-default`). (L2: confirm a dev host actually pulls a private package before minting a second dev credential — `hr-dev-prd-distinct` doubles at-rest surface.)
- [ ] Add `doppler_secret` resource(s) for `GHCR_READ_TOKEN` (+ `GHCR_READ_USER`) to a new/extended `*.tf` under `apps/web-platform/infra/`, mirroring the `github-app.tf` `doppler_secret` precedent; provision to dev + prd.
- [ ] cloud-init `docker login ghcr.io` for **fresh-boot t=0** (`hr-fresh-host-provisioning-reachable-from-terraform-apply`) writing `/home/deploy/.docker/config.json` (`deploy:deploy`, `chmod 600`) via `--password-stdin` (never argv), before the first pull. **HIGH (security-sentinel #1): fetch the token AT BOOT via `doppler secrets get GHCR_READ_TOKEN --plain` using the already-present ambient `DOPPLER_TOKEN` — NEVER `templatefile`-interpolate it into cloud-init user-data** (that lands in Hetzner instance metadata + `/var/log/cloud-init-output.log`, mirroring the `cloud-init.yml:312` `${doppler_token}` precedent). The `TF_VAR_ghcr_read_token` + `variables.tf` entry is ONLY the `doppler_secret` *publishing* source, never a cloud-init interpolation var. The **running-host** login is the per-deploy one in ci-deploy.sh (Phase 3) — which also refreshes config.json on rotation (M2).

### Phase 2 — trusted_root.json (repo + cloud-init, NOT baked)
- [ ] Commit `trusted_root.json` under `apps/web-platform/infra/` (e.g. `cosign-trusted-root.json`) with a header/NOTE documenting provenance (which TUF root, capture date) AND a one-line rotation recipe comment (`to rotate: cosign initialize; copy trusted_root.json`) — no standalone refresh script (YAGNI, code-simplicity review).
- [ ] Deliver it to the host via **cloud-init `write_files`** (rendered from the committed repo file) at a stable path (e.g. `/opt/soleur/cosign-trusted-root.json`, `deploy:deploy`, `0644`), so the cosign `--trusted-root` mount source is identical on fresh + running hosts. Do **NOT** `COPY` it into the deploy image — the deploy image is the artifact under verification (circular trust, architecture-strategist H1); cloud-init is the separate, out-of-image trust channel the fresh boot needs anyway.
- [ ] Record the committed root's `sha256` in its header + ADR (TOFU guard, security-sentinel #5).
- [ ] **Add a CI staleness gate (security-sentinel HIGH #2): parse the pinned root's expiry/`validFor` timestamps and FAIL the build when within N days (e.g. 60).** Must land before the ENFORCE follow-up — a stale root is WARN noise now but fail-closes every deploy under ENFORCE.

### Phase 3 — Rework the cosign verify invocation (ci-deploy.sh) — PIN THE MECHANISM (H2)
- [ ] **Add ONE early scoped Doppler fetch near the top of the deploy critical path (before the pull at `:909`)** that exports into ci-deploy.sh's OWN shell env: `GHCR_READ_TOKEN`, `GHCR_READ_USER`, and `SENTRY_INGEST_DOMAIN`/`SENTRY_PROJECT_ID`/`SENTRY_PUBLIC_KEY`. This is REQUIRED because the only existing Doppler download (`resolve_env_file`, `:626`) is called at `~:993` — AFTER the pull (`:909`) and verify (`:916`) — and passes secrets to the container via `--env-file`, so they are NEVER in the script's own env at pull/verify time. Without this fetch, neither the host login nor the WARN telemetry lands. Use a single `doppler secrets download`/`get` (DOPPLER_TOKEN is ambiently present, `cloud-init.yml:312`); keep the token OUT of argv/logs.
- [ ] Host `docker login ghcr.io -u "$GHCR_READ_USER" --password-stdin` using `$GHCR_READ_TOKEN`, **before** `docker pull` (`:909`, `:1366`) — makes the private pull succeed AND writes `/home/deploy/.docker/config.json`. Run the login **on every deploy** so a rotated/expired token propagates to a weeks-running host without a reboot (M2). **Reuse this `/home/deploy/.docker/config.json` for the cosign mount — do NOT make a second on-disk token copy.** If a scoped `DOCKER_CONFIG` temp dir is unavoidable, `mktemp -d` `0700` + `trap … EXIT` cleanup so the token config isn't left on disk when verify aborts under `set -e` (security-sentinel #4). Under Design C no credential enters the cosign container at all.
- [ ] Replace `docker run --rm "$COSIGN_IMAGE" verify --offline …` with the **Design B** set (sandboxed, no `--network host`):
  ```sh
  docker run --rm \
    -v /home/deploy/.docker/config.json:/root/.docker/config.json:ro \
    -v /opt/soleur/cosign-trusted-root.json:/trust/trusted_root.json:ro \
    "$COSIGN_IMAGE" verify \
    --offline=true --new-bundle-format=false \
    --trusted-root=/trust/trusted_root.json \
    --certificate-identity-regexp="$COSIGN_IDENTITY_REGEXP" \
    --certificate-oidc-issuer="$COSIGN_OIDC_ISSUER" \
    "$repo_digest"
  ```
  Egress: add `ghcr.io` to `cron-egress-allowlist.txt` so the sandboxed container reaches GHCR (D3); exact flag set pinned by the Phase 0 probe.
- [ ] Correct the stale code comment at `:499-501` ("The app image is public GHCR, so the cosign container needs no registry auth") and `:34-35` header.
- [ ] Preserve the WARN/ENFORCE semantics exactly — telemetry fires identically, mode branch unchanged, ENFORCE default stays `warn`.

### Phase 4 — Observability (telemetry-not-dark + credential SPOF)
- [ ] The `SENTRY_*`-before-verify fix is delivered by the Phase 3 early Doppler fetch (they are exported into the script env before `verify_image_signature` runs) — the WARN `verify_result` event now reaches Sentry, which is what makes the ENFORCE-flip soak gate observable (the whole point of an "ENFORCE-prep" issue). Assert the ordering with a test.
- [ ] Add a **loud, no-SSH** failure event for the host **pull** itself — an authenticated private-pull denial must be Sentry/Better Stack diagnosable, not journald-only (`hr-no-ssh-fallback-in-runbooks`, observability-coverage-reviewer §4.6). Because every deploy + fresh boot now hard-depends on a valid GHCR credential (M2 SPOF), this pull-failure event is load-bearing, not additive. **Scrub the captured docker/cosign stderr to the classification string before it enters the Sentry payload** — a verbose `401`/`403` daemon error can echo the registry auth header (security-sentinel #7; applies to the existing `cosign_verify_event` `tail` at `ci-deploy.sh:519` too).
- [ ] Add a **proactive credential-expiry** liveness signal (M2) — a fine-grained PAT with bounded expiry silently fail-closes the whole fleet's deploys AND fresh boots at expiry; a reactive pull-failure event fires too late. Alert before expiry (e.g. a scheduled check, or enroll the rotation follow-through per `wg-record-recurring-vendor-expense-before-ready`-style cadence).

### Phase 5 — C4 + ADR + tests
- [ ] `model.c4:238-240`: change "Public GHCR registry" → private, note the host authenticates via `read:packages`. Run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts`.
- [ ] Amend **ADR-082** (`## Decision` + `## Alternatives Considered`): private-visibility credential model, the D1 scoped-credential exception to `hr-github-app-auth-not-pat` with rationale, and the committed-`trusted_root.json` offline-verify decision.
- [ ] Extend `ci-deploy.test.sh` mock-cosign handler for the new flag set + a mounted-config/egress trace assertion; keep the existing WARN-never-blocks / ENFORCE-blocks / inspect-fallback tests green (they must pass identically).
- [ ] File the WARN→ENFORCE flip as a tracked follow-up issue (re-eval: verify observed PASSING with no `verify_result` failures over a soak) so WARN-forever is not the silent resting state.

## Files to Edit
- `apps/web-platform/infra/ci-deploy.sh` — early Doppler fetch (GHCR token + SENTRY_*, before `:909`), per-deploy `docker login`, cosign invocation (`:487-524`) flag set + config/trusted-root mounts (no `--network host`), host-login ordering before pulls (`:909`, `:1366`), stale comments (`:34-35`, `:499-501`).
- `apps/web-platform/infra/cloud-init.yml` — `write_files` for `cosign-trusted-root.json` (D4, NOT baked). Fresh-boot `docker login ghcr.io` (if a boot-time login is used in addition to the per-deploy login) writing `/home/deploy/.docker/config.json`. Note: the per-deploy login lives in ci-deploy.sh (Phase 3), which covers the running host; cloud-init covers t=0 fresh boot before ci-deploy runs.
- `apps/web-platform/infra/<new-or-existing>.tf` — `doppler_secret` for `GHCR_READ_TOKEN` (+ user), dev+prd; `variables.tf` for the `TF_VAR_*` (no default).
- `apps/web-platform/infra/cron-egress-allowlist.txt` — add `ghcr.io` (Design B — sandboxed cosign container needs it to fetch the signature bundle).
- `apps/web-platform/infra/cosign-trusted-root.json` — NEW, committed pinned root + provenance/rotation-recipe comment. (NO Dockerfile `COPY` — H1 circular-trust.)
- `apps/web-platform/infra/ci-deploy.test.sh` — mock-cosign flag-set + mounted-config trace assertions; SENTRY_*-before-verify ordering assertion.
- `knowledge-base/engineering/architecture/diagrams/model.c4` — `ghcr` element description (`:238-240`) AND the falsified `hetzner → sigstore` verify edge (`:312`, now no live sigstore call).
- `knowledge-base/engineering/architecture/principles-register.md` — add a discoverability pointer (AP-row) for the `hr-github-app-auth-not-pat` read-only-GHCR-pull exception (M3b).
- `knowledge-base/engineering/architecture/decisions/ADR-082-fresh-web2-boot-observability.md` — amendment.

## Files to Create
- `apps/web-platform/infra/cosign-trusted-root.json` (committed pinned root + provenance/rotation-recipe comment + `sha256`). No refresh script (YAGNI — the rotation recipe is a comment).
- A **CI staleness gate** (test or workflow step) parsing the pinned root's expiry/`validFor` and failing within N days (security-sentinel HIGH #2) — must precede the ENFORCE flip.

## Acceptance Criteria

### Pre-merge (PR)
- [ ] The cosign `docker run` in `ci-deploy.sh` uses the **non-deprecated** 3.x offline flag set (`--offline=true --new-bundle-format=false --trusted-root=…`, exact set pinned by the Phase 0 `--help` probe) — no bare deprecated `--offline`, no `--network host`; `git grep -n 'cosign' ci-deploy.sh` shows the mounted `-v …/config.json` and `-v …/trusted_root.json`; `ghcr.io` is present in `cron-egress-allowlist.txt` (Design B egress).
- [ ] Phase 0 offline probe evidence (successful offline verify of the live signed web-v0.188.1 digest with a real GHCR credential + local trusted_root.json) pasted into the spec/PR body.
- [ ] `IMAGE_VERIFY_MODE` default is still `warn` (`grep -n 'IMAGE_VERIFY_MODE:-warn' ci-deploy.sh` → 1 hit); no ENFORCE flip.
- [ ] `ci-deploy.test.sh` green: existing WARN-never-blocks, ENFORCE-blocks (load-bearing), inspect-fallback tests unchanged + new flag/mount assertions.
- [ ] `model.c4` `ghcr` description no longer contains "Public"; `c4-code-syntax.test.ts` + `c4-render.test.ts` green.
- [ ] ADR-082 amended (private credential model + hr-github-app-auth-not-pat exception + trusted_root decision).
- [ ] `SENTRY_*` are set before `verify_image_signature` runs (verify_result event can reach Sentry) — asserted by a test or a code-ordering check.
- [ ] `GHCR_READ_TOKEN` `TF_VAR_*` has no default; Doppler dev+prd wiring present; value confirmed in `prd_terraform` before the `*.tf`-triggered auto-apply (sequencing note in PR body).
- [ ] WARN→ENFORCE flip follow-up issue filed (`Ref #6005`, re-eval criteria = clean soak).
- [ ] PR body uses `Closes #6005`.

### Post-merge (operator / automated)
- [ ] `apply-web-platform-infra.yml` applies cleanly (Doppler `GHCR_READ_TOKEN` present); host `docker login` provisioned.
- [ ] On the running host, a real signed deploy: `docker pull` of the private tag succeeds (authenticated) AND the cosign verify **PASSES** offline (`IMAGE_VERIFY: ok` in journald; no `verify_result` failure event in Sentry). Pull data via the deploy webhook / Sentry, not SSH eyeballing (`hr-no-dashboard-eyeball-pull-data-yourself`).

## Domain Review

**Domains relevant:** Engineering (CTO — assessed), Operations/Infra (infra-security, terraform-architect), Security (security-sentinel). Product: NONE (no UI surface — infra/supply-chain change; Files lists contain no `components/**`, `app/**/page.tsx`, or UI-surface path → Product/UX Gate skipped).

### Engineering / CTO
**Status:** reviewed (assessed this session).
**Assessment:** Root cause = public→private visibility flip breaking every anonymous GHCR touch. Recommends: (1) scoped fine-grained PAT over App-JWT-on-host (record as deliberate exception to hr-github-app-auth-not-pat); (2) one host `docker login` fixes both pull + cosign (do NOT go cosign-only — the fail-closed pull is the higher-severity break, esp. fresh web-2 #5274); (3) commit+bake `trusted_root.json`, never `cosign initialize` at build; (4) IaC routing = credential/login in TF+cloud-init, only flags/mounts in ci-deploy.sh, amend ADR-082; (5) keep WARN, file ENFORCE follow-up, and note the fail-closed pull is the real brand risk. Flagged security-sentinel (credential-at-rest) + observability-coverage-reviewer (pull-failure must be no-SSH diagnosable) for review.

### Operations / Infra
**Status:** to be run at deepen-plan (terraform-architect for the doppler_secret + cloud-init login shape; infra-security for D3 `--network host` vs allowlist and credential-at-rest).

### Security
**Status:** to be run at review (security-sentinel — least-privilege token scope, no token in argv/logs, config.json perms; user-impact-reviewer per single-user-incident threshold).

## Infrastructure (IaC)

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->

### Terraform changes
- New/extended `apps/web-platform/infra/*.tf`: `doppler_secret` for `GHCR_READ_TOKEN` (+ `GHCR_READ_USER`) → Doppler `soleur/dev` + `soleur/prd`, mirroring `github-app.tf`. `variables.tf` adds `TF_VAR_ghcr_read_token` (+ user), **no default** (`hr-tf-variable-no-operator-mint-default`). Value sourced from Doppler `prd_terraform` at apply; must exist before the `*.tf` edit triggers `apply-web-platform-infra.yml` (sequencing per the operator-mint-vs-auto-applied-IaC Sharp Edge).

### Apply path
cloud-init + idempotent bootstrap: fresh host gets `docker login` + baked trusted_root at boot (`hr-fresh-host-provisioning-reachable-from-terraform-apply`); running host gets the credential via the auto-applied infra root + the next deploy's login step. Blast radius: none to the running container (verify is WARN; login is additive). Downtime: none expected.

### Distinctness / drift safeguards
dev != prd credentials. `/home/deploy/.docker/config.json` written `chmod 600` `deploy:deploy`. Token never in argv (`--password-stdin`) or logs. trusted_root.json committed (diff-visible on rotation).

### Vendor-tier reality check
GHCR `read:packages` — no paid-tier gate. Fine-grained PAT / machine account is free.

## Observability

```yaml
liveness_signal:
  what: "cosign verify result (IMAGE_VERIFY: ok / IMAGE_VERIFY_FAIL) per deploy"
  cadence: "every web-platform deploy"
  alert_target: "Sentry (op=image-verify, tag verify_result); journald logger tag ci-deploy"
  configured_in: "ci-deploy.sh cosign_verify_event (:458) + verify_image_signature (:487)"
error_reporting:
  destination: "Sentry store endpoint (SENTRY_* env), level warning (WARN) / error (ENFORCE)"
  fail_loud: "true — but ONLY once SENTRY_* are set before verify (Phase 4 fix); today the event is dark at verify time"
failure_modes:
  - mode: "cosign verify fails (unsigned/wrong_identity/verify_failed)"
    detection: "Sentry event verify_result=<class>, mode=warn"
    alert_route: "Sentry supply-chain / op=image-verify"
  - mode: "private-image pull denied (auth missing/expired)"
    detection: "NEW loud event on docker pull failure (Phase 4) — must not be journald-only"
    alert_route: "Sentry / Better Stack, no-SSH"
  - mode: "cosign container cannot reach ghcr.io (egress/trusted-root misconfig)"
    detection: "verify_result classification on connection/registry error; Phase 0 probe pre-empts"
    alert_route: "Sentry op=image-verify"
  - mode: "GHCR credential expired/revoked → every deploy + fresh boot fail-closed (M2 SPOF)"
    detection: "PROACTIVE credential-expiry check (before expiry), NOT just the reactive pull-failure event"
    alert_route: "scheduled expiry alarm + rotation follow-through"
  - mode: "pinned trusted_root.json stale (past sigstore rotation) → verify_failed now, fail-closed under ENFORCE"
    detection: "CI staleness gate parses root expiry/validFor, fails within N days (security-sentinel HIGH #2)"
    alert_route: "red CI build (pre-merge); must land before ENFORCE flip"
logs:
  where: "journald (logger -t ci-deploy) + Sentry"
  retention: "journald host-local; Sentry per project retention"
discoverability_test:
  command: "gh/Sentry query for op=image-verify events after a signed deploy; deploy-state webhook read"
  expected_output: "verify_result=ok (or no failure event) on a real signed deploy; no ssh"
```

## Architecture Decision (ADR/C4)

### ADR
Amend **ADR-082** (dual-path verify decision it already owns; amend, not new — same decision, ordinal N/A). The amendment must:
- Own **pull + verify** (M3a) — the credential now serves the private-image PULL, not just verify (broader than #5933 Item 4's "signing + verify"). Cross-reference **ADR-080** (image bakes host bootstrap) and **#5274** (fresh web-2 boot) — the fresh boot now cannot pull unauthenticated.
- Record the **private-visibility GHCR credential model** (`read:packages` over BOTH `soleur-web-platform` + `soleur-inngest-bootstrap`, Doppler-threaded, host `docker login`).
- Record the **`hr-github-app-auth-not-pat` exception** with the HONEST rationale (M3c): primary driver = **fresh-boot t=0 static-credential availability** (an App installation token needs a JWT + `api.github.com` exchange before the first pull); record the **counter-cost** (a ≤1yr PAT is a worse secret-at-rest than a 1hr installation token). Add a `principles-register.md` AP-row pointer so the exception is discoverable (M3b).
- Record the **offline-verify decision**: pinned `trusted_root.json`, provenance = the committed repo via TF-rendered cloud-init `write_files`, **NEVER the image under verification** (H1); `cosign initialize`-at-build rejected as non-hermetic.
- Record the **Design B egress decision** (sandboxed cosign container + narrow ghcr.io allowlist, NOT `--network host`) and why (loopback exposure + ADR-082-Item-3 container-egress invariant, M1).

### C4 views
Checked all three `.c4` files (`model.c4`, `views.c4`, `spec.c4`). Relevant elements: `ghcr` system (`model.c4:238`, external), `sigstore` system (`:246`), `hetzner → ghcr` pull edge (`:309`), `hetzner → sigstore` verify edge (`:312`), `github → sigstore` signing edge (`:311`). Corrections this change requires:
- `ghcr` description (`:240`): "Public GHCR registry" → private; the fresh-host pull is now **authenticated** (`read:packages`).
- **`hetzner → sigstore` verify edge (`:312`) is FALSIFIED and must be corrected/removed.** It reads `Verifies the image signature (cosign --offline, identity-pinned) … technology "HTTPS (cosign)"` — but with a pinned local `trusted_root.json` + true offline verify, the host makes **no live HTTPS call to sigstore** at verify time (it uses the local root + the GHCR-attached bundle fetched from `ghcr`). Re-describe as "verifies the signature fully offline against a pinned trusted-root + the GHCR-attached bundle (NO live sigstore call)" or drop the edge and fold the offline-verify note into the `hetzner → ghcr` edge. The `github → sigstore` signing edge (`:311`) STAYS accurate (CI dials Fulcio/Rekor at sign time).
- `hetzner → ghcr` edge (`:309`): now carries the signature-bundle fetch too (authenticated) — description may note it.
No new external actor/system/relationship is introduced (the credential is an attribute of the existing pull edge, not a new element). Run `c4-code-syntax.test.ts` + `c4-render.test.ts` after edit (a `view include` referencing an undefined element fails there, not at `tsc`).

### Sequencing
The credential + login are true immediately on apply; trusted_root offline-verify is true once cloud-init writes the pinned root to the host. No soak-gated ADR status change (WARN→ENFORCE is the separate follow-up, not this ADR amendment).

## Risks & Sharp Edges
- A plan whose `## User-Brand Impact` section is empty/placeholder fails deepen-plan Phase 4.6 — it is filled above.
- **Fresh-host vs running-host validation:** the running host may have a cached image or a pre-applied `docker login` masking the break. Validate on a genuinely fresh/uncached host (or `docker logout` + prune first), not just the running host — otherwise the fail-closed pull looks fixed when it isn't.
- **`--network host` REJECTED (Design A) in favour of the sandboxed Design B** — its real cost is host-loopback exposure (inngest/redis/webhook), not egress (M1), and it reverses the ADR-082 container-egress invariant. Design B adds `ghcr.io` to the container allowlist instead. Do NOT add sigstore/rekor/fulcio/TUF to any allowlist — the pinned trusted-root exists precisely so they stay unreachable.
- **Circular-trust (H1):** never `COPY` `trusted_root.json` into the deploy image — that image is the artifact under verification. Source it via cloud-init `write_files` from the committed repo file.
- **HIGH — cloud-init metadata leak (security-sentinel #1):** the GHCR token must be fetched at boot via `doppler secrets get` (using the ambient `DOPPLER_TOKEN`), NEVER `templatefile`-interpolated into user-data — interpolation lands it in Hetzner instance metadata + `cloud-init-output.log`.
- **HIGH — trusted-root silent staleness (security-sentinel #2):** a pinned root that outlives sigstore's rotation windows fail-closes every deploy under ENFORCE. A CI expiry gate (fail within N days) is required and must land before the ENFORCE flip. Pinning also disables TUF revocation propagation (record the trade-off).
- **Credential-expiry SPOF (M2):** once the host pull is authenticated, EVERY deploy + fresh boot hard-depends on a valid GHCR credential. A lapsed PAT fail-closes the whole fleet; a stale `config.json` on a weeks-running host is why the per-deploy login (Phase 3) must rewrite it each run, and why a PROACTIVE expiry alarm (not just reactive pull-failure) is required.
- **Telemetry mechanism (H2):** the SENTRY_*-before-verify fix is NOT free — it requires a NEW early Doppler fetch (Phase 3) because the existing download runs after verify. Without it the fix is prose, not code.
- **Deprecated-flag drift:** pin the exact 3.x flag set against the SHA-pinned cosign container via `--help` at Phase 0; do not trust docs alone (`--new-bundle-format` default and `--offline` deprecation semantics vary by minor version).
- **Telemetry ordering is load-bearing for the ENFORCE gate:** if `SENTRY_*` remain unset at verify time, the soak that gates the flip observes nothing — a green-looking WARN with an invisible failure rate. Assert the ordering.
- **Auto-apply sequencing:** the `GHCR_READ_TOKEN` `TF_VAR_*` (no default) must be in Doppler `prd_terraform` before the `*.tf` edit merges, or the auto-applied infra root fails the whole apply (resolves every root var before `-target` pruning).
- **PAT person-dependency:** a fine-grained PAT tied to a human account rots when that human leaves — prefer a machine/bot account or the App-installation path if security review requires it.
- cosign reads registry auth via go-containerregistry from `~/.docker/`; if D1 chooses a `credsStore` helper config (it won't by default), the naive mount breaks (helper binary absent in the cosign container) — keep it a static `auths` entry.

## Test Scenarios
- Mock-cosign (`ci-deploy.test.sh`): verify the new flag set appears in the traced `docker run` argv (`--trusted-root`, `--offline=true`, `--new-bundle-format=false`, `-v …config.json`, egress path); WARN MOCK_COSIGN_VERIFY_FAIL still does not block; ENFORCE still blocks (load-bearing); inspect-no-digest fallback unchanged.
- Ordering: a test/assertion that `SENTRY_*` are resolvable before `verify_image_signature` (telemetry not dark).
- Phase 0 live probe (offline verify of the real signed digest) — evidence in spec/PR body, not a CI test.

## Out of Scope (do NOT do here)
- The `IMAGE_VERIFY_MODE` default `warn`→`enforce` flip (separate follow-up, gated on a clean WARN soak).
- Broad refactor of the deploy env-load ordering beyond what Phase 4 needs.

## Open Code-Review Overlap
None found (no open `code-review`-labelled issue references `ci-deploy.sh`, `cloud-init.yml`, `model.c4`, or ADR-082 at plan time — re-check at deepen-plan via the `gh issue list --label code-review` sweep).

## Sources (cosign 3.x offline verification research)
- Sigstore — Verifying Signatures: https://docs.sigstore.dev/cosign/verifying/verify/
- Cosign v3 announcement (new-bundle-format, --trusted-root, --signing-config): https://blog.sigstore.dev/cosign-3-0-available/
- Offline / air-gapped cosign verification (trusted_root.json via `cosign initialize`, `--offline=true --new-bundle-format=false --trusted-root`): https://some-natalie.dev/blog/cosign-disconnected/
- cosign CHANGELOG (v3.1.1 deprecations, removed in v4): https://github.com/sigstore/cosign/blob/main/CHANGELOG.md
- TUF-CDN reach even with local key (motivates pinned trusted-root): https://github.com/sigstore/cosign/issues/4550
