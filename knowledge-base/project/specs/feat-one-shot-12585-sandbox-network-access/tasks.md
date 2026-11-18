# Tasks: explicit SandboxNetworkAccess arm (#12585)

Plan: `knowledge-base/project/plans/2026-11-18-fix-sandbox-network-access-canusetool-arm-plan.md`
Rulings: `knowledge-base/project/specs/feat-one-shot-12585-sandbox-network-access/decision-challenges.md`

## Phase 1: Setup and measurement (go/no-go gate)

- 1.1 Write `apps/web-platform/test/helpers/netns-egress-harness.mts`. It is a child harness run under `unshare -rnm` that hosts `query()`, the tap, the Anthropic stub, the production forwarder (via `spawnEgressForwarder`), the recording gateway and the decoys. It reports one JSON record per arm back to vitest (CTO T7).
- 1.2 Step 0, required: inside the namespace, bring up `lo`, add the `10.0.0.1/32` and `10.0.0.2/32` aliases, and run the nested bwrap/apply-seccomp probe.
  - 1.2.1 Run the child with `node_modules/.bin/tsx`. Assert that it imports `permission-callback.ts` and `egress-forwarder.ts` (CTO D6). Include `--proc /proc` in the bwrap probe.
  - 1.2.2 If step 0 fails under `C4_BWRAP_REQUIRED=1`, throw so the lane goes red. Use `UNVERIFIED:nested-userns` only for local runs without the flag. Never run arm B outside the namespace (CTO D4).
- 1.3 Phase 1a: create `apps/web-platform/test/sandbox-network-access-runtime.test.ts` with a test-local allow-all tap. Write no Phase 2-5 code before this passes.
  - 1.3.1 Permanent control arm: allow-all with no egress env must hit the `10.0.0.1:443` decoy (CTO T9/T16).
  - 1.3.2 Arm B: entitled open-web shapes arrive at the recording gateway with the session `Proxy-Authorization`. Any decoy hit fails the suite.
  - 1.3.3 Arm D: bind-mount a hosts file that maps `api.anthropic.com` to the stub on `10.0.0.2`. That traffic must never appear at the gateway (CTO T8).
  - 1.3.4 Arm E: dead forwarder. Await the `exit` event and assert `isEgressForwarderLive` is false. Send a second request to the same host after the 403.
  - 1.3.5 Arm F: request, teardown while the command sleeps, re-request, all in one compound command. Add the second-request-after-403 case.
  - 1.3.6 Assert `MEASURED_ON_SDK = "0.3.321"` against the installed SDK. On failure, print the recorded tool names.
  - 1.3.7 Floor test: every arm ran to its last assertion. Record the measured wallclock and set per-arm timeouts from it.
