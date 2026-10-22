// One scripted Bash turn through the REAL Agent SDK (query()), a local stand-in for the Messages API, and
// whatever `bwrap` the PATH resolves (the shim, in the suite and production images). No model, no network, no real
// credential. Two modes, one file (the production image has no TypeScript sources, so the probe is plain ESM):
//
//   runtime (SMOKE=1 and SDK_BASH_PROBE_RUNTIME=1)  The runtime Bash synthetic (infra/web-bash-synthetic.sh, ADR-079 addendum
//                          2026-10-20) in the RUNNING production container. Same verdict function and result contract as the
//                          deploy smoke, with three differences: the seccomp artifact comes from SDK_BASH_PROBE_SELECTOR (the
//                          host asked the dispatcher's own resolver, so the synthetic tests what production would select now),
//                          coverage names THAT artifact, and nothing is created outside the probe's own scratch dirs (the
//                          masked dirs belong to real sessions: the ones that exist are masked, the rest are counted in the
//                          result as masks_missing).
//
//   default (SMOKE unset)  The docker suite's control/treatment probe (infra/sandbox-masked-proc-docker.test.sh):
//                          observes, under the production run tuple, what a hosted Bash call returns with and
//                          without `network.allowAllUnixSockets` (#10445).
//                          Env (set by the suite): APP (app root, for the SDK), KNOB (0|1), CMD (the Bash command).
//                          Prints exactly one line: SDK_BASH_RESULT {"isError":bool,"content":"..."} — or
//                          SDK_BASH_RESULT {"error":"..."}.
//
//   smoke   (SMOKE=1)      The deploy-time SDK Bash smoke (#10453, ADR-079 addendum): ci-deploy.sh execs this inside the
//                          CANARY container under `/usr/bin/env -i` with an explicit allowlist. The probe runs the
//                          production sandbox config (smokeSandboxConfig, pinned to buildAgentSandboxConfig by
//                          test/sdk-bash-probe-parity.test.ts) and computes its OWN verdict in JavaScript
//                          (smokeVerdict, unit-tested under node). Env: NONCE (fresh per-run hex, required), HOME
//                          (the container's real HOME: the transcript mask derives from it), APP (default /app).
//                          Prints `SDK_BASH_DISPATCHED` once the Bash tool_use turn has been delivered to the SDK (the
//                          host reads it to classify a host-cap timeout), then exactly one result line:
//                          SDK_BASH_RESULT {"verdict":"pass|sdk_bash_smoke_failed|smoke_infra_error","reason":"...",
//                                           "coverage":"sdk_wrapper_shim_prodtuple|replay_only"}
//                          and exits 0 for every verdict (the caller classifies rc only for docker/node failures).
//
// The module has no top-level side effects: the pure pieces are exported for the unit tests and main() runs only when
// the file is the entry point.
import http from "node:http";
import { createRequire } from "node:module";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, statSync } from "node:fs";
import { delimiter, join } from "node:path";
import { pathToFileURL } from "node:url";

// ---- Pure pieces (exported) --------------------------------------------------------------------------------------

export const SMOKE_COVERAGE_FULL = "sdk_wrapper_shim_prodtuple";
export const SMOKE_COVERAGE_REPLAY_ONLY = "replay_only";

/** Decoy credential handed to the SDK child: the real key must never be reachable from the probe. */
export const SMOKE_DECOY_API_KEY = "decoy-api-key-sentinel";

/** The seccomp artifacts, by name. `base` is pinned to what the production env selects when nothing overrides the selector: the
 *  shim's own default (`BPF=${SOLEUR_BWRAP_SECCOMP_BPF:-...}` in infra/bwrap-shim/bwrap), the Dockerfile COPY and the
 *  self-probe default. It is never edited by the variant work. `unixdeny` (#10455 a) is the AF_UNIX-deny variant that
 *  `buildAgentEnv` selects for a NO-EGRESS session while the runtime flag `agent-sandbox-unix-deny` is ON.
 *  test/sdk-bash-probe-parity.test.ts pins both paths to the builders, the Dockerfile and the self-probe. */
export const SMOKE_SELECTOR_PATHS = Object.freeze({
  base: "/app/infra/bwrap-userns-clone3-deny.bpf",
  unixdeny: "/app/infra/bwrap-userns-clone3-unixdeny.bpf",
});

