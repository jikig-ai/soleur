---
title: "fix: integration-ci auth.admin.deleteUser 500s on dev — route suite teardown through the anonymise-first helper"
type: fix
date: 2026-10-12
slug: fix-integration-deleteuser-500s-teardown
branch: feat-one-shot-9994-deleteuser-500s
issue: 9994
closes: 9994
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# fix: integration-ci auth.admin.deleteUser 500s on dev — route suite teardown through the anonymise-first helper

## Overview

Nightly integration legs `supabase-dev` and `byok` (`.github/workflows/scheduled-integration-suites.yml`)
are red: `auth.admin.deleteUser` returns GoTrue's opaque `500 unexpected_failure`
("Database error deleting user") for synthetic test users. **The issue-prescribed probe has
already run during planning** — live evidence below names the blocker:
`workspace_members_user_id_fkey` (ON DELETE RESTRICT), created for *every* auth user by the
`handle_new_user` trigger (mig 053 → current shape mig 112). Raw `admin.deleteUser` can never
succeed for a created user; only suites that run the production anonymise-first cascade (or an
equivalent manual FK-reverse) can tear down. This is hypothesis 1 of the issue, confirmed.

The fix is suite-side: widen `test/helpers/tenant-isolation-teardown.ts`'s synthetic-email
sentinel to a prefix allowlist and route the five defective suites through it, plus a small
fold-in repair of stale `conversations` inserts missing the NOT-NULL `workspace_id` (same leg,
same verify-green gate). A source-grep sentinel test makes the next raw-deleteUser suite a red
unit test instead of a red nightly.

*Spec lacks valid `lane:` — defaulted to cross-domain (TR2 fail-closed).*

## Enhancement Summary

**Deepened on:** 2026-10-12 (soleur:deepen-plan)
**Sections enhanced:** Problem Statement, Phase 2, Phase 4, Phase 5, Guard Contract,
Observability, Non-Goals, Acceptance Criteria

### Key improvements

1. **Wider latent class measured, not guessed:** census over `test/**` found 32 files
   containing `admin.deleteUser(` (13 on the nightly surface); supabase-js returns
   `{ data, error }` rather than throwing, which is *why* ~18 `test/server/**` suites silently
   leak synthetic users while only the result-checking suites went red. Filed as **#10096**.
2. **`messages` fold-in added:** dev `information_schema` shows `messages.workspace_id` is also
   `NOT NULL` — the same suites' `assistantRowFor`/direct message inserts would fail `23502`
   the moment the conversation seeds pass. Phase 4 + AC6 now cover both tables.
3. **`## Observability` added** (Phase 4.7 halt) with a Check-10-shaped
   `discoverability_test` (`rg -l -e SYNTHETIC_PREFIXES …` → `tenant-isolation-teardown`).
4. **Exact-shape constraint pinned by learning:** the prefix allowlist keeps the
   `[a-f0-9]{16}` suffix; a permissive prefix repeats the PR #2597 permissive-regex incident.

### New considerations discovered

- The four allowlisted manual-FK-reverse suites were re-verified — each calls
  `anonymise_workspace_members` + manual `workspaces` delete deliberately (WORM-trigger
  bypass comment included); allowlisting is correct, not a gap.
- Both acquire RPCs (`acquire_conversation_slot`, `acquire_worktree_lease`) already populate
  `workspace_id` on dev — the #10094 failures are genuinely a different root cause.
- All generator shapes verified in-file (5/5 emit `randomBytes(8).toString("hex")`).

## Problem Statement / Motivation

- `test/beta-crm-dsar.integration.test.ts` AC10 calls `service.auth.admin.deleteUser(userA.id)`
  mid-test → 500; the cascade-erase assertion then fails (`expected [2 rows] to have length 0`).
- `test/byok.integration.test.ts` `afterAll` calls raw `deleteUser` and throws on error → leg red.
- Same defect, same leg, confirmed in the run log: `cc-dispatcher-cross-tenant` and
  `conversations-rail-cross-tenant` `afterAll` (`afterAll: deleteUser(…) failed: Database error
  deleting user`), and `dsar-export-cross-tenant` whose best-effort `try/catch` silently leaks
  the synthetic user (86,916 NULL-owner `organizations` rows already sit on dev from this
  cruft class — measured 2026-10-12).
