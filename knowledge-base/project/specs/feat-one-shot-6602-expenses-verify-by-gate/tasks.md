<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
# Tasks — feat-one-shot-6602-expenses-verify-by-gate

Plan: `knowledge-base/project/plans/2026-07-17-fix-expenses-verify-by-expiry-gate-plan.md`
Lane: cross-domain · Issue: #6602 · Threshold: aggregate pattern

## Phase 0 — Preconditions (in /work; parent retains Doppler / curl / Playwright)
- [ ] 0.1 Re-confirm credential availability (`doppler secrets -p soleur -c prd_terraform --only-names`; `-c prd`): `HCLOUD_TOKEN`, `RESEND_API_KEY` present (probed 2026-07-17).
- [ ] 0.2 Hetzner capability probe (verify-before-assert): `GET /v1/pricing` + `/v1/servers` + `/v1/volumes` + `/v1/primary_ips`; explicitly test whether ANY billing/invoice endpoint is reachable (strong prior: no — catalog+inventory only). Record verdict.
- [ ] 0.3 Resend capability probe: confirm present key is a restricted send key (cannot read billing).
- [ ] 0.4 agent-browser sanity (`AGENT_BROWSER_ARGS="--no-sandbox"`) or Playwright MCP available.

## Phase 1 — D1: pull actual draw + correct expenses.md (trace every figure; no re-estimate)
- [ ] 1.0 Primary billed source = the invoice EMAIL in `ops@soleur.ai` (billed PDF; Resend Inbound triage chain) for ALL three vendors; browser billing area is the fallback; keep-estimate+marker is last resort (cfo review).
- [ ] 1.1 Hetzner: API for inventory + catalog EUR (correct count/type drift); billed USD from the Hetzner invoice (email primary / billing-area browser fallback). If invoice unavailable → keep catalog-EUR×~1.08 FX as an estimate WITH a fresh verify_by marker.
- [ ] 1.1b Fold in the two #6589-named gaps: volume-row FX basis (~$0.35/mo) + missing web-1/registry Primary IPv4 rows (~$1.08/mo).
- [ ] 1.2 Resend Pro: read actual charge + billing/renewal date from the Resend invoice (email primary / browser fallback). Book actual (drop marker) or keep $20 + marker dated to next monthly cycle.
- [ ] 1.3 Proton Mail — ANNUAL plan (cfo): NO monthly charge. Read the annual invoice (~$168/2 users) → book `annual ÷ 12` (like Cloudflare $70/yr÷12). Named human-gate (OTP/passkey) handoff if reached. If unreadable → keep $14 + marker dated to the ANNUAL RENEWAL (not month-out, else monthly noise-file).
- [ ] 1.4 Every touched row's Notes carries a cited source; marker removed (verified) or fresh verify_by marker (estimate).

## Phase 2 — D2 (schema): machine-readable verify_by marker in expenses.md
- [ ] 2.1 Adopt marker `<!-- estimate verify_by=YYYY-MM-DD owner=<role> source="<named invoice/endpoint>" -->` in the Notes cell (invisible, greppable, no `|` inside; marker IS the estimate flag).
- [ ] 2.1b `verify_by` = the date the vendor's NEXT invoice will exist (billing cadence): Resend→next monthly; Proton→annual renewal (cfo). Record the "no marker = verified collapses estimate vs usage-volatile" limitation as a follow-up note.
- [ ] 2.2 Apply to rows that remain estimates after Phase 1 — including the R&D catalog-derived Hetzner rows (grok-dogfood host + IPv4), not COGS-only (cfo). Verified rows carry none. Replace the prose "verify on next invoice" caveat with the marker.

