---
title: Image signing + running-host deploy-path verify (#5933 Item 4, PR 2/2)
issue: 5933
lane: cross-domain
brand_survival_threshold: single-user incident
governing_adr: ADR-082
umbrella_plan: knowledge-base/project/plans/2026-07-03-feat-web2-absence-detector-image-pin-plan.md
status: implemented
created: 2026-07-04
---

# Spec: Image signing + running-host verify (#5933 Item 4, PR 2/2)

PR 2/2 of #5933. PR 1/2 (Item 1, per-host absence detector) shipped via #5970. Design + 4-agent
plan-review in the umbrella plan (see `umbrella_plan`); ADR-082 is the governing decision.

## Problem
The running web host pulls the app image by semver tag and runs it **unsigned** — a GHCR/typo-squat
substitution = full RCE on the host serving every user. The `host_scripts_content_hash` is a coherence
control, not authenticity.

## Goals
- **G1.** cosign-keyless-sign the released image digest in `reusable-release.yml` (offline-verifiable bundle).
- **G2.** cosign-verify on the **running-host deploy path** (`ci-deploy.sh`): resolve tag→digest, verify via
  a SHA-pinned cosign container (`--offline`, identity pinned to `reusable-release.yml@main/tags`), run the
  **verified digest** (not the tag; TOCTOU). WARN mode (never blocks); ENFORCE = soak-gated fast-follow.
- **G3.** Model `sigstore` in C4; amend ADR-082 Item 4.

## Non-Goals
- **NG1.** Fresh-host `cloud-init.yml` verify + `var.image_digest` pin → ride the #5274 cutover (web-2-only; not testable until web-2 boots).
- **NG2.** ENFORCE flip — a soak-gated fast-follow after one signed release deploys clean.
- **NG3.** Signing/verifying the inngest-bootstrap image (a separate content-carrier image, out of scope).

## Functional Requirements
- **FR1.** `reusable-release.yml`: `id-token: write` + pinned `sigstore/cosign-installer` + `cosign sign --yes …@${digest}`.
- **FR2.** `ci-deploy.sh` after the app pull: `verify_image_signature` resolves `docker inspect RepoDigests`
  (empty/multi → Sentry `inspect_failed`), verifies via pinned cosign container, runs the verified digest at
  plugin-seed + canary + production; WARN → `verify_result` Sentry event, no `final_write_state 1`; ENFORCE → abort keeping old container.
- **FR3.** Identity regexp `@(refs/heads/main|refs/tags/v[0-9].+)$` (NOT `refs/(heads|tags)/.+`).
- **FR4.** `sigstore` system + `github->sigstore` (sign) + `hetzner->sigstore` (verify) in C4; `model.likec4.json` regenerated.

## Acceptance Criteria
- [x] AC1: signing steps in `reusable-release.yml` (actionlint clean).
- [x] AC2: `ci-deploy.sh` verify + run-verified-digest at all three web-platform run sites; `bash -n` clean.
- [x] AC3: `ci-deploy.test.sh` 103/103 incl. WARN-does-not-block (verify + inspect) and ENFORCE-blocks (gate load-bearing).
- [x] AC4: identity regexp pinned to main/tags (grep-verified).
- [x] AC5: `sigstore` in C4; `c4-model-freshness` + `c4-render`/`c4-code-syntax` green (model regenerated).
- [x] AC6: ADR-082 Item 4 amended (dual-path rationale + verify-by-tag/tfvars/loose-identity rejections).
- [ ] AC7 (post-merge, auto): after the next release, `cosign verify --offline …:latest` exits 0 (a signed image exists); WARN verify observed clean → then the ENFORCE fast-follow.

## Delivery
`ci-deploy.sh` is a `terraform_data.deploy_pipeline_fix` trigger → `apply-deploy-pipeline-fix.yml` auto-applies
on merge. Signing (same PR) means the next release signs the image the next deploy verifies; WARN mode keeps
the transition (and any rollback to a pre-signing image) safe.

## Domain Review (carry-forward)
Engineering/Product/Legal from the umbrella brainstorm/plan. CLO OP1: BetterStack Vendor DPA pending signature (Item 1 follow-up, tracked).
