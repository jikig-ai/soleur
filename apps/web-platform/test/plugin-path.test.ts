// Tests for `plugin-path.ts` — the canonical plugin-mount resolution + the
// loaded-gun trust guard (fix-plugin-shadow-deployed-load, Slice A / AC7b + AC12b).
//
// Two guarantees under test:
//   1. `assertTrustedPluginPath` — the "loaded gun" guard. Both SDK factories now
//      load `plugins:[{ path: getPluginPath() }]` (an absolute `/app/` path). A
//      future dev who wires a workspace-relative path into that binding must fail
//      LOUDLY, not silently reopen the connected-repo-shadow hole. Test-tolerant:
//      it mirrors getPluginPath()'s VITEST/NODE_ENV=test bypass (fixtures use
//      mkdtemp `/tmp` paths).
//   2. `getPluginPath` — AC12b (F4): a non-`/app/` SOLEUR_PLUGIN_PATH override in
//      PRODUCTION falls back to the default (the `/app/` prefix guard holds); this
//      fix adds no new production exposure.
import { afterEach, describe, expect, it, vi } from "vitest";
import {
  SOLEUR_PLUGIN_PATH_DEFAULT,
  assertTrustedPluginPath,
  getPluginPath,
} from "../server/plugin-path";

afterEach(() => {
  vi.unstubAllEnvs();
});

// Force the production branch of the env-guarded logic. `vi.unstubAllEnvs()` in
// afterEach reverts these; the ambient VITEST/NODE_ENV are restored after.
function stubProductionEnv(): void {
  vi.stubEnv("VITEST", "");
  vi.stubEnv("NODE_ENV", "production");
}

describe("assertTrustedPluginPath (loaded-gun guard)", () => {
  it("returns an absolute /app/ path unchanged in production", () => {
    stubProductionEnv();
    expect(assertTrustedPluginPath("/app/shared/plugins/soleur")).toBe("/app/shared/plugins/soleur");
    // Broader /app/ prefix (ops repointing) is allowed, mirroring ALLOWED_PREFIXES.
    expect(assertTrustedPluginPath("/app/green/plugins/soleur")).toBe("/app/green/plugins/soleur");
  });

  it("throws LOUDLY on a workspace-relative path in production (the reopened-hole guard)", () => {
    stubProductionEnv();
    // The exact shape a naive "wire up the ignored pluginPath arg" regression emits.
    expect(() => assertTrustedPluginPath("/workspaces/abc123/plugins/soleur")).toThrow(/plugin path/i);
    expect(() => assertTrustedPluginPath("plugins/soleur")).toThrow(/plugin path/i);
    expect(() => assertTrustedPluginPath("/tmp/evil/plugins/soleur")).toThrow(/plugin path/i);
    // Normalization guard: a non-canonical path that lexically starts with /app/
    // but resolves OUTSIDE it must still throw (path.resolve collapses the `..`).
    expect(() => assertTrustedPluginPath("/app/../workspaces/x/plugins/soleur")).toThrow(/plugin path/i);
  });

  it("is test-tolerant: under VITEST any path passes (fixtures use mkdtemp roots)", () => {
    // Ambient VITEST is set in this runner — no stubbing needed.
    expect(assertTrustedPluginPath("/tmp/ctxq-fix-xyz/plugins/soleur")).toBe("/tmp/ctxq-fix-xyz/plugins/soleur");
    expect(assertTrustedPluginPath("/var/folders/whatever/plugins/soleur")).toBe("/var/folders/whatever/plugins/soleur");
  });

  it("is test-tolerant via NODE_ENV=test as well", () => {
    vi.stubEnv("VITEST", "");
    vi.stubEnv("NODE_ENV", "test");
    expect(assertTrustedPluginPath("/anywhere/plugins/soleur")).toBe("/anywhere/plugins/soleur");
  });
});

describe("getPluginPath (AC12b / F4 — no new production exposure)", () => {
  it("falls back to the default for a non-/app override in production", () => {
    stubProductionEnv();
    vi.stubEnv("SOLEUR_PLUGIN_PATH", "/tmp/attacker/plugins/soleur");
    expect(getPluginPath()).toBe(SOLEUR_PLUGIN_PATH_DEFAULT);
  });

  it("accepts an /app override in production", () => {
    stubProductionEnv();
    vi.stubEnv("SOLEUR_PLUGIN_PATH", "/app/green/plugins/soleur");
    expect(getPluginPath()).toBe("/app/green/plugins/soleur");
  });

  it("returns the default when no override is set in production", () => {
    stubProductionEnv();
    vi.stubEnv("SOLEUR_PLUGIN_PATH", "");
    expect(getPluginPath()).toBe(SOLEUR_PLUGIN_PATH_DEFAULT);
  });
});
