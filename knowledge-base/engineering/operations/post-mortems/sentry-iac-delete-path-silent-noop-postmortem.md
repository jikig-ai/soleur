---
title: "Sentry IaC delete path was a silent no-op — a target-scoped apply cannot destroy a removed block; monitors accreted 8→49, one orphaned + billing for 12 days"
date: 2026-07-17
incident_pr: "#6582"
incident_window: "2026-05-xx (first orphan, #4929) → 2026-07-17 (systemic fix). Latent throughout; the specific orphan scheduled_ghcr_token_minter has been live+unreclaimable since #6074 (~12 days at detection)."
recovery_at: "2026-07-17 — full-root apply lands on this PR's merge; the two orphans (scheduled_ghcr_token_minter, kb_tenant_mint_silent_fallback) are destroyed by the acked push-to-main apply."
suspected_change: "apply-sentry-infra.yml planned Terraform against a hand-maintained `-target=` allow-list. A `-target`-scoped plan restricts the plan universe to the named addresses, so a resource whose `.tf` block is DELETED is no longer nameable and the live resource is never destroyed — deletion was a silent no-op."
brand_survival_threshold: single-user incident
status: resolved
triggers:
  - observability-gap
  - iac-drift
  - cost-accretion
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — availability/observability/cost incident with zero personal-data exposure. The affected resources are Sentry cron/uptime monitors and issue-alert rules (infrastructure metadata); no user content is moved or exposed. GDPR Art. 33/34 not engaged. (The gdpr-gate ran over the diff at plan and work phases and matched zero regulated-data surfaces.)"
---

## Actor key

- `agent` — Claude Code did this autonomously (no operator ack required).
- `agent-with-ack` — Claude Code did this AFTER operator confirmed via menu option per `hr-menu-option-ack-not-prod-write-auth`.
- `human` — Operator did this directly.

# Incident Overview

**Class:** observability / cost / IaC-drift. Not a user-facing outage — but a `single-user incident` threshold applies because the affected artifact is the production monitor set whose silent failure is itself a single-user incident (missed-run detection is how a dark alarm gets caught).

`apply-sentry-infra.yml` applied Terraform against a hand-maintained list of ~71 `-target=<address>` lines. Because a `-target`-scoped plan only considers the addresses named on the command line, **deleting a resource block from a `.tf` file never destroyed the live Sentry resource** — the deleted block simply became un-nameable, so it fell out of CI's view while staying live and billing.

The failure was **latent and self-concealing**: adding a monitor worked (block + target line), removing one silently no-op'd, and the workflow's own comment documented a prior instance of the leak that nobody re-checked.

**Consequences:**
- Monitor count grew **8 → 49 in two months and never once decreased** — because nothing could make it.
- `sentry_cron_monitor.scheduled_ghcr_token_minter` was orphaned by #6074 (which removed its block AND its target line together — the intuitive edit) and has been live + unreclaimable at $0.78/mo since, carrying a 12-day unresolved incident on the resource it monitored.
- `sentry_issue_alert.kb_tenant_mint_silent_fallback` was orphaned by #4929 (superseded, never destroy-applied).
- PAYG draw reached **$42.22/mo against a $50 cap** (84%), and the ledger understated the Sentry line by 78% ($40.00 vs a live-verified $71.22).

## Timeline

| when | what | actor |
|---|---|---|
| #4929 | First orphan: `kb_tenant_mint_silent_fallback` left in state, never destroy-applied. Leak documented in the workflow comment. | — |
| #6034 | A monitor added correctly (block + `-target=` line). | — |
| #6074 | Same monitor's block AND target line removed together → `scheduled_ghcr_token_minter` orphaned, live + billing. | — |
| 2026-07-17 | Sentry's own PAYG budget notification (approaching cap) triggered the investigation. | agent |
| 2026-07-17 | Root cause traced to `-target=` scoping making deletion structurally impossible; full-root fix designed and shipped (#6582). | agent-with-ack |

## Root Cause

`-target=` scoping is the root cause, and it is structural, not a typo. Terraform's plan universe under `-target` is exactly the named set; a removed block is unrepresentable in that set. So the "remove" path had no mechanism to work, while the "add" path did — a durable asymmetry that guarantees monotonic growth.

The secondary cause is that the leak was **documented in prose and never re-checked**: the workflow comment named the #4929 orphan, and #6074 reproduced the exact class one edit later.

## Remediation (this PR, #6582)

1. **Full-root apply** — `terraform plan` runs unscoped, so the universe is `state ∪ config` and removing a block yields a real destroy.
2. **PR-time destroy gate** (`sentry-destroy-required`, required) — surfaces destroys *before* merge with the destroyed addresses named, gated on a pre-staged `[ack-destroy]`. Full-root alone would only relocate the footgun (a post-merge red with the orphan surviving); the PR gate is the load-bearing half.
3. **Create gate** — the mirror-image leak (an unreviewed create from state/config divergence) is diff-matched and blocked.
4. **Class D orphan detection** — a live monitor with no `.tf` block and not in state fails the apply closed, so this exact orphan class is caught going forward.
5. **Ledger + cost model corrected** against a live read.

The learnings capturing the mechanism in depth are already committed:
- `2026-07-17-target-scoped-terraform-apply-makes-resource-deletion-a-silent-noop.md` — the root-cause mechanism.
- `2026-07-17-a-detector-placed-before-the-cure-blocks-it.md` — Class D deadlock (a fail-closed detector firing for the wrong reason).
- `2026-07-17-a-copy-adapted-gate-drifted-in-the-half-i-did-not-parity-pin.md` — the PR-time gate shipped permanently-red via a dropped line.
- `2026-07-17-unmanaged-is-not-dead-and-a-plan-premise-about-a-repo-setting-is-checkable.md` — the refused Phase 5c delete + the false plan premise.

## Detection gap — why it ran latent

Nothing watched the live↔IaC direction. `sentry-monitors-audit.sh` checked A/B/C orphan classes (all print-only) but had no "live monitor with no `.tf` block" check, and no scheduled drift check covered `apps/web-platform/infra/sentry`. The systemic detection gap (declared ≡ applied has no monitor) is why the fix's own invariant needs a drift check — tracked as #6612.

## Action Items & Follow-ups

| Issue | Item | Status |
|---|---|---|
| #6606 | Import the unmanaged live uptime monitor `1422253` (`app.soleur.ai`) into Terraform — it is the only Sentry uptime coverage of the app and was nearly deleted as a "dead orphan" (the same not-in-Terraform ≠ dead confusion this incident is about, in mirror image). | open |
| #6612 | Add `apps/web-platform/infra/sentry` to `scheduled-terraform-drift` so "declared ≡ applied" has a monitor — closes the detection gap that let this incident run latent. Needs raw-`SENTRY_AUTH_TOKEN` plumbing. | open |
| #6602 | ~$84/mo of COGS on unverified estimates whose verify-by dates passed — the same "estimate that outlives its verify-by date" class that let the Sentry line sit 78% wrong for five weeks. | open |

## Prevention

The remediation IS the prevention for the delete-path class (full-root makes deletion real; Class D catches the orphan class; the PR gate makes destroys visible pre-merge). The residual prevention — a standing drift monitor for the sentry root — is #6612.
