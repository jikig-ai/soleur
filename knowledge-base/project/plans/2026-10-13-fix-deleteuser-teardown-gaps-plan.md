---
title: "fix: close the silent admin.deleteUser teardown gap across test/server/** — route all 15 drain files through tearDownTenantUser"
type: fix
date: 2026-10-13
slug: fix-deleteuser-teardown-gaps
branch: feat-one-shot-10096-deleteuser-teardown-gaps
issue: 10096
closes: 10096
domain: engineering
lane: cross-domain
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
---

# fix: close the silent admin.deleteUser teardown gap across test/server/**

## Overview

#9994 shipped the canonical anonymise-first teardown helper
(`test/helpers/tenant-isolation-teardown.ts::tearDownTenantUser`, 22-RPC
FK-reverse sequence, parity-guarded) plus a recursive source-grep sentinel
(`test/server/teardown-deleteuser-sentinel.test.ts`) whose `KNOWN_LEGACY_CARRIERS`
ratchet already enumerates every remaining offender: **15 files under
`test/server/**` carrying 18 raw `auth.admin.deleteUser` call sites**. Each leaks
its synthetic user (plus trigger-created solo org/workspace rows) on every
`TENANT_INTEGRATION_TEST=1` run because supabase-js returns `{data,error}` —
never throws — and the deterministic RESTRICT 500 lands in an ignored error
field or a `.catch(() => {})` swallow.

The fix is mechanical: migrate all 15 files to `tearDownTenantUser`, add ONE new
synthetic prefix (`workspace-backfill-parity-`) to the helper's allowlist, and
drain `KNOWN_LEGACY_CARRIERS`/`EXPECTED_CALL_COUNTS` to zero in the same commit
so the sentinel itself proves the class closed.

## Premise Validation (measured at plan time, 2026-10-13)

**Issue's "~18 files" → actual: 15 files / 18 call sites.** The sentinel is the
authoritative census — it scans `test/**` recursively (`.ts/.tsx/.mts/.cts`,
symlinks followed, comments stripped via `helpers/strip-comments.ts`) and passed
6/6 on this worktree, proving carriers == enumerated set exactly:

```
$ npx vitest run test/server/teardown-deleteuser-sentinel.test.ts --project unit
  ✓ unit test/server/teardown-deleteuser-sentinel.test.ts (6 tests)
  Test Files  1 passed (1)  Tests  6 passed (6)
```

Carrier inventory (from `KNOWN_LEGACY_CARRIERS` + `EXPECTED_CALL_COUNTS`,
cross-checked against `grep -rn "deleteUser" apps/web-platform/test/`):

| Shape | Files | Calls |
|---|---|---|
| `.catch(() => {})` swallow | attachment-pipeline, cc-dispatcher, conversations-tools, current-repo-url, kb-document-resolver, kb-route-helpers, lookup-conversation-for-path, ws-handler (all `.tenant-isolation.test.ts`) | 8 |
| Unchecked bare `await` (incl. `try/catch` swallows in worm suites) | action-sends-worm (2), email-triage-worm (2), template-authorizations-worm (1), tenant-jwt-deny (2), scope-grants/lifecycle (1), workspace-backfill-trigger-parity (1), workspace-member-revocation (1) | 10 |
| **Drain total** | **15** | **18** |
| Canonical helper (keep) | helpers/tenant-isolation-teardown.ts | 1 |
| Deliberate manual FK-reverse (keep, allowlisted) | concurrency-acquire-slot-workspace-id, conversation-archive-release-slot, workspace-binding-restart-survival, worktree-write-lease, mu1.integration (`#9995`-revisit) | 5 |

**Premise updates vs the issue text:**

1. *"Extend the sentinel scope from `test/*.integration.test.ts + test/helpers/`
   to all of `test/**`"* — **already shipped.** The merged sentinel does a
   recursive census over `test/**` and enforces it via the `KNOWN_LEGACY_CARRIERS`
   ratchet (the drain set IS the scope widening). The remaining work is draining
   the ratchet, not widening the scan.
