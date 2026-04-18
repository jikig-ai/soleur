---
category: analytics
tags: [plausible, dashboard, filter, audit, path-pii]
date: 2026-04-18
---

# Plausible Dashboard Filter Audit after path-PII sentinel rollout

One-time audit after PR #2503 (issue #2462) replaced raw PII path tokens
in Plausible events with fixed sentinels. Merged to `main` as commit
`95d574eb77026da1fb1c50c0f32f5b463fc06dc5` on 2026-04-17T19:16:02Z.

The enforcing rule is AGENTS.md `wg-when-deferring-a-capability-create-a`
(the deferral tracked by issue #2508 becomes this runbook's invocation).

## Scope

Any saved dashboard filter, BI query, shared-link filter, or CSV-export
key that was pinned to a raw PII path (for example
`/users/alice@example.com/settings`) will no longer match events emitted
after 2026-04-17. The scrubber rewrites those paths to sentinel form at
ingest — see `apps/web-platform/app/api/analytics/track/sanitize.ts`
(`SCRUB_PATTERNS`).

Expected blast radius is **low**: path cardinality was already unbounded
pre-scrub (one unique path per user), so any dashboard that pinned a
single raw path was already a degenerate aggregate. This audit surfaces
and fixes any ad-hoc cases that exist.

## Sentinel mapping

| Raw path (pre-2026-04-17)                            | Post-scrub path                       | Sentinel  |
| ---------------------------------------------------- | ------------------------------------- | --------- |
| `/users/alice@example.com/settings`                  | `/users/[email]/settings`             | `[email]` |
| `/kb/docs/550e8400-e29b-41d4-a716-446655440000`      | `/kb/docs/[uuid]`                     | `[uuid]`  |
| `/billing/customer/123456/invoices`                  | `/billing/customer/[id]/invoices`     | `[id]`    |

Full regex definitions live in `plausible-pii-erasure.md` (sibling
runbook) and in the scrubber source at the `SCRUB_PATTERNS` symbol.

## Audit procedure

### 1. Knowledge-base grep

Run this once to surface any committed dashboard definition, SQL note,
or BI export spec that pinned a raw PII path:

```bash
rg -n -i \
  -e '\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b' \
  -e '\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b' \
  -e '\b\d{6,}\b' \
  -g '*.md' \
  knowledge-base/
```

Expected hits (these are the runbook and scrubber docs quoting the
patterns — not dashboards):

- `knowledge-base/engineering/ops/runbooks/plausible-pii-erasure.md`
- `knowledge-base/engineering/ops/runbooks/plausible-dashboard-filter-audit.md`
- `knowledge-base/project/plans/2026-04-17-fix-analytics-track-path-pii-plan.md`
- `knowledge-base/project/plans/2026-04-18-docs-path-pii-followups-plausible-erasure-and-filter-audit-plan.md`
- `knowledge-base/project/specs/feat-fix-analytics-track-path-pii/`
- `knowledge-base/project/specs/feat-one-shot-close-2507-2508-path-pii-followups/`
- Any prior learning file that quoted a sample raw-PII path.

Any hit outside the list above is a candidate dashboard or filter
reference — inspect and remediate (next section). If the hit is itself a
historical incident note that references a user's identity, open a
separate issue; do not mutate institutional learning files as part of
this audit.

### 2. BI / dashboard tool checklist

Walk each currently-configured Plausible integration:

- [ ] Plausible built-in dashboards — shared-link filters and saved views.
- [ ] Looker Studio — Plausible data source filters.
- [ ] Metabase — any Plausible native queries or saved questions.
- [ ] Tableau — any extracts sourcing the Plausible Stats API.
- [ ] Grafana — any Plausible datasource panels.

Per integration:

1. Open each filter / query definition.
2. Grep (or visually scan) for `@`, a UUID shape, or any 6+ digit run
   inside a `path` literal.
3. If a match is found, apply the remediation below.

Record each integration's audit result (pass / fixed / not applicable)
in the close-out section of the compliance ticket that triggered this
runbook.

## Remediation

Replace a raw-PII filter with one of these shapes:

- **Prefix filter (preferred):** `path starts with /users/` captures
  every user route without depending on the identifier. This is
  structure-aware and time-range-independent.
- **Sentinel filter:** `path contains /[email]/` matches post-scrub
  events that carried an email. **Combine with a time-window filter
  starting 2026-04-17**; sentinels do not exist before that date, so a
  sentinel-only filter across a window that straddles the merge will
  under-count.
- **Regex filter:** if the dashboard needs to match both historical and
  post-scrub events, use a regex that accepts either the PII shape OR
  the sentinel. Only adopt this if the sentinel-only filter produces a
  material under-count; otherwise prefer the prefix filter.

## Operator announcement template

Post once in #engineering immediately after this PR merges so no operator
silently hits a stale filter:

> Heads-up: `/api/analytics/track` now scrubs emails, UUIDs, and 6+
> digit runs from the `path` prop before forwarding to Plausible, as of
> 2026-04-17. Any saved dashboard, BI query, or shared-link filter
> pinned to a raw-PII path will silently stop matching events from that
> date forward. See
> `knowledge-base/engineering/ops/runbooks/plausible-dashboard-filter-audit.md`
> for the audit + remediation procedure. Report a broken dashboard in
> this thread by 2026-05-17 so we can decide whether to re-open #2508.

## Close-out criteria

Per issue #2508's re-evaluation criterion: **close `wontfix` on
2026-05-17** (30 days after PR #2503 merged on 2026-04-17) if no
operator has reported a broken dashboard or filter by that date.

Reopen only if a saved dashboard, shared link, or BI query is reported
as having broken because of the sentinel rollout. If reopened, the
remediation section above is the prescription.

## Cross-references

- Scrubber source: `apps/web-platform/app/api/analytics/track/sanitize.ts`, symbol `SCRUB_PATTERNS`.
- Sibling runbook: `plausible-pii-erasure.md` (historical-event erasure path).
- Scrubber plan: `knowledge-base/project/plans/2026-04-17-fix-analytics-track-path-pii-plan.md`.
- Plausible Stats API v1: <https://plausible.io/docs/stats-api-v1>.
- Related issues: #2462 (root), #2503 (merged scrubber PR), #2508 (this runbook), #2507 (erasure runbook).
