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
// G2 also measures (#10455, PR 1a) what a sibling tenant can read of the REAL CLI's persisted output: per-run synthesized markers for
// the first tenant's prompt text and tool output must each be proven persisted at a host path and then be absent from the three roots the
// second tenant's search covers (its HOME, its TMPDIR and the host /tmp, files up to 7812 KiB; one canary per root proves the search can find them); the CLI state the sibling CAN read in the shared HOME is
// pinned as a documented residual (ADR-075 addendum 2026-10-31), and the first tenant's recorded messaging socket path must not be
// visible from the sibling's mount view.
//
// Runs on a CI runner, not the production image: the docker suite
// (infra/sandbox-masked-proc-docker.test.sh) carries the production-tuple arms.

import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { spawnSync } from "node:child_process";
import { randomBytes } from "node:crypto";
import { existsSync, mkdirSync, mkdtempSync, readdirSync, readFileSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import type { Dirent } from "node:fs";
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
import { checkSeccompAgreement } from "@/server/agent-sandbox-seccomp";
import { AGENT_SESSION_TMP_ROOT, agentSessionTmpDir } from "@/server/agent-session-tmp";
import { classifyBashSandboxFailure } from "@/server/sandbox-startup-classifier";
import { startAnthropicStub, type AnthropicStub } from "./helpers/anthropic-stub";
import { pointCliAtStub, scrubAmbientCliEnv } from "./helpers/hermetic-cli-env";

const APP_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const BWRAP_SHIM = join(APP_ROOT, "infra", "bwrap-shim", "bwrap");
const BWRAP_BPF = join(APP_ROOT, "infra", "bwrap-userns-clone3-deny.bpf");
const BWRAP_BPF_UNIXDENY = join(APP_ROOT, "infra", "bwrap-userns-clone3-unixdeny.bpf");

// The credential every G2 session is given; a B-readable CLI state file must never hold it (or its tail).
const DECOY_KEY = "decoy-api-key-sentinel";

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
  /** The user prompt the CLI persists (G2 plants a per-run marker here); the scripted stub ignores its text. */
  prompt?: string;
}): Promise<ToolResult | null> {
  const controller = new AbortController();
  opts.signal?.addEventListener("abort", () => controller.abort());
  let found: ToolResult | null = null;
  const q = query({
    prompt: opts.prompt ?? "run it",
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
    expect(probeSrc).toContain('return ["/tmp/cc-socks", `/tmp/cc-socks-${uid}`, transcriptDir(home)];');
    expect(probeSrc).toContain("return `${home}/.claude/projects`;");
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
// Size bound of B's in-sandbox search (largest searched file: 7812 KiB); the host-side check reads whatever its small test directories hold.
const MAX_SCAN_KIB = 7812;
// Host-side waits, in the order the scenario takes them. Worst case before B's probe even starts is their SUM (60 + 60 + 45 + 20 s).
const SOCKET_WAIT_MS = 60_000;
const PERSIST_WAIT_MS = 60_000;
const MARKER_BUDGET_MS = 45_000;
const G2_ARMS_RUN = new Set<string>();

describe.skipIf(!SANDBOX_OK)("G2: a second tenant's Bash cannot use a sibling session's proxy sockets or read its persisted CLI content (#10445, #10455)", () => {
  let stubA: AnthropicStub | undefined;
  let stubB: AnthropicStub | undefined;
  let shared: string;
  let rootA: string;
  let rootB: string;
  let home: string;
  let shimDir: string;
  // #10455 (PR 1a): per-run synthesized markers for the content A's real CLI persists. promptNeedle rides A's user prompt,
  // toolNeedle is printed by A's scripted Bash call; neither is a secret. B must not be able to read either anywhere.
  let promptNeedle: string;
  let toolNeedle: string;
  // A's messaging socket paths (host side, read from A's own session files); B must not be able to see any of them.
  let probeSockets: string[] = [];
  // Host /tmp canaries (B searches the host /tmp), removed after each test.
  const tmpCanaries: string[] = [];
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
      // ONE bounded pass over the three roots B's search covers (its HOME, its TMPDIR and the host /tmp): files up to MAX_SCAN_KIB, a 60 s
      // wall-clock cap whose expiry is reported (SEARCH_FIND_RC=124) so a truncated walk can never read as "nothing found". -a, not -I: a
      // file the CLI writes with a NUL byte or invalid UTF-8 must still be searched, for the credential and for the content markers alike.
      `pn='${promptNeedle}'; tn='${toolNeedle}'`,
      // B writes a canary into its OWN TMPDIR: a write that works proves the root it searches is the root it can write to.
      `printf '%s %s\\n' "$pn" "$tn" > "$TMPDIR/g2-canary-tmpdir.txt" 2>/dev/null`,
      `all=$( { timeout 60 find "$HOME" "$TMPDIR" /tmp -xdev -type f -size -${MAX_SCAN_KIB + 1}k ! -name probe.sh -print0 2>/dev/null; echo $? > "$TMPDIR/.g2-find-rc"; } | xargs -0 -r grep -aoHF -e "$needle" -e "$pn" -e "$tn" 2>/dev/null | sort -u)`,
      `echo SEARCH_FIND_RC=$(cat "$TMPDIR/.g2-find-rc" 2>/dev/null || echo missing)`,
      `hits=$(printf '%s\\n' "$all" | grep -F ":$needle" | cut -d: -f1 | sort -u | head -5)`,
      `echo NEEDLE_HITS=$(printf '%s' "$hits" | grep -c .)`,
      `echo NEEDLE_PATHS=$(printf '%s' "$hits" | tr '\\n' ,)`,
      `echo PROMPT_NEEDLE_HITS=$(printf '%s\\n' "$all" | grep -cF ":$pn")`,
      `echo PROMPT_NEEDLE_PATHS=$(printf '%s\\n' "$all" | grep -F ":$pn" | cut -d: -f1 | tr '\\n' ,)`,
      `echo TOOL_NEEDLE_HITS=$(printf '%s\\n' "$all" | grep -cF ":$tn")`,
      `echo TOOL_NEEDLE_PATHS=$(printf '%s\\n' "$all" | grep -F ":$tn" | cut -d: -f1 | tr '\\n' ,)`,
      // Reachability, not a path-prefix claim: can B even SEE the path A's CLI recorded for its messaging socket?
      `ns=0; for sp in ${probeSockets.map((x) => `'${x}'`).join(" ")}; do ns=$((ns+1)); [ -e "$sp" ] && echo SOCK_VISIBLE=$sp; done; echo SOCK_CHECKED=$ns`,
      // Which of the CLI's other persisted files B can read at all (names only, ids collapsed): the residual surface the content
      // markers above cannot see (session metadata, keys, shell snapshots, account state). No depth cap; files, sockets and symlinks.
      `echo HOME_READABLE=$(find "$HOME/.claude" "$HOME/.claude.json" \\( -type f -o -type s -o -type l \\) -readable 2>/dev/null | sed "s|$HOME/||; s|sessions/[0-9]*\\.[0-9a-f]\\{64\\}\\.key|sessions/<pid>.<hash>.key|; s|sessions/[0-9]*\\.json|sessions/<pid>.json|; s|snapshot-bash-[0-9]*-[a-z0-9]*\\.sh|snapshot-bash-<ts>-<id>.sh|; s|backup\\.[0-9]*|backup.<ts>|" | sort -u | tr '\\n' ,)`,
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
    promptNeedle = `PROMPTNEEDLE${randomBytes(6).toString("hex")}`;
    toolNeedle = `TOOLNEEDLE${randomBytes(6).toString("hex")}`;
    probeSockets = [];
    stubA = await startAnthropicStub(`echo ${toolNeedle}; env; sleep 60`);
    stubB = await startAnthropicStub(`bash ${shared}/probe.sh`);
    scrubAmbientCliEnv();
    pointCliAtStub(stubA.port, home, DECOY_KEY);
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
    for (const dir of [shared, rootA, rootB, home, shimDir, agentSessionTmpDir(IDS.a), agentSessionTmpDir(IDS.b), ...tmpCanaries.splice(0)]) {
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

  /** Host side: every regular file under the roots whose content holds `value` (no symlinks followed; probe.sh excluded). */
  const hostPathsHolding = (value: string, roots: string[]): string[] => {
    const found: string[] = [];
    const walk = (d: string): void => {
      let entries: Dirent[];
      try {
        entries = readdirSync(d, { withFileTypes: true });
      } catch {
        return;
      }
      for (const e of entries) {
        const p = join(d, e.name);
        if (e.isDirectory()) walk(p);
        else if (e.isFile() && e.name !== "probe.sh") {
          // No stat before the read (a stat-then-read on the path is a check-then-use race). These roots are the test's own small
          // directories; B's in-sandbox search skips files above MAX_SCAN_KIB, a documented bound (ADR-075 addendum).
          try {
            if (readFileSync(p, "utf8").includes(value)) found.push(p);
          } catch {
            /* unreadable or vanished */
          }
        }
      }
    };
    roots.forEach(walk);
    return found;
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
      prompt: `${promptNeedle} please run the scripted command`,
    });
    try {
      // Wait until A's bridge socket exists: B must run while A is live, or the probe has nothing to find.
      const deadline = Date.now() + SOCKET_WAIT_MS;
      const sockets = () => readdirSync(shared).filter((n) => n.endsWith(".sock"));
      while (Date.now() < deadline && sockets().length === 0) await new Promise((r) => setTimeout(r, 500));
      expect(sockets().length, "session A never created a proxy socket (the probe would be vacuous)").toBeGreaterThan(0);

      // Non-vacuity: A's `env` output (with its credential) is on disk host-side BEFORE B looks. B runs against the oracle.
      let needle: string | null = null;
      const nDeadline = Date.now() + PERSIST_WAIT_MS;
      while (Date.now() < nDeadline && !(needle = findNeedle(perTenantTmp))) await new Promise((r) => setTimeout(r, 500));
      expect(needle, "A's persisted `env` output never appeared, so the cross-tenant scan would be vacuous").not.toBeNull();
      // #10455 PR 1a non-vacuity, per needle class: the REAL CLI must have persisted each marker at a named host path before
      // B's zero-hit result can mean anything. A class A never persisted is "not_exercisable" and fails here, never green.
      const hostRoots = [home, shared, agentSessionTmpDir(IDS.a)];
      const budget = Date.now() + MARKER_BUDGET_MS; // one shared budget for the marker polls; the stacked worst case (165 s, plus the transcript wait) still leaves B's run inside the 240 s test timeout only on a healthy runner
      const pollUntil = async <T,>(read: () => T, done: (v: T) => boolean): Promise<T> => {
        let v = read();
        while (Date.now() < budget && !done(v)) {
          await new Promise((r) => setTimeout(r, 500));
          v = read();
        }
        return v;
      };
      const hostPrompt = await pollUntil(() => hostPathsHolding(promptNeedle, hostRoots), (v) => v.length > 0);
      const hostTool = await pollUntil(() => hostPathsHolding(toolNeedle, hostRoots), (v) => v.length > 0);
      expect(hostPrompt, "not_exercisable: A's CLI never persisted its prompt marker anywhere host-visible").not.toEqual([]);
      expect(hostTool, "not_exercisable: A's CLI never persisted its tool-output marker anywhere host-visible").not.toEqual([]);
      // A's recorded messaging socket paths, read from A's own session files; each must exist host-side or the reachability probe is vacuous.
      const sessionDir = join(home, ".claude", "sessions");
      const readSocketPaths = (): string[] => {
        try {
          return readdirSync(sessionDir)
            .filter((f) => f.endsWith(".json"))
            .map((f) => (JSON.parse(readFileSync(join(sessionDir, f), "utf8")) as { messagingSocketPath?: string }).messagingSocketPath)
            .filter((x): x is string => typeof x === "string" && x.startsWith("/"));
        } catch {
          return [];
        }
      };
      const socketPaths = await pollUntil(readSocketPaths, (v) => v.length > 0 && v.some((sp) => existsSync(sp)));
      expect(socketPaths.length, "no messagingSocketPath recorded, so the key-reachability check is vacuous").toBeGreaterThan(0);
      expect(socketPaths.some((sp) => existsSync(sp)), "A's messaging socket does not exist host-side, so the reachability probe is vacuous").toBe(true);
      probeSockets = socketPaths;
      // Positive controls for B's one-pass marker search, ONE PER ROOT it covers: its HOME, the host /tmp, and its own TMPDIR (B writes that
      // one itself; its TMPDIR is <shared>/claude-<uid>, not <shared>). A dead search flag, a typo'd root or a dropped root reads 0 for
      // every class and would otherwise stay green; each canary must be found exactly once.
      const canary = join(home, "g2-canary.txt");
      writeFileSync(canary, `${promptNeedle} ${toolNeedle}\n`);
      // A NUL-bearing carrier in HOME: pins -a (a search that skips binary files misses a state file with an embedded NUL byte).
      const canaryBin = join(home, "g2-canary.bin");
      writeFileSync(canaryBin, Buffer.concat([Buffer.from([0]), Buffer.from(`${promptNeedle} ${toolNeedle}`), Buffer.from([0, 1])]));
      const canaryTmp = join("/tmp", `g2-canary-${randomBytes(6).toString("hex")}.txt`);
      writeFileSync(canaryTmp, `${promptNeedle} ${toolNeedle}\n`);
      tmpCanaries.push(canaryTmp);
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
      const hitsOf = (label: string) => Number(new RegExp(`^${label}_HITS=(\\d+)$`, "m").exec(out)?.[1] ?? "-1");
      const pathsOf = (label: string) => new RegExp(`^${label}_PATHS=(.*)$`, "m").exec(out)?.[1] ?? "?";
      // The search must have completed: a timed-out walk (rc 124) or a missing rc would make every zero below meaningless.
      const findRc = /^SEARCH_FIND_RC=(\S+)$/m.exec(out)?.[1];
      expect(findRc, "B's search walk timed out or never reported, so a zero below proves nothing").toBeDefined();
      expect(findRc).not.toBe("124");
      expect(findRc).not.toBe("missing");
      // The four canary files (HOME text and binary, host /tmp, B's own TMPDIR) are the only B-readable carriers of either marker under the production
      // layout; the control arm's shared CLI temp additionally holds A's tool output. Soft: a failure here must not hide the #10445 checks.
      const CANARY_FILES = 4; // HOME text, HOME binary, host /tmp, B's own TMPDIR
      for (const [label, expected] of [["PROMPT_NEEDLE", "prompt"], ["TOOL_NEEDLE", "tool output"]] as const) {
        const exact = label === "PROMPT_NEEDLE" || perTenantTmp;
        if (exact) expect.soft(hitsOf(label), `B read A's ${expected} at: ${pathsOf(label)} (expected only the ${CANARY_FILES} canary files)`).toBe(CANARY_FILES);
        else expect.soft(hitsOf(label), "control: B's marker search must find A's tool output in the shared CLI temp as well as the canaries").toBeGreaterThan(CANARY_FILES);
        for (const c of [canary, canaryBin, canaryTmp, "/g2-canary-tmpdir.txt"]) expect.soft(pathsOf(label), `the ${c} canary was not found: that root is not searched`).toContain(c);
      }

      // #10455 PR 1a CTO ruling: the readable CLI state in the shared HOME is a DOCUMENTED RESIDUAL (not relocated; ADR-075 addendum).
      // Required members must still be readable (else the measurement has gone vacuous) and nothing outside required + optional may
      // be: a CLI upgrade that adds a file fails here and forces a review. Optional members depend on CLI startup/backup timing.
      // Relocation is triggered by: a readable file shown to hold a credential, prompt or tool output; a demonstrated peer-key use from
      // inside the sandbox; or a messagingSocketPath B can see.
      const REQUIRED_HOME_STATE = [
        ".claude.json",
        ".claude/sessions/<pid>.<hash>.key",
        ".claude/sessions/<pid>.json",
        ".claude/shell-snapshots/snapshot-bash-<ts>-<id>.sh",
      ];
      const OPTIONAL_HOME_STATE = [".claude/.last-cleanup", ".claude/backups/.claude.json.backup.<ts>"];
      const readable = [...new Set((/^HOME_READABLE=(.*)$/m.exec(out)?.[1] ?? "").split(",").filter(Boolean))].sort();
      expect.soft(REQUIRED_HOME_STATE.filter((r) => !readable.includes(r)), "a required CLI state file is no longer readable: the pin is stale or the probe is blind").toEqual([]);
      expect.soft(
        readable.filter((r) => !REQUIRED_HOME_STATE.includes(r) && !OPTIONAL_HOME_STATE.includes(r)),
        "B can read a CLI state file that is not in the reviewed pin: review it, then update the pin and the ADR-075 addendum",
      ).toEqual([]);
      // The peer key is NOT demonstrated usable from B's view (usability is not measured here). Realized, not declared: B must not be able to SEE the recorded path.
      expect.soft(out, "B could see A's recorded messaging socket path").not.toMatch(/^SOCK_VISIBLE=/m);
      expect.soft(out).toMatch(new RegExp(`^SOCK_CHECKED=${socketPaths.length}$`, "m"));
      const deniedDirs = (sandboxB as { filesystem: { denyRead: string[] } }).filesystem.denyRead;
      for (const sp of socketPaths) {
        expect.soft(
          deniedDirs.some((d) => sp === d || sp.startsWith(`${d}/`)),
          `A's messaging socket ${sp} is outside every denied dir (secondary check; the probe above is the proof)`,
        ).toBe(true);
      }
      // The pinned scan set (the account state file plus the shell-snapshots, backups and sessions directories; .last-cleanup is not
      // scanned) may not hold a credential or a content marker, and A's workspace id may not be in the account state file (the CLI writes
      // it into sessions/*.json; that is the documented residual, and only the messaging socket path is read back by this test).
      // The scan must have actually read something.
      const readableHostFiles: string[] = [join(home, ".claude.json")];
      for (const dir of ["shell-snapshots", "backups", "sessions"]) {
        try {
          for (const f of readdirSync(join(home, ".claude", dir))) readableHostFiles.push(join(home, ".claude", dir, f));
        } catch {
          /* absent */
        }
      }
      const forbidden = [needle!, DECOY_KEY, DECOY_KEY.slice(-12), promptNeedle, toolNeedle];
      let scanned = 0;
      for (const f of readableHostFiles) {
        let body: string;
        try {
          body = readFileSync(f, "utf8");
        } catch {
          continue;
        }
        scanned += 1;
        for (const marker of forbidden) {
          expect.soft(body.includes(marker), `a B-readable CLI state file holds a tenant secret or content marker: ${f.replace(home, "$HOME")}`).toBe(false);
        }
        if (f === join(home, ".claude.json")) expect.soft(body.includes(IDS.a), "the account state file holds A's workspace id").toBe(false);
      }
      expect.soft(scanned, `the forbidden-marker scan read too few files to prove anything: ${readableHostFiles.map((f) => f.replace(home, "$HOME")).join(",")}`).toBeGreaterThanOrEqual(2); // the account state file plus at least one session file; backups and snapshots rotate
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
      G2_ARMS_RUN.add(perTenantTmp ? "per-tenant" : "control");
    } finally {
      stopA.abort();
      await sessionA.catch(() => undefined);
    }
  };

  it("per-tenant CLI temp: B cannot find or replay A's credential (A ran `env`); tokenless and wrong-credential requests return 407; the caller's own credential is live", () => scenario(true), 240_000);
  it("CONTROL: with a shared CLI temp (the pre-fix layout) the same scan finds A's credential and the replay is accepted", () => scenario(false), 240_000);

  it("floor: both arms ran to their last assertion (an emptied or deleted arm cannot pass vacuously)", () => {
    expect([...G2_ARMS_RUN].sort()).toEqual(["control", "per-tenant"]);
  });
});

// ---- #10455 (a): the AF_UNIX-deny variant through the real SDK ---------------------------------------------------
// The variant is selected per session by buildAgentEnv (flag ON, no egress) and loaded by the real shim. Every arm drives
// the REAL SDK with the REAL builders, so the selector, the config and the shim are the production chain. The flip-to-
// descope condition (ADR-075 addendum 2026-10-19) is "the variant breaks no-egress Bash": the first arm is that check.
const PERL_OK = process.platform === "linux" && spawnSync("sh", ["-c", "command -v perl"], { stdio: "ignore" }).status === 0;
const CURL_OK = process.platform === "linux" && spawnSync("sh", ["-c", "command -v curl"], { stdio: "ignore" }).status === 0;
const VARIANT_ARMS_RUN = new Set<string>();

describe.skipIf(!SANDBOX_OK || !PERL_OK)("the AF_UNIX-deny variant through the real SDK (#10455 a)", () => {
  let stub: AnthropicStub | undefined;
  let root: string;
  let own: string;
  let home: string;
  let shimDir: string;
  const savedPath = process.env.PATH;

  // One script, printed line by line; the tool_result is parsed. `curl` is optional (CURL_OK).
  const PROBE =
    `perl -e 'use Socket; ` +
    `socket(S, PF_UNIX, SOCK_STREAM, 0) ? print "unix=OK\\n" : print "unix=ERR:$!\\n"; ` +
    `socket(T, PF_INET, SOCK_STREAM, 0) ? print "inet=OK\\n" : print "inet=ERR:$!\\n"; ` +
    `socketpair(A, B, PF_UNIX, SOCK_STREAM, 0) ? print "pair=OK\\n" : print "pair=ERR:$!\\n";'; ` +
    `echo VARIANT_BASH_OK; ` +
    `if command -v curl >/dev/null; then ` +
    `P="\${https_proxy:-$HTTPS_PROXY}"; ` +
    `s=$(date +%s); out=$(curl -sS -m 20 -o /dev/null \${P:+-x "$P"} https://example.test/ 2>&1); rc=$?; e=$(date +%s); ` +
    `echo "curl_rc=$rc"; echo "curl_secs=$((e-s))"; echo "curl_out=$(printf '%s' "$out" | head -n1)"; fi`;

  beforeAll(async () => {
    root = realpathSync(mkdtempSync(join(tmpdir(), "sbx-unixdeny-")));
    own = join(root, "00000000-0000-0000-0000-000000000001");
    mkdirSync(own);
    home = realpathSync(mkdtempSync(join(tmpdir(), "sbx-unixdeny-home-")));
    shimDir = realpathSync(mkdtempSync(join(tmpdir(), "sbx-unixdeny-shim-")));
    writeFileSync(join(shimDir, "bwrap"), `#!/usr/bin/env bash\nexec ${JSON.stringify(BWRAP_SHIM)} "$@"\n`);
    spawnSync("chmod", ["+x", join(shimDir, "bwrap")], { stdio: "ignore" });
    stub = await startAnthropicStub(PROBE);
    scrubAmbientCliEnv();
    pointCliAtStub(stub.port, home, "decoy-api-key-sentinel");
    vi.stubEnv("WORKSPACES_ROOT", root);
    vi.stubEnv("C4_RENDER_STAGING_ROOT", `${root}-c4-staging`);
    vi.stubEnv("SOLEUR_BWRAP_REAL", "/usr/bin/bwrap");
    // The ambient selector (the base artifact) and the variant path the repo checkout provides (no /app here).
    vi.stubEnv("SOLEUR_BWRAP_SECCOMP_BPF", BWRAP_BPF);
    vi.stubEnv("SOLEUR_BWRAP_SECCOMP_BPF_UNIXDENY", BWRAP_BPF_UNIXDENY);
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

  const field = (out: string, key: string): string | undefined => new RegExp(`^${key}=(.*)$`, "m").exec(out)?.[1];

  /** Runs the probe the way the dispatcher builds a session: env AND sandbox from the production builders. */
  const arm = async (label: string, session: { egress: boolean; flag: boolean }) => {
    const env = buildAgentEnv({ value: "decoy-api-key-sentinel", scheme: "api_key" }, {}, {
      ...(session.egress ? { ghToken: "ghs_decoy" } : {}),
      sandboxUnixDeny: session.flag,
    });
    const sandbox = buildAgentSandboxConfig(own, { allowGithubEgress: session.egress, sandboxUnixDeny: session.flag });
    expect(checkSeccompAgreement(env, sandbox), `${label}: env and sandbox must agree`).toBeNull();
    const result = await runBash({
      stubPort: stub!.port,
      home,
      cwd: own,
      sandbox,
      // buildAgentEnv's selector (when it sets one) beats the ambient stub; otherwise the ambient base applies.
      env: env.SOLEUR_BWRAP_SECCOMP_BPF ? { SOLEUR_BWRAP_SECCOMP_BPF: env.SOLEUR_BWRAP_SECCOMP_BPF } : {},
    });
    VARIANT_ARMS_RUN.add(label);
    expect(result, `${label}: no Bash tool_result came back`).not.toBeNull();
    return { result: result!, env };
  };

  it("NO-EGRESS + flag ON: Bash still starts, socket(AF_UNIX) is EPERM, AF_INET sockets and socketpair(AF_UNIX) work, curl fails", async () => {
    const { result, env } = await arm("no-egress-on", { egress: false, flag: true });
    expect(env.SOLEUR_BWRAP_SECCOMP_BPF, "the builder did not select the variant").toBe(BWRAP_BPF_UNIXDENY);
    const out = result.content;
    expect(result.isError, out).toBe(false);
    expect(out, "Bash did not start under the variant (the descope condition)").toContain("VARIANT_BASH_OK");
    expect(field(out, "unix")).toMatch(/^ERR:Operation not permitted$/);
    expect(field(out, "inet")).toBe("OK");
    expect(field(out, "pair")).toBe("OK");
    if (CURL_OK) {
      // Measured 2026-10-19 (curl 8, vendored SDK 0.3.284): the in-sandbox socat bridge cannot create its AF_UNIX
      // client, so the proxy is never reached: "Proxy CONNECT aborted", not an HTTP status from the proxy.
      expect(field(out, "curl_out"), `the proxy answered through the bridge under the variant:\n${out}`).not.toMatch(
        /CONNECT tunnel failed, response \d{3}/,
      );
      expect(Number(field(out, "curl_rc")), `curl should fail:\n${out}`).not.toBe(0);
      expect(Number(field(out, "curl_secs")), "curl must fail fast, not hang").toBeLessThan(15);
    }
  }, 180_000);

  it("NO-EGRESS + flag OFF: the base artifact, AF_UNIX works (today's posture)", async () => {
    const { result, env } = await arm("no-egress-off", { egress: false, flag: false });
    expect(env.SOLEUR_BWRAP_SECCOMP_BPF).toBe(BWRAP_BPF); // the ambient value, passed through unchanged
    const out = result.content;
    expect(result.isError, out).toBe(false);
    expect(out).toContain("VARIANT_BASH_OK");
    expect(field(out, "unix")).toBe("OK");
    expect(field(out, "pair")).toBe("OK");
    if (CURL_OK) {
      // Control for the variant arm's curl assertion: under the base artifact the bridge works and the proxy answers
      // (an HTTP status for the refused host), so the variant arm's "aborted" is attributable to the AF_UNIX deny.
      expect(field(out, "curl_out")).toMatch(/CONNECT tunnel failed, response \d{3}/);
    }
  }, 180_000);

  it("EGRESS + flag ON: the base artifact stays, AF_UNIX works and the in-sandbox proxy bridge answers", async () => {
    const { result, env } = await arm("egress-on", { egress: true, flag: true });
    expect(env.SOLEUR_BWRAP_SECCOMP_BPF).toBe(BWRAP_BPF);
    const out = result.content;
    expect(result.isError, out).toBe(false);
    expect(out).toContain("VARIANT_BASH_OK");
    expect(field(out, "unix")).toBe("OK");
    if (CURL_OK) {
      // The bridge reaches the proxy: the proxy refuses the non-allowlisted host with a status, rather than the connection
      // being refused at the bridge (which is what a socket(AF_UNIX) deny would produce).
      expect(field(out, "curl_out"), `the proxy did not answer through the bridge:\n${out}`).toMatch(/CONNECT tunnel failed, response \d{3}/);
    }
  }, 180_000);

  it("floor: every arm ran (a skipped describe, or a filtered run, cannot pass vacuously)", () => {
    expect([...VARIANT_ARMS_RUN].sort()).toEqual(["egress-on", "no-egress-off", "no-egress-on"]);
  });
});
if (process.platform === "linux" && process.env.C4_BWRAP_REQUIRED && !PERL_OK) {
  throw new Error("C4_BWRAP_REQUIRED is set but perl is not on PATH, so the AF_UNIX variant arms would be skipped.");
}
