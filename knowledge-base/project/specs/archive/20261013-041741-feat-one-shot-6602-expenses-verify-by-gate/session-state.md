# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-07-17-fix-expenses-verify-by-expiry-gate-plan.md
- Status: complete (isolated subagent; plan + deepen-plan; CFO domain review; deepen HALT gates 4.6-4.9 + scheduled-work precedent passed)

### Errors
None. Two non-blocking friction points: (a) iac-plan-write-guard hook blocked writes on prose trigger phrases ("operator-driven", "doppler secrets set") — resolved by co-locating the `<!-- iac-routing-ack: plan-phase-2-8-reviewed -->` opt-out in each write payload; (b) the only new "infra" is a code-only Inngest cron + existing IaC apply (no manual provisioning).

### Decisions
- verify_by schema: greppable, render-invisible HTML-comment marker in the Notes cell — `<!-- estimate verify_by=YYYY-MM-DD owner=<role> source="<named invoice>" -->`; no pipe; additive (no table-schema change); marker presence IS the estimate flag (removed on verification, like the closed Sentry row). verify_by tracks the vendor's real billing cadence (Proton→annual renewal).
- Enforcing check: dispatch-hybrid mirroring cron-domain-model-drift (raw `schedule:` is hook-blocked; Inngest canonical per ADR-033) — deterministic `scripts/expenses-verify-by-check.sh` (exit 1 expired / 0 clean / 2 malformed) + workflow_dispatch executor filing an idempotent issue + Inngest scheduler in route.ts serve-list + cron-manifest.ts (3 parity tests) + RED/GREEN/anomaly/positive `.test.sh`. NO new Sentry cron monitor (Design A) — would spend $0.78/mo of the ~$7.78 PAYG headroom on the very row this corrects; cfo-endorsed.
- Vendor-read credential findings (read-only Doppler probe 2026-07-17): HCLOUD_TOKEN + RESEND_API_KEY present in prd_terraform BUT limited — Hetzner Cloud API = inventory + catalog-EUR only (NOT invoiced totals); Resend send key can't read billing; Proton has no billing API. **Authoritative billed USD comes from the invoice email in ops@soleur.ai** (the billed PDF), browser fallback, then estimate+marker. → /work must reach the mailbox/invoices; where a billed figure is genuinely unreachable this cycle, keep the estimate WITH the new verify_by marker (the fix makes it visible).
- Cost-model re-derivation fires on EITHER >10% category-subtotal shift OR corrected burn crossing a `⌈burn÷49⌉`/`⌈burn÷48⌉` integer break-even boundary (all-in $651.18 sits ~$14 above the 13-user boundary — a sub-10% Hetzner correction could flip headline break-even 14→13).
- Provisional ADR-121 authored as the complementary control to issue 6584's existence-only parity gate. D3 = `gh issue comment 6584` scope note in /work.

### Components Invoked
soleur:plan, soleur:deepen-plan; agents: Explore, learnings-researcher, soleur:finance:cfo (blocking domain review).

## Work Phase (started, then paused at a clean boundary for a fresh-session resume — operator's call)

### Operator decision (2026-07-17)
**Option 1 confirmed:** build the durable check now + correct the API-derivable Hetzner drift + mark every figure unreachable-from-invoice with a fresh `verify_by` date. **Do NOT open the Proton mailbox this run** (billed-USD invoices in ops@soleur.ai are behind a likely Proton login gate). The scheduled expiry check catches any marked estimate when its date passes — that is the durable value, independent of today's exact numbers.

### Phase 0 findings (COMPLETE — do NOT re-probe; verified live 2026-07-17)
- **Credentials (Doppler prd_terraform):** `HCLOUD_TOKEN`, `RESEND_API_KEY`, `RESEND_INBOUND_WEBHOOK_SECRET`, `RESEND_RECEIVING_API_KEY` present. NONE is billing-readable (Resend keys are send/receiving-scoped).
- **Hetzner Cloud API (HCLOUD_TOKEN):** `/v1/servers`, `/v1/volumes`, `/v1/primary_ips`, `/v1/pricing` → **200** (inventory + catalog EUR reachable). `/v1/invoices`, `/v1/billing` → **404** (billed USD total NOT reachable via API — needs the invoice email). Verdict: correct count/type drift + IPv4 rows + FX basis via API; billed USD stays estimate+marker unless an invoice is read.
- **Server inventory (5, all `running`):** soleur-web-platform `cx33`, soleur-web-2 `cx33`, soleur-grok-dogfood `cx33`, soleur-registry `cx23`, soleur-inngest `cpx22`. 5+ primary IPv4s present (the #6589 missing-row gap — confirmed real).
- Both ledger files exist: `knowledge-base/operations/expenses.md` (25KB), `knowledge-base/finance/cost-model.md` (32KB).

### Remaining work for the fresh session (per tasks.md Phases 1–5 + A.1)
Phase 1 (D1 corrections, marker-fallback for billed USD) → Phase 2 (marker schema) → Phase 3 (`scripts/expenses-verify-by-check.sh` + `.github/workflows/scheduled-expenses-verify-by.yml` + `apps/web-platform/server/inngest/functions/cron-expenses-verify-by.ts` + route.ts/cron-manifest.ts registration + `.test.sh` + parity tests) → Phase 4 (cost-model re-derivation if a subtotal shifts >10% or burn crosses a break-even integer boundary) → Phase 5 (`gh issue comment 6584` scope note) → A.1 (ADR-121). Then one-shot tail: review → qa → compound → ship. Worktree: `.worktrees/feat-one-shot-6602-expenses-verify-by-gate`; draft PR #6614.

