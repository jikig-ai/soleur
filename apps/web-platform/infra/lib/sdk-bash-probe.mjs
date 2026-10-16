// One scripted Bash turn through the REAL Agent SDK (query()), a local stand-in for the Messages API, and
// whatever `bwrap` the PATH resolves (the shim, in the suite container). It exists so the docker suite
// (infra/sandbox-masked-proc-docker.test.sh) can observe, under the production run tuple, what a hosted Bash
// call returns with and without `network.allowAllUnixSockets` (#10445). No model, no network, no credential.
//
// Env (all set by the suite): APP (app root, for the SDK), KNOB (0|1), CMD (the Bash command).
// Prints exactly one line: SDK_BASH_RESULT {"isError":bool,"content":"..."} — or SDK_BASH_RESULT {"error":"..."}.
// The sandbox object is a literal carrying the fields that matter to the wrapper (the production builder is
// TypeScript and is not in the suite image); test/sandbox-wrapped-command-runtime.test.ts drives the real builder.
import http from "node:http";
import { createRequire } from "node:module";
import { mkdirSync, mkdtempSync, rmSync } from "node:fs";

const APP = process.env.APP;
const KNOB = process.env.KNOB === "1";
const CMD = process.env.CMD ?? "echo SMOKE_OK_10445";
const require = createRequire(`${APP}/package.json`);
const { query } = await import(require.resolve("@anthropic-ai/claude-agent-sdk"));

function sse(res, events) {
  res.writeHead(200, { "content-type": "text/event-stream", "cache-control": "no-cache" });
  for (const [ev, data] of events) res.write(`event: ${ev}\ndata: ${JSON.stringify(data)}\n\n`);
  res.end();
}
const server = http.createServer((req, res) => {
  let body = "";
  req.on("data", (c) => (body += c));
  req.on("end", () => {
    let j = {};
    try { j = JSON.parse(body || "{}"); } catch { /* plain-text answer */ }
    if (!req.url.startsWith("/v1/messages")) { res.writeHead(404); res.end("{}"); return; }
    if (!j.stream) {
      res.writeHead(200, { "content-type": "application/json" });
      res.end(JSON.stringify({ id: "m", type: "message", role: "assistant", model: "stub", content: [{ type: "text", text: "x" }], stop_reason: "end_turn", usage: { input_tokens: 1, output_tokens: 1 } }));
      return;
    }
    const start = { type: "message_start", message: { id: "msg", type: "message", role: "assistant", model: j.model || "stub", content: [], stop_reason: null, usage: { input_tokens: 1, output_tokens: 1 } } };
    const toolTurn = !JSON.stringify(j.messages || []).includes("tool_result");
    if (toolTurn) {
      sse(res, [["message_start", start],
        ["content_block_start", { type: "content_block_start", index: 0, content_block: { type: "tool_use", id: "toolu_1", name: "Bash", input: {} } }],
        ["content_block_delta", { type: "content_block_delta", index: 0, delta: { type: "input_json_delta", partial_json: JSON.stringify({ command: CMD }) } }],
        ["content_block_stop", { type: "content_block_stop", index: 0 }],
        ["message_delta", { type: "message_delta", delta: { stop_reason: "tool_use", stop_sequence: null }, usage: { output_tokens: 5 } }],
        ["message_stop", { type: "message_stop" }]]);
    } else {
      sse(res, [["message_start", start],
        ["content_block_start", { type: "content_block_start", index: 0, content_block: { type: "text", text: "" } }],
        ["content_block_delta", { type: "content_block_delta", index: 0, delta: { type: "text_delta", text: "done" } }],
        ["content_block_stop", { type: "content_block_stop", index: 0 }],
        ["message_delta", { type: "message_delta", delta: { stop_reason: "end_turn", stop_sequence: null }, usage: { output_tokens: 1 } }],
        ["message_stop", { type: "message_stop" }]]);
    }
  });
});
await new Promise((r) => server.listen(0, "127.0.0.1", r));
const port = server.address().port;

const ws = mkdtempSync(`${process.env.TMPDIR || "/tmp"}/sdk-bash-probe-`);
// The peer-messaging socket dir is masked for every production session and must exist before the namespace is
// built (the SDK skips a deny landing that does not). Parity with the production deny list is pinned by
// test/sandbox-wrapped-command-runtime.test.ts.
mkdirSync("/tmp/cc-socks", { recursive: true, mode: 0o700 });
const sandbox = {
  enabled: true, failIfUnavailable: true, autoAllowBashIfSandboxed: true, allowUnsandboxedCommands: false, enableWeakerNestedSandbox: true,
  network: { allowedDomains: [], allowManagedDomainsOnly: true, ...(KNOB ? { allowAllUnixSockets: true } : {}) },
  filesystem: { allowWrite: [ws], denyRead: ["/proc", "/sys", "/tmp/cc-socks"] },
};
const env = { ...process.env, ANTHROPIC_API_KEY: "decoy-api-key-sentinel", ANTHROPIC_BASE_URL: `http://127.0.0.1:${port}`, CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: "1", DISABLE_TELEMETRY: "1", DISABLE_AUTOUPDATER: "1" };
const timer = setTimeout(() => { console.log('SDK_BASH_RESULT {"error":"timeout"}'); process.exit(3); }, 120000);
let found = null;
let err = "";
try {
  const q = query({ prompt: "run it", options: { cwd: ws, env, sandbox, allowedTools: ["Bash"], permissionMode: "bypassPermissions", allowDangerouslySkipPermissions: true, maxTurns: 3, model: "claude-haiku-4-5-20251001", settingSources: [] } });
  for await (const m of q) {
    if (m.type !== "user" || !Array.isArray(m.message?.content)) continue;
    for (const b of m.message.content) {
      if (b.type !== "tool_result") continue;
      const text = typeof b.content === "string" ? b.content : Array.isArray(b.content) ? b.content.map((c) => c.text ?? "").join("") : "";
      found = { isError: b.is_error === true, content: text };
    }
  }
} catch (e) { err = String(e).slice(0, 300); }
clearTimeout(timer);
// The scratch workspace is this probe's own; remove it so repeated runs do not accumulate directories.
try { rmSync(ws, { recursive: true, force: true }); } catch { /* best-effort scratch cleanup */ }
console.log(`SDK_BASH_RESULT ${JSON.stringify(found ?? { error: err || "no tool_result" })}`);
server.close();
process.exit(0);
