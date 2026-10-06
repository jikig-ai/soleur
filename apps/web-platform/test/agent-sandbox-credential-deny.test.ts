// W1 (#9601): the hosted agent's sandboxed Bash must not see the owner's
// Anthropic credential. `buildAgentSandboxConfig` carries
// `credentials.envVars` deny entries for exactly the auth variables
// `buildAgentEnv` can inject; service tokens and GH_TOKEN stay readable
// (Connected Services depends on them — see ADR-272).
//
// The assertions are over the RETURNED object and over what `buildAgentEnv`
// actually injects per scheme — never over a constant — so deleting the
// block, changing `mode`, or adding an auth variable on the injection side
// alone all fail here.

import { mkdirSync, mkdtempSync, rmSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { buildAgentEnv, type AgentCredential } from "@/server/agent-env";
import { AGENT_AUTH_ENV_VARS } from "@/server/agent-auth-env-vars";
import { buildAgentSandboxConfig } from "@/server/agent-runner-sandbox-config";
import { PROVIDER_CONFIG } from "@/server/providers";

const SCHEMES: AgentCredential["scheme"][] = ["api_key", "oauth_token"];

describe("buildAgentSandboxConfig — Anthropic credential deny (W1)", () => {
  let root: string;
  let own: string;

  beforeEach(() => {
    root = mkdtempSync(join(tmpdir(), "sbx-cred-deny-"));
    own = join(root, "00000000-0000-0000-0000-000000000001");
    mkdirSync(own);
    vi.stubEnv("WORKSPACES_ROOT", root);
    vi.stubEnv("C4_RENDER_STAGING_ROOT", `${root}-c4-staging`);
  });

  afterEach(() => {
    vi.unstubAllEnvs();
    rmSync(root, { recursive: true, force: true });
    rmSync(`${root}-c4-staging`, { recursive: true, force: true });
  });

  const denied = (): { name: string; mode: string }[] =>
    buildAgentSandboxConfig(own).credentials.envVars;

  // The auth variables buildAgentEnv can inject, derived from its OUTPUT:
  // each scheme injects exactly one exclusive auth variable, so the union of
  // per-scheme keys minus the keys common to every scheme is the auth set.
  // A third auth variable added on the injection side changes this set.
  const injectedAuthVars = (): string[] => {
    const perScheme = SCHEMES.map(
      (scheme) =>
        new Set(Object.keys(buildAgentEnv({ scheme, value: "probe-value" }))),
    );
    const union = new Set(perScheme.flatMap((s) => [...s]));
    return [...union].filter((k) => !perScheme.every((s) => s.has(k))).sort();
  };

  it("denies exactly the auth variables buildAgentEnv can inject, in deny mode", () => {
    const entries = denied();
    expect(entries.map((e) => e.name).sort()).toEqual(injectedAuthVars());
    for (const e of entries) expect(e.mode).toBe("deny");
  });

  it("covers both schemes and the shared constant (instrument is not empty)", () => {
    expect(SCHEMES.length).toBeGreaterThanOrEqual(2);
    expect(injectedAuthVars().length).toBe(SCHEMES.length);
    expect(denied().length).toBe(AGENT_AUTH_ENV_VARS.length);
    expect(new Set(denied().map((e) => e.name)).size).toBe(denied().length);
  });

  it("does NOT deny connected-service tokens, GH_TOKEN, or the git installation token", () => {
    const names = new Set(denied().map((e) => e.name));
    const serviceVars = Object.values(PROVIDER_CONFIG)
      .map((c) => c.envVar)
      .filter((v) => !(AGENT_AUTH_ENV_VARS as readonly string[]).includes(v));
    expect(serviceVars.length).toBeGreaterThan(5);
    for (const v of serviceVars) expect(names.has(v)).toBe(false);
    expect(names.has("GH_TOKEN")).toBe(false);
    expect(names.has("GIT_INSTALLATION_TOKEN")).toBe(false);
  });

  it("keeps the credentials block on the read-only (support persona) config too", () => {
    const entries = buildAgentSandboxConfig(own, {
      readOnly: true,
    }).credentials.envVars;
    expect(entries.map((e) => e.name).sort()).toEqual(injectedAuthVars());
  });
});
