#!/usr/bin/env bash
# engine-contract-probe.sh — run the pencil-setup contract checks against the REAL
# @pen.dev/cli engine (`pen interactive --out <f> [--in <f>]`), the ones the unit and
# stub tests can only assume.
#
# pyramid-justified: the real engine is the only oracle for the contract
#
# This is the one test that touches the real engine. The stub integration test
# (test/pencil-adapter-stub-repl.test.ts) encodes our BELIEF about the REPL, which is how
# #11143 passed review (learning: a-stub-that-encodes-your-belief-about-an-engine-passes-
# the-bug-it-was-written-to-catch). Run it by hand before any bump of PEN_CLI_VERSION in
# check_deps.sh or of the engine lockfile. It is deliberately not a *.test.sh: it needs the
# credential, so it must never be a required CI job or an auto-registered suite.
#
#   doppler run -p soleur -c dev -- bash plugins/soleur/skills/pencil-setup/scripts/engine-contract-probe.sh
#
# Credential: resolved ONCE as ${PEN_CLI_KEY:-${PENCIL_CLI_KEY:-}} (empty or whitespace counts
# as unset), handed to every child explicitly as PEN_CLI_KEY, never printed, never written to the
# transcript. Every line this probe emits passes through a redactor that knows the raw, JSON, URL
# and base64 forms, and the transcript is scrubbed again and scanned by gitleaks; raw child output
# that never reaches an emitted line is not recorded at all. Account details from `pen status` are
# never recorded.
#
# Engine-only cases (no adapter needed):
#   0  `pen status` reports Active (a fail-open engine runs with a bad key: it must not yield OK)
#   1  `pen interactive --help` signatures == REPL_SURFACE for the REPL tools; the removed tools absent
#   2  startup banner, then the prompt `pen > ` (raw coloured bytes recorded)
#   3  `OK` reply prefix; `## Print output` section
#   4  nonce-tagged top-level count round trip (the save sentinel's memory probe)
#   5  `save()` -> exactly `Saved <path>`; the file holds the nodes
#   6  a failing save prints `Save failed:` and writes nothing, now or later (idle window)
#   7  each removed name answers `Unknown tool:` and the enrichment appends the exact hint
#   8  export: every format has the right magic bytes; scale and quality change the output
#   9  read_skill on every guide path, each followed by an intact save() reply; the engine's guide
#      names equal the guide lists in SKILL.md and ux-design-lead.md
#  10  no engine write outside save(): positive control, then exit(), SIGTERM, SIGKILL, over a
#      >= 15 s idle window watched by mtime polling
#  11  batch_design raw DSL: the QuickJS sandbox exposes no process/require/fetch (pinned) and its
#      host-function set is pinned; Export reaches any path (recorded and pinned, CTO ruling 11.2)
#  12  a file with an unrecognised `version` opened via --in (recorded and pinned), idle window
#  13  canary credential in a scratch HOME: the engine's output, the saved .pen bytes and every file
#      the engine wrote under HOME are scanned in raw, base64 and URL-encoded forms
#  14  install method: `npm ci --ignore-scripts` from the committed lockfile yields a working engine
# Adapter cases (the INSTALLED adapter over MCP stdio, through test/lib/pencil-adapter-roundtrip.mjs):
#  A1  round trip, removed tools answer with the exact hint, reopen
#  A2  the same through the adapter's DEFAULT binary resolution (HOME at the real prefix, no override)
#  A3  refusal markers on line 1 of the TOOL RESULT (`REFUSED save: [reason=<code>]`): empty, stale,
#      and no write after an idle window
#  A4  a file removed behind a live session is recreated with the NOTE (ruling 2)
#  A5  unrecognised version via open_document (load fidelity refusal, ruling 6)
#  A6  canary credential through adapter stderr and every tool result
#  A7  load-fidelity acceptance (ruling 6): every committed knowledge-base/product/design/**/*.pen
#      loads with at least as many top-level nodes as the file holds
#
# Stated limits: an engine timer longer than the 15 s window would not be seen; atomicity of the
# engine's write and behaviour on a file written by a newer Desktop are not asserted beyond case 12's
# recorded answer; a count cannot see dropped NESTED nodes.
#
# Output: PASS/FAIL/RECORD/SKIP lines, then one verdict line. The redacted transcript goes to the
# stable path knowledge-base/engineering/operations/references/pencil-engine-probe-transcript.md
# (PROBE_TRANSCRIPT overrides it), scrubbed by test/lib/scrub-transcript.mjs and checked with
# gitleaks; a leak fails the run. A run that hit a tooling error does not touch the transcript.
#
# Environment: PROBE_PEN_BINARY=<abs path> probes another `pen` instead of the installed default (the
# adapter never reads an engine-binary environment variable, so this one is the probe's own);
# PROBE_TRANSCRIPT=<path> redirects the transcript.
#
# Exit codes: 0   PROBE OK: every case ran and passed
#             1   a contract check failed, the credential is not Active, or the transcript leaked
#                 (also when a tooling error stops the run after a check had already FAILED:
#                 `PROBE FAILED (n)` is printed first, then the tooling line)
#             2   internal setup error (for example the work directory is not absolute)
#             3   PROBE SKIPPED (no key), tooling missing or broken, or a case was skipped:
#                 an incomplete run is never reported as PROBE OK
#             78  refusing to run under `set -x` with a live credential (see #7797)

set -uo pipefail

