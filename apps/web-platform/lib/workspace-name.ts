// Shared workspace/organization name constants + validation.
//
// DEFAULT_ORG_NAME is the generic non-PII label that migration 091's
// handle_new_user trigger + backfill write for new/legacy organizations
// (was NULL in mig 053). It is peer-visible via orgs_select_for_members, so
// it MUST stay generic (never an email-derived value).
//
// IMPORTANT: this value is duplicated as a SQL literal in
// apps/web-platform/supabase/migrations/091_rename_organization_and_default_names.sql
// (SQL cannot import TS). If you change it here, change it there too — the
// invite modal's "is this still the default name?" heuristic compares against
// DEFAULT_ORG_NAME, so drift silently breaks the first-invite rename prompt.
export const DEFAULT_ORG_NAME = "My Workspace";

// Render-time fallback when an org name is somehow still NULL/empty. After
// migration 091 this is unreachable (defense-in-depth only).
export const UNTITLED_FALLBACK = "Untitled";

// Max length for a user-supplied workspace name, enforced at every layer
// (rename RPC, route, wrapper, component). The SQL RPC re-states `60` (it
// cannot import this constant) — keep them in sync.
export const WORKSPACE_NAME_MAX = 60;

export type WorkspaceNameValidation =
  | { ok: true; trimmed: string }
  | { ok: false };

/** Trim + bound a user-supplied workspace name (1..WORKSPACE_NAME_MAX chars). */
export function validateWorkspaceName(raw: string): WorkspaceNameValidation {
  const trimmed = raw.trim();
  if (trimmed.length === 0 || trimmed.length > WORKSPACE_NAME_MAX) {
    return { ok: false };
  }
  return { ok: true, trimmed };
}
