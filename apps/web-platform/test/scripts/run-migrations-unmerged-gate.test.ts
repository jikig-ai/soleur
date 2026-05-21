import { describe, test, expect, beforeAll, afterAll } from "vitest";
import { spawnSync } from "node:child_process";
import { writeFileSync, unlinkSync, mkdtempSync, chmodSync } from "node:fs";
import { resolve, join } from "node:path";
import { tmpdir } from "node:os";

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
// test relies on the fact that 099_test_unmerged.sql is brand-new in this
// branch and not on origin/main.

const REPO_ROOT = resolve(__dirname, "../../../..");
const SCRIPT_PATH = resolve(
  __dirname,
  "../../scripts/run-migrations.sh",
);
const SYNTHETIC_MIGRATION = resolve(
  __dirname,
  "../../supabase/migrations/099_test_unmerged.sql",
);

function makePsqlStub(): string {
  const dir = mkdtempSync(join(tmpdir(), "psql-stub-"));
  const stub = join(dir, "psql");
  // Returns "1" on any SELECT count(*) (so already_applied check skips), and
  // exits 0 with empty output on any other invocation (CREATE TABLE / INSERT
  // / heredoc apply). Matches the contract the script reads via -tAq:
  // newline-stripped count integer for SELECT, empty for DDL.
  writeFileSync(
    stub,
    [
      "#!/usr/bin/env bash",
      "# psql stub for run-migrations gate tests (#4241).",
      'cmd_input="${*}"',
      "while IFS= read -r line; do",
      '  cmd_input+="\\n$line"',
      "done < <(cat 2>/dev/null || true)",
      'if echo "$cmd_input" | grep -qi "SELECT count(\\*)"; then',
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

describe("scripts/run-migrations.sh — unmerged-apply gate (#4241)", () => {
  beforeAll(() => {
    writeFileSync(
      SYNTHETIC_MIGRATION,
      "-- synthetic test migration; never on origin/main.\nSELECT 1;\n",
    );
  });

  afterAll(() => {
    try {
      unlinkSync(SYNTHETIC_MIGRATION);
    } catch {
      /* tolerate already-removed */
    }
  });

  test("ALLOW_UNMERGED_DEV_APPLY unset: gate blocks with non-zero exit + ::error::", () => {
    const { stdout, stderr, status } = runScript({
      DATABASE_URL_POOLER: "postgres://stub@localhost:5432/stub",
      ALLOW_UNMERGED_DEV_APPLY: undefined,
    });
    const combined = `${stdout}\n${stderr}`;
    expect(status).not.toBe(0);
    expect(combined).toMatch(
      /099_test_unmerged\.sql is NOT on origin\/main/i,
    );
  });

  test("ALLOW_UNMERGED_DEV_APPLY=1: gate warns and proceeds (exit 0)", () => {
    const { stdout, stderr, status } = runScript({
      DATABASE_URL_POOLER: "postgres://stub@localhost:5432/stub",
      ALLOW_UNMERGED_DEV_APPLY: "1",
    });
    const combined = `${stdout}\n${stderr}`;
    expect(status).toBe(0);
    expect(combined).toMatch(/099_test_unmerged\.sql is not on origin\/main/i);
    expect(combined).toMatch(/ALLOW_UNMERGED_DEV_APPLY=1/i);
  });
});
