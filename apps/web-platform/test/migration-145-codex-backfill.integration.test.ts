import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import path from "node:path";
import { afterAll, beforeAll, describe, expect, it } from "vitest";

const isCi = process.env.CI === "true";
const container = isCi
  ? `codex_rebind_pg_${process.pid}_${Math.floor(Math.random() * 1_000_000)}`
  : "supabase_db_web-platform";
const migration = path.join(__dirname, "../supabase/migrations/145_codex_auth_mode_rebind.sql");
const erasureMigration = path.join(__dirname, "../supabase/migrations/152_agent_engine_erasure_lock_order.sql");
const docker = (args: string[], input?: string, timeout = 10_000) => spawnSync("docker", args, {
  encoding: "utf8",
  input,
  timeout,
  maxBuffer: 1024 * 1024,
});
const dockerAvailable = isCi
  ? { status: 0, stdout: "true" }
  : docker(["inspect", "--format", "{{.State.Running}}", container]);
const canRunDatabaseTest = isCi || (dockerAvailable.status === 0 && dockerAvailable.stdout.trim() === "true");
const dbUser = isCi ? "postgres" : "supabase_admin";

function runSql(database: string, sql: string): string {
  const result = docker([
    "exec", "-i", container, "psql", "-X", "-q", "-A", "-t", "-F", "|",
    "-v", "ON_ERROR_STOP=1", "-U", dbUser, "-d", database,
  ], sql);
  if (result.status !== 0) {
    throw new Error(`isolated Codex backfill SQL failed (${result.status}): ${result.stderr}`);
  }
  return result.stdout.trim();
}

const ownerId = "70000000-0000-4000-8000-000000000001";
const otherOwnerId = "70000000-0000-4000-8000-000000000004";
const workspaceId = "70000000-0000-4000-8000-000000000002";
const otherWorkspaceId = "70000000-0000-4000-8000-000000000003";
const runId = (index: number) => `80000000-0000-4000-8000-${String(index).padStart(12, "0")}`;

