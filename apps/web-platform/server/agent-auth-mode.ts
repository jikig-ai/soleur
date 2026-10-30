// The authMode lookup for the agent auth-failure diagnostic (agent-auth-failure.ts). Injected at both call sites as a
// resolver so the matcher and the probe stay free of the Supabase graph, and so the lookup runs only on the failure path.
//
// REMOVAL CHECKLIST (the diagnostic is temporary; deleting it is one pass):
//   1. server/agent-auth-failure.ts and this file. KEEP server/engine-binding-auth-mode.ts (the runner and dispatcher
//      wire its lease resolver; DELETE its `readConversationBindingAuthMode` export and the matching cases of
//      test/engine-binding-auth-mode.test.ts, which only this file calls) and server/auth-mode-error.ts (the lease
//      reads it, #11591). KEEP server/agent-auth-match.ts (the pure matcher) and
//      server/agent-auth-user-message.ts: the friendly error (#11086) calls the matcher, so the matcher is product code now.
//      agent-auth-failure.ts only re-exports the matcher, and the only importer of that re-export is the matcher test
//      that step 6 splits, so no server import needs re-pointing;
//   2. in `claude-error-signatures.ts` delete only SDK_API_KEY_SOURCES. KEEP CLI_AUTH_FAILURE_REPLIES, SDK_AUTHENTICATION_FAILED,
//      the `CliAuthFailureKind` type and the "REPLY signatures" paragraph of the file header (the matcher reads them);
//   3. in agent-runner.ts and cc-dispatcher.ts: the import, `createAgentAuthFailureProbe` with its `let authProbe = NOOP_AGENT_AUTH_PROBE`
//      try/catch and the `warnAgentAuthProbeUnavailable()` call, the `authProbe.bindOptions(` wrapper (re-indent the closing
//      parens), the `observe` call, and `tapAgentAuthFailure(` around `sdkQuery(`;
//   4. in claude-code-message-translator.ts RETARGET (do not delete) the comment that names SDK_AUTHENTICATION_FAILED: the
//      constant stays, because the matcher reads it. Delete the "Wrapper note" comment in
//      test/agent-sandbox-seccomp-selector.test.ts;
//   5. the Sentry rule `agent_auth_failure`: ONE PR deletes the rule from issue-alerts.tf, its alert-reference.json entry and the
//      infra/sentry README counts, entry and decode table (the plan_pr gate requires the committed reference to equal the
//      plan's projection in the same PR), with `[ack-destroy]` alone on a line in a commit BODY (infra/sentry/README.md);
//   6. the tests: agent-auth-failure-{probe,tap,sentry-path}.test.ts, sentry-agent-auth-failure-alert-op-contract.test.ts
//      (SPLIT agent-auth-failure-matcher.test.ts: move its matcher describe blocks to a new test/agent-auth-match.test.ts
//      importing from ../server/agent-auth-match, and delete the blocks that test deriveAgentAuthContext,
//      buildAgentAuthPayload, the __reset* seam and the SDK_API_KEY_SOURCES parity: those import code step 1 deletes. The two
//      friendly-error wire tests, agent-auth-friendly-error-wire{,-legacy}.test.ts, import the diagnostic's probe, tap and
//      dedupe reset to prove the matcher saw the RAW message first: replace those imports with a test-local observer and
//      keep every frame-order, persistence and one-frame assertion; the legacy one also drops its agent-auth-mode mock),
//      the wiring cases (and their hoisted mocks and imports) in agent-runner-unix-deny-wire.test.ts and
//      cc-dispatcher-real-factory.test.ts, and the widened regex in test/server/cc-dispatcher-bash-sandbox-mirror.test.ts
//      (back to `options: recordCcSeccompArtifact(`).
//      Also delete test/auth-mode-lease-vs-diagnostic.test.ts (the two documented lease-vs-diagnostic divergences, AC10);
//      and, in agent-runner-unix-deny-wire.test.ts / agent-auth-friendly-error-wire-legacy.test.ts, KEEP the
//      `engine-binding-auth-mode` mock (it pins the lease resolver those cases need);
//   7. the `AUTH_FAILURE_DIAGNOSTIC` entries in test/oauth-token-injection-site.test.ts (the CWE-526 identifier allowlist).
//
// Accepted cost: `getFreshTenantClient` may mint a JWT (about 750 ms, against the 60/hour `precheck_jwt_mint` ceiling), and the
// probe's 1.5 s `Promise.race` leaves a slow mint running after the timeout. The probe claims its debounce slot BEFORE it
// calls this resolver, which caps the lookup at one per (user, tuple) per 5 minutes plus the process-wide cap.

import { readConversationBindingAuthMode } from "./engine-binding-auth-mode";

/**
 * Build the resolver for one conversation. It resolves the persisted engine binding's `authMode`, or `null` when the
 * conversation has no engine-run row (an old or unbound conversation; the probe reports that as `unbound`). It rejects on a
 * client or query error (the probe reports that as `unknown`). The raw value is NOT trusted: the probe normalises anything
 * outside `managed | api-key` to `unknown`. The read itself lives in engine-binding-auth-mode.ts, which the credential lease
 * also uses (#11591), so the diagnostic label and the lease read the same fact.
 */
export function makeAuthModeResolver(userId: string, conversationId: string): () => Promise<string | null> {
  return () => readConversationBindingAuthMode(userId, conversationId);
}
