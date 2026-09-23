// #8603 — the pinned `@anthropic-ai/claude-code` CLI knows every tier model id
// (Guard 2) and accepts the audit effort value (Guard 3).
//
// Why: an Anthropic model id missing from the pinned CLI's bundled model table
// is treated as unknown — the CLI silently halves max_tokens (64000 → 32000,
// #6934) and takes thinking/effort params from the wrong row, while tsc, the
// suite and CI all stay green. Separately, an unknown `--effort` VALUE is not
// an error: the CLI prints `Unknown --effort value '<v>' — ignoring it and
// using the default effort` and exits 0 (measured on 2.1.280), so a mistyped
// AUDIT_EFFORT would silently run the audit crons at the default.
//
// On the next CLI bump / model launch:
//   1. Bump the pin in apps/web-platform/package.json, regenerate
//      package-lock.json, and edit the Dockerfile `npm install -g` line — in
//      ONE PR, before or together with any id swap (model-launch-review
//      SKILL.md step 2b; honour its release-age note).
//   2. Re-read the new bundle's `default_effort` for every tier's row and
//      re-decide AUDIT_EFFORT (model-tiers.ts; ADR-053 amendment #8603).
//   3. If the positive control below fails, the CLI reworded its warning:
//      update EFFORT_WARNING to the new text. It never passes silently.
//
// The boundary + harvest regexes are ported from
// plugins/soleur/skills/model-launch-review/scripts/audit-models.sh `[2b]`,
// which stays the hand-run check for CANDIDATE versions. This file is its CI
// twin against the PINNED version.
//
// Completeness: the id set is harvested from model-tiers.ts and
// leader-prompts/constants.ts only. That is sufficient because
// model-tiers.test.ts Guard 1 walk (c) proves every cron `--model` value is a
// model-tiers.ts identifier. The Agent SDK's own bundled CLI
// (claude-agent-sdk-linux-x64) is out of scope — tracked in #8643.

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
  EXECUTION_MODEL,
} from "@/server/inngest/model-tiers";
import { stripComments } from "../../helpers/strip-comments";

const APP_ROOT = join(__dirname, "../../..");
const PKG = "@anthropic-ai/claude-code";

// The linux-x64 PLATFORM binary only. Never resolve through the @anthropic-ai
// scope dir: the sibling claude-agent-sdk* packages carry sonnet ids too, and
// would vouch for an id the cron CLI does not know.
const BIN = join(APP_ROOT, "node_modules/@anthropic-ai/claude-code-linux-x64/claude");

// The CLI's unknown-value fallback warning. The positive control asserts it is
// still the text the CLI prints, so a reword fails loudly (checklist step 3).
const EFFORT_WARNING = "Unknown --effort value";

// Fail closed in CI and on any linux-x64 host (where npm ci installs BIN).
// The CI terms only matter if a CI runner is ever not linux-x64.
const MUST_RUN =
  Boolean(process.env.CI) ||
  process.env.GITHUB_ACTIONS === "true" ||
  (process.platform === "linux" && process.arch === "x64");
const HAVE_BIN = existsSync(BIN);

function readPin(): string {
  const pkg = JSON.parse(readFileSync(join(APP_ROOT, "package.json"), "utf8"));
  return pkg.dependencies?.[PKG];
}

