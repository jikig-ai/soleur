---
title: "fix(finance): correct unverified estimates + machine-readable verify_by expiry gate"
issue: 6602
branch: feat-one-shot-6602-expenses-verify-by-gate
lane: cross-domain
brand_survival_threshold: aggregate pattern
owner: cfo
created: 2026-07-17
depends_on:
  - knowledge-base/operations/expenses.md
  - knowledge-base/finance/cost-model.md
related:
  - 6584   # parity gate (existence check) — D3 scope note target
  - 6589   # settled Sentry precedent (do NOT re-derive)
  - 6538   # prior fleet under-count correction
---

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
<!-- Phase 2.8 reviewed: this plan introduces NO new server/service/secret/vendor infrastructure.
     The D2 Inngest cron + GHA workflow are CODE artifacts (committed, served via app route, no
     provisioning); the deliberate no-new-Sentry-monitor decision (§3.5) means zero new .tf resource.
     The "operator/browser" framing below refers to reading vendor INVOICES (Proton has no billing API),
     handled via agent-browser/Playwright with a named human-gate handoff — a read, not server provisioning
     via SSH/dashboard. hr-no-dashboard-eyeball-pull-data-yourself governs it (pull the data), not 2.8. -->

# fix(finance): correct unverified estimates + machine-readable verify_by expiry gate

## Enhancement Summary

**Deepened:** 2026-07-17 · **Gates passed:** User-Brand (4.6, `aggregate pattern`), Observability (4.7, no-SSH),
PAT-shaped (4.8, App-auth only), UI-wireframe (4.9, no UI surface), scheduled-work precedent (Inngest canonical, 49
crons). **Inputs:** direct reads of expenses.md / cost-model.md / the sweeper + domain-model-drift executor;
cron-registration research (exact serve-list + `cron-manifest.ts` + parity-test paths); learnings research
(awk pipe-offset, fail-safe positive-sample, producer-derived fixtures); a **read-only Doppler probe** (HCLOUD_TOKEN
+ RESEND send key present); and a **blocking cfo domain review** (recomputed the tables; verdict + 4 folded findings).

### Key improvements folded from the cfo review
1. **Break-even boundary trigger** (§4.1 + AC) — re-derive when corrected burn crosses a `⌈burn÷49⌉`/`⌈burn÷48⌉`
   boundary, not only on a >10% category shift; all-in burn sits ~$14 above the 13-user boundary, so a sub-10%
   Hetzner correction would silently flip the headline break-even. Closes the plan's own defect class against itself.
2. **Proton is ANNUAL** (§1.3) — amortize the annual invoice ÷12; date its `verify_by` to the annual renewal (else
   the gate noise-files monthly).
3. **`verify_by` = next-invoice-availability date** (§2.1), tracking each vendor's real billing cadence.
4. **Marker scope = the whole defect class** (§2.2) — extend to the R&D catalog-derived Hetzner rows, not COGS-only.
5. **Invoice-EMAIL as primary billed source** (§1) — the billed PDF landing in `ops@soleur.ai` beats OTP-gated
   Console scrapes; browser is the fallback.

### Load-bearing capability corrections (verify-before-assert)
- Hetzner Cloud API = inventory + catalog EUR only (NOT invoiced totals); Resend key is a restricted send key (no
  billing read); all three vendors' billed USD is authoritative only from the received invoice. See Research Reconciliation.

## Overview

