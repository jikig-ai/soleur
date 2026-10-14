---
date: 2026-06-02
topic: ci-tunnel-apply-generalize
issue: 4844
lane: cross-domain
brand_survival_threshold: single-user incident
status: complete
---

# Brainstorm — Generalize the CF Tunnel CI-apply pattern (#4844)

## What We're Building

Extend the proven CF Tunnel SSH bridge (shipped in PR #4830, merged 2026-06-02) so GitHub
CI can auto-apply the **7 remaining on-host SSH-provisioned `terraform_data.*` resources** in
`apps/web-platform/infra/server.tf` on merge — instead of letting them drift until a
detect-only job files an issue telling a non-technical operator to run `terraform apply`
locally (which they structurally cannot do).

**Scope chosen: Approach A (parts 1+2 now, part 3 deferred).**

**PR-A (this issue, #4844):**
1. **Extract the inline tunnel bridge into a reusable composite action** `.github/actions/cf-tunnel-ssh-bridge/` (setup steps only; teardown stays caller-side `if: always()`). Precedent: `sentry-heartbeat` (extracted inline→composite in #3971 for 7 callers).
2. **Retrofit the 7 siblings with the #4829 dual-context connection block** and append them to `apply-web-platform-infra.yml`'s `-target=` set behind the bridge, so they auto-apply on merge.
3. **Add a `-target` allowlist parity-guard test** (model on the self-healing `ship-deploy-pipeline-fix-gate.test.ts`) to close the currently-unguarded `-target` drift surface.
4. **Fix the stale header comment** in `apply-web-platform-infra.yml` that falsely claims the 7 resources "land via `apply-deploy-pipeline-fix.yml`".
5. **Verify CODEOWNERS** covers `.github/workflows/`, `apps/web-platform/infra/*.tf`, and the hardening profile files — the reviewed merge is now the *only* human checkpoint for host-hardening changes.

**Deferred → PR-B (new issue):** part 3 — convert `scheduled-terraform-drift.yml` from detect-only to auto-apply-over-tunnel, with an ADR and guardrails.

## Why This Approach

- **Captures ~90% of the operator value (CPO).** These 7 resources only change via merged PRs (~2–4 changes/yr each), so auto-apply-on-merge eliminates the drift-then-block path for every realistic change. The detect-only drift job has rarely or never actually fired in anger.
- **Merge = authorization (respects `hr-menu-option-ack-not-prod-write-auth`).** Part 2 extends the post-#4830 model where the reviewed, CODEOWNERS-gated merge *is* the human prod-write authorization. Part 3 has **no merge gate** — that is exactly where the prior deliberate rejection of unattended `-auto-approve` still bites, so it is deferred.
- **Resolves the `apparmor` `-target` coupling incidentally (CTO).** Part 2 gives all 7 siblings the dual-context connection block, which is precisely what the already-pulled-in `apparmor_bwrap_profile` needs — no separate prerequisite.
- **Keeps the highest-risk piece (unattended root-SSH cron) out of the critical PR.** Part 3 is a trust-model posture change deserving its own ADR + review.

## Key Decisions

| Decision | Choice | Rationale |
|---|---|---|
| Scope of primary PR | Parts 1 + 2 | Operator value with merge-gated authorization |
| Bridge abstraction | **Composite action**, not `workflow_call` | iptables NAT rule + terraform apply must share one job's network namespace between bridge-up and teardown; a reusable workflow runs as a separate job and can't wrap the caller's steps (CTO) |
| Teardown placement | Caller-side `if: always()` step | Composite actions can't register a post-job cleanup without a JS action `post:` hook; keep teardown caller-side and enforce its presence via a workflow lint/test (CTO) |
| Secret passing into action | Explicit `inputs:`, caller forwards `${{ secrets.X }}`, re-export to `env:` inside step | Composite actions can't read `secrets.*`; matches `sentry-heartbeat`/`notify-ops-email` convention (repo research) |
| 7 sibling connection blocks | Convert `agent = true` → dual-context (`private_key = var.ci_ssh_private_key` + `agent = var.ci_ssh_private_key == null`) | All 7 still use the OLD agent-only shape; only `infra_config_handler_bootstrap` has the #4829 shape. Operator-local apply stays byte-equivalent (key var unset → `agent = true`) |
| Bridge mechanism | iptables `-t nat OUTPUT REDIRECT` (unchanged) | Terraform's Go SSH client never parses `~/.ssh/config`/`/etc/hosts`; only kernel NAT is transparent to it — `ProxyCommand`/ssh-config bridges are a dead end |
| `-target` allowlist safety | New parity-guard test deriving scope from the `.tf` resource set | The `-target` allowlists across the 3 apply workflows are an unguarded drift surface; a resource not in the list is planned-but-never-applied (silent no-op on merge) |
| Part 3 (auto-apply drift) | **Defer** to its own PR + ADR | Unattended prod write, no merge gate, x==x tautology risk; single-user-incident blast-radius class |
| Visual design | N/A — no UI surface | Pure infra/CI; Phase 3.55 trigger boundary not met |

## Open Questions

1. **Bridge live during `apply`, not just `plan`.** `apply-web-platform-infra.yml` saves a `tfplan` at plan time and consumes it at apply time. The bridge must be live during the **apply** step (SSH provisioners run then), not only during plan. Plan-time decision: keep bridge up across both, or re-open before apply.
2. **Tunnel idle-timeout / throughput during apply.** No learning documents tunnel behavior across longer applies. The 7 provisioners are short (file-push + `systemctl`), so risk is low, but the plan should confirm no idle-disconnect between plan and apply.
3. **CODEOWNERS state.** Must verify (not assume) that the infra `.tf` and profile files are CODEOWNERS-protected before relying on the merge as the authorization checkpoint. If not, add it in PR-A.
4. **Doppler `prd_terraform` service-token scope for any new apply path.** Service tokens are config-scoped; the existing read token + two-token write model already cover `apply-web-platform-infra.yml`, so part 2 inherits them — confirm no new token is needed.

## Domain Assessments

**Assessed:** Engineering (CTO), Product (CPO), Legal (CLO)

### Engineering (CTO)
**Summary:** Composite action is the correct abstraction (shared network namespace requirement); blast radius is MEDIUM — credential radius is unchanged (root already reachable via the live bridge) but hardening files become CI-writable, making CODEOWNERS the load-bearing replacement checkpoint. Only `apparmor_bwrap_profile` has a `depends_on` edge (server.tf:502); `docker_seccomp_config` does not (corrects the issue-body premise). Parts 1+2 ship together; part 3 separate. Recommends an ADR for part 3.

### Product (CPO)
**Summary:** Low product relevance (internal CI), but the operator-burden lens is real: the pain is low-frequency (~2–4 changes/yr per resource) but high per-incident (a non-technical operator can't run terraform locally). Part 2 captures ~90% of value; part 3 is gold-plating relative to its risk. Slice into PR-A (1+2) and deferred PR-B (3). Post-MVP milestone is correct.

### Legal (CLO)
**Summary:** LOW relevance — no user-PII surface in the hardening resources. Verdict: PERMITTED-WITH-GUARDRAILS, no downstream specialist, no legal-document lockstep (GDPR-Policy lockstep explicitly does NOT apply). The two guardrails apply only to the deferred part 3: (1) durable/WORM audit trail for every auto-applied drift correction; (2) a break-glass pause sentinel so the unattended loop can't silently revert an operator's intentional Art. 32-control change during an incident.

## Session Errors

- **Stale header comment found (in-scope fix).** `apply-web-platform-infra.yml` header claims the 7 SSH-provisioned `terraform_data.*` resources "land via `apply-deploy-pipeline-fix.yml`". They do NOT — that workflow only `-target`s `deploy_pipeline_fix` + `infra_config_handler_bootstrap`. The 7 genuinely drift. Fixing this comment is part of PR-A.
- **Issue-body premise corrected.** Issue #4844 states `apparmor_bwrap_profile` AND `docker_seccomp_config` are pulled into the CI graph via `deploy_pipeline_fix`'s `depends_on`. Only `apparmor_bwrap_profile` is (server.tf:502); `docker_seccomp_config` appears only in prose comments.

## Deferred Items (→ tracking issues)

- **Part 3: auto-apply-over-tunnel drift detector** — convert `scheduled-terraform-drift.yml` from detect-only to apply-over-tunnel. Re-evaluation criteria (promote when ANY holds): (1) a `terraform_data.*` drift issue actually fires from *out-of-band* host mutation (not a merged-PR change); (2) host config begins mutating outside Terraform; (3) the 7-resource change frequency rises materially above ~2–4/yr. Mandatory guardrails when built: `-target` allowlist (never bare apply), plan-then-apply with the existing destroy-guard jq filter (no-new-resources/no-destroy assertion), issue-file on apply-failure OR novel/out-of-allowlist drift (avoids the x==x tautology), WORM audit trail per mutation, break-glass pause sentinel, and an ADR for the trust-model change.
