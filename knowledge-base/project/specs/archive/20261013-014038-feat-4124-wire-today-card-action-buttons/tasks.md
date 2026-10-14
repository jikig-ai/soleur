---
title: "Tasks — feat-4124-wire-today-card-action-buttons (PR-A substrate)"
date: 2026-05-22
plan: knowledge-base/project/plans/2026-05-22-feat-wire-today-card-spawn-agent-buttons-pr-a-plan.md
issue: 4124
lane: cross-domain
requires_cpo_signoff: true
brand_survival_threshold: single-user incident
---

# Tasks — wire today-card Spawn-agent / Fix-link buttons (PR-A)

Derived from the plan referenced in frontmatter. Each phase is RED/GREEN/REFACTOR-shaped; commit after each phase's GREEN gate.

## Phase 0 — Pre-conditions (verify before code)

- [x] 0.1 Confirm worktree path: `pwd` shows `.worktrees/feat-4124-wire-today-card-action-buttons/`.
- [x] 0.2 Re-read `apps/web-platform/components/dashboard/today-card.tsx` (lines 88-99, 101-217, 221-462) and `apps/web-platform/app/api/dashboard/today/[id]/send/route.ts` (lines 73-339) for the canonical StripeCard wiring shape.
- [x] 0.3 Verify next migration number is genuinely `062` — `ls apps/web-platform/supabase/migrations/ | tail -3`. If `062_*` already exists, rebase or pick next.
- [x] 0.4 Verify `action_sends` WORM trigger scope — read `apps/web-platform/supabase/migrations/<WORM_TRIGGER>.sql` (find via `rg -l "action_sends.*WORM|TRIGGER.*action_sends"`); confirm trigger guards INSERT immutability only, NOT UPDATE on three new columns. If UPDATE-blocking, migration 062 must add column-list exception.
- [x] 0.5 Verify PA-19 is genuinely the next strict ordinal — re-read `knowledge-base/legal/article-30-register.md` tail; PA-16 known out-of-order at line 306.
- [x] 0.6 Verify Kieran P1-7 mitigation: `default_legacy` template at `apps/web-platform/server/templates/template-registry.ts:45-56` is `action_class: null` AND PR-I `first_send` path exists at `apps/web-platform/server/templates/is-template-authorized.ts:74-80`. First-send-IS-authorization covers the four spawn classes without new TEMPLATE_REGISTRY rows.
- [x] 0.7 Verify event-name convention exception is defensible — re-read `server/inngest/functions/github-on-event.ts:287-291` (per-class webhook events) and confirm the cross-cutting `agent.spawn.requested` umbrella is justified per `## Alternative Approaches Considered`.

## Phase 1 — DB migration + Article 30 register

- [x] 1.1 RED: write `apps/web-platform/supabase/migrations/062_action_sends_acknowledgment.test.ts` asserting (a) three new columns exist on `action_sends` with NULL defaults, (b) WORM trigger UPDATE-compat on the three new columns, (c) RLS owner-SELECT still works after the migration.
- [x] 1.2 GREEN: write `062_action_sends_acknowledgment.sql` (ADD COLUMN x3 + COMMENTs) + `062_action_sends_acknowledgment.down.sql` (DROP COLUMN x3).
- [x] 1.3 Apply to dev Supabase via the migration runner; assert test passes.
- [x] 1.4 Append PA-19 entry to `knowledge-base/legal/article-30-register.md` using the verbatim block from the plan's GDPR gate section. Verify: `grep -c "^## Processing Activity 19"` returns `1`.
- [x] 1.5 Commit: `migration: 062 action_sends acknowledgment columns + PA-19 register entry`.

## Phase 2 — Inngest function (deterministic acknowledgment)

