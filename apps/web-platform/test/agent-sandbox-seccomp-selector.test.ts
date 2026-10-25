// #10455 (a): the per-session seccomp artifact selector (ADR-075 addendum 2026-10-19).
// Guard 3 rows 1, 8, 9: usesUnixDenyArtifact is the single predicate and seccompArtifactFor the single path resolver;
// buildAgentEnv sets SOLEUR_BWRAP_SECCOMP_BPF to the unixdeny artifact only for NO-EGRESS
// sessions while the runtime flag is ON; the flag defaults OFF and fails closed to OFF;
// every direct caller of the two builders is accounted for.
// Census residual (accepted, A6a): the spawn-site scan finds `query({` / `sdkQuery({` object literals. A site written as
// `sdkQuery(variable)`, where the variable carries its own `env`, is not caught.
// Wrapper note: both runners write `options: authProbe.bindOptions(buildAgentQueryOptions({...}))` (the cc factory with
// `recordCcSeccompArtifact(...)` between them). The identity wrapper keeps `buildAgentQueryOptions(` INSIDE the `query({...})`
// literal, which is what the `routed` scan below needs; extracting the options into a variable first would red it.
import { describe, it, expect, afterEach, beforeEach, vi } from "vitest";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const APP_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const REPO_ROOT = join(APP_ROOT, "..", "..");

