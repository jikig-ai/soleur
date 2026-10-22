---
title: "fix: 031_normalize_repo_url.sql lacks the re-trim the TS twin gained - add re-trim + stored-row re-normalization backfill"
type: fix
date: 2026-10-22
slug: normalize-repo-url-sql-retrim-backfill
branch: feat-one-shot-10633-normalize-repo-url-sql-retrim
issue: 10633
closes: "#10633, #10732, #10713"
lane: cross-domain
brand_survival_threshold: aggregate pattern
---

# fix: SQL twin of `normalizeRepoUrl` - re-trim, stored-row re-normalization, parity gate

`lane:` defaulted to `cross-domain` (fail-closed): no `spec.md` exists for this branch.

## Enhancement Summary

**Deepened on:** 2026-10-22
**Sections enhanced:** Research Insights (flake audit, divergence inventory, backfill safety), Implementation Phases 1-4, Guard Contract, Observability, Encryption Posture, Acceptance Criteria
**Research and review agents used:** repo and institutional-learnings research, CTO (rulings R2-R5 plus eligibility), DHH-style, Kieran-style and code-simplicity plan reviewers, CTO devex lens, data-migration-expert, deployment-verification, test-design-reviewer, security-sentinel, GDPR gate; direct measurements on the dev and prd Postgres projects (read-only) and fast-check fuzz runs.

### Key improvements

1. **Eligibility guard (migration-expert finding 1).** The first design would have rewritten rows to a form that differs from `normalizeRepoUrl`, hiding conversations whose stored value is the TS form. The backfill now writes a row only when SQL provably equals TS; the safety property is part of the parity gate (600,000 adversarial runs, 0 violations; both guard clauses mutation-tested).
2. **Real-engine oracle.** The parity port is validated against a Postgres-generated golden table covering every fixture, including the old 031 chain, and a JS-vs-Postgres comparison on 398 adversarial inputs found 0 mismatches.
3. **Review-driven fixes.** Fixtures and generator restricted to parity-safe shapes (path-position spaces are `%20` in TS; numeric hosts are IPv4-canonicalized); the TS re-trim is redundant under the fixpoint loop, so the TS-side mutation row was replaced; `LOCK TABLE` closes the check-to-UPDATE race; the precondition error and the length insurance are count-only.
4. **Stack trimmed.** Helper module, separate property file, census test, residue probes and the gated live-DB block were cut; the shape test is explicitly a tripwire.

### New considerations discovered

- `verify/031`'s input-guarded probe would stay red for any row 163 skips but the old chain would rewrite; prd must show 0 such rows (baseline column `skipped_but_changed`).
- `verify/163` is deliberately strict and permanent: a future non-normalizing writer blocks deploys until fixed.
- Postgres regex cost is quadratic-leaning on pathological values (0.9 s at 400 KB); prod max length is 59.

## Overview

The TypeScript `normalizeRepoUrl` (`apps/web-platform/lib/repo-url.ts`) now runs a pass of
`trim -> URL-parse rebuild -> strip trailing "/" and ".git" (any interleaving) -> re-trim` to a fixpoint. Its
Postgres twin, migration `031_normalize_repo_url.sql`, still runs the pre-fix chain
(`trim -> strip "/+$" -> strip "(\.git)+$" -> strip "/+$"`): no re-trim, no interleaving-complete strip, and a
`trim()` that only removes U+0020. Three deliverables, plus a closing audit of two flaky-test issues:

1. **(a) Corrected SQL chain.** Because 031 is merged it is immutable (`lint-migration-immutability.sh`
   fails any PR that edits it), so the corrected chain ships as a NEW migration, `163_renormalize_repo_url.sql`.
2. **(b) Stored-row re-normalization** in that same migration (both live `repo_url` columns, same file, per the
   029 coupling invariant) plus a sibling `supabase/verify/163_renormalize_repo_url.sql` sentinel.
3. **(c) Parity-test additions** with shielded-whitespace fixtures, a real-Postgres golden table, and a property
   test of TS-vs-SQL parity over URL-clean inputs.
