# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-30-infra-deny-ghcr-on-web-hosts-plan.md
- Status: complete
- Plan artifact: complete (selector=branch)

### Errors
- None blocking. Precondition 2 verified: web-2 pulls cosign from gcr.io since 02:12Z 2026-09-30; ci-deploy.sh hash on web-2 matches repo; zero IMAGE_VERIFY_FAIL/cosign_absent in 3d. Issue's literal IMAGE_VERIFY-ref wording is unsatisfiable as written (ref= is the app image).

### Decisions
- Running hosts delivered via existing TF resources in new secret-free provisioner blocks (web-1: zot_consumer_probe_install; web-2: deploy_pipeline_fix_web2); cloud-init for fresh hosts.
- ghcr_blocked evidence = per-deploy GHCR_DENY marker in ci-deploy.sh (no periodic heartbeat reaches both hosts) — logged in decision-challenges.md.
- PR body uses `Ref #9169`; close only after applies green + GHCR_DENY ghcr_blocked=1 from both hosts in Better Stack.
- cloud-init-registry.yml untouched (byte change forces registry replace).
- Container-side GHCR reachability + docker.pkg.github.com deferred to #9275.

### Components Invoked
- soleur:plan, soleur:plan-review, soleur:deepen-plan + research/review agents (see plan Enhancement Summary).
- Post-plan re-probe (lead): #9169/#9275 no linked/open PRs; anchor probe: only #6778 touches preflight-discoverability-test.test.ts (baseline-count overlap, not same scope).
