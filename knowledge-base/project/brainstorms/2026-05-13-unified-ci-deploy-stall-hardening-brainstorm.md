---
title: Unified CI Deploy Stall Hardening
date: 2026-05-13
status: complete
related_issues: ["#3712", "#3704", "#2207", "#3706"]
brand_survival_threshold: single-user incident
user_brand_critical: true
lane: cross-domain
---

# Brainstorm: Unified CI Deploy Stall Hardening

## User-Brand Impact

**Artifact:** Web Platform Release pipeline (`ci-deploy.sh` + `apply-deploy-pipeline-fix.yml` auto-apply).

**Vector(s) endorsed by operator:**

1. **Release pipeline stays brittle — features can't ship.** GDPR-statutory features (e.g., #3634 DSAR Art. 15+20 endpoint) silently block on infra.
2. **Cross-tenant / data-integrity risk if deploy hangs mid-rollout.** CLO traced the script — `ci-deploy.sh` does NOT run DB migrations (those run app-boot / elsewhere), so the "new binary vs old schema" split-brain is out of scope. The actual atomicity gap is the docker swap window (lines 492-526 in `ci-deploy.sh`): `docker stop` + `docker rm` of prod completes, TERM lands, `docker run` of new prod never starts → prod serves nothing on :80/:3000 (Art. 32 *availability* leg, not integrity/confidentiality).
3. **Operator-only impact (release toil + delayed shipments).**

**Threshold:** `single-user incident` (default for user-brand-critical tag; carry to plan).

## What We're Building

A unified disposition for three open issues that all share one failure mode (`ci-deploy.sh` hangs on prod), plus a compliance-learning entry capturing the GDPR-organizational-measure framing.

**Scope of this PR (branch `feat-unified-ci-deploy-stall-hardening`):**

1. **Brainstorm + spec artifacts** documenting the unified disposition (this file + `spec.md`).
2. **Compliance learning entry** at `knowledge-base/project/learnings/compliance/2026-05-13-pipeline-reliability-as-gdpr-art32-control.md` covering: (a) Art. 32(1)(d) organizational-measure framing when the pipeline ships rights-fulfillment code; (b) SIGKILL audit-trail-completeness caveat (`reason=running` stays stale if bash is SIGKILLed before the trap dispatches).
3. **No code changes** to `ci-deploy.sh`, `ci-deploy-wrapper.sh`, `server.tf`, or workflows. #3706 already shipped the engineering fix in main; this PR is documentation + close-out.

**Operator actions (NOT in this PR — executed by the operator from an allowlisted IP, per `hr-menu-option-ack-not-prod-write-auth`):**

