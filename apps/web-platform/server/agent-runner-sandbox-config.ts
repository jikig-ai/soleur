import { mkdirSync, readdirSync, realpathSync } from "fs";
import { c4RenderStagingRoot } from "./c4-staging-root";
import { AGENT_AUTH_ENV_VARS } from "./agent-auth-env-vars";
import { basename, join } from "path";

import { createChildLogger } from "./logger";
import { reportSilentFallback, warnSilentFallback } from "./observability";

// Match the agent-runner logging convention (`createChildLogger` — see
// agent-runner.ts / agent-runner-query-options.ts) so the shared test mocks
// that stub `createChildLogger` (not the default export) keep working.
const log = createChildLogger("agent-sandbox");

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
//     /proc inside user namespaces; this skips `--proc /proc` in bwrap
//     (#1557). `denyRead` is NOT what keeps the CLI parent's environment out
//     of reach. Measured (ADR-272): no process environment readable from
//     inside the sandbox carries the key. Which bubblewrap flag does that work
//     is not established, so a change to the sandbox flags needs re-measuring
//     (`sandbox-credential-deny-runtime.test.ts` repeats it).
//   - `network.allowedDomains` + `allowManagedDomainsOnly: true` —
//     no outbound network by default; `opts.allowGithubEgress` widens
//     the allowlist to exactly `ENTITLED_EGRESS_DOMAINS` (entitled-token
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
//     `enumerateSiblingDenyPaths`. ADR-075; durable TOCTOU closer is
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
 * FAIL-CLOSED (strand-over-leak): if the root cannot be enumerated, fall back
 * to the BROAD parent deny `[root, "/proc"]`. That makes the workspace
 * read-only (the agent strands) but CANNOT leak a sibling — the correct
 * security failure mode. A non-ENOENT error (permissions, I/O) is always
 * `degraded` + Sentry-mirrored. ENOENT is benign ONLY outside production
 * (local dev / CI / fresh provisioning — no mounted volume, no siblings to
 * leak); in PRODUCTION the volume is bind-mounted at boot, so ENOENT means it
 * VANISHED at runtime — a real fault that also flags `degraded` + pages,
 * instead of masking the strand as expected local-dev absence.
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
    const code = (err as NodeJS.ErrnoException)?.code;
    // ENOENT is benign ONLY in dev/CI (no mounted volume). In production the
    // volume is bind-mounted at boot, so ENOENT means it vanished at runtime —
    // a real fault. Any other error is always a real fault. Both fail closed to
    // the broad parent deny + `degraded` + Sentry mirror
    // (cq-silent-fallback-must-mirror-to-sentry); strand-over-leak. `workspace`
    // (the own UUID) is the join key back to the #5733 strand telemetry so an
    // operator can attribute the degraded event to the session it stranded.
    const benignEnoent =
      code === "ENOENT" && process.env.NODE_ENV !== "production";
    if (!benignEnoent) {
      reportSilentFallback(err, {
        feature: "agent-sandbox",
        op: "enumerateSiblingDenyPaths",
        extra: { workspacesRoot: root, workspace: basename(ownReal) },
      });
      return { denyRead: [root, "/proc"], degraded: true };
    }
    // Benign ENOENT (dev/CI): no siblings exist; deny the root broadly as the
    // safe default. Not `degraded` — it is an expected env.
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
  // W1 (#9601, ADR-272): unset the owner's Anthropic credential for every
  // sandboxed Bash command. Typed (not left to the index signature) so a test
  // reads the entries as data, not `unknown`.
  credentials: {
    envVars: { name: (typeof AGENT_AUTH_ENV_VARS)[number]; mode: "deny" }[];
  };
} & { [x: string]: unknown };

