import { describe, test, expect, beforeAll, afterAll } from "vitest";
import { spawnSync } from "node:child_process";
import {
  writeFileSync,
  unlinkSync,
  mkdtempSync,
  chmodSync,
  rmSync,
  existsSync,
} from "node:fs";
import { resolve, join } from "node:path";
import { tmpdir } from "node:os";
import { randomBytes } from "node:crypto";

// Gate behaviour for apps/web-platform/scripts/run-migrations.sh — issue
// #4241. When a migration filename is NOT on origin/main, the runner must
// exit non-zero unless ALLOW_UNMERGED_DEV_APPLY=1 is set. This prevents the
// dev-vs-main drift class that broke `Tenant integration (dev-Supabase)` on
// 2026-05-21 (team-workspace branch applied migrations 053-057 to dev with
// no merge to main; PostgREST schema cache then diverged from main's
// grant_action_class shape).
//
// The gate is git-local: `git ls-tree origin/main -- <path>` returns empty
// for files not on main; non-empty (a blob entry) for files on main. The
// test writes a synthetic file with a randomized suffix into the real
// migrations dir (the SUT's *.sql glob roots there); on-disk leak protection
// runs via afterAll + a process.on("exit") sweep + a beforeAll precondition
// that fails fast if a stale synthetic file from a prior crashed run
// already exists.

const REPO_ROOT = resolve(__dirname, "../../../..");
const SCRIPT_PATH = resolve(__dirname, "../../scripts/run-migrations.sh");
const MIGRATIONS_DIR = resolve(__dirname, "../../supabase/migrations");

// Per-process randomized filename — survives parallel vitest workers + watch-
// mode reruns. The `zzz_` prefix sorts after every real migration so the
// glob's *.sql expansion processes it last (real migrations run first; the
// gate fires on this synthetic file at the end of the loop).
const SYNTHETIC_FILE = `zzz_unmerged_gate_${randomBytes(4).toString("hex")}.sql`;
const SYNTHETIC_MIGRATION = join(MIGRATIONS_DIR, SYNTHETIC_FILE);

// A known-merged migration (PR-I, on origin/main as of 2026-05-21). Used by
// the positive control test below; if PR-I is ever reverted, switch to
// `001_initial_schema.sql` (the earliest stable filename).
const KNOWN_MERGED_FILE = "053_template_authorizations.sql";

// Track every tempdir mkdtempSync allocates so afterAll can sweep them.
const stubDirs: string[] = [];

function makePsqlStub(): string {
  const dir = mkdtempSync(join(tmpdir(), "psql-stub-"));
  stubDirs.push(dir);
  const stub = join(dir, "psql");
  // Returns "1" on any SELECT count(*) so the script's bootstrap (line ~97)
  // and per-file already_applied (line ~178) checks both route into the
  // "skip" branch — the gate test exercises ONLY the gate, not the apply
  // path. Other invocations (CREATE TABLE / INSERT / heredoc apply) exit 0
  // with empty output. -tAq's contract: newline-stripped count integer for
  // SELECT, empty for DDL.
  writeFileSync(
    stub,
    [
      "#!/usr/bin/env bash",
      "# psql stub for run-migrations gate tests (#4241).",
      'if echo "${*}" | grep -qi "SELECT count(\\*)"; then',
      '  echo "1"',
      "fi",
      "exit 0",
      "",
    ].join("\n"),
  );
  chmodSync(stub, 0o755);
  return dir;
}

function runScript(env: Record<string, string | undefined>): {
  stdout: string;
  stderr: string;
  status: number;
} {
  const stubDir = makePsqlStub();
  const result = spawnSync("bash", [SCRIPT_PATH, "--bootstrap=skip"], {
    cwd: REPO_ROOT,
    env: {
      ...process.env,
      ...env,
      PATH: `${stubDir}:${process.env.PATH ?? ""}`,
    },
    encoding: "utf8",
    timeout: 30_000,
  });
  return {
    stdout: result.stdout?.toString() ?? "",
    stderr: result.stderr?.toString() ?? "",
    status: result.status ?? -1,
  };
}

