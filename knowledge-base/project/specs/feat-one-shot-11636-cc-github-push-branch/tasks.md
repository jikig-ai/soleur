# Tasks: register github_push_branch in the cc platform server (Ref #11636, Ref #11635)

Plan: `knowledge-base/project/plans/2026-11-05-fix-register-github-push-branch-in-cc-platform-server-plan.md`
Branch: feat-one-shot-11636-cc-github-push-branch. One PR, `fix(approval):` prefix, `Ref` only (no closing keyword).

## Phase 0 - Baseline (census tests first)

- 0.1 Confirm deps: `cd apps/web-platform && ls node_modules >/dev/null 2>&1 || npm ci`
- 0.2 Run and record the green baseline: tools-census, runner-census, builder-grants-required, cc-approval-fail-closed, permission-callback-gated-branch, cc-mcp-tier-allowlist, build-allowed-tools-census, crm-lead-dispatch, cc-dispatcher-real-factory, github-tools-push-grant; derive the full consumer list with `git grep -l` and add any file not named
- 0.3 `bash apps/web-platform/test/approval-guard1-mutation.test.sh --check-anchors` (baseline)

## Phase 1 - RED tests

- Order: write 1.7 first (the second builder forces the pairing change), then 1.2, 1.1, 1.3-1.6, 1.8
- 1.1 `test/cc-github-push.test.ts`: registrar matrix (flag off / throws / timeout / undefined, not entitled, entitled with no forwarder, support persona, no repo, no installation, lookup throws / times out / unsafe name, lookup not called on the dark path, same flag identity as the gate, toolNames exactly the push FQN)
- 1.2 `test/github-tools-push-grant.test.ts`: `buildGithubPushBranchTool` strict cases (requireGrant with enforcing false refuses and reports; granted pushes exactly the approved commit with closed-over values; headSha absent; commit unavailable; model-supplied owner/repo stripped) plus legacy parity
- 1.3 `test/approval/cc-push-gate-flow.test.ts`: real `createCanUseTool` in the cc shape: approved / rejected / pending / flag off / expired / consume rejected / aborted texts, no tool input in messages, durable surfaces exercised, HEAD-moved case, shared live row
- 1.4 `test/approval/cc-allow-source-pin.test.ts`: minimal text scan of the plugin tree with canary, must-pass fixture and a per-directory floor (SKILL.md >= 100)
- 1.5 `test/approval/tools-census.test.ts`: allowed-set sweep, allowlist throw matrix (mixed lists both orders, denylist), non-vacuity
- 1.6 `test/approval/runner-census.test.ts`: one `new ExecutionGrants()`, same identifier to gate and registrar, builders census, `activeWorkspaceId` never reassigned
- 1.7 `test/approval/builder-grants-required.test.ts`: per-builder interface pairing and inverse check (failure strings unchanged)
- 1.8 `test/cc-dispatcher-real-factory.test.ts`: byte-identical dark path; registered path; grants identity; workspace-capture equality plus mid-Query switch; support persona; entitled with no forwarder; factory-throw drains the Map
- 1.9 `test/build-allowed-tools-census.test.ts` (push FQN joins the cc names) and one assertion line in `test/cc-mcp-tier-allowlist.test.ts`
- 1.10 `test/approval/cc-push-boundaries.test.ts`: push FQN does not match the sandbox hook matcher (both directions), two factories never share grants, conversation B cannot consume A's row, flag off later => next call refused

## Phase 2 - Implementation

- 2.1 `server/github-tools.ts`: extract `buildGithubPushBranchTool` (required `requireGrant`, `readonly grants`), `buildGithubTools` reuses it with `requireGrant: false`, export the FQN
- 2.2 `server/cc-github-push.ts`: grant-wired constant, registrar (cheapest-first checks, bounded flag read last, fail-closed default-branch lookup, lazy `github-tools` import, a Sentry outcome event `cc-push-registration`, distinct reasons and ops `cc-push-flag-resolve` / `cc-push-default-branch-resolve`), prompt addendum
- 2.3 `server/cc-dispatcher.ts`: hoist grants and repo slug, registrar call, `approvalTools` parameter, `platformToolNames`, addendum, per-conversation Map (publish after build, drain at all sites, consult in `onToolUse`), `readCcMcpAllowlist` relaxation
- 2.4 `approval-guard1-mutation.test.sh`: `--check-anchors` after the 2.1 rewrite (strict branch is a separate statement so the X7 anchor stays), three new mutant rows run with `--only`

## Phase 3 - Docs

- 3.1 ADR-309 dated addendum (workspace capture verified with evidence, allow-source treatment, durable surface, default-branch rule, registration-policy statement, flip preconditions as checklist items 8 and 9 incl. archived handover mirror, negative-claim sweep, probe result, #11534 triggers)
- 3.2 C4: extend the `engine -> approvalStore` edge description; run the C4 syntax, render and count-parity checks
- 3.3 `bash scripts/markdown-lint.sh --repo-sweep` before committing markdown

## Phase 4 - Verify

- 4.1 All Phase 0/1 files green; typecheck and lint scripts CI runs for `apps/web-platform`
- 4.2 Real-SDK approval-gate probe via the ci Doppler config; record the `RESULT:` line (CANT-RUN stays CANT-RUN)
- 4.3 Check whether any `real-sdk-ask-probe` push-path file changed; add the Guard 1 table row and run the suite with `timeout 580` only if so
- 4.4 Pre-push token grep must print nothing; commit trailer `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`
- 4.5 PR body per the plan's Ship Notes (no flag, environment, migration, toggle or legal change; `closingIssuesReferences = []`)
