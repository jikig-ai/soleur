---
title: "Drain Phase-4 web-platform deferred-scope-out backlog (#3331 + #3184 + #3333)"
date: 2026-06-05
type: refactor
branch: feat-one-shot-drain-p4-awp-3331-3184-3333
milestone: "Phase 4: Validate + Scale"
lane: cross-domain
closes: [3331, 3184, 3333]
pattern_pr: 2486
brand_survival_threshold: none
---

# Drain Phase-4 web-platform deferred-scope-out backlog (#3331 + #3184 + #3333)

## Enhancement Summary

**Deepened on:** 2026-06-05
**Gates passed:** 4.6 User-Brand Impact (threshold `none` + sensitive-path scope-out bullet), 4.7 Observability (5-field schema for the `createIssue` tool), 4.8 PAT-shape (no match), 4.9 UI-Wireframe (committed `.pen` produced via Pencil MCP), 4.4 Precedent-Diff.

### Key Improvements
1. **Wireframe produced** — `knowledge-base/product/design/auth/otp-code-step-wireframe.pen` committed as the design-of-record for the `OtpCodeStep` extracted surface (4.9 hard gate satisfied for the one-shot path).
2. **Observability 5-field schema** added for the `createIssue` tool (inherits `createPullRequest`'s error path 1:1; no SSH in discoverability test).
3. **Mirror test targets pinned** to exact existing files (`github-app-pr.test.ts`, `tool-tiers.test.ts`, `canusertool-tiered-gating.test.ts`, `agent-runner-tools.test.ts`, `soleur-go-runner-narration.test.ts`) — implementer mirrors, not invents.
4. **Allow-list break-risk cleared** — verified no exact-list/length/snapshot assertion on the github tool set, so adding `create_issue` to `toolNames[]` is non-breaking.
5. **Precedent-diff** for `createIssue` vs `createPullRequest` (near-verbatim; only endpoint/body/result-type differ); `issues: write` scope confirmed already granted.

### New Considerations Discovered
- #3333 end-to-end gate test (`canusertool-tiered-gating`) recommended to prove the gate *fires* (tier-map entry is a proxy, not the invariant).
- The 5 `create_pull_request`-referencing test files are parity-coverage candidates, not break-fixes.

> One PR, three closures. All three issues are `deferred-scope-out` + `code-review` + `do-not-autoclose`, on milestone **Phase 4: Validate + Scale**, scoped entirely to `apps/web-platform`. Pattern reference: **PR #2486** (one PR, multiple `Closes #N`). Closing via a real merged PR (not autoclose) is correct — the `do-not-autoclose` label is honored because `Closes #N` in a merged PR body is an explicit human-authored closure, not triage automation.

`Spec lacks valid lane:` — no spec.md exists for this branch; defaulted to `cross-domain` (three distinct surfaces: test infra + auth UI + agent tool). TR2 fail-closed.

## Overview

Three net-additive internal cleanups, independent of one another, folded into one coherent refactor PR:

- **#3331** — Extract a shared SDK fixture harness for the `soleur-go-runner-*.test.ts` files into `apps/web-platform/test/helpers/soleur-go-fixtures.ts`; backfill each runner test to import from it. **Pure refactor — every existing test must stay green.**
- **#3184** — Extract `useOtpFlow` hook + `OtpCodeStep` presentational component to kill the login/signup OTP duplication. Preserve every behavioral branch (success routes, error envelope, no-account redirect) exactly. **Existing auth tests must stay green.**
- **#3333** — Add a `createIssue` agent tool mirroring the failure-card "File an issue" affordance, gated identically to `createPr`, plus a Concierge system-prompt hint to offer issue-filing on failure-recovery turns.

The three sub-tasks share no files, so they can be implemented in any order and reviewed independently. They are bundled because all three are the *same backlog class* (Phase-4 web-platform scope-outs) and PR #2486 established the one-PR-multi-closure pattern for exactly this situation.

## Research Reconciliation — Spec vs. Codebase

The issue bodies contain several stale or imprecise claims that materially change scope. All verified against the worktree at plan time.

| Issue claim | Codebase reality | Plan response |
|---|---|---|
| #3331 names **5** runner test files (`tool-result-idle-reset, awaiting-user, interactive-prompt, lifecycle, narration`) | There are **10** `soleur-go-runner-*.test.ts` files. **8** carry duplicated helpers (`awaiting-user, tool-result-idle-reset, interactive-prompt, lifecycle, chapter-chunked, session-id-rebound, session-revoked` + the named ones). `narration` and `chapter-chunked-prompt` have **zero** local fixture helpers (system-prompt-only tests). | Scope the extraction to the **8 helper-bearing files** (grep-derived, not the issue's list). `narration` is NOT a backfill target (it imports only from `@/server/soleur-go-runner`). Per Sharp Edge "validate N at planning time by grepping the distinguishing pattern — never trust the issue's enumerated list." |
| #3331 implies the 7 helpers are identical and can be extracted verbatim | The helpers are **near-duplicates with real signature divergence**: `makeResult` is positional `(totalCostUsd, sessionId)` in most files but options-object `({totalCostUsd?, sessionId?})` in `session-id-rebound`; `duration_ms` differs (100 vs 1); `createMockQuery` has a rich scripted-stream variant (`awaiting-user`, `tool-result-idle-reset`) vs. a lean `emit/finish` variant (`lifecycle`, `session-id-rebound`); `makeEvents` returns `DispatchEvents & {...}` in some files, the lean 5-fn object in others. | The shared helper exposes **configurable supersets** (options-object signatures with defaults that reproduce each call site's current behavior), NOT a single verbatim copy. Backfill each file to the superset; only delete a local helper when the superset reproduces its exact output. Where a variant is structurally incompatible (e.g. the scripted `createMockQuery` vs the lean one), the helper exports **both** named variants. `tsc --noEmit` + full vitest run is the green gate. |
| #3184: "reduce **both pages** to thin wrappers"; login/signup logic lives in `login/page.tsx` + `signup/page.tsx` | `login/page.tsx` is **already** a 552-byte thin wrapper delegating to `components/auth/login-form.tsx` (12 KB — the real OTP logic). `signup/page.tsx` (12 KB) holds an inline `SignupForm`. | The duplication is between **`login-form.tsx` and `signup/page.tsx`'s inline `SignupForm`**, not the two `page.tsx` files. Extract the hook + component, refactor `login-form.tsx` and `SignupForm` to consume them. `login/page.tsx` is left as-is (already thin). |
| #3184: "login routes to `/dashboard`, signup to `/accept-terms`" | Confirmed: `login-form.tsx:208` → `router.push(redirectTo ?? "/dashboard")`; `signup/page.tsx:177` → `router.push(/accept-terms[?redirectTo])`. | Hook takes `onVerifySuccess` callback; login passes the `/dashboard` push, signup passes the `/accept-terms` push. Verified exact. |
| #3333: "review the auth scope before ship — write-scoped GitHub tool" | The GitHub App manifest (`apps/web-platform/infra/github-app-manifest.json:23`) **already declares `issues: write`** — bumped read→write at PR #4226 so installation-token crons can file issues. `createPullRequest` (`github-app.ts:1051`) uses the same `generateInstallationToken` path. | **No new App permission required.** `createIssue` reuses the identical auth surface as `createPr`. The write-scope review item the issue flags is satisfied: scope already provisioned, no manifest change, `github-app-manifest-parity.test.ts` stays green. |
| #3333: "permission-gate via `canUseTool` mirroring createPr" | `createPr`'s gate is NOT in `github-tools.ts`; it is the `"gated"` tier in `TOOL_TIER_MAP` (`tool-tiers.ts:48`) + a `buildGateMessage` case. The default tier is `"gated"` (fail-closed). | `createIssue` gets an explicit `"gated"` entry in `TOOL_TIER_MAP` + a `buildGateMessage` case (documents intent; the fail-closed default would already gate it, but explicit > implicit per the file's own convention). |

## User-Brand Impact

**If this lands broken, the user experiences:** (#3331) a flaky/failing CI test suite that blocks unrelated merges; (#3184) a broken sign-in or sign-up OTP flow — the single highest-stakes path for a non-technical founder (cannot get into the product at all); (#3333) the Concierge offers to file an issue but the tool 403s or files into the wrong repo.
**If this leaks, the user's data is exposed via:** N/A for #3331/#3184 (no new data surface). For #3333, the `createIssue` tool writes a `title`/`body` the user/agent supplies to the user's **own** connected repo via their own installation token — same blast radius as the existing `createPr`; no cross-tenant surface (owner/repo/installationId are closed over from the caller's workspace, never tool input).
**Brand-survival threshold:** none. Rationale: pure-internal cleanups; #3184 preserves an existing flow exactly (behavior-neutral refactor with a green-test gate); #3333 adds a gated write tool whose blast radius equals the already-shipped `createPr` and whose scope is already provisioned. No new sensitive-path surface, no new data egress.

- **threshold: none, reason:** the diff touches sensitive paths (`apps/web-platform/server/*`, `apps/web-platform/lib/auth/*`) but is behavior-neutral — #3331/#3184 are extractions with a green-test regression gate (no semantic change), and #3333 mirrors the existing `createPr` gated-write tool 1:1 (same auth surface, same `"gated"` tier, scope already provisioned at PR #4226), introducing no new data-egress, secret, or cross-tenant surface.

> Sharp Edge: a plan whose `## User-Brand Impact` section is empty, `TBD`, or omits the threshold fails `deepen-plan` Phase 4.6. Filled above. The `threshold: none, reason:` scope-out bullet is required because Files-to-Edit match the sensitive-path regex (preflight Check 6 / deepen-plan 4.6).

## Implementation Phases

### Phase 1 — #3331: Shared SDK fixture harness

**Goal:** one source of truth for the runner test fixtures; every existing test stays green.

1. Create `apps/web-platform/test/helpers/soleur-go-fixtures.ts`. It is collected by vitest's `test/**/*.test.ts` node-project glob? **No** — the helper has no `.test.ts` suffix, so it is correctly NOT collected as a suite (verified against `vitest.config.ts:44`). Import-only.
2. Move into it, as **configurable supersets**:
   - `Mutable<T>` type alias (currently local to `awaiting-user.test.ts:65`).
   - `makeAssistant(partial)` — byte-identical across `awaiting-user`/`tool-result-idle-reset`/`interactive-prompt`/`chapter-chunked`; extract verbatim.
   - `makeResult(opts: { totalCostUsd?: number; sessionId?: string | null; durationMs?: number })` — superset covering the positional form (`totalCostUsd, sessionId`) AND the options form (`session-id-rebound`). Default `durationMs` per call-site (100 vs 1) — provide both via the option; keep a thin positional adapter where a file used positional args so the diff stays minimal.
   - `makeUserToolResult(toolUseId, sessionId?)` and `makeUserToolResultReplay(...)` — currently only in `tool-result-idle-reset`; extract verbatim. (`makeUserNoToolResult` is single-use; leave local OR move it too — decide at /work by whether moving it reduces net lines.)
   - `createMockQueryScripted(scripted?)` (the rich variant: queue + `emit`/`emitError`/`finish`/`throwOnNext`) AND `createMockQueryLean(sessionId?)` (the `emit`/`finish`-only variant). Export both named; do NOT force one shape onto files that need the other.
   - `makeEvents()` — superset returning the full `DispatchEvents & { ... }` shape; lean call sites ignore the extra fields. Verify each consumer compiles.
   - `flushMicrotasks(count = 8)` — identical across files; extract verbatim.
3. Backfill the **8 helper-bearing files** to import from the helper and delete their local copies. Per file, choose the matching `createMockQuery*`/`makeResult` variant. Do NOT touch `narration.test.ts` or `chapter-chunked-prompt.test.ts`.
4. Green gate: `cd apps/web-platform && ./node_modules/.bin/vitest run test/soleur-go-runner-*.test.ts` then full `npm run test:ci` + `npm run typecheck`. Zero behavior change — every assertion that passed before passes after.

**Files to create:** `apps/web-platform/test/helpers/soleur-go-fixtures.ts`
**Files to edit:** the 8 runner test files — `apps/web-platform/test/soleur-go-runner-{awaiting-user,tool-result-idle-reset,interactive-prompt,lifecycle,chapter-chunked,session-id-rebound,session-revoked}.test.ts` (note: `narration` excluded; it has no helpers).

### Phase 2 — #3184: `useOtpFlow` hook + `OtpCodeStep` component

**Goal:** kill the OTP-flow duplication between `login-form.tsx` and `signup/page.tsx`; preserve every behavioral branch exactly.

1. Create `apps/web-platform/lib/auth/useOtpFlow.ts` exporting `useOtpFlow(opts)`:
   ```ts
   useOtpFlow({
     shouldCreateUser: boolean,         // login=false, signup=true(default-omitted)
     onVerifySuccess: () => void,       // login → router.push(redirectTo ?? "/dashboard")
                                        // signup → router.push(/accept-terms[?redirectTo])
     onSendError?: (error: AuthErrorLike) => boolean,
                                        // login passes redirectIfNoAccount (isNoAccountError →
                                        //   router.replace(/signup?...); returns true to short-circuit)
                                        // signup omits it
   })
   ```
   The hook owns: `email/otpSent/otp/error/loading/cooldownSeconds/cooldownEmail` state, `otpRef`/`cooldownTimerRef`, `cooldownActive`, `clearCooldown`/`startCooldown`/unmount cleanup effect, `sendOtp`/`handleSendOtp`/`handleResendOtp`/`handleVerifyOtp`. It calls `supabase.auth.signInWithOtp` (passing `options: { shouldCreateUser }`) and `verifyOtp`. **Preserve the `reportSilentFallback(error, { feature:"auth", op, extra:{ errorCode, errorName, status } })` envelope verbatim** at both the send and verify error sites. In `sendOtp`, after `reportSilentFallback`, call `onSendError?.(error)`; if it returns `true`, short-circuit (login's no-account redirect path). Otherwise `setError(mapSupabaseAuthError(error))`.
2. Create `apps/web-platform/components/auth/OtpCodeStep.tsx` — the `if (otpSent)` verification-code UI (the `<main>…<form onSubmit={handleVerifyOtp}>` block + resend + "Try a different email"). Props: `email, otp, setOtp, error, loading, cooldownActive, cooldownSeconds, onVerify, onResend, onTryDifferentEmail, submitLabel` (`"Sign in"` vs `"Create account"` — the only copy difference). It is a new `components/**/*.tsx` file → BLOCKING tier per the mechanical UI-surface escalation (see Domain Review). **Design-of-record wireframe:** `knowledge-base/product/design/auth/otp-code-step-wireframe.pen` — the rendered output MUST match the byte-identical existing JSX (the 5 auth tests enforce this).
3. Refactor `components/auth/login-form.tsx`: consume `useOtpFlow({ shouldCreateUser:false, onVerifySuccess:()=>router.push(redirectTo ?? "/dashboard"), onSendError: redirectIfNoAccount })` where `redirectIfNoAccount` encapsulates the `isNoAccountError` → `router.replace(/signup?...)` block (lines 142-152). Keep login-only surfaces (revoked banner, callback-error effect) in the component. Render `<OtpCodeStep submitLabel="Sign in" .../>` when `otpSent`.
4. Refactor `signup/page.tsx`'s `SignupForm`: consume `useOtpFlow({ shouldCreateUser:true, onVerifySuccess:()=>router.push(/accept-terms...) })` (no `onSendError`). Keep signup-only surfaces (T&C checkbox gate, no-account banner, OAuth-disabled-until-accepted, `tc-hint`). Render `<OtpCodeStep submitLabel="Create account" .../>`.
5. Green gate: the 5 existing auth tests MUST pass unchanged — `login-redirect-cooldown.test.tsx`, `signup-redirect-cooldown.test.tsx`, `signup-helper-hint.test.tsx`, `components/login-form-verify-error.test.tsx`, `components/login-form-revoked-banner.test.tsx`. Run `./node_modules/.bin/vitest run` on these + `npm run typecheck`. These tests exercise cooldown, redirect, helper-hint, verify-error, and revoked-banner — the exact surfaces the extraction touches.

**Files to create:** `apps/web-platform/lib/auth/useOtpFlow.ts`, `apps/web-platform/components/auth/OtpCodeStep.tsx`
**Files to edit:** `apps/web-platform/components/auth/login-form.tsx`, `apps/web-platform/app/(auth)/signup/page.tsx` (login/signup `page.tsx` wrappers untouched — login is already thin)

### Phase 3 — #3333: `createIssue` agent tool + Concierge hint

**Goal:** an agent-callable `createIssue` mirroring the failure-card affordance, gated like `createPr`.

> **Phase order:** the `createIssue` **delegate** (Phase 3a, contract producer) MUST land before the **tool** (Phase 3b, consumer) per the plan-phase-order Sharp Edge — the tool imports the delegate.

1. **3a — delegate.** Add `createIssue(installationId, owner, repo, title, body?, labels?)` to `apps/web-platform/server/github-app.ts`, mirroring `createPullRequest` exactly: `generateInstallationToken` → `githubFetch(POST ${GITHUB_API}/repos/${owner}/${repo}/issues, { body: JSON.stringify({ title, body, labels }) })` → `parseGitHubError` on `!ok` with `log.error({status, body, installationId, owner, repo})` → return `{ number, htmlUrl, url }`. Define an `IssueResult` type alongside `PullRequestResult`. **No new App scope** — `issues: write` already granted (manifest:23, parity test green).
2. **3b — tool.** Add `createIssue` tool in `apps/web-platform/server/github-tools.ts` mirroring `createPr`:
   ```ts
   tool("create_issue",
     "File an issue on the user's connected GitHub repository. The repository is determined server-side from the user's connected repo.",
     { title: z.string().describe(...),
       body: z.string().optional().describe(...),
       labels: z.array(z.string()).default([]).describe(...) },
     async (args) => wrapToolHandler("Error creating issue",
       () => createIssue(installationId, owner, repo, args.title, args.body, args.labels),
       /* pretty */ false))
   ```
   Register in `tools[]` and add `"mcp__soleur_platform__create_issue"` to `toolNames[]`.
3. **3c — gate.** Add `"mcp__soleur_platform__create_issue": "gated"` to `TOOL_TIER_MAP` in `apps/web-platform/server/tool-tiers.ts` (mirrors `create_pull_request: "gated"`). Add a `buildGateMessage` case: `` `Agent wants to file an issue: **${toolInput.title ?? "untitled"}**. Allow?` ``. (The fail-closed default already returns `"gated"`; the explicit entry documents intent per the file's own convention.)
4. **3d — Concierge hint.** Add an exported const `FAILURE_RECOVERY_FILE_ISSUE_DIRECTIVE` to `apps/web-platform/server/soleur-go-runner.ts` (same shape as `PRE_DISPATCH_NARRATION_DIRECTIVE`), instructing: on a failure-recovery turn, offer to file a GitHub issue **with the user's permission**, including the last tool label and the conversation id. Add it to the `baseline` array in `buildSoleurGoSystemPrompt` (after `GH_AUTH_STATUS_GUIDANCE_DIRECTIVE`, ~line 1161) with a `""` separator. Keep phrasing negation-free (per the file's prompt-engineering convention) and clear of punctuation boundaries for any grep-anchored substrings.
5. **3e — failure-card parity note.** `message-bubble.tsx:361-381` (`case "error"`) renders a static "File an issue" link to `…/issues/new`. This PR adds the *agent-mediated* equivalent; the static link stays. No edit to `message-bubble.tsx` is required for the tool — the file is referenced by the issue only as the affordance being mirrored. (Confirm at /work whether the directive should cite the failure-card's labels; if so it is read-only context, no component change.)
6. Tests (RED → GREEN, per `cq-write-failing-tests-before`) — exact mirror targets verified at deepen time:
   - **delegate:** add a `createIssue` block to `apps/web-platform/test/github-app-pr.test.ts` (the canonical mirror — it already mocks `fetch` + the installation-token response and tests `createPullRequest` happy/error paths). Assert POST to `/repos/{owner}/{repo}/issues` with `{title, body, labels}`, returns `{number, htmlUrl, url}`, and `log.error` + throw on `!ok`. (Or a new `github-app-issue.test.ts` with the same scaffold if co-locating in the PR test feels wrong; the scaffold is the load-bearing reuse.)
   - **tier:** extend `apps/web-platform/test/tool-tiers.test.ts` — mirror the existing `"returns gated for create_pull_request"` test for `create_issue`, and mirror the `buildGateMessage` "create PR message" test asserting the title-bearing string.
   - **registration:** the github tool surface is asserted in `apps/web-platform/test/agent-runner-tools.test.ts` (there is NO dedicated `github-tools.test.ts`). Add a `create_issue` assertion alongside the `create_pull_request` ones.
   - **end-to-end gating (optional but recommended):** `apps/web-platform/test/canusertool-tiered-gating.test.ts` has a `"create_pull_request triggers review gate"` test — a sibling `create_issue` test proves the gate actually fires for the new tool, not just that the tier map says `"gated"` (proxy-vs-invariant: tier-map entry ≠ gate-fires).
   - **directive:** assert `FAILURE_RECOVERY_FILE_ISSUE_DIRECTIVE` is a non-empty string and `buildSoleurGoSystemPrompt()` embeds it (template: `apps/web-platform/test/soleur-go-runner-narration.test.ts`).

   **Allow-list note (`cq-union-widening-grep-three-patterns`):** 5 test files reference `create_pull_request` (`agent-runner-tools`, `tool-tiers`, `agent-runner-kb-share-tools`, `canusertool-tiered-gating`, `canusertool-decisions`). Verified at deepen time: **none uses exact-array-equality, `toHaveLength`, or a snapshot on the tool set** — all use `toContain`/`not.toContain`/individual-tool calls. So adding `create_issue` to `toolNames[]` does NOT break them. Adding a `create_issue` sibling assertion is parity coverage, not a break-fix; do it for the tier + registration + gating files above, skip the others.

**Files to create:** none required beyond optional new test files — the mirror tests extend existing files (see test list). If a new delegate test file is preferred: `apps/web-platform/test/github-app-issue.test.ts` (scaffold copied from `github-app-pr.test.ts`).
**Files to edit:** `apps/web-platform/server/github-app.ts`, `apps/web-platform/server/github-tools.ts`, `apps/web-platform/server/tool-tiers.ts`, `apps/web-platform/server/soleur-go-runner.ts`; tests — `apps/web-platform/test/github-app-pr.test.ts` (or new issue test), `apps/web-platform/test/tool-tiers.test.ts`, `apps/web-platform/test/agent-runner-tools.test.ts`, `apps/web-platform/test/canusertool-tiered-gating.test.ts`, `apps/web-platform/test/soleur-go-runner-narration.test.ts` (or a new `soleur-go-runner-file-issue-directive.test.ts`). `message-bubble.tsx` is NOT edited (the static failure-card link stays).

## Acceptance Criteria

### Pre-merge (PR)

- **AC1 (#3331):** `apps/web-platform/test/helpers/soleur-go-fixtures.ts` exists and exports `makeAssistant`, `makeResult`, `makeUserToolResult`, `makeUserToolResultReplay`, `flushMicrotasks`, the `createMockQuery*` variant(s), `makeEvents`, and `Mutable`. The 8 helper-bearing runner test files import from it; `grep -L "from \"./helpers/soleur-go-fixtures\"" $(grep -rln "function createMockQuery\|function makeEvents" apps/web-platform/test/soleur-go-runner-*.test.ts)` returns empty (every file that still defines a local helper is intentional — only `narration`/`chapter-chunked-prompt`, which define none).
- **AC2 (#3331):** `cd apps/web-platform && ./node_modules/.bin/vitest run test/soleur-go-runner-*.test.ts` is fully green with the same test count as before the change (no test deleted, no `.skip` added).
- **AC3 (#3184):** `apps/web-platform/lib/auth/useOtpFlow.ts` and `apps/web-platform/components/auth/OtpCodeStep.tsx` exist. `login-form.tsx` and `signup/page.tsx`'s `SignupForm` both consume `useOtpFlow`; neither file contains a duplicate `sendOtp`/`handleVerifyOtp`/`startCooldown` definition (`grep -c "async function sendOtp" apps/web-platform/components/auth/login-form.tsx apps/web-platform/app/\(auth\)/signup/page.tsx` returns 0 for both).
- **AC4 (#3184):** the 5 existing auth tests pass unchanged: `./node_modules/.bin/vitest run test/login-redirect-cooldown.test.tsx test/signup-redirect-cooldown.test.tsx test/signup-helper-hint.test.tsx test/components/login-form-verify-error.test.tsx test/components/login-form-revoked-banner.test.tsx`. The `reportSilentFallback` envelope (`feature:"auth"`, `op`, `extra:{errorCode,errorName,status}`) is present at both send and verify error sites in the hook (`grep -c "reportSilentFallback" apps/web-platform/lib/auth/useOtpFlow.ts` ≥ 2). Login verify-success routes to `/dashboard`; signup to `/accept-terms`; login `onSendError` performs the `isNoAccountError` → `/signup` replace.
- **AC5 (#3333):** `getToolTier("mcp__soleur_platform__create_issue") === "gated"`; `create_issue` is in `buildGithubTools().toolNames`; `buildSoleurGoSystemPrompt()` contains `FAILURE_RECOVERY_FILE_ISSUE_DIRECTIVE`. New unit tests for all three pass.
- **AC6 (#3333):** `github-app-manifest-parity.test.ts` stays green (no manifest change; `issues: write` already present). `createIssue` delegate POSTs to `/repos/{owner}/{repo}/issues` with `{title, body, labels}` and returns `{number, htmlUrl, url}`.
- **AC7 (whole PR):** `cd apps/web-platform && npm run typecheck && npm run test:ci` is fully green. `npm run lint` clean.
- **AC8 (PR body):** contains `Closes #3331`, `Closes #3184`, `Closes #3333` (in the body, not the title, per `wg-use-closes-n-in-pr-body-not-title-to`). Milestone "Phase 4: Validate + Scale" set on the PR. References PR #2486 as the pattern.

### Post-merge (operator)

- None. `Closes #N` in the merged PR body closes all three issues automatically (correct here — these are real human-authored closures, which `do-not-autoclose` permits; the label only blocks triage-automation autoclose). No infra apply, no migration, no external-service config.

## Open Code-Review Overlap

3 open scope-outs touch these files — they ARE the three target issues (#3331 → `test/helpers/soleur-go-fixtures`; #3184 → `(auth)/login`, `(auth)/signup`, `useOtpFlow`, `OtpCodeStep`; #3333 → `github-tools.ts`, `message-bubble.tsx`). All three are **folded in** (closed by this PR).

One tangential match: **#2246** mentions `github-app.ts` — but only as a candidate destination for a `parseOwnerRepo` extraction (a KB-route-helper consolidation). It does not overlap the `createIssue` delegate addition. Disposition: **Acknowledge** — different concern, needs its own cycle, remains open.

## Domain Review

**Domains relevant:** Product (UI surface — auth components).

### Product/UX Gate

**Tier:** blocking (mechanical UI-surface escalation: `apps/web-platform/components/auth/OtpCodeStep.tsx` is a new `components/**/*.tsx` file; `signup/page.tsx` matches `app/**/page.tsx`)
**Decision:** reviewed — wireframe produced (pipeline path)
**Agents invoked:** ux-design-lead (wireframe producer, via Pencil MCP)
**Skipped specialists:** none
**Pencil available:** yes (Node v22.22.1; `PENCIL_CLI_KEY` from Doppler `soleur/dev`; Pencil MCP live)

**Wireframe (committed):** `knowledge-base/product/design/auth/otp-code-step-wireframe.pen` (verified non-empty + tracked). It captures the `OtpCodeStep` extracted surface — heading, email subtext, 6-digit code input, the submit button (label varies: login `"Sign in"` / signup `"Create account"`), resend, and "Try a different email". Screenshot of record: `knowledge-base/product/design/auth/screenshots/0ikEc-*.png`.

This is a **behavior-neutral extraction**: `OtpCodeStep` renders the byte-identical verification-code JSX that already ships in `login-form.tsx:212-272` and `signup/page.tsx:185-246` — no new visual surface, no new flow, no new copy beyond the existing submit-label difference. The wireframe is therefore the design-of-record for the surface being componentized, not a new design. The existing 5 auth tests (AC4) are the visual-regression guard: they assert the rendered output is unchanged.

## Observability

The only new runtime surface is #3333's `createIssue` delegate + tool. It inherits the **exact** observability of `createPullRequest` (`github-app.ts:1051`): on GitHub API failure it calls `log.error({status, body, installationId, owner, repo}, "Failed to create issue")` and throws through `wrapToolHandler`'s `isError` envelope (the same `parseGitHubError` path), surfacing to the agent and to pino/Sentry identically to every other github-tool. #3331 (test infra) and #3184 (behavior-neutral UI extraction) add no server runtime surface. The 5-field schema below is scoped to the `createIssue` tool (the only production-code addition).

```yaml
liveness_signal:
  what: createIssue tool invocations succeed (HTTP 201 from POST /repos/{owner}/{repo}/issues)
  cadence: on-demand (agent-driven, per failure-recovery turn the user authorizes)
  alert_target: none required — the tool is a user-authorized write, not a background service; failures surface synchronously to the agent + user via the isError tool response
  configured_in: apps/web-platform/server/github-tools.ts (wrapToolHandler isError envelope) + apps/web-platform/server/github-app.ts (log.error on !response.ok)
error_reporting:
  destination: pino structured log (log.error) + Sentry via the existing agent-runner exception path (same as createPullRequest)
  fail_loud: true — wrapToolHandler returns { isError: true, content:[{text:"Error creating issue: <message>"}] }; the agent sees the failure and relays it to the user. No silent fallback.
failure_modes:
  - mode: GitHub API rejects the create (422 validation, 403 scope, 404 repo)
    detection: response.ok === false in createIssue delegate
    alert_route: log.error({status, body, installationId, owner, repo}) → pino → Sentry; surfaced to agent via thrown Error → wrapToolHandler isError
  - mode: installation token generation fails (auth)
    detection: generateInstallationToken throws (shared path with createPr)
    alert_route: same wrapToolHandler isError envelope + existing token-error Sentry breadcrumbs
  - mode: user denies the review-gate permission prompt (expected, not an error)
    detection: canUseTool / review-gate returns deny for the gated tool
    alert_route: none — denial is a normal user choice; the agent receives a permission-denied result and continues
logs:
  where: pino (stdout, shipped to Better Stack via the existing web-platform log pipeline) + Sentry for thrown exceptions
  retention: per the existing web-platform log/Sentry retention (no new sink introduced)
discoverability_test:
  command: "grep -E 'create_issue' <(cd apps/web-platform && node -e \"const {buildGithubTools}=require('./dist/...');\") || rg 'mcp__soleur_platform__create_issue' apps/web-platform/server/tool-tiers.ts apps/web-platform/server/github-tools.ts"
  expected_output: create_issue present in toolNames and TOOL_TIER_MAP as \"gated\" — verifiable without ssh, by grepping the registered tool surface; runtime verification is the unit tests in AC5 (no live GitHub call needed to prove the tool is wired)
```

## Risks & Mitigations

- **#3331 signature divergence (highest risk):** a naive verbatim extraction breaks `tsc` (options-vs-positional `makeResult`) or changes runtime (`duration_ms` 100→1). Mitigation: configurable supersets with per-call-site defaults; both `createMockQuery*` variants exported; `tsc --noEmit` + full vitest run as the gate. Precedent: PR #2486 extracted shared test mocks the same way.
- **#3184 behavioral drift:** the hook must reproduce login's no-account redirect (`isNoAccountError` → `router.replace`), the per-email cooldown reset-bypass guard, and the distinct success routes. Mitigation: the 5 existing auth tests are the regression net (AC4); preserve the `reportSilentFallback` envelope verbatim. Risk that a test was written against the *old* file structure and references internals — verify at /work that the tests assert behavior (rendered output, router calls), not implementation.
- **#3333 gate bypass:** if `createIssue` is omitted from `TOOL_TIER_MAP`, the fail-closed default (`"gated"`) still gates it — but the explicit entry + `buildGateMessage` case are required for a useful confirmation prompt. Mitigation: AC5 asserts the tier explicitly. The write scope is already provisioned (`issues: write`) — no manifest/Terraform change, so no infra-apply risk.

## Research Insights (deepen-plan)

### Precedent-Diff Gate (Phase 4.4) — pattern-bound behaviors

**#3333 `createIssue` delegate vs `createPullRequest` (`github-app.ts:1051-1110`):** the new delegate is a near-verbatim mirror. Side-by-side:

| Aspect | `createPullRequest` (precedent) | `createIssue` (this PR) |
|---|---|---|
| auth | `generateInstallationToken(installationId)` | identical |
| endpoint | `POST ${GITHUB_API}/repos/${owner}/${repo}/pulls` | `POST .../repos/${owner}/${repo}/issues` |
| body | `{ head, base, title, body }` | `{ title, body, labels }` |
| error | `parseGitHubError` + `log.error({status, body, installationId, owner, repo})` + throw | identical (message: `"Failed to create issue"`) |
| return | `{ number, htmlUrl, url }` from `data.number/html_url/url` | identical → define `IssueResult` alongside `PullRequestResult` (`github-app.ts:32`) |
| App scope | `pull_requests: write` (manifest) | `issues: write` (manifest:23 — ALREADY granted, PR #4226) |

No novel pattern; the only divergences are the endpoint path, the request body keys, and the result type name. This is the lowest-risk shape for a new write tool.

**#3331 fixture extraction vs PR #2486 (`refactor(kb): … shared test mocks`):** #2486 is the direct precedent — it extracted shared test mocks into a helper and backfilled consumers. The configurable-superset approach (vs verbatim copy) is the lesson from the signature-divergence reality documented in Research Reconciliation. No novel pattern.

**#3184 hook extraction:** standard React custom-hook extraction; no security/atomicity primitive. The precedent is any `lib/auth/*` or `components/auth/use-sign-out.ts` hook already in the tree. The load-bearing constraint is behavioral preservation, enforced by the 5 existing auth tests — not a pattern-correctness question.

### Implementation realism (verified at deepen time)

- **Mirror test scaffolds confirmed present:** `github-app-pr.test.ts` (mock fetch + token), `tool-tiers.test.ts` (`returns gated for create_pull_request` + `buildGateMessage` tests), `canusertool-tiered-gating.test.ts` (`create_pull_request triggers review gate`), `agent-runner-tools.test.ts` (tool registration), `soleur-go-runner-narration.test.ts` (directive embed). The implementer mirrors these, not invents.
- **No exact-list/length/snapshot assertion** exists on the github tool set (grep verified), so adding `create_issue` to `toolNames[]` is non-breaking to the 5 enumerating test files.
- **Negative claims verified:** `issues: write` present at `github-app-manifest.json:23` (confirms "no new scope"); `create_issue`/`createIssue` absent from `github-tools.ts`/`tool-tiers.ts` (confirms net-additive).
- **`narration.test.ts` / `chapter-chunked-prompt.test.ts` define zero fixture helpers** (grep count 0) — confirmed NOT #3331 backfill targets.

## Alternative Approaches Considered

| Approach | Why not |
|---|---|
| Three separate PRs | Defeats the purpose — these are the same backlog class; PR #2486 established one-PR-multi-closure for exactly this. One PR, one review pass, one merge. |
| #3331: extract verbatim, force one `createMockQuery` shape | Breaks the files needing the other shape; would require rewriting passing tests (scope creep, regression risk). Supersets keep every test green. |
| #3333: add a new GitHub App scope for issues | Unnecessary — `issues: write` already granted at PR #4226. Adding scope would force a re-consent flow and a manifest-parity-test change for zero benefit. |
| #3333: auto-approve tier (like `edit_c4_diagram`) | No — `createIssue` is a public write to the user's repo with agent-supplied body; mirrors `createPr`'s `"gated"` exactly. The issue explicitly requires permission-gating. |

## Sharp Edges

- `narration.test.ts` and `chapter-chunked-prompt.test.ts` are NOT #3331 backfill targets — they define zero local fixture helpers (system-prompt-only tests). Editing them would be churn with no extraction.
- `login/page.tsx` is already a thin wrapper — the #3184 work is in `login-form.tsx`, NOT `login/page.tsx`. Do not "thin out" a file that's already thin.
- New helper file `soleur-go-fixtures.ts` must NOT carry a `.test.ts` suffix (would be collected as an empty suite by vitest's `test/**/*.test.ts` glob → "no tests" failure).
- Web-platform tests run under **vitest**, not bun (`bunfig.toml` blocks bun test discovery; `package.json scripts.test = "vitest"`). Use `./node_modules/.bin/vitest run <path>`. Component tests (`.test.tsx`) must live under `test/` (happy-dom project glob `test/**/*.test.tsx`), not co-located.
- The `createIssue` delegate must reuse `generateInstallationToken` + `githubFetch` + `parseGitHubError` — do NOT hand-roll a new fetch; the shared error path is what gives it observability parity with `createPr`.

## Plan Provenance

All file paths, line numbers, symbol names, and the `issues: write` scope were verified against the worktree at plan time (2026-06-05). Premise validation: all three issues OPEN with the expected labels/milestone; #2486 MERGED. No external research (strong local patterns, no new security surface — write scope already provisioned and reviewed).
