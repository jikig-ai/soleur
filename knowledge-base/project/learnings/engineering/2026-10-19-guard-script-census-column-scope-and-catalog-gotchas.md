# Guard-script census queries: column-scoping, confdelsetcols, tgenabled, schema bounds

**Context.** Extending `preflight-worm-cascade-contradiction.sh` (#10379) to a
delete-cone census surfaced four catalog subtleties that a naive
`pg_trigger`/`pg_constraint` join gets wrong — each was caught either by a
live-dev census before merge (the `action_sends.message_id` false-positive)
or by the live-verified review seat.

1. **`BEFORE UPDATE OF <cols>` triggers only match an RI write when the
   column sets overlap.** `tgattr` (`int2vector`, space-separated `::text`)
   lists the trigger's columns; empty = unscoped. An RI SET NULL/SET DEFAULT
   write touches only the FK's write columns — match `con.conkey` ∩ `tgattr`,
   never just `(tgtype & 16) = 16`. A statement-level 11-column-scoped
   trigger false-flagged until scoping was added.
2. **PG15+ `ON DELETE SET NULL (col)` writes `confdelsetcols`, not all of
   `conkey`.** Always `unnest(COALESCE(con.confdelsetcols, con.conkey))` —
   `confdelsetcols` is NULL (not `{}`) when no subset is declared.
3. **`tg.tgenabled` filters dead triggers.** `'D'` (disabled) and `'R'`
   (replica-only) never fire in a normal session — exclude or a dormant
   raising trigger flags a live contradiction.
4. **Bound the census to `public`.** Unbounded child-class joins pull in
   third-party schemas (`storage.objects` via Supabase's own raise triggers)
   — they can't be remediated by repo migrations, and word-grep ownership
   checks (`\btable\b` across `migrations/*.sql`) false-own them (`objects`
   appears in `019_chat_attachments.sql` → cross-schema false-red).

Also: a `*)` catch-all in a case-dispatched disposition must fail LOUD
(emit an error), not `continue` — a 5th class added later would otherwise
vanish silently from a gate whose purpose is failing closed.

**Verified against live dev:** post-fix census = 0 blocking rows,
18 dormant, 4 cone-write-row residue — exactly the audited anchor set.