- **Why only some suites went red:** supabase-js `deleteUser` returns `{ data, error }` — it
  does not throw. Suites that check the result fail loudly; suites that ignore it (bare
  `await`, `.catch(() => {})`, `try {} catch {}` swallows) leak the user and stay green. The
  defect class is therefore much wider than the two red legs — ~18 `test/server/**` files share
  it silently (tracked as #10096; this plan fixes the nightly-leg surface).
- Same leg, different root cause also blocking green: `conversations` inserts missing
  `workspace_id` (NOT NULL since mig 059) in `cc-dispatcher-cross-tenant` and
  `conversations-rail-cross-tenant` → `23502` failures.
- Run: <https://github.com/jikig-ai/soleur/actions/runs/38130672233> (tracker #9993 —
  referenced, never closed).

## Probe Evidence (captured at plan time, 2026-10-12, dev project)

The issue asked for the actual Postgres error behind GoTrue's 500. Reproduced live:

1. `admin.createUser` → `admin.deleteUser` on a fresh minimal fixture user
   (`plan-probe-9994-*@soleur.test`): `AuthApiError status=500 code=unexpected_failure`. ✓ symptom.
2. `DELETE FROM public.users WHERE id='<uid>'` (psql via `doppler run -p soleur -c dev`):
   `ERROR: update or delete on table "users" violates foreign key constraint
   "workspace_members_user_id_fkey" on table "workspace_members"`. **Named constraint —
   hypothesis 1 confirmed.** The blocker is the trigger-created owner membership, present for
   *every* user before any suite seeding.
3. After `SELECT anonymise_workspace_members(uid)` + `anonymise_workspace_member_actions(uid)`:
   `DELETE 1`; the subsequent `admin.deleteUser` returned `error: null`. No second blocker behind
   the first for a minimal user. Probe user + residue removed.
4. Live FK census (`pg_constraint`, `confrelid=public.users`): 26 `RESTRICT` + 2 `SET NULL` +
   12 `CASCADE` children. Every RESTRICT table maps to an RPC already in the helper's
   `ANONYMISE_SEQUENCE` (22 RPCs, parity-guarded).
5. **Hypothesis 2 refuted:** `pg_proc.prosrc` for `audit_byok_use_no_mutate` on dev contains the
   mig-066 `founder_id` Art-17 carve-out (`position('founder_id' in prosrc) > 0` → true).
6. **Hypothesis 3 — one real drift found (non-blocking for these suites):**
   `audit_github_token_use_founder_id_fkey` is `RESTRICT` on dev but mig 052:68 declares
   `SET NULL` on main — dev carries a shape that never existed on main. Filed as **#10095**
   (dev-ledger reconcile; relevant to mu1's future teardown, noted for #9995's owner).
