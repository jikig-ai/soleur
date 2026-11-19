// Module rows for server/workspace-collision.ts (review fix round 1, WP1, ruling D35): the collision precheck the pull
// writer and the self-heal share. The git runner is injected, so these rows use a fake runner over real on-disk entries
// (no git). The listing argv is the pinned shape the connected-repo guard accepts. Synthesized data only.
import { mkdirSync, mkdtempSync, realpathSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterAll, beforeAll, describe, expect, test } from "vitest";
import { assertConnectedRepoArgv } from "@/server/connected-repo-git";
import { hasUntrackedCollision } from "@/server/workspace-collision";

const T = "c".repeat(40);
let base = "";
beforeAll(() => {
  base = realpathSync(mkdtempSync(join(tmpdir(), "ws-collision-")));
});
afterAll(() => {
  if (base) rmSync(base, { recursive: true, force: true });
});

/** A fake runner: the name-status listing as `[status, path]` pairs, and the `ls-files --others` answer per pathspec. */
function runner(listing: Array<[string, string]>, others: Record<string, string> = {}) {
  const calls: string[][] = [];
  const run = async (argv: string[]): Promise<Buffer> => {
    calls.push(argv);
    if (argv[0] === "diff") return Buffer.from(listing.map(([s, p]) => `${s}\0${p}\0`).join(""));
    return Buffer.from(others[argv[argv.length - 1]] ?? "");
  };
  return { run, calls };
}

describe("hasUntrackedCollision (D15(a) shapes 1-3, shared by the pull writer, D35)", () => {
  test("the listing and the shape-3 read are the pinned connected-repo shapes", async () => {
    const ws = realpathSync(mkdtempSync(join(base, "ws-")));
    mkdirSync(join(ws, "lib"));
    const { run, calls } = runner([["A", "lib"], ["D", "lib/x.ts"]]);
    expect(await hasUntrackedCollision(run, ws, T)).toBe(false);
    expect(calls[0]).toEqual(["diff", "--name-status", "-z", "--no-renames", "--no-ext-diff", "--no-textconv", "--diff-filter=AD", "HEAD", T, "--"]);
    expect(calls[1]).toEqual(["ls-files", "-z", "--others", "--directory", "--", ":(literal)lib/"]);
    for (const argv of calls) expect(() => assertConnectedRepoArgv(argv)).not.toThrow();
  });

  test("shape 1: an on-disk entry (an ignored file) at an added path collides", async () => {
    const ws = realpathSync(mkdtempSync(join(base, "ws-")));
    mkdirSync(join(ws, "build"));
    writeFileSync(join(ws, "build", "out.txt"), "local\n");
    expect(await hasUntrackedCollision(runner([["A", "build/out.txt"]]).run, ws, T)).toBe(true);
  });

  test("shape 1 (the dir variant): an ignored directory where the target adds a file collides", async () => {
    const ws = realpathSync(mkdtempSync(join(base, "ws-")));
    mkdirSync(join(ws, "cache"));
    writeFileSync(join(ws, "cache", "data.bin"), "bytes\n");
    expect(await hasUntrackedCollision(runner([["A", "cache"]]).run, ws, T)).toBe(true);
  });

  test("shape 2: a non-directory at a leading directory of an added path collides", async () => {
    const ws = realpathSync(mkdtempSync(join(base, "ws-")));
    writeFileSync(join(ws, "docs"), "a file\n");
    expect(await hasUntrackedCollision(runner([["A", "docs/x.md"]]).run, ws, T)).toBe(true);
  });

  test("shape 3: an untracked entry under a tracked directory the target turns into a file collides", async () => {
    const ws = realpathSync(mkdtempSync(join(base, "ws-")));
    mkdirSync(join(ws, "lib"));
    const { run } = runner([["A", "lib"], ["D", "lib/x.ts"]], { ":(literal)lib/": "lib/local.ts\0" });
    expect(await hasUntrackedCollision(run, ws, T)).toBe(true);
  });

  test("nothing on disk at the added paths: no collision", async () => {
    const ws = realpathSync(mkdtempSync(join(base, "ws-")));
    expect(await hasUntrackedCollision(runner([["A", "src/new.ts"], ["D", "src/old.ts"]]).run, ws, T)).toBe(false);
  });
});
