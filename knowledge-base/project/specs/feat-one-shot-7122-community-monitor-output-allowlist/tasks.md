# Tasks: schema-constrained publication path for cron-community-monitor (#7122)

Plan: `knowledge-base/project/plans/2026-10-06-fix-community-monitor-output-allowlist-plan.md`

Run tests from `apps/web-platform` with `./node_modules/.bin/vitest run <file>`.

## Phase 0: RED tests and spikes

- [x] 0.1 Write `test/server/inngest/cron-community-publication.test.ts` (leaf-injection over leaves derived from the metrics table with a count floor; unknown-key rows on every object; must-PASS non-canonical draft; rendered-grammar fuzz; constructor-allowlist source test; codes exclude `unrecognized_keys` names).
- [x] 0.2 Write `test/server/inngest/cron-community-monitor-allowlist.test.ts` (`decide()` over the lines `buildAllowlistLines` produces; `no-file-tools` denies Read/Glob/Grep/Write/Edit/MultiEdit/Task/Agent/Skill and is per-cron; the reproduced bypass probes and `gh issue list --jq env` denied; posting verbs `bsky post`, `linkedin post-content`, `x post-tweet` denied and still present in the scripts; prompt-parity over every router literal; one spawned-hook row through `runHookSelfTest`).
- [x] 0.3 Write `test/server/inngest/cron-community-monitor-publication-flow.test.ts` (valid, replay, issue-exists-digest-absent recovery via PATCH on a closed issue, invalid/missing/oversized, timeout, non-zero exit with valid message, sidecar red/missing override, list-read throws, 5xx retry, milestone failure, PATCH-target checks, commit failure PATCHes the notice, token custody by permissions, both tokens redacted, audit fallback uses the installation client).
- [x] 0.4 Add `no-file-tools` rows to `test/server/inngest/cron-bash-allowlist-hook.test.ts`; extend `exactPaths`/`isPathAllowed`/count-marker rows in `cron-safe-commit.test.ts`; add `finalMessage` rows to the substrate suite and `withholdModelOutput` rows to `cron-shared.test.ts`.
- [x] 0.5a Spike S3: confirm no prompt step needs a file-reading tool (evidence: the 2026-10-05 digest note "output exceeded inline limit"); if one does, switch to the `read-root` allow-list fallback in the plan and record it in ADR-272.
- [x] 0.5 Spike S2: confirm the read-permission set against `apps/web-platform/infra/github-app-manifest.json` and GitHub's per-endpoint table; confirm `mintInstallationToken` accepts it.
- [x] 0.6 Run the new suites; confirm each fails for the expected reason.

## Phase 1: publication module

- [x] 1.1 Create `server/inngest/functions/_cron-community-publication.ts`: metrics table with realistic caps, strict schema (constructor allowlist, safe-integer bounds, topic uniqueness), `parseCommunityDraft`, `readFinalMessage`, `renderCommunityPublication` (with github override), contained digest write (lazy `node:fs`), `upsertDigestIssue` (fail-closed read, bounded retry, milestone lookup).
- [x] 1.2 Make 0.1 green.

## Phase 2: safe-commit hardening

- [x] 2.1 `exactPaths` on `SafeCommitConfig` with one shared `isPathAllowed`; count-only marker in exact mode; update log/comment strings.
- [x] 2.2 Make the `cron-safe-commit` rows green; confirm the other 14 callers' marker is byte-identical.

## Phase 3: containment closure

