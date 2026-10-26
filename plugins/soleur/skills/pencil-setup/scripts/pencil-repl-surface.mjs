// pencil-repl-surface.mjs — the REPL contract between the adapter and
// @pencil.dev/cli 0.2.9, as pure functions (no imports) so bun tests need no
// MCP SDK. Retire with #11156 (migration to @pen.dev/cli, whose REPL has a
// different surface).
//
// Why this exists (#11143): the adapter sent `batch_design({ operations })`
// while the engine takes `{ input }`. The engine drops an unknown key and
// prints `OK`, so every design call "succeeded" and did nothing. Every REPL
// command line now flows through `formatReplCommand`, which refuses a tool or
// key that is not in this table. The table is the signature list printed by
// `pencil interactive --help` for the pinned version;
// engine-contract-probe.sh diffs the two on every pin bump.

export class ReplContractError extends Error {
  constructor(message) {
    super(message);
    this.name = "ReplContractError";
  }
}

// tool -> allowed parameter keys. `save` is the REPL's own command and takes none.
export const REPL_SURFACE = Object.freeze({
  batch_design: ["input"],
  batch_get: [
    "includePathGeometry",
    "nodeIds",
    "parentId",
    "patterns",
    "readDepth",
    "resolveInstances",
    "resolveVariables",
    "searchDepth",
  ],
  export_html: [
    "format",
    "includeHtmlScaffold",
    "includeLayerIds",
    "includeLayerNames",
    "nodeIds",
    "outputPath",
  ],
  export_nodes: ["format", "nodeIds", "outputDir", "quality", "scale"],
  get_editor_state: ["include_schema"],
  get_guidelines: ["category", "name", "params"],
  get_screenshot: ["nodeId"],
  get_variables: [],
  save: [],
  snapshot_layout: ["maxDepth", "parentId", "problemsOnly"],
});

// 0.2.9 no longer defines the short aliases Desktop-style scripts use
// (`I(...)`, `U(...)`: ReferenceError). `var`, not `const`, so a preamble that
// runs on every call can re-declare them.
export const BATCH_DESIGN_PREAMBLE =
  "var I=Insert,U=Update,C=Copy,R=Replace,M=Move,D=Delete,G=Generate;";

// JSON.stringify leaves U+2028/U+2029 literal; readline may treat them as line
// ends, which would split one command across two REPL lines.
function jsonLine(value) {
  return JSON.stringify(value)
    .replace(/\u0085/g, "\\u0085")
    .replace(/\u2028/g, "\\u2028")
    .replace(/\u2029/g, "\\u2029");
}

export function formatReplCommand(toolName, params) {
  if (!Object.hasOwn(REPL_SURFACE, toolName)) {
    throw new ReplContractError(
      `Unknown tool: ${toolName} (not in the @pencil.dev/cli 0.2.9 REPL surface)`
    );
  }
  const given = {};
  for (const [k, v] of Object.entries(params ?? {})) {
    if (v !== undefined) given[k] = v;
  }

  if (toolName === "batch_design") {
    const keys = Object.keys(given);
    // The adapter's MCP schema calls the field `operations`; the engine calls
    // it `input`. Accept only the former here so the two can never both be sent.
    for (const k of keys) {
      if (k !== "operations") {
        throw new ReplContractError(`batch_design: unexpected parameter '${k}' (only 'operations' is accepted)`);
      }
    }
    const ops = given.operations;
    if (typeof ops !== "string" || ops.trim() === "") {
      throw new ReplContractError("batch_design: 'operations' must be a non-empty string");
    }
    return `batch_design({ input: ${jsonLine(`${BATCH_DESIGN_PREAMBLE}\n${ops}`)} })`;
  }

  const allowed = REPL_SURFACE[toolName];
  for (const k of Object.keys(given)) {
    if (!allowed.includes(k)) {
      throw new ReplContractError(
        `${toolName}: unexpected parameter '${k}' (allowed: ${allowed.join(", ") || "none"})`
      );
    }
  }
  if (Object.keys(given).length === 0) return `${toolName}()`;
  return `${toolName}(${jsonLine(given)})`;
}

// Decide the `--in` argument for one spawn of `pencil interactive --out <outFile>`.
//
// `initialInFile` is the caller's explicit input (a template). The adapter
// passes it for the open_document spawn only and passes none on a respawn, so a
// respawn after a crash reloads `outFile` and a template can never overwrite
// saved edits.
// Without an explicit input, an existing non-empty `outFile` is reloaded:
// before this, `open_document({ filePath })` started an empty document at
// `--out` and the next save replaced the file with 96 bytes.
//
// `resumeInFile` is the template a previous spawn of the SAME target loaded
// from. It applies only while `outFile` holds nothing saved: a child that dies
// before the first save would otherwise respawn empty and silently drop the
// template. Saved edits in `outFile` always win over it.
//
// `probe` is `{ exists(path): boolean, size(path): number }`, injected so this
// stays pure.
export function planSpawn({ outFile, initialInFile, resumeInFile = null, probe }) {
  if (initialInFile) {
    if (!probe.exists(initialInFile)) {
      throw new Error(`Input file not found: ${initialInFile}`);
    }
    return { inFile: initialInFile };
  }
  if (probe.exists(outFile) && probe.size(outFile) > 0) {
    return { inFile: outFile };
  }
  if (resumeInFile && probe.exists(resumeInFile)) {
    return { inFile: resumeInFile };
  }
  return { inFile: null };
}
