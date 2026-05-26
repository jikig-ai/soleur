// One-shot post-deploy runner for the workspace filesystem migration
// (feat-team-workspace-multi-user). Renames `/workspaces/<userId>` →
// `/workspaces/<workspaceId>` for every row in `workspace_members` where the
// two diverge, and leaves a symlink at the legacy path. Idempotent — see
// `server/workspace-fs-migrate.ts` invariants. NOT a Post-merge operator
// step; intended to be invoked inline by the deploy pipeline (Soleur deploy
// skill, after `run-migrations.sh` lands the SQL migrations).
//
// For today's solo-only fleet (N2 invariant: workspaces.id === user.id) this
// runs as a pure no-op pass and reports `migrated: 0, skipped: N, failed: 0`.
// Once Phase 5 team invites land, new members will have workspaces.id ≠
// user.id, and this script becomes the only path that moves their on-disk
// directory under the canonical mount.
//
// Usage:
//   doppler run -p soleur -c prd -- bun run apps/web-platform/scripts/run-workspace-fs-migrate.ts
//
// Requires:
//   SUPABASE_URL                 (any env)
//   SUPABASE_SERVICE_ROLE_KEY    (any env)
//   WORKSPACES_ROOT              (host-side; default "/workspaces")

import { createClient } from "@supabase/supabase-js";
import {
  migrateAllUserWorkspaces,
  type UserWorkspacePair,
} from "../server/workspace-fs-migrate";

async function main(): Promise<void> {
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) {
    throw new Error(
      "SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY must be set (use `doppler run -- bun run ...`)",
    );
  }

  const supabase = createClient(url, key, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { data, error } = await supabase
    .from("workspace_members")
    .select("user_id, workspace_id");
  if (error) {
    throw new Error(`workspace_members query failed: ${error.message}`);
  }
  if (!data) {
    throw new Error("workspace_members query returned no data envelope");
  }

  const pairs: UserWorkspacePair[] = data.map((r) => ({
    userId: r.user_id as string,
    workspaceId: r.workspace_id as string,
  }));

  const result = migrateAllUserWorkspaces(pairs);

  // Structured single-line output so the deploy runner can grep + mirror to
  // Sentry / its own log surface.
  console.log(
    JSON.stringify({
      script: "run-workspace-fs-migrate",
      total: pairs.length,
      ...result,
    }),
  );

  if (result.failed > 0) {
    process.exit(1);
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