~$84/mo of product COGS in `knowledge-base/operations/expenses.md` rests on **unverified
estimates whose implied verify-by has passed** — the exact defect class that let the Sentry
row sit 78% wrong for five weeks (#6589, settled precedent — do NOT re-derive). Three rows
carry a prose "verify on next invoice" caveat with **no date, no owner, no machine-readable
marker**, so nothing fires when the estimate outlives its own verification window:

| Row (`expenses.md`) | Est. amount | Estimate since | Exposure |
|---|---:|---|---|
| Resend Pro | $20.00 | 2026-06-16 | operator-driven Pro upgrade; flat published tier, first-invoice proration unseen |
| Proton Mail Workspace Standard (2 users) | $14.00 | 2026-07-16 | "~$7/user/mo annual estimate — TBD confirm exact rate" |
| Hetzner fleet (catalog-derived amounts) | ~$50.00 | 2026-07-16 | **largest + most exposed** — catalog list price ≠ billed price; omits FX drift (EUR→USD), IPv4 line items, VAT, traffic overage, per-hour proration on rebuilds |

This plan does three things (all-three scope, operator-approved):

- **D1 — Correct the numbers from ground truth.** Pull the *actual* draw for Resend, Proton,
  and the Hetzner fleet; correct `expenses.md`; re-derive `knowledge-base/finance/cost-model.md`
  (break-evens, margins) if any category subtotal shifts >10%. Every corrected figure must
  trace to an API read or a named invoice — **never a re-estimate**, never an operator paste.
- **D2 — Make the defect class mechanically visible.** Give estimate rows a **machine-readable
  `verify_by` marker** (replacing the unparseable prose caveat) and ship an **enforcing scheduled
  check** that parses `expenses.md`, finds estimate rows whose `verify_by` has passed, and **fails
  loud** (files an idempotent GitHub issue + non-zero exit). Include a RED/GREEN test. Re-checking
  today's three numbers alone rebuilds the trap; the marker + expiry gate is what stops the *next*
  estimate from rotting.
- **D3 — Post a scope note on #6584.** The parity gate proposed there compares tabled cost-model
  lines to *active* ledger rows — an **existence check**. The Sentry row was present, tabled, and
  correctly anchored; only its *amount* was fiction. Existence-checking cannot see a present-but-wrong
  number. The D2 verify_by/expiry check is the complementary control the parity gate does not provide.

**Precedent + model for the fix (already confirmed live 2026-07-17, do NOT re-derive):** the Sentry
row is already corrected to **$71.22** = $29 base + $42.22 PAYG (49×$0.78 cron seats + 4×$1.00 uptime
monitors), read via the Sentry API. That correction moved all-in break-even 13→14 users and is the
template: read the vendor, trace every term, remove the estimate marker when a live source closes it.

## Research Reconciliation — Task Claims vs. Codebase

| Task claim | Reality (verified) | Plan response |
|---|---|---|
| expenses.md at `knowledge-base/operations/expenses.md` | ✅ confirmed via `git ls-files` | use as-is |
| cost-model.md at `knowledge-base/finance/cost-model.md` | ✅ confirmed via `git ls-files` | use as-is |
| Resend + Hetzner billing tokens exist in Doppler | ✅ **probed read-only 2026-07-17** (Phase 0): `HCLOUD_TOKEN`, `RESEND_API_KEY`, `RESEND_RECEIVING_API_KEY` present in `soleur/prd_terraform`; RESEND_* also in `soleur/prd` | credential-availability recorded; see D1 approach |
| "Hetzner Cloud API exposes server pricing **+ the billing endpoint**" | ⚠️ **UNVERIFIED capability claim.** The Hetzner **Cloud** API (`api.hetzner.cloud/v1`) exposes `/pricing` (catalog list prices) + inventory (`/servers`, `/volumes`, `/primary_ips`). Invoiced totals (VAT, FX, IPv4, traffic) live in the **accounts/Console** billing area, historically NOT reachable by a project-scoped Cloud API token. | Do NOT assert the Cloud API returns billed totals. Phase 0 (in /work) probes for any billing endpoint; strong prior = catalog+inventory only. Hetzner is a **hybrid**: API for inventory/count/catalog-EUR truth, **Console invoice (browser)** for the billed USD. |
| "Resend has a billing/usage API" | ⚠️ The present `RESEND_API_KEY` is a **restricted send key** (the ledger note itself says a restricted send-key "can't self-upgrade"). Resend exposes no public billing/invoice API, and a send key cannot read billing regardless. | Resend Pro is a flat **$20/mo published** price; the *actual* billed charge (first-invoice proration + billing/renewal date) is authoritative only from the **Resend dashboard invoice (browser)**. |
| Proton Mail has NO billing API | ✅ correct | browser path (agent-browser `--no-sandbox`, fix merged 2026-07-17, or Playwright MCP); named human-gate (OTP/passkey) handoff only if reached |
| Sentry row still an estimate | ❌ **already corrected** to $71.22 (live-verified, #6589) in both files | Sentry carries **no** verify_by marker (it is the reference example of a *closed* estimate) |

**Honest convergence (shapes D1):** the API tokens present are useful for **inventory/catalog truth**
(Hetzner: which servers exist, their types, net EUR) but the **authoritative billed figure** for all
three vendors requires a **browser invoice read**. "API-first" is still correct — the Hetzner API
closes the count/type/catalog-EUR half (the self-correcting drift, à la Sentry's 40→49) — but the plan
must not overclaim that any present token returns the billed USD. That is the same
capability-claim-before-assert trap the Sharp Edges warn about.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — `expenses.md` and `cost-model.md`
are **operator-facing internal financial artifacts**, not a user surface. The concrete broken artifact
is an operator reading a wrong COGS subtotal / break-even count / gross-margin figure and mispricing or
misjudging runway on it (the #6589 harm, replayed). A broken *checker* silently fails to catch the next
estimate that rots — reinstating the exact defect class this feature exists to close.

**If this leaks, the user's data is exposed via:** N/A — the diff touches no user data, no PII, no
regulated-data surface. The figures are the company's own vendor spend. The one credential surface is the
D2 Inngest cron's short-lived GitHub App installation token (actions:write), which mirrors `_cron-shared`
token handling with `redactToken` — no new secret class.

**Brand-survival threshold:** `aggregate pattern` — the failure mode is *systematic* (financial-accuracy
drift over time), not a single-user incident. No per-PR CPO sign-off required; section present per gate.
`threshold: aggregate pattern, reason: internal financial/ops artifacts + a read-only scheduled checker; no user-facing surface, no user data, no regulated-data path.`

## Infrastructure (IaC)

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
**No manual infrastructure provisioning** (Phase 2.8 reviewed). The only new runtime "infra" is a **cron
job**, routed entirely through committed code + existing automated Terraform:

### Terraform / substrate changes
- **Scheduler (code):** the new Inngest cron function `cron-expenses-verify-by.ts` lives in the existing
  Inngest substrate (ADR-033), registered in the app's `serve()` list — application code, shipped by the
  ordinary web-platform release.
- **Sentry cron monitor:** **declined** by default (§3.5, cost self-consistency) → **no new `.tf` resource**.
  If ever added, it is a `sentry_cron_monitor` in `apps/web-platform/infra/sentry/cron-monitors.tf`, applied
  by the existing auto-applying `apply-sentry-infra.yml` root.
- No new server, host, volume, DNS record, TLS cert, secret, firewall rule, or vendor account; no secret writes.

### Apply path
Ships with the normal web-platform release — no separate apply, no first-boot config, no bootstrap script.

### Vendor-billing reads are NOT infrastructure
The Proton / Hetzner billing-area / Resend invoice reads are browser-gated by the **vendors' own design**
(no billing API), executed via agent-browser / Playwright in /work with a **named human-gate** handoff
(OTP/passkey) only if reached — the permitted OAuth/OTP-consent-class exception. They provision nothing;
the read follows `hr-no-dashboard-eyeball-pull-data-yourself` (pull the data, don't eyeball).

## Implementation Phases

### Phase 0 — Preconditions (executed in /work; the parent retains Doppler / curl / Playwright)

> The actual vendor reads run in `/work`. This plan **designs the approach + records the credential
> findings already probed**. Phase 0 confirms capabilities before spending the read budget.

0.1 **Credential availability (already probed read-only 2026-07-17 for this plan — re-confirm at /work):**
  - `doppler secrets -p soleur -c prd_terraform --only-names` → **`HCLOUD_TOKEN`**, **`RESEND_API_KEY`**,
    `RESEND_INBOUND_WEBHOOK_SECRET`, `RESEND_RECEIVING_API_KEY` present.
  - `doppler secrets -p soleur -c prd --only-names` → `RESEND_API_KEY`, `RESEND_RECEIVING_API_KEY` present.
  - No `PROTON_*` / no billing-scoped key for any vendor (expected).
0.2 **Hetzner capability probe (verify-before-assert):** with `HCLOUD_TOKEN`, `GET https://api.hetzner.cloud/v1/pricing`
  (catalog) and `GET /v1/servers`, `/v1/volumes`, `/v1/primary_ips` (inventory). **Explicitly test whether any
  billing/invoice endpoint is reachable** (strong prior: NOT — Cloud API is catalog+inventory only). Record the
  verdict; do not assume.
0.3 **Resend capability probe:** confirm the present key is a restricted send key (cannot read billing). Resend
  Pro is a flat published $20/mo; the billed charge + billing/renewal date come from the dashboard invoice.
0.4 **agent-browser sanity:** confirm `AGENT_BROWSER_ARGS="--no-sandbox"` path works (fix merged 2026-07-17) or
  Playwright MCP is available, for the Proton (and Hetzner Console, and Resend dashboard) invoice reads.

### Phase 1 — D1: Pull actual draw + correct `expenses.md`

Each corrected figure MUST carry a **cited source** (API response with endpoint + date, or a named invoice
with date). No re-estimates. No pasted figures.

<!-- iac-routing-ack: plan-phase-2-8-reviewed -->
**Primary billed-source = the invoice EMAIL (cfo review), browser Console as fallback.** All three vendors
email their monthly/annual invoice to `ops@jikigai.com` — the Proton `ops@soleur.ai` mailbox whose inbound
already forwards to Resend Inbound for triage (documented in the ledger + `gdpr-policy.md`). Parsing the
**received invoice PDF/email** is the authoritative billed figure (the Console is only a viewer of that PDF)
and avoids three separate OTP-gated browser scrapes. Order of preference per vendor: (1) the invoice email in
`ops@soleur.ai`, (2) the vendor billing area via browser, (3) keep the estimate + a fresh `verify_by` marker.

1.1 **Hetzner fleet.**
  - **API (`HCLOUD_TOKEN`):** enumerate live inventory — `hcloud server list` equivalent (`GET /v1/servers`) +
    volumes + primary_ips. Confirm which rows correspond to *real* live resources (correct any count/type drift,
    the Sentry-40→49 self-correcting class), and read catalog net EUR per type from `/v1/pricing`.
  - **Billed USD (authoritative):** read the **next/most-recent Hetzner Console invoice (browser)** for the true
    billed total including FX, VAT, IPv4 line items, traffic. If the invoice is not yet available, the corrected
    figure stays an **estimate** (catalog-EUR × documented ~1.08 FX) and **keeps a verify_by marker** with a fresh
    date = next invoice cycle (see D2). Do NOT silently harden catalog-EUR into a "verified" number.
  - Correct each affected Hetzner row's amount + append/update its Notes with the cited source.
  - **Also fold in the two pre-existing gaps #6589 named** (both need invoice verification before booking): the
    volume rows' FX basis disagrees with the host rows' ~1.08 basis by ~$0.35/mo, and **web-1 + registry have no
    Primary IPv4 row** (~$1.08/mo) though web-2/inngest/grok each do. Resolve or explicitly carry as estimates.
1.2 **Resend Pro.** Read the actual charge + billing/renewal date from the **Resend dashboard invoice (browser)**.
  If the first Pro invoice exists → book the actual (remove the estimate marker). If not yet issued → keep the
  flat $20 with a verify_by marker dated to the next billing cycle.
1.3 **Proton Mail — ANNUAL plan (cfo review — do NOT treat as monthly).** The row is "~$7/user/mo *annual*"; there
  is **no monthly charge** to read. The real artifact is **one annual invoice (~$168 for 2 users)** that must be
  **amortized ÷12** to stay consistent with the monthly-burn model (identical treatment to the Cloudflare
  `$70/yr ÷ 12 = 5.83` row). Source it from the annual invoice email in `ops@soleur.ai` (primary) or the Proton
  billing area (browser fallback); a human gate (OTP/passkey) is handed off **named** (clear the auth gate only —
  never paste the figure). Book `annual ÷ 12` + cite the invoice. If unreadable this cycle → keep $14 with a
  `verify_by` marker **dated to the ANNUAL RENEWAL** (§2.1) — a month-out date on an annually-billed row expires
  every month and would noise-file a GitHub issue for a figure that genuinely cannot be re-verified until renewal.
1.4 **Every row touched gets its Notes updated** with the cited source and (per D2) either an estimate marker
  removed (verified) or a fresh `verify_by` marker (still estimate).

### Phase 2 — D2 (schema): machine-readable `verify_by` marker in `expenses.md`

2.1 **Marker shape (design — suggested, fits the current markdown ledger).** The ledger is a pipe-delimited
  markdown table; the last column is free-prose **Notes**. Embed an **HTML-comment marker** in the Notes cell:

  ```text
  <!-- estimate verify_by=YYYY-MM-DD owner=<role> source="<named invoice or endpoint>" -->
  ```

  - **Invisible** in the rendered ledger (operator view stays clean); **greppable**
    (`grep -oE 'verify_by=[0-9]{4}-[0-9]{2}-[0-9]{2}'`); **parseable** per field.
  - **Additive** — no new column, no table-schema change; only estimate rows are touched (the other ~50 rows
    are untouched). Avoids the `replace_all` column-spacing hazard
    (`learnings/2026-03-27-replace-all-markdown-table-column-removal.md`).
  - **Constraint: no `|` inside the marker** (a pipe breaks the table cell) — `source="…"` must be pipe-free;
    the check + test enforce this (malformed → anomaly exit, see 3.1).
  - **The marker IS the estimate flag.** A row is an estimate **iff** it carries the marker. When a figure is
    verified against a live source, the marker is **removed** (exactly like the Sentry row, which now carries
    none). This makes `verify_by`/`owner`/`source` the **single source of truth** — no prose date to drift from
    the marker date (the precise rot in #6589, where a prose TODO date hardened into a cited number).
  - **Required fields:** `verify_by` (ISO date), `owner` (role token, e.g. `cfo`/`coo`), `source` (quoted free
    text naming what will close it). All three required; missing any → the check treats the marker as malformed.
  - **`verify_by` = the date the vendor's NEXT invoice will exist, not booking-date + an arbitrary window (cfo
    review).** It must track the vendor's actual billing cadence — Resend Pro's monthly proration → next monthly
    cycle; **Proton's annual cycle → the annual renewal date** (§1.3). A marker dated ahead of when a real invoice
    can exist just generates noise; a marker dated to a real invoice makes the expiry meaningful.
  - **Schema limitation (cfo — record, don't fix here):** "no marker = verified" collapses *estimate* and
    *verified-but-usage-volatile* into one state. The Sentry row is the counter-example — markerless yet moves per
    monitor added. Usage/monitor-count-driven rows arguably need a *recurring* re-verify cadence, not a one-shot
    `verify_by`; out of scope for this PR (Sentry has its own note + monitor-count driver), noted for a follow-up.
  - The prose "VERIFY on next invoice" caveat is **replaced** by the marker (its `source=` carries the same
    intent in parseable form); a short human hint may remain but the authoritative date/owner/source live only
    in the marker.

2.2 **Apply the marker** to the rows that remain estimates after Phase 1 (Resend and/or Proton and/or Hetzner
  catalog-derived rows — whichever the actual reads did not fully close). Verified rows get **no** marker.
  **Scope the marker to the whole defect class, not just COGS (cfo review):** the catalog-vs-billed estimate also
  lives in the **R&D** Hetzner rows (`grok-dogfood` host + its IPv4, both catalog-derived + unverified). Mark those
  too — a COGS-only gate would be narrower than the defect it exists to catch. (The check parses the whole ledger,
  so R&D estimate rows are covered automatically once marked.)

### Phase 3 — D2 (enforcing check): scheduled expiry gate that fails loud

**Why scheduled, not a CI test:** the defect is *time-based* — "an estimate that outlives its verify_by date"
fires with **zero commits** between PRs. A commit-time test/hook only runs on PRs and cannot catch rot that
happens on the calendar. So the runtime gate MUST be scheduled. (A unit test *also* exists — 3.4 — but tests
the checker, not the calendar.)

**Scheduling substrate (load-bearing constraint):** a raw GHA `schedule:` key is **blocked by the
`new-scheduled-cron-prefer-inngest` PreToolUse hook** — Inngest is the single scheduling substrate (ADR-033).
So this mirrors the **`cron-domain-model-drift` dispatch-hybrid** (near-exact semantic twin: "cite a source that
no longer resolves → file idempotent issue"), NOT the older `schedule:`-keyed follow-through sweeper.

3.1 **`scripts/expenses-verify-by-check.sh` (deterministic bash — the executor logic).**
  - Parses `knowledge-base/operations/expenses.md`; extracts every `verify_by=<date>` + its `owner`/`source`.
  - **Fail-safe positive-sample guard** (`learnings/best-practices/2026-07-09-oom-telemetry-...-fail-safe-soak-gate.md`):
    do NOT conclude "all clear" from the *absence* of expired rows if the parse found **zero** markers when the
    ledger is expected to contain ≥1 estimate — a broken parser reads every row as "no verify_by" → false all-clear.
    Assert ≥1 marker parsed (or an explicit "0 estimates in ledger" state) before a clean exit.
  - **Malformed-marker anomaly:** a marker missing `owner`/`source`, a non-parseable date, or a `|` in `source`
    → **exit 2 (anomaly)**, never a silent skip (an unparseable marker is the exact rot this prevents).
  - **Verdict:** any expired (`today > verify_by`, UTC) → **exit 1** (fail loud) with each offending row named
    (service + amount + verify_by + owner + source). None expired → **exit 0**. Parse/format anomaly → **exit 2**.
  - **awk pipe-offset caution** (`learnings/2026-05-26-awk-pipe-delimited-markdown-table-column-offset.md`): a
    leading `|` makes visual column N = awk field `$(N+1)`; trim with `gsub(/^ +| +$/,"",$f)`; prefer matching the
    marker token directly over column-indexing. The marker is greppable independent of column position — grep the
    marker, then parse its fields — which sidesteps the column-offset trap entirely.
  - `BASH_SOURCE`-guard `main` so the test can source it (mirror `sweep-followthroughs.sh` / `zot-soak-6122.sh`).

3.2 **`.github/workflows/scheduled-expenses-verify-by.yml` (executor).** Mirror `scheduled-domain-model-drift.yml`,
  minus the Sentry-heartbeat step (§3.5 — Design A, no monitor):
  - **`workflow_dispatch` only — NO `schedule:` key** (hook-blocked).
  - `permissions: contents: read, issues: write`; `set +e +o pipefail` around the analyzer + parse (grep exits 1
    on no-match) per the domain-model-drift comment.
  - **rc 1 (expired)** → self-create label `expenses-verify-by` (`gh label create … || true`; NB the repo has
    `domain/finance`, `domain/operations`, `deferred-expense`, `follow-through` but **no** verify-by label — new one
    needed) + file/update a **single idempotent issue** keyed by a **constant title** (e.g. `expenses: unverified
    estimate past verify_by`) with the offending-rows section in the **body** (not title — identical titles for
    dedup; distinguish real vs self-report by body marker per
    `learnings/2026-07-07-scheduled-cron-monitor-red-triage-...`). Also label `domain/finance`.
  - **rc 2 (anomaly)** → `::error::` + `GITHUB_STEP_SUMMARY`, **file NO estimate issue** (anomaly ≠ finding), fail
    the run loudly (mirror domain-model-drift's rc-2/3 arm + empty-heading guard).
  - **rc 0** → clean.
3.3 **`apps/web-platform/server/inngest/functions/cron-expenses-verify-by.ts` (scheduler).** Copy
  `cron-domain-model-drift.ts`: SCHEDULER ONLY — fires on its cron, dispatches the workflow via `workflow_dispatch`
  (Octokit, short-lived App installation token via `mintInstallationToken` + `redactToken`; dispatch failure →
  `reportSilentFallback`). **Cadence: weekly `"0 8 * * 1"`** (Mon 08:00 UTC — verify_by dates are month-granularity;
  weekly is sufficient + cheaper than daily; also on-demand runnable). `WORKFLOW_FILE =
  "scheduled-expenses-verify-by.yml"`. The `createFunction` shape (id + `[ { cron: "0 8 * * 1" }, { event:
  "cron/expenses-verify-by.manual-trigger" } ]` + concurrency `cron-platform` + `retries: 1`) copies
  domain-model-drift verbatim. **Registration touch-points (all confirmed against the codebase — see Files to Edit;
  three are parity-test-enforced — skipping any fails CI):**
    1. `apps/web-platform/app/api/inngest/route.ts` — import `cronExpensesVerifyBy` + append to the
       `serve({ … functions: [ … ] })` array (alphabetized; there is **no** `functions/` barrel — registration is
       direct in this route).
    2. `apps/web-platform/server/inngest/cron-manifest.ts` — add `"cron-expenses-verify-by",` to
       `EXPECTED_CRON_FUNCTIONS` (alpha position). Enforced by
       `apps/web-platform/test/server/inngest/function-registry-count.test.ts` case (e) [file-set parity] and
       `apps/web-platform/test/lib/inngest/manual-trigger-allowlist.test.ts` [the `{ event: … }` trigger name must
       equal `manualTriggerEventFor("cron-expenses-verify-by")`].
3.4 **`scripts/expenses-verify-by-check.test.sh` (RED/GREEN harness).** Mirror `zot-soak-6122.test.sh` (exit-code
  assertions against fixture ledgers). **Fixtures derived from the REAL `expenses.md` row shape**, not synthesized
  (`learnings/best-practices/2026-07-12-dry-run-fixture-must-derive-from-producer-source-...`):
    - **RED:** a fixture row with `verify_by=<past date>` → assert **exit 1** + the row named in output.
    - **GREEN:** a fixture row with `verify_by=<future date>` → assert **exit 0**.
    - **Anomaly:** a marker missing `owner`/`source` OR a non-date OR a `|` in `source` → assert **exit 2**.
    - **Positive-sample:** a ledger with markers present parses ≥1 (guards the false-all-clear on a broken parser).
  Wire into `scripts/test-all.sh` (root `npm test` → `bash scripts/test-all.sh`).
3.5 **Observability decision — NO new Sentry cron monitor (Design A, cost-aware).** A Sentry cron monitor costs
  **$0.78/mo against the ~$7.78 PAYG headroom on the very row this feature corrects** (#6589). For a low-stakes
  weekly advisory checker that is not worth it, so this mirrors **`cron-dev-migration-drift` (Design A)** — **no
  `cron-monitors.tf` block, no `sentry-heartbeat` workflow step**. Scheduler liveness rides the
  `cron-inngest-cron-watchdog` + `EXPECTED_CRON_FUNCTIONS` parity (a missed run only delays noticing an expired
  estimate by a week; the check is also on-demand runnable). NB: omitting BOTH the tf monitor and the workflow
  monitor-slug keeps `sentry-monitor-iac-parity.test.ts` green (nothing to mismatch). The feature practices the
  frugality it enforces. (Flagged as a decision for cfo / plan-review.)

### Phase 4 — D1: re-derive `cost-model.md` (if any category subtotal shifts >10%)

Read `cost-model.md`'s derivation sections first (done at plan time): Product COGS subtotal **$231.33**, all-in
burn **$651.18**, break-evens (COGS-scope **5 users**, all-in **14 users** at both $49 gross and $48 Stripe-net),
per-user marginal **~$0.91**, 50-user margins (COGS-based **90.56%**, all-in **73.42%**). The three estimates live
in COGS (Resend $20 + Proton $14 + Hetzner catalog rows ~$50).

4.1 After Phase 1's actual figures land, recompute the **Product COGS subtotal**. Per the ledger's
  Downstream-Consumers rule + `cost-model.md` frontmatter (`review_cadence: monthly`, `owner: cfo`):
  - **Full re-derivation trigger (TWO conditions — either fires it; cfo review):** (i) any category subtotal shifts
    **>10%**, OR (ii) corrected burn **crosses a `⌈burn ÷ price⌉` integer boundary at $49 OR $48**. Condition (ii) is
    load-bearing and NOT implied by (i): all-in burn is **651.18 = ⌈13.29⌉ = 14 users**, only **~$14/mo above the
    13-user boundary ($637)** — a Hetzner correction of ~$15 (a ~6.5% COGS shift, *below* the 10% gate) silently
    flips the headline break-even 14→13. Gating solely on 10% would let this plan's own defect class (a silent
    financial-model drift) survive against itself. Compute `⌈burn÷49⌉` and `⌈burn÷48⌉` for the corrected burn and
    compare to the current 14/14 before deciding.
  - **Full re-derivation** = all-in burn, **both** break-even counts (gross $49 + Stripe-net $48, `⌈burn ÷ price⌉`),
    per-user marginal cost, and 50-user margins (COGS-based + all-in + Stripe-adjusted). Add a **dated Review note**
    following the existing `> **[YYYY-MM-DD Review note]**` convention; update the tabled Source anchors
    (`[expenses.md@<date>]`) to the new dates; walk the "~91%"/"~73%" framing.
  - **A shift that trips NEITHER condition** still updates the specific tabled line + its anchor (accuracy is
    paramount) — only (i)/(ii) trigger the full break-even/margin narrative.
4.2 **Trace every re-derived figure to a source** (the corrected ledger row at its new anchor date). No figure in
  `cost-model.md` may cite a re-estimate.

### Phase 5 — D3: scope note on #6584 (executed in /work)

5.1 `gh issue comment 6584` (a scope note ON the issue — **not** a re-scope). Content: #6584's parity gate compares
  tabled `cost-model.md` lines to *active* ledger rows = an **existence check**; the Sentry row (#6589) was
  present, tabled, and correctly anchored — only its *amount* was fiction, which existence-checking cannot see.
  The **D2 `verify_by`/expiry gate shipped here is the complementary control** #6584's parity gate does not
  provide (present-but-wrong amount vs present-vs-absent row). Reference the shipped
  `scripts/expenses-verify-by-check.sh` + the scheduled workflow as the concrete mechanism.

## Architecture Decision (ADR/C4)

### ADR
Author **ADR-121** (provisional ordinal — ADR-118/119/120 exist; `/ship` re-verifies the next-free ordinal against
`origin/main` before merge; if renumbered, sweep this plan + tasks.md + any AC naming the ordinal in the same edit).
Short record: *"machine-readable `verify_by` estimate marker + scheduled expiry gate as the complementary control to
#6584's existence-based parity gate."* Rationale mirrors ADR-076 (curated-register + deterministic drift detector)
and ADR-033 (Inngest dispatch-hybrid). `## Decision` + `## Alternatives Considered` (raw `schedule:` cron — rejected,
hook-blocked; commit-time test only — rejected, cannot catch calendar rot; new Sentry monitor — rejected, PAYG-cost).

### C4 views
**No C4 impact — enumeration (per the C4 completeness mandate; all three model files read at plan time):**
- **External human actors:** none new. The operator/cfo reads the ledger (already implicit); no new correspondent.
- **External systems/vendors:** Resend + Hetzner are already modeled (`model.c4` `resend`, `hetzner`) for their
  *runtime* roles (email, hosting). The billing-invoice **reads are one-time human-driven corrections in /work**,
  not a new persistent platform runtime edge — no new element/edge. Proton is a billing data source read manually,
  not a modeled runtime container.
- **Container/data-store:** none. `expenses.md` is a KB doc, not a modeled container.
- **Access-relationship:** none changes. The D2 scheduled check + Inngest cron are internal platform mechanisms
  already represented by the generic scheduler/cron pattern (C4 does not model each of the ~40 crons as an element).

The test — *would a competent engineer reading the ADRs + C4 be misled about the system after this ships?* — is **no**.

## Domain Review

**Domains relevant:** finance (cfo), operations (coo/ops-advisor)

### Finance (cfo)
**Status:** reviewed (blocking Task — the CFO re-derivation is what surfaced this defect class; #6589)
**Assessment (cfo, 2026-07-17 — recomputed the tables against the ledger first: COGS $231.33, all-in $651.18,
all four break-evens reconcile):**
- D1 methodology (trace-to-source, both-price recompute, anchor discipline) **sound**; COGS/R&D classification
  clean; no margin-framing error.
- **Verdict on the no-new-Sentry-monitor decision: AGREE** — $0.78/mo is 10% of the entire $7.78 PAYG headroom on
  the row this feature corrects; that headroom is not fungible slack (at `onDemandPeriodEnd` 2026-08-16 an overrun
  deactivates every monitor at once, #3958). Keep Design A.
- **4 findings folded into the plan:** (1) break-even **boundary trigger** added to §4.1 + AC (the >10% gate alone
  lets a sub-10% Hetzner correction silently flip all-in break-even 14→13); (2) **Proton is ANNUAL** — §1.3 now
  amortizes ÷12 and dates `verify_by` to the annual renewal (a month-out date would noise-file monthly); (3)
  **`verify_by` = next-invoice-availability date** tracking each vendor's billing cadence (§2.1); (4) the
  catalog-vs-billed defect also lives in the **R&D** Hetzner rows → §2.2 extends the marker there.
- **Bonus folded:** the authoritative billed source is the **invoice EMAIL landing in `ops@soleur.ai`** (the billed
  PDF, not a Console view) — §1 now makes email-parse primary, browser fallback, reducing OTP-scrape brittleness.

### Operations (coo / ops-advisor)
**Status:** reviewed inline — ops-advisor owns the expense ledger; the marker convention + which rows stay
estimates is an ops-ledger concern. Vendor-read approach (API-first, browser for billed totals) aligns with
`hr-no-dashboard-eyeball-pull-data-yourself` (pull the data, do not eyeball a dashboard).

### Product/UX Gate
**Not applicable.** No `## Files to Create`/`## Files to Edit` path matches a UI-surface term/glob (no
`components/**`, `app/**/page.tsx`, etc.). Mechanical UI-surface override does not fire → Product = NONE.

## Observability

```yaml
liveness_signal:
  what: cron-expenses-verify-by dispatches scheduled-expenses-verify-by.yml weekly (Mon 08:00 UTC)
  cadence: weekly (Inngest cron trigger "0 8 * * 1")
  alert_target: cron-inngest-cron-watchdog via EXPECTED_CRON_FUNCTIONS parity (NO new Sentry monitor — Design A, §3.5)
  configured_in: apps/web-platform/server/inngest/functions/cron-expenses-verify-by.ts + apps/web-platform/server/inngest/cron-manifest.ts
error_reporting:
  destination: (a) the filed idempotent GitHub issue is the actionable finding output; (b) workflow ::error:: + GITHUB_STEP_SUMMARY on rc 2 anomaly; (c) Inngest dispatch failure → reportSilentFallback (Sentry, token redacted)
  fail_loud: true  # rc 1 files an issue AND exits non-zero; rc 2 anomaly fails the run loudly
failure_modes:
  - mode: an estimate row's verify_by date has passed
    detection: scripts/expenses-verify-by-check.sh exit 1, offending rows named in body
    alert_route: idempotent GitHub issue (label expenses-verify-by + domain/finance)
  - mode: malformed marker (missing owner/source, bad date, pipe in source) or broken parser (zero markers parsed)
    detection: exit 2 anomaly (positive-sample + well-formedness guards)
    alert_route: workflow ::error:: + GITHUB_STEP_SUMMARY; NO estimate issue filed
  - mode: Inngest dispatch (workflow_dispatch) fails
    detection: try/catch in cron-expenses-verify-by.ts
    alert_route: reportSilentFallback → Sentry issues stream (token redacted)
logs:
  where: GITHUB_STEP_SUMMARY + workflow run logs; Inngest run logs for the scheduler
  retention: GitHub Actions default
discoverability_test:
  command: "gh workflow run scheduled-expenses-verify-by.yml --ref main   # then gh run view <id>  — OR locally: bash scripts/expenses-verify-by-check.sh; echo $?"
  expected_output: "exit 0 (no expired) / exit 1 + offending rows named (expired) / exit 2 (anomaly); NO ssh"
```

## Acceptance Criteria

### Pre-merge (PR)
- [ ] **D1 (a):** Resend, Proton, and each corrected Hetzner row's amount in `expenses.md` **traces to a cited
      source** (API response w/ endpoint+date, or a named invoice w/ date). Grep every touched row's Notes for a
      source citation; **no bare re-estimate**. Any figure still an estimate carries a `verify_by` marker (not a
      bare number).
- [ ] **D1 (b):** `cost-model.md` re-derived — full re-derivation fires if EITHER (i) a category subtotal shifted
      >10% OR (ii) corrected burn crossed a `⌈burn÷49⌉`/`⌈burn÷48⌉` integer boundary (current 14/14). When it fires,
      a dated Review note updates both break-even counts, per-user marginal, and 50-user margins; tabled Source
      anchors updated to new dates. Every re-derived figure traces to a corrected ledger row. A change tripping
      neither still updates the specific line + anchor.
- [ ] **D2 (schema):** every remaining estimate row in `expenses.md` carries a well-formed
      `<!-- estimate verify_by=… owner=… source="…" -->` marker (greppable, no `|` in the marker); verified rows
      carry none.
- [ ] **D2 (check):** `scripts/expenses-verify-by-check.sh` exists, `BASH_SOURCE`-guarded, exit 1 on any expired
      marker (rows named), exit 0 on none, exit 2 on malformed/anomaly.
- [ ] **D2 (test) — RED/GREEN:** `scripts/expenses-verify-by-check.test.sh` asserts exit 1 (expired fixture, named),
      exit 0 (future fixture), exit 2 (malformed fixture), + positive-sample guard; wired into `scripts/test-all.sh`
      and passing.
- [ ] **D2 (scheduler):** `.github/workflows/scheduled-expenses-verify-by.yml` is `workflow_dispatch`-only (no
      `schedule:` key); `cron-expenses-verify-by.ts` registered in `app/api/inngest/route.ts` serve list + added to
      `EXPECTED_CRON_FUNCTIONS` in `cron-manifest.ts`; `function-registry-count.test.ts` (e),
      `manual-trigger-allowlist.test.ts`, and `sentry-monitor-iac-parity.test.ts` all green.
- [ ] **ADR-121** authored (`## Decision` + `## Alternatives Considered`); C4 "no impact" recorded with enumeration.

### Post-merge (operator/automated)
- [ ] **D3:** `gh issue comment 6584` posted with the scope note (existence-check vs present-but-wrong-amount;
      names the shipped D2 check). Automation: `gh` CLI in /work — not operator-manual.
- [ ] Scheduled workflow dispatched once post-merge (`gh workflow run scheduled-expenses-verify-by.yml --ref main`,
      since a new workflow must exist on the default branch first) to confirm the executor path is green.

## Test Scenarios

1. **Expiry-check RED:** fixture ledger row `... <!-- estimate verify_by=2026-01-01 owner=cfo source="x" -->`
   → `scripts/expenses-verify-by-check.sh` exits **1**, names the row. (The trap that #6589 sprung, now caught.)
2. **Expiry-check GREEN:** same row with `verify_by=2027-01-01` → exits **0**.
3. **Anomaly:** `<!-- estimate verify_by=notadate owner=cfo source="x" -->` → exit **2**; and a marker missing
   `owner` → exit **2**; and `source="a|b"` → exit **2**.
4. **Positive-sample guard:** a ledger containing ≥1 marker parses ≥1 (a stubbed broken parser returning zero
   markers must NOT read as exit-0 all-clear).
5. **Vendor-read source-trace (D1):** for each of Resend / Proton / Hetzner, the corrected `expenses.md` amount
   has a cited API-read or named-invoice source in its Notes; grep proves no touched amount is a bare re-estimate.
6. **cost-model trace (D1):** every figure changed in `cost-model.md` traces to a corrected ledger row at its
   bracketed anchor date; break-even recompute is arithmetic-consistent (`⌈burn ÷ price⌉`).

## Files to Create
- `scripts/expenses-verify-by-check.sh` — deterministic expiry checker (executor logic).
- `scripts/expenses-verify-by-check.test.sh` — RED/GREEN/anomaly/positive-sample harness.
- `.github/workflows/scheduled-expenses-verify-by.yml` — `workflow_dispatch`-only executor (files idempotent issue).
- `apps/web-platform/server/inngest/functions/cron-expenses-verify-by.ts` — Inngest scheduler (dispatch-hybrid).
- `knowledge-base/engineering/architecture/decisions/ADR-121-*.md` — provisional; verify-by marker + expiry control.

## Files to Edit
- `knowledge-base/operations/expenses.md` — correct Resend/Proton/Hetzner amounts + add `verify_by` markers to
  remaining estimates (D1 + D2 schema).
- `knowledge-base/finance/cost-model.md` — re-derive subtotals/break-evens/margins + dated Review note + anchors (D1).
- `apps/web-platform/app/api/inngest/route.ts` — import + add `cronExpensesVerifyBy` to the `serve()` functions array.
- `apps/web-platform/server/inngest/cron-manifest.ts` — add `"cron-expenses-verify-by"` to `EXPECTED_CRON_FUNCTIONS`.
- `scripts/test-all.sh` — invoke the new `.test.sh`.

## Open Code-Review Overlap
_None — no open `code-review`-labelled issue names these files (to be re-confirmed once Files lists finalize)._

## Risks & Mitigations
- **Overclaiming API capability (Hetzner/Resend billed totals).** Mitigated by the Research Reconciliation table +
  Phase 0 verify-before-assert probes; the plan routes billed USD through the browser invoice, API only for
  inventory/catalog.
- **Marker breaks the markdown table** (a `|` in `source`). Mitigated by the no-pipe constraint + the anomaly-exit
  test.
- **False all-clear on a broken parser.** Mitigated by the positive-sample guard (assert ≥1 marker parsed).
- **awk column-offset on the pipe-delimited ledger.** Mitigated by grepping the marker token directly (position-
  independent) rather than column-indexing.
- **New workflow can't be `workflow_dispatch`-triggered from the feature branch** (GitHub requires it on the default
  branch first) — verification is post-merge, reflected in the AC split.
- **Self-referential Sentry cost.** A new cron monitor would consume the very PAYG headroom this feature corrects →
  explicitly declined (§3.5, Observability; Design A mirrors cron-dev-migration-drift).

## Sharp Edges
- A plan whose `## User-Brand Impact` section is empty/placeholder fails `deepen-plan` Phase 4.6 — filled above.
- The provisional **ADR-121** ordinal is not final; `/ship` re-verifies against `origin/main`. On renumber, sweep
  this plan + `tasks.md` + any AC naming the ordinal in the same edit.
- `cost-model.md` Source anchors (`[expenses.md@YYYY-MM-DD]`) are load-bearing — after correction, update the anchor
  dates on every changed line, not just the amount, or the trace-to-source contract silently rots.
- The `{ event: "cron/expenses-verify-by.manual-trigger" }` trigger name MUST equal
  `manualTriggerEventFor("cron-expenses-verify-by")` or `manual-trigger-allowlist.test.ts` fails.
