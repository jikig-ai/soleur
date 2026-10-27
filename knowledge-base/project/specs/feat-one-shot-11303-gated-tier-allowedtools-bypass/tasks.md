# Tasks: fix(security): gated approval tier bypassed by allowedTools (#11303)

Plan: knowledge-base/project/plans/2026-10-27-fix-gated-tier-allowedtools-bypass-plan.md
Branch: feat-one-shot-11303-gated-tier-allowedtools-bypass | Draft PR: #11304

## Phase 0: Setup and premise measurement (no commit)

- [ ] 0.1 `git fetch origin main origin/feat-hitl-approval-queue`; confirm no `buildAllowedTools` / probe on origin/main
- [ ] 0.2 Baseline vitest on touched suites + `tsc --noEmit`
- [ ] 0.3 Re-derive the platform tool census from the builders (counts derived, never hard-coded)
- [ ] 0.4 Cherry-pick `0acc541b6f` with `-n` into the working tree; scratch-edit the prompt to a plain string; run `PROBE_ONLY=email_send:no-allowed` against Doppler `ci` (never prd); expect `invoked=yes`; capture the `CAN_USE_TOOL_SHADOWED` line format. STOP and re-plan if `invoked=no`
- [ ] 0.5 Confirm ws-handler late-click behaviour; `rg "User rejected the action"` in tests

## Phase 1: Gate lifecycle (commit 1)

- [ ] 1.1 RED: `test/permission-callback-platform-gate-expiry.test.ts` (timeout, abort with controller aborted [both reasons], per-call abort, approve, reject, status-write failure hold/restore, concurrent gates, gate + Bash stacking, `agentID`, Bash regression, in-window status observation)
- [ ] 1.2 GREEN: `holdForUser` options object + `gateClass`; gated branch via `holdForUser`; skip `active` write when `ctx.controllerSignal.aborted` (platform only); static deny texts; ops `platform-gate-status-hold|restore` with own static messages
- [ ] 1.3 Commit `fix(security): gated platform-tool gate fails closed on expiry and restores status (#11303)`

## Phase 2: The filter (commit 2)

- [ ] 2.1 RED: `test/build-allowed-tools-census.test.ts` (unit census, in-suite mutation battery, registered-name explicit-entry check, `buildAgentQueryOptions` assertion cases incl. bare server name and wildcards and real `CC_PATH_ALLOWED_TOOLS`, frontmatter sentinel, gate-message test)
- [ ] 2.2 RED: flip `agent-runner-tools`, `agent-runner-kb-share-tools`, `email-triage-tools` presence assertions; switch `kb_share_create` verbatim sites (`agent-runner-query-options.test.ts` 221/498, `agent-runner-helpers.test.ts` 422) to `kb_share_list`; add `startAgentSession` wiring test
- [ ] 2.3 GREEN: `buildAllowedTools` + `conversations_lookup` auto + explicit gated entries (`plausible_*`, `account_*`) + six `buildGateMessage` cases in `tool-tiers.ts`
- [ ] 2.4 GREEN: `agent-runner.ts` call site; `agent-runner-query-options.ts` fail-closed assertion; comment refresh
- [ ] 2.5 Run production-code mutation rows (Guard 1 rows 1, 4, 5, 6) via edit + `git checkout -- <file>`; record RED evidence
- [ ] 2.6 Commit `fix(security): stop pre-approving gated platform tools via allowedTools (#11303)`

## Phase 3: Real-SDK probe (commit 3)

- [ ] 3.1 Keep only `apps/web-platform/scripts/dev-probe-approval-gate.ts`; drop `phase-0-measurements.md`
- [ ] 3.2 Switch to `buildAllowedTools`, full derived legacy name set, production string prompt, drop `:no-allowed`, add `email_send:raw` canary and `email_send:prod-stream`, builder-import failure = CANT-RUN, update header and floor
- [ ] 3.3 Run against Doppler `ci`: expect `RESULT: PASS`; paste PROVENANCE/REGISTRATION/PROBE lines for the PR body
- [ ] 3.4 Fix stale comment in `dev-probe-destroy-ask.ts` only if Phase 0.4 contradicts it
- [ ] 3.5 Commit `test(approval): real-SDK probe builds allowedTools via buildAllowedTools; prod rows now invoke canUseTool (#11303)`

## Phase 4: ADR (commit 4)

- [ ] 4.1 `soleur:architecture create` ADR (ordinal re-verified vs origin/main); run `plugins/soleur/test/c4-count-parity.test.sh`
- [ ] 4.2 Confirm no legal text / compliance-posture / flag file changed
- [ ] 4.3 Commit `docs(adr): gated-tier platform tools never enter SDK allowedTools`

## Phase 5: Verify and ship

- [ ] 5.1 `tsc --noEmit`, vitest (touched + new), eslint, markdown lint, `lint-guard-contract.py`
- [ ] 5.2 PR body: first line behaviour-change answer + changelog line; CLO ruling; plugin-wildcard residual risk; #11289 conflict note; `Closes #11303`; probe lines; RED evidence
- [ ] 5.3 One comment on PR #11289 about the probe add/add conflict (no new issue)
- [ ] 5.4 Post-merge: `soleur:postmerge` deploy verification; absence check on soleur-web-1 and soleur-web-2 with generated gated-name list; record verdicts on PR and #11303 (exit 2 = unobserved, not clean)
