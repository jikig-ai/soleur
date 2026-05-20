---
title: Daily Priorities multi-source expansion (PR-H)
date: 2026-05-19
status: captured
umbrella: "#3244"
parent_plan: "PR-F #3940 (merged 2026-05-17) carry-forward"
lane: cross-domain
brand_survival_threshold: single-user incident
related_prs: ["#3940", "#3947"]
related_issues: ["#3244", "#3947", "#3948"]
---

# Daily Priorities multi-source (PR-H) — brainstorm

## What we're building

Add **two new signal sources** to the Daily Priorities Today section so umbrella **#3244**'s acceptance criterion ("≥3 signal sources + 'let [leader] handle it' one-click delegation") flips from `[ ]` to `[x]`.

- **GitHub source** (4 signal classes): PR-awaiting-review, CI-failure-on-main, P0/P1 issue (label + freshness-gated), GitHub security advisories (CVE / secret-scan).
- **KB-drift source** (2 signal classes, **direct-action only — no leader symmetry**): broken intra-KB links, code-anchor drift (rule/learning refs to moved/deleted files).

Brings Today section from 1 → 6 signal classes across 3 sources (Stripe, GitHub, KB-drift).

## Why this approach

**Approach A — single PR-H, fully hardened.** All CLO blockers inline (audit + redaction + DPD + Article 30 + Privacy + AUP). Migration 047 inline (load-bearing for webhook idempotency per learnings `2026-04-14-atomic-webhook-idempotency-via-in-filter` + `2026-04-22-stripe-webhook-idempotency-dedup-insert-first-pattern`). One merge closes umbrella AC.

Rejected alternatives:
- **B (split GitHub + KB-drift)** — KB-drift slice is genuinely small (nightly cron + 2 walkers + UI affordance); bundling avoids 2 rounds of regression-test setup.
- **C (carry CLO non-blockers)** — Trades brand-survival posture for ~1 week saved under inherited `single-user incident` threshold; flag-default is not a tenant-level gate (PR-G learning).

## User-Brand Impact

