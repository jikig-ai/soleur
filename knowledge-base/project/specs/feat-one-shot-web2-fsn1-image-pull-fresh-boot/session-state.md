# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-13-fix-web-2-fsn1-fresh-boot-image-pull-plan.md
- Status: complete

### Errors
None. Two notes: (1) initial Write was blocked by the worktree guard and retried at the correct worktree path; (2) deepen-plan gate 4.8 (PAT-shaped) mechanically matched the pre-existing `var.ghcr_read_token` — reconciled as a false positive (ADR-088 GitHub-App-installation-minted read-only `packages:read` cred, which satisfies `hr-github-app-auth-not-pat`).

### Decisions
- Diagnose-then-fix, not fix-blind. The pull path is engineered to survive hel1→fsn1 (GHCR fallback + eu-central-zonal private net + DC-agnostic baked creds + host pulls bypass container egress firewall). Decisive evidence is the baked-DSN Sentry `tags.stage`+`detail`; Phase 0 pulls it in-session (no operator ask) and a deterministic decision matrix selects the fix branch.
- Premise corrections: #6090 is CLOSED (recurrence via #6393 `-replace`); "Better Stack SOLEUR_* markers" don't exist for weight-0 web-2 (Vector gated off by `web_colocate_inngest=false`) — boot channel is Sentry, and "ships logs" needs a real Vector-on-web-2 fix.
- Default root-cause candidate is Branch B (fresh hel1 zot volume → GHCR fallback), not A (expired-but-present token). §1A credential-fallback hardening (Doppler re-fetch on login failure, not only EMPTY) ships as durable fix regardless.
- Must-fix folded (P1-1): Phase-0 Sentry query widened from pull-stage enum to all stages; added Branch G for "pull OK, later fatal."
- Scope disciplined to web-2 only (P2-3): Phase 2 Vector install web-2-only, fail-open, sequenced after `:9000` bind; apply via existing no-SSH `web-2-recreate` scoped `-replace` (zero-downtime, web-2 serves zero traffic).

### Components Invoked
- Skills: soleur:plan, soleur:deepen-plan
- Agents: Explore, learnings-researcher, architecture-strategist
- Deepen gates: 4.5, 4.55, 4.6, 4.7, 4.8 (reconciled), 4.9 (n/a); precedent-diff + KB-citation integrity