/**
 * GitHub-owned Actions log/artifact download hosts: `api.github.com`
 * 302s `/actions/{runs,jobs}/.../logs` and artifact zips to signed
 * per-account Azure Blob URLs. Enumerated, NOT a wildcard — a
 * `*.blob.core.windows.net` entry would admit EVERY Azure storage
 * account, and exact hosts keep both layers (this domain filter AND
 * the container nftables allowlist) GitHub-scoped even off-host.
 * Fleet verified 2026-10-05: sa0..sa99 resolve EXCEPT sa22 (NXDOMAIN —
 * listing it would page via the resolver failcount). Keep in sync with
 * the productionresultssa block in infra/cron-egress-allowlist.txt and
 * the fleet guards in cron-egress-firewall.test.sh.
 */
const GITHUB_ACTIONS_LOG_ACCOUNTS = Object.freeze([
  "productionresultssa0.blob.core.windows.net",
  "productionresultssa1.blob.core.windows.net",
  "productionresultssa2.blob.core.windows.net",
  "productionresultssa3.blob.core.windows.net",
  "productionresultssa4.blob.core.windows.net",
  "productionresultssa5.blob.core.windows.net",
  "productionresultssa6.blob.core.windows.net",
  "productionresultssa7.blob.core.windows.net",
  "productionresultssa8.blob.core.windows.net",
  "productionresultssa9.blob.core.windows.net",
  "productionresultssa10.blob.core.windows.net",
  "productionresultssa11.blob.core.windows.net",
  "productionresultssa12.blob.core.windows.net",
  "productionresultssa13.blob.core.windows.net",
  "productionresultssa14.blob.core.windows.net",
  "productionresultssa15.blob.core.windows.net",
  "productionresultssa16.blob.core.windows.net",
  "productionresultssa17.blob.core.windows.net",
  "productionresultssa18.blob.core.windows.net",
  "productionresultssa19.blob.core.windows.net",
  "productionresultssa20.blob.core.windows.net",
  "productionresultssa21.blob.core.windows.net",
  "productionresultssa23.blob.core.windows.net",
  "productionresultssa24.blob.core.windows.net",
  "productionresultssa25.blob.core.windows.net",
  "productionresultssa26.blob.core.windows.net",
  "productionresultssa27.blob.core.windows.net",
  "productionresultssa28.blob.core.windows.net",
  "productionresultssa29.blob.core.windows.net",
  "productionresultssa30.blob.core.windows.net",
  "productionresultssa31.blob.core.windows.net",
  "productionresultssa32.blob.core.windows.net",
  "productionresultssa33.blob.core.windows.net",
  "productionresultssa34.blob.core.windows.net",
  "productionresultssa35.blob.core.windows.net",
  "productionresultssa36.blob.core.windows.net",
  "productionresultssa37.blob.core.windows.net",
  "productionresultssa38.blob.core.windows.net",
  "productionresultssa39.blob.core.windows.net",
  "productionresultssa40.blob.core.windows.net",
  "productionresultssa41.blob.core.windows.net",
  "productionresultssa42.blob.core.windows.net",
  "productionresultssa43.blob.core.windows.net",
  "productionresultssa44.blob.core.windows.net",
  "productionresultssa45.blob.core.windows.net",
  "productionresultssa46.blob.core.windows.net",
  "productionresultssa47.blob.core.windows.net",
  "productionresultssa48.blob.core.windows.net",
  "productionresultssa49.blob.core.windows.net",
  "productionresultssa50.blob.core.windows.net",
  "productionresultssa51.blob.core.windows.net",
  "productionresultssa52.blob.core.windows.net",
  "productionresultssa53.blob.core.windows.net",
  "productionresultssa54.blob.core.windows.net",
  "productionresultssa55.blob.core.windows.net",
  "productionresultssa56.blob.core.windows.net",
  "productionresultssa57.blob.core.windows.net",
  "productionresultssa58.blob.core.windows.net",
  "productionresultssa59.blob.core.windows.net",
  "productionresultssa60.blob.core.windows.net",
  "productionresultssa61.blob.core.windows.net",
  "productionresultssa62.blob.core.windows.net",
  "productionresultssa63.blob.core.windows.net",
  "productionresultssa64.blob.core.windows.net",
  "productionresultssa65.blob.core.windows.net",
  "productionresultssa66.blob.core.windows.net",
  "productionresultssa67.blob.core.windows.net",
  "productionresultssa68.blob.core.windows.net",
  "productionresultssa69.blob.core.windows.net",
  "productionresultssa70.blob.core.windows.net",
  "productionresultssa71.blob.core.windows.net",
  "productionresultssa72.blob.core.windows.net",
  "productionresultssa73.blob.core.windows.net",
  "productionresultssa74.blob.core.windows.net",
  "productionresultssa75.blob.core.windows.net",
  "productionresultssa76.blob.core.windows.net",
  "productionresultssa77.blob.core.windows.net",
  "productionresultssa78.blob.core.windows.net",
  "productionresultssa79.blob.core.windows.net",
  "productionresultssa80.blob.core.windows.net",
  "productionresultssa81.blob.core.windows.net",
  "productionresultssa82.blob.core.windows.net",
  "productionresultssa83.blob.core.windows.net",
  "productionresultssa84.blob.core.windows.net",
  "productionresultssa85.blob.core.windows.net",
  "productionresultssa86.blob.core.windows.net",
  "productionresultssa87.blob.core.windows.net",
  "productionresultssa88.blob.core.windows.net",
  "productionresultssa89.blob.core.windows.net",
  "productionresultssa90.blob.core.windows.net",
  "productionresultssa91.blob.core.windows.net",
  "productionresultssa92.blob.core.windows.net",
  "productionresultssa93.blob.core.windows.net",
  "productionresultssa94.blob.core.windows.net",
  "productionresultssa95.blob.core.windows.net",
  "productionresultssa96.blob.core.windows.net",
  "productionresultssa97.blob.core.windows.net",
  "productionresultssa98.blob.core.windows.net",
  "productionresultssa99.blob.core.windows.net",
] as const);

