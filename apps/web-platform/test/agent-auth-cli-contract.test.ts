// @vitest-environment node
import { describe, it, expect, beforeAll, afterAll } from "vitest";
import { spawn } from "node:child_process";
import { existsSync, mkdtempSync, rmSync } from "node:fs";
import http from "node:http";
import { tmpdir } from "node:os";
import path from "node:path";
import { connect } from "node:net";

import { OAUTH_ENV_VAR } from "@/server/agent-auth-env-vars";
import { classifyCliDroppedValue } from "@/server/oauth-token-shape";

// Bundled-binary contract for #11086: the Claude CLI that the Agent SDK ships silently DROPS a subscription-token value
// that is not shaped like a real one, then replies "Not logged in · Please run /login". The lease boundary
// (server/oauth-token-shape.ts classifyCliDroppedValue) and the write boundary (the strict allowlist) are derived from
// the table measured here. RE-DERIVE ON EVERY SDK BUMP: this test is the tripwire.
//
// What was measured (SDK 0.3.284, CLI 2.1.284, linux-x64), default base URL:
//   - sk-ant-api03-.., sk-ant-admin01-.., "sk-ant-oat01-.. BBBB" in the credential variable: reply is exactly the
//     not-logged-in line, apiKeySource "none". The value is dropped, not sent as a credential.
//   - blank/whitespace value: same reply, answered with no inference request (/v1/messages) at all.
//   - valid-shaped sk-ant-oat01-<fake>: the value is USED, so the reply is the API's own auth failure
//     ("Failed to authenticate. API Error: 401 ..."), never the not-logged-in line.
//
// Deviations from a pure "offline" arm, measured while writing this:
//   - Only the blank class is answered without an inference request. The other dropped classes make an unauthenticated API call
//     (the CLI emits api_retry events) and render the 401 as the not-logged-in line, so those arms need egress to the
//     real API host. They are guarded by a reachability probe: no egress => visible skip (even in CI, so a network flake cannot wedge the
//     merge gate); an ABSENT BINARY is the hard CI failure, and the offline blank/stub arms still run.
//   - A loopback ANTHROPIC_BASE_URL stub CANNOT discriminate dropped from used values: with a non-default base URL the
//     CLI sends every non-blank value as a bearer token (a "dropped" api03 value reaches the stub too). The stub is
//     therefore used only to prove, offline, that a valid-shaped value is actually SENT as the credential
//     (the stub observes a request carrying it), not to prove the dropped classes are dropped.
//
// Harness-validity guards (mutation concern): every spawn must emit a real `system`/`init` stream message with a
// string claude_code_version, and its `apiKeySource` is read from that message. A harness that "passes" because the
// binary never ran (or printed something else) fails on those assertions rather than on the reply text.
//
// Only synthesized fake credentials appear here. The variable name comes from the shared names module on purpose.

const ROOT = path.join(__dirname, "..");
const NOT_LOGGED_IN = "Not logged in · Please run /login";
const SPAWN_TIMEOUT_MS = 15_000;
const TEST_TIMEOUT_MS = 30_000;
const API_HOST = "api.anthropic.com";

const CANDIDATE_BINARIES = [
  `@anthropic-ai/claude-agent-sdk-${process.platform}-${process.arch}`,
  `@anthropic-ai/claude-agent-sdk-${process.platform}-${process.arch}-musl`,
].map((pkg) => path.join(ROOT, "node_modules", pkg, process.platform === "win32" ? "claude.exe" : "claude"));
const BIN = CANDIDATE_BINARIES.find((p) => existsSync(p));
const IN_CI = Boolean(process.env.CI);

interface CliRun {
  timedOut: boolean;
  init: { apiKeySource?: string; claude_code_version?: string } | null;
  assistantText: string | null;
  resultText: string | null;
  messageTypes: string[];
}

