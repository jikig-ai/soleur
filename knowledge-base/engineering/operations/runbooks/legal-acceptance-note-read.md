# Legal acceptance: read a Request changes note, reconcile a row, triage the signals

Pull-only (ADR-319, amendment 2026-11-05). The note lives only in `legal_acceptance.requested_edit`; nothing pushes it
anywhere (no email, issue or chat). The operator reads it personally, never an agent session: the verify endpoint returns
`status`, `text_hash`, `decided_at` and `row_ok` only. The note is not readable through the endpoint or through any
`service_role` path. This is a rule for you to follow, not a technical block: a database-owner credential could read it, and
you hold that credential, and so does the production migration pipeline (a CI secret that runs the migrate and verify steps); no agent session is meant to use either, which is a rule and not a control. Never paste the note into an agent session.

Every query below runs in the SQL editor of the **production Supabase project** (prd), signed in with your own login: no ssh,
no service key. Dev and prd are distinct projects; a row in dev is not a row in prd. Every query is scoped to the one founder id
the endpoint is configured with, `LEGAL_ACCEPTANCE_FOUNDER_ID`, because the endpoint and the screens answer for that one id and the key is
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
| `registry` | The legal text file could not be read, or is malformed (emitted by the verify route and by the counts route) | Read the error `code` on the event (`extra.code`). `read_failed`: the texts directory is missing or unreadable in the image; redeploy a build that contains `server/legal-acceptance/texts`. Any other code: the committed text file is malformed; edit the file. Nothing is wrong with the database either way. |
| `counts` | The aggregate read behind `scripts/legal-acceptance-counts.sh` (the `[key]/counts` route) failed, threw, or answered an undocumented shape | The helper exited non-zero with `counts: HTTP 503 store_failed` or `HTTP 502 bad_gateway`. Read `extra.code` (the SQLSTATE) and `extra.reason`; the full triage is in "The counts route answered 503" below. Recorded in Sentry, not paged. |
| 401 (no event) | A caller sent a wrong or missing token | Unthrottled by design and not an event; paging is #12195. A burst of 401s in the request logs is the signal; rotate nothing unless the token is believed leaked. |
| `config` | The token or the founder id is set but malformed (once per reading module per process: a token is reported by the verify and the counts route, a founder id by the verify route and the card surface; names only the variable) | Fix the value in Doppler (token: 48 to 256 characters of `A-Za-z0-9._~+/=-`; founder id: a uuid) and redeploy. |

Read with the `ack` row above: a flush that is slow or answers false is not a Sentry event. It writes one warning log line
(`legal acceptance ack skipped: flush not confirmed`), the row stays unacknowledged, and the next verify surfaces it.

### A Sentry event `op=page_read_failed` with `read=legal_acceptance_inbox` (the Inbox legal row)

The Inbox row fails closed: on any failure the loader returns no legal row, the other Inbox items still load, and the founder
sees neither a row nor a hint. This event is the only signal (recorded, not paged). Read `extra.step`
(`apps/web-platform/server/legal-acceptance/inbox-rows.ts`); the other `read` labels (`legal_text`, `legal_acceptance`,
`legal_acceptance_index`) come from the card pages and have no `step`.

| `extra.step` | What stopped | What to do |
|---|---|---|
| `gate` | The founder-surface gate threw. Since 2026-11-10 it reads only the `LEGAL_ACCEPTANCE_FOUNDER_ID` variable, so only an unexpected throw (a bug, for example a missing user id) produces this; a refusal is not an event | Read `extra.code` and `extra.errName`, then the stack trace; no configuration or database step fixes it. |
| `registry` | A declared legal text could not be read (the event carries `extra.key`), or the list of registry keys could not be read (no `extra.key`) | As the `registry` row of the `store_failed` table: the text file is missing, unreadable or malformed in the deployed image; read `extra.code`. Only that key's row is lost. |
| `read` | The user-session read of `legal_acceptance` (row-level security, columns `key, text_hash, choice`) returned an error | Supabase availability or a policy or grant drift on migration 184; read `extra.code` (the SQLSTATE) and check that Supabase is up. |
| `shape` | The read answered rows of an unrecognised shape | Treat as a bug or schema drift in migration 184; escalate, do not retry in a loop. |
| `state` | Deriving the card state threw | A bug in the loader; escalate with the event. |