**Threshold:** `single-user incident` (carry-forward from PR-F #3940; operator re-affirmed 2026-05-19 with all-of-the-above).

**Vectors:**
1. **Wrong card → wrong delegation.** A high-confidence-looking card mis-routes a P0 security alert to the wrong leader; agent spawns and touches prod while founder sleeps. Mitigated by hybrid ranking (strict-tier-first), per-signal-class scope-grant kinds, trust-tier policy engine (3-tier MVP from PR-F).
2. **Cross-tenant data leak.** GitHub webhook payload / installation token / polled metadata for tenant A renders on tenant B's dashboard. Mitigated by `isGranted(supabase, founderId, ...)` scope-grant gate (the load-bearing safety primitive — `SOLEUR_FR5_*` env flag alone is NOT a tenant gate); cookie-scoped `createClient()` + belt-and-suspenders `.eq('user_id', userId)` on the Today read path.
3. **Credential / webhook-secret exposure.** GitHub App private key (PEM) or webhook signing secret leaks. Mitigated by Doppler `prd` custody (same tier as Inngest signing secret), short-lived install tokens preferred over PAT (CLO + learning `2026-03-29-repo-connection-implementation` — PAT is off-table), new `audit_github_token_use` table before 2nd hosted founder (Art. 5(2) accountability).
4. **Signal noise drowns the real signal.** Mitigated by hybrid ranking with surface cap of 7, dedup-insert-first via partial-unique index on `(user_id, source, source_ref) WHERE status='draft'`, CPO-classified signal taxonomy (zero-hit-rules and bare-orphaned-constitution dropped as NOISE).
5. **(NEW)** **Inadvertent disclosure via card body.** A security-alert card may render a CVE description that contains library names, version strings, internal hostnames, or accidentally-uploaded customer PII. Founder shoulder-surf or screenshare leaks third-party data. Mitigated by:
   - Security-alert cards render **CVE ID + severity only** — never the full advisory body.
   - PR-A #3240 redaction allowlist (scoped to LLM output) extended to cover GitHub-sourced text rendered in any card body.
   - DPD discloses "we display third-party repo content as-is and do not re-process" (display-only, no persistence beyond ephemeral cache).

## Key Decisions

| # | Decision | Rationale |
|---|---|---|
| K1 | **Webhook → Inngest bridge**, not polling | COO: O(events) not O(tenants × poll-interval); per-install rate budget doesn't scale. CTO: mirrors proven `stripe/route.ts:437-516` pattern. Adds 1 endpoint + 3 alert rules. |
| K2 | **GitHub App + short-lived install tokens.** PAT is off-table. | CLO: PAT creates long-lived broad-scope credential class — materially worsens Art. 33 breach blast radius. Learning `2026-03-29-repo-connection-implementation` already encodes this pattern. |
| K3 | **4 GitHub signal classes**: PR-review, CI-fail-on-main, P0/P1-issue (gated), security-advisory | Operator-confirmed CPO classifications. Excludes `dependabot[bot]` *PRs* (noise) but keeps GitHub Security *advisories* (signal). P0/P1 issue gate: `priority/p0`/`priority/p1` label + opened <24h OR new non-bot comment. |
| K4 | **KB-drift = 2 signals only**, direct-action only (no leader) | Operator dropped zero-hit-rules + orphaned-constitution per CPO NOISE classification. Broken-links + code-anchor-drift fire a "Fix link" / "Update anchor" button → scoped one-file PR. Umbrella AC reinterpreted: "3 sources, delegation where a leader fits, direct-action where it doesn't." |
| K5 | **KB-drift runs as GH Actions nightly cron**, not Inngest scheduled | COO: GH Actions has pre-checked-out working tree for free; internal-only so latency story doesn't matter. One more entry on TR9 (#3948) migration list — acceptable. |
| K6 | **Migration 047 inline**: add `messages.source_ref text` column + partial-unique index `(user_id, source, source_ref) WHERE status='draft'` | Learnings `2026-04-14` + `2026-04-22`: webhook idempotency requires DB-level unique (dedup-insert-first), not application-set logic. CTO confirmed migration 046 has only comment-references to `source_ref`. |
| K7 | **Hybrid ranking** (strict tier → score within tier, cap surface at 7) | CTO recommendation. Money/legal always first; within tier, score = recency × severity × leader-confidence. Cap=7 keeps the dashboard scannable across 6 signal classes from 3 sources. |
| K8 | **CVE / security-alert cards render ID + severity only** | Vector (e) mitigation. Full advisory body stays in the Inngest payload + audit row; never reaches the rendered card. |
| K9 | **Dedup cross-source signals on stable downstream ref** (commit SHA, issue ID), not source-specific titles | Learning `2026-05-17-sentry-issue-alert-create-dedup-on-action-match-not-conditions`. "PR with failing CI AND review-pending → one card" keyed on `(source='github', source_ref='pr-{number}')` — CI failure and review-pending are status fields on the same card, not separate cards. |
| K10 | **5 new scope-grant kinds** for PR-G to recognize | `engineering.pr_review_pending`, `engineering.ci_failed`, `triage.p0p1_issue`, `security.cve_alert`, `knowledge.kb_drift`. KB-drift gets a grant kind so the direct-fix button respects trust-tier policy even without a leader. |
| K11 | **CLO blockers all inline in PR-H** | Brand-survival threshold inherited; flag-default is not a tenant-level gate. Audit + redaction + DPD + Article 30 + Privacy + AUP ship together. |
| K12 | **ADRs** required: (a) GitHub App webhook → Inngest as second multi-source ingress; (b) `messages.source_ref` composite-unique for idempotent multi-source upsert | CTO. Run `/soleur:architecture create` after spec. |

## Open Questions

- **OQ1** — Multi-org scope. GitHub App is per-org-install; founder may have multiple orgs (personal + employer + side-project). Today's CFO function assumes one founder-row → one tenant. Does the install-token bookkeeping support `(user_id, installation_id)` 1-to-many, or do we constrain to one install per founder for MVP? Verify against `apps/web-platform/app/api/auth/github-resolve/` callback shape before spec authoring.
- **OQ2** — KB-drift code-anchor staleness threshold. A rule citing `2026-04-21-foo.md:42` becomes stale when (a) the file is deleted, (b) line 42 no longer matches the cited text, or (c) the file moves. Should the walker run an exact-text re-anchor check, or just an existence check for MVP? Recommend existence-only for MVP (cheap); semantic re-anchor in a follow-up.
- **OQ3** — KB-drift fix-button trust tier. "Fix link" generates a one-file PR — does it auto-merge (trust-tier internal-infra-auto) or require the founder's 1-click? Recommend 1-click for MVP (no precedent for KB direct-action) — re-evaluate after 30 days of evidence.
- **OQ4** — Inngest event-publisher helper. Currently `stripe/route.ts` hand-rolls `inngest.send(...)` inline. PR-H's webhook will repeat the shape. Worth extracting `lib/inngest/publish-tenant-event.ts` in this PR for reuse, or follow-up refactor? Recommend follow-up (#TBD) — premature abstraction with N=2.

## Domain Assessments

**Assessed:** Engineering (CTO), Product (CPO), Legal (CLO), Operations (COO). Skipped: Marketing, Sales, Finance, Support — Today section is internal product surface, no orthogonal angle.

### Product (CPO)

Refined operator's signal taxonomy: GitHub PR-review/CI-fail/security-CVE = KEEP; P0/P1 = CONDITIONAL (label+freshness gate); KB-drift zero-hit-rules = NOISE; orphaned-constitution = CONDITIONAL (semantic conflict only). Flagged that KB-drift has no leader → direct-action affordance. Surfaced new vector (e): inadvertent disclosure via card body.

### Legal (CLO)

Required: new Article 30 row (GitHub as data source = distinct purpose); DPD update (GitHub Inc. as US-stored sub-processor, SCC-reliant for EU founders); `audit_github_token_use` before 2nd hosted founder (Art. 5(2)); redaction allowlist extension for GitHub-sourced card-body text; soft AUP clause for screenshare/redaction of cards. Treat PAT as legal blocker absent explicit founder ack — App install tokens preferred. Flagged processor-of-processor disclosure when founder connects an org containing their customers' repos.

### Engineering (CTO)

Premise corrections vs operator framing: `rule-metrics.json` + aggregator + nightly workflow all already exist (operator was right to cite them, my pre-spawn grep was wrong). `source_ref` is comment-only in migration 046 — partial-unique index requires migration 047. No production Octokit client today (only `auth/github-resolve` OAuth route exists) — webhook handler is net-new alongside `stripe/route.ts`. Hybrid ranking with surface cap. Two ADRs warranted.

### Operations (COO)

Webhook over polling for THIS slice; adds 1 endpoint + 3 alert rules. KB-drift cron in GH Actions (pre-checked-out tree). No new sub-processor, no paid-tier trigger. Inngest self-hosted Hetzner break-even ~3k events/day vs Cloud free-tier; well under threshold for single-tenant pilot. Re-eval at 5+ active tenants.

## Capability Gaps

1. **GitHub App provisioning runbook + IaC.** No prior runbook for App-creation. Evidence: `find apps/web-platform/infra -iname "*github*"` returns nothing; `grep -rn "GITHUB_APP_ID" apps/web-platform/ | grep -v test` returns no production references. Required before PR-H ships.
2. **`audit_github_token_use` table + RPC.** CLO blocker. Evidence: `grep -rn "audit_.*github" apps/web-platform/supabase/migrations/` returns no hits. Migration 047 carries it (alongside `source_ref`).
3. **Card-body redaction allowlist extension.** PR-A allowlist is LLM-output-scoped. Evidence: `lib/safety/redaction-allowlist.ts` (per PR-A #3240) covers Claude SDK output channels, not third-party text rendered in cards.
4. **KB-drift walker (broken-link + code-anchor checks).** No existing scanner. Evidence: `grep -rn "dead-link\|broken-link\|code-anchor" plugins/soleur/skills/ scripts/` returns no hits. Closest is `scripts/rule-metrics-aggregate.sh` (rule-hit stats, not KB integrity).
5. **Inngest event-publisher helper.** Stripe webhook hand-rolls `inngest.send()`; GitHub webhook will repeat. **Deferred** to follow-up refactor — premature abstraction at N=2.
6. **Knowledge/CKO leader role.** Operator chose direct-action MVP for KB-drift. **Deferred** — re-evaluate if a 2nd founder requests KB-source-with-leader symmetry.

## Out of Scope (Deferred)

| Item | Why deferred | Re-evaluate when |
|---|---|---|
| KB-drift "zero-hit rules >8w" signal | CPO NOISE: low-hit ≠ wrong; incident-response rules are rare-but-critical | Founder reports missing a stale rule that turned out wrong |
| KB-drift "orphaned constitution rules" signal | Requires LLM-judge for semantic conflict — most expensive of 4 candidates | After 30 days of broken-link + code-anchor evidence; if false-positive rate <5%, add semantic check |
| Knowledge/CKO leader role | Out-of-scope for AC closure | 2nd hosted founder requests KB-source delegation symmetry |
| Migration of GH Actions crons to Inngest scheduler | Parent plan TR9, tracked as #3948 | Per #3948's existing re-eval criteria |
| Inngest event-publisher helper extraction | N=2 is premature abstraction | When N=3 (any new webhook source) |
| Semantic re-anchor check for code-anchor drift (line text match) | OQ2 — existence check is cheap MVP | After 30 days of MVP signal; if existence-only misses real drift, add text-match |

## Bundled scoping — PR-H (Daily Priorities multi-source)

- **Brainstorm:** `knowledge-base/project/brainstorms/2026-05-19-daily-priorities-multi-source-brainstorm.md`
- **Spec:** `knowledge-base/project/specs/feat-daily-priorities-multi-source/spec.md`
- **Branch:** `feat-daily-priorities-multi-source`
- **Draft PR:** #4066
- **Brand-survival threshold:** `single-user incident` (carry-forward from PR-F)
- **Closes umbrella AC:** Daily Priorities dashboard ships with at least 3 signal sources + delegation
- **Deferrals** (filed as follow-up issues at Phase 3.6): 2 KB-drift signal classes; Knowledge/CKO role; semantic re-anchor check; Inngest publisher helper extraction
