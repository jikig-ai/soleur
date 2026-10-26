// pencil-stub-repl.mjs — synthesized stand-in for `pencil interactive`
// (@pencil.dev/cli 0.2.9) used by pencil-adapter-stub-repl.test.ts. It
// replays no captured transcript: every response is built here from the
// documented REPL contract (prompt "pencil > ", `tool({ json })` lines).
//
// Side channels, because the adapter hands the child a scrubbed environment:
//   <out>.log    every command line received, plus one ARGS line per start
//   <out>.pid    the child's pid (the test kills it to simulate a crash)
//   <out>.flags  JSON read before each command: { loadEmpty: boolean }
//
// The signature whitelist below is the second of three copies of the 0.2.9
// surface (module table, this stub, the live --help). It exits 64 on an
// unknown tool key, so a regression to `batch_design({ operations })` fails the
// round trip instead of being silently accepted the way the real engine did.
// It reads stdin to EOF-or-exit (a stub that stops draining makes pipefail
// suites flake on EPIPE).

import { createInterface } from "node:readline";
import { appendFileSync, existsSync, readFileSync, writeFileSync } from "node:fs";

const argv = process.argv.slice(2);
if (argv[0] !== "interactive") {
  process.stderr.write("stub: expected 'interactive'\n");
  process.exit(2);
}
const flag = (names) => {
  const i = argv.findIndex((a) => names.includes(a));
  return i === -1 ? null : argv[i + 1] ?? null;
};
const outFile = flag(["--out", "-o"]);
const inFile = flag(["--in", "-i"]);
if (!outFile) {
  process.stderr.write("stub: --out is required in headless mode\n");
  process.exit(2);
}

const SURFACE = {
  batch_design: ["input"],
  batch_get: ["includePathGeometry", "nodeIds", "parentId", "patterns", "readDepth", "resolveInstances", "resolveVariables", "searchDepth"],
  export_html: ["format", "includeHtmlScaffold", "includeLayerIds", "includeLayerNames", "nodeIds", "outputPath"],
  export_nodes: ["format", "nodeIds", "outputDir", "quality", "scale"],
  get_editor_state: ["include_schema"],
  get_guidelines: ["category", "name", "params"],
  get_screenshot: ["nodeId"],
  get_variables: [],
  snapshot_layout: ["maxDepth", "parentId", "problemsOnly"],
};

const log = (line) => appendFileSync(`${outFile}.log`, line + "\n");
const flags = () => {
  try {
    return JSON.parse(readFileSync(`${outFile}.flags`, "utf8"));
  } catch {
    return {};
  }
};

log(`ARGS ${argv.join(" ")}`);
writeFileSync(`${outFile}.pid`, String(process.pid));

let nodes = [];
if (inFile) {
  if (!existsSync(inFile)) {
    process.stderr.write(`Input file not found: ${inFile}\n`);
    process.exit(1);
  }
  if (!flags().loadEmpty) {
    try {
      const doc = JSON.parse(readFileSync(inFile, "utf8"));
      nodes = Array.isArray(doc.children) ? doc.children : [];
    } catch {
      process.stderr.write(`Input file is not a valid .pen: ${inFile}\n`);
      process.exit(1);
    }
  }
}

let counter = 0;
const PROMPT = "pencil > ";
const reply = (text) => process.stdout.write(`${text}\n${PROMPT}`);
process.stdout.write(PROMPT);

const rl = createInterface({ input: process.stdin });
rl.on("line", (line) => {
  const cmd = line.trim();
  if (cmd === "") return reply("");
  log(cmd);
  if (cmd === "exit()") process.exit(0);
  const m = /^([a-z_]+)\(([\s\S]*)\)$/.exec(cmd);
  if (!m) return reply(`Error: cannot parse '${cmd.slice(0, 80)}'`);
  const [, tool, rest] = m;

  let args = {};
  if (rest.trim() !== "") {
    try {
      args = new Function(`return (${rest})`)();
    } catch (e) {
      return reply(`Error: bad arguments: ${e.message}`);
    }
  }

  if (tool === "save") {
    writeFileSync(outFile, JSON.stringify({ version: "2.9", children: nodes }));
    return reply(`Saved to ${outFile}`);
  }
  if (!(tool in SURFACE)) return reply(`Unknown tool: ${tool}`);
  for (const k of Object.keys(args)) {
    if (!SURFACE[tool].includes(k)) {
      process.stderr.write(`stub: ${tool} got unexpected key '${k}'\n`);
      log(`REJECTED ${tool} key=${k}`);
      process.exit(64);
    }
  }

  if (tool === "batch_get") return reply(JSON.stringify({ nodes }));
  if (tool === "batch_design") {
    const input = String(args.input ?? "");
    if (input.includes("BADOP")) return reply("Error: invalid operation BADOP");
    const inserts = (input.match(/\bInsert\(|\bI\(/g) ?? []).length;
    const out = [];
    for (let i = 0; i < inserts; i++) {
      const id = `n${++counter}_${nodes.length}`;
      nodes.push({ id, type: "frame" });
      out.push(`node${i}=${id}`);
    }
    return reply(out.join("\n") || "OK");
  }
  if (tool === "get_editor_state") return reply(JSON.stringify({ topLevelNodes: nodes.length }));
  return reply("ok");
});
rl.on("close", () => process.exit(0));
