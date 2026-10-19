// #10455 (a): the per-session seccomp artifact selector (ADR-075 addendum 2026-10-19).
// Guard 3 rows 1, 8, 9: usesUnixDenyArtifact is the single predicate and seccompArtifactFor the single path resolver;
// buildAgentEnv sets SOLEUR_BWRAP_SECCOMP_BPF to the unixdeny artifact only for NO-EGRESS
// sessions while the runtime flag is ON; the flag defaults OFF and fails closed to OFF;
// every direct caller of the two builders is accounted for.
import { describe, it, expect, afterEach, beforeEach, vi } from "vitest";
import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const APP_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const REPO_ROOT = join(APP_ROOT, "..", "..");

vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
  warnSilentFallback: vi.fn(),
  mirrorWarnWithDebounce: vi.fn(),
  mirrorWithDebounce: vi.fn(),
}));
const childLog = vi.hoisted(() => ({ info: vi.fn(), warn: vi.fn(), error: vi.fn() }));
vi.mock("@/server/logger", () => ({ default: childLog, createChildLogger: vi.fn(() => childLog) }));

import {
  SECCOMP_BASE_ARTIFACT,
  SECCOMP_UNIXDENY_ARTIFACT,
  seccompArtifactFor,
  usesUnixDenyArtifact,
  checkSeccompAgreement,
  unixdenyArtifactPath,
} from "@/server/agent-sandbox-seccomp";
import { buildAgentEnv } from "@/server/agent-env";
import { buildAgentSandboxConfig, probeAgentSandboxHardening } from "@/server/agent-runner-sandbox-config";
import { buildAgentQueryOptions } from "@/server/agent-runner-query-options";
import { warnSilentFallback } from "@/server/observability";
import { resolveWorkspaceMode } from "@/server/workspace-mode";

const CRED = { value: "sk-test", scheme: "api_key" as const };
const SEL = "SOLEUR_BWRAP_SECCOMP_BPF";

describe("usesUnixDenyArtifact is the single predicate; seccompArtifactFor the single path resolver", () => {
  it("the table: variant only for no-egress with the flag ON", () => {
    const rows: Array<[boolean, boolean, string]> = [
      [false, true, SECCOMP_UNIXDENY_ARTIFACT],
      [false, false, SECCOMP_BASE_ARTIFACT],
      [true, true, SECCOMP_BASE_ARTIFACT],
      [true, false, SECCOMP_BASE_ARTIFACT],
    ];
    expect(rows.length).toBe(4);
    for (const [egress, flag, want] of rows) {
      expect(seccompArtifactFor(egress, flag, {}), `egress=${egress} flag=${flag}`).toBe(want);
    }
  });
  it("the flag argument defaults OFF (a caller that forgets it gets today's posture)", () => {
    expect(seccompArtifactFor(false, undefined, {})).toBe(SECCOMP_BASE_ARTIFACT);
    expect(usesUnixDenyArtifact(false)).toBe(false);
  });
  it("the base arm honours the ambient incident-time override", () => {
    expect(seccompArtifactFor(true, true, { [SEL]: "/tmp/override.bpf" })).toBe("/tmp/override.bpf");
    expect(seccompArtifactFor(false, false, { [SEL]: "/tmp/override.bpf" })).toBe("/tmp/override.bpf");
  });
  it("the variant path is under the baked infra dir next to the base artifact", () => {
    expect(SECCOMP_UNIXDENY_ARTIFACT).toBe("/app/infra/bwrap-userns-clone3-unixdeny.bpf");
    expect(SECCOMP_BASE_ARTIFACT).toBe("/app/infra/bwrap-userns-clone3-deny.bpf");
  });
});

