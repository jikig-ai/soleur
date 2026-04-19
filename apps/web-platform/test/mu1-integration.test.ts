// MU1 (Multi-User Readiness Gate item 1) — verification integration tests.
// Evidence that the 4 AC of issue #1448 still hold for each release:
//   AC-1: new signup triggers workspace-row creation via handle_new_user trigger.
//   AC-2: workspace clones the user's connected GitHub repo.
//   AC-3: Soleur plugin is installed (symlinked) in the workspace.
//   AC-4: workspaces are isolated per user (distinct paths + sandbox reject).
//
// Default lane: only the offline tests (AC-3, AC-4) run.
// MU1_INTEGRATION=1: AC-1 runs against the dev Supabase project.
// AC-2 is deferred until a public fixture repo exists — see #2605.
//
// See:
//   - knowledge-base/project/plans/2026-04-18-ops-verify-signup-workspace-provisioning-plan.md
//   - knowledge-base/engineering/ops/runbooks/mu1-signup-workspace-verification.md

import { tmpdir } from "os";
import { mkdtempSync, existsSync, readlinkSync } from "fs";
import { join } from "path";
import { randomUUID } from "crypto";

// Set env BEFORE importing the module under test — workspace.ts reads these
// at call time, not load time, but the GIT_* hygiene must happen before any
// git subprocess runs (see workspace.test.ts for rationale).
const PLUGIN_ROOT = mkdtempSync(join(tmpdir(), "mu1-plugin-"));
const WORKSPACES_ROOT = mkdtempSync(join(tmpdir(), "mu1-workspaces-"));
process.env.SOLEUR_PLUGIN_PATH = PLUGIN_ROOT;
process.env.WORKSPACES_ROOT = WORKSPACES_ROOT;
process.env.GIT_CEILING_DIRECTORIES = tmpdir();
delete process.env.GIT_DIR;
delete process.env.GIT_INDEX_FILE;
delete process.env.GIT_WORK_TREE;

import { afterEach, describe, expect, test } from "vitest";
import {
  provisionWorkspace,
  removeWorkspaceDir,
} from "../server/workspace";
import { isPathInWorkspace } from "../server/sandbox";

// Synthetic-identifier allowlist for MU1. Per
// cq-destructive-prod-tests-allowlist — any destructive cleanup must refuse
// to touch an identifier that does not match this regex. Pinned to the v4
// UUID shape (8-4-4-4-12 hex) rather than a permissive hex-blob prefix so
// the same regex can safely drive the runbook's sweep one-liner.
const SYNTH_EMAIL_RE =
  /^mu1-integration-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}@soleur-test\.invalid$/i;

function assertSyntheticEmail(email: string): void {
  if (!SYNTH_EMAIL_RE.test(email)) {
    throw new Error(`Refusing to act on non-synthetic email: ${email}`);
  }
}

const provisionedWorkspaces: string[] = [];

afterEach(() => {
  while (provisionedWorkspaces.length > 0) {
    const ws = provisionedWorkspaces.pop();
    if (ws) removeWorkspaceDir(ws);
  }
});

// ---------------------------------------------------------------------------
// AC-3: Latest Soleur plugin is installed (symlinked) in the workspace.
// Offline — no external deps. Always runs.
// ---------------------------------------------------------------------------

describe("MU1 AC-3: plugin symlink", () => {
  test("provisionWorkspace creates plugins/soleur symlink pointing to SOLEUR_PLUGIN_PATH", async () => {
    const userId = randomUUID();
    const ws = await provisionWorkspace(userId);
    provisionedWorkspaces.push(ws);

    const symlinkPath = join(ws, "plugins", "soleur");
    expect(existsSync(symlinkPath)).toBe(true);

    const target = readlinkSync(symlinkPath);
    expect(target).toBe(PLUGIN_ROOT);
  });
});

// ---------------------------------------------------------------------------
// AC-4: Workspaces are isolated per user.
// Two layers:
//   (a) path-level — two UUIDs produce non-overlapping workspace roots.
//   (b) resolver-level — isPathInWorkspace rejects an attempt from user A's
//       context to read user B's settings via ../ traversal.
// Offline — always runs.
// ---------------------------------------------------------------------------