function ownerRebindFixture(): string {
  const definitions = [
    { file: migration, name: "set_workspace_default_engine" },
    { file: migration, name: "count_codex_conversation_rebinds" },
    { file: erasureMigration, name: "save_agent_engine_recovery_checkpoint" },
    { file: erasureMigration, name: "anonymise_agent_engine_data" },
  ].map(({ file, name }) => {
    const definition = readFileSync(file, "utf8").match(new RegExp(`^CREATE OR REPLACE FUNCTION public\\.${name}\\([\\s\\S]*?^\\$\\$;`, "m"));
    expect(definition, `${path.basename(file)} ${name} RPC`).not.toBeNull();
    return definition![0];
  });
  // Execute the migration's public RPC bodies unchanged. The fixture provides
  // their table dependencies; it does not prove the complete migration chain.
  return `
    CREATE SCHEMA auth;
    CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS
      $$ SELECT '${ownerId}'::uuid $$;
    CREATE FUNCTION auth.role() RETURNS text LANGUAGE sql STABLE AS
      $$ SELECT 'service_role'::text $$;
    CREATE TABLE public.workspaces (id uuid PRIMARY KEY, owner_id uuid NOT NULL);
    CREATE TABLE public.workspace_engine_settings (
      workspace_id uuid PRIMARY KEY REFERENCES public.workspaces(id),
      default_engine_id text NOT NULL,
      default_auth_mode text NOT NULL,
      codex_auth_mode text NOT NULL,
      updated_by uuid DEFAULT '${ownerId}',
      updated_at timestamptz NOT NULL DEFAULT now()
    );
    CREATE TABLE public.agent_engine_runs (
      id uuid PRIMARY KEY,
      workspace_id uuid NOT NULL REFERENCES public.workspaces(id),
      execution_kind text NOT NULL,
      engine_id text NOT NULL,
      auth_mode text NOT NULL,
      auth_mode_generation bigint NOT NULL,
      created_by uuid DEFAULT '${ownerId}'
    );
    CREATE TABLE public.agent_engine_attempts (
      id uuid PRIMARY KEY,
      run_id uuid NOT NULL REFERENCES public.agent_engine_runs(id),
      auth_mode_generation bigint NOT NULL
    );
    CREATE TABLE public.agent_engine_recovery_checkpoints (
      run_id uuid PRIMARY KEY REFERENCES public.agent_engine_runs(id),
      checkpoint jsonb NOT NULL,
      updated_at timestamptz NOT NULL DEFAULT now()
    );
    CREATE FUNCTION public.is_workspace_owner(uuid, uuid) RETURNS boolean
      LANGUAGE sql STABLE AS $$
        SELECT EXISTS (SELECT 1 FROM public.workspaces WHERE id = $1 AND owner_id = $2)
      $$;
    INSERT INTO public.workspaces VALUES
      ('${workspaceId}', '${ownerId}'), ('${otherWorkspaceId}', '${otherOwnerId}');
    INSERT INTO public.workspace_engine_settings
      (workspace_id, default_engine_id, default_auth_mode, codex_auth_mode)
    VALUES
      ('${workspaceId}', 'claude-code', 'api-key', 'managed'),
      ('${otherWorkspaceId}', 'codex', 'managed', 'managed');
    INSERT INTO public.agent_engine_runs
      (id, workspace_id, execution_kind, engine_id, auth_mode, auth_mode_generation)
    VALUES
      ('${runId(1)}', '${workspaceId}', 'conversation', 'codex', 'managed', 2),
      ('${runId(2)}', '${workspaceId}', 'conversation', 'codex', 'managed', 5),
      ('${runId(3)}', '${workspaceId}', 'conversation', 'codex', 'api-key', 7),
      ('${runId(4)}', '${workspaceId}', 'conversation', 'claude-code', 'managed', 11),
      ('${runId(5)}', '${workspaceId}', 'routine', 'codex', 'managed', 13),
      ('${runId(6)}', '${otherWorkspaceId}', 'conversation', 'codex', 'managed', 17);
    UPDATE public.agent_engine_runs SET created_by = '${otherOwnerId}' WHERE id = '${runId(6)}';
    UPDATE public.workspace_engine_settings SET updated_by = '${otherOwnerId}' WHERE workspace_id = '${otherWorkspaceId}';
    INSERT INTO public.agent_engine_recovery_checkpoints (run_id, checkpoint)
      SELECT id, jsonb_build_object('threadId', 'synthetic-thread-' || id::text)
        FROM public.agent_engine_runs;
    ${definitions.join("\n")}
  `;
}

function withOwnerRebindDatabase<T>(assertBehavior: (database: string) => T): T {
  const database = `codex_rebind_scope_${process.pid}_${Math.floor(Math.random() * 1_000_000)}`;
  const create = docker(["exec", container, "createdb", "-U", dbUser, database]);
  expect(create.status, create.stderr).toBe(0);
  try {
    runSql(database, ownerRebindFixture());
    return assertBehavior(database);
  } finally {
    const drop = docker(["exec", container, "dropdb", "--if-exists", "-U", dbUser, database]);
    expect(drop.status, drop.stderr).toBe(0);
  }
}

function rebindSnapshot(database: string) {
  return JSON.parse(runSql(database, `
    SELECT jsonb_build_object(
      'settings', (SELECT jsonb_agg(to_jsonb(s) ORDER BY s.workspace_id) FROM public.workspace_engine_settings AS s),
      'runs', (SELECT jsonb_agg(to_jsonb(r) ORDER BY r.id) FROM public.agent_engine_runs AS r),
      'checkpoints', (SELECT jsonb_agg(to_jsonb(c) ORDER BY c.run_id) FROM public.agent_engine_recovery_checkpoints AS c)
    );
  `));
}