describe("dispatcher agreement: buildAgentEnv and buildAgentSandboxConfig", () => {
  let ambient: string | undefined;
  beforeEach(() => {
    ambient = process.env[SEL];
    delete process.env[SEL];
  });
  afterEach(() => {
    if (ambient === undefined) delete process.env[SEL];
    else process.env[SEL] = ambient;
  });

  // [github egress, web egress, flag]
  const cases: Array<[boolean, boolean, boolean]> = [
    [false, false, true],
    [false, false, false],
    [true, false, true],
    [true, false, false],
    [false, true, true],
    [false, true, false],
  ];
  const build = (gh: boolean, web: boolean, flag: boolean) => {
    const env = buildAgentEnv(CRED, undefined, {
      ...(gh ? { ghToken: "ghs_x" } : {}),
      ...(web ? { egressProxy: { workspaceId: "w", token: "t", port: 1 } } : {}),
      sandboxUnixDeny: flag,
    });
    const sandbox = buildAgentSandboxConfig("/workspaces/w", {
      allowGithubEgress: gh,
      allowWebEgress: web,
      sandboxUnixDeny: flag,
    });
    return { env, sandbox };
  };

  it("the variant selector is set for no-egress + flag ON only", () => {
    let evaluated = 0;
    for (const [gh, web, flag] of cases) {
      const { env, sandbox } = build(gh, web, flag);
      const egress = gh || web;
      const wantVariant = !egress && flag;
      expect(env[SEL], `gh=${gh} web=${web} flag=${flag}`).toBe(wantVariant ? SECCOMP_UNIXDENY_ARTIFACT : undefined);
      expect(checkSeccompAgreement(env, sandbox), `gh=${gh} web=${web} flag=${flag}`).toBeNull();
      evaluated++;
    }
    expect(evaluated).toBe(cases.length);
  });
  it("flag OFF passes the ambient override through unchanged; flag ON for an egress session also does", () => {
    process.env[SEL] = "/tmp/incident-override.bpf";
    expect(build(false, false, false).env[SEL]).toBe("/tmp/incident-override.bpf");
    expect(build(true, false, true).env[SEL]).toBe("/tmp/incident-override.bpf");
    expect(build(false, false, true).env[SEL]).toBe(SECCOMP_UNIXDENY_ARTIFACT);
  });
  it("the flag defaults OFF in both builders (omitted option = base artifact)", () => {
    const env = buildAgentEnv(CRED, undefined, {});
    expect(env[SEL]).toBeUndefined();
    const sandbox = buildAgentSandboxConfig("/workspaces/w");
    expect(checkSeccompAgreement(env, sandbox)).toBeNull();
  });
  it("the spawn-time check returns the disagreement text (it never throws) when env and config disagree", () => {
    // a no-egress config with the flag ON, but an env that kept the base artifact
    const sandbox = buildAgentSandboxConfig("/workspaces/w", { sandboxUnixDeny: true });
    const envBase = buildAgentEnv(CRED, undefined, { sandboxUnixDeny: false });
    expect(checkSeccompAgreement(envBase, sandbox)).toMatch(/seccomp/i);
    // an egress env carrying the variant (the bridge-breaking direction)
    const egressEnv = buildAgentEnv(CRED, undefined, { ghToken: "ghs_x", sandboxUnixDeny: false });
    egressEnv[SEL] = SECCOMP_UNIXDENY_ARTIFACT;
    const egressCfg = buildAgentSandboxConfig("/workspaces/w", { allowGithubEgress: true, sandboxUnixDeny: true });
    expect(checkSeccompAgreement(egressEnv, egressCfg)).toMatch(/artifact disagreement/i);
    // egress disagreement: env has a GH token, config was built without egress
    const noEgressCfg = buildAgentSandboxConfig("/workspaces/w", { sandboxUnixDeny: false });
    expect(checkSeccompAgreement(egressEnv, noEgressCfg)).toMatch(/egress/i);
  });
  it("a config that was not built by buildAgentSandboxConfig is reported (no recorded posture)", () => {
    expect(checkSeccompAgreement({}, { enabled: true } as never)).toMatch(/posture/i);
  });
});

