// Egress injector spike (#12517): the SDK egress driver. Test path only. Runs INSIDE the app container, outside
// bwrap, as the app uid, under tsx so it can call the real server builders:
//
//   tsx --tsconfig /app/tsconfig.json /app/test/infra/egress-injector-spike/probes/sdk-egress-driver.mts <spec.json>
//
// It builds the session's sandbox with the production `buildAgentSandboxConfig(workspace, { allowWebEgress: true,
// denyReadExtra })` and its env with the production `buildAgentEnv(..., { egressProxy })`, pointed at the session's
// connect-router instead of the forwarder (the router takes the forwarder's place in front of the sandbox). Arm "A"
// keeps that env as is; arm "B" removes the four inject hosts from NO_PROXY (CTO R11; a production change #11637
// owns); arm "N" is an unentitled session (no egressProxy, no allowWebEgress, WebFetch disallowed as production does). The CA bundle variables are added on top (SSL_CERT_FILE, GIT_SSL_CAINFO, NODE_EXTRA_CA_CERTS).
//
// The model is kept out of the assertion path: an in-process stub Messages API plays the spec's `script` (one
// scripted tool call per turn: Bash, Read or WebFetch) and captures each tool result from the next request.
// Permissions follow production (agent-runner-query-options.ts, permission-callback.ts): permissionMode "default",
// no bare allowedTools (the SDK auto-approves a bare entry before canUseTool runs; measured 2026-11-10 as the
// CLAUDE_SDK_CAN_USE_TOOL_SHADOWED warning), disallowedTools ["WebSearch"] (the web-egress set), and a canUseTool
// whose file-tool branch is production's layer-2 containment, built from the same exported predicates
// (isFileTool, pathFieldsEscape + isPathInWorkspace, patternEscapesWorkspace). Production's other canUseTool gates
// (Bash approval, platform tools) and its PreToolUse hooks are not reproduced: every other tool is allowed, so a
// refusal recorded here comes from the sandbox or from the file-tool containment, never from a missing gate.
//
// spec.json: { workspace, home, routerPort, routerCredentialFile, caBundle, arm: "A"|"B", denyReadExtra: [..],
//              script: [{ id, tool: "Bash"|"Read"|"WebFetch", input: {...} }], declaredFiles: [{ id, file }],
//              timeoutMs }
// Output: exactly one line `SDK_EGRESS_RESULT <json>` with { arm, env: {proxy vars present, NO_PROXY}, steps: [{id,
// tool, isError, content, hits}] }. Every declared secret value is replaced by `<declared:ID>` in `content` and
// reported in `hits` (Guard 1 records surfaces by id, never by value). Exit 0 unless the driver itself failed.
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import http from "node:http";
import { createRequire } from "node:module";

import { buildAgentEnv } from "/app/server/agent-env.ts";
import { buildAgentSandboxConfig } from "/app/server/agent-runner-sandbox-config.ts";
import { isPathInWorkspace } from "/app/server/sandbox.ts";
import { isFileTool, pathFieldsEscape } from "/app/server/tool-path-checker.ts";
import { patternEscapesWorkspace } from "/app/server/tool-pattern-checker.ts";

type Step = { id: string; tool: "Bash" | "Read" | "WebFetch"; input: Record<string, unknown> };
type Spec = {
  workspace: string; home: string; routerPort: number; routerCredentialFile: string; caBundle: string;
  arm: "A" | "B" | "N"; denyReadExtra: string[]; script: Step[]; timeoutMs?: number;
  // transform: "pem-body" declares the longest base64 line of a PEM (a leak rarely carries the armour lines);
  // "basic-b64" declares base64("x-access-token:" + value), the form git carries.
  declaredFiles: { id: string; file: string; transform?: "pem-body" | "basic-b64" }[];
  // A control string the driver writes into the workspace before the run; the scan must find it (Guard 1 row 2).
  planted?: { id: string; value: string; path: string };
  // Files a sandboxed step wrote with everything it observed; scanned IN FULL after the run (tool output reaching
  // the model is truncated, so a scan of tool results alone would silently drop coverage; Guard 1 row 3).
  scanFiles?: string[];
  // Recorded-only control (CTO R34): answer every SandboxNetworkAccess request with allow.
  networkAllowAll?: boolean;
  // CTO R30: the CLI's OWN Messages API traffic under production's env. No in-process stub and no
  // ANTHROPIC_BASE_URL, so the CLI reaches api.anthropic.com however production's env sends it; one tool-less query,
  // counting the streamed text deltas.
  streaming?: boolean;
};