- [x] 2.1 RED: write `apps/web-platform/test/server/inngest/agent-on-spawn-requested.test.ts` covering: happy-path PR comment, happy-path issue label, cross-tenant installation mismatch (founder lacks `github_installation_id` → throws), GitHub 401 (Octokit hook.error path), idempotency on duplicate event (one artifact, one UPDATE).
- [x] 2.2 RED: write `apps/web-platform/test/server/inngest/installation-id-source-of-truth.test.ts` — TypeScript compile assertion (event payload type omits `installationId` field) + runtime grep negative pattern (`grep -nE "event\.data\.installationId|payload\.installationId|\.data\.installationId|\binstallationId\b\s*[:=]\s*event"` returns 0 matches).
- [x] 2.3 GREEN: write `apps/web-platform/server/inngest/agent-acknowledgment-templates.ts` (`ACK_PR_COMMENT_TEMPLATE`, `parseSourceRef` helper).
- [x] 2.4 GREEN: write `apps/web-platform/server/inngest/functions/agent-on-spawn-requested.ts` per the architecture pseudo-code in the plan. Enforce: `AgentSpawnRequestedEvent` type omits `installationId`; idempotency key = `event.data.actionSendId`; retries: 3; step ordering is resolve-installation → post-acknowledgment → mark-acknowledged.
- [x] 2.5 Register the new function in the Inngest function index (verify against existing `cfo-on-payment-failed.ts` registration pattern).
- [x] 2.6 Run Phase 2 test suite (2.1 + 2.2); assert all GREEN.
- [x] 2.7 Run `byok-audit-writer-sweep` lint — assert no new `runWithByokLease(` site added (PR-A makes zero Anthropic calls).
- [x] 2.8 Commit: `feat: agent-on-spawn-requested Inngest function (deterministic stub for PR-A)`.

## Phase 3 — `/send` route + tier bump

- [x] 3.1 RED: extend `apps/web-platform/test/api/dashboard/today/[id]/send-route.spawn.test.ts` covering: kb_drift draft_one_click happy-path (200 with action_send_id + artifact_view_url); `inngest.send` mock called once between writeActionSend and archive; enqueue-failure → 200 with `degraded:"enqueue_failed"` flag; degraded path does NOT return 500.
- [x] 3.2 RED: write `apps/web-platform/test/server/scope-grants/kb-drift-tier-bump.test.ts` asserting `ACTION_CLASS_DEFAULTS["knowledge.kb_drift"] === "draft_one_click"` + producer-side cascade grep returns 0 hits.
- [x] 3.3 GREEN: bump tier in `apps/web-platform/server/scope-grants/action-class-map.ts:86` from `"auto"` to `"draft_one_click"`. Update `test/server/scope-grants/action-class-exhaustive.test.ts` per the in-file checklist (action-class-map.ts:8-14).
- [x] 3.4 GREEN: edit `apps/web-platform/app/api/dashboard/today/[id]/send/route.ts` — add `inngest.send(...)` AFTER writeActionSend AND BEFORE archive, wrapped in try/catch + reportSilentFallback. Extend 200 success payload with `action_send_id` + deterministic `artifact_view_url` (compute from sourceRef + resolved owner/repo). Add optional `degraded` field on enqueue failure.
- [x] 3.5 Run Phase 3 test suite; assert all GREEN.
- [x] 3.6 Commit: `feat(send-route): dispatch agent.spawn.requested + acknowledgment URL; bump kb_drift tier`.

## Phase 4 — Client hook + component wiring