describe("spawn-time agreement is fail-safe (F1: mirror to Sentry, correct toward base, never throw)", () => {
  const OVERRIDE = "/tmp/incident-override.bpf";
  const args = {
    workspacePath: "/tmp/test-workspace",
    pluginPath: "/tmp/test-workspace/plugins/soleur",
    mode: resolveWorkspaceMode("command_center"),
    credential: CRED,
    serviceTokens: {} as Record<string, string>,
    systemPrompt: "x",
    canUseTool: (async () => ({ behavior: "allow" as const, updatedInput: {} })) as never,
  };
  let ambient: string | undefined;
  beforeEach(() => {
    ambient = process.env[SEL];
    vi.mocked(warnSilentFallback).mockClear();
  });
  afterEach(() => {
    if (ambient === undefined) delete process.env[SEL];
    else process.env[SEL] = ambient;
  });

  it("an egress session with the ambient selector set to the unixdeny path ends on base, warns once, does not throw", () => {
    process.env[SEL] = unixdenyArtifactPath();
    let opts: Record<string, any> | undefined;
    expect(() => {
      opts = buildAgentQueryOptions({ ...args, ghToken: "ghs_x", sandboxUnixDeny: false });
    }).not.toThrow();
    expect(opts!.env?.[SEL]).toBe(SECCOMP_BASE_ARTIFACT);
    const calls = vi.mocked(warnSilentFallback).mock.calls.filter((c) => (c[1] as { op?: string })?.op === "seccomp-agreement");
    expect(calls.length).toBe(1);
    expect(calls[0][1]).toMatchObject({ feature: "agent-sandbox", op: "seccomp-agreement" });
    expect((calls[0][1] as { message: string }).message).toMatch(/artifact disagreement/i);
  });
  it("a no-egress flag-OFF session with the ambient unixdeny selector is corrected to base too", () => {
    process.env[SEL] = unixdenyArtifactPath();
    const opts = buildAgentQueryOptions({ ...args, sandboxUnixDeny: false });
    expect(opts.env?.[SEL]).toBe(SECCOMP_BASE_ARTIFACT);
  });
  it("never corrects in the other direction: a flag-ON no-egress session keeps the variant, with no warning", () => {
    delete process.env[SEL];
    const opts = buildAgentQueryOptions({ ...args, sandboxUnixDeny: true });
    expect(opts.env?.[SEL]).toBe(SECCOMP_UNIXDENY_ARTIFACT);
    expect(vi.mocked(warnSilentFallback).mock.calls.filter((c) => (c[1] as { op?: string })?.op === "seccomp-agreement").length).toBe(0);
  });
  it("an unrelated ambient override (not the unixdeny path) is left untouched", () => {
    process.env[SEL] = OVERRIDE;
    const opts = buildAgentQueryOptions({ ...args, ghToken: "ghs_x", sandboxUnixDeny: false });
    expect(opts.env?.[SEL]).toBe(OVERRIDE);
    expect(vi.mocked(warnSilentFallback).mock.calls.filter((c) => (c[1] as { op?: string })?.op === "seccomp-agreement").length).toBe(0);
  });
});

describe("probeAgentSandboxHardening verifies BOTH artifacts", () => {
  const BASE = join(APP_ROOT, "infra/bwrap-userns-clone3-deny.bpf");
  const VARIANT = join(APP_ROOT, "infra/bwrap-userns-clone3-unixdeny.bpf");
  const shimDir = join(APP_ROOT, "infra/bwrap-shim");
  it("ok only when the base and the unixdeny artifact are both sock_filter-shaped", () => {
    const ok = probeAgentSandboxHardening({ PATH: shimDir, [SEL]: BASE, SOLEUR_BWRAP_SECCOMP_BPF_UNIXDENY: VARIANT });
    expect(ok).toMatchObject({ shim: true, filter: true, unixdenyFilter: true, ok: true, unixdenyBytes: 160 });
    const missing = probeAgentSandboxHardening({
      PATH: shimDir,
      [SEL]: BASE,
      SOLEUR_BWRAP_SECCOMP_BPF_UNIXDENY: join(shimDir, "absent.bpf"),
    });
    expect(missing).toMatchObject({ filter: true, unixdenyFilter: false, ok: false, unixdenyBytes: 0 });
  });
});

describe("the runtime flag agent-sandbox-unix-deny", () => {
  const FLAG_ENV = "FLAG_AGENT_SANDBOX_UNIX_DENY";
  it("is registered, defaults OFF in .env.example and is read only through the resolver", () => {
    const src = readFileSync(join(APP_ROOT, "lib/feature-flags/server.ts"), "utf8");
    expect(src).toContain(`"agent-sandbox-unix-deny": "${FLAG_ENV}"`);
    const envExample = readFileSync(join(APP_ROOT, ".env.example"), "utf8");
    expect(envExample).toMatch(new RegExp(`^${FLAG_ENV}=0$`, "m"));
  });
});