describe("MU1 AC-4: per-user isolation", () => {
  test("two provisionings yield distinct workspace paths", async () => {
    const userA = randomUUID();
    const userB = randomUUID();
    const wsA = await provisionWorkspace(userA);
    const wsB = await provisionWorkspace(userB);
    provisionedWorkspaces.push(wsA, wsB);

    expect(wsA).not.toBe(wsB);
    expect(wsA.endsWith(userA)).toBe(true);
    expect(wsB.endsWith(userB)).toBe(true);
  });

  test("sandbox resolver rejects cross-workspace traversal", async () => {
    const userA = randomUUID();
    const userB = randomUUID();
    const wsA = await provisionWorkspace(userA);
    const wsB = await provisionWorkspace(userB);
    provisionedWorkspaces.push(wsA, wsB);

    // Simulate user A (scoped to wsA) trying to read user B's settings via
    // a relative-path traversal. The resolver must canonicalize and refuse.
    const traversal = join(wsA, "..", userB, ".claude", "settings.json");
    expect(isPathInWorkspace(traversal, wsA)).toBe(false);
  });

  test("sandbox resolver accepts within-workspace paths", async () => {
    const userA = randomUUID();
    const wsA = await provisionWorkspace(userA);
    provisionedWorkspaces.push(wsA);

    const settings = join(wsA, ".claude", "settings.json");
    expect(isPathInWorkspace(settings, wsA)).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// AC-1: Supabase handle_new_user trigger writes public.users.workspace_path.
// Requires MU1_INTEGRATION=1 + dev Supabase credentials via Doppler.
// ---------------------------------------------------------------------------

describe.skipIf(process.env.MU1_INTEGRATION !== "1")(
  "MU1 AC-1: handle_new_user trigger",
  () => {
    test("new auth.users row populates public.users with /workspaces/<uuid> path", async () => {
      const { createServiceClient } = await import("../lib/supabase/server");
      const client = createServiceClient();
      const email = `mu1-integration-${randomUUID()}@soleur-test.invalid`;
      assertSyntheticEmail(email);

      let userId: string | undefined;
      try {
        const { data: created, error: createErr } =
          await client.auth.admin.createUser({
            email,
            email_confirm: true,
            password: `mu1-${randomUUID()}`,
          });
        if (createErr || !created?.user) {
          throw new Error(
            `auth.admin.createUser failed: ${createErr?.message ?? "no user returned"}`,
          );
        }
        // Defense-in-depth: the allowlist passed on the email we requested;
        // re-assert the server-returned user has the same synthetic email
        // before we'll ever call deleteUser on its id.
        expect(created.user.email?.toLowerCase()).toBe(email.toLowerCase());
        userId = created.user.id;

        const { data: row, error: selectErr } = await client
          .from("users")
          .select("workspace_path")
          .eq("id", userId)
          .single();

        expect(selectErr).toBeNull();
        expect(row?.workspace_path).toBe(`/workspaces/${userId}`);
      } finally {
        if (userId) {
          assertSyntheticEmail(email);
          await client.auth.admin.deleteUser(userId);
        }
      }
    }, 30_000);
  },
);

// ---------------------------------------------------------------------------
// AC-2: provisionWorkspaceWithRepo clones the user's connected repo.
// Gated on MU1_FIXTURE_REPO_URL + MU1_FIXTURE_INSTALLATION_ID. Orthogonal to
// AC-1's MU1_INTEGRATION gate (AC-1 needs dev Supabase; AC-2 needs GitHub App
// creds + a public fixture repo). See #2605 and
// knowledge-base/engineering/ops/runbooks/mu1-signup-workspace-verification.md.
// ---------------------------------------------------------------------------

describe.skipIf(
  !process.env.MU1_FIXTURE_REPO_URL ||
    !process.env.MU1_FIXTURE_INSTALLATION_ID,
)("MU1 AC-2: provisionWorkspaceWithRepo clones fixture", () => {
  test("clones the fixture repo and overlays plugin symlink", async () => {
    const { provisionWorkspaceWithRepo } = await import("../server/workspace");
    const userId = randomUUID();
    const repoUrl = process.env.MU1_FIXTURE_REPO_URL!;
    const rawId = process.env.MU1_FIXTURE_INSTALLATION_ID ?? "";
    const installationId = Number(rawId);
    // Guard BEFORE calling generateInstallationToken — a malformed env var
    // would otherwise fail deep in the GitHub API with a cryptic
    // "Bad credentials". This assertion names the real problem.
    expect(
      Number.isFinite(installationId) &&
        installationId > 0 &&
        Number.isInteger(installationId),
    ).toBe(true);

    const ws = await provisionWorkspaceWithRepo(userId, repoUrl, installationId);
    provisionedWorkspaces.push(ws);

    // Fixture top-level files land in the workspace.
    expect(existsSync(join(ws, "README.md"))).toBe(true);
    expect(existsSync(join(ws, ".git"))).toBe(true);

    // Plugin symlink is overlaid post-clone (AC-3 contract).
    const symlinkPath = join(ws, "plugins", "soleur");
    expect(readlinkSync(symlinkPath)).toBe(PLUGIN_ROOT);
  }, 60_000);
});
