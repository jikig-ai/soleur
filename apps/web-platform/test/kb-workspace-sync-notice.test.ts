import { readFileSync } from "node:fs";
import path from "node:path";
import { describe, expect, test } from "vitest";
import {
  KB_WORKSPACE_SYNC_PENDING_NOTICE,
  kbWorkspaceSyncPendingNotice,
  kbWorkspaceSyncResyncPendingNotice,
} from "@/lib/kb-workspace-sync-notice";

// #12714 V6(5): the D16 KB notice copy is final. The four `lead` clauses and the resync notice stay as shipped; the
// `detail` gains the "this page may still show the files as they were" sentence; the "Interim copy" header is removed.

const DETAIL =
  "Your workspace has local changes that aren't on your repository's main branch yet, so it was not updated. Until it is, this page may still show the files as they were. You don't need to try again.";

describe("kb-workspace-sync-notice (V6(5))", () => {
  test("detail is the V6 string verbatim", () => {
    expect(KB_WORKSPACE_SYNC_PENDING_NOTICE.detail).toBe(DETAIL);
  });

  test("the four lead clauses are unchanged, and each notice is lead + detail", () => {
    expect(KB_WORKSPACE_SYNC_PENDING_NOTICE.lead).toEqual({
      upload: "Saved to GitHub.",
      delete: "Deleted on GitHub.",
      rename: "Renamed on GitHub.",
      save: "Saved to GitHub.",
    });
    expect(kbWorkspaceSyncPendingNotice("upload")).toBe(`Saved to GitHub. ${DETAIL}`);
    expect(kbWorkspaceSyncPendingNotice("delete")).toBe(`Deleted on GitHub. ${DETAIL}`);
    expect(kbWorkspaceSyncPendingNotice("rename")).toBe(`Renamed on GitHub. ${DETAIL}`);
    expect(kbWorkspaceSyncPendingNotice("save")).toBe(`Saved to GitHub. ${DETAIL}`);
  });

  test("the resync notice is final as shipped", () => {
    expect(kbWorkspaceSyncResyncPendingNotice()).toBe(
      "Saved to GitHub. Your workspace may not show the updated diagram yet, because it has local changes that aren't on your repository's main branch yet. You don't need to try again.",
    );
  });

  test("the header no longer calls the copy interim", () => {
    const src = readFileSync(path.join(__dirname, "../lib/kb-workspace-sync-notice.ts"), "utf8");
    expect(src).not.toMatch(/Interim copy/);
    expect(src).not.toMatch(/wireframe may refine it/);
  });
});
