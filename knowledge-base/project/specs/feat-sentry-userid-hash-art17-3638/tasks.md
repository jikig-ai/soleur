---
title: "Tasks — feat-sentry-userid-hash-art17-3638"
issue: 3638
related: [3603, 3686]
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Tasks: feat-sentry-userid-hash-art17-3638

Derived from `knowledge-base/project/plans/2026-05-12-feat-sentry-userid-hash-art17-erasure-plan.md` (v2).

## Phase 1 — HMAC helper

- [ ] 1.1 In `apps/web-platform/server/observability.ts`, add `import { createHmac } from "node:crypto";` immediately after the existing imports.
- [ ] 1.2 Load `SENTRY_USERID_PEPPER = process.env.SENTRY_USERID_PEPPER` at module top-level.
- [ ] 1.3 Emit one-shot boot warning via `console.warn` when `SENTRY_USERID_PEPPER` is unset.
- [ ] 1.4 Export `hashUserId(userId: string, pepper?: string): string` with full 64-hex HMAC-SHA256 digest; return `"pepper_unset"` sentinel when no pepper is available (neither arg nor env).
- [ ] 1.5 Add JSDoc on `hashUserId` documenting the contract (deterministic, fail-closed sentinel, optional pepper arg for future rotation lookup).

## Phase 2 — Apply transform at emit boundaries

- [ ] 2.1 Inside `reportSilentFallback` (line 82-117), compute `transformedExtra` that renames `userId` → `userIdHash` via `hashUserId`. Replace every `extra` reference inside the function body with `transformedExtra` (logger call + Sentry calls).
- [ ] 2.1.5 Inside `warnSilentFallback` (line 123-149), apply the identical `transformedExtra` transformation.
- [ ] 2.2 Verify `mirrorWithDebounce` (line 265-273) requires NO change — delegates to `reportSilentFallback`. Add a one-line code comment confirming the inheritance.
- [ ] 2.3 In `mirrorP0Deduped` (line 322-357), compute `userIdHash = hashUserId(ctx.userId)` once. Update the pino `logger.error` call to emit `userIdHash` (not `userId`). Update the Sentry payload (preserving the existing `typeof Sentry.captureException === "function"` guard AND the `try/catch` envelope) so `tags` contain `userIdHash` AND `extra` contains `userIdHash` (no raw `userId` anywhere).
- [ ] 2.4 Verify dedup-map key at line 326 stays raw (`${ctx.userId}:${ctx.op}:${ctx.conversationId}`). Verify dedup-map key at line 271 stays raw (`${userId}:${errorClass}`).
- [ ] 2.6 In `apps/web-platform/server/ws-handler.ts`, migrate the direct `Sentry.captureMessage` site at line ~693 (createConversation 23505 fallback: activeWorkflow diverged) to `warnSilentFallback({ feature: "create-conversation", op: "23505-fallback-active-workflow", extra: { conversationId, existingWorkflow, intendedWorkflow, userId } })`. Add `import { warnSilentFallback } from "@/server/observability";` if not present.
- [ ] 2.7 Migrate the direct `Sentry.captureMessage` site at line ~719 (createConversation 23505 fallback: context_path diverged) to `warnSilentFallback({ feature: "create-conversation", op: "23505-fallback-context-path", extra: { conversationId, existingContextPath, intendedContextPath, userId } })`.
- [ ] 2.8 Run `git grep -n 'Sentry.captureMessage\|Sentry.captureException' apps/web-platform/server/` and audit every site for raw `userId` in `extra`. Note any additional sites in the PR description; either migrate inline if the same pattern, or open a follow-up issue.
- [ ] 2.9 File follow-up issue for `lib/client-observability.ts` pseudonymization (cannot share server pepper; out of scope for #3638).

## Phase 3 — Tests

- [ ] 3.1 In `apps/web-platform/test/observability.test.ts`, replace raw `userId: "u1"` / `userId: "u2"` assertions at lines 35, 52, 72, 96-100 with `userIdHash` assertions. Use `vi.stubEnv("SENTRY_USERID_PEPPER", "test-pepper")` for determinism.
- [ ] 3.2 Add `hashUserId` unit tests: determinism, distinct-input distinct-output (1000-iteration smoke), `"pepper_unset"` sentinel when no pepper, prior-pepper override via explicit arg.
- [ ] 3.3 Add emit-shape tests for `reportSilentFallback`, `warnSilentFallback`, and `mirrorP0Deduped`: assert NO raw `userId` key appears in Sentry `extra`/`tags`, assert `userIdHash` value matches `hashUserId(rawUserId, "test-pepper")`, assert pino mock receives `{ userIdHash, ... }`.
- [ ] 3.4 Add pepper-unset fail-closed tests for all three functions: emit `userIdHash: "pepper_unset"`, no throw, no silent drop.
- [ ] 3.5 Add dedup-invariance test: two `mirrorP0Deduped` calls with same raw `userId` but different test peppers still dedupe (validates dedup-map key stays raw).
- [ ] 3.6 If `cc-dispatcher.test.ts` or `ws-handler.test.ts` covers the 23505 fallback paths, update assertions to expect `userIdHash`. If no test covers those paths, file follow-up rather than expanding scope.
- [ ] 3.7 Run full vitest suite: `pnpm --filter web-platform vitest run`. Confirm T-W4-orphan regression at `cc-dispatcher.test.ts:1591` passes.
- [ ] 3.8 Run grep gate: `rg "(extra|tags):\s*\{[^}]*\buserId\b" apps/web-platform/server/` should return zero production-code matches.

## Phase 4 — Article 30 PA8 update

- [ ] 4.1 In `knowledge-base/legal/article-30-register.md`, replace PA8 row `(c) Categories of personal data` (line 157) with the pseudonymization disclosure text from plan Phase 4.1.
- [ ] 4.2 Append the Art. 17 retention clarification sentence to PA8 row `(f) Retention` (line 162).
- [ ] 4.3 Bump `last_reviewed` frontmatter to today's date.
- [ ] 4.4 Verify no recipient list change (line 160) and no vendor table change (lines 167-179) — Better Stack remains correctly absent (uptime-only, not a data recipient).

## Phase 5 — Doppler secret provisioning

- [ ] 5.1 Generate two distinct random peppers: `openssl rand -hex 32` for dev, again for prd. Do NOT paste via conversation `!`-prefix (`hr-never-paste-secrets-via-bang-prefix`).
- [ ] 5.2 Set dev pepper: `doppler secrets set SENTRY_USERID_PEPPER -p soleur -c dev`. Verify: `doppler secrets get SENTRY_USERID_PEPPER -p soleur -c dev --plain` returns the value.
- [ ] 5.3 (Post-merge / operator) Set prd pepper: `doppler secrets set SENTRY_USERID_PEPPER -p soleur -c prd`. Roll Vercel deployment. Verify by tailing prd container logs for absence of the `pepper_unset` warning.

## Phase 6 — PR finalize

- [ ] 6.1 PR body includes `Closes #3638` and `Refs #3686 (deferred D-durable-audit-log)`.
- [ ] 6.2 PR body includes CPO sign-off ack and notes `requires_cpo_signoff: true` from plan frontmatter.
- [ ] 6.3 PR body includes a one-line note: "Events emitted after merge are pseudonymized; pre-merge Sentry events age out per retention."
- [ ] 6.4 Invoke `/soleur:gdpr-gate` against plan + diff. Resolve any Critical findings before review-ready.
- [ ] 6.5 Mark PR ready-for-review; `user-impact-reviewer` runs at review time and verifies the User-Brand Impact section against the diff.
