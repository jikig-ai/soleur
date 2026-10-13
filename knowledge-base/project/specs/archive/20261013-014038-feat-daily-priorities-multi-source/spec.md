---
title: Daily Priorities multi-source (PR-H)
status: spec
date: 2026-05-19
umbrella: "#3244"
brand_survival_threshold: single-user incident
lane: cross-domain
brainstorm: knowledge-base/project/brainstorms/2026-05-19-daily-priorities-multi-source-brainstorm.md
branch: feat-daily-priorities-multi-source
draft_pr: "#4066"
related_prs: ["#3940", "#3947"]
related_issues: ["#3244", "#3947", "#3948"]
---

# feat: Daily Priorities multi-source (PR-H) — spec

## Problem Statement

Umbrella **#3244** acceptance criterion is unchecked: *"Daily Priorities dashboard ships with at least 3 signal sources and 'let [leader] handle it' one-click delegation."* PR-F #3940 shipped the substrate + Stripe-only single-source MVP on 2026-05-17. Two sources remain deferred:

- **GitHub** (PRs awaiting review, failing CI on main, P0/P1 issue events, security advisories).
- **KB-drift** (knowledge-base content that has gone stale relative to code — broken intra-KB links and AGENTS.md / learning code-anchor drift).

Without these sources, the umbrella stays open and the Today section under-delivers on the "what needs you today" promise.

## Goals

- Bring Today section from 1 → 3 signal sources, satisfying umbrella #3244 AC.
- Mirror the proven Stripe webhook → Inngest bridge pattern (`apps/web-platform/app/api/webhooks/stripe/route.ts:437-516`) for GitHub.
- Ship under inherited brand-survival threshold `single-user incident` with no flag-default-driven legal-posture gaps.
- Close 5 new scope-grant kinds for PR-G to recognize.

## Non-Goals

