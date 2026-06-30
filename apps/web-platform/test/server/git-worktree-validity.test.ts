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
  probeGitWorktreeShape,
  isReadyGitWorkTree,
  isStrandingFilePointer,
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

  // #5733 — structural shape classification for the dispatch readiness gate +
  // observability. A `.git` FILE pointer is the strand precondition: it passes
  // isValidGitWorkTree (lstat) but the agent's in-bwrap `git rev-parse` fails,
  // especially when the gitdir target is under /workspaces (sandbox denyRead).
  describe("probeGitWorktreeShape (#5733)", () => {
    it("dir with HEAD+objects → dir-valid", async () => {
      const p = await ws("shape-valid");
      await mkdir(join(p, ".git", "objects"), { recursive: true });
      await writeFile(join(p, ".git", "HEAD"), "ref: refs/heads/main\n");
      expect(probeGitWorktreeShape(p)).toEqual({ kind: "dir-valid" });
    });

    it("absent `.git` → absent", async () => {
      const p = await ws("shape-absent");
      expect(probeGitWorktreeShape(p)).toEqual({ kind: "absent" });
    });

    it("bare `mkdir .git` (no HEAD/objects) → dir-invalid", async () => {
      const p = await ws("shape-bare");
      await mkdir(join(p, ".git"), { recursive: true });
      expect(probeGitWorktreeShape(p)).toEqual({ kind: "dir-invalid" });
    });

    it("`.git` FILE whose gitdir target ESCAPES the workspace (under /workspaces) → file-pointer, escapes=true (the strand)", async () => {
      const p = await ws("shape-escape");
      await writeFile(
        join(p, ".git"),
        "gitdir: /workspaces/other/.git/worktrees/x\n",
      );
      const shape = probeGitWorktreeShape(p);
      expect(shape.kind).toBe("file-pointer");
      expect(shape.gitdirTarget).toBe("/workspaces/other/.git/worktrees/x");
      expect(shape.gitdirEscapesWorkspace).toBe(true);
    });

    it("`.git` FILE whose gitdir target stays INSIDE the workspace → file-pointer, escapes=false", async () => {
      const p = await ws("shape-inside");
      await writeFile(join(p, ".git"), "gitdir: ./.git-real\n");
      const shape = probeGitWorktreeShape(p);
      expect(shape.kind).toBe("file-pointer");
      expect(shape.gitdirEscapesWorkspace).toBe(false);
    });

    it("`.git` SYMLINK → other (O_NOFOLLOW does not follow it; never a file-pointer)", async () => {
      // Pins the no-follow semantics the TOCTOU-safe fd open relies on: a
      // symlink `.git` must NOT be read-through and classified file-pointer.
      const p = await ws("shape-symlink");
      const real = join(dir, "shape-real-git");
      await mkdir(join(real, "objects"), { recursive: true });
      await writeFile(join(real, "HEAD"), "ref: refs/heads/main\n");
      await symlink(real, join(p, ".git"));
      expect(probeGitWorktreeShape(p).kind).toBe("other");
    });
  });

  // #5733 — readiness-grade validity: a `.git` FILE pointer is lstat-VALID but
  // NOT ready (it strands the agent's in-bwrap rev-parse) → must route to heal.
  describe("isReadyGitWorkTree (#5733)", () => {
    it("dir with HEAD+objects → ready (true)", async () => {
      const p = await ws("ready-valid");
      await mkdir(join(p, ".git", "objects"), { recursive: true });
      await writeFile(join(p, ".git", "HEAD"), "ref: refs/heads/main\n");
      expect(isValidGitWorkTree(p)).toBe(true);
      expect(isReadyGitWorkTree(p)).toBe(true);
    });

    it("ESCAPING `.git` FILE pointer → lstat-VALID but NOT ready (false) — routes to re-clone", async () => {
      const p = await ws("ready-pointer-escape");
      await writeFile(join(p, ".git"), "gitdir: /workspaces/other/.git/worktrees/x\n");
      expect(isValidGitWorkTree(p)).toBe(true); // the lstat trap
      expect(isReadyGitWorkTree(p)).toBe(false); // escaping → readiness rejects it
    });

    it("NON-escaping in-workspace `.git` FILE pointer → READY (true) — readable in-sandbox, left untouched", async () => {
      const p = await ws("ready-pointer-inside");
      await writeFile(join(p, ".git"), "gitdir: ./.git-real\n");
      expect(isValidGitWorkTree(p)).toBe(true);
      expect(isReadyGitWorkTree(p)).toBe(true); // non-escaping → ready, NOT healed
    });

    it("absent `.git` → not ready (false)", async () => {
      const p = await ws("ready-absent");
      expect(isReadyGitWorkTree(p)).toBe(false);
    });
  });

  // #5733 — the destructive-heal predicate: ONLY an escaping/unclassifiable
  // pointer strands (and is re-cloned); a non-escaping pointer is left untouched.
  describe("isStrandingFilePointer (#5733)", () => {
    it("escaping pointer → stranding (true)", () => {
      expect(
        isStrandingFilePointer({ kind: "file-pointer", gitdirEscapesWorkspace: true }),
      ).toBe(true);
    });
    it("unreadable/unclassifiable pointer body (escapes undefined) → stranding (true)", () => {
      expect(isStrandingFilePointer({ kind: "file-pointer" })).toBe(true);
    });
    it("non-escaping in-workspace pointer → NOT stranding (false)", () => {
      expect(
        isStrandingFilePointer({ kind: "file-pointer", gitdirEscapesWorkspace: false }),
      ).toBe(false);
    });
    it("a valid dir / absent / dir-invalid is never a stranding pointer", () => {
      expect(isStrandingFilePointer({ kind: "dir-valid" })).toBe(false);
      expect(isStrandingFilePointer({ kind: "absent" })).toBe(false);
      expect(isStrandingFilePointer({ kind: "dir-invalid" })).toBe(false);
    });
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
