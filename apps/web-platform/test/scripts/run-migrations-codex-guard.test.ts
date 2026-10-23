import { spawnSync } from "node:child_process";
import { chmodSync, cpSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { describe, expect, it } from "vitest";

const scripts = path.resolve(__dirname, "../../scripts");

describe("migration 165 admission in the real migration runner", () => {
  function captureApply(filename: string, missingGuard = false, legacyRows: string[] = [], migrationBodies: Record<string, string> = {}, failAckPreflight = false, failOwnerScopeApply = false) {
    const fixture = mkdtempSync(path.join(tmpdir(), "codex-migration-runner-"));
    try {
      for (const dir of ["scripts/sql", "supabase/migrations", "bin"]) mkdirSync(path.join(fixture, dir), { recursive: true });
      cpSync(path.join(scripts, "run-migrations.sh"), path.join(fixture, "scripts/run-migrations.sh"));
      if (!missingGuard) cpSync(path.join(scripts, "sql/codex-auth-mode-pre-migration.sql"), path.join(fixture, "scripts/sql/codex-auth-mode-pre-migration.sql"));
      writeFileSync(path.join(fixture, "supabase/migrations", filename), migrationBodies[filename] ?? "BEGIN;\nCREATE TABLE public.synthetic_migration_body (id integer);\nCOMMIT;\n");
      for (const [name, body] of Object.entries(migrationBodies)) {
        if (name !== filename) writeFileSync(path.join(fixture, "supabase/migrations", name), body);
      }
      writeFileSync(path.join(fixture, "scripts/postgrest-reload-schema.sh"), "#!/usr/bin/env bash\nexit 0\n");
      writeFileSync(path.join(fixture, "bin/git"), "#!/usr/bin/env bash\ncase \"$1\" in\nfetch) exit 0 ;;\nls-tree) printf '100644 blob 1111111111111111111111111111111111111111 fixture.sql\\n' ;;\nhash-object) printf '1111111111111111111111111111111111111111\\n' ;;\n*) exit 64 ;;\nesac\n");
      writeFileSync(path.join(fixture, "bin/psql"), `#!/usr/bin/env bash
case "$*" in
  *" -c "*) case "$*" in
    *"SELECT count(*)"*) printf '0\\n' ;;
    *"SELECT filename FROM public._schema_migrations"*) printf '%s\\n' ${legacyRows.map((row) => `'${row}'`).join(" ") || ""} ;;
    *"REVOKE ALL ON FUNCTION public.record_codex_history_transfer_acknowledgment"*)
      if [[ '${failAckPreflight}' == true ]]; then exit 1; fi
      printf '%s\\n' "$*" >> '${path.join(fixture, "ack-preflight.sql")}';;
  esac ;;
  *"--single-transaction"*" -f -"*)
    printf '\\n-- migration apply --\\n' >> '${path.join(fixture, "apply.sql")}'; cat >> '${path.join(fixture, "apply.sql")}';
    if [[ '${failOwnerScopeApply}' == true ]] && grep -q '^CREATE OR REPLACE FUNCTION public.record_codex_history_transfer_acknowledgment(' '${path.join(fixture, "apply.sql")}'; then exit 1; fi ;;
  *) exit 64 ;;
esac
`);
      for (const file of ["bin/git", "bin/psql"]) chmodSync(path.join(fixture, file), 0o755);
      const result = spawnSync("bash", [path.join(fixture, "scripts/run-migrations.sh"), "--bootstrap=skip"], {
        cwd: fixture,
        // An allowlisted environment keeps operator credentials out of the fixture.
        env: { NODE_ENV: "test", PATH: `${path.join(fixture, "bin")}:${process.env.PATH}`, DATABASE_URL: "postgres://synthetic.invalid/test", MIGRATION_SCHEMA_PRECONDITION_PROBE: "0" },
        encoding: "utf8", timeout: 15_000,
      });
      let sql = "";
      try { sql = readFileSync(path.join(fixture, "apply.sql"), "utf8"); } catch { /* No apply invocation on refusal. */ }
      let ackPreflightSql = "";
      try { ackPreflightSql = readFileSync(path.join(fixture, "ack-preflight.sql"), "utf8"); } catch { /* No preflight invocation. */ }
      return { status: result.status, output: result.stdout + result.stderr, sql, ackPreflightSql };
    } finally { rmSync(fixture, { recursive: true, force: true }); }
  }

  it("places the bounded lock and rejection before the unchanged migration and its ledger write in one transaction", () => {
    const result = captureApply("165_codex_auth_mode_rebind.sql");
    expect(result.status, result.output).toBe(0);
    const lock = result.sql.search(/^LOCK TABLE public\.workspace_engine_settings IN ACCESS EXCLUSIVE MODE;/m);
    const rejection = result.sql.search(/^\s*RAISE EXCEPTION 'Codex auth-mode migration refused:/m);
    const body = result.sql.search(/^CREATE TABLE public\.synthetic_migration_body/m);
    const ledger = result.sql.search(/^\s*INSERT INTO public\._schema_migrations/m);
    expect(lock).toBeGreaterThan(0);
    expect(rejection).toBeGreaterThan(lock);
    expect(body).toBeGreaterThan(rejection);
    expect(ledger).toBeGreaterThan(body);
    expect(result.sql).toMatch(/^SET LOCAL lock_timeout = '30s';/m);
    expect(result.sql).toMatch(/^SET LOCAL statement_timeout = '5min';/m);
    expect(result.sql).not.toMatch(/^(?:BEGIN|COMMIT|ROLLBACK);/m);
  });

  it("fails before applying when the required guard asset is absent", () => {
    const result = captureApply("165_codex_auth_mode_rebind.sql", true);
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

  it.each([
    ["143_agent_engine_attempts.sql", "163_agent_engine_attempts.sql"],
    ["144_codex_auth_mode_rebind.sql", "164_codex_auth_mode_rebind.sql"],
    ["145_codex_auth_mode_rebind.sql", "165_codex_auth_mode_rebind.sql"],
  ])("fails closed on legacy ledger row %s before applying the renamed chain", (legacy, renamed) => {
    const result = captureApply(renamed, false, [legacy]);
    expect(result.status, result.output).not.toBe(0);
    expect(result.output).toContain(`legacy migration ledger row ${legacy}`);
    expect(result.output).toContain(`renamed migration ${renamed}`);
    expect(result.output).toContain("explicit ledger reconciliation");
    expect(result.sql).toBe("");
  });

  it("checks the whole renamed chain before an earlier pending migration", () => {
    const result = captureApply("163_agent_engine_attempts.sql", false, ["145_codex_auth_mode_rebind.sql"]);
    expect(result.status, result.output).not.toBe(0);
    expect(result.output).toContain("legacy migration ledger row 145_codex_auth_mode_rebind.sql");
    expect(result.output).toContain("renamed migration 165_codex_auth_mode_rebind.sql");
    expect(result.sql).toBe("");
  });

  it("keeps authenticated RPC execution closed across migrations 169 and 170", () => {
    const migrations = path.resolve(__dirname, "../../supabase/migrations");
    const migrationBodies = Object.fromEntries([
      "169_codex_history_transfer_ack.sql",
      "170_codex_history_ack_owner_scope.sql",
    ].map((name) => [name, readFileSync(path.join(migrations, name), "utf8")]));
    const result = captureApply("169_codex_history_transfer_ack.sql", false, [], migrationBodies);
    expect(result.status, result.output).toBe(0);
    const applies = result.sql.split("-- migration apply --").slice(1);
    expect(applies).toHaveLength(2);
    const [first, second] = applies;
    const indexOfLine = (sql: string, expression: RegExp) => sql.match(expression)?.index ?? -1;
    const firstGrant = indexOfLine(first, /^GRANT EXECUTE ON FUNCTION public\.record_codex_history_transfer_acknowledgment\(uuid, bigint\) TO authenticated;$/m);
    const recordRevoke = indexOfLine(first, /^REVOKE ALL ON FUNCTION public\.record_codex_history_transfer_acknowledgment\(uuid, bigint\) FROM PUBLIC, anon, authenticated, service_role;$/m);
    const acknowledgedRevoke = indexOfLine(first, /^REVOKE ALL ON FUNCTION public\.codex_history_transfer_acknowledged\(uuid, bigint\) FROM PUBLIC, anon, authenticated, service_role;$/m);
    const firstLedger = indexOfLine(first, /^\s*INSERT INTO public\._schema_migrations/m);
    expect(firstGrant).toBeGreaterThan(0);
    expect(recordRevoke).toBeGreaterThan(firstGrant);
    expect(acknowledgedRevoke).toBeGreaterThan(firstGrant);
    expect(firstLedger).toBeGreaterThan(recordRevoke);
    expect(firstLedger).toBeGreaterThan(acknowledgedRevoke);

    const recordRevokeBeforeReplace = indexOfLine(second, /^REVOKE ALL ON FUNCTION public\.record_codex_history_transfer_acknowledgment\(uuid, bigint\) FROM PUBLIC, anon, authenticated, service_role;$/m);
    const acknowledgedRevokeBeforeReplace = indexOfLine(second, /^REVOKE ALL ON FUNCTION public\.codex_history_transfer_acknowledged\(uuid, bigint\) FROM PUBLIC, anon, authenticated, service_role;$/m);
    const recordDefinition = indexOfLine(second, /^CREATE OR REPLACE FUNCTION public\.record_codex_history_transfer_acknowledgment\(/m);
    const recordOwner = indexOfLine(second, /^[\t ]+AND c\.user_id = v_member_user_id$/m);
    const acknowledgedDefinition = indexOfLine(second, /^CREATE OR REPLACE FUNCTION public\.codex_history_transfer_acknowledged\(/m);
    const ownerPredicates = [...second.matchAll(/^[\t ]+AND c\.user_id = v_member_user_id$/gm)];
    const scopedGrants = [...second.matchAll(/^GRANT EXECUTE ON FUNCTION public\.(?:record_codex_history_transfer_acknowledgment|codex_history_transfer_acknowledged)\(uuid, bigint\) TO authenticated;$/gm)];
    const secondLedger = indexOfLine(second, /^\s*INSERT INTO public\._schema_migrations/m);
    expect(result.ackPreflightSql).toContain("--single-transaction");
    expect(result.ackPreflightSql).toContain("REVOKE ALL ON FUNCTION public.record_codex_history_transfer_acknowledgment(uuid, bigint)");
    expect(result.ackPreflightSql).toContain("REVOKE ALL ON FUNCTION public.codex_history_transfer_acknowledged(uuid, bigint)");
    expect(recordRevokeBeforeReplace).toBeGreaterThan(0);
    expect(acknowledgedRevokeBeforeReplace).toBeGreaterThan(0);
    expect(recordRevokeBeforeReplace).toBeLessThan(recordDefinition);
    expect(acknowledgedRevokeBeforeReplace).toBeLessThan(recordDefinition);
    expect(recordOwner).toBeGreaterThan(recordDefinition);
    expect(acknowledgedDefinition).toBeGreaterThan(recordOwner);
    expect(ownerPredicates).toHaveLength(2);
    expect(ownerPredicates[0]!.index).toBe(recordOwner);
    expect(ownerPredicates[1]!.index).toBeGreaterThan(acknowledgedDefinition);
    expect(scopedGrants).toHaveLength(2);
    for (const grant of scopedGrants) expect(grant.index).toBeGreaterThan(ownerPredicates[1]!.index);
    expect(secondLedger).toBeGreaterThan(scopedGrants[1]!.index);
    for (const sql of applies) expect(sql).not.toMatch(/^(?:BEGIN|COMMIT|ROLLBACK);/m);
  });

  it("does not apply migration 170 when the committed acknowledgment revoke fails", () => {
    const migrations = path.resolve(__dirname, "../../supabase/migrations");
    const migrationBodies = Object.fromEntries([
      "169_codex_history_transfer_ack.sql",
      "170_codex_history_ack_owner_scope.sql",
    ].map((name) => [name, readFileSync(path.join(migrations, name), "utf8")]));
    const result = captureApply("169_codex_history_transfer_ack.sql", false, [], migrationBodies, true);
    expect(result.status).not.toBe(0);
    expect(result.output).toContain("Could not close Codex acknowledgment RPC grants before migration 170");
    expect(result.sql.split("-- migration apply --")).toHaveLength(2);
  });

  it("keeps migration 170 failure after the committed revoke fail-closed", () => {
    const migrations = path.resolve(__dirname, "../../supabase/migrations");
    const migrationBodies = Object.fromEntries([
      "169_codex_history_transfer_ack.sql",
      "170_codex_history_ack_owner_scope.sql",
    ].map((name) => [name, readFileSync(path.join(migrations, name), "utf8")]));
    const result = captureApply("169_codex_history_transfer_ack.sql", false, [], migrationBodies, false, true);
    expect(result.status).not.toBe(0);
    expect(result.output).toContain("Migration failed: 170_codex_history_ack_owner_scope.sql");
    expect(result.ackPreflightSql).toContain("REVOKE ALL ON FUNCTION public.record_codex_history_transfer_acknowledgment(uuid, bigint)");
    const applies = result.sql.split("-- migration apply --").slice(1);
    expect(applies).toHaveLength(2);
    expect(applies[1]).toContain("GRANT EXECUTE ON FUNCTION public.record_codex_history_transfer_acknowledgment(uuid, bigint) TO authenticated;");
  });
});
