#!/usr/bin/env bash
# engine-contract-probe.sh — run the pencil-setup adapter against the REAL
# @pencil.dev/cli engine and check the contract the unit/stub tests only assume.
#
# This is the one test that touches the real engine. The stub integration test
# (test/pencil-adapter-stub-repl.test.ts) encodes our BELIEF about the REPL,
# which is how #11143 passed review; only this probe confirms it. Run it by
# hand whenever the @pencil.dev/cli pin in check_deps.sh is bumped (see #11156).
# It is deliberately not a *.test.sh: it needs PENCIL_CLI_KEY, so it must never
# be a required CI job or an auto-registered suite.
#
# Checks:
#   1. `pencil interactive --help` signatures == REPL_SURFACE (minus `save`)
#   2. open a new file, batch_design with the I(...) alias twice, save
#   3. a fresh adapter session reopens the file: top-level nodes loaded, file
#      larger than the 96-byte empty document
#   4. batch_get() returns the JSON shape the save sentinel parses
#
# Exit codes: 0 all checks passed; 1 a contract check failed;
#             3 UNRESOLVED (PENCIL_CLI_KEY unset or tooling missing): nothing was asserted.

set -uo pipefail

case "$-" in
  *x*)
    if [ -n "${PENCIL_CLI_KEY:+x}" ]; then
      printf '[FATAL] refusing to trace with a live credential set (see #7797)\n' >&2
      exit 78
    fi
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "${PENCIL_CLI_KEY:-}" ]]; then
  echo "UNRESOLVED: PENCIL_CLI_KEY is not set, so this probe asserted nothing." >&2
  echo "  Run: doppler run -p soleur -c dev -- bash $0" >&2
  exit 3
fi
for tool in node npm; do
  command -v "$tool" >/dev/null 2>&1 || { echo "UNRESOLVED: $tool not on PATH" >&2; exit 3; }
done

PENCIL_BIN="${PENCIL_BINARY:-$HOME/.local/node_modules/.bin/pencil}"
if [[ ! -e "$PENCIL_BIN" ]]; then
  echo "UNRESOLVED: pencil binary not found at $PENCIL_BIN (set PENCIL_BINARY)" >&2
  exit 3
fi

