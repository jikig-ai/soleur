// CodeQL js/file-system-race (alert 312) on `snapshotClone`: the snapshot opens each path once (O_NOFOLLOW) instead of
// lstat-then-read. PROPERTY: the snapshot value is unchanged for the three shapes a clone can hold -- a regular file
// (sha256 of its bytes), a symlink (`link:<target>`, never read through), and a path git lists that is gone ("deleted").
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";
import { createHash } from "node:crypto";
import { mkdtempSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});
vi.mock("@/server/observability", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/observability")>()),
  reportSilentFallback: vi.fn(),
}));
import { snapshotClone } from "@/server/compound-promote-create-gates";
import { gitFixture, gitFixtureEnv } from "../../../../plugins/soleur/test/lib/git-fixture-env";

let root: string;
beforeAll(() => {
  root = mkdtempSync(join(tmpdir(), "snapshot-clone-"));
  const git = gitFixture(root);
  git(["init", "-q"]);
  writeFileSync(join(root, "tracked.txt"), "tracked\n");
  git(["add", "tracked.txt"]);
  git(["commit", "-q", "-m", "seed"]);
});
afterAll(() => rmSync(root, { recursive: true, force: true }));

describe("snapshotClone single-open reading", () => {
  it("hashes a regular file, records a symlink by target without reading through it, and marks a removed path deleted", async () => {
    writeFileSync(join(root, "plain.txt"), "hello\n");
    // The target is a real file with different bytes: reading THROUGH the link would produce its hash, not `link:...`.
    writeFileSync(join(root, "real.txt"), "other bytes\n");
    symlinkSync("real.txt", join(root, "alias.txt"));
    rmSync(join(root, "tracked.txt"));

    const snap = await snapshotClone(root, gitFixtureEnv(root));
    expect(snap).not.toBeNull();
    expect(snap!.get("plain.txt")).toBe(createHash("sha256").update("hello\n").digest("hex"));
    expect(snap!.get("alias.txt")).toBe("link:real.txt");
    expect(snap!.get("tracked.txt")).toBe("deleted");
  });
});