7. The issue's example `denied_jti.founder_id` is stale: mig 106 flipped it to `ON DELETE
   CASCADE` (dev census confirms `c`). The RESTRICT *class* it exemplified is what held.

## Proposed Solution

### Phase 1 — Probe (completed at plan time)

Evidence above. Residual work-phase verification: none required — the constraint is named and
the cascade path proven. (The issue's suggested Postgres-log read turned out unnecessary:
PostgREST/psql `DELETE` surfaces the constraint name directly.)

### Phase 2 — Helper generalization (the core fix)

`test/helpers/tenant-isolation-teardown.ts`:

- Replace the single-prefix `SYNTHETIC_EMAIL_PATTERN` with an explicit **prefix allowlist**
  (fail-closed, same sentinel semantics — any non-listed prefix or domain still refuses):
  `tenant-isolation-`, `byok-isolation-`, `beta-crm-`, `cc-cross-tenant-`,
  `conv-rail-cross-tenant-`, `dsar-cross-tenant-`. All share the existing
  `[a-f0-9]{16}@soleur.test` suffix shape. Deriving the regex from an exported `const
  SYNTHETIC_PREFIXES` keeps the next suite's adoption a one-line, review-visible edit.
- Update the docblock: helper now serves every synthetic-suite teardown, not only
  tenant-isolation.
- `test/helpers/tenant-isolation-teardown.test.ts`: add positive cases per new prefix and the
  existing non-synthetic negatives; keep the throw-on-non-synthetic assertions.
- **Exact-shape constraint (learning-pinned):** the `[a-f0-9]{16}` suffix is load-bearing, not
  stylistic — every suite's generator emits `randomBytes(8).toString("hex")` (verified in-file:
  beta-crm:36, byok:35, cc:82, rail:48, dsar:34). A permissive `<prefix>-.*@` shape would let a
  future fixture's leftovers match (the PR #2597 incident class). See
  `knowledge-base/project/learnings/best-practices/2026-04-18-destructive-test-allowlist-regex-must-pin-exact-shape.md`.

### Phase 3 — Adopt the helper in the five defective suites

For each: import `tearDownTenantUser`, keep the suite's own `assertSynthetic` + `getUserById`
email round-trip checks where present, replace the raw `admin.deleteUser` (and its bespoke
error handling) with `await tearDownTenantUser(service, user)`:

- `test/beta-crm-dsar.integration.test.ts` — `afterAll` (userA/userB) **and** AC10's mid-test
  `deleteUser(userA.id)`. AC10's assertion semantics are preserved: the beta tables
  (`beta_contacts` etc.) are `ON DELETE CASCADE`, so they still empty at the auth-delete step —
  the anonymise RPCs do not touch them. Keep `userA.id = ""` to prevent double-delete.
- `test/byok.integration.test.ts` — `afterAll` (keeps the `getUserById` round-trip guard).
- `test/cc-dispatcher-cross-tenant.integration.test.ts` — `afterAll`.
- `test/conversations-rail-cross-tenant.integration.test.ts` — `afterAll`.
- `test/dsar-export-cross-tenant.integration.test.ts` — `afterAll` (upgrades best-effort
  swallow to the fail-loud helper path — same defect, currently a silent user-leak).

NOT adopted (deliberate): `conversation-archive-release-slot`, `worktree-write-lease`,
`concurrency-acquire-slot-workspace-id`, `workspace-binding-restart-survival` run deliberate
manual FK-reverse teardown that works (verified in the run log); `mu1` is #9995's scope.
`workspace-members-fixtures.ts`'s `tearDownSharedWorkspace` stays the multi-member path.

### Phase 4 — Fold-in: `workspace_id` insert repair (same leg, required for green)

`conversations.workspace_id` AND `messages.workspace_id` are both `NOT NULL` on dev (verified
live via `information_schema` 2026-10-12 — `user_concurrency_slots` and `worktree_write_lease`
also carry NOT NULL workspace_id; those tables are not seeded by these suites). The
trigger-created solo workspace id equals `user.id` (ADR-038 N2). The contract-pair learning
(`2026-05-22-tenant-integration-runtime-failures-post-mig-059.md`) records mig 059 making
`workspace_id` NOT NULL on **six** write tables and every stale caller failing 23514/23502 —
this fold-in is that class's test-side twin. These suites have been `describe.skip`-dormant
since creation, so **every** insert site needs the audit, not just the ones the failed run
reached:

- `test/cc-dispatcher-cross-tenant.integration.test.ts` — `conversations` inserts (~lines 196,
  496) AND every `messages` insert: the `assistantRowFor({conversationId, content})` helper
  (lines ~268, 309, 344, 361, 437) plus the direct `from("messages").insert(...)` (~line 455).
  Extend `assistantRowFor` to accept/emit `workspace_id` (or set it at each call site — pick at
  write time; the helper touches ~5 sites, so helper-level is the smaller diff).
- `test/conversations-rail-cross-tenant.integration.test.ts` — `conversations` inserts
  (~lines 209, 269 and any site the same grep surfaces).

Verification command (run at write time, expected = 0 offending sites):

```bash
rg -n 'from\("(conversations|messages)"\)' -A3 \
  apps/web-platform/test/{cc-dispatcher-cross-tenant,conversations-rail-cross-tenant}.integration.test.ts \
  | rg -B3 'insert\(' | rg -c 'workspace_id'   # == insert-site count for those tables
```

Without this the `supabase-dev` leg stays red on `23502` and Phase 3's fix cannot be verified.

### Phase 5 — Recurrence sentinel (guard deliverable)

New `apps/web-platform/test/server/teardown-deleteuser-sentinel.test.ts` — pure source-grep
unit test in the always-on shard (mirrors `teardown-anonymise-parity.test.ts`'s shape):

- Property + assembly + matrix in `## Guard Contract` below.
- Scope is deliberately `apps/web-platform/test/*.integration.test.ts` +
  `apps/web-platform/test/helpers/*.ts` — the nightly-leg surface where the defect shipped.
  `test/server/**` carries the same class silently and is tracked separately (#10096); widening
  the census there first would enshrine a ~20-file allowlist.
- Assert every in-scope file containing `\.admin\.deleteUser\(` is either a canonical teardown
  helper or on the explicit manual-teardown allowlist (post-fix census = 7: the two helpers,
  the four deliberate manual-FK-reverse suites, `mu1.integration.test.ts` allowlisted with a
  `#9995`-revisit comment).
- Anti-vacuity floor: the census must match ≥1 file (12 today on the scoped surface) so a
  call-expression drift can't silently vacate the guard.

### Phase 6 — Issue bookkeeping

- Post the probe evidence as a comment on **#9994** (named constraint + census + refutation of
  hypothesis 2).