function runCli(binary: string, credential: string, extraEnv: Record<string, string> = {}): Promise<CliRun> {
  const home = mkdtempSync(path.join(tmpdir(), "cli-contract-"));
  // Equivalent of `env -i`: the child gets ONLY these variables.
  // Telemetry and non-essential traffic are switched off so a run sends only what the credential check itself needs.
  const env = {
    HOME: home,
    PATH: "/usr/bin:/bin",
    [OAUTH_ENV_VAR]: credential,
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: "1",
    DISABLE_TELEMETRY: "1",
    ...extraEnv,
  } as unknown as NodeJS.ProcessEnv;
  return new Promise((resolve, reject) => {
    const child = spawn(
      binary,
      ["-p", "hi", "--output-format", "stream-json", "--verbose", "--input-format", "text"],
      { env, cwd: home, stdio: ["ignore", "pipe", "pipe"] },
    );
    let out = "";
    let timedOut = false;
    child.stdout.on("data", (d) => (out += d));
    child.stderr.on("data", () => {});
    const timer = setTimeout(() => {
      timedOut = true;
      child.kill("SIGKILL");
    }, SPAWN_TIMEOUT_MS);
    child.on("error", (e) => {
      clearTimeout(timer);
      rmSync(home, { recursive: true, force: true });
      reject(e);
    });
    child.on("close", () => {
      clearTimeout(timer);
      rmSync(home, { recursive: true, force: true });
      const run: CliRun = { timedOut, init: null, assistantText: null, resultText: null, messageTypes: [] };
      for (const line of out.split("\n")) {
        if (!line.trim()) continue;
        let m: any;
        try {
          m = JSON.parse(line);
        } catch {
          continue;
        }
        run.messageTypes.push(`${m.type}${m.subtype ? `/${m.subtype}` : ""}`);
        if (m.type === "system" && m.subtype === "init") run.init = m;
        if (m.type === "assistant" && Array.isArray(m.message?.content)) {
          const t = m.message.content.find((c: any) => c?.type === "text");
          if (t) run.assistantText = t.text;
        }
        if (m.type === "result" && typeof m.result === "string") run.resultText = m.result;
      }
      resolve(run);
    });
  });
}

function expectRealRun(run: CliRun) {
  expect(run.timedOut, `CLI did not finish in ${SPAWN_TIMEOUT_MS} ms (seen: ${run.messageTypes.join(",")})`).toBe(false);
  // The binary really ran: a genuine init message, with a version and a readable apiKeySource.
  expect(run.init, "no system/init message: the binary did not run").not.toBeNull();
  expect(typeof run.init?.claude_code_version).toBe("string");
  expect(typeof run.init?.apiKeySource).toBe("string");
}

function canReachApiHost(): Promise<boolean> {
  return new Promise((resolve) => {
    const sock = connect({ host: API_HOST, port: 443, timeout: 3_000 });
    const done = (ok: boolean) => {
      sock.destroy();
      resolve(ok);
    };
    sock.on("connect", () => done(true));
    sock.on("timeout", () => done(false));
    sock.on("error", () => done(false));
  });
}