case "$-" in
  *x*)
    if [ -n "${PEN_CLI_KEY:+x}" ] || [ -n "${PENCIL_CLI_KEY:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve the key once; empty or whitespace-only counts as unset.
KEY="${PEN_CLI_KEY:-}"
KEY="${KEY#"${KEY%%[![:space:]]*}"}"; KEY="${KEY%"${KEY##*[![:space:]]}"}"
if [[ -z "$KEY" ]]; then
  KEY="${PENCIL_CLI_KEY:-}"
  KEY="${KEY#"${KEY%%[![:space:]]*}"}"; KEY="${KEY%"${KEY##*[![:space:]]}"}"
fi
if [[ -z "$KEY" ]]; then
  echo "PROBE SKIPPED (no key)"
  echo "  This probe asserted nothing. Run: doppler run -p soleur -c dev -- bash $0" >&2
  exit 3
fi
unset PEN_CLI_KEY PENCIL_CLI_KEY

for tool in node npm; do
  command -v "$tool" >/dev/null 2>&1 || { echo "UNRESOLVED: $tool not on PATH" >&2; exit 3; }
done

PENCIL_BIN="${PROBE_PEN_BINARY:-$HOME/.local/share/pen-cli/node_modules/.bin/pen}"
if [[ ! -e "$PENCIL_BIN" ]]; then
  echo "UNRESOLVED: pen binary not found at $PENCIL_BIN (run: bash $SCRIPT_DIR/check_deps.sh --auto, or set PROBE_PEN_BINARY)" >&2
  exit 3
fi

# The default binary must pass the same identity rule check_deps.sh and the adapter apply
# (the real .bin/pen resolves to the installed package's declared bin.pen target).
OVERRIDE=0
if [[ -n "${PROBE_PEN_BINARY:-}" ]]; then
  OVERRIDE=1
elif ! resolved_pen="$(bash -c 'f="$1"; set --; source "$f"; detect_headless_cli' _ "$SCRIPT_DIR/check_deps.sh" 2>/dev/null)" || [[ -z "$resolved_pen" ]]; then
  echo "FAIL the default .bin/pen does not pass the check_deps.sh identity rule: $PENCIL_BIN"
  echo "PROBE FAILED (1)"
  exit 1
else
  PENCIL_BIN="$resolved_pen"
fi

PIN="$(sed -n 's/^PEN_CLI_VERSION="\([0-9][0-9.]*\)"$/\1/p' "$SCRIPT_DIR/check_deps.sh" | head -1)"
[[ -n "$PIN" ]] || { echo "UNRESOLVED: could not read PEN_CLI_VERSION from check_deps.sh" >&2; exit 3; }

REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
# A stable home: the per-feature specs directory is archived when its PR merges.
STABLE_DIR="$REPO_ROOT/knowledge-base/engineering/operations/references"
TRANSCRIPT_PATH="${PROBE_TRANSCRIPT:-}"
if [[ -z "$TRANSCRIPT_PATH" && -d "$STABLE_DIR" ]]; then
  TRANSCRIPT_PATH="$STABLE_DIR/pencil-engine-probe-transcript.md"
fi

work="$(mktemp -d -t pen-contract-probe.XXXXXXXX)"
[[ "$work" == /* ]] || { echo "FATAL: work dir not absolute: $work" >&2; exit 2; }
cleanup() {
  chmod -R u+w -- "$work" 2>/dev/null || true
  rm -rf -- "$work"
}
trap cleanup EXIT

cat > "$work/probe.mjs" <<'NODE'
import { spawn, spawnSync } from "node:child_process";
import {
  chmodSync, copyFileSync, existsSync, mkdirSync, readFileSync, readdirSync, realpathSync, rmSync, statSync, writeFileSync,
} from "node:fs";
import { basename, dirname, join } from "node:path";
import { pathToFileURL } from "node:url";
import { createHash, randomBytes } from "node:crypto";

const [scriptsDir, testLib, workDir, penBin, pin, transcriptPath, penCliDir, repoRoot, overrideFlag] = process.argv.slice(2);
const USING_OVERRIDE = overrideFlag === "1";
const KEY = process.env.PROBE_CRED ?? "";
delete process.env.PROBE_CRED;
const HOME = process.env.HOME ?? "";
const imp = (dir, f) => import(pathToFileURL(join(dir, f)).href);

const surface = await imp(scriptsDir, "pencil-repl-surface.mjs");
const {
  REPL_SURFACE, REPL_PROMPT, REPL_PROMPT_RAW, nodeVersionOk, redactionForms,
  buildBatchDesignCommand, buildCountCommand, newCountNonce, parseCountReply,
  buildExportCommand, buildReadSkillCommand, buildSaveCommand, validateSkillPath,
} = surface;
const { REMOVED_TOOL_NAMES, removedToolHint, enrichErrorMessage } = await imp(scriptsDir, "pencil-error-enrichment.mjs");
const { stripAnsi } = await imp(scriptsDir, "pencil-response-classify.mjs");
const scrub = await imp(testLib, "scrub-transcript.mjs");

// ---------------------------------------------------------------------------
// Output. Every emitted line passes through redact(): the credential in every form it can take.
let failures = 0;
let nPass = 0;
const skipped = [];
const LOG = [];
const canaryForms = [];
const redact = (s) => {
  let t = String(s);
  for (const f of [...redactionForms(KEY), ...canaryForms]) t = t.split(f).join("<redacted>");
  return t;
};
const emit = (line) => {
  const safe = redact(line);
  LOG.push(safe);
  console.log(safe);
};
const check = (ok, label, detail = "") => {
  const safe = redact(String(detail)).replace(/\s+/g, " ").slice(0, 300);
  emit(`${ok ? "PASS" : "FAIL"} ${label}${ok || !safe ? "" : `: ${safe}`}`);
  ok ? nPass++ : failures++;
};
const record = (label, value) => emit(`RECORD ${label}: ${redact(String(value)).replace(/\s+/g, " ").slice(0, 300)}`);
const note = (text) => emit(`NOTE ${text}`);
// A skipped case means the run asserted less than it promises: the verdict is never PROBE OK.
const skip = (label, why) => {
  skipped.push(label);
  emit(`SKIP ${label}: ${why}`);
};

const strip = stripAnsi;
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const isGone = (pid) => {
  try { process.kill(pid, 0); return false; } catch (e) { return e.code === "ESRCH"; }
};

// A stop that is a verdict, not a crash: carries the exit code and the verdict line.
class ProbeStop extends Error {
  constructor(code, verdict) { super(verdict); this.code = code; this.verdict = verdict; }
}

// Anything that escapes the case runner (a stray rejection inside an event handler) is a tooling
// error too: release the children, say so, exit 3 (1 when a check had already failed).
const fatal = (e) => {
  try { for (const x of sessions) x.child.kill("SIGKILL"); } catch { /* a child already gone, or the registry not created yet */ }
  if (failures > 0) console.log(`PROBE FAILED (${failures})`);
  console.log(`PROBE TOOLING ERROR (uncaught, nothing further was asserted): ${redact(String(e?.message ?? e)).replace(/\s+/g, " ").slice(0, 300)}`);
  process.exit(failures > 0 ? 1 : 3);
};
process.on("uncaughtException", fatal);
process.on("unhandledRejection", fatal);

if (!nodeVersionOk(process.version)) {
  console.error(`UNRESOLVED: node ${process.version} is below the engine floor 22.19.0`);
  process.exit(3);
}

const cwd = join(workDir, "cwd"); // private empty cwd for every engine child
mkdirSync(cwd, { recursive: true });
const engineEnv = (key = KEY, home = HOME) => ({ PATH: process.env.PATH ?? "", HOME: home, PEN_CLI_KEY: key });

// ---------------------------------------------------------------------------
// A REPL session driven directly over pipes. Error replies arrive on stderr, success on stdout
// (measured), so a reply is both streams after the command, up to the prompt at the END of the
// stdout buffer followed by a quiet period.
class Engine {
  constructor(args, { key = KEY, home = HOME, bin = penBin } = {}) {
    this.out = ""; this.err = ""; this.exit = null; this.startup = "";
    this.child = spawn(process.execPath, [bin, "interactive", ...args], {
      cwd, env: engineEnv(key, home), stdio: ["pipe", "pipe", "pipe"],
    });
    this.pid = this.child.pid;
    this.child.stdout.on("data", (d) => (this.out += d));
    this.child.stderr.on("data", (d) => (this.err += d));
    this.child.on("exit", (code, sig) => (this.exit = { code, sig }));
  }
  async waitPrompt(timeoutMs = 90000) {
    const t0 = Date.now();
    for (;;) {
      if (this.exit) return false;
      if (strip(this.out).endsWith(REPL_PROMPT)) {
        const n = this.out.length;
        await sleep(150);
        if (this.out.length === n && strip(this.out).endsWith(REPL_PROMPT)) return true;
      }
      if (Date.now() - t0 > timeoutMs) throw new Error(`no prompt within ${timeoutMs} ms`);
      await sleep(20);
    }
  }
  async start() {
    const ok = await this.waitPrompt();
    this.startup = this.out;
    this.startupErr = this.err;
    return ok;
  }
  async send(cmd) {
    this.out = ""; this.err = "";
    this.child.stdin.write(`${cmd}\n`);
    const ok = await this.waitPrompt();
    const out = strip(this.out).replace(/\s*pen > $/, "").trim();
    const err = strip(this.err).trim();
    return { ok, out, err, all: `${out}\n${err}`.trim() };
  }
  async quit() {
    if (this.exit) return;
    this.child.stdin.write("exit()\n");
    for (let i = 0; i < 250 && !this.exit; i++) await sleep(20);
    if (!this.exit) this.child.kill("SIGKILL");
  }
}
const sessions = new Set();
const adapters = new Set();
const open = (args, opts) => { const e = new Engine(args, opts); sessions.add(e); return e; };
// Kills every engine child and closes every adapter client, whatever state the run is in.
const finish = async () => {
  for (const e of sessions) if (!e.exit) { try { e.child.kill("SIGKILL"); } catch { /* already gone */ } }
  for (const a of adapters) { try { await a.close(); } catch { /* already closed */ } }
  adapters.clear();
};

// engine processes whose command line carries a unique path (ps works on Linux and macOS)
const lookup = (needle) => {
  const r = spawnSync("ps", ["-eo", "pid=,args="], { encoding: "utf8" });
  return r.stdout.split("\n")
    .map((l) => l.trim().match(/^(\d+)\s+(.*)$/))
    .filter((m) => m && Number(m[1]) !== process.pid && m[2].includes(needle))
    .map((m) => Number(m[1]));
};
const waitNoProcess = async (needle) => {
  for (let i = 0; i < 250; i++) { if (lookup(needle).length === 0) return true; await sleep(20); }
  return false;
};

const savedLine = (file) => `Saved ${join(realpathSync(dirname(file)), file.split("/").pop())}`;
const isSaved = (reply, file) => reply.out === savedLine(file) && reply.err === "";
const bytesOf = (f) => readFileSync(f);
const sameBytes = (a, b) => Buffer.compare(bytesOf(a), bytesOf(b)) === 0;

// A timed autosave would fire some time after an edit: watch the file for this long by mtime and
// size polling. A timer longer than the window is the stated limit.
const IDLE_WINDOW_MS = 15000;
const fileStamp = (f) => { try { const st = statSync(f); return `${st.mtimeMs}:${st.size}`; } catch { return "missing"; } };
async function watchQuiet(files, ms = IDLE_WINDOW_MS) {
  const base = files.map(fileStamp);
  const changed = new Set();
  const t0 = Date.now();
  while (Date.now() - t0 < ms) {
    await sleep(250);
    files.forEach((f, i) => { if (fileStamp(f) !== base[i]) changed.add(basename(f)); });
  }
  return [...changed];
}

const MANY_RECTS =
  'var f=I(document,{type:"frame",name:"qa",layout:"none",width:400,height:300,fill:"#ffffff"});' +
  'for(var i=0;i<60;i++){I(f,{type:"rectangle",x:(i*37)%380,y:(i*53)%280,width:20+(i%7)*9,height:15+(i%5)*11,' +
  'fill:"#"+(((i+1)*2654435)%16777216).toString(16).padStart(6,"0")});}Print("ID:"+f);';
const idOf = (reply) => /ID:([A-Za-z0-9_-]+)/.exec(reply.out)?.[1];
const printed = (reply) => /## Print output\n([\s\S]*)$/.exec(reply.out)?.[1].trim() ?? `no Print output: ${reply.all.slice(0, 120)}`;

async function runCases() {
// ---------------------------------------------------------------------------
// 0. The credential must be Active. A bad key does NOT stop `pen interactive` (fail-open usage
//    check), so without this a probe run against a revoked key would still print PASS lines.
{
  const st = spawnSync(process.execPath, [penBin, "status"], { encoding: "utf8", cwd, env: engineEnv(), timeout: 60000 });
  const text = strip(`${st.stdout}\n${st.stderr}`);
  const active = st.status === 0 && /Active/.test(text);
  check(active, "pen status reports Active for the credential (fail-open engine guard)", active ? "" : "status was not Active (reply not recorded: it carries account details)");
  if (!active) throw new ProbeStop(1, "PROBE FAILED (credential not Active)");
}

// installed engine == the pin this probe is run for
{
  let ver = "";
  try {
    const pkgPath = join(dirname(realpathSync(penBin)), "..", "package.json");
    ver = JSON.parse(readFileSync(pkgPath, "utf8")).version;
  } catch { /* handled by the check */ }
  check(ver === pin, "installed @pen.dev/cli version equals the check_deps.sh pin", `installed=${ver || "unreadable"} pin=${pin}`);
  // the engine's HTTP client is the lockfile-bumped dependency (pen-cli/package.json overrides); record what this run exercised
  let undici = "unreadable";
  try {
    const nm = dirname(dirname(dirname(dirname(realpathSync(penBin)))));
    undici = JSON.parse(readFileSync(join(nm, "undici", "package.json"), "utf8")).version;
  } catch { /* recorded as unreadable */ }
  record("undici version in the engine tree under test", undici);
}

// ---------------------------------------------------------------------------
// 1. Signatures in `pen interactive --help` vs REPL_SURFACE; removed tools absent.
const REMOVED = [...REMOVED_TOOL_NAMES];
{
  const help = spawnSync(process.execPath, [penBin, "interactive", "--help"], { encoding: "utf8", cwd, env: engineEnv() });
  const text = strip(`${help.stdout}\n${help.stderr}`);
  const live = {};
  for (const m of text.matchAll(/^# ([a-z_]+)\(\{?\s*([^})]*?)\s*\}?\)\s*$/gm)) {
    live[m[1]] = m[2].split(",").map((k) => k.trim().replace(/\?$/, "")).filter(Boolean).sort();
  }
  check(Object.keys(live).length > 0, "parsed tool signatures from --help", text.slice(0, 200));
  const table = Object.fromEntries(
    Object.entries(REPL_SURFACE).filter(([t]) => t !== "save").map(([t, k]) => [t, [...k].sort()])
  );
  const mismatched = Object.entries(table).filter(([t, k]) => JSON.stringify(live[t]) !== JSON.stringify(k));
  check(mismatched.length === 0, "every REPL_SURFACE tool has exactly the signature the CLI prints",
    `mismatched=${JSON.stringify(mismatched)} live=${JSON.stringify(live)}`);
  const stillListed = REMOVED.filter((t) => t in live);
  check(stillListed.length === 0, `none of the ${REMOVED.length} removed tools is listed in --help`, stillListed.join(","));
  check(/^\s*save\(\)\s/m.test(text) || /save\(\)/.test(text), "--help documents the save() shell command");
}

// ---------------------------------------------------------------------------
// 2-5, 7, 9. One session on seed.pen: prompt, OK, print output, count, save, removed names, skills.
const seed = join(workDir, "seed.pen");
let engineGuideNames = [];
{
  const s = open(["--out", seed]);
  const started = await s.start();
  check(started, "session starts and reaches the prompt", strip(s.out).slice(-200));
  check(strip(s.startup).includes("[INFO] Ready."), "startup prints [INFO] Ready. before the prompt");
  check(strip(s.startup).trimEnd().endsWith(REPL_PROMPT.trimEnd()), "prompt is `pen > ` at the end of the buffer");
  check(s.startup.endsWith(REPL_PROMPT_RAW), "raw prompt bytes equal REPL_PROMPT_RAW", JSON.stringify(s.startup.slice(-40)));
  record("ANSI escapes on piped stdout", s.startup.includes("\x1b[") ? "yes (the engine colours even on a pipe)" : "no");

  // count on an empty document, then edits
  let nonce = newCountNonce();
  let r = await s.send(buildCountCommand(nonce));
  check(parseCountReply(r.all, nonce) === 0, "nonce count on an empty document is 0", r.all);
  check(parseCountReply(r.all, newCountNonce()) === null, "a count line for another nonce is not accepted");

  r = await s.send(buildBatchDesignCommand('f=I(document,{type:"frame",width:200,height:100,fill:"#FFFFFF"})\nt=I(f,{type:"text",content:"probe"})\nPrint("probe-print-line")'));
  check(/^OK\b/.test(r.out), "batch_design reply starts with OK", r.all);
  check(r.out.includes("## Print output") && r.out.includes("probe-print-line"), "reply carries a ## Print output section", r.all);
  r = await s.send(buildBatchDesignCommand('g=I(document,{type:"frame",width:50,height:50})'));
  check(/^OK\b/.test(r.out), "second consecutive batch_design reply starts with OK", r.all);
  const typeofAlias = await s.send(buildBatchDesignCommand('Print(typeof I, typeof U)'));
  check(/function\s+function/.test(typeofAlias.out), "the alias preamble defines I and U inside execute", typeofAlias.all);

  nonce = newCountNonce();
  r = await s.send(buildCountCommand(nonce));
  check(parseCountReply(r.all, nonce) === 2, "nonce count after two top-level inserts is 2", r.all);
  // a node named like a count line must not forge the probe: the nonce differs per call
  const n2 = newCountNonce();
  await s.send(buildBatchDesignCommand(`I(document,{type:"frame",name:"TOPLEVEL_COUNT:${n2}:99",width:5,height:5})`));
  r = await s.send(buildCountCommand(n2));
  check(parseCountReply(r.all, n2) === 3, "a node name that imitates the count line does not change the parse", r.all);

  r = await s.send(buildSaveCommand());
  check(isSaved(r, seed), "save() replies exactly `Saved <path>` on stdout", r.all);
  let doc = {};
  try { doc = JSON.parse(readFileSync(seed, "utf8")); } catch { /* checked below */ }
  check(Array.isArray(doc.children) && doc.children.length === 3, "the saved file holds the three top-level nodes", `children=${doc.children?.length}`);
  check(statSync(seed).size > 96, "the saved file is larger than the 96-byte empty document", `size=${statSync(seed).size}`);
  check(typeof doc.version === "string", "the saved document carries a version", String(doc.version));

  // 7. removed names: the engine's own answer, and the enrichment the adapter appends to it
  for (const name of REMOVED) {
    r = await s.send(`${name}()`);
    check(r.ok && /Unknown tool:/.test(r.all), `${name}() answers Unknown tool:`, r.all);
    const enriched = enrichErrorMessage(r.all);
    check(enriched.includes(`[adapter hint] ${removedToolHint(name)}`), `${name}: the enrichment appends the exact removed-tool hint to the engine's answer`, enriched.slice(-160));
  }
  r = await s.send("batch_design({ operations: 'x' })");
  check(r.ok && /Unknown tool:/.test(r.all), "batch_design() (the old name) answers Unknown tool:", r.all);

  // 9. read_skill on every guide path, each followed by an intact save() reply
  const idx = await s.send(buildReadSkillCommand());
  // the index is a markdown table whose link TARGETS are the readable paths: `[x.md](./guide/x.md)`
  const paths = [...new Set([...idx.out.matchAll(/\]\(\.\/((?:guide\/)?[a-z0-9-]+\.md)\)/g)].map((m) => m[1]))];
  check(paths.length >= 12, "read_skill() index lists the guide and top-level paths", `found ${paths.length}: ${paths.join(" ")}`);
  for (const must of ["pen-schema.md", "execute.md"]) check(paths.includes(must), `read_skill index lists ${must}`);
  check(paths.filter((p) => p.startsWith("guide/")).length >= 9, "read_skill index lists at least 9 guide/ paths");
  engineGuideNames = paths.filter((p) => p.startsWith("guide/")).map((p) => p.slice(6, -3)).sort();
  let bad = [];
  for (const p of paths) { try { validateSkillPath(p); } catch { bad.push(p); } }
  check(bad.length === 0, "every listed path passes the adapter's read_skill validator", bad.join(","));
  let skillFailures = [];
  for (const p of paths) {
    const rr = await s.send(buildReadSkillCommand(p));
    const sv = await s.send(buildSaveCommand());
    if (!rr.ok || rr.out.length < 50 || rr.err !== "" || !isSaved(sv, seed)) skillFailures.push(`${p}: skill=${rr.out.length}b err=${rr.err.slice(0, 60)} save=${sv.all.slice(0, 80)}`);
  }
  check(skillFailures.length === 0, `read_skill on all ${paths.length} paths, each followed by an intact save() reply`, skillFailures.join(" | "));
  await s.quit();
}

// 9b. the guide names the prose promises are the guide names the engine lists
{
  const guideList = (text, re) => {
    const m = re.exec(text);
    return m ? [...m[1].matchAll(/[a-z][a-z0-9-]*/g)].map((x) => x[0]).sort() : null;
  };
  const read = (rel) => { try { return readFileSync(join(repoRoot, rel), "utf8"); } catch { return ""; } };
  const sources = [
    ["plugins/soleur/skills/pencil-setup/SKILL.md", /guides: ([a-z0-9, -]+)\)/],
    ["plugins/soleur/agents/product/design/ux-design-lead.md", /design type \(([^)]*)\)/],
  ];
  for (const [rel, re] of sources) {
    const names = guideList(read(rel), re);
    check(names !== null && JSON.stringify(names) === JSON.stringify(engineGuideNames),
      `guide names in ${basename(rel)} equal the engine's read_skill index`,
      names === null ? "guide list not found in the file" : `file=${names.join(",")} engine=${engineGuideNames.join(",")}`);
  }
}

// 6. a failing save prints `Save failed:` and writes nothing, now or later
{
  const ro = join(workDir, "ro");
  mkdirSync(ro, { recursive: true });
  const target = join(ro, "x.pen");
  if (typeof process.getuid === "function" && process.getuid() === 0) {
    skip("Save failed: case", "running as root: a read-only directory does not fail the write");
  } else {
    const s = open(["--out", target]);
    await s.start();
    await s.send(buildBatchDesignCommand('I(document,{type:"frame",width:10,height:10})'));
    chmodSync(ro, 0o555);
    const r = await s.send(buildSaveCommand());
    chmodSync(ro, 0o755);
    check(/^Save failed:/m.test(r.all), "a failed save prints `Save failed:`", r.all);
    record("Save failed: stream", r.err.includes("Save failed:") ? "stderr" : r.out.includes("Save failed:") ? "stdout" : "none");
    check(!/^Saved /m.test(r.all), "a failed save is not confirmed with a Saved line");
    check(!existsSync(target), "a failed save left no file behind");
    // the directory is writable again: an engine write timer that retried the unsaved document would land now
    const late = await watchQuiet([target]);
    check(late.length === 0 && !existsSync(target), `no engine write appears in the ${IDLE_WINDOW_MS / 1000} s after a failed save (directory writable again)`, late.join(","));
    const again = await s.send(buildSaveCommand());
    record("save() after the cause of a failed save is fixed", isSaved(again, target) ? "Saved (the engine kept the edit in memory)" : again.all.slice(0, 120));
    await s.quit();
  }
}

// 8. export formats, scale and quality
{
  const s = open(["--out", join(workDir, "export.pen")]);
  await s.start();
  const r0 = await s.send(buildBatchDesignCommand(MANY_RECTS));
  const id = idOf(r0);
  check(Boolean(id), "created a frame to export and read its id", r0.all);
  const exportTo = async (name, options) => {
    const dir = join(workDir, `ex-${name}`);
    mkdirSync(dir, { recursive: true });
    const r = await s.send(buildExportCommand({ nodeIds: [id], outputDir: dir, ...options }));
    const files = [...r.out.matchAll(/^Exported (\/.+)$/gm)].map((m) => m[1]);
    return { r, dir, files, file: files[0], bytes: files[0] && existsSync(files[0]) ? readFileSync(files[0]) : null };
  };
  const magic = {
    png: (b) => b.subarray(0, 4).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47])),
    jpeg: (b) => b.subarray(0, 3).equals(Buffer.from([0xff, 0xd8, 0xff])),
    webp: (b) => b.subarray(0, 4).toString("latin1") === "RIFF" && b.subarray(8, 12).toString("latin1") === "WEBP",
    pdf: (b) => b.subarray(0, 4).toString("latin1") === "%PDF",
  };
  const results = {};
  for (const fmt of ["png", "jpeg", "webp", "pdf"]) {
    results[fmt] = await exportTo(fmt, { format: fmt });
    const x = results[fmt];
    check(Boolean(x.bytes) && magic[fmt](x.bytes), `export format ${fmt} writes a ${fmt} file`, x.r.all);
    check(x.files.length === 1 && x.file.startsWith(x.dir + "/"), `export ${fmt}: the reply names one path inside the requested directory`, x.files.join(","));
  }
  const dims = (b) => ({ w: b.readUInt32BE(16), h: b.readUInt32BE(20) });
  const s1 = await exportTo("png-s1", { format: "png", scale: 1 });
  const s3 = await exportTo("png-s3", { format: "png", scale: 3 });
  const d1 = s1.bytes && dims(s1.bytes), d3 = s3.bytes && dims(s3.bytes);
  check(Boolean(d1 && d3) && d3.w === d1.w * 3 && d3.h === d1.h * 3, "png scale 3 yields 3x the pixel dimensions of scale 1", `${JSON.stringify(d1)} vs ${JSON.stringify(d3)}`);
  for (const fmt of ["jpeg", "webp"]) {
    const lo = await exportTo(`${fmt}-q10`, { format: fmt, quality: 10 });
    const hi = await exportTo(`${fmt}-q95`, { format: fmt, quality: 95 });
    const ok = lo.bytes && hi.bytes && lo.bytes.length < hi.bytes.length;
    check(Boolean(ok), `${fmt} quality 10 yields a smaller file than quality 95`, `q10=${lo.bytes?.length} q95=${hi.bytes?.length}`);
  }
  // a missing node id must fail before writing anything
  const dirMissing = join(workDir, "ex-missing");
  mkdirSync(dirMissing);
  const rm = await s.send(buildExportCommand({ nodeIds: ["noSuchNode1"], outputDir: dirMissing, format: "png" }));
  check(readdirSync(dirMissing).length === 0 && /rror/.test(rm.all), "Export of a missing node id errors and writes nothing", rm.all);
  await s.quit();
}

