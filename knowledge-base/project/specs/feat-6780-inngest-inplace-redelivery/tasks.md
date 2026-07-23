---
feature: inngest-host-inplace-redelivery
issue: 6780
lane: single-domain
brand_survival_threshold: single-user incident
plan: knowledge-base/project/plans/2026-07-22-feat-inngest-host-inplace-redelivery-plan.md
---

# Tasks: in-place signed redelivery channel for the dedicated Inngest host (#6780)

> Contract-first ordering. HARD-N refer to the plan's "Plan-Review Hardening" section.
> Build is gated on the #6178 cutover for the host-side bake (HARD-11).

## Phase 0 — Preconditions & enumeration (verify, no code)
- [ ] 0.1 Enumerate the exact host-executed `*.sh` refresh-set on 10.0.1.40 vs web-host-only (OQ2).
- [ ] 0.2 Record host egress evidence: boot self-check already runs `doppler run --project soleur-inngest --config prd` → api.doppler.com + GHCR proven.
- [ ] 0.3 (HARD-12) Verify baked GHCR creds can pull the **config-bundle OCI repo** specifically (not just the bootstrap-image repo).
- [ ] 0.5 (DEEPEN-CORRECTION-1) Probe `cosign verify-blob` **keyless-offline** against the baked `/etc/soleur/cosign-trusted-root.json` on the pinned cosign image — confirm before choosing keyless over static-key (static-key is the documented fallback).
- [ ] 0.4 Audit `DEST_SPEC`/`FILE_MAP` gap in `infra-config-install.sh` for the refresh-set dests; note it's NOT baked in `cloud-init-inngest.yml` today.

## Phase 1 — ADR-135 + C4
- [ ] 1.1 Author `ADR-135-*.md` via `/soleur:architecture` (decision + alternatives + D-ZOT divergence + HARD-7 CI-compromise threat model + replace-only-TCB + isolated-project write-path). Re-verify next-free ordinal at ship.
- [ ] 1.2 Edit `.c4` (model/views/spec): CI signer (`#external`), config-artifact registry→host edge, refresh relationship. Run `c4-code-syntax.test.ts` + `c4-render.test.ts`.

## Phase 2 — CI build + cosign sign + publish (producer contract)
- [ ] 2.1 (DEEPEN-CORRECTION-1, keyless preferred) CI signs the bundle **keyless** (`cosign sign-blob`, Fulcio/Rekor at sign-time — CI has egress); the host verifies offline via `verify-blob --certificate-identity-regexp <config-workflow> --certificate-oidc-issuer … --trusted-root /etc/soleur/cosign-trusted-root.json` (baked). No static private key. **Fallback (only if 0.5 fails):** static keypair, private → `soleur/prd` as `COSIGN_CONFIG_SIGNING_KEY` (CI-only), public committed.
- [ ] 2.2 Workflow (or job in an existing `pull_request` workflow — NOT a temporary `workflow_dispatch`): package refresh-set + per-file sha256 manifest + a **signed** monotonic `VERSION` (HARD-2); sign; publish OCI artifact to **both zot + GHCR**.
- [ ] 2.3 The signing job behind a GitHub environment with a **non-empty required-reviewer set**, OIDC-scoped, protected branch (HARD-7); the config-signing workflow identity is pinned by the host's `COSIGN_IDENTITY_REGEXP`.

## Phase 3 — Promoted digest pointer + isolation self-check (contract)
- [ ] 3.1 `inngest-config-digest.tf` — `doppler_secret INNGEST_CONFIG_DIGEST` in `soleur-inngest/prd` (mirror `inngest-betterstack-token.tf`: copy into `soleur/prd_terraform` → verify read-only → apply).
- [ ] 3.2 Promotion writes the pointer via **`terraform apply` of the `doppler_secret`** (no standing CI write-token into the isolated project); distinct sign vs promote principal (HARD-6).
- [ ] 3.3 (DEC-FLOOR) Extend the boot isolation self-check regex (`cloud-init-inngest.yml:315-333`) to include `INNGEST_CONFIG_DIGEST`; set floor per DEC-FLOOR (dark-present → 6; cutover-only → keep 5, raise exact-set). Make the digest `doppler_secret` applied+verified a **precondition of the #6178 cutover provision**.
- [ ] 3.4 (HARD-9) Gate promotion on `pointer.version > baked-floor.version`.

