---
category: docs
tags: [analytics, plausible, gdpr, pii, runbook, path-pii, ops]
date: 2026-04-18
deepened: 2026-04-18
issues: [2507, 2508]
source_pr: 2503
source_pr_merge_sha: 95d574eb77026da1fb1c50c0f32f5b463fc06dc5
source_pr_merged_at: 2026-04-17T19:16:02Z
related_issue: 2462
---

# Drain #2507 + #2508: Path-PII follow-ups (ops runbooks)

## Enhancement Summary

**Deepened on:** 2026-04-18
**Sections enhanced:** Research Reconciliation (added live-resolved merge SHA), Phase 1 (concrete Plausible Stats API v1 endpoints verified against the existing `scripts/weekly-analytics.sh`), Phase 2 (grep exclusions for expected hits), Risks (API-key scope check).

### Key Improvements

1. **Merge SHA resolved live from git, not memory.** PR #2503 (squash-merged 2026-04-17T19:16:02Z) committed as `95d574eb77026da1fb1c50c0f32f5b463fc06dc5` on `main`. Every "30 days after merge" reference in the runbook resolves to **2026-05-17**. Captured in the frontmatter so future readers can cross-check.
2. **Plausible Stats API v1 endpoints validated against existing repo patterns.** `scripts/weekly-analytics.sh` already uses `/api/v1/stats/aggregate` and `/api/v1/stats/breakdown` with `PLAUSIBLE_API_KEY` + `PLAUSIBLE_SITE_ID` from CI secrets. The erasure-runbook audit query reuses the identical auth pattern — no new secret, no new endpoint. This anchors the runbook against a known-working shape, not a speculative one. Reference: the `api_get` helper at `scripts/weekly-analytics.sh:210` and the breakdown invocation at `:304`.
3. **Institutional-learning alignment.** `knowledge-base/project/learnings/integration-issues/2026-03-13-plausible-analytics-operationalization-pattern.md` confirms the Stats API v1 pattern, credentials, and that `PLAUSIBLE_API_KEY` is the canonical env var (already wired in GitHub Actions secrets). The erasure runbook should cite this learning so an on-call with no Plausible context can self-onboard in one read.
4. **Grep false-positive carve-out.** The filter-audit runbook's own grep patterns produce expected hits against: (a) this plan file, (b) the two runbooks themselves, (c) `scripts/weekly-analytics.sh` and `scripts/provision-plausible-goals.sh`, (d) prior plans/specs for the scrubber (`2026-04-17-fix-analytics-track-path-pii-plan.md`, `feat-fix-analytics-track-path-pii/`). Explicitly carve these out in the runbook's grep template so a future auditor doesn't chase them.
5. **Breakdown query shape confirmed.** Plausible Stats API v1 supports filtering custom-event props via `filters=event:props:path==<value>` or `~<regex>` (contains). Documented at <https://plausible.io/docs/stats-api-v1> (authoritative). No `DELETE` endpoint exists — confirmed by search — which is why the cloud-deletion path is a support ticket, not an API call.

## Overview

PR #2503 (branch `fix-analytics-track-path-pii`, referenced in issue/PR #2462)
landed a server-side PII scrubber at `POST /api/analytics/track` that replaces
emails, UUIDs, and 6+ digit runs in the `path` prop with fixed sentinels
(`[email]`, `[uuid]`, `[id]`) before forwarding to Plausible.

Two review-origin scope-outs remain open:

- **#2507** — the scrubber does not remediate the pre-merge backlog. Events
  already stored in Plausible's `events_v2` table can still carry raw PII.
  GDPR Art. 17 / CCPA §1798.105 erasure requests therefore need a documented
  deletion path.
- **#2508** — any saved dashboard filter, BI query, or CSV-export key that
  was pinned to a raw PII path (e.g., `/users/alice@example.com/settings`)
  no longer matches post-merge events. Operators need a one-time audit step.

Both are **ops / documentation** work, not code. Scope-out justifications
(`pre-existing-unrelated`, co-signed by `code-simplicity-reviewer`) stand.
The purpose of this PR is to close the scope-outs by shipping the runbook
entries the issues prescribe — so a future operator hitting an erasure
request or a broken dashboard does not need to reconstruct the context.

