---
title: "chore: remove FLAG_CC_SOLEUR_GO (always-on in prd and dev)"
issue: 3270
type: chore
classification: code-removal
requires_cpo_signoff: false
brand_impact_threshold: none
status: planned
---

# chore: remove FLAG_CC_SOLEUR_GO (always-on in prod and dev)

## Overview

`FLAG_CC_SOLEUR_GO` is set to `"1"` in both `prd` and `dev` Doppler configs.
The `false` branch is unreachable in any deployed environment, which means
every read of the flag and every conditional that gates on it is dead code
pretending to be live infrastructure. Daisy flagged this for removal during
PR #3263 review.

This plan removes the flag itself, inlines its single load-bearing consumer
(`resolveInitialRouting`), drops the `ccFlagEnabled` branch in
`ws-handler.ts` so the cc-specific rate limiter runs unconditionally,
reframes the `router-flag-stickiness` test to assert the underlying invariant
without flag input, and updates two stale comments.

The fix shape is fully specified in #3270. The prior bot-fix attempt
(2026-05-08) declined the PR citing multi-file scope; the scope is in fact
small but spans 5 source files + 1 ADR, which is what the bot's
single-file heuristic balked at. This plan ships all 6 file edits in one
atomic PR.

**Doppler cleanup (`unset` the env var in `prd`/`dev`/`ci`) is explicitly
out of scope** for this PR — see Non-Goals. After this code lands, the env
var is dead in code regardless of its Doppler value, so the cleanup can
land lazily without coordination.

## Research Reconciliation — Spec vs. Codebase

