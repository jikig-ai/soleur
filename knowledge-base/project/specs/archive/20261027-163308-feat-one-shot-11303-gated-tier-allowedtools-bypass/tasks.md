# Tasks: fix(security): gated approval tier bypassed by allowedTools (#11303)

Plan: knowledge-base/project/plans/2026-10-27-fix-gated-tier-allowedtools-bypass-plan.md
Branch: feat-one-shot-11303-gated-tier-allowedtools-bypass | Draft PR: #11304

## Phase 0: Setup and premise measurement (no commit)

- [x] 0.1 `git fetch origin main origin/feat-hitl-approval-queue`; confirm no `buildAllowedTools` / probe on origin/main
- [x] 0.2 Baseline vitest on touched suites + `tsc --noEmit`
- [x] 0.3 Re-derive the platform tool census from the builders (counts derived, never hard-coded)
- [x] 0.4 Cherry-pick `0acc541b6f` with `-n` into the working tree; scratch-edit the prompt to a plain string; run `PROBE_ONLY=email_send:no-allowed` against Doppler `ci` (never prd); expect `invoked=yes`; capture the `CAN_USE_TOOL_SHADOWED` line format. STOP and re-plan if `invoked=no`
- [x] 0.5 Confirm ws-handler late-click behaviour (error must say expired/not performed); `rg "User rejected the action"` in tests
- [x] 0.6 Prove the post-deploy channel: find a historical `CAN_USE_TOOL_SHADOWED` row in Better Stack (read-only query, Doppler prd_terraform), record `host_name` (`soleur-web-platform` / `soleur-web-2`), the discriminating journald field, and whether it lists auto-approve names; none found = post-deploy check recorded as unobservable up front

## Phase 1: Gate lifecycle (commit 1)

- [x] 1.1 RED: `test/permission-callback-platform-gate-expiry.test.ts` (timeout, abort with controller aborted [both reasons], per-call abort, approve, reject, status-write failure hold/restore, concurrent gates, gate + Bash stacking, `agentID`, Bash regression, in-window status observation)
- [x] 1.2 GREEN: `holdForUser` options object + `gateClass`; gated branch via `holdForUser`; skip `active` write when `ctx.controllerSignal.aborted` (platform only); static deny texts; ops `platform-gate-status-hold|restore` with own static messages
- [x] 1.3 Commit `fix(security): gated platform-tool gate fails closed on expiry and restores status (#11303)`

## Phase 2: The filter (commit 2)

- [x] 2.1 RED: `test/build-allowed-tools-census.test.ts` (unit census with derived floors, in-suite mutation battery, registered-name explicit-entry check incl. Plausible-registered vacuity guard, `buildAgentQueryOptions` assertion cases incl. bare server name, wildcards, rule-content/case/whitespace variants, empty result equivalence, non-mutation, real `CC_PATH_ALLOWED_TOOLS` plus an injected unclassified name, call-site-by-equality assertion, frontmatter and `annotations` sentinels, distinct status-op messages, card-text hardening tests, offline-message content-free test)
- [x] 2.2 RED: flip `agent-runner-tools`, `agent-runner-kb-share-tools`, `email-triage-tools` presence assertions; switch `kb_share_create` verbatim sites (`agent-runner-query-options.test.ts` 221/498, `agent-runner-helpers.test.ts` 422) to `kb_share_list`; add `startAgentSession` wiring test
- [x] 2.3 GREEN: `buildAllowedTools` (plugin names validated `^[a-z0-9-]+$`) + `conversations_lookup` auto + explicit gated entries (`plausible_*`, `account_*`) + six `buildGateMessage` cases + card-field helper (bounded, neutralised, email truncation marker) + content-free `buildOfflineGateMessage` for every gated tool in `tool-tiers.ts`
- [x] 2.3a Cite the approved-body binding at `server/email-triage/outbound.ts` for the PR body (stop and escalate if the body is not bound)
- [x] 2.4 GREEN: `agent-runner.ts` call site; `agent-runner-query-options.ts` allowlist-form assertion (exact auto FQN or validated plugin wildcard; rejects `bypassPermissions`); comment refresh
- [x] 2.5 Run production-code mutation rows (Guard 1 rows 1, 4, 5, 6) via edit + `git checkout -- <file>`; record RED evidence
- [x] 2.6 Commit `fix(security): stop pre-approving gated platform tools via allowedTools (#11303)`

## Phase 3: Real-SDK probe (commit 3)