- 1.3.8 Extend `test/helpers/anthropic-stub.ts` with a `host` parameter and a scripted tool sequence, for arms D and G.
- 1.3.9 Arm E targets `10.0.0.1`. Arm F syncs on a barrier file, not a sleep.
- 1.3.10 Arm B adds `169.254.169.254`, plus a hosts-file name that resolves to it. The gateway must refuse both.
- 1.3.11 Each arm asserts at least one `SandboxNetworkAccess` call was recorded.
- 1.3.12 Poll gateway and forwarder readiness with a 30 s deadline.
- 1.3.13 Set an explicit per-arm timeout.
- 1.3.14 Record the raw input key set and host format the SDK sends (CTO D7).
- 1.4 Go/no-go: if B, E or F fails, switch to the fail-closed design (row 6', `gateway-unverified`), file the follow-up issue and trigger the CLO DPIA t4 re-screen (CTO T12, AC22).

## Phase 2: Core implementation

- 2.1 Create `apps/web-platform/server/sandbox-network-access.ts`, importing only `node:net`.
  - 2.1.1 Exports: `SANDBOX_NETWORK_ACCESS_TOOL`, `WEB_EGRESS_NO_PROXY` (byte-identical literal), `normalizeHost`, `noProxyMatches`, and `decideSandboxNetworkAccess(input, egress: { live } | undefined, noProxy = WEB_EGRESS_NO_PROXY)` with the full reason order (CTO T2).
  - 2.1.2 Deny `malformed-host` on any input key set other than `{ host }`, and on a non-primitive `host`.
  - 2.1.3 Normalize in this order: an ASCII check on the raw value, then strip one trailing dot, then canonicalize IPv6 via `URL`, then lowercase.
  - 2.1.4 Deny a `%` zone ID and a hex or octal last label.
  - 2.1.5 Deny any `:` outside a valid IPv6 literal, and any `@`, `/` or whitespace (CTO D7).
  - 2.1.6 Drive bypass shapes through `createCanUseTool` with the raw `toolInput`.
- 2.2 Write unit tests in `apps/web-platform/test/sandbox-network-access.test.ts`:
  - the property sweep;
  - the import-set test (CTO T17);
  - the no-GitHub-token case, where `github.com` gets `no-proxy-match` (CTO T19).
- 2.3 Add the arm in `server/permission-callback.ts`.
  - 2.3.1 Add `sandboxNetworkEgress?: { isLive }` and `webEgressGranted?: boolean` to `CanUseToolContext`.
  - 2.3.2 Place the branch first, after `const subagentCtx = ...`, matching the exact tool name and never falling through.
  - 2.3.3 Wrap `isLive()` in try/catch, so a throw counts as not-live (CTO T4). Return one shared host-deny message.
- 2.4 Add `"canUseTool-sandbox-network"` to `PermissionLayer` in `server/permission-log.ts`.
- 2.5a Log one pino `logger.warn` per deny occurrence, outside the dedup. Deduplicate only the Sentry mirror (CTO D3). Put `granted` in `extra` too. Key the model message on `(reason, granted)`; the CPO writes the granted-but-degraded wording (CTO D2b).
- 2.5b Add a Better Stack alert on granted-but-degraded denies in `infra/betterstack-logs-alerts.tf`, following its seven-step recipe:
  - the `-target=` lines;
  - the drift guard and its `infra-validation.yml` step;
  - the exploration-count bump;
  - the runbook row.
  Merging creates these two resources (CTO D2a).
- 2.5c Toggle-off: add `teardownEgressForwardersForWorkspace` and call it from `app/api/workspace/web-egress/route.ts` after `setWebEgress(false)`. Add a route test (CTO D1).
- 2.5 Add the Sentry reporter: per-`createCanUseTool`-instance dedup on `(reason, matchedEntry)`, tags `reason` and `granted`, and the explicit message `"sandboxed network request denied"`. No host is passed in any field.
- 2.6 Wire it up.
  - 2.6.1 Export `isEgressForwarderLive(conversationId, token)` from `server/egress-forwarder.ts`.
  - 2.6.2 Make `server/agent-env.ts` import `WEB_EGRESS_NO_PROXY`, and correct the measurement-4 comment.
  - 2.6.3 Make `server/cc-dispatcher.ts` pass `sandboxNetworkEgress` from a `const` capture of `webEgress`, plus `webEgressGranted`.
- 2.7 Update the spike driver (`sdk-egress-driver.mts`) to use `decideSandboxNetworkAccess` with `live: true`. Record the raw host plus the normalized host and `reason`.
  - 2.7.1 Update the `lib/arms.sh` criterion to accept `loopback-literal` (CTO T15).
  - 2.7.2 Add the module to the `.github/workflows/egress-injector-spike.yml` `pull_request.paths`.

## Phase 3: Testing

- 3.1 Write `apps/web-platform/test/permission-callback-sandbox-network.test.ts`:
  - AC1 layer assertions on the allow path, the deny path, the support persona and a subagent;
  - AC2 and AC3;
  - AC7 revocation and re-spawn;
  - AC11 dedup;
  - AC12 canary across every sink: warnSilentFallback, logPermissionDecision with the debug flag on, the scrubbed event, and the deny message;
  - AC20 per-Query dedup.
- 3.2 Add a NO_PROXY pin test: `buildAgentEnv(...).NO_PROXY` equals the literal written out in the test (CTO T1).
- 3.3 Add the cc-dispatcher real-factory wiring test (CTO T10, AC17) and the toggle-off re-resolve test (CTO T18, AC18).
- 3.4 Add a census test over `createCanUseTool(` call sites: only `cc-dispatcher.ts` passes the field.
- 3.5 Phase 1b: swap the tap for the production `createCanUseTool`.
  - 3.5.1 Add arm A: unentitled targets including `10.0.0.1:443`.
  - 3.5.2 Add arm C: bypass shapes, plus in-sandbox `localhost` (or record `UNVERIFIED:in-sandbox-loopback`).
  - 3.5.3 Add arm G: a scripted `Task` subagent (CTO T11).
- 3.6 Run the full verification set: webplat vitest, the C4 tests, and `cd apps/web-platform && ./node_modules/.bin/tsc --noEmit`.

## Phase 4: Records

- 4.1 Add dated addenda to ADR-051 and ADR-272 correcting the `allowedDomains: []` claim.
- 4.2 Add an ADR-278 addendum covering:
  - the arm as boundary mechanics;
  - the 0.3.321 measurements, with the spike run URL;
  - the within-turn revocation window;
  - the GitHub-host residual;
  - a note that it replaces the "#11637 owns" assignment.
- 4.3 Add a dated ADR-325 note (CTO T14). In the ADR-278 addendum, name the gateway public-IP residual (#12904) and the cross-host revocation window (#12903).
- 4.4 Fix the `agent-runner-sandbox-config.ts` docstring and the `model.c4` edge prose. Add one correction line to the 2026-06-10 learning.

## Phase 5: Merge preconditions and post-merge

- 5.1 The egress-injector spike must be green on the PR head SHA, and its URL must be cited in ADR-278 (AC14).
- 5.2 Post-merge: pull from Sentry (`op:sandbox-network-denied`) and Better Stack yourself. Run the no-host check only on a fetched event JSON. If no event exists, record `UNVERIFIED:prod-deny-event-shape` and file an issue.
- 5.3 The hosted entitled-session check is a production write. Name it as one plain ACTION for the operator's go-ahead. Without that go-ahead, record `UNVERIFIED:hosted-entitled-sandboxed-egress` and file an issue.
- 5.4 The PR body must contain `Closes #12585`.

## Work status (2026-11-18)

- Phase 1a ran: NO-GO on per-host caching (arms F, F2), so row 6' (deny-all `gateway-unverified`) shipped and AC2 is replaced by AC22. Follow-up allow arm: #12906. Hosted check: #12907 (`UNVERIFIED:hosted-entitled-sandboxed-egress`).
- Deviation: the open-web decoy is `198.51.100.1` (TEST-NET-2), not `10.0.0.1`: the SDK sets the sandboxed command's `NO_PROXY` to loopback plus every RFC 1918 and link-local range, so a `10.0.0.1` target would bypass the proxy by the SDK's own rule and measure nothing about routing.
- Deviation: arm F2 added (the cache spans commands). Arm E's sub-case is the allow-all MEASUREMENT run; the production run shows the arm's `egress-not-running`.
- Deviation: the warm re-resolve was extracted unchanged into `reResolveWarmWebEgress` so AC18 can await it.
- Finding fixed: the forwarder registry moved to `globalThis` (the Next route bundle and the custom server load separate module copies; the toggle-off teardown would otherwise see an empty registry).
- Spike driver: calls the production decision and allows exactly the `gateway-unverified` hosts (it measures the route an allow would get).
