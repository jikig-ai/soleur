# Phase 0.1 measurements: real-SDK probe of the gated-tool permission chain

Ref #4672. Plan: `knowledge-base/project/plans/2026-10-27-feat-durable-action-bound-approval-requests-plan.md` (Phase 0.1, AC10, Guard 1).
Probe: `apps/web-platform/scripts/dev-probe-approval-gate.ts` (modelled on `dev-probe-destroy-ask.ts`).
Run date: 2026-10-27. Doppler config `ci` (never `prd`). This is the PRE-BUILD run; AC10 also needs a re-run on the finished branch (Phase 5.4).

## Verdict

**Stop point reached.** Under the legacy runner's real option composition, `canUseTool` is NOT invoked for any of the eight slice-1 tools, because
`allowedTools` lists them and short-circuits the callback. The stub handler ran in all eight cases, i.e. the call executed with no gate and no
review card. With the tool's name removed from `allowedTools`, `canUseTool` IS invoked for all eight, sees tier `gated`, and the deny is honoured
(the handler does not run). Plan 0.1 clause (b) applies: the `buildAllowedTools` fix is REQUIRED, and plan stop-point (a) fails for the legacy
runner as composed today, so re-plan/fix this before building the rest (the fix is small and already specified in the plan).

This is also a live defect independent of the feature: in the legacy runner the existing in-memory `gated` tier for these eight tools (the
`review_gate` card, Approve/Reject) is currently unreachable. SDK 0.3.284 / CLI 2.1.284 itself prints
`[CLAUDE_SDK_CAN_USE_TOOL_SHADOWED] Warning: canUseTool will not be invoked for: mcp__soleur_platform__email_send, ... Bare allowedTools entries
auto-approve the whole tool before the callback is consulted. To gate every tool call, use a PreToolUse hook; or remove the bare names from
allowedTools so they fall through to canUseTool.` (16 occurrences in the run, one per case, listing the names still in `allowedTools`).

## Result lines (AC10: one per slice-1 tool name)

`prod` = `allowedTools` as the legacy runner composes it (all eight FQNs). `no-allowed` = same list with that tool's FQN removed (other seven stay).
`invoked` = production `createCanUseTool` was called with the FQN. `stubRan` = the inert handler body executed (the call was NOT stopped).

| Tool | prod: invoked | prod: stubRan | no-allowed: invoked | no-allowed: tier seen | no-allowed: decision | no-allowed: stubRan (deny honoured) |
|---|---|---|---|---|---|---|
| email_send | no | yes | yes | gated | deny | no (honoured) |
| email_reply | no | yes | yes | gated | deny | no (honoured) |
| email_suppress | no | yes | yes | gated | deny | no (honoured) |
| github_push_branch | no | yes | yes | gated | deny | no (honoured) |
| create_pull_request | no | yes | yes | gated | deny | no (honoured) |
| github_trigger_workflow | no | yes | yes | gated | deny | no (honoured) |
| kb_share_create | no | yes | yes | gated | deny | no (honoured) |
| workspace_set_autonomous | no | yes | yes | gated | deny | no (honoured) |

Raw probe lines (verbatim, `sdk=0.3.284 cli=2.1.284` suffix trimmed):

