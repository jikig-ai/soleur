// #10445 — the wrapped-command defect, observed through the FULL production chain: the real Agent
// SDK + the real production `buildAgentSandboxConfig` + our real bwrap shim + a scripted API
// stand-in (no model, no network, no real credential).
//
// THE DEFECT. With `network.allowAllUnixSockets` unset the vendored builder wraps EVERY sandboxed
// command in its embedded `apply-seccomp` helper, whose first call is unshare(CLONE_NEWUSER). Our
// shim's own --add-seccomp-fd filter denies that syscall, so every hosted Bash call died with
//   apply-seccomp: unshare(CLONE_NEWUSER): Operation not permitted
// from the first production deploy of web-v0.324.3 (2026-10-06). The faithful canary stayed green
// because its replay ends in `-- true` and never runs a wrapper.
//
// G1 (control + treatment). The two arms differ ONLY in the knob:
//   CONTROL    knob off -> the command's bwrap spawn carries `apply-seccomp` and the tool_result is the
//              helper's EPERM line (the committed RCA reproduction).
//   TREATMENT  production config -> the spawn carries no `apply-seccomp` and the command's own stdout
//              comes back.
//
// G2 (cross-session socket exposure, the CTO's condition on the knob). With AF_UNIX no longer blocked
// inside the inner sandbox, a second tenant's Bash can see and connect to a sibling session's proxy
// sockets in the shared temp dir. Pass means every request that lacks that sibling's proxy credential is
// refused with 407, while a request carrying the caller's OWN credential is live (negative control: the
// check can answer something other than 407).
//
// Runs on a CI runner, not the production image: the docker suite
// (infra/sandbox-masked-proc-docker.test.sh) carries the production-tuple arms.

import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readdirSync, readFileSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import { query } from "@anthropic-ai/claude-agent-sdk";

import { buildAgentSandboxConfig } from "@/server/agent-runner-sandbox-config";
import { startAnthropicStub, type AnthropicStub } from "./helpers/anthropic-stub";
import { pointCliAtStub, scrubAmbientCliEnv } from "./helpers/hermetic-cli-env";

const APP_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const BWRAP_SHIM = join(APP_ROOT, "infra", "bwrap-shim", "bwrap");
const BWRAP_BPF = join(APP_ROOT, "infra", "bwrap-userns-clone3-deny.bpf");

const HELPER_EPERM = "apply-seccomp: unshare(CLONE_NEWUSER): Operation not permitted";

const BWRAP_OK =
  process.platform === "linux" &&
  spawnSync("bwrap", ["--unshare-user", "--unshare-pid", "--ro-bind", "/", "/", "--", "true"], {
    stdio: "ignore",
    timeout: 15_000,
  }).status === 0;
const SOCAT_OK =
  process.platform === "linux" && spawnSync("sh", ["-c", "command -v socat"], { stdio: "ignore" }).status === 0;
const SANDBOX_OK = BWRAP_OK && SOCAT_OK;
if (process.platform === "linux" && !SANDBOX_OK && process.env.C4_BWRAP_REQUIRED) {
  throw new Error(
    `C4_BWRAP_REQUIRED is set but the sandbox cannot run here (bwrap usable: ${BWRAP_OK}, socat on PATH: ${SOCAT_OK}). ` +
      "apt-get install bubblewrap socat && sysctl -w kernel.apparmor_restrict_unprivileged_userns=0 (Ubuntu)",
  );
}

interface ToolResult {
  content: string;
  isError: boolean;
}

/** Drive one scripted Bash turn through the real SDK and return the Bash tool_result. */
async function runBash(opts: {
  stubPort: number;
  home: string;
  cwd: string;
  sandbox: unknown;
  env?: Record<string, string | undefined>;
  signal?: AbortSignal;
}): Promise<ToolResult | null> {
  const controller = new AbortController();
  opts.signal?.addEventListener("abort", () => controller.abort());
  let found: ToolResult | null = null;
  const q = query({
    prompt: "run it",
    options: {
      abortController: controller,
      model: "claude-haiku-4-5-20251001",
      maxTurns: 3,
      permissionMode: "default",
      cwd: opts.cwd,
      allowedTools: ["Bash"],
      settingSources: [],
      sandbox: opts.sandbox as never,
      env: {
        ...process.env,
        ANTHROPIC_BASE_URL: `http://127.0.0.1:${opts.stubPort}`,
        HOME: opts.home,
        ...(opts.env ?? {}),
      },
      canUseTool: async (_name, input) => ({ behavior: "allow", updatedInput: input }),
    },
  });
  try {
    for await (const msg of q) {
      if (msg.type !== "user") continue;
      const content = (msg.message as { content?: unknown }).content;
      if (!Array.isArray(content)) continue;
      for (const block of content as { type?: string; content?: unknown; is_error?: boolean }[]) {
        if (block.type !== "tool_result") continue;
        const text =
          typeof block.content === "string"
            ? block.content
            : Array.isArray(block.content)
              ? (block.content as { text?: string }[]).map((c) => c.text ?? "").join("")
              : "";
        found = { content: text, isError: block.is_error === true };
      }
    }
  } catch (e) {
    if (!controller.signal.aborted) throw e;
  } finally {
    controller.abort();
  }
  return found;
}

