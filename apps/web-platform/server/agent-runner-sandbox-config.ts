import { accessSync, constants, mkdirSync, readdirSync, readFileSync, realpathSync, statSync } from "fs";
import { c4RenderStagingRoot } from "./c4-staging-root";
import { AGENT_AUTH_ENV_VARS } from "./agent-auth-env-vars";
import { basename, delimiter, join } from "path";
import * as Sentry from "@sentry/nextjs";

import { ALLOWED_SERVICE_ENV_VARS } from "./agent-env";
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
//
// #8752 — the two hardening layers this config cannot express through the SDK
// (the vendored builder owns the whole bwrap argv, transported on `--args
// <fd>`) live OUTSIDE this object, at the spawn layer: the PATH shim
// `infra/bwrap-shim/bwrap` (installed at /usr/local/bin/bwrap) closes
// inherited fds not referenced by the argv and injects the shared
// nested-userns filter via --add-seccomp-fd before exec'ing the real
// /usr/bin/bwrap. `probeAgentSandboxHardening` below is the boot-time
// measurement of that pair; the deploy-time measurement is the canary's
// `runHardeningProbes`.

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
    envVars: { name: string; mode: "deny" }[];
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

// feat-open-web-egress (#9534) — Phase-A credential quarantine for sessions
// whose workspace enabled open web egress. With an open egress path, ANY
// secret readable inside the sandbox is one prompt-injected `curl` away
// from an attacker host — so the entitled session runs with NO readable
// credentials in-sandbox (the UI copy promises "sessions run without stored
// credentials in sandboxed commands"; the Phase-B broker #9543 restores
// credentialed push). This census lives HERE (next to the deny emission) so
// a new credential-bearing env var lands in the deny set the moment it is
// added — derived from ALLOWED_SERVICE_ENV_VARS (the injection allowlist),
// never hand-copied.
//
// Fixed names:
//   - `GH_TOKEN`, `GIT_ASKPASS`, `GIT_INSTALLATION_TOKEN`, `GIT_USERNAME` —
//     the in-sandbox gh/raw-git auth set (the askpass pair is deliberately
//     injected for non-entitled sessions; under open egress it becomes an
//     exfiltratable secret, so ALL four go — the both-or-nothing env pair
//     is denied as a unit).
//   - `GIT_TERMINAL_PROMPT` — not a secret, but denying the whole GIT_*
//     auth surface keeps the census one rule ("no GIT_* auth plumbing
//     readable") rather than a per-name judgment call. The `0` value only
//     suppresses credential prompts — irrelevant once the credential set
//     itself is denied.
//   - the two CLI auth vars — denied for EVERY session by the W1 baseline
//     (#9601); the census omits them because the CWE-526 sentinel pins even
//     the identifiers to agent-env.ts and denies-reference right is reserved
//     to AGENT_AUTH_ENV_VARS below.
//     `deny` unsets for SANDBOXED COMMANDS ONLY (the CLI process keeps
//     them; model calls unaffected — see plan §corrections).
//   - every ALLOWED_SERVICE_ENV_VARS name — the full BYOK service-token
//     census (STRIPE_SECRET_KEY, GITHUB_TOKEN, DOPPLER_TOKEN, …).
// `GIT_CONFIG_NOSYSTEM`/`GIT_CONFIG_GLOBAL` are deliberately ABSENT: they
// are `/dev/null` neutralizations, and denying them would undo the
// neutralization (plan review correction (a)).
// Deduped: GITHUB_TOKEN appears in BOTH the fixed list and
// ALLOWED_SERVICE_ENV_VARS (plan review correction (b)). The two Anthropic
// auth vars are absent on purpose — the W1 baseline denies them for every
// session and the credentials block unions both lists.
const WEB_EGRESS_ENV_DENY_CENSUS = Object.freeze(
  Array.from(
    new Set([
      "GH_TOKEN",
      "GIT_ASKPASS",
      "GIT_INSTALLATION_TOKEN",
      "GIT_USERNAME",
      "GIT_TERMINAL_PROMPT",
      ...ALLOWED_SERVICE_ENV_VARS,
    ]),
  ),
);

/** Absolute paths denied to the entitled session's sandboxed commands:
 *  the token-dir mount (a readable session token = gateway auth for the
 *  session's whole lifetime) + the conventional credential file locations
 *  (`GOOGLE_APPLICATION_CREDENTIALS` holds a PATH, so its target is a file
 *  deny, not an env deny). `~` resolves against the container HOME. */
