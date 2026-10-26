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
# check_deps.sh. It is deliberately not a *.test.sh: it needs the credential, so it must
# never be a required CI job or an auto-registered suite.
#
#   doppler run -p soleur -c dev -- bash plugins/soleur/skills/pencil-setup/scripts/engine-contract-probe.sh
#
# Credential: resolved ONCE as ${PEN_CLI_KEY:-${PENCIL_CLI_KEY:-}} (empty or whitespace counts
# as unset), handed to every child explicitly as PEN_CLI_KEY, never printed (every line goes
# through a redactor that knows the raw, JSON, URL and base64 forms), never written to the
# transcript. Account details from `pen status` are never recorded.
#
# Engine-only cases (this file, no adapter needed):
#   0  `pen status` reports Active (a fail-open engine runs with a bad key: it must not yield OK)
#   1  `pen interactive --help` signatures == REPL_SURFACE for the REPL tools; the 9 removed tools absent
#   2  startup banner, then the prompt `pen > ` (raw coloured bytes recorded)
#   3  `OK` reply prefix; `## Print output` section
#   4  nonce-tagged top-level count round trip (the save sentinel's memory probe)
#   5  `save()` -> exactly `Saved <path>`; the file holds the nodes
#   6  a failing save prints `Save failed:` and writes nothing
#   7  each of the 9 removed names answers `Unknown tool:`
#   8  export: every format has the right magic bytes; scale and quality change the output
#   9  read_skill on every guide path, each followed by an intact save() reply
#  10  no engine write outside save(): positive control, then exit(), SIGTERM, SIGKILL
#  11  batch_design Export / image fill with an absolute url (recorded and pinned, CTO ruling 11.2)
#  12  a file with an unrecognised `version` opened via --in (recorded and pinned)
#  13  canary credential: the engine's own output is scanned in raw, base64 and URL-encoded forms
# Adapter cases (TODO(adapter), gated by ADAPTER_READY below): round trip through the INSTALLED
# adapter, empty-over-non-empty refusal, stale refusal behind a real engine, open_document on the
# unrecognised-version file, canary through adapter stderr and every tool result.
#
# A timed autosave that fires outside the case-10 observation window (2 s after the edit) would not
# be seen: stated limit. Atomicity of the engine's write and behaviour on a file written by a newer
# Desktop are likewise not asserted beyond case 12's recorded answer.
#
# Output: PASS/FAIL/RECORD lines, then one verdict line. The redacted transcript goes to
# knowledge-base/project/specs/feat-one-shot-11156-11168-pen-cli-migration/probe-transcript.md when
# that directory exists (PROBE_TRANSCRIPT overrides the path), scrubbed by
# test/lib/scrub-transcript.mjs and checked with gitleaks; a leak fails the run.
#
# Exit codes: 0  every case passed (engine AND adapter cases)
#             1  a contract check failed, or the credential is not Active, or the transcript leaked
#             3  PROBE SKIPPED (no key) or tooling missing: nothing was asserted
#             4  every engine case passed but the adapter cases are not wired yet (TODO(adapter)):
#                an incomplete run is never reported as PROBE OK

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

PENCIL_BIN="${PENCIL_BINARY:-$HOME/.local/share/pen-cli/node_modules/.bin/pen}"
if [[ ! -e "$PENCIL_BIN" ]]; then
  echo "UNRESOLVED: pen binary not found at $PENCIL_BIN (run: bash $SCRIPT_DIR/check_deps.sh --auto, or set PENCIL_BINARY)" >&2
  exit 3
fi

# The default binary must pass the same identity rule check_deps.sh and the adapter apply
# (the real .bin/pen resolves to the installed package's declared bin.pen target).
if [[ -z "${PENCIL_BINARY:-}" ]]; then
  if ! resolved_pen="$(bash -c 'f="$1"; set --; source "$f"; detect_headless_cli' _ "$SCRIPT_DIR/check_deps.sh" 2>/dev/null)" || [[ -z "$resolved_pen" ]]; then
    echo "FAIL the default .bin/pen does not pass the check_deps.sh identity rule: $PENCIL_BIN"
    echo "PROBE FAILED (1)"
    exit 1
  fi
  PENCIL_BIN="$resolved_pen"
fi

PIN="$(sed -n 's/^PEN_CLI_VERSION="\([0-9][0-9.]*\)"$/\1/p' "$SCRIPT_DIR/check_deps.sh" | head -1)"
[[ -n "$PIN" ]] || { echo "UNRESOLVED: could not read PEN_CLI_VERSION from check_deps.sh" >&2; exit 3; }

