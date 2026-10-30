// #10455 (b): the resolver CLI the runtime Bash synthetic execs in the RUNNING container. A cold one-shot process routinely loses the
// dispatcher's 300 ms race and falls back to the env mirror; the CLI must say `unresolved` then (the synthetic skips the run), never
// print a guessed `base` that pings green for an artifact production may not be using.
import { execFileSync } from "node:child_process";
import { existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

const mockGetIdentityFlags = vi.fn();
vi.mock("flagsmith-nodejs", () => ({
  Flagsmith: vi.fn().mockImplementation(function (this: Record<string, unknown>) {
    this.getIdentityFlags = mockGetIdentityFlags;
  }),
}));
vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
  mirrorWarnWithDebounce: vi.fn(),
}));

import { CLI_RESOLVE_BUDGET_MS, selectorSentinel } from "@/server/resolve-sandbox-selector";
import { __resetFeatureFlagsForTests, readAgentSandboxUnixDenyDetailed } from "@/lib/feature-flags/server";

const APP_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const ORIGINAL_ENV = process.env;

beforeEach(() => {
  process.env = { ...ORIGINAL_ENV };
  delete process.env.FLAG_AGENT_SANDBOX_UNIX_DENY;
  delete process.env.FLAGSMITH_ENVIRONMENT_KEY;
  mockGetIdentityFlags.mockReset();
  __resetFeatureFlagsForTests();
});
afterEach(() => {
  process.env = ORIGINAL_ENV;
  vi.useRealTimers();
});

describe("readAgentSandboxUnixDenyDetailed", () => {
  it("Flagsmith answered ON / OFF: the value, not a fallback", async () => {
    process.env.FLAGSMITH_ENVIRONMENT_KEY = "ser.test-key";
    mockGetIdentityFlags.mockResolvedValue({ isFeatureEnabled: (n: string) => n === "agent-sandbox-unix-deny" });
    await expect(readAgentSandboxUnixDenyDetailed()).resolves.toEqual({ value: true, fellBack: false });
    __resetFeatureFlagsForTests();
    mockGetIdentityFlags.mockResolvedValue({ isFeatureEnabled: () => false });
    await expect(readAgentSandboxUnixDenyDetailed()).resolves.toEqual({ value: false, fellBack: false });
  });

  it("Flagsmith did not answer: the env mirror's value is reported WITH fellBack=true (the mirror can be ON)", async () => {
    process.env.FLAGSMITH_ENVIRONMENT_KEY = "ser.test-key";
    process.env.FLAG_AGENT_SANDBOX_UNIX_DENY = "1";
    mockGetIdentityFlags.mockRejectedValue(new Error("timeout"));
    await expect(readAgentSandboxUnixDenyDetailed()).resolves.toEqual({ value: true, fellBack: true });
  });

  it("no Flagsmith key at all is a fallback too", async () => {
    await expect(readAgentSandboxUnixDenyDetailed()).resolves.toEqual({ value: false, fellBack: true });
  });
});

describe("selectorSentinel", () => {
  it("maps an ANSWERED read to the artifact name", async () => {
    await expect(selectorSentinel(async () => ({ value: true, fellBack: false }))).resolves.toBe("unixdeny");
    await expect(selectorSentinel(async () => ({ value: false, fellBack: false }))).resolves.toBe("base");
  });

  it("a fallback read is `unresolved` whatever value the mirror gave", async () => {
    await expect(selectorSentinel(async () => ({ value: true, fellBack: true }))).resolves.toBe("unresolved");
    await expect(selectorSentinel(async () => ({ value: false, fellBack: true }))).resolves.toBe("unresolved");
  });

  it("a throw is `unresolved`", async () => {
    await expect(selectorSentinel(async () => { throw new Error("boom"); })).resolves.toBe("unresolved");
  });

  it("losing the race is `unresolved`, and the budget is the 3 s cold-read budget (not the dispatcher's 300 ms)", async () => {
    expect(CLI_RESOLVE_BUDGET_MS).toBe(3000);
    vi.useFakeTimers();
    const p = selectorSentinel(() => new Promise(() => {}));
    await vi.advanceTimersByTimeAsync(299);
    let settled = false;
    void p.then(() => { settled = true; });
    await vi.advanceTimersByTimeAsync(1);
    expect(settled, "a 300 ms budget would have settled here").toBe(false);
    await vi.advanceTimersByTimeAsync(CLI_RESOLVE_BUDGET_MS);
    await expect(p).resolves.toBe("unresolved");
  });
});

describe("the CLI bundle (Dockerfile builder step) and its consumers", () => {
  const dockerfile = readFileSync(join(APP_ROOT, "Dockerfile"), "utf8");
  const esbuildLine = dockerfile.split("\n").find((l) => l.startsWith("RUN ./node_modules/.bin/esbuild server/resolve-sandbox-selector-cli.ts "));

  it("the Dockerfile bundles the CLI to infra/lib/resolve-sandbox-selector.mjs and the runner COPYs exactly that path", () => {
    expect(esbuildLine, "builder-stage esbuild line for the resolver CLI").toBeDefined();
    expect(esbuildLine).toContain("--outfile=infra/lib/resolve-sandbox-selector.mjs");
    expect(dockerfile).toContain(
      "COPY --from=builder /app/infra/lib/resolve-sandbox-selector.mjs ./infra/lib/resolve-sandbox-selector.mjs",
    );
  });

  it("web-bash-synthetic.sh execs the path the image carries, and greps the three sentinels the CLI prints", () => {
    const sh = readFileSync(join(APP_ROOT, "infra", "web-bash-synthetic.sh"), "utf8");
    expect(sh).toContain('RESOLVER_PATH="/app/infra/lib/resolve-sandbox-selector.mjs"');
    expect(sh).toContain("SOLEUR_SELECTOR=(base|unixdeny|unresolved)");
    const cli = readFileSync(join(APP_ROOT, "server", "resolve-sandbox-selector-cli.ts"), "utf8");
    expect(cli).toContain("`SOLEUR_SELECTOR=${await selectorSentinel()}\\n`");
  });

  it("the bundle built with the Dockerfile's own esbuild line runs under plain node and prints ONE `unresolved` sentinel with no Flagsmith key", () => {
    const outDir = mkdtempSync((() => { const d = join(APP_ROOT, "node_modules", ".cache"); mkdirSync(d, { recursive: true }); return join(d, "selector-cli-"); })());
    try {
      const out = join(outDir, "resolve-sandbox-selector.mjs");
      const args = esbuildLine!
        .replace("RUN ./node_modules/.bin/esbuild ", "")
        .split(" ")
        .map((a) => (a.startsWith("--outfile=") ? `--outfile=${out}` : a));
      execFileSync(join(APP_ROOT, "node_modules", ".bin", "esbuild"), args, { cwd: APP_ROOT, stdio: "pipe" });
      expect(existsSync(out)).toBe(true);
      const stdout = execFileSync(process.execPath, [out], { cwd: APP_ROOT, env: { PATH: process.env.PATH ?? "", NODE_ENV: "production" }, encoding: "utf8", timeout: 20000 });
      expect(stdout.split("\n").filter((l) => l.startsWith("SOLEUR_SELECTOR="))).toEqual(["SOLEUR_SELECTOR=unresolved"]);
    } finally {
      rmSync(outDir, { recursive: true, force: true });
    }
  }, 60000);
});
