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
import { readFileSync, statSync } from "node:fs";
import { join } from "node:path";
import { pathToFileURL } from "node:url";

const [scriptsDir, testLib, workDir, pencilBin] = process.argv.slice(2);
const { REPL_SURFACE } = await import(pathToFileURL(join(scriptsDir, "pencil-repl-surface.mjs")).href);
const { installAdapter, connectAdapter } = await import(pathToFileURL(join(testLib, "pencil-adapter-roundtrip.mjs")).href);

let failures = 0;
const check = (ok, label, detail = "") => {
  console.log(`${ok ? "PASS" : "FAIL"} ${label}${ok || !detail ? "" : `: ${detail}`}`);
  if (!ok) failures++;
};

// 1. signature diff against `pencil interactive --help`
const help = spawnSync(process.execPath, [pencilBin, "interactive", "--help"], {
  encoding: "utf8",
  env: { PATH: process.env.PATH, HOME: process.env.HOME, PENCIL_CLI_KEY: process.env.PENCIL_CLI_KEY },
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
  let shape = null;
  try {
    const j = JSON.parse(g.text);
    shape = Array.isArray(j) ? j.length : Array.isArray(j.nodes) ? j.nodes.length : null;
  } catch {}
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

console.log(failures === 0 ? "PROBE OK" : `PROBE FAILED (${failures})`);
process.exit(failures === 0 ? 0 : 1);
NODE

node "$work/probe.mjs" "$SCRIPT_DIR" "$SCRIPT_DIR/../../../test/lib" "$work" "$PENCIL_BIN"
rc=$?
exit "$rc"
