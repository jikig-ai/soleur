// `computeHeldFiles` / `readRecoveredKbSyncTips` against the real git binary (#12714: TW1, TW1-b's count half, TW4-a/b/c;
// rulings W1, W4, D6, D27, D29(1)/(8)). Synthesized fixtures only (cq-test-fixtures-synthesized-only). The isolated directory
// is the real creator's, so the count runs under the real hardened, token-free env.
//
// What is counted (W1): non-KB FILES from `diff --name-only --no-renames -z <T>...<head>` (three-dot: from the merge base), unioned
// with the same diff for every `refs/heads/soleur/recovered-kb-sync-*` tip, deduplicated, clamped to 0..10000. Files, not
// commits: a commit count stays stale after a squash merge (probe6 C2) and drops to 0 under pathspec history simplification
// (probe6 C3) while the work is still unmerged.
import { execFileSync } from "node:child_process";
import { mkdirSync, mkdtempSync, realpathSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";

// The count's own log lines (`kb-sync.held-files` with its closed nullCause, `tips_truncated`) are observed here; the
// git children run for real.
const { logSpy } = vi.hoisted(() => ({ logSpy: { info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() } }));
vi.mock("../server/logger", async (importOriginal) => ({
  ...(await importOriginal<typeof import("../server/logger")>()),
  createChildLogger: () => logSpy,
}));
import { gitFixtureEnv } from "../../../plugins/soleur/test/lib/git-fixture-env";
import { createIsolatedPushDir, type IsolatedPushDirHandle } from "../server/git-isolated-push-dir";
import {
  computeHeldFiles,
  HELD_FILES_MAX,
  RECOVERED_TIPS_MAX,
  readRecoveredKbSyncTips,
} from "../server/kb-sync-held";
import { HELD_FILES_RENDER_MAX } from "../lib/kb-sync-held-copy";

/** The `kb-sync.held-files` lines logged so far (one per computed or failed count). */
const heldLines = (): Array<Record<string, unknown>> =>
  [...logSpy.info.mock.calls, ...logSpy.warn.mock.calls]
    .map((c) => c[0] as Record<string, unknown>)
    .filter((o) => o?.op === "kb-sync.held-files");

const git = (cwd: string, ...args: string[]): string =>
  execFileSync("git", args, { cwd, stdio: "pipe", encoding: "utf8", env: gitFixtureEnv(cwd) }).trim();

const write = (path: string, body: string): void => {
  mkdirSync(dirname(path), { recursive: true });
  writeFileSync(path, body);
};

describe("kb-sync-held (real git)", () => {
  let root: string;
  let remote: string;
  let ws: string;
  let up: string;
  let T: string;
  const isos: IsolatedPushDirHandle[] = [];
  const saved: Record<string, string | undefined> = {};

  const iso = (): IsolatedPushDirHandle => {
    const h = createIsolatedPushDir(ws);
    isos.push(h);
    return h;
  };
  const head = (): string => git(ws, "rev-parse", "HEAD");
  const commitCode = (repo: string, file: string, body: string, msg: string): string => {
    write(join(repo, file), body);
    git(repo, "add", "-A");
    git(repo, "commit", "-q", "-m", msg);
    return git(repo, "rev-parse", "HEAD");
  };
  const recoveredRef = (name: string): string => join(ws, ".git", "refs", "heads", "soleur", name);

  beforeEach(() => {
    vi.clearAllMocks();
    for (const k of ["HOME", "TMPDIR"]) saved[k] = process.env[k];
    root = realpathSync(mkdtempSync(join(tmpdir(), "kb-held-")));
    mkdirSync(join(root, "home"));
    mkdirSync(join(root, "tmp"));
    process.env.HOME = join(root, "home");
    process.env.TMPDIR = join(root, "tmp");

    remote = join(root, "remote.git");
    mkdirSync(remote);
    git(remote, "init", "-q", "--bare", "-b", "main");

    // Upstream author clone: T = one code file and one KB file.
    up = join(root, "up");
    mkdirSync(up);
    git(up, "init", "-q", "-b", "main");
    write(join(up, "src", "app.ts"), "export const a = 1;\n");
    write(join(up, "knowledge-base", "notes.md"), "# notes\n");
    git(up, "add", "-A");
    git(up, "commit", "-q", "-m", "T");
    git(up, "remote", "add", "origin", remote);
    git(up, "push", "-q", "origin", "main");
    T = git(up, "rev-parse", "HEAD");

    ws = join(root, "ws");
    git(root, "clone", "-q", remote, ws);
  });

  afterEach(() => {
    for (const h of isos.splice(0)) h.dispose();
    for (const [k, v] of Object.entries(saved)) {
      if (v === undefined) delete process.env[k];
      else process.env[k] = v;
    }
    rmSync(root, { recursive: true, force: true });
  });

  test("TW1: a held code commit F1 and a KB commit K1 over T count 1 code file, 0 on recovered branches", async () => {
    commitCode(ws, "src/feature.ts", "export const f = 1;\n", "F1");
    commitCode(ws, "knowledge-base/notes.md", "# notes\nmore\n", "K1");
    expect(await computeHeldFiles({ isolated: iso(), base: T, head: head(), recovered: [] })).toEqual({ total: 1, onRecovered: 0 });
  });

  test("TW1: nothing held (HEAD = T, or KB-only commits) counts 0", async () => {
    expect(await computeHeldFiles({ isolated: iso(), base: T, head: head(), recovered: [] })).toEqual({ total: 0, onRecovered: 0 });
    commitCode(ws, "knowledge-base/notes.md", "# notes\nkb only\n", "K1");
    expect(await computeHeldFiles({ isolated: iso(), base: T, head: head(), recovered: [] })).toEqual({ total: 0, onRecovered: 0 });
  });

  test("TW1: after upstream squash-merges F1's change and the pull merges it, the count is 0 (not a stale commit count)", async () => {
    commitCode(ws, "src/feature.ts", "export const f = 1;\n", "F1");
    expect((await computeHeldFiles({ isolated: iso(), base: T, head: head(), recovered: [] }))?.total).toBe(1);
    // Upstream squash-merges the same content as a different commit S.
    const S = commitCode(up, "src/feature.ts", "export const f = 1;\n", "S (squash of F1)");
    git(up, "push", "-q", "origin", "main");
    git(ws, "fetch", "-q", "origin");
    git(ws, "merge", "-q", "--no-edit", "origin/main");
    expect(await computeHeldFiles({ isolated: iso(), base: S, head: head(), recovered: [] })).toEqual({ total: 0, onRecovered: 0 });
    // An unrelated upstream commit and a second merge (probe6 C3): still 0, never a negative or stale value.
    const U = commitCode(up, "src/other.ts", "export const o = 1;\n", "U");
    git(up, "push", "-q", "origin", "main");
    git(ws, "fetch", "-q", "origin");
    git(ws, "merge", "-q", "--no-edit", "origin/main");
    expect(await computeHeldFiles({ isolated: iso(), base: U, head: head(), recovered: [] })).toEqual({ total: 0, onRecovered: 0 });
  });

  test("TW1: an upstream code change not yet pulled is not counted (three-dot base, not a two-dot diff)", async () => {
    commitCode(ws, "src/feature.ts", "export const f = 1;\n", "F1");
    const U = commitCode(up, "src/upstream.ts", "export const u = 1;\n", "U");
    git(up, "push", "-q", "origin", "main");
    git(ws, "fetch", "-q", "origin"); // objects present, nothing merged
    expect(await computeHeldFiles({ isolated: iso(), base: U, head: head(), recovered: [] })).toEqual({ total: 1, onRecovered: 0 });
  });

  test("TW1: an approved push of HEAD to a new branch leaves the count unchanged (counted until merged into main)", async () => {
    commitCode(ws, "src/feature.ts", "export const f = 1;\n", "F1");
    git(ws, "push", "-q", "origin", "HEAD:refs/heads/feature/x");
    expect(await computeHeldFiles({ isolated: iso(), base: T, head: head(), recovered: [] })).toEqual({ total: 1, onRecovered: 0 });
  });

  test("renames count as files (--no-renames: a rename is a delete and an add, both non-KB)", async () => {
    git(ws, "mv", "src/app.ts", "src/renamed.ts");
    git(ws, "commit", "-q", "-m", "rename");
    expect((await computeHeldFiles({ isolated: iso(), base: T, head: head(), recovered: [] }))?.total).toBe(2);
  });

  test("no merge base (unrelated history) or a non-HEX40 revision gives null, never 0", async () => {
    const orphan = join(root, "orphan");
    mkdirSync(orphan);
    git(orphan, "init", "-q", "-b", "main");
    const O = commitCode(orphan, "x.ts", "x\n", "orphan");
    git(ws, "fetch", "-q", orphan, "main");
    expect(await computeHeldFiles({ isolated: iso(), base: O, head: head(), recovered: [] })).toBeNull();
    expect(await computeHeldFiles({ isolated: iso(), base: "HEAD", head: head(), recovered: [] })).toBeNull();
    expect(await computeHeldFiles({ isolated: iso(), base: T, head: "refs/heads/main", recovered: [] })).toBeNull();
    expect(await computeHeldFiles({ isolated: iso(), base: T, head: head(), recovered: ["not-a-sha"] })).toBeNull();
    // A HEX40 value that names no object is a git failure: null.
    expect(await computeHeldFiles({ isolated: iso(), base: "1".repeat(40), head: head(), recovered: [] })).toBeNull();
    // Each null names its closed cause (obs F6, D39(b)), in the order the five calls above ran.
    // A HEX40 value naming no object is an invalid revision too (git: "bad object").
    expect(heldLines().map((l) => l.nullCause)).toEqual(["no_merge_base", "invalid_rev", "invalid_rev", "invalid_rev", "invalid_rev"]);
    for (const l of heldLines()) expect(l.bucket).toBe("null");
  });

  test("a computed count logs one kb-sync.held-files line with its bucket and no nullCause", async () => {
    commitCode(ws, "src/feature.ts", "export const f = 1;\n", "F1");
    await computeHeldFiles({ isolated: iso(), base: T, head: head(), recovered: [] });
    expect(heldLines()).toHaveLength(1);
    expect(heldLines()[0]).toMatchObject({ bucket: "1-9", onRecoveredBucket: "0" });
    expect(heldLines()[0]).not.toHaveProperty("nullCause");
  });

  test("D38(5): an expired budget gives null with nullCause budget, never a partial count", async () => {
    commitCode(ws, "src/feature.ts", "export const f = 1;\n", "F1");
    expect(await computeHeldFiles({ isolated: iso(), base: T, head: head(), recovered: [] }, { budgetMs: 0 })).toBeNull();
    expect(heldLines()).toEqual([expect.objectContaining({ bucket: "null", nullCause: "budget" })]);
  });

  test("a value above the cap is clamped to HELD_FILES_MAX", async () => {
    // Exercise the clamp through the injectable cap seam rather than writing 10 001 files.
    for (let i = 0; i < 5; i++) write(join(ws, "src", `f${i}.ts`), `export const v = ${i};\n`);
    git(ws, "add", "-A");
    git(ws, "commit", "-q", "-m", "many");
    expect(await computeHeldFiles({ isolated: iso(), base: T, head: head(), recovered: [] }, { cap: 3 })).toEqual({ total: 3, onRecovered: 0 });
    // V9 / D39(e): one bound for the store, the migration's range check and the copy, so a stored value equal to it is
    // the clamp ("10000 or more"), never an exact count the copy could print as exact.
    expect(HELD_FILES_MAX).toBe(10_000);
    expect(HELD_FILES_MAX).toBe(HELD_FILES_RENDER_MAX);
  });

  describe("recovered kb-sync branches (W4)", () => {
    test("TW4-a: a planted legacy recovered tip carrying a non-KB file contributes its files (onRecovered > 0)", async () => {
      const R = commitCode(ws, "src/recovered.ts", "export const r = 1;\n", "R");
      git(ws, "branch", "soleur/recovered-kb-sync-1700000000000", R);
      git(ws, "reset", "-q", "--hard", T);
      const tips = readRecoveredKbSyncTips(ws);
      expect(tips).toEqual([R]);
      expect(await computeHeldFiles({ isolated: iso(), base: T, head: head(), recovered: tips! })).toEqual({ total: 1, onRecovered: 1 });
      // HEAD's own held file and the recovered one: union, deduplicated.
      commitCode(ws, "src/feature.ts", "export const f = 1;\n", "F1");
      commitCode(ws, "src/recovered.ts", "export const r = 2;\n", "F2 (same path as R)");
      expect(await computeHeldFiles({ isolated: iso(), base: T, head: head(), recovered: tips! })).toEqual({ total: 2, onRecovered: 1 });
    });

    test("TW4-a: a packed recovered ref is still counted; a loose ref overrides its packed value", async () => {
      const R = commitCode(ws, "src/recovered.ts", "export const r = 1;\n", "R");
      git(ws, "branch", "soleur/recovered-kb-sync-1700000000001", R);
      git(ws, "reset", "-q", "--hard", T);
      git(ws, "pack-refs", "--all");
      expect(readRecoveredKbSyncTips(ws)).toEqual([R]);
      expect(await computeHeldFiles({ isolated: iso(), base: T, head: head(), recovered: readRecoveredKbSyncTips(ws)! })).toEqual({
        total: 1,
        onRecovered: 1,
      });
      // A loose file for the same name wins over packed-refs (git's own precedence).
      write(recoveredRef("recovered-kb-sync-1700000000001"), `${T}\n`);
      expect(readRecoveredKbSyncTips(ws)).toEqual([T]);
    });

    test("TW4-a: a symlinked recovered ref, a symlinked refs/heads/soleur or a symlinked packed-refs gives null", () => {
      const R = commitCode(ws, "src/recovered.ts", "export const r = 1;\n", "R");
      const target = join(root, "planted-ref");
      write(target, `${R}\n`);
      mkdirSync(join(ws, ".git", "refs", "heads", "soleur"), { recursive: true });
      symlinkSync(target, recoveredRef("recovered-kb-sync-1"));
      expect(readRecoveredKbSyncTips(ws)).toBeNull();
      rmSync(recoveredRef("recovered-kb-sync-1"));

      rmSync(join(ws, ".git", "refs", "heads", "soleur"), { recursive: true, force: true });
      const planted = join(root, "planted-dir");
      mkdirSync(planted);
      write(join(planted, "recovered-kb-sync-2"), `${R}\n`);
      symlinkSync(planted, join(ws, ".git", "refs", "heads", "soleur"));
      expect(readRecoveredKbSyncTips(ws)).toBeNull();
      rmSync(join(ws, ".git", "refs", "heads", "soleur"));

      const packed = join(root, "planted-packed-refs");
      write(packed, `${R} refs/heads/soleur/recovered-kb-sync-3\n`);
      rmSync(join(ws, ".git", "packed-refs"), { force: true });
      symlinkSync(packed, join(ws, ".git", "packed-refs"));
      expect(readRecoveredKbSyncTips(ws)).toBeNull();
    });

    test("an oversized or non-HEX40 recovered ref file gives null; an oversized packed-refs gives null", () => {
      write(recoveredRef("recovered-kb-sync-big"), "a".repeat(65));
      expect(readRecoveredKbSyncTips(ws)).toBeNull();
      write(recoveredRef("recovered-kb-sync-big"), "ref: refs/heads/main\n");
      expect(readRecoveredKbSyncTips(ws)).toBeNull();
      rmSync(recoveredRef("recovered-kb-sync-big"));
      expect(readRecoveredKbSyncTips(ws)).toEqual([]);
      write(join(ws, ".git", "packed-refs"), `# pack-refs with: peeled\n${"x".repeat(1024 * 1024 + 1)}\n`);
      expect(readRecoveredKbSyncTips(ws)).toBeNull();
    });

    test("names outside the recovered prefix are ignored (soleur/kb-sync, other soleur/* branches, packed lines too)", () => {
      const R = commitCode(ws, "src/recovered.ts", "export const r = 1;\n", "R");
      git(ws, "branch", "soleur/kb-sync", R);
      git(ws, "branch", "soleur/other", R);
      git(ws, "branch", "recovered-kb-sync-1", R);
      expect(readRecoveredKbSyncTips(ws)).toEqual([]);
      git(ws, "pack-refs", "--all");
      expect(readRecoveredKbSyncTips(ws)).toEqual([]);
    });

    test(`at most ${RECOVERED_TIPS_MAX} set-aside tips are read (the first in sorted ref order), duplicates collapse`, () => {
      const shas: string[] = [];
      for (let i = 0; i < RECOVERED_TIPS_MAX + 5; i++) {
        shas.push(commitCode(ws, `src/r${i}.ts`, `export const r = ${i};\n`, `R${i}`));
        git(ws, "branch", `soleur/recovered-kb-sync-${1700000000000 + i}`, shas[i]);
      }
      const tips = readRecoveredKbSyncTips(ws)!;
      expect(tips).toHaveLength(RECOVERED_TIPS_MAX);
      expect(tips).toEqual(shas.slice(0, RECOVERED_TIPS_MAX));
      // Two names at one sha read as one tip.
      rmSync(join(ws, ".git", "refs", "heads", "soleur"), { recursive: true, force: true });
      rmSync(join(ws, ".git", "packed-refs"), { force: true });
      git(ws, "branch", "soleur/recovered-kb-sync-1", shas[0]);
      git(ws, "branch", "soleur/recovered-kb-sync-2", shas[0]);
      expect(readRecoveredKbSyncTips(ws)).toEqual([shas[0]]);
    });

    test("D39(c) (arch F3): a recovered tip whose work GitHub squash-merged is not counted; an unmerged one is", async () => {
      // Recovered branch R adds src/merged.ts; main squash-merges the same content as a NEW commit S, so R never becomes an
      // ancestor of the tip and the three-dot diff alone would count src/merged.ts forever.
      const R = commitCode(ws, "src/merged.ts", "export const m = 1;\n", "R");
      git(ws, "branch", "soleur/recovered-kb-sync-1700000000010", R);
      git(ws, "reset", "-q", "--hard", T);
      const S = commitCode(up, "src/merged.ts", "export const m = 1;\n", "S (squash of R)");
      git(up, "push", "-q", "origin", "main");
      git(ws, "fetch", "-q", "origin");
      git(ws, "merge", "-q", "--no-edit", "origin/main");
      expect(git(ws, "diff", "--name-only", `${S}...${R}`, "--", ".", ":(exclude)knowledge-base/")).toBe("src/merged.ts");
      expect(await computeHeldFiles({ isolated: iso(), base: S, head: head(), recovered: readRecoveredKbSyncTips(ws)! })).toEqual({
        total: 0,
        onRecovered: 0,
      });
      // An unmerged recovered tip (a file GitHub does not have) is still counted.
      const R2 = commitCode(ws, "src/unmerged.ts", "export const u = 1;\n", "R2");
      git(ws, "branch", "soleur/recovered-kb-sync-1700000000011", R2);
      git(ws, "reset", "-q", "--hard", S);
      expect(await computeHeldFiles({ isolated: iso(), base: S, head: head(), recovered: readRecoveredKbSyncTips(ws)! })).toEqual({
        total: 1,
        onRecovered: 1,
      });
    });

    test("D39(d): a soleur-store-tip-<12 hex> rescue branch is counted (loose and packed); other flat names are not", async () => {
      const P = commitCode(ws, "src/rescued.ts", "export const p = 1;\n", "P (store tip)");
      git(ws, "branch", `soleur-store-tip-${P.slice(0, 12)}`, P);
      git(ws, "branch", "soleur-store-tip-nothex", P);
      git(ws, "branch", `soleur-store-tip-${P.slice(0, 11)}`, P);
      git(ws, "reset", "-q", "--hard", T);
      expect(readRecoveredKbSyncTips(ws)).toEqual([P]);
      expect(await computeHeldFiles({ isolated: iso(), base: T, head: head(), recovered: readRecoveredKbSyncTips(ws)! })).toEqual({
        total: 1,
        onRecovered: 1,
      });
      git(ws, "pack-refs", "--all");
      expect(readRecoveredKbSyncTips(ws)).toEqual([P]);
    });

    test("D39(d): a symlinked or oversized store-tip ref gives null (same bounds as the recovered refs)", () => {
      const P = commitCode(ws, "src/rescued.ts", "export const p = 1;\n", "P");
      const leaf = join(ws, ".git", "refs", "heads", `soleur-store-tip-${P.slice(0, 12)}`);
      const target = join(root, "planted-store-ref");
      write(target, `${P}\n`);
      symlinkSync(target, leaf);
      expect(readRecoveredKbSyncTips(ws)).toBeNull();
      rmSync(leaf);
      write(leaf, "a".repeat(65));
      expect(readRecoveredKbSyncTips(ws)).toBeNull();
    });

    test("D39(d) (quality P3-5): 21 tips across both families: the first 20 in sorted ref order are counted, tips_truncated logged", async () => {
      const shas: string[] = [];
      // Independent tips (each one file over T), so the count shows exactly which tips were read.
      for (let i = 0; i < RECOVERED_TIPS_MAX; i++) {
        git(ws, "reset", "-q", "--hard", T);
        shas.push(commitCode(ws, `src/r${i}.ts`, `export const r = ${i};\n`, `R${i}`));
        git(ws, "branch", `soleur/recovered-kb-sync-${1700000000100 + i}`, shas[i]);
      }
      git(ws, "reset", "-q", "--hard", T);
      const P = commitCode(ws, "src/store.ts", "export const s = 1;\n", "P");
      git(ws, "branch", `soleur-store-tip-${P.slice(0, 12)}`, P);
      git(ws, "reset", "-q", "--hard", T);
      const tips = readRecoveredKbSyncTips(ws)!;
      // `refs/heads/soleur-store-tip-*` sorts before `refs/heads/soleur/` ('-' < '/'), so the newest recovered name drops.
      expect(tips).toEqual([P, ...shas.slice(0, RECOVERED_TIPS_MAX - 1)]);
      expect(logSpy.warn.mock.calls.filter((c) => (c[0] as { reason?: string })?.reason === "tips_truncated")).toHaveLength(1);
      expect((await computeHeldFiles({ isolated: iso(), base: T, head: head(), recovered: tips }))?.onRecovered).toBe(RECOVERED_TIPS_MAX);
    });

    test("no .git/refs/heads/soleur and no packed-refs reads as no tips ([]), not null", () => {
      expect(readRecoveredKbSyncTips(ws)).toEqual([]);
    });

    test("a symlinked .git gives null", () => {
      const other = join(root, "other");
      git(root, "clone", "-q", remote, other);
      const ws2 = join(root, "ws2");
      mkdirSync(ws2);
      symlinkSync(join(other, ".git"), join(ws2, ".git"));
      expect(readRecoveredKbSyncTips(ws2)).toBeNull();
    });

    test("TW4-b: after a D6 self-heal reset, the new recovered ref (content already upstream) contributes 0", async () => {
      // D6(c): the reset with branch-aside runs only when the local commits carry no non-KB content upstream lacks
      // (three-dot diff vs origin/D is empty). Model: a local KB-only commit, set aside, then reset to the upstream tip.
      const L = commitCode(ws, "knowledge-base/notes.md", "# notes\nlocal kb\n", "L (KB only)");
      const U = commitCode(up, "knowledge-base/other.md", "# other\n", "U (upstream KB)");
      git(up, "push", "-q", "origin", "main");
      git(ws, "fetch", "-q", "origin");
      git(ws, "branch", "soleur/recovered-kb-sync-1700000000002", L);
      git(ws, "reset", "-q", "--hard", "origin/main");
      const tips = readRecoveredKbSyncTips(ws)!;
      expect(tips).toEqual([L]);
      expect(await computeHeldFiles({ isolated: iso(), base: U, head: head(), recovered: tips })).toEqual({ total: 0, onRecovered: 0 });
    });

    test("TW4-c: after a D27 self-heal merge (held code kept on the branch), the count equals HEAD's non-KB files vs T", async () => {
      commitCode(ws, "src/feature.ts", "export const f = 1;\n", "F1 (held)");
      const U = commitCode(up, "knowledge-base/other.md", "# other\n", "U (upstream KB)");
      git(up, "push", "-q", "origin", "main");
      git(ws, "fetch", "-q", "origin");
      git(ws, "merge", "-q", "--no-edit", "origin/main");
      const expected = git(ws, "diff", "--name-only", "--no-renames", `${U}...HEAD`, "--", ".", ":(exclude)knowledge-base/")
        .split("\n")
        .filter(Boolean).length;
      expect(expected).toBe(1);
      expect(await computeHeldFiles({ isolated: iso(), base: U, head: head(), recovered: readRecoveredKbSyncTips(ws)! })).toEqual({
        total: expected,
        onRecovered: 0,
      });
    });
  });
});
