---
title: "chore(ci): pre-merge gate for verify/068 jti_deny_policies_count drift (recurred twice)"
date: 2026-07-09
type: chore
issue: 6273
branch: feat-one-shot-6273-jti-deny-count-pr-gate
lane: single-domain
brand_survival_threshold: none
requires_cpo_signoff: false
status: implemented
---

> **Deepen-plan review integration (2026-07-09).** Three review agents
> (architecture / test-design / spec-flow) hardened the SET_M spec before
> implementation. Deltas folded into the shipped test
> (`068-jti-deny-count-sync.test.ts`):
> - **Content-based producer detection** (not migration-number-keyed): migration
>   files share numeric prefixes (`068_attachments_*` AND `068_jti_deny_*`), so
>   the ARRAY/loop producer is identified by the `tenant_tables text[] := ARRAY[`
>   block, not by number 068.
> - **Producer-completeness guard**: fail loud on any dynamic `format(... CREATE
>   POLICY ..._jti_not_denied)` loop that is NOT paired with the `tenant_tables`
>   ARRAY (a new loop producer would be invisible to the static parser →
>   false-green → deploy freeze).
> - **`AS RESTRICTIVE`-anchored** inline-create regex (mirror the sentinel's
>   `permissive='RESTRICTIVE'` predicate; name-only would admit a PERMISSIVE
>   policy → false-green).
> - **Whole-file, comment-stripped, unified `[a-z0-9_]+` case-insensitive** parse
>   (covers multi-line CREATE, `--` comments, digit-bearing table names in one).
> - **Fold in filename order** (not global set-minus) — handles
>   create→drop→recreate across separate migrations.
> - **`DROP POLICY (IF EXISTS)?`** — recognise drops without `IF EXISTS`.
> - **No hardcoded totals committed** (21/6/27 demoted to Phase-0 preconditions);
>   only self-updating relational asserts + fail-loud `size>0` ship.
> - **Manual scratch-copy AC replaced by committed negative fixtures** (add /
>   swap / down.sql / ARRAY-throw / comment-strip / dynamic-producer /
>   cross-file-recreate / permissive-not-counted) exercising the SAME pure
>   parsers on in-test string constants.

# chore(ci): pre-merge gate for verify/068 `jti_deny_policies_count` drift 🛡️

## Overview

The `verify/068_jti_deny_rls_predicate_and_revoke_rpc.sql` sentinel hard-codes
the number of RESTRICTIVE `*_jti_not_denied` RLS policies (currently **27**). It
runs **only** in the post-merge, deploy-time `verify-migrations` job (against a
real Postgres with every migration applied) — **never in PR CI**. So a migration
that adds a new `*_jti_not_denied` policy without updating `verify/068` passes
every PR check, merges, and then **fails the release `verify-migrations` job →
`deploy` is skipped** (a deploy freeze).