// 10. no engine write outside save(): positive control, then exit(), SIGTERM, SIGKILL, all idle together
{
  const edit = buildBatchDesignCommand('I(document,{type:"frame",name:"unsaved-edit",width:30,height:30})');
  const prep = (name) => {
    const f = join(workDir, `nw-${name}.pen`);
    copyFileSync(seed, f);
    return f;
  };
  {
    const f = prep("control");
    const s = open(["--out", f, "--in", f]);
    await s.start();
    await s.send(edit);
    const sv = await s.send(buildSaveCommand());
    await s.quit();
    check(isSaved(sv, f) && !sameBytes(f, seed), "positive control: the same edit plus save() DOES change the bytes", sv.all);
  }
  const paths = ["exit()", "SIGTERM", "SIGKILL"];
  const runs = [];
  for (const path of paths) {
    const f = prep(path.replace(/\W/g, ""));
    const s = open(["--out", f, "--in", f]);
    const started = await s.start();
    const ed = await s.send(edit);
    runs.push({ path, f, s, started, ed });
  }
  // the sessions sit idle with an unsaved edit while the files are watched by mtime polling
  const changed = await watchQuiet(runs.map((x) => x.f));
  check(changed.length === 0, `no engine write to any file during a ${IDLE_WINDOW_MS / 1000} s idle window after an unsaved edit (mtime polling)`, changed.join(","));
  for (const { path, f, s, started, ed } of runs) {
    if (path === "exit()") s.child.stdin.write("exit()\n");
    else s.child.kill(path);
    for (let i = 0; i < 250 && !s.exit; i++) await sleep(20);
    const gone = isGone(s.pid) && (await waitNoProcess(f));
    check(started && /^OK\b/.test(ed.out) && gone, `edit then ${path}: the engine process is gone`, `started=${started} edit=${ed.out.slice(0, 40)} exit=${JSON.stringify(s.exit)}`);
    check(sameBytes(f, seed), `edit then ${path}: the file is byte-identical to before the session`);
  }
  note(`a timed autosave firing later than ${IDLE_WINDOW_MS / 1000} s after the edit is outside the observation window (stated limit)`);
}

