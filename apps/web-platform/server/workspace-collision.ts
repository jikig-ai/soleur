// ---------------------------------------------------------------------------
// Workspace collision precheck: would moving the workspace to `target` replace or remove an on-disk entry HEAD does not
// track (CTO ruling D15(a))?
//
// Extracted unchanged from server/workspace-sync.ts (review Phase 0) so the pull's writer can run the same check (D35).
// The git runner is injected: the self-heal passes its token-free local runner; the check itself spawns nothing.
// ---------------------------------------------------------------------------

import { lstat } from "node:fs/promises";

/** `diff --name-status -z` output as raw added and deleted path bytes (a filename is bytes, not UTF-8). */
function parseNameStatusZ(out: Buffer): { added: Buffer[]; deleted: Buffer[] } {
  const fields: Buffer[] = [];
  let start = 0;
  for (let i = 0; i < out.length; i++) {
    if (out[i] === 0) {
      fields.push(out.subarray(start, i));
      start = i + 1;
    }
  }
  if (start !== out.length || fields.length % 2 !== 0) throw new Error("untracked-collision precheck: malformed diff output");
  const added: Buffer[] = [];
  const deleted: Buffer[] = [];
  for (let i = 0; i < fields.length; i += 2) {
    const status = fields[i].toString("latin1");
    if (status === "A") added.push(fields[i + 1]);
    else if (status === "D") deleted.push(fields[i + 1]);
    else throw new Error("untracked-collision precheck: unexpected diff status");
  }
  return { added, deleted };
}

/** `lstat` without following a symlink; null when nothing is there (or a leading component is not a directory). */
async function lstatOrNull(path: Buffer): Promise<Awaited<ReturnType<typeof lstat>> | null> {
  try {
    return await lstat(path);
  } catch (err) {
    const code = (err as { code?: unknown }).code;
    if (code === "ENOENT" || code === "ENOTDIR") return null;
    throw err;
  }
}

const SLASH = 0x2f;

/** Every proper leading directory of `p` (`a`, `a/b` for `a/b/c`), as subarrays of `p`. */
function leadingDirs(p: Buffer): Buffer[] {
  const out: Buffer[] = [];
  for (let i = p.indexOf(SLASH); i > 0; i = p.indexOf(SLASH, i + 1)) out.push(p.subarray(0, i));
  return out;
}

/**
 * CTO ruling D15(a): true when the reset to `target` would replace or remove an on-disk entry that HEAD does not track.
 * The tracked tree is already clean (D6b), so the index equals HEAD and every entry the reset can touch is a path that
 * `diff --name-status -z --no-renames --diff-filter=AD HEAD <target>` lists (`--name-status` rather than `--name-only`
 * so one call tells an added path from a deleted one). Three shapes refuse:
 *  1. an existing entry (lstat, no symlink follow) at an added path, unless it is a tracked directory the target turns
 *     into a file, which is shape 3;
 *  2. an existing non-directory at a leading directory of an added path that is not itself a deleted tracked path;
 *  3. an untracked OR IGNORED entry under a tracked directory an added path turns into a file:
 *     `ls-files -z --others --directory -- :(literal)<p>/` with no `--exclude-standard`, so ignored files are listed
 *     too; `--directory` (D23) lists a wholly-untracked subdirectory as one entry instead of every file under it (an
 *     ignored build tree would otherwise overflow the runner's buffer), and still lists empty directories.
 * `reset --keep` refuses shapes 1-2 for untracked files by itself but overwrites an IGNORED file (measured, git 2.56),
 * which is why this precheck, not `--keep`, is the guard; a `--keep` refusal reaching the catch means a missed shape.
 * A path that is not valid UTF-8 cannot be passed as an argv pathspec, so shape 3 on such a path refuses (fail closed).
 * Leading-directory lstats are memoised per call (D23): added paths share prefixes, and an import of N files at depth d
 * would otherwise cost N x d sequential lstats inside a user's KB write.
 */
export async function hasUntrackedCollision(
  run: (argv: string[]) => Promise<Buffer>,
  workspacePath: string,
  target: string,
): Promise<boolean> {
  const listing = await run(["diff", "--name-status", "-z", "--no-renames", "--diff-filter=AD", "HEAD", target, "--"]);
  const { added, deleted } = parseNameStatusZ(Buffer.isBuffer(listing) ? listing : Buffer.from(String(listing)));
  if (added.length === 0) return false;
  const deletedPaths = new Set(deleted.map((p) => p.toString("latin1")));
  const deletedDirs = new Set(deleted.flatMap((p) => leadingDirs(p).map((d) => d.toString("latin1"))));
  const onDisk = (rel: Buffer): Buffer => Buffer.concat([Buffer.from(`${workspacePath}/`), rel]);
  const dirStats = new Map<string, Awaited<ReturnType<typeof lstatOrNull>>>();
  const lstatDir = async (dir: Buffer): Promise<Awaited<ReturnType<typeof lstatOrNull>>> => {
    const key = dir.toString("latin1");
    if (!dirStats.has(key)) dirStats.set(key, await lstatOrNull(onDisk(dir)));
    return dirStats.get(key) ?? null;
  };

  for (const p of added) {
    const at = await lstatOrNull(onDisk(p));
    if (at) {
      if (!(at.isDirectory() && deletedDirs.has(p.toString("latin1")))) return true; // shape 1
      const name = p.toString("utf8");
      if (!Buffer.from(name, "utf8").equals(p)) return true;
      const others = await run(["ls-files", "-z", "--others", "--directory", "--", `:(literal)${name}/`]);
      if (others.length > 0) return true; // shape 3
      continue;
    }
    for (const dir of leadingDirs(p)) {
      const lead = await lstatDir(dir);
      if (!lead) break;
      if (lead.isDirectory()) continue;
      if (deletedPaths.has(dir.toString("latin1"))) break; // a tracked file the reset removes first
      return true; // shape 2
    }
  }
  return false;
}
