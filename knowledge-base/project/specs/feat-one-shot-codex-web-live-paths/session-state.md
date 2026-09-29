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
- The resumed `test/ws-resume-by-context-path.test.ts` synthetic Codex stream failed the new terminal-status contract; the fixture now emits `completed`, and its full 14-test file passes.
- The first refreshed CI RLS run rejected a lifecycle object because the test supplied `JSON.stringify(...)` as a text parameter, which PostgreSQL cast to a JSON string scalar. Replaced it with `t.json(...)`; a local driver probe confirms `jsonb_typeof` is now `object`, and the refreshed CI RLS job passes.
- The rename guard detected a historical mainline rename inside an old merge commit. The feature branch was collapsed onto the latest main tree as one reviewable feature commit, removing that unrelated merge history; the refreshed rename-guard job passes.
- The affected local `bun-test` hook was explicitly excluded after the full run exceeded 50 minutes and the user approved relying on CI. Focused Codex tests, typecheck, server build, and all other applicable pre-commit hooks passed; required CI remains the full-suite gate.
- A search included a nonexistent `apps/web-platform/app/api/routines` path; the repository search reported that path absent. The current `runRoutine()` callers were then enumerated from existing server and dashboard route paths.
- One `apply_patch` hunk for the learning file omitted a `+` prefix and was rejected without changing the file; the patch was reread and applied correctly.
- An inspection guessed the affected runner lived at `scripts/test-all-affected.sh`; that path does not exist. The failing regression was traced through the tracked `scripts/test-all-affected.test.sh` fixture and current main's fix.
- A PR-check `jq` filter had incorrect pipeline precedence and tried to index a string; parenthesizing the name predicates fixed the query. The unfiltered `gh pr checks --watch` repeated the full check list and exceeded the output budget; it was stopped and replaced with bounded status queries.

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

