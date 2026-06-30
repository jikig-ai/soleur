import { describe, it, expect, beforeEach, afterEach } from "vitest";
import {
  mkdtemp,
  rm,
  mkdir,
  writeFile,
  symlink,
  chmod,
} from "node:fs/promises";
import { tmpdir } from "node:os";
import { join } from "node:path";

import {
  isValidGitWorkTree,
  isEmptyCorruptGitDir,
} from "@/server/git-worktree-validity";

// Safety-critical probes (deepen-plan F2): `isEmptyCorruptGitDir` is the ONLY
// authorization for the destructive re-clone `rm`. These tests pin that:
//   - a valid tree (HEAD + objects, incl. Start-Fresh) is VALID, never fingerprinted;
//   - a bare `mkdir .git` is INVALID and matches the empty-corrupt fingerprint;
//   - a populated-but-broken `.git` (HEAD present, objects missing — or vice
//     versa) is INVALID but does NOT match the fingerprint (honest-block, never rm);
//   - a `.git` FILE (gitdir pointer / linked worktree) is VALID, never rm'd;
//   - an absent `.git` is invalid + not-fingerprinted (the graft handles absence).

describe("git-worktree-validity", () => {
  let dir: string;
  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), "gitvalidity-"));
  });
  afterEach(async () => {
    await rm(dir, { recursive: true, force: true });
  });

  async function ws(name: string): Promise<string> {
    const p = join(dir, name);
    await mkdir(p, { recursive: true });
    return p;
  }

  it("valid tree (HEAD + objects) → valid, NOT empty-corrupt (Start-Fresh preserved)", async () => {
    const p = await ws("valid");
    await mkdir(join(p, ".git", "objects"), { recursive: true });
    await writeFile(join(p, ".git", "HEAD"), "ref: refs/heads/main\n");
    expect(isValidGitWorkTree(p)).toBe(true);
    expect(isEmptyCorruptGitDir(p)).toBe(false);
  });

  it("bare `mkdir .git` (no HEAD/objects) → INVALID and matches the empty-corrupt fingerprint", async () => {
    const p = await ws("bare");
    await mkdir(join(p, ".git"), { recursive: true });
    expect(isValidGitWorkTree(p)).toBe(false);
    expect(isEmptyCorruptGitDir(p)).toBe(true); // the ONLY rm-authorized shape
  });

  it("populated-but-broken: HEAD present, objects MISSING → INVALID but NOT empty-corrupt (honest-block, never rm)", async () => {
    const p = await ws("broken-head");
    await mkdir(join(p, ".git"), { recursive: true });
    await writeFile(join(p, ".git", "HEAD"), "ref: refs/heads/main\n");
    expect(isValidGitWorkTree(p)).toBe(false);
    expect(isEmptyCorruptGitDir(p)).toBe(false); // HEAD present → not the empty fingerprint
  });

  it("populated-but-broken: objects present, HEAD MISSING → INVALID but NOT empty-corrupt", async () => {
    const p = await ws("broken-objects");
    await mkdir(join(p, ".git", "objects"), { recursive: true });
    expect(isValidGitWorkTree(p)).toBe(false);
    expect(isEmptyCorruptGitDir(p)).toBe(false); // objects present → not the empty fingerprint
  });

  it("populated `.git`, HEAD/objects UNREADABLE (EACCES≠ENOENT) → NOT empty-corrupt (never rm'd)", async () => {
    if (process.getuid?.() === 0) return; // root bypasses mode bits
    const p = await ws("eacces");
    await mkdir(join(p, ".git", "objects"), { recursive: true });
    await writeFile(join(p, ".git", "HEAD"), "ref: refs/heads/main\n");
    await chmod(join(p, ".git"), 0o000); // lstat(HEAD) → EACCES, not ENOENT
    try {
      // Non-vacuity: lstatSync(HEAD/objects) throws EACCES (not ENOENT), so the
      // ENOENT-positive fingerprint is NOT matched → false. An `existsSync`-based
      // check would collapse EACCES→false→"absent" and WRONGLY classify this
      // populated repo as empty-corrupt, authorizing an `rm`.
      expect(isEmptyCorruptGitDir(p)).toBe(false);
    } finally {
      await chmod(join(p, ".git"), 0o755); // restore for afterEach cleanup
    }
  });

  it("`.git` FILE (gitdir pointer / linked worktree) → VALID, NOT empty-corrupt (never removable)", async () => {
    const p = await ws("gitdir-file");
    await writeFile(join(p, ".git"), "gitdir: /some/other/path/.git/worktrees/x\n");
    expect(isValidGitWorkTree(p)).toBe(true);
    expect(isEmptyCorruptGitDir(p)).toBe(false);
  });

  it("absent `.git` → invalid + NOT empty-corrupt (the graft handles true absence, not this probe)", async () => {
    const p = await ws("absent");
    expect(isValidGitWorkTree(p)).toBe(false);
    expect(isEmptyCorruptGitDir(p)).toBe(false);
  });

  it("`.git` symlink to a valid repo dir → treated by lstat as a non-dir/non-file link → not the empty fingerprint (never rm'd)", async () => {
    // lstat does NOT follow the link; a symlink is neither isFile nor isDirectory
    // here, so it is conservatively NOT classified empty-corrupt (never removed).
    const p = await ws("symlink");
    const real = join(dir, "realgit");
    await mkdir(join(real, "objects"), { recursive: true });
    await writeFile(join(real, "HEAD"), "ref: refs/heads/main\n");
    await symlink(real, join(p, ".git"));
    expect(isEmptyCorruptGitDir(p)).toBe(false); // a symlink is never the rm fingerprint
    expect(isValidGitWorkTree(p)).toBe(false); // a symlink is neither file nor dir → not valid
  });
});
