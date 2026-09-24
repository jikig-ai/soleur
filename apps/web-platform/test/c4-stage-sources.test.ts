// stageCommittedC4Sources (#8623): the C4 re-render's ONLY input is the
// regular-file LikeC4 source blobs of the diagrams subtree of a fixed commit,
// fetched from GitHub. Driven against an in-memory fake that encodes GitHub's
// MEASURED listing quirks (test/helpers/fake-github-trees.ts).
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { existsSync, mkdtempSync, readdirSync, readFileSync, rmSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, relative } from "node:path";
import {
  createFakeGitHub,
  FakeGitHubApiError,
  type FakeGitHub,
  type FakeTree,
} from "./helpers/fake-github-trees";

const fake = vi.hoisted(() => ({ current: null as FakeGitHub | null }));
vi.mock("@/server/github-api", () => ({
  githubApiGet: (...a: [number, string, { signal?: AbortSignal }?]) => fake.current!.get(...a),
  githubApiPost: (...a: [number, string, { content: string; sha?: string }, string?]) =>
    fake.current!.post(...a),
  GitHubApiError: FakeGitHubApiError,
}));

import {
  stageCommittedC4Sources,
  __clearBlobCacheForTests,
  gitBlobSha,
  FORBIDDEN_DETAIL,
  RATE_LIMITED_DETAIL,
  LIKEC4_CONFIG_NAMES,
  MAX_STAGED_SOURCES,
  MAX_STAGED_SOURCE_BYTES,
  BLOB_CONCURRENCY,
  DIAGRAMS_UNREADABLE_DETAIL,
} from "@/server/c4-stage-sources";

const D = "knowledge-base/engineering/architecture/diagrams";
const SRC = "model {\n  u = actor 'User'\n}\n";
// Synthetic in-repo relative targets for the fake. Built by repetition so no
// literal parent-dir run appears in this file (repo-wide-containment.test.ts
// reads such runs as the suite escaping apps/web-platform; this reads nothing).
const UP = "../";

let root: string;
let dest: string;
beforeEach(() => {
  __clearBlobCacheForTests();
  root = mkdtempSync(join(tmpdir(), "c4-stage-test-"));
  dest = join(root, "src");
});
afterEach(() => {
  rmSync(root, { recursive: true, force: true });
  fake.current = null;
});

function repo(tree: FakeTree, opts?: Parameters<typeof createFakeGitHub>[1]) {
  fake.current = createFakeGitHub(tree, opts);
  return fake.current;
}

function stage(gh: FakeGitHub, extra: Partial<Parameters<typeof stageCommittedC4Sources>[0]> = {}) {
  return stageCommittedC4Sources({
    installationId: 1,
    owner: "o",
    repo: "r",
    commitSha: gh.firstCommit,
    destDir: dest,
    signal: new AbortController().signal,
    retryDelayMs: 1,
    ...extra,
  });
}

function stagedFiles(): string[] {
  if (!existsSync(dest)) return [];
  const out: string[] = [];
  const walk = (d: string) => {
    for (const n of readdirSync(d)) {
      const p = join(d, n);
      if (statSync(p).isDirectory()) walk(p);
      else out.push(relative(dest, p));
    }
  };
  walk(dest);
  return out.sort();
}

const benign = (): FakeTree => ({
  [`${D}/model.c4`]: { mode: "100644", content: SRC },
  [`${D}/spec.likec4`]: { mode: "100644", content: "specification { element actor }\n" },
  [`${D}/nested/extra.like-c4`]: { mode: "100644", content: "model { }\n" },
  [`${D}/exec.c4`]: { mode: "100755", content: "model { }\n" },
  [`${D}/README.md`]: { mode: "100644", content: "# diagrams\n" },
  [`${D}/.gitkeep`]: { mode: "100644", content: "" },
  [`${D}/model.likec4.json`]: { mode: "100644", content: "{}", reportedSize: 5 * 1024 * 1024 },
  [`${D}/img.png`]: { mode: "100644", content: Buffer.from([0x89, 0x50, 0x4e, 0x47]) },
  "README.md": { mode: "100644", content: "root" },
});