/** The artifact path the smoke sets as SOLEUR_BWRAP_SECCOMP_BPF for the SDK child. The smoke tuple is the NO-EGRESS tuple, so it
 *  runs under the unixdeny selector: a variant that breaks Bash start is reported (sdk_bash_smoke_failed) on the deploy that
 *  carries it, BEFORE the flag is ever turned on. The variant is a strict superset of the base program (same rules plus the
 *  socket(AF_UNIX) deny), so a base artifact that cannot start Bash would fail this run too. */
export function smokeSelectorPath() {
  return SMOKE_SELECTOR_PATHS.unixdeny;
}

/** Runtime mode: the pinned path for a selector NAME (`base` | `unixdeny`), else null. A closed lookup, never a path from the
 *  environment: an unknown name (or a prototype key) is refused rather than turned into a file path. */
export function runtimeSelectorPath(name) {
  return typeof name === "string" && Object.hasOwn(SMOKE_SELECTOR_PATHS, name) ? SMOKE_SELECTOR_PATHS[name] : null;
}

/** Runtime mode's view of the masked dirs: the ones that already exist (real sessions create them) and the count that do not.
 *  `exists` is injected so this is pure; it calls nothing else, so it can never create a directory. */
export function runtimeMaskedDirs(uid, home, exists) {
  const present = maskedDirs(uid, home).filter((d) => exists(d));
  return { present, missing: maskedDirs(uid, home).length - present.length };
}

/** The per-session masked dirs of the production config for a container env with no XDG_RUNTIME_DIR /
 *  CLAUDE_CODE_TMPDIR / TMPDIR: `/tmp/cc-socks`, the CLI's `/tmp/cc-socks-<uid>` fallback and the shared-HOME transcript
 *  dir (server/agent-runner-sandbox-config.ts `peerMessagingSocketDirs` / `sessionTranscriptDirs`). */
export function maskedDirs(uid, home) {
  return ["/tmp/cc-socks", `/tmp/cc-socks-${uid}`, `${home}/.claude/projects`];
}

/** The literal sandbox config of the deploy smoke: what `buildAgentSandboxConfig(workspace)` returns for the NO-EGRESS
 *  shape (no allowGithubEgress / readOnly / denyReadExtra / allowWebEgress) in a container with the default roots. The
 *  production builder is TypeScript and is not in the image, so this is a literal pinned by deep equality in
 *  test/sdk-bash-probe-parity.test.ts: a builder edit reds that test and prints the exact line to change here.
 *  `workspace` is the probe's scratch dir (production passes `<workspaces root>/<uuid>`); `uid`/`home` derive the masks. */
export function smokeSandboxConfig({ workspace, uid, home, masked = maskedDirs(uid, home) }) {
  return {
    enabled: true,
    failIfUnavailable: true,
    autoAllowBashIfSandboxed: false,
    allowUnsandboxedCommands: false,
    enableWeakerNestedSandbox: true,
    network: { allowedDomains: [], allowManagedDomainsOnly: true, allowAllUnixSockets: true },
    filesystem: {
      allowWrite: [workspace],
      // Order is the builder's: tenant roots, C4 staging root, /proc, /sys, egress token dir, masked dirs, session tmp root.
      denyRead: [
        "/workspaces",
        "/var/lib/soleur/worktrees",
        `${home}/.cache/soleur-c4-render`,
        "/proc",
        "/sys",
        "/var/lib/soleur/egress-tokens",
        ...masked,
        "/tmp/.cs",
      ],
    },
    credentials: {
      envVars: [
        { name: "ANTHROPIC_API_KEY", mode: "deny" },
        { name: "CLAUDE_CODE_OAUTH_TOKEN", mode: "deny" },
      ],
    },
  };
}

/** The nonce, rewritten the way the smoke command rewrites it: each hex digit is mapped by `tr 0-9a-f a-f0-9` (0->a, 5->f,
 *  6->0, 9->3, a->4, f->9), so the output has the same length and alphabet but no digit in place. */
export function transformNonce(nonce) {
  const from = "0123456789abcdef";
  const to = "abcdef0123456789";
  return String(nonce).replace(/[0-9a-f]/g, (c) => to[from.indexOf(c)]);
}

