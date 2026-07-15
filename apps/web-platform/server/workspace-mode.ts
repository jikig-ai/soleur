// Workspace execution mode — the single pure discriminant that drives whether a
// Concierge dispatch runs the repo lifecycle (Command Center) or read-only from
// the platform docs root (in-app support chat).
//
// feat-wire-concierge-support-chat, ADR-113 (CTO ruling: "Hardened B" — a
// required `persona` discriminant computed ONCE into a discriminated union, with
// the repo-gate skip + cwd + sandbox write-set all DERIVED from that one value,
// rather than the plan's ExecutionEnvironment provider-seam extraction of the
// 4367-line realSdkQueryFactory). This is the subsystem's own idiom
// (agent-runner-query-options.ts `credential` / `ghToken`→egress derivation):
// deriving the three concerns from one union makes the half-wired state
// UNREPRESENTABLE — a docs cwd can never pair with a non-empty write-set, and a
// repo-less mode can never keep the readiness/clone/lease gates.
//
// `persona` is a REQUIRED string-literal union on the dispatch interfaces (NOT an
// optional flag): the two leak axes have OPPOSITE safe defaults (a support turn's
// danger is GAINING repo/write; a Command Center turn's danger is LOSING gates),
// so there is no safe default — the only safe posture is "must be set explicitly."
// A dropped hop is then a missing-required-field compile error, and a garbage/cast
// value hits the exhaustive `never` and THROWS rather than silently defaulting to
// the repo path.

export type Persona = "command_center" | "support";

/**
 * The resolved, self-consistent execution mode. Built by `resolveWorkspaceMode`
 * so the three axes are bound together at construction:
 *  - `runRepoLifecycle` — run the readiness gate / clone self-heal / worktree
 *    write-lease / patchWorkspacePermissions (Command Center) or skip them all
 *    (support runs against pre-existing platform docs).
 *  - `cwdSource` — `"workspace"` = the user's resolved workspace path;
 *    `"plugin"` = `getPluginPath()` (the boot-validated, read-only platform docs
 *    root; ADR-093).
 *  - `sandboxWrite` — `"workspace"` = `allowWrite: [workspacePath]`;
 *    `"none"` = `allowWrite: []`. Support MUST be `"none"`: otherwise a
 *    `cwd = getPluginPath()` session with the default `allowWrite:[workspacePath]`
 *    would grant WRITE to the shared platform plugin root (the supply-chain
 *    read-only-escape the CTO review flagged as P1).
 */
export type WorkspaceMode =
  | {
      persona: "command_center";
      runRepoLifecycle: true;
      cwdSource: "workspace";
      sandboxWrite: "workspace";
    }
  | {
      persona: "support";
      runRepoLifecycle: false;
      cwdSource: "plugin";
      sandboxWrite: "none";
    };

export function resolveWorkspaceMode(persona: Persona): WorkspaceMode {
  switch (persona) {
    case "command_center":
      return {
        persona: "command_center",
        runRepoLifecycle: true,
        cwdSource: "workspace",
        sandboxWrite: "workspace",
      };
    case "support":
      return {
        persona: "support",
        runRepoLifecycle: false,
        cwdSource: "plugin",
        sandboxWrite: "none",
      };
    default: {
      // Exhaustiveness guard — a garbage/cast persona must THROW LOUDLY, never
      // fall through to the repo (over-capability) path.
      const _exhaustive: never = persona;
      throw new Error(`resolveWorkspaceMode: unknown persona ${String(_exhaustive)}`);
    }
  }
}