- [x] 3.1 Keep only `apps/web-platform/scripts/dev-probe-approval-gate.ts`; drop `phase-0-measurements.md`
- [x] 3.2 Add `pyramid-justified` marker to the probe header; exit 4 never green. Switch to `buildAllowedTools`, full derived legacy name set, production string prompt, drop `:no-allowed`, add `email_send:raw` canary and `email_send:prod-stream`, builder-import failure = CANT-RUN, update header and floor
- [x] 3.3 Run against Doppler `ci`: expect `RESULT: PASS`; paste PROVENANCE/REGISTRATION/PROBE lines for the PR body
- [x] 3.4 Fix stale comment in `dev-probe-destroy-ask.ts` only if Phase 0.4 contradicts it
- [x] 3.5 Commit `test(approval): real-SDK probe builds allowedTools via buildAllowedTools; prod rows now invoke canUseTool (#11303)`

## Phase 4: ADR (commit 4)

- [x] 4.1 `soleur:architecture create` ADR (ordinal re-verified vs origin/main); run `plugins/soleur/test/c4-count-parity.test.sh`
- [x] 4.2 Confirm no legal text / compliance-posture / flag file changed
- [x] 4.3 Commit `docs(adr): gated-tier platform tools never enter SDK allowedTools`

## Phase 5: Verify and ship

- [x] 5.1 `tsc --noEmit`, vitest (touched + new), eslint, markdown lint, `lint-guard-contract.py`
- [ ] 5.2 PR body: first line behaviour-change answer + changelog line; CLO ruling; plugin-wildcard residual risk; #11289 conflict note; `Closes #11303`; probe lines; RED evidence
- [ ] 5.3 One comment on PR #11289 about the probe add/add conflict (no new issue)
- [ ] 5.4 Post-merge: `soleur:postmerge` deploy verification; absence check on `soleur-web-platform` (web-1) and `soleur-web-2` with generated gated-name list; record verdicts on PR and #11303 (exit 2 = unobserved, not clean)

## Phase 6: Review fixes (12-seat panel + CTO ruling, 2026-10-27)

- [x] 6.1 A1 late-click wording (`ERR_REVIEW_GATE_NOT_FOUND` text), platform deny texts tell the agent to tell the user
- [x] 6.2 A2 email cards: full parsed recipient, reply-to, subject, entire body (cap 4000), hidden characters made visible, static fail-closed denies (`buildGateCard`), zod `.max`, `+N more`, pre-capped scalars, new strip set; hash comments corrected; other gated cards name inputs they do not print
- [x] 6.3 A3 deterministic abort/restore rule (CAS restore, abort-skip; the abort finalize stays active-only, #3463) with ordering tests
- [x] 6.4 A4 explicit `nonInteractive` flag from the auto-sync seam; immediate static deny
- [x] 6.5 A5 pending-card cap (5), `permissionMode` allowlist, Bash-family rejection in `allowedTools`
- [x] 6.6 B1 expiry/abort log rows (`delivered`, `conversationId`, `reason`, distinct `platform-gate-aborted`), B2 gate registered before the status write, B3 shared keep-rule exports
- [x] 6.7 B4 full hand-written tier table, signal-delivery and real-gate fake-timer tests, assertion anchors, shared `registeredPlatformTools`; B5 comment truth; B6 system-prompt line; B7 plan/ADR corrections
- [x] 6.8 Mutation-verify every new guard in an allocated sandbox (round-1 and round-2 results recorded in the plan, section Mutation Evidence)
- [x] 6.10 Fix-round 2 (CTO round-2 rulings): abort finalize reverted to active-only; Approve after abort denied; ASCII/trim recipient fidelity, one hidden-character class, exact quoting, shared caps in zod; wrapping approval card with a short aria-label; test-design rows; ADR and plan corrections
- [ ] 6.9 FOLLOW-UP (not here; also under ADR-305 "Scoped out"): replay unresolved `review_gate` frames on resume; email_reply sender/subject lookup for the card; per-session toolUseID-keyed body hash map; full non-MCP `allowedTools` allowlist; `nonInteractive` for Bash gates in headless sync; serialise hold/restore writes per session; per-Query closed flag instead of the sticky controller skip (cc path); `failed` finalizers with active-only guards leaving a parked row, and the AskUserQuestion / destroy-gate status writers bypassing `pendingGates` / CAS (pre-existing); one shared tool-tiers `vi.mock` factory across eight test files; consent fatigue; other-field cards print "not shown" notes