const DRIVER_TOOLS = new Set(["Bash", "Read", "WebFetch"]);

/** NO_PROXY semantics for a host: an exact entry, or a `*.suffix` / `.suffix` entry covering it (R34). */
export function noProxyMatches(host: string, noProxy: string): boolean {
  for (const raw of noProxy.split(",")) {
    const e = raw.trim().toLowerCase();
    if (!e) continue;
    if (e === host) return true;
    const suffix = e.startsWith("*.") ? e.slice(1) : e.startsWith(".") ? e : null;
    if (suffix && host.endsWith(suffix)) return true;
  }
  return false;
}
const INJECT_HOSTS = ["github.com", "api.github.com", "uploads.github.com", "codeload.github.com"];
const out = (o: unknown) => process.stdout.write(`SDK_EGRESS_RESULT ${JSON.stringify(o)}\n`);

function sse(res: http.ServerResponse, events: [string, unknown][]) {
  res.writeHead(200, { "content-type": "text/event-stream", "cache-control": "no-cache" });
  for (const [ev, data] of events) res.write(`event: ${ev}\ndata: ${JSON.stringify(data)}\n\n`);
  res.end();
}

const textOf = (b: any): string =>
  typeof b?.content === "string" ? b.content : Array.isArray(b?.content) ? b.content.map((c: any) => c?.text ?? "").join("") : "";

function startStub(script: Step[], results: Map<string, { isError: boolean; content: string }>) {
  return http.createServer((req, res) => {
    let body = "";
    req.on("data", (c) => (body += c));
    req.on("end", () => {
      let j: any = {};
      try { j = JSON.parse(body || "{}"); } catch { /* plain answer below */ }
      if (!String(req.url).startsWith("/v1/messages")) { res.writeHead(404); res.end("{}"); return; }
      // Capture every tool_result the CLI sends back, keyed by our tool_use id.
      for (const m of j.messages ?? []) {
        if (m?.role !== "user" || !Array.isArray(m.content)) continue;
        for (const b of m.content) if (b?.type === "tool_result" && !results.has(b.tool_use_id)) results.set(b.tool_use_id, { isError: b.is_error === true, content: textOf(b) });
      }
      const start = { type: "message_start", message: { id: "msg", type: "message", role: "assistant", model: j.model || "stub", content: [], stop_reason: null, usage: { input_tokens: 1, output_tokens: 1 } } };
      const text = (t: string) => sse(res, [["message_start", start],
        ["content_block_start", { type: "content_block_start", index: 0, content_block: { type: "text", text: "" } }],
        ["content_block_delta", { type: "content_block_delta", index: 0, delta: { type: "text_delta", text: t } }],
        ["content_block_stop", { type: "content_block_stop", index: 0 }],
        ["message_delta", { type: "message_delta", delta: { stop_reason: "end_turn", stop_sequence: null }, usage: { output_tokens: 1 } }],
        ["message_stop", { type: "message_stop" }]]);
      if (!j.stream) {
        res.writeHead(200, { "content-type": "application/json" });
        res.end(JSON.stringify({ id: "m", type: "message", role: "assistant", model: "stub", content: [{ type: "text", text: "x" }], stop_reason: "end_turn", usage: { input_tokens: 1, output_tokens: 1 } }));
        return;
      }
      // Only the main agent turn carries tools; a side call (WebFetch summarisation, title) gets text.
      const toolTurn = Array.isArray(j.tools) && j.tools.length > 0 && (j.max_tokens ?? 2) > 1;
      if (!toolTurn) return text("ok");
      const next = script.find((s) => !results.has(`toolu_${s.id}`));
      if (!next) return text("done");
      sse(res, [["message_start", start],
        ["content_block_start", { type: "content_block_start", index: 0, content_block: { type: "tool_use", id: `toolu_${next.id}`, name: next.tool, input: {} } }],
        ["content_block_delta", { type: "content_block_delta", index: 0, delta: { type: "input_json_delta", partial_json: JSON.stringify(next.input) } }],
        ["content_block_stop", { type: "content_block_stop", index: 0 }],
        ["message_delta", { type: "message_delta", delta: { stop_reason: "tool_use", stop_sequence: null }, usage: { output_tokens: 5 } }],
        ["message_stop", { type: "message_stop" }]]);
    });
  });
}

