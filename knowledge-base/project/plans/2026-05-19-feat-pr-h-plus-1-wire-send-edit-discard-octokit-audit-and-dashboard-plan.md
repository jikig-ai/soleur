---
title: "PR-H+1: Wire send/edit/discard buttons + per-Octokit audit writer + /dashboard/audit/github surface"
issue: 4098
branch: feat-one-shot-pr-h-plus-1-4098
pr: 4100
lane: cross-domain
brand_survival_threshold: single-user-incident
requires_cpo_signoff: true
created: 2026-05-19
status: draft
depends_on:
  - "#4066"  # PR-H — Daily Priorities multi-source (introduces audit_github_token_use, record_github_token_use, github-on-event.ts, redactGithubSourcedText)
  - "#4065"  # PR-H' trust-tier — introduces action_sends WORM ledger + anonymise_action_sends RPC
  - "#3947"  # PR-G — introduces today-card stub, scope-grants UI, audit page precedent
---

# PR-H+1: Wire send/edit/discard buttons + per-Octokit audit writer + /dashboard/audit/github surface

## Enhancement Summary

**Deepened on:** 2026-05-19
**Sections enhanced:** Overview, Research Reconciliation, Phase 0, Phase 1-5, Acceptance Criteria, Risks, Sharp Edges
**Research agents used:** repo-research (inline), learnings-researcher (inline), framework-docs (inline — Octokit/fetch/Next.js), pattern-recognition (inline — modal precedent), code-quality (inline — AGENTS.md citation gate), kieran-rails-reviewer (inline — single-write-boundary pattern), git-history-analyzer (inline — sibling-PR state probe), user-impact-reviewer (inline — single-user-incident framing)

### Key Improvements

1. **The "per-Octokit-call audit writer" wording is paraphrase.** `apps/web-platform/server/github-api.ts` and `github-app.ts` use raw `fetch()` (no `@octokit/*` dependency in `apps/web-platform/package.json`). The instrumentation surface is `fetchWithRetry()` at `github-api.ts:56` (or PR-H's `server/github/app-client.ts` per-request factory if that name differs post-rebase). The plan now prescribes a `recordGithubApiCall(...)` wrapper around the response handler — NOT an Octokit `after` hook.
2. **The WORM-trigger `current_user = 'service_role'` bypass is broken under PostgREST routing** (`knowledge-base/project/learnings/2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-routing.md`). PR-H+1 does NOT introduce a new WORM table, but it consumes `action_sends` from #4065 via `writeActionSend(...)`. Phase 0 must verify the `action_sends` trigger bypass uses the GUC-only (not role-check) mechanism, OR the `writeActionSend` boundary is exercised live (not mock-only) by at least one integration test.
3. **Modal precedent locked.** `apps/web-platform/components/auth/sign-out-confirm-modal.tsx` is the canonical focus-trap + Escape-to-close + restore-trigger-focus precedent. `TypedConfirmModal` mirrors this verbatim — same `useRef`, same `keydown` handler, same `:disabled` filter on the focusable selector.
4. **Migration-mandates-without-wired-call-sites class** (`2026-05-16-migration-mandates-must-have-wired-call-sites-in-same-pr.md`) applies symmetrically here: this PR mandates that *every* Octokit call site writes through the audit RPC. AC must include a sentinel sweep — `git grep` for direct `fetch("https://api.github.com")` calls that bypass the wrapper — not just verify the wrapper itself works.
5. **Foundations-PR-must-not-declare-downstream-contracts** (`2026-05-07-foundations-pr-must-not-declare-downstream-contracts.md`) inverted: PR-H+1 is the *consumer* of foundations declared by #4066 and #4065. Phase 0 reconciliation is the inversion — if foundations aren't on `main`, the consumer is unreachable.
6. **AGENTS.md rule citations verified live.** All 8 cited rule IDs in this plan (`hr-write-boundary-sentinel-sweep-all-write-sites`, `hr-dev-prd-distinct-supabase-projects`, `cq-silent-fallback-must-mirror-to-sentry`, `cq-nextjs-route-files-http-only-exports`, `wg-use-closes-n-in-pr-body-not-title-to`, `hr-weigh-every-decision-against-target-user-impact`, `hr-gdpr-gate-on-regulated-data-surfaces`, `wg-after-a-pr-merges-to-main-verify-all`) resolve to active rules in `AGENTS.md`. No retired or fabricated citations.
7. **Type-widening cascade signal** (`2026-05-12-type-widening-cascades-and-write-boundary-sentinels.md`) applies if `writeActionSend(...)` accepts a discriminated union over `{kind: "send" | "edit" | "discard"}`. The plan now prescribes per-variant typed payloads (no `payload: unknown`).

### New Considerations Discovered

- The `record_github_token_use` RPC's `REVOKE … GRANT service_role` posture is identical to the WORM-bypass posture; if the RPC is mock-only in CI, the live PostgREST path is never exercised. **Integration test against DEV Supabase is non-negotiable** (per the learning's "every SECURITY DEFINER RPC … MUST be exercised by a live integration test" rule).
- The today-card flip from server-component-stub to `"use client"` cascades: any server-only import (`@/lib/supabase/server`, `headers()`, secrets) must move to the parent route. Verified via the sibling `runtime-explainer-banner.tsx` / `foundation-cards.tsx` precedent which already runs `"use client"`.
- Per the `2026-04-22 paraphrase-without-verification` learning, "Octokit" in the issue body is the paraphrase that survived past brainstorm. Reality check: zero Octokit imports anywhere in `apps/web-platform/`. The plan now uses "GitHub API call" terminology with `fetchWithRetry()` as the canonical wrap site.

## Overview