This has recurred **twice**: mig 126 (beta-CRM, 3 policies, 23→26, hotfix #6229)
and mig 127 (beta_contact_access_log, 26→27, hotfix #6270). Prose prevention (a
grep rule) + a postmortem + two learnings already exist and did **not** prevent
the second recurrence. Prose is insufficient; a **mechanical PR-time gate** is
required.

This plan adds a single offline vitest source-parsing test that runs in the
normal PR CI web-platform suite and fails the moment a migration adds (or drops)
a `*_jti_not_denied` policy without keeping `verify/068` in sync — moving
detection from deploy-time (post-merge, deploy-blocking) to PR-time (pre-merge,
fast feedback).

**No runtime, schema, DDL, or migration change.** The deploy-time `verify/068`
sentinel remains the real-DB ground truth; this test is a fast pre-merge mirror
of the same invariant, parseable entirely from committed text files.

## Research Reconciliation — Spec (issue #6273) vs. Codebase

The issue proposes a sound goal but its **step-1 counting mechanism is naive and
undercounts**. The plan corrects it.

| Issue claim / proposed mechanism | Codebase reality | Plan response |
| --- | --- | --- |
| "Count `CREATE POLICY <name>_jti_not_denied ... AS RESTRICTIVE` statements across migrations" as the source of truth. | Only **6** such literal statements exist (migs 076, 077, 126×3, 127). The **21 base** policies from mig 068 are created inside a `DO $$ ... FOREACH t IN ARRAY tenant_tables LOOP EXECUTE format('CREATE POLICY %I_jti_not_denied ...') END LOOP $$` block over a hard-coded `tenant_tables text[] := ARRAY[…]` (21 entries). A literal-`CREATE POLICY` grep returns 6, not 27. | The migration counter MUST sum **two producers**: (a) parse mig 068's `tenant_tables` ARRAY literal (21 table names); (b) regex every inline `CREATE POLICY (\w+)_jti_not_denied` across all non-`.down` migrations (6). Total 27. |
| Count-equality (`migration-count == sentinel-N == per-table-assertion-count`). | Two learnings (2026-07-08) prove a **count-only** guard misses the identity case: "one dropped + one unrelated added → count still passes, set is wrong." | Assert **set equality** of table names (strictly stronger than count), plus `count(*) = N` literal ↔ `_N` check-name-suffix consistency. Names give a precise failure message. |
| (unstated) | Migs 126/127 contain `DROP POLICY IF EXISTS <t>_jti_not_denied` **idempotency pairs** immediately followed by the matching `CREATE POLICY`. There are currently **zero** unpaired (net) drops. `.down.sql` files also drop policies. | Counter must (i) exclude `*.down.sql`, and (ii) treat a `DROP POLICY IF EXISTS <t>_jti_not_denied` as a net-drop only when NOT paired with a `CREATE POLICY <t>_jti_not_denied` in the same up-migration. |
| (unstated) | `verify/068` header prose contains BOTH "Exactly **27** RESTRICTIVE" (total) and "**21** base" (sub-count). | A prose-sync assertion (optional, low-value) must anchor on `Exactly (\d+) RESTRICTIVE`, not any bare number. |

**Premise Validation (Phase 0.6):** #6273 is OPEN, not closed by any merged PR —
plan is valid. Referenced fixes #6229/#6270 are merged hotfixes; #6233 (count-only
hotfix) is CLOSED; #6172 ("Ref #6172") is an unrelated OPEN feature, not a blocker.
No ADR governs the verify-sentinel/count-drift mechanism (grepped
`decisions/` — only ADR-076/ADR-087, unrelated), so this plan neither reverses nor
conflicts with an ADR, and adding a test is not itself an architectural decision.
Labels `type/chore` and `domain/engineering` exist.

## User-Brand Impact

**If this lands broken, the user experiences:** nothing directly — this is a
dev-tooling CI guard, not a user-facing surface. A **false-positive** (test fails
on a correct DB) would block unrelated PRs from merging until fixed; a
**false-negative** (test passes while drift exists) simply lets the pre-existing
deploy-freeze failure mode recur exactly as today (no regression). The downstream
user-facing value is *fewer deploy freezes*, so shipping RLS/security fixes and
features reaches production without a post-merge stall.

**If this leaks, the user's data is exposed via:** N/A — the test reads
committed migration/verify SQL **text** offline; it touches no user data, no
secrets, no live DB, and adds no processing activity.

**Brand-survival threshold:** none — reason: pure PR-CI text-parsing guard; no
user-facing surface, no regulated-data surface modified, no new processing. The
diff adds one test file (and optionally a docs/prose sync); it does not touch
schemas, auth flows, or API routes.

## The invariant to enforce (all parseable offline at PR time)

Let:

- **SET_M** = set of tenant-table names carrying a `*_jti_not_denied` RESTRICTIVE
  policy across up-migrations = { mig-068 `tenant_tables` ARRAY entries } ∪
  { inline `CREATE POLICY (\w+)_jti_not_denied` across all non-`.down`
  migrations } − { net unpaired `DROP POLICY IF EXISTS (\w+)_jti_not_denied` }.
  Currently 27.
- **SET_V** = set of table names asserted by `<table>_jti_not_denied_policy_present`
  rows in `verify/068`. Currently 27.
- **N** = the integer in `verify/068`'s `jti_deny_policies_count_N` sentinel,
  read from BOTH the `check_name` suffix (`_27`) AND the `count(*) = 27` literal.

Assertions:

1. `SET_M === SET_V` (set equality by table name — the primary, identity-preserving check).
2. `|SET_M| === N` and `|SET_V| === N`.
3. The sentinel's `_N` check-name suffix === its `count(*) = N` literal (self-consistency).
4. (Optional, low-value) header prose `Exactly (\d+) RESTRICTIVE` === N.

Set equality (1) is what the two 2026-07-08 learnings demand: it catches the
"count coincidentally matches but a table is wrong/missing" identity failure that
a pure count check (2 alone) cannot.