```
PROBE email_send:prod invoked=no verdict=BYPASS allowedToolsListsIt=true attempted=true tier=n/a decisions=[] gateCalls=0 stubRan=true denyHonoured=false
PROBE email_send:no-allowed invoked=yes verdict=ok allowedToolsListsIt=false attempted=true tier=gated decisions=[deny] gateCalls=1 stubRan=false denyHonoured=true
PROBE email_reply:prod invoked=no verdict=BYPASS allowedToolsListsIt=true attempted=true tier=n/a decisions=[] gateCalls=0 stubRan=true denyHonoured=false
PROBE email_reply:no-allowed invoked=yes verdict=ok allowedToolsListsIt=false attempted=true tier=gated decisions=[deny] gateCalls=1 stubRan=false denyHonoured=true
PROBE email_suppress:prod invoked=no verdict=BYPASS allowedToolsListsIt=true attempted=true tier=n/a decisions=[] gateCalls=0 stubRan=true denyHonoured=false
PROBE email_suppress:no-allowed invoked=yes verdict=ok allowedToolsListsIt=false attempted=true tier=gated decisions=[deny] gateCalls=1 stubRan=false denyHonoured=true
PROBE github_push_branch:prod invoked=no verdict=BYPASS allowedToolsListsIt=true attempted=true tier=n/a decisions=[] gateCalls=0 stubRan=true denyHonoured=false
PROBE github_push_branch:no-allowed invoked=yes verdict=ok allowedToolsListsIt=false attempted=true tier=gated decisions=[deny] gateCalls=1 stubRan=false denyHonoured=true
PROBE create_pull_request:prod invoked=no verdict=BYPASS allowedToolsListsIt=true attempted=true tier=n/a decisions=[] gateCalls=0 stubRan=true denyHonoured=false
PROBE create_pull_request:no-allowed invoked=yes verdict=ok allowedToolsListsIt=false attempted=true tier=gated decisions=[deny] gateCalls=1 stubRan=false denyHonoured=true
PROBE github_trigger_workflow:prod invoked=no verdict=BYPASS allowedToolsListsIt=true attempted=true tier=n/a decisions=[] gateCalls=0 stubRan=true denyHonoured=false
PROBE github_trigger_workflow:no-allowed invoked=yes verdict=ok allowedToolsListsIt=false attempted=true tier=gated decisions=[deny] gateCalls=1 stubRan=false denyHonoured=true
PROBE kb_share_create:prod invoked=no verdict=BYPASS allowedToolsListsIt=true attempted=true tier=n/a decisions=[] gateCalls=0 stubRan=true denyHonoured=false
PROBE kb_share_create:no-allowed invoked=yes verdict=ok allowedToolsListsIt=false attempted=true tier=gated decisions=[deny] gateCalls=1 stubRan=false denyHonoured=true
PROBE workspace_set_autonomous:prod invoked=no verdict=BYPASS allowedToolsListsIt=true attempted=true tier=n/a decisions=[] gateCalls=0 stubRan=true denyHonoured=false
PROBE workspace_set_autonomous:no-allowed invoked=yes verdict=ok allowedToolsListsIt=false attempted=true tier=gated decisions=[deny] gateCalls=1 stubRan=false denyHonoured=true
RESULT: FAIL (sdk=0.3.284 cli=2.1.284, cases-run=16)     (exit 1)
```

The FAIL is the expected measurement of the defect (the `prod` rows are BYPASS), not a probe malfunction: all 16 cases were attempted by the model
(no CANT-RUN), and the eight `no-allowed` controls show the probe can see an invocation and a honoured deny when `allowedTools` does not list the tool.

## `allowedTools` finding and the required fix (plan 0.1.1)

`allowedTools` short-circuits `canUseTool`: measured, not inferred, for all eight names, on SDK 0.3.284 / CLI 2.1.284. A tool listed in `allowedTools`
auto-approves before the callback; only removing the name makes the SDK call `canUseTool`.

Fix needed: a pure `buildAllowedTools(platformToolNames, pluginMcpServerNames, { approvalRequired })` used at `server/agent-runner.ts` (`allowedToolsList`),
which drops every `APPROVAL_REQUIRED_TOOLS` entry when the `approval-queue` flag is on, pinned by the Guard 1 census test. Note the measured defect is
broader than the feature flag: with the flag OFF the same eight tools (and, by the same mechanism, every other `gated` platform tool in
`platformToolNames`: `create_issue`, `kb_share_revoke`, `routine_run`, `account_delete_initiate`, the CRM writes, ...) also bypass the existing in-memory
gate in the legacy runner today. Whether to drop the gated entries from `allowedTools` unconditionally (restoring the existing review gate) or only
under the flag is a product/risk decision for the plan owner; the plan's flag-conditional wording leaves the flag-off bypass in place. The probe's
`no-allowed` rows show that dropping the name restores the gate, so either is mechanically sound. This probe did not test the other gated tools.

## Registration per runner

Derived at probe runtime from the real builders (`buildGithubTools`, `buildWorkspaceSettingsTools`, `buildKbShareTools`, `buildEmailTriageTools`,
`soleurPlatformToolsForTests`); no handler is called. `REGISTRATION` lines printed by the probe:

| Tool | Legacy runner (`agent-runner.ts`) | cc-dispatcher (`cc-soleur-go`) |
|---|---|---|
| email_send | yes (always; in `platformToolNames` and `allowedTools`) | no |
| email_reply | yes (always) | no |
| email_suppress | yes (always) | no |
| github_push_branch | yes, only when the workspace has a connected repo and a GitHub App installation | no |
| create_pull_request | yes, same condition | no |
| github_trigger_workflow | yes, same condition | no |
| kb_share_create | yes (always) | no |
| workspace_set_autonomous | yes (always; leader surface only) | no |

Legacy: one `soleur_platform` MCP server (21 tools in the probe's derived set), `allowedTools = [...platformToolNames, ...plugin MCP wildcards]`,
`canUseTool` has `platformToolNames` as its allowlist. cc-dispatcher: a `soleur_platform` server of narration (`narrate`, `summarize`), the flag-gated
`edit_c4_diagram`, and, only for crm-lead chats, the seven `crm_*` tools (10 tools in the derived set); `allowedTools = CC_PATH_ALLOWED_TOOLS` (+ `WebFetch`
when entitled), `platformToolNames` holds only `edit_c4_diagram` and the crm-lead names. None of the eight is registered in the cc runner, so
`createCanUseTool`'s platform branch is unreachable for them there; `shouldMirrorUnregisteredPlatformToolUse` documents that the SDK rejects an
unregistered `mcp__soleur_platform__*` call without invoking `canUseTool`. The census (Guard 1/2) should assert: each of the eight is registered in
the legacy runner or exempt with a reason, and absent from the cc runner by design (or, if cc later registers any, that it enters `APPROVAL_REQUIRED_TOOLS`
handling and is not in cc's `allowedTools`). The cc runner's approval-queue surface for slice 1 is therefore the legacy runner only.

## Commands run

```
cd apps/web-platform && ./node_modules/.bin/tsc --noEmit                      # clean (new file included by tsconfig "**/*.ts")
PROBE_ONLY=email_suppress:prod NODE_ENV=test doppler run -p soleur -c ci -- bun run apps/web-platform/scripts/dev-probe-approval-gate.ts   # smoke run, 1 case: BYPASS
NODE_ENV=test doppler run -p soleur -c ci -- bun run apps/web-platform/scripts/dev-probe-approval-gate.ts                                 # full run, 16 cases
```

Provenance line: `sdk=0.3.284 cli=2.1.284 node=v26.3.0 bun=1.4.4 doppler-config=ci`. Model: the production default in `buildAgentQueryOptions`
(`claude-sonnet-5-5`), the same as the destroy-ask probe; `maxTurns 4`, `maxBudgetUsd 0.5` per case. Paid calls: 17 (1 smoke + 16 matrix); cost not measured.
`cli=` is the SDK package's declared `claudeCodeVersion`.

## What the probe cannot show

- Handler behaviour: the eight handlers are inert stubs on a same-named `soleur_platform` server, so email body-hash checks, protected-branch checks,
  rate limiters and the real side effects are not exercised. (`stubRan=true` in a `prod` row means "the SDK let the call through", the real handler would have run.)
- `allowedTools` here lists only the eight FQNs. Production lists ~20 more platform tools plus plugin MCP wildcards; those cannot make the eight less shadowed,
  but the "other tools are also bypassing" statement above is inferred from the same mechanism and the SDK warning, not measured.
- Dev host only (host bwrap, NODE_ENV=test), not the hosted container; no real Supabase, GitHub, or Resend, and no approval code (this run is the pre-build baseline
  against the unchanged `createCanUseTool`). It does not measure the post-fix behaviour, the altered-input deny (Guard 1 anchor), the throwing-`canUseTool`
  behaviour (already read from `sdk.mjs`), reconnect replay, or the cc runner at all (no cc session was driven; cc registration is from the builders).
- The model attempted the tool in all 16 cases, but a different model or prompt could behave differently; one sample per case, no repeat-run variance measured.
- Allow rules from settings files can also shadow the callback; `settingSources: []` in the builder removes that source here, and the probe does not test it.
- Only the `canUseTool`-allow short-circuit is characterised; a PreToolUse hook `allow` (the #10054 class) was not a factor in these runs (the production hooks are
  in the composition and the `no-allowed` rows reached `canUseTool`).