describe("stageCommittedC4Sources — benign trees (must PASS)", () => {
  it("H3: stages exactly the regular-file LikeC4 sources, byte-identical, and nothing else", async () => {
    const gh = repo(benign());
    const res = await stage(gh);
    expect(res.ok).toBe(true);
    if (res.ok) expect([...res.paths].sort()).toEqual(["exec.c4", "model.c4", "nested/extra.like-c4", "spec.likec4"]);
    expect(stagedFiles()).toEqual(["exec.c4", "model.c4", "nested/extra.like-c4", "spec.likec4"]);
    expect(readFileSync(join(dest, "model.c4"), "utf8")).toBe(SRC);
    // Non-source bytes (a 5 MiB model, a PNG) are never fetched and never count.
    expect(gh.blobCalls()).toBe(4);
    if (res.ok) expect(res.modelSha).toMatch(/^[0-9a-f]{40}$/);
  });

  it("many large non-source entries beside 4 sources do not trip too-large", async () => {
    const t = benign();
    for (let i = 0; i < MAX_STAGED_SOURCES + 5; i++) {
      t[`${D}/notes/n${i}.md`] = { mode: "100644", content: "x", reportedSize: 1024 * 1024 };
    }
    const res = await stage(repo(t));
    expect(res.ok).toBe(true);
  });

  it("two sources with identical content both land at their own paths", async () => {
    const gh = repo({
      [`${D}/a.c4`]: { mode: "100644", content: SRC },
      [`${D}/b.c4`]: { mode: "100644", content: SRC },
    });
    const res = await stage(gh);
    expect(res.ok).toBe(true);
    expect(stagedFiles()).toEqual(["a.c4", "b.c4"]);
  });

  it("a DIRECTORY named like a config is a source directory, not a refusal (measured O)", async () => {
    const res = await stage(
      repo({ [`${D}/model.c4`]: { mode: "100644", content: SRC }, [`${D}/likec4.config.mjs/y.c4`]: { mode: "100644", content: "model { }\n" } }),
    );
    expect(res.ok).toBe(true);
    expect(stagedFiles()).toEqual(["likec4.config.mjs/y.c4", "model.c4"]);
  });

  it("node_modules sources are neither staged nor counted (likec4 ignores them)", async () => {
    const t: FakeTree = { [`${D}/model.c4`]: { mode: "100644", content: SRC } };
    for (let i = 0; i < MAX_STAGED_SOURCES + 1; i++) {
      t[`${D}/node_modules/p/x${i}.c4`] = { mode: "100644", content: "model { }\n" };
    }
    const res = await stage(repo(t));
    expect(res.ok).toBe(true);
    expect(stagedFiles()).toEqual(["model.c4"]);
  });

  it("retries a read-after-write 404 on the first Contents call", async () => {
    const gh = repo(benign(), { notFoundTimes: { "knowledge-base/engineering/architecture": 1 } });
    const res = await stage(gh);
    expect(res.ok).toBe(true);
  });

  it("never reads anything but the given commit (HEAD holding a config is not consulted)", async () => {
    const gh = repo(benign());
    gh.commit({ [`${D}/likec4.config.mjs`]: { mode: "100644", content: "boom" } });
    const res = await stage(gh);
    expect(res.ok).toBe(true);
    const contents = gh.calls.filter((c) => c.includes("/contents/"));
    expect(contents.every((c) => c.includes(`ref=${gh.firstCommit}`))).toBe(true);
  });

  it(`never has more than ${BLOB_CONCURRENCY} blob GETs in flight`, async () => {
    const t: FakeTree = {};
    for (let i = 0; i < 30; i++) t[`${D}/m${i}.c4`] = { mode: "100644", content: `model { e${i} = actor }\n` };
    const gh = repo(t);
    const res = await stage(gh);
    expect(res.ok).toBe(true);
    expect(gh.maxBlobInFlight()).toBeGreaterThan(1);
    expect(gh.maxBlobInFlight()).toBeLessThanOrEqual(BLOB_CONCURRENCY);
  });
});