## Files to Create

- `apps/web-platform/test/supabase-migrations/068-jti-deny-count-sync.test.ts`
  — the offline source-parsing vitest test. **Primary template:**
  `apps/web-platform/test/supabase-migrations/byok-rpc-body-markers.test.ts`
  (already does `readdirSync(MIGRATIONS_DIR).filter(f => f.endsWith(".sql") &&
  !f.endsWith(".down.sql"))` and an exact-**set** assertion
  `expect(Object.keys(MARKER_MAP).sort()).toEqual([...])` + a fail-loud negative
  test — a direct analog of our set invariant). **Path-resolution:** a file at
  `test/supabase-migrations/` is two levels deep, so use
  `path.join(__dirname, "../../supabase/migrations")` and
  `path.join(__dirname, "../../supabase/verify")` (verified against sibling
  `117-…test.ts:18-20`). Vitest **node** project glob `test/**/*.test.ts`
  (`apps/web-platform/vitest.config.ts:44`, `environment: "node"`) collects it —
  name it `.test.ts` (NOT `.tsx`) so `node:fs`/`readdirSync` run in the node env.

## Files to Edit

- (none required for the mechanism). **No** edit to `verify/068`, migrations,
  `ci.yml`, or `web-platform-release.yml` is needed. The new test file runs in the
  existing `test-webplat` job of `.github/workflows/ci.yml` (2-way shard matrix,
  `pull_request:` with **no path filter → every PR**, via `scripts/test-all.sh
  webplat` → `cd apps/web-platform && npm run test:ci`), and is a **required**
  merge gate through the synthetic `test` aggregator context (`ci.yml:578-605`).
  Zero workflow YAML changes.

## Implementation Phases

### Phase 0 — Preconditions (grep against installed state; RED-before-GREEN)

0.1 Confirm the current production counts so the test's first run is GREEN on
`main` state:
- Mig-068 ARRAY entries: `awk '/tenant_tables text\[\] := ARRAY\[/{f=1} f{print} /\];/{if(f)exit}' apps/web-platform/supabase/migrations/068_jti_deny_rls_predicate_and_revoke_rpc.sql | grep -cE "^\s*'[a-z_]+',?$"` → **21**.
- Inline creates: `for f in apps/web-platform/supabase/migrations/*.sql; do case "$f" in *.down.sql) continue;; esac; grep -oE "CREATE POLICY [a-z_]+_jti_not_denied" "$f"; done | wc -l` → **6**.
- Per-table assertions in verify/068: `grep -cE "_jti_not_denied_policy_present" apps/web-platform/supabase/verify/068_jti_deny_rls_predicate_and_revoke_rpc.sql` → **27**.
- Sentinel N: `grep -oE "jti_deny_policies_count_[0-9]+|count\(\*\) = [0-9]+" verify/068…` → **27** in both forms.
- So SET_M (21+6−0) = 27 = SET_V = N. First test run must pass on current `main`.

0.2 Confirm the vitest runner form for this package (repo has NO root
`workspaces` field; runner is vitest, NOT bun test):
`cd apps/web-platform && ./node_modules/.bin/vitest run test/supabase-migrations/068-jti-deny-count-sync.test.ts`.

### Phase 1 — Write the failing test first (RED), then implement to GREEN

1.1 Author the test with these `describe`/`it` blocks:
- **parse mig-068 ARRAY** → 21 names; assert count>0 and array-terminator found
  (fail loudly if the `ARRAY[ … ];` block cannot be located — guards against a
  future refactor silently zeroing SET_M).
- **parse inline creates** across non-`.down` migrations → collect
  `CREATE POLICY (\w+)_jti_not_denied`.
- **net-drop handling** → collect `DROP POLICY IF EXISTS (\w+)_jti_not_denied`
  per up-migration; subtract from SET_M only those NOT paired with a same-file
  `CREATE POLICY \1_jti_not_denied`.
- **parse verify/068** → SET_V from `(\w+)_jti_not_denied_policy_present`; N from
  `jti_deny_policies_count_(\d+)` AND `count\(\*\) = (\d+)`.
- **assert** set equality `SET_M === SET_V` (diff both directions, error names the
  offending table(s)); `|SET_M| === N === |SET_V|`; suffix-N === literal-N;
  optional prose `Exactly (\d+) RESTRICTIVE` === N.