- [x] 4.1 RED: write `apps/web-platform/test/components/today-card.click.test.tsx` (happy-dom env; method-aware `vi.fn` fetch mock per `2026-05-20-happy-dom-ws-fetch-blockade.md`) covering: GitHubCard PR comment happy-path, KbDriftCard label happy-path, 403 no_grant, 409 requires_confirmation + typed-confirm, 409 already_sent, 200 with `degraded:"enqueue_failed"` → "Acknowledged (queued)" pill state.
- [x] 4.2 GREEN: extract StripeCard's click logic into `apps/web-platform/hooks/use-action-send.ts` returning the `{ onSend, isPending, error, acknowledged, artifactUrl, confirming, onConfirmTyped, onCancelConfirm }` shape. Hooks dir kebab-case precedent.
- [x] 4.3 GREEN: refactor StripeCard in `apps/web-platform/components/dashboard/today-card.tsx` to consume `useActionSend()` (no behavioral change).
- [x] 4.4 GREEN: drop `disabled aria-disabled="true" title="Wires in PR-H+1"` from GitHubCard + KbDriftCard buttons. Add `onClick={onSend}`, `disabled={isPending}` from the hook. Add "Acknowledged — View on GitHub" pill state rendering `artifactUrl` as a link. Pill replaces `setArchived(true)` for GitHub + KbDrift sources (StripeCard keeps existing archive behavior on send).
- [x] 4.5 GREEN: extend `apps/web-platform/components/ui/typed-confirm-modal.tsx` with optional `actionTargetLabel?: string` prop (backwards-compatible default = `recipientExcerpt`). GitHubCard's `approve_every_time` flow (cve_alert, secret-scan- variants) passes `actionTargetLabel="PR #<n>"` or `"issue #<n>"`.
- [x] 4.6 Run full app type-check (`bun run typecheck` or `./node_modules/.bin/tsc --noEmit`) — confirm no `event.data.installationId` reads anywhere (compile-time guard).
- [x] 4.7 Run Phase 4 test suite via `./node_modules/.bin/vitest run apps/web-platform/test/components/today-card.click.test.tsx` (in-worktree vitest invocation per `cq-in-worktrees-run-vitest-via-node-node`).
- [x] 4.8 Commit: `feat(today-card): wire GitHubCard + KbDriftCard onClick handlers + Acknowledged pill`.

## Phase 5 — Pre-merge verification + follow-up filing

- [x] 5.1 Run full test suite for `apps/web-platform/`: `cd apps/web-platform && ./node_modules/.bin/vitest run`. All green.
- [x] 5.2 Run all sentinel greps from ACs 1-3 manually: confirm zero matches against the new files.
- [x] 5.3 File **PR-B issue** before opening PR-A — body sketches: ADR-039 (Anthropic-SDK-inside-Inngest), per-class leader-prompt loop replacing the deterministic stub body, `runWithByokLease` scope, `record_byok_use_and_check_cap` wiring, per-turn idempotency, max-turns, 60s timeout, card-surfaced failure UX. Tag with `milestone: "Post-MVP / Later"` or appropriate phase.
- [x] 5.4 File **copywriter follow-up issue** — scope: provisional `ACK_PR_COMMENT_TEMPLATE` + label name + failure-state copy + 5 GitHubCard button hover strings + 2 KbDrift button labels.
- [x] 5.5 (Optional) File **transactional outbox** follow-up — conditional on observed orphan rate. Do NOT file pre-emptively per skill rule.
- [x] 5.6 Run `bun run typecheck`, `bun run lint`, markdownlint on the plan + tasks files.
- [x] 5.7 Open PR. PR body uses `Closes #4124` (this PR ships the substrate slice declared in #4124 body). PR description references PR-B follow-up issue. Add `domain/product` + `priority/p2-medium` + `type/feature` labels (copy from #4124).
- [x] 5.8 Trigger `/ultrareview` after pushing for a multi-agent cloud review pass.

## Phase 6 — Post-merge (operator)

- [ ] 6.1 Verify migration 062 applied to prd via the migration runner.
- [ ] 6.2 Operator triggers a real GitHub webhook (PR review pending on connected dev repo) → card appears → operator clicks "Spawn review agent" → expects within 60s: PR comment visible at `action_sends.artifact_url`; `acknowledged_at IS NOT NULL`; `audit_github_token_use` row count incremented.
- [ ] 6.3 Operator triggers a real KB-drift detection → KbDriftCard appears → click "Fix link" → issue label `soleur/acknowledged` appears on the linked issue within 60s.
- [ ] 6.4 Operator inspects Sentry for `feature=spawn-agent` tag rows; no unexpected `op=inngest-enqueue` failures in the first hour.
- [ ] 6.5 Close #4124 via `gh issue close 4124 --comment "PR-A shipped; PR-B follow-up tracked at #<N>"` once acceptance verified.
- [ ] 6.6 Update PR-B issue with the merged PR-A SHA so the leader-loop work has a known substrate baseline.
- [ ] 6.7 Run `/soleur:compound` to capture learnings (single-user-incident threshold framing carry-over from CPO sign-off; deterministic-stub-as-brand-survival-mitigation pattern; per-Octokit audit factory verification flow).
