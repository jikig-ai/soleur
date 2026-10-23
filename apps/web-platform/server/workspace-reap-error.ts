// Dependency-light home of the reap failure shape (#8211), so callers that mock or avoid
// `server/workspace.ts` (account-delete, repo/disconnect) can still `instanceof` it and
// share the Sentry op literal.
import type { ReapRootLabel } from "./workspace-resolver";

/**
 * The `op` tag of the Art. 17 local working-tree erasure failure. Emitted by BOTH
 * account-delete (`feature: account-delete`) and repo/disconnect
 * (`feature: repo-disconnect`); `sentry_alert.art17_workspace_tree_erasure_incomplete`
 * pages on this op regardless of feature.
 */
export const WORKSPACE_TREE_ERASURE_OP = "workspace-tree-erasure";

/** Which leg of the reap failed. `resolver` = a tenant root could not be resolved. */
export type ReapFailureRoot = ReapRootLabel | "resolver";

/**
 * Why. `moved-aside`: the tree was only RENAMED to `<id>.orphaned-<ts>` (still on
 * disk, nothing under WORKTREE_ROOT ever sweeps it). `survived`: the path is still
 * there after the removal. `recreated`: it was gone, then reappeared (a straggling
 * writer). `timeout`: a removal child process was killed at its time limit. `error`:
 * a removal/stat call threw.
 */
export type ReapFailureKind = "moved-aside" | "survived" | "recreated" | "timeout" | "error";

export interface ReapFailure {
  root: ReapFailureRoot;
  kind: ReapFailureKind;
  code?: string;
  /** For `root: "resolver"`: which tenant root could not be resolved. */
  label?: ReapRootLabel;
}

/**
 * Thrown by `deleteWorkspace` after EVERY target was attempted. Carries path-free,
 * id-free summaries only (root LABEL, kind, errno code): the raw errors from
 * rm/unlink/lstat embed `<root>/<uuid>`, and this object is handed to Sentry by callers.
 */
export class WorkspaceReapError extends AggregateError {
  readonly failures: ReadonlyArray<ReapFailure>;
  constructor(failures: ReapFailure[], errors: Error[], total: number) {
    super(
      errors,
      `deleteWorkspace: ${failures.length} of ${total} reap targets could not be reaped`,
    );
    this.name = "WorkspaceReapError";
    this.failures = failures;
  }
}

/**
 * Thrown by a path that would CREATE `<root>/<id>` (provision, clone, ensure) while
 * `deleteWorkspace` is still reaping that id: the reap's `rm -rf` can run up to a minute with
 * the event loop free, and would delete the new tree. Retryable; carries no id.
 */
export class WorkspaceReapInProgressError extends Error {
  readonly code = "WORKSPACE_REAP_IN_PROGRESS";
  constructor() {
    super("Workspace is being deleted; retry shortly");
    this.name = "WorkspaceReapInProgressError";
  }
}