describe.skipIf(!SANDBOX_OK)("a hosted Bash call through the real SDK, the production config and our shim (#10445)", () => {
  let stub: AnthropicStub | undefined;
  let root: string;
  let own: string;
  let home: string;
  let shimDir: string;
  let shimLog: string;
  const savedPath = process.env.PATH;

  const spawns = (): string[][] => {
    // The log does not exist until the first recorded spawn.
    let raw = "";
    try {
      raw = readFileSync(shimLog, "utf8");
    } catch (e) {
      if ((e as NodeJS.ErrnoException).code !== "ENOENT") throw e;
    }
    return raw
      .split("\0\0")
      .filter(Boolean)
      .map((call) => call.split("\0").filter(Boolean));
  };
  /** The spawn(s) whose command part (after the `--` boundary) runs the scripted command. */
  const commandSpawns = (marker: string): string[][] =>
    spawns().filter((toks) => {
      const boundary = toks.indexOf("--");
      return boundary >= 0 && toks.slice(boundary + 1).some((t) => t.includes(marker));
    });

  beforeAll(async () => {
    root = realpathSync(mkdtempSync(join(tmpdir(), "sbx-wrapcmd-")));
    own = join(root, "00000000-0000-0000-0000-000000000001");
    mkdirSync(own);
    home = realpathSync(mkdtempSync(join(tmpdir(), "sbx-wrapcmd-home-")));
    shimDir = realpathSync(mkdtempSync(join(tmpdir(), "sbx-wrapcmd-shim-")));
    shimLog = join(shimDir, "calls.log");
    // The wrapper records each invocation, then execs the REAL shim (the interception chain, not a look-alike).
    writeFileSync(
      join(shimDir, "bwrap"),
      `#!/usr/bin/env bash\n` +
        `printf '%s\\0' "$@" >> ${JSON.stringify(shimLog)}\n` +
        `printf '\\0' >> ${JSON.stringify(shimLog)}\n` +
        `exec ${JSON.stringify(BWRAP_SHIM)} "$@"\n`,
    );
    spawnSync("chmod", ["+x", join(shimDir, "bwrap")], { stdio: "ignore" });
    stub = await startAnthropicStub("echo WRAPCMD_OK_10445");
    scrubAmbientCliEnv();
    pointCliAtStub(stub.port, home, "decoy-api-key-sentinel");
    vi.stubEnv("WORKSPACES_ROOT", root);
    vi.stubEnv("C4_RENDER_STAGING_ROOT", `${root}-c4-staging`);
    vi.stubEnv("SOLEUR_BWRAP_REAL", "/usr/bin/bwrap");
    vi.stubEnv("SOLEUR_BWRAP_SECCOMP_BPF", BWRAP_BPF);
    vi.stubEnv("PATH", `${shimDir}:${savedPath ?? "/usr/bin:/bin"}`);
  });

  afterAll(async () => {
    vi.unstubAllEnvs();
    await stub?.close();
    for (const dir of [root, root && `${root}-c4-staging`, home, shimDir]) {
      if (!dir) continue;
      try {
        rmSync(dir, { recursive: true, force: true, maxRetries: 10, retryDelay: 300 });
      } catch {
        /* scratch space */
      }
    }
  });

  it("CONTROL: with the knob off the command is wrapped in apply-seccomp and dies with the helper's EPERM (the RCA reproduction)", async () => {
    const prod = buildAgentSandboxConfig(own) as { network: Record<string, unknown> };
    const control = { ...prod, network: { ...prod.network, allowAllUnixSockets: false } };
    const before = commandSpawns("WRAPCMD_OK_10445").length;
    const result = await runBash({ stubPort: stub!.port, home, cwd: own, sandbox: control });

    const wrapped = commandSpawns("WRAPCMD_OK_10445").slice(before);
    expect(wrapped.length, "the scripted command never reached a bwrap spawn").toBeGreaterThan(0);
    expect(
      wrapped.some((toks) => toks.some((t) => t.includes("apply-seccomp"))),
      "knob off: the command spawn should carry the apply-seccomp wrapper",
    ).toBe(true);
    expect(result, "no Bash tool_result came back").not.toBeNull();
    expect(result!.isError).toBe(true);
    expect(result!.content).toContain(HELPER_EPERM);
  }, 180_000);

  it("TREATMENT: the production config runs the command with no apply-seccomp wrapper and returns its stdout", async () => {
    const before = commandSpawns("WRAPCMD_OK_10445").length;
    const result = await runBash({ stubPort: stub!.port, home, cwd: own, sandbox: buildAgentSandboxConfig(own) });

    const wrapped = commandSpawns("WRAPCMD_OK_10445").slice(before);
    expect(wrapped.length, "the scripted command never reached a bwrap spawn").toBeGreaterThan(0);
    for (const toks of wrapped) {
      expect(toks.filter((t) => t.includes("apply-seccomp")), "the production config still wraps the command").toEqual([]);
    }
    expect(result, "no Bash tool_result came back").not.toBeNull();
    expect(result!.isError).toBe(false);
    expect(result!.content).toContain("WRAPCMD_OK_10445");
    expect(result!.content).not.toContain("apply-seccomp");
  }, 180_000);
});

