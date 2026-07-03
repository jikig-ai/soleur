import { readdirSync, statSync } from "fs";
import { join } from "path";
import { sessions } from "./session-registry";
import { reportSilentFallback } from "./observability";

// Mirror of `getWorkspacesRoot` in workspace.ts. Inlined here so this module
// stays decoupled from workspace.ts's github-app / token-generation imports
// (see session-registry for the same decoupling rationale).
const WORKSPACES_ROOT = process.env.WORKSPACES_ROOT || "/workspaces";

export function getActiveSessionCount(): number {
  return sessions.size;
}

// Count host-local workspace directories under an explicitly-passed root.
// Root-parameterized so callers that resolve WORKSPACES_ROOT once (the
// readiness probe, #5966) can prove both their signals read the SAME root —
// getActiveWorkspaceCount below delegates here with the module-load const.
export function countWorkspaceDirsAt(root: string): number {
  try {
    return readdirSync(root)
      .filter((name) => !name.startsWith(".orphaned-"))
      // `.cron` is the isolated ephemeral cron-clone subdir (#4882) — a sibling
      // of the UUID workspace dirs, not a user workspace. Exclude it so it never
      // inflates the active-workspace count by one.
      .filter((name) => name !== ".cron")
      // `lost+found` is created by mkfs on a freshly-formatted ext4/xfs volume
      // and is a directory — without this exclusion a truly-empty (bare) volume
      // would false-report as populated when WORKSPACES_ROOT is the mount root
      // directly (the readiness "populated" signal, #5966). Prod mounts
      // /workspaces as a subdir of /mnt/data so lost+found is invisible there,
      // but the generic default invites the direct-mount case — exclude it
      // defensively.
      .filter((name) => name !== "lost+found")
      .filter((name) => {
        try {
          return statSync(join(root, name)).isDirectory();
        } catch {
          return false;
        }
      }).length;
  } catch (err) {
    // ENOENT on the configured root is "this env has no mounted volume yet"
    // (local dev, CI, fresh provisioning) — expected degraded state, don't
    // page on it. Any other error (permissions, I/O) IS a real silent
    // fallback and goes to Sentry per cq-silent-fallback-must-mirror-to-sentry.
    if ((err as NodeJS.ErrnoException)?.code !== "ENOENT") {
      reportSilentFallback(err, {
        feature: "resource-monitoring",
        // op string pinned for Sentry alert-grouping continuity — do NOT rename
        // to match countWorkspaceDirsAt. `extra.workspacesRoot` disambiguates
        // which caller (metrics vs readiness) triggered the error.
        op: "getActiveWorkspaceCount",
        extra: { workspacesRoot: root },
      });
    }
    return 0;
  }
}

export function getActiveWorkspaceCount(): number {
  return countWorkspaceDirsAt(WORKSPACES_ROOT);
}
