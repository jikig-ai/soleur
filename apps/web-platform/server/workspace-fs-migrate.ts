import {
  existsSync,
  lstatSync,
  realpathSync,
  renameSync,
  symlinkSync,
} from "fs";
import { join } from "path";
import { createChildLogger } from "./logger";

// Filesystem migration: rename `/workspaces/<userId>` → `/workspaces/<workspaceId>`
// and leave a symlink at the legacy path so older bwrap mounts / cached
// `user.workspace_path` columns still resolve. Required for users who join
// or are migrated into a shared workspace whose id ≠ their own user_id.
//
// For solo users (N2 invariant: workspaces.id === user.id), this is a no-op:
// the legacy and canonical paths coincide, so neither rename nor symlink is
// needed. The function is idempotent — safe to call on every deploy.
//
// Symlink-safety (CWE-59): realpathSync BOTH sides before believing any
// path-string match. If the legacy path is a symlink that already resolves
// to a different target than the requested canonical, refuse (could be an
// operator-mistake or attacker-controlled). Dangling symlinks (realpath
// throws) also refuse. See learning
// `2026-03-20-symlink-escape-cwe59-workspace-sandbox`.

const log = createChildLogger("workspace-fs-migrate");

export interface MigrateUserWorkspaceParams {
  userId: string;
  workspaceId: string;
  /** Override `/workspaces` for tests. */
  root?: string;
}

function workspacesRoot(override?: string): string {
  return override || process.env.WORKSPACES_ROOT || "/workspaces";
}

/**
 * Idempotently migrate a single user's on-disk workspace from the legacy
 * userId-keyed path to the canonical workspaceId-keyed path. See module
 * docstring for invariants.
 *
 * Steps:
 *   1. Solo case (userId === workspaceId): return immediately.
 *   2. Legacy path absent: nothing to migrate, return.
 *   3. Legacy path is a symlink: realpath both sides; if it already points
 *      to the canonical path, return (idempotent). If it points elsewhere
 *      (or is dangling), throw.
 *   4. Legacy path is a real directory: rename → canonical, then create the
 *      legacy symlink.
 */
export function migrateUserWorkspace(params: MigrateUserWorkspaceParams): void {
  const { userId, workspaceId, root: rootOverride } = params;
  const root = workspacesRoot(rootOverride);
  const legacyPath = join(root, userId);
  const canonicalPath = join(root, workspaceId);

  // 1. Solo case — paths coincide, nothing to do.
  if (userId === workspaceId) {
    return;
  }

  // 2. No legacy directory exists. User has not yet provisioned a workspace
  //    on disk (e.g., signed up but never visited the dashboard). Nothing
  //    to migrate; the next provisioning call will create the canonical
  //    directory directly.
  if (!existsSync(legacyPath)) {
    // existsSync returns false for dangling symlinks too. Catch that via
    // lstatSync — if the legacy path is a dangling symlink, refuse.
    try {
      const st = lstatSync(legacyPath);
      if (st.isSymbolicLink()) {
        // Symlink exists but its target does not — dangling. Refuse.
        throw new Error(
          `legacy path ${legacyPath} is a dangling symlink; refusing to migrate (CWE-59)`,
        );
      }
    } catch (err) {
      if ((err as NodeJS.ErrnoException).code === "ENOENT") {
        return;
      }
      throw err;
    }
    return;
  }

  // 3. Legacy path exists. Inspect without following symlinks.
  const legacyStat = lstatSync(legacyPath);

  if (legacyStat.isSymbolicLink()) {
    // Resolve both sides to canonical real paths. Mismatch (or realpath
    // throwing for a broken target) means we cannot safely complete the
    // migration without overwriting potentially good data — refuse.
    let legacyReal: string;
    let canonicalReal: string;
    try {
      legacyReal = realpathSync(legacyPath);
    } catch (err) {
      throw new Error(
        `legacy symlink at ${legacyPath} has unresolvable target (dangling or permission-denied): ${(err as Error).message}`,
      );
    }
    try {
      canonicalReal = realpathSync(canonicalPath);
    } catch {
      // Canonical doesn't exist yet but symlink already points elsewhere —
      // operator state is inconsistent. Refuse.
      throw new Error(
        `legacy symlink at ${legacyPath} resolves to ${legacyReal} but canonical ${canonicalPath} does not exist; refusing to overwrite (CWE-59)`,
      );
    }
    if (legacyReal !== canonicalReal) {
      throw new Error(
        `legacy symlink at ${legacyPath} resolves to ${legacyReal}, not ${canonicalReal}; refusing to migrate (CWE-59 — possible attacker-controlled target)`,
      );
    }
    // Symlink already correct — idempotent re-run. Done.
    return;
  }

  // Legacy is a real directory.
  if (!legacyStat.isDirectory()) {
    throw new Error(
      `legacy path ${legacyPath} is neither a directory nor a symlink (mode=${legacyStat.mode}); refusing to migrate`,
    );
  }

  // 4. Rename legacy → canonical. If canonical already exists, refuse —
  //    two workspace directories cannot exist for the same workspace_id.
  if (existsSync(canonicalPath)) {
    throw new Error(
      `both legacy ${legacyPath} and canonical ${canonicalPath} exist; manual reconciliation required`,
    );
  }
  renameSync(legacyPath, canonicalPath);

  // Create legacy symlink → canonical. After symlinkSync, lstatSync at the
  // legacy path returns isSymbolicLink()=true and realpathSync resolves to
  // the canonical path — the per-test assertion contract.
  symlinkSync(canonicalPath, legacyPath);

  log.info(
    { userId, workspaceId, legacyPath, canonicalPath },
    "Migrated workspace directory",
  );
}

export interface UserWorkspacePair {
  userId: string;
  workspaceId: string;
}

/**
 * Iterate `migrateUserWorkspace` across every (user_id, workspace_id) row in
 * `workspace_members`. Designed for one-shot post-deploy invocation; the
 * runnable wrapper at `scripts/run-workspace-fs-migrate.mjs` queries Postgres
 * directly and feeds the rows in.
 *
 * Per-row errors are logged and collected; the function does not abort the
 * batch on a single failure (one bad symlink should not block migrating the
 * rest of the fleet). Returns `{migrated, skipped, failed}` counts so the
 * deploy runner can mirror them to Sentry / its log surface.
 *
 * Idempotent — see `migrateUserWorkspace` invariants. For all rows where
 * user_id === workspace_id (solo users, today's entire population), this
 * is a zero-op pass.
 */
export function migrateAllUserWorkspaces(
  pairs: Iterable<UserWorkspacePair>,
  root?: string,
): { migrated: number; skipped: number; failed: number } {
  let migrated = 0;
  let skipped = 0;
  let failed = 0;

  for (const { userId, workspaceId } of pairs) {
    if (userId === workspaceId) {
      skipped++;
      continue;
    }
    try {
      migrateUserWorkspace({ userId, workspaceId, root });
      migrated++;
    } catch (err) {
      failed++;
      log.error(
        { userId, workspaceId, err: (err as Error).message },
        "migrateUserWorkspace failed; continuing batch",
      );
    }
  }

  return { migrated, skipped, failed };
}