// G2. A short, shared temp dir: a unix socket path is limited to 108 bytes, and the SDK names its proxy
// sockets under TMPDIR, so a long tmpdir fails bridge creation ("Failed to create bridge sockets").
describe.skipIf(!SANDBOX_OK)("G2: a second tenant's Bash cannot use a sibling session's proxy sockets (#10445)", () => {
  let stubA: AnthropicStub | undefined;
  let stubB: AnthropicStub | undefined;
  let shared: string;
  let rootA: string;
  let rootB: string;
  let home: string;
  let shimDir: string;
  const savedPath = process.env.PATH;

  // Runs inside B's sandbox. For every pathname socket in the shared dir it sends a CONNECT with (1) no
  // credential, (2) a wrong credential and (3) B's own proxy credential, and prints the status line.
  const probeScript = (dir: string) =>
    [
      `cd ${dir}`,
      `own=$(printf '%s' "$grpc_proxy" | sed -n 's|^http://\\([^@]*\\)@.*|\\1|p' | sed 's/%3D/=/g')`,
      `echo OWN_CRED_PRESENT=$([ -n "$own" ] && echo yes || echo no)`,
      `n=0; for s in ${dir}/*.sock; do [ -S "$s" ] || continue; n=$((n+1)); b=$(basename "$s")`,
      `  for label in tokenless wrong own; do`,
      `    case $label in tokenless) auth='' ;; wrong) auth="Proxy-Authorization: Basic $(printf 'x:y' | base64)\\r\\n" ;; own) auth="Proxy-Authorization: Basic $(printf '%s' "$own" | base64 -w0)\\r\\n" ;; esac`,
      // stdin stays open for a second after the request: an immediate EOF half-closes the connection and the
      // proxy may drop it before it answers, which would read as an empty (and therefore vacuous) response.
      `    line=$( { printf "CONNECT example.test:443 HTTP/1.1\\r\\nHost: example.test:443\\r\\n$auth\\r\\n"; sleep 1; } | socat -T3 - "UNIX-CONNECT:$s" 2>/dev/null | head -n1 | tr -d '\\r')`,
      `    echo "PROBE $b $label [$line]"`,
      `  done`,
      `done`,
      `echo SOCKETS=$n`,
    ].join("\n");

  beforeAll(async () => {
    shared = realpathSync(mkdtempSync(join("/tmp", "sbx-g2-")));
    rootA = realpathSync(mkdtempSync(join(tmpdir(), "sbx-g2a-")));
    rootB = realpathSync(mkdtempSync(join(tmpdir(), "sbx-g2b-")));
    home = realpathSync(mkdtempSync(join(tmpdir(), "sbx-g2-home-")));
    shimDir = realpathSync(mkdtempSync(join(tmpdir(), "sbx-g2-shim-")));
    mkdirSync(join(rootA, "00000000-0000-0000-0000-00000000000a"));
    mkdirSync(join(rootB, "00000000-0000-0000-0000-00000000000b"));
    writeFileSync(join(shared, "probe.sh"), probeScript(shared));
    writeFileSync(join(shimDir, "bwrap"), `#!/usr/bin/env bash\nexec ${JSON.stringify(BWRAP_SHIM)} "$@"\n`);
    spawnSync("chmod", ["+x", join(shimDir, "bwrap")], { stdio: "ignore" });
    stubA = await startAnthropicStub("sleep 60");
    stubB = await startAnthropicStub(`bash ${shared}/probe.sh`);
    scrubAmbientCliEnv();
    pointCliAtStub(stubA.port, home, "decoy-api-key-sentinel");
    vi.stubEnv("SOLEUR_BWRAP_REAL", "/usr/bin/bwrap");
    vi.stubEnv("SOLEUR_BWRAP_SECCOMP_BPF", BWRAP_BPF);
    vi.stubEnv("PATH", `${shimDir}:${savedPath ?? "/usr/bin:/bin"}`);
  });

  afterAll(async () => {
    vi.unstubAllEnvs();
    await stubA?.close();
    await stubB?.close();
    for (const dir of [shared, rootA, rootB, home, shimDir]) {
      if (!dir) continue;
      try {
        rmSync(dir, { recursive: true, force: true, maxRetries: 10, retryDelay: 300 });
      } catch {
        /* scratch space */
      }
    }
  });

  it("tokenless and wrong-credential requests through any visible sibling socket return 407; the caller's own credential is live", async () => {
    const ownA = join(rootA, "00000000-0000-0000-0000-00000000000a");
    const ownB = join(rootB, "00000000-0000-0000-0000-00000000000b");
    const stopA = new AbortController();
    // A needs a proxy to bridge: an allowed domain makes the SDK stand up its http/socks proxies.
    const sandboxA = buildAgentSandboxConfig(ownA, { allowGithubEgress: true });
    const sandboxB = buildAgentSandboxConfig(ownB, { allowGithubEgress: true });
    const sessionA = runBash({
      stubPort: stubA!.port,
      home,
      cwd: ownA,
      sandbox: sandboxA,
      env: { TMPDIR: shared },
      signal: stopA.signal,
    });
    try {
      // Wait until A's bridge socket exists: B must run while A is live, or the probe has nothing to find.
      const deadline = Date.now() + 60_000;
      const sockets = () => readdirSync(shared).filter((n) => n.endsWith(".sock"));
      while (Date.now() < deadline && sockets().length === 0) await new Promise((r) => setTimeout(r, 500));
      expect(sockets().length, "session A never created a proxy socket (the probe would be vacuous)").toBeGreaterThan(0);

      const result = await runBash({
        stubPort: stubB!.port,
        home,
        cwd: ownB,
        sandbox: sandboxB,
        env: { TMPDIR: shared },
      });
      expect(result, "B's probe returned no tool_result").not.toBeNull();
      const out = result!.content;
      const probes = [...out.matchAll(/^PROBE (\S+) (tokenless|wrong|own) \[(.*)\]$/gm)].map((m) => ({
        sock: m[1],
        label: m[2],
        line: m[3],
      }));
      const socketsSeen = Number(/^SOCKETS=(\d+)$/m.exec(out)?.[1] ?? "0");

      // Non-vacuity: the probe found sockets and could authenticate as itself.
      expect(socketsSeen, `the probe saw no socket:\n${out}`).toBeGreaterThan(0);
      expect(out).toContain("OWN_CRED_PRESENT=yes");
      expect(probes.length).toBe(socketsSeen * 3);

      // The property: no request lacking the target session's credential is served.
      for (const p of probes.filter((x) => x.label !== "own")) {
        expect(p.line, `${p.sock} answered a ${p.label} request with something other than 407`).toContain("407");
      }
      // Negative control: the caller's own credential is accepted by its own socket(s) (the check is live,
      // not a proxy that answers 407 to everything) and refused by the sibling's.
      const ownAnswers = probes.filter((x) => x.label === "own");
      expect(ownAnswers.some((p) => !p.line.includes("407")), `no socket accepted B's own credential:\n${out}`).toBe(true);
      expect(ownAnswers.some((p) => p.line.includes("407")), `every socket accepted B's credential:\n${out}`).toBe(true);
    } finally {
      stopA.abort();
      await sessionA.catch(() => undefined);
    }
  }, 240_000);
});
