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
import { lstatSync, mkdirSync, mkdtempSync, readFileSync, renameSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
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
// A cold `npx -y likec4@…` install was MEASURED at 151s and just-under-120s on the
// same machine — i.e. the old 120s budget straddled the install it wraps, making a
// customer's FIRST sync a bandwidth coin flip. The render itself is separately slow
// on dense corpora (30 components/90 relationships = 13.9s; 35 = timeout at 120s).
// 600s covers both without hiding a genuine hang: the timeout arm is reported, not
// swallowed, and reports `render-timeout` rather than blaming the CLI.
const RENDER_TIMEOUT_MS = 600_000;

// `spawnSync`'s default maxBuffer is 1 MiB. Exceeding it sets `error` and kills the
// child, which routed a >1MiB diagnostic stream into the `likec4-unavailable` arm —
// downgrading `failed` to `degraded` (exit 0). That is a fail-open in the exact
// diagnostic gate this producer exists to provide, on the corpus most likely to be
// broken. Measured: a 3 MiB child stdout yields status:null + ENOBUFS.
const RENDER_MAX_BUFFER = 32 * 1024 * 1024;

/** Collapse to one line — a marker must be greppable as a single record. */
function oneLine(s: string): string {
  return s.replace(/\s+/g, " ").trim();
}

type WriteOutcome =
  | "written"
  | "skipped-hand-edited"
  | "skipped-exists"
  | "skipped-symlink"
  | "unchanged";

/**
 * Outcomes where the producer REFUSED to write something it otherwise would have.
 *
 * `skipped-exists` is deliberately NOT here. The seed artifacts (spec.c4, views.c4,
 * c4-model.md) exist on every run after the first, so counting that as a refusal made
 * every repeat sync report `degraded` — the steady state misreported as a problem.
 * It is still surfaced separately in the marker as `seeded=`, because "a file is
 * already there" and "I declined to touch your work" are different facts.
 */
const REFUSED_OUTCOMES: readonly WriteOutcome[] = ["skipped-hand-edited", "skipped-symlink"];

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
 * True when `path` is a symlink. Uses `lstat`, which does NOT follow the link.
 *
 * ‼️ WHY THIS EXISTS. Without it the producer performs an ARBITRARY FILE WRITE.
 * Reproduced: plant a DANGLING symlink at `generated-components.c4` pointing
 * anywhere (`../../../../.bashrc`); `readOrNull` gets ENOENT and returns null,
 * `canOverwrite(null)` returns true, and `writeFileSync`'s default `w` flag
 * (O_CREAT|O_TRUNC) FOLLOWS the link and creates the victim file with producer
 * content — which embeds an attacker-chosen line from a doc's `component:`
 * frontmatter. A directory symlink on the diagrams dir relocates all four writes.
 *
 * The check must be lstat, not "does it exist": a dangling link is exactly the
 * dangerous case and is invisible to every existence test.
 */
function isSymlink(path: string): boolean {
  try {
    return lstatSync(path).isSymbolicLink();
  } catch (err) {
    if ((err as NodeJS.ErrnoException).code === "ENOENT") return false;
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
  if (isSymlink(path)) return "skipped-symlink";
  try {
    writeFileSync(path, content, { flag: "wx" });
    return "written";
  } catch (err) {
    // EEXIST means a file is already there and we deliberately did not touch it.
    // That is NOT "unchanged" — a hand-authored views.c4 carrying the operator's
    // own view set would otherwise be indistinguishable from a no-op, and the
    // skipped count could never see it.
    if ((err as NodeJS.ErrnoException).code === "EEXIST") return "skipped-exists";
    throw err;
  }
}

/**
 * Write only if the existing file carries the GENERATED header (or is absent).
 * Returns `unchanged` when the bytes already match, so an unchanged KB produces
 * no diff — the same determinism requirement kb-coverage.md carries.
 */
function guardedWrite(path: string, content: string): WriteOutcome {
  // Refuse symlinks outright — see isSymlink. A dangling link reads as ENOENT,
  // so without this the "is it hand-edited?" question is answered about a file
  // that is not the file we are about to write.
  if (isSymlink(path)) return "skipped-symlink";
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
        `SOLEUR_KB_SYNC_C4 status=degraded reason=no-component-docs elements=0 relationships=0 skipped=0 seeded=0`,
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

  // `skipped` counts REFUSALS (we would have written, and did not). `seeded` counts
  // targets that already existed — the normal steady state, reported but not a degrade.
  const skipped = Object.values(outcomes).filter((o) => REFUSED_OUTCOMES.includes(o)).length;
  const seeded = Object.values(outcomes).filter((o) => o === "skipped-exists").length;

  // ‼️ RENDER OFF-TREE, PUBLISH ONLY AFTER THE GATE PASSES.
  //
  // The earlier form rendered IN PLACE (`-o model.likec4.json`, cwd = diagramsDir)
  // and validated the file it had already overwritten. Reproduced: a good 13,109-byte
  // model became 1,001 bytes and THEN the run reported `failed` and exited 1 — the
  // committed artifact was destroyed by the very run that declared the source broken.
  // On this repo the same path replaced a 755,747-byte artifact carrying operator-
  // positioned `manualLayouts` geometry.
  //
  // `scripts/regenerate-c4-model.sh:75-118` renders to a temp dir for exactly this
  // reason and states it: "On error we never publish, so a broken .c4 can never
  // clobber the good committed artifact." There is a post-mortem in this repo for
  // that clobber having already happened once. The previous version of this file
  // copied that script's DIAG_RE and not its publish discipline.
  //
  // `model.likec4.json` is also the one artifact with no GENERATED header (it is
  // JSON), so it can never route through guardedWrite — publishing it is gated by
  // the render verdict instead.
  const jsonPath = join(diagramsDir, MODEL_JSON);
  const stageDir = mkdtempSync(join(tmpdir(), "soleur-c4-"));
  const stagedJson = join(stageDir, MODEL_JSON);

  const run = spawnSync(
    "npx",
    // `--ignore-scripts`: the version pin is a VERSION pin, not an integrity pin.
    // `npx -y` resolves likec4's transitive dependencies by semver at run time with
    // no lockfile, so a compromised patch release of any transitive dep would run its
    // postinstall with the operator's privileges and cwd inside the customer's
    // repository. likec4 needs no install scripts to export JSON, so this costs
    // nothing and closes the largest surface the pin does not cover.
    ["-y", "--ignore-scripts", `likec4@${LIKEC4_VERSION}`, "export", "json", "-o", stagedJson, "."],
    {
      cwd: diagramsDir,
      encoding: "utf8",
      timeout: RENDER_TIMEOUT_MS,
      maxBuffer: RENDER_MAX_BUFFER,
      // SIGKILL rather than the default SIGTERM, which `npm exec` can swallow.
      //
      // KNOWN LIMITATION, stated rather than papered over: this signals the DIRECT
      // child only. `spawnSync` has no `detached` option (that is `spawn`-only), so
      // the `likec4` grandchild behind npm's shim layers can outlive the timeout —
      // measured at 405s/263s/143s past a 120s budget, each pinning a core. Raising
      // RENDER_TIMEOUT_MS above the measured cold-install worst case makes the
      // timeout arm rare rather than routine, which is mitigation, not a fix. A real
      // fix means resolving the likec4 binary and spawning it directly instead of
      // through `npm exec`; that changes how the version pin is enforced, which the
      // diagnostic gate depends on, so it is deliberately not bundled into this PR.
      killSignal: "SIGKILL",
    },
  );

  // A timeout is NOT "the CLI is unavailable". Reporting it as such sends an operator
  // hunting a network fault that does not exist — and the render genuinely does time
  // out on dense corpora (measured: 30 components/90 relationships = 13.9s, 35 =
  // timeout). Distinguish the two, and keep both a clean degrade.
  const timedOut = run.error !== undefined && (run.error as NodeJS.ErrnoException).code === "ETIMEDOUT";
  if (run.error || run.status === null) {
    rmSync(stageDir, { recursive: true, force: true });
    const reason = timedOut ? "render-timeout" : "likec4-unavailable";
    // Report the counts from the artifact ALREADY on disk rather than hardcoding 0 —
    // a stale-but-valid model is not the same as no model, and those zeros were being
    // committed into kb-coverage.md as a permanent record of a run that produced
    // nothing.
    const prior = countModel(jsonPath);
    return {
      code: 0,
      marker: oneLine(
        `SOLEUR_KB_SYNC_C4 status=degraded reason=${reason} ` +
          `detail="${String(run.error?.message ?? "no exit status")}" ` +
          `elements=${prior.elements} relationships=${prior.relationships} ` +
          `docs=${docs.length} skipped=${skipped} seeded=${seeded}`,
      ),
    };
  }

  // A non-zero exit with a clean diagnostic stream would otherwise fall through to
  // countModel and read whatever JSON is on disk — a stale good model reported as a
  // fresh success. The shell precedent checks this; the first version did not.
  if (run.status !== 0) {
    rmSync(stageDir, { recursive: true, force: true });
    const prior = countModel(jsonPath);
    return {
      code: 1,
      marker: oneLine(
        `SOLEUR_KB_SYNC_C4 status=failed reason=likec4-nonzero-exit ` +
          `detail="exit ${run.status}" ` +
          `elements=${prior.elements} relationships=${prior.relationships} ` +
          `docs=${docs.length} skipped=${skipped} seeded=${seeded}`,
      ),
    };
  }

  // Gate on the STAGED render, never on the published artifact.
  const diagnostics = `${run.stdout ?? ""}\n${run.stderr ?? ""}`;
  const staged = countModel(stagedJson);
  const verdict = assessRender({
    diagnostics,
    elementCount: staged.elements,
    relationshipCount: staged.relationships,
    // The GATE. `edges` is this producer's own contribution, computed in-process —
    // the merged render's count is dominated by any hand-authored model.c4 and
    // cannot answer "did MY corpus produce edges?".
    generatedRelationships: edges.length,
  });

  // A refusal to overwrite is a DEGRADE, not a clean run. sync.md documents
  // `status=degraded` as covering "a hand-edited file was skipped", and the first
  // version computed `skipped` and never passed it to assessRender — so declining to
  // update an operator's hand-corrected diagram reported `status=ok`, and the E2E
  // asserted only `skipped=1`, never the status, so that arm passed on `ok`.
  const effective =
    skipped > 0 && verdict.status === "ok"
      ? { status: "degraded" as const, reason: "skipped-write-target", detail: undefined }
      : verdict;

  // Publish only on a verdict that is not `failed`. A degraded render (0 relationships)
  // is still a correct model of a link-free corpus and SHOULD be published; a failed
  // one must never replace the committed artifact.
  let published = false;
  if (effective.status !== "failed" && !isSymlink(jsonPath)) {
    // Same filesystem as the destination would be ideal for a true rename; across
    // devices Node falls back to copy+unlink, which is still strictly better than
    // writing the CLI's output directly onto the live path.
    try {
      renameSync(stagedJson, jsonPath);
      published = true;
    } catch {
      writeFileSync(jsonPath, readFileSync(stagedJson));
      published = true;
    }
  }
  rmSync(stageDir, { recursive: true, force: true });

  return {
    code: effective.status === "failed" ? 1 : 0,
    marker: oneLine(
      `SOLEUR_KB_SYNC_C4 status=${effective.status} ` +
        (effective.reason ? `reason=${effective.reason} ` : "") +
        (effective.detail ? `detail="${effective.detail}" ` : "") +
        `elements=${staged.elements} relationships=${staged.relationships} ` +
        `generated_components=${docs.length} generated_relationships=${edges.length} ` +
        `skipped=${skipped} seeded=${seeded} published=${published ? 1 : 0}`,
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