function webEgressDenyReadPaths(): string[] {
  const home = process.env.HOME ?? "/root";
  const paths = [
    process.env.EGRESS_TOKEN_DIR ?? "/var/lib/soleur/egress-tokens",
    join(home, ".ssh"),
    join(home, ".gnupg"),
    join(home, ".netrc"),
    join(home, ".aws"),
    join(home, ".git-credentials"),
    join(home, ".config", "gh"),
    join(home, ".claude", ".credentials.json"),
  ];
  // A GOOGLE_APPLICATION_CREDENTIALS path (when set) is a credential FILE —
  // deny its target too.
  const gac = process.env.GOOGLE_APPLICATION_CREDENTIALS;
  if (gac) paths.push(gac);
  return paths;
}


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
  opts?: {
    allowGithubEgress?: boolean;
    readOnly?: boolean;
    denyReadExtra?: readonly string[];
    /** feat-open-web-egress (#9534) — the workspace's `web_egress` grant is
     *  ON for this dispatch AND the forwarder is live (fail-closed: the
     *  dispatcher passes false when spawn fails). Phase-A quarantine:
     *  `credentials.envVars` deny census unsets every secret var for
     *  sandboxed commands and `denyRead` gains the credential-file + token-
     *  dir paths. Open egress NEEDS no `httpProxyPort` here — the spawned
     *  CLI's env proxy URL already steers both the in-process and the
     *  SRT-chained sandboxed paths (Phase-0 spike, spec TR7). */
    allowWebEgress?: boolean;
  },
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
    new Set([
      ...siblingDeny,
      c4StagingRoot,
      ...(opts?.denyReadExtra ?? []),
      // feat-open-web-egress (#9534): credential files + the token-dir mount
      // are denied ONLY for the entitled session (an unentitled session has
      // no gateway credential to protect, and the extra denies would just be
      // dead config there).
      ...(opts?.allowWebEgress ? webEgressDenyReadPaths() : []),
    ]),
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
    // feat-open-web-egress (#9534) — Phase-A credential quarantine. The W1
    // baseline denies the two Anthropic auth vars to sandboxed Bash for EVERY
    // session (#9601, ADR-272). For a web-egress-entitled session the deny
    // widens to the full secret census: service tokens, GH_* auth vars, the
    // GIT_* auth surface — the CLI process keeps them all (in-process tools
    // unaffected). No `mask` entries: masking would re-inject the real value
    // at the SRT proxy for allowedDomains hosts, and under open egress the
    // whole point is that NOTHING credential-shaped leaves the box through
    // the agent's channel.
    credentials: {
      envVars: Array.from(
        new Set([
          ...AGENT_AUTH_ENV_VARS,
          ...(opts?.allowWebEgress ? WEB_EGRESS_ENV_DENY_CENSUS : []),
        ]),
      ).map((name) => ({ name, mode: "deny" as const })),
    },
  };
}

// ---------------------------------------------------------------------------
// #8752 — boot self-check for the Agent SDK sandbox hardening pair.
// ---------------------------------------------------------------------------

/** Default path of the committed nested-userns filter artifact inside the
 *  runner image (Dockerfile COPY) — the same default the C4 close-fds prelude
 *  and the bwrap PATH shim resolve via `SOLEUR_BWRAP_SECCOMP_BPF`. */
const BWRAP_SECCOMP_BPF_DEFAULT = "/app/infra/bwrap-userns-clone3-deny.bpf";

/** PATH resolution for `name`; returns the first executable hit or null. */
function resolveOnPath(name: string, env: Record<string, string | undefined>): string | null {
  for (const dir of (env.PATH ?? "").split(delimiter)) {
    if (!dir) continue;
    const p = join(dir, name);
    try {
      accessSync(p, constants.X_OK);
      return p;
    } catch {
      // not here / not executable — keep looking
    }
  }
  return null;
}

export interface AgentSandboxHardeningProbe {
  /** Resolved PATH location of `bwrap` (null when absent). */
  bwrapPath: string | null;
  /** The resolved binary carries the shim's `bwrap-shim:` marker. */
  shim: boolean;
  bpfPath: string;
  bpfBytes: number;
  /** Readable, non-empty, raw-sock_filter-sized (multiple of 8 bytes). */
  filter: boolean;
  ok: boolean;
}

/**
 * Measure — never throw — whether the agent-sandbox hardening pair is live in
 * this image: PATH-resolved `bwrap` is our shim (closes inherited fds +
 * injects the filter) and the committed seccomp artifact is present and
 * `sock_filter`-shaped. Shim identity is a CONTENT marker (`bwrap-shim:`), not
 * the path — a PATH-order or binary-swap drift cannot satisfy it.
 */
export function probeAgentSandboxHardening(
  env: Record<string, string | undefined> = process.env,
): AgentSandboxHardeningProbe {
  const bwrapPath = resolveOnPath("bwrap", env);
  let shim = false;
  if (bwrapPath) {
    try {
      shim = readFileSync(bwrapPath, "utf8").includes("bwrap-shim:");
    } catch {
      shim = false;
    }
  }
  const bpfPath = env.SOLEUR_BWRAP_SECCOMP_BPF || BWRAP_SECCOMP_BPF_DEFAULT;
  let bpfBytes = 0;
  try {
    bpfBytes = statSync(bpfPath).size;
  } catch {
    // artifact absent
  }
  const filter = bpfBytes > 0 && bpfBytes % 8 === 0;
  return { bwrapPath, shim, bpfPath, bpfBytes, filter, ok: shim && filter };
}

/**
 * Emit the #8752 self-probe result once at boot: `log.info` + Sentry info on
 * success (the success signal — Vector ships WARN+ to Better Stack, so info
 * goes to Sentry like `c4 render sandbox probe ok`), `warnSilentFallback`
 * otherwise (Sentry warn + Better Stack). Never throws; called un-awaited
 * from the server `listen` callback in production.
 */
export function verifyAgentSandboxHardening(): void {
  try {
    const p = probeAgentSandboxHardening();
    if (p.ok) {
      log.info(
        { feature: "agent-sandbox", op: "sandbox-hardening-selfprobe", ...p },
        "agent-sandbox: hardening self-probe ok (shim on PATH + filter artifact present)",
      );
      try {
        Sentry.captureMessage("agent sandbox hardening probe ok", {
          level: "info",
          tags: { event_type: "agent-sandbox-hardening-probe" },
          extra: { ...p },
        });
      } catch {
        // Sentry must never break the probe.
      }
      return;
    }
    warnSilentFallback(null, {
      feature: "agent-sandbox",
      op: "sandbox-hardening-selfprobe",
      message: "agent sandbox hardening self-probe: shim or filter artifact missing",
      extra: { ...p },
    });
  } catch (err) {
    warnSilentFallback(err, {
      feature: "agent-sandbox",
      op: "sandbox-hardening-selfprobe",
      message: "agent sandbox hardening self-probe threw",
    });
  }
}
