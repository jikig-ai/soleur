// W1 (#9601): the hosted agent's sandboxed Bash must not see the owner's
// Anthropic credential. `buildAgentSandboxConfig` carries
// `credentials.envVars` deny entries for exactly the auth variables
// `buildAgentEnv` can inject; service tokens and GH_TOKEN stay readable
// (Connected Services depends on them — see ADR-272).
//
// The injected set is DERIVED from `buildAgentEnv`'s output by value flow: the
// credential is a unique sentinel, and an auth variable is any key whose value
// carries it. That makes the guard independent of the constant it checks — a
// third variable set from the credential, in one scheme or in every scheme, in
// any option shape, changes the derived set and fails here. The wire from the
// builder to the real `query()` options is pinned in
// agent-runner-query-options.test.ts.

import { mkdirSync, mkdtempSync, rmSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

import { buildAgentEnv, type AgentCredential } from "@/server/agent-env";
import { API_KEY_ENV_VAR, AGENT_AUTH_ENV_VARS } from "@/server/agent-auth-env-vars";
import { buildAgentSandboxConfig } from "@/server/agent-runner-sandbox-config";
import { PROVIDER_CONFIG } from "@/server/providers";

// Every auth scheme. A Record keyed on the union makes a NEW scheme a compile
// error here, so it cannot be added to the injector without being sampled.
const SCHEME_REGISTRY: Record<AgentCredential["scheme"], true> = {
  api_key: true,
  oauth_token: true,
};
const SCHEMES = Object.keys(SCHEME_REGISTRY) as AgentCredential["scheme"][];

const SENTINEL = "credential-sentinel-7c1e4f";

// Option shapes buildAgentEnv takes: bare, and with every optional input set.
const SHAPES: { label: string; tokens?: Record<string, string>; opts?: Parameters<typeof buildAgentEnv>[2] }[] = [
  { label: "bare" },
  {
    label: "all inputs",
    tokens: Object.fromEntries(Object.values(PROVIDER_CONFIG).map((c) => [c.envVar, "service-token-value"])),
    opts: {
      ghToken: "gh-token-value",
      gitAskpassScriptPath: "/tmp/askpass.sh",
      gitInstallationToken: "installation-token-value",
      pluginPath: "/tmp/plugins/soleur",
    },
  },
];

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

  // Keys of buildAgentEnv's output whose VALUE carries the credential.
  const authVarsFor = (scheme: AgentCredential["scheme"], shape: (typeof SHAPES)[number]): string[] =>
    Object.entries(buildAgentEnv({ scheme, value: SENTINEL }, shape.tokens, shape.opts))
      .filter(([, v]) => v.includes(SENTINEL))
      .map(([k]) => k)
      .sort();

  const injectedAuthVars = (): string[] =>
    [...new Set(SCHEMES.flatMap((scheme) => SHAPES.flatMap((shape) => authVarsFor(scheme, shape))))].sort();

  it("injects exactly ONE auth variable per scheme and option shape (the silent-billing trap)", () => {
    for (const scheme of SCHEMES) {
      for (const shape of SHAPES) {
        expect(authVarsFor(scheme, shape), `${scheme} / ${shape.label}`).toHaveLength(1);
      }
    }
  });

  it("denies exactly the auth variables buildAgentEnv can inject, in deny mode", () => {
    const entries = denied();
    expect(entries.map((e) => e.name).sort()).toEqual(injectedAuthVars());
    for (const e of entries) expect(e.mode).toBe("deny");
  });

  it("is anchored to the shared constant, and the instrument is not empty", () => {
    expect(SCHEMES.length).toBeGreaterThanOrEqual(2);
    expect(injectedAuthVars()).toEqual([...AGENT_AUTH_ENV_VARS].sort());
    expect(new Set(denied().map((e) => e.name)).size).toBe(denied().length);
  });

  it("the provider table names the same API-key variable as the shared constant", () => {
    // `providers.ts` repeats the literal (it must stay importable on the client
    // side); a rename in one place must not leave the other behind.
    expect(PROVIDER_CONFIG.anthropic.envVar).toBe(API_KEY_ENV_VAR);
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

  it("keeps the credentials block on the read-only (support persona) and egress configs too", () => {
    for (const opts of [{ readOnly: true }, { allowGithubEgress: true }]) {
      const entries = buildAgentSandboxConfig(own, opts).credentials.envVars;
      expect(entries.map((e) => e.name).sort(), JSON.stringify(opts)).toEqual(injectedAuthVars());
    }
  });
});
