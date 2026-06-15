/**
 * Regression: the Concierge document resolver must read the open KB document
 * from the caller's ACTIVE workspace — the same source the UI KB file tree
 * renders from (`resolveActiveWorkspaceKbRoot`) — NOT the legacy
 * `users.workspace_path` column.
 *
 * Agent-native parity bug (ADR-044 / #4543 class): pre-fix,
 * `fetchUserWorkspacePath` read `users.workspace_path` (the caller's SOLO
 * workspace, empty for an invited member or stale post-relocation), so the
 * Concierge replied "the document didn't come through" while the UI showed a
 * populated tree. This test seeds a member whose ACTIVE workspace differs from
 * their solo workspace, puts the document ONLY in the active workspace, and
 * asserts the resolver finds the body.
 *
 * RED on origin/main: the resolver reads `users.workspace_path` → the (empty)
 * solo dir → ENOENT → `{}` → assertion fails.
 * GREEN after the fix: the resolver computes the active-workspace path →
 * reads the body.
 *
 * Drives the resolver/dispatch boundary deterministically (no LLM): the
 * structural tenant-client mock returns BOTH the old (`users.workspace_path`)
 * and new (`user_session_state` + `workspace_members`) read shapes, so the
 * pass/fail signal isolates the workspace-source change, not a mock gap.
 */
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { mkdtempSync, rmSync, mkdirSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import path from "path";

// Structural tenant client implementing both the pre-fix `users` read and the
// post-fix `user_session_state` / `workspace_members` reads. `.from(table)`
// returns a recursive chain; the terminal `single`/`maybeSingle` resolve the
// table-specific row. Mutated per-test via `rowsByTable`.
const rowsByTable: Record<string, { data: unknown; error: unknown }> = {};

function makeTenantClient() {
  return {
    from(table: string) {
      const result = rowsByTable[table] ?? { data: null, error: null };
      const chain: Record<string, unknown> = {};
      chain.select = () => chain;
      chain.eq = () => chain;
      chain.maybeSingle = () => Promise.resolve(result);
      chain.single = () => Promise.resolve(result);
      return chain;
    },
  };
}

vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: async () => makeTenantClient(),
  RuntimeAuthError: class RuntimeAuthError extends Error {},
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
  warnSilentFallback: vi.fn(),
  mirrorWithDebounce: vi.fn(),
  __resetMirrorDebounceForTests: vi.fn(),
  MIRROR_DEBOUNCE_MS: 5 * 60 * 1000,
}));

// Avoid dragging the pdfjs lazy-import into a text-only test. The fixture is a
// `.md` file so these are never invoked; the mock just keeps the import cheap.
vi.mock("@/server/pdf-text-extract", async () => {
  const actual = await vi.importActual<typeof import("@/server/pdf-text-extract")>(
    "@/server/pdf-text-extract",
  );
  return { ...actual, extractPdfText: vi.fn(), extractPdfMetadata: vi.fn() };
});

import {
  resolveConciergeDocumentContext,
  _resetWorkspacePathCacheForTests,
} from "@/server/kb-document-resolver";

const MEMBER_ID = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa";
const ACTIVE_WS_ID = "44444444-4444-4444-8444-444444444444";

let workspacesRoot: string;
let prevWorkspacesRoot: string | undefined;

beforeEach(() => {
  workspacesRoot = mkdtempSync(path.join(tmpdir(), "ws-root-"));
  prevWorkspacesRoot = process.env.WORKSPACES_ROOT;
  process.env.WORKSPACES_ROOT = workspacesRoot;

  // Solo workspace = the member's own id (N2 invariant). Created EMPTY — the
  // document is NOT here. Pre-fix this is where the resolver looked.
  const soloDir = path.join(workspacesRoot, MEMBER_ID);
  mkdirSync(path.join(soloDir, "knowledge-base"), { recursive: true });

  // Active (shared) workspace — the document lives ONLY here. This is what the
  // UI file tree renders from.
  const activeDir = path.join(workspacesRoot, ACTIVE_WS_ID);
  mkdirSync(path.join(activeDir, "knowledge-base"), { recursive: true });
  writeFileSync(
    path.join(activeDir, "knowledge-base", "shared-postmortem.md"),
    "# Shared Postmortem\n\nMigration 059 made messages.workspace_id NOT NULL.\n",
  );

  rowsByTable.users = {
    // Pre-fix source: points at the EMPTY solo dir.
    data: { workspace_path: soloDir },
    error: null,
  };
  rowsByTable.user_session_state = {
    // Post-fix source: the member's active workspace is the shared one.
    data: { current_workspace_id: ACTIVE_WS_ID },
    error: null,
  };
  rowsByTable.workspace_members = {
    // Membership self-heal probe: the member IS a member of the active ws, so
    // resolution stays on the active workspace (does not fall back to solo).
    data: { user_id: MEMBER_ID },
    error: null,
  };

  _resetWorkspacePathCacheForTests();
});

afterEach(() => {
  rmSync(workspacesRoot, { recursive: true, force: true });
  if (prevWorkspacesRoot === undefined) delete process.env.WORKSPACES_ROOT;
  else process.env.WORKSPACES_ROOT = prevWorkspacesRoot;
  vi.clearAllMocks();
  for (const k of Object.keys(rowsByTable)) delete rowsByTable[k];
});

describe("Concierge open-document context — active-workspace parity", () => {
  it("resolves the open doc from the ACTIVE workspace, not the solo column", async () => {
    const out = await resolveConciergeDocumentContext({
      userId: MEMBER_ID,
      contextPath: "knowledge-base/shared-postmortem.md",
    });

    expect(out.documentKind).toBe("text");
    expect(out.artifactPath).toBe("knowledge-base/shared-postmortem.md");
    // The body proves the resolver read the ACTIVE workspace dir. Pre-fix it
    // read the empty solo dir and `documentContent` was undefined.
    expect(out.documentContent).toContain("Shared Postmortem");
    expect(out.documentContent).toContain("messages.workspace_id NOT NULL");
  });

  it("falls back to the SOLO workspace when the active claim is non-member", async () => {
    // Stale claim the caller is no longer a member of: the membership probe
    // returns no row → self-heal to solo (never the sibling). Put a solo doc to
    // prove the solo path is read (not the sibling's).
    rowsByTable.workspace_members = { data: null, error: null };
    const soloDir = path.join(workspacesRoot, MEMBER_ID);
    writeFileSync(
      path.join(soloDir, "knowledge-base", "solo-note.md"),
      "# Solo Note\n",
    );

    const out = await resolveConciergeDocumentContext({
      userId: MEMBER_ID,
      contextPath: "knowledge-base/solo-note.md",
    });

    expect(out.documentKind).toBe("text");
    expect(out.documentContent).toContain("Solo Note");
  });
});
