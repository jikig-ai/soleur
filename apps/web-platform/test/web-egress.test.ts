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
  readFileSync,
  rmSync,
  existsSync,
  writeFileSync,
  statSync,
  utimesSync,
} from "fs";
import { tmpdir } from "os";
import { join } from "path";
import net from "node:net";

import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

vi.mock("@sentry/nextjs", () => ({ captureException: vi.fn() }));
import * as SentryMock from "@sentry/nextjs";

import { buildAgentEnv } from "@/server/agent-env";
import { buildAgentSandboxConfig } from "@/server/agent-runner-sandbox-config";
import {
  withoutTokenPath,
  egressGwTarget,
  writeTokenFile,
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

  it("absent egressProxy → ambient proxy vars are NOT copied (default-deny)", () => {
    // Structural-enum A8: ambient proxy env on the dispatcher must never
    // steer an unentitled session — the allowlist no longer carries the
    // proxy keys, so there is nothing to "pass through".
    vi.stubEnv("HTTP_PROXY", "http://ambient:9999");
    const env = buildAgentEnv(CREDENTIAL, {});
    expect(env.HTTP_PROXY).toBeUndefined();
  });

  it("absent egressProxy AND no ambient → no proxy keys at all", () => {
    const env = buildAgentEnv(CREDENTIAL, {});
    expect(env.HTTP_PROXY).toBeUndefined();
    expect(env.http_proxy).toBeUndefined();
  });

  it("NO_PROXY enumerates the full control-plane set (hard requirement, spec TR7)", () => {
    const env = buildAgentEnv(CREDENTIAL, {}, { egressProxy: EGRESS });
    for (const host of [
      "api.anthropic.com",
      "mcp-proxy.anthropic.com",
      "statsig.anthropic.com",
      "*.sentry.io",
      "*.datadoghq.com",
      "*.supabase.co",
      "*.supabase.in",
      "api.stripe.com",
      "github.com",
      "*.github.com",
      "localhost",
      "127.0.0.1",
      "::1",
    ]) {
      expect(env.NO_PROXY).toContain(host);
    }
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
    // The shared token dir is denied for EVERY session — it holds other
    // sessions' live bearer files (existence = the gateway credential).
    expect(cfg.filesystem!.denyRead).toContain(`${root}-tokens`);
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
  let gwServer: ReturnType<typeof net.createServer>;
  let gwPort: number;
  /** First head-bytes a client delivered upstream through the forwarder. */
  let gwReceived: Buffer;
  const FORWARDER = join(
    __dirname,
    "..",
    "infra",
    "egress-forwarder.mjs",
  );

  beforeEach(async () => {
    tokenDir = mkdtempSync(join(tmpdir(), "egress-tokens-"));
    vi.stubEnv("EGRESS_TOKEN_DIR", tokenDir);
    vi.stubEnv("EGRESS_FORWARDER_PATH", FORWARDER);
    // The spawn-time liveness probe requires a REAL listening gateway —
    // bind a loopback recorder that captures what each CONNECT forwards.
    gwReceived = Buffer.alloc(0);
    gwServer = net.createServer((sock) => {
      let head = Buffer.alloc(0);
      let done = false;
      sock.on("data", (d) => {
        if (done) return;
        head = Buffer.concat([head, d]);
        // Capture through the header terminator — a segmented head must not
        // partial-read green (or red-flake); data past it is tunnel payload.
        const end = head.indexOf("\r\n\r\n");
        if (end !== -1) {
          done = true;
          gwReceived = head.subarray(0, end + 4);
        }
      });
      // Never answer — lifecycle tests only need the dial to succeed; the
      // byte-exact test reads gwReceived instead of a 200 reply.
    });
    await new Promise<void>((r) => gwServer.listen(0, "127.0.0.1", r));
    gwPort = (gwServer.address() as { port: number }).port;
    vi.stubEnv("EGRESS_GW_HOST", "127.0.0.1");
    vi.stubEnv("EGRESS_GW_PORT", String(gwPort));
  });

  afterEach(async () => {
    teardownEgressForwarder("conv-1");
    await new Promise<void>((r) => gwServer.close(() => r()));
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

  it("upstream head is byte-exact: one Proxy-Authorization (ours), single blank terminator, zero stray bytes", async () => {
    const h = await spawnEgressForwarder("conv-1", "ws-123");
    const creds = Buffer.from(`ws-123:${h.token}`).toString("base64");
    // A duplicate inbound header must ALSO be stripped — the filter removes
    // every Proxy-Authorization line, not the first.
    await connectRaw(
      h.port,
      `CONNECT example.com:443 HTTP/1.1\r\nHost: example.com:443\r\nProxy-Authorization: Basic ${creds}\r\nProxy-Authorization: Basic dGVzdA==\r\nX-Custom: keep\r\n\r\n`,
    );
    // The gateway sees exactly: CONNECT + remaining headers (the inbound
    // Proxy-Authorization stripped, ours re-injected — identical bytes here,
    // so the distinct assertion is the COUNT) + a single blank terminator,
    // then NOTHING. A stray delimiter byte before the TLS ClientHello is the
    // review-P0 framing defect this pins.
    const text = gwReceived.toString("latin1");
    expect(text.startsWith("CONNECT example.com:443 HTTP/1.1\r\n")).toBe(true);
    expect((text.match(/Proxy-Authorization:/g) ?? []).length).toBe(1);
    const injected = `Proxy-Authorization: Basic ${creds}\r\n`;
    expect(text.endsWith(`${injected}\r\n`)).toBe(true);
    expect(text).toContain("X-Custom: keep");
    // Pre-fix this ended `\r\n\r\n\r\n` — the delimiter was re-emitted
    // inside the tunnel stream.
    expect(text).not.toContain("\r\n\r\n\r\n");
  }, 15000);

  it("token file is world-readable (0644): the gateway's auth helper runs as the squid `proxy` uid and READS the file", async () => {
    // Measured against the pinned ubuntu/squid image: the helper (uid 13) gets
    // `Permission denied` on a 0600 uid-1001 file, so every session token would be
    // rejected even with the dir mounted. Content is only the workspace id; the 0711
    // dir (and the unguessable 192-bit name) keep it unlistable to other host uids.
    const h = await spawnEgressForwarder("conv-1", "ws-123");
    expect(statSync(join(tokenDir, h.token)).mode & 0o777).toBe(0o644);
  }, 15000);

  it("writeTokenFile chmods explicitly: a restrictive pre-existing/umask-narrowed mode is widened to 0644", () => {
    // writeFileSync's `mode` only applies on CREATE (and is masked by the umask), so a
    // 0600 file already on disk stays 0600 unless the code chmods. Deleting the chmod reds this.
    const p = join(tokenDir, "pre-existing-0600");
    writeFileSync(p, "old\n", { mode: 0o600 });
    writeTokenFile(p, "ws-9");
    expect(statSync(p).mode & 0o777).toBe(0o644);
    expect(readFileSync(p, "utf8")).toBe("ws-9\n");
  });

  it("writeTokenFile leaves NO file behind when the write fails (the name is a live credential)", () => {
    const p = join(tokenDir, "no-such-subdir", "tok");
    expect(() => writeTokenFile(p, "ws-9")).toThrow();
    expect(existsSync(p)).toBe(false);
  });

  it("the exported spawn entry point scrubs token paths at the boundary (source-level wire check)", () => {
    // Every throw out of spawnEgressForwarder reaches cc-dispatcher's reportSilentFallback raw;
    // the scrub must sit at the public entry point, not only at three inner report sites.
    const src = readFileSync(join(__dirname, "..", "server", "egress-forwarder.ts"), "utf8")
      .split("\n")
      .filter((l) => !/^\s*(\/\/|\*|\/\*)/.test(l))
      .join("\n");
    expect(src).toMatch(
      /export async function spawnEgressForwarder\([^)]*\)[^{]*\{[\s\S]{0,400}catch \(err\)[\s\S]{0,80}throw withoutTokenPath\(err\)/,
    );
  });

  describe("withoutTokenPath", () => {
    const TOK = "SECRETSECRETSECRETSECRET1234";
    it.each([
      { label: "plain dir", dir: "/var/lib/soleur/egress-tokens" },
      { label: "dir with a trailing slash", dir: "/var/lib/soleur/egress-tokens/" },
      { label: "dir with regex metacharacters", dir: "/var/lib/soleur+x(1)/egress-tokens" },
    ])("removes the token name from message, stack and path ($label)", ({ dir }) => {
      vi.stubEnv("EGRESS_TOKEN_DIR", dir);
      const norm = dir.replace(/\/+$/, "");
      const e = Object.assign(
        new Error(`EISDIR: illegal operation on a directory, rm '${norm}/${TOK}'`),
        { code: "EISDIR", syscall: "rm", path: `${norm}/${TOK}` },
      );
      const out = withoutTokenPath(e) as NodeJS.ErrnoException;
      expect(out).toBeInstanceOf(Error);
      expect(out.code).toBe("EISDIR");
      expect(out.message).toContain("<token-dir>");
      const everything = `${out.message}\n${out.stack ?? ""}\n${JSON.stringify(out, Object.getOwnPropertyNames(out))}`;
      expect(everything).not.toContain(TOK);
    });

    it("returns the ORIGINAL error (stack intact) when there is nothing to scrub, and non-Errors unchanged", () => {
      vi.stubEnv("EGRESS_TOKEN_DIR", "/var/lib/soleur/egress-tokens");
      const e = new Error("egress gateway unreachable at 172.31.100.2:8443");
      expect(withoutTokenPath(e)).toBe(e);
      expect(withoutTokenPath("str")).toBe("str");
      expect(withoutTokenPath(undefined)).toBe(undefined);
    });
  });

  it.each(["teardown", "reap", "exit"] as const)(
    "a failing token-file delete is reported WITHOUT the token file name (%s path)",
    async (site) => {
      // rmSync(<non-empty dir>, {force:true}) throws EISDIR with the full path in its message.
      const h = await spawnEgressForwarder("conv-1", "ws-123");
      const tokPath = join(tokenDir, h.token);
      rmSync(tokPath, { force: true });
      mkdirSync(tokPath);
      writeFileSync(join(tokPath, "x"), "x");
      vi.mocked(SentryMock.captureException).mockClear();
      if (site === "teardown") {
        teardownEgressForwarder("conv-1");
      } else if (site === "reap") {
        // drop the registry entry first (the live registry would protect this token), then
        // sweep the leftover directory that is named like a token.
        teardownEgressForwarder("conv-1");
        vi.mocked(SentryMock.captureException).mockClear();
        mkdirSync(tokPath, { recursive: true });
        writeFileSync(join(tokPath, "x"), "x");
        reapOrphanEgressForwarders();
      } else {
        process.kill(h.pid, "SIGKILL"); // the registered exit handler then deletes the token file
        for (let i = 0; i < 40 && vi.mocked(SentryMock.captureException).mock.calls.length === 0; i++) {
          await new Promise((r) => setTimeout(r, 100));
        }
      }
      const calls = vi.mocked(SentryMock.captureException).mock.calls;
      expect(calls.length).toBeGreaterThan(0); // positive control: the failure WAS reported
      for (const [err] of calls) {
        const e = err as Error;
        expect(`${e.message}\n${e.stack ?? ""}`).not.toContain(h.token);
      }
      rmSync(tokPath, { recursive: true, force: true });
    },
    20000,
  );

  describe("egressGwTarget (.gw-target is only honoured inside the bootstrap's own subnets)", () => {
    beforeEach(() => {
      vi.stubEnv("EGRESS_GW_HOST", "");
      vi.stubEnv("EGRESS_GW_PORT", "");
    });
    it.each(["172.31.100.2:8443", "172.31.101.2:8443", "172.31.102.2:9443", "172.31.103.2:8443"])(
      "honours %s",
      (line) => {
        writeFileSync(join(tokenDir, ".gw-target"), `${line}\n`);
        const [host, port] = line.split(":");
        expect(egressGwTarget()).toEqual({ host, port: Number(port) });
      },
    );
    it.each([
      "10.9.9.9:4444",
      "172.31.99.2:8443",
      "172.31.104.2:8443",
      "172.30.100.2:8443",
      "10.172.31.100.2:8443",
      "172.31.100.2.5:8443",
      "172.31.100.1:8443", // the bridge's host-side address, not the gateway (.2)
      "172.31.100.999:8443",
      "172.31.100.2:0",
      "172.31.100.2:99999",
      "garbage",
    ])("ignores %s and falls back to the pinned default", (line) => {
      writeFileSync(join(tokenDir, ".gw-target"), `${line}\n`);
      expect(egressGwTarget()).toEqual({ host: "172.31.100.2", port: 8443 });
    });
  });

  it("reaper keeps a FRESH probe-* token (a host cron probe mints these in the same dir) but sweeps a stale one", async () => {
    // A boot-time sweep landing between the probe writing its file and its curl
    // authenticating would 407 a healthy gateway and page a false gw_allow_fail.
    const at = (name: string, ageMs: number) => {
      writeFileSync(join(tokenDir, name), "probe\n");
      const t = new Date(Date.now() - ageMs);
      utimesSync(join(tokenDir, name), t, t);
    };
    at("probe-fresh0123456789", 0);
    at("probe-4min00123456789", 4 * 60 * 1000); // inside the 10-minute grace
    at("probe-stale0123456789", 11 * 60 * 1000); // outside it
    at("probe-future01234567", -24 * 60 * 60 * 1000); // a future mtime must NOT be kept forever
    writeFileSync(join(tokenDir, "stale-token-3"), "ws-z\n");
    reapOrphanEgressForwarders();
    expect(existsSync(join(tokenDir, "probe-fresh0123456789"))).toBe(true);
    expect(existsSync(join(tokenDir, "probe-4min00123456789"))).toBe(true);
    expect(existsSync(join(tokenDir, "probe-stale0123456789"))).toBe(false);
    expect(existsSync(join(tokenDir, "probe-future01234567"))).toBe(false);
    expect(existsSync(join(tokenDir, "stale-token-3"))).toBe(false);
  });

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

// Runner-image packaging (#9952) — server/egress-forwarder.ts › forwarderPath()
// defaults to process.cwd()/infra/egress-forwarder.mjs and cwd is /app in the
// runner image. The host-scripts COPY block lands egress-forwarder.mjs under
// /opt/soleur/host-scripts/ for cloud-init extraction only, so the runtime
// default path was EMPTY: an entitled session's spawn hit ENOENT and degraded
// to zero egress (fail-closed — silent by design). The lifecycle suite above
// overrides EGRESS_FORWARDER_PATH to the repo fixture and cannot attest image
// admission; this guard pins the runner COPY that lands the file at its
// runtime path.
describe("runner-image forwarder packaging (#9952)", () => {
  const dockerfile = readFileSync(join(__dirname, "..", "Dockerfile"), "utf8");
  const RUNTIME_COPY =
    "COPY --from=builder /app/infra/egress-forwarder.mjs ./infra/egress-forwarder.mjs";

  // The runner stage with full-line comments removed — a commented-out COPY
  // must not satisfy the guard (cq-assert-anchor-not-bare-token).
  function runnerNoComments(src: string): string {
    const start = src.search(/^FROM\s+\S+\s+AS\s+runner\s*$/m);
    if (start === -1) throw new Error("Dockerfile has no `FROM … AS runner` stage");
    const rest = src.slice(start + 1);
    const next = rest.search(/^FROM\s/m);
    const stage = next === -1 ? rest : rest.slice(0, next);
    return stage.replace(/^[ \t]*#.*$/gm, "");
  }

  it("the runner stage bakes egress-forwarder.mjs at its runtime default path", () => {
    expect(runnerNoComments(dockerfile)).toContain(RUNTIME_COPY);
  });

  it("a commented-out COPY line does not satisfy the guard", () => {
    const fake = `FROM x AS runner\n# ${RUNTIME_COPY}\n`;
    expect(runnerNoComments(fake)).not.toContain(RUNTIME_COPY);
  });
});