**Single PR deliverable:** two new files in
`knowledge-base/engineering/ops/runbooks/`:

1. `plausible-pii-erasure.md` — remediation path for historical PII events
   (cloud Plausible via support request + self-hosted SQL template).
2. `plausible-dashboard-filter-audit.md` — one-time grep + config audit for
   filters pinned to raw paths, with the sentinel mapping.

Optionally cross-link the existing `apps/web-platform/app/api/analytics/track/sanitize.ts`
header comment to the new runbooks so a future maintainer landing on the
scrubber code discovers the historical-backlog context in one hop.

## Research Reconciliation — Spec vs. Codebase

| Spec claim (from issue bodies) | Reality (this worktree) | Plan response |
| --- | --- | --- |
| PR #2462 landed the path-PII scrub | The branch `fix-analytics-track-path-pii` was merged as **PR #2503** on 2026-04-17T19:16:02Z (not #2462 — that number is the issue this PR closed). Merge SHA `95d574eb77026da1fb1c50c0f32f5b463fc06dc5` resolved live via `git log --all --oneline --grep="2462"` on 2026-04-18. Both issues correctly reference #2462 as the triggering ticket. | Runbooks cite both numbers and the merge SHA to avoid confusion: `(issue #2462 → PR #2503 → commit 95d574e)`. |
| `knowledge-base/engineering/ops/runbooks/gdpr-erasure.md` might already exist | Confirmed absent. The ops/runbooks dir contains `cloudflare-service-token-rotation.md`, `disk-monitoring.md`, `supabase-migrations.md` only. | New file; no edit. Also per-vendor naming (`plausible-pii-erasure.md`) fits the existing one-file-per-vendor pattern better than a catch-all `gdpr-erasure.md`. |
| Scrubber sentinels are `[email]`, `[uuid]`, `[id]` | Confirmed in `app/api/analytics/track/sanitize.ts:61,66,68`. Regexes use length-bound pre-slice (`MAX_SCRUB_INPUT_LEN = 400`) and `.replace()` (no `.test()` gate) per PR-review P1. | Runbooks quote the exact regexes and sentinels so the SQL/Stats-API queries match what the scrubber produces. |
| Plausible Cloud has no bulk-delete API | Verified 2026-04-18: the Plausible Stats API is read-only (`/api/v1/stats/{breakdown,aggregate,timeseries}`); no `DELETE` endpoint. Ref: <https://plausible.io/docs/stats-api>. | Cloud path = Plausible support ticket with the exact path list. Self-hosted path = direct SQL against `events_v2`. |
| Self-hosted target table is `events_v2` | The Plausible OSS schema uses ClickHouse with a `plausible_events_db.events_v2` table. Ref: <https://github.com/plausible/community-edition/blob/main/db/clickhouse/events_v2.sql>. | Self-hosted template uses `ALTER TABLE ... DELETE WHERE ...` (ClickHouse idiom, not plain Postgres `DELETE`). Dry-run via `SELECT count()` first. |

## Open Code-Review Overlap

Query: `jq -r '.[] | select((.body // "") | contains("analytics-track") or contains("plausible") or contains("sanitize.ts"))' /tmp/open-review-issues.json`.

| Issue | Disposition | Rationale |
| --- | --- | --- |
| #2507 | **Fold in** — `Closes #2507` via `plausible-pii-erasure.md` | This is the subject of this PR. |
| #2508 | **Fold in** — `Closes #2508` via `plausible-dashboard-filter-audit.md` | This is the subject of this PR. |

No other open `code-review`-labeled issue touches `apps/web-platform/app/api/analytics/track/**`, `lib/analytics-client.ts`, or `knowledge-base/engineering/ops/runbooks/**`. Confirmed against 42 open issues in `/tmp/open-review-issues.json` (2026-04-18).

## Acceptance Criteria

### Pre-merge (PR)

