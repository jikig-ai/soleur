# Legal acceptance: read a Request changes note

Pull-only (ADR-319, amendment 2026-11-05). The note lives only in `legal_acceptance.requested_edit`; nothing pushes it
anywhere (no email, issue or chat). The operator reads it personally, never an agent session: the verify endpoint returns
`status`, `text_hash`, `decided_at` and `row_ok` only.

## Read

Sign in to the Supabase dashboard with your own login and open the SQL editor of the project that holds the decision (no ssh,
no service key). List the rows (no note text), then read one by key and hash:

```sql
select key, version, text_hash, created_at from public.legal_acceptance
 where choice = 'request_changes' order by created_at desc;
select requested_edit from public.legal_acceptance
 where choice = 'request_changes' and key = '<key>' and text_hash = '<64 hex>';
```

Do not forward, quote or paste the note into a ticket, pull request, chat or agent session; describe any change in your own
words.

## Publish a revised text

A decision is final for its text hash. Edit `apps/web-platform/server/legal-acceptance/texts/<key>.md`: the new bytes give a
new `text_hash`, so the founder is asked again and a new row is written. A Decline needs the same. A hold that named the old
hash stays held until its gate names the new one.

## A row whose acknowledgement was lost

A Sentry event `op=row_without_event` means the web route recorded no acknowledgement for that row. Confirm with the founder
that the decision was theirs, then add it in the same SQL editor:

```sql
insert into public.legal_acceptance_ack (acceptance_id)
select id from public.legal_acceptance where key = '<key>' and text_hash = '<64 hex>'
on conflict do nothing;
```

If the founder does not recognise the decision, leave the row as it is and escalate; the record is evidence.