- No new leader role (Knowledge/CKO) — KB-drift uses direct-action affordance.
- No KB-drift signal for zero-hit-rules-over-8w or orphaned-constitution-rules — CPO classified as NOISE / requires LLM-judge; deferred.
- No migration of existing GH Actions crons to Inngest scheduler (tracked as #3948).
- No multi-org install support — one GitHub App install per founder for MVP (OQ1 to verify against `github-resolve` callback shape; constrain if needed).
- No PAT-based auth path.
- No Inngest publisher helper extraction (N=2 is premature abstraction).

## Functional Requirements

**FR1 — GitHub webhook ingestion.** `POST /api/webhooks/github` validates `X-Hub-Signature-256` against `GITHUB_APP_WEBHOOK_SECRET` (Doppler `prd`); fail-closed on signature mismatch or missing secret. Mirrors `stripe/route.ts` flag + scope-grant gate shape.

**FR2 — GitHub event → Inngest dispatch.** For each of 4 supported event classes, the webhook resolves `founderId` via `github_installation_id → users.id`, runs `isGranted(supabase, founderId, "<kind>")` against the corresponding scope-grant kind, and on `granted` emits `inngest.send({ id: "github-${delivery_id}", name: "<event-name>", v: "1", data: { founderId, domain, event, tier: grant.tier, payload } })`. On `!granted` log and break (fail-closed).

Event classes and scope-grant kinds:
| GitHub event | Scope-grant kind | Inngest event name | Owning domain |
|---|---|---|---|
| `pull_request.opened` / `pull_request.review_requested` | `engineering.pr_review_pending` | `engineering.pr_review_pending` | `engineering` |
| `workflow_run.completed` (conclusion=failure on default branch) | `engineering.ci_failed` | `engineering.ci_failed` | `engineering` |
| `issues.opened` / `issues.labeled` (label ∈ {priority/p0, priority/p1}) AND opened <24h OR new non-bot comment | `triage.p0p1_issue` | `triage.p0p1_issue` | `engineering` (label-routed: `engineering` for `area/*` labels, `product` for `type/feature`) |
| `repository_advisory.published` / `secret_scanning_alert.created` | `security.cve_alert` | `security.cve_alert` | `engineering` |

**FR3 — 4 GitHub Inngest functions.** One function per event class, each following the canonical `cfo-on-payment-failed.ts` shape: non-throwing `step.run` schema-gate; verify-state outside `step.run` (ADR-030 I3); SDK call inside `runWithByokLease`; `persist-draft` step opens `getFreshTenantClient(founderId)` and INSERTs `messages` row with `tier='external_brand_critical'`, `status='draft'`, `source='github'`, `source_ref='<event-class>-<id>'`, `owning_domain`, `draft_preview`, `urgency`, `trust_tier=grant.tier`. CEL concurrency `{scope:"fn", key:"event.data.founderId", limit:1}` + `{scope:"account", limit:50}`.

**FR4 — KB-drift nightly walker.** GH Actions workflow `.github/workflows/kb-drift-walker.yml` runs nightly (03:00 UTC). Two checks:
- **Broken intra-KB links** — `grep -rEo '\]\([^)]+\.md[^)]*\)' knowledge-base/ | xargs -I{} test -e {}` produces a list of `(source_file, broken_target)` tuples.
- **Code-anchor drift** — parse `AGENTS.md` rule IDs + `knowledge-base/project/learnings/*.md` `## Source` blocks for `path/to/file.ext:line` anchors; for each anchor, `test -e` the file. Existence-only check for MVP (OQ2 — semantic text-match deferred).

For each finding, INSERT a `messages` row with `source='kb-drift'`, `source_ref='link-<sha256(source+target)[:16]>'` or `anchor-<sha256(source+target)[:16]>'`, `tier='external_low_stakes'`, `status='draft'`, `owning_domain='knowledge'`, `urgency='low'`, `trust_tier='internal_infra_auto'` (the implicit grant kind `knowledge.kb_drift` is granted-by-default at install — no per-founder opt-in needed because the data is internal-only).

**FR5 — Today section response shape (additive).** `GET /api/dashboard/today` continues to return `{ items: TodayItem[], disclosure: RUNTIME_COST_DISCLOSURE }`. New `items[].source` values: `'github'`, `'kb-drift'` (in addition to existing `'stripe'`). No schema break.

**FR6 — Today card render variants.**
- **Source-aware card.** `<TodayCard>` switches button affordance by `source + owning_domain`:
  - `stripe` / `cfo` → existing "let CFO handle it" (Send / Edit / Discard).
  - `github` / any → "let CTO handle it" (Spawn-review-agent / Spawn-fix-agent / Spawn-triage-agent / Spawn-CVE-bump-agent by `source_ref` prefix). Same Send/Edit/Discard surface for the resulting draft.
  - `kb-drift` / `knowledge` → **direct-action**: "Fix link" or "Update anchor" button opens a scoped one-file PR via the existing fix-issue skill path. No leader name.
- **CVE redaction.** When `source='github'` AND `source_ref` starts with `cve-` or `secret-scan-`, the rendered card body shows **CVE ID + severity only**. The full advisory text stays in `messages.draft_preview` (audited) but is never rendered.

**FR7 — Hybrid ranking with surface cap.**
1. Strict tier-first sort: `urgency='critical' > 'high' > 'normal' > 'low'`.
2. Within tier: score = `recency_weight × severity_weight × leader_confidence`. Tie-break by `created_at DESC`.
3. Cap rendered surface at 7. Items 8+ exposed as "Show N more" expander (no fetch round-trip; data is already in `items[]`).

**FR8 — Dedup at INSERT.** Partial-unique index on `messages(user_id, source, source_ref) WHERE status='draft'` prevents duplicate active drafts from webhook replays. Webhook ingestion uses INSERT … ON CONFLICT DO NOTHING; the Inngest event's `id: "github-${delivery_id}"` provides a second dedup layer at Inngest's 24h window.

**FR9 — Scope-grant kinds (PR-G integration).** 5 new kinds shipped: `engineering.pr_review_pending`, `engineering.ci_failed`, `triage.p0p1_issue`, `security.cve_alert`, `knowledge.kb_drift`. Add to PR-G's grant-kinds enum + onboarding-flow UI.

## Technical Requirements

**TR1 — Migration 047.** `apps/web-platform/supabase/migrations/047_multi_source_dedup.sql`:
- ALTER `messages` ADD COLUMN `source_ref text` (nullable for backfill safety; new INSERTs always populate).
- Partial-unique index: `CREATE UNIQUE INDEX messages_active_draft_dedup_idx ON messages (user_id, source, source_ref) WHERE status='draft' AND source_ref IS NOT NULL;`.
- New table `audit_github_token_use` (founder_id, installation_id, repo_full_name, endpoint, ts, response_status). RLS policies. RPC `record_github_token_use(...)` with SECURITY DEFINER + `SET search_path=public, pg_temp` (per `cq-pg-security-definer-search-path-pin-pg-temp`).
- Add `audit_github_token_use` to the audit-table inventory in `audit-byok-writer-sweep.test.ts` peer file.

**TR2 — GitHub App provisioning + IaC.** New runbook `knowledge-base/operations/runbooks/github-app-provisioning.md` (alongside existing Inngest runbook). Terraform module `apps/web-platform/infra/github-app/` if a Cloudflare-anchored zone-binding is needed (verify with infra-security agent at plan-time). Doppler `prd` keys: `GITHUB_APP_ID`, `GITHUB_APP_PRIVATE_KEY` (PEM), `GITHUB_APP_WEBHOOK_SECRET`, `GITHUB_APP_CLIENT_ID`, `GITHUB_APP_CLIENT_SECRET` (reuses `auth/github-resolve` OAuth pair if same app).

**TR3 — Webhook handler.** `apps/web-platform/app/api/webhooks/github/route.ts`. Mirrors `stripe/route.ts`: signature verify → `processed_github_events` dedup table INSERT (similar to `processed_stripe_events`) → switch on `event.headers['x-github-event']` → per-class branch. NEW `processed_github_events` table in migration 047 keyed on `delivery_id text PRIMARY KEY`.

**TR4 — Inngest function files.** 4 new files under `apps/web-platform/server/inngest/functions/`:
- `engineering-on-pr-review-pending.ts`
- `engineering-on-ci-failed.ts`
- `triage-on-p0p1-issue.ts`
- `security-on-cve-alert.ts`

Each registered in `apps/web-platform/app/api/inngest/route.ts` serve array.

**TR5 — KB-drift walker workflow.** `.github/workflows/kb-drift-walker.yml` runs nightly. Workflow body: checkout repo (already there), run `scripts/kb-drift-walker.sh`, on findings POST to `https://<prd-host>/api/internal/kb-drift-ingest` with a one-shot Doppler-issued JWT. Internal-ingest route INSERTs `messages` rows (bypasses webhook signature flow; auth via Doppler-rotated bearer).

**TR6 — Card-body redaction extension (PR-H amended 2026-05-19).** `apps/web-platform/lib/safety/redaction-allowlist.ts` exports a new entry-point `redactGithubSourcedText(s: string, opts?: { source?: 'pr_title'|'issue_body'|'cve_description' }): string` applied as **belt-and-suspenders**: INSERT-time inside the github-on-event Inngest dispatcher (Phase 4) PLUS render-time inside `<TodayCard>` (Phase 6). **Render-time is the load-bearing Art. 14 minimization gate** (EDPB Guidelines 3/2025; the brainstorm CLO recommendation supersedes the original "INSERT-time only" stance of this TR). If only one redaction layer can ship, drop INSERT-time and keep render-time. Per ADR-037 and the plan-review Kieran P1 finding, the corresponding `Cache-Control: private, max-age=60` header on `/api/dashboard/today` minimizes the Art. 14 surface on rapid-refresh. Note: the plan provisionally referenced this file as "PR-A scope" but PR-A #3240 did not actually create `lib/safety/redaction-allowlist.ts`; PR-H lands it fresh.

**TR7 — Article 30 + DPD + Privacy + AUP updates.**
- `knowledge-base/legal/compliance-posture.md` — new Processing Activity 14 (GitHub-sourced priority signals).
- `docs/legal/data-protection-disclosure.md` — GitHub Inc. as sub-processor; "ingested third-party repo content" clause.
- `docs/legal/privacy-policy.md` — "Data we collect from third parties" section update.
- `docs/legal/acceptable-use-policy.md` — card-screenshot-redaction clause.
- Processor-of-processor onboarding disclosure (when founder connects an org containing customer repos).

**TR8 — ADRs.** Two ADRs via `/soleur:architecture create`:
- `ADR-031-github-app-webhook-as-second-multi-source-ingress.md` — webhook over polling, App over PAT, status `accepted`.
- `ADR-032-messages-source-ref-composite-unique-for-multi-source-dedup.md` — partial-unique pattern, status `accepted`.

**TR9 — Better Stack alerts.**
1. `/api/webhooks/github` 4xx/5xx rate > 2% over 5min.
2. `X-Hub-Signature-256` verification failures > 0 (page on-call).
3. GitHub API 429 sustained > 10min.
4. KB-drift workflow failure → Discord/Slack webhook (no Better Stack needed — internal, low-stakes).

**TR10 — Tests.**
- Unit: per-Inngest-function (4 files), Stripe-shape parity tests.
- Component: `TodayCard` source-variant rendering (3 source × N owning_domain matrix).
- Migration shape test: 047 — new columns + partial-unique index + audit table + RPC.
- Webhook integration: signature-verify, dedup, scope-grant-gate, no-grant-fail-closed.
- KB-drift walker: golden fixture with known broken-link + known good-link; assert ingest payload shape.
- E2E: install GitHub App on test repo → push fake PR → assert Today card appears within 60s. (Behind `SOLEUR_FR5_GITHUB_ENABLED` flag, default off in CI.)

## Acceptance Criteria

- [ ] AC1: `/api/webhooks/github` accepts signed `pull_request`, `workflow_run`, `issues`, `repository_advisory`, `secret_scanning_alert` events; rejects unsigned with 401.
- [ ] AC2: Scope-grant gate fail-closed (no active grant OR DB error → skip `inngest.send` AND log).
- [ ] AC3: 5 scope-grant kinds registered in PR-G enum + onboarding UI.
- [ ] AC4: KB-drift walker writes ≥1 broken-link card + ≥1 code-anchor-drift card on a seeded fixture; nightly schedule active.
- [ ] AC5: Today section renders cards from 3 sources (stripe + github + kb-drift) with source-correct button affordance.
- [ ] AC6: CVE / secret-scanning cards render ID + severity only (advisory body in `draft_preview` audited, not rendered).
- [ ] AC7: Ranking caps surface at 7; expander shows N more without round-trip.
- [ ] AC8: Migration 047 applies idempotently; partial-unique index prevents webhook-replay duplicate active drafts.
- [ ] AC9: `audit_github_token_use` table exists with RLS; RPC `record_github_token_use` writes a row per Octokit call.
- [ ] AC10: Article 30 + DPD + Privacy + AUP updates merged before flag flip.
- [ ] AC11: ADR-031 + ADR-032 status `accepted`.
- [ ] AC12: Umbrella #3244's "≥3 signal sources + delegation" AC flips `[x]`.

## Dependencies

- PR-G #3947 (scope-grant UX + audit-log viewer + onboarding) — must merge BEFORE `SOLEUR_FR5_GITHUB_ENABLED=true` in prd. Operator can pre-merge PR-H with flag-default off.
- Existing GitHub App primitive (tests reference `GITHUB_APP_ID`/`GITHUB_APP_PRIVATE_KEY`) — confirm production-side file at plan time; net-new if absent (most likely).
- Better Stack on-call (already wired from PR-F).
- Inngest self-hosted Hetzner dev server (already running from PR-F).

## Risks

- **R1 (high)** — Multi-org install. OQ1 unresolved; constrain to one install per founder if `github-resolve` callback can't accommodate.
- **R2 (medium)** — Card-body redaction extension regression: applying to LLM-output too aggressively may strip legitimate content from CFO drafts. Mitigation: separate redaction entry-point (`redactGithubSourcedText`) keeps Stripe path untouched.
- **R3 (medium)** — KB-drift false-positive rate. Existence-only anchor check may flag intentional file moves where AGENTS.md already cites a stable shim. Mitigation: include path in card body so founder can dismiss with one click; track 30-day FP rate.
- **R4 (low)** — Inngest event volume break-even (~3k/day per COO). Single-tenant pilot stays well under; flag for 5+ tenants.

## Brand-Survival Threshold

`single-user incident` — inherited from PR-F. See brainstorm `## User-Brand Impact` for 5 vectors and mitigations.

## Domain Review (carry-forward)

CPO ✓ — signal taxonomy + vector (e) flagged. CLO ✓ — 4 legal blockers inline (audit + redaction + DPD + Article 30 + Privacy + AUP); processor-of-processor disclosure. CTO ✓ — webhook over polling, App over PAT, migration 047, 2 ADRs. COO ✓ — webhook adds 1 endpoint + 3 alert rules, KB-drift in GH Actions, no new sub-processor, no paid-tier trigger.

`user-impact-reviewer` invoked at PR review-time (multi-agent review per PR-F precedent). Preflight Check 6 fires on `apps/web-platform/app/api/webhooks/github/**` + `apps/web-platform/server/inngest/functions/*-on-*.ts` + migration 047.
