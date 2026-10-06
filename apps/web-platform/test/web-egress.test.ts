// feat-open-web-egress (#9534) — the dispatch-side egress wiring:
//   - buildAgentEnv egressProxy → credentialed per-session proxy URL +
//     NO_PROXY control-plane list, overriding the ambient allowlist copy.
//   - buildAgentSandboxConfig allowWebEgress → credentials.envVars deny
//     census + credential-file/token-dir denyRead (Phase-A quarantine).
//   - egress-forwarder module — real spawn against the baked
//     infra/egress-forwarder.mjs: token-file write, loopback bind, inbound
//     token auth (407 without it), teardown, orphan reaper.

import {
  mkdtempSync,
  mkdirSync,
  rmSync,
  existsSync,
  writeFileSync,
} from "fs";
import { tmpdir } from "os";
import { join } from "path";
import net from "node:net";

import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

vi.mock("@sentry/nextjs", () => ({ captureException: vi.fn() }));

import { buildAgentEnv } from "@/server/agent-env";
import { buildAgentSandboxConfig } from "@/server/agent-runner-sandbox-config";
import {
  spawnEgressForwarder,
  teardownEgressForwarder,
  hasEgressForwarder,
  reapOrphanEgressForwarders,
} from "@/server/egress-forwarder";

const CREDENTIAL = { value: "sk-test", scheme: "api_key" as const };
const EGRESS = { workspaceId: "ws-123", token: "tok-abc", port: 28711 };

// ---------------------------------------------------------------------------
// buildAgentEnv — egress proxy env
// ---------------------------------------------------------------------------

describe("buildAgentEnv — egressProxy (#9534)", () => {
  afterEach(() => {
    vi.unstubAllEnvs();
  });

  it("injects the credentialed proxy URL into HTTP(S)_PROXY (both cases) + NO_PROXY", () => {
    const env = buildAgentEnv(CREDENTIAL, {}, { egressProxy: EGRESS });
    const url = "http://ws-123:tok-abc@127.0.0.1:28711";
    for (const k of ["HTTP_PROXY", "HTTPS_PROXY", "http_proxy", "https_proxy"]) {
      expect(env[k]).toBe(url);
    }
    for (const k of ["NO_PROXY", "no_proxy"]) {
      expect(env[k]).toContain("api.anthropic.com");
      expect(env[k]).toContain("localhost");
    }
  });

  it("overrides an ambient HTTP_PROXY from the allowlist copy", () => {
    vi.stubEnv("HTTP_PROXY", "http://ambient:9999");
    const env = buildAgentEnv(CREDENTIAL, {}, { egressProxy: EGRESS });
    expect(env.HTTP_PROXY).toBe("http://ws-123:tok-abc@127.0.0.1:28711");
  });

  it("absent egressProxy → ambient proxy vars pass through unchanged (non-entitled parity)", () => {
    vi.stubEnv("HTTP_PROXY", "http://ambient:9999");
    const env = buildAgentEnv(CREDENTIAL, {});
    expect(env.HTTP_PROXY).toBe("http://ambient:9999");
  });

  it("absent egressProxy AND no ambient → no proxy keys at all", () => {
    const env = buildAgentEnv(CREDENTIAL, {});
    expect(env.HTTP_PROXY).toBeUndefined();
    expect(env.http_proxy).toBeUndefined();
  });
});

// ---------------------------------------------------------------------------
// buildAgentSandboxConfig — allowWebEgress quarantine
// ---------------------------------------------------------------------------