- **negative/self-test guards** (SpecFlow edge cases, below): inline fixtures that
  prove each regex fires — e.g. a synthetic string with a `CREATE POLICY
  foo_jti_not_denied` is counted, a paired `DROP…IF EXISTS`+`CREATE` nets zero, an
  unpaired `DROP` nets −1. These run on in-test string constants, NOT by mutating
  real files.

1.2 Run `vitest run` on the file; iterate to GREEN against current `main` state.
1.3 Run the full package suite (`cd apps/web-platform && ./node_modules/.bin/vitest run`) to confirm no collateral breakage, and `./node_modules/.bin/tsc --noEmit`.

### Phase 2 — Documentation sync (retire the now-mechanical prose rule)

2.1 The postmortem `knowledge-base/engineering/operations/post-mortems/verify-068-jti-deny-count-sentinel-drift-postmortem.md` and the two 2026-07-08 learnings should be updated with a one-line "Now mechanically gated by
`068-jti-deny-count-sync.test.ts` (#6273)" note so future readers see the prose
rule was superseded by a gate. (Prose edit only; optional but recommended.)

## Edge Cases (SpecFlow-style enumeration — CI logic is where silent drops hide)

- **Loop-generated policies (mig 068):** the 21 base policies are NOT literal
  `CREATE POLICY` — counted via the ARRAY literal parse. If that parse fails to
  locate the block, the test MUST fail loudly (not silently return 0), else a
  future 068 refactor zeroes SET_M and the guard darks.
- **Idempotency DROP pairs (migs 126/127):** `DROP POLICY IF EXISTS … ; CREATE
  POLICY …` must net to +1, not 0. Pair by table name within the same file.
- **`.down.sql` exclusion:** down-migrations drop policies; they must never
  contribute to SET_M.
- **Set vs count:** a hypothetical future migration that drops table A's policy
  and adds table B's keeps `count` at 27 but changes the set — assertion (1)
  catches it; (2) alone would not.
- **Sentinel dual-number:** `jti_deny_policies_count_27` suffix AND `count(*) = 27`
  literal must both be read and must agree (a hotfix that bumps one but not the
  other is caught by assertion 3).
- **Header prose dual-number:** "Exactly 27" (total) vs "21 base" (sub-count) —
  anchor the optional prose check on `Exactly (\d+) RESTRICTIVE`.
- **Robustness to N growth:** `readdirSync` the migration dir so migration 128+ is
  auto-included; never hardcode the migration file list.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `apps/web-platform/test/supabase-migrations/068-jti-deny-count-sync.test.ts`
  exists and passes: `cd apps/web-platform && ./node_modules/.bin/vitest run test/supabase-migrations/068-jti-deny-count-sync.test.ts` exits 0 against current `main` state (SET_M = SET_V = N = 27).
- [ ] The test derives SET_M from BOTH producers (mig-068 ARRAY parse yields 21;
  inline-create regex yields 6) — verified by a self-test assertion that
  `|SET_M| === 27` and by an in-test negative fixture proving each regex fires.
- [ ] The test asserts **set equality** `SET_M === SET_V` (not merely count
  equality), and the failure message names the differing table(s).
- [ ] The test reads N from both the `_N` check-name suffix and the `count(*) = N`
  literal and asserts they agree.
- [ ] A deliberate local mutation (temporarily add a fake
  `CREATE POLICY zzz_jti_not_denied ON public.zzz … AS RESTRICTIVE` to a scratch
  copy, OR add an entry to the ARRAY, without touching verify/068) makes the test
  FAIL — proving it catches the exact recurrence class. (Demonstrated in the
  session log / PR description; reverted before commit.)
- [ ] `cd apps/web-platform && ./node_modules/.bin/vitest run` (full suite) and
  `./node_modules/.bin/tsc --noEmit` are green.
- [ ] PR body uses `Closes #6273`.

### Post-merge (operator)

- [ ] None. The test runs automatically in the existing PR web-platform vitest
  job; no infra, secret, or workflow provisioning. `Automation: N/A` — no
  operator step exists.

## Observability

This feature IS an observability guard; its signals are CI-native (no SSH, no
runtime surface):

```yaml
liveness_signal:
  what: ci.yml test-webplat job runs 068-jti-deny-count-sync.test.ts on every PR (no path filter)
  cadence: per-PR (every PR; and always on migration/verify changes)
  alert_target: GitHub PR check status via required `test` aggregator context (ci.yml:578-605) — red = drift or false-positive
  configured_in: .github/workflows/ci.yml test-webplat job (scripts/test-all.sh webplat) + apps/web-platform/vitest.config.ts:44 glob
error_reporting:
  destination: vitest assertion output in the PR check log (fail-loud by design — a failing assertion is the entire point)
  fail_loud: true
failure_modes:
  - mode: migration adds a *_jti_not_denied policy, verify/068 not updated
    detection: SET_M > SET_V → set-equality assertion fails, names the missing table
    alert_route: PR check red (pre-merge)
  - mode: sentinel N bumped but per-table assertion not added (or vice versa)
    detection: |SET_V| !== N OR suffix-N !== literal-N
    alert_route: PR check red (pre-merge)
  - mode: mig-068 ARRAY block refactored so parse returns 0 (guard darks)
    detection: explicit "ARRAY block located / count>0" assertion fails loudly
    alert_route: PR check red (pre-merge)
logs:
  where: GitHub Actions PR run logs (vitest reporter)
  retention: standard GitHub Actions retention
discoverability_test:
  command: cd apps/web-platform && ./node_modules/.bin/vitest run test/supabase-migrations/068-jti-deny-count-sync.test.ts
  expected_output: "Test Files 1 passed" (exit 0) on current main; non-zero with a named-table diff when drift is introduced
```

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — a PR-CI dev-tooling guard (test surface
only). No Product/UX surface (no file under `components/**`, `app/**/page.tsx`,
etc.); mechanical UI-surface override does not fire. Engineering-domain concerns
are self-covered by the plan.

## Architecture Decision (ADR/C4)

Skipped — no architectural decision. This adds a test guard; it moves no
tenancy/ownership boundary, introduces no substrate/integration pattern, changes
no resolver/dispatch/trust boundary, and neither reverses nor extends an ADR
(grepped `decisions/` — no verify-sentinel/count-drift ADR exists). A competent
engineer reading the existing ADRs + C4 would not be misled by this change.
C4 external-actor/system/access-relationship check: the change adds no external
actor, no external system, no container/data-store, and no access relationship —
it parses committed text in CI.

## Infrastructure (IaC)

Skipped — no new infrastructure. No server, service, secret, vendor, DNS, cert,
firewall rule, or persistent runtime process. The test runs inside the existing
CI job; the deploy-time `verify-migrations` job is unchanged.

## GDPR / Compliance

Skipped — no regulated-data surface touched. The plan adds a `.test.ts` that
reads DDL **text** offline; it creates/modifies no schema, migration, auth flow,
or API route, adds no LLM/external processing, declares threshold `none`, adds no
cron reading learnings, and adds no new distribution surface. None of the
canonical-regex or (a)–(d) expansion triggers fire.

## Alternative Approaches Considered

| Approach | Verdict |
| --- | --- |
| **Bash `test-scripts` gate** instead of vitest. | Rejected — a bash SQL-lint precedent exists (`apps/web-platform/scripts/lint-migration-fk-preconditions.sh`, wired into `tenant-integration.yml`), but it fills the `--from-pr-diff` niche and needs a workflow step. The dominant on-point precedent is vitest (56 tests in `test/supabase-migrations/`, incl. the set-assertion `byok-rpc-body-markers.test.ts`), which auto-gates via the required `test` context with zero YAML. Vitest chosen. |
| **Count-only equality** (issue's literal proposal). | Rejected — the 2026-07-08 learnings prove count-only misses the identity case; set equality is the same cost and strictly stronger. |
| **Grep only literal `CREATE POLICY`** as source of truth (issue's step 1). | Rejected — undercounts to 6 (misses the mig-068 ARRAY-loop 21). |
| **Add the check to the deploy-time `verify-migrations` job earlier / to PR CI as SQL against a spun-up Postgres.** | Rejected — heavier (needs a DB in PR CI), slower, and the offline text invariant is sufficient to catch the recurrence class. The real-DB sentinel already exists as ground truth; this is a fast pre-merge mirror. |

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only
  `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan`
  Phase 4.6. This plan's section is filled with threshold `none` + reason.
- The mig-068 ARRAY parse is the fragile half of SET_M. Its "block located,
  count>0" self-assertion is load-bearing: without it, a future 068 refactor that
  moves the table list would silently zero SET_M and the guard would dark while
  reading green.
- Do not count `.down.sql` files, and pair idempotency `DROP…IF EXISTS`+`CREATE`
  within the same up-migration — otherwise migs 126/127 mis-net.