Follow-up to PR-H (#3244, currently in flight via PR #4066). Captures the three deferred items called out in the multi-agent review of #4066:

1. Activate the `Send` / `Edit` / `Discard` buttons on `components/dashboard/today-card.tsx` (currently rendered `disabled aria-disabled="true"`).
2. Replace the `byok-audit-writer-sweep: out-of-scope` stub at the per-Octokit-call site in `server/inngest/functions/github-on-event.ts` with an actual writer that calls the `record_github_token_use` RPC after every Octokit response.
3. Ship `/dashboard/audit/github` — a founder-facing read-only viewer for `audit_github_token_use`.

This plan is for **PR-H+1**. Three sibling PRs (#4066 PR-H, #4065 PR-H' trust-tier, #3947 PR-G) are still **OPEN** on origin. The branch `feat-one-shot-pr-h-plus-1-4098` was branched from `main` and currently contains NONE of the load-bearing surfaces this plan extends. Reconciliation is mandatory before `/work` (see "Research Reconciliation — Spec vs. Codebase" below).

## Research Reconciliation — Spec vs. Codebase

The issue body paraphrases artifacts that exist on sibling branches but not on `main`. Phase 0 of `/work` MUST rebase this branch onto the final merged state of #4066 + #4065 (in that order) — or the plan is unimplementable. Cheapest gate: `git ls-files apps/web-platform/supabase/migrations/ | grep -E '^051'` returns nothing as of plan-draft time.

| Spec/issue claim | Reality on `main` @ HEAD | Plan response |
|---|---|---|
| `server/action-sends/write-action-send.ts` exists as single write boundary | Directory does NOT exist; `find apps/web-platform/server -name "*action-send*"` returns 0 hits | Plan PRESUMES PR #4065 (trust-tier + WORM `action_sends`) lands first; Phase 0 rebase gates `/work` start |
| `server/inngest/functions/github-on-event.ts` exists with BYOK-out-of-scope stub | File does NOT exist; `find . -name "github-on-event.ts"` returns 0 hits | Plan PRESUMES PR #4066 lands first; Phase 0 rebase gates `/work` start |
| Migration 051 + `audit_github_token_use` + `record_github_token_use` RPC | Most recent migration is `050_runtime_mint_hook_intent_gate.sql`; no GitHub audit migration | Same — depends on #4066 |
| `anonymise_action_sends` RPC for WORM replica-mode bypass | RPC does NOT exist on main; lives on #4065 | Same — depends on #4065 |
| `today-card.tsx` buttons say `"Wires in PR-H+1"` | Buttons say `"Wires in PR-G (#3947)"` (current `main` is at PR-G stub) | The handoff label drifts as upstream merges; plan keeps phase scope focused on flipping `disabled → enabled` + wiring handlers regardless of stub label |
| `today-card.tsx` has the trust-tier-aware variants (stripe / github / cfo / kb-drift) | Today-card has only one path (stripe-style; 5 props: id, source, owningDomain, draftPreview, urgency) | The source-aware variants land in PR-H #4066; this plan only adds click handlers + `approve_every_time` modal — no source-variant logic |
| `isGranted(supabase, founderId, actionClass)` available | EXISTS at `apps/web-platform/server/scope-grants/is-granted.ts:25` (PR-G stub merged on a sibling, but the file is on main) | ✓ usable — but note signature returns `Promise<ActiveGrant | null>` with `{tier: ActionClassTier}` — must be called from a server route with service-role client |
| `runWithByokLease(userId, fn)` available | EXISTS at `apps/web-platform/server/byok-lease.ts:213` | ✓ usable |
| `audit/page.tsx` precedent | EXISTS at `apps/web-platform/app/(dashboard)/dashboard/audit/page.tsx` (BYOK + Inngest sections) | ✓ usable as precedent for the new `/dashboard/audit/github/page.tsx` |

**Phase 0 hard gate:** before any TR/FR code lands, the work skill MUST verify both #4066 and #4065 are merged to `main` (or have a deterministic rebase target). If either is still open, halt and report. Per `wg-after-a-pr-merges-to-main-verify-all` and the foundations-PR learning (`2026-05-07-foundations-pr-must-not-declare-downstream-contracts.md`), this PR's contracts (write-action-send boundary, `record_github_token_use` consumer, `audit_github_token_use` reader) all consume contracts declared upstream — atomic-delivery alignment is load-bearing.

## User-Brand Impact

**If this lands broken, the user experiences:** a `Send` button that fires without (a) re-checking the cookie-scoped scope grant at click time, (b) re-validating the typed-SEND token server-side for `approve_every_time` tier, or (c) writing through the WORM `action_sends` boundary — producing one of three concrete failure shapes:
1. A founder clicks `Send` after revoking the relevant action-class grant from another tab; the request fires anyway because the client cached the old grant. The customer receives a message the founder explicitly un-approved.
2. A founder types `send` (lowercase) into the verbatim-`SEND` modal; the server `.trim().toLowerCase()` the input and accepts it; the founder believed the modal would reject anything not literally `SEND`.
3. A founder clicks `Send` on a `finance.payment_failed` draft; the write succeeds, but the per-Octokit audit writer's call to `record_github_token_use` silently fails (RPC returns error, dropped on the floor) — and the `/dashboard/audit/github` ledger renders no row. The founder's Article 30 PA-16 disclosure of "every GitHub call is logged" is now false.

**If this leaks, the user's workflow is exposed via:** the `audit_github_token_use` ledger leaking across tenants if the route's `.eq("founder_id", user.id)` is dropped or if RLS regresses. The PR-H ledger contains `installation_id`, `repo_full_name`, `endpoint`, and timestamp — repository names disclose the founder's customer roster and engineering velocity.

**Brand-survival threshold:** single-user incident

CPO sign-off required at plan time before `/work` begins. CPO was invoked at brainstorm time for PR-H (#4066); this plan inherits the threshold and the framing rather than re-asking. `user-impact-reviewer` runs at PR-review time.

## Open Code-Review Overlap

Per Phase 1.7.5, query open code-review issues against the planned `## Files to Edit` paths:

```bash
gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json
jq -r --arg path "today-card.tsx" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json
jq -r --arg path "audit_github_token_use" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json
jq -r --arg path "record_github_token_use" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json
jq -r --arg path "write-action-send" '.[] | select(.body // "" | contains($path)) | "#\(.number): \(.title)"' /tmp/open-review-issues.json
```

Result at plan-draft time: **None.** Phase 0 of `/work` re-runs these queries on the rebased branch and reconciles fresh matches.

## Domain Review

**Domains relevant:** Engineering, Security/Compliance, Product/UX

### Engineering

**Status:** reviewed (inline)
**Assessment:** Three surfaces have load-bearing single-write-boundary invariants (`write-action-send.ts` for sends, `record_github_token_use` RPC for Octokit audits, `audit_github_token_use` RLS for reads). Per `hr-write-boundary-sentinel-sweep-all-write-sites`, every code path that creates `action_sends` rows or `audit_github_token_use` rows MUST route through the canonical helper. New direct INSERTs are a workflow violation.

### Security/Compliance

**Status:** reviewed (inline)
**Assessment:** Three concerns:
1. Approval signature MUST be canonical-JSON over ordered keys (`{founder_id, message_id, typed_value, ts}`) — `JSON.stringify` of an object with non-deterministic key order produces signature drift. Use `orderedKeys()` helper from `lib/canonical-json/` if it exists; otherwise inline `JSON.stringify({...}, Object.keys({...}).sort())`.
2. `record_github_token_use` is `REVOKE FROM PUBLIC, anon, authenticated; GRANT TO service_role`. The Inngest function path is service-role context — ✓. But fail-mode is "audit row not written" — non-blocking per issue body. AC must distinguish "audit failure must be Sentry-mirrored" (`cq-silent-fallback-must-mirror-to-sentry`) from "audit failure must NOT block the agent action".
3. Typed-SEND verbatim — issue body explicitly bans `.trim()` / `.normalize()` (Kieran P2-7 from PR-H review). Server-side re-validation must compare `typed_value === "SEND"` byte-for-byte.

### Product/UX Gate

**Tier:** advisory (modifies an existing user-facing component; does not add a new page route beyond `/dashboard/audit/github` which mirrors an existing precedent at `/dashboard/audit/`)

**Mechanical escalation check:** Files to create includes `app/(dashboard)/dashboard/audit/github/page.tsx` which matches `app/**/page.tsx` → BLOCKING per the mechanical rule.

**Decision:** auto-accepted (pipeline) — pipeline mode per the SKILL contract; UX precedent is the existing `/dashboard/audit/page.tsx` which the new route mirrors. Wireframes would not change the structure (same table-of-rows shape).

**Agents invoked:** none (pipeline auto-accept)
**Skipped specialists:** ux-design-lead (pipeline auto-accept; new page mirrors precedent), copywriter (no new external prose beyond empty-state copy borrowed from existing audit page)
**Pencil available:** N/A

#### Findings

Empty-state copy for the new page: "Your GitHub audit ledger populates as Soleur uses your GitHub App to read or write on your behalf. No calls yet." (Mirrors the brand voice in the existing audit page's "Every Soleur run, every BYOK call. You decide. Agents execute. The ledger is the record.")

## Infrastructure (IaC)

**Skip:** this plan introduces no new infrastructure. All new code paths consume existing infrastructure landing in #4066 (migration 051 + `audit_github_token_use` + RPC) and #4065 (WORM `action_sends` + `anonymise_action_sends` RPC). The new `/dashboard/audit/github` route is a Next.js server component — no Terraform changes.

## Acceptance Criteria

### Pre-merge (PR)

- [ ] **AC1 — Phase-0 rebase gate.** `git log origin/main..HEAD --oneline` includes commits referencing #4066 (or #4066 is merged into `main` and the branch rebased onto `main`); same for #4065. If either is open, halt.
- [ ] **AC2 — Send/Edit/Discard handlers wired.** `today-card.tsx` no longer renders `disabled aria-disabled="true"` on the three buttons. Each button has an `onClick` handler that routes through the corresponding server boundary.
- [ ] **AC3 — Click-time grant re-check.** Every server route handling Send / Edit / Discard calls `isGranted(serviceClient, founderId, actionClass)` BEFORE invoking the write boundary. On `null` return, route responds `409 GrantRevoked` and does NOT write to `action_sends`. Verified by a unit test that revokes a grant between page-load and click.
- [ ] **AC4 — Typed-SEND verbatim modal.** For `approve_every_time` tier, the client renders a modal that requires typing the exact string `SEND` (no normalisation). Server-side re-validation uses byte-equality (`typed_value === "SEND"`). Test fixtures include `send`, ` SEND`, `SEND `, `SEND\n`, `ＳＥＮＤ` (fullwidth) — all rejected as `400 TypedValueMismatch`.
- [ ] **AC5 — Canonical approval signature.** Server computes `sha256(JSON.stringify({founder_id, message_id, ts, typed_value}, ["founder_id", "message_id", "ts", "typed_value"]))` (alphabetised key list, explicit array form to lock order) and persists with the row. Verified by a test that mutates key order in the input and asserts identical signature output.
- [ ] **AC6 — Single write boundary (`write-action-send.ts`).** `git grep -nE "from\(\"action_sends\"\)\.insert" apps/web-platform/` returns matches ONLY inside `server/action-sends/write-action-send.ts`. Every other code path that needs to write `action_sends` calls the helper. Per `hr-write-boundary-sentinel-sweep-all-write-sites`.
- [ ] **AC7 — Per-Octokit audit writer wired.** `github-on-event.ts` wraps every Octokit response with `await serviceClient.rpc("record_github_token_use", {...})`. Verified by an integration test that fires a synthetic webhook → asserts one `audit_github_token_use` row per Octokit call (counted by hooking the Octokit `after` hook).
- [ ] **AC8 — Audit-write failure is non-blocking + Sentry-mirrored.** If the RPC returns an error, the Inngest function continues; the error is captured via `Sentry.captureException(err, { tags: { surface: "github-audit-writer", endpoint: "<endpoint>" }})`. Verified by a test that mocks the RPC to throw and asserts both (a) the agent step completes and (b) `Sentry.captureException` was called. Per `cq-silent-fallback-must-mirror-to-sentry`.
- [ ] **AC9 — `/dashboard/audit/github` route.** New page at `apps/web-platform/app/(dashboard)/dashboard/audit/github/page.tsx`. Server component. Cookie-scoped Supabase client. `.eq("founder_id", user.id)` belt-and-suspenders filter. `.order("ts", { ascending: false }).limit(50)`. Columns: `installation_id`, `repo_full_name`, `endpoint`, `ts`, `response_status`.
- [ ] **AC10 — Empty state copy.** When the ledger is empty, the page renders the exact string: `"Your GitHub audit ledger populates as Soleur uses your GitHub App to read or write on your behalf. No calls yet."`
- [ ] **AC11 — Article 30 PA-16 TOM-#10 caveat removed.** `git grep -nE "TOM-#10|record_github_token_use no longer ships unpopulated|unpopulated"` against `knowledge-base/legal/` returns the amendment in this PR (text removed from canonical + plugins/soleur mirror — same convention as PR-H Phase 7).
- [ ] **AC12 — All three actions persist + 200 in <500ms p95.** Integration test fires 100 requests against the local dev server; p95 is computed from response times; passes if `p95 < 500ms`. Per issue acceptance criteria.
- [ ] **AC13 — Wrapping inside `runWithByokLease`.** `git grep -nE "record_github_token_use" apps/web-platform/server/inngest/functions/github-on-event.ts` lands inside a function body where the surrounding scope is established by `runWithByokLease(...)`. Verified by an AST or grep-based test.
- [ ] **AC14 — Production-synthetic-user gate.** No integration test creates synthetic `auth.users`, `action_sends`, or `audit_github_token_use` rows against PROD Supabase. Test scope is DEV-only per `hr-dev-prd-distinct-supabase-projects`. Verified by `grep -E "SUPABASE_URL|NEXT_PUBLIC_SUPABASE_URL" test/server/` matches DEV URL pattern only.
- [ ] **AC15 — GitHub-API-call wrapper sentinel sweep.** `git grep -nE "fetch\(.*api\.github\.com" apps/web-platform/server/` returns matches ONLY inside the wrapped helper file(s) (`server/github/app-client.ts` if PR-H ships that, else `server/github-api.ts` / `server/github-app.ts`). No direct `fetch("https://api.github.com/...")` exists outside the wrapper. Per `hr-write-boundary-sentinel-sweep-all-write-sites` applied to the audit-write surface.
- [ ] **AC16 — Live-PostgREST RPC integration test.** `test/server/inngest/github-on-event-audit-writer.test.ts` calls `record_github_token_use` against DEV Supabase (NOT a mocked `.rpc()`). The test verifies (a) successful row insert, (b) service-role grant works, (c) cookie-scoped client returns 403. Mock-only tests pass the SQL grammar check but do NOT exercise PostgREST routing — the WORM-trigger learning class. (`2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-routing.md`).
- [ ] **AC17 — Wrapped contract assertion: GitHub API call iff audit row.** Integration fixture fires a synthetic webhook that triggers N GitHub API calls inside one Inngest step. After the step completes, `audit_github_token_use` row count for that test fixture is exactly N. RPC-throw counterfactual: inject a thrown error on the Nth call; assert N-1 rows persisted AND `Sentry.captureException` was called once with the throwing endpoint in tags (per AC8).
- [ ] **AC18 — Canonical-JSON signature determinism.** `test/lib/canonical-json.test.ts` covers shallow + nested key-order independence + non-finite-number rejection per the Phase 1 contract.
- [ ] **AC19 — Discoverability of new audit page.** `app/(dashboard)/dashboard/audit/page.tsx` (parent) includes a link to `/dashboard/audit/github` so the new sub-route is reachable from the existing UI. Test asserts the anchor exists.
- [ ] **AC20 — `cq-nextjs-route-files-http-only-exports` compliance.** Each new route file (`send/route.ts`, `edit/route.ts`, `discard/route.ts`) exports ONLY HTTP-verb handlers (`GET`/`POST`/etc.). No named helpers. Verified via `node` AST grep or `tsc` declarations.
- [ ] **AC21 — Foundations-PR contract self-check (Phase 0 carry-forward).** Phase 0's rebase verification grep results (presence of `write-action-send.ts`, `github-on-event.ts`, migration 051) are recorded in the PR body's `## Phase 0 reconciliation` section. If any artefact is missing post-rebase, the PR is paused (not merged).
- [ ] **AC22 — IME composition handling on TypedConfirmModal.** Tests cover an IME composition scenario: type `SEND` via a fake CJK IME (composition-start, composition-update, composition-end). Button must remain disabled until `compositionend` fires, then re-evaluate against `"SEND"` byte-equality.

### Post-merge (operator)

- [ ] **AC-PM1 (automatable).** `gh issue close 4098 --comment "PR-H+1 merged via #<N>"` after CI green. No manual step.
- [ ] **AC-PM2 (automatable).** Verify `record_github_token_use` populates the ledger by inspecting a recent webhook event in DEV → DEV Supabase row count incremented. Use `mcp__plugin_supabase_supabase__execute_sql` against DEV.
- [ ] **AC-PM3 (automatable).** `gh workflow run wait-for-pr-checks.yml --ref main` to confirm post-merge CI is green.

(Per the automation-feasibility gate, no genuinely operator-only steps remain. Subjective design or strategy decisions do not apply.)

## Files to Edit

| File | Edit | Why |
|---|---|---|
| `apps/web-platform/components/dashboard/today-card.tsx` | Replace `disabled aria-disabled="true"` stub with click handlers that POST to `/api/dashboard/today/send`, `/api/dashboard/today/edit`, `/api/dashboard/today/discard`. Add `TypedConfirmModal` import + invocation for `approve_every_time` tier. Component becomes a client component (`"use client"` directive). | AC2, AC4 |
| `apps/web-platform/app/(dashboard)/dashboard/audit/page.tsx` | Add a link to the new `/dashboard/audit/github` page (sidebar or `AuditSections` extension). Keep existing BYOK + Inngest sections intact. | Discoverability of the new audit surface |
| `apps/web-platform/server/inngest/functions/github-on-event.ts` | Replace the `byok-audit-writer-sweep: out-of-scope` stub at the per-Octokit-call site with an actual writer that calls `serviceClient.rpc("record_github_token_use", {...})` after every Octokit response. | AC7, AC8, AC13 |
| `knowledge-base/legal/dpd-soleur.md` (and plugins/soleur mirror) | Remove the Article 30 PA-16 TOM-#10 caveat `"record_github_token_use no longer ships unpopulated"` per AC11. Convention: append HTML-comment change-log entry. | AC11 |

## Files to Create

| File | Purpose |
|---|---|
| `apps/web-platform/app/(dashboard)/dashboard/audit/github/page.tsx` | New page route — read-only viewer for `audit_github_token_use`. Mirrors `app/(dashboard)/dashboard/audit/page.tsx` precedent. |
| `apps/web-platform/app/api/dashboard/today/send/route.ts` | Server route — handles Send. Re-checks grant, runs typed-SEND verbatim re-validation for `approve_every_time` tier, computes canonical-JSON approval signature, calls `writeActionSend(...)`. |
| `apps/web-platform/app/api/dashboard/today/edit/route.ts` | Server route — handles Edit. Same predicate as Send (grant + tier-based modal) plus the edited body. |
| `apps/web-platform/app/api/dashboard/today/discard/route.ts` | Server route — handles Discard. Grant re-check; writes a discard event through `writeActionSend(...)` (or the equivalent ledger surface — coordinate with #4065 schema). |
| `apps/web-platform/components/dashboard/typed-confirm-modal.tsx` | Client component — verbatim-typed-SEND modal. Renders disabled "Send" button until input strictly equals `SEND`. No `.trim()` / `.normalize()`. |
| `apps/web-platform/components/audit/github-audit-table.tsx` | Table component for the new audit page. Mirrors `audit-sections.tsx` precedent. |
| `apps/web-platform/test/server/dashboard/today/send.test.ts` | Unit + integration tests for Send route. |
| `apps/web-platform/test/server/dashboard/today/edit.test.ts` | Unit + integration tests for Edit route. |
| `apps/web-platform/test/server/dashboard/today/discard.test.ts` | Unit + integration tests for Discard route. |
| `apps/web-platform/test/server/inngest/github-on-event-audit-writer.test.ts` | Integration test asserting per-Octokit-call → per-`audit_github_token_use`-row. |
| `apps/web-platform/test/components/dashboard/today-card.click.test.tsx` | React component test for click-time grant re-check + typed-SEND modal. |
| `apps/web-platform/test/components/dashboard/typed-confirm-modal.test.tsx` | Component test for the modal's strict-byte-equality semantics. |
| `apps/web-platform/test/app/dashboard/audit/github.test.tsx` | Server-component test for the new audit page (cookie-scope + RLS belt-and-suspenders). |

## Implementation Phases

### Phase 0 — Rebase gate + reconciliation (1-2 commits)

1. **Verify upstream merged.** `gh pr view 4066 --json state,mergeCommit` AND `gh pr view 4065 --json state,mergeCommit`. If either is OPEN, halt and report. (See Hard rule on stacked-PR dependencies.)
2. **Rebase.** `git fetch origin main && git rebase origin/main`. Confirm tree contains:
   - `apps/web-platform/supabase/migrations/051_*.sql`
   - `apps/web-platform/server/action-sends/write-action-send.ts`
   - `apps/web-platform/server/inngest/functions/github-on-event.ts`
   - The `audit_github_token_use` RLS policy and `record_github_token_use` RPC.
3. **Re-run the Open-Code-Review-Overlap queries.** Reconcile new matches into "Fold in / Acknowledge / Defer" disposition per Phase 1.7.5.
4. **Read `today-card.tsx` post-rebase.** Confirm the buttons say `"Wires in PR-H+1"` (PR-H Phase 5 commit `551cb222` flips the label from PR-G).

### Phase 1 — Typed-confirm modal + canonical-JSON signature helper (RED → GREEN)

> **Precedent locked (deepen-pass):** `apps/web-platform/components/auth/sign-out-confirm-modal.tsx` is the canonical focus-trap + Escape-handler + restore-trigger-focus pattern. `TypedConfirmModal` mirrors verbatim: `useRef<HTMLDivElement>` for the dialog node, `useRef<HTMLElement | null>` for the trigger, `:disabled` filter on the focusable selector, `role="dialog" aria-modal="true" aria-labelledby="..."`.
>
> **Canonical-JSON helper not found** — `find . -path ./node_modules -prune -o -name "canonical-json*" -print` returns 0 results across the repo. Must create at `apps/web-platform/lib/canonical-json/index.ts`.

1. **RED:** Write `test/components/dashboard/typed-confirm-modal.test.tsx` covering:
   - (a) Empty input → confirm button disabled.
   - (b) `send` input (lowercase) → button disabled.
   - (c) `SEND ` input (trailing space) → button disabled.
   - (d) ` SEND` input (leading space) → button disabled.
   - (e) `SEND\n` (trailing newline) → button disabled.
   - (f) `ＳＥＮＤ` (fullwidth Unicode) → button disabled.
   - (g) Exact `SEND` → button enabled; submit fires `onConfirm(typedValue)` with `typed_value = "SEND"`.
   - (h) Escape closes the modal (matches sign-out-confirm-modal precedent).
   - (i) Trigger-focus is restored on close.
   - (j) Tab/Shift+Tab cycles among focusable elements inside the dialog.

2. **GREEN:** Implement `components/dashboard/typed-confirm-modal.tsx`. Strict byte-equality (`input === "SEND"`). No `.trim()` / `.normalize()` ANYWHERE. Copy the focus-trap useEffect from `sign-out-confirm-modal.tsx` verbatim, swapping only the heading/copy and the disabled-condition (`input !== "SEND"` instead of `isSigningOut`).

3. **RED:** Write `test/lib/canonical-json.test.ts` covering:
   - (a) Two objects with same keys/values constructed in different key order produce identical canonical string.
   - (b) Extra key changes the canonical string.
   - (c) Value mutation changes the canonical string.
   - (d) Nested object key order is also normalised (deep canonical, not just shallow).
   - (e) Non-finite values (`NaN`, `Infinity`) are explicitly rejected (throw) — these have no JSON representation and silently turn into `null` under default `JSON.stringify`.

4. **GREEN:** Implement `apps/web-platform/lib/canonical-json/index.ts`:
   ```typescript
   export function canonicalStringify(value: unknown): string {
     return JSON.stringify(value, sortReplacer);
   }

   function sortReplacer(_key: string, value: unknown): unknown {
     if (typeof value === "number" && !Number.isFinite(value)) {
       throw new TypeError("canonicalStringify: non-finite numbers are not representable");
     }
     if (value && typeof value === "object" && !Array.isArray(value)) {
       const sorted: Record<string, unknown> = {};
       for (const k of Object.keys(value as Record<string, unknown>).sort()) {
         sorted[k] = (value as Record<string, unknown>)[k];
       }
       return sorted;
     }
     return value;
   }
   ```
   (Approval signature computation: `sha256(canonicalStringify({founder_id, message_id, ts, typed_value}))`. The shallow-explicit-keys approach in the original plan is replaced by deep canonicalisation — safer against future shape extension.)

### Research Insights — Phase 1

**Best Practices:**
- The focus-trap + Escape pattern in `sign-out-confirm-modal.tsx` already handles `:disabled` filter correctly — adopt verbatim. Re-implementing the focus-trap risks subtle regressions (PR-G code-quality reviewer's history).
- Deep canonical-JSON > shallow explicit-keys because it withstands schema extension (e.g., if `request_id` gets added later, the signature spec doesn't need updating).
- The verbatim-`SEND` check is byte-equality on the JavaScript string. JavaScript strings are UTF-16 code-unit sequences; `"SEND" === "ＳＥＮＤ"` is `false` because the fullwidth glyphs have different code units. No further normalisation needed.

**Anti-patterns to Avoid:**
- DO NOT use `input.trim() === "SEND"` — Kieran P2-7 from PR-H review explicitly bans `.trim()` / `.normalize()`. A founder who copy-pastes `SEND` from a source that adds trailing whitespace should NOT pass.
- DO NOT lowercase-compare. The whole point of the verbatim modal is to force the founder to type the exact uppercase form (cognitive speed-bump).
- DO NOT use a `<input pattern="^SEND$">` HTML5 validation in lieu of the JS check. Pattern attributes can be bypassed by removing the `required` attribute via devtools. The server-side re-check (AC4) is the only load-bearing layer; the client check is UX only.

**Edge Cases:**
- Paste with trailing newline from a multiline source: `SEND\n` rejected (test case e).
- IME composition (CJK input methods): the modal must wait for `compositionend` before accepting the value. Add `onCompositionEnd` handler that triggers re-check.
- Screen-reader user: the modal's `aria-describedby` MUST point at instructions saying "type the word SEND exactly to confirm". Without this, the verbatim requirement is invisible to AT users — accessibility regression.

### Phase 2 — Server routes (Send / Edit / Discard) (RED → GREEN per route)

For each of `/api/dashboard/today/{send,edit,discard}`:

1. **RED:** Write the route's integration test covering:
   - Grant present (`approve_every_time` tier) + typed-SEND modal token correct → 200 + row in `action_sends`.
   - Grant present (`draft_one_click` tier) → 200 (no modal token expected).
   - Grant present (`auto` tier) → 200.
   - Grant revoked between page-load and click → `409 GrantRevoked` (verified by mutating the DB row between fixture setup and request fire).
   - Grant present + typed-SEND `send` (lowercase) → `400 TypedValueMismatch`.
   - Grant present + typed-SEND ` SEND` (leading space) → `400 TypedValueMismatch`.
   - Audit-write failure path is non-blocking + Sentry-mirrored (mock the RPC to throw; assert Sentry was called).
2. **GREEN:** Implement the route handlers. All three route through `writeActionSend(...)`.

Per `cq-nextjs-route-files-http-only-exports`, each route file exports only `GET` / `POST` etc., NEVER named helpers.

### Phase 3 — Wire today-card click handlers (RED → GREEN)

1. **RED:** Write `test/components/dashboard/today-card.click.test.tsx` covering:
   - Click Send on `approve_every_time` tier → modal opens; submit → POST `/api/dashboard/today/send` with `typed_value: "SEND"`.
   - Click Send on `draft_one_click` tier → no modal; POST `/api/dashboard/today/send` with `typed_value: null`.
   - Click Edit → POST `/api/dashboard/today/edit`.
   - Click Discard → POST `/api/dashboard/today/discard`.
   - Component is now `"use client"` (verified by inspecting the source's first non-comment line).
2. **GREEN:** Implement the click handlers. Drop the `disabled aria-disabled="true"` attributes and the `Wires in PR-H+1` titles. Keep the `min-h-[44px]` touch-target classes.

### Phase 4 — Per-GitHub-API-call audit writer (RED → GREEN)

> **Reality check (deepen-pass):** `apps/web-platform/package.json` has no `@octokit/*` dependency; `server/github-api.ts:56` uses raw `fetchWithRetry(url, init)`. PR-H #4066 introduces `server/github/app-client.ts` per the issue body; Phase 0 grep determines whether it adopts Octokit or extends the existing `fetch()` wrapper. The audit-writer wires into whichever response-handling site PR-H ships.

1. **Probe site (Phase 0 carry-forward):** After rebase, run:
   ```bash
   grep -nE "Octokit|octokit\.|@octokit" apps/web-platform/server/github/ 2>/dev/null
   grep -nE "fetch\(.*api\.github\.com" apps/web-platform/server/github/ 2>/dev/null
   grep -nE "fetchWithRetry" apps/web-platform/server/github/ 2>/dev/null
   ```
   Record which surface PR-H actually uses. The audit writer wraps THAT surface — not a paraphrased "Octokit hook".

2. **RED:** Write `test/server/inngest/github-on-event-audit-writer.test.ts` covering:
   - Single GitHub API call → single `audit_github_token_use` row with matching `installation_id`, `repo_full_name`, `endpoint`, `response_status`.
   - 3 GitHub API calls in one Inngest step → 3 audit rows.
   - RPC throw → step continues; row not written; `Sentry.captureException` called with `tags: { surface: "github-audit-writer", endpoint: "<endpoint>" }`.
   - The writer is invoked inside a `runWithByokLease(...)` scope (verified by reading `getCurrentByokLease()` inside the wrapper — non-null asserts the scope is open).
   - **Bypass sentinel:** `git grep -nE "fetch\(.*api\.github\.com" apps/web-platform/server/` returns matches ONLY inside the wrapped helper file (no direct fetches that bypass the audit writer). Per `hr-write-boundary-sentinel-sweep-all-write-sites` applied to the audit write surface symmetrically.

3. **GREEN:** Add a `recordGithubApiCall(...)` helper at `apps/web-platform/server/github/audit-writer.ts` (or whatever path PR-H sets). Wire it INSIDE the response handler of `fetchWithRetry()` (or `app-client.ts`'s response path). The helper:
   ```typescript
   // server/github/audit-writer.ts
   import { createServiceClient } from "@/lib/supabase/service";
   import * as Sentry from "@sentry/nextjs";

   export async function recordGithubApiCall(args: {
     founderId: string;
     installationId: string;
     repoFullName: string;
     endpoint: string;
     responseStatus: number;
   }): Promise<void> {
     try {
       const client = createServiceClient();
       const { error } = await client.rpc("record_github_token_use", {
         p_founder_id: args.founderId,
         p_installation_id: args.installationId,
         p_repo_full_name: args.repoFullName,
         p_endpoint: args.endpoint,
         p_response_status: args.responseStatus,
       });
       if (error) throw error;
     } catch (err) {
       // Non-blocking per AC8 + cq-silent-fallback-must-mirror-to-sentry.
       Sentry.captureException(err, {
         tags: {
           surface: "github-audit-writer",
           endpoint: args.endpoint,
         },
       });
     }
   }
   ```
4. **Wire from `github-on-event.ts`:** The Inngest function constructs a per-request fetch client inside `runWithByokLease(founderId, async () => { ... })`. Every GitHub API response in that scope is passed to `recordGithubApiCall(...)`. AC13's runtime check asserts `getCurrentByokLease()` is non-null inside the audit writer (the writer must NOT be called from outside a lease scope).

### Research Insights — Phase 4

**Best Practices:**
- The PostgreSQL RPC path is service-role-only. Cookie-scoped or anon callers will get 403 — verified by reading the RPC's `REVOKE FROM PUBLIC, anon, authenticated; GRANT TO service_role` posture in PR-H #4066's migration 051.
- Per `2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-routing.md`, mock-only CI does not exercise the live PostgREST path. The plan's integration test MUST run against DEV Supabase (not a mocked `.rpc()`).
- Per `2026-05-16-migration-mandates-must-have-wired-call-sites-in-same-pr.md`, the AC sentinel sweep is non-negotiable. Every GitHub API call site must route through the audit writer; bypass scans (`git grep -E "fetch\(.*api\.github\.com"`) must be in the AC, not just the comment.

**Edge Cases:**
- **GitHub rate-limit response (429):** `response_status: 429` must still produce an audit row (rate-limit observations are load-bearing for capacity planning + Article 30 PA-16).
- **Network error (no response):** `fetchWithRetry()` throws after exhausting retries. No HTTP status exists. The plan defers — the audit row records only completed responses, not network failures. Document this in the helper's JSDoc.
- **Concurrent requests:** Inngest functions can fan out parallel API calls (e.g., listing N repos). The helper is per-call, not per-step — N audit rows from N calls. Verified by AC7's "3 calls = 3 rows" test.

**References:**
- `apps/web-platform/server/github-api.ts:56` — `fetchWithRetry()` wrapper precedent.
- `apps/web-platform/server/byok-lease.ts:213,244` — `runWithByokLease()` + `getCurrentByokLease()` AsyncLocalStorage scope.
- `knowledge-base/project/learnings/2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-routing.md` — service-role gating + GUC mechanism.

### Phase 5 — `/dashboard/audit/github` surface (RED → GREEN)

> **Precedent locked (deepen-pass):** `apps/web-platform/app/(dashboard)/dashboard/audit/page.tsx` (PR-G #3947) is the canonical pattern: `export const dynamic = "force-dynamic"`, server component, `createClient()` from `@/lib/supabase/server`, `redirect("/login")` on missing user, `.eq("founder_id", user.id)` belt-and-suspenders, `.order("ts", { ascending: false }).limit(50)`.

1. **RED:** Write `test/app/dashboard/audit/github.test.tsx` covering:
   - Unauthenticated → redirect to `/login`.
   - Authenticated + 0 audit rows → renders empty-state copy verbatim: `"Your GitHub audit ledger populates as Soleur uses your GitHub App to read or write on your behalf. No calls yet."`
   - Authenticated + N audit rows → renders table with columns `installation_id`, `repo_full_name`, `endpoint`, `ts`, `response_status` in `ts DESC` order.
   - **Cross-tenant guard:** seed audit rows for founder B; founder A's page does NOT include them. Test failure mode: drop the `.eq("founder_id", user.id)` filter — test must FAIL when belt-and-suspenders is removed (regression rail).
   - Limit 50: seed 60 rows; assert exactly 50 rendered (oldest 10 elided).
   - Page header copy: `"GitHub audit log"` + subhead mirroring the brand voice of the parent audit page (`"Every Soleur run, every BYOK call. You decide. Agents execute. The ledger is the record."`).
   - Discoverability link: `apps/web-platform/app/(dashboard)/dashboard/audit/page.tsx` includes a link to `/dashboard/audit/github` (RED test: assert the parent page renders an `<a href="/dashboard/audit/github">` anchor).

2. **GREEN:** Implement `app/(dashboard)/dashboard/audit/github/page.tsx` + `components/audit/github-audit-table.tsx`. Mirror `audit/page.tsx` verbatim, swapping table query from `audit_byok_use` to `audit_github_token_use` and column set accordingly. Add the discoverability link on the parent audit page in the same commit (avoid orphan-route shipment per `2026-05-16-migration-mandates-must-have-wired-call-sites-in-same-pr.md`'s generalisation: a new surface must be reachable from existing UI).

### Research Insights — Phase 5

**Best Practices:**
- `export const dynamic = "force-dynamic"` is required: the page reads cookies (auth) and runs a Supabase query per request. Static generation would cache across tenants — single-user-incident-class leak.
- Belt-and-suspenders `.eq("founder_id", user.id)` is load-bearing per the precedent comment: `// Belt-and-suspenders: .eq("founder_id", user.id) defends against any future RLS loosening on audit_byok_use`. AC9 tests verify failure when removed.
- Per `cq-nextjs-route-files-http-only-exports`, the new page exports ONLY the default page component — no named exports. Helpers (column formatters, status-code colour mapping) live in `components/audit/github-audit-table.tsx` or `lib/audit/format.ts`.

**Implementation Details:**
```tsx
// app/(dashboard)/dashboard/audit/github/page.tsx
import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { GithubAuditTable, type GithubAuditRow } from "@/components/audit/github-audit-table";

export const dynamic = "force-dynamic";

export default async function GithubAuditPage() {
  const supabase = await createClient();
  const { data: { user } } = await supabase.auth.getUser();
  if (!user) redirect("/login");

  const { data: rows } = await supabase
    .from("audit_github_token_use")
    .select("installation_id, repo_full_name, endpoint, ts, response_status")
    .eq("founder_id", user.id)
    .order("ts", { ascending: false })
    .limit(50);

  return (
    <main className="mx-auto max-w-4xl px-6 py-8">
      <header className="mb-8">
        <h1 className="text-2xl font-medium text-soleur-text-primary">GitHub audit log</h1>
        <p className="mt-2 text-sm text-soleur-text-secondary">
          Every Soleur run, every BYOK call. You decide. Agents execute. The ledger is the record.
        </p>
      </header>
      <GithubAuditTable rows={(rows ?? []) as GithubAuditRow[]} />
    </main>
  );
}
```

**Edge Cases:**
- `response_status: 0` or `null` (network errors stored, if any): table cell renders `"—"` not `"0"`. Tested in fixture.
- Long `repo_full_name` (e.g., `very-long-org-name/very-long-repository-name-with-many-words`): table cell uses `truncate` + `title` attribute for full value on hover. Mobile fallback: line-wrap acceptable (table is read-only display).
- RTL languages in `repo_full_name`: out-of-scope (GitHub repos use ASCII).
- 50-row limit + pagination: deferred. If a founder exceeds 50 audit rows in a session, the older rows are invisible until the limit is raised. Document in empty-state-with-link as a follow-up issue, do NOT auto-paginate in this PR (out of scope per Non-Goals).

**References:**
- `apps/web-platform/app/(dashboard)/dashboard/audit/page.tsx` — canonical precedent.
- `apps/web-platform/components/audit/audit-sections.tsx` — table component precedent.

### Phase 6 — Legal doc amendment (Article 30 PA-16 TOM-#10) (1 commit)

1. Remove the TOM-#10 caveat string from `knowledge-base/legal/dpd-soleur.md` (canonical) and `plugins/soleur/docs/legal/dpd-soleur.md` (mirror). Append HTML-comment change-log entry per PR-H Phase 7 convention. Verify with `grep -nE "TOM-#10|record_github_token_use no longer ships unpopulated"`.

### Phase 7 — Full test sweep + push for CI (1 commit)

1. `bun run typecheck` clean.
2. `bun test apps/web-platform/test/` clean.
3. `git push` and wait for CI green.
4. Mark PR #4100 ready for review (already created per Step 0c).

## Test Strategy

Test runner: `bun test` (per existing `apps/web-platform/test/` precedent; verify via `bun test apps/web-platform/test/server/cc-dispatcher.tenant-isolation.test.ts` runs cleanly at Phase 0).

Test scope: DEV-only Supabase project (per `hr-dev-prd-distinct-supabase-projects`). All synthetic users / rows seed against DEV. No PROD writes.

Coverage matrix:
- Component tests: today-card + typed-confirm-modal + github-audit-table.
- Server route tests: send / edit / discard × {auto, draft_one_click, approve_every_time} × {grant present, grant revoked} × {audit RPC ok, audit RPC throws}.
- Integration test: webhook-fire → assert audit rows.
- E2E (optional, deferred): Playwright spec covering "founder lands on today-card → clicks Send → modal → ledger row appears". Defer to follow-up issue if PR scope grows; not load-bearing for AC1-AC14.

## Risks

- **R1 — Stacked-PR drift.** If #4066 or #4065 take review-cycle iterations after this plan freezes, the plan's file paths may shift (e.g., `write-action-send.ts` lands at a different path). Phase 0 reconciles. Mitigation: re-verify `find` outputs at the start of Phase 1.
- **R2 — Canonical-JSON helper drift.** If a `lib/canonical-json/` helper exists with a different signature, prefer the existing helper over a fresh implementation. Mitigation: `find . -path ./node_modules -prune -o -name "canonical*" -print` at Phase 1.
- **R3 — Octokit after-hook timing.** The Octokit `after` hook fires after the response is parsed; if the hook itself throws, default Octokit behaviour is to propagate. Wrap the hook body in `try/catch` and Sentry-mirror so the agent action's success path is the load-bearing signal (per issue acceptance criteria + `cq-silent-fallback-must-mirror-to-sentry`).
- **R4 — Modal accessibility.** `TypedConfirmModal` must trap focus, support Escape-to-close, and announce the verbatim-typed-SEND instruction to screen readers. Mitigation: borrow modal primitives from any existing modal in `components/` (e.g., the runtime-explainer-banner pattern); confirm at Phase 1 component test time.
- **R5 — Approve-every-time race.** A founder could revoke the grant between (a) the verbatim-SEND modal opening and (b) clicking Submit. The server-side re-check at AC3 closes the race deterministically — fail-closed on revocation.
- **R6 — Paraphrase drift on "Octokit".** Issue body uses "Octokit" wording but `apps/web-platform/` has no `@octokit/*` dependency (verified). If PR-H #4066 introduces `@octokit/*`, AC15's grep changes shape. Mitigation: Phase 0 grep probes for both `Octokit` AND `fetch(.*api.github.com)`; whichever is present is the wrap surface. Generalises `2026-04-22-ts-sql-normalizer-parity-when-shipping-backfill-migration.md` (paraphrase-without-verification).
- **R7 — WORM-trigger interaction with `writeActionSend(...)`.** PR-H' #4065 introduces `action_sends` + `anonymise_action_sends` RPC with the WORM-trigger pattern. Per `2026-05-18-worm-trigger-bypass-role-check-fails-under-postgrest-routing.md`, the role-check bypass can silently always-false. PR-H+1's Phase 0 MUST verify `anonymise_action_sends` uses GUC-only (not role-check) gating before relying on the boundary. If broken, file a tracking issue (per `wg-when-deferring-a-capability-create-a`) — do NOT silently consume a broken contract.
- **R8 — Live-PostgREST CI cost.** AC16 (live RPC integration test) adds DEV-Supabase round-trips to CI. If the test suite is slow (>10s per run), consider gating behind a `RUN_LIVE_RPC=1` env var. But: per the WORM learning, mock-only is exactly the gap; the test MUST run in the default CI path. Mitigation: keep the integration test scope to ONE end-to-end fixture (not per-permutation).
- **R9 — `recordGithubApiCall` non-blocking failure exposes Article 30 PA-16 disclosure gap.** If the RPC silently fails frequently (e.g., Supabase pool exhaustion under load), the audit ledger under-counts and the founder's "every GitHub call is logged" disclosure is false in practice. Mitigation: AC8 mirrors to Sentry on every failure; weekly Sentry digest for `surface: "github-audit-writer"` is a follow-up issue (deferred-scope-out label).
- **R10 — Discord-role / nav surface drift.** The new `/dashboard/audit/github` page is only discoverable if AC19 (parent-page link) is enforced; ship-time spot-check from the audit page must include the new link.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. Fill it before requesting deepen-plan or `/work`.
- The Phase 0 rebase gate is load-bearing. Without #4066 + #4065 merged, the file paths in `## Files to Edit` do NOT resolve, and `/work` will fail at the first `Read` call. Do NOT skip Phase 0 even under time pressure.
- `today-card.tsx`'s `"use client"` flip is a directive change with cascading bundle implications. Verify `next build` clean at Phase 3.
- The typed-SEND modal MUST NOT call `.trim()` or `.normalize()` anywhere — client OR server. Kieran P2-7 from PR-H review. Test cases for fullwidth `ＳＥＮＤ`, trailing whitespace, leading whitespace, and lowercase `send` all assert rejection.
- `record_github_token_use` is `REVOKE FROM PUBLIC, anon, authenticated; GRANT TO service_role`. Calling it from a cookie-scoped client returns 403; tests must mock with service-role client.
- `audit_github_token_use` RLS uses `auth.uid() = founder_id`. The dashboard page MUST use cookie-scoped client (not service-role). Belt-and-suspenders `.eq("founder_id", user.id)` defends against future RLS regression (precedent: `today/route.ts`).
- The new `/dashboard/audit/github` page must be added to the dashboard nav (sidebar OR `AuditSections` extension on the existing `/dashboard/audit` page) — otherwise it's unreachable from the UI even though it's a routable URL. Phase 5 verifies discoverability.
- AC11 (legal doc amendment) must edit BOTH `knowledge-base/legal/` (canonical) AND `plugins/soleur/docs/legal/` (mirror) — PR-H Phase 7 established this convention. Single-file edits will fail CI smoke checks.
- Per `wg-use-closes-n-in-pr-body-not-title-to`, PR body uses `Closes #4098` (this issue) and `Ref #3244, #4066, #4077` (umbrella + sibling PRs).
- The issue body says "per-Octokit-call audit writer"; the codebase uses raw `fetch()` not Octokit (verified at deepen-pass). Do NOT add `@octokit/*` packages to satisfy the issue paraphrase — wrap the existing `fetchWithRetry()` instead. If #4066 lands `@octokit/*`, re-evaluate at Phase 0.
- The WORM-trigger learning (`2026-05-18-...-bypass-role-check-fails-under-postgrest-routing.md`) is load-bearing: Phase 0 reads the `action_sends` trigger definition AND `anonymise_action_sends` body; if the role-check pattern is present, the bypass is broken and `writeActionSend(...)` cannot rely on the standard cascade. File a follow-up issue and use the GUC-only fallback for this PR.
- Per `2026-05-16-migration-mandates-must-have-wired-call-sites-in-same-pr.md`, the migration mandate "every Octokit call → audit row" cannot be enforced by comment-only documentation. AC15's sentinel sweep is the structural enforcement.
- The deepen-pass replaced the original explicit-keys-array signature recipe with a deep canonical-JSON helper. The signature contract changed shape — verify the `action_sends.approval_signature` column in PR-H' #4065 stores the canonical-stringified output, not the legacy explicit-keys form. If #4065 already shipped the explicit-keys form, the choice is: (a) backport the canonical helper to #4065, or (b) keep the explicit-keys form in this PR for compat. Decide at Phase 0.
- The new `/dashboard/audit/github` page is reachable at URL but NOT in the nav by default unless AC19 is enforced. The parent `/dashboard/audit` page MUST link to it — single-commit edit, not deferred.
- AGENTS.md citation gate: every rule ID cited in this plan (`hr-*`, `cq-*`, `wg-*`) was grep-verified against `AGENTS.md` at deepen-pass time. No retired or fabricated IDs. Re-verify if AGENTS.md changes between plan and `/work`.

## Alternative Approaches Considered

| Approach | Why not chosen | Deferred? |
|---|---|---|
| Land per-Octokit audit writer in #4066 PR-H itself instead of PR-H+1 | PR-H is already in review and large; folding in adds another review cycle and risks blocking the multi-source ingress work that closes umbrella #3244 AC | No — scope-out is intentional, captured in this PR |
| Use cookie-scoped client (not service-role) for `record_github_token_use` | The RPC is `REVOKE FROM PUBLIC, anon, authenticated; GRANT TO service_role` — cookie-scoped call returns 403. Only service-role works. | N/A |
| Ship `/dashboard/audit/github` as a tab on the existing `/dashboard/audit` page | The existing page already has BYOK + Inngest sections; adding a third section grows the page beyond first-screen scroll. A dedicated sub-route at `/dashboard/audit/github` is cleaner and mirrors how Stripe/CFO audits would expand. | No |
| Skip typed-SEND verbatim modal for `approve_every_time` tier | The verbatim modal is the single user-facing speed-bump preventing a single-user incident (Kieran P2-7). Without it, a misclick at `approve_every_time` tier sends a real message. | No — load-bearing per brand-survival threshold |
| Make audit-write failure blocking (transactional with the agent action) | Issue body explicitly calls out non-blocking; making it blocking would couple BYOK-audit-write availability to the agent action's success, increasing surface for a Supabase write outage to wedge agent execution. Sentry-mirroring closes the visibility gap without coupling. | No |

## Non-Goals

- Anthropic SDK retry/backoff hardening (separate concern, per issue body).
- Cross-installation token caching (current per-request factory is intentional, AC14 in PR-H).
- A Playwright E2E for the click-to-modal-to-ledger flow (deferrable; component + route tests cover the contract).
- Cross-tenant audit-aggregation views or admin tooling (no admin surface exists; not in scope).