// 11. batch_design raw DSL: what the sandbox exposes, and what the path-taking host functions do
{
  const s = open(["--out", join(workDir, "dsl.pen")]);
  await s.start();
  const pr = async (code) => printed(await s.send(buildBatchDesignCommand(code)));

  // (a) no Node/host globals reach the DSL. The `typeof` of each name and two escape routes are
  // pinned: a different answer after a bump means the "QuickJS sandbox with no process, require,
  // fetch" sentence in ADR-304 must be re-read.
  const DENY = ["process", "require", "fetch", "XMLHttpRequest", "Buffer", "module", "exports", "WebSocket", "Deno", "Bun",
    "console", "setTimeout", "setInterval", "setImmediate", "queueMicrotask", "importScripts", "navigator", "window", "self", "global", "std", "os"];
  const kinds = (await pr(`Print([${DENY.map((n) => `typeof ${n}`).join(",")}].join(","))`)).split(",");
  const exposed = DENY.filter((n, i) => kinds[i] !== "undefined");
  check(kinds.length === DENY.length && exposed.length === 0, "the DSL sandbox defines none of process/require/fetch/XMLHttpRequest/Buffer/module/console/timers/std/os (typeof is undefined)", `exposed=${exposed.join(",")} raw=${kinds.join(",").slice(0, 120)}`);
  const viaThis = await pr('Print(typeof (function(){return this})().process)');
  const viaCtor = await pr('Print((function(){}).constructor("return typeof process + typeof require + typeof fetch")())');
  const viaEval = await pr('Print(eval("typeof process + typeof require + typeof fetch"))');
  check(viaThis === "undefined" && viaCtor === "undefinedundefinedundefined" && viaEval === "undefinedundefinedundefined",
    "escape routes (this, Function constructor, eval) reach no process/require/fetch", `this=${viaThis} ctor=${viaCtor} eval=${viaEval}`);
  // (b) the host-function set: every global that is not an ECMAScript built-in
  const ES = new Set(("AggregateError,Array,ArrayBuffer,BigInt,BigInt64Array,BigUint64Array,Boolean,DataView,Date,Error,EvalError,FinalizationRegistry," +
    "Float16Array,Float32Array,Float64Array,Function,Infinity,Int16Array,Int32Array,Int8Array,InternalError,Iterator,JSON,Map,Math,NaN,Number,Object,Promise,Proxy," +
    "RangeError,ReferenceError,Reflect,RegExp,Set,SharedArrayBuffer,String,Symbol,SyntaxError,TypeError,URIError,Uint16Array,Uint32Array,Uint8Array,Uint8ClampedArray," +
    "WeakMap,WeakRef,WeakSet,decodeURI,decodeURIComponent,encodeURI,encodeURIComponent,escape,eval,globalThis,isFinite,isNaN,parseFloat,parseInt,undefined,unescape").split(","));
  const names = (await pr('Print(Object.getOwnPropertyNames(globalThis).sort().join(","))')).split(",");
  const host = names.filter((n) => !ES.has(n)).join(",");
  record("DSL host globals (every global that is not an ECMAScript built-in)", host);
  const PINNED_HOST_GLOBALS = "C,Copy,D,Delete,Export,FindEmptySpace,G,Generate,Get,GetVariables,I,Insert,M,Move,Print,R,Replace,SetVariables,TakeScreenshot,U,Update," +
    "__batchDesignC,__batchDesignD,__batchDesignExportGlobals,__batchDesignFindEmptySpace,__batchDesignG,__batchDesignGet,__batchDesignGetVariables,__batchDesignI,__batchDesignM,__batchDesignP,__batchDesignR,__batchDesignT,__batchDesignU,__batchDesignV,__batchDesignX,document,root";
  check(host === PINNED_HOST_GLOBALS, "pinned engine behaviour: the DSL host-function set", `observed=${host}`);

  // a dynamic import must not hand the DSL a loadable node:fs; its promise is observed on the NEXT call
  await pr('(function(){try{var p=eval(\'import("node:fs")\');p.then(function(m){globalThis.__dyn="loaded:"+typeof m.readFileSync},function(e){globalThis.__dyn="rejected:"+String(e&&e.message).slice(0,60)})}catch(e){globalThis.__dyn="threw:"+String(e.message).slice(0,60)}})()');
  const dynImport = await pr('Print(typeof globalThis.__dyn==="undefined"?"never-settled":globalThis.__dyn)');
  record("dynamic import(\"node:fs\") inside the DSL", dynImport);
  check(!/^loaded/.test(dynImport), "dynamic import does not hand the DSL a loadable node:fs module", dynImport);

  // (c) path-taking host functions: Export reaches any path; image-fill urls read local files
  const docDir = join(workDir, "doc-pin");
  const outside = join(workDir, "outside");
  mkdirSync(docDir, { recursive: true });
  mkdirSync(outside, { recursive: true });
  const p = open(["--out", join(docDir, "pin.pen")]);
  await p.start();
  const r0 = await p.send(buildBatchDesignCommand('var red=I(document,{type:"frame",layout:"none",width:40,height:40,fill:"#FF0000"});var blue=I(document,{type:"frame",layout:"none",width:30,height:30,fill:"#0000FF"});Print("ID:"+red+" "+blue);'));
  const [redId, blueId] = /ID:(\S+) (\S+)/.exec(r0.out)?.slice(1) ?? [];
  // (c1) Export through raw DSL to an absolute directory outside the document's directory
  const ex = await p.send(buildBatchDesignCommand(`Export([${JSON.stringify(redId)}],"png",${JSON.stringify(outside)})`));
  const wrote = readdirSync(outside).filter((f) => f.endsWith(".png"));
  const outsideFile = wrote[0] ? join(outside, wrote[0]) : null;
  record("batch_design Export to an absolute dir outside the document dir", wrote.length ? "writes there" : `no file (${ex.all.slice(0, 80)})`);
  // (c2) does Export overwrite an existing file at that path?
  let overwrote = "n/a";
  if (outsideFile) {
    writeFileSync(outsideFile, "sentinel-not-a-png");
    const again = await p.send(buildBatchDesignCommand(`Export([${JSON.stringify(redId)}],"png",${JSON.stringify(outside)})`));
    overwrote = readFileSync(outsideFile, "latin1") === "sentinel-not-a-png" ? "no (kept the existing file)" : "yes (replaced the existing file)";
    record("batch_design Export over an existing file", `${overwrote}; reply: ${again.all.slice(0, 80)}`);
  }
  // (c3) two nodes as pdf: one combined export.pdf in the directory
  const pdfDir = join(workDir, "doc-pdf");
  mkdirSync(pdfDir, { recursive: true });
  await p.send(buildBatchDesignCommand(`Export([${JSON.stringify(redId)},${JSON.stringify(blueId)}],"pdf",${JSON.stringify(pdfDir)})`));
  const pdfFiles = readdirSync(pdfDir).sort().join(",");
  record("batch_design Export of two nodes as pdf", pdfFiles || "no file");
  // (c4) the non-image formats html-css / html-tailwind take a FILE path as the third argument
  const sv = await p.send(buildSaveCommand());
  const docFile = join(docDir, "pin.pen");
  const docBefore = existsSync(docFile) ? readFileSync(docFile) : Buffer.alloc(0);
  const htmlNew = join(docDir, "out.html");
  await p.send(buildBatchDesignCommand(`Export([${JSON.stringify(redId)}],"html-css",${JSON.stringify(htmlNew)})`));
  const htmlNewKind = existsSync(htmlNew) && /^<!doctype html>/i.test(readFileSync(htmlNew, "utf8")) ? "writes the named html file" : "no html file";
  record("batch_design Export html-css to a new file path in the document dir", htmlNewKind);
  const overDoc = await p.send(buildBatchDesignCommand(`Export([${JSON.stringify(redId)}],"html-css",${JSON.stringify(docFile)})`));
  const docAfter = readFileSync(docFile);
  const overDocKind = Buffer.compare(docBefore, docAfter) === 0 ? "document untouched"
    : /^<!doctype html>/i.test(docAfter.toString("utf8")) ? "OVERWRITES the open document file with html (the design is gone from disk)" : "document changed to something else";
  record("batch_design Export html-css to the open document's own path", `${overDocKind}; reply: ${overDoc.all.slice(0, 80)}`);
  check(isSaved(sv, docFile), "the document was saved before the html Export-over-document test", sv.all);
  // (c5) image fills with local urls: loaded or ignored?
  const probeImage = async (label, url) => {
    const a = await p.send(buildBatchDesignCommand(`var im=I(document,{type:"rectangle",width:40,height:40,fill:{type:"image",url:${JSON.stringify(url)},mode:"cover"}});Print("ID:"+im);`));
    const imId = idOf(a);
    if (!imId) return null;
    const d = join(workDir, `pin-${label}`);
    mkdirSync(d, { recursive: true });
    await p.send(buildExportCommand({ nodeIds: [imId], outputDir: d, format: "png" }));
    const f = readdirSync(d)[0];
    return f ? readFileSync(join(d, f)) : null;
  };
  let loaded = {};
  if (outsideFile) {
    // restore a real png at the outside path
    await p.send(buildBatchDesignCommand(`Export([${JSON.stringify(redId)}],"png",${JSON.stringify(outside)})`));
    const redPng = readFileSync(outsideFile);
    const missing = await probeImage("missing", join(workDir, "no-such-image.png"));
    // reference: the same rectangle filled with the colour the image holds
    const solid = await p.send(buildBatchDesignCommand('var rr=I(document,{type:"rectangle",width:40,height:40,fill:"#FF0000"});Print("ID:"+rr);'));
    const refDir = join(workDir, "pin-solid");
    mkdirSync(refDir, { recursive: true });
    await p.send(buildExportCommand({ nodeIds: [idOf(solid)], outputDir: refDir, format: "png" }));
    const solidPng = readFileSync(join(refDir, readdirSync(refDir)[0]));
    for (const [label, url] of [
      ["abs", outsideFile],
      ["fileurl", `file://${outsideFile}`],
      ["traversal", `../outside/${wrote[0]}`],
    ]) {
      const got = await probeImage(label, url);
      loaded[label] = !got || !missing ? "inconclusive"
        : Buffer.compare(got, solidPng) === 0 ? "loaded (renders the local file's pixels)"
        : Buffer.compare(got, missing) === 0 ? "ignored (same output as a missing file)"
        : "differs from a missing file but is not the file's pixels";
      record(`image fill url (${label}) pointing outside the document dir`, loaded[label]);
    }
    check(redPng.length > 100, "the image fills above were tried against a real exported png", `size=${redPng.length}`);
  }
  note("batch_design host-function behaviour is RECORDED above and PINNED below; switch to a shadowing prelude only if Export overwrites arbitrary files or image urls read local files (CTO ruling 11.2)");
  // PINNED: the observed behaviour at the pin. A different answer after a bump FAILS here so the
  // residual-risk statement in ADR-304 is re-read; it never silently drifts.
  const PINNED = {
    exportOutside: "writes there",
    exportOverwrite: "yes (replaced the existing file)", // png/jpeg/webp/pdf: <nodeId>.<format> (export.pdf for several nodes) inside the chosen directory
    exportPdfMulti: "export.pdf",
    exportHtmlNewFile: "writes the named html file", // html-css/html-tailwind take a FILE path, not a directory
    exportHtmlOverDocument: "OVERWRITES the open document file with html (the design is gone from disk)",
    imageAbs: "loaded (renders the local file's pixels)",
    imageFileUrl: "loaded (renders the local file's pixels)",
    imageTraversal: "loaded (renders the local file's pixels)",
  };
  const observed = {
    exportOutside: wrote.length ? "writes there" : "no file",
    exportOverwrite: overwrote,
    exportPdfMulti: pdfFiles,
    exportHtmlNewFile: htmlNewKind,
    exportHtmlOverDocument: overDocKind,
    imageAbs: loaded.abs,
    imageFileUrl: loaded.fileurl,
    imageTraversal: loaded.traversal,
  };
  for (const k of Object.keys(PINNED)) {
    check(observed[k] === PINNED[k], `pinned engine behaviour: ${k}`, `observed=${observed[k]} pinned=${PINNED[k]}`);
  }
  await s.quit();
  await p.quit();
}

