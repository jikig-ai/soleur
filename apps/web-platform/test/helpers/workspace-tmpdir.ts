import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { randomUUID } from "node:crypto";

/**
 * Create a UUID-named workspace directory under a fresh temp parent.
 *
 * The share / KB resolvers (ADR-044) compute the on-disk workspace dir as
 * `<WORKSPACES_ROOT>/<workspace_id>` via `workspacePathForWorkspaceId`, whose
 * #5344 UUID-shape guard (CWE-22 defense-in-depth) now THROWS on a non-UUID id.
 * The `share-mocks` helper derives the fixture `workspace_id` from
 * `path.basename(workspacePath)`, so the workspace dir's basename MUST be a real
 * UUID — a bare `mkdtempSync` suffix (e.g. `shared-c4-Ab12Cd`) is rejected.
 *
 * Returns the UUID-named workspace path plus its parent (the value to assign to
 * `process.env.WORKSPACES_ROOT`). `path.dirname(workspacePath)` also equals
 * `workspacesRoot`, so existing `process.env.WORKSPACES_ROOT = path.dirname(...)`
 * call sites keep working unchanged.
 */
export function makeUuidWorkspaceTmpdir(prefix: string): {
  workspacePath: string;
  workspacesRoot: string;
  workspaceId: string;
} {
  const workspacesRoot = fs.mkdtempSync(path.join(os.tmpdir(), prefix));
  const workspaceId = randomUUID();
  const workspacePath = path.join(workspacesRoot, workspaceId);
  fs.mkdirSync(workspacePath, { recursive: true });
  return { workspacePath, workspacesRoot, workspaceId };
}
