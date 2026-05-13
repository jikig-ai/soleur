# Tasks: feat-pino-userid-formatters-log (#3698 PR-A)

Plan: `knowledge-base/project/plans/2026-05-12-feat-pino-userid-formatters-log-plan.md`
Spec: `knowledge-base/project/specs/feat-pino-userid-redaction-3698/spec.md`
ADR: `knowledge-base/engineering/architecture/decisions/ADR-029-rename-at-boundary-userid-pseudonymisation.md`
Follow-ups: #3710 (PR-B Sentry-side), #3711 (PR-C operator UX + retention), #3708 (DPD), #3696 (client-side).

## Phase 0: Preflight

- [x] 0.1 Re-run inventory grep: `git grep -nE '(log|logger)\.(error|warn|info|debug).*\buserId\b' apps/web-platform/app/ apps/web-platform/server/` — expect 11 sites.
- [x] 0.2 Confirm pino formatters.log signature at `apps/web-platform/node_modules/pino/pino.d.ts:642-663` and ordering at `pino/lib/tools.js:161-200`.
- [x] 0.3 Confirm `apps/web-platform/server/userid-pseudonymize.ts` path is free (no collision).

## Phase 1: Shared rename helper

- [x] 1.1 Write failing tests in `apps/web-platform/test/userid-pseudonymize.test.ts` (6 fixtures: top-level userId/user_id rename, null → "pepper_unset_null", missing pepper → "pepper_unset", double-hash defensive, empty/no-key pass-through, nested-NOT-renamed boundary).
- [x] 1.2 Implement `renameUserIdToHash(obj)` + `hashUserIdValue(rawValue)` in `apps/web-platform/server/userid-pseudonymize.ts`. Imports `hashUserId` from `./observability`. Pure functions.
- [x] 1.3 Refactor `hashExtraUserId` in `observability.ts:48-55` to delegate to the shared helper.
- [x] 1.4 Run `bun test apps/web-platform/test/observability*.test.ts` — must stay green (refactor regression gate).

## Phase 2: Pino formatters.log() rename hook (with try/catch)

- [x] 2.1 Write failing tests in `apps/web-platform/test/logger-formatters.test.ts` (vi.hoisted env discipline per `observability.test.ts:5-42`):
  - [x] 2.1.1 `logger.error({userId})` → emit contains `userIdHash`, not `userId`
  - [x] 2.1.2 `logger.info({user_id})` → emit contains `userIdHash`
  - [x] 2.1.3 `logger.warn({extra: {userId}})` → nested userId NOT renamed (top-level boundary)
  - [x] 2.1.4 Adversarial throw safety: stub `hashUserId` to throw → emit pass-through + one `console.warn`
- [x] 2.2 Wire `formatters.log` into pino factory at `apps/web-platform/server/logger.ts:15-30`. Try/catch wrapper returns `obj` on throw + one-time `console.warn`. Module-scope `formatterErrorReported` flag.
- [x] 2.3 Dev smoke: `doppler run -c dev -- pnpm dev`; trigger one route with userId log; confirm `pino-pretty` shows `userIdHash`.

## Phase 3: PA8 §(c) §(ii) wording update

- [x] 3.1 Edit `knowledge-base/legal/article-30-register.md:157` PA8 §(c) §(ii). Replace with the single-path explanation drafted in plan Phase 3.1 (explicit `formatters.log()` citation; forward-reference to #3710 for Sentry symmetric coverage; forward-reference to §(f) for retention).

## Phase 4: ADR-029 (rename-at-boundary) + persistent CI gate

- [x] 4.1 Confirm ADR-029 (`knowledge-base/engineering/architecture/decisions/ADR-029-rename-at-boundary-userid-pseudonymisation.md`) is committed (already authored during planning).
- [x] 4.2 Add CI gate to `.github/workflows/lint.yml` (or PR-triggered workflow): `lint-userid-bypass` step that runs the bypass-grep on PR diff. Allowlist: `github-resolve/callback/route.ts:1\d+` (the leave-and-cover info site).
- [x] 4.3 Test CI gate locally: simulate a PR diff adding `logger.error({userId: 'x'})` to a scratch file → grep returns it → step fails. Remove scratch file before commit.

## Phase 5: Verification, multi-agent review, follow-ups

- [x] 5.1 Confirm follow-up issues #3710 (PR-B) and #3711 (PR-C) exist and link this PR. (Already filed during planning.)
- [x] 5.2 Run full test suite: `bun test apps/web-platform/` — all green.
- [x] 5.3 Type check: `cd apps/web-platform && tsc --noEmit` — zero errors.
- [ ] 5.4 Mark PR #3701 ready for review.
- [ ] 5.5 Trigger `/soleur:review` multi-agent panel. `user-impact-reviewer` auto-invokes per `single-user incident` threshold.
- [ ] 5.6 Address review findings inline per `rf-review-finding-default-fix-inline`. *(Pending /soleur:review)*
- [x] 5.7 Two-clause verification:
  - [x] 5.7.1 Helper-routed: 46/46 tests green across userid-pseudonymize, logger-formatters, observability, observability-pepper-unset, observability-mirror-debounce.
  - [x] 5.7.2 Direct-bypass: actual baseline is 61 sites (not 11 — plan-time research undercount; inventory drift documented in commit `c3783799`). ALL covered by formatters.log at the pino boundary. CI gate at Phase 4.2 enforces baseline for future PRs.

## Phase 6: Merge + post-merge

- [ ] 6.1 Squash-merge PR #3701. PR body uses `Closes #3698`.
- [ ] 6.2 SSH prod host: `ssh root@135.181.45.178 'docker logs --tail 200 web-platform-app | grep -E "userIdHash|userId" | head -20'`. Confirm `userIdHash` present, no raw `userId` in fresh emissions.
- [ ] 6.3 CI gate smoke test: throwaway PR adding `logger.error({userId})` is rejected by `lint-userid-bypass`. (Optional; the gate is also exercised by every future PR.)
- [ ] 6.4 Close #3698. Verify #3710 and #3711 follow-ups remain open and queued for next sprint.
