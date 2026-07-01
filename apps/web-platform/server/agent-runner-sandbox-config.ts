// Sandbox config helper extracted from agent-runner.ts so two consumers
// — `startAgentSession` (legacy domain-leader path) and the cc-soleur-go
// `realSdkQueryFactory` in `cc-dispatcher.ts` — share the same literal
// shape, identical except for the token-derived `network.allowedDomains`
// (#5041 follow-up). See drift-guard `agent-runner-helpers.test.ts`.
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
//   - `network.allowedDomains` + `allowManagedDomainsOnly: true` —
//     no outbound network by default; `opts.allowGithubEgress` widens
//     the allowlist to exactly `GITHUB_EGRESS_DOMAINS` (entitled-token
//     sessions only — derived from `ghToken` presence at the consumer).
//   - `filesystem.allowWrite: [workspacePath]` + `denyRead` +
//     `allowRead: [workspacePath]` — workspace-confined writes; deny reads
//     outside; RE-ALLOW reads of the agent's OWN workspace within the
//     `denyRead: ["/workspaces"]` region. Critical (#5733): `allowWrite`
//     grants WRITE only — per the SDK, reading within a `denyRead` region
//     requires an explicit `allowRead` (which "takes precedence over
//     denyRead"). Without it, the bwrap builder tmpfs-obscures the whole
//     `/workspaces` tree and nothing re-binds the workspace for read, so the
//     agent cannot `git rev-parse`/`ls` its own repo and strands on "not a
//     git repository" (Sentry WEB-PLATFORM-46: gitKind=dir-valid,
//     gitRevParseValid=false). `allowRead` re-binds ONLY `workspacePath`
//     (read-only, on top of the tmpfs), so sibling tenants' `/workspaces/<other>`
//     stay hidden — cross-tenant isolation is preserved.

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
    allowRead: string[];
  };
} & { [x: string]: unknown };

/**
 * Exact-host egress allowlist for the Concierge's in-sandbox GitHub
 * surface. No wildcards — `gh` (REST + GraphQL) needs `api.github.com`;
 * raw `git push/fetch` via the GIT_ASKPASS path needs `github.com`.
 * Widening beyond these two hosts (gist/upload/CDN) requires its own
 * security review — each added host is exfiltration surface.
 */
const GITHUB_EGRESS_DOMAINS = Object.freeze([
  "github.com",
  "api.github.com",
] as const);

/**
 * Build the canonical sandbox options block. Output is deep-equal to the
 * inline literal previously inlined at the `query({ options: { sandbox: ... } })`
 * call site in `agent-runner.ts`. Drift here propagates to BOTH the
 * legacy domain-leader runner AND the cc-soleur-go factory.
 *
 * `opts.allowGithubEgress` widens ONLY `network.allowedDomains` to the
 * exact GitHub hosts. Callers must derive it from entitled-token
 * presence (`Boolean(ghToken)`), never pass `true` unconditionally —
 * the sandbox proxy denies all other hosts either way
 * (`allowManagedDomainsOnly` stays on).
 */
export function buildAgentSandboxConfig(
  workspacePath: string,
  opts?: { allowGithubEgress?: boolean },
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
      allowedDomains: opts?.allowGithubEgress ? [...GITHUB_EGRESS_DOMAINS] : [],
      allowManagedDomainsOnly: true,
    },
    filesystem: {
      allowWrite: [workspacePath],
      denyRead: ["/workspaces", "/proc"],
      // Re-allow reading the agent's OWN workspace within the `/workspaces`
      // deny region (#5733). `allowWrite` grants write only; without this
      // the agent cannot read its own repo and strands on "not a git
      // repository". Scoped to `workspacePath` alone — sibling workspaces
      // stay denied (cross-tenant isolation).
      allowRead: [workspacePath],
    },
  };
}
