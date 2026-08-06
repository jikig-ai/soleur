#!/usr/bin/env bun
// CLI wrapper for the C4 producer (#7332, plan Phase 1). Pure logic lives in
// ../lib/c4-from-components.ts; this file owns the filesystem and the likec4
// invocation, mirroring the heartbeat-live-reconcile.ts -> reconcile-live-
// heartbeats.ts split.
//
// Reads component docs, writes a distinct composing `.c4` file (never the
// canonical three — /soleur:architecture owns those and the sandbox pins
// cwd = workspacePath, so they have two writers), renders via the pinned likec4
// CLI, and prints a structured `SOLEUR_KB_SYNC_C4` marker to stdout.
//
// Exit contract:
//   0  OK        — rendered, elements > 0, relationships > 0
//   0  DEGRADED  — rendered but 0 relationships; or writes skipped because a
//                  target was hand-edited; or likec4 unreachable. NOT a failure:
//                  the docs (or the sandbox) are the defect, not the run, and a
//                  hard error here would fail a tester's whole sync over a corpus
//                  Soleur itself taught them to write.
//   1  ERROR     — likec4 reported a source fault, or produced an empty model.
//
// Observability: layer 7 (`cli-stdout-artifact`). There is no Soleur-side sink for
// this surface and there must not be one — see ADR-171 §Observability boundary.

import { spawnSync } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

import {
  LIKEC4_VERSION,
  assessRender,
  buildEdges,
  canOverwrite,
  countModelJson,
  generateC4,
  generateSpecC4,
  generateViewPage,
  generateViewsC4,
  loadComponentDir,
} from "../lib/c4-from-components";

const COMPONENTS_DIR = "knowledge-base/project/components";
const DIAGRAMS_DIR = "knowledge-base/engineering/architecture/diagrams";
const GENERATED_MODEL = "generated-components.c4";
const MODEL_JSON = "model.likec4.json";
const VIEW_PAGE = "c4-model.md";
const RENDER_TIMEOUT_MS = 120_000;

/** Collapse to one line — a marker must be greppable as a single record. */
function oneLine(s: string): string {
  return s.replace(/\s+/g, " ").trim();
}

type WriteOutcome = "written" | "skipped-hand-edited" | "unchanged";

/**
 * Read a file, or `null` when it does not exist.
 *
 * ONE syscall, deliberately — `existsSync(p) ? readFileSync(p) : null` is a
 * check-then-use race (CodeQL `js/file-system-race`, flagged high on this file).
 * That matters more here than the generic case: the caller's whole purpose is to
 * decide whether a file is hand-edited, so a stale answer between the check and
 * the read is precisely the state that would let the producer clobber an operator's
 * correction — the one outcome the guard exists to prevent.
 */
function readOrNull(path: string): string | null {
  try {
    return readFileSync(path, "utf8");
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === "ENOENT") return null;
    throw err;
  }
}

/**
 * Create a file only if it does not already exist, atomically.
 *
 * `wx` is `O_CREAT|O_EXCL`, so the existence test and the create are one
 * indivisible operation — a separate `existsSync` guard would reintroduce the
 * same race. Used for the seed artifacts (`spec.c4`, `views.c4`, the view page),
 * where the rule is strictly "never touch an existing one".
 */
function writeIfAbsent(path: string, content: string): WriteOutcome {
  try {
    writeFileSync(path, content, { flag: "wx" });
    return "written";
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === "EEXIST") return "unchanged";
    throw err;
  }
}

/**
 * Write only if the existing file carries the GENERATED header (or is absent).
 * Returns `unchanged` when the bytes already match, so an unchanged KB produces
 * no diff — the same determinism requirement kb-coverage.md carries.
 */
function guardedWrite(path: string, content: string): WriteOutcome {
  const existing = readOrNull(path);
  if (!canOverwrite(existing)) return "skipped-hand-edited";
  if (existing === content) return "unchanged";
  writeFileSync(path, content);
  return "written";
}

function countModel(jsonPath: string): { elements: number; relationships: number } {
  const json = readOrNull(jsonPath);
  return json === null ? { elements: 0, relationships: 0 } : countModelJson(json);
}