function readDockerfilePins(): string[] {
  const src = readFileSync(join(APP_ROOT, "Dockerfile"), "utf8");
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

/**
 * Does `file` contain `id` as a whole token? Two-sided boundary: the right side
 * is audit-models.sh [2b]'s ID_BOUNDARY (rejects `<id>-20260101` shadowing);
 * the left side rejects an id embedded in a longer token such as the Bedrock
 * form `us.anthropic.<id>`. LC_ALL=C so a non-UTF-8 byte after the id cannot
 * fail the bracket class and report a present id as absent. rc 0 = present,
 * 1 = absent, anything else = could-not-look (throws — never read as absent).
 */
function bundleHasId(file: string, id: string): boolean {
  if (!/^claude-[a-z0-9-]+$/.test(id)) throw new Error(`refusing unvalidated id: ${id}`);
  const r = spawnSync(
    "grep",
    ["-aqE", "-e", `(^|[^0-9A-Za-z.-])${id}([^0-9A-Za-z-]|$)`, "--", file],
    // NODE_ENV: Next augments ProcessEnv to require it (tsc); inert to grep.
    { env: { LC_ALL: "C", PATH: "/usr/bin:/bin", NODE_ENV: "test" } },
  );
  if (r.error) throw r.error;
  if (r.status === 0) return true;
  if (r.status === 1) return false;
  throw new Error(`grep could not read ${file} (rc=${r.status}): ${r.stderr}`);
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

/**
 * Spawn the CLI hermetically: temp HOME/CLAUDE_CONFIG_DIR (the CLI writes
 * $HOME/.claude*), cwd outside the checkout (whose .git/config holds the job
 * token), and the same traffic-off env the production spawn uses.
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
  return { status: r.status, out: `${r.stdout}\n${r.stderr}` };
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
      `Dockerfile \`npm install -g ${PKG}@…\` must appear exactly once and equal package.json (${pin}). ` +
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
  });
});

describe("bundleHasId — boundary semantics (synthesized blobs)", () => {
  it("a dated id does NOT vouch for its alias prefix", () => {
    const f = join(tmp("bundle-blob-"), "claude");
    writeFileSync(f, Buffer.from("\0claude-opus-5-5-20260101\0"));
    expect(bundleHasId(f, "claude-opus-5-5")).toBe(false);
  });

  it("an id at EOF with no trailing byte is present", () => {
    const f = join(tmp("bundle-blob-"), "claude");
    writeFileSync(f, Buffer.from("\0\0claude-opus-5-5"));
    expect(bundleHasId(f, "claude-opus-5-5")).toBe(true);
  });

  it("an id embedded in a longer dotted token is not present", () => {
    const f = join(tmp("bundle-blob-"), "claude");
    writeFileSync(f, Buffer.from('"us.anthropic.claude-opus-5-5"'));
    expect(bundleHasId(f, "claude-opus-5-5")).toBe(false);
  });

  it("a missing file throws (could-not-look is never 'absent')", () => {
    expect(() => bundleHasId(join(tmp("bundle-blob-"), "nope"), "claude-opus-5-5")).toThrow();
  });
});

if (!HAVE_BIN && !MUST_RUN) {
  process.stderr.write(
    `[skip] ${BIN} not installed on ${process.platform}-${process.arch}; ` +
      "the pinned-bundle checks run in CI and on linux-x64.\n",
  );
}

describe.skipIf(!HAVE_BIN && !MUST_RUN)(
  "pinned claude-code CLI bundle — Guards 2/3 (#8603)",
  () => {
    it("the linux-x64 binary is installed", () => {
      expect(
        HAVE_BIN,
        `${BIN} is missing — run: cd apps/web-platform && npm ci`,
      ).toBe(true);
    });

    it(
      "is the pinned build and accepts AUDIT_EFFORT without falling back",
      () => {
        const pin = readPin();
        // One spawn with the exact tuple the audit crons pass.
        const probe = runCli(BIN, ["--print", ...AUDIT_CLI_ARGS, "--version"]);
        expect(probe.status).toBe(0);
        expect(
          probe.out.trimStart().startsWith(`${pin} `),
          `installed CLI is not the pinned ${pin} (got: ${probe.out.trim()}) — run: cd apps/web-platform && npm ci`,
        ).toBe(true);
        expect(
          probe.out,
          "the pinned CLI printed an effort warning for AUDIT_EFFORT — it would silently fall back to the default effort",
        ).not.toMatch(/effort/i);

        // Positive control: the same tuple with only the effort value replaced
        // must produce the fallback warning. Proves the probe above can see a
        // rejection at all, and pins the warning text (checklist step 3).
        const args = [...AUDIT_CLI_ARGS] as string[];
        const at = args.indexOf("--effort");
        expect(at, "AUDIT_CLI_ARGS carries no --effort").toBeGreaterThanOrEqual(0);
        args[at + 1] = "not-a-level";
        const control = runCli(BIN, ["--print", ...args, "--version"]);
        expect(
          control.out,
          `the CLI no longer prints "${EFFORT_WARNING}" for a bad value — update EFFORT_WARNING`,
        ).toContain(EFFORT_WARNING);
      },
      60_000,
    );

    it("contains every tier model id (boundary-anchored)", () => {
      const pin = readPin();
      const ids = harvestIds();
      const absent = ids.filter((id) => !bundleHasId(BIN, id));
      process.stdout.write(`checked ${ids.length} ids @ ${pin}\n`);
      expect(
        absent,
        `the pinned ${PKG}@${pin} bundle does not know: ${absent.join(", ")}. ` +
          "An unknown id silently halves max_tokens (#6934) — bump the CLI pin to a version whose bundle carries them.",
      ).toEqual([]);
    });

    it("real-bundle negative control: a made-up id is absent", () => {
      expect(bundleHasId(BIN, "claude-zz-not-a-model-0")).toBe(false);
    });
  },
);