- Post a heads-up comment on **#9995**: mu1's raw `deleteUser` (line ~183) will hit the same
  `workspace_members` RESTRICT once its 401 is fixed, plus the `audit_github_token_use` dev
  drift (#10095) is mu1-relevant (it mints installation tokens).
- Reference #9993; never close it.
- Already filed at plan time: **#10094** (slot-trigger `cap_hit` + worktree-lease `acquire`
  failures — unrelated root cause, separate legs), **#10095** (`audit_github_token_use` dev
  drift reconcile), **#10096** (latent `test/server/**` deleteUser gap — silent variant of this
  defect class).

## Technical Considerations

- **Why the helper over per-suite manual teardown:** `tearDownTenantUser` runs the full
  22-RPC anonymise sequence in production order with per-RPC fatality classes, and
  `test/server/teardown-anonymise-parity.test.ts` re-derives that list from
  `server/account-delete.ts` + migrations in the always-on shard. Per-suite hand-rolls are the
  proven drift source (the helper's docblock cites #5582's 8-vs-23 reopening).
- **Sentinel widening is a security boundary edit** (`hr-write-boundary-sentinel-sweep-all-write-sites`):
  an explicit prefix allowlist preserves fail-closed — the helper still refuses any email
  outside the enumerated synthetic shapes. The alternative (parameterizing the pattern) would
  let a caller pass a permissive regex; rejected.