- Previously completed focused Codex/legal Vitest set: 10 files and 120 tests passed, including two disposable-local-PostgreSQL migration/RPC cases and production-composition fail-closed boundary tests; both test databases were dropped. Separate Codex rebinding-focused tests passed 43/43, and the resumed-WebSocket file passed 14/14. `tsc --noEmit`, server build, legal SHA/mirror guards, migration FK precondition lint, and dev-ledger parity (256/256 at that point) passed.
- The complete local Web Platform suite is intentionally skipped at the operator's direction; prior full run passed 15,315 with 385 skipped and 1 todo. Current local verification for the review fix: `scripts/check-tom4-rls-posture.test.sh` passed 16/16 mutation cases, including the new disabled-WORM-trigger case; the posture gate passed 24/24 assertions; `git diff --check` passed. No current full-suite result is claimed.
- Current `origin/main` is `9198fc924292f7f92bee00b17749ba223b0d7bcf` (PR #9220), merged into the feature branch at `5bec1bcde1d527c747b6f380e18319f6beb8cb4d`. Latest pushed feature head is `39868fc638766dc2e4e982e3e95deb0bb9c0e192`. PR #9051 remains draft and blocked.
- CI on the earlier pushed head `131a7351a7ec7fd4a8cf0e951e088d582144b6d7` failed tenant migration-ledger parity because shared dev has orphaned `144_codex_auth_mode_rebind.sql` while this PR owns ordinal 145. No shared database mutation was made. Two smoke jobs failed the pinned Gitleaks 8.24.2 archive checksum; the pin is still present on current main and has not been changed. A fresh full CI run on the merged head is still required.
- Full CI on pushed head `c29eabcf71413fc8647c11dc7c5af99d5c293a90` passed `test-bun`, both Web Platform shards, all heavy script shards, six of seven regular script shards, build, E2E, RLS fuzz, CodeQL and other security checks. Regular script shard 3/7 failed because two `test-all-affected` assertions expected `tests/hooks/incidents` in the always-on selection (`s1`/`s2` reported `ran=0`). Current main's merged PR #9220 removed those two stale assertions; main has now been merged locally to the feature branch and CI must rerun on the new head. The tenant-integration parity check also failed on the orphaned migration described above.
- The complete CI test matrix passed on pushed head `39868fc638766dc2e4e982e3e95deb0bb9c0e192`: all seven regular script shards, all three heavy script shards, both Web Platform shards, `test-bun`, build, E2E and other code/security checks succeeded. Only `tenant-integration` and its required aggregate failed, both at the same shared dev-ledger parity refusal. PR #9051 is `BLOCKED` and remains draft; no admin merge was attempted because required CI is red and runtime/CLO qualification gates remain open.
- A dry run of `dev-ledger-reconcile.yml` for PR #9051 made no database changes and refused reconciliation: the paired down migration for `143_agent_engine_attempts.sql` is destructive/CASCADE while two later rows exist (`144_pending_checkout_sessions.sql` and `144_codex_auth_mode_rebind.sql`). Its diagnostic was posted to the PR. No `--execute` or `--allow-later-rows` dispatch was made.
- Doppler dev_scheduled names-only check found no secret names containing OPENAI or CODEX. No API key or managed credential was available, no provider request was made, no feature flag changed, and both CLO dispositions remain PENDING/no authorization.
- The reviewed persistence, terminal-attempt, auth-mode UI state, WORM disclosure/provenance and migration-lock findings are addressed. Repeated run/binding reads were reduced and covered by focused tests. The migration posture guard now models enabled/disabled WORM triggers; its new mutation test was shown red before the implementation and passes now. The real WebSocket test pins the auth mode/generation sent to the attempt-admission RPC and verifies stale-generation rejection emits no stream or Claude call; removing the fixture generation made both Codex-path tests fail, then restoring it passed the focused file 8/8. The push hook's Web Platform typecheck also passed.
- `runRoutine()` still rejects non-Claude persisted bindings, and no scheduled Inngest consumer reads `engine_run_id`; current scheduled crons have specialized Claude behavior and none is an eligible Codex routine. Do not synthesize routine semantics.
- The settings auth-mode mutation intentionally remains an authenticated owner UI/API action: it changes credential routing workspace-wide and already requires affected-count/provider/billing confirmation. Agent-tool parity is deferred until the same identity, scope and confirmation contract can be provided; this disposition is recorded in `decision-challenges.md`.
- Review panel, review trailer, screenshot QA, runtime composition, a qualifying routine consumer, separate API-key/managed synthetic Web matrices, and mode-specific CLO dispositions remain incomplete. Latest code-quality review found no actionable quality issues; test-design rated coverage 7.6/10 (B) and its handler-generation finding is resolved; latest Semgrep scan of 30 changed TS/JS files ran 218 rules with zero findings. No authorized runtime API key or managed synthetic credentials were available; no provider request or feature-flag change was made. Keep the feature default-off and customer processing blocked.

## Verification as of 2026-09-29 continuation

- The operator identified the authorized synthetic workspace as “Soleur Workspace” and confirmed browser sign-in. The headed browser session subsequently showed the sign-in page, so credential readiness could not be verified. No credential value was read, no provider request was made, and no runtime qualification is claimed.
- The operator clarified that neither API-key nor managed mode has CLO authorization yet. Both mode-specific dispositions remain PENDING; no cohort or feature flag may change.
- Current main advanced to `b1ad9fb0d6d5fee88f553791fd3604b5e0d4b34d` (#9201). It was merged without conflicts into `feat-one-shot-codex-web-live-paths`; the merge adds unrelated current-main Inngest pin and architecture updates. A fresh CI run is required for the new head.
- Before resync, all code/security checks on `1c772267229889f913a55c3c666c47b1ebe5d4fa` passed, including all seven script shards, all three heavy shards, both Web Platform shards, build, E2E, RLS fuzz and CodeQL. Only `tenant-integration` and `tenant-integration-required` failed, both at the shared dev migration-ledger parity refusal. PR #9051 remained draft and `BEHIND`; no merge was attempted.
- An agent-browser snapshot attempt was blocked by the credential-redaction hook because the command shape was not accepted as routed through the redactor. No unredacted snapshot was captured. Subsequent browser output used the approved redactor pipeline.
- CI completed on `80cec9301000dc869288cf1b9671652f41e52b97` with all code, security, and test checks passing. Only `tenant-integration` and `tenant-integration-required` failed on the same orphaned `144_codex_auth_mode_rebind.sql` parity violation. PR #9051 remains draft and blocked; no merge or shared database mutation occurred.

## Verification as of 2026-09-29 latest-main resync

- Current main `37bbb82361c086a1e907ed87b521e3687728b816` is an ancestor of the feature branch. Latest pushed head is `b712c4d6feee97fe850a1603abb23520c2ac4991`; GitHub PR #9051 now reports that head and base correctly.
- All 89 check runs on `b712c4d6feee97fe850a1603abb23520c2ac4991` completed: 87 passed, with only `tenant-integration` and `tenant-integration-required` failing on the dev migration-ledger parity check for orphaned `144_codex_auth_mode_rebind.sql`. RLS fuzz passed. An earlier run on head `814c2c2f04b0f2b05c46378c0cd1f40fafa685df` had an RLS test deadlock while dropping `conversations_engine_binding_state_insert`; it did not recur on the current head.
- The operator said they logged into Slack; that does not verify the Soleur workspace browser session or Codex runtime credentials. Both CLO dispositions remain PENDING, and no provider calls or feature-flag changes occurred.
- The required session-start `cleanup-merged` ran successfully. A previous sandboxed session could not acquire its cleanup lock because `.git` was read-only; no cleanup occurred then. The root `.mcp.json` hash matches `origin/main:.mcp.json`, so no refresh write was needed.

## Verification as of 2026-09-29 tenant-parity repair

- CI on `d651afc5110e8474d75d8d669631c48fcabe51b6` confirmed the only required failure was tenant-ledger parity: dev has `144_codex_auth_mode_rebind.sql` at blob `be38bcb39d313de4e24ba44f02cdb47aebc3f00b`, absent from the PR tree. All other reported checks passed.
- Restored that exact migration blob as `144_codex_auth_mode_rebind.sql`; changed `145` to apply only its follow-on schema/function delta and changed `145.down.sql` to restore the `144` schema and function contracts without dropping `144`'s generation columns.
- Added a Git-blob identity regression and adjusted the SQL extractor for `CREATE OR REPLACE`. Focused tests passed: 2 files, 7 tests, including disposable PostgreSQL tests. Migration immutability lint and `git diff --check` passed. The operator-authorized local affected-suite hook was stopped after running over 20 minutes; rely on fresh CI for the full suite and tenant-integration.
- Current `origin/main` is `f1d1dc017fb7822a424fd0c7e9e62190013fa8b6`; it has been merged into the feature branch after the repair. The latest repair commit still needs to be pushed.
- The repair did not write to shared dev or prod. CLO dispositions remain PENDING for both modes; no provider request or feature-flag change occurred.
- Session errors and recovery are recorded in `knowledge-base/project/learnings/workflow-patterns/2026-09-29-ledgered-migration-repair-starts-from-applied-blob.md`.

## Verification as of 2026-09-30 continuation

- All PR #9051 checks completed successfully on head `e37a7ab5d11de3e715cfa95d6e83e1e426957d84`, including `tenant-integration`, `tenant-integration-required`, the aggregate `test` check, all script shards, Web Platform shards, build, E2E, and security checks. That green head predates the latest main commit and does not cover the resync below.
- `origin/main` advanced to `41304fc887` (#9238). A clean merge into the feature worktree produced local head `12852ff7bd0eaa1036f923a3a7a56941715dd12c`; it has not been pushed yet. The PR still points at `e37a7ab5d1` and reports `BEHIND` until the new head is pushed and fresh CI completes.
- `pencil-setup --auto` exited 1: the CLI was detected, but its headless authentication failed; this Codex session exposes no Pencil MCP tools. The member history-transfer UI and its required wireframe remain blocked. The setup script printed `/home/jean/.local/node_modules/.bin/pencil login`; no credential was read or entered.
- No review panel or QA has run on the resynced head. PR #9051 remains a draft. Both mode-specific CLO dispositions remain PENDING/no authorization; no provider request or flag change occurred. Do not merge before the review, QA, member history acknowledgment, synthetic qualification and CLO gates are resolved.
- A diff check caught an extra terminal blank line in the check-run SHA learning. The working copy was corrected; the initial range check was against committed `HEAD`, so use `git diff --check origin/main` for the current working tree and `git diff --cached --check` after staging.
