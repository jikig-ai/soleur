---
title: "An ON DELETE SET NULL FK into a WORM table fires the WORM gate on the cascade — and a `public.users`-scoped preflight cannot see `auth.users` references"
date: 2026-10-12
category: test-failures
module: apps/web-platform/supabase/migrations/{041,066,087,160}, scripts/preflight-worm-cascade-contradiction.sh
issues: [9994, 5372]
---

# The cascade is an UPDATE, so it raises like any other write

## Problem

`dsar_export_audit_pii.user_id` is `ON DELETE SET NULL` by design (mig 041 — the Art. 5(2) audit row
survives erasure anonymised). `auth.admin.deleteUser` therefore issues an internal
`UPDATE ONLY dsar_export_audit_pii SET user_id = NULL` on the cascade — which fires the table's
BEFORE UPDATE WORM trigger and raises P0001, surfacing as GoTrue's opaque `500 Database error
deleting user`. The SET NULL design and the append-only gate contradict each other at teardown time,
and the contradiction was latent on **prd** for any user with export history because the suites that
exercise it had been dormant.

The preflight gate (`preflight-worm-cascade-contradiction.sh`) that exists for exactly this defect
class could not see it: its catalog probe filters `con.confrelid = 'public.users'::regclass`, and
this FK references `auth.users`. Two independent misses shared one envelope — the drift lived inside
the blind spot for months.

## The fix shape that works (and the initiator check that makes it safe)

Mirror `audit_byok_use_no_mutate`'s founder_id gate (mig 066): inside the WORM trigger, allow exactly
`OLD.col IS NOT NULL AND NEW.col IS NULL AND (to_jsonb(NEW) - 'col') = (to_jsonb(OLD) - 'col')` —
the drift-proof row-hash compare that a future `ADD COLUMN` cannot silently widen. Then go one step
further than the precedent: `AND NOT EXISTS (SELECT 1 FROM auth.users WHERE id = OLD.col)`. The RI
action fires after the parent row is removed, so the cascade satisfies the check while a direct
`UPDATE ... SET col = NULL` from any privileged role (service_role bypasses the zero-policy RLS)
against a **live** user's row is rejected. Without the initiator check the carve-out widens the WORM
into a permanent Art. 5(2) de-attribution primitive — copying the precedent's shape without its
threat model propagates the hole, not the fix.

## Directional corollaries worth keeping

- **A Postgres FK census that counts only `confdeltype = 'r'` misses `NO ACTION` (`'a'`)**, which
  blocks a parent delete the same way and raised this exact failure first (`dsar_export_jobs.user_id`
  on dev was `a` + `NOT NULL` while main declared SET NULL + nullable — a second out-of-band dev
  drift, same class as #10095).
- **Dev can drift from main's migration state with zero ledger signal**: `041`'s `_schema_migrations`
  row has no `content_sha` (legacy), so the drift was invisible to every automated probe. The
  class-C targeted-SQL reconcile (mutex → backup → ALTER → verify `confdeltype='n'` → NOTIFY)
  realigned dev without touching prd.
- **The verify-file contract (`supabase/verify/NNN_*.sql` emitting `(check_name, bad)` rows) is the
  only permanent gate that a live `prosrc` matches the file's** — the `content_sha` ledger probe
  compares ledger-vs-git, never the applied body. `verify/160` now gates it.
- **A retained dead-code cleanup line was a live leak**: the suite's
  `dsar_export_jobs.delete().eq("id", jobId)` fired the sibling `job_id` SET NULL cascade into the
  same WORM gate and its `{error}` was unchecked — the job row silently survived `pending` where the
  dev worker could claim it. Production's shape (abort-status UPDATE, not DELETE) is the correct
  teardown idiom for lifecycle tables.

Gate extension (scanning `auth.users`-referencing WORM FKs) is a tracked follow-up — the
`confrelid='public.users'` filter is now documented in the gate's own header.