- **No production code, no migrations** *(amended at work time — see below):*
  `server/account-delete.ts` and all workflow files are untouched. The dev drift
  (#10095) is reconciled via the dev-ledger machinery, not this PR.
- **Amendment (work time, operator-approved):** the dsar-export leg exposed a latent
  **prod** defect requiring one migration: `dsar_export_audit_pii_no_mutate`'s WORM
  gate lacked the `user_id→NULL` carve-out the `ON DELETE SET NULL` FK (mig 041) was
  designed around — `auth.admin.deleteUser` 500'd for every user with an
  export-audit row, on prd too. Migration
  `160_dsar_export_audit_pii_cascade_null_carveout.sql` (+`.down`) adds the
  carve-out mirroring `audit_byok_use_no_mutate`'s `founder_id` gate; applied to
  dev under the dev-suite mutex (operator-approved reconcile; both
  `NO ACTION`+`NOT NULL` FKs there realigned to `SET NULL`+nullable). This
  constraint otherwise holds — no production TS or workflow changes.
- **NFR:** no performance/security-surface change to shipped code; test-runtime cost increases
  slightly (22 RPCs per user teardown vs one call) — bounded, dev-only, and already paid by the
  suites using this helper.
- `psql` IS present on this workstation (`/usr/bin/psql`); the prior plan's sharp edge ("psql
  absent") applies to the GH runner — keep suite code on supabase-js, but direct-SQL probes are
  available locally via `doppler run -p soleur -c dev`.

## Research Insights

**Premise Validation (Phase 0.6):** #9994 OPEN (`type/bug`, `ci/integration-suites`); #9993
OPEN tracker — referenced, never closed; #9995 OPEN sibling — no work planned for it here.
Cited artifacts all exist: `test/beta-crm-dsar.integration.test.ts`,
`test/byok.integration.test.ts`, `server/account-delete.ts`,
`test/helpers/gotrue-retry.ts` (`withGoTrueRetry`), `scripts/run-migrations.sh`,
`scripts/preflight-worm-cascade-contradiction.sh`, migrations 037/065/066/106/112. One stale
premise: `denied_jti.founder_id` RESTRICT — already CASCADE'd by mig 106. Prior-art plan
`2026-06-15-fix-authusers-delete-cascade-dev-drift-plan.md` (#5372) covers the same symptom
with a different root cause (dev drift, not teardown shape) — confirmed this is NOT that class
(named constraint is a main-side RESTRICT FK, no orphan migration involved).

**Property List (Phase 0.6b):** (1) supabase-dev + byok legs green — suite teardown succeeds
for users carrying dependent rows; (2) the blocking Postgres constraint named with live
evidence; (3) the *next* raw-deleteUser suite fails fast in the always-on shard, not in a
nightly; (4) zero production-path change.

**Cut List (Phase 0.6b):** new teardown helper (cut — `tearDownTenantUser` exists,
parity-guarded); new anonymise RPCs / fix migration (cut — all 26 dev RESTRICT FKs covered by
the existing sequence); workflow/leg edits (cut — leg file lists already contain the failing
suites); Postgres-log-diving machinery (cut — direct `DELETE` already named the constraint).

**Institutional learnings applied:** `2026-05-21-dev-supabase-drift-from-unmerged-feature-branch-migrations.md`;
`2026-06-15-per-ref-schema-gate-over-shared-dev-and-worm-cascade-contradiction.md`;
#5372 plan's verified-repro recipe (doppler dev + service-client SQL path).

**Open Code-Review Overlap:** #3221 (`ci: nightly cron for env-gated integration tests`)
mentions `test/byok.integration.test.ts`. Disposition: **acknowledge** — its ask (nightly
wiring) was delivered by #9855 PR 2 (the very legs now failing); this plan edits that file's
teardown, not its gating. Worth a close-look by whoever owns #3221 — no fold-in.

## User-Brand Impact

- **If this lands broken, the user experiences:** an Art-17 erasure / DSAR account deletion
  silently fails with "Database error deleting user" — exactly the symptom these suites exist
  to catch — while the suite reads green because a wrongly-edited helper masked the cascade
  regression. That is the masking failure mode the parity guard and this plan's sentinel exist
  to prevent.
- **If this leaks, the user's data is exposed via:** retained auth/users rows and audit
  artifacts past a confirmed erasure (the rows the RESTRICT FKs are deliberately placed to
  force through the anonymise-first path).
- **Brand-survival threshold:** `single-user incident`
- **Threshold decision (challengeable):** the diff is test-side only, but the helper is a
  direct mirror of the statutory erasure cascade; a defective change could mask a real Art-17
  regression — the same surface and threshold as the #5372 plan. Downgrade to `none` is only
  honest if the helper ends up untouched (it isn't — the sentinel widens).

*CPO sign-off required at plan time before `soleur:work` begins (requires_cpo_signoff). No
Agent tool exists in this harness to spawn `soleur:product:cpo` — recorded as a pending ruling
in `decision-challenges.md`; `soleur:engineering:review:user-impact-reviewer` covers the
review-time seat.*

## Guard Contract

### Guard 1 — teardown-deleteuser-sentinel

**Property.** No test file may invoke `auth.admin.deleteUser` directly outside the two
canonical teardown helpers and an explicit, reviewed allowlist of suites with deliberate
manual FK-reverse teardown.

**Assembly.** Every file under `apps/web-platform/test/*.integration.test.ts` and
`apps/web-platform/test/helpers/*.ts` matched by the call-expression grep `\.admin\.deleteUser\(`
(any receiver — `service`, `client`, …; the literal-call form only, so prose mentions in
comments like `tenant-isolation-teardown.test.ts`'s docblock do not match). Scope excludes
`test/server/**` deliberately — its ~18 latent carriers are tracked by #10096, and including
them now would bake a ~20-name allowlist into the guard. The chokepoints members must flow
through: `test/helpers/tenant-isolation-teardown.ts` (`tearDownTenantUser`) and
`test/helpers/workspace-members-fixtures.ts` (`tearDownSharedWorkspace`). The allowlist (in
the test source, reviewed per-diff) is the *second* chokepoint — both are named here because
the property quantifies over files, not over one code path. Files enumerated at write time
from the grep, not from memory.

**Mutation matrix:**

| # | Mutation | Expected |
|---|----------|----------|
| 1 | Add a new `test/foo.integration.test.ts` calling `service.auth.admin.deleteUser(u.id)` | RED |
| 2 | Rename the call expression in every production call site (e.g. `admin . deleteUser`) so the census matches 0 files | RED (anti-vacuity floor: census ≥ 1) |
| 3 | Add TWO new non-allowlisted files calling raw `deleteUser` — a guard that stops at the first member must still fail | RED |
| 4 | Empty the allowlist | RED (allowlisted suites today legitimately call it) |
| 5 | Add `test/x.test.ts` that imports `tearDownTenantUser` and never calls `admin.deleteUser` | PASS (compliant non-canonical member) |
| 6 | Delete one allowlist entry while its file still calls `admin.deleteUser` | RED |

**Anchor.** The allowlist is part of the guarded system's own diff surface — a PR that adds a
file to the allowlist is the review-visible act; the guard cannot (and is not meant to)
prevent a reviewed allowlist edit. Set-identity assertion, not a count floor, is what binds
membership.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "capture the actual Postgres error behind GoTrue's opaque 500 — `deleteUser` a fixture user on dev and read the dev project's Postgres logs for the aborting constraint/trigger name" [issue #9994] | Phase 1 (done at plan time — `workspace_members_user_id_fkey` named via direct DELETE; log-diving cut as unnecessary) | mapped |
| 2 | "if hypothesis 1 holds the fix is suite-side (route teardown through the anonymise-first path or strip dependent rows first)" [issue #9994] | Phase 2 + Phase 3 | mapped |
| 3 | "if 2/3, it's a migration/dev-state defect" [issue #9994] | Probe refuted hyp 2 (prosrc check); hyp 3 drift filed as #10095 (reconcile path, not this PR's scope) | mapped |
| 4 | "supabase-dev + byok nightly legs red" [issue #9994 title — the leg-green outcome] | Phase 4 fold-in (23502 repairs — same leg can't verify green otherwise) | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| Widen helper sentinel to prefix allowlist | "route teardown through the anonymise-first path" | asked |
| Adopt helper in beta-crm-dsar / byok / cc-dispatcher / conversations-rail | "the suites call `admin.deleteUser` directly on users that carry dependent rows" | asked |
| Adopt helper in dsar-export-cross-tenant | — | inferred — same raw-deleteUser defect in the same red leg; its try/catch only silences the failure and leaks the user (86,916 NULL-owner orgs on dev are this cruft class) |
| `workspace_id` insert repairs in cc-dispatcher + conversations-rail (conversations + messages tables) | — | inferred — the `supabase-dev` leg is the issue's named verification surface; it cannot go green while these 23502 failures stand |
| teardown-deleteuser-sentinel guard test | — | inferred — third recurrence of this exact defect class (#5582, #4791, #9994); a source-grep sentinel is the standing repo mechanism for recurrence (parity-guard precedent) |
| Comments on #9994 / #9995; reference #9993 | — | inferred — evidence handoff: probe results belong on the issue; mu1 will hit the same blockers once #9995's 401 is fixed |

### Split Assessment

- Subsystems touched: 1 — `apps/web-platform` (test files + one helper only)
- Planned files: 7 edit + 1 create | Estimated changed lines: ~300
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

- [ ] AC1 — `doppler run -p soleur -c dev_scheduled -- env SUPABASE_DEV_INTEGRATION=1 npm run test:ci -- <the six-file leg list>` exits 0 locally for the touched supabase-dev-leg suites (beta-crm-dsar, cc-dispatcher, conversations-rail, dsar-export-cross-tenant green; conversation-visibility + dsar-author-redaction untouched).
- [ ] AC2 — `doppler run -p soleur -c dev_scheduled -- env BYOK_INTEGRATION_TEST=1 npm run test:ci -- test/byok.integration.test.ts` exits 0 (afterAll teardown succeeds).
- [ ] AC3 — `tearDownTenantUser` accepts the six enumerated synthetic prefixes and still throws on any non-allowlisted email; `test/helpers/tenant-isolation-teardown.test.ts` covers each new prefix positively and a real-domain email negatively.
- [ ] AC4 — beta-crm-dsar AC10 still asserts all three beta tables empty after the account-delete path (CASCADE semantics preserved — the helper's anonymise RPCs do not delete beta rows; the auth-delete does).
- [ ] AC5 — `test/server/teardown-deleteuser-sentinel.test.ts` exists, runs in the default (`--project unit`) shard, and each `## Guard Contract` matrix row is exercised (at least one RED-driving mutation demonstrated during implementation).
- [ ] AC6 — every `.from("conversations").insert(` AND `.from("messages").insert(` site in `cc-dispatcher-cross-tenant` and `conversations-rail-cross-tenant` supplies `workspace_id` (dev shows both columns NOT NULL); the Phase 4 verification command reports every site covered.
- [ ] AC7 — probe evidence comment posted on #9994; heads-up comment posted on #9995; #9993 referenced and left open; #10094 + #10095 + #10096 exist and are referenced.
- [ ] AC8 — post-merge, the next `scheduled-integration-suites.yml` run shows `supabase-dev` and `byok` legs green (or, if the run precedes merge, the leg-green evidence is the local AC1/AC2 runs + CI on the PR's own scheduled-workflow dispatch if available).

## Observability

The deliverable is test-side, so the observability surface is the CI legs and the sentinel —
not production telemetry.

- `liveness_signal`:
  - `what`: `supabase-dev` and `byok` legs of `scheduled-integration-suites.yml` exit green;
    `test/server/teardown-deleteuser-sentinel.test.ts` runs in the always-on `--project unit`
    shard and passes.
  - `where`: nightly run logs (`gh run list --workflow scheduled-integration-suites.yml`); the
    PR's `test-all.sh` unit shard.
- `error_reporting`:
  - `what`: vitest failure output names the offending file — the sentinel prints the
    un-allowlisted `deleteUser` carrier; leg failures print `Database error deleting user` /
    `23502` in the suite's own stderr.
  - `where`: workflow step output; tracker issue #9993 aggregates recurring reds.
- `failure_modes`:
  - `helper refuses new synthetic email` → teardown throws before deleteUser — loud, correct.
  - `new suite adds raw deleteUser` → sentinel red at unit-shard time — loud, correct.
  - `missing workspace_id on a seeded conversations/messages row` → `23502` in the leg — loud.
  - `sentinel allowlist silently widened` → review-visible diff on the test source (the
    allowlist is a named constant, not data).
- `logs`: `npm run test:ci -- <files> --project unit --reporter=verbose` output in the leg
  step; deleteUser error objects surfaced by suites that check the result.
- `discoverability_test`:
  - `command`: `rg -l -e SYNTHETIC_PREFIXES apps/web-platform/test/helpers/tenant-isolation-teardown.ts`
  - `expected_output`: `tenant-isolation-teardown`
  - `why`: proves the widened prefix allowlist shipped to the helper; a revert or rename makes
    the probe print nothing.

## Test Scenarios

- **unit:** Given a `byok-isolation-<hex>@soleur.test` email, when `tearDownTenantUser` is
  invoked, then it does not throw the sentinel refusal. (helper test)
- **unit:** Given `alice@example.com`, when `tearDownTenantUser` is invoked, then it throws
  `refusing non-synthetic email`. (helper test, existing negatives extended)
- **unit:** Given a scratch test file containing `admin.deleteUser(`, when the sentinel scans,
  then the file is flagged unless allowlisted. (guard matrix rows 1–6)
- **integration:** Given a fresh synthetic user on dev, when `tearDownTenantUser` runs, then
  `auth.admin.deleteUser` succeeds — already demonstrated by the plan-time probe
  (`anonymise_workspace_members` + `anonymise_workspace_member_actions` → `DELETE 1` →
  `deleteUser` error null).
- **integration:** Given the fixed suites, when the supabase-dev leg runs under
  `dev_scheduled`, then `afterAll` completes with zero `deleteUser` errors and zero leaked
  synthetic users for the run.
- **regression:** beta-crm-dsar AC10 — after `crm_contact_upsert` seeds a fresh contact, the
  account-delete path empties `beta_contacts`, `interview_notes`, and
  `beta_contact_stage_transitions` for that user.

## Implementation Phases

1. **Helper widening** — `test/helpers/tenant-isolation-teardown.ts` prefix-allowlist +
   docblock; extend `test/helpers/tenant-isolation-teardown.test.ts`.
2. **Suite adoption** — the five call sites (incl. beta-crm-dsar AC10 + afterAll).
3. **workspace_id fold-in** — both files' `conversations` inserts.
4. **Sentinel guard** — new `test/server/teardown-deleteuser-sentinel.test.ts` + exercise the
   matrix.
5. **Verification** — local `dev_scheduled` runs of the two legs (AC1/AC2); confirm zero
   `Database error deleting user` in output.
6. **Bookkeeping** — comments on #9994/#9995 per Phase 6.

## Files to Edit

- `apps/web-platform/test/helpers/tenant-isolation-teardown.ts`
- `apps/web-platform/test/helpers/tenant-isolation-teardown.test.ts`
- `apps/web-platform/test/beta-crm-dsar.integration.test.ts`
- `apps/web-platform/test/byok.integration.test.ts`
- `apps/web-platform/test/cc-dispatcher-cross-tenant.integration.test.ts`
- `apps/web-platform/test/conversations-rail-cross-tenant.integration.test.ts`
- `apps/web-platform/test/dsar-export-cross-tenant.integration.test.ts`

## Files to Create

- `apps/web-platform/test/server/teardown-deleteuser-sentinel.test.ts`

## Non-Goals

- `mu1.integration.test.ts` teardown — #9995's owner (heads-up comment only).
- slot-trigger `cap_hit` / worktree-lease `acquire` failures — #10094.
- `audit_github_token_use` dev-drift reconcile — #10095.
- `test/server/**` latent deleteUser teardown gap (~18 files, silent variant) — #10096.
- Migrating the four working manual-FK-reverse suites onto the helper — allowed future cleanup;
  the sentinel allowlists them.
- Any production code, migration, or workflow change.

## Domain Review

**Domains relevant:** Engineering, Legal (advisory — Art-17 cascade surface)

### Engineering

**Status:** reviewed (inline — no Agent tool in this harness to spawn `soleur:engineering:cto`)
**Assessment:** CI/test-tooling fix on an established, parity-guarded helper. The one technical
fork (widen-helper vs per-suite manual FK-reverse) is recorded in `decision-challenges.md` as a
pending CTO ruling with the helper-route default — the manual pattern is the proven defect
source.

### Legal / GDPR (advisory)

**Status:** reviewed (inline; `soleur:gdpr-gate` could not be spawned — headless, no Agent tool)
**Assessment:** No new processing activity, no new regulated-data surface, no production-code
change. The Art-17 cascade semantics are exercised, not altered; the change makes the test
mirror *more* faithful to the production path. Critical findings: none. The #10095 drift and
the helper's `set-null` fatality class on dev are recorded for the reconcile issue.

### Product/UX Gate

**Tier:** none
**Decision:** N/A — no user-facing surface; no `components/**/*.tsx`, `app/**/page.tsx`, or
`app/**/layout.tsx` in Files to Create/Edit. Mechanical override does not fire.
**Pencil available:** N/A (no UI surface)

#### Findings

CPO sign-off is carried by the `single-user incident` threshold (Art-17 adjacency), not by any
UI surface.

## Sharp Edges

- `tearDownTenantUser` must keep refusing non-allowlisted emails — it is a write-boundary
  sentinel; a `.*`-shaped widening re-opens the real-account deletion surface.
- Do NOT "fix" this with a migration or an `ON DELETE` downgrade — `RESTRICT` is deliberate
  (mig 107 header: it guarantees the GoTrue cascade never fires a WORM-forbidden child UPDATE).
  The blocker is the suite skipping the canonical cascade, not the FK.
- Do NOT strip dependent rows in the suites by hand-deleting `workspace_members` — the
  membership audit trigger re-creates a `workspace_member_actions` row and re-blocks the
  delete (documented in `conversation-archive-release-slot`'s afterAll). The anonymise RPCs
  set `app.worm_bypass`; that is why the helper exists.
- `withGoTrueRetry` treats "Database error deleting user" as transient — raw-deleteUser call
  sites wrapped in it burned 5 attempts before surfacing. The helper's pre-delete RPC-failure
  collection exists precisely so the real failure is not masked as a retry storm.
- AC10 must keep asserting the beta tables empty *after the delete*, not after the anonymise
  step — conflating the two would weaken the Art-17 regression it guards.
- The sentinel's anti-vacuity floor is load-bearing: a regex that stops matching
  `admin.deleteUser(` must be RED, not green-over-zero-files.
- `mu1.integration.test.ts` uses a different synthetic domain (`@soleur-test.invalid`) — it is
  NOT covered by the helper's allowlist and must stay allowlist-only in the sentinel with a
  `#9995` revisit comment; do not touch its body.

## Context

- Issue: #9994 · tracker: #9993 (referenced, never closed) · sibling: #9995 (mu1, other session)
- Filed this run: #10094 (slot/worktree legs), #10095 (dev drift reconcile),
  #10096 (latent `test/server/**` teardown gap)
- Prior incident of the same symptom class: #5372 → plan
  `2026-06-15-fix-authusers-delete-cascade-dev-drift-plan.md`
- Nightly workflow: `.github/workflows/scheduled-integration-suites.yml` (legs run
  `doppler run -p soleur -c dev_scheduled -- env <GATE>=1 npm run test:ci -- <files>`)

## References

- `apps/web-platform/test/helpers/tenant-isolation-teardown.ts` (the adopted mechanism)
- `apps/web-platform/test/server/teardown-anonymise-parity.test.ts` (the parity guard)
- `apps/web-platform/server/account-delete.ts` (the production cascade the helper mirrors)
- `knowledge-base/project/plans/2026-06-15-fix-authusers-delete-cascade-dev-drift-plan.md`
- `knowledge-base/project/learnings/2026-05-21-dev-supabase-drift-from-unmerged-feature-branch-migrations.md`
