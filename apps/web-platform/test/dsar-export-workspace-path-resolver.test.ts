import { describe, it, expect, beforeEach, afterEach } from "vitest";

// #5005 — DSAR export workspace-path convergence.
//
// `runExport` previously derived the workspace-files enumeration root from
// the subject's own `users.workspace_path` column. That column is stale/empty
// for any account provisioned after the ADR-044 `users → workspaces`
// relocation, so a post-relocation subject's DSAR silently omitted their
// workspace files — an incomplete Art. 15/20 right-of-access response.
//
// The fix resolves the path from the subject's workspace id directly via
// `resolveDsarWorkspacePath(subjectUserId)` → `workspacePathForWorkspaceId`.
// Crucially this is the N2 SOLO path (`workspace_id == user_id`), NOT the
// active-workspace resolver: a DSAR is per-subject, and a member's personal
// data lives in their solo workspace. Resolving the member's *active* (possibly
// shared) workspace would over-export the owner's files into the member's
// DSAR — a cross-tenant leak. The helper takes ONLY the subject id (no supabase
// client, no active claim), so over-export is structurally impossible.

import {
  resolveDsarWorkspacePath,
} from "../server/dsar-export";

const ORIGINAL_ROOT = process.env.WORKSPACES_ROOT;

describe("resolveDsarWorkspacePath (#5005)", () => {
  beforeEach(() => {
    process.env.WORKSPACES_ROOT = "/workspaces";
  });

  afterEach(() => {
    if (ORIGINAL_ROOT === undefined) delete process.env.WORKSPACES_ROOT;
    else process.env.WORKSPACES_ROOT = ORIGINAL_ROOT;
  });

  it("derives the export root id-keyed from the subject's workspace id (N2 solo), independent of any users-row column", () => {
    // The legacy `users.workspace_path` column is irrelevant — the path is a
    // pure function of the subject id. A stale/empty column cannot affect it.
    const subjectId = "11111111-1111-1111-1111-111111111111";
    expect(resolveDsarWorkspacePath(subjectId)).toBe(
      `/workspaces/${subjectId}`,
    );
  });

  it("resolves distinct subjects to distinct solo paths (no shared/active over-export)", () => {
    // A member subject gets THEIR solo path, never an active shared workspace
    // they happen to be viewing. The signature (subjectId only, no supabase)
    // makes resolving a sibling/active workspace impossible.
    const memberA = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
    const memberB = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";
    expect(resolveDsarWorkspacePath(memberA)).toBe(`/workspaces/${memberA}`);
    expect(resolveDsarWorkspacePath(memberB)).toBe(`/workspaces/${memberB}`);
    expect(resolveDsarWorkspacePath(memberA)).not.toBe(
      resolveDsarWorkspacePath(memberB),
    );
  });

  it("honors WORKSPACES_ROOT (ADR-038 bwrap mount), not a hard-coded prefix", () => {
    process.env.WORKSPACES_ROOT = "/mnt/data/workspaces";
    const subjectId = "22222222-2222-2222-2222-222222222222";
    expect(resolveDsarWorkspacePath(subjectId)).toBe(
      `/mnt/data/workspaces/${subjectId}`,
    );
  });
});
