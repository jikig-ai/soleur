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

import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readdirSync, readFileSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

import { query } from "@anthropic-ai/claude-agent-sdk";

import {
  buildAgentSandboxConfig,
  peerMessagingSocketDirs,
  sessionTranscriptDirs,
} from "@/server/agent-runner-sandbox-config";
import { buildAgentEnv } from "@/server/agent-env";
import { AGENT_SESSION_TMP_ROOT, agentSessionTmpDir } from "@/server/agent-session-tmp";
import { classifyBashSandboxFailure } from "@/server/sandbox-startup-classifier";
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

// The docker suite's probe (infra/lib/sdk-bash-probe.mjs) carries a LITERAL sandbox object because the production
// builder is TypeScript and is not in the suite image. Its static deny entries must stay the production builder's:
// the census arm is only meaningful if the probe masks what production masks.
describe("the docker suite's probe literal tracks the production config (#10445)", () => {
  const probeSrc = readFileSync(join(APP_ROOT, "infra", "lib", "sdk-bash-probe.mjs"), "utf8");
  // The docker-suite (default) mode's literal only: the file also carries the deploy smoke's production-equal literal, which
  // test/sdk-bash-probe-parity.test.ts pins separately (there autoAllowBashIfSandboxed is false, as in production).
  const defaultModeSrc = probeSrc.slice(probeSrc.indexOf("async function runDefault"), probeSrc.indexOf("const SMOKE_INTERNAL_CAP_MS"));
  const literalOf = (key: string): string => {
    const m = new RegExp(`\\b${key}:\\s*([^,}\\n]+)`).exec(defaultModeSrc);
    expect(m, `the probe no longer carries ${key}`).not.toBeNull();
    return m![1].trim();
  };

  it("the probe masks exactly what the production builder masks in the suite container's env (no XDG/TMPDIR, uid, HOME)", () => {
    // The probe derives these from its own process (uid, HOME); the production functions get the same inputs here.
    // The derivation lives in the probe's exported maskedDirs() (also used by the smoke mode); the probe's own parity suite
    // (test/sdk-bash-probe-parity.test.ts) pins its output to the production functions. Here: the default mode uses it.
    expect(probeSrc).toContain("const MASKED_DIRS = maskedDirs(uid, HOME);");
    expect(probeSrc).toContain('return ["/tmp/cc-socks", `/tmp/cc-socks-${uid}`, `${home}/.claude/projects`];');
    expect(probeSrc).toContain("const HOME = process.env.HOME;");
    expect(peerMessagingSocketDirs({}, 1001)).toEqual(["/tmp/cc-socks", "/tmp/cc-socks-1001"]);
    expect(sessionTranscriptDirs({ HOME: "/home/soleur" })).toEqual(["/home/soleur/.claude/projects"]);
    expect(probeSrc).toMatch(/denyRead:\s*\["\/proc",\s*"\/sys",\s*\.\.\.MASKED_DIRS\]/);
    const prod = buildAgentSandboxConfig("/var/lib/soleur/workspaces/00000000-0000-0000-0000-000000000001").filesystem.denyRead;
    expect(prod).toEqual(expect.arrayContaining(["/proc", "/sys", ...peerMessagingSocketDirs(), ...sessionTranscriptDirs()]));
  });

  it("the probe's static sandbox fields equal the production builder's (autoAllowBashIfSandboxed is the one documented difference)", () => {
    const prod = buildAgentSandboxConfig("/var/lib/soleur/workspaces/00000000-0000-0000-0000-000000000001") as Record<string, unknown> & {
      network: Record<string, unknown>;
    };
    expect(literalOf("failIfUnavailable")).toBe(String(prod.failIfUnavailable));
    expect(literalOf("allowUnsandboxedCommands")).toBe(String(prod.allowUnsandboxedCommands));
    expect(literalOf("enableWeakerNestedSandbox")).toBe(String(prod.enableWeakerNestedSandbox));
    expect(literalOf("allowManagedDomainsOnly")).toBe(String(prod.network.allowManagedDomainsOnly));
    // The knob itself: the probe sets it behind KNOB, and production sets it unconditionally to this value.
    expect(probeSrc).toContain("...(KNOB ? { allowAllUnixSockets: true } : {})");
    expect(prod.network.allowAllUnixSockets).toBe(true);
    // Production is `false` so a Bash call reaches canUseTool (#10054); the probe runs with bypassPermissions and no
    // canUseTool, so it sets `true` to avoid a permission prompt. It is the only static field that differs.
    expect(prod.autoAllowBashIfSandboxed).toBe(false);
    expect(literalOf("autoAllowBashIfSandboxed")).toBe("true");
  });
});

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
    // The alert's classifier must recognise the line the REAL SDK produced, not only hand-written fixtures: an SDK
    // bump that reshapes the helper's output turns this red instead of silently blinding the page.
    expect(
      classifyBashSandboxFailure(result!.content)?.errorCode,
      `the classifier did not recognise the real tool_result: ${JSON.stringify(result!.content)}`,
    ).toBe("helper_userns_eperm");
  }, 180_000);

  it("TREATMENT: the production config runs the command with no apply-seccomp wrapper and returns its stdout", async () => {
    const before = commandSpawns("WRAPCMD_OK_10445").length;
    const result = await runBash({ stubPort: stub!.port, home, cwd: own, sandbox: buildAgentSandboxConfig(own) });

    const wrapped = commandSpawns("WRAPCMD_OK_10445").slice(before);
    expect(wrapped.length, "the scripted command never reached a bwrap spawn").toBeGreaterThan(0);
    for (const toks of wrapped) {
      expect(toks.filter((t) => t.includes("apply-seccomp")), "the production config still wraps the command").toEqual([]);
      // Abstract-namespace unix sockets are bounded only by the per-command network namespace; the vendored
      // builder emits --unshare-net whenever it restricts the network, independent of allowAllUnixSockets.
      const boundary = toks.indexOf("--");
      expect(boundary, "no -- boundary in the command spawn").toBeGreaterThan(0);
      expect(toks.slice(0, boundary), "the command spawn lost --unshare-net").toContain("--unshare-net");
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
  const probeScript = (dir: string, needle: string) =>
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
      // #10445 CTO ruling: A ran `env`, so its per-session proxy credential sits in the CLI's persisted output. The host
      // read it from A's own temp dir and wrote it here as the needle; B searches everything it can read for it.
      `needle='${needle}'`,
      `hits=$(grep -rIlF --exclude=probe.sh -- "$needle" /tmp "$TMPDIR" "$HOME" 2>/dev/null | head -5)`,
      `echo NEEDLE_HITS=$(printf '%s' "$hits" | grep -c .)`,
      `echo NEEDLE_PATHS=$(printf '%s' "$hits" | tr '\\n' ,)`,
      `echo SESSION_TMP_ROOT_ENTRIES=$(ls -A ${AGENT_SESSION_TMP_ROOT} 2>/dev/null | grep -c .)`,
      `lc=$(printf '%s' "$needle" | sed 's/%3D/=/g')`,
      `for s in $([ -n "$hits" ] && echo ${dir}/*.sock); do [ -S "$s" ] || continue; b=$(basename "$s")`,
      `  line=$( { printf "CONNECT example.test:443 HTTP/1.1\\r\\nHost: example.test:443\\r\\nProxy-Authorization: Basic $(printf '%s' "$lc" | base64 -w0)\\r\\n\\r\\n"; sleep 1; } | socat -T3 - "UNIX-CONNECT:$s" 2>/dev/null | head -n1 | tr -d '\\r')`,
      `  echo "REPLAY $b [$line]"`,
      `done`,
      `echo SOCKETS=$n`,
      `echo CCSOCKS_IN_SANDBOX=$(ls -A ${peerMessagingSocketDirs().join(" ")} 2>/dev/null | grep -c '\\.sock$')`,
      `echo TRANSCRIPTS_IN_SANDBOX=$(ls -A ${sessionTranscriptDirs().join(" ")} 2>/dev/null | grep -vc '^$')`,
    ].join("\n");

  beforeEach(async () => {
    // The per-run temp root, kept short: a unix socket path is capped at 108 bytes and the SDK names its proxy sockets
    // `<dir>/claude-http-<16 hex>.sock`, so a long TMPDIR fails bridge creation ("Failed to create bridge sockets").
    shared = realpathSync(mkdtempSync(join(tmpdir(), "sbx-g2-")));
    if (Buffer.byteLength(shared) > 60) {
      throw new Error(`TMPDIR_TOO_LONG: ${shared} would push the SDK's proxy socket paths past the 108-byte limit; run with a shorter TMPDIR`);
    }
    rootA = realpathSync(mkdtempSync(join(tmpdir(), "sbx-g2a-")));
    rootB = realpathSync(mkdtempSync(join(tmpdir(), "sbx-g2b-")));
    home = realpathSync(mkdtempSync(join(tmpdir(), "sbx-g2-home-")));
    shimDir = realpathSync(mkdtempSync(join(tmpdir(), "sbx-g2-shim-")));
    mkdirSync(join(rootA, "00000000-0000-0000-0000-00000000000a"));
    mkdirSync(join(rootB, "00000000-0000-0000-0000-00000000000b"));
    writeFileSync(join(shimDir, "bwrap"), `#!/usr/bin/env bash\nexec ${JSON.stringify(BWRAP_SHIM)} "$@"\n`);
    spawnSync("chmod", ["+x", join(shimDir, "bwrap")], { stdio: "ignore" });
    stubA = await startAnthropicStub("env; sleep 60");
    stubB = await startAnthropicStub(`bash ${shared}/probe.sh`);
    scrubAmbientCliEnv();
    pointCliAtStub(stubA.port, home, "decoy-api-key-sentinel");
    // Production shape: the CLI's env is the allowlisted one, so XDG_RUNTIME_DIR is unset and TMPDIR is the short
    // shared dir. The builder reads this same process env, so its masked dirs are derived from what the CLI sees.
    vi.stubEnv("XDG_RUNTIME_DIR", undefined);
    vi.stubEnv("TMPDIR", shared);
    writeFileSync(join(shared, "probe.sh"), probeScript(shared, "NO_NEEDLE_YET"));
    vi.stubEnv("SOLEUR_BWRAP_REAL", "/usr/bin/bwrap");
    vi.stubEnv("SOLEUR_BWRAP_SECCOMP_BPF", BWRAP_BPF);
    vi.stubEnv("PATH", `${shimDir}:${savedPath ?? "/usr/bin:/bin"}`);
  });

  afterEach(async () => {
    vi.unstubAllEnvs();
    await stubA?.close();
    await stubB?.close();
    for (const dir of [shared, rootA, rootB, home, shimDir, agentSessionTmpDir(IDS.a), agentSessionTmpDir(IDS.b)]) {
      if (!dir) continue;
      try {
        rmSync(dir, { recursive: true, force: true, maxRetries: 10, retryDelay: 300 });
      } catch {
        /* scratch space */
      }
    }
  });

  const IDS = { a: "00000000-0000-0000-0000-00000000000a", b: "00000000-0000-0000-0000-00000000000b" };
  const tenantEnv = (id: string, perTenantTmp: boolean): Record<string, string> => ({
    TMPDIR: shared,
    // The production env builder, not a hand-set value: the control arm omits the option (the pre-fix shared CLI temp).
    ...(perTenantTmp
      ? { CLAUDE_CODE_TMPDIR: buildAgentEnv({ value: "decoy", scheme: "api_key" }, {}, { claudeTmpDir: agentSessionTmpDir(id) }).CLAUDE_CODE_TMPDIR! }
      : {}),
  });
  /** Host side: the proxy userinfo A's `env` printed, read from A's own persisted output (null until it exists). */
  const findNeedle = (perTenantTmp: boolean): string | null => {
    const root = perTenantTmp ? agentSessionTmpDir(IDS.a) : shared;
    const walk = (d: string): string[] =>
      readdirSync(d, { withFileTypes: true }).flatMap((e) => {
        try {
          return e.isDirectory() ? walk(join(d, e.name)) : e.name.endsWith(".output") ? [join(d, e.name)] : [];
        } catch {
          return [];
        }
      });
    try {
      for (const f of walk(root)) {
        const m = /grpc_proxy=http:\/\/([^@\s]+)@/.exec(readFileSync(f, "utf8"));
        if (m) return m[1];
      }
    } catch {
      /* not there yet */
    }
    return null;
  };

  const scenario = async (perTenantTmp: boolean) => {
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
      env: tenantEnv(IDS.a, perTenantTmp),
      signal: stopA.signal,
    });
    try {
      // Wait until A's bridge socket exists: B must run while A is live, or the probe has nothing to find.
      const deadline = Date.now() + 60_000;
      const sockets = () => readdirSync(shared).filter((n) => n.endsWith(".sock"));
      while (Date.now() < deadline && sockets().length === 0) await new Promise((r) => setTimeout(r, 500));
      expect(sockets().length, "session A never created a proxy socket (the probe would be vacuous)").toBeGreaterThan(0);

      // Non-vacuity: A's `env` output (with its credential) is on disk host-side BEFORE B looks. B runs against the oracle.
      let needle: string | null = null;
      const nDeadline = Date.now() + 60_000;
      while (Date.now() < nDeadline && !(needle = findNeedle(perTenantTmp))) await new Promise((r) => setTimeout(r, 500));
      expect(needle, "A's persisted `env` output never appeared, so the cross-tenant scan would be vacuous").not.toBeNull();
      writeFileSync(join(shared, "probe.sh"), probeScript(shared, needle!));

      const result = await runBash({
        stubPort: stubB!.port,
        home,
        cwd: ownB,
        sandbox: sandboxB,
        env: tenantEnv(IDS.b, perTenantTmp),
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

      // #10445 CTO ruling. The credential-recovery channel: B must not find A's credential anywhere it can read, and must not
      // be able to replay it. The control arm (shared CLI temp, the pre-fix layout) PROVES the scan can see the leak.
      const hits = Number(/^NEEDLE_HITS=(\d+)$/m.exec(out)?.[1] ?? "-1");
      const replays = [...out.matchAll(/^REPLAY (\S+) \[(.*)\]$/gm)].map((m) => ({ sock: m[1], line: m[2] }));
      if (perTenantTmp) {
        expect(replays, "B found nothing to replay").toEqual([]);
        expect(hits, `B found A's credential at: ${/^NEEDLE_PATHS=(.*)$/m.exec(out)?.[1]}`).toBe(0);
        expect(Number(/^SESSION_TMP_ROOT_ENTRIES=(\d+)$/m.exec(out)?.[1] ?? "-1"), "B sees a sibling's CLI temp base").toBe(1);
      } else {
        expect(hits, "control: the scan failed to find the leak in the shared CLI temp").toBeGreaterThan(0);
        expect(replays.length, `control: no replay ran:\n${out}`).toBe(socketsSeen);
        expect(replays.some((r) => !r.line.includes("407")), "control: the replay was never accepted").toBe(true);
      }

      // The property: no request lacking the target session's credential is served.
      for (const p of probes.filter((x) => x.label !== "own")) {
        expect(p.line, `${p.sock} answered a ${p.label} request with something other than 407`).toContain("407");
      }
      // The CLI's peer-messaging sockets: present on the host side while the sessions are live (non-vacuity), and
      // masked from the tenant's sandbox (ADR-075 addendum 2026-10-16).
      const hostSideCcSocks = peerMessagingSocketDirs().flatMap((d) => {
        try {
          return readdirSync(d).filter((n) => n.endsWith(".sock"));
        } catch {
          return [];
        }
      });
      if (!perTenantTmp) {
        expect(
          hostSideCcSocks.length,
          "no live peer-messaging socket on the host side, so the mask assertion below is vacuous",
        ).toBeGreaterThan(0);
      }
      expect(out).toContain("CCSOCKS_IN_SANDBOX=0");
      // Session transcripts under the shared HOME: A's CLI wrote one (host-side non-vacuity), B's sandbox sees none.
      const transcriptDirs = sessionTranscriptDirs();
      const hostSideTranscripts = () =>
        transcriptDirs.flatMap((d) => {
          try {
            return readdirSync(d);
          } catch {
            return [];
          }
        });
      const tDeadline = Date.now() + 20_000;
      while (Date.now() < tDeadline && hostSideTranscripts().length === 0) await new Promise((r) => setTimeout(r, 500));
      expect(
        hostSideTranscripts().length,
        "no session transcript on the host side, so the transcript-mask assertion below is vacuous",
      ).toBeGreaterThan(0);
      expect(out).toContain("TRANSCRIPTS_IN_SANDBOX=0");
      // Negative control: the caller's own credential is accepted by its own socket(s) (the check is live,
      // not a proxy that answers 407 to everything) and refused by the sibling's.
      const ownAnswers = probes.filter((x) => x.label === "own");
      expect(ownAnswers.some((p) => !p.line.includes("407")), `no socket accepted B's own credential:\n${out}`).toBe(true);
      expect(ownAnswers.some((p) => p.line.includes("407")), `every socket accepted B's credential:\n${out}`).toBe(true);
    } finally {
      stopA.abort();
      await sessionA.catch(() => undefined);
    }
  };

  it("per-tenant CLI temp: B cannot find or replay A's credential (A ran `env`); tokenless and wrong-credential requests return 407; the caller's own credential is live", () => scenario(true), 240_000);
  it("CONTROL: with a shared CLI temp (the pre-fix layout) the same scan finds A's credential and the replay is accepted", () => scenario(false), 240_000);
});