describe("buildAgentSandboxConfig — allowWebEgress (#9534)", () => {
  let root: string;
  let own: string;

  beforeEach(() => {
    root = mkdtempSync(join(tmpdir(), "egress-sbx-"));
    own = join(root, "00000000-0000-0000-0000-000000000001");
    mkdirSync(own);
    vi.stubEnv("WORKSPACES_ROOT", root);
    vi.stubEnv("C4_RENDER_STAGING_ROOT", `${root}-c4-staging`);
    vi.stubEnv("EGRESS_TOKEN_DIR", `${root}-tokens`);
  });

  afterEach(() => {
    vi.unstubAllEnvs();
    rmSync(root, { recursive: true, force: true });
    rmSync(`${root}-c4-staging`, { recursive: true, force: true });
  });

  it("emits the credentials.envVars deny census — fixed secrets + BYOK census", () => {
    const cfg = buildAgentSandboxConfig(own, { allowWebEgress: true });
    const envVars = (cfg as { credentials?: { envVars: { name: string; mode: string }[] } })
      .credentials!.envVars;
    const names = envVars.map((e) => e.name);
    // Fixed credential-bearing names.
    for (const n of [
      "GH_TOKEN",
      "GIT_ASKPASS",
      "GIT_INSTALLATION_TOKEN",
      "GIT_USERNAME",
      "GIT_TERMINAL_PROMPT",
      "ANTHROPIC_API_KEY",
      "CLAUDE_CODE_OAUTH_TOKEN",
    ]) {
      expect(names).toContain(n);
    }
    // BYOK service-token census (ALLOWED_SERVICE_ENV_VARS — the real set).
    for (const n of ["STRIPE_SECRET_KEY", "GITHUB_TOKEN", "DOPPLER_TOKEN"]) {
      expect(names).toContain(n);
    }
    // GIT_CONFIG_* are /dev/null neutralizations — denied would UNDO them
    // (plan review correction (a)).
    expect(names).not.toContain("GIT_CONFIG_NOSYSTEM");
    expect(names).not.toContain("GIT_CONFIG_GLOBAL");
    // Every entry is `deny` — no `mask` (masking would re-inject at the
    // SRT proxy for allowlisted hosts).
    expect(envVars.every((e) => e.mode === "deny")).toBe(true);
    // Deduped.
    expect(new Set(names).size).toBe(names.length);
  });

  it("denyRead gains the token-dir + credential-file paths", () => {
    const cfg = buildAgentSandboxConfig(own, { allowWebEgress: true });
    const denyRead = cfg.filesystem!.denyRead;
    expect(denyRead).toContain(`${root}-tokens`);
    const home = process.env.HOME ?? "/root";
    expect(denyRead).toContain(join(home, ".ssh"));
    expect(denyRead).toContain(join(home, ".config", "gh"));
    expect(denyRead).toContain(join(home, ".claude", ".credentials.json"));
  });

  it("non-entitled session: credentials carries ONLY the W1 auth-var baseline, token dir NOT denied", () => {
    const cfg = buildAgentSandboxConfig(own);
    // W1 (#9601): every session denies the two Anthropic auth vars to
    // sandboxed Bash — the block is always present. The egress census (service
    // tokens, GH_*/GIT_* auth vars) is the entitlement-scoped widening.
    const names = (
      cfg as { credentials: { envVars: { name: string }[] } }
    ).credentials.envVars.map((e) => e.name);
    expect(new Set(names)).toEqual(
      new Set(["ANTHROPIC_API_KEY", "CLAUDE_CODE_OAUTH_TOKEN"]),
    );
    expect(cfg.filesystem!.denyRead).not.toContain(`${root}-tokens`);
  });
});

// ---------------------------------------------------------------------------
// egress-forwarder — real process lifecycle (spawn, inbound auth, teardown)
// ---------------------------------------------------------------------------

/** One-shot raw CONNECT helper — writes the request head, returns the first
 *  response bytes (or "" if the peer closed silently). */
function connectRaw(port: number, head: string): Promise<string> {
  return new Promise((resolve, reject) => {
    const sock = net.connect(port, "127.0.0.1", () => sock.write(head));
    const chunks: Buffer[] = [];
    sock.on("data", (d) => chunks.push(d));
    sock.on("close", () => resolve(Buffer.concat(chunks).toString("latin1")));
    sock.on("error", reject);
    setTimeout(() => {
      sock.destroy();
      resolve(Buffer.concat(chunks).toString("latin1"));
    }, 2000);
  });
}

