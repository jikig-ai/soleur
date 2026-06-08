import { describe, test, expect, beforeAll, afterAll } from "vitest";
import { spawnSync } from "node:child_process";
import {
  writeFileSync,
  mkdtempSync,
  chmodSync,
  cpSync,
  rmSync,
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
// for files not on main; non-empty (a blob entry) for files on main.
//
// Test isolation (#4957): the synthetic `zzz_*` fixture is staged in a
// per-process temp dir (a copy of the real migrations dir) and the SUT is
// pointed at it via RUN_MIGRATIONS_TEST_DIR — it is NEVER written into the
// real apps/web-platform/supabase/migrations/ tree. Previously the fixture
// was written into the real dir, where four sibling suites
// (dsar-worm-guc-sites, dsar-message-redact-fields-sweep, migration-rpc-grants,
// dsar-allowlist-completeness) readdirSync + readFileSync the same directory;
// when this producer's afterAll unlinkSync'd the fixture between a reader's
// readdir and its read, the reader hit ENOENT. Staging in a temp dir removes
// the shared write surface entirely. The git ls-tree gate below stays anchored
// to the canonical repo path (basename-only lookup), so a temp-dir filename
// absent from origin/main still trips the gate — exactly what these tests
// exercise.

const REPO_ROOT = resolve(__dirname, "../../../..");
const SCRIPT_PATH = resolve(__dirname, "../../scripts/run-migrations.sh");
const REAL_MIGRATIONS_DIR = resolve(__dirname, "../../supabase/migrations");

// Per-process randomized filename — survives parallel vitest workers + watch-
// mode reruns. The `zzz_` prefix sorts after every real migration so the
// glob's *.sql expansion processes it last (real migrations run first; the
// gate fires on this synthetic file at the end of the loop).
const SYNTHETIC_FILE = `zzz_unmerged_gate_${randomBytes(4).toString("hex")}.sql`;

// A known-merged migration (PR-I, on origin/main as of 2026-05-21). Used by
// the positive control test below; if PR-I is ever reverted, switch to
// `001_initial_schema.sql` (the earliest stable filename).
const KNOWN_MERGED_FILE = "053_template_authorizations.sql";

// Each runScript spawns bash + the psql stub + git + schema probes; give
// headroom over the 16s global default so a slow/contended CI runner does not
// flake. The minimal-fixture rewrite (2 git spawns vs ~130) is the real fix;
// this is belt-and-braces.
const SLOW_SUBPROCESS_TIMEOUT_MS = 45_000;

// Track every tempdir mkdtempSync allocates so afterAll can sweep them.
const stubDirs: string[] = [];

// The per-process staging dir holding a copy of the real migrations + the
// synthetic fixture. Set in beforeAll, swept in afterAll. The SUT globs this
// dir via RUN_MIGRATIONS_TEST_DIR instead of the real migrations tree.
let tempMigrationsDir = "";

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
      // Point the SUT's *.sql glob at the temp staging dir (#4957) so the
      // synthetic fixture never lands in the real migrations tree. The gate's
      // `git ls-tree origin/main -- apps/web-platform/supabase/migrations/<name>`
      // predicate stays anchored to the canonical path (basename-only), so it
      // still fires for the temp-dir-only `zzz_*` file.
      RUN_MIGRATIONS_TEST_DIR: tempMigrationsDir,
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
  // Best-effort recursive removal of the temp staging dir + psql stub dirs.
  // No file is ever written into the real migrations tree, so there is
  // nothing to unlink there. `force: true` tolerates already-removed dirs
  // (e.g., a process.on("exit") sweep after afterAll already ran).
  if (tempMigrationsDir) {
    try {
      rmSync(tempMigrationsDir, { recursive: true, force: true });
    } catch {
      /* best-effort sweep — already-removed dir is fine */
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
    // Stage a MINIMAL per-process migrations dir — one known-merged file plus
    // the synthetic unmerged fixture — instead of copying the whole real tree.
    // The dir is never the real tree (mkdtemp under os.tmpdir(); #4957
    // isolation preserved), so sibling suites that readdir the real dir are
    // unaffected.
    //
    // Why minimal, not a full copy (#4906): the SUT loops over every *.sql in
    // the dir, spawning a `git ls-tree origin/main` subprocess PER FILE
    // (run-migrations.sh:208). A full ~130-file copy means ~130 sequential git
    // spawns per `runScript` × 3 runs, pushing each test to the 16s testTimeout
    // boundary (flaky on slower machines). It also breaks the synthetic-only
    // invariant the moment THIS branch adds its own in-PR migration (present on
    // disk, absent from origin/main): the gate `exit 1`s on the FIRST unmerged
    // file in glob order, so it would fire on the in-PR migration instead of
    // SYNTHETIC_FILE. A two-file fixture {known-merged, synthetic} reproduces
    // the gate behavior exactly (gate at :208 runs BEFORE the already-applied
    // skip at :258, so the psql stub doesn't shadow it) with ~2 git spawns per
    // run — fast and robust regardless of the working tree's unmerged set.
    tempMigrationsDir = mkdtempSync(join(tmpdir(), "run-migrations-gate-"));
    // Guard against a future refactor leaving tempMigrationsDir empty: the
    // script's `${RUN_MIGRATIONS_TEST_DIR:-<real dir>}` default would then
    // silently fall back to the REAL dir, and the gate-blocks test could pass
    // for the wrong reason (firing on a real worktree file, not the synthetic).
    expect(tempMigrationsDir).toBeTruthy();
    // KNOWN_MERGED_FILE is on origin/main, so the gate stays silent on it
    // (positive control). Copy the real file so its content is byte-faithful;
    // the psql stub means it is never actually applied.
    cpSync(
      join(REAL_MIGRATIONS_DIR, KNOWN_MERGED_FILE),
      join(tempMigrationsDir, KNOWN_MERGED_FILE),
    );
    writeFileSync(
      join(tempMigrationsDir, SYNTHETIC_FILE),
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
    // The temp staging dir holds a copy of the real (all on-origin/main)
    // migrations plus exactly one unmerged file: SYNTHETIC_FILE. So the gate
    // fires deterministically on the synthetic basename. Assert the contract
    // (`::error::` + the unmerged-on-main predicate) AND pin the synthetic
    // filename so a regression that trips the gate on a *different* file (or
    // fires it for everything) cannot pass. ::error:: lands on stdout (the
    // script uses `echo`, not `echo >&2`).
    expect(stdout).toMatch(/::error::Migration .*\.sql is NOT on origin\/main/i);
    expect(stdout).toMatch(
      new RegExp(`Migration ${SYNTHETIC_FILE} is NOT on origin/main`, "i"),
    );
    expect(stdout).toMatch(/ALLOW_UNMERGED_DEV_APPLY=1/);
    expect(stderr).toBe("");
  }, SLOW_SUBPROCESS_TIMEOUT_MS);

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
  }, SLOW_SUBPROCESS_TIMEOUT_MS);

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
  }, SLOW_SUBPROCESS_TIMEOUT_MS);
});
