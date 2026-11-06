# Tasks — fix: Warn when Discord blog webhook falls back to general channel

Plan: `knowledge-base/project/plans/2026-10-29-fix-discord-blog-webhook-fallback-warning-plan.md`

## Phase 1 — Script-side warning + marker (RED first)

- [x] 1.1 In `test/content-publisher.test.ts`, `describe("post_discord webhook URL resolution")` (~:660): extend the "falls back to DISCORD_WEBHOOK_URL when blog URL not set" test to assert `result.stderr` contains `SOLEUR_PUBLISHER_FALLBACK`; extend the "uses DISCORD_BLOG_WEBHOOK_URL when set" test to assert it does NOT; extend the "skips posting when no webhook URLs set" test to assert no marker; add an empty-string case (`DISCORD_BLOG_WEBHOOK_URL=""` + general set → marker fires). (AC-1..AC-4)
- [x] 1.2 In `scripts/test-content-publisher.sh`, add stderr-capture assertions using the existing `tmp_stderr=$(mktemp -p "$SUITE_TMP")` + `grep -q` pattern (:100-114): marker present when only `DISCORD_WEBHOOK_URL` set; marker absent when `DISCORD_BLOG_WEBHOOK_URL` set. (AC-1, AC-2)
- [x] 1.3 Run both suites and confirm the new assertions FAIL (warning not yet implemented): `bun test test/content-publisher.test.ts` and `bash scripts/test-content-publisher.sh`.

## Phase 2 — Core implementation (GREEN)

- [x] 2.1 `scripts/content-publisher.sh` `post_discord()` (~:330): after the `[[ -z "$webhook_url" ]]` early-return, add the `[[ -z "${DISCORD_BLOG_WEBHOOK_URL:-}" ]]` stderr warning carrying `SOLEUR_PUBLISHER_FALLBACK` — fixed strings only, never the URL. (AC-1, AC-5)
- [x] 2.2 `scripts/content-publisher.sh` header env-var block (:9-12): document that an unset/empty `DISCORD_BLOG_WEBHOOK_URL` emits a stderr warning + `SOLEUR_PUBLISHER_FALLBACK` marker when the general fallback is used. (AC-9)
- [x] 2.3 `apps/web-platform/server/inngest/functions/cron-content-publisher.ts`: add `warnSilentFallback` to the `@/server/observability` import; add exported pure helper `publisherStderrSignals(stderr: string): string[]` (returns matched `SOLEUR_PUBLISHER_FALLBACK` signal tokens); in `run-publisher-script`, call it on `result.stderr` and on match emit `warnSilentFallback(null, { feature: "cron-content-publisher", op: "discord-blog-webhook-fallback", message: <fixed string>, extra: { fn } })`; extend step return to `{ exitCode, discordBlogFallback }`. Do NOT touch `PUBLISHER_ENV_KEYS`/`buildPublisherEnv`. (AC-7, AC-8)
- [x] 2.4 Re-run 1.3's suites — all assertions green. Verify `allowed_mentions: {parse: []}` and resolution order unchanged (AC-6: `git diff` on those lines shows only added code).

## Phase 3 — Cron-side tests + verification

- [x] 3.1 `apps/web-platform/test/server/inngest/cron-content-publisher.test.ts`: unit tests for `publisherStderrSignals` (marker mid-stream → matched; absent → empty) + source-shape anchors for `SOLEUR_PUBLISHER_FALLBACK` and `op: "discord-blog-webhook-fallback"`; assert `PUBLISHER_ENV_KEYS`/`buildPublisherEnv` blocks unchanged (AC-7 via existing allowlist suite).
- [x] 3.2 Typecheck: `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit` (the repo has no `workspaces` field — never `npm run -w`).
- [x] 3.3 Shell-lint baselines clean: `lint-shell-capture-exit` and `lint-shell-trace-credential-refusal` show no new violations for `scripts/content-publisher.sh` (AC-10).
- [x] 3.4 Confirm `scripts/content-publisher.test.sh` (the residue suite, separate file) needs no change — it does not exercise `post_discord` webhook resolution.
- [x] 3.5 Verify AC-5: grep added emit sites for `$webhook_url`/`${DISCORD_*}` interpolation → zero hits.
