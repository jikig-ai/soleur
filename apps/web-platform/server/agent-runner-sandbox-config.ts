import { readdirSync, realpathSync } from "fs";
import { join } from "path";

import logger from "./logger";
import { reportSilentFallback } from "./observability";

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
//   - `filesystem.allowWrite: [workspacePath]` + PER-SIBLING `denyRead` —
//     the agent gets full READ+WRITE of its OWN `/workspaces/<uuid>` while
//     every OTHER tenant workspace is hidden. Critical history (#5733):
//     the `@anthropic-ai/claude-agent-sdk` (v0.2.85) bwrap builder emits
//     the write-plane binds FIRST, then the read-plane LAST (`--tmpfs
//     <denyRead-dir>`, then `--ro-bind` for each `allowRead` child). So a
//     broad `denyRead: ["/workspaces"]` `--tmpfs`-obscures the whole tree
//     AFTER the `allowWrite --bind`, and the ONLY post-tmpfs re-bind the
//     SDK offers (`allowRead`) is READ-ONLY — which shadows the rw bind and
//     makes the workspace read-only (PR #5848 shipped exactly that and
//     turned the "not a git repository" strand into "read-only file
//     system"; verified locally with bwrap 0.11.1). There is no
//     "allowWrite-within-deny" knob. The only SDK-expressible config that
//     is simultaneously writable-own AND tenant-isolated is to deny each
//     SIBLING individually (so the own workspace is never under a `--tmpfs`
//     and its `allowWrite --bind` survives), computed at dispatch by
//     `enumerateSiblingDenyPaths`. ADR-<pending>; durable TOCTOU closer is
//     the vendored SDK bwrap-arg reorder (tracked follow-up).

const WORKSPACES_ROOT_DEFAULT = "/workspaces";

/** Resolve WORKSPACES_ROOT at call time so tests can stub the env per-case. */
function workspacesRoot(): string {
  return process.env.WORKSPACES_ROOT || WORKSPACES_ROOT_DEFAULT;
}

/** Canonicalize a path, tolerating a missing target (returns the input). */
function safeRealpath(p: string): string {
  try {
    return realpathSync(p);
  } catch {
    return p;
  }
}

/**
 * Compute the sandbox `denyRead` list for the agent whose workspace is
 * `workspacePath`: every OTHER entry under `WORKSPACES_ROOT` (each tenant
 * workspace, plus infra siblings like `.cron` / `.orphaned-*` the agent has
 * no business reading) is denied, PLUS `/proc`. The agent's OWN workspace is
 * deliberately NOT in the deny set — so the SDK never `--tmpfs`-obscures it
 * and its `allowWrite --bind` keeps it read+write (see the module header for
 * why a broad `denyRead: ["/workspaces"]` cannot do this).
 *
 * Own-vs-sibling is decided on CANONICALIZED paths (`realpathSync`), never a
 * basename string, so a symlinked workspace cannot be misclassified as a
 * sibling (which would deny the agent its own repo) or vice-versa.
 *
 * FAIL-CLOSED (strand-over-leak): if the root cannot be enumerated for any
 * reason OTHER than ENOENT (permissions, I/O), fall back to the BROAD parent
 * deny `[root, "/proc"]` and flag `degraded`. That makes the workspace
 * read-only (the agent strands) but CANNOT leak a sibling — the correct
 * security failure mode. ENOENT means "no mounted volume" (local dev / CI /
 * fresh provisioning): expected, no Sentry page, and there are no siblings to
 * leak, so the broad deny is harmless there.
 */
export function enumerateSiblingDenyPaths(workspacePath: string): {
  denyRead: string[];
  degraded: boolean;
} {
  const root = workspacesRoot();
  const ownReal = safeRealpath(workspacePath);
  try {
    const siblings = readdirSync(root)
      .map((name) => join(root, name))
      .filter((p) => safeRealpath(p) !== ownReal);
    return { denyRead: [...siblings, "/proc"], degraded: false };
  } catch (err) {
    if ((err as NodeJS.ErrnoException)?.code !== "ENOENT") {
      // Real enumeration failure — mirror to Sentry
      // (cq-silent-fallback-must-mirror-to-sentry) and fail closed to the
      // broad parent deny. strand-over-leak.
      reportSilentFallback(err, {
        feature: "agent-sandbox",
        op: "enumerateSiblingDenyPaths",
        extra: { workspacesRoot: root },
      });
      return { denyRead: [root, "/proc"], degraded: true };
    }
    // ENOENT: no mounted volume (local/CI). No siblings exist; deny the root
    // broadly as the safe default. Not `degraded` — it is an expected env.
    return { denyRead: [root, "/proc"], degraded: false };
  }
}

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
 * Build the canonical sandbox options block. Drift here propagates to BOTH
 * the legacy domain-leader runner AND the cc-soleur-go factory (they both
 * call this helper), so the per-sibling deny stays byte-identical across
 * paths automatically.
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
  const { denyRead, degraded } = enumerateSiblingDenyPaths(workspacePath);
  // Structured, no-SSH observability of the isolation decision per dispatch
  // (observability-coverage-reviewer §Step 4.6 — the affected surface is the
  // agent sandbox). `degraded: true` is the fail-closed broad-deny path a
  // reviewer/operator can alert on; `deniedCount` makes the deny-set size
  // queryable per session.
  logger.info(
    {
      feature: "agent-sandbox",
      op: "sibling-deny",
      workspacesRoot: workspacesRoot(),
      deniedCount: denyRead.length,
      degraded,
    },
    "agent-sandbox: computed per-sibling denyRead",
  );
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
      // Full read+write of the agent's OWN workspace: it is NOT in denyRead,
      // so the base `--ro-bind / /` grants read and this `--bind` grants
      // write — no read-only `--ro-bind` shadow (the PR #5848 regression).
      allowWrite: [workspacePath],
      // Per-sibling deny (NOT the broad "/workspaces" parent) so the own
      // workspace's rw bind is never `--tmpfs`-shadowed. See module header.
      denyRead,
    },
  };
}
