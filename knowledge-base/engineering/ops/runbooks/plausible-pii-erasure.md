---
category: compliance
tags: [plausible, gdpr, pii, erasure]
date: 2026-04-18
---

# Plausible PII Erasure: historical event backlog

Use this runbook any time a GDPR Art. 17 (Right to Erasure) or CCPA
§1798.105 request names a user whose Plausible events predate the
server-side path scrubber that shipped in PR #2503 (issue #2462), merged
to `main` as commit `95d574eb77026da1fb1c50c0f32f5b463fc06dc5` on
2026-04-17T19:16:02Z.

The enforcing rule is AGENTS.md `wg-when-deferring-a-capability-create-a`
(the deferral tracked by issue #2507 becomes this runbook's invocation).

## Scope

The path scrubber at `POST /api/analytics/track` (see
`apps/web-platform/app/api/analytics/track/sanitize.ts`, symbol
`SCRUB_PATTERNS`) replaces emails, UUIDs, and 6+ digit runs in the `path`
custom prop with fixed sentinels before the event is forwarded to
Plausible. **New events are safe.** This runbook exists for the historical
backlog: events stored in Plausible's `events_v2` table before the merge
can still carry raw PII in the `pathname` column and `props` map.

Trigger this runbook on:

- A data-subject erasure request (GDPR Art. 17, CCPA §1798.105, or an
  equivalent regional regulation) that names a user whose events predate
  2026-04-17.
- A legal review that surfaces the pre-scrub backlog independently (for
  example during a DPA renegotiation or a privacy-policy audit).

Do **not** trigger this runbook for post-merge events. The scrubber is
deterministic and the sentinels are irreversible — there is nothing to
erase that is not already a sentinel.

## Regex source of truth

The three sentinels this runbook queries for are the ones defined in
`apps/web-platform/app/api/analytics/track/sanitize.ts` under the
`SCRUB_PATTERNS` symbol. As of 2026-04-18 they are:

- Sentinel `[email]` — regex `/[^\s/@]+(?:@\|%40)[^\s/@]+\.[^\s/@]+/gi` — triggers on an email literal or its percent-encoded form.
- Sentinel `[uuid]` — regex `/[0-9a-f]{8}(?:-\|%2d)[0-9a-f]{4}(?:-\|%2d)[0-9a-f]{4}(?:-\|%2d)[0-9a-f]{4}(?:-\|%2d)[0-9a-f]{12}/gi` — triggers on any 8-4-4-4-12 hex (v1..v5).
- Sentinel `[id]` — regex `/\d{6,}/g` — triggers on 6+ consecutive decimal digits.

The `\|` escapes above are a markdown rendering artefact; the actual regexes in
`SCRUB_PATTERNS` use a literal `|` alternation.

**Re-read `SCRUB_PATTERNS` at the symbol anchor before running the audit
below** (per AGENTS.md `cq-code-comments-symbol-anchors-not-line-numbers`).
If a fourth sentinel has been added, extend this runbook's audit queries
in lock-step.

## Audit — identify affected events

### Cloud Plausible — Stats API v1 breakdown

The Plausible Stats API v1 is read-only; use it to count how many events
in the retention window match the raw-PII shapes. The API key and site
ID are the same ones that `scripts/weekly-analytics.sh` uses — no new
secret is required.

Fetch the key from Doppler and run one breakdown per sentinel:

```bash
# Fetch the same read-only key scripts/weekly-analytics.sh uses.
PLAUSIBLE_API_KEY="$(doppler secrets get PLAUSIBLE_API_KEY -p soleur -c prd --plain)"
PLAUSIBLE_SITE_ID="$(doppler secrets get PLAUSIBLE_SITE_ID -p soleur -c prd --plain)"

# Retention window: from first-event to the merge date (2026-04-17).
FROM="2024-01-01"
TO="2026-04-17"

# Plausible Stats API v1 supports a "contains regex" operator via `~` on
# the event:props:path dimension. One query per sentinel. Replace
# <regex> inline before the call.
curl -sS -H "Authorization: Bearer ${PLAUSIBLE_API_KEY}" \
  "https://plausible.io/api/v1/stats/breakdown?site_id=${PLAUSIBLE_SITE_ID}&period=custom&date=${FROM},${TO}&property=event:props:path&filters=event:props:path~<regex>&limit=1000"
```

Regex values to substitute for `<regex>` (URL-encoded once):

- Email: `%5B%5E%5Cs%2F%40%5D%2B(%3F%3A%40%7C%2540)%5B%5E%5Cs%2F%40%5D%2B%5C.%5B%5E%5Cs%2F%40%5D%2B`
- UUID: `%5B0-9a-f%5D%7B8%7D(-%7C%252d)%5B0-9a-f%5D%7B4%7D(-%7C%252d)%5B0-9a-f%5D%7B4%7D(-%7C%252d)%5B0-9a-f%5D%7B4%7D(-%7C%252d)%5B0-9a-f%5D%7B12%7D`
- Digit-run: `%5Cd%7B6%2C%7D`

Response shape (expected): JSON with a `results` array; each entry is
`{ "path": "<unique-path>", "visitors": <int>, "pageviews": <int> }`. A
2xx with an empty `results` means no matches — close the erasure request
with a null-finding note. A non-zero count is the candidate set for
deletion.

**Preserve the JSON output.** Redact the values before attaching to an
internal ticket — the `path` field is the PII you are trying to erase.
Attach counts only, or use `jq 'del(.results[].path)'` before the paste.

### Self-hosted Plausible — ClickHouse dry-run

For the self-hosted edition (Plausible Community Edition on ClickHouse),
the dry-run is a `SELECT count()` per sentinel against
`plausible_events_db.events_v2`. Run the pre-flight first — the schema
can drift between CE releases:

```sql
-- 0. Schema pre-flight: confirm the column we query still exists.
DESCRIBE TABLE plausible_events_db.events_v2;

-- 1. Email-shaped pathnames.
SELECT count() FROM plausible_events_db.events_v2
WHERE match(pathname, '[^\\s/@]+(@|%40)[^\\s/@]+\\.[^\\s/@]+');

-- 2. UUID-shaped pathnames.
SELECT count() FROM plausible_events_db.events_v2
WHERE match(pathname, '[0-9a-f]{8}(-|%2d)[0-9a-f]{4}(-|%2d)[0-9a-f]{4}(-|%2d)[0-9a-f]{4}(-|%2d)[0-9a-f]{12}');

-- 3. 6+ consecutive digit runs in pathname.
SELECT count() FROM plausible_events_db.events_v2
WHERE match(pathname, '\\d{6,}');
```

A zero count across all three → close the request with a null-finding.
Any non-zero count is the set that the deletion step below removes.

If the event emits `path` as a **custom prop** (per
`apps/web-platform/lib/analytics-client.ts`) rather than as the
`pathname` column, swap the column to the prop-map lookup:
`props['path']` (ClickHouse-CE stores custom props in a parallel `Map`
column named `props`). Both forms may coexist in historical data; run
both before asserting a null finding.

## Deletion path — Cloud Plausible (support request)

Plausible Cloud exposes no `DELETE` endpoint (confirmed against the
Stats API v1 as of 2026-04-18). Erasure proceeds via a support ticket.

Template:

> **Subject:** GDPR Art. 17 / CCPA §1798.105 erasure — site
> `<PLAUSIBLE_SITE_ID>`
>
> **Body:**
>
> Hello Plausible team,
>
> Acting as the data controller for `<PLAUSIBLE_SITE_ID>`, we request
> erasure of events matching the path patterns below from the site's
> historical data (retention window: `<FROM>` to `2026-04-17`). All
> events after 2026-04-17 are scrubbed server-side and do not carry the
> PII in question.
>
> **Patterns to erase (custom prop `path` or column `pathname`):**
>
> - Email-shaped: `/[^\s/@]+(?:@|%40)[^\s/@]+\.[^\s/@]+/i`
> - UUID-shaped (v1..v5): `/[0-9a-f]{8}(?:-|%2d)[0-9a-f]{4}(?:-|%2d)[0-9a-f]{4}(?:-|%2d)[0-9a-f]{4}(?:-|%2d)[0-9a-f]{12}/i`
> - 6+ consecutive digits: `/\d{6,}/`
>
> If narrower targeting is preferred, the specific user identifier(s)
> at issue are attached out-of-band via `<secure channel>`.
>
> Please confirm (a) the number of rows deleted and (b) the run time in
> UTC, and we will record both in our internal compliance log.
>
> Regards,
> `<data controller name>`
> `<data controller email>`

Expected turnaround (2026-04 baseline): 5-10 business days. Log the
ticket ID, the support reply, and the row count in the internal
compliance ticket that triggered this runbook.

## Deletion path — Self-hosted Plausible (ClickHouse)

> Only run after a successful dry-run (`SELECT count()`), a database
> backup, and a peer review. `ALTER TABLE … DELETE` is a mutation in
> ClickHouse and is asynchronous — monitor `system.mutations` for
> completion.

Change-control checklist:

- [ ] Dry-run `SELECT count()` per sentinel has been run and the counts
      are captured in the compliance ticket.
- [ ] A ClickHouse snapshot / logical backup was taken immediately
      before the mutation.
- [ ] A second on-call has reviewed the `ALTER TABLE` statement.
- [ ] An incident channel is open for the duration of the mutation.

Template:

```sql
-- Emails.
ALTER TABLE plausible_events_db.events_v2
DELETE WHERE match(pathname, '[^\\s/@]+(@|%40)[^\\s/@]+\\.[^\\s/@]+');

-- UUIDs.
ALTER TABLE plausible_events_db.events_v2
DELETE WHERE match(pathname, '[0-9a-f]{8}(-|%2d)[0-9a-f]{4}(-|%2d)[0-9a-f]{4}(-|%2d)[0-9a-f]{4}(-|%2d)[0-9a-f]{12}');

-- 6+ digit runs.
ALTER TABLE plausible_events_db.events_v2
DELETE WHERE match(pathname, '\\d{6,}');

-- Monitor:
SELECT mutation_id, create_time, is_done
FROM system.mutations
WHERE table = 'events_v2'
ORDER BY create_time DESC LIMIT 5;
```

Post-mutation verification: re-run the three `SELECT count()` statements
from the dry-run section. All three must return `0` before closing the
compliance ticket. If the event used the `props['path']` map column,
rewrite each `ALTER TABLE` clause against `props['path']` and re-run.

## Privacy-policy note

After a historical erasure completes, update the privacy policy's
retention-window section to reflect that pre-2026-04-17 events may
contain raw path data until an erasure request is processed. The
post-merge retention window is unaffected (path data is sanitized at
ingest). The canonical copy lives in the legal documents under
`knowledge-base/legal/` — update the data-retention subsection the next
time a broader privacy-policy revision is due. Do not open a separate PR
for this edit; it is a batched documentation change.

## Cross-references

- Scrubber source: `apps/web-platform/app/api/analytics/track/sanitize.ts`, symbol `SCRUB_PATTERNS`.
- Scrubber plan: `knowledge-base/project/plans/2026-04-17-fix-analytics-track-path-pii-plan.md`.
- Sibling runbook: `plausible-dashboard-filter-audit.md` (one-time audit for saved dashboards that pinned raw paths).
- Plausible Stats API v1: <https://plausible.io/docs/stats-api-v1>.
- Plausible Community Edition schema: <https://github.com/plausible/community-edition>.
- Existing script using the same credentials: `scripts/weekly-analytics.sh` (`api_get` helper, `PLAUSIBLE_API_KEY` + `PLAUSIBLE_SITE_ID`).
- Plausible operationalization pattern: `knowledge-base/project/learnings/integration-issues/2026-03-13-plausible-analytics-operationalization-pattern.md`.
- Related issues: #2462 (root review comment), #2503 (merged PR that shipped the scrubber), #2507 (this runbook), #2508 (filter audit).