| Spec claim (issue #3270 body) | Codebase reality | Plan response |
|---|---|---|
| `cc-dispatcher.ts:7-10` has stale comment claiming `FLAG_CC_SOLEUR_GO=0` in prod default | Confirmed verbatim at lines 7-10 of `apps/web-platform/server/cc-dispatcher.ts`. | Update comment to remove the flag reference; describe `realSdkQueryFactory` as the always-on cc-soleur-go SDK binding. |
| `cc-dispatcher.ts:375` has stale comment | Line 375 is `record.session.reviewGateResolvers.delete(args.gateId);` — NOT a comment. The actual stale flag-reference is at line 419 (`"realSdkQueryFactory — Stage 2.12 binding (replaces the prior stub that throw-mirrored to Sentry under FLAG_CC_SOLEUR_GO)"`). | Update the comment at **line 419** instead. The issue body cited the wrong line number; the only other `FLAG_CC_SOLEUR_GO` reference in the file is in that block header. |
| `ws-handler.ts:676-703` — runtime gate for cc routing + cc rate limiter | The actual gate sits at lines **975-1018** (the issue cites pre-edit line numbers from before #3263 / migration 032 landed). The gate's three load-bearing parts: (a) `const ccFlagEnabled = getFlag("command-center-soleur-go")` at 991, (b) `if (ccFlagEnabled) { rate-limiter check }` at 992-1017, (c) `resolveInitialRouting(ccFlagEnabled)` at 1018. | Plan targets the line range **975-1018**; the structural shape matches the issue's intent exactly. |
| `conversation-routing.ts:67-76` (`resolveInitialRouting`) is the only consumer of `flagEnabled` | Confirmed via `grep -rn "resolveInitialRouting" apps/web-platform/` — three call sites: one definition, one ws-handler caller, three test refs. The function is the single flag-to-routing adapter described in #2853. | Inline it: replace the only ws-handler call with the literal `{ kind: "soleur_go_pending" } as ConversationRouting` and delete the function. |
| `router-flag-stickiness.test.ts` exists and should be reframed (NOT deleted) | Confirmed at `apps/web-platform/test/router-flag-stickiness.test.ts` (67 lines, 5 `it` blocks). Two of the five tests assert against `resolveInitialRouting` directly; three assert against `parseConversationRouting` and are already flag-agnostic. | Drop the two `resolveInitialRouting` tests; keep + rename the file to assert the underlying `active_workflow IS NULL → legacy` invariant from `parseConversationRouting`. |
| ADR-022 not mentioned in issue | `knowledge-base/engineering/architecture/decisions/ADR-022-sdk-as-router.md:72` references `FLAG_CC_SOLEUR_GO=false` as the legacy gate. | Touch ADR-022 to replace the conditional-removal sentence with a "Stage 8 landed in #3270" note. Keeps the decision record historically faithful without rewriting the body. |

## User-Brand Impact

**If this lands broken, the user experiences:** WebSocket `start_session` rejects every new conversation with a 500 / abort, or new conversations silently route to the legacy `agent-runner.ts` path (regression of #3263 / migration 032).

**If this leaks, the user's data/workflow is exposed via:** N/A — this PR removes a runtime flag; no new PII vector, no new credential surface, no new authorization edge. The only data path touched is `conversations.active_workflow` which is already written under the always-on prod branch today.

**Brand-survival threshold:** `none` — this is dead-code removal. The cc-soleur-go path has been the sole live path in both prd and dev for the soak window described in ADR-022, and the failure mode of this PR is identical to the failure mode of any push to `ws-handler.ts` start-session logic.

**Reason for threshold = none** (per `plugins/soleur/skills/preflight/SKILL.md` Check 6): no new credentials, auth flow, regulated-data column, payment surface, or user-owned-resource touch. The diff is a flag deletion; the runtime behavior is the same branch that already executes for 100% of traffic.

## Files to Edit

1. `apps/web-platform/lib/feature-flags/server.ts` — remove `"command-center-soleur-go": "FLAG_CC_SOLEUR_GO"` line from `FLAG_VARS`.
2. `apps/web-platform/lib/feature-flags/server.test.ts` — delete the `describe("command-center-soleur-go flag", ...)` block (lines 75-100) AND remove the two `delete process.env.FLAG_CC_SOLEUR_GO` lines inside the `getFeatureFlags` `it` blocks (lines 52, 64) plus the corresponding `"command-center-soleur-go": false` entries in the `toEqual` expectations.
3. `apps/web-platform/server/conversation-routing.ts` — delete `resolveInitialRouting` (lines 67-76 of the function block, plus its preceding comment). Update the module header comment (`// COUPLING INVARIANT` block at lines 1-25) to drop the `resolveInitialRouting` reference.
4. `apps/web-platform/server/ws-handler.ts` — at lines 975-1018:
   - Delete `const ccFlagEnabled = getFlag("command-center-soleur-go");` and the `if (ccFlagEnabled) { ... }` wrapper (lines 991-1017), leaving the rate-limiter check body unconditional.
   - Replace `const initialRouting: ConversationRouting = resolveInitialRouting(ccFlagEnabled);` (line 1018) with `const initialRouting: ConversationRouting = { kind: "soleur_go_pending" };`.
   - Remove `resolveInitialRouting` from the import on line 48.
   - Remove `getFlag` from the import on line 63 — UNLESS another `getFlag(...)` call exists in the file (verify via `grep -n "getFlag(" apps/web-platform/server/ws-handler.ts`; the dev-signin and kb-chat-sidebar flags may still be used). Drop the import only if the grep returns zero non-deleted hits.
   - Update the inline comment at lines 987-990 ("soleur-go path gets an additional per-user + per-IP sliding-window limiter") to drop the conditional framing — the cc rate limiter is now the universal post-`sessionThrottle` limiter for all new conversations.
5. `apps/web-platform/test/router-flag-stickiness.test.ts` — rename to `router-stickiness-invariant.test.ts` (per `git mv`) and reframe:
   - Drop the two `it` blocks that call `resolveInitialRouting` (lines 32-38).
   - Drop the `resolveInitialRouting` import from line 4.
   - Keep the three `parseConversationRouting` `it` blocks (lines 40-66) — they already assert the underlying invariant.
   - Update the `describe` block title from `"router-flag-stickiness (Stage 2.3)"` to `"router stickiness invariant (active_workflow → ConversationRouting)"`.
   - Rewrite the file-header doc-comment (lines 9-29) to drop the FLAG_CC_SOLEUR_GO framing and instead document the load-bearing invariant: `parseConversationRouting` is the only routing decision for turn 2+, and a row with `active_workflow IS NULL` is invariably `{ kind: "legacy" }` regardless of any future flag/config state.
6. `apps/web-platform/server/cc-dispatcher.ts` — two comment edits:
   - Lines 6-10: replace the `Stage 2.12 — bind real-SDK query()` / `Behind FLAG_CC_SOLEUR_GO=0 in prod (default) this code path is unreachable; in dev (FLAG_CC_SOLEUR_GO=1) the runner actually invokes the SDK end-to-end` block with a corrected note explaining `realSdkQueryFactory` is the always-on production cc-soleur-go SDK binding (post-#3270).
   - Line 419: replace `realSdkQueryFactory — Stage 2.12 binding (replaces the prior stub that throw-mirrored to Sentry under FLAG_CC_SOLEUR_GO).` with `realSdkQueryFactory — Stage 2.12 binding (originally gated behind FLAG_CC_SOLEUR_GO; flag removed in #3270, this is now the unconditional production binding).`
7. `knowledge-base/engineering/architecture/decisions/ADR-022-sdk-as-router.md:71-73` — replace the paragraph `Legacy domain-router.ts / agent-runner.ts / dispatchToLeaders remain behind FLAG_CC_SOLEUR_GO=false until a 14-day dev soak confirms the new path, then Stage 8 (separate PR) removes them.` with a one-line follow-up: `Stage 8 landed via #3270 — FLAG_CC_SOLEUR_GO was removed and the cc-soleur-go path is now the unconditional production binding. Legacy router code is retained for the SDK-router fallback paths only.`

## Files to Create

None.

## Open Code-Review Overlap

5 open code-review issues touch files this plan modifies, none scope-overlap with the flag-removal scope:

- **#3374** (ws-handler.ts): `slot_reclaimed` WS frame for ledger-divergence recovery — touches divergence-recovery surface (`tryLedgerDivergenceRecovery`), not `start_session`/`ccFlagEnabled`. **Acknowledge** — different concern, kept open.
- **#3372** (ws-handler.ts): stale-heartbeat branch tautological — same divergence-recovery surface as #3374. **Acknowledge** — kept open.
- **#2191** (ws-handler.ts): `clearSessionTimers` helper extraction + refresh-timer jitter — touches session-lifecycle/timer logic, not start-session routing. **Acknowledge** — kept open.
- **#3369** (cc-dispatcher.ts): extract `mirrorWithDebounce` to observability — extraction concern, no overlap with the comment-only edit at lines 6-10 / 419. **Acknowledge** — kept open.
- **#3243** (cc-dispatcher.ts): decompose cc-dispatcher into focused modules — architectural decomposition concern; this PR's two-comment edit is too narrow to fold in. **Acknowledge** — kept open.
- **#3242** (cc-dispatcher.ts): `tool_use` WS event lacks raw `name` field — different code path. **Acknowledge** — kept open.
- **#2955** (cc-dispatcher.ts): process-local state assumption needs ADR — orthogonal architectural concern. **Acknowledge** — kept open.

Decision: all overlaps acknowledged; no fold-in. The flag-removal scope and the surrounding cc-dispatcher / ws-handler review backlog are independent.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] `apps/web-platform/lib/feature-flags/server.ts` no longer mentions `command-center-soleur-go` / `FLAG_CC_SOLEUR_GO` (`grep -F FLAG_CC_SOLEUR_GO apps/web-platform/lib/feature-flags/server.ts` returns zero).
- [ ] `apps/web-platform/server/conversation-routing.ts` no longer exports `resolveInitialRouting` (`grep -n 'export function resolveInitialRouting' apps/web-platform/server/conversation-routing.ts` returns zero).
- [ ] `apps/web-platform/server/ws-handler.ts` no longer references `ccFlagEnabled` or `resolveInitialRouting` (`grep -nE 'ccFlagEnabled|resolveInitialRouting' apps/web-platform/server/ws-handler.ts` returns zero).
- [ ] The cc rate-limiter check (`getCcStartSessionRateLimiter().check({ userId, ip: rateLimitIp })`) runs unconditionally for every `start_session` call (no `if (ccFlagEnabled)` wrapper).
- [ ] `apps/web-platform/test/router-flag-stickiness.test.ts` has been renamed to `router-stickiness-invariant.test.ts` (verify via `git status` shows R → ).
- [ ] The renamed test file imports neither `resolveInitialRouting` nor `getFlag`, and its `describe` title no longer contains `"flag"`.
- [ ] Class-wide grep for the symbol `FLAG_CC_SOLEUR_GO` across `apps/`, `knowledge-base/engineering/`, `knowledge-base/product/`, `.github/`, root `*.md` returns matches only in:
  - `knowledge-base/project/learnings/**` (historical record — keep)
  - `knowledge-base/project/plans/**` (this plan + prior plans — keep)
  - `knowledge-base/project/specs/**/archive/**` (historical specs — keep)
  - any path under `archive/` (preserved history — keep)
  
  Run `git grep -F FLAG_CC_SOLEUR_GO -- ':!knowledge-base/project/learnings/**' ':!knowledge-base/project/plans/**' ':!knowledge-base/project/specs/**' ':!**/archive/**'` and verify zero hits before merging.
- [ ] `getFlag` import in `ws-handler.ts` is either removed (if no other `getFlag(` call remains in the file) OR retained (verified by `grep -c 'getFlag(' apps/web-platform/server/ws-handler.ts ≥ 1`). The grep count justifies the decision — record the count in the PR body.
- [ ] `bun test apps/web-platform/lib/feature-flags/server.test.ts` passes (5 remaining tests).
- [ ] `bun test apps/web-platform/test/router-stickiness-invariant.test.ts` passes (3 remaining tests).
- [ ] `bun run typecheck` (or repo's canonical `tsc --noEmit` runner per `package.json`) passes — verifies no orphan reference to `resolveInitialRouting` survives.
- [ ] Full vitest suite for `apps/web-platform/` is green; in particular the WS-handler tests touching `start_session` (`apps/web-platform/test/ws-handler.test.ts` if present, `apps/web-platform/test/agent-session.test.ts` for the legacy path) still pass.
- [ ] PR body uses `Closes #3270` on its own line (per `wg-use-closes-n-in-pr-body-not-title-to`); does NOT use `Closes` for any of the acknowledged code-review issues (#3374, #3372, #2191, #3369, #3243, #3242, #2955).

### Post-merge (operator)

- [ ] **Optional Doppler cleanup (deferred — separate PR/task).** Run `doppler secrets unset FLAG_CC_SOLEUR_GO -p soleur -c dev` and same for `prd` and `ci` configs. This is operator-only because env-var presence after code removal is harmless (no reader). Track as scope-out, do NOT auto-close from this PR.
- [ ] Verify `start_session` traffic in Sentry for the first 24h post-deploy shows no new error class introduced (search: `start_session AND (cc OR rate_limited OR soleur_go_pending)` over the deploy window).

## Test Plan

### TDD ordering

The plan touches a TypeScript surface where the compiler is load-bearing (per `2026-05-07-tsc-not-source-grep-enumerates-exhaustiveness-rails.md`). The required RED-GREEN sequence:

1. **RED — test edits first.** Apply the renames + import drops + `it`-block deletions in `router-flag-stickiness.test.ts` (now `router-stickiness-invariant.test.ts`) and remove the FLAG-specific block in `server.test.ts`. The test file will reference `resolveInitialRouting` until its import is dropped; running `bun test` at this state should fail with a clear "cannot find name" if the function is also deleted concurrently. **This is the structural sanity smoke.**
2. **GREEN — source edits.** Delete `resolveInitialRouting` from `conversation-routing.ts`. Remove `FLAG_CC_SOLEUR_GO` entry from `feature-flags/server.ts`. Drop the `ccFlagEnabled` branch and `resolveInitialRouting` call in `ws-handler.ts`. The compiler must come back clean.
3. **GREEN — comment edits.** Update `cc-dispatcher.ts` (lines 6-10, 419) and `ADR-022-sdk-as-router.md` (line 72). Comment-only — no test impact.
4. **Run typecheck + full vitest suite** — every step's GREEN is the suite, not just a single targeted file.

### Test scenarios

- `apps/web-platform/lib/feature-flags/server.test.ts` — remaining 5 tests on `kb-chat-sidebar` and `dev-signin` still pass; the `getFeatureFlags` shape test now expects `{ "kb-chat-sidebar": ..., "dev-signin": ... }` only (no `"command-center-soleur-go"` key).
- `apps/web-platform/test/router-stickiness-invariant.test.ts` — 3 `parseConversationRouting` tests still pass, demonstrating that the invariant ("turn 2+ routing is determined by `active_workflow` column, not by any flag") survives the flag removal.

### Non-test verification

- Run `tsc --noEmit` (via the repo's canonical script) and confirm zero errors. The compiler is the canonical enumerator of dangling references — if any consumer of `resolveInitialRouting` was missed, `tsc` will fail with TS2305 (`Module has no exported member`).
- Run `git grep -F FLAG_CC_SOLEUR_GO -- ':!knowledge-base/project/learnings/**' ':!knowledge-base/project/plans/**' ':!knowledge-base/project/specs/**' ':!**/archive/**'` and verify zero matches. This is the class-wide retirement-cleanup grep (per `2026-05-09-retirement-cleanup-grep-must-scan-full-class-not-named-id.md`) — the named-target ID is `FLAG_CC_SOLEUR_GO`, the protected surface is "everything not in historical record".

## Non-Goals

- **Doppler env-var cleanup.** Removing `FLAG_CC_SOLEUR_GO` from Doppler `prd` / `dev` / `ci` configs is operator-only post-merge work. After this PR lands, the env var has no reader — its Doppler value is irrelevant. The cleanup is tracked as a Post-merge AC (optional) but is NOT a merge blocker.
- **`getFlag` / feature-flag module redesign.** The flag-registry shape is unchanged. Future flags continue to be added via the `FLAG_VARS` map.
- **Legacy-path removal.** The `agent-runner.ts` / `domain-router.ts` / `dispatchToLeaders` codepaths are reachable via the legacy `startAgentSession` entry (for conversations with `active_workflow IS NULL`) — that's the per-conversation stickiness invariant the renamed test still asserts. This PR does NOT delete the legacy path; ADR-022 is updated to reflect that the legacy code is retained for stickiness/fallback, not gated by the (now-removed) flag.
- **Rate-limiter cap retuning.** The cc rate limiter's caps (10/user/hour, 30/IP/hour) become the universal `start_session` caps when the flag is removed. The issue body asked for a "sanity check against current legacy traffic"; this plan keeps the existing caps untouched and tracks any retune as a separate follow-up (see Deferrals). The runtime safety net for the universal cap is the upstream `sessionThrottle` check at `ws-handler.ts:975` (same as today's behavior for any user whose Doppler config has the flag set — i.e., everyone in prd and dev).

## Deferrals (tracked separately)

| Item | Why deferred | Re-evaluation criteria | Tracking |
|---|---|---|---|
| Rate-limiter cap retune (10/u/h, 30/IP/h) for universal traffic | Out of scope per issue body — the issue says "needs a sanity check"; sanity check ≠ retune. Doing this PR atomically with cap changes would conflate "remove dead branch" with "tune a live policy". | If Sentry shows rate_limited errors increasing >10× post-deploy, file a separate follow-up. | Mention in PR body; defer formally to a Post-MVP issue if rejection rate spikes. |
| Doppler `unset FLAG_CC_SOLEUR_GO` across prd/dev/ci | Post-merge operator step; not a merge blocker. | After PR merges + deploy verifies clean. | Post-merge AC. |
| ADR-022 deeper refactor (clarify that "legacy" path is retained as stickiness fallback, not deprecated) | Out of scope — this PR only updates the one sentence that references the removed flag. A broader ADR rewrite would change the decision record without a new decision. | If a future PR removes the legacy path entirely, rewrite ADR-022 then. | Single-line edit in this PR. |

## Risks

1. **`getFlag` import removal from `ws-handler.ts` may be premature.** If another flag (e.g., `dev-signin`, `kb-chat-sidebar`) is read elsewhere in the file, dropping the import breaks build. **Mitigation:** the per-task verification step `grep -c 'getFlag(' apps/web-platform/server/ws-handler.ts` decides this at edit time; the import is retained if the count is non-zero after the deletion.
2. **`tsc --noEmit` may miss orphan references in `*.test-d.ts` exhaustiveness rails** (per `2026-05-07-tsc-not-source-grep-enumerates-exhaustiveness-rails.md`). `resolveInitialRouting` is not a discriminated-union widening, so the risk is low, but a `*.test-d.ts` could still import the symbol. **Mitigation:** run `git grep -nE 'resolveInitialRouting' -- '*.test-d.ts' '*.ts'` after the source edit lands and confirm zero hits before pushing.
3. **The `router-flag-stickiness.test.ts` rename loses git blame history** for the surviving three test bodies. **Mitigation:** use `git mv` (not delete-and-create) so the rename is recorded as a rename, not a new file. Verify via `git status` showing `R` (renamed) before commit.
4. **The cc rate limiter now fires for legacy users too.** Prior to this change, users whose env was `FLAG_CC_SOLEUR_GO=1` already hit the cc limiter — which is everyone in prd and dev. The behavioral delta is **zero in any deployed environment**. The only place the change matters is local-dev environments where someone has explicitly set `FLAG_CC_SOLEUR_GO=0` for testing; those environments now also hit the cc limiter (10/user/hour, 30/IP/hour). **Mitigation:** the only person likely to have FLAG_CC_SOLEUR_GO=0 locally is a developer testing the legacy path. They'll see the rate limiter trip on their 11th start_session in an hour — which is annoying but not breaking, and the legacy path is retained for stickiness anyway.
5. **The `Closes #3270` sentinel triggers issue auto-close at merge.** Per `wg-use-closes-n-in-pr-body-not-title-to`, this is the intended behavior — the issue is genuinely resolved at merge, no post-merge remediation runs (the Doppler cleanup is operator-only and tracked as a Post-merge AC, not a blocking remediation). Use `Closes #3270` on its own line in the PR body, NOT in the title.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan's threshold is `none` with a one-line rationale per `plugins/soleur/skills/preflight/SKILL.md` Check 6 — fill remains intact.
- When renaming `router-flag-stickiness.test.ts` → `router-stickiness-invariant.test.ts`, use `git mv` exactly. A delete-then-create masquerading as a rename produces a no-history file and complicates `git blame`. **Verify the rename via `git status` shows `R` before commit; if it shows `D` + `??`, run `git mv` again.**
- When removing the FLAG_VARS entry, verify the surrounding `as const` typedef still produces a valid `FlagName` union. The current type is `keyof typeof FLAG_VARS` — removing one entry simply narrows the union to two members and is type-safe by construction. No type-assertion fix-up is needed.
- The `comment-center-soleur-go` flag string (the slug used as the key in `FLAG_VARS`) is NOT referenced anywhere else by string literal (verify with `git grep -F 'command-center-soleur-go'`). All consumers go through the typed `getFlag("command-center-soleur-go")` call, which TypeScript will reject after the key is removed.
- The `FLAG_CC_SOLEUR_GO` env-var symbol appears in `cc-dispatcher.ts:419` ONLY as a comment-narrative reference (in the historical `replaces the prior stub that throw-mirrored to Sentry under FLAG_CC_SOLEUR_GO` line). Comment edits are not load-bearing; do not over-engineer this into a JSDoc rewrite — keep the edit minimal and historically faithful.
- This is a **chore** PR (no semver-bump label needed). Per `wg-never-bump-version-files-in-feature` do NOT edit `plugin.json` or `marketplace.json`. The CI label-bot does not add semver labels to `type/chore` PRs by default.
- The class-wide verification grep MUST exclude `knowledge-base/project/learnings/**`, `knowledge-base/project/plans/**`, `knowledge-base/project/specs/**`, and any `**/archive/**` path (per `2026-04-29-docs-fix-verification-greps-must-span-operator-surfaces.md` — operator-surface scope is the right default, but historical record is explicitly exempt because plans/learnings record the prior state and must not be rewritten). The literal grep is in AC §"Class-wide grep" — use exactly that invocation.

## Domain Review

**Domains relevant:** none (engineering-only refactor; no PII, auth, payment, infra-provisioning, content, or UX surface).

This is a dead-code removal that has no cross-domain implications. The brand-impact threshold is `none` (Step 2.6) and per the routing rules in `plugins/soleur/skills/brainstorm/references/brainstorm-domain-config.md` no domain leader's assessment question matches the diff:

- **CPO/Product:** no user-facing surface changes — the cc-soleur-go path has been live in prd for the entire soak window.
- **CTO/Engineering:** the architectural decision (`ADR-022-sdk-as-router.md`) is touched only to update its historical-status sentence; no new architectural decision is being made.
- **CMO/CRO/COO/CFO:** zero relevance — no growth/marketing/ops/finance surface.
- **CLO/Compliance:** zero PII/regulated-data surface — `conversation-routing.ts` reads `active_workflow` which is not PII.
- **CSO/Security:** zero new surface — the cc rate limiter (10/u/h, 30/IP/h) is moving from gated-but-100%-on to unconditional, but is functionally already 100%-on in prd today.

## Plan Phase Ordering

Per the lesson in `2026-05-10-plan-phase-order-load-bearing-when-contract-changes.md`, contract-changing edits ship before consumers. In this plan:

- **Phase 1 (contract removal):** delete `resolveInitialRouting` from `conversation-routing.ts`.
- **Phase 2 (consumer cleanup):** drop the call site and import in `ws-handler.ts`. The compiler enforces Phase 2 cannot land alone — Phase 1's deletion of the export breaks Phase 2's import path. Coupling is correct.
- **Phase 3 (registry edit):** drop FLAG_VARS entry in `feature-flags/server.ts`.
- **Phase 4 (test reshape):** rename + edit the test files.
- **Phase 5 (comment + ADR sweep):** `cc-dispatcher.ts` lines 6-10 + 419, ADR-022 line 72.

All five phases land in a single PR (atomic merge), but the per-edit order matters during `/work` to avoid intermediate red builds. Apply in the order above.

## PR Title

`chore: remove FLAG_CC_SOLEUR_GO (always-on in prod and dev)`

## PR Body (skeleton — drop into the eventual PR)

```
Closes #3270

## Summary
- Removes FLAG_CC_SOLEUR_GO from the feature-flags registry; the cc-soleur-go path has been 100% on in prd and dev for the entire soak window per ADR-022.
- Inlines resolveInitialRouting (its single consumer) as a literal `{ kind: "soleur_go_pending" }` in ws-handler.ts and deletes the helper.
- Drops the `if (ccFlagEnabled) { ... }` wrapper around the cc rate limiter — the limiter is now unconditional for every start_session.
- Reframes router-flag-stickiness.test.ts → router-stickiness-invariant.test.ts: the load-bearing invariant ("turn 2+ routing is determined by active_workflow, not by any flag") is preserved without the flag input.
- Updates two stale comments in cc-dispatcher.ts (lines 6-10, 419) and the ADR-022 status sentence.

## Out of scope
- Doppler env-var cleanup (operator-only, post-merge). Tracked as Post-merge AC.
- Rate-limiter cap retune. Not a merge blocker; will follow if Sentry shows post-deploy rate_limited spikes.

## Test plan
- bun test apps/web-platform/lib/feature-flags/server.test.ts
- bun test apps/web-platform/test/router-stickiness-invariant.test.ts
- bun run typecheck (verifies zero dangling resolveInitialRouting refs)
- git grep -F FLAG_CC_SOLEUR_GO -- ':!knowledge-base/project/learnings/**' ':!knowledge-base/project/plans/**' ':!knowledge-base/project/specs/**' ':!**/archive/**' returns zero matches

Ref #3263 (PR where Daisy surfaced the removal opportunity)
Ref ADR-022 (legacy-path retention rationale)
```