work="$(mktemp -d -t pencil-contract-probe.XXXXXXXX)"
[[ "$work" == /* ]] || { echo "FATAL: work dir not absolute: $work" >&2; exit 2; }
trap 'rm -rf -- "$work"' EXIT

cat > "$work/probe.mjs" <<'NODE'
import { spawnSync } from "node:child_process";
import { readFileSync, statSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const [scriptsDir, testLib, workDir, pencilBin] = process.argv.slice(2);
const { REPL_SURFACE } = await import(pathToFileURL(join(scriptsDir, "pencil-repl-surface.mjs")).href);
const { installAdapter, connectAdapter } = await import(pathToFileURL(join(testLib, "pencil-adapter-roundtrip.mjs")).href);
const { memoryTopLevelCount } = await import(pathToFileURL(join(scriptsDir, "pencil-save-gate.mjs")).href);

let failures = 0;
const check = (ok, label, detail = "") => {
  // never print the credential, even inside engine output echoed on a failure
  const safe = String(detail).split(process.env.PENCIL_CLI_KEY).join("<redacted>").slice(0, 400);
  console.log(`${ok ? "PASS" : "FAIL"} ${label}${ok || !safe ? "" : `: ${safe}`}`);
  if (!ok) failures++;
};

// 1. signature diff against `pencil interactive --help`
const help = spawnSync(process.execPath, [pencilBin, "interactive", "--help"], {
  encoding: "utf8",
  env: { PATH: process.env.PATH, HOME: process.env.HOME },
});
const text = `${help.stdout}\n${help.stderr}`.replace(/\x1b\[[0-9;]*m/g, "");
const live = {};
for (const m of text.matchAll(/^# ([a-z_]+)\(\{?\s*([^})]*?)\s*\}?\)\s*$/gm)) {
  live[m[1]] = m[2].split(",").map((k) => k.trim().replace(/\?$/, "")).filter(Boolean).sort();
}
const table = Object.fromEntries(
  Object.entries(REPL_SURFACE).filter(([t]) => t !== "save").map(([t, k]) => [t, [...k].sort()])
);
check(Object.keys(live).length > 0, "parsed tool signatures from --help", text.slice(0, 200));
check(
  JSON.stringify(Object.entries(live).sort()) === JSON.stringify(Object.entries(table).sort()),
  "REPL_SURFACE matches the installed CLI",
  `live=${JSON.stringify(live)} table=${JSON.stringify(table)}`
);

// 2-4. round trip through the INSTALLED adapter copy against the real engine
const installDir = installAdapter(join(workDir, "install"));
const pen = join(workDir, "probe.pen");
let a = await connectAdapter({ installDir, binary: pencilBin, key: process.env.PENCIL_CLI_KEY });
try {
  const o = await a.call("open_document", { filePath: pen });
  check(!o.isError, "open_document on a new path", o.text);
  const b1 = await a.call("batch_design", {
    operations: 'f=I(document,{type:"frame",width:200,height:100,fill:"#FFFFFF"})\nt=I(f,{type:"text",content:"probe"})',
  });
  check(!b1.isError, "batch_design with I(...) aliases", b1.text);
  const b2 = await a.call("batch_design", { operations: 'g=I(document,{type:"frame",width:50,height:50})' });
  check(!b2.isError, "second consecutive batch_design", b2.text);
  const g = await a.call("batch_get", {});
  // the parser the save sentinel itself uses, not a re-implementation of it
  const shape = memoryTopLevelCount(g.text);
  check(shape !== null && shape >= 2, "batch_get() returns a parseable top-level node list", g.text.slice(0, 200));
  const sv = await a.call("save");
  check(!sv.isError, "explicit save", sv.text);
} finally {
  await a.close();
}
let size = 0;
try { size = statSync(pen).size; } catch {}
check(size > 96, "saved file is larger than the 96-byte empty document", `size=${size}`);

a = await connectAdapter({ installDir, binary: pencilBin, key: process.env.PENCIL_CLI_KEY });
try {
  const o = await a.call("open_document", { filePath: pen });
  check(!o.isError, "reopen in a fresh session", o.text);
  const n = /\((\d+) top-level node/.exec(o.text);
  check(n && Number(n[1]) >= 2, "reopen loaded the saved top-level nodes", o.text);
  // the sentinel must refuse an empty document over this non-empty file only
  const g = await a.call("batch_get", {});
  check(!g.isError && g.text.length > 20, "batch_get after reopen has content", g.text.slice(0, 200));
} finally {
  await a.close();
}
const doc = JSON.parse(readFileSync(pen, "utf8"));
check(Array.isArray(doc.children) && doc.children.length >= 2, "on-disk document keeps its children", JSON.stringify(doc).slice(0, 200));

// 5. A design whose batch_get() reply exceeds 64 KiB must still save and reopen:
//    the sentinel parses the UNtruncated reply (a capped reply is not valid JSON).
const big = join(workDir, "big.pen");
a = await connectAdapter({ installDir, binary: pencilBin, key: process.env.PENCIL_CLI_KEY });
try {
  const o = await a.call("open_document", { filePath: big });
  check(!o.isError, "open_document on a new path (large design)", o.text);
  const pad = "x".repeat(500);
  const ops = Array.from({ length: 140 }, (_, i) => `n${i}=I(document,{type:"frame",name:"${pad}${i}",width:10,height:10})`).join("\n");
  const r = await a.call("batch_design", { operations: ops });
  check(!r.isError, "batch_design inserting 140 frames with long names", r.text);
  const g = await a.call("batch_design", { operations: 'extra=I(document,{type:"frame",width:5,height:5})' });
  check(!g.isError, "a second edit over a non-empty file is allowed by the sentinel", g.text);
} finally {
  await a.close();
}
let bigSize = 0;
try { bigSize = statSync(big).size; } catch {}
check(bigSize > 60000, "the large design reached disk", `size=${bigSize}`);
a = await connectAdapter({ installDir, binary: pencilBin, key: process.env.PENCIL_CLI_KEY });
try {
  const o = await a.call("open_document", { filePath: big });
  const n = /\((\d+) top-level node/.exec(o.text);
  check(!o.isError && n && Number(n[1]) >= 140, "the large design reopens with its nodes", o.text);
} finally {
  await a.close();
}

// 6. The sentinel against the REAL engine: content appears behind the session's
//    back while the session's document is empty. A save must be refused.
const guarded = join(workDir, "guarded.pen");
a = await connectAdapter({ installDir, binary: pencilBin, key: process.env.PENCIL_CLI_KEY });
try {
  const o = await a.call("open_document", { filePath: guarded });
  check(!o.isError, "open_document on a new path (sentinel check)", o.text);
  writeFileSync(guarded, readFileSync(pen));
  const before = readFileSync(guarded, "utf8");
  const sv = await a.call("save");
  check(sv.isError && /REFUSED save:/.test(sv.text), "an empty document is refused over a non-empty file", sv.text);
  check(readFileSync(guarded, "utf8") === before, "the refused save left the file byte-identical");
  writeFileSync(guarded, "# not a pen document\n");
  const garbage = await a.call("batch_design", { operations: 'z=I(document,{type:"frame",width:5,height:5})' });
  check(garbage.isError && /not a recognizable/.test(garbage.text), "an unrecognizable file is never overwritten", garbage.text);
} finally {
  await a.close();
}

console.log(failures === 0 ? "PROBE OK" : `PROBE FAILED (${failures})`);
process.exit(failures === 0 ? 0 : 1);
NODE

node "$work/probe.mjs" "$SCRIPT_DIR" "$SCRIPT_DIR/../../../test/lib" "$work" "$PENCIL_BIN"
rc=$?
exit "$rc"
