# Legal acceptance: read a Request changes note, reconcile a row, triage the signals

Pull-only (ADR-319, amendment 2026-11-05). The note lives only in `legal_acceptance.requested_edit`; nothing pushes it
anywhere (no email, issue or chat). The operator reads it personally, never an agent session: the verify endpoint returns
`status`, `text_hash`, `decided_at` and `row_ok` only. The note is not readable through the endpoint or through any
`service_role` path. This is a rule for you to follow, not a technical block: a database-owner credential could read it, and
you hold that credential, and so does the production migration pipeline (a CI secret that runs the migrate and verify steps); no agent session is meant to use either, which is a rule and not a control. Never paste the note into an agent session.

Every query below runs in the SQL editor of the **production Supabase project** (prd), signed in with your own login: no ssh,
no service key. Dev and prd are distinct projects; a row in dev is not a row in prd. Every query is scoped to the one founder id
the endpoint is configured with, `LEGAL_ACCEPTANCE_FOUNDER_ID`, because the flag is global and the key is
`(founder_id, key, text_hash)`.

## Read a note

List the rows (no note text), then read one by key and hash:

```sql
select founder_id, key, version, text_hash, created_at from public.legal_acceptance
 where founder_id = '<LEGAL_ACCEPTANCE_FOUNDER_ID>' and choice = 'request_changes' order by created_at desc;
select requested_edit from public.legal_acceptance
 where founder_id = '<LEGAL_ACCEPTANCE_FOUNDER_ID>' and choice = 'request_changes' and key = '<key>' and text_hash = '<64 hex>';
```

Do not forward, quote or paste the note into a ticket, pull request, chat or agent session; describe any change in your own
words.

## Publish a revised text

A decision is final for its text hash. Edit `apps/web-platform/server/legal-acceptance/texts/<key>.md`: the new bytes give a
new `text_hash`, so the founder is asked again and a new row is written. A Decline needs the same. A hold that named the old
hash stays held until its gate names the new one.

## Rows with no acknowledgement

List the decision rows that have no acknowledgement (the endpoint only looks at a row when it is asked about it, so this is the
way to see them all):

```sql
select l.id, l.key, l.text_hash, l.choice, l.created_at
  from public.legal_acceptance l
  left join public.legal_acceptance_ack a on a.acceptance_id = l.id
 where l.founder_id = '<LEGAL_ACCEPTANCE_FOUNDER_ID>' and a.acceptance_id is null
 order by l.created_at desc;
```

## A Sentry event `op=row_without_event`

It means the web route recorded no acknowledgement for that row; the event carries the key and the text hash. A row that is
less than two minutes old is not yet reported (the grace). It is alert-only (if the reconciliation read itself fails, the endpoint answers 503 or 502, never a partial 200). Confirm with the founder that
the decision was theirs, then add the acknowledgement:

```sql
insert into public.legal_acceptance_ack (acceptance_id)
select id from public.legal_acceptance
 where founder_id = '<LEGAL_ACCEPTANCE_FOUNDER_ID>' and key = '<key>' and text_hash = '<64 hex>'
on conflict do nothing;
```

The `acked_at` of a row you insert is the time you inserted it, not the time the event was flushed, and a manually inserted acknowledgement is not proof that the event was ever sent; it only silences the signal for a row you have checked with the founder. Then **resolve** the Sentry
issue (never archive it, so that a recurrence reopens it). If the founder does not recognise the decision, leave the row as it
is and escalate; the record is evidence.

A missing `row_without_event` is not proof that the `accepted` event was delivered: a `true` result from the event flush means
the flush completed without an error, not that Sentry received and kept the event (it can also be `true` when no DSN is
configured, or when the event was dropped before sending). The signal proves only the converse, that the web route did not
acknowledge a row.

## Triage: `record_invalid` and `store_failed`

