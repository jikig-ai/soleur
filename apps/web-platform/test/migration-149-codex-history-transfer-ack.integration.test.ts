import { spawnSync } from "node:child_process";
import { readFileSync } from "node:fs";
import path from "node:path";
import { describe, expect, it } from "vitest";

const isCi = process.env.CI === "true";
const container = isCi
  ? `codex_ack_pg_${process.pid}_${Math.floor(Math.random() * 1_000_000)}`
  : "supabase_db_web-platform";
const migration = path.join(__dirname, "../supabase/migrations/149_codex_history_transfer_ack.sql");
const ownershipHardening = path.join(__dirname, "../supabase/migrations/150_codex_history_ack_owner_scope.sql");
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
    throw new Error(`Codex acknowledgment SQL failed (${result.status}): ${result.stderr}`);
  }
  return result.stdout.trim();
}

describe("migration 149 acknowledgment RPCs on disposable PostgreSQL", () => {
  it.skipIf(!canRunDatabaseTest)("fences acknowledgments by active member and current binding generation", async () => {
    let ownsContainer = false;
    const database = `codex_ack_test_${process.pid}_${Math.floor(Math.random() * 1_000_000)}`;
    let databaseCreated = false;

    try {
      if (isCi) {
        const start = docker([
          "run", "--detach", "--rm", "--name", container,
          "-e", "POSTGRES_PASSWORD=codex-ack-test-only",
          "postgres:17-alpine",
        ], undefined, 180_000);
        expect(start.status, `could not start disposable PostgreSQL: ${start.stderr}`).toBe(0);
        ownsContainer = true;
        let ready = false;
        for (let attempt = 0; attempt < 90; attempt += 1) {
          const probe = docker(["exec", container, "pg_isready", "-U", "postgres"]);
          if (probe.status === 0) {
            ready = true;
            break;
          }
          await new Promise((resolve) => setTimeout(resolve, 500));
        }
        expect(ready, "disposable PostgreSQL did not become ready within 45 seconds").toBe(true);
      }

      const create = docker(["exec", container, "createdb", "-U", dbUser, database]);
      expect(create.status, create.stderr).toBe(0);
      databaseCreated = true;
      const migrationSql = readFileSync(migration, "utf8");
      const ownershipHardeningSql = readFileSync(ownershipHardening, "utf8");
      const output = runSql(database, `
        CREATE SCHEMA auth;
        CREATE FUNCTION auth.uid() RETURNS uuid LANGUAGE sql STABLE AS $$
          SELECT NULLIF(current_setting('request.jwt.claim.sub', true), '')::uuid
        $$;
        DO $$ BEGIN CREATE ROLE anon; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
        DO $$ BEGIN CREATE ROLE authenticated; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
        DO $$ BEGIN CREATE ROLE service_role; EXCEPTION WHEN duplicate_object THEN NULL; END $$;
        CREATE TABLE public.users (id uuid PRIMARY KEY);
        CREATE TABLE public.conversations (id uuid PRIMARY KEY, user_id uuid NOT NULL, workspace_id uuid NOT NULL);
        CREATE TABLE public.workspace_members (
          workspace_id uuid NOT NULL,
          user_id uuid NOT NULL REFERENCES public.users(id),
          created_at timestamptz NOT NULL,
          PRIMARY KEY (workspace_id, user_id)
        );
        CREATE TABLE public.agent_engine_runs (
          id uuid PRIMARY KEY,
          workspace_id uuid NOT NULL,
          execution_kind text NOT NULL,
          conversation_id uuid NOT NULL,
          engine_id text NOT NULL,
          auth_mode_generation bigint NOT NULL
        );
        CREATE FUNCTION public.is_workspace_member(uuid, uuid) RETURNS boolean
        LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp AS $$
        BEGIN
          RETURN EXISTS (
            SELECT 1 FROM public.workspace_members AS m
             WHERE m.workspace_id = $1 AND m.user_id = $2
          );
        END;
        $$;
        ${migrationSql}
        SELECT has_table_privilege('service_role', 'public.codex_history_transfer_acknowledgments', 'SELECT');
        SELECT has_table_privilege('authenticated', 'public.codex_history_transfer_acknowledgments', 'SELECT');
        SELECT has_table_privilege('anon', 'public.codex_history_transfer_acknowledgments', 'SELECT');
        INSERT INTO public.users VALUES
          ('30000000-0000-4000-8000-000000000001'),
          ('30000000-0000-4000-8000-000000000002');
        INSERT INTO public.conversations VALUES
          ('40000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001', '50000000-0000-4000-8000-000000000001');
        INSERT INTO public.workspace_members VALUES
          ('50000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001', '2026-09-01T00:00:00Z'),
          ('50000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000002', '2026-09-01T00:00:00Z');
        INSERT INTO public.agent_engine_runs VALUES (
          '60000000-0000-4000-8000-000000000001',
          '50000000-0000-4000-8000-000000000001',
          'conversation',
          '40000000-0000-4000-8000-000000000001',
          'codex',
          3
        );
        -- A row permitted by 149 must be purged by the forward correction.
        INSERT INTO public.codex_history_transfer_acknowledgments
          (conversation_id, member_user_id, auth_mode_generation, workspace_member_created_at)
        VALUES ('40000000-0000-4000-8000-000000000001',
          '30000000-0000-4000-8000-000000000002', 3, '2026-09-01T00:00:00Z');
        ${ownershipHardeningSql}
        SELECT count(*) FROM public.codex_history_transfer_acknowledgments;
        -- Another member of the SAME workspace cannot acknowledge the owner's conversation.
        SET request.jwt.claim.sub = '30000000-0000-4000-8000-000000000002';
        SELECT public.record_codex_history_transfer_acknowledgment(
          '40000000-0000-4000-8000-000000000001', 3
        );
        SELECT public.codex_history_transfer_acknowledged(
          '40000000-0000-4000-8000-000000000001', 3
        );
        SET request.jwt.claim.sub = '30000000-0000-4000-8000-000000000001';
        SELECT public.record_codex_history_transfer_acknowledgment(
          '40000000-0000-4000-8000-000000000001', 3
        );
        SELECT public.codex_history_transfer_acknowledged(
          '40000000-0000-4000-8000-000000000001', 3
        );
        SET request.jwt.claim.sub = '30000000-0000-4000-8000-000000000002';
        SELECT public.record_codex_history_transfer_acknowledgment(
          '40000000-0000-4000-8000-000000000001', 3
        );
        SET request.jwt.claim.sub = '30000000-0000-4000-8000-000000000001';
        UPDATE public.agent_engine_runs SET auth_mode_generation = 4
         WHERE conversation_id = '40000000-0000-4000-8000-000000000001';
        SELECT count(*) FROM public.codex_history_transfer_acknowledgments;
        SELECT public.codex_history_transfer_acknowledged(
          '40000000-0000-4000-8000-000000000001', 3
        );
        SELECT public.record_codex_history_transfer_acknowledgment(
          '40000000-0000-4000-8000-000000000001', 4
        );
        UPDATE public.workspace_members SET created_at = '2026-09-02T00:00:00Z'
         WHERE user_id = '30000000-0000-4000-8000-000000000001';
        SELECT public.codex_history_transfer_acknowledged(
          '40000000-0000-4000-8000-000000000001', 4
        );
        SELECT public.record_codex_history_transfer_acknowledgment(
          '40000000-0000-4000-8000-000000000001', 4
        );
        DELETE FROM public.workspace_members WHERE user_id = '30000000-0000-4000-8000-000000000001';
        DELETE FROM public.users WHERE id = '30000000-0000-4000-8000-000000000001';
        SELECT count(*) FROM public.codex_history_transfer_acknowledgments;
      `);

      expect(output.split("\n")).toEqual(["t", "f", "f", "0", "f", "f", "t", "t", "f", "0", "f", "t", "f", "t", "0"]);
    } finally {
      if (databaseCreated) {
        const drop = docker(["exec", container, "dropdb", "--if-exists", "-U", dbUser, database]);
        expect(drop.status, drop.stderr).toBe(0);
      }
      if (ownsContainer) {
        const remove = docker(["rm", "--force", container]);
        expect(remove.status, remove.stderr).toBe(0);
      }
    }
  }, 180_000);
});
