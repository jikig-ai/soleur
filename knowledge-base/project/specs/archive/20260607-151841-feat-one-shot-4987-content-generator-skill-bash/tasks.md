# Tasks — #4987 content-generator skill + build-validation fix

Single domain (Inngest cron producer). Both code changes land in one file
(`apps/web-platform/server/inngest/functions/cron-content-generator.ts`); tests in
`apps/web-platform/test/server/inngest/cron-content-generator.test.ts`.

## Phase 1 — Flags: skill + plugin-dir resolution (AC1, AC2)
- [x] RED: tests assert `CLAUDE_CODE_FLAGS` source contains `Skill` + `Task` in the
      `--allowedTools` value, `--plugin-dir`+`plugins/soleur` before `--`, and `--max-turns 50`
      unchanged. (4 meaningful failures confirmed pre-impl.)
- [x] GREEN: `CLAUDE_CODE_FLAGS` — `--allowedTools` now `…WebSearch,WebFetch,Skill,Task`;
      `"--plugin-dir", "plugins/soleur",` inserted before `"--"`; argv comment expanded.

## Phase 2 — Prompt STEP 4: CI-deferred validation (AC3)
- [x] RED: test asserts STEP 4 mentions CI validation + `no node_modules` and no longer
      reads as a bare local-build imperative gate. `@11ty/eleventy` anchor description
      updated to "CI Eleventy build validation".
- [x] GREEN: `CONTENT_GENERATOR_PROMPT` STEP 4 rewritten to CI-defers-validation text,
      preserving `@11ty/eleventy` + `validate-blog-links` anchor strings.

## Phase 3 — Exit gate (AC4)
- [x] cron-content-generator + cron-claude-eval-substrate + cron-producer-output-wiring
      green (77 passed); whole server/inngest dir + cron-substrate-imports green (1502).
- [x] `./node_modules/.bin/tsc --noEmit` in apps/web-platform green.
- [x] Orphan-suite check: no shell/bun/plugin test references the changed flags/prompt
      symbols (`git grep` clean) → targeted inngest sweep is the authoritative gate for
      this localized const-string change; full `test-all.sh` adds no coverage here.