async function main() {
  const spec: Spec = JSON.parse(readFileSync(process.argv[2], "utf8"));
  const derive = (d: Spec["declaredFiles"][number]) => {
    const raw = readFileSync(d.file, "utf8").trim();
    if (d.transform === "pem-body") return raw.split("\n").filter((l) => !l.startsWith("-----")).sort((a, b) => b.length - a.length)[0] ?? "";
    if (d.transform === "basic-b64") return Buffer.from(`x-access-token:${raw}`).toString("base64");
    return raw;
  };
  const declared = spec.declaredFiles.map((d) => ({ id: d.id, value: derive(d) })).filter((d) => d.value.length >= 8);
  if (spec.planted) declared.push({ id: spec.planted.id, value: spec.planted.value });
  const redact = (s: string) => {
    let t = s;
    const hits: string[] = [];
    for (const d of declared) if (t.includes(d.value)) { hits.push(d.id); t = t.split(d.value).join(`<declared:${d.id}>`); }
    return { text: t.slice(0, 6000), hits };
  };
  mkdirSync(spec.workspace, { recursive: true, mode: 0o700 });
  mkdirSync(spec.home, { recursive: true, mode: 0o700 });
  const cfgDir = `${spec.home}/.spike-claude-config`;
  mkdirSync(cfgDir, { recursive: true, mode: 0o700 });
  process.env.HOME = spec.home;
  if (spec.planted) writeFileSync(spec.planted.path, `${spec.planted.value}\n`, { mode: 0o600 });

  // Arm "N" is an UNENTITLED session (criterion 6): no egress proxy and no web-egress sandbox posture.
  const entitled = spec.arm !== "N";
  // Entitled arms also carry allowGithubEgress: production derives it from the GitHub token a #11637 session holds
  // (CTO R34).
  const sandbox = buildAgentSandboxConfig(spec.workspace, { allowWebEgress: entitled, allowGithubEgress: entitled, denyReadExtra: spec.denyReadExtra });
  const routerPw = readFileSync(spec.routerCredentialFile, "utf8").trim().split(":").slice(1).join(":");
  // buildAgentEnv only exports CLAUDE_PLUGIN_ROOT and requires it under /app/; the spike loads no plugin from it.
  const pluginDir = "/app/test/infra/egress-injector-spike";
  const base = buildAgentEnv({ value: "decoy-api-key-sentinel", scheme: "api_key" }, {}, {
    ...(entitled ? { egressProxy: { workspaceId: "session", token: routerPw, port: spec.routerPort } } : {}), pluginPath: pluginDir,
  });
  const env: Record<string, string> = { ...base };
  if (spec.arm === "B") {
    env.NO_PROXY = String(env.NO_PROXY ?? "").split(",").filter((h) => !INJECT_HOSTS.includes(h) && h !== "*.github.com").join(",");
    env.no_proxy = env.NO_PROXY;
  }
  Object.assign(env, { SSL_CERT_FILE: spec.caBundle, GIT_SSL_CAINFO: spec.caBundle, NODE_EXTRA_CA_CERTS: spec.caBundle, CLAUDE_CONFIG_DIR: cfgDir });

  const results = new Map<string, { isError: boolean; content: string }>();
  const server = spec.streaming ? null : startStub(spec.script, results);
  if (server) {
    await new Promise<void>((r) => server.listen(0, "127.0.0.1", () => r()));
    env.ANTHROPIC_BASE_URL = `http://127.0.0.1:${(server.address() as { port: number }).port}`;
  } else {
    delete env.ANTHROPIC_BASE_URL;
  }
  let deltas = 0;
  // Every permission request the SDK raised, by tool name (a network request outside the sandbox's allowlist
  // reaches canUseTool too; recording them shows which decisions came from the callback rather than the sandbox).
  const permissionCalls: string[] = [];
  const networkDecisions: { host: string; decision: string }[] = [];
  const stderrTls: string[] = [];

  const require = createRequire("/app/package.json");
  const { query } = await import(require.resolve("@anthropic-ai/claude-agent-sdk"));
  const controller = new AbortController();
  let thrown = "";
  const timer = setTimeout(() => controller.abort(), spec.timeoutMs ?? 240_000);
  try {
    const q = query({
      prompt: "run the scripted steps",
      options: {
        abortController: controller, cwd: spec.workspace, env, sandbox,
        permissionMode: "default", disallowedTools: entitled ? ["WebSearch"] : ["WebSearch", "WebFetch"],
        canUseTool: async (name: string, input: Record<string, unknown>) => {
          permissionCalls.push(`${name} ${redact(JSON.stringify(input)).text.slice(0, 160)}`);
          // CTO R34: the SDK raises SandboxNetworkAccess for every host outside the sandbox's allowedDomains.
          // Production's callback has no arm for it and denies it as an unknown tool (#11637 owns the change). The
          // driver answers as that change would have to: deny for an unentitled session; for an entitled one, deny a
          // host the session's NO_PROXY matches (it would go direct, e.g. to the app container's loopback) and allow
          // any other host, so the gateway or the injector is the policy boundary. IP literals not in NO_PROXY are
          // allowed, so squid's deny list is what refuses them.
          if (name === "SandboxNetworkAccess") {
            const host = String((input as { host?: unknown })?.host ?? "").toLowerCase().replace(/\.$/, "");
            const allow = spec.networkAllowAll === true || (entitled && !noProxyMatches(host, String(env.NO_PROXY ?? "")));
            networkDecisions.push({ host, decision: allow ? "allow" : "deny" });
            return allow ? { behavior: "allow", updatedInput: input } : { behavior: "deny", message: "network access denied" };
          }
          if (isFileTool(name) && (pathFieldsEscape(input, (p: string) => isPathInWorkspace(p, spec.workspace)) || patternEscapesWorkspace(name, input))) {
            return { behavior: "deny", message: "Access denied: outside workspace" };
          }
          // Production's createCanUseTool ends deny-by-default ("block unrecognized tools", permission-callback.ts);
          // the SDK's SandboxNetworkAccess request is one such name (measured 2026-11-10: allowing it gave an
          // unentitled session a route). Only the tools these probes script are allowed.
          if (!DRIVER_TOOLS.has(name)) return { behavior: "deny", message: "unrecognized tool" };
          return { behavior: "allow", updatedInput: input };
        },
        maxTurns: spec.streaming ? 1 : spec.script.length + 2, model: "claude-haiku-5-5", settingSources: [],
        includePartialMessages: true,
        stderr: (line: string) => { if (/certif|NODE_EXTRA_CA|tls|ssl/i.test(line) && stderrTls.length < 20) stderrTls.push(redact(line).text.slice(0, 200)); },
      },
    });
    for await (const m of q as AsyncIterable<any>) {
      if (m?.type === "stream_event" && m.event?.type === "content_block_delta") deltas += 1;
    }
  } catch (e) {
    thrown = String(e).slice(0, 300);
  } finally {
    clearTimeout(timer);
    controller.abort();
    server?.close();
  }
  const steps: any[] = spec.script.map((s) => {
    const r = results.get(`toolu_${s.id}`);
    if (!r) return { id: s.id, tool: s.tool, isError: null, content: null, hits: [] };
    const { text, hits } = redact(r.content);
    return { id: s.id, tool: s.tool, isError: r.isError, content: text, hits };
  });
  for (const f of spec.scanFiles ?? []) {
    let text = "";
    let readable = true;
    try { text = readFileSync(f, "utf8"); } catch { readable = false; }
    const hits = declared.filter((d) => text.includes(d.value)).map((d) => d.id);
    steps.push({ id: `scan:${f}`, tool: "Bash", isError: !readable, content: `bytes=${Buffer.byteLength(text)} readable=${readable}`, hits });
  }
  const envSummary = { noProxy: env.NO_PROXY, proxyVars: ["HTTP_PROXY", "HTTPS_PROXY", "http_proxy", "https_proxy"].filter((k) => env[k]) };
  out({ arm: spec.arm, env: envSummary, thrown: redact(thrown).text, steps, permissionCalls: permissionCalls.slice(0, 40), networkDecisions, ...(spec.streaming ? { streaming: { deltas, stderrTls } } : {}) });
  process.exit(0);
}

main().catch((e) => { out({ error: String(e).slice(0, 300) }); process.exit(1); });
