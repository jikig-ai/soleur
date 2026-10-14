# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-06-17-fix-inbound-email-ingress-dead-plan.md
- Status: recovered from partial-artifact (planning subagent completed plan + deepen-plan on disk; the connection dropped before it emitted the Session Summary — 41 tool calls / ~17 min. Plan verified complete: full frontmatter, Overview, L3→L7 hypotheses, diagnosis-driven fix, acceptance criteria, test scenarios, IaC, domain review, sharp edges. Scope check passed: only knowledge-base/project/{plans,specs}/ touched.)

### Errors
- Planning subagent connection closed mid-response (agentId a803a427f0fe1d918) before Session Summary emission. Recovered via on-disk artifacts per one-shot fallback step 1.

### Decisions
- Diagnose against LIVE prod state FIRST (L3→L7, unverified network layers before code) — do NOT pin a single root cause from code-reading. The probe still failed 2026-06-17 06:15 AFTER the #5413 grace-window egress fix, so LB-rotation is not a complete explanation.
- Break window overlaps both the DOCKER-USER egress default-drop rollout (#5089, 2026-06-10) and the inbound route go-live (#5125, 2026-06-11) — firewall is egress-only, so if the inbound svix POST never reached the route, the firewall is NOT the cause (pivot to MX/webhook/tunnel).
- Diagnosis is read-only; the only sanctioned prod write is the probe's own synthetic mail_class='probe' marker.
- Add a regression guard only if the confirmed cause is a code/config regression.

### Components Invoked
- soleur:plan, soleur:deepen-plan (via general-purpose planning subagent)
- soleur:work (this session — live L3→L7 diagnosis + runbook)

## Work Phase (2026-06-17) — diagnosis complete

### Confirmed root cause: H2b — Proton Sieve forward broken (HOP A)
The Proton Sieve auto-forward `ops@soleur.ai → <x>@inbound.soleur.ai` is
broken. Every Soleur-controlled hop (tunnel, route, secret, dedup, Inngest,
Supabase egress) is PROVEN healthy. The egress firewall was a red herring
(egress-only) — which is exactly why the probe still failed after #5413.

### Decisive evidence (live, read-only)
- **Differential:** direct-to-inbound diagnostics land end-to-end
  (`processed_resend_events` msg_3FGK 06-17 11:30, msg_3F39 06-12 19:32;
  `email_triage_items` rows 5de15f49, 361908db); Proton-routed daily probes
  never produce a Resend webhook despite clean daily outbound sends
  (`probe_tokens` 06-13→06-17 at 06:00). Only differing hop = Proton.
- `curl POST /api/webhooks/resend-inbound` → 401 (route svix-header guard),
  server=cloudflare → tunnel + secret healthy (401 not 500).
- `dig MX inbound.soleur.ai` → inbound-smtp.eu-west-1.amazonaws.com (intact).
- Supabase claim-inserts succeed for direct mail → egress healthy (H1 out).
- Sentry monitor: status=error daily 06-13→06-17 (fired+asserted, row absent).

### Fix shape
H2b is operator-owned config → NO code regression → guard N/A. Deliverable:
runbook `knowledge-base/engineering/operations/runbooks/inbound-email-ingress-dead.md`
+ operator re-enables the Sieve forward. Files-to-Edit pruned to runbook only.

### Secondary discovered defect (separate follow-up)
Both landed diagnostics are `mail_class=null`/`summary=null` → the non-probe
HOP F `fetch-sanitize-summarize` tail fails. Does NOT affect the probe path.

### Remediation — DONE + VERIFIED (2026-06-17 13:36 UTC)
Refined mechanism: the #5103 Sieve `redirect :copy "triage@inbound.soleur.ai"`
was enabled + matching but never delivered — forwarding breaks SPF/DMARC, so
Resend inbound dropped the forwarded copy (probes piled up in the ops@ inbox).
Fix: replaced it with Proton's **native auto-forward** ops@soleur.ai →
triage@inbound.soleur.ai (SRS → survives SPF). Setup driven via Playwright
(operator entered the Proton password — true human gate; confirmation link read
from the Resend dashboard Receiving tab and activated). **AC8 verified:** a
manual-trigger probe (token 739db236…) round-tripped to `mail_class='probe'` in
~11s. Operator inbox restored.

Residual (separate, #5468): non-probe mail finalizes mail_class=null — prod
RESEND_API_KEY is send-only so HOP F fetchReceivedEmail fails. Inbox still
receives mail; only summaries are pending the read-key fix.

Optional cleanup (needs Proton password again): remove the now-redundant
#5103 Sieve filter (its failing redirect is harmless; native forward supersedes).

### Decisions
- Did NOT run the plan's "MANDATORY" nft/dig diff: H1 is ruled out by a
  STRONGER end-to-end proof (Supabase writes succeed through the firewall),
  which supersedes nft-set membership. No SSH needed.
- No speculative code edits (AC3) — operator-config cause, runbook only.