REPO_ROOT="$(cd "$SCRIPT_DIR/../../../../.." && pwd)"
SPEC_DIR="$REPO_ROOT/knowledge-base/project/specs/feat-one-shot-11156-11168-pen-cli-migration"
TRANSCRIPT_PATH="${PROBE_TRANSCRIPT:-}"
if [[ -z "$TRANSCRIPT_PATH" && -d "$SPEC_DIR" ]]; then
  TRANSCRIPT_PATH="$SPEC_DIR/probe-transcript.md"
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
  chmodSync, copyFileSync, existsSync, mkdirSync, readFileSync, readdirSync, realpathSync, statSync, writeFileSync,
} from "node:fs";
import { dirname, join } from "node:path";
import { pathToFileURL } from "node:url";
import { randomBytes } from "node:crypto";

const [scriptsDir, testLib, workDir, penBin, pin, transcriptPath] = process.argv.slice(2);
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
// TODO(adapter): the shared scrubber is written by the stub/transcript work; this path is its contract.
const scrub = await imp(testLib, "scrub-transcript.mjs");

// ---------------------------------------------------------------------------
// Output. Every line passes through redact(): the credential in every form it can take.
let failures = 0;
let nPass = 0;
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

const strip = (s) => String(s).replace(/\x1b\[[0-9;]*[a-zA-Z]/g, "");
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const isGone = (pid) => {
  try { process.kill(pid, 0); return false; } catch (e) { return e.code === "ESRCH"; }
};

if (!nodeVersionOk(process.version)) {
  console.error(`UNRESOLVED: node ${process.version} is below the engine floor 22.19.0`);
  process.exit(3);
}

const cwd = join(workDir, "cwd"); // private empty cwd for every engine child
mkdirSync(cwd, { recursive: true });
const engineEnv = (key = KEY) => ({ PATH: process.env.PATH ?? "", HOME, PEN_CLI_KEY: key });

// ---------------------------------------------------------------------------
// A REPL session driven directly over pipes. Error replies arrive on stderr, success on stdout
// (measured), so a reply is both streams after the command, up to the prompt at the END of the
// stdout buffer followed by a quiet period.
class Engine {
  constructor(args, { key = KEY } = {}) {
    this.out = ""; this.err = ""; this.exit = null; this.startup = "";
    this.child = spawn(process.execPath, [penBin, "interactive", ...args], {
      cwd, env: engineEnv(key), stdio: ["pipe", "pipe", "pipe"],
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
const open = (args, opts) => { const e = new Engine(args, opts); sessions.add(e); return e; };
const finish = async () => { for (const e of sessions) if (!e.exit) { e.child.kill("SIGKILL"); } };

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

const TEN_RECTS =
  'var f=I(document,{type:"frame",name:"qa",layout:"none",width:400,height:300,fill:"#ffffff"});' +
  'for(var i=0;i<60;i++){I(f,{type:"rectangle",x:(i*37)%380,y:(i*53)%280,width:20+(i%7)*9,height:15+(i%5)*11,' +
  'fill:"#"+(((i+1)*2654435)%16777216).toString(16).padStart(6,"0")});}Print("ID:"+f);';
const idOf = (reply) => /ID:([A-Za-z0-9_-]+)/.exec(reply.out)?.[1];

// ---------------------------------------------------------------------------
// 0. The credential must be Active. A bad key does NOT stop `pen interactive` (fail-open usage
//    check), so without this a probe run against a revoked key would still print PASS lines.
{
  const st = spawnSync(process.execPath, [penBin, "status"], { encoding: "utf8", cwd, env: engineEnv(), timeout: 60000 });
  const text = strip(`${st.stdout}\n${st.stderr}`);
  const active = st.status === 0 && /Active/.test(text);
  check(active, "pen status reports Active for the credential (fail-open engine guard)", active ? "" : "status was not Active (reply not recorded: it carries account details)");
  if (!active) {
    emit("PROBE FAILED (credential not Active)");
    process.exit(1);
  }
}

// installed engine == the pin this probe is run for
{
  let ver = "";
  try {
    const pkgPath = join(dirname(realpathSync(penBin)), "..", "package.json");
    ver = JSON.parse(readFileSync(pkgPath, "utf8")).version;
  } catch { /* handled by the check */ }
  check(ver === pin, "installed @pen.dev/cli version equals the check_deps.sh pin", `installed=${ver || "unreadable"} pin=${pin}`);
}

// ---------------------------------------------------------------------------
// 1. Signatures in `pen interactive --help` vs REPL_SURFACE; removed tools absent.
const REMOVED = [
  "batch_get", "snapshot_layout", "get_guidelines", "get_style_guide", "get_style_guide_tags",
  "find_empty_space_on_canvas", "search_all_unique_properties", "replace_all_matching_properties", "set_variables",
];
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
  check(stillListed.length === 0, "none of the 9 removed tools is listed in --help", stillListed.join(","));
  check(/^\s*save\(\)\s/m.test(text) || /save\(\)/.test(text), "--help documents the save() shell command");
}

// ---------------------------------------------------------------------------
// 2-5, 7, 9. One session on seed.pen: prompt, OK, print output, count, save, removed names, skills.
const seed = join(workDir, "seed.pen");
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

  // 7. removed names
  for (const name of REMOVED) {
    r = await s.send(`${name}()`);
    check(r.ok && /Unknown tool:/.test(r.all), `${name}() answers Unknown tool:`, r.all);
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

// 6. a failing save prints `Save failed:` and writes nothing
{
  const ro = join(workDir, "ro");
  mkdirSync(ro, { recursive: true });
  const target = join(ro, "x.pen");
  if (typeof process.getuid === "function" && process.getuid() === 0) {
    note("SKIP Save failed: case (running as root: a read-only directory does not fail the write)");
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
    await s.quit();
  }
}

// 8. export formats, scale and quality
{
  const s = open(["--out", join(workDir, "export.pen")]);
  await s.start();
  const r0 = await s.send(buildBatchDesignCommand(TEN_RECTS));
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

// 10. no engine write outside save(): positive control, then exit(), SIGTERM, SIGKILL
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
  for (const path of ["exit()", "SIGTERM", "SIGKILL"]) {
    const f = prep(path.replace(/\W/g, ""));
    const s = open(["--out", f, "--in", f]);
    const started = await s.start();
    const ed = await s.send(edit);
    await sleep(2000); // observation window for a timed autosave (stated limit: nothing later is seen)
    if (path === "exit()") s.child.stdin.write("exit()\n");
    else s.child.kill(path);
    for (let i = 0; i < 250 && !s.exit; i++) await sleep(20);
    const gone = isGone(s.pid) && (await waitNoProcess(f));
    check(started && /^OK\b/.test(ed.out) && gone, `edit then ${path}: the engine process is gone`, `started=${started} edit=${ed.out.slice(0, 40)} exit=${JSON.stringify(s.exit)}`);
    check(sameBytes(f, seed), `edit then ${path}: the file is byte-identical to before the session`);
  }
  note("a timed autosave firing later than 2 s after the edit is outside the observation window (stated limit)");
}

// 11. batch_design reaches path-taking host functions: record what the engine does and pin it
{
  const docDir = join(workDir, "doc-pin");
  const outside = join(workDir, "outside");
  mkdirSync(docDir, { recursive: true });
  mkdirSync(outside, { recursive: true });
  const s = open(["--out", join(docDir, "pin.pen")]);
  await s.start();
  const r0 = await s.send(buildBatchDesignCommand('var red=I(document,{type:"frame",layout:"none",width:40,height:40,fill:"#FF0000"});Print("ID:"+red);'));
  const redId = idOf(r0);
  // (a) Export through raw DSL to an absolute directory outside the document's directory
  const ex = await s.send(buildBatchDesignCommand(`Export([${JSON.stringify(redId)}],"png",${JSON.stringify(outside)})`));
  const wrote = readdirSync(outside).filter((f) => f.endsWith(".png"));
  const outsideFile = wrote[0] ? join(outside, wrote[0]) : null;
  record("batch_design Export to an absolute dir outside the document dir", wrote.length ? "writes there" : `no file (${ex.all.slice(0, 80)})`);
  // (b) does Export overwrite an existing file at that path?
  let overwrote = "n/a";
  if (outsideFile) {
    writeFileSync(outsideFile, "sentinel-not-a-png");
    const again = await s.send(buildBatchDesignCommand(`Export([${JSON.stringify(redId)}],"png",${JSON.stringify(outside)})`));
    overwrote = readFileSync(outsideFile, "latin1") === "sentinel-not-a-png" ? "no (kept the existing file)" : "yes (replaced the existing file)";
    record("batch_design Export over an existing file", `${overwrote}; reply: ${again.all.slice(0, 80)}`);
  }
  // (c) image fills with local urls: loaded or ignored?
  const probeImage = async (label, url) => {
    const a = await s.send(buildBatchDesignCommand(`var im=I(document,{type:"rectangle",width:40,height:40,fill:{type:"image",url:${JSON.stringify(url)},mode:"cover"}});Print("ID:"+im);`));
    const imId = idOf(a);
    if (!imId) return null;
    const d = join(workDir, `pin-${label}`);
    mkdirSync(d, { recursive: true });
    await s.send(buildExportCommand({ nodeIds: [imId], outputDir: d, format: "png" }));
    const f = readdirSync(d)[0];
    return f ? readFileSync(join(d, f)) : null;
  };
  let loaded = {};
  if (outsideFile) {
    // restore a real png at the outside path
    await s.send(buildBatchDesignCommand(`Export([${JSON.stringify(redId)}],"png",${JSON.stringify(outside)})`));
    const redPng = readFileSync(outsideFile);
    const missing = await probeImage("missing", join(workDir, "no-such-image.png"));
    // reference: the same rectangle filled with the colour the image holds
    const solid = await s.send(buildBatchDesignCommand('var rr=I(document,{type:"rectangle",width:40,height:40,fill:"#FF0000"});Print("ID:"+rr);'));
    const refDir = join(workDir, "pin-solid");
    mkdirSync(refDir, { recursive: true });
    await s.send(buildExportCommand({ nodeIds: [idOf(solid)], outputDir: refDir, format: "png" }));
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
    exportOverwrite: "yes (replaced the existing file)", // only <nodeId>.<format> inside the chosen directory
    imageAbs: "loaded (renders the local file's pixels)",
    imageFileUrl: "loaded (renders the local file's pixels)",
    imageTraversal: "loaded (renders the local file's pixels)",
  };
  const observed = {
    exportOutside: wrote.length ? "writes there" : "no file",
    exportOverwrite: overwrote,
    imageAbs: loaded.abs,
    imageFileUrl: loaded.fileurl,
    imageTraversal: loaded.traversal,
  };
  for (const k of Object.keys(PINNED)) {
    check(observed[k] === PINNED[k], `pinned engine behaviour: ${k}`, `observed=${observed[k]} pinned=${PINNED[k]}`);
  }
  await s.quit();
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

// 13. canary credential: does the engine itself echo the credential anywhere?
{
  const canary = `CANARY-${randomBytes(12).toString("hex")}`;
  const forms = [canary, Buffer.from(canary).toString("base64"), encodeURIComponent(canary)];
  canaryForms.push(...forms);
  const f = join(workDir, "canary.pen");
  const s = open(["--out", f], { key: canary });
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
  note("the adapter side of the canary case (stderr and every tool result) is a TODO(adapter) case below");
  const redacted = redact(`x ${canary} y ${forms[1]} z ${forms[2]}`);
  check(forms.every((x) => !redacted.includes(x)), "positive control: this probe's own redactor removes the canary in all three forms");
}

// ---------------------------------------------------------------------------
// Adapter cases. TODO(adapter): flip ADAPTER_READY once pencil-mcp-adapter.mjs speaks @pen.dev/cli and
// test/lib/pencil-adapter-roundtrip.mjs accepts `keys`. Until then they are NOT run and the verdict
// is exit 4 (incomplete), never PROBE OK.
const ADAPTER_READY = true;
async function adapterCases() {
  // TODO(adapter): everything in this function is unexercised until the adapter lands.
  const { installAdapter, connectAdapter } = await imp(testLib, "pencil-adapter-roundtrip.mjs");
  const installDir = installAdapter(join(workDir, "install"));
  const connect = (key = KEY, extraEnv = {}) =>
    connectAdapter({ installDir, binary: penBin, keys: { PEN_CLI_KEY: key }, extraEnv });
  const pen = join(workDir, "adapter.pen");

  // round trip: open, batch_design x2, save, reload, screenshot, export
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
  } finally { await a.close(); }
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
      check(r.isError && /removed|no longer|read_skill|batch_design|get_editor_state/i.test(r.text), `adapter: removed tool ${name} answers with a hint`, r.text.slice(0, 120));
    }
  } finally { await a.close(); }

  // empty document over a non-empty file behind the session: refused
  const guarded = join(workDir, "adapter-guarded.pen");
  a = await connect();
  try {
    await a.call("open_document", { filePath: guarded });
    writeFileSync(guarded, readFileSync(pen));
    const before = readFileSync(guarded, "utf8");
    const sv = await a.call("save");
    check(sv.isError && /REFUSED save:/.test(sv.text), "adapter: an empty document is refused over a non-empty file", sv.text);
    check(readFileSync(guarded, "utf8") === before, "adapter: the refused save left the file byte-identical");
  } finally { await a.close(); }

  // stale refusal behind a real engine (#11168): rewrite the file behind an open session, then edit
  const stale = join(workDir, "adapter-stale.pen");
  a = await connect();
  try {
    await a.call("open_document", { filePath: stale });
    await a.call("batch_design", { operations: 'a1=I(document,{type:"frame",width:10,height:10})' });
    copyFileSync(pen, stale);
    const before = readFileSync(stale, "utf8");
    const r = await a.call("batch_design", { operations: 'a2=I(document,{type:"frame",width:11,height:11})' });
    check(r.isError && /REFUSED save:/.test(r.text) && /reason=stale|changed on disk/i.test(r.text), "adapter: a save over a file rewritten behind the session is refused as stale", r.text);
    check(readFileSync(stale, "utf8") === before, "adapter: the stale refusal left the file byte-identical");
  } finally { await a.close(); }

  // unrecognised version via open_document: record the answer
  {
    const vf = join(workDir, "adapter-version.pen");
    const d = JSON.parse(readFileSync(seed, "utf8")); d.version = "99.0"; writeFileSync(vf, JSON.stringify(d));
    a = await connect();
    try {
      const o = await a.call("open_document", { filePath: vf });
      record("adapter open_document on an unrecognised document version", `${o.isError ? "isError" : "ok"}: ${o.text.slice(0, 160)}`);
    } finally { await a.close(); }
  }

  // canary credential through the adapter: stderr and every tool result carry no form of it
  {
    const canary = `CANARY-${randomBytes(12).toString("hex")}`;
    const forms = [canary, Buffer.from(canary).toString("base64"), encodeURIComponent(canary)];
    canaryForms.push(...forms);
    const cf = join(workDir, "adapter-canary.pen");
    a = await connect(canary);
    let seen = "";
    try {
      for (const [tool, args] of [["open_document", { filePath: cf }], ["batch_design", { operations: 'c1=I(document,{type:"frame",width:9,height:9})' }], ["get_editor_state", {}], ["save", {}]]) {
        const r = await a.call(tool, args); seen += r.text;
      }
    } finally { await a.close(); }
    seen += a.stderr();
    check(forms.every((x) => !seen.includes(x)), "adapter: a canary credential appears nowhere in adapter stderr or any tool result (raw, base64, urlencoded)");
  }
}
if (ADAPTER_READY) await adapterCases();
else note("SKIP adapter cases (TODO(adapter): round trip, empty-over-non-empty refusal, stale refusal, unrecognised version via open_document, canary through the adapter)");

await finish();

// ---------------------------------------------------------------------------
// Redacted transcript.
let leaked = false;
if (transcriptPath) {
  const header = [
    `# Engine contract probe transcript`,
    ``,
    `engine: @pen.dev/cli@${pin} probed ${new Date().toISOString().slice(0, 10)}`,
    `scope: ${ADAPTER_READY ? "engine and adapter cases" : "engine-only cases (adapter cases pending, TODO(adapter))"}`,
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
    console.log(`FAIL transcript not written: ${leaks.length} leak(s) (${leaks.slice(0, 3).map((l) => l.split(":")[0]).join(",")}) gitleaks=${g.ok ? "clean" : g.missing ? "missing" : "finding"}`);
  } else {
    writeFileSync(transcriptPath, text);
    console.log(`transcript written: ${transcriptPath.replace(HOME, "~")}`);
  }
}

if (failures > 0 || leaked) {
  console.log(`PROBE FAILED (${failures + (leaked ? 1 : 0)})`);
  process.exit(1);
}
if (!ADAPTER_READY) {
  console.log("PROBE ENGINE-ONLY OK (adapter cases not wired: TODO(adapter)); this is NOT a PROBE OK");
  process.exit(4);
}
console.log("PROBE OK");
process.exit(0);
NODE

PROBE_CRED="$KEY" node "$work/probe.mjs" "$SCRIPT_DIR" "$SCRIPT_DIR/../../../test/lib" "$work" "$PENCIL_BIN" "$PIN" "$TRANSCRIPT_PATH"
rc=$?
exit "$rc"
