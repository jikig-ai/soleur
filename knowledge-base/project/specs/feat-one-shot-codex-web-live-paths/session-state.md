# Session State

## Work Phase
- Plan file: `knowledge-base/project/plans/2026-09-27-feat-codex-web-live-handler-wiring-plan.md`
- Status: partial implementation; production qualification and required review gates pending

### Errors
- An initial multi-file patch did not match the current RPC upsert clause, so `apply_patch` applied none of that patch. The exact migration and source ranges were reread, and the change is now split into smaller edits.
- A WebSocket test suite currently verifies synthetic Codex bridge composition through real handler branches, but production runtime composition intentionally fails closed: no live App Server launcher is supplied, managed credentials are not composed, and egress evidence is unverified.
- No Inngest consumer reads `engine_run_id`; `cron-daily-triage`, `cron-bug-fixer`, and `cron-content-generator` execute specialized Claude prompts. Keep Codex routine binding rejected.
- Durable native thread checkpoint/restart, client-turn idempotency, actionable approvals, usage persistence/presentation, actual transport egress, and provider lifecycle parity remain unimplemented or unverified.
- The authorized Soleur Workspace owner relationship was read-only verified. No valid OpenAI API key was present; no provider request or flag mutation was made.
- The owner confirmed on 2026-09-28 that changing Codex auth mode must affect existing conversations. Updated plan review found that switched conversations use each resumer's own user-scoped key, not the workspace owner's key; missing keys must fail closed. The switch must preserve transcript context, clear old provider recovery state, fence stale requests/checkpoint writes, and affect only an explicit auth-mode change (not an engine change). Codex is settings-selectable while execution rollout remains off; choosing it does not change the persisted workspace default.
- Workspace-wide Codex auth-mode rebinding remains dashboard-only in this rollout. The live `cc-dispatcher` exposes no platform MCP tools, and this operation needs an explicit owner confirmation; an agent equivalent remains deferred until the platform-tool allowlist supports the same identity, scope, and confirmation checks.
- The CLO assessment recorded separate PENDING/no-authorization dispositions for API-key and managed modes; neither qualifies for an internal synthetic cohort yet.
- The first bounded full suite exposed a DSAR allowlist completeness failure for migration 143. Added scoped attempt/checkpoint export metadata, then reran the full suite successfully: 15,315 passed, 385 skipped, 1 todo.
- Local Supabase migration probe initially caught a PL/pgSQL CASE-expression syntax error; the migration was corrected and then passed apply, duplicate-key/state-transition/erasure checks, and rollback on the loopback-only local database. No production migration was applied.
- The public repository check caught the owner's email in an uncommitted qualification edit; it was removed before staging and a learning was added.
- A shell inventory probe returned nonzero from a trailing `&&`; it was rerun with valid syntax.
- An early direct full-suite invocation was interrupted with exit 130 after fixture log volume overwhelmed the terminal; the captured rerun completed, and 130 was not a suite verdict.
- `db:status` returned 127 because `supabase` was absent from PATH; `npm exec --package=supabase` recovered the CLI and exposed the stopped local stack.
- The first async question-tool call used the wrong field name; the request was retried with the active `{title, options}` schema.
- A plan-context search referenced `spec.md`, but this feature spec contains only `session-state.md` and `tasks.md`; the branch plan correctly records that no `spec.md` exists.
- Pencil automatic setup failed while building the optional headless adapter's `sharp` dependency (`Please add node-addon-api to your dependencies`). The installed Pencil CLI was detected, but this session has no Pencil MCP tools.
- The owner-settings browser navigation redirected to `/login`; no sign-in code was sent and no credentials were entered or exposed.
- Two implementation subagents hit the Codex usage limit; their incomplete findings were independently checked against source before proceeding.
- The current-main session-start cleanup could not pull because this worktree has uncommitted changes. It safely skipped the pull; a bounded `git fetch origin main` updated the ref to `ec5b2fcede99602edfee43961d77e4dd5677fb10` for deliberate reconciliation.
- An initial focused combined test run failed because the resumed-WebSocket synthetic stream ended without a terminal event. The fixture now emits `completed`; the same focused set passes 120/120.
- The TOM-4 mutation test first removed one trigger where a second trigger shared the same WORM function, so the gate correctly remained green. The mutation now drops a uniquely attached function and proves assertion 24 fails.
- Pencil format validation is unresolved: installed `@pencil.dev/cli@0.2.9` does not read the committed format 2.18 wireframe. Installing `@pen.dev/cli@0.3.9` failed during `sharp` setup (`Please add node-addon-api`), and the retry ended after repeated tar `Unknown system error -122` errors. No wireframe or screenshot was changed.
- One read-only discovery command ended with a dangling `&&` and returned shell syntax error; it was rerun successfully without the extra operator. An attempted fixture cleanup command using `rm -rf` was rejected by the shell command guard; no files were removed by that attempt.

