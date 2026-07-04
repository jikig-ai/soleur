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

## Overview

The supply-chain image-signing + WARN-mode deploy-path verify shipped earlier (the "#5933 Item 4" work; running-host half in ci-deploy.sh, keyless signing in `reusable-release.yml`, dual-path amendment recorded in ADR-082). The WARN verify is safe (never blocks a deploy) but live validation on 2026-07-04 (dispatched release web-v0.188.1, run 28705048144, signing SUCCEEDED) found it will not actually PASS on the real host. This plan makes it PASSable — authenticated against the now-**private** GHCR package and verifying fully **offline** with the cosign 3.x non-deprecated flag set — while remaining in WARN.

Grounding research this session surfaced that the fix is **materially larger than the issue's two-bullet framing** ("both in ci-deploy.sh"). Three root problems, only one of which is a lone `--offline` flag swap:

1. **No GHCR credential exists anywhere in the repo.** The host `docker pull` (`ci-deploy.sh:909` app, `:1366` inngest, plus the fresh-boot pulls in `cloud-init.yml`) is an **anonymous** pull that worked only while the package was public. There is no `docker login`, no `~/.docker/config.json` provisioning, and no `read:packages` token in Doppler (Explore-agent sweep, confirmed against `variables.tf`, `cloud-init.yml`, git history). So the cosign container has no host credential to "inherit" — the issue's premise that the host has credentials the container doesn't inherit is **false**; the credential must be *created*. This also means the **host pull itself is now fail-closed** for any uncached private tag (every deploy pulls a new tag; a fresh web-2 boot per #5274 cannot come up at all) — a higher-severity break than the WARN verify.
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

- **D1 — Credential type & ownership.** A single `read:packages` credential scoped to the one package. Options: (a) fine-grained PAT on a **machine/bot account** (simplest; static Doppler secret; no bash JWT mint) vs. (b) **GitHub App installation token** (aligns with `hr-github-app-auth-not-pat`; the App private key is *already* in Doppler `prd` via `github-app.tf`, but minting on the host needs RS256-JWT + token-exchange in bash, and the key is not in the ambient webhook env until after the Doppler download). **Recommendation:** scoped fine-grained PAT on a machine account, recorded in the ADR as a **deliberate, narrow exception** to `hr-github-app-auth-not-pat` (rationale: avoid a headless bash JWT-mint / minimize live credential surface; single-package read-only, revocable). Route to `security-sentinel` + `infra-security` for the final call. A user-account PAT (person-dependency) is the anti-pattern to avoid.
- **D2 — Scope: include the host pull fix.** CONFIRMED IN SCOPE. One `docker login ghcr.io` writing `/home/deploy/.docker/config.json` fixes both the host pull (`:909`, `:1366`, fresh-boot) and the cosign container (mount that config). Cosign-container-only would ship a still-broken fail-closed pull.
- **D3 — Cosign container egress to ghcr.io.** Options: (a) add **only** `ghcr.io` to `cron-egress-allowlist.txt` (permanent, narrow, but widens the *app* container's steady-state egress surface too), or (b) run the cosign `docker run` with `--network host` (scoped to the verify invocation only; cosign uses host egress which already reaches GHCR; sigstore stays unreachable which is fine because the root is local). trusted-root being local means sigstore hosts are NEVER needed either way. **Lean:** `--network host` (surgical to the verify path, no steady-state app-egress change) — but confirm with `infra-security` that `--network host` on a SHA-pinned, single-purpose cosign container is acceptable vs. the allowlist widening. deepen-plan Phase 4.4 precedent-diff.
- **D4 — trusted_root.json shipping.** CONFIRMED: **commit `trusted_root.json` to the repo** (reviewable/diffable) and **bake it into the deploy image** at build (`COPY`), mounted into the cosign container at `--trusted-root`. Do NOT `cosign initialize` at build (reaches TUF CDN → non-hermetic, defeats the offline posture). Rotation (~yearly, on sigstore root rotation) via a committed refresh script run deliberately in a PR. Provenance note + rotation cadence comment required.
- **D5 — credential minting automation.** `automation-status: UNVERIFIED — /work MUST run a Playwright attempt before any operator handoff.` Fine-grained PAT / machine-account creation is a GitHub dashboard flow under an authenticated session — presumptively Playwright-automatable until a real attempt reaches a named human gate (password sudo-mode / 2FA). Per `hr-block-pr-ready-on-undeferred-operator-steps` + the never-defer-operator-actions memory, wire the value into Doppler via TF and confirm in-session; do not defer as a checklist bullet.

## Implementation Phases

### Phase 0 — Preconditions (verify before coding)
- [ ] Confirm cosign v3.1.1 offline flag set against the **pinned cosign container** (not docs alone): `docker run --rm $COSIGN_IMAGE verify --help` and confirm `--offline`, `--trusted-root`, `--new-bundle-format` are all recognized; capture output into the plan/spec (CLI-verification gate #2566). Confirm `--offline` still runs (deprecated-not-removed) as a fallback.
- [ ] Generate `trusted_root.json` for the sigstore public-good instance on a connected machine (`cosign initialize`; grab `~/.sigstore/root/tuf-repo-cdn.sigstore.dev/targets/trusted_root.json`) and confirm a local offline verify of the **already-signed** web-v0.188.1 digest succeeds with `--offline=true --new-bundle-format=false --trusted-root <file>` + the existing identity-regexp/OIDC-issuer + a valid GHCR credential. This is the load-bearing end-to-end probe — do it before writing the shell.
- [ ] Confirm the signing identity regexp (`COSIGN_IDENTITY_REGEXP`, `ci-deploy.sh:41`) still matches the signature on the live digest (no drift since #5933).
- [ ] Confirm `DOPPLER_TOKEN` is in the ambient env at verify time (it is — `cloud-init.yml:312` `/etc/default/webhook-deploy`) so a pre-verify `doppler secrets get` for the GHCR token + `SENTRY_*` is feasible.

### Phase 1 — Credential provisioning (IaC)
- [ ] Mint the scoped `read:packages` credential (Decision D1) — `/work` attempts Playwright first (D5), else routes to the named human gate reached.
- [ ] Add `doppler_secret` resource(s) for `GHCR_READ_TOKEN` (+ `GHCR_READ_USER` if PAT) to a new/extended `*.tf` under `apps/web-platform/infra/`, mirroring the `github-app.tf` `doppler_secret` precedent; provision to **both dev and prd** configs per the repo pattern. No default on the `TF_VAR_*` (`hr-tf-variable-no-operator-mint-default`); confirm the value is present in `prd_terraform` before the auto-applied infra root runs (sequencing per the operator-mint-vs-auto-applied-IaC Sharp Edge — a `*.tf` edit triggers `apply-web-platform-infra.yml`).
- [ ] Add the host `docker login ghcr.io` to **cloud-init** (fresh-boot parity, `hr-fresh-host-provisioning-reachable-from-terraform-apply`) writing `/home/deploy/.docker/config.json` (owned `deploy:deploy`, `chmod 600`) from the Doppler-provided token, via `--password-stdin` (never argv). Ensure `runcmd` ordering places it before the first pull.

### Phase 2 — trusted_root.json (repo + image build)
- [ ] Commit `trusted_root.json` under `apps/web-platform/infra/` (e.g. `cosign-trusted-root.json`) with a header/NOTE documenting provenance (which TUF root, capture date) and the rotation cadence.
- [ ] Bake it into the deploy image (`COPY` in the web-platform Dockerfile) at a stable path, OR (if simpler and firewall-safe) place it on the host via cloud-init `write_files`. Choose the path that keeps the cosign `--trusted-root` mount source stable across fresh + running hosts.
- [ ] Add a committed refresh script + note (deliberate-PR rotation, not runtime fetch).

### Phase 3 — Rework the cosign verify invocation (ci-deploy.sh)
- [ ] In `verify_image_signature` (`:487`): before the cosign `docker run`, ensure `/home/deploy/.docker/config.json` exists (host login from Phase 1) OR construct a scoped `DOCKER_CONFIG` dir from a pre-verify `doppler secrets get GHCR_READ_TOKEN`.
- [ ] Replace `docker run --rm "$COSIGN_IMAGE" verify --offline …` with the 3.x offline set + auth + egress:
  ```sh
  docker run --rm --network host \
    -v /home/deploy/.docker/config.json:/root/.docker/config.json:ro \
    -v "$TRUSTED_ROOT_PATH":/trust/trusted_root.json:ro \
    "$COSIGN_IMAGE" verify \
    --offline=true --new-bundle-format=false \
    --trusted-root=/trust/trusted_root.json \
    --certificate-identity-regexp="$COSIGN_IDENTITY_REGEXP" \
    --certificate-oidc-issuer="$COSIGN_OIDC_ISSUER" \
    "$repo_digest"
  ```
  (Exact `--network` vs allowlist per D3; exact flag set pinned by the Phase 0 probe.)
- [ ] Fix the host pull auth: ensure `docker pull "$IMAGE:$TAG"` (`:909`, `:1366`) runs after the host `docker login` (Phase 1) — the login makes the private pull succeed.
- [ ] Correct the stale code comment at `:499-501` ("The app image is public GHCR, so the cosign container needs no registry auth") and `:34-35` header.
- [ ] Preserve the WARN/ENFORCE semantics exactly — telemetry fires identically, mode branch unchanged, ENFORCE default stays `warn`.

### Phase 4 — Make WARN telemetry reach Sentry at verify time
- [ ] Ensure `SENTRY_INGEST_DOMAIN` / `SENTRY_PROJECT_ID` / `SENTRY_PUBLIC_KEY` are set **before** `verify_image_signature` runs (options: a scoped pre-verify `doppler secrets get` of the three vars, or move the env-file resolution earlier). Without this the `verify_result` Sentry event never fires and the ENFORCE soak gate is blind.
- [ ] Add a **loud, no-SSH** failure event for the host **pull** itself (currently an anonymous-pull-denied surfaces only in host docker logs) — an authenticated-pull failure on a private image must be Sentry/Better Stack diagnosable (`hr-no-ssh-fallback-in-runbooks`, observability-coverage-reviewer §4.6).

### Phase 5 — C4 + ADR + tests
- [ ] `model.c4:238-240`: change "Public GHCR registry" → private, note the host authenticates via `read:packages`. Run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts`.
- [ ] Amend **ADR-082** (`## Decision` + `## Alternatives Considered`): private-visibility credential model, the D1 scoped-credential exception to `hr-github-app-auth-not-pat` with rationale, and the committed-`trusted_root.json` offline-verify decision.
- [ ] Extend `ci-deploy.test.sh` mock-cosign handler for the new flag set + a mounted-config/egress trace assertion; keep the existing WARN-never-blocks / ENFORCE-blocks / inspect-fallback tests green (they must pass identically).
- [ ] File the WARN→ENFORCE flip as a tracked follow-up issue (re-eval: verify observed PASSING with no `verify_result` failures over a soak) so WARN-forever is not the silent resting state.

## Files to Edit
- `apps/web-platform/infra/ci-deploy.sh` — cosign invocation (`:487-524`), flag set, config/trusted-root mounts, `--network`, host-login ordering before pulls (`:909`, `:1366`), telemetry ordering (`:916` vs `:992`), stale comments (`:34-35`, `:499-501`).
- `apps/web-platform/infra/cloud-init.yml` — host `docker login ghcr.io` writing `/home/deploy/.docker/config.json`; possibly `write_files` for trusted_root.json.
- `apps/web-platform/infra/<new-or-existing>.tf` — `doppler_secret` for `GHCR_READ_TOKEN` (+ user), dev+prd; `variables.tf` for the `TF_VAR_*` (no default).
- `apps/web-platform/infra/cron-egress-allowlist.txt` — only if D3 chooses the allowlist path (add `ghcr.io`).
- `apps/web-platform/Dockerfile` (or infra) — `COPY` trusted_root.json into the deploy image (D4).
- `apps/web-platform/infra/cosign-trusted-root.json` — NEW, committed pinned root + provenance/rotation note.
- `apps/web-platform/infra/ci-deploy.test.sh` — mock-cosign flag-set + mount/egress trace assertions.
- `knowledge-base/engineering/architecture/diagrams/model.c4` — `ghcr` element description (`:238-240`).
- `knowledge-base/engineering/architecture/decisions/ADR-082-fresh-web2-boot-observability.md` — amendment.

## Files to Create
- `apps/web-platform/infra/cosign-trusted-root.json` (committed pinned root).
- (optional) `apps/web-platform/infra/refresh-cosign-trusted-root.sh` (deliberate-PR rotation helper).

## Acceptance Criteria

### Pre-merge (PR)
- [ ] The cosign `docker run` in `ci-deploy.sh` uses the **non-deprecated** 3.x offline flag set (`--offline=true --new-bundle-format=false --trusted-root=…`, exact set pinned by the Phase 0 `--help` probe) — no bare deprecated `--offline`; `git grep -n 'cosign' ci-deploy.sh` shows the mounted `-v …/config.json` and trusted-root, and the resolved egress path (`--network host` or allowlisted ghcr.io).
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
logs:
  where: "journald (logger -t ci-deploy) + Sentry"
  retention: "journald host-local; Sentry per project retention"
discoverability_test:
  command: "gh/Sentry query for op=image-verify events after a signed deploy; deploy-state webhook read"
  expected_output: "verify_result=ok (or no failure event) on a real signed deploy; no ssh"
```

## Architecture Decision (ADR/C4)

### ADR
Amend **ADR-082** (dual-path verify decision it already owns): add (a) the private-visibility GHCR credential model (`read:packages`, Doppler-threaded, host `docker login`), (b) the deliberate scoped exception to `hr-github-app-auth-not-pat` (rationale: no headless bash JWT-mint / minimize live credential surface; single-package read-only), (c) the committed+baked `trusted_root.json` offline-verify decision (vs `cosign initialize`-at-build, rejected as non-hermetic). New ADR NOT warranted — this is the same decision ADR-082 scopes. (ADR ordinal N/A — amendment, not a new record.)

### C4 views
Checked all three `.c4` files. Relevant elements: `ghcr` system (`model.c4:238`, external), `sigstore` system (`:246`), `hetzner → ghcr` pull edge (`:309`), `hetzner → sigstore` verify edge (`:312`). Change: `ghcr` description "Public GHCR registry" → private + "host authenticates via read:packages". The `hetzner → ghcr` edge already exists (no new edge). The `hetzner → sigstore` verify edge remains accurate (offline, now via pinned trusted-root — description tweak optional). No new external actor/system/relationship is introduced (the credential is an attribute of the existing pull edge, not a new element). Run `c4-code-syntax.test.ts` + `c4-render.test.ts` after edit.

### Sequencing
The credential + login are true immediately on apply; trusted_root offline-verify is true once baked. No soak-gated ADR status change (WARN→ENFORCE is the separate follow-up, not this ADR amendment).

## Risks & Sharp Edges
- A plan whose `## User-Brand Impact` section is empty/placeholder fails deepen-plan Phase 4.6 — it is filled above.
- **Fresh-host vs running-host validation:** the running host may have a cached image or a pre-applied `docker login` masking the break. Validate on a genuinely fresh/uncached host (or `docker logout` + prune first), not just the running host — otherwise the fail-closed pull looks fixed when it isn't.
- **`--network host` on the cosign container** gives it full host egress for the verify window — confirm with infra-security it's acceptable vs. narrowly allowlisting `ghcr.io` (D3). Either way, do NOT add sigstore/rekor/fulcio/TUF hosts to any allowlist — the whole point of the pinned trusted-root is that they stay unreachable.
- **Deprecated-flag drift:** pin the exact 3.x flag set against the SHA-pinned cosign container via `--help` at Phase 0; do not trust docs alone (`--new-bundle-format` default and `--offline` deprecation semantics vary by minor version).
- **Telemetry ordering is load-bearing for the ENFORCE gate:** if `SENTRY_*` remain unset at verify time, the soak that gates the flip observes nothing — a green-looking WARN with an invisible failure rate. Assert the ordering.
- **Auto-apply sequencing:** the `GHCR_READ_TOKEN` `TF_VAR_*` (no default) must be in Doppler `prd_terraform` before the `*.tf` edit merges, or the auto-applied infra root fails the whole apply (resolves every root var before `-target` pruning).
- **PAT person-dependency:** a fine-grained PAT tied to a human account rots when that human leaves — prefer a machine/bot account or the App-installation path if security review requires it.
- cosign reads registry auth via go-containerregistry from `~/.docker/config.json`; if D1 chooses a `credsStore` helper config (it won't by default), the naive mount breaks (helper binary absent in the cosign container) — keep it a static `auths` entry.

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
