import { accessSync, constants, existsSync, mkdirSync, readFileSync, statSync } from "fs";
import { c4RenderStagingRoot } from "./c4-staging-root";
import {
  getWorkspacesRoot,
  isGitDataStoreEnabled,
  workspaceEffectiveRoot,
  workspaceTenantDenyRoots,
} from "./workspace-resolver";
import { AGENT_AUTH_ENV_VARS } from "./agent-auth-env-vars";
import { basename, delimiter, join } from "path";
import * as Sentry from "@sentry/nextjs";

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
//   - `filesystem.allowWrite: [workspacePath]` + broad PARENT `denyRead` —
//     the agent gets full READ+WRITE of its OWN `/workspaces/<uuid>` while
//     every OTHER tenant workspace (present AND future) is masked. History
//     (#5733): the SDK at v0.2.85 emitted write-plane binds FIRST, then
//     `--tmpfs <denyRead-dir>` LAST — a broad `/workspaces` deny obscured the
//     own workspace and the only post-tmpfs re-bind (`allowRead`) was
//     READ-ONLY, shadowing the rw bind (PR #5848's read-only regression). So
//     the interim fix denied each sibling individually via dispatch-time
//     `readdirSync` — which carried a residual TOCTOU (a sibling created
//     after namespace build was never enumerated).
//     The vendored CLI 2.1.284 builder closes that gap (#5862, ADR-075 exit
//     criterion): per covering `denyRead` landing, the builder emits
//     `--tmpfs <landing>` BEFORE re-binding each covered `allowWrite` path rw
//     (`Re-bound write path wiped by denyRead tmpfs`) and each covered
//     `allowRead` path ro (`Re-allowed read access within denied region`).
//     Broad `denyRead: [<tenant roots>]` is
//     therefore expressible AND safe — the parent tmpfs masks the whole tree
//     at namespace build, so a sibling created mid-session is never visible.
//     The committed argv fixture pins this ordering; a future SDK drift that
//     re-inverts it fails `test/sandbox-canary.test.ts`'s ordering pin and the
//     capture gate's byte-diff.
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
    /** ADR-113 support persona only: ro re-bind of `workspacePath` inside the
     * denied parent (the vendor's allowWithinDeny restore). */
    allowRead?: string[];
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
 * call this helper), so the constant tenant deny stays byte-identical across
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
  // ADR-113 — support-persona containment: additional absolute paths to obscure
  // (`--tmpfs`) from the read-only support session. The support agent runs under
  // `--ro-bind / /` (whole FS readable) with Bash retained as the
  // deny+escalate tripwire (kb-search itself is Read/Grep/Glob-only, #9559), so the
  // internal `knowledge-base/` (confidential operator post-mortems/roadmap/ADRs)
  // is denied here at the tool/root level — NOT by prompt. Deduped with the
  // constant deny set. NOTE: this is defense-in-depth; the LIVE `support-live` flag
  // stays OFF until a deployed-env QA confirms no internal-KB content leaks.
  //
  // #8623: the C4 re-render stages OTHER tenants' committed `.c4` sources
  // under this server-private root for the length of a render. Deny it so no
  // agent can read a concurrent render's stage. The SDK SKIPS a deny landing
  // that does not exist or cannot be mounted ("mounts nothing this wrap can
  // place (absent, or uninspectable, …)" in the vendored builder), so create it
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
  // #5862 (ADR-075 exit criterion): the CONSTANT parent deny. The vendored
  // CLI 2.1.284 builder emits `--tmpfs <landing>` per denyRead entry, then
  // re-binds each covered `allowWrite`/`allowRead` path after the covering
  // landing — so masking the whole workspaces root also masks every sibling
  // created after the namespace build (the enumeration-era TOCTOU). A deny
  // landing that does not exist mounts nothing and is skipped by the builder,
  // which reproduces the old benign-ENOENT posture on dev hosts with no
  // /workspaces volume — but in PRODUCTION the volume is bind-mounted at
  // boot, so a missing root is a vanished-mount fault worth paging on
  // (the signal the deleted `degraded` arm carried; restored here as a
  // cheap existence bit, not enumeration).
  // #9725 (ADR-068 aftermath): the deny set is every root where tenant
  // working trees can live — workspaceTenantDenyRoots() returns the volume
  // root AND, once the git-data flag is on, the worktree root. Denying only
  // WORKSPACES_ROOT post-cutover would mask an empty directory while sibling
  // trees sit readable under /var/lib/soleur/worktrees. Constant per dispatch
  // (roots, not dir entries), so the mid-session TOCTOU posture is unchanged.
  const denyRoots = workspaceTenantDenyRoots();
  const denyRootsExist = denyRoots.map((root) => existsSync(root));
  denyRoots.forEach((root, i) => {
    // Page only on roots expected to exist NOW: the volume root always, the
    // worktree root once the flag is on (pre-flip, a not-yet-staged NVMe root
    // is expected-absent — reporting it would desensitize the real
    // vanished-mount tripwire this arm restores).
    const expected = i === 0 || isGitDataStoreEnabled();
    if (expected && process.env.NODE_ENV === "production" && !denyRootsExist[i]) {
      reportSilentFallback(new Error(`tenant deny root missing: ${root}`), {
        feature: "agent-sandbox",
        op: "tenant-deny",
        extra: { denyRoot: root, workspace: basename(workspacePath) },
      });
    }
  });
  // Guard the catastrophic misconfiguration: a workspacePath that IS or
  // CONTAINS a deny root would make the vendor's restore re-bind the whole
  // root after the tmpfs — unmasking every sibling rw. Impossible under the
  // uuid layout (join(root, uuid)); fail loud if it ever drifts.
  const wsNorm = workspacePath.replace(/\/+$/, "");
  for (const rootNorm of denyRoots) {
    if (wsNorm === rootNorm || rootNorm.startsWith(`${wsNorm}/`)) {
      throw new Error(
        `buildAgentSandboxConfig: workspacePath ${workspacePath} equals/contains deny root ${rootNorm} — refusing to build a sandbox that would unmask every tenant`,
      );
    }
  }
  // denyReadExtra contract: absolute paths to existing DIRECTORIES (a file →
  // `--tmpfs` → spawn failure). An extra under the own workspace only masks
  // if the vendor emits it after the ws restore — do not rely on that order.
  //
  // #9723: the vendored builder's `enableWeakerNestedSandbox` tail re-binds
  // the real `--bind /proc /proc` AFTER every denyRead entry — the `/proc`
  // tmpfs here is intent only; the REALIZED mask is the bwrap shim's tail
  // `--proc /proc` splice (a pidns-scoped procfs mounted over the tail bind —
  // see infra/bwrap-shim/bwrap + test/bwrap-shim.test.ts).
  const denyRead = Array.from(
    new Set([...denyRoots, c4StagingRoot, "/proc", ...(opts?.denyReadExtra ?? [])]),
  );
  // Structured, no-SSH observability of the isolation decision per dispatch
  // (observability-coverage-reviewer §Step 4.6 — the affected surface is the
  // agent sandbox). `deniedCount` is now constant (3 + extras) per session —
  // a drift in it is a config diff, not live directory state.
  log.info(
    {
      feature: "agent-sandbox",
      op: "tenant-deny",
      // Self-describing per-root rows (not parallel arrays) — a Sentry query
      // reads root+existence as one record, no positional correlation.
      tenantDenyRoots: denyRoots.map((root, i) => ({
        root,
        exists: denyRootsExist[i],
      })),
      // The git-data flag state + the effective resolution root — the pair a
      // cutover-window reader needs to tell a legit flag-off deny from drift.
      gitDataStoreEnabled: isGitDataStoreEnabled(),
      workspaceEffectiveRoot: workspaceEffectiveRoot(),
      // Own workspace UUID — the join key so this isolation decision is
      // attributable to a session (every sibling shares the deny roots).
      workspace: basename(workspacePath),
      deniedCount: denyRead.length,
      c4StagingRootReady,
      // Detection surface for the vanished-volume fault (replaces the deleted
      // enumeration arm's `degraded`): emitted per dispatch, always. Resolved
      // from the resolver's own getter, not the deny-set position (a "/" env
      // value is excluded from the set and would mislabel index 0).
      workspacesRootExists: existsSync(getWorkspacesRoot()),
      workspaceUnderDenyRoot: denyRoots.some((root) => wsNorm.startsWith(`${root}/`)),
      // The drift tripwire #9725 names: the workspace resolves under the
      // resolver's EFFECTIVE root (flag-shaped), not just any deny root — a
      // post-flip workspace still under the volume root must read false.
      workspaceUnderEffectiveRoot: wsNorm.startsWith(`${workspaceEffectiveRoot()}/`),
    },
    "agent-sandbox: computed tenant denyRead",
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
      // Full read+write of the agent's OWN workspace: it sits UNDER the
      // denied parent root, but the vendored builder (CLI 2.1.284) re-binds
      // every covered `allowWrite` path rw AFTER the `--tmpfs` landing
      // (deny-then-restore — see module header), so the bind survives the
      // mask. PR #5848's read-only regression cannot recur under this
      // ordering, and the committed-fixture ordering pin
      // (test/sandbox-canary.test.ts) reddens on any SDK drift that
      // re-inverts it.
      //
      // feat-wire-concierge-support-chat (ADR-113): `readOnly` (support persona)
      // sets `allowWrite: []` — the whole session is read-only. This is
      // load-bearing: the support cwd is `getPluginPath()` (the shared platform
      // plugin root), so a default `allowWrite:[workspacePath]` would grant WRITE
      // to platform-controlled code (the CTO-flagged P1 supply-chain escape). The
      // read-only invariant is enforced HERE (a sandbox-write fact), not merely by
      // the cwd or the disallowedTools list.
      allowWrite: opts?.readOnly ? [] : [workspacePath],
      denyRead,
      // readOnly arm: if `workspacePath` ever lands under the denied parent
      // (a root-resident read-only session), `allowRead` → the vendor's
      // `allowWithinDeny` re-binds it `--ro-bind` after the tmpfs. Today's
      // support persona sets workspacePath=pluginPath (outside the root), so
      // the arm is inert — kept as the forward-declared contract so a future
      // root-resident read-only caller doesn't silently blank.
      ...(opts?.readOnly ? { allowRead: [workspacePath] } : {}),
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
