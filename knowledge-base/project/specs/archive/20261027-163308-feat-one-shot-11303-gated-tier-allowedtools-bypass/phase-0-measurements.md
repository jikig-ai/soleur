# Phase 0 and probe measurements: gated-tier allowedTools bypass (#11303)

Measured 2026-10-27 on SDK 0.3.284 / CLI 2.1.284, Doppler config `ci` (never `prd`), `NODE_ENV=test`, node v26.3.0, bun 1.4.4.

## 0.4 String-prompt reachability (before building anything)

Question: with the production prompt shape (a plain string, as `startAgentSession` passes), is `canUseTool` invoked for a gated tool whose name is NOT in `allowedTools`?

Method: the sibling-branch probe (`0acc541b6f`) with the prompt switched to a plain string, one paid call: `PROBE_ONLY=email_send:no-allowed`.

```
PROBE email_send:no-allowed invoked=yes verdict=ok allowedToolsListsIt=false attempted=true tier=gated decisions=[deny] gateCalls=1 stubRan=false denyHonoured=true sdk=0.3.284 cli=2.1.284
RESULT: DIAGNOSTIC (sdk=0.3.284 cli=2.1.284, cases-run=1)
```

Result: `invoked=yes`. A string prompt reaches `canUseTool`; the header claim in the `dev-probe-*` family ("only a streaming-input prompt wires the callback") is wrong and was corrected (`dev-probe-approval-gate.ts` header, comment in `dev-probe-destroy-ask.ts`). Removing gated names from `allowedTools` therefore gates them rather than hard-denying them. Proceed.

The SDK warning printed for the other seven names, verbatim format: `canUseTool will not be invoked for: <comma-separated FQNs>. Bare allowedTools entries auto-approve the whole tool before the callback is consulted. ...` (code `CLAUDE_SDK_CAN_USE_TOOL_SHADOWED`). It lists every bare entry, so after the fix a legacy session still lists the auto-approve names it pre-approves.

## 0.5 Late click and the old deny text

- `review_gate_response` for an unknown or expired gate: `resolveReviewGate` throws `ERR_REVIEW_GATE_NOT_FOUND` ("Review gate not found or already resolved"); ws-handler sends `{ type: "error", gateId }` with the sanitised text **"This review prompt has already been answered."** (`error-sanitizer.ts`). It is an error frame, never an allow. Finding: for an EXPIRED card that wording does not say the action was not performed. `error-sanitizer.ts` is outside this PR's file list, so it is not changed here; recorded as a follow-up for the #11289 approval-queue design (expired-card UX).
- `rg "User rejected the action"` across `apps/web-platform` before this change: only `server/permission-callback.ts`; no test pinned the old string.

## 0.6 Post-deploy channel proof (Better Stack, read-only, Doppler `prd_terraform`)

`scripts/betterstack-query.sh --since 30d --grep "canUseTool will not be invoked"`: 58 real SDK warning rows, earliest 2026-09-30, latest 2026-10-27.

