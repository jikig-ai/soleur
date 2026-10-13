# 🐛 fix: populate workspace_id on interactive `messages` INSERTs (RLS-blocked chat outage)

## Enhancement Summary

**Deepened on:** 2026-06-02
**Sections enhanced:** Fix strategy, Test scenarios, Verification, Domain Review
**Research applied:** Context7 (`/supabase/supabase` RLS INSERT WITH CHECK), 5 institutional learnings, review-agent lenses (data-integrity-guardian, security-sentinel, silent-failure-hunter, pr-test-analyzer) applied inline (no `Task` subagent tool available in this environment).

### Key Improvements
1. **Test infra already exists — no new capture seam needed.** The cc-dispatcher harness (`test/helpers/cc-dispatcher-harness.ts:116-118,143-145`) already wires `tenant.from("messages").insert` to a spy `opts.mockMessagesInsert`, and `cc-dispatcher.test.ts:1085-1091` already reads `insertMock.mock.calls` and filters by role. T1-T4 reduce to adding a `workspace_id` assertion on the already-captured payload. This shrinks AC5 effort substantially.
2. **Context7 confirms the fix shape.** supabase-js v2 (`^2.49.0`, installed) returns `{ data, error }` (no throw) and an INSERT WITH CHECK policy referencing `workspace_id` requires the column be populated with a value satisfying the predicate — the Clerk `organization_id` example is the direct analog. The fix's "derive from parent conversation" approach is the documented-correct way to satisfy a membership-keyed WITH CHECK.
3. **`saveMessage` reuses the SAME conversation read it can piggyback.** `sendUserMessage` already SELECTs the conversation (add `workspace_id` to the existing select — zero extra RTT); `saveMessage` and cc-dispatcher need exactly one added SELECT each, on the already-minted tenant client.
4. **Symptom-chain precedent documented.** Learning `2026-03-28-unapplied-migration-command-center-chat-failure.md` is the canonical "An unexpected error occurred" → schema/RLS-mismatch debugging chain and establishes the merge-time prod-DB verification rule this plan's §Verification implements.

### New Considerations Discovered
- **`{ error }` destructure is already correct at all sites** (learning `2026-03-20-supabase-silent-error-return-values.md`) — the fix must preserve it; do not switch to `throwOnError()`.
- **Negative-control is mandatory for the grep-sweep test** (T5) so it can't vacuously pass — assert a synthetic insert WITHOUT `workspace_id` fails the matcher (silent-failure-hunter lens).
- **`buildRow` is a pure function returning `Record<string, unknown>`** — adding `workspace_id` is type-safe but the column is not statically checked against the DB; the grep-sweep test is the only mechanical guard (type-widening-cascade lens).

---

**Date:** 2026-06-02
**Type:** bug / production outage
**Branch:** `feat-one-shot-messages-workspace-id-rls-insert`
**Severity:** brand-survival — single-user incident; core chat unusable for ~3 weeks (last real interactive message saved 2026-05-11)
**Class:** cc-dispatcher persistence-asymmetry + write-boundary-sentinel sweep

---

## Summary

Migration `059_workspace_keyed_rls_sweep.sql` made `messages.workspace_id` `NOT NULL`
and replaced the legacy FK-join INSERT policy with:

```sql
CREATE POLICY messages_workspace_member_insert ON public.messages
  FOR INSERT TO authenticated
  WITH CHECK (public.is_workspace_member(workspace_id, auth.uid()));
```

The interactive message-INSERT sites were never updated to populate `workspace_id`.
Every interactive INSERT omits the column → the row's `workspace_id` is `NULL` →
`is_workspace_member(NULL, auth.uid())` returns `false` → Postgres rejects with
`new row violates row-level security policy for table messages` → the dispatch
throws `Failed to save user message` → `sanitizeErrorForClient` returns the generic
`"An unexpected error occurred. Please try again."` bubble the user sees.

Service-role cron inserts (`insert-draft-card.ts`) bypass RLS, so background writes
kept working — masking the outage for ~3 weeks.

