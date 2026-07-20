# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-07-fix-zot-doppler-registry-isolation-plan.md
- Status: complete

### Errors
None. CWD verified; branch confirmed non-main; all four deepen-plan review agents completed; Doppler provider capabilities verified against DopplerHQ provider source + official docs.

### Decisions
- Isolation approach: standalone ENVIRONMENT `registry` inside the existing `soleur` project (option b), NOT a dedicated project. Uses `doppler_environment` (basic Project-Structure resource) — avoids the paid config-inheritance feature this workspace lacks (the feature that sank `doppler_config.prd_ghcr` at apply in #6067). New environment gets its own root config holding only the 2 ZOT tokens = true isolation, while keeping `--project soleur` everywhere.
- A `prd` branch config can never isolate (branch configs inherit the environment root unless the secret is deleted) — hence the boundary must not share the prd root.
- Highest-value deepen enhancement: convert isolation into a cloud-init BOOT-TIME self-assertion run under the host's actual token (count==2 AND both ZOT_*, exit 1 before `docker run`) — closes the fail-open gap that every prior signal has on an over-scoped token.
- Phase-0 go-condition: `terraform plan`-clean is insufficient to pick PRIMARY (the #6067 limit is apply-time tier, not plan error) — PRIMARY requires an operator-acked real create+destroy apply; default FALLBACK otherwise.
- Scope discipline: #6122 stays OPEN; identical bug in prd_git_data/prd_kb_drift_walker/prd_cla/prd_ghcr deferred to a follow-up audit issue (Ref, not Closes). Security review flags prd_cla (and possibly prd_git_data) as LIVE over-reads now → file as P1, triaged by provisioning status.

### Components Invoked
- Skill soleur:plan → soleur:deepen-plan
- context7 (Doppler config-inheritance model) + GitHub API (DopplerHQ/terraform-provider-doppler docs)
- Research: learnings-researcher, git-history-analyzer
- Deepen review: security-sentinel, architecture-strategist, spec-flow-analyzer, user-impact-reviewer
- Deepen hard gates verified: User-Brand Impact, Observability (ssh-free), PAT-shaped-var, UI-wireframe, downtime, precedent-diff