2. Issue fix shape adopted with one correction: 14/15 drain files already emit
   an allowlisted prefix (13 × `tenant-isolation-` + 1 × `workspace-fixture-`,
   the member-revocation fixture user);
   `workspace-backfill-trigger-parity.test.ts` uses
   `workspace-backfill-parity-[a-f0-9]{16}@soleur.test`, which needs a one-line
   `SYNTHETIC_PREFIXES` addition (the designed mechanism per the helper docblock).
3. **Third leak shape discovered by census, outside the issue's enumeration:**
   `byok-delegation.atomicity`, `byok-kill-switch.atomicity`, and
   `byok-delegations.tenant-isolation.test.ts` create synthetic users and call
   **no** `deleteUser` at all — documented orphan-acceptance under deferred
   sweeper #3934, with comments claiming `deleteUser` "would 23503". That claim
   is stale (pre-helper, pre-mig-065; sibling `audit-byok-use.tenant-isolation.test.ts:129`
   already tears down via `tearDownTenantUser` over the same WORM `audit_byok_use`
   rows). ~6 users/run leaked by *reviewed* decision, not defect. Disposition:
   `operator (scope)` row in decision-challenges.md — recommended default is
   leave + report; changing a documented acceptance is not this PR's call.
4. All 15 drain files are gated `TENANT_INTEGRATION_TEST=1` and run in the
   `tenant-integration.yml` leg (`test/server/` with `--project unit --project
   repo-wide`, workflow line ~689). The PR-time path anchor already includes
   `apps/web-platform/test/helpers/` (line ~135), so this PR's helper edit
   guarantees the leg executes on the PR — real dev-Supabase verification is
   built into CI, no workflow change needed.