## Phase 4 — Host verify+apply + timer/service + cosign pubkey (consumer; RIDES #6178 cutover)
- [ ] 4.1 `inngest-config-refresh.sh` (baked): resolve digest from Doppler → pull `@sha256` GHCR-direct → `cosign verify-blob --key <pub>` → verify per-file sha256 vs manifest → read signed VERSION (HARD-2) → monotonic gate vs `applied.version` (HARD-3/HARD-9, rejection-as-signal) → **stage-all-then-swap-all** via `infra-config-install.sh` (HARD-5) → advance `applied.version` only after last file.
- [ ] 4.2 (HARD-10) Explicit fail-closed on every gate; no inherited `set +e`/`|| true` on a decision.
- [ ] 4.3 (HARD-1) Ensure engine paths (this script, cosign binary, pubkey, units, `applied.version`) are excluded from `DEST_SPEC`/refresh-set.
- [ ] 4.4 (HARD-3) cloud-init seeds `applied.version` to the baked-floor version; create `/var/lib/inngest-config` + version file **`root:root`**.
- [ ] 4.5 systemd `.service` (`User=root`, HARD-4) + `.timer` (cadence per OQ3) + `OnFailure=` alarm; bake cosign binary + public key.
- [ ] 4.6 Add refresh-set dests to `DEST_SPEC` + `FILE_MAP` in lockstep (AC18); root-invoked-only, no webhook/sudoers import (HARD-12).

## Phase 5 — Off-box observability
- [ ] 5.1 Marker verbs via `inngest-boot-phone-home.sh`: `SOLEUR_INFRA_PULL_APPLIED version=… sha256= verify=ok`; `SOLEUR_INFRA_PULL_VERIFY_FAIL …`. Boot-floor marker distinguishable (`version=floor`, HARD-8).
- [ ] 5.2 Terraform: Better Stack **absence-heartbeat** monitor (grace window = OQ3 cadence); `OnFailure=` Sentry-Crons/Resend (mirror `cron-egress-alarm.sh`).
- [ ] 5.3 (HARD-8 + DEEPEN-CORRECTION-2) Off-box **drift comparator** as an **Inngest `cron-inngest-config-drift.ts`** (ADR-033, beside the 51 existing cron functions — reads Doppler pointer + latest Better Stack APPLIED marker → alarm on divergence beyond N windows). NOT a GH Actions cron.
- [ ] 5.4 Host state file `{applied_version, bundle_sha256, signer_keyid, per_file_sha256[], applied_ts, verify_result}` + `cat-…-state.sh`-style reader.

## Phase 6 — Tests + runbook
- [ ] 6.1 `inngest-config-refresh.test.sh` (mirror `inngest-host.test.sh`): AC10–AC19 (TCB exclusion, signed-version replay reject, positive apply, root ownership + fresh first-pull, set-atomic, per-arm fail-closed, round-trip verify, lockstep, drift comparator). Deterministic, no live prod writes.
- [ ] 6.2 Runbook (HARD-11): ship-a-host-script-change flow + **channel-live precondition** + promotion cadence + rotation recipe (leak → emergency replace).
- [ ] 6.3 Enroll AC9 as a soak follow-through (`scripts/followthroughs/`) — `/ship` Phase 5.5 gate.

## Exit
- [ ] PR body: `Ref #6780` (not Closes). `/review` → `/ship`. Close #6780 post-cutover with off-box marker evidence.
