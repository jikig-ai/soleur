// #8603 — the pinned `@anthropic-ai/claude-code` CLI knows every tier model id
// (Guard 2), accepts the audit effort value (Guard 3), and still carries the
// per-model default effort we last reviewed.
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
// The boundary + harvest regexes follow
// plugins/soleur/skills/model-launch-review/scripts/audit-models.sh `[2b]`,
// which stays the hand-run check for CANDIDATE versions. This file is its CI
// twin against the INSTALLED pinned version.
//
// Completeness: ids are harvested from model-tiers.ts and
// leader-prompts/constants.ts. That covers the cron CLI because
// model-tiers.test.ts G1-c and G1-f forbid every other way a model id can
// reach it from server/inngest/functions/. HAIKU_MODEL only reaches HTTP
// callers today; it is checked anyway (conservative — an id the bundle does
// not know is never a safe thing to hand the CLI later). The Agent SDK's own
// bundled CLI (claude-agent-sdk-*) is out of scope — tracked in #8643.

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

import { HAIKU_MODEL } from "@/server/inngest/leader-prompts/constants";
import {
  AUDIT_CLI_ARGS,
  AUDIT_MODEL,
  CLI_EFFORT_FALLBACK_NEEDLE,
  EXECUTION_MODEL,
} from "@/server/inngest/model-tiers";
import { stripComments } from "../../helpers/strip-comments";

const APP_ROOT = join(__dirname, "../../..");
const PKG = "@anthropic-ai/claude-code";

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
  process.env.GITHUB_ACTIONS === "true" ||
  (process.platform === "linux" && process.arch === "x64" && IS_GLIBC);
const HAVE_BIN = existsSync(BIN);

// The per-model `default_effort` in the pinned bundle for each tier that
// reaches the cron CLI, as last reviewed (checklist step 2). The audit tier
// overrides its default with AUDIT_EFFORT; the execution tier deliberately
// runs on its default (ADR-053 amendment #8603).
const REVIEWED_DEFAULT_EFFORT: Record<string, string> = {
  [AUDIT_MODEL]: "medium",
  [EXECUTION_MODEL]: "high",
};

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

// Every quoted Claude model id on a NON-comment line of the two tier files.
// A historical id quoted in a comment is not a required bundle id.
function harvestIds(): string[] {
  const ids = new Set<string>();
  for (const rel of [
    "server/inngest/model-tiers.ts",
    "server/inngest/leader-prompts/constants.ts",
  ]) {
    const src = stripComments(readFileSync(join(APP_ROOT, rel), "utf8"));
    for (const m of src.matchAll(
      /["'`](claude-(?:opus|sonnet|haiku|fable)-[0-9a-z-]+)["'`]/g,
    )) {
      ids.add(m[1]);
    }
  }
  return [...ids].sort();
}

function assertIdShape(id: string): void {
  if (!/^claude-[a-z0-9-]+$/.test(id)) throw new Error(`refusing unvalidated id: ${id}`);
}

/** Run grep over a (possibly binary) file. rc 0 → matches, 1 → none, else throw. */
function grepFile(args: string[], file: string): string | null {
  const r = spawnSync("grep", [...args, "--", file], {
    // NODE_ENV: Next augments ProcessEnv to require it (tsc); inert to grep.
    env: { LC_ALL: "C", PATH: "/usr/bin:/bin", NODE_ENV: "test" },
    encoding: "latin1",
    maxBuffer: 16 * 1024 * 1024,
  });
  if (r.error) throw r.error;
  if (r.status === 0) return r.stdout;
  if (r.status === 1) return null;
  throw new Error(`grep could not read ${file} (rc=${r.status}): ${r.stderr}`);
}

/**
 * Does `file` contain `id` as a whole token? Two-sided boundary: the right side
 * is audit-models.sh [2b]'s ID_BOUNDARY (rejects `<id>-20260101` shadowing);
 * the left side rejects an id embedded in a longer token such as the Bedrock
 * form `us.anthropic.<id>`. LC_ALL=C so a non-UTF-8 byte after the id cannot
 * fail the bracket class and report a present id as absent. Could-not-look
 * throws — it is never read as absent.
 */
function bundleHasId(file: string, id: string): boolean {
  assertIdShape(id);
  return grepFile(["-aqE", "-e", `(^|[^0-9A-Za-z.-])${id}([^0-9A-Za-z-]|$)`], file) !== null;
}

/** Every id the bundle does not know — all of them, not just the first. */
function absentIds(file: string, ids: string[]): string[] {
  return ids.filter((id) => !bundleHasId(file, id));
}

/**
 * The model-table row for `id`: `{id:"<id>",family:…` up to the next row. Returns
 * its `default_effort` and `capabilities`, or null when no such row exists.
 */
function modelRow(
  file: string,
  id: string,
): { defaultEffort: string | null; capabilities: string[] } | null {
  assertIdShape(id);
  const out = grepFile(["-aoE", "-e", `\\{id:"${id}",family:.{0,3000}`], file);
  if (out === null) return null;
  const windows = out.split("\n").filter(Boolean);
  if (windows.length !== 1) {
    throw new Error(`expected exactly one model-table row for ${id}, found ${windows.length}`);
  }
  const end = windows[0].indexOf('},{id:"');
  const row = end === -1 ? windows[0] : windows[0].slice(0, end);
  const caps = row.match(/capabilities:\[([^\]]*)\]/);
  return {
    defaultEffort: row.match(/default_effort:"([a-z]+)"/)?.[1] ?? null,
    capabilities: caps ? [...caps[1].matchAll(/"([a-z_0-9]+)"/g)].map((m) => m[1]) : [],
  };
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
    const ids = harvestIds();
    for (const id of ids) expect(id).toMatch(/^claude-[a-z0-9-]+$/);
    expect(ids).toEqual(
      expect.arrayContaining([AUDIT_MODEL, EXECUTION_MODEL, HAIKU_MODEL]),
    );
    for (const id of Object.keys(REVIEWED_DEFAULT_EFFORT)) expect(ids).toContain(id);
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
      `[${row(AUDIT_MODEL, '"effort"', "medium")},${row(EXECUTION_MODEL, '"effort"', "high")}]`,
    );
    expect(tierRows(ok)).toEqual({ defaults: REVIEWED_DEFAULT_EFFORT, auditSupportsEffort: true });
    const noEffort = blob(
      `[${row(AUDIT_MODEL, '"adaptive_thinking"', "medium")},${row(EXECUTION_MODEL, '"effort"', "high")}]`,
    );
    expect(tierRows(noEffort).auditSupportsEffort).toBe(false);
    expect(() => tierRows(blob(row(AUDIT_MODEL, '"effort"', "medium")))).toThrow();
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
    });

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
    });

    it("real-bundle negative control: a made-up id is absent", () => {
      expect(bundleHasId(BIN, "claude-zz-not-a-model-0")).toBe(false);
    });
  },
);