5. Nightly legs `byok`/`supabase-dev` (scheduled-integration-suites.yml) were
   #9994's legs, fixed by merged PR #10090 — they do NOT wait on this fix. This
   issue's suites run in the PR/push-to-main leg, not the nightly. #9993 stays
   open (tracker; mu1/slot-trigger/worktree-lease owned by #9995/#10094).

## Does `tearDownTenantUser` cover each suite's shape? (per-file verification)

The helper verifies id↔email binding (`getUserById`, fail-closed), runs the
22-RPC anonymise sequence in production order (all `ON DELETE RESTRICT` FKs —
parity-guarded by `teardown-anonymise-parity.test.ts`), then `deleteUser` under
`withGoTrueRetry`, throwing on any real failure. Per-suite fit:

| File | Current teardown | Migration |
|---|---|---|
| 8 × `.catch` suites | `afterAll` loops users, `assertSynthetic`, `deleteUser().catch(()=>{})` | Swap for `await tearDownTenantUser(service, user)`; keep `assertSynthetic` + any preceding non-user cleanup (attachment-pipeline's storage `.remove()` stays — storage bytes don't cascade, gdpr-gate TS-05) |
| action-sends-worm | `afterAll` loops `[userA,userB]`: try/catch `anonymise_action_sends` + `anonymise_scope_grants` + `deleteUser`; in-test throwaway user (~line 451) try/catch `anonymise_scope_grants`+`deleteUser` | Both RPCs already in the helper sequence — replace each 2–3-op block with one helper call, both sites |
| email-triage-worm | afterAll ~194 runs `anonymise_email_triage_items` + `deleteUser` per user; in-test ~579 is a bare try/catch `deleteUser` | Both helper-covered; swap both sites |
| template-authorizations-worm | 3-RPC try/catch + `deleteUser` (all three RPCs in helper) | Swap |
| tenant-jwt-deny | TWO describes, each `afterAll`: `denied_jti` row delete + bare `deleteUser` | Keep the `denied_jti` delete (founder_id CASCADE since mig 106 — belt-and-suspenders, minimal diff), then `tearDownTenantUser` |
| scope-grants/lifecycle | afterAll bare `deleteUser(userA.id)` relying on the test having run `anonymise_scope_grants` at step 7 — leaks userA if the test fails early | Helper anonymises scope_grants itself — strictly more robust |
| workspace-member-revocation | in-test (~360): `workspace_members.delete().eq("user_id", dId)` + `deleteUser(dId)` in try/catch — the member delete fires the WORM audit trigger, so the raw delete 500s today and is swallowed; dEmail is `workspace-fixture-` (already allowlisted) | Replace both ops with `tearDownTenantUser(service, {id: dId, email: dEmail})`; D's ownership-transfer membership is scrubbed by `anonymise_workspace_members` without re-firing audit |
| workspace-backfill-trigger-parity | 4-step try/catch manual FK-reverse (members → workspaces → organizations → deleteUser), all swallowed — **silently failing today**: the member delete re-fires the audit trigger (`workspace_member_actions` RESTRICT child) which re-blocks `deleteUser` | Replace with helper; requires new prefix `workspace-backfill-parity-` in `SYNTHETIC_PREFIXES`. NULL-owner org/workspace residue accepted per canonical helper semantics (same residue every other suite's teardown leaves — see "residue owner" caveat in Context) |

## Proposed Solution

### Phase 1 — Helper prefix allowlist: +1 entry

- `test/helpers/tenant-isolation-teardown.ts`: append `"workspace-backfill-parity-"`
  to `SYNTHETIC_PREFIXES`; docblock note.
- `test/helpers/tenant-isolation-teardown.test.ts`: append the same literal to
  `EXPECTED_PREFIXES` (the set-equality census goes RED otherwise — deliberate).
  The per-prefix positive test loop picks up the new entry automatically.
- Boundary unchanged: `^(?:…)[a-f0-9]{16}@soleur\.test$` suffix pin stays
  load-bearing (PR #2597 incident class). The suite generator emits exactly
  `workspace-backfill-parity-${randomBytes(8).toString("hex")}@soleur.test`
  (verified in-file, lines 39–42).

### Phase 2 — Migrate the 15 drain files

Uniform edit per file: import
`import { tearDownTenantUser } from "@/test/helpers/tenant-isolation-teardown";`
(the alias convention used by agent-runner/api-messages/audit-byok-use), keep
each suite's own `assertSynthetic` call-site guard, replace the raw deleteUser
call shape with `await tearDownTenantUser(service, user)` — including mid-test
throwaway-user sites (loud, unwrapped: a teardown failure is a leak and SHOULD
red the test — the #9994 fail-loud philosophy; a `try/catch` wrapper would
reintroduce the silent class this issue closes).

Per-file detail table above. Non-user cleanup (storage remove, `denied_jti`
delete, the `workspace_members` row-delete in email-triage-worm's finally)
stays untouched.

Timeout note (CTO amendment): the helper runs ~24 sequential round-trips per
user (`getUserById` + 22 RPCs + `deleteUser`, all under `withGoTrueRetry`).
vitest defaults are `testTimeout: 16_000` / `hookTimeout: 20_000`
(`vitest.config.ts:52-53`) — NOT 30s. In the same commit: set ≥`30_000` on the
two mid-test worm `(h)` tests that gain a helper call (action-sends-worm ~451,
email-triage-worm ~579), and `60_000` on every `afterAll` looping ≥2 users that
lacks an explicit timeout (action-sends-worm, email-triage-worm,
template-authorizations-worm, tenant-jwt-deny ×2);
workspace-member-revocation's 3.2.4 already carries `60_000`.

### Phase 3 — Drain the sentinel ratchet

`test/server/teardown-deleteuser-sentinel.test.ts`:

- Remove all 15 entries from `KNOWN_LEGACY_CARRIERS` and `EXPECTED_CALL_COUNTS`
  (same commit as the migrations — the "no stale entries" and "count-pin" tests
  force this). Keep the now-empty `KNOWN_LEGACY_CARRIERS` set + comment as the
  standing drain mechanism for any future deferral.
- Update docblocks: the `test/server/**` "tracked for drain by #10096" language
  becomes "drained by #10096"; post-drain enumerated set = 6 (1 canonical + 5
  manual allowlist).
- No scope/regex/mechanism changes — the census is already recursive.

### Phase 4 — Verification

- Unit shard (always-on, no env gate):
  `npx vitest run test/server/teardown-deleteuser-sentinel.test.ts test/helpers/tenant-isolation-teardown.test.ts --project unit` → green.
- Adversarial self-check during implementation: temporarily re-add one raw
  `deleteUser(` to a non-enumerated file → sentinel RED; revert.
- CI leg: `tenant-integration.yml` fires on this PR (helpers/ anchored). The
  `tenant-integration` job running `test/server/` green is the real-dev proof
  that migrated teardowns now delete users.
- Optional local corroboration (requires doppler):
  `doppler run -p soleur -c dev_scheduled -- env TENANT_INTEGRATION_TEST=1 npm run test:ci -- test/server/ --project unit --project repo-wide` → exit 0, zero
  `Database error deleting user` in output.

### Phase 5 — Bookkeeping

- Comment on #10096: true census (15/18 vs "~18"), third-shape finding (3 byok
  suites' stale orphan-acceptance comments, ~6 users/run by design → #3934
  territory), sentinel-scope premise update.
- Reference #9993 — never close (tracker).
- `Closes #10096` in the PR body.

## Non-Goals

- The 5 manual-FK-reverse allowlisted suites + `mu1` (#9995's owner) — untouched.
- The 3 deliberate-leak byok suites (#3934 documented acceptance) — reported, not
  migrated; see decision table.
- Extending `tearDownTenantUser` to delete the leftover solo org/workspace rows —
  technical fork, ruled NO by CTO consult 2026-10-13 (see decision table — anonymise-first contract is load-bearing; helper would need a second FK-reverse apparatus).
- A sweeper/janitor for the accumulated 86,916 NULL-owner `organizations` rows —
  that is deferred-scope-out #3934's job.
- Any production code, migration, or workflow change.

## Acceptance Criteria

- [ ] AC1 — Sentinel drained: `KNOWN_LEGACY_CARRIERS` empty; all 6 sentinel tests
  green in the `--project unit` shard; `EXPECTED_CALL_COUNTS` has exactly the 6
  remaining entries (1 canonical + 5 allowlist).
- [ ] AC2 — All 15 drain files route teardown through `tearDownTenantUser`
  (directly or via `tearDownSharedWorkspace`); `grep -c "\.deleteUser("` is 0 in
  each migrated file; the sentinel's carrier census proves it (stale-entry test
  would go RED on any leftover).
- [ ] AC3 — `tearDownTenantUser` accepts `workspace-backfill-parity-` emails and
  still refuses non-allowlisted emails; helper unit-test census + per-prefix
  positives green.
- [ ] AC4 — The `tenant-integration` leg runs on this PR and is green (or the
  optional local `dev_scheduled` run exits 0): migrated teardowns actually delete
  users on dev — zero `Database error deleting user`, zero new leaked users for
  the run.
- [ ] AC5 — Zero production-code, migration, or workflow changes
  (`git diff origin/main -- apps/web-platform/server apps/web-platform/supabase .github` empty).
- [ ] AC6 — #10096 comment posted with census + third-shape finding; #9993
  referenced and left open; PR body carries `Closes #10096`.

## Observability

- `liveness_signal`: `tenant-integration` job green on the PR and on the
  post-merge push-to-main run; sentinel stays green in every `ci.yml` unit shard.
- `error_reporting`: a teardown regression now throws inside the suite (vitest
  reds the test/describe, naming the failing RPC and fatality class) instead of
  landing in an ignored `{error}` field; a NEW raw-deleteUser file reds the
  sentinel immediately, not a nightly.
- `failure_modes`: `anonymise RPC fatal` → helper throws before deleteUser
  (loud); `helper refuses email` → throw names the unregistered prefix (loud);
  `new carrier file` → sentinel offender test names the file (loud).
- `discoverability_test`:
  - `command`: `rg -l 'KNOWN_LEGACY_CARRIERS' apps/web-platform/test/server/teardown-deleteuser-sentinel.test.ts && rg -c 'tearDownTenantUser' apps/web-platform/test/server/`
  - `expected_output`: the sentinel file listed; count ≥ 15 across `test/server/`
  - `why`: proves the drain mechanism shipped and the suites adopted the helper.

## Test Scenarios

- **unit:** Given a `workspace-backfill-parity-<hex>@soleur.test` email, when
  `tearDownTenantUser` is invoked, then no sentinel refusal is thrown. (helper
  test — auto-covered by the per-prefix loop once EXPECTED_PREFIXES is updated)
- **unit:** Given the 15 formerly-listed files post-migration, when the sentinel
  census runs, then they appear in NEITHER carriers NOR enumerated sets, and the
  stale-entry test stays green. (guard matrix — "no stale entries" row)
- **unit (mutation):** Given a scratch file under `test/server/` calling
  `service.auth.admin.deleteUser(x)`, when the sentinel runs, then the offender
  test fails naming the file. (exercise during implementation, then revert)
- **integration:** Given `workspace-backfill-trigger-parity` creates its user,
  when `afterAll` runs the helper, then the auth user is deleted despite the
  WORM-audit row written by the earlier member-row delete — where the raw
  `deleteUser` silently 500'd before.
- **integration:** Given a suite whose test body fails early (scope-grants
  lifecycle before step 7), when `afterAll` runs, then the user is still deleted
  — the helper anonymises `scope_grants` itself rather than depending on test
  progress.
- **regression:** `workspace-member-revocation` test 3.2.4 still asserts the
  ownership-transfer audit row BEFORE teardown of D — order preserved (helper
  call sits after assertions).

## Risk & Rollback

- **Risk: a previously-silent teardown failure now reds a suite.** Intended —
  fail-loud is the fix. A genuinely uncleanable user shape would surface as a
  new red; the parity guard bounds this (every dev RESTRICT FK maps to a helper
  RPC — probed live for #9994: 26 RESTRICT + 2 SET NULL + 12 CASCADE).
- **Risk: `workspace-member-revocation` mid-test helper call deletes D while
  later tests still use fixtureX.** Mitigated: D is added and asserted within
  test 3.2.4 only; `tearDownSharedWorkspace(fixtureX/Y)` in `afterAll` iterates
  `fixture.members` (D is not a member entry) — unaffected.
- **Risk: afterAll timeouts** — mitigated by the 30s→60s bump guidance.
- **Risk: helper prefix widening** — bounded by the unchanged
  `[a-f0-9]{16}@soleur.test` suffix pin and the sentinel's claimed-prefix test.
- **Rollback:** `git revert` the single PR; the sentinel's ratchet re-lists any
  re-introduced carrier loudly. No DB state to roll back.

## Sharp Edges

- Do NOT wrap the migrated helper calls in `try/catch` or `.catch(() => {})` —
  that re-creates the silent-leak class being fixed. Mid-test "best-effort"
  sites go loud on purpose.
- Do NOT hand-delete `workspace_members` rows as a substitute for the helper —
  the membership audit trigger writes a `workspace_member_actions` RESTRICT row
  that re-blocks `deleteUser` (workspace-binding-restart-survival documents this;
  workspace-backfill-trigger-parity's manual teardown is silently failing today
  for exactly this reason).
- `tearDownTenantUser` anonymises; it does not delete the user's solo
  org/workspace rows (they become NULL-owner residue — same residue production
  erasure leaves, `account-delete.ts:830-836`). CTO amendment on the citation:
  #3934 owns only the `audit_byok_use` sweeper RPC — NOT the NULL-owner
  `organizations`/`workspaces` residue class, and its `denied_jti`-RESTRICT
  premise is stale post-mig-106 (now CASCADE). The 86,916-row cruft class has
  no tracked owner today; the #10096 evidence comment says so explicitly and
  asks to scope-widen #3934 (or file a dedicated janitor issue) rather than
  citing it as already owning the residue.
- The sentinel counts ALL `CALL_RES` shapes per file — adding any new
  `deleteUser(`-shaped call (even in a string literal) inside an enumerated file
  trips the count pin.

## Context

- Issue: #10096 · umbrella tracker: #9993 (never close) · related merged:
  #9994→PR #10090 (helper + sentinel), #10095→PR #10226 (dev FK drift reconcile)
  · sibling in flight: #10094 (other red legs, verify-and-close)
- #9994 plan (the loud variant + helper machinery):
  `knowledge-base/project/plans/archive/20261013-062704-2026-10-12-fix-integration-deleteuser-500s-teardown-plan.md`
- Residue ownership caveat (CTO): #3934 is scoped to the `audit_byok_use` WORM
  sweeper, not the NULL-owner `organizations`/`workspaces` residue this issue
  measured (86,916 rows) — the evidence comment scope-widens or re-files it
  explicitly; it is not cited here as already owning the class.

## Domain Review

**Domains relevant:** Engineering, Legal (advisory — Art-17 cascade surface)

### Engineering

Inline review (no Agent tool in this harness): mechanical adoption of an
established, parity-guarded helper; the widen-vs-manual fork was already ruled
in #9994 (helper route). Forks recorded in `decision-challenges.md`.

### Legal / GDPR (advisory)

No new processing activity, no production-code change; the change makes test
teardown *more* faithful to the Art-17 cascade (anonymise-first, fail-loud).

### Product/UX Gate

**Tier:** none — no UI surface. CPO sign-off carried by the
`single-user incident` threshold (helper is a direct mirror of the statutory
erasure cascade — same basis as the #9994 plan); the CPO sign-off row is ruled
in `decision-challenges.md` (operator-scope, recommended authorized action).

## Implementation Phases

1. Helper prefix add + helper unit-test `EXPECTED_PREFIXES` update.
2. Migrate 15 drain files (18 call sites) to `tearDownTenantUser`.
3. Drain sentinel `KNOWN_LEGACY_CARRIERS`/`EXPECTED_CALL_COUNTS`; docblock updates.
4. Verification: unit shard green + mutation self-check + CI leg (or local
   dev_scheduled run).
5. Bookkeeping: #10096 evidence comment; PR body `Closes #10096`.

## Files to Edit

- `apps/web-platform/test/helpers/tenant-isolation-teardown.ts`
- `apps/web-platform/test/helpers/tenant-isolation-teardown.test.ts`
- `apps/web-platform/test/server/teardown-deleteuser-sentinel.test.ts`
- `apps/web-platform/test/server/action-sends-worm.test.ts`
- `apps/web-platform/test/server/attachment-pipeline.tenant-isolation.test.ts`
- `apps/web-platform/test/server/cc-dispatcher.tenant-isolation.test.ts`
- `apps/web-platform/test/server/conversations-tools.tenant-isolation.test.ts`
- `apps/web-platform/test/server/current-repo-url.tenant-isolation.test.ts`
- `apps/web-platform/test/server/email-triage-worm.test.ts`
- `apps/web-platform/test/server/kb-document-resolver.tenant-isolation.test.ts`
- `apps/web-platform/test/server/kb-route-helpers.tenant-isolation.test.ts`
- `apps/web-platform/test/server/lookup-conversation-for-path.tenant-isolation.test.ts`
- `apps/web-platform/test/server/scope-grants/lifecycle.test.ts`
- `apps/web-platform/test/server/template-authorizations-worm.test.ts`
- `apps/web-platform/test/server/tenant-jwt-deny.tenant-isolation.test.ts`
- `apps/web-platform/test/server/workspace-backfill-trigger-parity.test.ts`
- `apps/web-platform/test/server/workspace-member-revocation.tenant-isolation.test.ts`
- `apps/web-platform/test/server/ws-handler.tenant-isolation.test.ts`

## Files to Create

- None.
