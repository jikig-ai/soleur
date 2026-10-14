# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-06-17-fix-inbound-mail-finalize-tail-plan.md
- Status: complete

### Errors
None. One hook block hit and resolved during planning: initial plan write blocked by IaC-routing gate (`hr-all-infrastructure-provisioning-servers`) because AC10 prescribed a raw `doppler secrets set`. Re-routed the secret through a `doppler_secret` Terraform resource + added `iac-routing-ack` opt-out comment for the CAPTCHA-gated Resend key mint.

### Decisions
- Root cause grounded via Sentry at plan time (not left as the issue's three hypotheses): Sentry issue WEB-PLATFORM-35 = `Error: fetch-received-email failed: restricted_api_key`. Cause is a send-scoped Resend key reused for the inbound `receiving.get` body fetch — not an egress drop, 404, or data error.
- Two-pronged fix: (1) least-privilege `RESEND_RECEIVING_API_KEY` consumed only by `fetch-received-email.ts`; (2) final-attempt-gated degraded finalize so any future fetch/summarizer egress drop writes a visible degraded row + notify instead of a silent permanent NULL.
- Deepen-pass folded in a P0 + two P1s: P0 — degraded `mail_class='other'` write targets a disjoint one-time-set column from `statutory_class` so WORM trigger does NOT P0001 against a concurrent statutory finalize; added `.is(...null)` WHERE race guard (AC7). P1 — degraded sentinel excluded from daily-LLM-ceiling count (AC8); fetch-failure degraded notify sent statutory-grade.
- Simplified per code-simplicity: dropped dev fallback to `RESEND_API_KEY` (silent-in-dev, hazardous-in-prd); receiving var now required.
- Attempt-gating confirmed as existing repo idiom (`_cron-shared.ts` + `cron-stale-deferred-scope-outs.ts:358`, inngest 3.54.2 `BaseContext.attempt`) — copy verbatim. Brand-survival threshold = single-user incident; `requires_cpo_signoff: true`.

### Components Invoked
- Skill `soleur:plan` (#5468), Skill `soleur:deepen-plan`
- Agents: `repo-research-analyst`, `learnings-researcher`, Inngest-SDK verifier, verify-the-negative pass, `data-integrity-guardian`, `code-simplicity-reviewer`
- Sentry API (issue/event read), Doppler (token read), `gh`, git (commit+push)