- Host: all 58 on `host_name=soleur-web-platform` (web-1). Zero on `soleur-web-2` in 30 days.
- Discriminating fields for a real SDK row (versus a webhook payload that merely quotes the text): `source_kind=app_container`, `_SYSTEMD_UNIT=docker.service`, `_COMM=dockerd`, `SYSLOG_IDENTIFIER=<container id, varies>`, `shipper=vector`. Webhook-payload rows (which quote these names) arrive on `host_name=soleur-inngest-prd`, `source_kind=journald`, `_SYSTEMD_UNIT=inngest-server.service`.
- Content: 56 rows list `Read, Glob, Grep, LS, NotebookRead, TodoWrite, ExitPlanMode, mcp__soleur_platform__narrate, mcp__soleur_platform__summarize` and 2 add `WebFetch`: all are the cc path (`CC_PATH_ALLOWED_TOOLS`). No row lists any other `mcp__soleur_platform__` name, so there is no legacy session with platform tools in 30 days (consistent with the issue's evidence limits).
- Consequence for the post-merge check: the channel is proven (real rows reach Better Stack with a stable field shape) but the plan's positive control `mcp__soleur_platform__kb_share_list` cannot be satisfied unless a legacy session runs in the window; expect exit 2 (`unshipping`) recorded as **unobserved, not clean**. A control on `mcp__soleur_platform__narrate` proves the channel only (cc path), not that a legacy session ran. The field to add as `--control-require-field` / `--absence-require` is `source_kind=app_container` (or `_SYSTEMD_UNIT=docker.service`).

## Final probe (commit 3), Guard 3

Command: `NODE_ENV=test doppler run -p soleur -c ci -- bun run apps/web-platform/scripts/dev-probe-approval-gate.ts` exit 0.

```
PROVENANCE sdk=0.3.284 cli=2.1.284 node=v26.3.0 bun=1.4.4 doppler-config=ci
REGISTRATION summary legacyTools=46 ccTools=10
COMPOSITION prod=23 entries (auto-approve platform tools + plugin wildcards) raw=47 entries (unfiltered)
PROBE email_send:prod invoked=yes verdict=ok allowedToolsListsIt=false prompt=string attempted=true tier=gated decisions=[deny] gateCalls=1 stubRan=false denyHonoured=true
PROBE email_reply:prod invoked=yes verdict=ok ... tier=gated decisions=[deny] gateCalls=1 stubRan=false denyHonoured=true
PROBE email_suppress:prod invoked=yes verdict=ok ... tier=gated decisions=[deny] gateCalls=1 stubRan=false denyHonoured=true
PROBE github_push_branch:prod invoked=yes verdict=ok ... tier=gated decisions=[deny] gateCalls=1 stubRan=false denyHonoured=true
PROBE create_pull_request:prod invoked=yes verdict=ok ... tier=gated decisions=[deny] gateCalls=1 stubRan=false denyHonoured=true
PROBE github_trigger_workflow:prod invoked=yes verdict=ok ... tier=gated decisions=[deny] gateCalls=1 stubRan=false denyHonoured=true
PROBE kb_share_create:prod invoked=yes verdict=ok ... tier=gated decisions=[deny] gateCalls=1 stubRan=false denyHonoured=true
PROBE workspace_set_autonomous:prod invoked=yes verdict=ok ... tier=gated decisions=[deny] gateCalls=1 stubRan=false denyHonoured=true
PROBE email_send:raw invoked=no verdict=CANARY-OK allowedToolsListsIt=true prompt=string attempted=true tier=n/a decisions=[] gateCalls=0 stubRan=true denyHonoured=false
PROBE email_send:prod-stream invoked=yes verdict=ok allowedToolsListsIt=false prompt=stream attempted=true tier=gated decisions=[deny] gateCalls=1 stubRan=false denyHonoured=true
RESULT: PASS (sdk=0.3.284 cli=2.1.284, cases-run=10)
```

The derived legacy set is 46 names (the plan's plan-time census), of which 22 are auto-approve; with one plugin wildcard server the production composition is 23 entries. A green run is evidence about the sampled model behaviour only.

### Probe mutation rows (edit-and-run on a scratch copy of the probe, deleted afterwards; each mutation asserted to land exactly once)

| Row | Mutation | Result |
|---|---|---|
| 1a | `:prod` list = the unfiltered list (builder bypassed) | pre-spend guard: `PROBE prod-composition leaked-gated-tools=<all eight>`, `RESULT: FAIL ... cases-run=0`, exit 1, no spend |
| 1b | `:prod` row gets the unfiltered list assigned after the builder (`PROBE_ONLY=email_send:prod`) | `invoked=no verdict=BYPASS stubRan=true`, `RESULT: FAIL`, exit 1 |
| 3 | `:raw` canary given the FILTERED list (`PROBE_ONLY=email_send:raw`) | `invoked=yes verdict=CANARY-NOT-BYPASSING`, `RESULT: FAIL`, exit 1 |
| 4 | the `plausible-tools` import path broken | `legacyFailures=plausible-tools-import-failed`, `RESULT: CANT-RUN:registration-import-failed`, exit 3, no spend |
| 2 | model never attempts the tool | by reading the verdict function: `!r.attempted` gives `MODEL-DID-NOT-TRY`, which sets `cantRun` and exits 3, never PASS |

Paid calls: 1 (Phase 0.4) + 10 (final probe) + 2 (rows 1b and 3) = 13.
