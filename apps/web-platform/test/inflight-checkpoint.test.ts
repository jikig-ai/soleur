// RED→GREEN for #5275 — in-flight work durability via ref-based worktree
// checkpoint + gated restore. Deterministic: asserts on git ref state +
// restored file bytes, never on agent prose (2026-04-19 learning).
//
// Fixtures are SYNTHESIZED temp git repos (cq-test-fixtures-synthesized-only) —
// no captured-real workspace state.
import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { mkdtemp, rm, writeFile, mkdir } from "node:fs/promises";
import { existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { promisify } from "node:util";
import { execFile } from "node:child_process";

// Observability is mocked so we can assert op-tagged mirrors (AC6, AC3) without
// reaching Sentry. The helper must mirror failures here, never throw.
vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
}));
import { reportSilentFallback } from "@/server/observability";

import {
  checkpointInflightWork,
  restoreInflightCheckpoint,
  checkpointRefName,
} from "@/server/inflight-checkpoint";

const execFileP = promisify(execFile);

// Deterministic, host-config-isolated git env. Identity is supplied via env so
// `commit`/`commit-tree` work even with global/system config nulled.
const GIT_ENV: NodeJS.ProcessEnv = {
  ...process.env,
  GIT_CONFIG_GLOBAL: "/dev/null",
  GIT_CONFIG_SYSTEM: "/dev/null",
  GIT_CONFIG_NOSYSTEM: "1",
  GIT_AUTHOR_NAME: "Test",
  GIT_AUTHOR_EMAIL: "test@example.com",
  GIT_COMMITTER_NAME: "Test",
  GIT_COMMITTER_EMAIL: "test@example.com",
};

async function git(cwd: string, ...args: string[]): Promise<string> {
  const { stdout } = await execFileP("git", args, { cwd, env: GIT_ENV });
  return stdout;
}

/** Synthesized workspace: a git repo with one committed base file (a clone
 *  always has a HEAD commit — verified at clone time). */
async function makeRepo(): Promise<string> {
  const repo = await mkdtemp(join(tmpdir(), "inflight-ckpt-"));
  await git(repo, "init", "-b", "main");
  await writeFile(join(repo, "base.txt"), "base\n");
  await git(repo, "add", "base.txt");
  await git(repo, "commit", "-m", "base");
  return repo;
}

async function refExists(repo: string, conversationId: string): Promise<boolean> {
  try {
    await git(repo, "rev-parse", "--verify", "--quiet", checkpointRefName(conversationId));
    return true;
  } catch {
    return false;
  }
}

async function headSha(repo: string): Promise<string> {
  return (await git(repo, "rev-parse", "HEAD")).trim();
}

async function porcelain(repo: string): Promise<string> {
  return (await git(repo, "status", "--porcelain")).trim();
}

const repos: string[] = [];
async function newRepo(): Promise<string> {
  const r = await makeRepo();
  repos.push(r);
  return r;
}

beforeEach(() => {
  vi.mocked(reportSilentFallback).mockClear();
});

afterEach(async () => {
  await Promise.all(repos.splice(0).map((r) => rm(r, { recursive: true, force: true })));
});

describe("checkpointRefName", () => {
  it("derives a deterministic refs/checkpoints/<id> name", () => {
    expect(checkpointRefName("conv-1")).toBe("refs/checkpoints/conv-1");
  });
});

describe("RED-A: checkpoint survives grace-abort", () => {
  it("snapshots uncommitted CODE + KB changes to a ref without touching HEAD/index/worktree", async () => {
    const repo = await newRepo();
    const base = await headSha(repo);

    // In-flight work: an uncommitted code edit (the actual point of the
    // feature — not just knowledge-base/**) and a KB file.
    await writeFile(join(repo, "feature.ts"), "export const inFlight = true;\n");
    await mkdir(join(repo, "knowledge-base"), { recursive: true });
    await writeFile(join(repo, "knowledge-base", "notes.md"), "in-flight notes\n");

    expect(await refExists(repo, "conv-A")).toBe(false);

    await checkpointInflightWork(repo, "conv-A", "user-A");

    // Ref exists and its tree carries BOTH uncommitted files' content.
    expect(await refExists(repo, "conv-A")).toBe(true);
    expect(await git(repo, "show", "refs/checkpoints/conv-A:feature.ts")).toBe(
      "export const inFlight = true;\n",
    );
    expect(
      await git(repo, "show", "refs/checkpoints/conv-A:knowledge-base/notes.md"),
    ).toBe("in-flight notes\n");

    // Real index untouched (temp-index snapshot): nothing staged.
    expect((await git(repo, "diff", "--cached", "--name-only")).trim()).toBe("");
    // HEAD unmoved (no WIP commit on the branch).
    expect(await headSha(repo)).toBe(base);
    // Working tree still dirty — checkpoint is non-destructive.
    expect(existsSync(join(repo, "feature.ts"))).toBe(true);
    expect(await porcelain(repo)).not.toBe("");
  });
});