## Verification as of 2026-09-27

- Focused conversation, persistence, migration, and DSAR suites: 58 tests passed; legal-document suites: 43 tests passed.
- Full Web Platform suite: 1,163 files passed, 55 skipped; 15,315 tests passed, 385 skipped, 1 todo.
- `tsc --noEmit`, server build, legal SHA guard, legal mirror-drift ratchet, and migration FK precondition lint passed. ESLint reported three existing `ws-handler.ts` fallthrough warnings and no errors.
- Production runtime qualification, API-key and managed Web matrices, eligible routine consumer, and mode-specific authorization remain blocked or incomplete as stated above.

### Decisions
- Write failing tests through the real WebSocket and routine/Inngest paths first.
- Implement ADR-233 durable turn attempts, event sequences and protected checkpoints before qualifying multi-turn execution.
- Enforce egress at the actual App Server boundary, with separate API-key and managed qualification.
- Require mode-specific CLO disposition before any corresponding cohort change.
- Preserve fail-closed behavior where the real runtime or a routine consumer is absent; synthetic handler tests do not count as live qualification.
- Keep the PR draft until independent review, remaining code gaps, and mode-specific authorization gates are resolved; no flag or customer-processing state has changed.
- A workspace owner changing Codex auth mode updates existing Codex conversation runs, while the engine ID remains stable. Clear old-account recovery handles before dispatching with the newly selected credential source. Do not update Claude bindings or routine runs.
- An automatic auth-mode fallback caused by changing the selected engine must not be treated as an explicit auth-mode change or rewrite existing Codex bindings.
- Keep the visible workspace default distinct from local Codex settings selection; the settings-only Codex choice must not imply that new conversations will dispatch to Codex.
- Persist Codex auth mode separately from the active workspace default so reopening settings restores the mode applied to existing Codex conversations.

### Components Invoked
- `soleur:one-shot`, `soleur:plan`, `soleur:deepen-plan`, `soleur:spec-templates`, `soleur:gdpr-gate` advisory, and conditional CPO/CTO plan review.

## Verification as of 2026-09-29

- Current focused Codex/legal Vitest set: 10 files passed, 120 tests passed, including two disposable-local-PostgreSQL migration/RPC cases and the exact production-composition fail-closed boundary tests. The database cases dropped both test databases.
- TOM-4 posture gate: 24/23 assertions passed; mutation suite 15/15 passed, including the dropped-trigger attachment regression and explicit mutable-table WORM exclusions.
- Codex rebinding-focused Vitest: 4 files/43 tests passed. Dev-ledger parity: 256/256. `git diff --check` passes.
- Main advanced to `ec5b2fcede99602edfee43961d77e4dd5677fb10`; this branch has not yet reconciled that update. The branch remains draft PR #9051, with current pushed head `89f7eaf6556f0cee74ed15fbfa0cbfc6981eba3d`.
- Doppler dev_scheduled names-only check found no secret names containing OPENAI or CODEX. No API key or managed credential was available, no provider request was made, no feature flag changed, and both CLO dispositions remain PENDING/no authorization.
- The verified work closes reviewed persistence, terminal-attempt, auth-mode UI state, WORM disclosure/provenance and migration lock-budget findings. Full current-main suite, review trailer, UI screenshot QA, production composition, eligible routine consumer, both-mode synthetic Web qualification and CLO dispositions remain incomplete.