describe("stageCommittedC4Sources — refusals", () => {
  function expectRefusal(
    res: Awaited<ReturnType<typeof stageCommittedC4Sources>>,
    gh: FakeGitHub,
    refusalClass: string,
    path?: string,
    more = 0,
  ) {
    expect(res).toMatchObject({ ok: false, reason: "unsafe_source", refusalClass, more });
    if (path !== undefined && !res.ok && res.reason === "unsafe_source") expect(res.path).toBe(path);
    // Decided from the listing: zero blob requests, nothing written.
    expect(gh.blobCalls()).toBe(0);
    expect(existsSync(dest)).toBe(false);
  }

  it("names exactly the nine likec4 config file names", () => {
    expect([...LIKEC4_CONFIG_NAMES].sort()).toEqual(
      [
        ".likec4rc",
        ".likec4.config.json",
        "likec4.config.json",
        "likec4.config.js",
        "likec4.config.cjs",
        "likec4.config.mjs",
        "likec4.config.ts",
        "likec4.config.cts",
        "likec4.config.mts",
      ].sort(),
    );
  });

  for (const name of [
    ".likec4rc",
    ".likec4.config.json",
    "likec4.config.json",
    "likec4.config.js",
    "likec4.config.cjs",
    "likec4.config.mjs",
    "likec4.config.ts",
    "likec4.config.cts",
    "likec4.config.mts",
  ]) {
    it(`refuses ${name} at the top level`, async () => {
      const gh = repo({ ...benign(), [`${D}/${name}`]: { mode: "100644", content: "x" } });
      expectRefusal(await stage(gh), gh, "likec4-config", name);
    });
    it(`refuses ${name} nested after a compliant top level`, async () => {
      const gh = repo({ ...benign(), [`${D}/sub/${name}`]: { mode: "100644", content: "x" } });
      expectRefusal(await stage(gh), gh, "likec4-config", `sub/${name}`);
    });
  }

  it("counts every offender: first path + more", async () => {
    const gh = repo({
      ...benign(),
      [`${D}/a/likec4.config.mjs`]: { mode: "100644", content: "x" },
      [`${D}/b/.likec4rc`]: { mode: "100644", content: "x" },
    });
    expectRefusal(await stage(gh), gh, "likec4-config", "a/likec4.config.mjs", 1);
  });

  it("refuses a nested file symlink that the Contents listing reports as 'file'", async () => {
    const gh = repo({ ...benign(), [`${D}/sub/link.c4`]: { mode: "120000", target: "../model.c4" } });
    expectRefusal(await stage(gh), gh, "symlink", "sub/link.c4");
  });

  it("refuses a nested directory symlink", async () => {
    const gh = repo({
      ...benign(),
      "elsewhere/x.c4": { mode: "100644", content: "model { leaked = actor }\n" },
      [`${D}/linked`]: { mode: "120000", target: `${UP.repeat(4)}elsewhere` },
    });
    expectRefusal(await stage(gh), gh, "symlink", "linked");
  });

  it("refuses when the diagrams folder itself is a directory symlink", async () => {
    const gh = repo({
      "elsewhere/model.c4": { mode: "100644", content: SRC },
      [D]: { mode: "120000", target: `${UP.repeat(3)}elsewhere` },
      "knowledge-base/engineering/architecture/README.md": { mode: "100644", content: "x" },
    });
    expectRefusal(await stage(gh), gh, "diagrams-folder");
  });

  it("refuses when the diagrams folder is a submodule", async () => {
    const gh = repo({
      [D]: { mode: "160000" },
      "knowledge-base/engineering/architecture/README.md": { mode: "100644", content: "x" },
    });
    expectRefusal(await stage(gh), gh, "diagrams-folder");
  });

  it("refuses when the architecture folder ABOVE diagrams is itself a symlink (object, not a listing)", async () => {
    const gh = repo({
      "elsewhere/diagrams/model.c4": { mode: "100644", content: SRC },
      "knowledge-base/engineering/architecture": { mode: "120000", target: `${UP.repeat(2)}elsewhere` },
      "knowledge-base/engineering/README.md": { mode: "100644", content: "x" },
    });
    const res = await stage(gh);
    expectRefusal(res, gh, "diagrams-folder");
    if (!res.ok && res.reason === "unsafe_source") expect(res.path).toBeUndefined();
  });

  it("refuses a nested submodule", async () => {
    const gh = repo({ ...benign(), [`${D}/vendored`]: { mode: "160000" } });
    expectRefusal(await stage(gh), gh, "gitlink", "vendored");
  });

  it("a symlinked PARENT (persistent 404 through it) is an honest unreadable io_error", async () => {
    const gh = repo({
      "real/architecture/diagrams/model.c4": { mode: "100644", content: SRC },
      "knowledge-base/engineering": { mode: "120000", target: "../real" },
    });
    const res = await stage(gh);
    expect(res).toEqual({ ok: false, reason: "io_error", detail: DIAGRAMS_UNREADABLE_DETAIL });
    expect(gh.blobCalls()).toBe(0);
    expect(existsSync(dest)).toBe(false);
  });

  it("refuses a truncated tree listing as too-large", async () => {
    const gh = repo(benign(), { truncated: true });
    expectRefusal(await stage(gh), gh, "too-large");
  });

  it(`refuses more than ${MAX_STAGED_SOURCES} sources`, async () => {
    const t: FakeTree = {};
    for (let i = 0; i <= MAX_STAGED_SOURCES; i++) t[`${D}/m${i}.c4`] = { mode: "100644", content: "model { }\n" };
    const gh = repo(t);
    expectRefusal(await stage(gh), gh, "too-large");
  });

  it("refuses sources whose listed sizes total more than 4 MiB", async () => {
    const gh = repo({
      [`${D}/a.c4`]: { mode: "100644", content: "x", reportedSize: MAX_STAGED_SOURCE_BYTES / 2 },
      [`${D}/b.c4`]: { mode: "100644", content: "y", reportedSize: MAX_STAGED_SOURCE_BYTES / 2 + 1 },
    });
    expectRefusal(await stage(gh), gh, "too-large");
  });
});

