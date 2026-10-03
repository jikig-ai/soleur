import { spawnSync } from "node:child_process";
import { chmodSync, cpSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { describe, expect, it } from "vitest";

const scripts = path.resolve(__dirname, "../../scripts");

describe("migration 145 admission in the real migration runner", () => {
  function captureApply(filename: string, missingGuard = false) {
    const fixture = mkdtempSync(path.join(tmpdir(), "codex-migration-runner-"));
    try {
      for (const dir of ["scripts/sql", "supabase/migrations", "bin"]) mkdirSync(path.join(fixture, dir), { recursive: true });
      cpSync(path.join(scripts, "run-migrations.sh"), path.join(fixture, "scripts/run-migrations.sh"));
      if (!missingGuard) cpSync(path.join(scripts, "sql/codex-auth-mode-pre-migration.sql"), path.join(fixture, "scripts/sql/codex-auth-mode-pre-migration.sql"));
      writeFileSync(path.join(fixture, "supabase/migrations", filename), "BEGIN;\nCREATE TABLE public.synthetic_migration_body (id integer);\nCOMMIT;\n");
      writeFileSync(path.join(fixture, "scripts/postgrest-reload-schema.sh"), "#!/usr/bin/env bash\nexit 0\n");
      writeFileSync(path.join(fixture, "bin/git"), "#!/usr/bin/env bash\ncase \"$1\" in\nfetch) exit 0 ;;\nls-tree) printf '100644 blob 1111111111111111111111111111111111111111 fixture.sql\\n' ;;\nhash-object) printf '1111111111111111111111111111111111111111\\n' ;;\n*) exit 64 ;;\nesac\n");
      writeFileSync(path.join(fixture, "bin/psql"), `#!/usr/bin/env bash
case "$*" in
  *" -c "*) case "$*" in *"SELECT count(*)"*) printf '0\\n' ;; esac ;;
  *"--single-transaction"*" -f -"*) cat > '${path.join(fixture, "apply.sql")}' ;;
  *) exit 64 ;;
esac
`);
      for (const file of ["bin/git", "bin/psql"]) chmodSync(path.join(fixture, file), 0o755);
      const result = spawnSync("bash", [path.join(fixture, "scripts/run-migrations.sh"), "--bootstrap=skip"], {
        cwd: fixture,
        // An allowlisted environment keeps operator credentials out of the fixture.
        env: { PATH: `${path.join(fixture, "bin")}:${process.env.PATH}`, DATABASE_URL: "postgres://synthetic.invalid/test", MIGRATION_SCHEMA_PRECONDITION_PROBE: "0" },
        encoding: "utf8", timeout: 15_000,
      });
      let sql = "";
      try { sql = readFileSync(path.join(fixture, "apply.sql"), "utf8"); } catch { /* No apply invocation on refusal. */ }
      return { status: result.status, output: result.stdout + result.stderr, sql };
    } finally { rmSync(fixture, { recursive: true, force: true }); }
  }

  it("places the bounded lock and rejection before the unchanged migration and its ledger write in one transaction", () => {
    const result = captureApply("145_codex_auth_mode_rebind.sql");
    expect(result.status, result.output).toBe(0);
    const lock = result.sql.search(/^LOCK TABLE public\.workspace_engine_settings IN ACCESS EXCLUSIVE MODE;/m);
    const rejection = result.sql.search(/^\s*RAISE EXCEPTION 'Codex auth-mode migration refused:/m);
    const body = result.sql.search(/^CREATE TABLE public\.synthetic_migration_body/m);
    const ledger = result.sql.search(/^INSERT INTO public\._schema_migrations/m);
    expect(lock).toBeGreaterThan(0);
    expect(rejection).toBeGreaterThan(lock);
    expect(body).toBeGreaterThan(rejection);
    expect(ledger).toBeGreaterThan(body);
    expect(result.sql).toMatch(/^SET LOCAL lock_timeout = '30s';/m);
    expect(result.sql).toMatch(/^SET LOCAL statement_timeout = '5min';/m);
    expect(result.sql).not.toMatch(/^(?:BEGIN|COMMIT|ROLLBACK);/m);
  });

  it("fails before applying when the required guard asset is absent", () => {
    const result = captureApply("145_codex_auth_mode_rebind.sql", true);
    expect(result.status).not.toBe(0);
    expect(result.output).toContain("Codex auth-mode pre-migration guard is unavailable");
    expect(result.sql).toBe("");
  });

  it("leaves unrelated migrations independent of the Codex guard asset", () => {
    const result = captureApply("145_unrelated_synthetic.sql", true);
    expect(result.status, result.output).toBe(0);
    expect(result.sql).toMatch(/^CREATE TABLE public\.synthetic_migration_body/m);
    expect(result.sql).not.toMatch(/^LOCK TABLE public\.workspace_engine_settings/m);
  });
});