4. **Flake audit (#10732, #10713).** Both are resolved on `main` by the fixpoint loop (`c97a0be3b8`, #10695);
   evidence below. This PR pins their counterexamples as named regression fixtures, posts the evidence, and closes
   both via `Closes #` in the PR body.

## Research Insights

### Premise Validation (Phase 0.6)

- `#10633`, `#10732`, `#10713` all `OPEN`, none closed by a merged PR. PR `#10876` (this branch) and stale draft
  PR `#10692` are `OPEN` drafts; `#10692` is not touched (brief). `#10716` (the dot-segment counterexample) is
  `CLOSED` by `#10695`.
- `lib/repo-url.ts` on `main` has `normalizeRepoUrlOnce`, `stripTrailingSlashAndGit`, `MAX_EXTRA_PASSES = 32`. Confirmed.
- **Stale premise in the issue body.** #10633 says the TS normalizer yields the trimmed form for
  `"https://x/y .git"`. It does not: the URL parse percent-encodes the path space, so TS returns
  `"https://x/y%20"`. Path-internal whitespace is therefore NOT in the parity domain (SQL cannot mirror `%20`
  encoding). The re-trim matters only where whitespace sits in a segment the URL parser rejects but SQL's
  `[^/]+` host accepts (`"http://a.aa .git"`), or at the string tail after a strip. Fixtures are chosen
  accordingly (see Phase 1).
- **`users.repo_url` no longer exists** (dropped by migration 112, ADR-044 PR-2b). The live columns are
  `public.conversations.repo_url` (029) and `public.workspaces.repo_url` (079). `verify/031` already carries
  named-0 stubs for `users_*`. The backfill targets these two tables only.
- ADR corpus grep (`SQL`, `twin`, `031`): ADR-293 §First yield records the SQL twin as "tracked as a follow-up";
  ADR-044 owns the workspace-keyed repo contract. No ADR rejects a corrective backfill migration. No new
  architectural decision is made (see Phase 2.10 note below).
- **Prod read-only baseline (counts only, 2026-10-22):** `workspaces` 6 rows with a repo_url, `conversations`
  187; rows carrying any whitespace, trailing `/` or `.git`, or an uppercase scheme/host: **0 and 0**. The backfill is
  expected to be a no-op on prod; its value is the idempotence/contract fix, fresh and dev environments, and the
  verify sentinel that keeps the contract enforced.

### Property List (Phase 0.6b)

1. After the deploy, no ELIGIBLE stored `conversations.repo_url` / `workspaces.repo_url` differs from the canonical
   form of itself (trim, lowercase scheme+host, no trailing `/`, `.git`, or whitespace). Eligible = a clean http(s) URL
   shape whose canonical form provably equals what `normalizeRepoUrl` returns (see "Backfill safety" below); every other
   row is left untouched, exactly as 031 left non-URL rows.
2. The canonical SQL form equals `normalizeRepoUrl(x)` for every URL-clean input (parity domain).
3. Re-running the migration is `UPDATE 0` (idempotent), and a collision on the `conversations` unique index is
   detected up front with a clear count-only error instead of a mid-UPDATE `23505` (the abort is deliberate and loud).
4. The backfill only writes a value that equals `normalizeRepoUrl(<old value>)`. Readers compare a conversation's stored
   value to `normalizeRepoUrl(workspaces.repo_url)` and `ws-handler` stamps new conversations with the TS output, so a
   rewrite that differs from the TS result would hide a user's conversations.
5. `normalizeRepoUrl` is a fixpoint on the two flake counterexample classes, and the pins make that permanent.

### Cut List (Phase 0.6b)

| Proposed / tempting mechanism | Property it would buy | Verdict |
|---|---|---|
| Edit 031 in place (issue wording "(a) the SQL re-trim") | 1, 3 | **Cut**: 031 is merged and the immutability lint fails the PR; the corrected chain lives in 163. |
| Permanent `public.normalize_repo_url(text)` SQL function | 2 | **Cut** (CTO ruling R3): PostgREST exposes it as an RPC (needs EXECUTE hygiene as in 128) and it is a third copy of the contract. |
| Mirror the URL parse / dot-segments / `%20` in SQL | 2 for non-clean inputs | **Cut**: not expressible; documented out-of-domain and pinned by an OUT_OF_PARITY test. |
| `.git`/`/` strip loop in a PL/pgSQL DO block | 1 | **Cut**: one regex alternation is the exact fixpoint (unique right-to-left token decomposition). |
| Collision-skipping UPDATE guard | 3 | **Cut** (CTO ruling R4): leaves permanent residue; a precondition `DO` block that raises is chosen instead. |
| Edit `verify/031` | 1 | **Cut**: it keeps passing (its old expression is the identity on canonical rows); a new verify file owns 163's checks. |
| New helper module, separate property file, census test, `*_ws_residue` probes, gated live-DB block, generator widening | 2, 3 | **Cut** (plan-review consolidation): each is killed by a surviving assertion (golden table, selftest, dev rehearsal, the existing pins). |
| Rewriting out-of-parity rows (path whitespace, userinfo, port, `%`, dot-segments, non-http schemes) | 1 | **Cut** (migration-expert finding 1): SQL cannot reproduce the TS result, and a SQL-only rewrite breaks the conversation-to-workspace match; those rows are left untouched by an eligibility guard. |
| A pre-image snapshot table | rollback | **Cut** (deployment-verification): it would add an account-linked data store to protect zero rows; take a Supabase backup first only if the pre-merge baseline shows rows to rewrite. |
| New TS changes | 5 | **Cut**: TS already correct (700,000 fuzz runs, zero failures); only a docstring pointer changes. |

### Flake audit evidence for #10732 and #10713 (Phase 0 deliverable)

Run against the worktree (`main` + docs), Node 26.12, `fast-check` via the repo's `node_modules`:

| Input | pre-fixpoint code (`91594324ef`, PBT adoption) | current `main` |
|---|---|---|
| `" http://a.aa/..git.git/"` (#10716 class, named in brief) | `"http://a.aa/."` NOT a fixpoint (next call returns `"http://a.aa"`) | `"http://a.aa"`, fixpoint |
| `"http://a.aa/."` (#10732, named in brief) | `"http://a.aa"`, fixpoint when run alone | `"http://a.aa"`, fixpoint |
| `"http://a.aa/..git"` (#10732's literal failure message: first pass returns `"http://a.aa/."`) | `"http://a.aa/."` NOT a fixpoint | `"http://a.aa"`, fixpoint |
| `"a://A"` (#10713) | `"a://a"`, fixpoint when run alone | `"a://a"`, fixpoint |
| `" a://A .git"` (#10713 mechanism: unparseable first pass keeps host case, strip leaves a parseable value) | `"a://A"` NOT a fixpoint (next call returns `"a://a"`) | `"a://a"`, fixpoint |
| `"a://A /"` | `"a://A"` NOT a fixpoint | `"a://a"`, fixpoint |
| `" a://A/..git"` | `"a://a/."` NOT a fixpoint | `"a://a"`, fixpoint |

Fuzz on current `main`: 7 seeds x 100,000 runs (includes the three historical seeds -590792931, -1488952269,
1186074284) over a widened generator (`fc.string()`, URL-ish x suffix classes incl. `" .git"`, `"/."`, `"\t.git"`,
padded variants, uppercase-host non-URL class, `a://A`-shaped regex strings): **0 failures**, asserting
`f(f(x)) === f(x)` and `f(x) === f(x).trim()`. #10732's and #10713's shrunk values are exactly the classes the
fixpoint loop closes (a strip exposes a dot-segment; an unparseable first pass keeps case that the next pass's
parse lowers). `lib/repo-url.ts` needs no change. The pins in Phase 4 make the closure permanent; the new pins are verified once against the pre-fixpoint code (acceptance criterion).

### Divergences between 031 and the TS chain (full inventory)

| # | Divergence | In backfill scope? |
|---|---|---|
| D1 | No re-trim after the strips (`"http://a.aa .git"` -> SQL `"http://a.aa "`, TS `"http://a.aa"`) | Yes: the issue |
| D2 | Strip is not interleaving-complete (`".../r/.git/.git"` leaves `/.git` in 031, TS strips all) | Yes: same "re-strip" class; fixed by the same single alternation |
| D3 | `trim()` removes only U+0020; JS `trim()` also removes tab/newline/etc. | Yes (ASCII class only): `"\thttps://h/o/r"` is untouched by 031 |
| D4 | TS URL parse: `%20` path encoding, dot-segments, `%2e`, userinfo/port, default-port drop, numeric-host IPv4 canonicalization (`https://0` -> `https://0.0.0.0`) | **No**: not expressible in SQL; out-of-domain, pinned; rows with these shapes are INELIGIBLE and left untouched |
| D5 | Exotic Unicode whitespace (NBSP, U+2028, BOM...) in JS `trim()` | **No**: locale-dependent in PG; the setup route regex rejects it at the write boundary |
| D6 | Non-URL rows skipped by 031's host guard | Unchanged: 163 keeps the same hands-off stance |

D2 and D3 are "more than the issue named"; the brief allows them because the single regex that fixes D1 fixes
D2/D3 with no extra mechanism, and each is a trailing/leading whitespace-or-suffix re-strip divergence.

### Backfill safety: only write what the TS normalizer agrees with (deepen-plan finding)

Migration-expert finding 1 (verified against `server/current-repo-url.ts:86`, `ws-handler.ts:1012-1051`): readers compare a
conversation's stored value to `normalizeRepoUrl(workspaces.repo_url)`, and new conversations are stamped with the TS
output. Applying the same SQL chain to both tables preserves raw equality only; for a workspace stored as
`https://github.com/o .git` TS yields `https://github.com/o%20` (conversations carry that form) while SQL yields
`https://github.com/o`, so the rewrite would hide those conversations. The fix is an ELIGIBILITY guard in the
`canon-expr` block, so a row is rewritten only when SQL provably equals TS:

- the trimmed input has no internal ASCII whitespace (031's output keeps whitespace only at the tail, which is exactly the
  stored shape this migration repairs; a raw `x y .git` is never what 031 left behind), and
- the trimmed input is at most 2048 characters (CTO L2: over-length rows are skipped, not raised on, which also bounds the
  quadratic-leaning regex; prod max is 59), and
- the canonical result matches a clean shape:
  `^https?://([a-z0-9-]+[.])*[a-z][a-z0-9-]*(/[A-Za-z0-9_~-][A-Za-z0-9._~-]*)*$` (http/https, letter-bearing final host
  label so no IPv4 canonicalization, no userinfo, port, `%`, `?`, `#`, dot-segment or empty segment).

Evidence (scratch, not committed): safety property `backfill(x) !== x implies backfill(x) === normalizeRepoUrl(x)` held on
3 seeds x 200,000 adversarial inputs (600,000 runs, 5,199 rewrites, 0 violations); removing either guard clause turns it
red (counterexamples `https://github.com//../o\n` and `https://github.com/o .git`); the JS port and Postgres agreed on
398 adversarial inputs (29 rewrites, 0 mismatches). Consequence for the baseline: a row the OLD 031 chain would still
rewrite but 163 skips (`skipped_but_changed`) would keep `verify/031`'s input-guarded probe red; prd must show 0.

### Institutional learnings applied

- `2026-10-20-repo-url-retrim-shielded-whitespace-sql-twin.md`: the follow-up needs BOTH the chain patch and
  stored-row re-normalization; "already covered by the parity gate" is a claim about the gate's fixture set.
- `best-practices/2026-04-22-ts-sql-normalizer-parity-when-shipping-backfill-migration.md`: verify the SQL chain
  with a `WITH fixtures AS (VALUES ...)` query against a real database before commit (done at plan time on dev,
  SELECT only; repeated in Phase 2).
- `test-failures/2026-07-11-verify-sentinel-content-test-must-pin-case-polarity.md`: the verify content test binds
  check names, probes, and `CASE` polarity, not mere probe presence.
- `build-errors/2026-05-25-migration-body-no-top-level-begin-commit.md`: no `BEGIN;`/`COMMIT;` in the body.
- `2026-07-18-rls-initplan-wrap-breaks-verify-sentinels-...md` and the mig-112 post-mortem: verify files run on
  EVERY deploy, so `verify/163` must reference only columns that exist on `main`, and must not source names from prod.
- `best-practices/2026-10-20-fastcheck-v4-substitutions-and-json-canonical-oracle.md`: fast-check 4.x API
  (`fc.stringMatching`, no `stringOf`); every property file keeps a negative control.
- Runbook `supabase-migrations.md`: ordinal check, dev-first rehearsal, immutability after apply, verify contract.

### Technical rulings (full rows in `decision-challenges.md`)

- Ruled by CTO agent, 2026-10-22: **R2** one trailing `regexp_replace(..., '(/|\.git|[ \t\n\r\f\v])+$', '', 'i')`
  after an explicit-ASCII-class trim; explicit class, not `[[:space:]]` (locale-dependent); guard that the result
  still matches `^[^/]*//[^/]+`.
- Ruled by CTO agent, 2026-10-22: **R3** inline expression via a derived table joined on `id`; no function.
- Ruled by CTO agent, 2026-10-22: **R4** precondition `DO` block raising on any (user_id, canonical, context_path)
  collision over the unique index's coverage; strict verify, no excused residue.
- Ruled by CTO agent, 2026-10-22: **R5** targets are `conversations` + `workspaces`; new `verify/163`; `verify/031` untouched.
- Ruled by CTO agent, 2026-10-22: **E1** eligibility skip-guard (rewrite only rows where SQL provably equals the TS normalizer;
  flips to a loud raise only if the pre-merge prd re-run shows `skipped_but_changed` above 0). **L1** `SET LOCAL lock_timeout = '5s'`
  plus `LOCK TABLE public.conversations IN SHARE ROW EXCLUSIVE MODE` before the precondition. **L2** a 2048-character eligibility
  clause instead of a raise.
- CTO-flagged additional risks adopted: no-op `.down.sql`; pinned OUT_OF_PARITY corpus; run the migration on dev
  first (collision rows could exist there); re-check ordinal 163 immediately before merge.

## Research Reconciliation - Spec vs. Codebase

| Claim (issue / brief) | Reality | Plan response |
|---|---|---|
| "(a) the SQL re-trim ... in 031" | 031 is merged; immutability lint fails any edit | Corrected chain ships in new migration 163; 031's header claim stays frozen and is superseded by 163's header |
| "stored `repo_url` rows (users and conversations)" | `users.repo_url` dropped by 112 | Backfill covers `conversations` + `workspaces`; 080 copied users->workspaces without re-normalizing, so workspaces is in scope |
| "`https://x/y .git` -> TS trimmed form" | TS gives `https://x/y%20` | Not a parity fixture; pinned as OUT_OF_PARITY. Parity fixtures use host-space and tail-whitespace shapes |
| "corrected `sqlNormalize031`" (parity port) | `sqlNormalize031` mirrors 031 and uses JS `trim()` (PG `trim()` is space-only) | Keep 031's port as the historical oracle (fix its trim to space-only to be faithful) and add `sqlNormalize163` for the new chain |
| "~200 lines / 4 files" | Real set is ~12 files incl. shape test, golden SQL fixture, docs pointers | See Files to Create/Edit; split assessment: single PR |
| "#10732 / #10713 intermittent flakes" | Not reproducible on `main`; reproducible on pre-fixpoint code | Pin, post evidence, close via PR body |

## Open Code-Review Overlap

None. (`gh issue list --label code-review --state open` bodies searched for every file path in Files to Edit/Create: zero matches.)

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "(a) the SQL re-trim mirroring the TS chain" [brief] | Phase 2: `163_renormalize_repo_url.sql` canonical expression | mapped |
| 2 | "(b) a stored-row re-normalization backfill migration with a sibling supabase/verify sentinel per the data-backfill runbook" [brief] | Phase 2 (UPDATEs + precondition) + Phase 3 (`verify/163_renormalize_repo_url.sql`) | mapped |
| 3 | "(c) parity-test additions with shielded-whitespace fixtures" [brief] | Phase 1: `repo-url-sql-parity.test.ts` (ports, golden table, fixtures, property tests) | mapped |
| 4 | "verify whether the intermittent property-test flakes #10732 and #10713 are already resolved by the TS fixpoint loop on main" [brief] | Research Insights flake audit + Phase 4 evidence comments | mapped |
| 5 | "pin their counterexamples `' http://a.aa/..git.git/', 'http://a.aa/.', 'a://A'` as regression cases if not already pinned" [brief] | Phase 4: `repo-url.property.test.ts` regression block | mapped |
| 6 | "close them with evidence if so" [brief] | Phase 4: `gh issue comment` + `Closes #10732`, `Closes #10713` in PR body | mapped |
| 7 | "the backfill must only fix the trailing-whitespace / re-strip divergence unless the plan finds more" [brief] | Divergence inventory D1-D6; only D1-D3 fixed, D4-D6 explicitly out | mapped |
| 8 | "Stale draft PR #10692 ... exists; do not touch it" [brief] | Non-goal; PR #10692 never edited or closed | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|---|---|---|
| `supabase/migrations/163_renormalize_repo_url.sql` | "a stored-row re-normalization backfill migration" | asked |
| `supabase/migrations/163_renormalize_repo_url.down.sql` (no-op) | - | inferred - justification: dev-ledger-reconcile pairs an unmerged migration with its `.down.sql`; absence makes a rolled-back dev run unrecoverable by the standard workflow |
| `supabase/verify/163_renormalize_repo_url.sql` | "a sibling supabase/verify sentinel" | asked |
| `test/supabase-migrations/163-renormalize-repo-url.test.ts` | "a sibling supabase/verify sentinel" | inferred - justification: the verify file runs only post-merge in CI; a shape test is the only pre-merge defence (learning 2026-07-11, `verify-sql-string-literals` precedent) |
| `test/repo-url-sql-parity.test.ts` (edit) | "parity-test additions with shielded-whitespace fixtures" | asked |
| `test/fixtures/sql/normalize-repo-url-163-golden.sql` (new) | "parity-test additions" | inferred - justification: the golden table must be regenerated from Postgres, not hand-edited, or the oracle becomes self-referential (CTO devex finding) |
| Eligibility guard inside the `canon-expr` block | - | inferred - justification: without it the backfill rewrites rows to a form that differs from `normalizeRepoUrl`, hiding conversations stored in the TS form (migration-expert finding 1); it narrows the backfill to the divergence the brief names |
| `LOCK TABLE` with a 5 s `lock_timeout`, and the 2048-character eligibility clause | - | inferred - justification: close the check-to-UPDATE race that would print row data in a `23505` detail, and bound the quadratic-leaning regex (security findings B and C; CTO L1 and L2) |
| `test/lib/repo-url.property.test.ts` (edit) | "pin their counterexamples" | asked |
| `lib/repo-url.ts` (docstring pointer only) | - | inferred - justification: the coupling note names 031 only; leaving it makes the next editor miss 163 |
| ADR-293 / learning follow-up lines | - | inferred - justification: both say the SQL twin is "tracked as a follow-up"; leaving them stale misleads the next reader |

### Split Assessment

- Subsystems touched: 2 - `apps/web-platform`, `knowledge-base`
- Planned files: 12 | Estimated changed lines: ~520
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## User-Brand Impact

- **If this lands broken, the user experiences:** a connected workspace whose Command Center conversations disappear
  (readers scope by `(user_id, repo_url)`; a mis-rewritten `conversations.repo_url` that no longer equals the
  workspace's `repo_url` hides history), or a webhook push that reconciles zero workspaces; or a failed deploy if the
  migration aborts. On current prod data (0 non-canonical rows of 193) the migration wrote nothing when observed on 2026-10-22 (an observation, not a guarantee).
- **If this leaks, the user's data is exposed via:** no new exposure vector. The change rewrites an existing text
  column in place; it adds no read path, grant, function, or table, and never touches `github_installation_id`. `repo_url` is account-linked repository metadata.
- **Brand-survival threshold:** `aggregate pattern`
- **Threshold decision (challengeable):** one wrong expression would affect many rows at once (a pattern), not one
  user, and the baseline shows zero rows to rewrite, so `single-user incident` (CPO sign-off) is not warranted.

## GDPR / Compliance Gate (Phase 2.7)

The plan adds a `supabase/migrations/*.sql` file, which matches the `hr-gdpr-gate-on-regulated-data-surfaces` regex.
Ran `soleur:gdpr-gate` on this plan: all six v1 checks clean (no new column, table, FK, vendor, or Art. 9 data;
`repo_url` is repository metadata). Disposition: no new processing activity, no new column or data category, no
new recipient, no retention change; no `compliance-posture.md` row. One Suggestion adopted (`GDPR-Suggestion-1`):
the precondition `RAISE EXCEPTION` text names the collision-group COUNT only - never `user_id`, `repo_url` or
`context_path` - and the shape test asserts the message carries no placeholder other than that count.

## Implementation Phases

TDD order per `cq-write-failing-tests-before`: tests first (RED), then the migration, then the verify file.
Sizing note (plan-review consolidation, see `decision-challenges.md`): the test stack was reduced where a surviving
assertion kills the same mutation.

### Phase 1 - Parity oracle and tests (deliverable c)

Everything lives in the existing `apps/web-platform/test/repo-url-sql-parity.test.ts` (ports stay local, as
`sqlNormalize031` is today; no new helper module, no new property file). RED/GREEN honesty: the ports live in the test file,
so the fixture and property tests are green on their own; only the golden-table and shape tests are RED until the Phase 2
migration exists.

1. **Ports.**
   - `sqlNormalize031(raw)`: kept, made faithful: PG `trim()` removes only U+0020, so use `raw.replace(/^ +| +$/g, "")`
     instead of JS `trim()`. The `rest` pattern becomes `/^[^/]*\/\/[^/]+(\/[\s\S]*)$/` (PG `.` matches newline by default;
     JS `.` does not).
   - `sqlChain163(raw)`: the canonicalization chain only (ASCII-class trim `/^[ \t\n\r\f\v]+|[ \t\n\r\f\v]+$/g`;
     `schemeHost`; `lower(schemeHost) + rest`; tail strip `/(\/|\.git|[ \t\n\r\f\v])+$/i`; returns `null` when there is no
     scheme+host or the result no longer has one). This is the part that mirrors TS (deliverable a).
   - `sqlBackfill163(raw)`: `sqlChain163` plus the eligibility guard (no internal whitespace in the trimmed input AND it is at most
     2048 characters AND the canonical result matches the clean-shape regex); returns `raw` unchanged when ineligible (the UPDATE skips the row).
   - Header comment = the **sync-sites registry**: a future edit of `normalizeRepoUrl` must touch `lib/repo-url.ts`, the ports,
     the golden SQL fixture, and a NEW migration plus verify file (163 is frozen once applied). Parity domain = URL-clean
     ASCII; D4-D6 listed.
2. **Golden table** `PG_GOLDEN_163`: `[raw, pg031Chain, pg163Chain, pg163Backfill]` for EVERY raw string used by
   `SHIELDED_WS_FIXTURES`, `OUT_OF_PARITY` and `BACKFILL_FIXTURES` (about 25 rows), produced by Postgres running the committed
   expressions. The generator is committed as `apps/web-platform/test/fixtures/sql/normalize-repo-url-163-golden.sql` (a
   `SELECT ... FROM (VALUES ...) AS x(repo_url)` script, SELECT only; the 031 chain and the `canon-expr` block as comment-marked
   copies) with its runner in the test header (`doppler run -p soleur -c dev -- sh -c 'psql "$DATABASE_URL_POOLER" --no-psqlrc
   -tA -F"|" -f <script>'`, with `sh -c` so the variable expands inside Doppler's environment; control characters built with
   `chr()`). Assertions: both ports equal their golden columns for every row (so the old-chain defect claims and the
   out-of-parity SQL values come from a real engine, not from the port); every fixture raw appears in the table; and
   `PG_GOLDEN_163.length` equals the script's VALUES row count, so the table cannot drift from the script.
3. **`SHIELDED_WS_FIXTURES`** (chain parity, synthesized per `cq-test-fixtures-synthesized-only`), parity-safe by construction
   (a space after a path segment becomes `%20` in TS, so a space shield is admitted only in HOST position):
   `"http://a.aa .git"`, `"http://a.aa /"`, `"a://A .git"`, `"http://a.aa\t.git"`, `"http://a.aa/\n.git/"`,
   `"https://github.com/foo/bar/.git/.git"`, `"https://github.com/foo/bar.GIT\t/"`, and the must-PASS padding row
   `"\thttps://github.com/foo/bar\n"`. For each: `TS === sqlChain163 === expected`. The URL parser strips tab and newline
   itself, so only the host-space rows exercise the re-trim path; the tab and newline rows exercise the SQL chain's ASCII class.
   A sub-list asserts the `sqlNormalize031` port differs from expected for the documented 031 defects (D1 `"http://a.aa .git"`,
   D2 `".../bar/.git/.git"`, D3 the tab-padded row).
4. **`BACKFILL_FIXTURES`** (what the migration actually does to stored rows): 031-shaped stored forms are rewritten:
   `"http://a.aa "` -> `http://a.aa`, `"https://github.com/Foo/Bar/ "` -> `https://github.com/Foo/Bar`,
   `"HTTPS://GitHub.com/foo/bar.git/"` -> `https://github.com/foo/bar`; ineligible rows are left untouched:
   `"https://github.com/o .git"` (internal whitespace; TS gives `.../o%20`), `"http://a.aa .git"`, `"https://u:p@Host/x"`,
   `"http://a.aa:80/x"`, `"http://a.aa/./x"`, `"https://0/x"`, `"http://.git"`, `"a://A"`.
5. **`OUT_OF_PARITY`** table pinning BOTH sides' exact values from the golden table: `"https://x/y .git"` (TS `https://x/y%20`),
   `"http://a.aa/ \n.git/ "` (TS `http://a.aa/%20`), `"http://a.aa/./x"`, `"http://a.aa:80/x"`, `"http://.git"` (TS `http:`).
6. **Property tests** (fast-check 4.x, same file, own `describe`, negative-control `it` per README):
   - `urlCleanArb` = scheme in `{https, http, HTTPS}` x host (labels `[A-Za-z][A-Za-z0-9]{0,5}`, 1-3 labels, letter-initial because an
     all-numeric label is IPv4-canonicalized by the URL parser, D4) x 0-3 path segments `[A-Za-z0-9_-]{1,6}` x suffix from
     `{"", "/", ".git", ".GIT", ".git.git/", "/.git/.git", "\t.git", "\n/"}` plus, ONLY with zero path segments, the host-position
     shields `{" .git", " /", " .git/ "}` x padding from `{"", " ", "\t", "\n"}`. P1: `TS(x) === sqlChain163(x)`.
   - P2 (backfill safety, the migration's key property): over a wide adversarial generator (specials such as `%20`, `/./`,
     `/..`, `:80`, `@`, `?q=A`, `#F`, `//`, `.git`, spaces, newlines, non-http schemes, numeric hosts, over-length values around the 2048 boundary, plus `fc.string()`):
     `sqlBackfill163(x) !== x` implies `sqlBackfill163(x) === normalizeRepoUrl(x)`; and `sqlBackfill163` is idempotent.
   - No `fc.sample` floors; the fixture lists carry `length >= 8` floors.

### Phase 2 - Migration 163 (deliverable a + b)

New `apps/web-platform/supabase/migrations/163_renormalize_repo_url.sql`. Ordinal: re-check against `origin/main` immediately
before commit and before merge (two PRs already collided on 162; this is a pre-commit/pre-merge step, not a checked AC).
No `BEGIN`/`COMMIT`, no `CONCURRENTLY`. Header documents: the 031 defects D1-D3 fixed; D4-D6 out of scope; the 2026-10-22
prod observation (0 non-canonical rows of 193, an observation not a guarantee); immutability of 031 and why this is a new
file; the 029 coupling invariant (both tables, same file); ASCII-whitespace parity domain; idempotence (`UPDATE 0` on re-run); that `verify/163` is deliberately strict and permanent (a
future writer that bypasses `normalizeRepoUrl` will block deploys until the row is fixed); that the migration only rewrites
values in place and adds no grant, function or table; and the forward-fix rule (a defect in 163 ships as 164, never an edit).

**Ordering constraint.** Capture the dev and prd baseline counts (read-only, counts only) BEFORE the first push containing
the file: `tenant-integration` applies the migration to dev on push, which also freezes the file's bytes (comments included)
for the PR's life, so finalize the SQL text first. Rehearse the full migration body on dev inside `BEGIN; ... ROLLBACK;`
(same mechanism as the precondition proof), not via `run-migrations.sh`, so the CI push is the first real apply.

Canonical expression. The `canon-expr` marker block is the table-independent LATERAL chain reading `x.repo_url` (every copy aliases
its source row as `x` with column `repo_url`; the golden and selftest scripts use `FROM (VALUES ...) AS x(repo_url)`), so one
set-size comparison can cover all copies:

```sql
-- canon-expr begin
CROSS JOIN LATERAL (SELECT regexp_replace(x.repo_url, '^[ \t\n\r\f\v]+|[ \t\n\r\f\v]+$', '', 'g') AS t) a
CROSS JOIN LATERAL (SELECT regexp_replace(
        lower(substring(a.t FROM '^([^/]*//[^/]+)')) || COALESCE(substring(a.t FROM '^[^/]*//[^/]+(/.*)$'), ''),
        '(/|\.git|[ \t\n\r\f\v])+$', '', 'i') AS canon) b
CROSS JOIN LATERAL (SELECT CASE
        WHEN a.t !~ '[ \t\n\r\f\v]'
         AND char_length(a.t) <= 2048
         AND b.canon ~ '^https?://([a-z0-9-]+[.])*[a-z][a-z0-9-]*(/[A-Za-z0-9_~-][A-Za-z0-9._~-]*)*$'
        THEN b.canon END AS canon_ok) c
-- canon-expr end
```

Each statement then reads `FROM public.<table> x <canon-expr block> WHERE x.repo_url IS NOT NULL` and uses `c.canon_ok` (NULL means
"ineligible, leave the row alone", which also subsumes the host guard).

Validated at plan time against Postgres on the dev project (third-party-behaviour measurement): SELECT-over-`VALUES` for the
expression (including this 3-LATERAL form); a rolled-back prototype of the DO block, the UPDATE shape, a second run and a seeded
collision over a TEMP copy of the table (`UPDATE 2` then `UPDATE 0`, then `163 precondition failed: 1 collision group(s)`); and a
398-input adversarial comparison of the JS `sqlBackfill163` port against Postgres (0 mismatches).

Statements, in order:

0. `SET LOCAL lock_timeout = '5s';` then `LOCK TABLE public.conversations IN SHARE ROW EXCLUSIVE MODE;` before the precondition (CTO L1: the
   timeout makes a lock queued behind a long transaction fail loudly instead of stalling every `ws-handler` insert), so a concurrent insert cannot
   create a collision between the check and the UPDATE (a mid-UPDATE `23505` would print `DETAIL: Key (user_id, repo_url,
   context_path)=(...)` into the CI log and defeat the count-only rule). The tables hold about 200 rows, so the lock is
   held for milliseconds. (Security finding B.)
1. **Precondition `DO $$ ... $$` block** (CTO R4): over `public.conversations` rows covered by the unique index
   (`repo_url IS NOT NULL AND context_path IS NOT NULL AND archived_at IS NULL`; the NULL filter must be explicit because
   `GROUP BY` treats NULLs as equal while the unique index treats them as distinct), compute the effective value
   `COALESCE(c.canon_ok, x.repo_url)` and `GROUP BY user_id, effective, context_path HAVING count(*) > 1`; if any group exists,
   `RAISE EXCEPTION '163 precondition failed: % collision group(s)', <count>`: the count only, never `user_id`,
   `repo_url` or `context_path` (GDPR-Suggestion-1); no `USING DETAIL` or `HINT`. Includes already-canonical rows so new-vs-existing and new-vs-new collisions are both caught.
   Raises BEFORE any write. A raise blocks every release until the data is fixed (the runner uses `psql --single-transaction`
   and `migrate` gates `deploy`); it is a data decision owned by the engineer holding the failed release, and prd shows none.
2. `UPDATE public.conversations x SET repo_url = n.canon_ok FROM (SELECT x.id, c.canon_ok FROM public.conversations x <canon-expr> WHERE x.repo_url IS NOT NULL) n WHERE n.id = x.id AND n.canon_ok IS NOT NULL AND x.repo_url <> n.canon_ok;`
   (alias handling is for the implementer; the shape above was prototyped).
3. The same `UPDATE` for `public.workspaces`. (No unique index on `workspaces.repo_url`, so no collision risk. No trigger fires on a
   `repo_url` update for either table: the only triggers are `UPDATE OF archived_at` and `UPDATE OF engine_binding_state`, plus an
   `INSERT` trigger on conversations, grep-verified.)

New `163_renormalize_repo_url.down.sql`: an explicit no-op with a comment ("data backfill is not reversible; the pre-image is
not retained"). No `DROP`/`DELETE`/`UPDATE`.

Then generate `PG_GOLDEN_163` from the committed expressions against dev (SELECT only) and re-run the Phase 1 tests (GREEN).

### Phase 3 - Verify sentinel and shape test (deliverable b)

New `apps/web-platform/supabase/verify/163_renormalize_repo_url.sql` (contract: `check_name`, `bad`; obeys
`verify-sql-string-literals.test.ts`: no double quotes, no backslash in code position, no non-ASCII, no `E''`; control
characters built with `chr()`; regex backslash escapes appear only inside `'...'` literals). Three rows:

| check_name | bad = |
|---|---|
| `conversations_noncanonical` | rows where `canon_ok IS NOT NULL AND repo_url <> canon_ok` (the migration's own WHERE as a SELECT; ineligible rows are excluded by construction) |
| `workspaces_noncanonical` | same for workspaces |
| `canon_expr_selftest` | count of `VALUES` fixtures (shielded, interleaved, padded, eligible stored forms, and ineligible rows expecting NULL) whose expression output differs from the literal expected value; evaluated on a real engine on every deploy |

Strict: no excused residue (CTO R4). `verify/031` is untouched. Caveat recorded in the migration header: its
`conversations_idempotence` probe guards on the INPUT and uses the OLD chain, so a stored row that 031's chain would still rewrite
but 163 skips (`skipped_but_changed`: internal whitespace, port, userinfo, non-http, degenerate host) is flagged by the old probe
forever; the pre-merge baseline must show 0 such rows on prd.

New `test/supabase-migrations/163-renormalize-repo-url.test.ts` (offline text lint, repo pattern from 080/162; it is a regression
tripwire, not proof of runtime behaviour: Test Scenarios 7 and 8 are one-time dev rehearsals), on comment-stripped text where the
080 test does so:

- migration: no `BEGIN`/`COMMIT`/`CONCURRENTLY`; `SET LOCAL lock_timeout` and `LOCK TABLE public.conversations` precede the precondition `DO` block and the
  `DO` block (byte offset) precedes the first `UPDATE`; both tables updated; `<>` idempotence guard and `IS NOT NULL` on
  `canon_ok`; no reference to `public.users`; `.down.sql` is a no-op (no `DROP`/`DELETE`/`UPDATE`).
- precondition body (extract the text between `DO $$` and `END $$`, then assert inside it): `repo_url IS NOT NULL`,
  `context_path IS NOT NULL` and `archived_at IS NULL` are all present there (a bare-token match on the whole file would pass with
  the filter dropped, since the same tokens appear in the UPDATE); every `RAISE EXCEPTION` has exactly one `%` and one argument
  that is a `count(*)` variable; no `USING DETAIL` or `HINT` anywhere in the migration.
- expression identity: extract each `-- canon-expr begin ... end` block BEFORE comment stripping (the markers are comments),
  collapse whitespace, and assert `new Set(copies).size === 1` across the migration (precondition and two UPDATEs), the verify
  file (two probes and the selftest) and the golden SQL fixture. This is the one assertion linking the migration text to verify and
  to the golden recipe; the block is table-independent, so the set size can be 1.
- verify: exact `check_name` SET `{conversations_noncanonical, workspaces_noncanonical, canon_expr_selftest}`, each bound to its
  table and comparison polarity (learning 2026-07-11).

### Phase 4 - Flake pins and closure (#10732, #10713)

Already pinned on `main` (do not duplicate): `" http://a.aa/..git.git/"`, `"http://a.aa/..git.git"`, `"https://x.io/a/..git"`
(the `pinned #10716` `it.each`), `" http://a.aa/..git.git"` and the dot-segment table in `repo-url.property.test.ts`.

Edit `apps/web-platform/test/lib/repo-url.property.test.ts`: add a `describe` with an `it.each` of `[input, expected]`
(each asserts the expected value AND `normalize(once) === once`), labelled
`// regression fixture: counterexample from CI run 39506606768 (#10732), fast-check seed not recorded` and
`// regression fixture: counterexample from CI run 39462075257 (#10713), fast-check seed not recorded`:
`"http://a.aa/."` -> `http://a.aa`, `"http://a.aa/..git"` -> `http://a.aa`, `"a://A"` -> `a://a`, `" a://A .git"` -> `a://a`, `"a://A /"` -> `a://a`,
`" a://A/..git"` -> `a://a`. `"http://a.aa/."` and `"a://A"` are issue-named pins annotated in a comment as non-discriminating
(they pass on the pre-fixpoint code in isolation); the other four are the discriminators. No `{ seed }` params, no `.only`/`.skip`; the generator is NOT widened (the pins carry the
regression; the fuzz audit above is the one-time evidence).

Evidence + closure: post one `gh issue comment` on each of #10732 and #10713 quoting the Flake-audit table (pre-fixpoint
non-fixpoint vs current fixpoint, 7 seeds x 100,000 runs, fix commit `c97a0be3b8`, #10695, the pin test names). Closure is
via `Closes #10732`, `Closes #10713` and `Closes #10633` in the PR body (after the pins merge), per
`wg-use-closes-n-in-pr-body-not-title-to`. PR #10692 is neither edited nor closed; the final PR body mentions it for the operator.

### Phase 5 - Docs and pointers

- `lib/repo-url.ts`: docstring only. Replace "Coupled with the Postgres backfill in 031 ..." with a pointer to the
  sync-sites registry in `test/repo-url-sql-parity.test.ts` (a migration number goes stale at 164). No executable change.
- ADR-293 section "First yield": replace "tracked as a follow-up" with the resolution (migration 163, #10633).
- Learning `2026-10-20-repo-url-retrim-shielded-whitespace-sql-twin.md`: mark the "Follow-up needed" line resolved and add
  the findings (D2/D3 beyond the issue; the issue's example is `%20` in TS; migration immutability forces a new file).
  No rule-file or `AGENTS.md` edits.

### Phase 6 - Post-merge (automated)

`web-platform-release.yml` `migrate` applies 163; `verify-migrations` runs `verify/163` (all `bad` must be 0); the
follow-through scan closes issues naming `163_renormalize_repo_url`. No soak window and no operator step. If `migrate` aborts
on the precondition (a collision group on prd), the failure is a plain loud error naming the count; resolution is a data
decision (which conversation to keep), not made by the migration.

## Files to Create

- `apps/web-platform/supabase/migrations/163_renormalize_repo_url.sql`
- `apps/web-platform/supabase/migrations/163_renormalize_repo_url.down.sql`
- `apps/web-platform/supabase/verify/163_renormalize_repo_url.sql`
- `apps/web-platform/test/supabase-migrations/163-renormalize-repo-url.test.ts`
- `apps/web-platform/test/fixtures/sql/normalize-repo-url-163-golden.sql`
- `knowledge-base/project/specs/feat-one-shot-10633-normalize-repo-url-sql-retrim/decision-challenges.md`
- `knowledge-base/project/specs/feat-one-shot-10633-normalize-repo-url-sql-retrim/tasks.md`

## Files to Edit

- `apps/web-platform/test/repo-url-sql-parity.test.ts`
- `apps/web-platform/test/lib/repo-url.property.test.ts`
- `apps/web-platform/lib/repo-url.ts` (docstring only)
- `knowledge-base/engineering/architecture/decisions/ADR-293-property-based-testing-adoption.md` (one paragraph)
- `knowledge-base/project/learnings/logic-errors/2026-10-20-repo-url-retrim-shielded-whitespace-sql-twin.md` (follow-up resolved)

Glob check: every existing path above is verified with `git ls-files`; for new paths the parent directory exists
(`test/fixtures/` exists; `test/fixtures/sql/` is created with the first file).

## Non-Goals

- Mirroring URL parse, dot-segments, `%20` encoding, userinfo/port in SQL (D4); exotic Unicode whitespace (D5).
- Any change to `normalizeRepoUrl` behavior (already correct).
- Editing 031 or `verify/031` (immutable / still passing).
- Touching stale draft PR #10692.
- A permanent SQL normalizer function (CTO R3), a census test for future `repo_url` tables, a gated live-DB test block, widening
  the existing property generator.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `163_renormalize_repo_url.sql` and `.down.sql` exist; ordinal 163 re-checked free on freshly fetched `origin/main` and across pushed
  branches immediately before commit and again before merge (procedure, not a checkbox that can rot).
- [ ] `bash apps/web-platform/scripts/lint-migration-immutability.sh --base origin/main --head HEAD` prints `migration-immutability: clean`.
- [ ] Baseline counts for dev and prd (counts only: per table `total`, `with_url`, `to_rewrite` (eligible rows the migration would change), `skipped_but_changed` (rows the old 031 chain would rewrite but the eligibility guard skips), plus the collision-group count) recorded in the PR body BEFORE the first push containing the migration, and re-run on prd within the hour before merge; STOP if any of `to_rewrite`, `skipped_but_changed` or collisions is above 0 and take a Supabase backup first if `to_rewrite > 0` (no pre-image table: it would add an account-linked data store for zero rows).
- [ ] Expression validated on real Postgres: the committed golden SQL script run on dev (SELECT only) output equals `PG_GOLDEN_163`
  row for row; the parity test asserts the port against that table.
- [ ] Rehearsal on dev inside `BEGIN; ... ROLLBACK;` (one-time evidence; the shape test is only a tripwire): the migration body rewrites seeded eligible shielded rows, leaves seeded ineligible rows (`https://github.com/o .git`, port, userinfo) untouched, a second run is `UPDATE 0`, a seeded collision pair makes the DO block raise with the count and modify nothing, and a NULL-`repo_url` pair does not raise.
- [ ] After CI applies 163 to dev: `verify/163` run via `psql -f` (wrapped in `doppler run ... -- sh -c`) returns `bad = 0` on all three rows.
- [ ] `cd apps/web-platform && ./node_modules/.bin/vitest run test/repo-url-sql-parity.test.ts test/lib/repo-url.property.test.ts test/repo-url.test.ts test/supabase-migrations/163-renormalize-repo-url.test.ts test/supabase-migrations/verify-sql-string-literals.test.ts` passes.
- [ ] One-time scratch fuzz (not committed): P1 and P3 at 100,000 runs over at least 3 seeds pass; result noted in the PR (the
  generators that produced #10732/#10713 were the flake; this guards the new generator against becoming the next one).
- [ ] One RED proof per guard recorded in the PR body (Guard Contract rows), then reverted: Guard 1 row 1, Guard 2 row 1.
- [ ] Against the pre-fixpoint code (`git show 91594324ef:apps/web-platform/lib/repo-url.ts` into a scratch copy) the pins `"http://a.aa/..git"`, `" a://A .git"`, `"a://A /"` and `" a://A/..git"` fail the fixpoint assertion; `"http://a.aa/."` and `"a://A"` (the issue-named values) pass in isolation there, because their failing contexts depended on the shrink path. All six pass on `main`; noted in the PR.
- [ ] `git diff origin/main...HEAD -- apps/web-platform/lib/repo-url.ts` shows comment lines only (merge-base diff, not the moving tip).
- [ ] `python3 scripts/lint-guard-contract.py` and `bash plugins/soleur/skills/ship/scripts/technical-ruling-gate.sh --branch feat-one-shot-10633-normalize-repo-url-sql-retrim` pass; `npx markdownlint-cli2` clean on the plan and `tasks.md`.
- [ ] Evidence comments posted on #10732 and #10713; PR body contains `Closes #10633`, `Closes #10732`, `Closes #10713` (not in the title) and notes #10692 untouched.
- [ ] No `{ seed }` or `.only`/`.skip` added by this PR: `git diff origin/main...HEAD -U0 | grep -E '^\+.*(\{ *seed|\.only\(|\.skip\()'` returns nothing.

### Post-merge (automated, no operator action)

- [ ] `migrate` job green and its log shows `Applying: 163_renormalize_repo_url.sql`. `verify-migrations` is skipped on the `workflow_run` deploy arm (#9471, open), so the merge deploy cannot run `verify/163`; the equivalent evidence is the pre-merge dev run of the verify file (all three rows `bad = 0` after CI applies 163) and the prd read-only run of the same file recorded in the PR body. Once #9471 lands, `verify/163` runs on every release.
  > Amended 2026-10-23 (review): the original criterion required the `verify-migrations` conclusion to be `success`; the deployment-verification seat showed the merge arm skips it.
- [ ] Forward-fix procedure (documented in the migration header): a defect in 163 ships as migration 164; 163 is never edited. A precondition raise is resolved as a data decision (which conversation to keep), then `migrate` re-runs.

## Test Scenarios

1. `"http://a.aa .git"` -> chain: TS `http://a.aa`, 163 `http://a.aa`; the 031 port keeps a trailing space (defect). Backfill: ineligible (internal whitespace), untouched.
2. `"https://github.com/foo/bar/.git/.git"` -> TS and 163 chain `https://github.com/foo/bar`; 031 port `https://github.com/foo/bar/.git`. Backfill: rewritten.
3. `"\thttps://github.com/foo/bar\n"` -> TS and 163 `https://github.com/foo/bar`; 031 port keeps the tab (D3).
4. `"https://x/y .git"` -> TS `https://x/y%20`, 163 chain `https://x/y` (OUT_OF_PARITY, pinned both sides); backfill ineligible, untouched.
5. `"http://.git"` -> TS `http:`, 163 leaves the row unchanged; OUT_OF_PARITY, pinned both sides.
6. Re-run of 163 on migrated data -> `UPDATE 0`.
7. (one-time dev rehearsal) Two conversations differing only by a trailing space for one user/context_path -> precondition raises, no write.
8. (one-time dev rehearsal) Two NULL-`repo_url` rows sharing `(user_id, context_path)` -> precondition does NOT raise (explicit NULL filter).
9. `" a://A .git"` and `" http://a.aa/..git.git/"` -> fixpoint on current TS; NOT a fixpoint on `91594324ef`.
10. Stored 031-shaped rows `"http://a.aa "`, `"https://github.com/Foo/Bar/ "` -> rewritten to the TS form; `"https://github.com/o .git"`, `"https://u:p@Host/x"`, `"http://a.aa:80/x"`, `"https://0/x"` -> untouched.

## Guard Contract

### Guard 1 - verify/163 sentinel and its shape test

**Property.** After every deploy, no eligible `conversations.repo_url` or `workspaces.repo_url` value differs from the canonical form of
itself, and the canonical expression (chain plus eligibility) still maps its fixtures correctly on the live engine.

**Assembly.** Quantifies over: (a) both tables with a live `repo_url` column (`conversations`, `workspaces`; `users` dropped by
112); (b) every copy of the `canon-expr` block: the precondition and two UPDATEs in `163_renormalize_repo_url.sql`, the two
noncanonical probes and the selftest in `verify/163_renormalize_repo_url.sql`, and the golden SQL fixture, all forced identical
(after whitespace collapse) by one set-size comparison in `163-renormalize-repo-url.test.ts`; (c) the three `check_name` rows as a SET.
The chokepoint is the `canon-expr` marker block: copies are compared against each other, not against a snapshot string.

**Mutation matrix.**

| # | Edit (must drive RED) | Caught by |
|---|---|---|
| 1 | Remove `[ \t\n\r\f\v]` from the tail alternation in ONE verify copy only | expression-identity set comparison; selftest fixture `"http://a.aa "` |
| 2 | Remove the `a.t !~ ...` internal-whitespace clause (eligibility) from ONE copy | expression-identity set comparison; selftest fixture `"https://github.com/o .git"` expecting NULL |
| 3 | Delete the `workspaces_noncanonical` SELECT (own dispatch: fewer checks, still exit 0) | check_name SET-identity assertion (not a count floor) |
| 4 | Move the precondition `DO` block after the first `UPDATE` (REORDER, not delete) | shape test byte-offset assertion |
| 5 | Drop `context_path IS NOT NULL` (or the `repo_url IS NOT NULL` filter) from the precondition body only | precondition-body-scoped assertions (a whole-file token match would pass) |

**Harness rows.** Suite edit that must go RED: empty the expected `check_name` set in the shape test, and the set-identity
assertion fails. Must-PASS non-canonical input: the same verify SQL reformatted (keyword case, indentation, extra comment lines)
still passes the identity check, and a stored `https://github.com/Foo/Bar` (mixed-case path, otherwise canonical) is not counted as bad.

**Anchor.** The verify compares live rows to an expression living in the same commit as the migration. What must move outside
this commit for a weakening to pass: the Postgres-generated golden table (which carries the 031 chain and 163 columns) and the TS
`normalizeRepoUrl` suites (`test/repo-url.test.ts`, `repo-url.property.test.ts`), both asserted equal to the SQL ports in Guard 2.
Editing the expression and the verify consistently still fails the golden and TS-parity assertions.

### Guard 2 - TS <-> SQL(163) parity and backfill-safety gate

**Property.** For every URL-clean ASCII input `normalizeRepoUrl(x)` equals the 163 SQL chain; and the BACKFILL only ever writes
`normalizeRepoUrl(old)` (it rewrites a row only when SQL provably equals TS); and `normalizeRepoUrl` is a fixpoint on the
#10732/#10713/#10716 counterexample classes.

**Assembly.** Quantifies over: input dimensions (scheme case x host case x path segments x suffix tokens `/` `.git` any case
x whitespace shield tokens x padding x interleaving order x repetition), each named in `urlCleanArb`, with the space shield
restricted to host position (path-position spaces are `%20` in TS); the adversarial dimensions of the safety property (percent
escapes, dot-segments, ports, userinfo, query/fragment, empty segments, non-http schemes, numeric hosts, internal whitespace);
implementations: the TS function, `sqlChain163`, `sqlBackfill163`, `sqlNormalize031` (historical oracle) and the Postgres golden
table; all in one file whose header is the sync-sites registry. Out-of-domain inputs are enumerated in `OUT_OF_PARITY`.

**Mutation matrix.**

| # | Edit (must drive RED) | Caught by |
|---|---|---|
| 1 | Drop the whitespace alternative from `sqlChain163`'s tail strip | `SHIELDED_WS_FIXTURES`, P1, golden table |
| 2 | Make TS `stripTrailingSlashAndGit` stop after one token (no interleaving loop). Reverting only the final `working.trim()` is NOT a valid mutation: the fixpoint loop's next pass re-trims, which is why the re-trim is redundant in TS and matters only in the SQL twin | fixture `".../bar/.git/.git"`, P1, existing TS fixtures |
| 3 | Restore the 031 three-step chain in the port (non-interleaved strip), after the first compliant fixture: second member | fixture `".../bar/.git/.git"`, P1, golden table |
| 4 | Remove the eligibility guard (either clause) from `sqlBackfill163` (precondition satisfied: the chain output is valid, the property fails) | safety property P2 (counterexamples `https://github.com/o .git`, `https://github.com//../o`), `BACKFILL_FIXTURES` |
| 5 | Generator emits only canonical strings (the guard's own dispatch: the property still "passes") | `SHIELDED_WS_FIXTURES.length >= 8` / `BACKFILL_FIXTURES.length >= 8` floors plus the golden table, which does not depend on the generator |

**Harness rows.** Suite edit that must go RED: empty `SHIELDED_WS_FIXTURES`, and the length floor fails. Must-PASS non-canonical
input: `"\thttps://github.com/foo/bar\n"` (padding the contract explicitly permits) passes parity, and
`"https://github.com/Owner/Repo"` (mixed-case path) passes unchanged.

**Anchor.** Port correctness is anchored outside the repo's code by the Postgres-generated golden table; TS correctness by
`test/repo-url.test.ts` and `repo-url.property.test.ts`. A weakening must edit the port, the golden table AND the TS suites
consistently; editing the port alone reds the golden assertion, editing port and golden reds TS-versus-port.

## Domain Review

**Domains relevant:** engineering (CTO), legal (GDPR gate, advisory)

### Engineering (CTO)

**Status:** reviewed
**Assessment:** Four design rulings (R2-R5) recorded in `decision-challenges.md`; additional risks adopted (no-op down
file, pinned out-of-parity corpus, dev rehearsal for collision rows, ordinal re-check).

### Legal (GDPR gate)

**Status:** reviewed (advisory). `soleur:gdpr-gate` clean on all six v1 checks; one Suggestion adopted (no row data in the precondition error text).

Product/UX: none - no user-facing surface, no component or page file in the Files lists (mechanical UI-surface override: no match).

## Architecture Decision (ADR/C4)

No new architectural decision. A corrective backfill on two existing columns, in the ADR-044 ownership model, with no
new substrate, trust boundary, or resolver change. C4 check: external actors/systems (GitHub App webhook sender, GitHub
installation), data stores (`conversations`, `workspaces`), and the webhook-reconcile access relationship are
already modeled (`model.c4`, `views.c4`, `spec.c4` read); no actor, system, container, or relationship changes, and no
derived cardinality in edge prose moves. The only architecture-record edit is the stale "follow-up" sentence in ADR-293.

## Encryption Posture

No new persistent store and no new connection: the change rewrites values inside two already-provisioned Supabase tables
over the already-ledgered server-to-Supabase connection. `supabase/migrations/*.sql` matches the detection regex as a file
pattern, so the existing ledger rows are cited here rather than the section being skipped. Both rows live in
`scripts/encryption-posture-ledger.json` (store `supabase.prd`; connection `web-platform server -> Supabase Postgres/PostgREST`).

```yaml
at_rest:
  - store: public.conversations and public.workspaces (supabase.prd), unchanged by this plan
    mechanism: provider-managed:supabase-postgres-aes256
    evidence: ledger row supabase.prd cites the Supabase security documentation (https://supabase.com/docs/guides/security), retrieved 2026-07-24
    defends_against: physical-media compromise of the managed Postgres storage
    does_not_defend: a leaked service-role key, an RLS bypass, or any query via a legitimate connection; the encryption key is provider-managed
    disclosed_as: not-publicly-claimed
    live_verification: unavailable:named SOC 2 attestation formalization pending; tracked #6911 (inherited from the ledger row)
in_transit:
  - connection: migration runner and verify job -> Supabase Postgres (psql over DATABASE_URL_POOLER), and the existing web-platform server -> Supabase path
    tls: TLS 1.2+ (ledger row for the web-platform server connection; the runner uses the same pooler endpoint)
    cert_verification: on
    does_not_defend: a leaked database URL or service key; TLS protects the channel, not the credential
    disclosed_as: not-publicly-claimed
```

No `exception` block: no row is `plaintext-exception` and no connection has `cert_verification: off`.

## Observability

```yaml
liveness_signal:
  what: the verify-migrations job runs apps/web-platform/scripts/run-verify.sh, which executes verify/163_renormalize_repo_url.sql and fails on any bad > 0
  cadence: every release run on push to main (per deploy)
  alert_target: the deploy job is gated on verify-migrations (needs list), so a red verify blocks the deploy and the release workflow reports failure
  configured_in: .github/workflows/web-platform-release.yml (verify-migrations job, run-verify.sh step)
error_reporting:
  destination: GitHub Actions run annotations (::error:: lines from run-verify.sh); the migrate job surfaces the migration's RAISE EXCEPTION text via psql ON_ERROR_STOP
  fail_loud: verify-migrations exits 1 and deploy is skipped; migrate exits non-zero with "163 precondition failed: N collision group(s)" (count only, no row data)
failure_modes:
  - mode: two conversations collide after canonicalization (unique index would abort the UPDATE)
    detection: precondition DO block raises before any write; migrate job red
    alert_route: release workflow failure blocks deploy
  - mode: a non-canonical repo_url appears after the migration (new writer bypasses normalizeRepoUrl)
    detection: verify conversations_noncanonical / workspaces_noncanonical bad > 0 on the next release
    alert_route: verify-migrations red blocks deploy
  - mode: Postgres regex semantics differ from the golden table (engine upgrade, locale change)
    detection: verify canon_expr_selftest bad > 0 on a real engine every release
    alert_route: verify-migrations red blocks deploy
logs:
  where: GitHub Actions run logs for the release workflow (verify-migrations and migrate jobs)
  retention: repository Actions log retention setting (GitHub default 90 days)
discoverability_test:
  command: grep -o -e conversations_noncanonical -e workspaces_noncanonical -e canon_expr_selftest apps/web-platform/supabase/verify/163_renormalize_repo_url.sql
  expected_output: canon_expr_selftest or workspaces_noncanonical
```

The probe reads the committed sentinel in this PR's tree and prints its check names; the runtime evidence is the CI job above
(no SSH, no dashboard). The command has no shell-active characters and finishes well inside Check 10's 15-second cap.

## Risks and Sharp Edges

- **Ordinal collision.** Two PRs already share 162. Re-run the `git ls-tree origin/main` check right before committing
  and again before merge; renumber the migration, `.down.sql`, verify file, shape test names, and every AC/task that
  names `163` in the same edit.
- **Applied-migration immutability.** `tenant-integration` applies 163 to dev on first push; any later edit (even a
  comment) breaks the "Assert unmerged migrations match the dev ledger" gate. Finalize the SQL text, including comments,
  before the first push that contains it.
- **Verify file lexer.** No `"`, no backslash in code position, no non-ASCII, no `E''`; build control chars with `chr()`.
- **Regex class vs locale.** Use the explicit ASCII class, never `[[:space:]]`; exotic Unicode whitespace is out of domain.
- **A plan whose `## User-Brand Impact` is empty fails deepen-plan Phase 4.6**: filled above.
- **Golden-table provenance.** The golden table must be generated by Postgres from the committed expression, SELECT only;
  never paste values produced by the JS port (that would make the oracle self-referential).
- **Reconcile ambiguity effect.** If the rewrite made two same-installation solo workspaces' `repo_url` equal,
  `server/resolve-founder-for-installation.ts` would move from one match to ambiguous and drop events: an availability effect,
  not a leak, and the prd baseline shows nothing to rewrite.
- **Regex cost bound (measured).** On the dev engine the trim regex took 0.9 s on a 400 KB value with a 200 KB interior
  whitespace run and the tail strip 0.1-0.3 s on 600 KB inputs (quadratic-leaning, not catastrophic). Prod `repo_url` max
  length is 59 (workspaces) and 44 (conversations), checked 2026-10-22 with an aggregate `max(length())`, and the write
  boundary enforces `^https://github.com/[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$`; no length guard is added.
- **Reduced verify cost.** `verify/163` scans ~200 rows today; re-check if `conversations` grows by orders of magnitude.

## Plan Review Revisions (2026-10-22)

Panel: DHH-style, Kieran-style, code-simplicity (per mechanism, against the Property and Cut Lists), and the CTO devex lens.
Applied as mechanical: shield fixtures and generator restricted to host position for spaces (path-position spaces are `%20`
in TS, D4); `http://.git` pinned out-of-parity (TS `http:`); JS ports use `[\s\S]*` for PG `.` semantics; explicit
`repo_url IS NOT NULL` filter in the precondition; `verify/031` degenerate-row caveat recorded; baseline counts captured
before the first push; AC ordinal check moved to a pre-commit/pre-merge procedure; numeric-host IPv4 canonicalization added
to D4 after a fuzz run found it; golden-table regeneration script committed; docstring points at a registry, not a migration
number. Applied as taste (recorded in `decision-challenges.md`): helper module, separate property file, census test,
`*_ws_residue` probes, gated live-DB block, and generator widening cut. Kept against the DHH/simplicity "drop the Guard
Contract tables" suggestion: the plan skill requires them (Phase 2.12) and `lint-guard-contract.py` enforces them; the
matrices were shortened instead.

## Deepen-plan Revisions (2026-10-22)

Applied from the migration-expert, deployment-verification, test-design and security passes plus direct measurement: eligibility
guard and its safety property (see "Backfill safety"); fixtures and golden table extended to every fixture and to the old 031 chain,
with a row-count tie to the script; `canon-expr` block made table-independent so the identity set can be size 1; precondition-body-scoped
shape assertions; Guard 2 row 2 replaced (a TS-side re-trim revert is not killable because the fixpoint loop re-trims; verified by
mutation); non-discriminating pins annotated; `LOCK TABLE` with `lock_timeout` and a 2048-character eligibility clause (CTO L1, L2); baseline columns `to_rewrite` and
`skipped_but_changed` re-run on prd within the hour before merge; post-merge AC requires the `verify-migrations` conclusion to be
`success`, not `skipped`; forward-fix procedure documented (164, never an edit). Not applied: a pre-image snapshot table and a CSV
backup (zero rows to protect; backup only if the baseline shows rewrites).