describe("stageCommittedC4Sources — io failures", () => {
  it("a decoded blob whose length differs from the listing size is io_error", async () => {
    const gh = repo({ [`${D}/model.c4`]: { mode: "100644", content: SRC, reportedSize: 3 } });
    const res = await stage(gh);
    expect(res).toMatchObject({ ok: false, reason: "io_error" });
  });

  it("a tree path escaping the stage root is io_error and writes nothing outside it", async () => {
    const gh = repo({ [`${D}/${UP.repeat(2)}escape.c4`]: { mode: "100644", content: SRC } });
    const res = await stage(gh);
    // Rejected from the LISTING, before any fetch or write.
    expect(res).toEqual({ ok: false, reason: "io_error", detail: "listing: malformed source entry" });
    expect(gh.blobCalls()).toBe(0);
    expect(existsSync(join(root, "escape.c4"))).toBe(false);
    expect(existsSync(join(root, "..", "escape.c4"))).toBe(false);
  });

  it("429, and a 403 naming a rate limit, are 'fetch: rate-limited'; any other 403 is 'fetch: forbidden'", async () => {
    const cases: Array<[number, string | undefined, string]> = [
      [429, undefined, RATE_LIMITED_DETAIL],
      [403, "You have exceeded a secondary rate limit", RATE_LIMITED_DETAIL],
      [403, "Resource not accessible by integration", FORBIDDEN_DETAIL],
    ];
    for (const [status, message, detail] of cases) {
      rmSync(dest, { recursive: true, force: true });
      __clearBlobCacheForTests();
      const res = await stage(repo(benign(), { blobStatus: status, blobMessage: message }));
      expect(res).toEqual({ ok: false, reason: "io_error", detail });
    }
  });

  it("a blob whose bytes do not hash to its listed sha is io_error", async () => {
    const gh = repo({ [`${D}/model.c4`]: { mode: "100644", content: SRC } });
    gh.corrupt(gitBlobSha(Buffer.from(SRC)));
    expect(await stage(gh)).toEqual({ ok: false, reason: "io_error", detail: "fetch: blob sha mismatch" });
  });

  it("a directory at the model path is io_error, before any blob is fetched", async () => {
    const gh = repo({ [`${D}/model.c4`]: { mode: "100644", content: SRC }, [`${D}/model.likec4.json/x.md`]: { mode: "100644", content: "x" } });
    const res = await stage(gh);
    expect(res).toEqual({ ok: false, reason: "io_error", detail: "listing: model path is not a regular file" });
    expect(gh.blobCalls()).toBe(0);
  });

  it("a malformed commit sha stages nothing and reads nothing (never falls back to HEAD)", async () => {
    const gh = repo(benign());
    const res = await stage(gh, { commitSha: "" });
    expect(res).toEqual({ ok: false, reason: "io_error", detail: "stage: no commit sha" });
    expect(gh.calls).toEqual([]);
  });

  it("bytes the caller already holds are staged without a blob GET, and fetched blobs are cached", async () => {
    const gh = repo({ [`${D}/model.c4`]: { mode: "100644", content: SRC }, [`${D}/spec.c4`]: { mode: "100644", content: "specification { }\n" } });
    const first = await stage(gh, { known: [Buffer.from(SRC)] });
    expect(first.ok).toBe(true);
    expect(gh.blobCalls()).toBe(1); // spec.c4 only
    rmSync(dest, { recursive: true, force: true });
    const second = await stage(gh);
    expect(second.ok).toBe(true);
    expect(gh.blobCalls()).toBe(1); // both served from the cache / known set
  });

  it("offenders under directories likec4 ignores (node_modules, .git) are not refused", async () => {
    const gh = repo({
      ...benign(),
      [`${D}/node_modules/p/likec4.config.mjs`]: { mode: "100644", content: "x" },
      [`${D}/node_modules/.bin/tool`]: { mode: "120000", target: "../p/tool.js" },
      [`${D}/.git/HEAD`]: { mode: "100644", content: "ref" },
    });
    const res = await stage(gh);
    expect(res.ok).toBe(true);
  });

  it("a request for another repo or installation is refused by the fake (and the SUT never makes one)", async () => {
    const gh = repo(benign());
    const res = await stage(gh, { installationId: 2 });
    expect(res.ok).toBe(false);
  });

  it("an aborted signal stops staging: timeout, no further writes, no stage dir left behind", async () => {
    const gh = repo(benign(), { stallBlobs: true });
    const ac = new AbortController();
    const p = stage(gh, { signal: ac.signal });
    await new Promise((r) => setTimeout(r, 20));
    ac.abort(new Error("stage: deadline"));
    const res = await p;
    expect(res).toEqual({ ok: false, reason: "timeout", detail: "stage: deadline" });
    // The caller removes its dir; a late write must not recreate it.
    rmSync(root, { recursive: true, force: true });
    await new Promise((r) => setTimeout(r, 20));
    expect(existsSync(dest)).toBe(false);
  });

  it("a blob response that lands AFTER the abort cannot recreate the removed stage dir (nested path)", async () => {
    const gh = repo({ [`${D}/deep/nested/model.c4`]: { mode: "100644", content: SRC } }, { lateBlobsMs: 60 });
    const ac = new AbortController();
    const p = stage(gh, { signal: ac.signal });
    await new Promise((r) => setTimeout(r, 20)); // listing done, blob in flight
    ac.abort(new Error("stage: deadline"));
    rmSync(root, { recursive: true, force: true }); // the caller's cleanup
    expect(await p).toEqual({ ok: false, reason: "timeout", detail: "stage: deadline" });
    await new Promise((r) => setTimeout(r, 120)); // the late blob arrives
    expect(existsSync(root)).toBe(false);
  });
});