- [x] 3.1 Replace the community allowlist with `COMMUNITY_ROUTER_READ_VERBS` only (no `gh` verbs at all); `allow[0]` is a full literal command.
- [x] 3.2 Add the `no-file-tools` directive: producer (`CRON_NO_FILE_TOOLS`), hook consumer, `runHookSelfTest` probe, parity-test directive regex; add `SpawnResult.finalMessage`/`finalMessageTruncated` in the substrate.
- [x] 3.3 Add `--disallowedTools Read,Glob,Grep,Write,Edit,MultiEdit,NotebookEdit,Task,Agent,Skill` and set `--allowedTools Bash` in `CLAUDE_CODE_FLAGS`.
- [x] 3.4 Add `filer: "agent" | "handler"` to `_cron-run-reports.ts`; derive `CRON_RUN_REPORT_LABELS` from agent rows only; split parity row (ii); fix the counts and fixtures in `cron-claude-eval-substrate.test.ts`; remove community from the `RESTORED` loop.
- [x] 3.5 Register the allowlist suite in `test/repo-wide-suites.ts`.

## Phase 4: handler flow and prompt

- [x] 4.1 Rewrite the prompt (one-line compact-JSON final-message contract with generated example, `discord messages` literal, PERSISTENCE anchor line only, remove brand-guide/issue/milestone/quotes/contributor/`gh issue list` text).
- [x] 4.2 Wire the steps in order: claude-eval, verify-collector-status (moved up), skip all below on timeout, validate-publication (parse, render, contained write), mint-write-token and re-point origin, publish-issue (upsert; PATCH never reopens), verify-output, `heartbeatOk = (verifyOutputOk || via==="patched") && publication.ok`, the unchanged persistence gate, safe-commit-pr with `exactPaths` (idempotent digest re-write first; on non-committed, PATCH the issue to the fixed notice). Audit fallback takes the `createProbeOctokit()` client.
- [x] 4.3 Drop `DISCORD_WEBHOOK_URL` from `buildSpawnEnv`; update anchors in `cron-community-monitor.test.ts`.
- [x] 4.4 Rework the heartbeat/dedup/collector-status fixtures (shared `validDraftFinalMessage()`, fake-store routes, publish seam).

## Phase 5: failure path and credential custody

- [x] 5.1 `withholdModelOutput` in `ensureScheduledAuditIssue`; community passes true.
- [x] 5.3 Observability: all-tools `permissionDenialCount`/`deniedTools`, warn op `community-agent-denied-verb`, extras on `community-publication-rejected`, marker 3 `verdict`/`writer`.
- [x] 5.2 Read token (keep `repositories`) for clone and spawn (`COMMUNITY_SPAWN_TOKEN_PERMISSIONS`), post-spawn write token, `setOriginToken` helper, redact both tokens in every `catch`.

## Phase 6: records

- [x] 6.1 ADR-272 (re-verify the ordinal at ship), including the RED-streak trigger and the forward-path-only claim.
- [x] 6.2 C4: `api -> kb` edge text; regenerate `model.likec4.json` and the mirror; run the C4 tests and `c4-model-freshness`/`c4-count-parity`.
- [x] 6.3 Legal: register PA-32 (a)/(c)/(f)/(g) and PA-31 (g), posture rows (#7119, #7122 stays OPEN for daily-triage, cite #9606), DPIA residuals and triggers, LIA R4 row, `statutory-response-catalog.md`/`ccla-register.md` check; append-only supersede markers; no `docs/legal/` edits.
- [x] 6.4 CLO attestation `knowledge-base/legal/audits/2026-10-clo-attestation-7122.md` with re-evaluation triggers.
- [x] 6.5 Runbook entry (day lost and not retried, no action for one occurrence, three REDs trigger, first-RED-after-deploy note, format discontinuity).
- [x] 6.6 Run `soleur:gdpr-gate` on the diff.

## Phase 7: verification

- [x] 7.1 `./node_modules/.bin/tsc --noEmit`; the full vitest list from the plan's Acceptance Criteria; `issue-flow-measure.test.sh`; `lint-guard-contract.py`.
- [ ] 7.2 After merge: fire the manual trigger with `soleur:trigger-cron`, poll (bounded) for the issue, the Sentry check-in and the digest on main; check for `collector-status-failed`.
- [ ] 7.3 PR body: first line on redeploy and rollback, `Closes #7122`, `Relates to #7119`, link the Decision Challenge.
