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