describe("RED-B: safe restore on resume (clean tree, no sibling)", () => {
  it("materializes prior uncommitted work, leaves index unstaged, and consumes the ref", async () => {
    const repo = await newRepo();
    await writeFile(join(repo, "feature.ts"), "export const inFlight = true;\n");
    await checkpointInflightWork(repo, "conv-B", "user-B");

    // Simulate the resume scenario: the in-flight file is gone and the tree is
    // clean (e.g. a fresh reclone / a turn that never re-attached the bytes).
    await rm(join(repo, "feature.ts"));
    expect(await porcelain(repo)).toBe("");

    const result = await restoreInflightCheckpoint(repo, "conv-B", {
      siblingSlotActive: false,
    });

    expect(result.restored).toBe(true);
    // File materialized back with its exact bytes.
    expect(await git(repo, "show", "HEAD:base.txt")).toBe("base\n"); // sanity
    expect(existsSync(join(repo, "feature.ts"))).toBe(true);
    expect((await git(repo, "diff", "--cached", "--name-only")).trim()).toBe("");
    // Ref consumed — a second resume must not re-restore.
    expect(await refExists(repo, "conv-B")).toBe(false);
  });

  it("no-checkpoint is a benign no-op (no message)", async () => {
    const repo = await newRepo();
    const result = await restoreInflightCheckpoint(repo, "conv-none", {
      siblingSlotActive: false,
    });
    expect(result.restored).toBe(false);
    expect(result.reason).toBe("no-checkpoint");
    expect(reportSilentFallback).not.toHaveBeenCalled();
  });
});

describe("RED-C: refuse-and-report (unsafe), no clobber", () => {
  it("refuses on a DIRTY tree — newer content intact, ref retained, op mirrored", async () => {
    const repo = await newRepo();
    await writeFile(join(repo, "feature.ts"), "export const inFlight = true;\n");
    await checkpointInflightWork(repo, "conv-C", "user-C");

    // Newer work present at resume time (dirty tree).
    await writeFile(join(repo, "feature.ts"), "export const NEWER = 42;\n");

    const result = await restoreInflightCheckpoint(repo, "conv-C", {
      siblingSlotActive: false,
    });

    expect(result.restored).toBe(false);
    expect(result.reason).toBe("dirty");
    // The newer content was NOT overwritten by the checkpoint.
    expect(await git(repo, "show", `${await headSha(repo)}:base.txt`)).toBe("base\n");
    const onDisk = await execFileP("cat", [join(repo, "feature.ts")]);
    expect(onDisk.stdout).toBe("export const NEWER = 42;\n");
    // Ref retained (not consumed) so the work is still recoverable.
    expect(await refExists(repo, "conv-C")).toBe(true);
    // Honest signal mirrored with the triage op. The refuse path passes `null`
    // as the err (it is not an error condition) — `expect.anything()` would
    // reject null, so match the options arg directly.
    expect(reportSilentFallback).toHaveBeenCalledWith(
      null,
      expect.objectContaining({
        op: "restore-refused",
        extra: expect.objectContaining({ reason: "dirty" }),
      }),
    );
  });

  it("refuses when a sibling slot is active (team workspace), even on a clean tree", async () => {
    const repo = await newRepo();
    await writeFile(join(repo, "feature.ts"), "export const inFlight = true;\n");
    await checkpointInflightWork(repo, "conv-D", "user-D");
    await rm(join(repo, "feature.ts"));
    expect(await porcelain(repo)).toBe("");

    const result = await restoreInflightCheckpoint(repo, "conv-D", {
      siblingSlotActive: true,
    });

    expect(result.restored).toBe(false);
    expect(result.reason).toBe("sibling-active");
    expect(existsSync(join(repo, "feature.ts"))).toBe(false); // not restored
    expect(await refExists(repo, "conv-D")).toBe(true); // retained
  });
});

