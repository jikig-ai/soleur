# Decision challenges - feat-one-shot-10633-normalize-repo-url-sql-retrim

Plan: `knowledge-base/project/plans/2026-10-22-fix-normalize-repo-url-sql-retrim-backfill-plan.md`

## Decision Classes

| Item | Class | Ruling |
|---|---|---|
| R2: SQL canonical expression shape (one trailing regex alternation vs repeated three-step chain; whitespace class; host guard) | technical | Ruled by CTO agent, 2026-10-22: one `regexp_replace(<lower(scheme+host)\|\|path>, '(/\|\.git\|[ \t\n\r\f\v])+$', '', 'i')` after an explicit-ASCII-class trim; explicit class, not `[[:space:]]` (locale-dependent); skip rows whose result no longer matches `^[^/]*//[^/]+` - the tokens `/`, `.git`, one whitespace char decompose uniquely right to left, so the alternation is the exact fixpoint of the TS loop; repetition only approximates it with an arbitrary N. |
| R3: inline expression vs permanent `public.normalize_repo_url` function | technical | Ruled by CTO agent, 2026-10-22: inline via a derived table joined on `id`, no function - a function is PostgREST-exposed as an RPC (needs EXECUTE hygiene as in 128) and is a third copy of the canonicalization to keep in sync. |
| R4: unique-index collision handling on `conversations` | technical | Ruled by CTO agent, 2026-10-22: precondition `DO` block that raises with the colliding-group count before any write (covers new-vs-existing and new-vs-new); verify is strict with no excused residue - resolving a collision is a data decision no migration should make silently; prod has zero such rows. |
| R5: target tables and verify placement | technical | Ruled by CTO agent, 2026-10-22: `conversations` and `workspaces` only (`users.repo_url` dropped by 112), both rewritten in the same file per the 029 coupling invariant; new `verify/163_*.sql`, `verify/031` untouched. |
| Edit 031 in place vs new migration | taste | Not a fork, recorded for visibility: `lint-migration-immutability.sh` fails any PR that edits a merged migration; the corrected chain ships as 163. |
| Brand-survival threshold | taste | Planner default, 2026-10-22 (challengeable): `aggregate pattern` - a wrong expression would hit many rows (pattern), baseline is 0 rows of 193 on prd, no per-PR CPO sign-off required. |
| Test-stack sizing after the plan-review panel (drop census test, `*_ws_residue` probes, gated live block, generator widening; fold property tests into the existing parity file; keep a minimal expression-identity check and the Guard Contract tables the plan skill requires) | taste | Applied by planner, 2026-10-22, from the DHH, code-simplicity and CTO-devex findings; a smaller stack was preferred where a surviving assertion kills the same mutation. Challengeable at the PR. |