// 11b. the recipe forms the prose promises (SKILL.md, ux-design-lead.md, the removed-tool hints): they must
// RUN against the engine, not merely read well. A hint that names a form that errors is worse than no hint.
{
  const s = open(["--out", join(workDir, "recipes.pen")]);
  await s.start();
  const pr = async (code) => s.send(buildBatchDesignCommand(code));
  const r0 = await pr(MANY_RECTS);
  const id = idOf(r0);
  check(Boolean(id), "recipes: created the 60-rectangle frame and read its id", r0.all);

  // Get(id,(n,c)=>Print(c.bounds.width)): the visitor runs for the node AND every descendant (measured:
  // 61 calls for the frame plus its 60 rectangles), frame first. The prose must not promise a single value.
  const w = await pr(`Get(${JSON.stringify(id)},(n,c)=>Print(c.bounds.width))`);
  const widths = printed(w).split(/\s+/);
  check(!/rror/.test(w.all) && widths[0] === "400", "recipe: Get(id,(n,c)=>Print(c.bounds.width)) prints the frame's measured width FIRST", `${widths.slice(0, 4).join(" ")} | ${w.all.slice(0, 120)}`);
  check(widths.length === 61, "pinned engine behaviour: Get(id, visitor) visits the node and all of its descendants (one Print line per node)", `values=${widths.length}`);
  const w2 = await pr(`Get(${JSON.stringify(id)},(n,c)=>Print(n.id+' '+c.bounds.width))`);
  check(!/rror/.test(w2.all) && printed(w2).split(/\s+/).slice(0, 2).join(" ") === `${id} 400`, "recipe: Get(id,(n,c)=>Print(n.id+' '+c.bounds.width)) (the hint's own example) prints the id and the width, frame first", `${printed(w2).slice(0, 60)} | ${w2.all.slice(0, 120)}`);

  // c.problems: a STRING per node (or undefined), "partially clipped" / "fully clipped"; the frame's rectangles
  // that overhang it report it. The hint wording "clipping (partially or fully clipped)" is pinned to this.
  const pf = await pr(`var out=[];Get(${JSON.stringify(id)},(n,c)=>{out.push(c.problems===undefined?"-":typeof c.problems+":"+c.problems)});Print(out.join("|"))`);
  const pvals = printed(pf).split("|");
  const kindsSeen = [...new Set(pvals.map((v) => v.replace(/^string:(.*)$/, "string:$1")))].sort();
  record("recipe: c.problems values across the frame and its 60 rectangles", kindsSeen.join(", "));
  check(!/rror/.test(pf.all) && pvals.length === 61, "recipe: the c.problems visitor runs on every node of the frame without an error", `values=${pvals.length} ${pf.all.slice(0, 120)}`);
  check(pvals.some((v) => v === "string:partially clipped") && pvals.every((v) => v === "-" || /^string:(partially|fully) clipped$/.test(v)),
    "pinned engine behaviour: c.problems is a string, `partially clipped` or `fully clipped`, undefined when the node has no problem (the 400x300 frame clips overhanging rectangles)", kindsSeen.join(", "));

  // Print(FindEmptySpace({width:50,height:50})): the hint for the removed find_empty_space_on_canvas
  const fes = await pr("Print(FindEmptySpace({width:50,height:50}))");
  check(!/rror/.test(fes.all) && /## Print output\n\S/.test(fes.out), "recipe: Print(FindEmptySpace({width:50,height:50})) prints a position", `${printed(fes)} | ${fes.all.slice(0, 120)}`);
  record("recipe: FindEmptySpace reply", printed(fes));
  await s.quit();

  // The steering sentence "do not call Export inside batch_design": a raw Export with a RELATIVE directory is
  // resolved against the DOCUMENT's directory (measured), not the engine's working directory: it lands inside the
  // project, next to the .pen, with none of the adapter's containment or overwrite list applied.
  const docDir = join(workDir, "rel-doc");
  mkdirSync(docDir, { recursive: true });
  const rs = open(["--out", join(docDir, "rel.pen")]);
  await rs.start();
  const mk = await rs.send(buildBatchDesignCommand('var rf=I(document,{type:"frame",layout:"none",width:20,height:20,fill:"#00FF00"});Print("ID:"+rf);'));
  const rid = idOf(mk);
  await rs.send(buildBatchDesignCommand(`Export([${JSON.stringify(rid)}],"png","rel-export-dir")`));
  const underCwd = existsSync(join(cwd, "rel-export-dir")) ? readdirSync(join(cwd, "rel-export-dir")).filter((f) => f.endsWith(".png")) : [];
  const nextToDoc = existsSync(join(docDir, "rel-export-dir")) ? readdirSync(join(docDir, "rel-export-dir")).filter((f) => f.endsWith(".png")) : [];
  record("recipe (steering): raw Export with a relative directory lands", nextToDoc.length ? "next to the document (relative to the .pen's directory)" : underCwd.length ? "under the engine's working directory" : "nowhere found");
  check(nextToDoc.length === 1 && underCwd.length === 0, "pinned engine behaviour: a raw Export with a relative directory is resolved against the document's directory, not the engine's working directory", `nextToDoc=${nextToDoc.join(",") || "nothing"} cwd=${underCwd.join(",") || "nothing"}`);
  await rs.quit();
}

// 12. a file with an unrecognised version, opened via --in: record the engine's answer
{
  const f = join(workDir, "version.pen");
  const d = JSON.parse(readFileSync(seed, "utf8"));
  d.version = "99.0";
  writeFileSync(f, JSON.stringify(d));
  const before = readFileSync(f);
  {
    // control: the unmodified document loads its three nodes, so a different answer below is the version's doing
    const c = join(workDir, "version-control.pen");
    copyFileSync(seed, c);
    const cs = open(["--out", c, "--in", c]);
    await cs.start();
    const cn = newCountNonce();
    const cr = await cs.send(buildCountCommand(cn));
    await cs.quit();
    check(parseCountReply(cr.all, cn) === 3, "control: an unmodified copy of the seed document loads its 3 top-level nodes", cr.all);
  }
  const s = open(["--out", f, "--in", f]);
  let answer;
  try {
    const started = await s.start();
    if (started) {
      const nonce = newCountNonce();
      const r = await s.send(buildCountCommand(nonce));
      const loadedCount = parseCountReply(r.all, nonce);
      answer = loadedCount === 0 ? "opens EMPTY (0 top-level nodes loaded, no error): the save sentinel is the only guard" : `opens; top-level nodes loaded=${loadedCount}`;
      // an edit on the (possibly empty) document, then idle: the engine must not write the file by itself
      await s.send(buildBatchDesignCommand('I(document,{type:"frame",name:"v-edit",width:20,height:20})'));
      const changed = await watchQuiet([f]);
      check(changed.length === 0 && Buffer.compare(readFileSync(f), before) === 0, `no engine write to the unrecognised-version file in a ${IDLE_WINDOW_MS / 1000} s idle window after an edit (mtime polling)`, changed.join(","));
    } else {
      answer = `exits (code ${s.exit?.code}): ${strip(s.err || s.out).split("\n").find((l) => l.trim()) ?? ""}`;
    }
  } catch (e) {
    answer = `no prompt: ${e.message}`;
  }
  record("--in with an unrecognised document version", answer);
  const PIN_VERSION = "opens-empty";
  const kind = answer.startsWith("opens EMPTY") ? "opens-empty" : answer.startsWith("opens") ? "opens-loaded" : "refuses";
  check(kind === PIN_VERSION, "pinned engine behaviour: unrecognised document version", `observed=${kind}`);
  await s.quit();
  check(Buffer.compare(readFileSync(f), before) === 0, "opening the unrecognised-version file did not rewrite it");
}

// 13. canary credential: does the engine itself echo the credential anywhere? Run in a scratch HOME so
//     every file the engine writes there is listed and scanned, and the real HOME never sees the canary.
{
  const canary = `CANARY-${randomBytes(12).toString("hex")}`;
  const forms = [canary, Buffer.from(canary).toString("base64"), encodeURIComponent(canary)];
  canaryForms.push(...forms);
  const scratchHome = join(workDir, "canary-home");
  mkdirSync(scratchHome, { recursive: true });
  const f = join(workDir, "canary.pen");
  const s = open(["--out", f], { key: canary, home: scratchHome });
  let text = "";
  try {
    await s.start();
    text += s.startup + s.startupErr;
    const r = await s.send(buildBatchDesignCommand('I(document,{type:"frame",width:10,height:10})'));
    text += r.all;
    const sv = await s.send(buildSaveCommand());
    text += sv.all;
    const g = await s.send("get_app_state()");
    text += g.all;
  } catch (e) {
    text += String(e.message);
  }
  await s.quit();
  const echoed = forms.filter((x) => text.includes(x));
  record("engine echoes a canary credential in its own output (raw/base64/urlencoded)", echoed.length ? `yes (${echoed.length} form(s)): the adapter redactor is load-bearing` : "no");
  const hit = (buf) => forms.filter((x) => buf.includes(x) || buf.includes(Buffer.from(x).toString("latin1")));
  const savedHits = existsSync(f) ? hit(readFileSync(f).toString("latin1")) : [];
  check(existsSync(f) && savedHits.length === 0, "the saved .pen holds no form of the canary credential (bytes scanned)", `forms=${savedHits.length}`);
  const homeFiles = [];
  const walk = (dir, rel = "") => {
    for (const e of readdirSync(dir, { withFileTypes: true })) {
      const r2 = join(rel, e.name);
      if (e.isDirectory()) walk(join(dir, e.name), r2);
      else if (e.isFile()) homeFiles.push(r2);
    }
  };
  walk(scratchHome);
  const homeHits = homeFiles.filter((r2) => { try { return hit(readFileSync(join(scratchHome, r2)).toString("latin1")).length > 0; } catch { return false; } });
  record("files the engine wrote under HOME in a session", homeFiles.length ? `${homeFiles.length}: ${homeFiles.slice(0, 8).join(", ")}` : "none");
  check(homeHits.length === 0, "no file the engine wrote under HOME contains a form of the canary credential", homeHits.join(","));
  const redacted = redact(`x ${canary} y ${forms[1]} z ${forms[2]}`);
  check(forms.every((x) => !redacted.includes(x)), "positive control: this probe's own redactor removes the canary in all three forms");
}

// 14. install method: npm ci --ignore-scripts from the committed lockfile yields a working engine
{
  const ci = join(workDir, "ci-prefix");
  mkdirSync(ci, { recursive: true });
  const lockPath = join(penCliDir, "package-lock.json");
  copyFileSync(join(penCliDir, "package.json"), join(ci, "package.json"));
  copyFileSync(lockPath, join(ci, "package-lock.json"));
  const lock = JSON.parse(readFileSync(lockPath, "utf8"));
  const withScripts = Object.entries(lock.packages ?? {}).filter(([, v]) => v.hasInstallScript).map(([k]) => k.replace(/^.*node_modules\//, ""));
  record("lockfile packages declaring an install script (skipped by --ignore-scripts)", withScripts.length ? withScripts.join(", ") : "none");
  const npmV = spawnSync("npm", ["--version"], { encoding: "utf8" }).stdout.trim();
  const t0 = Date.now();
  // the credential is not in this environment: an install script (if any ran) could not read it
  const inst = spawnSync("npm", ["ci", "--ignore-scripts", "--no-audit", "--no-fund"], {
    cwd: ci, encoding: "utf8", timeout: 300000, env: { PATH: process.env.PATH ?? "", HOME },
  });
  record("install method", `npm ${npmV} ci --ignore-scripts rc=${inst.status} in ${Math.round((Date.now() - t0) / 1000)} s; node ${process.version}`);
  check(inst.status === 0, "npm ci --ignore-scripts from the committed lockfile succeeds", `${inst.stderr}`.slice(-200));
  const sameLock = createHash("sha256").update(readFileSync(lockPath)).digest("hex") === createHash("sha256").update(readFileSync(join(ci, "package-lock.json"))).digest("hex");
  check(sameLock, "npm ci left the lockfile byte-identical");
  const ciBin = join(ci, "node_modules/@pen.dev/cli/dist/index.mjs");
  const ciVer = (() => { try { return JSON.parse(readFileSync(join(ci, "node_modules/@pen.dev/cli/package.json"), "utf8")).version; } catch { return ""; } })();
  check(ciVer === pin, "the --ignore-scripts install holds the pinned engine version", `installed=${ciVer || "unreadable"} pin=${pin}`);
  if (inst.status === 0 && existsSync(ciBin)) {
    const f = join(workDir, "ci-session.pen");
    const s = open(["--out", f], { bin: ciBin });
    await s.start();
    const r = await s.send(buildBatchDesignCommand('I(document,{type:"frame",width:20,height:20})'));
    const sv = await s.send(buildSaveCommand());
    await s.quit();
    check(/^OK\b/.test(r.out) && isSaved(sv, f), "an engine installed with --ignore-scripts starts, applies an edit and saves", `${r.all.slice(0, 80)} | ${sv.all.slice(0, 80)}`);
    const st = spawnSync(process.execPath, [ciBin, "status"], { encoding: "utf8", cwd, env: engineEnv(), timeout: 60000 });
    check(st.status === 0 && /Active/.test(strip(`${st.stdout}\n${st.stderr}`)), "pen status reports Active from the --ignore-scripts install");
  }
  rmSync(ci, { recursive: true, force: true }); // the tree is large: free it before the adapter cases
}

// ---------------------------------------------------------------------------
// Adapter cases: the INSTALLED adapter over MCP stdio.
{
  const { installAdapter, connectAdapter } = await imp(testLib, "pencil-adapter-roundtrip.mjs");
  const installDir = installAdapter(join(workDir, "install"));
  const connect = async (opts = {}) => {
    const { key = KEY, penBinary = penBin, extraEnv = {} } = opts;
    const a = await connectAdapter({ installDir, penBinary, keys: { PEN_CLI_KEY: key }, extraEnv });
    adapters.add(a);
    return a;
  };
  const closeAdapter = async (a) => { await a.close(); adapters.delete(a); };
  const firstLine = (text) => String(text).split("\n")[0];
  const pen = join(workDir, "adapter.pen");

  // A1. round trip: open, batch_design x2, save, reload, screenshot, export, removed tools
  let a = await connect();
  let nodeId;
  try {
    const o = await a.call("open_document", { filePath: pen });
    check(!o.isError, "adapter: open_document on a new path", o.text);
    const b1 = await a.call("batch_design", { operations: 'f=I(document,{type:"frame",width:200,height:100,fill:"#FFFFFF"})\nt=I(f,{type:"text",content:"probe"})\nPrint("ID:"+f)' });
    check(!b1.isError, "adapter: batch_design with I(...) aliases", b1.text);
    nodeId = /ID:([A-Za-z0-9_-]+)/.exec(b1.text)?.[1];
    const b2 = await a.call("batch_design", { operations: 'g=I(document,{type:"frame",width:50,height:50})' });
    check(!b2.isError, "adapter: second consecutive batch_design", b2.text);
    const sv = await a.call("save");
    check(!sv.isError, "adapter: explicit save", sv.text);
  } finally { await closeAdapter(a); }
  check(statSync(pen).size > 96, "adapter: saved file is larger than the 96-byte empty document");
  a = await connect();
  try {
    const o = await a.call("open_document", { filePath: pen });
    const n = /\((\d+) top-level node/.exec(o.text);
    check(!o.isError && n && Number(n[1]) >= 2, "adapter: reopen in a fresh session loads the saved nodes", o.text);
    const shot = await a.call("get_screenshot", { nodeId });
    check(!shot.isError, "adapter: get_screenshot", shot.text.slice(0, 120));
    const ex = await a.call("export_nodes", { nodeIds: [nodeId], outputDir: join(dirname(pen), "adapter-exports"), format: "png" });
    check(!ex.isError, "adapter: export_nodes", ex.text.slice(0, 120));
    for (const name of REMOVED) {
      const r = await a.call(name, {});
      check(r.isError && r.text.includes(removedToolHint(name)), `adapter: removed tool ${name} answers with its exact hint`, r.text.slice(0, 160));
    }
  } finally { await closeAdapter(a); }

  // A2. the adapter's DEFAULT binary resolution: HOME is the real prefix, no --pencil-binary flag
  if (USING_OVERRIDE) {
    skip("adapter: default binary resolution", "PROBE_PEN_BINARY is set for this run, so the default prefix is not the engine under test");
  } else {
    const d = join(workDir, "adapter-default.pen");
    a = await connect({ penBinary: "" });
    try {
      const o = await a.call("open_document", { filePath: d });
      const e = await a.call("batch_design", { operations: 'dd=I(document,{type:"frame",width:12,height:12})' });
      const sv = await a.call("save");
      check(!o.isError && !e.isError && !sv.isError && statSync(d).size > 96, "adapter: the default binary resolution (HOME at the real prefix, no override) opens, edits and saves", `${o.text.slice(0, 80)} | ${e.text.slice(0, 80)} | ${sv.text.slice(0, 80)}`);
      check(!/--pencil-binary override in use/.test(a.stderr()), "adapter: the default resolution did not go through the --pencil-binary override", a.stderr().slice(0, 160));
    } finally { await closeAdapter(a); }
  }

  // A3a. delete-every-node over a non-empty file: refused as `empty`, marker on line 1 of the TOOL RESULT
  const emptied = join(workDir, "adapter-emptied.pen");
  a = await connect();
  try {
    await a.call("open_document", { filePath: emptied });
    const mk = await a.call("batch_design", { operations: 'e1=I(document,{type:"frame",width:10,height:10})\nPrint("ID:"+e1)' });
    const eid = /ID:([A-Za-z0-9_-]+)/.exec(mk.text)?.[1];
    const nodesBefore = JSON.parse(readFileSync(emptied, "utf8")).children?.length;
    const r = await a.call("batch_design", { operations: `D(${JSON.stringify(eid)})` });
    check(r.isError && /^REFUSED save: \[reason=empty\] /.test(firstLine(r.text)), "adapter: deleting every node of a saved file is refused, `REFUSED save: [reason=empty]` is line 1 of the tool result", firstLine(r.text));
    check(nodesBefore === 1 && JSON.parse(readFileSync(emptied, "utf8")).children?.length === 1, "adapter: the `empty` refusal left the saved node on disk", `before=${nodesBefore}`);
  } finally { await closeAdapter(a); }

  // A3b. a file rewritten behind the session: refused as `stale` (#11168), no engine write afterwards
  const stale = join(workDir, "adapter-stale.pen");
  a = await connect();
  try {
    await a.call("open_document", { filePath: stale });
    await a.call("batch_design", { operations: 'a1=I(document,{type:"frame",width:10,height:10})' });
    copyFileSync(pen, stale);
    const before = readFileSync(stale, "utf8");
    const r = await a.call("batch_design", { operations: 'a2=I(document,{type:"frame",width:11,height:11})' });
    check(r.isError && /^REFUSED save: \[reason=stale\] /.test(firstLine(r.text)), "adapter: a save over a file rewritten behind the session is refused, `REFUSED save: [reason=stale]` is line 1 of the tool result", firstLine(r.text));
    check(readFileSync(stale, "utf8") === before, "adapter: the stale refusal left the file byte-identical");
    const changed = await watchQuiet([stale]);
    check(changed.length === 0 && readFileSync(stale, "utf8") === before, `adapter: no write to the stale file in a ${IDLE_WINDOW_MS / 1000} s idle window after the refusal (mtime polling)`, changed.join(","));
    const sv = await a.call("save");
    check(sv.isError && /^REFUSED save: \[reason=refusal-pending\] /.test(firstLine(sv.text)), "adapter: an explicit save while the refusal is pending is refused as refusal-pending", firstLine(sv.text));
  } finally { await closeAdapter(a); }

  // A4. a file removed behind a LIVE session is recreated, with the NOTE (ruling 2)
  const removed = join(workDir, "adapter-removed.pen");
  a = await connect();
  try {
    await a.call("open_document", { filePath: removed });
    await a.call("batch_design", { operations: 'r1=I(document,{type:"frame",width:10,height:10})' });
    rmSync(removed);
    const r = await a.call("batch_design", { operations: 'r2=I(document,{type:"frame",width:11,height:11})' });
    const back = existsSync(removed) ? JSON.parse(readFileSync(removed, "utf8")).children?.length : 0;
    check(!r.isError && /had been removed from disk/.test(r.text) && back === 2, "adapter: a file removed behind a live session is recreated from the session with the removal NOTE", `${r.text.slice(0, 160)} children=${back}`);
  } finally { await closeAdapter(a); }

  // A4b. Export of html over the open document through raw DSL: record what the adapter does (known engine behaviour)
  {
    const ow = join(workDir, "adapter-overwrite.pen");
    a = await connect();
    try {
      await a.call("open_document", { filePath: ow });
      const mk = await a.call("batch_design", { operations: 'o1=I(document,{type:"frame",width:10,height:10,fill:"#00FF00"})\nPrint("ID:"+o1)' });
      const oid = /ID:([A-Za-z0-9_-]+)/.exec(mk.text)?.[1];
      const r = await a.call("batch_design", { operations: `Export([${JSON.stringify(oid)}],"html-css",${JSON.stringify(ow)})` });
      const html = /^<!doctype html>/i.test(readFileSync(ow, "utf8"));
      record("adapter: raw DSL Export html-css over the open document", `file ${html ? "OVERWRITTEN with html" : "intact"}; result: ${firstLine(r.text).slice(0, 120)}`);
      check(html === true, "pinned adapter behaviour: a raw-DSL Export html over the open document destroys it (the accepted-residual boundary, reported)", `html=${html}`);
      const after = await a.call("batch_design", { operations: 'o2=I(document,{type:"frame",width:11,height:11})' });
      check(after.isError && /^REFUSED save: \[reason=unrecognized\] /.test(firstLine(after.text)), "adapter: the next edit after such an overwrite is refused as `unrecognized` (the overwritten file is never saved over)", firstLine(after.text));
    } finally { await closeAdapter(a); }
  }

  // A5. unrecognised version via open_document: load fidelity (ruling 6) refuses it, nothing is modified
  {
    const vf = join(workDir, "adapter-version.pen");
    const d = JSON.parse(readFileSync(seed, "utf8")); d.version = "99.0"; writeFileSync(vf, JSON.stringify(d));
    const before = readFileSync(vf);
    a = await connect();
    try {
      const o = await a.call("open_document", { filePath: vf });
      record("adapter open_document on an unrecognised document version", `${o.isError ? "isError" : "ok"}: ${o.text.slice(0, 160)}`);
      check(o.isError && /top-level node\(s\) on disk but loaded empty/.test(o.text), "adapter: open_document refuses a file the engine loads with fewer top-level nodes (load fidelity)", o.text.slice(0, 160));
      check(Buffer.compare(readFileSync(vf), before) === 0, "adapter: the refused open did not modify the file");
    } finally { await closeAdapter(a); }
  }

  // A6. canary credential through the adapter: stderr and every tool result carry no form of it
  {
    const canary = `CANARY-${randomBytes(12).toString("hex")}`;
    const forms = [canary, Buffer.from(canary).toString("base64"), encodeURIComponent(canary)];
    canaryForms.push(...forms);
    const cf = join(workDir, "adapter-canary.pen");
    a = await connect({ key: canary });
    let seen = "";
    try {
      for (const [tool, args] of [["open_document", { filePath: cf }], ["batch_design", { operations: 'c1=I(document,{type:"frame",width:9,height:9})' }], ["get_editor_state", {}], ["save", {}]]) {
        const r = await a.call(tool, args); seen += r.text;
      }
    } finally { await closeAdapter(a); }
    seen += a.stderr();
    check(forms.every((x) => !seen.includes(x)), "adapter: a canary credential appears nowhere in adapter stderr or any tool result (raw, base64, urlencoded)");
    const fileHits = existsSync(cf) ? forms.filter((x) => readFileSync(cf).toString("latin1").includes(x)) : [];
    check(existsSync(cf) && fileHits.length === 0, "adapter: the saved .pen holds no form of the canary credential");
  }

  // A7. load fidelity acceptance (ruling 6): every committed design .pen loads with >= its top-level nodes
  {
    const env = Object.fromEntries(Object.entries(process.env).filter(([k]) => !k.startsWith("GIT_")));
    const ls = spawnSync("git", ["-C", repoRoot, "ls-files", "-z", "--", "knowledge-base/product/design"], { encoding: "utf8", env });
    if (ls.status !== 0) throw new Error(`git ls-files failed: ${String(ls.stderr).slice(0, 120)}`);
    const files = ls.stdout.split("\0").filter((x) => x.endsWith(".pen")).sort();
    check(files.length >= 50, "acceptance: the committed design .pen set was enumerated", `count=${files.length}`);
    const accept = join(workDir, "accept");
    mkdirSync(accept, { recursive: true });
    const rows = [];
    const queue = files.map((rel, i) => ({ rel, i }));
    const worker = async () => {
      const ad = await connect();
      try {
        for (let job = queue.shift(); job; job = queue.shift()) {
          const { rel, i } = job;
          const bytes = readFileSync(join(repoRoot, rel));
          let disk = null;
          try { const c = JSON.parse(bytes.toString("utf8"))?.children; if (Array.isArray(c)) disk = c.length; } catch { /* not a valid document */ }
          const copy = join(accept, `${String(i).padStart(3, "0")}-${basename(rel)}`);
          writeFileSync(copy, bytes);
          const o = await ad.call("open_document", { filePath: copy });
          const m = /\((\d+|unknown) top-level node\(s\) loaded\)/.exec(o.text);
          rows.push({ rel, disk, loaded: m ? (m[1] === "unknown" ? null : Number(m[1])) : null, isError: o.isError, text: o.text, intact: Buffer.compare(readFileSync(copy), bytes) === 0 });
        }
      } finally { await closeAdapter(ad); }
    };
    const t0 = Date.now();
    await Promise.all(Array.from({ length: 6 }, worker));
    rows.sort((x, y) => x.rel.localeCompare(y.rel));
    // hyphens become spaces in the recorded name: a long hyphenated path with digits reads as a key to the transcript scanner
    const label = (rel) => rel.replace("knowledge-base/product/design/", "").replace(/[-/]/g, " ");
    for (const r of rows) record(`acceptance ${label(r.rel)}`, `disk=${r.disk ?? "invalid"} loaded=${r.loaded ?? (r.isError ? "REFUSED" : "unknown")}`);
    const valid = rows.filter((r) => r.disk !== null);
    // A file the engine refuses to open at all is not a silent drop (the adapter reports `open failed:` and
    // runs nothing); it is recorded loudly and pinned. A file that LOADS with fewer nodes is the ruling-6 risk.
    const refused = valid.filter((r) => r.isError);
    const fewer = valid.filter((r) => !r.isError && (r.loaded === null || r.loaded < r.disk));
    for (const r of refused) record(`acceptance REFUSED ${label(r.rel)}`, r.text.split(/ at [A-Za-z_$]/)[0]);
    record("load-fidelity acceptance summary", `${rows.length} committed design .pen files, ${valid.length} parse as documents, ${valid.length - refused.length - fewer.length} load faithfully, ${refused.length} refused by the engine, ${fewer.length} load with fewer top-level nodes, ${Math.round((Date.now() - t0) / 1000)} s`);
    check(rows.length === files.length, "acceptance: every committed file was evaluated", `evaluated=${rows.length} of ${files.length}`);
    check(fewer.length === 0, "acceptance (ruling 6): no committed design .pen loads with fewer top-level nodes than on disk", fewer.map((r) => `${r.rel}:${r.disk}->${r.loaded ?? "unknown"}`).join(" "));
    // pinned: committed files whose content the engine rejects outright (schema-invalid: node type "rect" is not a node type).
    // A repaired file must leave this list; a new rejection fails here instead of passing silently.
    const PINNED_ENGINE_REJECTS = ["knowledge-base/product/design/dashboard/dashboard-load-states.pen"];
    const gotRejects = refused.map((r) => r.rel).sort();
    check(JSON.stringify(gotRejects) === JSON.stringify(PINNED_ENGINE_REJECTS), "acceptance: the committed files the engine refuses to open are exactly the pinned set", `observed=${gotRejects.join(",") || "none"}`);
    check(rows.every((r) => r.intact), "acceptance: opening every file left every copy byte-identical", rows.filter((r) => !r.intact).map((r) => r.rel).join(","));
  }
}
}

// ---------------------------------------------------------------------------
// Run, then always release every child; a tooling error is a verdict, not a stack trace.
let verdict = null;
try {
  await runCases();
} catch (e) {
  if (e instanceof ProbeStop) verdict = { code: e.code, line: e.verdict };
  else verdict = { code: failures > 0 ? 1 : 3, line: `PROBE TOOLING ERROR (nothing further was asserted): ${redact(String(e?.message ?? e)).replace(/\s+/g, " ").slice(0, 300)}` };
} finally {
  await finish();
}
if (verdict) {
  // A check that already FAILED must not be hidden behind a tooling error: the failure count comes first.
  if (failures > 0 && !verdict.line.startsWith("PROBE FAILED")) console.log(`PROBE FAILED (${failures})`);
  emit(verdict.line);
  process.exit(verdict.code);
}

// ---------------------------------------------------------------------------
// Redacted transcript.
let leaked = false;
if (transcriptPath) {
  const header = [
    `# Engine contract probe transcript`,
    ``,
    `engine: @pen.dev/cli@${pin} probed ${new Date().toISOString().slice(0, 10)}`,
    `scope: engine and adapter cases${skipped.length ? ` (skipped: ${skipped.join("; ")})` : ""}`,
    `result: ${failures === 0 ? "all cases passed" : `${failures} case(s) FAILED`} (${nPass} passed)`,
    ``,
    "Credential, `$HOME`, absolute paths, UUIDs (including a document `fileToken`) and account lines are scrubbed by `plugins/soleur/test/lib/scrub-transcript.mjs`; `pen status` output is never recorded.",
    ``,
    "```text",
  ].join("\n");
  const body = scrub.scrubTranscript(LOG.join("\n"), {
    secrets: [KEY, ...canaryForms],
    paths: [[realpathSync(workDir), "<WORK>"], [workDir, "<WORK>"], [HOME, "<HOME>"]],
  });
  const text = `${header}\n${body}\n\`\`\`\n`;
  const leaks = scrub.findLeaks(text, { secrets: [KEY] });
  mkdirSync(dirname(transcriptPath), { recursive: true });
  const tmp = join(workDir, "transcript.md");
  writeFileSync(tmp, text);
  const g = scrub.gitleaksFindings(tmp);
  if (leaks.length > 0 || !g.ok) {
    leaked = true;
    console.log(`FAIL transcript not written: ${leaks.length} leak(s) (${leaks.slice(0, 3).map((l) => (l.startsWith("key-shaped") ? l.slice(0, 22) : l.split(":")[0])).join(",")}) gitleaks=${g.ok ? "clean" : g.missing ? "missing" : "finding"}`);
  } else {
    writeFileSync(transcriptPath, text);
    console.log(`transcript written: ${transcriptPath.replace(HOME, "~")}`);
  }
}

if (failures > 0 || leaked) {
  console.log(`PROBE FAILED (${failures + (leaked ? 1 : 0)})`);
  process.exit(1);
}
if (skipped.length > 0) {
  console.log(`PROBE INCOMPLETE (${skipped.length} case(s) skipped: ${skipped.join("; ")}); this is NOT a PROBE OK`);
  process.exit(3);
}
console.log("PROBE OK");
process.exit(0);
NODE

PROBE_CRED="$KEY" node "$work/probe.mjs" "$SCRIPT_DIR" "$SCRIPT_DIR/../../../test/lib" "$work" "$PENCIL_BIN" "$PIN" "$TRANSCRIPT_PATH" "$SCRIPT_DIR/pen-cli" "$REPO_ROOT" "$OVERRIDE"
rc=$?
exit "$rc"
