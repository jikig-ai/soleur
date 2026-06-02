---
title: "Tasks — repair stale conversation-archive-release-slot integration suite"
plan: knowledge-base/project/plans/2026-06-02-fix-repair-stale-conversation-archive-release-slot-integration-suite-plan.md
branch: feat-one-shot-4798-stale-slot-integration-suite
lane: single-domain
date: 2026-06-02
status: planned
related_issues: [4798]
---

# Tasks — repair stale `conversation-archive-release-slot` integration suite

> No `spec.md` exists for this branch. The plan's frontmatter declares
> `lane: single-domain` based on the actual scope (one opt-in test file, one
> domain). Honored here rather than the legacy-spec `cross-domain` default
> because the determination is explicit and scope-grounded.

Derived from the finalized plan. The whole change is one file:
`apps/web-platform/test/conversation-archive-release-slot.integration.test.ts`.

## Phase 1 — Setup / Pre-conditions

- [ ] 1.1 Read the target file and the canonical sibling
  `apps/web-platform/test/concurrency-acquire-slot-workspace-id.integration.test.ts`
  (the merged #4791 pattern) before editing.
- [ ] 1.2 Confirm dev creds are available for the live run
  (`doppler run -p soleur -c dev -- env | grep -E 'NEXT_PUBLIC_SUPABASE_URL|SUPABASE_SERVICE_ROLE_KEY'`).
  If unavailable, AC7 will be reported as "pending live dev run" in the PR body
  rather than claimed green (Sharp Edge).

## Phase 2 — Core Implementation (single file)

- [ ] 2.1 `insertConversation`: remove `title: "slot-trigger integration"`.
- [ ] 2.2 `insertConversation`: add `workspace_id: user.id` (solo workspace =
  user.id, ADR-038 N2 — matches the existing `acquireSlot` `p_workspace_id`).
  Optionally add `last_active: new Date().toISOString()` for fidelity with
  `createConversation`.
- [ ] 2.3 `afterAll`: replace bare `deleteUser` with the FK-ordered teardown —
  `user_concurrency_slots` delete → `conversations` delete →
  `anonymise_workspace_members` RPC → `anonymise_workspace_member_actions` RPC →
  `workspaces` delete (id = user.id) → `organizations` delete
  (owner_user_id = user.id) → keep `assertSynthetic` + `getUserById` email
  re-check → `deleteUser`. Keep the `throw` on `deleteUser` failure (this suite
  fails loud on teardown regressions).
- [ ] 2.4 Remove the in-file `#4798` staleness `NOTE` paragraph inside
  `acquireSlot` (file lines ~138-142). Keep the mig-093 4-arg contract comment.
- [ ] 2.5 Update the header docstring `Plan:` line to cite this plan; drop any
  stale-schema caveat.
- [ ] 2.6 Do NOT add a `teamWorkspaceId` fixture (YAGNI — unused here).
  Do NOT change `afterEach`, the 6 test bodies, or the helper signatures.

## Phase 3 — Verification (Acceptance Criteria)

- [ ] 3.1 AC1 — `title` gone from the `insertConversation` INSERT payload.
- [ ] 3.2 AC2 — `workspace_id: user.id` present in `insertConversation`.
- [ ] 3.3 AC3 — `anonymise_workspace_member*` RPCs (×2) called before `deleteUser`.
- [ ] 3.4 AC4 — no `#4798` / "independently stale" / "does not run in CI" text remains.
- [ ] 3.5 AC5 — `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` exits 0.
- [ ] 3.6 AC6 — default (no-env-flag) vitest run reports the describe block
  skipped, exit 0.
- [ ] 3.7 AC7 — live dev run all-green:
  `cd apps/web-platform && doppler run -p soleur -c dev -- env SLOT_TRIGGER_INTEGRATION_TEST=1 ./node_modules/.bin/vitest run test/conversation-archive-release-slot.integration.test.ts`
  → `6 passed`, exit 0, no synthetic rows left in dev. Paste summary into PR body.
- [ ] 3.8 AC8 — `SYNTHETIC_EMAIL_PATTERN` + `assertSynthetic` guards unchanged.

## Phase 4 — Ship

- [ ] 4.1 PR body uses `Closes #4798` (this PR fully resolves the staleness;
  not an ops-remediation, so `Closes` is correct).
- [ ] 4.2 No post-merge operator steps — merging is the whole deliverable.
