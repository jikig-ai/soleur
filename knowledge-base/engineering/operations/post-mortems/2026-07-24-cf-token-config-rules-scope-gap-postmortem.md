---
title: "Cloudflare token missing Config-Rules scope — six review gates missed it; surfaced at terraform apply"
date: 2026-07-24
incident_pr: 6892
incident_window: "2026-07-20 (plan→apply of PR #6746)"
recovery_at: "2026-07-20"
suspected_change: "PR #6746 plan prescribed a Configuration Rule in a ruleset phase the cf_api_token_rulesets token did not carry"
brand_survival_threshold: single-user incident
status: resolved
triggers:
  - process-gap
art_33_triggered: false
art_34_triggered: false
art_33_deadline: "n/a — no personal-data breach; a token-scope gap blocked a terraform apply, no data was exposed or lost"
---

## Actor key

- `agent` — Claude Code did this autonomously.
- `agent-with-ack` — Claude Code did this after operator menu-ack.
- `human` — Operator did this directly.

# Incident Overview

While fixing a GSC "Not found (404)" on `/cdn-cgi/l/email-protection` (PR #6746), the plan prescribed a Cloudflare Configuration Rule in the `http_config_settings` ruleset phase. Neither the plan, its **6-agent review panel**, nor `/deepen-plan` noticed that `cf_api_token_rulesets` does not carry the Configuration-Rules permission. The gap surfaced only at implementation time, from a live probe returning `403 request is not authorized`. There was **no production outage** — the missing scope blocked a `terraform apply`; the fix was a dashboard token widen, done manually because no browser transport was available in that session (which spawned tracking issue #6755).

## Status

resolved — the token was widened (`Config Rules:Edit` appended to `cf_api_token_rulesets` on 2026-07-20; live probe confirms the scope), PR #6746 merged, ADR-130 recorded the widen-vs-mint rule, ADR-136 shipped a standing pre-apply gate, and this PR (#6892) ships the first-party `soleur:cf-token-scope` skill closing the tooling half.

## Symptom

`GET /zones/<zone>/rulesets/phases/http_config_settings/entrypoint` → **403** `request is not authorized`, discovered only when the ruleset resource failed to apply.

## Incident Timeline

- **Start time (detected):** 2026-07-20 (implementation-time live probe during PR #6746)
- **End time (recovered):** 2026-07-20 (token widened via dashboard)
- **Duration (MTTR):** same-day

| Actor | Time (UTC) | Action |
|---|---|---|
| agent | 2026-07-20 | Live probe during PR #6746 implementation returned 403 for `http_config_settings` — scope gap detected. |
| human | 2026-07-20 | Widened `cf_api_token_rulesets` via the Cloudflare dashboard (browser transport unavailable in-session → filed #6755). |
| agent | 2026-07-20 | ADR-130 (widen-vs-narrow-alias) + ADR-136 (pre-apply entrypoint-enumeration gate) authored. |
| agent | 2026-07-24 | `soleur:cf-token-scope` skill built (this PR), verified live against production. |

## Participants and Systems Involved

Cloudflare API tokens (`cf_api_token_rulesets`), `apps/web-platform/infra` Terraform, the plan/review/deepen-plan pipeline.

## Detection (+ MTTD)

- **How detected:** implementation-time live API probe (not by any planning/review gate).
- **MTTD:** the gap existed from plan authoring through the full 6-agent review + deepen-plan; caught only at apply.

## Resolution

Token widened (dashboard); the four-probe ADR-130 retained-scope set confirmed no scope was dropped. ADR-130 + ADR-136 + this skill are the durable remediation.

## Recovery verification

Live read-only probe (this session): `cf-token-scope.sh` → all five zone phases + account list `authorized (200)`, exit 0 — the `Config Rules:Edit` scope is live.

---

# Incident Post-Mortem Analysis

## Root Cause(s) — 5-Whys

1. **Why did the apply fail?** The token lacked `Config Rules:Edit`.
2. **Why was the missing scope not caught earlier?** No gate compared the prescribed ruleset phase against the token's actual scope ledger.
3. **Why did 6 review agents + deepen-plan miss it?** They reasoned about the ruleset resource's correctness, not the credential's capability — the scope ledger (`variables.tf` descriptions) was accurate but nothing read it against the new phase.
4. **Why was there no first-party tool to check/fix token scope?** `soleur:provision-cloudflare` mints tenant tokens (requires `User API Tokens:Edit`, which no Soleur token holds); first-party scope changes had no path and became ad-hoc dashboard trips (3rd on record: #6657, #6649, #6755).
5. **Root cause:** a missing capability — no deterministic, first-party way to (a) enforce a pre-apply scope check and (b) execute + verify a token widen. ADR-136 addresses (a); this skill addresses (b).

## Impact details

### Services Impacted

The PR #6746 SEO Config-Rule apply (blocked until the widen). No user-facing service degraded.

### Customer Impact (by role)

- Prospect: none.
- Authenticated app user: none.
- Legal-document signer: none.
- Admin via Access: none.
- Billing customer: none.
- OAuth installation owner: none.

(A GSC 404 remediation was briefly delayed; no live user path broke.)

### Revenue Impact

None.

### Team Impact

One same-day manual dashboard trip; a follow-up tracking issue (#6755).

## Lessons Learned

### Where we got lucky

The gap surfaced at `terraform apply` (loud, pre-production) rather than as a silent partial apply. A `kind="zone"` ruleset that had applied could instead have clobbered dashboard-created rules (the ADR-130 whole-list-REPLACE hazard).

### What went well

The scope ledger in `variables.tf` was accurate; the live probe gave unambiguous ground truth; ADR-130 + ADR-136 landed the same cycle.

## Action Items & Follow-ups

| Issue | Action | Status |
|---|---|---|
| #6755 | Build the first-party `soleur:cf-token-scope` skill (Playwright widen + fail-closed retained-scope probe) so token-scope changes are no longer ad-hoc dashboard trips | in this PR (#6892) |
| #6767 | ADR-136 standing pre-apply entrypoint-enumeration gate (catches a plan prescribing a resource the credential cannot create) | done |