/**
 * Egress allowlist for an entitled (ghToken-minting) session. Exact
 * hosts only, no wildcards — each added host is exfiltration surface:
 *  - `github.com` — raw `git push/fetch` via the GIT_ASKPASS path.
 *  - `api.github.com` — `gh` (REST + GraphQL).
 *  - `registry.npmjs.org` — sessions regenerate package-lock.json via
 *    `npx npm@11` (the lockfile-sync gate pins npm@11); npm serves
 *    metadata and tarballs from this one host.
 *  - `...GITHUB_ACTIONS_LOG_ACCOUNTS` — the signed-URL hosts above.
 * Widening further (gist/upload/CDN, GitHub user-content domains)
 * requires its own security review.
 */
const ENTITLED_EGRESS_DOMAINS = Object.freeze([
  "github.com",
  "api.github.com",
  "registry.npmjs.org",
  ...GITHUB_ACTIONS_LOG_ACCOUNTS,
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
  opts?: { allowGithubEgress?: boolean; readOnly?: boolean; denyReadExtra?: readonly string[] },
): AgentSandboxConfig {
  const { denyRead: siblingDeny, degraded } = enumerateSiblingDenyPaths(workspacePath);
  // ADR-113 — support-persona containment: additional absolute paths to obscure
  // (`--tmpfs`) from the read-only support session. The support agent runs under
  // `--ro-bind / /` (whole FS readable) with Bash (kb-search greps), so the
  // internal `knowledge-base/` (confidential operator post-mortems/roadmap/ADRs)
  // is denied here at the tool/root level — NOT by prompt. Deduped with the
  // sibling deny set. NOTE: this is defense-in-depth; the LIVE `support-live` flag
  // stays OFF until a deployed-env QA confirms no internal-KB content leaks.
  //
  // #8623: the C4 re-render stages OTHER tenants' committed `.c4` sources
  // under this server-private root for the length of a render. Deny it so no
  // agent can read a concurrent render's stage. The SDK SKIPS a deny path that
  // does not exist yet ("Skipping non-existent read deny path"), so create it
  // first (0700, best-effort) — otherwise the first render after boot would
  // create an undenied root under a sandbox that started earlier.
  const c4StagingRoot = c4RenderStagingRoot();
  let c4StagingRootReady = true;
  try {
    mkdirSync(c4StagingRoot, { recursive: true, mode: 0o700 });
  } catch (err) {
    // The SDK skips a missing deny path, so a root created LATER (by a render)
    // would be readable from this session. Surface it rather than swallow it.
    c4StagingRootReady = false;
    warnSilentFallback(err, {
      feature: "agent-sandbox",
      op: "c4-staging-root",
      message: "agent-sandbox: C4 staging root could not be created; its read-deny may not apply",
    });
  }
  const denyRead = Array.from(
    new Set([...siblingDeny, c4StagingRoot, ...(opts?.denyReadExtra ?? [])]),
  );
  // Structured, no-SSH observability of the isolation decision per dispatch
  // (observability-coverage-reviewer §Step 4.6 — the affected surface is the
  // agent sandbox). `degraded: true` is the fail-closed broad-deny path a
  // reviewer/operator can alert on; `deniedCount` makes the deny-set size
  // queryable per session.
  log.info(
    {
      feature: "agent-sandbox",
      op: "sibling-deny",
      workspacesRoot: workspacesRoot(),
      // Own workspace UUID — the join key so this isolation decision is
      // attributable to a session (every sibling shares `workspacesRoot`).
      workspace: basename(workspacePath),
      deniedCount: denyRead.length,
      degraded,
      c4StagingRootReady,
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
    // restriction). enableWeakerNestedSandbox skips --proc /proc in bwrap
    // (#1557). `denyRead` is not what protects the CLI parent's environment;
    // the outcome (no readable environ carries the key) is measured in ADR-272
    // and pinned by sandbox-credential-deny-runtime.test.ts, the mechanism is not.
    enableWeakerNestedSandbox: true,
    network: {
      allowedDomains: opts?.allowGithubEgress ? [...ENTITLED_EGRESS_DOMAINS] : [],
      allowManagedDomainsOnly: true,
    },
    filesystem: {
      // Full read+write of the agent's OWN workspace: it is NOT in denyRead,
      // so the base `--ro-bind / /` grants read and this `--bind` grants
      // write — no read-only `--ro-bind` shadow (the PR #5848 regression).
      //
      // feat-wire-concierge-support-chat (ADR-113): `readOnly` (support persona)
      // sets `allowWrite: []` — the whole session is read-only. This is
      // load-bearing: the support cwd is `getPluginPath()` (the shared platform
      // plugin root), so a default `allowWrite:[workspacePath]` would grant WRITE
      // to platform-controlled code (the CTO-flagged P1 supply-chain escape). The
      // read-only invariant is enforced HERE (a sandbox-write fact), not merely by
      // the cwd or the disallowedTools list.
      allowWrite: opts?.readOnly ? [] : [workspacePath],
      // Per-sibling deny (NOT the broad "/workspaces" parent) so the own
      // workspace's rw bind is never `--tmpfs`-shadowed. See module header.
      denyRead,
    },
    // W1 (#9601, ADR-272): a prompt-injected session cannot read the owner's
    // Anthropic key out of its shell. `deny` unsets the variable for
    // every sandboxed command; the CLI process keeps it for its own API calls.
    // Deliberately NOT denied: connected-service tokens (the agent is told they
    // are available — `## Connected Services`), GH_TOKEN and
    // GIT_INSTALLATION_TOKEN (`gh`/`git` need the short-lived App token). Those
    // stay readable until the credential broker (#9543). Measured on SDK
    // 0.3.284: the API key reaches Bash by default; the OAuth token is already
    // withheld by the CLI, so its entry is defense in depth.
    credentials: {
      envVars: AGENT_AUTH_ENV_VARS.map((name) => ({
        name,
        mode: "deny" as const,
      })),
    },
  };
}
