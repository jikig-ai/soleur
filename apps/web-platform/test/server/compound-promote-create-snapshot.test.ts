// CodeQL js/file-system-race (alert 312) on `snapshotClone`: the snapshot opens each path once (O_NOFOLLOW) instead of
// lstat-then-read. PROPERTY: the snapshot value is unchanged for the three shapes a clone can hold -- a regular file
// (sha256 of its bytes), a symlink (`link:<target>`, never read through), and a path git lists that is gone ("deleted").
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";
import { createHash } from "node:crypto";
import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
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

const sha = (s: string): string => createHash("sha256").update(s).digest("hex");

let root: string;
beforeAll(() => {
  root = mkdtempSync(join(tmpdir(), "snapshot-clone-"));
  const git = gitFixture(root);
  git(["init", "-q"]);
  for (const f of ["tracked.txt", "pipe-target.txt", "dir-target.txt"]) writeFileSync(join(root, f), `${f}\n`);
  git(["add", "."]);
  git(["commit", "-q", "-m", "seed"]);
});
afterAll(() => rmSync(root, { recursive: true, force: true }));

describe("snapshotClone single-open reading", () => {
  it("hashes regular files, records a symlink by target without reading through it, and marks removed or non-regular paths deleted", async () => {
    writeFileSync(join(root, "plain.txt"), "hello\n");
    // The target is a real file with different bytes: reading THROUGH the link would produce its hash, not `link:...`.
    writeFileSync(join(root, "real.txt"), "other bytes\n");
    symlinkSync("real.txt", join(root, "alias.txt"));
    symlinkSync("missing-target", join(root, "dangling.txt"));
    rmSync(join(root, "tracked.txt"));
    // A tracked path replaced by a FIFO: a blocking open() would hang this test (the 10 s timeout below turns that into a red).
    rmSync(join(root, "pipe-target.txt"));
    execFileSync("mkfifo", [join(root, "pipe-target.txt")], { env: gitFixtureEnv(root) });
    // A tracked path replaced by a directory.
    rmSync(join(root, "dir-target.txt"));
    mkdirSync(join(root, "dir-target.txt"));
    writeFileSync(join(root, "dir-target.txt", "inner.txt"), "inner\n");

    const snap = await snapshotClone(root, gitFixtureEnv(root));
    expect(snap).not.toBeNull();
    expect(snap!.get("plain.txt")).toBe(sha("hello\n"));
    expect(snap!.get("real.txt")).toBe(sha("other bytes\n"));
    expect(snap!.get("alias.txt")).toBe("link:real.txt");
    expect(snap!.get("dangling.txt")).toBe("link:missing-target");
    expect(snap!.get("tracked.txt")).toBe("deleted");
    expect(snap!.get("pipe-target.txt")).toBe("deleted");
    expect(snap!.get("dir-target.txt")).toBe("deleted");
    expect(snap!.get("dir-target.txt/inner.txt")).toBe(sha("inner\n"));
  }, 10_000);
});