- [ ] New file `knowledge-base/engineering/ops/runbooks/plausible-pii-erasure.md` exists.
  - [ ] YAML frontmatter with `category: compliance`, `tags: [plausible, gdpr, pii, erasure]`, `date: 2026-04-18`.
  - [ ] Sections: **Scope**, **Audit (identify affected events)**, **Deletion path (cloud)**, **Deletion path (self-hosted)**, **Privacy-policy note**, **Cross-references**.
  - [ ] Audit section includes a Plausible Stats API v1 `curl` invocation that matches the scrubber's three sentinels in a custom-props breakdown query (`property=event:props:path`, `filters=event:props:path~<regex>`), using the **same auth pattern as `scripts/weekly-analytics.sh:210`** (`Authorization: Bearer ${PLAUSIBLE_API_KEY}`). 2xx exit criterion, worked examples for `[email]` / `[uuid]` / `[id]`. Cites `https://plausible.io/docs/stats-api-v1`.
  - [ ] Audit section also includes the ClickHouse `SELECT count()` dry-run matching the three regexes in the `pathname` column of `events_v2`.
  - [ ] Deletion-cloud section includes the Plausible support-request template (subject line, body fields, data-controller signature line).
  - [ ] Deletion-self-hosted section includes the ClickHouse `ALTER TABLE plausible_events_db.events_v2 DELETE WHERE ...` template with a mandatory dry-run `SELECT` first and a change-control reminder.
  - [ ] Privacy-policy note explains retention-window semantics: historical raw paths remain until an erasure request triggers the deletion path.
  - [ ] Cross-references: AGENTS.md rule on PII regex design (`cq-*` — link to the scrubber source), `apps/web-platform/app/api/analytics/track/sanitize.ts`, `knowledge-base/project/plans/2026-04-17-fix-analytics-track-path-pii-plan.md`.
