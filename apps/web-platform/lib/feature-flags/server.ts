/**
 * Runtime feature flags — read from process.env at request time.
 *
 * These are NOT NEXT_PUBLIC_* vars (those are baked at build time).
 * Toggle via Doppler + container restart — no Docker rebuild needed.
 *
 * To add a flag: add one entry to FLAG_VARS below.
 */

const FLAG_VARS = {
  "kb-chat-sidebar": "FLAG_KB_CHAT_SIDEBAR",
  "dev-signin": "FLAG_DEV_SIGNIN",
  "team-workspace-invite": "FLAG_TEAM_WORKSPACE_INVITE",
} as const;

type FlagName = keyof typeof FLAG_VARS;

export function getFlag(name: FlagName): boolean {
  return process.env[FLAG_VARS[name]] === "1";
}

export function getFeatureFlags(): Record<FlagName, boolean> {
  const flags = {} as Record<FlagName, boolean>;
  for (const [name, envVar] of Object.entries(FLAG_VARS) as [FlagName, string][]) {
    flags[name] = process.env[envVar] === "1";
  }
  return flags;
}

// Cache keyed on the raw env-var string. Production sees `process.env`
// fixed at boot, so the cache hits on every subsequent call. Tests that
// mutate `TEAM_WORKSPACE_ALLOWLIST_ORG_IDS` re-parse without needing a
// test-only reset hook.
let cachedAllowlist: { raw: string; set: ReadonlySet<string> } | null = null;

export function getTeamWorkspaceAllowlist(): ReadonlySet<string> {
  const raw = process.env.TEAM_WORKSPACE_ALLOWLIST_ORG_IDS ?? "";
  if (cachedAllowlist && cachedAllowlist.raw === raw) return cachedAllowlist.set;
  const set = new Set(
    raw
      .split(",")
      .map((s) => s.trim())
      .filter(Boolean),
  );
  cachedAllowlist = { raw, set };
  return set;
}

/**
 * Two-key gate per AC-F: `FLAG_TEAM_WORKSPACE_INVITE=1` AND `orgId`
 * present in `TEAM_WORKSPACE_ALLOWLIST_ORG_IDS`. Both must hold.
 */
export function isTeamWorkspaceInviteEnabled(orgId: string): boolean {
  if (!getFlag("team-workspace-invite")) return false;
  if (!orgId) return false;
  return getTeamWorkspaceAllowlist().has(orgId);
}
