# Learning: on resume, prior-session artifacts from a contaminated tool layer are UNVERIFIED — re-derive from authoritative sources

category: integration-issues
module: apps/web-platform/supabase/migrations
issue: 4709
pr: 4711

## Problem

A `/soleur:work` run resumed a feature (#4709 template auto-revoke 42501 fix)
from a `session-state.md` that explicitly documented that the *originating*
session's tool layer had been intermittently contaminated (node-deprecation
warnings prepended to `Read` results, batched/delayed output). The prior session
had produced:

- A migration `089_template_auto_revoke_carveout.sql` + `.down.sql` **authored
  against a misread of the migration it was supposed to mirror (088)**.
- A `session-state.md` correctly flagging that two earlier conclusions
  ("089 applied to DEV / GREEN 20/20"; a destructive overwrite of the existing
  integration test) were FALSE and had been recovered.

The trap: the session-state correctly retracted the *status claims* (applied/
GREEN) but the *migration files themselves* — also a product of the contaminated
session — were left presented as trustworthy ("migration written, NOT applied").
They were not trustworthy. Reading the REAL migration 088 body revealed the
written 089 had:

- `RETURNS void` where 088 is `RETURNS integer` — **`CREATE OR REPLACE` cannot
  change a function's return type**, so the migration would have errored at apply
  with `cannot change return type of existing function` (HINT: use DROP FIRST).
  It could never have been "applied GREEN," confirming the retracted claim.
- Dropped the authenticated-session `auth.uid() IS NULL → 42501` guard.
- Dropped the 8-value `p_reason` enum gate (`22023`).
- Used `set_config('app.worm_bypass','on',true)` (twice) instead of 088's
  `SET LOCAL app.worm_bypass='on' ... 'off'` bracket.
- Used `COALESCE(revoked_at, now())` / `COALESCE(v_founder_id, founder_id)`
  instead of 088's plain `revoked_at = now()` / `founder_id = v_founder_id`
  (the COALESCE-to-self form is the exact cross-founder over-reach the plan's
  Approach-2 decision rejected).

## Solution

Treat EVERY artifact produced by a contaminated/degraded prior session as
unverified input, not as work-in-progress to extend:

1. Read the **authoritative source** the artifact claims to mirror (here: the
   real `088_worm_bypass_non_erasure_rpcs.sql` body, lines 108-182) directly,
   not the plan's or session-state's paraphrase of it.
2. Rewrite the artifact as a **verbatim delta** from that source — for 089,
   reproduce 088's body exactly and swap only the one founder-attribution gate
   block for the carve-out. Diff the down-migration against the source body to
   prove byte-identity (`diff <(sed -n '108,182p' 088.sql) <(...089.down...)`).
3. Re-establish status from scratch: apply to DEV yourself (here via node-pg
   over the session-mode pooler since `pg`/`psql` were absent — installed `pg`
   into `/tmp`, NOT the repo lockfile), then verify the live function body
   (`pg_get_functiondef`) shows the carve-out, RETURNS integer, search_path pin,
   etc. Re-run the RED→GREEN cycle (down to 088 → tests RED → up to 089 → GREEN)
   rather than trusting "GREEN 20/20."

## Key Insight

This generalizes the existing "plan-quoted numbers are preconditions to verify"
rule (`[[2026-05-10-handshake-schema-drift-and-stale-precondition-budgets]]`)
and the planning-subagent-fabrication learning
(`[[2026-05-29-planning-subagent-fabrication-and-output-corruption-false-untracked]]`)
to **resumed sessions**: when `session-state.md` documents prior tool-layer
contamination, the contamination taints not just the retracted *claims* but
every *file* the prior session wrote. A retraction of "I applied it" is not a
retraction of "the file I wrote is correct." For SQL specifically, a misread
`RETURNS` type is a free tripwire — a wrong return type makes `CREATE OR REPLACE`
fail at apply, so any "applied GREEN" claim against a return-type-changed body is
self-evidently false.

Corollary (review agents): a review agent's *prescribed* fix is itself a
precondition to verify. architecture-strategist prescribed adding
`AND revoked_at IS NULL` to the carve-out's re-derive SELECT; that would have
turned the idempotent second-fire (0-row no-op) into a `42501`, breaking the
idempotency test. The two concurring agents had recommended a clarifying comment
instead — which is what shipped. Verify before applying (per
`hr` "verify reviewer-prescribed CLI flags/fixes before applying").

## Session Errors

1. **[forwarded] Prior session's "089 applied to DEV / GREEN 20/20" was false.**
   `psql`/`pg` both absent; apply exited 127; the rewritten test failed to import
   `pg`. DEV was never modified. — Recovery: re-applied 089 to DEV myself via
   node-pg over the `:5432` session pooler and re-verified the live body. —
   **Prevention:** on resume, never trust a prior session's "applied"/"GREEN"
   status; re-apply + re-verify against the live DB.
2. **[forwarded] Prior session overwrote the existing integration test with a
   pg-based rewrite** (contaminated Read returned wrong content). Recovered from
   git HEAD. — **Prevention:** `hr-always-read-a-file-before-editing-it` +
   confirm `git diff HEAD <file>` is empty before extending a "recovered" file.
3. **Migration 089 + down were authored against a misread of 088** (RETURNS void
   vs integer; dropped NULL-auth + 22023 gates; set_config vs SET LOCAL; COALESCE
   forms). — Recovery: read real 088, rewrote both as verbatim delta; diffed down
   vs 088 (byte-identical). — **Prevention:** this learning; route a bullet to
   the work skill's resume handling.
4. **`pg`/`psql` absent locally.** — Recovery: `npm i pg` into `/tmp/pgapply`
   (NOT the repo, to avoid lockfile churn) + node-pg over the pooler with
   `:6543→:5432` rewrite for multi-statement DDL. — **Prevention:** documented
   fallback chain already exists in work/SKILL.md; the only addition is "install
   pg out-of-tree" so the integration-test lockfile stays clean.
5. **Review agent's prescribed fix would have broken idempotency.** — Recovery:
   verified the prescribed `AND revoked_at IS NULL` against the idempotency test
   mentally + via the existing GREEN run; applied a clarifying comment instead. —
   **Prevention:** treat agent-prescribed fixes as hypotheses; verify against the
   test matrix before applying (already an AGENTS sharp-edge).

## Tags
category: integration-issues
module: apps/web-platform/supabase/migrations
related: [[2026-05-10-handshake-schema-drift-and-stale-precondition-budgets]], [[2026-05-29-planning-subagent-fabrication-and-output-corruption-false-untracked]], [[2026-05-31-worm-bypass-fix-must-enumerate-all-mechanisms-not-just-the-reported-one]]
