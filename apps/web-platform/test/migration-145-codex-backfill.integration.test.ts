import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";

const container = "supabase_db_web-platform";
const migration = path.join(__dirname, "../supabase/migrations/145_codex_auth_mode_rebind.sql");
const docker = (args: string[], input?: string) => spawnSync("docker", args, {
  encoding: "utf8",
  input,
  maxBuffer: 1024 * 1024,
});
const dockerAvailable = docker(["inspect", "--format", "{{.State.Running}}", container]);
const canRunDatabaseTest = dockerAvailable.status === 0 && dockerAvailable.stdout.trim() === "true";

function runSql(database: string, sql: string): string {
  const result = docker([
    "exec", "-i", container, "psql", "-X", "-q", "-A", "-t", "-F", "|",
    "-v", "ON_ERROR_STOP=1", "-U", "supabase_admin", "-d", database,
  ], sql);
  if (result.status !== 0) {
    throw new Error(`isolated Codex backfill SQL failed (${result.status}): ${result.stderr}`);
  }
  return result.stdout.trim();
}

describe("migration 145 Codex mode SQL on disposable PostgreSQL", () => {
  it.skipIf(!canRunDatabaseTest)("keeps an existing API-key default without history or after an older managed run", () => {
    const database = `codex_backfill_test_${process.pid}_${Math.floor(Math.random() * 1_000_000)}`;
    const create = docker(["exec", container, "createdb", "-U", "supabase_admin", database]);
    expect(create.status, create.stderr).toBe(0);
    if (process.env.CODEX_TEST_REPORT_DATABASES === "1") process.stderr.write(`disposable test database: ${database}\n`);

    try {
      const migrationSql = readFileSync(migration, "utf8");
      const update = migrationSql.match(/UPDATE public\.workspace_engine_settings AS settings[\s\S]*?;\n\nCREATE INDEX/);
      expect(update, "migration 145 backfill statement").not.toBeNull();
      const backfill = update![0].replace(/\n\nCREATE INDEX[\s\S]*$/, "").replaceAll("public.", "codex_backfill.");
      const output = runSql(database, `
        CREATE SCHEMA codex_backfill;
        CREATE TABLE codex_backfill.workspace_engine_settings (
          workspace_id uuid PRIMARY KEY,
          default_engine_id text NOT NULL,
          default_auth_mode text NOT NULL,
          codex_auth_mode text NOT NULL DEFAULT 'managed'
        );
        CREATE TABLE codex_backfill.agent_engine_runs (
          workspace_id uuid NOT NULL,
          execution_kind text NOT NULL,
          engine_id text NOT NULL,
          auth_mode text NOT NULL,
          created_at timestamptz NOT NULL
        );
        INSERT INTO codex_backfill.workspace_engine_settings VALUES
          ('10000000-0000-4000-8000-000000000001', 'codex', 'api-key', 'managed'),
          ('10000000-0000-4000-8000-000000000002', 'codex', 'api-key', 'managed'),
          ('10000000-0000-4000-8000-000000000003', 'claude-code', 'managed', 'managed'),
          ('10000000-0000-4000-8000-000000000004', 'claude-code', 'managed', 'managed');
        INSERT INTO codex_backfill.agent_engine_runs VALUES
          ('10000000-0000-4000-8000-000000000002', 'conversation', 'codex', 'managed', '2025-01-01T00:00:00Z'),
          ('10000000-0000-4000-8000-000000000003', 'conversation', 'codex', 'api-key', '2025-01-01T00:00:00Z'),
          ('10000000-0000-4000-8000-000000000004', 'conversation', 'codex', 'managed', '2025-01-01T00:00:00Z'),
          ('10000000-0000-4000-8000-000000000004', 'conversation', 'codex', 'api-key', '2025-02-01T00:00:00Z');
        ${backfill}
        SELECT workspace_id, codex_auth_mode
          FROM codex_backfill.workspace_engine_settings
         ORDER BY workspace_id;
      `);
      expect(output.split("\n")).toEqual([
        "10000000-0000-4000-8000-000000000001|api-key",
        "10000000-0000-4000-8000-000000000002|api-key",
        "10000000-0000-4000-8000-000000000003|api-key",
        "10000000-0000-4000-8000-000000000004|api-key",
      ]);
    } finally {
      const drop = docker(["exec", container, "dropdb", "--if-exists", "-U", "supabase_admin", database]);
      expect(drop.status, drop.stderr).toBe(0);
    }
  });

  it.skipIf(!canRunDatabaseTest)("preserves and returns the current defaults from inside the locked rebind RPC", () => {
    const database = `codex_rebind_rpc_test_${process.pid}_${Math.floor(Math.random() * 1_000_000)}`;
    const create = docker(["exec", container, "createdb", "-U", "supabase_admin", database]);
    expect(create.status, create.stderr).toBe(0);
    if (process.env.CODEX_TEST_REPORT_DATABASES === "1") process.stderr.write(`disposable test database: ${database}\n`);

    try {
      const migrationSql = readFileSync(migration, "utf8");
      const functionDefinition = migrationSql.match(/CREATE(?: OR REPLACE)? FUNCTION public\.set_workspace_default_engine\([\s\S]*?^\$\$;/m);
      expect(functionDefinition, "migration 145 owner rebind RPC").not.toBeNull();
      const rpc = functionDefinition![0].replaceAll("public.", "codex_rpc.");
      const output = runSql(database, `
        CREATE SCHEMA auth;
        CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS
          $$ SELECT '20000000-0000-4000-8000-000000000001'::uuid $$;
        CREATE SCHEMA codex_rpc;
        CREATE TABLE codex_rpc.workspaces (id uuid PRIMARY KEY);
        CREATE TABLE codex_rpc.workspace_engine_settings (
          workspace_id uuid PRIMARY KEY,
          default_engine_id text NOT NULL,
          default_auth_mode text NOT NULL,
          codex_auth_mode text NOT NULL,
          updated_by uuid,
          updated_at timestamptz NOT NULL DEFAULT now()
        );
        CREATE TABLE codex_rpc.agent_engine_runs (
          id uuid PRIMARY KEY,
          workspace_id uuid NOT NULL,
          execution_kind text NOT NULL,
          engine_id text NOT NULL,
          auth_mode text NOT NULL,
          auth_mode_generation bigint NOT NULL DEFAULT 0
        );
        CREATE TABLE codex_rpc.agent_engine_recovery_checkpoints (run_id uuid PRIMARY KEY);
        CREATE FUNCTION codex_rpc.is_workspace_owner(uuid, uuid) RETURNS boolean
          LANGUAGE sql STABLE AS $$ SELECT true $$;
        INSERT INTO codex_rpc.workspaces VALUES ('20000000-0000-4000-8000-000000000002');
        INSERT INTO codex_rpc.workspace_engine_settings
          (workspace_id, default_engine_id, default_auth_mode, codex_auth_mode)
        VALUES ('20000000-0000-4000-8000-000000000002', 'claude-code', 'managed', 'managed');
        INSERT INTO codex_rpc.agent_engine_runs
          (id, workspace_id, execution_kind, engine_id, auth_mode)
        VALUES ('20000000-0000-4000-8000-000000000003', '20000000-0000-4000-8000-000000000002', 'conversation', 'codex', 'managed');
        ${rpc}
        -- Simulate a separate owner save after an earlier request read settings.
        UPDATE codex_rpc.workspace_engine_settings SET default_auth_mode = 'api-key'
         WHERE workspace_id = '20000000-0000-4000-8000-000000000002';
        WITH rebind AS (
          SELECT codex_rpc.set_workspace_default_engine(
            '20000000-0000-4000-8000-000000000002', 'codex', 'api-key', true, 1
          ) AS value
        )
        SELECT (rebind.value->>'defaultEngineId') || '|' ||
               (rebind.value->>'defaultAuthMode')
          FROM rebind;
        SELECT default_engine_id || '|' || default_auth_mode || '|' || codex_auth_mode
          FROM codex_rpc.workspace_engine_settings
         WHERE workspace_id = '20000000-0000-4000-8000-000000000002';
      `);
      expect(output.split("\n")).toEqual(["claude-code|api-key", "claude-code|api-key|api-key"]);
    } finally {
      const drop = docker(["exec", container, "dropdb", "--if-exists", "-U", "supabase_admin", database]);
      expect(drop.status, drop.stderr).toBe(0);
    }
  });
});
