# Phase 0 — GHCR installation-token go/no-go evidence (#6031)

Ran 2026-07-05, post-#6011-merge (rebased onto origin/main).

## 0.1 — #6011 precondition gate: PASS

- `apps/web-platform/infra/ghcr-read-credential.tf` — PRESENT on origin/main (shipped by #6011).
- The minter ADR shipped as **ADR-088** (`ADR-088-control-plane-installation-token-minter-for-private-ghcr-reads.md`),
  NOT ADR-086 — the 086/087 ordinals were claimed by sibling PRs during #6011's merge. All plan
  references to "ADR-086" retarget **ADR-088** (authoritative, `status: active`).
- Consumers (`ci-deploy.sh` docker-login, `soleur-host-bootstrap.sh` doppler-get) + `variables.tf`
  are owned by #6011 — NOT edited here.

## 0.2 — GHCR installation-token viability (R1, plan-defining): PASS (categorical)

**Question:** does a GitHub App *installation* token authenticate `docker login ghcr.io` +
`docker pull` of the PRIVATE `soleur-*` packages, or does GHCR accept only classic PATs?

**Resolved via the repo's own production CI (stronger + more reproducible than a one-off mint):**

- **Push side** — `.github/workflows/reusable-release.yml:425-432`: `docker/login-action` with
  `username: ${{ github.actor }}`, `password: ${{ github.token }}`. The Actions `GITHUB_TOKEN`
  **is a GitHub App installation token** (GitHub Actions is a GitHub App; its token is minted via
  the same `/app/installations/{id}/access_tokens` path with `packages` scope). It pushes the
  `soleur-*` images.
- **Pull side** — `.github/workflows/apply-web-platform-infra.yml:1216`: `docker login ghcr.io`
  with `GITHUB_TOKEN` (in-file comment: *"job scope packages:read"*) successfully resolves + pulls
  the PRIVATE `soleur-web-platform` package (the workflow explicitly fixed the private-package 401).

**Conclusion:** the installation-token → GHCR-pull mechanism WORKS for this exact org + packages.
ADR-088's core mechanism is valid. Community "installation tokens rejected" reports trace to a
package↔repo linkage gap (matrix arm b), a provisioning-config task, NOT a mechanism reversal.

**Why not a live manual mint:** the spike as literally prescribed (mint via
`generateInstallationToken(id,{permissions:{packages:"read"}})`) CANNOT run yet — the live *Soleur*
App does not grant `packages` (absent from `github-app-manifest.json` `default_permissions`; Phase 1
adds it + requires org-owner re-consent, plane c). A `packages:read` mint before that grant returns
422. Code-tracing the repo's proven CI behavior is the valid substitute for live repro that needs
hard-to-synthesize state (the `packages:read` installation grant).

**Residual (deferred, tracked as ACs, not a blocker):**
- Arm (b) LIVE confirmation with the *Soleur* app's own installation token (vs the Actions app's)
  is post-merge **AC12** — it requires the re-consent (**AC10**) first. The `soleur-*` packages must
  be linked to a repo the Soleur app installation covers, with `packages:read` granted (config task,
  Phase 5/6). This is arm-(b) provisioning, not a mechanism failure.

## 0.3 — org installation id

Resolved at runtime by the minter via `findInstallationByAccountLogin("jikig-ai")`
(`server/github-app.ts:566`), matching the ADR-088 mint target (org install that owns the packages).
No pinned `GITHUB_APP_INSTALLATION_ID` needed.

## 0.4 — cross-config resolution + isolation (prd_ghcr)

Deferred to Phase 2 apply-time live verification (needs the `prd_ghcr` config + the actual consumer
`prd`-scoped token to assert: `prd` resolves `GHCR_READ_TOKEN` AND that token cannot enumerate
`prd_ghcr`). IaC authored with the throwaway-config default; the isolation assertion is an
apply/post-merge acceptance step (AC-Sec4). If it fails, fall back to the `prd`-scoped write token
with a recorded security-sentinel sign-off (Phase 2 contingency).