// mirrorWarnWithDebounce is modelled with the real helper's contract (one emission per key:errorClass per window, then
// it calls warnSilentFallback), so "exactly one warning per window" is observable through warnSilentFallback.
const obsMock = vi.hoisted(() => {
  const claimed = new Set<string>();
  const warn = vi.fn();
  const debounce = vi.fn((err: unknown, ctx: unknown, key: string, errorClass: string) => {
    if (claimed.has(`${key}:${errorClass}`)) return;
    claimed.add(`${key}:${errorClass}`);
    warn(err, ctx);
  });
  return { claimed, warn, debounce };
});
vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
  warnSilentFallback: obsMock.warn,
  mirrorWarnWithDebounce: obsMock.debounce,
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
const UNIXDENY_OVERRIDE = "SOLEUR_BWRAP_SECCOMP_BPF_UNIXDENY";

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
  it("the canary's hand-copied variant path literal equals the server constant (a rename must update every copy)", () => {
    const canarySource = readFileSync(join(APP_ROOT, "scripts/sandbox-canary.mjs"), "utf8");
    expect(canarySource).toMatch(/const UNIXDENY_ARTIFACT_DEFAULT = "\/app\/infra\/bwrap-userns-clone3-unixdeny\.bpf";/);
    expect(canarySource).toContain(SECCOMP_UNIXDENY_ARTIFACT);
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
  const agreementWarnings = () =>
    vi.mocked(warnSilentFallback).mock.calls.filter((c) => (c[1] as { op?: string })?.op === "seccomp-agreement");
  let ambient: string | undefined;
  let ambientUnixdeny: string | undefined;
  beforeEach(() => {
    ambient = process.env[SEL];
    ambientUnixdeny = process.env[UNIXDENY_OVERRIDE];
    vi.mocked(warnSilentFallback).mockClear();
    obsMock.debounce.mockClear();
    obsMock.claimed.clear();
  });
  afterEach(() => {
    if (ambient === undefined) delete process.env[SEL];
    else process.env[SEL] = ambient;
    if (ambientUnixdeny === undefined) delete process.env[UNIXDENY_OVERRIDE];
    else process.env[UNIXDENY_OVERRIDE] = ambientUnixdeny;
  });

  it("an egress session with the ambient selector set to the unixdeny path ends on base, warns once, does not throw", () => {
    process.env[SEL] = unixdenyArtifactPath();
    let opts: Record<string, any> | undefined;
    expect(() => {
      opts = buildAgentQueryOptions({ ...args, ghToken: "ghs_x", sandboxUnixDeny: false });
    }).not.toThrow();
    expect(opts!.env?.[SEL]).toBe(SECCOMP_BASE_ARTIFACT);
    const calls = agreementWarnings();
    expect(calls.length).toBe(1);
    expect(calls[0][1]).toMatchObject({ feature: "agent-sandbox", op: "seccomp-agreement" });
    expect((calls[0][1] as { message: string }).message).toMatch(/artifact disagreement/i);
  });
  it("A3: the warning is debounced under the registered errorClass, so repeated queries inside the window emit once", () => {
    process.env[SEL] = unixdenyArtifactPath();
    for (let i = 0; i < 5; i++) buildAgentQueryOptions({ ...args, ghToken: "ghs_x", sandboxUnixDeny: false });
    expect(agreementWarnings().length).toBe(1);
    expect(obsMock.debounce).toHaveBeenCalledTimes(5);
    expect(obsMock.debounce.mock.calls[0]).toEqual([
      null,
      expect.objectContaining({ feature: "agent-sandbox", op: "seccomp-agreement" }),
      "global",
      "agent-sandbox-seccomp-agreement",
    ]);
    // ...but every query is still corrected, not only the first.
    expect(buildAgentQueryOptions({ ...args, ghToken: "ghs_x", sandboxUnixDeny: false }).env?.[SEL]).toBe(SECCOMP_BASE_ARTIFACT);
  });
  it("A3: both errorClass strings are listed in the observability registry comment", () => {
    const registry = readFileSync(join(APP_ROOT, "server/observability.ts"), "utf8");
    expect(registry).toContain("agent-sandbox-seccomp-agreement");
    expect(registry).toContain("agent-sandbox-unix-deny-unresolved");
  });
  it("a no-egress flag-OFF session with the ambient unixdeny selector is corrected to base too", () => {
    process.env[SEL] = unixdenyArtifactPath();
    const opts = buildAgentQueryOptions({ ...args, sandboxUnixDeny: false });
    expect(opts.env?.[SEL]).toBe(SECCOMP_BASE_ARTIFACT);
  });
  it("F4: an egress session (ghToken) with the flag ON and the ambient unixdeny selector still ends on base", () => {
    process.env[SEL] = unixdenyArtifactPath();
    const opts = buildAgentQueryOptions({ ...args, ghToken: "ghs_x", sandboxUnixDeny: true });
    expect(opts.env?.[SEL]).toBe(SECCOMP_BASE_ARTIFACT);
    expect(agreementWarnings().length).toBe(1);
  });
  it("never corrects in the other direction: a flag-ON no-egress session keeps the variant, with no warning", () => {
    delete process.env[SEL];
    const opts = buildAgentQueryOptions({ ...args, sandboxUnixDeny: true });
    expect(opts.env?.[SEL]).toBe(SECCOMP_UNIXDENY_ARTIFACT);
    expect(agreementWarnings().length).toBe(0);
  });
  it("an unrelated ambient override (not the unixdeny path) is left untouched", () => {
    process.env[SEL] = OVERRIDE;
    const opts = buildAgentQueryOptions({ ...args, ghToken: "ghs_x", sandboxUnixDeny: false });
    expect(opts.env?.[SEL]).toBe(OVERRIDE);
    expect(agreementWarnings().length).toBe(0);
  });

  describe("A5: the comparison is on resolved paths, not strings", () => {
    let dir: string;
    let artifact: string;
    beforeEach(() => {
      dir = mkdtempSync(join(tmpdir(), "seccomp-alias-"));
      artifact = join(dir, "unixdeny.bpf");
      writeFileSync(artifact, Buffer.alloc(160));
      process.env[UNIXDENY_OVERRIDE] = artifact;
    });
    afterEach(() => rmSync(dir, { recursive: true, force: true }));

    it("a symlink alias of the unixdeny artifact on an egress session is corrected to base and warned once", () => {
      const alias = join(dir, "alias.bpf");
      symlinkSync(artifact, alias);
      process.env[SEL] = alias;
      const opts = buildAgentQueryOptions({ ...args, ghToken: "ghs_x", sandboxUnixDeny: false });
      expect(opts.env?.[SEL]).toBe(SECCOMP_BASE_ARTIFACT);
      expect(agreementWarnings().length).toBe(1);
    });
    it("a `..` alias of the unixdeny artifact is recognised too", () => {
      // Built by concatenation: path.join would normalise the `..` away and the row would test nothing.
      mkdirSync(join(dir, "sub"));
      process.env[SEL] = `${dir}/sub/../unixdeny.bpf`;
      expect(process.env[SEL]).toContain("/sub/../");
      const opts = buildAgentQueryOptions({ ...args, ghToken: "ghs_x", sandboxUnixDeny: false });
      expect(opts.env?.[SEL]).toBe(SECCOMP_BASE_ARTIFACT);
      expect(agreementWarnings().length).toBe(1);
    });
    it("lexical fallback: when the unixdeny override does not exist (realpath throws) a `..` alias still compares equal", () => {
      // Neither path exists, so realpathSync throws for both and the lexically resolved paths are compared.
      process.env[UNIXDENY_OVERRIDE] = `${dir}/missing.bpf`;
      process.env[SEL] = `${dir}/sub/../missing.bpf`;
      expect(process.env[SEL]).toContain("/sub/../");
      const opts = buildAgentQueryOptions({ ...args, ghToken: "ghs_x", sandboxUnixDeny: false });
      expect(opts.env?.[SEL]).toBe(SECCOMP_BASE_ARTIFACT);
      expect(agreementWarnings().length).toBe(1);
      // control: a different missing file is not the variant
      process.env[SEL] = `${dir}/sub/../other-missing.bpf`;
      expect(buildAgentQueryOptions({ ...args, ghToken: "ghs_x", sandboxUnixDeny: false }).env?.[SEL]).toBe(
        `${dir}/sub/../other-missing.bpf`,
      );
    });
    it("checkSeccompAgreement itself reports the alias (the selector names the unixdeny file on an egress session)", () => {
      const alias = join(dir, "alias.bpf");
      symlinkSync(artifact, alias);
      const egressCfg = buildAgentSandboxConfig("/workspaces/w", { allowGithubEgress: true, sandboxUnixDeny: false });
      const env = buildAgentEnv(CRED, undefined, { ghToken: "ghs_x" });
      env[SEL] = alias;
      expect(checkSeccompAgreement(env, egressCfg)).toMatch(/artifact disagreement/i);
      // control: a different file in the same directory is a legitimate base override
      const other = join(dir, "other.bpf");
      writeFileSync(other, Buffer.alloc(160));
      env[SEL] = other;
      expect(checkSeccompAgreement(env, egressCfg)).toBeNull();
    });
    it("a flag-ON no-egress session whose selector is an alias of the variant is in agreement (no false alarm)", () => {
      const alias = join(dir, "alias.bpf");
      symlinkSync(artifact, alias);
      const cfg = buildAgentSandboxConfig("/workspaces/w", { sandboxUnixDeny: true });
      const env = buildAgentEnv(CRED, undefined, { sandboxUnixDeny: true });
      env[SEL] = alias;
      expect(checkSeccompAgreement(env, cfg)).toBeNull();
    });
  });
});

