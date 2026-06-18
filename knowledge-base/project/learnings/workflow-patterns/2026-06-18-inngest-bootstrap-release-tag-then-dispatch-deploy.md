---
title: "Inngest bootstrap-image release is a 4-step tag→build→dispatch→pin flow — the build does NOT auto-deploy"
date: 2026-06-18
category: workflow-patterns
module: apps/web-platform/infra
tags: [inngest, deploy, release, vinngest, cloud-init, ci-deploy, no-ssh]
issue: 5547
pr: 5550
---

# Learning: releasing a new inngest-bootstrap image is a 4-step coordinated flow

## Problem

After merging a fix to `inngest-bootstrap.sh` (#5547), I needed to verify it
live (AC9: a real `deploy inngest` installs Redis + the durable ExecStart on
the prod host). I assumed pushing the `vinngest-vX.Y.Z` tag would
build-AND-deploy in one shot. It did not — `build-inngest-bootstrap-image.yml`
only **builds + pushes** the OCI image; the deploy stayed un-triggered, and the
deploy-status webhook kept showing the *previous* (web-platform) deploy.

## Solution — the actual 4-step flow

A new inngest-bootstrap image (carrying a changed `inngest-bootstrap.sh`,
`inngest-redis.*`, or a bumped `inngest_cli_version`) reaches the prod host via
FOUR coordinated steps. None of them are SSH (`hr-no-ssh-fallback-in-runbooks`):

1. **Push an ANNOTATED `vinngest-vX.Y.Z` tag** on the commit that carries the
   change. The repo config forces annotated tags — a bare `git tag <name> <sha>`
   fails `fatal: no tag message?`. Use:
   ```bash
   git tag -a vinngest-v1.1.16 <main-sha> -m "inngest-bootstrap v1.1.16: <what>"
   git push origin vinngest-v1.1.16
   ```
   This fires `build-inngest-bootstrap-image.yml` (`on: push: tags: vinngest-v*`),
   which builds + SHA-verifies + pushes `ghcr.io/jikig-ai/soleur-inngest-bootstrap:v1.1.16`.
   **It does NOT deploy.**

2. **Bump the cloud-init pin IN LOCKSTEP** (`apps/web-platform/infra/cloud-init.yml`,
   the 3 `soleur-inngest-bootstrap:vX.Y.Z` refs). `cloud-init-inngest-bootstrap.test.sh`
   AC6 asserts **pin == the semver-max published `vinngest-v*` git tag**. Pushing
   the tag without the pin bump turns `main` red (pin v1.1.15 ≠ latest tag v1.1.16);
   bumping the pin *before* the tag exists also fails AC6 on the bump PR's own CI.
   So: **push the tag first** (per `hr-tagged-build-workflow-needs-initial-tag-push`),
   then open + merge the pin-bump PR — the bump PR passes AC6 because the tag now
   exists. A brief AC6-red window on `main` exists between the two; the bump PR
   closes it.

3. **Dispatch the deploy explicitly** — `deploy-inngest-image.yml` is
   `workflow_dispatch`-only (its `push: branches: [main]` trigger exists ONLY to
   surface it in the Actions UI; the deploy job is `if: github.event_name ==
   "workflow_dispatch"`). The build never chains into it.
   ```bash
   gh workflow run deploy-inngest-image.yml -f tag=v1.1.16
   ```
   This POSTs `deploy inngest ghcr.io/jikig-ai/soleur-inngest-bootstrap v1.1.16`
   to the prod deploy webhook → the on-host `ci-deploy.sh` `case "inngest")` pulls
   + extracts + runs the bootstrap (NO SSH — the old runbook's
   `ssh deploy@<host>` form is stale and violates the no-SSH rule).

4. **Verify via the deploy-status webhook (no SSH)** — a single authenticated GET:
   ```bash
   WS=$(doppler secrets get WEBHOOK_DEPLOY_SECRET -p soleur -c prd_terraform --plain)
   CID=$(doppler secrets get CF_ACCESS_CLIENT_ID -p soleur -c prd_terraform --plain)
   CSEC=$(doppler secrets get CF_ACCESS_CLIENT_SECRET -p soleur -c prd_terraform --plain)
   HMAC=$(printf '' | openssl dgst -sha256 -hmac "$WS" | sed 's/.*= //')
   curl -fsS -H "X-Signature-256: sha256=${HMAC}" \
     -H "CF-Access-Client-Id: ${CID}" -H "CF-Access-Client-Secret: ${CSEC}" \
     "https://deploy.soleur.ai/hooks/deploy-status" | jq '{component, tag, reason, exit_code}'
   ```
   Expect `{component:"inngest", tag:"v1.1.16", reason:"success", exit_code:0}`.
   `reason:"success"` = durable backend live; `reason:"success_degraded_durability"`
   = the SQLite fail-safe fired (Redis not ready, #5547).

## Key Insight

- **Build ≠ deploy.** The OCI image build and the host deploy are two separate
  workflows; the deploy is a manual `workflow_dispatch`. Verifying any
  bootstrap/CLI change live requires step 3 explicitly — a green build is not a
  deploy.
- **The tag must precede the cloud-init pin bump** (AC6 chicken-and-egg). Tag →
  build → pin-bump-PR, in that order.
- **Use `deploy.soleur.ai` as the deploy-status host.** `APP_DOMAIN_BASE` in
  Doppler `prd_terraform` read empty under rapid sequential `doppler secrets get`
  (and a presence-check `&& echo ""` gives a misleading non-zero length); the
  canonical host is documented in `postmerge` Production Debugging — hardcode it
  rather than interpolating a flaky fetch into the URL.

## Session Errors

1. **Assumed the image build auto-fires the deploy.** — Recovery: `gh workflow
   run deploy-inngest-image.yml -f tag=v1.1.16` (the deploy is workflow_dispatch-only).
   **Prevention:** documented as step 3 of the release flow here + in
   `inngest-server.md`; the build workflow only builds+pushes.
2. **`git tag vinngest-v1.1.16 <sha>` → `fatal: no tag message?`.** — Recovery:
   `git tag -a … -m`. **Prevention:** the runbook now prescribes `-a -m`.
3. **`APP_DOMAIN_BASE` (Doppler prd_terraform) read empty → deploy-status URL
   `deploy.` → "Could not resolve host" (monitor fetch-error).** — Recovery: used
   the canonical `deploy.soleur.ai`. **Prevention:** Key Insight above + the
   runbook hardcodes the host.
4. **AC6 drift-guard turns `main` red if the cloud-init pin and the latest
   vinngest tag disagree.** — Recovery: pin-bump PR #5555 after the tag push.
   **Prevention:** step 2 documents the tag-first ordering.
5. **`session-state.md` (untracked one-shot scratch) blocked `cleanup-merged`.** —
   Recovery: `rm` it. **Prevention:** one-off; the next session's idempotent
   cleanup also handles it.
