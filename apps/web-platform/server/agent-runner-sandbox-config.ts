// Sandbox config helper extracted from agent-runner.ts so two consumers
// — `startAgentSession` (legacy domain-leader path) and the cc-soleur-go
// `realSdkQueryFactory` in `cc-dispatcher.ts` — share the SAME literal
// shape verbatim. See drift-guard `agent-runner-helpers.test.ts`.
//
// Field semantics:
//   - `failIfUnavailable: true` — refuse to start if bwrap/socat are
//     missing. Tier 4 defense-in-depth (see #2634). Without this flag the
//     SDK silently runs unsandboxed; agent-runner stderr-substring check
//     for `sandbox required but unavailable` mirrors to Sentry under
//     `feature: "agent-sandbox"` (the cc path mirrors the same precedent
//     — see `cc-dispatcher.ts realSdkQueryFactory` body).
//   - `enableWeakerNestedSandbox: true` — Docker containers cannot mount
//     /proc inside user namespaces; this skips `--proc /proc` in bwrap.
//     `/proc` is already in `denyRead`, so the weaker mode is acceptable
//     (#1557).
//   - `network.allowedDomains: []` + `allowManagedDomainsOnly: true` —
//     no outbound network.
//   - `filesystem.allowWrite: [workspacePath]` + `denyRead` —
//     workspace-confined writes; deny reads outside.

// SDK's `SandboxSettings` is a Zod-inferred type with `[x: string]: unknown`
// index signature. Our helper returns a structurally-compatible object
// without re-deriving from Zod (keeps the helper Zod-import-free).
// Index-signature intersection lets the call site assign without `as`
// at the SDK boundary.
export type AgentSandboxConfig = {
  enabled: true;
  failIfUnavailable: true;
  autoAllowBashIfSandboxed: true;
  allowUnsandboxedCommands: false;
  enableWeakerNestedSandbox: true;
  network: {
    allowedDomains: string[];
    allowManagedDomainsOnly: true;
  };
  filesystem: {
    allowWrite: string[];
    denyRead: string[];
  };
} & { [x: string]: unknown };

/**
 * Build the canonical sandbox options block. Output is deep-equal to the
 * inline literal previously inlined at the `query({ options: { sandbox: ... } })`
 * call site in `agent-runner.ts`. Drift here propagates to BOTH the
 * legacy domain-leader runner AND the cc-soleur-go factory.
 */
export function buildAgentSandboxConfig(
  workspacePath: string,
): AgentSandboxConfig {
  return {
    enabled: true,
    // Refuse to start if sandbox deps (bubblewrap, socat) are missing.
    // Without this flag, the SDK silently runs unsandboxed on dependency
    // drift (per `Options.sandbox.failIfUnavailable` in
    // @anthropic-ai/claude-agent-sdk) — Tier 4 defense-in-depth
    // disappears with no Sentry signal. See #2634.
    failIfUnavailable: true,
    autoAllowBashIfSandboxed: true,
    allowUnsandboxedCommands: false,
    // Docker containers cannot mount proc inside user namespaces (kernel
    // restriction). enableWeakerNestedSandbox skips --proc /proc in bwrap,
    // which is acceptable because /proc is already in denyRead (#1557).
    enableWeakerNestedSandbox: true,
    network: {
      allowedDomains: [],
      allowManagedDomainsOnly: true,
    },
    filesystem: {
      allowWrite: [workspacePath],
      denyRead: ["/workspaces", "/proc"],
    },
  };
}