**Fix:** set `workspace_id` on every interactive `messages` INSERT, derived from the
parent conversation's `workspace_id` (the conversation is already
fetched/ownership-verified in each path). Sweep ALL interactive insert sites so none
is missed, update the stale "RLS enforces FK-join to conversations.user_id" comments
(no longer true post-059), and add a source-grep guard test so a future insert site
that omits `workspace_id` fails CI.

---

## Confirmed root cause (verified)

- **Sentry (prod):** `Error: Failed to save user message: new row violates row-level security policy for table messages` `[dispatchSoleurGo(index)]` at `2026-06-02T19:06:18Z`, plus sibling `cc-dispatcher silent fallback`.
- **Prod DB (read-only REST):** `conversations` DO carry `workspace_id` (user's workspace `754ee124-…`); last real interactive chat message in that workspace was `2026-05-11`. Only service-role cron rows written since.
- **Migration:** `apps/web-platform/supabase/migrations/059_workspace_keyed_rls_sweep.sql:78-108` — `messages.workspace_id` `ADD COLUMN … REFERENCES workspaces(id)`, backfilled from `conversations.workspace_id` (lines 85-92), `SET NOT NULL` (94), new member-keyed SELECT/INSERT policies (102-108).
- **`is_workspace_member` semantics:** the INSERT WITH CHECK is satisfied iff `auth.uid()` is a member of the row's `workspace_id`. Deriving `workspace_id` from the parent conversation (whose own RLS already verified the caller is a member) is guaranteed to pass.

> Note: `059_workspace_keyed_rls_sweep.sql`'s header comment is mislabeled `055_…`
> (cosmetic; the file/applied prefix is 059). Mentioned for accuracy; **do not** edit
> in this PR.

---

## Affected insert sites (full sweep)

`git grep -nE '\.from\("messages"\)\.insert' apps/web-platform/server/` →

| # | Site | Role | `workspace_id` today | Action |
|---|------|------|----------------------|--------|
| 1 | `cc-dispatcher.ts:1449` | `user` (dispatchSoleurGo) | ❌ omitted | **FIX** |
| 2 | `cc-dispatcher.ts:1572` via `buildRow` (`cc-dispatcher.ts:433/449`) | `assistant` | ❌ omitted | **FIX** |
| 3 | `agent-runner.ts:447` (`saveMessage` choke point; callers `1956`, `2163`) | `user`/`assistant` | ❌ omitted | **FIX** |
| 4 | `agent-runner.ts:2438` (`sendUserMessage`) | `user` | ❌ omitted | **FIX** |
| 5 | `messages/insert-draft-card.ts:69` | draft card (service-role/cron) | ✅ already set (solo-pin, ADR-038 N2) | **NO CHANGE** — already correct; the grep-guard test must treat this as the passing exemplar |

**Stale comments to update** (all assert the pre-059 "RLS enforces FK-join to
conversations.user_id" contract):
- `cc-dispatcher.ts:1428-1431` (PR-C §2.11 comment above user INSERT)
- `cc-dispatcher.ts:1552-1556` (W1 comment in `saveAssistantMessage`)
- `agent-runner.ts:440-445` (`saveMessage` doc-comment)
- `agent-runner.ts:2435-2436` (`sendUserMessage` comment)

Replace with the post-059 contract: *RLS on `messages` requires `workspace_id` to be
a workspace the caller is a member of (`messages_workspace_member_insert` WITH CHECK
`is_workspace_member(workspace_id, auth.uid())`); we derive `workspace_id` from the
parent conversation, which the caller's conversation-RLS already gated on membership.*

---

## The fix — derivation strategy

**Source of truth: the parent conversation's `workspace_id`.** Each path already
touches the conversation; thread its `workspace_id` into the insert payload. This is
strictly correct (the conversation row itself is workspace-member-gated by
`conversations_workspace_member_all`), and survives any future multi-workspace
selection drift (unlike `resolveCurrentWorkspaceId`, which returns the *session-selected*
workspace and could diverge from the conversation's workspace).

### Site 1 + 2 — `cc-dispatcher.ts` (`dispatchSoleurGo`)

The ownership probe at `1395` (`updateConversationFor`, `expectMatch: true`) confirms
the caller owns the conversation but does **not** return `workspace_id`. Two options:

- **(A) Add a `workspace_id` read.** After the ownership probe, fetch
  `conversations.workspace_id` once via the minted tenant client
  (`tenant.from("conversations").select("workspace_id").eq("id", conversationId).single()`),
  reusing the `tenant` already minted at `1439`. Pass it into the user INSERT (1449)
  and into `buildRow` (so the assistant row at 1572 carries it too).
- **(B) Extend `updateConversationFor`** to optionally `select("workspace_id")` and
  return it from the same round-trip (avoids an extra RTT).

**Decision:** prefer (A) for minimal blast radius (one added SELECT on the tenant
client, no shared-helper signature change). Reuse the existing `tenant` mint — do not
mint a second client (Kieran single-RTT rule). If the conversation row's `workspace_id`
read fails, mirror via `reportSilentFallback` and throw (the dispatch's existing
user-INSERT-failure path already throws and is awaited).

`buildRow(mode, text, conversationId)` gains a `workspaceId: string` parameter and
adds `workspace_id: workspaceId` to the returned row object (`cc-dispatcher.ts:449-457`).

### Site 3 — `agent-runner.ts:saveMessage` (choke point for assistant rows 1956/2163)

`saveMessage(userId, conversationId, role, content, …)` does not currently know the
workspace. Fetch the conversation's `workspace_id` inside `saveMessage` via the minted
`tenant` (one SELECT before the INSERT) **or** thread it from callers. Because
`saveMessage` is the single choke point and both callers already have `conversationId`,
fetch inside `saveMessage` (keeps both call sites unchanged). Add `workspace_id` to the
insert payload at `447-456`. On conversation-read failure, throw
`Failed to save message: <reason>` consistent with the existing error contract.

### Site 4 — `agent-runner.ts:sendUserMessage`

`sendUserMessage` already fetches the conversation at `2426-2431`
(`.select("domain_leader, session_id").eq("id",…).eq("user_id",…).single()`). **Add
`workspace_id` to that existing select** — no extra round-trip — and include it in the
INSERT at `2438-2445`.

### Research Insights — fix strategy

**Context7 (`/supabase/supabase`, RLS INSERT WITH CHECK):** An INSERT policy whose
`WITH CHECK` references a column requires that column to carry a value satisfying the
predicate at insert time. The canonical example is the Clerk integration policy
("the newly inserted row has the user's org ID in the `organization_id` column"),
which is the exact analog of `is_workspace_member(workspace_id, auth.uid())`. Omitting
the column → it is `NULL` → predicate false → `new row violates row-level security
policy`. Confirms the bug mechanism and that populating `workspace_id` from a workspace
the caller is a member of is the documented fix.

**supabase-js contract (`^2.49.0` installed, verified in `apps/web-platform/package.json`):**
`.insert()` returns `{ data, error }` and does NOT throw (learning
`2026-03-20-supabase-silent-error-return-values.md`). All four sites already destructure
`{ error }` and surface it — **preserve this**; do NOT introduce `.throwOnError()`
(changes the whole-chain contract). The new conversation-`workspace_id` reads must
likewise destructure `{ data, error }` and branch on error (mirror via
`reportSilentFallback` per `cq-silent-fallback-must-mirror-to-sentry`).

**Single-RTT discipline (Kieran P2-2, reaffirmed):** Reuse the already-minted `tenant`
(cc-dispatcher) / `sendTenant` (agent-runner) clients for the workspace read. For
`sendUserMessage` there is ZERO added RTT (extend the existing select). For
cc-dispatcher and `saveMessage` there is exactly one added SELECT each.

**Anti-pattern avoided:** Do NOT derive `workspace_id` from `resolveCurrentWorkspaceId`
(`workspace-resolver.ts:190`) — it returns the *session-selected* workspace, which can
diverge from the conversation's workspace for a multi-membership operator and would
write a row into the wrong workspace (passes RLS by membership, but mis-attributes the
message). The parent conversation's `workspace_id` is the only correct source.

---

## Acceptance criteria

- [ ] **AC1** All four interactive insert sites (cc-dispatcher user 1449, cc-dispatcher assistant via `buildRow`, agent-runner `saveMessage`, agent-runner `sendUserMessage`) include `workspace_id` in the INSERT payload, derived from the parent conversation's `workspace_id`.
- [ ] **AC2** `insert-draft-card.ts` is unchanged (already correct).
- [ ] **AC3** Sending a chat message in the interactive path persists a `messages` row (no RLS rejection); the generic `"An unexpected error occurred"` bubble no longer appears for the save path.
- [ ] **AC4** All four stale "RLS enforces FK-join to conversations.user_id" comments are rewritten to the post-059 workspace-member contract.
- [ ] **AC5** RED → GREEN: per-path mock-chain tests assert the captured INSERT payload contains `workspace_id` equal to the conversation's `workspace_id`, on BOTH cc-dispatcher and agent-runner paths (user + assistant rows).
- [ ] **AC6** A source-grep sweep test asserts every `\.from\("messages"\)\.insert` in `apps/web-platform/server/` includes a `workspace_id` key (exemplar: `insert-draft-card.ts`). New insert sites omitting it fail CI.
- [ ] **AC7** Prod RLS state verified via the Doppler + Supabase read path before ship (see Verification), and the fix logic confirmed against the `is_workspace_member` WITH CHECK predicate.
- [ ] **AC8** No new tenant clients minted solely to read `workspace_id` (reuse existing mints / existing conversation selects).
- [ ] **AC9** Follow-up issue filed for the `094_*` duplicate-prefix migration collision (NOT renumbered in this PR).

---

## Test scenarios (RED first — `cq-write-failing-tests-before`)

**Capture seam already exists (verified — do NOT build new infra):** The cc-dispatcher
harness wires `tenant.from("messages").insert` to the spy `opts.mockMessagesInsert`
(`test/helpers/cc-dispatcher-harness.ts:116-118` for the service path and `143-145`
for the `getFreshTenantClient` tenant path). `cc-dispatcher.test.ts:1085-1091` already
defines `assistantInsertCalls(insertMock)` reading `insertMock.mock.calls` and filtering
by `role`. **T1-T4 just add a `workspace_id` assertion to the already-captured payload.**
For the agent-runner path, reuse / mirror `test/helpers/agent-runner-mocks.ts` the same
way. The tenant-isolation suites `test/server/cc-dispatcher.tenant-isolation.test.ts` +
`test/server/agent-runner.tenant-isolation.test.ts` are the natural home for the
cross-tenant + workspace-id assertions. `mock-supabase.ts`'s `mockQueryChain` already
returns `this` for `.insert` and is thenable; if a test uses it directly, assert
`insert.mock.calls[0][0].workspace_id`.

To exercise the workspace-read, the conversation mock must return a `workspace_id`
(e.g. `{ workspace_id: "ws-A", … }`) from the `.single()`/`.select()` terminal so the
fix has a value to thread.

1. **T1 (cc-dispatcher user row):** dispatch a turn; conversation mock returns
   `workspace_id: "ws-A"`. Assert the user-INSERT payload `(1449)` has
   `workspace_id === "ws-A"`.
2. **T2 (cc-dispatcher assistant row):** drive an `onText` → complete turn. Assert the
   assistant-INSERT payload (via `buildRow`/1572) has `workspace_id === "ws-A"`.
3. **T3 (agent-runner `saveMessage`):** call the assistant-persistence path; conversation
   mock returns `workspace_id: "ws-B"`. Assert INSERT payload has
   `workspace_id === "ws-B"`.
4. **T4 (agent-runner `sendUserMessage`):** conversation select returns `workspace_id`;
   assert the user INSERT (2438) carries it.
5. **T5 (grep-sweep guard):** read each `apps/web-platform/server/**/*.ts`, find every
   `.from("messages").insert(`, and assert the insert object literal (or `buildRow`
   return) contains a `workspace_id` key. `insert-draft-card.ts` passes (already has
   it). A synthetic fixture insert lacking `workspace_id` must make the test fail
   (negative-control assertion to avoid a vacuous pass).
6. **T6 (failure mirror):** when the conversation `workspace_id` read errors, assert
   `reportSilentFallback` is called and the path throws (no silent NULL insert).

> All fixtures synthesized (`cq-test-fixtures-synthesized-only`) — no real workspace
> ids except the redacted `754ee124-…` referenced in prose only.

### Research Insights — tests

**pr-test-analyzer lens:** T5 (grep-sweep) must be non-vacuous — include a negative
control: a synthetic insert-object literal lacking `workspace_id` MUST make the matcher
fail. Without it, a regex that matches nothing passes silently (the exact failure mode
in learning `2026-05-12` Defect B's call-count test). Mirror the existing
`T-W1-invariant-7` pattern at `cc-dispatcher.test.ts:1819` (call-site-exhaustive
assertion across user + complete + aborted writes) — add `workspace_id` presence to
each captured call there too.

**silent-failure-hunter lens:** T6 must assert BOTH that `reportSilentFallback` fires
AND that the path throws (or aborts the insert) — never a NULL-`workspace_id` insert
that would 500 in prod. A test that only checks the throw, or only the mirror, misses
half the contract.

**data-integrity-guardian lens:** add an assertion that the asserted `workspace_id`
equals the *conversation's* `workspace_id` (not merely "is present" and not
`resolveCurrentWorkspaceId`'s value) — the wrong-source bug (mis-attribution to the
session-selected workspace) passes a "present" check but is a data-integrity defect.

---

## Verification before ship (`hr-no-dashboard-eyeball-pull-data-yourself`, AC7)

Read-only, no prod writes. Source secrets from Doppler `prd` config (the
`apps/web-platform` runbooks use `-p soleur -c prd`; confirm exact config name with
`doppler configs -p soleur`).

1. **Confirm the INSERT policy + NOT NULL on prod:**
   ```bash
   SUPABASE_URL=$(doppler secrets get NEXT_PUBLIC_SUPABASE_URL -p soleur -c prd --plain)
   SRK=$(doppler secrets get SUPABASE_SERVICE_ROLE_KEY -p soleur -c prd --plain)
   # Read-only GET: confirm conversations carry workspace_id and recent messages gap.
   curl -sS "${SUPABASE_URL}/rest/v1/messages?select=workspace_id,created_at&order=created_at.desc&limit=5" \
     -H "apikey: ${SRK}" -H "Authorization: Bearer ${SRK}"
   ```
   Confirm: latest interactive (non-cron) `messages.created_at` is stale (~2026-05-11)
   pre-fix; `conversations.workspace_id` is populated.
2. **Confirm policy text** matches `messages_workspace_member_insert` WITH CHECK
   `is_workspace_member(workspace_id, auth.uid())` (read `059_…sql` locally; the prod
   schema is the source migration). Verify the fix's derived `workspace_id` (parent
   conversation's) satisfies the predicate: the caller is a member of the conversation's
   workspace (conversation RLS already enforced this on read).
3. **Post-deploy success signal:** after merge + deploy, a fresh interactive message
   persists (new `messages` row with non-null `workspace_id` in the user's workspace);
   the Sentry `Failed to save user message` + `cc-dispatcher silent fallback`
   signatures stop firing.

> Never paste secrets via `!`-prefix; assign via `$(doppler …)` only
> (`hr-never-paste-secrets-via-bang-prefix`). `dev`/`prd` are distinct Supabase
> projects (`hr-dev-prd-distinct-supabase-projects`) — use `prd` for verification.

---

## Out of scope / follow-ups

- **`094_*` duplicate-prefix migration collision (SEPARATE — do NOT fold in).** Both
  `apps/web-platform/supabase/migrations/094_dedup_tables_retention.sql` and
  `094_member_rpc_caller_override_and_byok_cap_update.sql` exist. File a follow-up
  issue to (a) renumber one of them and (b) check whether the prefix collision affected
  prod migration application order (which 094 applied, and whether the other was
  skipped/applied out of order). **Do NOT renumber in this PR** (AC9).
- **`059` header comment mislabel (`055_…`)** — cosmetic, leave as-is.
- No schema change, no new migration: the fix is application-layer only. The
  `messages.workspace_id` column + policy already exist in prod (that's the bug).

---

## Domain Review

**Domains relevant:** Engineering, Legal/Compliance

This is a backend bugfix (no new user-facing pages, flows, or UI components — the user
already sees the existing chat surface). Product/UX gate tier: **NONE** (a backend
write-path fix that restores existing behavior; no new screens or journeys).

### Engineering

**Status:** reviewed
**Assessment:** Root cause confirmed against Sentry + prod DB. Fix is the canonical
write-boundary-sweep remedy for the persistence-asymmetry class (learnings
`2026-05-05-cc-dispatcher-assistant-persistence-asymmetry.md`,
`2026-05-12-type-widening-cascades-and-write-boundary-sentinels.md`). Risk: missing an
insert site → the grep-sweep guard test (T5/AC6) is the mechanical defense. Reuse
existing tenant mints / conversation selects to avoid added RTTs.

### Legal/Compliance

**Status:** reviewed
**Assessment:** `messages` rows carry user PII (chat content). The fix writes
`workspace_id` derived from the parent conversation, which is already workspace-member
gated — no cross-tenant exposure introduced (Art. 33/34 surface unchanged; if anything
the workspace-keyed RLS is *stricter* than the pre-059 FK-join). No new data category,
no retention change. The existing `assertWriteScope` sentinel remains the defense-in-depth
layer. No DSAR/GDPR gate change required (`hr-gdpr-gate-on-regulated-data-surfaces`:
this is a fix to restore correct workspace-keyed writes, not a new regulated surface).

---

## References

- **Migration:** `apps/web-platform/supabase/migrations/059_workspace_keyed_rls_sweep.sql:78-108`
- **Insert sites:** `apps/web-platform/server/cc-dispatcher.ts:449,1449,1572`; `apps/web-platform/server/agent-runner.ts:447,2438`
- **Exemplar (correct):** `apps/web-platform/server/messages/insert-draft-card.ts:66-83`
- **Error sanitizer:** `apps/web-platform/server/error-sanitizer.ts:79`
- **Workspace resolvers:** `apps/web-platform/server/workspace-resolver.ts:190` (`resolveCurrentWorkspaceId`)
- **Learnings:** `knowledge-base/project/learnings/integration-issues/2026-05-05-cc-dispatcher-assistant-persistence-asymmetry.md`; `knowledge-base/project/learnings/2026-05-12-type-widening-cascades-and-write-boundary-sentinels.md`; `knowledge-base/project/learnings/2026-03-28-unapplied-migration-command-center-chat-failure.md` (the "An unexpected error occurred" → schema/RLS-mismatch chain + merge-time prod-DB verification rule); `knowledge-base/project/learnings/2026-03-20-supabase-silent-error-return-values.md` (`{ error }`-destructure contract — preserve)
- **Context7:** `/supabase/supabase` — RLS INSERT WITH CHECK requires the referenced column be populated to satisfy the predicate (Clerk `organization_id` analog)
- **Test infra:** `apps/web-platform/test/helpers/mock-supabase.ts`; `test/helpers/cc-dispatcher-harness.ts`; `test/helpers/agent-runner-mocks.ts`; `test/server/{cc-dispatcher,agent-runner}.tenant-isolation.test.ts`
- **Related rules:** `hr-write-boundary-sentinel-sweep-all-write-sites`, `cq-write-failing-tests-before`, `hr-no-dashboard-eyeball-pull-data-yourself`, `hr-dev-prd-distinct-supabase-projects`, `cq-silent-fallback-must-mirror-to-sentry`
- **Prior adjacent PR:** #4816 (history-fetch 404 noise — did NOT fix this write-path RLS failure)
