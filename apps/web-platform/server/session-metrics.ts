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

export function getActiveWorkspaceCount(): number {
  try {
    return readdirSync(WORKSPACES_ROOT)
      .filter((name) => !name.startsWith(".orphaned-"))
      .filter((name) => {
        try {
          return statSync(join(WORKSPACES_ROOT, name)).isDirectory();
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
        op: "getActiveWorkspaceCount",
        extra: { workspacesRoot: WORKSPACES_ROOT },
      });
    }
    return 0;
  }
}