describe("bundled CLI credential-shape contract (#11086)", () => {
  if (!BIN) {
    const reason = `bundled Claude CLI binary not found (looked for: ${CANDIDATE_BINARIES.join(", ")})`;
    if (IN_CI) {
      it("the bundled CLI binary is installed (CI: hard fail)", () => {
        throw new Error(`${reason}. CI must not skip the contract test; run npm ci with optional dependencies.`);
      });
    } else {
      console.warn(`[agent-auth-cli-contract] SKIPPED: ${reason}`);
      it.skip(`skipped locally: ${reason}`, () => {});
    }
    return;
  }
  const binary = BIN;

  let egress = false;
  beforeAll(async () => {
    egress = await canReachApiHost();
    if (!egress) console.warn(`[agent-auth-cli-contract] no egress to ${API_HOST}: network-dependent arms skipped`);
  }, 10_000);

  // Blank is answered locally by the CLI with no API request, so it is deterministic offline.
  it(
    "blank value: not-logged-in reply, no network required",
    async () => {
      const run = await runCli(binary, " ");
      expectRealRun(run);
      expect(run.assistantText).toBe(NOT_LOGGED_IN);
      expect(run.resultText).toBe(NOT_LOGGED_IN);
      expect(classifyCliDroppedValue(" ")).toBe("blank");
    },
    TEST_TIMEOUT_MS,
  );

  const DROPPED: Array<[string, string]> = [
    ["api key shaped (api03)", "sk-ant-api03-AAAA"],
    ["admin key shaped", "sk-ant-admin01-AAAA"],
    ["embedded whitespace", "sk-ant-oat01-AAAA BBBB"],
  ];

  it("offline drift tripwire: the lease classifier claims every value measured to be dropped, and no valid-shaped one", () => {
    // Does not depend on egress, so the classifier table cannot silently rot when the network arms below skip.
    for (const [, value] of DROPPED) expect(classifyCliDroppedValue(value), value).not.toBeNull();
    expect(classifyCliDroppedValue("sk-ant-oat01-FAKEfake_0123456789-abcdef")).toBeNull();
  });

  describe.each(DROPPED)("dropped class: %s", (_label, value) => {
    it(
      "the CLI replies exactly the not-logged-in line, and the lease classifier claims the value",
      async (ctx) => {
        if (!egress) {
          // A network flake must not wedge the required merge gate: skip visibly (the warn above names the reason).
          // The hard CI assertion is the binary-presence check, which is what makes the offline arms real.
          ctx.skip();
        }
        const run = await runCli(binary, value);
        expectRealRun(run);
        expect(run.assistantText).toBe(NOT_LOGGED_IN);
        expect(run.resultText).toBe(NOT_LOGGED_IN);
        // Drift tripwire: the negative predicate must cover every value measured to be dropped.
        expect(classifyCliDroppedValue(value)).not.toBeNull();
      },
      TEST_TIMEOUT_MS,
    );
  });

  describe("valid-shaped value is used", () => {
    const VALID = "sk-ant-oat01-FAKEfake_0123456789-abcdef";

    it(
      "default base URL: the reply is not the not-logged-in line",
      async (ctx) => {
        if (!egress) {
          // A network flake must not wedge the required merge gate: skip visibly (the warn above names the reason).
          // The hard CI assertion is the binary-presence check, which is what makes the offline arms real.
          ctx.skip();
        }
        const run = await runCli(binary, VALID);
        expectRealRun(run);
        // A real reply, not a missing one (a null would satisfy a bare `not.toBe`).
        expect(run.assistantText).toMatch(/Failed to authenticate|API Error/);
        expect(run.assistantText).not.toBe(NOT_LOGGED_IN);
        expect(run.resultText).not.toBe(NOT_LOGGED_IN);
        expect(classifyCliDroppedValue(VALID)).toBeNull();
      },
      TEST_TIMEOUT_MS,
    );

    describe("loopback stub", () => {
      const seen: Array<{ url: string; authorization: string | undefined }> = [];
      let server: http.Server;
      let baseUrl = "";
      beforeAll(async () => {
        server = http.createServer((req, res) => {
          req.resume();
          req.on("end", () => {
            seen.push({ url: req.url ?? "", authorization: req.headers.authorization });
            res.writeHead(401, { "content-type": "application/json" });
            res.end(JSON.stringify({ type: "error", error: { type: "authentication_error", message: "stub" } }));
          });
        });
        await new Promise<void>((r) => server.listen(0, "127.0.0.1", r));
        baseUrl = `http://127.0.0.1:${(server.address() as import("node:net").AddressInfo).port}`;
      });
      afterAll(() => new Promise<void>((r) => server.close(() => r())));

      it(
        "the stub observes a request carrying the valid-shaped value as its credential",
        async () => {
          seen.length = 0;
          const run = await runCli(binary, VALID, { ANTHROPIC_BASE_URL: baseUrl });
          expectRealRun(run);
          expect(run.assistantText).not.toBe(NOT_LOGGED_IN);
          const messages = seen.filter((r) => r.url.startsWith("/v1/messages"));
          expect(messages.length, "stub saw no API request: the value was not used").toBeGreaterThan(0);
          expect(messages[0].authorization).toBe(`Bearer ${VALID}`);
        },
        TEST_TIMEOUT_MS,
      );
    });
  });
});
