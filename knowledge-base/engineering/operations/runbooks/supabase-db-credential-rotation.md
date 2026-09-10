---
title: Supabase Postgres credential rotation
category: runbook
tags: [security, credentials, supabase, doppler, rotation]
last_updated: 2026-09-10
---

# Supabase Postgres credential rotation

Rotates a Supabase project's Postgres password and updates every Doppler
connection string that embeds it.

## Run it

```bash
scripts/rotate-supabase-db-credential.sh --config dev
scripts/rotate-supabase-db-credential.sh --config prd --yes-rotate-prd
scripts/rotate-supabase-db-credential.sh --config dev --leaked   # + session sweep
```

That is the whole procedure. There is no dashboard step and no SSH. If you are
reading this expecting a checklist of things to click, the script is the
checklist — `hr-never-label-any-step-as-manual-without`.

**The production gate is decided on the derived project ref, not the config
name** (exit 3). The name is a label the caller chooses; the ref is what actually
gets rotated. A config named `dev_anything` whose pooler URL points at the prd
project still demands `--yes-rotate-prd`. An earlier version gated on
`$CONFIG == prd*` while deriving the target from the secret — those are two
different things, and the mismatch was a path to rotating production without an
ack.

## Rotation does NOT drop established sessions

A session already authenticated with the leaked password **survives the
rotation**. For leaked-credential response this is the step people miss.

`--leaked` sweeps them, scoped to the **rotated role**:

```sql
select pg_terminate_backend(pid) from pg_stat_activity
where usename = '<rotated role>' and pid <> pg_backend_pid();
```

Scoping matters. A blanket terminate also kills Supabase's own backends —
`authenticator` (PostgREST), `supabase_admin` (pg_cron, pg_net,
postgres_exporter), `pgbouncer` (Supavisor auth_query). On the 2026-09-10 dev
rotation all 18 live sessions were exactly those, and **none** ran as `postgres`,
the rotated role — so there was nothing to terminate and a blanket sweep would
have been pure self-inflicted disruption. Check before you sweep.

## What it does

1. Derives the project ref from `DATABASE_URL_POOLER`'s username (`postgres.<ref>`).
   Deliberately not from `NEXT_PUBLIC_SUPABASE_URL` — prd sits behind the custom
   domain `api.soleur.ai`, which reveals no ref.
2. Confirms the Management API token can see **that** project before changing
   anything.
3. `PATCH /v1/projects/{ref}/database/password` with a 48-char alphanumeric
   password. Alphanumeric because the value is embedded in a postgres URI and any
   reserved character would need percent-encoding a naive URL rebuild gets wrong.
4. Rewrites `DATABASE_URL` and `DATABASE_URL_POOLER` in that Doppler config —
   both embed the same password, so rotating one without the other half-breaks
   the environment.
5. Verifies by **hash**, never by printing the value, then proves the new
   credential authenticates via a throwaway `postgres:16-alpine` container.

## The one genuinely surprising thing

**The old password keeps working for ~60 seconds after the API returns 200.**

Supavisor (the pooler) caches auth. An immediate re-test of the leaked credential
will succeed, and that is *not* evidence the rotation failed. Postgres stores one
password per role, so the old value is invalid at the database the moment the
PATCH returns; only the pooler's cache is still honouring it.

Measured 2026-09-10 with a controlled second rotation (rotate again, keeping the
outgoing password, then poll it): the prior password was rejected at the first
check ~60 s later.

The practical rule: **verify after the cache expires, not immediately.** An
immediate check answers a different question than the one you are asking.

## Token

Uses `SUPABASE_ACCESS_TOKEN` from `soleur/prd_terraform`.

It deliberately does **not** use `SUPABASE_PAT`, which returns HTTP 401 in every
config that carries it — see #8028.

## Verifying without the old password

If you rotated and did not keep the outgoing value, you cannot re-test it. The
mechanism is still demonstrable without it: rotate once more, keep that
password, and confirm it stops authenticating after the cache window. That tests
the property ("a prior password stops working") using a credential you control,
which is what establishes the leaked one is dead too.