1. Run the canonical apply triplet from `apps/web-platform/infra/` to install `ci-deploy-wrapper.sh` + the hardened `ci-deploy.sh` on prod (per #3712 issue body). Verify via `sha256sum /usr/local/bin/ci-deploy.sh /usr/local/bin/ci-deploy-wrapper.sh && systemctl is-active webhook` (canonical contract per `learnings/bug-fixes/2026-04-29-deploy-pipeline-fix-postapply-verification-cf-access.md`).
2. After 2 organic Web Platform Release runs report `exit_code=0 reason=ok` within 900s, close #3712 + #3704.
3. Comment-close #2207 citing this brainstorm + the #3706 plan §49-59 (the deepen-pass that rejected `systemd-run --scope` for documented polkit/non-TTY reasons).

**Deferred to a separate follow-up issue:**

- **Self-hosted GH Actions runner on Hetzner** (terraform-managed, static IP in `ADMIN_IPS`) to fix the auto-apply IP-allowlist drift. `apply-deploy-pipeline-fix.yml` ran exactly once (the run that failed) and will keep failing identically for every future merge that touches the 5 trigger files. New terraform root → must include destroy runbook per `hr-every-new-terraform-root-must-include-an`.

## Why This Approach

**Why NOT add `systemd-run --scope` as a second layer (CTO's initial recommendation):**
The #3706 deepen-pass plan (`knowledge-base/project/plans/2026-05-12-fix-harden-web-platform-release-pipeline-3704-plan.md` §49-59 + §190) explicitly compared `systemd-run --scope` vs `timeout(1)` and rejected the former because:

- `webhook.service` runs as `User=deploy` (unprivileged); `systemd-run --system` requires polkit, which **cannot prompt in a non-TTY context** and would block indefinitely — *making the original stall worse*.
- `systemd-run --user` requires `loginctl enable-linger deploy` (terraform/cloud-init work not currently in place).
- Sudoers NOPASSWD for `systemd-run` adds new permission surface for marginal benefit.

The `timeout(1)` wrapper achieves identical SIGTERM→20s→SIGKILL semantic with zero permission elevation and zero new dependency. **This means `ci-deploy-wrapper.sh` IS the implementation of #2207's intent**, just via a different primitive. Closing #2207 with that citation is correct.

**Why #3712 alone unblocks the p1 user-brand outcome:**
- CPO sequencing: #3706 is dead code on prod until #3712 lands. Every hour of delay extends the window where the next release can strand identically.
- #2207 hardening is additive defense-in-depth; sequencing it ahead of #3712 hardens a system that isn't yet hardened.
- The brand-survival lens (GDPR-rights features blocked on infra) is resolved by activating #3706's existing protection, not by adding a second layer.

**Why defer the Hetzner runner to a follow-up:**
- It's a new terraform root requiring its own destroy runbook + ADR.
- Auto-apply has fired exactly once and structurally fails on the IP allowlist. Operator-manual is the de-facto path until the runner lands; `/ship` Phase 5.5 Deploy Pipeline Fix Drift Gate + 12h `scheduled-terraform-drift.yml` cron catch missed applies.
- Bundling it into this PR would gate the simple operator unblock (#3712) on infra-provisioning work.

**Why a compliance learning entry now (CLO):**
- Article 32(1)(d) GDPR requires "regular testing, assessing and evaluating the effectiveness of technical and organisational measures." Release-pipeline reliability becomes an organizational control the moment the pipeline ships rights-fulfillment code (DSAR #3634 was caught by this exact stall).
- Documenting this once, now, while the incident is fresh, costs less than re-deriving the framing during a future audit cycle.

## Key Decisions

| # | Decision | Rationale | Defer/Ship |
|---|---|---|---|
| 1 | **#3712 disposition: operator-manual `terraform apply -target=terraform_data.deploy_pipeline_fix`.** | Only path that doesn't re-litigate the 2026-03-19 "GH Actions runner IPs can't be allowlisted" decision. | Ship (operator action, not code) |
| 2 | **#3704 disposition: passively close after 2 organic releases <900s with `exit_code=0 reason=ok`.** | #3706 is the durable fix; verification waits on natural traffic. | Ship (passive) |
| 3 | **#2207 disposition: close as superseded by `ci-deploy-wrapper.sh`'s `timeout(1)` primitive.** | The deepen-pass §49-59 documented the systemd-run rejection. `timeout(1)` achieves the same SIGTERM-then-SIGKILL semantic. #2207's intent is satisfied; the primitive differs from the issue body. | Ship (comment + close) |
| 4 | **Compliance learning entry** at `knowledge-base/project/learnings/compliance/2026-05-13-pipeline-reliability-as-gdpr-art32-control.md`. | Captures Art. 32(1)(d) framing + SIGKILL audit-trail caveat once, while context is fresh. | Ship (this PR) |
| 5 | **Hetzner self-hosted runner** to fix auto-apply IP-allowlist drift. Tracked in **#3723**. | Cheapest durable fix vs Tailscale mesh / runner-IP allowlist / delete-auto-apply. ~€4/mo. | Defer to #3723 |
| 6 | **No bash trap / `set -m` / docker-swap-atomicity changes.** | Plan Sharp Edge #5 documents SIGKILL → state-stays-`running` as accepted status quo (workflow's `elapsed>900s` branch recovers). Docker swap atomicity (CLO) is an Art. 32 availability concern documented in the compliance learning, not a code change here. | Out of scope |

## Open Questions

1. **Comment-closing #2207 — should we also flag that the `timeout(1)` primitive achieves the issue's *acceptance criteria* (SIGTERM-on-stall + `reason=timeout` state-write + CI fast-fail) via different mechanics?** The original AC list in #2207's body maps cleanly to #3706's deliverables; spelling that out once in the close-comment prevents future "but did we ever ship the systemd-run thing?" archaeology.
2. **The single auto-apply run was the inaugural one.** Until the Hetzner runner lands, every future merge that touches the 5 trigger files will time out identically. Is the operator OK with that drumbeat of file-an-issue noise, or should the Hetzner runner be prioritized higher than p3?
3. **CLO surfaced docker-swap availability gap** (lines 492-526 of `ci-deploy.sh` — TERM during the prod-swap window leaves nothing serving). Worth a separate p3 issue, or accept as known-residual? Plan Sharp Edge #5 already documents SIGKILL state-stays-running; this is the adjacent docker-state gap.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support.

### Engineering (CTO)

**Summary:** Recommended `systemd-run --scope` as a second layer (cgroup-kill catches SIGKILL gap), Hetzner self-hosted runner for the auto-apply allowlist drift, and a sequenced 2-PR rollout. Repo-research reconciliation: the systemd-run path was explicitly rejected by the #3706 deepen-pass on polkit/non-TTY grounds for the `deploy` user — verified by reading the plan and `webhook.service` (`User=deploy`). CTO's gap analysis remains valuable as documentation of *what `timeout(1)` does and doesn't protect against*; we ship that framing in the compliance learning rather than as a second wrapper.

### Product (CPO)

**Summary:** Endorsed sequencing #3712 > #3704 > #2207. Current pipeline-stall UX (stale `/health` version + no in-app banner) is acceptable at pre-beta operator-audience maturity; revisit when first regulated user-facing surface ships. Out of scope for product: wrapper primitive choice, terraform allowlist mechanics, deploy retry semantics. Defer to CLO whether stalled-deploy of a GDPR endpoint is itself an Art. 33 reportable incident.

### Legal (CLO)

**Summary:** `ci-deploy.sh` does NOT run DB migrations — split-brain "new binary vs old schema" is out of scope for the TERM trap. Real atomicity gap is the docker swap window (Art. 32 *availability*, not integrity). DSAR delivery SLA (Art. 12(3)) is not breached by an hours-long stall (1-month window has ~720h headroom), but "release brittleness delays statutory features" is a legitimate Art. 32(1)(d) organizational-measure concern — file a learning under `knowledge-base/project/learnings/compliance/`. `write_state` is atomic via `mktemp` + `rename(2)`, but SIGKILL leaves `reason=running` stale — audit-trail-completeness caveat to document in the same learning.

## Capability Gaps

None reported by any leader. All needed agents/skills exist: `soleur:deploy`, `soleur:postmerge`, `soleur:admin-ip-refresh`, `soleur:architecture`, `legal-document-generator`, `legal-compliance-auditor`, terraform-root provisioning.

## References

- **Plan:** `knowledge-base/project/plans/2026-05-12-fix-harden-web-platform-release-pipeline-3704-plan.md` (§49-59 systemd-run rejection rationale; §190 risk table)
- **Spec (#3706):** `knowledge-base/project/specs/feat-one-shot-3704-harden-release-pipeline/spec.md`
- **Learnings:**
  - `learnings/2026-05-12-pgid-inheritance-and-bash-trap-defer-on-foreground-commands.md` — SIGKILL is load-bearing fallback; trap is best-effort
  - `learnings/bug-fixes/2026-04-24-recurring-deploy-pipeline-fix-drift-as-feature.md` — drift IS the bridge; 9-cycle pattern
  - `learnings/bug-fixes/2026-04-29-deploy-pipeline-fix-postapply-verification-cf-access.md` — file-SHA + `systemctl is-active` is the canonical contract
  - `learnings/2026-03-19-ci-ssh-deploy-firewall-hidden-dependency.md` — GH Actions runner-IP allowlisting precluded (5000+ rotating ranges); origin of the Cloudflare Tunnel decision
  - `learnings/2026-05-05-defense-relaxation-must-name-new-ceiling.md` — multi-layer defense requires naming each layer's threat surface
- **Files (worktree):**
  - `apps/web-platform/infra/ci-deploy-wrapper.sh` (14 lines, `timeout(1)` primitive)
  - `apps/web-platform/infra/ci-deploy.sh` (state-write + trap)
  - `apps/web-platform/infra/server.tf:209-269` (`terraform_data.deploy_pipeline_fix`)
  - `apps/web-platform/infra/firewall.tf:6-13` (Hetzner FW `admin_ips`)
  - `apps/web-platform/infra/webhook.service` (`User=deploy`)
  - `.github/workflows/apply-deploy-pipeline-fix.yml` (single-run history; first inaugural run failed)
  - `.github/workflows/scheduled-terraform-drift.yml` (12h cron, files-issue-on-drift, does NOT apply)