describe("resolveSandboxUnixDeny fails closed to OFF", () => {
  const flagMock = vi.hoisted(() => ({ isAgentSandboxUnixDenyEnabled: vi.fn() }));
  vi.mock("@/lib/feature-flags/server", async (importOriginal) => ({
    ...(await importOriginal<typeof import("@/lib/feature-flags/server")>()),
    isAgentSandboxUnixDenyEnabled: flagMock.isAgentSandboxUnixDenyEnabled,
  }));
  it("true only when the flag service answers exactly true", async () => {
    const { resolveSandboxUnixDeny } = await import("@/server/resolve-sandbox-unix-deny");
    flagMock.isAgentSandboxUnixDenyEnabled.mockResolvedValueOnce(true);
    expect(await resolveSandboxUnixDeny()).toBe(true);
    flagMock.isAgentSandboxUnixDenyEnabled.mockResolvedValueOnce(false);
    expect(await resolveSandboxUnixDeny()).toBe(false);
    flagMock.isAgentSandboxUnixDenyEnabled.mockResolvedValueOnce(undefined);
    expect(await resolveSandboxUnixDeny()).toBe(false);
    flagMock.isAgentSandboxUnixDenyEnabled.mockResolvedValueOnce("true");
    expect(await resolveSandboxUnixDeny()).toBe(false);
  });
  it("an unreachable flag service (throw) or a hang (timeout) resolves OFF", async () => {
    const { resolveSandboxUnixDeny } = await import("@/server/resolve-sandbox-unix-deny");
    flagMock.isAgentSandboxUnixDenyEnabled.mockRejectedValueOnce(new Error("flagsmith down"));
    expect(await resolveSandboxUnixDeny()).toBe(false);
    flagMock.isAgentSandboxUnixDenyEnabled.mockImplementationOnce(() => new Promise(() => {}));
    expect(await resolveSandboxUnixDeny(25)).toBe(false);
  });
});

// ---- call-site census (Guard 3 row 9) ---------------------------------------
// Re-derived with git grep: every file that CALLS (not merely mentions) a builder.
describe("call-site census", () => {
  const grep = (pattern: string, paths: string[]) => {
    const r = spawnSync("git", ["grep", "--untracked", "-nE", pattern, "--", ...paths], { cwd: APP_ROOT, encoding: "utf8" });
    expect([0, 1]).toContain(r.status);
    return r.stdout
      .split("\n")
      .filter(Boolean)
      .filter((l) => {
        // drop comment-only and import lines
        const body = l.replace(/^[^:]+:\d+:/, "").trim();
        return !/^(\/\/|\*|\/\*|import\b)/.test(body) && !/\bfunction\s+(buildAgentSandboxConfig|buildAgentEnv|buildAgentQueryOptions)\b/.test(body);
      });
  };
  const files = (lines: string[]) => [...new Set(lines.map((l) => l.split(":")[0]))].sort();

  it("buildAgentSandboxConfig / buildAgentEnv are called from exactly the known modules", () => {
    const lines = grep("\\b(buildAgentSandboxConfig|buildAgentEnv)\\(", ["server", "scripts", "app", "lib"]);
    const f = files(lines).filter((x) => !/\.test\./.test(x));
    expect(f).toEqual([
      "scripts/plugin-root-sandbox-propagation-probe.mjs",
      "scripts/sandbox-canary.mjs",
      "server/agent-runner-query-options.ts",
    ]);
    expect(f.length).toBe(3); // floor: an empty grep must not pass
  });
  it("buildAgentQueryOptions is called from the two runners and the dev probe, and the runners pass the resolved flag", () => {
    const lines = grep("\\bbuildAgentQueryOptions\\(", ["server", "scripts"]);
    const f = files(lines).filter((x) => !/\.test\./.test(x));
    expect(f).toEqual(["scripts/dev-probe-destroy-ask.ts", "server/agent-runner.ts", "server/cc-dispatcher.ts"]);
    for (const runner of ["server/agent-runner.ts", "server/cc-dispatcher.ts"]) {
      const src = readFileSync(join(APP_ROOT, runner), "utf8");
      expect(src, runner).toMatch(/resolveSandboxUnixDeny\(\)/);
      expect(src, runner).toMatch(/sandboxUnixDeny/);
    }
  });
  it("query-options derives both builders' egress from the same session handles and runs the spawn-time assertion", () => {
    const src = readFileSync(join(APP_ROOT, "server/agent-runner-query-options.ts"), "utf8");
    expect(src).toContain("sandboxUnixDeny: args.sandboxUnixDeny");
    expect((src.match(/sandboxUnixDeny: args\.sandboxUnixDeny/g) ?? []).length).toBe(2);
    expect(src).toContain("checkSeccompAgreement(");
  });
  it("no module outside agent-sandbox-seccomp.ts names the artifact filenames inline", () => {
    const lines = grep("bwrap-userns-clone3-(unix)?deny\\.bpf", ["server"]);
    const f = files(lines).filter((x) => !/\.test\./.test(x));
    expect(f).toEqual(["server/agent-sandbox-seccomp.ts", "server/c4-render.ts"]);
  });
});

void REPO_ROOT;