/** The Bash command the smoke runs. The per-run nonce appears in its TEXT only as the argument of `printf`; the OUTPUT is
 *  the transformed value, so a tool_result that merely QUOTES the command (an error message echoing it, a stub replaying
 *  it) cannot contain what `smokeVerdict` requires. Only a shell that actually executed the pipeline can. The nonce is
 *  validated as 16-64 lowercase hex by the caller before it reaches here (safe inside single quotes). */
export function smokeCommand(nonce) {
  return `echo SDK_SMOKE_$(printf %s '${nonce}' | tr 0-9a-f a-f0-9)`;
}

/** The single line the smoke command prints when it really ran. */
export function smokeExpectedOutput(nonce) {
  return `SDK_SMOKE_${transformNonce(nonce)}`;
}

const SANDBOX_SIGNATURE = /apply-seccomp|bwrap|unshare|seccomp|sandbox required but unavailable|EPERM|Operation not permitted/i;

/** A print-safe, length-capped one-liner for the verdict reason (it rides journald and Sentry). */
function safeReason(text, max = 160) {
  const one = String(text ?? "")
    .replace(/[^\x20-\x7e\n]/g, " ")
    .replace(/\s*\n\s*/g, " | ")
    .replace(/\s+/g, " ")
    .trim();
  return one.length > max ? `${one.slice(0, max)}...` : one;
}

/** The first line of `text` that carries a sandbox signature, else its first non-blank line. */
function signatureLine(text) {
  const lines = String(text ?? "").split(/\r?\n/).map((l) => l.trim()).filter(Boolean);
  return lines.find((l) => SANDBOX_SIGNATURE.test(l)) ?? lines[0] ?? "";
}

/**
 * The deploy smoke's verdict, computed from what the probe observed. Pure.
 *
 *   input:  { nonce, dispatched, toolResult: {isError, content}|null, thrown: string, timedOut: boolean,
 *             infraError: string, coverage }
 *           `dispatched` = the stub delivered the Bash tool_use turn (the SDK was asked to run a command).
 *   output: { verdict, reason, coverage }
 *
 * `pass` ONLY when the real tool_result carries the transformed per-run nonce the wrapped command computed (and is not error-flagged)
 * AND the coverage is the shim-and-wrapper tuple. A pass-shaped result whose coverage is `replay_only` is a HOLD: it is
 * returned as smoke_infra_error so the soak counter does not move.
 * `sdk_bash_smoke_failed` when Bash was dispatched and the run produced no verified nonce (an error result, a clean result
 * without the nonce, a thrown SDK error, or a hang), independent of any error signature, so a new wording of a failure
 * cannot go silent (the #10445 shape); and for a thrown SDK error that carries a sandbox signature even before dispatch
 * (a sandbox that cannot start is the incident, not an infra hiccup).
 * `smoke_infra_error` only when Bash was never dispatched for a reason that is not a sandbox signature (module missing,
 * stub failure, malformed input) and for the replay_only HOLD.
 */
export function smokeVerdict(obs) {
  const { nonce = "", dispatched = false, toolResult = null, thrown = "", timedOut = false, infraError = "" } = obs ?? {};
  const coverage = obs?.coverage === SMOKE_COVERAGE_FULL ? SMOKE_COVERAGE_FULL : SMOKE_COVERAGE_REPLAY_ONLY;
  if (infraError) return { verdict: "smoke_infra_error", reason: safeReason(infraError), coverage };

  if (toolResult) {
    const content = String(toolResult.content ?? "");
    // The EXECUTED output (transformed nonce), never the command text: see smokeCommand.
    const echoed = nonce.length > 0 && content.includes(smokeExpectedOutput(nonce));
    if (echoed && toolResult.isError !== true) {
      if (coverage !== SMOKE_COVERAGE_FULL) {
        return { verdict: "smoke_infra_error", reason: "coverage_replay_only", coverage };
      }
      return { verdict: "pass", reason: "ok", coverage };
    }
    const line = signatureLine(content);
    if (toolResult.isError === true || SANDBOX_SIGNATURE.test(content)) {
      return { verdict: "sdk_bash_smoke_failed", reason: safeReason(line || "error_result_without_text"), coverage };
    }
    return { verdict: "sdk_bash_smoke_failed", reason: safeReason(`no_nonce${line ? `: ${line}` : ""}`), coverage };
  }

  if (thrown) {
    if (SANDBOX_SIGNATURE.test(thrown)) return { verdict: "sdk_bash_smoke_failed", reason: safeReason(signatureLine(thrown)), coverage };
    if (dispatched) return { verdict: "sdk_bash_smoke_failed", reason: safeReason(`dispatched_then_error: ${thrown}`), coverage };
    return { verdict: "smoke_infra_error", reason: safeReason(`sdk_error_before_dispatch: ${thrown}`), coverage };
  }
  if (timedOut) {
    if (dispatched) return { verdict: "sdk_bash_smoke_failed", reason: "hung_after_dispatch", coverage };
    return { verdict: "smoke_infra_error", reason: "hung_before_dispatch", coverage };
  }
  if (dispatched) return { verdict: "sdk_bash_smoke_failed", reason: "dispatched_no_tool_result", coverage };
  return { verdict: "smoke_infra_error", reason: "bash_not_dispatched", coverage };
}