function sweep(): void {
  if (existsSync(SYNTHETIC_MIGRATION)) {
    try {
      unlinkSync(SYNTHETIC_MIGRATION);
    } catch (err) {
      if ((err as NodeJS.ErrnoException).code !== "ENOENT") throw err;
    }
  }
  for (const dir of stubDirs) {
    try {
      rmSync(dir, { recursive: true, force: true });
    } catch {
      /* best-effort sweep — already-removed dirs are fine */
    }
  }
}

describe("scripts/run-migrations.sh — unmerged-apply gate (#4241)", () => {
  beforeAll(() => {
    if (existsSync(SYNTHETIC_MIGRATION)) {
      throw new Error(
        `precondition: ${SYNTHETIC_MIGRATION} already exists. ` +
          `Likely orphaned from a prior crashed run — delete manually before re-running.`,
      );
    }
    writeFileSync(
      SYNTHETIC_MIGRATION,
      "-- synthetic test migration; never on origin/main.\nSELECT 1;\n",
    );
    // Belt-and-braces: process.on("exit") fires even on uncaught throws /
    // explicit process.exit() that vitest's afterAll cannot intercept.
    process.on("exit", sweep);
  });

  afterAll(() => {
    sweep();
  });

  test("ALLOW_UNMERGED_DEV_APPLY unset: gate blocks with exit 1 + ::error::", () => {
    const { stdout, stderr, status } = runScript({
      DATABASE_URL_POOLER: "postgres://stub@localhost:5432/stub",
      ALLOW_UNMERGED_DEV_APPLY: undefined,
    });
    expect(status).toBe(1);
    // The gate fires on the FIRST unmerged file the *.sql glob hits (this is
    // the synthetic `zzz_*` if no other unmerged migration exists locally, or
    // a lower-prefix unmerged migration introduced by this same PR if one
    // sorts first). Assert the contract — the script exits with `::error::`
    // referencing the unmerged-on-main predicate — not the specific filename.
    // ::error:: lands on stdout (the script uses `echo`, not `echo >&2`).
    expect(stdout).toMatch(/::error::Migration .*\.sql is NOT on origin\/main/i);
    expect(stdout).toMatch(/ALLOW_UNMERGED_DEV_APPLY=1/);
    expect(stderr).toBe("");
  });

  test("ALLOW_UNMERGED_DEV_APPLY=1: gate warns and proceeds (exit 0)", () => {
    const { stdout, status } = runScript({
      DATABASE_URL_POOLER: "postgres://stub@localhost:5432/stub",
      ALLOW_UNMERGED_DEV_APPLY: "1",
    });
    expect(status).toBe(0);
    // With the ack set, the gate downgrades to ::warning:: for every unmerged
    // file — the synthetic one MUST appear (it is brand-new in this branch),
    // and so MAY any other in-PR migrations. Assert the synthetic file gets
    // its warning, plus the ack name surfaces in stdout for operator clarity.
    expect(stdout).toMatch(
      new RegExp(`${SYNTHETIC_FILE} is not on origin/main`, "i"),
    );
    expect(stdout).toMatch(/ALLOW_UNMERGED_DEV_APPLY=1/);
  });

  test("positive control: known-merged filename does NOT trigger the gate", () => {
    // Without this test, a regression that fires the gate for every file
    // would still let the two cases above pass — both test SYNTHETIC_FILE
    // exclusively, and both treat the gate firing as the expected outcome.
    // This case asserts the gate stays silent for a filename present on
    // origin/main: the only "Migration X is NOT on origin/main" line we
    // expect is the SYNTHETIC_FILE one, never KNOWN_MERGED_FILE.
    const { stdout, status } = runScript({
      DATABASE_URL_POOLER: "postgres://stub@localhost:5432/stub",
      ALLOW_UNMERGED_DEV_APPLY: "1",
    });
    expect(status).toBe(0);
    expect(stdout).not.toMatch(
      new RegExp(`${KNOWN_MERGED_FILE}.*NOT on origin/main`, "i"),
    );
    expect(stdout).not.toMatch(
      new RegExp(`${KNOWN_MERGED_FILE}.*is not on origin/main`, "i"),
    );
  });
});