- [ ] New file `knowledge-base/engineering/ops/runbooks/plausible-dashboard-filter-audit.md` exists.
  - [ ] YAML frontmatter with `category: analytics`, `tags: [plausible, dashboard, filter, audit, path-pii]`, `date: 2026-04-18`.
  - [ ] Sections: **Scope**, **Sentinel mapping**, **Audit procedure**, **Remediation**, **Operator announcement template**, **Close-out criteria**.
  - [ ] Sentinel mapping block names all three sentinels with an example BEFORE/AFTER path for each.
  - [ ] Audit procedure includes: (a) grep command over `knowledge-base/**/*.md` for literal PII path segments (email, UUID, 6+ digits) — **with explicit carve-outs for expected hits**: this plan file, the two new runbooks themselves, `scripts/weekly-analytics.sh`, `scripts/provision-plausible-goals.sh`, `knowledge-base/project/plans/2026-04-17-fix-analytics-track-path-pii-plan.md`, `knowledge-base/project/specs/feat-fix-analytics-track-path-pii/`. (b) Checklist for BI tools (Looker / Metabase / Tableau / Grafana) — each entry a boxed checkbox the operator ticks off.
  - [ ] Remediation section shows how to rewrite a hardcoded path filter as a prefix filter (`/users/[uid]/`) or a sentinel filter (`/users/[id]/` against post-merge events).
  - [ ] Operator-announcement template: copy-pasteable one-liner for the team channel explaining the dashboard-semantics change (scoped to #2508 re-evaluation criteria).
  - [ ] Close-out criteria reflect the issue's own criterion: close as `wontfix` after 30 days post-merge-of-PR-#2503 if no operator reports a broken filter. Explicit calendar date: 2026-05-17 (30 days after 2026-04-17).
- [ ] Both files pass `npx markdownlint-cli2 --fix` with no warnings.
- [ ] Header comment in `apps/web-platform/app/api/analytics/track/sanitize.ts` references `plausible-pii-erasure.md` in the existing block (one-line add in the SCRUB_PATTERNS comment — non-load-bearing, but closes the discovery loop for a future maintainer). Use a grep-stable symbol anchor, not a line number (per `cq-code-comments-symbol-anchors-not-line-numbers`).
- [ ] PR body contains both `Closes #2507` and `Closes #2508` on separate lines.
- [ ] PR body summarises: no code behaviour change, two runbooks added, one comment cross-link.

### Post-merge (operator)

Neither runbook prescribes a post-merge action that blocks this PR — both are
dormant references that activate on an external trigger (GDPR request or
broken-dashboard report). The **Close-out criteria** inside
`plausible-dashboard-filter-audit.md` does prescribe a 30-day follow-up, but
that lives on the operator's calendar, not the merge gate for this PR.

## Files to Create

- `knowledge-base/engineering/ops/runbooks/plausible-pii-erasure.md`
- `knowledge-base/engineering/ops/runbooks/plausible-dashboard-filter-audit.md`

## Files to Edit

- `apps/web-platform/app/api/analytics/track/sanitize.ts` — **one-line addition** inside the existing `SCRUB_PATTERNS` block comment: `// Historical backlog / dashboard audit: see knowledge-base/engineering/ops/runbooks/plausible-pii-erasure.md and plausible-dashboard-filter-audit.md`. No behaviour change.

## Non-Goals

- **No code behaviour change.** The scrubber regexes, allowlist, and length
  bounds are unchanged. This PR does not alter runtime behaviour in any
  code path.
- **No backfill job.** Writing a job that replays historical `events_v2`
  rows through the sanitizer would require a Plausible write API that does
  not exist on Cloud, and would risk event duplication on self-hosted. The
  remediation path is deletion-on-request, not rewrite.
- **No dashboard-migration code.** The #2508 issue explicitly scopes the
  audit as an operator workflow. No programmatic filter-rewrite utility.
- **No new AGENTS.md rule.** The existing `cq-silent-fallback-must-mirror-to-sentry`
  and `cq-nextjs-route-files-http-only-exports` rules already cover the
  scrubber's surface. A rule mandating "runbook for every new sanitizer"
  would be over-reaching — the scrubber is a one-off, not a pattern to
  codify. (If a reviewer disagrees, file separately — not blocking.)
- **No change to `knowledge-base/product/roadmap.md`.** Both issues are
  already in the `Post-MVP / Later` milestone and are being **closed**, not
  moved — no roadmap edit required per `wg-when-moving-github-issues-between-milestones`.

## Test Strategy

Documentation-only change; no new test code.

**Verification steps (all runnable pre-merge):**

1. `npx markdownlint-cli2 --fix knowledge-base/engineering/ops/runbooks/plausible-pii-erasure.md knowledge-base/engineering/ops/runbooks/plausible-dashboard-filter-audit.md` — returns 0 with no remaining violations after fix pass.
2. `grep -n "plausible-pii-erasure" apps/web-platform/app/api/analytics/track/sanitize.ts` — returns one line.
3. Dry-run the Plausible Stats API `curl` from the erasure runbook against the Cloud prod site (authenticated with `PLAUSIBLE_API_KEY` from Doppler `prd` if present, otherwise skip — read-only request, no side effects). A 200 with a JSON body counts as the runbook's query syntax being correct. If the key is absent, note the skip in the PR body and move on.
4. `rg -i 'alice@example|[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|\b\d{6,}\b' knowledge-base/` — exercises the filter-audit runbook's own grep template. Findings that hit the two new runbook files are expected (they quote the regexes) and don't count as dashboards-referencing-PII.
5. Scan the existing analytics-track test suite locally to confirm no regression from the comment edit:
   `cd apps/web-platform && ./node_modules/.bin/vitest run test/api-analytics-track.test.ts test/sanitize-props.test.ts`. Must pass.

## Risks

- **Low — spec accuracy on Plausible internals.** The runbooks quote ClickHouse schema details (`events_v2`, column name `pathname`) and the Plausible Stats API surface. If either drifts before an erasure request arrives, the runbook becomes stale. Mitigation: every `SELECT` and `curl` in the runbooks is **template-with-placeholders** (not a fire-and-forget script), and the "Audit section" explicitly tells the operator to verify the schema shape with `DESCRIBE TABLE plausible_events_db.events_v2` first. Cite the current Plausible doc URL.
- **Medium — the scrubber regex set may evolve.** If a future PR adds a fourth sentinel (e.g., `[phone]`), the runbooks will under-match. Mitigation: the runbooks include a `## Regex source of truth` pointer to `apps/web-platform/app/api/analytics/track/sanitize.ts` and instruct the operator to re-read the `SCRUB_PATTERNS` constant before running the audit. (Symbol anchor, not line number — `cq-code-comments-symbol-anchors-not-line-numbers`.)
- **Low — 30-day close-out calendar date drift.** PR #2503 merged on 2026-04-17T19:16:02Z (commit `95d574e`), so 30 days = **2026-05-17**. If a reader recomputes from a different date source, the runbook shows both the merge date and the close-out date in the same sentence.
- **Low — `PLAUSIBLE_API_KEY` scope.** The key already provisioned for `scripts/weekly-analytics.sh` is read-only Stats API v1. That is sufficient for the erasure runbook's audit step — no write scope, no admin scope required. If the audit query returns 401/403, the fix is to rotate the key, not to add a new one.
- **None — regression risk.** The single code edit is a comment; `tsc --noEmit` and vitest are unaffected.

## Cross-document Consistency

This plan triggers no edits to:

- `knowledge-base/product/roadmap.md` — issues remain in `Post-MVP / Later`; they transition from open to closed, not from one phase to another.
- `AGENTS.md` — no new rule.
- Any other runbook — the two new files cross-reference `supabase-migrations.md`'s structure (YAML frontmatter, apply/verify/rollback sections) as the house style but don't modify it.

## Domain Review

**Domains relevant:** none (compliance docs).

Two runbooks drop into `knowledge-base/engineering/ops/runbooks/` and one
source-code comment pointer is updated. Both runbooks exist to enable the
CTO / ops-on-call to execute a GDPR erasure or run a one-time filter audit
without reconstructing the path-PII context from PR #2503 review threads.

No user-facing UI, no new copy shown to end users, no new data model, no new
vendor signup, no pricing or billing, no legal-doc change (the privacy-policy
note inside the runbook is **guidance to the operator about what to update in
a future pass**, not an inline policy edit). The existing `feat-gdpr-web-platform-rights`
spec and `2026-03-20-legal-dpd-web-platform-data-subject-rights-plan.md`
already cover the user-facing data-subject-rights flow — this PR is a
back-office enablement doc for the path the operator takes once a request
arrives.

Result: no cross-domain review required; infrastructure/tooling change.

## Implementation Phases

### Research Insights (applied during Phases 1-2)

**Reuse the weekly-analytics.sh API pattern.** `scripts/weekly-analytics.sh`
already uses the Plausible Stats API v1 in CI. The erasure-runbook audit
must mirror that exact auth shape so the same `PLAUSIBLE_API_KEY` (from
GitHub Actions secrets / Doppler `prd`) works:

```bash
# Pattern from scripts/weekly-analytics.sh:210 (api_get helper)
curl -sS -H "Authorization: Bearer ${PLAUSIBLE_API_KEY}" \
  "https://plausible.io/api/v1/stats/breakdown?site_id=${PLAUSIBLE_SITE_ID}&period=custom&date=2025-01-01,2026-04-17&property=event:page&filters=event:page~%5B%5Bemail%5D%5D&limit=100"
```

Note: Plausible strips query strings before storing the page prop, so the
audit filter runs against the stored `event:page` dimension. Use
`event:props:path` only if the call site was passing `props.path` explicitly
at the time of emission. Confirm by checking which dimension the scrubber
emits — per `apps/web-platform/lib/analytics-client.ts` (`track` function),
the app emits `path` as a **custom prop**, so `event:props:path` is the
correct dimension for the audit query.

**Citation source of truth:** the existing learning
`knowledge-base/project/learnings/integration-issues/2026-03-13-plausible-analytics-operationalization-pattern.md`
(Key Insight §) confirms that `compare=previous_period` + the breakdown
endpoint are the stable API v1 surface — use both runbooks' audit queries
with the same endpoints.

**Plausible Cloud has no `DELETE` API** (confirmed via Stats API v1 docs
and the Plausible CE schema). Erasure requests must go through support for
Cloud; self-hosted uses ClickHouse `ALTER TABLE ... DELETE WHERE`.

### Phase 1 — Draft `plausible-pii-erasure.md`

**Target file:** `knowledge-base/engineering/ops/runbooks/plausible-pii-erasure.md`

**Structure (match `supabase-migrations.md` house style):**

```markdown
---
category: compliance
tags: [plausible, gdpr, pii, erasure]
date: 2026-04-18
---

# Plausible PII Erasure: historical event backlog

## Scope

This runbook covers the one-off remediation path for raw-PII events stored
in Plausible **before** the path scrubber shipped in PR #2503 (issue #2462).
New events are sanitized at `POST /api/analytics/track` via
`app/api/analytics/track/sanitize.ts` — the `SCRUB_PATTERNS` constant — and
do not reach Plausible with raw emails, UUIDs, or 6+ digit runs.

Trigger this runbook on:

- A GDPR Art. 17 (Right to Erasure) or CCPA §1798.105 request naming a user
  whose events predate 2026-04-17.
- A legal review that asks "what about the pre-scrub backlog?"

## Regex source of truth

The three sentinels this runbook queries for are defined in
`apps/web-platform/app/api/analytics/track/sanitize.ts` under `SCRUB_PATTERNS`:

- `[email]` — matched by `[^\s/@]+(?:@|%40)[^\s/@]+\.[^\s/@]+`
- `[uuid]`  — matched by `[0-9a-f]{8}(?:-|%2d)[0-9a-f]{4}(?:-|%2d)[0-9a-f]{4}(?:-|%2d)[0-9a-f]{4}(?:-|%2d)[0-9a-f]{12}`
- `[id]`    — matched by `\d{6,}`

Re-read `SCRUB_PATTERNS` before running the audit if the scrubber has been
updated since this runbook was written.

## Audit (identify affected events)

### Cloud Plausible — Stats API breakdown

[curl template for /api/v1/stats/breakdown with property=event:props:path and filter=event:props:path~<regex>.
Doppler prd key fetch, JSON response shape, count interpretation.]

### Self-hosted Plausible — ClickHouse dry-run

[SELECT count() FROM plausible_events_db.events_v2 WHERE match(pathname, '…') — three queries,
one per sentinel. Always run SELECT before ALTER TABLE ... DELETE.]

## Deletion path (cloud)

[Support-request template: subject, body fields (controller name, path list, retention window),
signature. Link to Plausible support contact. Expected turnaround.]

## Deletion path (self-hosted)

[ALTER TABLE plausible_events_db.events_v2 DELETE WHERE match(pathname, '…') template.
Change-control checklist: dry-run SELECT first, backup, peer review, execute,
verify count dropped, log to incident ticket.]

## Privacy-policy note

[How to document the retention-window semantics in the privacy policy / DPA:
historical raw paths exist until an erasure request triggers this runbook.
Link to existing legal docs.]

## Cross-references

- Scrubber source: `apps/web-platform/app/api/analytics/track/sanitize.ts` (`SCRUB_PATTERNS`)
- Scrubber plan: `knowledge-base/project/plans/2026-04-17-fix-analytics-track-path-pii-plan.md`
- Plausible Stats API docs: https://plausible.io/docs/stats-api
- Plausible CE events_v2 schema: https://github.com/plausible/community-edition
- AGENTS.md rule on PII regex design: `cq-` (see the scrubber's `SCRUB_PATTERNS` comment)
- Filter audit runbook: `plausible-dashboard-filter-audit.md` (sibling)
- Related issues: #2462 (root), #2503 (merged PR that shipped the scrubber), #2507 (this runbook), #2508 (filter audit)
```

Fill the bracketed sections with the exact templates. Target length: ~200
lines matching `supabase-migrations.md`.

### Phase 2 — Draft `plausible-dashboard-filter-audit.md`

**Target file:** `knowledge-base/engineering/ops/runbooks/plausible-dashboard-filter-audit.md`

**Structure:**

```markdown
---
category: analytics
tags: [plausible, dashboard, filter, audit, path-pii]
date: 2026-04-18
---

# Plausible Dashboard Filter Audit after path-PII sentinel rollout

## Scope

One-time audit after PR #2503 (issue #2462) replaced raw PII path tokens in
Plausible events with fixed sentinels. Any saved dashboard filter, BI query,
or CSV-export key pinned to a raw path (e.g., `/users/alice@example.com/settings`)
will no longer match post-merge events.

**Expected blast radius: low.** Per #2508, path cardinality was already
unbounded pre-scrub (one unique path per user), so any filter pinned to a
raw path was already a degenerate aggregate. This audit surfaces and fixes
the ad-hoc cases.

## Sentinel mapping

| Raw path prefix (pre-2026-04-17) | Post-scrub path | Sentinel |
| --- | --- | --- |
| `/users/alice@example.com/settings` | `/users/[email]/settings` | `[email]` |
| `/kb/docs/550e8400-e29b-41d4-a716-446655440000` | `/kb/docs/[uuid]` | `[uuid]` |
| `/billing/customer/123456/invoices` | `/billing/customer/[id]/invoices` | `[id]` |

## Audit procedure

### 1. Knowledge-base grep

[rg pattern over knowledge-base/**/*.md for literal PII path segments (email shape, UUID shape, 6+ digits).
Expected hits: this runbook + plausible-pii-erasure.md + scrubber plan — those quote the regexes.
Any other hit is a candidate dashboard filter ref.]

### 2. BI / dashboard tool checklist

Check each configured integration:

- [ ] Plausible built-in dashboards (shared-link filters, saved views)
- [ ] Looker Studio — Plausible data source filters
- [ ] Metabase — any Plausible native queries
- [ ] Tableau — any extracts sourcing Plausible Stats API
- [ ] Grafana — any Plausible datasource panels

Per integration:

1. Open filter / query definition.
2. Grep for `@`, UUID shape, or 6+ digit runs in path literals.
3. If found, see Remediation.

## Remediation

Replace a raw-PII filter with either:

- **Prefix filter** (preferred): `path starts with /users/` — catches all user
  routes without depending on the ID.
- **Sentinel filter**: `path contains /[email]/` — matches post-scrub events
  that carried an email. Does not match historical rows; combine with a
  time-window filter that starts on the PR #2503 merge date (2026-04-17).

## Operator announcement template

Post once in #engineering after this PR merges:

> Heads-up: `/api/analytics/track` now scrubs emails, UUIDs, and 6+ digit
> runs from the `path` prop before forwarding to Plausible. Any saved
> dashboard or BI query pinned to a raw-PII path will silently stop
> matching post-2026-04-17 events. See
> `knowledge-base/engineering/ops/runbooks/plausible-dashboard-filter-audit.md`
> for the audit + remediation procedure.

## Close-out criteria

Per #2508: close `wontfix` on **2026-05-17** (30 days after PR #2503 merge
on 2026-04-17) if no operator has reported a broken filter.

Reopen only if a saved dashboard query surfaces that was depending on raw
PII paths.

## Cross-references

- Scrubber source: `apps/web-platform/app/api/analytics/track/sanitize.ts` (`SCRUB_PATTERNS`)
- Erasure runbook: `plausible-pii-erasure.md` (sibling)
- Issues: #2462 (root), #2503 (scrubber PR), #2508 (this runbook), #2507 (erasure)
```

### Phase 3 — Source-comment cross-link

One-line edit in `apps/web-platform/app/api/analytics/track/sanitize.ts`
inside the existing comment above `SCRUB_PATTERNS`. The addition:

```text
// Historical backlog and dashboard audit: see
// knowledge-base/engineering/ops/runbooks/plausible-pii-erasure.md and
// plausible-dashboard-filter-audit.md.
```

Placement: immediately before the existing `const SCRUB_PATTERNS = …` line
(after the regex rationale comment already in place). Uses symbol anchors
(`SCRUB_PATTERNS`), not line numbers.

### Phase 4 — Lint + verify

1. `npx markdownlint-cli2 --fix knowledge-base/engineering/ops/runbooks/plausible-pii-erasure.md knowledge-base/engineering/ops/runbooks/plausible-dashboard-filter-audit.md`
2. `cd apps/web-platform && ./node_modules/.bin/vitest run test/api-analytics-track.test.ts test/sanitize-props.test.ts` — must pass.
3. Re-read the two runbooks from disk after markdownlint's autofix pass (per `cq-always-run-npx-markdownlint-cli2-fix-on`).

### Phase 5 — Commit, push, open PR

1. `git add knowledge-base/engineering/ops/runbooks/plausible-pii-erasure.md knowledge-base/engineering/ops/runbooks/plausible-dashboard-filter-audit.md apps/web-platform/app/api/analytics/track/sanitize.ts knowledge-base/project/plans/2026-04-18-docs-path-pii-followups-plausible-erasure-and-filter-audit-plan.md`
2. `git commit -m "docs(ops): drain path-PII scope-outs #2507 + #2508"`
3. `git push -u origin feat-one-shot-close-2507-2508-path-pii-followups`
4. `gh pr create --title "docs(ops): drain path-PII scope-outs #2507 + #2508" --body "..."` — PR body MUST contain `Closes #2507` and `Closes #2508` on separate lines per `wg-use-closes-n-in-pr-body-not-title-to`.

## Alternative Approaches Considered

| Approach | Why not |
| --- | --- |
| Write a catch-all `gdpr-erasure.md` covering every data store | Issue #2507 already notes this as a "companion issue if not yet exists". The ops/runbooks dir uses one-file-per-vendor (`cloudflare-service-token-rotation.md`, `supabase-migrations.md`). Plausible-scoped runbook fits the pattern. A cross-vendor GDPR erasure index can come later. |
| Script a programmatic dashboard-filter rewriter | #2508 explicitly scopes as operator work. The set of BI tools and shared-link filters is not uniformly API-accessible (Plausible shared links are opaque UUIDs with no bulk-edit endpoint). Scripting would save minutes at best and introduces drift risk. |
| Add a Terraform-managed dashboard/filter bundle | No Plausible Terraform provider exists as of 2026-04-18. Would be a from-scratch provider; vastly outsized for the close-the-scope-out mandate. |
| Add an AGENTS.md rule requiring a runbook for every new sanitizer | Over-reaching. Single-instance pattern; codifying would clutter AGENTS.md per `cq-agents-md-why-single-line`. |
| Close as wontfix without a runbook | Leaves the next on-call without the context — violates the "invisible deferral" concern that motivates `wg-when-deferring-a-capability-create-a`. The runbooks ARE the deferral-to-runnable-artifact. |

## PR body template

```text
Closes #2507
Closes #2508

## Summary

Drains the two review-origin scope-outs filed against PR #2503 (issue #2462,
path-PII scrubber). Both are ops/documentation work — no runtime code
changes.

- `plausible-pii-erasure.md`: audit + deletion templates for the
  historical Plausible event backlog (cloud via support request, self-hosted
  via ClickHouse). Referenced by a GDPR Art. 17 / CCPA §1798.105 request
  that names a user whose events predate 2026-04-17.
- `plausible-dashboard-filter-audit.md`: one-time audit + remediation
  procedure for saved dashboard filters / BI queries / CSV exports pinned
  to raw PII paths. Ships the sentinel mapping and operator-announcement
  template. Close-out criterion: wontfix on 2026-05-17 if no operator
  reports a broken filter.

## Test plan

- [ ] `npx markdownlint-cli2 --fix` passes on both new files.
- [ ] `vitest run test/api-analytics-track.test.ts test/sanitize-props.test.ts` passes (comment-only source edit).
- [ ] Plausible Stats API `curl` template dry-runs against prod (authenticated with `PLAUSIBLE_API_KEY` from Doppler if available; otherwise skip with a PR-body note).
- [ ] `grep` template in filter-audit runbook runs clean (the two new runbook files themselves are expected hits).
```

## Sharp Edges

- **Spec drift on Plausible internals.** The ClickHouse schema (`events_v2.pathname`) and the Plausible Stats API surface are external contracts. Every template in the erasure runbook MUST use placeholder syntax and instruct the operator to verify the column name with `DESCRIBE TABLE` before running mutations. Encoded into the acceptance criteria.
- **Source comment rot.** The sanitize.ts comment points at two new runbooks. If the runbooks are moved or renamed, the comment goes stale silently — `cq-code-comments-symbol-anchors-not-line-numbers` protects against LINE drift but not FILE-PATH drift. Mitigation: check symmetry during compound (if compound detects the files moved, flag both pointers). Acceptable residual risk.
- **30-day close-out bookkeeping.** The dashboard-filter audit runbook prescribes a `wontfix` close on 2026-05-17. No automation schedules this. Acceptable — the operator-announcement template in the runbook and the close-out section of the runbook itself are the dual reminders. If the ops team wants calendar automation, file a separate tracking issue.
- **Compound run required.** Per `wg-before-every-commit-run-compound-skill`, `skill: soleur:compound` must run before commit. The compound run should route any learnings captured in the drafting process to AGENTS.md / `knowledge-base/project/learnings/` rather than inlining them in the PR body.
