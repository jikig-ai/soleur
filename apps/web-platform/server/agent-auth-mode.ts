// The authMode lookup for the agent auth-failure diagnostic (agent-auth-failure.ts). Injected at both call sites as a
// resolver so the matcher and the probe stay free of the Supabase graph, and so the lookup runs only on the failure path.
//
// REMOVAL CHECKLIST (the diagnostic is temporary; deleting it is one pass):
//   1. server/agent-auth-failure.ts and this file. KEEP server/agent-auth-match.ts (the pure matcher) and
//      server/agent-auth-user-message.ts: the friendly error (#11086) calls the matcher, so the matcher is product code now.
//      When deleting, re-point the imports of `matchAgentAuthFailure`/`AgentAuthMatchKind` to ./agent-auth-match;
//   2. in `claude-error-signatures.ts` delete only SDK_API_KEY_SOURCES. KEEP CLI_AUTH_FAILURE_REPLIES, SDK_AUTHENTICATION_FAILED,
//      the `CliAuthFailureKind` type and the "REPLY signatures" paragraph of the file header (the matcher reads them);
//   3. in agent-runner.ts and cc-dispatcher.ts: the import, `createAgentAuthFailureProbe` with its `let authProbe = NOOP_AGENT_AUTH_PROBE`
//      try/catch and the `warnAgentAuthProbeUnavailable()` call, the `authProbe.bindOptions(` wrapper (re-indent the closing
//      parens), the `observe` call, and `tapAgentAuthFailure(` around `sdkQuery(`;
//   4. the comment in claude-code-message-translator.ts that names SDK_AUTHENTICATION_FAILED, and the "Wrapper note" comment
//      in test/agent-sandbox-seccomp-selector.test.ts;
//   5. the Sentry rule `agent_auth_failure`: ONE PR deletes the rule from issue-alerts.tf, its alert-reference.json entry and the
//      infra/sentry README counts, entry and decode table (the plan_pr gate requires the committed reference to equal the
//      plan's projection in the same PR), with `[ack-destroy]` alone on a line in a commit BODY (infra/sentry/README.md);
//   6. the tests: agent-auth-failure-{probe,tap,sentry-path}.test.ts, sentry-agent-auth-failure-alert-op-contract.test.ts
//      (KEEP agent-auth-failure-matcher.test.ts and rename it to agent-auth-match.test.ts: it is the matcher's own suite),
//      the wiring cases (and their hoisted mocks and imports) in agent-runner-unix-deny-wire.test.ts and
//      cc-dispatcher-real-factory.test.ts, and the widened regex in test/server/cc-dispatcher-bash-sandbox-mirror.test.ts
//      (back to `options: recordCcSeccompArtifact(`).
//   7. the `AUTH_FAILURE_DIAGNOSTIC` entries in test/oauth-token-injection-site.test.ts (the CWE-526 identifier allowlist).
//
// Accepted cost: `getFreshTenantClient` may mint a JWT (about 750 ms, against the 60/hour `precheck_jwt_mint` ceiling), and the
// probe's 1.5 s `Promise.race` leaves a slow mint running after the timeout. The probe claims its debounce slot BEFORE it
// calls this resolver, which caps the lookup at one per (user, tuple) per 5 minutes plus the process-wide cap.

import { getFreshTenantClient } from "@/lib/supabase/tenant";

import { AgentEnginePersistenceRepository, type PersistenceClient } from "./agent-engine-persistence";

/**
 * Build the resolver for one conversation. It resolves the persisted engine binding's `authMode`, or `null` when the
 * conversation has no engine-run row (an old or unbound conversation; the probe reports that as `unbound`). It rejects on a
 * client or query error (the probe reports that as `unknown`). The raw value is NOT trusted: the probe normalises anything
 * outside `managed | api-key` to `unknown`.
 */
export function makeAuthModeResolver(userId: string, conversationId: string): () => Promise<string | null> {
  return async () => {
    const tenant = await getFreshTenantClient(userId);
    const repo = new AgentEnginePersistenceRepository(tenant as unknown as PersistenceClient);
    const run = (await repo.getConversationRun(conversationId)) as { binding?: { authMode?: unknown } } | null;
    const mode = run?.binding?.authMode;
    return typeof mode === "string" ? mode : null;
  };
}