describe("RED-D: refuse on a MOVED HEAD (stale base), no clobber of newer commits", () => {
  it("refuses when HEAD advanced past the checkpoint's parent (e.g. a pull landed)", async () => {
    const repo = await newRepo();
    await writeFile(join(repo, "shared.txt"), "inflight-edit\n");
    await checkpointInflightWork(repo, "conv-HEAD", "user-H");

    // Simulate a pull/commit advancing HEAD between checkpoint and resume:
    // shared.txt is now committed with NEWER content, the tree is clean, but
    // HEAD != the checkpoint's parent.
    await rm(join(repo, "shared.txt"));
    await writeFile(join(repo, "shared.txt"), "v2-NEWER-COMMITTED\n");
    await git(repo, "add", "shared.txt");
    await git(repo, "commit", "-m", "newer work");
    expect(await porcelain(repo)).toBe("");

    const result = await restoreInflightCheckpoint(repo, "conv-HEAD", {
      siblingSlotActive: false,
    });

    expect(result.restored).toBe(false);
    expect(result.reason).toBe("stale-base");
    // The newer committed content was NOT reverted by the stale snapshot.
    const onDisk = await execFileP("cat", [join(repo, "shared.txt")]);
    expect(onDisk.stdout).toBe("v2-NEWER-COMMITTED\n");
    // Ref retained (recoverable).
    expect(await refExists(repo, "conv-HEAD")).toBe(true);
    expect(reportSilentFallback).toHaveBeenCalledWith(
      null,
      expect.objectContaining({
        op: "restore-refused",
        extra: expect.objectContaining({ reason: "stale-base" }),
      }),
    );
  });
});

describe("RED-E: in-flight DELETIONS are re-applied on restore (not resurrected)", () => {
  it("removes a file the checkpoint dropped vs its parent", async () => {
    const repo = await newRepo();
    // In-flight work: add feature.ts AND delete the tracked base.txt.
    await writeFile(join(repo, "feature.ts"), "export const x = 1;\n");
    await rm(join(repo, "base.txt"));
    await checkpointInflightWork(repo, "conv-DEL", "user-D");

    // Resume scenario: clean tree at HEAD (base.txt back, feature.ts gone).
    await git(repo, "checkout", "--", "base.txt");
    await rm(join(repo, "feature.ts"));
    expect(await porcelain(repo)).toBe("");
    expect(existsSync(join(repo, "base.txt"))).toBe(true);

    const result = await restoreInflightCheckpoint(repo, "conv-DEL", {
      siblingSlotActive: false,
    });

    expect(result.restored).toBe(true);
    // The added file came back...
    expect(existsSync(join(repo, "feature.ts"))).toBe(true);
    // ...and the in-flight deletion was re-applied (base.txt NOT resurrected).
    expect(existsSync(join(repo, "base.txt"))).toBe(false);
  });
});

describe("AC4: no checkpoint over a clean tree", () => {
  it("is a no-op when there are no uncommitted changes", async () => {
    const repo = await newRepo();
    expect(await porcelain(repo)).toBe("");
    await checkpointInflightWork(repo, "conv-clean", "user-clean");
    expect(await refExists(repo, "conv-clean")).toBe(false);
  });
});

describe("AC6: checkpoint failure is non-fatal", () => {
  it("does not throw and mirrors op=checkpoint-on-abort when git plumbing fails", async () => {
    // A non-git directory forces every plumbing call to fail.
    const notARepo = await mkdtemp(join(tmpdir(), "inflight-notrepo-"));
    repos.push(notARepo);
    await writeFile(join(notARepo, "feature.ts"), "x\n");

    await expect(
      checkpointInflightWork(notARepo, "conv-fail", "user-fail"),
    ).resolves.toBeUndefined();

    expect(reportSilentFallback).toHaveBeenCalledWith(
      expect.anything(),
      expect.objectContaining({ op: "checkpoint-on-abort" }),
    );
  });
});

// AC8 (erasure cascade) is satisfied without a dedicated helper: a successful
// restore CONSUMES its ref (asserted in RED-B above), and account deletion's
// `deleteWorkspace` removes the whole clone (and thus all checkpoint refs) for
// the solo case. The orphan-TTL prune is deferred (plan-review consensus).
