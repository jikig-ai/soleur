# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-14-fix-deploy-ghcr-pull-denial-recovery-plan.md
- Status: complete

### Errors
None blocking. Handled: iac-plan-write-guard false positive (resolved via iac-routing-ack opt-out; no new infra), deepen gate 4.8 PAT-shaped false positive (var.ghcr_read_token — sanctioned hr-github-app-auth-not-pat / ADR-088 carve-out), one cited path corrected.

### Decisions
- Root cause (structural): §1A (#6395) recovers only on `docker login` failure, but prod `image pull failed (auth_denied)` fires at `docker pull` — a cred can log in yet fail to pull. Fix recovers at the pull site (re-fetch prd PAT + relogin + retry once).
- Disproved issue's primary hypothesis: DOPPLER_TOKEN IS present + prd-scoped in deploy exec context; prd GHCR cred is a valid pull-capable PAT. Real gap = login-vs-pull capability split.
- Zero-operator delivery: fix ships as ci-deploy.sh edit, auto-applies to running hosts via existing HTTPS /hooks/infra-config path on merge.
- Review-driven revisions applied (helper returns login status; classifier gets stderr content; single recovery_stage-tagged event; relogin writes same GHCR_DOCKER_CONFIG cosign mounts; ADR-096 homes the contract; cloud-init boot-path parity deferred to follow-up).
- Threshold: aggregate pattern; no UI surface; no C4 topology change.

### Components Invoked
- Skills: soleur:plan, soleur:deepen-plan
- Agents: Explore, learnings-researcher, architecture-strategist, security-sentinel, observability-coverage-reviewer, code-simplicity-reviewer
- Tooling: gh, git