`op=kind_undeclared` (warn, `tags.key`) is a related event: a registry text has no entry in `LEGAL_TEXT_KIND`, so no card and
no Inbox row exist for it. Declare its kind in the copy leaf. It repeats on every Inbox load and card render while it stands.

After you have dealt with an event, resolve (never archive) its Sentry issue.

### The counts route answered 503 (or the helper printed `counts: HTTP 503 store_failed`)

The counts route has four different causes for the same generic 503 body; tell them apart by the Sentry event, not by the body:

| Cause | The event | What to do |
|---|---|---|
| The token is unset (the dark state) | None at all: this is deliberately silent | Apply `LEGAL_ACCEPTANCE_VERIFY_TOKEN` in Doppler `prd` and redeploy (the container's env file is frozen at creation). |
| The token is set but malformed | `store_failed`, `stage=config`, once per route module | Fix the value in Doppler (48 to 256 characters of `A-Za-z0-9._~+/=-`) and redeploy. |
| The registry text could not be read | `store_failed`, `stage=registry`; read `extra.code` | As the `registry` row above (the key is the one asked about; the text file is in the deployed image). |
| The aggregate RPC failed | `store_failed`, `stage=counts`; read `extra.code` (the SQLSTATE) | `42883`: the function does not exist, so migration 186 is not applied in prd; apply it. `54000` with `extra.reason=too_many_hashes`: the key has more distinct text hashes than the cap (20), which is an operator condition, not a missing migration; inspect the rows in the production SQL editor (distinct `text_hash` values for that key) before anything else. Any other code: Supabase or the service key; check that Supabase is up. |

A 502 (`bad_gateway`) means the database answered something that is not the documented shape: treat it as a bug in 186 or in
the parser and escalate; do not retry in a loop.

### The helper printed HTTP 401 or HTTP 404

`counts: HTTP 401 unauthorized`: the bearer the helper read from Doppler `prd` is not the one the running container holds.
Either the token was rotated and the container was not redeployed yet (redeploy; the env file is frozen at container
creation), or the helper read a different Doppler config than the one the container was deployed from. Check the config is
`prd` and compare the deploy time with the last rotation. Rotate nothing unless the token is believed leaked.

`counts: HTTP 404 not_found`: the key is not in the registry (check the spelling against `server/legal-acceptance/texts/`), or
the text file for that key is not in the deployed image (the build predates the file; redeploy a build that contains it).

`counts: response is not the documented shape` on a 200: the helper refused the body (a field missing or of the wrong type, a hash
that is not 64 hex, counts that do not sum to `total`, or an `ok_to_flag` that disagrees with the one it recomputed). The route
answered 200, so it emitted nothing and there is no Sentry event to find; the refusal exists only in the helper's exit status. Treat it as the 502 case: the
body was altered on the way or the route and the helper have drifted; escalate and do not retry in a loop.

### Who may run the counts step

An agent session may run `scripts/legal-acceptance-counts.sh`, because it needs only the verify bearer from Doppler and no
database-owner credential. Reading a note (above) stays operator-only.

Residual, accepted: the helper reads `LEGAL_ACCEPTANCE_VERIFY_TOKEN` from Doppler `prd` itself, so an agent session that runs it
(or reads the same secret by the same Doppler path) can use the production verify bearer. That bearer reads the configured
founder's status (`accepted` or not, with the hash and time of the decision) and the per-hash counts of a key, never the note and never a
write, and the same secret is already readable from the `prd_terraform` Doppler config and the Terraform state by a Tier-A reader (ADR-319, Update
2026-11-07). The widening is accepted because the alternative was the database-owner credential, which is not accepted for any agent session.
It is a rule and not a control: nothing technical stops an agent session from reading the secret by another route.

## The decision-row count for a key (`legal-acceptance-counts.sh`)

A founder id is already configured in production (the card's only gate since 2026-11-10; the `approval-queue` flag no longer gates it). This count is therefore a report of the current state, not a go signal:
`ok_to_flag=true total=1` is the expected value (one recorded decision, under the registry hash); the first run records it, since the route had not run when this was written. Run it before publishing a text change
(a new text hash makes every earlier row stale) and whenever you need to know whether any row sits under another hash. The
check needs no database credential (#12429, ADR-319 amendment 2026-11-08): it asks the web app through the verify bearer.

```bash
scripts/legal-acceptance-counts.sh founder-acceptance-record
```

On success it prints exactly one line, `ok_to_flag=<true|false> total=<n> measured=production-table-only`, and nothing else.
`ok_to_flag=true` means every decision row for that key is under the registry hash (vacuously true at `total=0`);
`ok_to_flag=false` means a row exists under another hash, so bump the version first.
`total=0` after the published documents have gone out is a STOP: those documents say that a record exists, so a count of zero
means the published statement is untrue. Escalate to the CLO and treat it as a docs rollback decision before anything else;
`total` above 1, or `ok_to_flag=false`, also means investigate before anything else. The helper does not trust the route's
verdict: it recomputes `ok_to_flag` from the per-hash counts and refuses a body where the two disagree. Any failure (401,
404, 502, 503, an unreadable token, a body that is not the documented shape) exits non-zero and prints no `ok_to_flag=` line
and one status line such as `counts: HTTP 503 store_failed`; the triage for each is above. The
helper reads `LEGAL_ACCEPTANCE_VERIFY_TOKEN` from Doppler `prd` itself, hardcodes `https://app.soleur.ai`, and refuses to run
under `set -x`. Run it from a checkout of `main`; do not paste the token anywhere.

What the number is and is not: it counts only the production table for that key. It does not measure database backups, the
Sentry `accepted` count, or dev and preview. `ok_to_flag` is advisory and never authorizes a flag flip or any other
production write; those still need the operator's exact go.

The zero-rows precondition is separate from `ok_to_flag`, and `ok_to_flag=true` does not subsume it: any row that exists
(`total` above 0, even `total=1` under the registry hash) needs its own acknowledgement (the insert above, once per row, scoped by
founder id, run in the production SQL editor with your own login), or it raises a false `row_without_event` when verified.
The founder id is already configured in production, so this is not a step before enabling anything: to see whether an existing row has its
acknowledgement, run the "Rows with no acknowledgement" query above (the counts route cannot see acknowledgement state). Read
`total`, not only `ok_to_flag`.

The rollout order below is the original first-enable sequence; keep it for re-provisioning (a new environment or a rotated secret).

When the secrets (`LEGAL_ACCEPTANCE_VERIFY_TOKEN`, `LEGAL_ACCEPTANCE_FOUNDER_ID`) are applied (#12196): the container receives them
through an env file that is frozen when the container is created, so a restart is not enough and a redeploy is needed. While the
endpoint is dark the probe expects the body `{"error":"Not available"}` with `cache-control: no-store`, not just a 503.

Order of the operator-owned steps (each depends on the one before): (1) enter `LEGAL_ACCEPTANCE_FOUNDER_ID` (the Supabase auth user uuid) in
Doppler `dev` and `prd`, then check, boolean-only, that the uuid exists in that project's `auth.users`; (2) redeploy the web app; (3) the
unauthenticated probe turns from 503 to 401; (4) an authenticated request with the Doppler token and no `hash` query answers 400, not 401,
which proves the container holds the current token; (5) the first real acceptance is verified through the gate. The card opens for the
founder at step (2), so step (5) is done by the founder through the card, and the `approval-queue` flag is not a step.

The session that performs the redeploy arms the pulls (they are not left to memory): at +1 hour and +24 hours after the redeploy, run

```bash
# slow or false flushes (no Sentry event; one warning log line each)
doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 24h --grep "flush not confirmed"
```

and a Sentry Discover query over the last 24 hours, `feature:legal-acceptance op:[record_invalid,store_failed,row_without_event,page_read_failed,kind_undeclared]`
(read one issue with `scripts/sentry-issue.sh <issue id>`), and the unacknowledged-rows query above in the production SQL editor.
All three must be empty, or each hit must be explained.

## Rolling back migration 185

The down file refuses while any acknowledgement row exists, so a rollback never drops evidence silently. Apply it with
`psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f apps/web-platform/supabase/migrations/185_legal_acceptance_ack.down.sql` against the
production project (your own owner login). A refusal exits non-zero and changes nothing. Acknowledgement rows stay on a rollback.