## Phase 3 — D2 (enforcing check): scheduled expiry gate (fails loud)
- [ ] 3.1 Create `scripts/expenses-verify-by-check.sh`: grep the marker token (position-independent), parse fields; exit 1 (expired, rows named) / exit 0 (none) / exit 2 (malformed marker OR zero-markers-parsed positive-sample failure). `BASH_SOURCE`-guard `main`.
- [ ] 3.2 Create `.github/workflows/scheduled-expenses-verify-by.yml` (`workflow_dispatch`-only, NO `schedule:`): rc1 → self-create `expenses-verify-by` label + idempotent issue (constant title, offending rows in body, label `domain/finance`); rc2 → `::error::` + step summary, no issue; Design A (no sentry-heartbeat step). Mirror `scheduled-domain-model-drift.yml`.
- [ ] 3.3 Create `apps/web-platform/server/inngest/functions/cron-expenses-verify-by.ts` (copy `cron-domain-model-drift.ts`; `id: cron-expenses-verify-by`, cron `"0 8 * * 1"`, event `cron/expenses-verify-by.manual-trigger`, `WORKFLOW_FILE = scheduled-expenses-verify-by.yml`, dispatch via `mintInstallationToken`/`redactToken`, failure → `reportSilentFallback`).
- [ ] 3.3a Register in `apps/web-platform/app/api/inngest/route.ts` (import + append to `serve({ functions: [...] })`).
- [ ] 3.3b Add `"cron-expenses-verify-by"` to `EXPECTED_CRON_FUNCTIONS` in `apps/web-platform/server/inngest/cron-manifest.ts`.
- [ ] 3.3c Verify parity tests green: `function-registry-count.test.ts` (e), `manual-trigger-allowlist.test.ts`, `sentry-monitor-iac-parity.test.ts`.
- [ ] 3.4 Create `scripts/expenses-verify-by-check.test.sh` (RED expired→exit1; GREEN future→exit0; anomaly malformed→exit2; positive-sample guard). Fixtures derived from the REAL expenses.md row shape. Wire into `scripts/test-all.sh`.
- [ ] 3.5 Confirm no new Sentry monitor / no heartbeat step (Design A). Confirm `sentry-monitor-iac-parity.test.ts` does not require a per-cron monitor; if it does, decide add-monitor (+$0.78/mo, re-derive headroom) vs exempt.

## Phase 4 — D1: re-derive cost-model.md (if any category subtotal shifts >10%)
- [ ] 4.1 Recompute Product COGS subtotal from corrected figures. Full re-derivation fires if EITHER (i) a subtotal shifts >10% OR (ii) corrected burn crosses a `⌈burn÷49⌉`/`⌈burn÷48⌉` integer boundary (current 14/14; all-in $651.18 sits ~$14 above the 13-user $637 boundary — a sub-10% Hetzner correction can flip it) (cfo). Full = all-in burn + both break-evens + per-user marginal + 50-user margins + dated Review note + updated `[expenses.md@date]` anchors + walk "~91%"/"~73%". Neither trigger: still update the specific line + anchor.
- [ ] 4.2 Every re-derived figure traces to a corrected ledger row; no re-estimates.

## Phase 5 — D3: scope note on #6584
- [ ] 5.1 `gh issue comment 6584` — parity gate = existence check, can't see a present-but-wrong amount; D2 verify_by/expiry gate is the complementary control. Reference the shipped check + workflow. Scope note, not a re-scope.

## Architecture / docs
- [ ] A.1 Author `knowledge-base/engineering/architecture/decisions/ADR-121-*.md` (provisional ordinal; `/ship` re-verifies): verify_by marker + expiry control as the complementary control to #6584. `## Decision` + `## Alternatives Considered`.
- [ ] A.2 C4 "no impact" already enumerated in the plan (three .c4 files read) — no `.c4` edit.

## Acceptance (see plan `## Acceptance Criteria` + `## Test Scenarios` for the full gates)
- Pre-merge: D1 figures traced-to-source; D2 markers well-formed; check + RED/GREEN test passing; scheduler registered + parity tests green; ADR-121 authored.
- Post-merge: `gh issue comment 6584` posted; workflow dispatched once to confirm executor path green.