describe.skipIf(!canRunDatabaseTest)("migration 145 Codex mode SQL on disposable PostgreSQL", () => {
  let ownsContainer = false;

  beforeAll(async () => {
    if (!isCi) return;
    const start = docker([
      "run", "--detach", "--rm", "--name", container,
      "-e", "POSTGRES_PASSWORD=codex-rebind-test-only",
      "postgres:17-alpine",
    ], undefined, 180_000);
    expect(start.status, `could not start disposable PostgreSQL: ${start.stderr}`).toBe(0);
    ownsContainer = true;
    let ready = false;
    for (let attempt = 0; attempt < 90; attempt += 1) {
      const probe = docker(["exec", container, "pg_isready", "-U", dbUser]);
      if (probe.status === 0) {
        ready = true;
        break;
      }
      await new Promise((resolve) => setTimeout(resolve, 500));
    }
    expect(ready, "disposable PostgreSQL did not become ready within 45 seconds").toBe(true);
  }, 240_000);

  afterAll(() => {
    if (!ownsContainer) return;
    const remove = docker(["rm", "--force", container]);
    expect(remove.status, remove.stderr).toBe(0);
  });

  it.skipIf(!canRunDatabaseTest)("keeps an existing API-key default without history or after an older managed run", () => {
    const database = `codex_backfill_test_${process.pid}_${Math.floor(Math.random() * 1_000_000)}`;
    const create = docker(["exec", container, "createdb", "-U", dbUser, database]);
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
      const drop = docker(["exec", container, "dropdb", "--if-exists", "-U", dbUser, database]);
      expect(drop.status, drop.stderr).toBe(0);
    }
  });

  it.skipIf(!canRunDatabaseTest)("preserves and returns the current defaults from inside the locked rebind RPC", () => {
    const database = `codex_rebind_rpc_test_${process.pid}_${Math.floor(Math.random() * 1_000_000)}`;
    const create = docker(["exec", container, "createdb", "-U", dbUser, database]);
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
      const drop = docker(["exec", container, "dropdb", "--if-exists", "-U", dbUser, database]);
      expect(drop.status, drop.stderr).toBe(0);
    }
  });

  it("rebinds only different-mode Codex conversations in the selected workspace and deletes only their checkpoints", () => {
    withOwnerRebindDatabase((database) => {
      const before = rebindSnapshot(database);
      expect(runSql(database, `SELECT public.count_codex_conversation_rebinds('${workspaceId}', 'api-key');`)).toBe("2");

      const result = JSON.parse(runSql(database, `
        SELECT public.set_workspace_default_engine('${workspaceId}', 'codex', 'api-key', true, 2);
      `));
      expect(result).toEqual({
        defaultEngineId: "claude-code",
        defaultAuthMode: "api-key",
        affectedConversationCount: 2,
        deletedCheckpointCount: 2,
      });

      const after = rebindSnapshot(database);
      expect(after.runs).toEqual(before.runs.map((run: { id: string; auth_mode_generation: number }) =>
        run.id === runId(1) || run.id === runId(2)
          ? { ...run, auth_mode: "api-key", auth_mode_generation: run.auth_mode_generation + 1 }
          : run,
      ));
      expect(after.checkpoints).toEqual(before.checkpoints.filter((checkpoint: { run_id: string }) =>
        checkpoint.run_id !== runId(1) && checkpoint.run_id !== runId(2),
      ));
      expect(after.settings.find((setting: { workspace_id: string }) => setting.workspace_id === workspaceId))
        .toEqual(expect.objectContaining({
          default_engine_id: "claude-code", default_auth_mode: "api-key",
          codex_auth_mode: "api-key", updated_by: ownerId,
        }));
      expect(after.settings.find((setting: { workspace_id: string }) => setting.workspace_id === otherWorkspaceId))
        .toEqual(before.settings.find((setting: { workspace_id: string }) => setting.workspace_id === otherWorkspaceId));
      expect(runSql(database, `SELECT public.count_codex_conversation_rebinds('${workspaceId}', 'api-key');`)).toBe("0");
    });
  });

  it("changes the workspace default without rebinding conversations or deleting checkpoints when intent is false", () => {
    withOwnerRebindDatabase((database) => {
      const before = rebindSnapshot(database);
      const result = JSON.parse(runSql(database, `
        SELECT public.set_workspace_default_engine('${workspaceId}', 'codex', 'api-key', false);
      `));
      expect(result).toEqual({
        defaultEngineId: "codex",
        defaultAuthMode: "api-key",
        affectedConversationCount: 0,
        deletedCheckpointCount: 0,
      });
      const after = rebindSnapshot(database);
      expect(after.runs).toEqual(before.runs);
      expect(after.checkpoints).toEqual(before.checkpoints);
      expect(after.settings.find((setting: { workspace_id: string }) => setting.workspace_id === workspaceId))
        .toEqual(expect.objectContaining({ default_engine_id: "codex", default_auth_mode: "api-key", codex_auth_mode: "api-key" }));
      expect(after.settings.find((setting: { workspace_id: string }) => setting.workspace_id === otherWorkspaceId))
        .toEqual(before.settings.find((setting: { workspace_id: string }) => setting.workspace_id === otherWorkspaceId));
    });
  });

  it("rejects a changed affected count with SQLSTATE 40001 and leaves all settings, bindings and checkpoints intact", () => {
    withOwnerRebindDatabase((database) => {
      const before = rebindSnapshot(database);
      const output = runSql(database, `
        CREATE TEMP TABLE caught_rebind_error (sqlstate text NOT NULL);
        DO $$
        BEGIN
          BEGIN
            PERFORM public.set_workspace_default_engine('${workspaceId}', 'codex', 'api-key', true, 1);
          EXCEPTION WHEN serialization_failure THEN
            INSERT INTO caught_rebind_error VALUES (SQLSTATE);
          END;
        END;
        $$;
        SELECT sqlstate FROM caught_rebind_error;
      `);
      expect(output, "count mismatch must reach the owner RPC's conflict guard").toBe("40001");
      expect(rebindSnapshot(database)).toEqual(before);
    });
  });

  it("purges recovery state on anonymization and rejects a later checkpoint write with SQLSTATE 55000", () => {
    withOwnerRebindDatabase((database) => {
      const attemptId = "90000000-0000-4000-8000-000000000001";
      runSql(database, `
        INSERT INTO public.agent_engine_attempts VALUES ('${attemptId}', '${runId(1)}', 2);
        DO $$ BEGIN
          PERFORM public.save_agent_engine_recovery_checkpoint(
            '${runId(1)}', '${attemptId}', '{"threadId":"synthetic-before-erasure"}'::jsonb
          );
        END $$;
      `);
      expect(JSON.parse(runSql(database, `
        SELECT checkpoint FROM public.agent_engine_recovery_checkpoints WHERE run_id = '${runId(1)}';
      `))).toEqual({ threadId: "synthetic-before-erasure" });
      const before = rebindSnapshot(database);

      expect(runSql(database, `SELECT public.anonymise_agent_engine_data('${ownerId}');`)).toBe("11");
      const anonymized = rebindSnapshot(database);
      expect(anonymized.runs).toEqual(before.runs.map((run: { created_by: string }) =>
        run.created_by === ownerId ? { ...run, created_by: null } : run,
      ));
      expect(anonymized.settings).toEqual(before.settings.map((setting: { updated_by: string }) =>
        setting.updated_by === ownerId ? { ...setting, updated_by: null } : setting,
      ));
      expect(anonymized.checkpoints).toEqual(before.checkpoints.filter((checkpoint: { run_id: string }) =>
        checkpoint.run_id === runId(6),
      ));

      const rejection = runSql(database, `
        CREATE TEMP TABLE caught_checkpoint_error (code text NOT NULL, message text NOT NULL);
        DO $$
        BEGIN
          BEGIN
            PERFORM public.save_agent_engine_recovery_checkpoint(
              '${runId(1)}', '${attemptId}', '{"threadId":"synthetic-after-erasure"}'::jsonb
            );
          EXCEPTION WHEN SQLSTATE '55000' THEN
            INSERT INTO caught_checkpoint_error VALUES (SQLSTATE, SQLERRM);
          END;
        END;
        $$;
        SELECT code, message FROM caught_checkpoint_error;
      `);
      expect(rejection, "a valid same-generation checkpoint write must be rejected because the run was anonymized")
        .toBe("55000|engine run was anonymised");
      expect(rebindSnapshot(database)).toEqual(anonymized);
    });
  });
});