describe("A7: the per-dispatch sandbox-config log records which seccomp artifact the session is paired with", () => {
  const artifactOf = () => {
    const row = childLog.info.mock.calls.map((c) => c[0]).filter((o) => o?.op === "tenant-deny").at(-1);
    return row?.seccompArtifact;
  };
  beforeEach(() => childLog.info.mockClear());
  it("unixdeny for a no-egress flag-ON session; base for every other posture", () => {
    buildAgentSandboxConfig("/workspaces/w", { sandboxUnixDeny: true });
    expect(artifactOf()).toBe("unixdeny");
    buildAgentSandboxConfig("/workspaces/w", { sandboxUnixDeny: false });
    expect(artifactOf()).toBe("base");
    buildAgentSandboxConfig("/workspaces/w", { allowGithubEgress: true, sandboxUnixDeny: true });
    expect(artifactOf()).toBe("base");
    buildAgentSandboxConfig("/workspaces/w", { allowWebEgress: true, sandboxUnixDeny: true });
    expect(artifactOf()).toBe("base");
    buildAgentSandboxConfig("/workspaces/w");
    expect(artifactOf()).toBe("base");
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

// resolveSandboxUnixDeny (fail-closed, memo, single-flight, bound) is pinned by test/resolve-sandbox-unix-deny.test.ts, and its
// wiring into both runners by test/agent-runner-unix-deny-wire.test.ts and test/cc-dispatcher-real-factory.test.ts.

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
  it("buildAgentQueryOptions is called from the two runners and the dev probe", () => {
    const lines = grep("\\bbuildAgentQueryOptions\\(", ["server", "scripts"]);
    const f = files(lines).filter((x) => !/\.test\./.test(x));
    expect(f).toEqual(["scripts/dev-probe-destroy-ask.ts", "server/agent-runner.ts", "server/cc-dispatcher.ts"]);
    expect(f.length).toBe(3);
    // That both runners pass the RESOLVED flag is driven behaviourally (agent-runner-unix-deny-wire / cc-dispatcher-real-factory).
  });
  it("A6(a): the artifact filenames are named only by the known modules, across the whole app tree", () => {
    // server/ lib/ scripts/ app/ infra/ minus the generator (which defines them) and tests. Every consumer here either
    // is the single constant, a shell/JSON/MJS runtime that cannot import it (each pinned to the constant by its own
    // parity row), or a generated fixture.
    const lines = grep("bwrap-userns-clone3-(unix)?deny\\.bpf", ["server", "lib", "scripts", "app", "infra"]);
    const f = files(lines).filter((x) => !/\.test\./.test(x) && x !== "scripts/gen-bwrap-userns-seccomp.mjs");
    expect(f).toEqual([
      "infra/bwrap-shim/bwrap",
      "infra/c4-render-sandbox-argv.json",
      "infra/lib/sdk-bash-probe.mjs",
      "scripts/bwrap-userns-seccomp-probe.sh",
      "scripts/sandbox-canary.mjs",
      "server/agent-sandbox-seccomp.ts",
      "server/c4-render.ts",
    ]);
    expect(f.length).toBe(7); // floor: an empty grep must not pass
  });
});

// A6(a): the SDK `query()` spawn sites. A site that passes its OWN `env` (instead of the one buildAgentQueryOptions
// derives, which carries the per-session seccomp selector) could spawn a session on an artifact nobody checked, so each
// one must be either routed through the builder or listed here with a justification.
describe("SDK query() spawn-site census (A6a)", () => {
  const SPAWN_FILES = [
    "scripts/dev-probe-destroy-ask.ts",
    "scripts/plugin-root-sandbox-propagation-probe.mjs",
    "scripts/sandbox-canary.mjs",
    "scripts/spike/cache-control-forwarding.ts",
    "server/agent-runner.ts",
    "server/cc-dispatcher.ts",
    "server/pdf-chapter-router.ts",
  ];
  // Spawn sites that build their OWN env, each with the reason that is acceptable.
  const OWN_ENV_JUSTIFIED: Record<string, string> = {
    "scripts/plugin-root-sandbox-propagation-probe.mjs": "dev probe: env from buildAgentEnv (base artifact), no tenant, no egress",
  };

  // Balanced-brace extraction of the object literal that follows `name(`; strings are skipped.
  const literalAfter = (src: string, from: number): string => {
    let depth = 0;
    let i = src.indexOf("{", from);
    const begin = i;
    for (; i < src.length; i++) {
      const c = src[i];
      if (c === '"' || c === "'" || c === "`") {
        const q = c;
        for (i++; i < src.length && src[i] !== q; i++) if (src[i] === "\\") i++;
        continue;
      }
      if (c === "{") depth++;
      else if (c === "}" && --depth === 0) return src.slice(begin, i + 1);
    }
    throw new Error("unbalanced literal");
  };
  const stripComments = (t: string) => t.replace(/\/\*[\s\S]*?\*\//g, "").replace(/^\s*\/\/.*$/gm, "").replace(/(\s)\/\/[^\n]*$/gm, "$1");

  const sites = (() => {
    const out: Array<{ file: string; routed: boolean; ownEnv: boolean }> = [];
    const r = spawnSync("git", ["grep", "--untracked", "-lE", "@anthropic-ai/claude-agent-sdk", "--", "server", "lib", "scripts", "app"], {
      cwd: APP_ROOT,
      encoding: "utf8",
    });
    expect([0, 1]).toContain(r.status);
    for (const file of r.stdout.split("\n").filter(Boolean)) {
      if (/\.test\./.test(file) || /\.d\.ts$/.test(file)) continue;
      const src = stripComments(readFileSync(join(APP_ROOT, file), "utf8"));
      for (const m of src.matchAll(/(?<![\w.$])(?:query|sdkQuery)\(\s*\{/g)) {
        const lit = literalAfter(src, m.index!);
        const routed = /\bbuildAgentQueryOptions\(/.test(lit) || (/\.\.\.opts\b/.test(lit) && /\bbuildAgentQueryOptions\(/.test(src));
        // an `env` KEY of the options object (`env,` / `env:`), not a nested mention
        const ownEnv = /(^|[\s,{])env\s*[,:}]/.test(lit.replace(/\{[^{}]*\}/g, (x) => (/\benv\b/.test(x) ? x : "")));
        out.push({ file, routed, ownEnv });
      }
    }
    return out;
  })();

  it("the spawn sites are exactly the known files (floor: an empty scan must not pass)", () => {
    expect([...new Set(sites.map((x) => x.file))].sort()).toEqual(SPAWN_FILES);
    expect(sites.length).toBeGreaterThanOrEqual(SPAWN_FILES.length);
  });
  it("the production runners build their options through buildAgentQueryOptions and pass no env of their own", () => {
    for (const file of ["server/agent-runner.ts", "server/cc-dispatcher.ts", "scripts/dev-probe-destroy-ask.ts"]) {
      const mine = sites.filter((x) => x.file === file);
      expect(mine.length, file).toBeGreaterThanOrEqual(1);
      for (const x of mine) {
        expect(x.routed, `${file} builds its options through buildAgentQueryOptions`).toBe(true);
        expect(x.ownEnv, `${file} must not pass an env of its own`).toBe(false);
      }
    }
  });
  it("every site that passes its OWN env is listed with a justification (an unlisted one reds)", () => {
    const own = [...new Set(sites.filter((x) => x.ownEnv).map((x) => x.file))].sort();
    expect(own).toEqual(Object.keys(OWN_ENV_JUSTIFIED).sort());
  });
});

void REPO_ROOT;