/** Is `bwrap` on `pathEnv` the repo's shim (content marker, not the path), and is the artifact at `bpfPath` a non-empty,
 *  sock_filter-sized file? Measured, never thrown. */
export function measureShimAndFilter(pathEnv, bpfPath) {
  let shim = false;
  for (const dir of String(pathEnv ?? "").split(delimiter)) {
    if (!dir) continue;
    try {
      shim = readFileSync(join(dir, "bwrap"), "utf8").includes("bwrap-shim:");
      break;
    } catch {
      /* not here: keep looking */
    }
  }
  let bytes = 0;
  try {
    bytes = statSync(bpfPath).size;
  } catch {
    /* artifact absent */
  }
  return { shim, filter: bytes > 0 && bytes % 8 === 0 };
}

/** `sdk_wrapper_shim_prodtuple` only when the command went through the real shim under the artifact that was asked for: the
 *  deploy smoke's pinned unixdeny path by default, the resolver-selected path in runtime mode (`expectedPath`). */
export function smokeCoverage({ shim, filter, bpfPath, expectedPath = smokeSelectorPath() }) {
  return shim && filter && bpfPath === expectedPath ? SMOKE_COVERAGE_FULL : SMOKE_COVERAGE_REPLAY_ONLY;
}

// ---- Entry point -------------------------------------------------------------------------------------------------

function sse(res, events) {
  res.writeHead(200, { "content-type": "text/event-stream", "cache-control": "no-cache" });
  for (const [ev, data] of events) res.write(`event: ${ev}\ndata: ${JSON.stringify(data)}\n\n`);
  res.end();
}