describe("egress-forwarder lifecycle (#9534)", () => {
  let tokenDir: string;
  const FORWARDER = join(
    __dirname,
    "..",
    "infra",
    "egress-forwarder.mjs",
  );

  beforeEach(() => {
    tokenDir = mkdtempSync(join(tmpdir(), "egress-tokens-"));
    vi.stubEnv("EGRESS_TOKEN_DIR", tokenDir);
    vi.stubEnv("EGRESS_FORWARDER_PATH", FORWARDER);
    // The forwarder needs SOME gateway to dial — it only connects on a
    // client CONNECT, so an unroutable dummy is fine for lifecycle tests.
    vi.stubEnv("EGRESS_GW_HOST", "127.0.0.1");
    vi.stubEnv("EGRESS_GW_PORT", "1");
  });

  afterEach(async () => {
    teardownEgressForwarder("conv-1");
    vi.unstubAllEnvs();
    // The forwarder writes the token file; teardown removes it, but the
    // dir itself is test-owned.
    rmSync(tokenDir, { recursive: true, force: true });
  });

  it("spawn mints a token file + returns a live bound port; teardown kills it", async () => {
    const h = await spawnEgressForwarder("conv-1", "ws-123");
    expect(h.port).toBeGreaterThan(0);
    expect(existsSync(join(tokenDir, h.token))).toBe(true);
    expect(hasEgressForwarder("conv-1")).toBe(true);

    teardownEgressForwarder("conv-1");
    expect(hasEgressForwarder("conv-1")).toBe(false);
    expect(existsSync(join(tokenDir, h.token))).toBe(false);
    // Listener is dead — a fresh connect is refused.
    await expect(
      connectRaw(h.port, "CONNECT x:443 HTTP/1.1\r\n\r\n"),
    ).rejects.toThrow();
  }, 15000);

  it("inbound auth: no/wrong token → 407; correct token passes the auth gate", async () => {
    const h = await spawnEgressForwarder("conv-1", "ws-123");
    // No Proxy-Authorization → 407.
    const noAuth = await connectRaw(
      h.port,
      "CONNECT example.com:443 HTTP/1.1\r\nHost: example.com:443\r\n\r\n",
    );
    expect(noAuth).toContain("407");
    // Wrong token → 407.
    const wrong = await connectRaw(
      h.port,
      `CONNECT example.com:443 HTTP/1.1\r\nProxy-Authorization: Basic ${Buffer.from("u:not-the-token").toString("base64")}\r\n\r\n`,
    );
    expect(wrong).toContain("407");
    // Correct token → NOT a 407 (the gateway is unroutable here, so the
    // tunnel dies after the auth gate — a silent close, never a 407).
    const ok = await connectRaw(
      h.port,
      `CONNECT example.com:443 HTTP/1.1\r\nProxy-Authorization: Basic ${Buffer.from(`ws-123:${h.token}`).toString("base64")}\r\n\r\n`,
    );
    expect(ok).not.toContain("407");
  }, 15000);

  it("reaper removes stale token files (registry-empty boundary)", async () => {
    writeFileSync(join(tokenDir, "stale-token-1"), "ws-x\n");
    writeFileSync(join(tokenDir, "stale-token-2"), "ws-y\n");
    reapOrphanEgressForwarders();
    expect(existsSync(join(tokenDir, "stale-token-1"))).toBe(false);
    expect(existsSync(join(tokenDir, "stale-token-2"))).toBe(false);
  });

  it("spawn failure (missing forwarder script) throws + cleans up the token file", async () => {
    vi.stubEnv("EGRESS_FORWARDER_PATH", "/nonexistent/egress-forwarder.mjs");
    await expect(spawnEgressForwarder("conv-1", "ws-123")).rejects.toThrow();
    expect(hasEgressForwarder("conv-1")).toBe(false);
    // Token file must not linger — a stray file is a live gateway credential.
    const { readdirSync } = await import("fs");
    expect(readdirSync(tokenDir)).toEqual([]);
  }, 15000);
});
