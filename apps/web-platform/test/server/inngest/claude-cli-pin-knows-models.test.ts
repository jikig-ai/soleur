// #8603 — the pinned `@anthropic-ai/claude-code` CLI knows every tier model id
// (Guard 2), accepts the audit effort value (Guard 3), and still carries the
// per-model default effort we last reviewed. #8643 — BOTH pinned platform
// binaries (claude-code and claude-agent-sdk) know every current model id
// (Guard 4) and carry the reviewed default effort for each CLI-reaching tier and
// for the `fable` alias target (Guard 5).
//
// Why: an Anthropic model id missing from the pinned CLI's bundled model table
// is treated as unknown — the CLI silently halves max_tokens (64000 → 32000,
// #6934) and takes thinking/effort params from the wrong row, while tsc, the
// suite and CI all stay green. Separately, an unknown `--effort` VALUE is not
// an error: the CLI prints `Unknown --effort value '<v>' — ignoring it and
// using the default effort` on stderr and exits 0 (measured on 2.1.280), so a
// mistyped AUDIT_EFFORT would silently run the audit crons at the default.
// And a model row's `default_effort` can move under a CLI bump with no argv
// change — that is how the Opus 5 → 5.5 swap dropped audit effort to medium.
//
// On the next CLI bump / model launch:
//   1. Bump the pin in apps/web-platform/package.json, regenerate
//      package-lock.json, and edit the Dockerfile `npm install -g` line — in
//      ONE PR, before or together with any id swap (model-launch-review
//      SKILL.md step 2b; honour its release-age note).
//   2. If REVIEWED_DEFAULT_EFFORT below reds, the new bundle moved a tier's
//      default: re-decide AUDIT_EFFORT (model-tiers.ts) for the audit tier,
//      explicitly accept the execution tier's new default, then update the map
//      (ADR-053 amendment #8603).
//   3. If the positive control below fails, the CLI reworded its warning:
//      update CLI_EFFORT_FALLBACK_NEEDLE in model-tiers.ts. The substrate's
//      Sentry mirror reads the same constant, so the two cannot diverge.
//
// The boundary + harvest rules follow
// plugins/soleur/skills/model-launch-review/scripts/audit-models.sh `[2b]`,
// which stays the hand-run check of the claude-code CANDIDATE version. This
// file is now WIDER than `[2b]` against the INSTALLED pinned versions: both
// platform binaries, every AUTOFIX_PAIRS target, and the hosted SDK default.
//
// Completeness: ids are harvested from model-tiers.ts and
// leader-prompts/constants.ts. That covers the cron CLI because
// model-tiers.test.ts G1-c and G1-f forbid every other way a model id can
// reach it from server/inngest/functions/. HAIKU_MODEL only reaches HTTP
// callers today; it is checked anyway (conservative — an id the bundle does
// not know is never a safe thing to hand the CLI later). The hosted Agent SDK
// session runs the claude-agent-sdk platform binary, so Guards 4/5 read it too,
// with the SDK default model from server/agent-model-defaults.ts in the harvest
// and the RHS of AUTOFIX_PAIRS (parsed by the one shared
// plugins/soleur/test/lib/autofix-pairs.ts) in the id set.

