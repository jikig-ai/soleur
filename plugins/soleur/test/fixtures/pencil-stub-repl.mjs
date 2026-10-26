// pencil-stub-repl.mjs — synthesized stand-in for `pencil interactive`
// (@pencil.dev/cli 0.2.9) used by pencil-adapter-stub-repl.test.ts. It
// replays no captured transcript: every response is built here from the
// documented REPL contract (prompt "pencil > ", `tool({ json })` lines).
//
// Side channels, because the adapter hands the child a scrubbed environment:
//   <out>.log    every command line received, plus one ARGS line per start
//   <out>.pid    the child's pid (the test kills it to simulate a crash)
//   <out>.flags  JSON read at start and before each command:
//     loadEmpty      ignore the --in document (the engine's silent empty load)
//     invalidAsEmpty an unparseable --in file loads empty with an [ERROR] line
//                    (measured on 0.2.9) instead of exiting
//     exitOnStart    exit 1 before the first prompt (a failed respawn)
//     slowExitMs     take this long to exit after SIGTERM (a slow old child)
//     startDelayMs   delay the first prompt by this long (a slow new child)
//     bigBatchGet    pad batch_get() past 64 KiB (a large design)
//     junkBatchGet   batch_get() answers text that is not a node list
//     failSave       save() answers an engine error and writes nothing
//     echoKey        batch_design answers an error that echoes PENCIL_CLI_KEY
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

if (flags().exitOnStart) {
  process.stderr.write("stub: exitOnStart flag set\n");
  process.exit(1);
}
const slowExitMs = Number(flags().slowExitMs ?? 0);
if (slowExitMs > 0) {
  process.on("SIGTERM", () => setTimeout(() => process.exit(0), slowExitMs));
}

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
      if (flags().invalidAsEmpty) {
        process.stderr.write(`[ERROR] Input file is not a valid .pen: ${inFile}\n`);
      } else {
        process.stderr.write(`Input file is not a valid .pen: ${inFile}\n`);
        process.exit(1);
      }
    }
  }
}

let counter = 0;
const PROMPT = "pencil > ";
const reply = (text) => process.stdout.write(`${text}\n${PROMPT}`);
const startDelayMs = Number(flags().startDelayMs ?? 0);
if (startDelayMs > 0) setTimeout(() => process.stdout.write(PROMPT), startDelayMs);
else process.stdout.write(PROMPT);

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
    if (flags().failSave) return reply("Error: disk full");
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

  if (tool === "batch_get") {
    if (flags().junkBatchGet) return reply("this is not a node list");
    if (flags().bigBatchGet) return reply(JSON.stringify({ nodes, pad: "x".repeat(70000) }));
    return reply(JSON.stringify({ nodes }));
  }
  if (tool === "batch_design") {
    const input = String(args.input ?? "");
    if (flags().echoKey) return reply(`Error: auth failed for key ${process.env.PENCIL_CLI_KEY}`);
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