export function runProducer(root: string): { code: number; marker: string } {
  const componentsDir = join(root, COMPONENTS_DIR);
  const diagramsDir = join(root, DIAGRAMS_DIR);

  // Attempt the read and classify ENOENT, rather than probing with existsSync and
  // reading afterwards — same check-then-use class as readOrNull above. "No
  // component docs" is a degraded run, not an error: a repo that has not been
  // synced yet simply has nothing to draw.
  let docs;
  try {
    docs = loadComponentDir(componentsDir);
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code !== "ENOENT") throw err;
    return {
      code: 0,
      marker: oneLine(
        `SOLEUR_KB_SYNC_C4 status=degraded reason=no-component-docs elements=0 relationships=0 skipped=0`,
      ),
    };
  }

  const edges = buildEdges(docs);

  mkdirSync(diagramsDir, { recursive: true });

  const outcomes: Record<string, WriteOutcome> = {};
  outcomes[GENERATED_MODEL] = guardedWrite(join(diagramsDir, GENERATED_MODEL), generateC4(docs, edges));

  // spec.c4 / views.c4 / the view page are seeded ONLY when absent. A repo that
  // already ran /soleur:architecture has hand-authored ones; a second
  // `specification` block would collide, and overwriting the view set would drop
  // the operator's views. `writeIfAbsent` makes the test-and-create atomic (O_EXCL)
  // rather than an existsSync check-then-write race.
  outcomes["spec.c4"] = writeIfAbsent(join(diagramsDir, "spec.c4"), generateSpecC4());
  outcomes["views.c4"] = writeIfAbsent(join(diagramsDir, "views.c4"), generateViewsC4());
  outcomes[VIEW_PAGE] = writeIfAbsent(join(diagramsDir, VIEW_PAGE), generateViewPage());

  const skipped = Object.values(outcomes).filter((o) => o === "skipped-hand-edited").length;

  // Render with the pinned CLI. `export json` is the same subcommand
  // regenerate-c4-model.sh uses; the pin is what makes diagnostic-stream gating
  // safe (wording is version-specific).
  const jsonPath = join(diagramsDir, MODEL_JSON);
  const run = spawnSync(
    "npx",
    ["-y", `likec4@${LIKEC4_VERSION}`, "export", "json", "-o", MODEL_JSON, "."],
    { cwd: diagramsDir, encoding: "utf8", timeout: RENDER_TIMEOUT_MS },
  );

  // likec4 unavailable (no npm in the sandbox, network denied, timeout) is a
  // clean degrade, never a hard error — the .c4 sources are still committed and
  // a later run or the operator's own render can produce the JSON.
  if (run.error || run.status === null) {
    return {
      code: 0,
      marker: oneLine(
        `SOLEUR_KB_SYNC_C4 status=degraded reason=likec4-unavailable ` +
          `detail="${String(run.error?.message ?? "no exit status")}" ` +
          `elements=0 relationships=0 skipped=${skipped}`,
      ),
    };
  }

  const diagnostics = `${run.stdout ?? ""}\n${run.stderr ?? ""}`;
  const { elements, relationships } = countModel(jsonPath);
  const verdict = assessRender({ diagnostics, elementCount: elements, relationshipCount: relationships });

  return {
    code: verdict.status === "failed" ? 1 : 0,
    marker: oneLine(
      `SOLEUR_KB_SYNC_C4 status=${verdict.status} ` +
        (verdict.reason ? `reason="${verdict.reason}" ` : "") +
        `elements=${elements} relationships=${relationships} ` +
        `docs=${docs.length} skipped=${skipped}`,
    ),
  };
}

// Only auto-run as a CLI; importing for tests must not execute.
if (import.meta.main) {
  try {
    const { code, marker } = runProducer(process.argv[2] ?? process.cwd());
    console.log(marker);
    process.exit(code);
  } catch (err) {
    console.log(
      oneLine(
        `SOLEUR_KB_SYNC_ERROR producer=c4 reason=uncaught detail="${String(
          (err as Error)?.message ?? err,
        )}"`,
      ),
    );
    process.exit(1);
  }
}
