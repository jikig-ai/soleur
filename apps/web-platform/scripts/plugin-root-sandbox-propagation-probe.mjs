#!/usr/bin/env bun
// F2 in-image propagation probe (Slice B / AC7a — connected-repo plugin-shadow
// fix). Proves the RUNTIME guarantee that AC3 cannot: that
// `CLAUDE_PLUGIN_ROOT` — injected into the agent env by `buildAgentEnv` — is
// actually PRESENT in the bwrap-SANDBOXED Bash subprocess's environment. AC3
// only proves it in `buildAgentEnv`'s OUTPUT; whether it survives the SDK's
// `query()` → claude-CLI → bwrap projection is SDK-internal and was the gating
// unknown (plan §Phase 2 F2). If it does NOT reach sandbox bash, the deployed
// skills' `${CLAUDE_PLUGIN_ROOT:-./plugins/soleur}` would silently fall back to
// the UNTRUSTED connected-repo `./plugins/soleur` copy on the server surface.
//
// MECHANISM (empirically established, #6121): the SDK spawns the bwrap process
// with `options.env` (= buildAgentEnv output) as its process env and does NOT
// pass `--clearenv`; bubblewrap therefore lets the sandboxed command inherit the
// full process env (minus explicit `--unsetenv`, plus the ~26 `--setenv`
// proxy/git/tmpdir vars). So `CLAUDE_PLUGIN_ROOT` reaches bash via INHERITANCE,
// not via `--setenv`. The env-isolation boundary (CWE-526) is `buildAgentEnv`
// upstream, NOT the sandbox. A future SDK bump that adds `--clearenv` (or an
// `--unsetenv CLAUDE_PLUGIN_ROOT`) would break this — which is exactly what this
// gate catches.
//
// HOW: drive the real SDK `query()` with the real `buildAgentEnv()` env + a
// recognizable CLAUDE_PLUGIN_ROOT sentinel and a bwrap-intercepting PATH shim
// (reused pattern from sandbox-canary.mjs). The shim computes the EXACT env the
// sandboxed command would receive — starting from its own process env (= the env
// the SDK spawned bwrap with) and applying `--clearenv`/`--setenv`/`--unsetenv`
// exactly as bubblewrap does — then records whether CLAUDE_PLUGIN_ROOT===sentinel
// survives. It records ONLY the sentinel presence + argv (never real env values).
//
// MUST run inside the node:22-slim deploy base image with `socat` installed (the
// SDK's sandbox availability check requires bwrap AND socat) — see the wrapper
// `plugin-root-propagation-verify-in-image.sh`. Running on a dev machine/CI
// runner is NOT authoritative per the ADR-079 capture-env==replay-env invariant.
// Emits a one-line verdict JSON on stdout; exits non-zero on `does_not_propagate`
// (fail-closed) so a CI gate reddens on a propagation regression.
//
// Auth: drives ONE real (paid) Haiku turn; ANTHROPIC_API_KEY must be exported.
import {
  mkdtempSync,
  writeFileSync,
  chmodSync,
  mkdirSync,
  readFileSync,
  rmSync,
  realpathSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { computeCanaryPaths } from "./sandbox-canary.mjs";
import { buildAgentSandboxConfig } from "../server/agent-runner-sandbox-config.ts";
import { buildAgentEnv } from "../server/agent-env.ts";

// A recognizable, non-secret `/app/`-prefixed sentinel (mirrors a real deployed
// getPluginPath() shape without colliding with any real path).
const SENTINEL = "/app/__plugin_root_propagation_probe__/plugins/soleur";
const ATTEMPTS = 3;
const ATTEMPT_TIMEOUT_MS = 120_000;

function emit(verdict, extra = {}) {
  process.stdout.write(`${JSON.stringify({ verdict, ...extra })}\n`);
}

const apiKey = process.env.ANTHROPIC_API_KEY;
if (!apiKey) {
  emit("infra_error", { reason: "creds_absent" });
  process.exit(0);
}

// bwrap-intercepting shim: answers the SDK's `--version` probe, records the
// EFFECTIVE sandbox-bash env (does CLAUDE_PLUGIN_ROOT survive as the sentinel?),
// then exits 0 WITHOUT exec'ing the model-chosen command (no model code runs).
const SHIM = `#!/usr/bin/env node
const fs=require("fs");const argv=process.argv.slice(2);
if(argv.length===1&&argv[0]==="--version"){process.stdout.write("bubblewrap 0.11.1\\n");process.exit(0);}
const SENTINEL=${JSON.stringify(SENTINEL)};
let toks=argv.slice();const ai=argv.indexOf("--args");
if(ai!==-1&&argv[ai+1]!=null){try{toks=toks.concat(fs.readFileSync(Number(argv[ai+1]),"utf8").split("\\0").filter(t=>t.length>0));}catch(e){}}
// Reproduce bubblewrap's env transform on the env bwrap itself was spawned with.
let effEnv=Object.assign({},process.env);
let clearenv=false;
for(let i=0;i<toks.length;i++){
  if(toks[i]==="--clearenv"){effEnv={};clearenv=true;}
  else if(toks[i]==="--setenv"||toks[i]==="--setenv-try"){effEnv[toks[i+1]]=toks[i+2];i+=2;}
  else if(toks[i]==="--unsetenv"){delete effEnv[toks[i+1]];i+=1;}
}
const isSetup=toks.includes("--unshare-user")||toks.includes("--unshare-all");
const rec={isSetup,clearenv,bashSeesSentinel:effEnv.CLAUDE_PLUGIN_ROOT===SENTINEL,bashCprDefined:effEnv.CLAUDE_PLUGIN_ROOT!==undefined};
try{fs.appendFileSync(process.env.PLUGIN_ROOT_PROBE_FILE,JSON.stringify(rec)+"\\n");}catch{}
process.exit(0);`;

function readRecs(file) {
  let raw;
  try {
    raw = readFileSync(file, "utf8");
  } catch {
    return [];
  }
  const out = [];
  for (const line of raw.split("\n")) {
    if (!line.trim()) continue;
    try {
      out.push(JSON.parse(line));
    } catch {}
  }
  return out;
}

const { query } = await import("@anthropic-ai/claude-agent-sdk");
const { root, ownWorkspacePath } = computeCanaryPaths();
const shimDir = mkdtempSync(join(tmpdir(), "soleur-plugin-root-probe-"));
const captureFile = join(shimDir, "probe.jsonl");
const prevPath = process.env.PATH;
const prevWsRoot = process.env.WORKSPACES_ROOT;

try {
  mkdirSync(ownWorkspacePath, { recursive: true });
  const resolvedRoot = realpathSync(root);
  const resolvedOwn = realpathSync(ownWorkspacePath);
  process.env.WORKSPACES_ROOT = resolvedRoot;
  chmodSync(shimDir, 0o700);
  writeFileSync(join(shimDir, "bwrap"), SHIM, { mode: 0o700 });
  process.env.PATH = `${shimDir}:${prevPath ?? ""}`;
  process.env.PLUGIN_ROOT_PROBE_FILE = captureFile;

  const sandbox = buildAgentSandboxConfig(resolvedOwn);
  // buildAgentEnv injects CLAUDE_PLUGIN_ROOT from opts.pluginPath (the REAL
  // Slice B B1/B2 code path). We assert the value that reaches sandbox bash is
  // the one THIS function produced.
  const built = buildAgentEnv(
    { value: apiKey, scheme: "api_key" },
    {},
    { pluginPath: SENTINEL },
  );
  if (built.CLAUDE_PLUGIN_ROOT !== SENTINEL) {
    emit("infra_error", { reason: "buildAgentEnv_did_not_inject_sentinel" });
    process.exit(2);
  }
  // Harness scaffolding: the SDK only ENGAGES the sandbox when its ambient env
  // carries the sandbox-runtime/proxy vars the CLI reads (SANDBOX_RUNTIME,
  // CLAUDE_CODE_HOST_*_PROXY_PORT, …) — which `buildAgentEnv`'s minimal allowlist
  // strips (in prod those live in the server process env, present here only via
  // process.env). Seed from the ambient env, then OVERLAY buildAgentEnv's output
  // so the CLAUDE_PLUGIN_ROOT under test is the one the real code path produced.
  // The propagation MECHANISM is env-inheritance (no --clearenv), independent of
  // how many vars options.env carries — so a future SDK `--clearenv`/`--unsetenv`
  // regression still flips `bashSeesSentinel` to false and reddens the gate.
  const env = { ...process.env, ...built };
  // Ensure PATH keeps the shim first (built.PATH copied the shim-prepended value).
  env.PATH = `${shimDir}:${prevPath ?? ""}`;

  let sawSetup = false;
  for (let attempt = 1; attempt <= ATTEMPTS && !sawSetup; attempt++) {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), ATTEMPT_TIMEOUT_MS);
    try {
      const q = query({
        prompt:
          "Run the Bash command `true` exactly once and then stop. Do not explain, do not run anything else.",
        options: {
          model: "claude-haiku-4-5",
          maxTurns: 2,
          permissionMode: "default",
          cwd: resolvedOwn,
          allowedTools: ["Bash"],
          sandbox,
          env,
          abortController: controller,
          canUseTool: async (_n, input) => ({ behavior: "allow", updatedInput: input }),
        },
      });
      for await (const _m of q) {
        void _m;
        if (readRecs(captureFile).some((r) => r.isSetup)) {
          sawSetup = true;
          break;
        }
      }
    } catch (e) {
      process.stderr.write(`attempt ${attempt}: ${(e && e.message) || e}\n`);
    } finally {
      clearTimeout(timer);
    }
  }

  const setupRecs = readRecs(captureFile).filter((r) => r.isSetup);
  if (setupRecs.length === 0) {
    // Never a false PASS: no sandbox spawn captured → the SDK did not sandbox
    // (missing socat/bwrap, auth failure, or model issued no Bash call).
    emit("infra_error", { reason: "no_sandbox_setup_captured" });
    process.exit(3);
  }
  const propagates = setupRecs.every((r) => r.bashSeesSentinel === true);
  const anyClearenv = setupRecs.some((r) => r.clearenv === true);
  if (propagates) {
    emit("propagates", { setups: setupRecs.length, clearenv: anyClearenv });
    process.exit(0);
  }
  emit("does_not_propagate", {
    setups: setupRecs.length,
    clearenv: anyClearenv,
    detail: setupRecs.map((r) => ({
      bashSeesSentinel: r.bashSeesSentinel,
      bashCprDefined: r.bashCprDefined,
    })),
  });
  process.exit(1);
} finally {
  if (prevPath === undefined) delete process.env.PATH;
  else process.env.PATH = prevPath;
  if (prevWsRoot === undefined) delete process.env.WORKSPACES_ROOT;
  else process.env.WORKSPACES_ROOT = prevWsRoot;
  delete process.env.PLUGIN_ROOT_PROBE_FILE;
  try {
    rmSync(shimDir, { recursive: true, force: true });
  } catch {}
}