/** The local stand-in for the Messages API. `state.dispatched` flips when the Bash tool_use turn is delivered. */
function startStub(cmd, state) {
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
        // Printed (stdout to a pipe is synchronous, so it is flushed) BEFORE the SDK runs the command: a host `timeout` that kills
        // this process mid-hang still leaves it in the captured output. ci-deploy.sh reads it to tell "Bash hung" from "never got
        // that far". The `grep '^SDK_BASH_RESULT '` parse ignores it.
        state.dispatched = true;
        if (state.announce) console.log("SDK_BASH_DISPATCHED");
        sse(res, [["message_start", start],
          ["content_block_start", { type: "content_block_start", index: 0, content_block: { type: "tool_use", id: "toolu_1", name: "Bash", input: {} } }],
          ["content_block_delta", { type: "content_block_delta", index: 0, delta: { type: "input_json_delta", partial_json: JSON.stringify({ command: cmd }) } }],
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
  return server;
}

const toolResultText = (b) => (typeof b.content === "string" ? b.content : Array.isArray(b.content) ? b.content.map((c) => c.text ?? "").join("") : "");

async function runDefault() {
  const APP = process.env.APP;
  const KNOB = process.env.KNOB === "1";
  const CMD = process.env.CMD ?? "echo SMOKE_OK_10445";
  const require = createRequire(`${APP}/package.json`);
  const { query } = await import(require.resolve("@anthropic-ai/claude-agent-sdk"));
  const server = startStub(CMD, {});
  await new Promise((r) => server.listen(0, "127.0.0.1", r));
  const port = server.address().port;

  const ws = mkdtempSync(`${process.env.TMPDIR || "/tmp"}/sdk-bash-probe-`);
  // The masked dirs of the production config for THIS container's env: no XDG_RUNTIME_DIR / CLAUDE_CODE_TMPDIR / TMPDIR,
  // so `/tmp/cc-socks` plus the CLI's `/tmp/cc-socks-<uid>` fallback, and the shared-HOME transcript dir. Each must exist
  // before the namespace is built (the SDK skips a deny landing that does not exist). Parity with the production builder
  // is pinned by test/sdk-bash-probe-parity.test.ts.
  const uid = process.getuid();
  const HOME = process.env.HOME;
  if (!HOME || !HOME.startsWith("/")) throw new Error("sdk-bash-probe: HOME must be an absolute path (the transcript mask is derived from it)");
  const MASKED_DIRS = maskedDirs(uid, HOME);
  for (const d of MASKED_DIRS) mkdirSync(d, { recursive: true, mode: 0o700 });
  const sandbox = {
    enabled: true, failIfUnavailable: true, autoAllowBashIfSandboxed: true, allowUnsandboxedCommands: false, enableWeakerNestedSandbox: true,
    network: { allowedDomains: [], allowManagedDomainsOnly: true, ...(KNOB ? { allowAllUnixSockets: true } : {}) },
    filesystem: { allowWrite: [ws], denyRead: ["/proc", "/sys", ...MASKED_DIRS] },
  };
  const env = { ...process.env, ANTHROPIC_API_KEY: SMOKE_DECOY_API_KEY, ANTHROPIC_BASE_URL: `http://127.0.0.1:${port}`, CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: "1", DISABLE_TELEMETRY: "1", DISABLE_AUTOUPDATER: "1" };
  const timer = setTimeout(() => { console.log('SDK_BASH_RESULT {"error":"timeout"}'); process.exit(3); }, 120000);
  let found = null;
  let err = "";
  try {
    const q = query({ prompt: "run it", options: { cwd: ws, env, sandbox, allowedTools: ["Bash"], permissionMode: "bypassPermissions", allowDangerouslySkipPermissions: true, maxTurns: 3, model: "claude-haiku-4-5-20251001", settingSources: [] } });
    for await (const m of q) {
      if (m.type !== "user" || !Array.isArray(m.message?.content)) continue;
      for (const b of m.message.content) {
        if (b.type !== "tool_result") continue;
        found = { isError: b.is_error === true, content: toolResultText(b) };
      }
    }
  } catch (e) { err = String(e).slice(0, 300); }
  clearTimeout(timer);
  // The scratch workspace is this probe's own; remove it so repeated runs do not accumulate directories.
  try { rmSync(ws, { recursive: true, force: true }); } catch { /* best-effort scratch cleanup */ }
  console.log(`SDK_BASH_RESULT ${JSON.stringify(found ?? { error: err || "no tool_result" })}`);
  server.close();
  process.exit(0);
}

const SMOKE_INTERNAL_CAP_MS = 120000;

async function runSmoke() {
  const emit = (v) => console.log(`SDK_BASH_RESULT ${JSON.stringify(v)}`);
  const nonce = process.env.NONCE ?? "";
  const infra = (reason) => { emit(smokeVerdict({ nonce, infraError: reason })); process.exit(0); };
  if (!/^[0-9a-f]{16,64}$/.test(nonce)) infra("nonce_missing_or_malformed");
  const home = process.env.HOME;
  if (!home || !home.startsWith("/")) infra("home_not_absolute");
  const runtime = process.env.SDK_BASH_PROBE_RUNTIME === "1";
  // Runtime mode: the host passes the selector NAME it got from the dispatcher's resolver; deploy mode always runs unixdeny.
  const selectorName = runtime ? process.env.SDK_BASH_PROBE_SELECTOR ?? "" : "unixdeny";
  const selectedPath = runtime ? runtimeSelectorPath(selectorName) : smokeSelectorPath();
  if (selectedPath === null) infra("selector_invalid");
  const APP = process.env.APP || "/app";
  let query;
  try {
    const require = createRequire(`${APP}/package.json`);
    ({ query } = await import(require.resolve("@anthropic-ai/claude-agent-sdk")));
  } catch (e) {
    infra(`sdk_module_unavailable: ${String(e).slice(0, 120)}`);
  }

  const state = { dispatched: false, announce: true };
  const server = startStub(smokeCommand(nonce), state);
  try {
    await new Promise((resolve, reject) => { server.once("error", reject); server.listen(0, "127.0.0.1", resolve); });
  } catch (e) {
    infra(`stub_server_failed: ${String(e).slice(0, 120)}`);
  }
  const port = server.address().port;

  const tmp = process.env.TMPDIR || "/tmp";
  const ws = mkdtempSync(`${tmp}/sdk-bash-probe-`);
  const cfg = mkdtempSync(`${tmp}/sdk-bash-probe-cfg-`);
  const uid = process.getuid();
  // Each masked dir must exist before the namespace is built (the SDK skips a deny landing that does not exist). The deploy
  // smoke runs in a canary that has none, so it creates them; the runtime synthetic runs in the production container, where
  // those paths belong to real sessions, so it creates nothing and masks only the ones that already exist.
  let masked = maskedDirs(uid, home);
  let masksMissing = 0;
  try {
    if (!runtime) {
      for (const d of maskedDirs(uid, home)) mkdirSync(d, { recursive: true, mode: 0o700 });
    } else {
      const r = runtimeMaskedDirs(uid, home, (d) => { try { return statSync(d).isDirectory(); } catch { return false; } });
      masked = r.present;
      masksMissing = r.missing;
    }
  } catch (e) {
    try { rmSync(ws, { recursive: true, force: true }); rmSync(cfg, { recursive: true, force: true }); } catch { /* scratch */ }
    infra(`masked_dir_precreate_failed: ${String(e).slice(0, 120)}`);
  }
  // SDK_BASH_PROBE_BPF is a TEST-ONLY override (a dev machine has no /app/infra); ci-deploy.sh never sets it. Any value
  // other than the pinned path reports coverage replay_only, which the verdict treats as a hold, never a pass.
  const bpfPath = process.env.SDK_BASH_PROBE_BPF || selectedPath;
  const coverage = smokeCoverage({ ...measureShimAndFilter(process.env.PATH, bpfPath), bpfPath, expectedPath: selectedPath });
  const sandbox = smokeSandboxConfig({ workspace: ws, uid, home, masked });
  const env = {
    ...process.env,
    ANTHROPIC_API_KEY: SMOKE_DECOY_API_KEY,
    ANTHROPIC_BASE_URL: `http://127.0.0.1:${port}`,
    CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: "1",
    DISABLE_TELEMETRY: "1",
    DISABLE_AUTOUPDATER: "1",
    SOLEUR_BWRAP_SECCOMP_BPF: bpfPath,
    // A scratch config dir keeps the synthetic transcript out of the shared HOME.
    CLAUDE_CONFIG_DIR: cfg,
  };

  const controller = new AbortController();
  let toolResult = null;
  let thrown = "";
  let timedOut = false;
  const timer = setTimeout(() => { timedOut = true; controller.abort(); }, SMOKE_INTERNAL_CAP_MS);
  try {
    const q = query({
      prompt: "run it",
      options: {
        abortController: controller,
        cwd: ws,
        env,
        sandbox,
        allowedTools: ["Bash"],
        permissionMode: "default",
        canUseTool: async (_name, input) => ({ behavior: "allow", updatedInput: input }),
        maxTurns: 3,
        model: "claude-haiku-4-5-20251001",
        settingSources: [],
      },
    });
    for await (const m of q) {
      if (m.type !== "user" || !Array.isArray(m.message?.content)) continue;
      for (const b of m.message.content) {
        if (b.type !== "tool_result") continue;
        toolResult = { isError: b.is_error === true, content: toolResultText(b) };
      }
    }
  } catch (e) {
    if (!timedOut) thrown = String(e);
  } finally {
    clearTimeout(timer);
    controller.abort();
  }
  const v = smokeVerdict({ nonce, dispatched: state.dispatched, toolResult, thrown, timedOut, coverage });
  for (const d of [ws, cfg]) {
    try { rmSync(d, { recursive: true, force: true }); } catch { /* best-effort scratch cleanup */ }
  }
  // Runtime mode adds two observations the host journals; the verdict contract is unchanged.
  emit(runtime ? { ...v, selector: selectorName, masks_missing: masksMissing } : v);
  server.close();
  process.exit(0);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  if (process.env.SMOKE === "1") await runSmoke();
  else await runDefault();
}