`record_invalid`: a stored row failed its checksum (the endpoint passed it through as `invalid`, `row_ok` false; the gate keeps
the hold). Do not edit the row. Treat it as a possible integrity incident: escalate to the CLO and CTO and assess it against
`knowledge-base/legal/breach-register.md`. The event carries the key and the text hash.

`store_failed`: read the tag `stage`.

| stage | What failed | What to do |
|---|---|---|
| `verify` | The lookup call in the endpoint | Check that migrations 184 and 185 are applied in prd and that Supabase is up; the gate shows "not available right now" and retries cleanly. |
| `ack_state` | The reconciliation read in the endpoint | Same check; a "function not found" answer means the migration or the schema cache; the endpoint answered 503 and no 200. |
| `ack` | The decide path could not write the acknowledgement (the flush threw, or the write failed) | The decision itself is recorded. The row will show as `row_without_event` when verified; reconcile it as above. |
| `registry` | The legal text file could not be read, or is malformed | Read the error `code` on the event (`extra.code`). `read_failed`: the texts directory is missing or unreadable in the image; redeploy a build that contains `server/legal-acceptance/texts`. Any other code: the committed text file is malformed; edit the file. Nothing is wrong with the database either way. |
| 401 (no event) | A caller sent a wrong or missing token | Unthrottled by design and not an event; paging is #12195. A burst of 401s in the request logs is the signal; rotate nothing unless the token is believed leaked. |
| `config` | The token or the founder id is set but malformed (once per process; names only the variable) | Fix the value in Doppler (token: 48 to 256 characters of `A-Za-z0-9._~+/=-`; founder id: a uuid) and redeploy. |

After you have dealt with an event, resolve (never archive) its Sentry issue.

A flush that is slow or answers false is not a Sentry event: it writes one warning log line (`legal acceptance ack skipped:
flush not confirmed`), the row stays unacknowledged, and the next verify surfaces it.

## Before the `approval-queue` flag is on in prd

There is no backfill migration, so check once, in the production project, before the flag is on for anyone:

```sql
select count(*) from public.legal_acceptance;
```

It must be 0. If it is not, insert the acknowledgement rows for those rows first (the insert above, once per row, scoped by
founder id), or each of them raises a false `row_without_event` when verified.

When the secrets (`LEGAL_ACCEPTANCE_VERIFY_TOKEN`, `LEGAL_ACCEPTANCE_FOUNDER_ID`) are applied (#12196): the container receives them
through an env file that is frozen when the container is created, so a restart is not enough and a redeploy is needed. While the
endpoint is dark the probe expects the body `{"error":"Not available"}` with `cache-control: no-store`, not just a 503.

Order of the operator-owned steps (each depends on the one before): (1) enter `LEGAL_ACCEPTANCE_FOUNDER_ID` (the Supabase auth user uuid) in
Doppler `dev` and `prd`, then check, boolean-only, that the uuid exists in that project's `auth.users`; (2) redeploy the web app; (3) the
unauthenticated probe turns from 503 to 401; (4) an authenticated request with the Doppler token and no `hash` query answers 400, not 401,
which proves the container holds the current token; (5) the first real acceptance is verified through the gate; (6) only then is the
`approval-queue` flag turned on.

The session that performs the redeploy arms the pulls (they are not left to memory): at +1 hour and +24 hours after the redeploy, run

```bash
# slow or false flushes (no Sentry event; one warning log line each)
doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 24h --grep "flush not confirmed"
```

and a Sentry Discover query over the last 24 hours, `feature:legal-acceptance op:[record_invalid,store_failed,row_without_event]`
(read one issue with `scripts/sentry-issue.sh <issue id>`), and the unacknowledged-rows query above in the production SQL editor.
All three must be empty, or each hit must be explained.

## Rolling back migration 185

The down file refuses while any acknowledgement row exists, so a rollback never drops evidence silently. Apply it with
`psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f apps/web-platform/supabase/migrations/185_legal_acceptance_ack.down.sql` against the
production project (your own owner login). A refusal exits non-zero and changes nothing. Acknowledgement rows stay on a rollback.