import { spawnSync } from "node:child_process";
import {
  existsSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

import { afterAll, describe, expect, it } from "vitest";

import { AGENT_DEFAULT_MODEL } from "@/server/agent-model-defaults";
import { HAIKU_MODEL } from "@/server/inngest/leader-prompts/constants";
import {
  AUDIT_CLI_ARGS,
  AUDIT_MODEL,
  CLI_EFFORT_FALLBACK_NEEDLE,
  EXECUTION_MODEL,
} from "@/server/inngest/model-tiers";
import {
  MIN_AUTOFIX_PAIRS,
  MIN_DISTINCT_TARGETS,
  assertPairFloors,
  distinctTargets,
  parseAutofixPairs,
  type AutofixPair,
} from "../../../../../plugins/soleur/test/lib/autofix-pairs";
import { stripComments } from "../../helpers/strip-comments";
import {
  BUN_FLOOR,
  BUN_FLOOR_PACKAGES,
  assertEmbeddedBunFloor,
  bufferSource,
  compareSemver,
  fileSource,
  resolveVendoredBinary,
  scanEmbeddedBunVersions,
  scanInstalledEmbeddedBun,
  scanNeedles,
  shouldSkipRealBinaryRows,
  type ByteSource,
  type EmbeddedBunRow,
} from "../../helpers/vendored-bwrap-tail";

const APP_ROOT = join(__dirname, "../../..");
const PKG = "@anthropic-ai/claude-code";
const AUDIT_SH = join(APP_ROOT, "../../plugins/soleur/skills/model-launch-review/scripts/audit-models.sh");

// The PLATFORM binary for this host only. Never resolve through the
// @anthropic-ai scope dir: the sibling claude-agent-sdk* packages carry sonnet
// ids too, and would vouch for an id the cron CLI does not know. On musl, npm
// installs the `-musl` variant, which this path deliberately does not name.
const IS_GLIBC = Boolean(
  (process.report?.getReport() as { header?: { glibcVersionRuntime?: string } })
    ?.header?.glibcVersionRuntime,
);
const PLATFORM_PKG = `claude-code-${process.platform}-${process.arch}`;
const PLATFORM_DIR = join(APP_ROOT, "node_modules/@anthropic-ai", PLATFORM_PKG);
const BIN = join(PLATFORM_DIR, "claude");

// Fail closed in CI and on glibc linux-x64 (the production image's platform,
// where `npm ci` must install BIN). Elsewhere a missing binary skips.
const MUST_RUN =
  Boolean(process.env.CI) ||
  (process.platform === "linux" && process.arch === "x64" && IS_GLIBC);
const HAVE_BIN = existsSync(BIN);

// The per-model `default_effort` in the pinned bundle for each tier that
// reaches the cron CLI, as last reviewed (checklist step 2). The audit tier
// overrides its default with AUDIT_EFFORT; the execution tier deliberately
// runs on its default (ADR-053 amendment #8603).
const REVIEWED_DEFAULT_EFFORT: Record<string, string> = {
  [AUDIT_MODEL]: "medium",
  // Sonnet 5.5's bundled row moved the execution default high→medium at the
  // 5→5.5 swap (bundle-verified 2026-09-29, claude-code 2.1.284). Execution
  // crons deliberately ride the CLI default (ADR-053 amendment #8603) — noted
  // as drift, not pinned back.
  //
  // Re-checked 2026-10-08 against claude-code 2.1.293 (the first release whose
  // bundle knows claude-haiku-5-5): this guard passes with both rows still at
  // `medium`. Re-checked 2026-11-04 against 2.1.311 (#12026): the guard passes
  // unchanged, both rows still `medium`. The Haiku id never reaches the cron CLI,
  // so it has no row here; the id-set guard below is what covers it.
  [EXECUTION_MODEL]: "medium",
};

// Guard 5: the `fable` alias target's bundled `default_effort`, as last reviewed (ADR-083 consult, ADR-053 tiering).
// A LITERAL, never keyed at runtime from the derived AUTOFIX_PAIRS target: a derived key would carry "medium" to an
// unreviewed claude-fable-5-3. A sibling of REVIEWED_DEFAULT_EFFORT so tierRows' audit-capability logic is never fed a
// non-tier key. Its key set must EQUAL the distinct `claude-fable-` targets of AUTOFIX_PAIRS (advisorKeyProblems).
// Measured 2026-11-10: "medium" in the 2.1.321 bundle (MEASURED_FABLE_5_2_ROW below); absent from 2.1.311.
const REVIEWED_ADVISOR_EFFORT: Readonly<Record<string, string>> = { "claude-fable-5-2": "medium" };
const REVIEWED_ADVISOR_KEYS = Object.keys(REVIEWED_ADVISOR_EFFORT);
const REVIEWED_EFFORT_ALL: Readonly<Record<string, string>> = { ...REVIEWED_DEFAULT_EFFORT, ...REVIEWED_ADVISOR_EFFORT };
/** Guard 4 checked-ids floor: opus, sonnet, haiku, fable (a loop over fewer ids is a collapsed id set, not a pass). */
const MIN_CHECKED_IDS = 4;

function readPin(): string {
  const pkg = JSON.parse(readFileSync(join(APP_ROOT, "package.json"), "utf8"));
  return pkg.dependencies?.[PKG];
}

function installedVersion(): string {
  return JSON.parse(readFileSync(join(PLATFORM_DIR, "package.json"), "utf8")).version;
}

function readDockerfilePins(): string[] {
  const src = readFileSync(join(APP_ROOT, "Dockerfile"), "utf8")
    .split("\n")
    .filter((l) => !l.trimStart().startsWith("#"))
    .join("\n");
  return [...src.matchAll(/npm install -g @anthropic-ai\/claude-code@(\S+)/g)].map(
    (m) => m[1],
  );
}

// Every quoted Claude model id outside comments. A historical id quoted in a
// comment is not a required bundle id.
function rawTierLiterals(src: string): string[] {
  const ids = new Set<string>();
  for (const m of stripComments(src).matchAll(
    /["'`](claude-(?:opus|sonnet|haiku|fable)-[0-9a-z-]+)["'`]/g,
  )) {
    ids.add(m[1]);
  }
  return [...ids].sort();
}

// Every quoted Claude model id on a NON-comment line of the tier files and the
// hosted SDK default (Guard 4 authority (c)).
function harvestIds(): string[] {
  const ids = new Set<string>();
  for (const rel of [
    "server/inngest/model-tiers.ts",
    "server/inngest/leader-prompts/constants.ts",
    "server/agent-model-defaults.ts",
  ]) {
    for (const id of rawTierLiterals(readFileSync(join(APP_ROOT, rel), "utf8"))) ids.add(id);
  }
  return [...ids].sort();
}

/** Guard 4's id set: AUTOFIX_PAIRS targets ∪ the tier harvest (which carries the SDK default), sorted. */
function currentModelIds(): string[] {
  const pairs = parseAutofixPairs(readFileSync(AUDIT_SH, "utf8"));
  assertPairFloors(pairs);
  return [...new Set([...distinctTargets(pairs), ...harvestIds()])].sort();
}

function assertIdShape(id: string): void {
  if (!/^claude-[a-z0-9-]+$/.test(id)) throw new Error(`refusing unvalidated id: ${id}`);
}

// Bundle readers. One implementation over a ByteSource (bounded chunked scans, never a whole-file read or an
// unbounded regex), shared by the claude-code Guards 2/3 rows (through the file wrappers below) and Guards 4/5
// (fed `bufferSource` blobs in the synthetic rows and `fileSource` binaries in the real ones).
//
// Whole-token boundary: the right side is audit-models.sh [2b]'s ID_BOUNDARY (rejects `<id>-20260101` shadowing); the
// left side rejects an id embedded in a longer token such as the Bedrock form `us.anthropic.<id>`.
const ID_LEFT_REJECT = /[0-9A-Za-z.-]/;
const ID_RIGHT_REJECT = /[0-9A-Za-z-]/;
// Rows measured at ~1 KB (2.1.280 opus-5-5: 996 B, sonnet-5: 922 B; 2.1.321 fable-5-2: 1015 B); the 3000-byte window
// leaves ~3x headroom, and a row that outgrows it throws rather than reading as a missing default.
const ROW_WINDOW_BYTES = 3000;

type ModelRow = { defaultEffort: string | null; capabilities: string[] };

/** Every id `src` does not contain as a whole token — all of them, not just the first. One scan for every id. */
function sourceAbsentIds(src: ByteSource, ids: readonly string[]): string[] {
  ids.forEach(assertIdShape);
  if (ids.length === 0) return [];
  const hits = scanNeedles(src, Object.fromEntries(ids.map((id) => [id, Buffer.from(id, "latin1")])));
  const byteAt = (at: number): string | null => {
    if (at < 0) return null;
    const b = src.read(at, 1);
    return b.length === 0 ? null : String.fromCharCode(b[0]);
  };
  const whole = (id: string, at: number): boolean => {
    const before = byteAt(at - 1);
    const after = byteAt(at + id.length);
    return (before === null || !ID_LEFT_REJECT.test(before)) && (after === null || !ID_RIGHT_REJECT.test(after));
  };
  return ids.filter((id) => !hits[id].some((at) => whole(id, at)));
}

/**
 * The model-table row of each id: `{id:"<id>",family:…` up to the next row (or the window, cut at a newline). Its
 * `default_effort` and `capabilities`, or null when no such row exists. Throws on two rows or an over-long row.
 */
function sourceModelRows(src: ByteSource, ids: readonly string[]): Record<string, ModelRow | null> {
  ids.forEach(assertIdShape);
  const anchors = Object.fromEntries(ids.map((id) => [id, Buffer.from(`{id:"${id}",family:`, "latin1")]));
  const hits = ids.length === 0 ? {} : scanNeedles(src, anchors);
  const out: Record<string, ModelRow | null> = {};
  for (const id of ids) {
    const at = hits[id];
    if (at.length === 0) {
      out[id] = null;
      continue;
    }
    if (at.length !== 1) throw new Error(`expected exactly one model-table row for ${id}, found ${at.length}`);
    let window = src.read(at[0], anchors[id].length + ROW_WINDOW_BYTES).toString("latin1");
    const nl = window.indexOf("\n");
    if (nl !== -1) window = window.slice(0, nl);
    const end = window.indexOf('},{id:"');
    if (end === -1 && window.length >= ROW_WINDOW_BYTES + anchors[id].length) {
      throw new Error(`model-table row for ${id} is longer than the ${ROW_WINDOW_BYTES}-byte window — widen it`);
    }
    const row = end === -1 ? window : window.slice(0, end);
    const caps = row.match(/capabilities:\[([^\]]*)\]/);
    out[id] = {
      defaultEffort: row.match(/default_effort:"([a-z]+)"/)?.[1] ?? null,
      capabilities: caps ? [...caps[1].matchAll(/"([a-z_0-9]+)"/g)].map((m) => m[1]) : [],
    };
  }
  return out;
}

function withFile<T>(file: string, fn: (src: ByteSource) => T): T {
  const fs = fileSource(file); // a missing file throws: could-not-look is never "absent"
  try {
    return fn(fs.source);
  } finally {
    fs.close();
  }
}

/** Does `file` contain `id` as a whole token? */
function bundleHasId(file: string, id: string): boolean {
  return absentIds(file, [id]).length === 0;
}

/** Every id the bundle does not know — all of them, not just the first. */
function absentIds(file: string, ids: string[]): string[] {
  return withFile(file, (src) => sourceAbsentIds(src, ids));
}

/** The model-table row for `id` in `file`, or null when no such row exists. */
function modelRow(file: string, id: string): ModelRow | null {
  return withFile(file, (src) => sourceModelRows(src, [id])[id]);
}

/**
 * Read every CLI-reaching tier's row: its `default_effort`, and whether the
 * audit model's row advertises the `effort` capability (without it `--effort`
 * is accepted and does nothing). Throws when a tier has no row.
 */
function tierRows(file: string): {
  defaults: Record<string, string | null>;
  auditSupportsEffort: boolean;
} {
  const defaults: Record<string, string | null> = {};
  let auditSupportsEffort = false;
  for (const id of Object.keys(REVIEWED_DEFAULT_EFFORT)) {
    const row = modelRow(file, id);
    if (row === null) throw new Error(`no model-table row for ${id} in ${file}`);
    defaults[id] = row.defaultEffort;
    if (id === AUDIT_MODEL) auditSupportsEffort = row.capabilities.includes("effort");
  }
  return { defaults, auditSupportsEffort };
}

const scratch: string[] = [];
function tmp(prefix: string): string {
  const d = mkdtempSync(join(tmpdir(), prefix));
  scratch.push(d);
  return d;
}
afterAll(() => {
  for (const d of scratch) rmSync(d, { recursive: true, force: true });
});

function blob(content: string): string {
  const f = join(tmp("bundle-blob-"), "claude");
  writeFileSync(f, Buffer.from(content, "latin1"));
  return f;
}

/**
 * Spawn the CLI hermetically: temp HOME/CLAUDE_CONFIG_DIR (the CLI writes
 * $HOME/.claude*), cwd outside the checkout (whose .git/config holds the job
 * token), and a superset of the traffic-off env the production spawn uses.
 * stdout and stderr stay separate: the substrate's mirror listens on stderr.
 */
function runCli(binPath: string, args: string[]) {
  const home = tmp("claude-cli-home-");
  const r = spawnSync(binPath, args, {
    cwd: home,
    env: {
      PATH: "/usr/bin:/bin",
      HOME: home,
      CLAUDE_CONFIG_DIR: join(home, ".claude"),
      CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC: "1",
      DISABLE_AUTOUPDATER: "1",
      NODE_ENV: "test", // required by Next's ProcessEnv augmentation (tsc)
    },
    timeout: 20_000,
    encoding: "utf8",
  });
  // A timeout or exec failure must not read as "the warning was reworded".
  expect(
    r.error === undefined && r.signal === null,
    `claude spawn failed (error=${r.error?.message} signal=${r.signal}): ${r.stderr}`,
  ).toBe(true);
  return { status: r.status, stdout: r.stdout, stderr: r.stderr };
}

// ---------------------------------------------------------------------------------------------
// Guards 4/5 (#8643) — pure functions over (package, ByteSource) rows, so every mutation row is a standing synthetic test.

/** One platform binary under test: the package it came from, a label for messages, and its bytes. */
interface BinaryUnderTest {
  pkg: string;
  label: string;
  src: ByteSource;
}

function failureOf(fn: () => void): string {
  try {
    fn();
    return "";
  } catch (e) {
    return (e as Error).message;
  }
}

function synthSrc(text: string): ByteSource {
  return bufferSource(Buffer.from(text, "latin1"));
}

function synthBin(pkg: string, text: string): BinaryUnderTest {
  return { pkg, label: `${pkg}@synthetic`, src: synthSrc(text) };
}

/** Shared by Guards 4 and 5: every required package was examined, so a loop over zero or one binary cannot pass. */
function coverageProblems(tag: string, rows: readonly BinaryUnderTest[], required: readonly string[]): string[] {
  const examined = rows.map((r) => r.pkg);
  return required
    .filter((pkg) => !examined.includes(pkg))
    .map((pkg) => `${tag} ${pkg} was not examined (examined: [${examined.join(", ")}], want: [${required.join(", ")}])`);
}

/** Guard 4: throws unless every required binary was examined, at least `minIds` ids were checked, and each knows each id. */
function assertIdsKnown(
  rows: readonly BinaryUnderTest[],
  ids: readonly string[],
  required: readonly string[] = BUN_FLOOR_PACKAGES,
  minIds: number = MIN_CHECKED_IDS,
): void {
  const problems = coverageProblems("MODEL_ID_COVERAGE", rows, required);
  if (ids.length < minIds) problems.push(`MODEL_ID_FLOOR checked ${ids.length} ids, floor ${minIds} (the id set collapsed)`);
  for (const r of rows) {
    for (const id of sourceAbsentIds(r.src, ids)) problems.push(`MODEL_ID_ABSENT ${r.label} does not know ${id}`);
  }
  if (problems.length === 0) return;
  throw new Error(
    `${problems.join("; ")}. An id the bundled model table does not know is treated as unknown — max_tokens is silently ` +
      "halved (#6934) with tsc and CI green. Move the @anthropic-ai/claude-code and @anthropic-ai/claude-agent-sdk pins " +
      "together to a pair whose bundles carry every AUTOFIX_PAIRS target, tier id and AGENT_DEFAULT_MODEL (honour the " +
      "model-launch-review release-age note), or keep the retarget out of this PR.",
  );
}

/**
 * Guard 5: throws unless every required binary was examined and, in each, every reviewed id has exactly one model-table
 * row whose default_effort equals the reviewed value, and the audit model's row advertises the `effort` capability.
 */
function assertReviewedEfforts(
  rows: readonly BinaryUnderTest[],
  reviewed: Readonly<Record<string, string>>,
  required: readonly string[] = BUN_FLOOR_PACKAGES,
  auditModel: string = AUDIT_MODEL,
): void {
  const problems = coverageProblems("EFFORT_COVERAGE", rows, required);
  const ids = Object.keys(reviewed);
  if (ids.length === 0) problems.push("EFFORT_FLOOR no reviewed ids to check");
  for (const r of rows) {
    let found: Record<string, ModelRow | null>;
    try {
      found = sourceModelRows(r.src, ids);
    } catch (e) {
      problems.push(`EFFORT_ROW_UNREADABLE ${r.label}: ${(e as Error).message}`);
      continue;
    }
    for (const id of ids) {
      const row = found[id];
      if (row === null) {
        problems.push(`EFFORT_NO_ROW ${r.label} ${id}: no model-table row ({id:"${id}",family: anchor)`);
        continue;
      }
      if (row.defaultEffort !== reviewed[id]) {
        problems.push(`EFFORT_MOVED ${r.label} ${id} default_effort is ${JSON.stringify(row.defaultEffort)}, reviewed ${JSON.stringify(reviewed[id])}`);
      }
      if (id === auditModel && !row.capabilities.includes("effort")) {
        problems.push(`EFFORT_CAPABILITY ${r.label} ${id}: the row lacks the "effort" capability — --effort would be accepted and do nothing`);
      }
    }
  }
  if (problems.length === 0) return;
  throw new Error(
    `${problems.join("; ")}. A bundle moved (or lacks) a reviewed default effort. For a tier id re-decide AUDIT_EFFORT / ` +
      "accept the execution default and update REVIEWED_DEFAULT_EFFORT (ADR-053 amendment #8603); for the fable alias " +
      "target re-review the ADR-083 consult effort and update REVIEWED_ADVISOR_EFFORT.",
  );
}

/** "" when REVIEWED_ADVISOR_EFFORT's keys EQUAL the distinct `claude-fable-` targets of the pairs, else the problem. */
function advisorKeyProblems(pairs: readonly AutofixPair[], reviewedAdvisor: Readonly<Record<string, string>>): string {
  const fable = distinctTargets(pairs).filter((t) => t.startsWith("claude-fable-"));
  const keys = Object.keys(reviewedAdvisor).sort();
  if (fable.length > 0 && fable.join(",") === keys.join(",")) return "";
  return (
    `ADVISOR_EFFORT_KEYS AUTOFIX_PAIRS claude-fable- targets [${fable.join(", ")}] != REVIEWED_ADVISOR_EFFORT keys ` +
    `[${keys.join(", ")}] — review the new fable target's bundled default_effort and edit the literal map`
  );
}

/** Opens both installed linux-x64 binaries (BINARY_MISSING, never a skip, on linux-x64 and under CI) for one callback. */
function withInstalledBinaries(fn: (rows: BinaryUnderTest[]) => void): void {
  const opened = BUN_FLOOR_PACKAGES.map((pkg) => {
    const bin = resolveVendoredBinary(pkg, join(APP_ROOT, "node_modules"));
    return { pkg, label: `${pkg}@${bin.version}`, fs: fileSource(bin.path) };
  });
  try {
    fn(opened.map(({ pkg, label, fs }) => ({ pkg, label, src: fs.source })));
  } finally {
    for (const o of opened) o.fs.close();
  }
}

describe("pinned claude-code CLI — pin agreement + id set (every host)", () => {
  it("package.json pins an exact version and the Dockerfile agrees", () => {
    const pin = readPin();
    expect(pin, `${PKG} must be an exact semver pin in package.json`).toMatch(
      /^\d+\.\d+\.\d+$/,
    );
    const docker = readDockerfilePins();
    expect(
      docker,
      `Dockerfile \`npm install -g ${PKG}@…\` must appear exactly once (outside comments) and equal package.json (${pin}). ` +
        "Bump package.json, regenerate package-lock.json, and edit apps/web-platform/Dockerfile in one PR " +
        "(model-launch-review SKILL.md step 2b, incl. its release-age note).",
    ).toEqual([pin]);
  });

  it("harvests every tier model id (⊇ the imported constants)", () => {
    expect(harvestIds()).toEqual(
      expect.arrayContaining([AUDIT_MODEL, EXECUTION_MODEL, HAIKU_MODEL, AGENT_DEFAULT_MODEL]),
    );
  });

  it.runIf(Boolean(process.env.CI))("CI installs the platform binary the guards read", () => {
    expect(HAVE_BIN, `${BIN} is missing in CI — run: cd apps/web-platform && npm ci`).toBe(true);
  });
});

describe("bundle helpers — semantics on synthesized blobs", () => {
  it("a dated id does NOT vouch for its alias prefix", () => {
    expect(bundleHasId(blob("\0claude-opus-5-5-20260101\0"), "claude-opus-5-5")).toBe(false);
  });

  it("an id at EOF with no trailing byte is present", () => {
    expect(bundleHasId(blob("\0\0claude-opus-5-5"), "claude-opus-5-5")).toBe(true);
  });

  it("an id embedded in a longer dotted token is not present", () => {
    expect(bundleHasId(blob('"us.anthropic.claude-opus-5-5"'), "claude-opus-5-5")).toBe(false);
  });

  it("a missing file throws (could-not-look is never 'absent')", () => {
    expect(() => bundleHasId(join(tmp("bundle-blob-"), "nope"), "claude-opus-5-5")).toThrow();
  });

  it("absentIds reports every absent id, not just the first", () => {
    const f = blob("\0claude-a-1\0");
    expect(absentIds(f, ["claude-a-1", "claude-b-2", "claude-c-3"])).toEqual([
      "claude-b-2",
      "claude-c-3",
    ]);
  });

  it("modelRow reads default_effort and capabilities from its own row only", () => {
    const f = blob(
      '[{id:"claude-x-1",family:"x",provider_ids:{first_party:"claude-x-1"},capabilities:["effort","adaptive_thinking"],default_effort:"medium",image_limits:{maxWidth:1}},' +
        '{id:"claude-y-2",family:"y",capabilities:["effort"],default_effort:"high"}]',
    );
    expect(modelRow(f, "claude-x-1")).toEqual({
      defaultEffort: "medium",
      capabilities: ["effort", "adaptive_thinking"],
    });
    // A row with no default_effort must not borrow the next row's value.
    const g = blob('{id:"claude-z-3",family:"z",capabilities:[]},{id:"claude-y-2",family:"y",default_effort:"high"}');
    expect(modelRow(g, "claude-z-3")).toEqual({ defaultEffort: null, capabilities: [] });
    expect(modelRow(f, "claude-nope-9")).toBeNull();
  });

  it("tierRows flags an audit row without the effort capability", () => {
    const row = (id: string, caps: string, eff: string) =>
      `{id:"${id}",family:"f",capabilities:[${caps}],default_effort:"${eff}"}`;
    const ok = blob(
      `[${row(AUDIT_MODEL, '"effort"', "medium")},${row(EXECUTION_MODEL, '"effort"', "medium")}]`,
    );
    expect(tierRows(ok)).toEqual({ defaults: REVIEWED_DEFAULT_EFFORT, auditSupportsEffort: true });
    const noEffort = blob(
      `[${row(AUDIT_MODEL, '"adaptive_thinking"', "medium")},${row(EXECUTION_MODEL, '"effort"', "medium")}]`,
    );
    expect(tierRows(noEffort).auditSupportsEffort).toBe(false);
    expect(() => tierRows(blob(row(AUDIT_MODEL, '"effort"', "medium")))).toThrow();
  });
});

// ---------------------------------------------------------------------------
// Install-tree pin. The Dockerfile `cli-tools` stage installs this CLI globally with
// NO `--before` date: its tree is the package plus its exact-pinned platform packages and
// nothing floating, and a date would ETARGET at the current pin (a version published late on
// day D is invisible to `--before=D`). That is only true while the lock entry says so, so the
// premise is asserted here, offline, on every host. The lock is valid evidence for a global
// install because the Dockerfile pin equals the package.json pin (the first test above).
// Residual, accepted (ADR-191, 2026-10-04): the entry carries `hasInstallScript: true`; its postinstall
// places the native binary, so this install keeps lifecycle scripts (the likec4 install does not).
// ---------------------------------------------------------------------------
type LockEntry = {
  version?: string;
  dependencies?: unknown;
  peerDependencies?: unknown;
  bundleDependencies?: unknown;
  bundledDependencies?: unknown;
  optionalDependencies?: Record<string, string>;
};

// Every field through which an entry could pull in something not pinned by name in the lock.
const FLOATING_FIELDS = ["dependencies", "peerDependencies", "optionalDependencies", "bundleDependencies", "bundledDependencies"] as const;

function checkClaudeCodeLock(
  lock: { packages?: Record<string, LockEntry> },
  pin: string,
): string[] {
  const violations: string[] = [];
  const packages = lock.packages ?? {};
  const mainKey = `node_modules/${PKG}`;
  const entry = packages[mainKey];
  if (!entry) return [`lock has no ${mainKey} entry — examined 0 claude-code entries`];
  if (entry.version !== pin) {
    violations.push(`lock entry version ${entry.version} differs from the package.json pin ${pin} (stale lock after a pin bump)`);
  }
  if (entry.dependencies !== undefined) violations.push(`${mainKey} has a dependencies block (a floating tree)`);
  if (entry.peerDependencies !== undefined) violations.push(`${mainKey} has a peerDependencies block`);
  if (entry.bundleDependencies !== undefined || entry.bundledDependencies !== undefined) violations.push(`${mainKey} has a bundled dependencies block`);
  const optional = entry.optionalDependencies ?? {};
  // An entry with no platform packages at all would make every loop below vacuous.
  if (Object.keys(optional).length === 0) violations.push(`${mainKey} has no optionalDependencies — examined 0 platform packages`);
  for (const [name, range] of Object.entries(optional)) {
    if (!name.startsWith(`${PKG}-`)) violations.push(`optionalDependency ${name} is not a ${PKG}-<platform> package`);
    if (range !== entry.version) violations.push(`optionalDependency ${name} is "${range}", not exactly ${entry.version}`);
  }
  const expected = Object.keys(optional).map((n) => `node_modules/${n}`).sort();
  const actual = Object.keys(packages).filter((k) => k.startsWith(`${mainKey}-`)).sort();
  for (const k of expected.filter((k) => !actual.includes(k))) violations.push(`optionalDependency ${k} has no lock entry`);
  for (const k of actual.filter((k) => !expected.includes(k))) violations.push(`lock entry ${k} is not an optionalDependency of ${PKG}`);
  for (const k of actual) {
    // A platform package is a leaf at exactly the main version: nothing it declares can float.
    if (packages[k].version !== entry.version) violations.push(`${k} is ${packages[k].version}, not ${entry.version}`);
    for (const f of FLOATING_FIELDS) {
      if (packages[k][f] !== undefined) violations.push(`${k} has a ${f} block (a floating tree)`);
    }
  }
  return violations;
}

describe("pinned claude-code install tree — two exact-pinned packages, nothing floating (every host)", () => {
  it("the real lock entry has no floating dependencies and matches the pin", () => {
    const lock = JSON.parse(readFileSync(join(APP_ROOT, "package-lock.json"), "utf8"));
    expect(checkClaudeCodeLock(lock, readPin())).toEqual([]);
  });

  type FixtureLock = { packages: Record<string, LockEntry> };
  const lockOf = (version: string, platforms: string[]): FixtureLock => ({
    packages: {
      [`node_modules/${PKG}`]: {
        version,
        optionalDependencies: Object.fromEntries(platforms.map((p) => [`${PKG}-${p}`, version])),
      } as LockEntry,
      ...Object.fromEntries(platforms.map((p) => [`node_modules/${PKG}-${p}`, { version } as LockEntry])),
    },
  });
  const PLATS = ["linux-x64", "linux-arm64", "darwin-arm64"];
  const run = (lock: FixtureLock, pin = "2.1.284") => checkClaudeCodeLock(lock, pin).join("\n");

  it("control: a compliant fixture lock is clean", () => {
    expect(checkClaudeCodeLock(lockOf("2.1.284", PLATS), "2.1.284")).toEqual([]);
  });

  it("row 1: a dependencies block on the claude-code entry is caught", () => {
    const lock = lockOf("2.1.284", PLATS);
    lock.packages[`node_modules/${PKG}`].dependencies = { "left-pad": "^1.0.0" };
    expect(run(lock)).toMatch(/has a dependencies block/);
  });

  it("row 2: an optionalDependency that is a range rather than the exact version is caught", () => {
    const lock = lockOf("2.1.284", PLATS);
    lock.packages[`node_modules/${PKG}`].optionalDependencies![`${PKG}-linux-x64`] = "^2.1.284";
    expect(run(lock)).toMatch(/not exactly 2\.1\.284/);
  });

  it("row 3: a platform entry carrying dependencies, and one foreign to optionalDependencies, are caught", () => {
    const lock = lockOf("2.1.284", PLATS);
    lock.packages[`node_modules/${PKG}-linux-arm64`].dependencies = { x: "1" };
    expect(run(lock)).toMatch(/node_modules\/@anthropic-ai\/claude-code-linux-arm64 has a dependencies block/);
    const foreign = lockOf("2.1.284", PLATS);
    foreign.packages[`node_modules/${PKG}-win32-x64`] = { version: "2.1.284" };
    expect(run(foreign)).toMatch(/win32-x64 is not an optionalDependency/);
  });

  it("row 3b: every other field a platform entry could float through, a skewed platform version, and bundled deps are caught", () => {
    for (const f of ["peerDependencies", "optionalDependencies", "bundleDependencies", "bundledDependencies"] as const) {
      const lock = lockOf("2.1.284", PLATS);
      (lock.packages[`node_modules/${PKG}-linux-x64`] as Record<string, unknown>)[f] = f.startsWith("bundle") ? ["x"] : { x: "^1" };
      expect(run(lock), f).toMatch(new RegExp(`claude-code-linux-x64 has a ${f} block`));
    }
    const skew = lockOf("2.1.284", PLATS);
    skew.packages[`node_modules/${PKG}-linux-x64`].version = "2.1.283";
    expect(run(skew)).toMatch(/claude-code-linux-x64 is 2\.1\.283, not 2\.1\.284/);
    // Both spellings npm accepts, each on the MAIN entry, each with its own verdict line.
    for (const f of ["bundleDependencies", "bundledDependencies"] as const) {
      const bundled = lockOf("2.1.284", PLATS);
      bundled.packages[`node_modules/${PKG}`][f] = ["x"];
      expect(run(bundled), f).toMatch(/has a bundled dependencies block/);
    }
    const peer = lockOf("2.1.284", PLATS);
    peer.packages[`node_modules/${PKG}`].peerDependencies = { x: "^1" };
    expect(run(peer)).toMatch(/has a peerDependencies block/);
    const foreignName = lockOf("2.1.284", PLATS);
    foreignName.packages[`node_modules/${PKG}`].optionalDependencies!["left-pad"] = "2.1.284";
    expect(run(foreignName)).toMatch(/optionalDependency left-pad is not a @anthropic-ai\/claude-code-<platform> package/);
  });

  it("row 3c: an entry with no platform packages is not a clean tree, it is an unexamined one", () => {
    expect(run(lockOf("2.1.284", []))).toMatch(/examined 0 platform packages/);
  });

  it("row 4: a lock with no claude-code entry fails instead of passing vacuously", () => {
    expect(run({ packages: {} })).toMatch(/examined 0 claude-code entries/);
  });

  it("row 5: a stale lock (version differs from the pin) and a missing platform entry are caught", () => {
    expect(run(lockOf("2.1.283", PLATS))).toMatch(/differs from the package\.json pin 2\.1\.284/);
    const lock = lockOf("2.1.284", PLATS);
    delete lock.packages[`node_modules/${PKG}-darwin-arm64`];
    expect(run(lock)).toMatch(/claude-code-darwin-arm64 has no lock entry/);
  });

  it("must-PASS: a ninth compliant platform package, and a lock plus pin both moved to another version, are clean", () => {
    expect(checkClaudeCodeLock(lockOf("2.1.284", [...PLATS, "freebsd-x64"]), "2.1.284")).toEqual([]);
    expect(checkClaudeCodeLock(lockOf("2.1.290", PLATS), "2.1.290")).toEqual([]);
  });
});

if (!HAVE_BIN && !MUST_RUN) {
  process.stderr.write(
    `[skip] ${BIN} not installed on ${process.platform}-${process.arch}; ` +
      "the pinned-bundle checks run in CI and on glibc linux-x64.\n",
  );
}

describe.skipIf(!HAVE_BIN && !MUST_RUN)(
  "pinned claude-code CLI bundle — Guards 2/3 (#8603)",
  () => {
    it("the platform binary is installed", () => {
      expect(
        HAVE_BIN,
        `${BIN} is missing on ${process.platform}-${process.arch} — run: cd apps/web-platform && npm ci`,
      ).toBe(true);
    });

    it(
      "is the pinned build and accepts AUDIT_EFFORT without falling back",
      () => {
        const pin = readPin();
        // One spawn with the exact tuple the audit crons pass. `--version`
        // exits before any model lookup, so this checks the effort VALUE
        // against the CLI's accepted levels; the model id is checked below.
        const probe = runCli(BIN, ["--print", ...AUDIT_CLI_ARGS, "--version"]);
        expect(probe.status).toBe(0);
        expect(
          probe.stdout.trimStart().startsWith(`${pin} `),
          `installed CLI is not the pinned ${pin} (got: ${probe.stdout.trim()}) — run: cd apps/web-platform && npm ci`,
        ).toBe(true);
        expect(
          `${probe.stdout}\n${probe.stderr}`,
          "the pinned CLI printed an effort warning for AUDIT_EFFORT — it would silently fall back to the default effort",
        ).not.toMatch(/effort/i);

        // Positive control: the same tuple with only the effort value replaced
        // must put the fallback warning on STDERR (where the substrate's
        // Sentry mirror listens). Proves the probe above can see a rejection
        // at all, and pins the shared needle (checklist step 3).
        const args = [...AUDIT_CLI_ARGS] as string[];
        const at = args.indexOf("--effort");
        expect(at, "AUDIT_CLI_ARGS carries no --effort").toBeGreaterThanOrEqual(0);
        args[at + 1] = "not-a-level";
        const control = runCli(BIN, ["--print", ...args, "--version"]);
        expect(
          control.stderr,
          `the CLI no longer prints "${CLI_EFFORT_FALLBACK_NEEDLE}" on stderr for a bad value — update CLI_EFFORT_FALLBACK_NEEDLE`,
        ).toContain(CLI_EFFORT_FALLBACK_NEEDLE);
        expect(control.stdout).not.toContain(CLI_EFFORT_FALLBACK_NEEDLE);
      },
      60_000,
    );

    it("contains every tier model id (boundary-anchored)", () => {
      const ids = harvestIds();
      const absent = absentIds(BIN, ids);
      const label = `${PKG} ${installedVersion()} (pin ${readPin()})`;
      process.stdout.write(`checked ${ids.length} ids @ ${installedVersion()}\n`);
      expect(
        absent,
        `the installed ${label} bundle does not know: ${absent.join(", ")}. ` +
          "An unknown id silently halves max_tokens (#6934) — bump the CLI pin to a version whose bundle carries them.",
      ).toEqual([]);
    }, 60_000);

    it("each CLI-reaching tier's default_effort matches the reviewed value, and the audit model supports effort", () => {
      const { defaults, auditSupportsEffort } = tierRows(BIN);
      expect(
        auditSupportsEffort,
        `${AUDIT_MODEL}'s row lacks the "effort" capability — --effort would be accepted and do nothing`,
      ).toBe(true);
      expect(
        defaults,
        "a CLI bump moved a tier's default_effort — re-decide AUDIT_EFFORT for the audit tier, " +
          "accept the execution tier's new default, then update REVIEWED_DEFAULT_EFFORT (checklist step 2)",
      ).toEqual(REVIEWED_DEFAULT_EFFORT);
    }, 60_000);

    it("real-bundle negative control: a made-up id is absent", () => {
      expect(bundleHasId(BIN, "claude-zz-not-a-model-0")).toBe(false);
    }, 60_000);
  },
);

// ---------------------------------------------------------------------------------------------
// Guard 1 (#12026, CVE-2026-111497): the Bun runtime EMBEDDED in each installed `claude` binary is at least 1.4.4.
//
// Everything above proves the PACKAGE version, and a package version says nothing about the runtime inside the binary: the
// claude-code 2.1.293 / agent-sdk 0.3.284 binaries embed Bun 1.4.3, whose Brotli decoder is the CVE. The Dockerfile's
// global install tree is not reached here (its pin is asserted equal to package.json above and the shipped copy is read from
// the released image after merge). The same pin equality stands in for `bin/claude.exe` (a postinstall copy of the exact-pinned platform
// package this reads) and for the arm64 / musl variants, which are not shipped to the server (a deliberate scope limit, #12073 review); this reads the `npm ci` tree both runtime paths use. The floor is a constant in
// test/helpers/vendored-bwrap-tail.ts, so one diff could lower it and move the pins together: it proves consistency with the stated floor, not integrity
// of the floor, and the sdk-bump attestation plus this header are what a reviewer sees in that diff.
//
// The issue's own probe, `strings <bin> | grep -m1 '^Bun v'`, can NEVER report a version: its first hit is the bare string-pool
// fragment `Bun v` in both measured pairs (2.1.293 and 2.1.311). Only a `Bun v<x.y.z> (` banner counts here.

describe("embedded Bun floor — synthetic mutation rows (#12026 Guard 1)", () => {
  const banner = (v: string, tail = "(Linux x64)") => `Bun v${v} ${tail}`;
  const rowOf = (pkg: string, text: string): EmbeddedBunRow => ({
    pkg,
    label: `${pkg}@synthetic`,
    versions: scanEmbeddedBunVersions(bufferSource(Buffer.from(text, "latin1"))),
  });
  const ok = (pkg: string) => rowOf(pkg, `xx ${banner("1.4.4")} \0 yy ${banner("1.4.4", "(0ae49f8b6)")}`);

  it("the floor is 1.4.4 and both packages are required", () => {
    expect([...BUN_FLOOR]).toEqual([1, 4, 4]);
    expect([...BUN_FLOOR_PACKAGES]).toEqual(["claude-agent-sdk", "claude-code"]);
  });

  it("must-PASS control: both packages at 1.4.4, in both banner spellings", () => {
    expect(failureOf(() => assertEmbeddedBunFloor([ok("claude-agent-sdk"), ok("claude-code")]))).toBe("");
  });

  it("row 1: a binary whose only banner is Bun 1.4.3 reds BUN_BELOW_FLOOR naming the package and both versions", () => {
    const vuln = rowOf("claude-code", `xx ${banner("1.4.3")} \0 yy ${banner("1.4.3", "(eecfd55de)")}`);
    const msg = failureOf(() => assertEmbeddedBunFloor([ok("claude-agent-sdk"), vuln]));
    expect(msg).toMatch(/BUN_BELOW_FLOOR claude-code@synthetic embeds Bun 1\.4\.3/);
    expect(msg).toMatch(/1\.4\.4 floor/);
    expect(msg).not.toMatch(/claude-agent-sdk@synthetic embeds/);
  });

  it("row 2: only bare `Bun v` fragments (the issue's probe shape) reds BUN_VERSION_NOT_FOUND, never a pass or a skip", () => {
    const bare = rowOf("claude-code", "Bun v\0 more Bun v\0 and Bun vX Bun v 1.4.4 without the paren");
    expect(bare.versions).toEqual([]);
    const msg = failureOf(() => assertEmbeddedBunFloor([ok("claude-agent-sdk"), bare]));
    expect(msg).toMatch(/BUN_VERSION_NOT_FOUND claude-code@synthetic/);
    expect(msg).toMatch(/bare "Bun v"/);
  });

  it("row 3: a package list that resolves zero binaries, or only one of the two, reds BUN_COVERAGE (\"0 checked\" cannot pass)", () => {
    expect(failureOf(() => assertEmbeddedBunFloor([]))).toMatch(/BUN_COVERAGE claude-agent-sdk was not examined/);
    const one = failureOf(() => assertEmbeddedBunFloor([ok("claude-agent-sdk")]));
    expect(one).toMatch(/BUN_COVERAGE claude-code was not examined/);
    expect(one).not.toMatch(/BUN_COVERAGE claude-agent-sdk/);
  });

  it("row 4: a compliant first banner followed by a LOWER later one reds (minimum over all occurrences, not the first)", () => {
    const mixed = rowOf("claude-agent-sdk", `${banner("1.4.4")} \0\0 ${banner("1.4.3", "(eecfd55de)")}`);
    expect(mixed.versions).toEqual(["1.4.3", "1.4.4"]);
    expect(failureOf(() => assertEmbeddedBunFloor([mixed, ok("claude-code")]))).toMatch(/BUN_BELOW_FLOOR claude-agent-sdk@synthetic embeds Bun 1\.4\.3 \(all occurrences: 1\.4\.3, 1\.4\.4\)/);
  });

  it("row 5: one package compliant and the other swapped to a 1.4.3 buffer reds naming only the swapped one", () => {
    const msg = failureOf(() => assertEmbeddedBunFloor([ok("claude-agent-sdk"), rowOf("claude-code", banner("1.4.3"))]));
    expect(msg).toMatch(/BUN_BELOW_FLOOR claude-code@synthetic/);
    expect(msg).not.toMatch(/BUN_BELOW_FLOOR claude-agent-sdk/);
  });

  it("harness: numeric, not lexicographic, comparison — 1.4.10 and 1.5.0 pass (must-PASS non-canonical), 1.4.3 and 0.9.99 do not", () => {
    for (const v of ["1.4.10", "1.5.0", "2.0.0", "1.10.0"]) {
      expect(failureOf(() => assertEmbeddedBunFloor([rowOf("claude-agent-sdk", banner(v)), rowOf("claude-code", banner(v))])), v).toBe("");
    }
    for (const v of ["1.4.3", "0.9.99", "1.3.99"]) {
      expect(failureOf(() => assertEmbeddedBunFloor([rowOf("claude-agent-sdk", banner(v)), rowOf("claude-code", banner(v))])), v).toMatch(/BUN_BELOW_FLOOR/);
    }
    expect(compareSemver("1.4.10", "1.4.4")).toBeGreaterThan(0);
    expect(failureOf(() => compareSemver("1.4", "1.4.4"))).toMatch(/SEMVER_SHAPE/);
  });

  it("harness: a banner straddling a chunk boundary is still read once, and a pre-release suffix is not a clean version", () => {
    const text = `${"z".repeat(50)}${banner("1.4.4")}${"z".repeat(50)}`;
    const at = text.indexOf("Bun v");
    for (const chunkSize of [at + 2, at, at + 5, 7]) {
      expect(scanEmbeddedBunVersions(bufferSource(Buffer.from(text, "latin1")), { chunkSize, overlap: 64 }), `chunkSize=${chunkSize}`).toEqual(["1.4.4"]);
    }
    expect(scanEmbeddedBunVersions(bufferSource(Buffer.from("Bun v1.4.4-canary.1 (Linux x64)", "latin1")))).toEqual([]);
  });
});

describe.skipIf(shouldSkipRealBinaryRows(process.platform, process.arch, process.env.CI))(
  "embedded Bun floor — the installed claude binaries (#12026 Guard 1)",
  () => {
    it(
      "both the agent-sdk and the claude-code linux-x64 binaries embed Bun >= 1.4.4 (BINARY_MISSING, never a skip, on linux-x64 and under CI)",
      () => {
        const rows = scanInstalledEmbeddedBun(join(APP_ROOT, "node_modules"));
        // Suite-level count: resolving fewer packages cannot leave this row green.
        expect(rows.map((r) => r.pkg)).toEqual([...BUN_FLOOR_PACKAGES]);
        // The floor is also asserted here directly, independent of assertEmbeddedBunFloor below: deleting that call
        // (mutation survivor in the #12073 review) must still red a vulnerable binary.
        for (const r of rows) {
          expect(r.versions.length, `${r.label}: no embedded Bun banner read`).toBeGreaterThanOrEqual(1);
          for (const v of r.versions) {
            expect(compareSemver(v, BUN_FLOOR.join(".")), `${r.label} embeds Bun ${v}, below the floor`).toBeGreaterThanOrEqual(0);
          }
        }
        process.stdout.write(`embedded Bun: ${rows.map((r) => `${r.label}=${r.versions.join("/")}`).join(" ")}\n`);
        assertEmbeddedBunFloor(rows);
      },
      180_000,
    );
  },
);

// Every CI `oven-sh/setup-bun` step reads `.bun-version` (#12009). It is the same CVE floor for the toolchain Bun, and it was the one
// member of the set that no test bounded (review of #12073: `echo 1.4.3 > .bun-version` stayed green).
describe("CI toolchain Bun floor (#12026)", () => {
  it(".bun-version is a plain x.y.z at or above the embedded-runtime floor", () => {
    const v = readFileSync(join(APP_ROOT, "..", "..", ".bun-version"), "utf8").trim();
    expect(compareSemver(v, BUN_FLOOR.join(".")), `.bun-version ${v} is below ${BUN_FLOOR.join(".")}`).toBeGreaterThanOrEqual(0);
  });
});

// ---------------------------------------------------------------------------------------------
// Guard 4 (#8643): every CURRENT model id is known by BOTH installed platform binaries. Guard 5: both binaries' bundled
// model-table rows carry the reviewed default_effort for every CLI-reaching tier id and for the `fable` alias target.
//
// The id set is the union of three authorities, each read from its source file and never retyped: the RHS of AUTOFIX_PAIRS
// in model-launch-review's audit-models.sh (parsed by the ONE shared plugins/soleur/test/lib/autofix-pairs.ts), the tier
// harvest above (model-tiers.ts, leader-prompts/constants.ts), and server/agent-model-defaults.ts (the hosted SDK default).
// The chokepoint is the same two-package list the Bun floor uses (BUN_FLOOR_PACKAGES), read through bounded chunked scans.
// The id set comes from files a model-launch PR edits, so one diff can drop an id from AUTOFIX_PAIRS and move the pins
// together: these guards prove consistency, not that the table is right. Not reached: the musl / arm64 / darwin / win32
// variants (lock version equality only) and the Dockerfile global install (the pin agreement row above).

// The `claude-fable-5-2` model-table row as MEASURED in @anthropic-ai/claude-code-linux-x64@2.1.321 (2026-11-10, read
// statically from the npm-packed binary, never executed): 1015 bytes from its `{id:"claude-fable-5-2",family:` anchor to
// the next row. The synthetic Guard 4/5 rows are built from it so they exercise the real row's shape, not a model of it.
const MEASURED_FABLE_5_2_ROW =
  '{id:"claude-fable-5-2",family:"fable",display_name:"Fable 5.2",knowledge_cutoff:"June 2026",provider_ids:{first_party:"claude-fable-5-2",bedrock:"us.anthropic.claude-fable-5-2",vertex:"claude-fable-5-2",foundry:"claude-fable-5-2",anthropic_aws:"claude-fable-5-2",anthropic_google_cloud:"claude-fable-5-2",mantle:"anthropic.claude-fable-5-2",gateway:"claude-fable-5-2"},eager_input_streaming:{bedrock:!0,vertex:!0},vertex_region_env_var:"VERTEX_REGION_CLAUDE_FABLE_5_2",fallback_3p:"claude-fable-5-1",context:{window:1e6,native_1m:!0,supports_1m_beta:!0},max_output_tokens:{default:128000,upper:128000},pricing:"tier_8_40_cache_read_0_20",capabilities:["effort","max_effort","xhigh_effort","adaptive_thinking","rejects_disabled_thinking","mid_conv_tool_change","per_turn_effort","per_turn_timing","context_management","fast_mode","lean_prompt","refusal_fallback","org_locked_thinking","fable_5_2_prompt_bundle"],default_effort:"medium",image_limits:{maxWidth:2576,maxHeight:2576,maxImageTokens:4784},advisor_rank:10}';

describe("AUTOFIX_PAIRS shared parser — synthetic rows (Guard 4 assembly)", () => {
  const table = (...lines: string[]) =>
    ["#!/usr/bin/env bash", "set -euo pipefail", "AUTOFIX_PAIRS=(", ...lines.map((l) => `  ${l}`), ")", "", 'echo "${AUTOFIX_PAIRS[@]}"', ""].join("\n");

  it("the real table parses above both floors, and its fable targets equal REVIEWED_ADVISOR_EFFORT's keys", () => {
    const pairs = parseAutofixPairs(readFileSync(AUDIT_SH, "utf8"));
    expect(failureOf(() => assertPairFloors(pairs))).toBe("");
    expect(pairs.length).toBeGreaterThanOrEqual(MIN_AUTOFIX_PAIRS);
    expect(distinctTargets(pairs).length).toBeGreaterThanOrEqual(MIN_DISTINCT_TARGETS);
    expect(advisorKeyProblems(pairs, REVIEWED_ADVISOR_EFFORT)).toBe("");
  });

  it("must-PASS non-canonical: a commented-out pair is not counted, a live pair with an inline trailing comment is", () => {
    const pairs = parseAutofixPairs(
      table('"claude-a-1=claude-a-2"', '# "claude-b-1=claude-b-2"', '"claude-c-1=claude-c-2"   # a trailing note', "claude-d-1=claude-d-2"),
    );
    expect(pairs).toEqual([["claude-a-1", "claude-a-2"], ["claude-c-1", "claude-c-2"], ["claude-d-1", "claude-d-2"]]);
  });

  it('a trailing `# was "a=b"` comment after a live pair is NOT a pair', () => {
    expect(parseAutofixPairs(table('"claude-a-1=claude-a-2"  # was "claude-old-1=claude-old-2"'))).toEqual([["claude-a-1", "claude-a-2"]]);
  });

  it("a `)` inside a comment line does not end the block (the old non-greedy regex stopped there)", () => {
    const pairs = parseAutofixPairs(table('"claude-a-1=claude-a-2"', "# (a parenthetical note)", '"claude-c-1=claude-c-2"'));
    expect(pairs.map(([from]) => from)).toEqual(["claude-a-1", "claude-c-1"]);
  });

  it("no block, two blocks, no closing `)` line, or a malformed live token throws — never reads as zero pairs", () => {
    expect(failureOf(() => parseAutofixPairs("echo nothing here\n"))).toMatch(/AUTOFIX_PAIRS_PARSE: expected exactly one .* found 0/);
    expect(failureOf(() => parseAutofixPairs(`${table('"claude-a-1=claude-a-2"')}\n${table('"claude-b-1=claude-b-2"')}`))).toMatch(/found 2/);
    expect(failureOf(() => parseAutofixPairs('AUTOFIX_PAIRS=(\n  "claude-a-1=claude-a-2"\n  "claude-b-1=claude-b-2")\n'))).toMatch(/no closing line/);
    expect(failureOf(() => parseAutofixPairs(table('"claude-a-1"')))).toMatch(/is not from=to/);
    expect(failureOf(() => parseAutofixPairs(table('"claude-a-1=claude-a-2')))).toMatch(/unterminated quote/);
  });

  it("Guard 4 row 4: an emptied block, or every pair commented out, reds BOTH floors (and assertIdsKnown on its targets reds the id floor)", () => {
    for (const src of [table(), table('# "claude-a-1=claude-a-2"', '# "claude-b-1=claude-b-2"')]) {
      const pairs = parseAutofixPairs(src);
      expect(pairs).toEqual([]);
      const msg = failureOf(() => assertPairFloors(pairs));
      expect(msg).toMatch(/AUTOFIX_PAIRS_FLOOR 0 pairs parsed, floor 11/);
      expect(msg).toMatch(/AUTOFIX_PAIRS_TARGET_FLOOR 0 distinct claude- targets/);
      expect(failureOf(() => assertIdsKnown([synthBin("claude-agent-sdk", ""), synthBin("claude-code", "")], distinctTargets(pairs)))).toMatch(
        /MODEL_ID_FLOOR checked 0 ids/,
      );
    }
  });

  it("the distinct-target floor is separate from the pair floor: 11 pairs onto 3 targets reds only the target floor", () => {
    const pairs = Array.from({ length: 11 }, (_, i) => [`claude-old-${i}`, `claude-new-${i % 3}`] as const);
    const msg = failureOf(() => assertPairFloors(pairs));
    expect(msg).toMatch(/AUTOFIX_PAIRS_TARGET_FLOOR 3 distinct/);
    expect(msg).not.toMatch(/AUTOFIX_PAIRS_FLOOR /);
  });
});

describe("Guard 4 — current model ids known by both binaries: synthetic mutation rows", () => {
  const SYNTH_TABLE = [
    "AUTOFIX_PAIRS=(",
    '  "claude-opus-5=claude-opus-5-5"',
    '  "claude-sonnet-5=claude-sonnet-5-5"',
    '  "claude-haiku-4-5=claude-haiku-5-5"',
    '  "claude-fable-5-1=claude-fable-5-2"',
    ")",
  ].join("\n");
  const KNOWS_ALL = `\0claude-opus-5-5\0"claude-sonnet-5-5"\0claude-haiku-5-5\0[${MEASURED_FABLE_5_2_ROW}]\0`;
  const ids = (src = SYNTH_TABLE) => distinctTargets(parseAutofixPairs(src));

  it("must-PASS control: both binaries carry every target (the fable id only through the measured 2.1.321 row)", () => {
    expect(ids()).toEqual(["claude-fable-5-2", "claude-haiku-5-5", "claude-opus-5-5", "claude-sonnet-5-5"]);
    expect(failureOf(() => assertIdsKnown([synthBin("claude-agent-sdk", KNOWS_ALL), synthBin("claude-code", KNOWS_ALL)], ids()))).toBe("");
  });

  it("row 1: one pair retargeted to an id absent from the binaries reds naming BOTH packages and the id", () => {
    const retargeted = SYNTH_TABLE.replace('"claude-fable-5-1=claude-fable-5-2"', '"claude-fable-5-1=claude-fable-9-9"');
    expect(retargeted).not.toBe(SYNTH_TABLE);
    const msg = failureOf(() => assertIdsKnown([synthBin("claude-agent-sdk", KNOWS_ALL), synthBin("claude-code", KNOWS_ALL)], ids(retargeted)));
    expect(msg).toMatch(/MODEL_ID_ABSENT claude-agent-sdk@synthetic does not know claude-fable-9-9/);
    expect(msg).toMatch(/MODEL_ID_ABSENT claude-code@synthetic does not know claude-fable-9-9/);
    expect(msg).not.toMatch(/claude-opus-5-5|claude-sonnet-5-5/);
  });

  it('row 2 (dispatch, shared with Guard 5): zero binaries, or only the claude-code one, reds MODEL_ID_COVERAGE ("0 checked" cannot pass)', () => {
    const none = failureOf(() => assertIdsKnown([], ids()));
    expect(none).toMatch(/MODEL_ID_COVERAGE claude-agent-sdk was not examined/);
    expect(none).toMatch(/MODEL_ID_COVERAGE claude-code was not examined/);
    const one = failureOf(() => assertIdsKnown([synthBin("claude-code", KNOWS_ALL)], ids()));
    expect(one).toMatch(/MODEL_ID_COVERAGE claude-agent-sdk was not examined/);
    expect(one).not.toMatch(/MODEL_ID_COVERAGE claude-code/);
  });

  it("row 3: the CLI binary compliant and the SDK binary lacking claude-sonnet-5-5 reds naming ONLY claude-agent-sdk", () => {
    const sdkText = KNOWS_ALL.replace('"claude-sonnet-5-5"', '"claude-sonnet-5"');
    expect(sdkText).not.toBe(KNOWS_ALL);
    const msg = failureOf(() => assertIdsKnown([synthBin("claude-agent-sdk", sdkText), synthBin("claude-code", KNOWS_ALL)], ids()));
    expect(msg).toMatch(/MODEL_ID_ABSENT claude-agent-sdk@synthetic does not know claude-sonnet-5-5/);
    expect(msg).not.toMatch(/claude-code@synthetic/);
  });

  it("row 5: a raw model-id literal in the runner reds even beside an AGENT_DEFAULT_MODEL import; a comment mention does not", () => {
    const reverted = [
      'import { AGENT_DEFAULT_MODEL } from "./agent-model-defaults";',
      "const opts = {",
      '  model: args.model ?? "claude-sonnet-5-5",',
      "};",
    ].join("\n");
    expect(rawTierLiterals(reverted)).toEqual(["claude-sonnet-5-5"]);
    expect(rawTierLiterals('/** Defaults to "claude-sonnet-5-5". */\nconst m = args.model ?? AGENT_DEFAULT_MODEL;\n')).toEqual([]);
  });

  it("row 5 (real source): agent-runner-query-options.ts carries no raw model-id literal outside comments", () => {
    expect(rawTierLiterals(readFileSync(join(APP_ROOT, "server/agent-runner-query-options.ts"), "utf8"))).toEqual([]);
  });

  it("harness (a): an empty id list reds the checked-ids floor instead of passing over nothing", () => {
    expect(failureOf(() => assertIdsKnown([synthBin("claude-agent-sdk", KNOWS_ALL), synthBin("claude-code", KNOWS_ALL)], []))).toMatch(
      /MODEL_ID_FLOOR checked 0 ids, floor 4/,
    );
  });

  it("harness (b): a dated id does NOT vouch for its undated prefix, a dotted Bedrock form does not either, an id at EOF does", () => {
    expect(sourceAbsentIds(synthSrc("\0claude-x-1-20260101\0"), ["claude-x-1"])).toEqual(["claude-x-1"]);
    expect(sourceAbsentIds(synthSrc('"us.anthropic.claude-x-1"'), ["claude-x-1"])).toEqual(["claude-x-1"]);
    expect(sourceAbsentIds(synthSrc("\0\0claude-x-1"), ["claude-x-1"])).toEqual([]);
    expect(sourceAbsentIds(synthSrc("claude-x-1\0"), ["claude-x-1"])).toEqual([]);
  });

  it("the id union carries the AUTOFIX_PAIRS targets, the tier harvest and the SDK default", () => {
    const union = currentModelIds();
    expect(union).toEqual(expect.arrayContaining([AGENT_DEFAULT_MODEL, AUDIT_MODEL, EXECUTION_MODEL, HAIKU_MODEL, ...REVIEWED_ADVISOR_KEYS]));
    expect(union.length).toBeGreaterThanOrEqual(MIN_CHECKED_IDS);
    expect(harvestIds()).toContain(AGENT_DEFAULT_MODEL);
  });
});

describe("Guard 5 — reviewed default_effort in both binaries: synthetic mutation rows", () => {
  const NEXT_ROW = '{id:"claude-zz-next-1",family:"zz",capabilities:["effort"],default_effort:"high"}';
  const tableOf = (row: string) => `[${row},${NEXT_ROW}]`;
  const FABLE = { "claude-fable-5-2": "medium" };
  const withEffort = (v: string) => MEASURED_FABLE_5_2_ROW.replace('default_effort:"medium"', `default_effort:"${v}"`);

  it("REVIEWED_ADVISOR_EFFORT is the literal reviewed map, and the measured row reads as medium with the effort capability", () => {
    expect(REVIEWED_ADVISOR_EFFORT).toEqual({ "claude-fable-5-2": "medium" });
    expect(MEASURED_FABLE_5_2_ROW.length).toBe(1015);
    const row = sourceModelRows(synthSrc(tableOf(MEASURED_FABLE_5_2_ROW)), ["claude-fable-5-2"])["claude-fable-5-2"];
    expect(row?.defaultEffort).toBe("medium");
    expect(row?.capabilities).toContain("effort");
  });

  it("must-PASS control: both binaries carry the measured row", () => {
    const t = tableOf(MEASURED_FABLE_5_2_ROW);
    expect(failureOf(() => assertReviewedEfforts([synthBin("claude-agent-sdk", t), synthBin("claude-code", t)], FABLE))).toBe("");
  });

  it('row 1: the fable row reading default_effort:"high" reds naming the id, the package and both values', () => {
    expect(withEffort("high")).not.toBe(MEASURED_FABLE_5_2_ROW);
    const ok = tableOf(MEASURED_FABLE_5_2_ROW);
    const msg = failureOf(() => assertReviewedEfforts([synthBin("claude-agent-sdk", ok), synthBin("claude-code", tableOf(withEffort("high")))], FABLE));
    expect(msg).toMatch(/EFFORT_MOVED claude-code@synthetic claude-fable-5-2 default_effort is "high", reviewed "medium"/);
    expect(msg).not.toMatch(/claude-agent-sdk@synthetic/);
  });

  it("row 2 (dispatch): a Guard 5 loop over zero binaries, or one, reds EFFORT_COVERAGE on its own", () => {
    const none = failureOf(() => assertReviewedEfforts([], FABLE));
    expect(none).toMatch(/EFFORT_COVERAGE claude-agent-sdk was not examined/);
    expect(none).toMatch(/EFFORT_COVERAGE claude-code was not examined/);
    const one = failureOf(() => assertReviewedEfforts([synthBin("claude-code", tableOf(MEASURED_FABLE_5_2_ROW))], FABLE));
    expect(one).toMatch(/EFFORT_COVERAGE claude-agent-sdk was not examined/);
    expect(one).not.toMatch(/EFFORT_COVERAGE claude-code/);
    expect(failureOf(() => assertReviewedEfforts([synthBin("claude-agent-sdk", ""), synthBin("claude-code", "")], {}))).toMatch(/EFFORT_FLOOR/);
  });

  it('row 3: the CLI row compliant and the SDK row moved to "low" reds naming ONLY claude-agent-sdk', () => {
    const msg = failureOf(() =>
      assertReviewedEfforts([synthBin("claude-agent-sdk", tableOf(withEffort("low"))), synthBin("claude-code", tableOf(MEASURED_FABLE_5_2_ROW))], FABLE),
    );
    expect(msg).toMatch(/EFFORT_MOVED claude-agent-sdk@synthetic claude-fable-5-2 default_effort is "low", reviewed "medium"/);
    expect(msg).not.toMatch(/claude-code@synthetic/);
  });

  it('row 4: the id present elsewhere but no `{id:"…",family:` row reds "no model-table row", never a missing default', () => {
    const noRow = `[${NEXT_ROW}] fallback_3p:"claude-fable-5-2" "claude-fable-5-2"`;
    const msg = failureOf(() => assertReviewedEfforts([synthBin("claude-agent-sdk", noRow), synthBin("claude-code", noRow)], FABLE));
    expect(msg).toMatch(/EFFORT_NO_ROW claude-agent-sdk@synthetic claude-fable-5-2: no model-table row/);
    expect(msg).toMatch(/EFFORT_NO_ROW claude-code@synthetic claude-fable-5-2: no model-table row/);
    expect(msg).not.toMatch(/EFFORT_MOVED/);
  });

  it("must-PASS non-canonical: fields after `family:` reordered, with an extra capability, still read medium", () => {
    const reordered = MEASURED_FABLE_5_2_ROW.replace(',default_effort:"medium"', "").replace(
      'pricing:"tier_8_40_cache_read_0_20",capabilities:["effort",',
      'pricing:"tier_8_40_cache_read_0_20",default_effort:"medium",capabilities:["some_new_cap","effort",',
    );
    expect(reordered.indexOf("default_effort")).toBeLessThan(reordered.indexOf("capabilities"));
    const t = tableOf(reordered);
    expect(failureOf(() => assertReviewedEfforts([synthBin("claude-agent-sdk", t), synthBin("claude-code", t)], FABLE))).toBe("");
  });

  it("must-RED: `family` before `id` is not a row (modelRow anchors on `{id:\"<id>\",family:` — stated behaviour)", () => {
    const flipped = MEASURED_FABLE_5_2_ROW.replace('{id:"claude-fable-5-2",family:"fable",', '{family:"fable",id:"claude-fable-5-2",');
    expect(flipped).not.toBe(MEASURED_FABLE_5_2_ROW);
    const t = tableOf(flipped);
    expect(failureOf(() => assertReviewedEfforts([synthBin("claude-agent-sdk", t), synthBin("claude-code", t)], FABLE))).toMatch(/EFFORT_NO_ROW/);
  });

  it("the audit model's row must still advertise the effort capability", () => {
    const row = (caps: string) => `{id:"${AUDIT_MODEL}",family:"opus",capabilities:[${caps}],default_effort:"medium"}`;
    const reviewed = { [AUDIT_MODEL]: "medium" };
    const ok = tableOf(row('"effort","adaptive_thinking"'));
    expect(failureOf(() => assertReviewedEfforts([synthBin("claude-agent-sdk", ok), synthBin("claude-code", ok)], reviewed))).toBe("");
    const bad = tableOf(row('"adaptive_thinking"'));
    expect(failureOf(() => assertReviewedEfforts([synthBin("claude-agent-sdk", ok), synthBin("claude-code", bad)], reviewed))).toMatch(
      new RegExp(`EFFORT_CAPABILITY claude-code@synthetic ${AUDIT_MODEL}`),
    );
  });

  it("REVIEWED_ADVISOR_EFFORT keys must EQUAL the distinct claude-fable- targets: zero, two, or a moved target reds", () => {
    const pairs = (...to: string[]) => to.map((t, i) => [`claude-old-${i}`, t] as const);
    expect(advisorKeyProblems(pairs("claude-opus-5-5", "claude-fable-5-2"), REVIEWED_ADVISOR_EFFORT)).toBe("");
    expect(advisorKeyProblems(pairs("claude-opus-5-5"), REVIEWED_ADVISOR_EFFORT)).toMatch(/ADVISOR_EFFORT_KEYS .*\[\] /);
    expect(advisorKeyProblems(pairs("claude-fable-5-2", "claude-fable-5-3"), REVIEWED_ADVISOR_EFFORT)).toMatch(/ADVISOR_EFFORT_KEYS/);
    expect(advisorKeyProblems(pairs("claude-fable-5-3"), REVIEWED_ADVISOR_EFFORT)).toMatch(/ADVISOR_EFFORT_KEYS .*claude-fable-5-3/);
  });
});

describe.skipIf(shouldSkipRealBinaryRows(process.platform, process.arch, process.env.CI))(
  "Guards 4/5 — the installed claude-agent-sdk and claude-code linux-x64 binaries (#8643)",
  () => {
    it(
      "Guard 4: every current model id (AUTOFIX_PAIRS targets ∪ tier harvest ∪ SDK default) is known by both binaries",
      () => {
        withInstalledBinaries((rows) => {
          expect(rows.map((r) => r.pkg)).toEqual([...BUN_FLOOR_PACKAGES]);
          const ids = currentModelIds();
          expect(ids.length).toBeGreaterThanOrEqual(MIN_CHECKED_IDS);
          process.stdout.write(`Guard 4: checked ${ids.length} ids [${ids.join(", ")}] in ${rows.map((r) => r.label).join(", ")}\n`);
          assertIdsKnown(rows, ids);
        });
      },
      180_000,
    );

    it(
      "Guard 5: each CLI-reaching tier and the fable alias target carry the reviewed default_effort in both binaries",
      () => {
        withInstalledBinaries((rows) => {
          expect(rows.map((r) => r.pkg)).toEqual([...BUN_FLOOR_PACKAGES]);
          assertReviewedEfforts(rows, REVIEWED_EFFORT_ALL);
        });
      },
      180_000,
    );

    it(
      "Guard 5 harness (a): every reviewed value flipped to \"high\" reds once per (package, id) — the comparison reads the real rows",
      () => {
        withInstalledBinaries((rows) => {
          const flipped = Object.fromEntries(Object.keys(REVIEWED_EFFORT_ALL).map((id) => [id, "high"]));
          const msg = failureOf(() => assertReviewedEfforts(rows, flipped));
          for (const r of rows) {
            for (const id of Object.keys(flipped)) {
              expect(msg, `${r.label} ${id}`).toMatch(new RegExp(`EFFORT_(MOVED|NO_ROW) ${r.label.replace(/\./g, "\\.")} ${id}[ :]`));
            }
          }
        });
      },
      180_000,
    );
  },
);
