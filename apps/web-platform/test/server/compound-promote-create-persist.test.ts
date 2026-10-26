// WikiSkill Phase 2 (#10550), review round -- Step B (`runCreatePersistStep`) against a REAL git remote and clone.
//
// PROPERTIES (CTO rulings R4 and R5 and the review fixes C, D, G):
//   R4  The installation token is NOT in `.git/config` while any create-arm script (scan, README sync) runs; it is
//       put back only for the commit helper, and stripped again when the step ends.
//   R5  Step B refreshes the depth-1 clone to the CURRENT main before it renders, re-runs the admission checks against
//       that tree, and refuses `persist/base-moved` when main moved a file it used (blob-scoped: an unrelated merge
//       does not refuse).
//   D   The bytes handed to the commit helper equal the bytes that were gated (rendered files, ledger baseline + row).
//   G   One deadline for the step; a lost clone is `persist/clone-missing`; the restore short-circuits.
//
// ASSEMBLY: a throwaway "remote" repository (the directory name contains the literal `x-access-token`, so the remote
// URL written by `setOriginToken` is detectable in `.git/config` exactly as the real token URL would be), a depth-1
// clone of it, the REAL Step A to produce the verdict, and the REAL Step B. Only the two SPAWN gates (scanner and
// README sync -- exercised for real in compound-promote-create-gates.test.ts and the dry-render suite) and the
// commit helper are doubles; each double records what `.git/config` held at the moment it ran.
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from "vitest";
import { appendFileSync, cpSync, existsSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";

vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

const h = vi.hoisted(() => ({
  url: "",
  scan: vi.fn(),
  sync: vi.fn(),
  /** `.git/config` as it was when each double ran. */
  configAt: { scan: [] as string[], sync: [] as string[], commit: [] as string[] },
}));

vi.mock("@/server/observability", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/observability")>()),
  reportSilentFallback: vi.fn(),
}));
vi.mock("@/server/inngest/functions/_cron-shared", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/inngest/functions/_cron-shared")>()),
  buildAuthenticatedCloneUrl: () => h.url,
}));
vi.mock("@/server/compound-promote-create-gates", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/compound-promote-create-gates")>()),
  runSkillScan: (...a: unknown[]) => h.scan(...a),
  syncReadmeCounts: (...a: unknown[]) => h.sync(...a),
}));

import { reportSilentFallback } from "@/server/observability";
import { setOriginToken } from "@/server/inngest/functions/_cron-claude-eval-substrate";
import { CREATE_STAGE_ORDER } from "@/server/compound-promote-create";
import { README_SYNC_TIMEOUT_MS, SCAN_TIMEOUT_MS, createSyntheticCheckNames } from "@/server/compound-promote-create-gates";
import {
  CREATE_PERSIST_DEADLINE_MS,
  DEADLINE_STAGES,
  PLAIN_ORIGIN_URL,
  runCreatePersistStep,
  runCreateProposeStep,
  type CreateVerdictCreate,
} from "@/server/compound-promote-create-arm";
import {
  CREATE_FIELD_MAX_CHARS,
  CREATE_ITEM_MAX_CHARS,
  CREATE_LIST_MAX_ITEMS,
  PROMOTION_LOG_PATH,
  countDescriptionWords,
  createPathList,
  proposalOverlapText,
  rankOverlap,
} from "@/server/compound-promote-create";
import type { PatternPage } from "@/server/compound-promote-patterns";
import { gitFixture } from "../../../../plugins/soleur/test/lib/git-fixture-env";
import { buildSyntheticPluginTree, skillMd } from "../helpers/compound-promote-tree";

const FIX = join(__dirname, "..", "fixtures", "compound-promote-create");
const PROPOSAL = JSON.parse(readFileSync(join(FIX, "proposal.json"), "utf8")) as Record<string, unknown>;
const SLUG = String(PROPOSAL.slug);
const PATTERN: PatternPage = {
  slug: String(PROPOSAL.pattern_slug), title: "Synthetic", summary: "Synthetic summary.", status: "open", openedOn: "2026-10-01", tags: ["retry"],
  evidence: [1, 2, 3, 4, 5].map((n) => `knowledge-base/project/learnings/2026-10-0${n}-synthetic-${n}.md`), requiredReading: false,
};
const RUN_AT = "2026-10-26T10:00:00.000Z";
const README = "README.md";
const PLUGIN_README = "plugins/soleur/README.md";

const roots: string[] = [];
const tmp = (prefix: string): string => {
  const d = mkdtempSync(join(tmpdir(), prefix));
  roots.push(d);
  return d;
};
const cleanEnv = (): NodeJS.ProcessEnv => {
  const env: Record<string, string> = {};
  for (const [k, v] of Object.entries(process.env)) if (!k.startsWith("GIT_") && v !== undefined) env[k] = v;
  return env as NodeJS.ProcessEnv;
};

// ---------------------------------------------------------------------------------------------------------
// A `git` first on PATH. It (1) logs the EVENT of every invocation (fetch, reset, clean, checkout, rev-parse, status,
// ls-tree, ls-remote, remote, set-url) to a file, (2) fails `set-url` while the counter file holds a positive number,
// and (3) writes BIG into the clock file on the Nth occurrence of a chosen event, so a test can make a deadline
// checkpoint fire exactly between two git calls. The clock file is what `now` reads. Everything else execs real git.
let clockFilePath = "";
const clockPath = (): string => clockFilePath;
const CLOCK_START = 1_000_000;
const CLOCK_BIG = 100_000_000;
interface GitWrapper {
  events: () => string[];
  /** Make the next `n` `set-url` calls fail. */
  failSetUrl: (n: number) => void;
  /** Jump the clock when the `nth` `ev` runs. */
  bumpOn: (ev: string, nth: number) => void;
  /** Make the `nth` `ev` fail with exit 128 (`fail`, the default) print one non-object-id line and exit 0 (`garble`), or die by SIGKILL (`kill`), instead of running git. */
  failOn: (ev: string, nth: number, mode?: "fail" | "garble" | "kill") => void;
  /** Append a marker to the same time-ordered stream (the suite's doubles use it). */
  mark: (name: string) => void;
  now: () => number;
  restore: () => void;
}
function installGitWrapper(): GitWrapper {
  const dir = tmp("create-persist-gitwrap-");
  const file = (n: string) => join(dir, n);
  writeFileSync(file("log"), "");
  writeFileSync(file("clock"), String(CLOCK_START));
  clockFilePath = file("clock");
  writeFileSync(file("fail-count"), "0");
  writeFileSync(file("bump"), "none 0");
  writeFileSync(file("inject"), "none 0 fail");
  const real = execFileSync("sh", ["-c", "command -v git"], { encoding: "utf8" }).trim();
  const script = [
    "#!/bin/sh",
    'ev=""',
    'for a in "$@"; do',
    '  case "$a" in fetch|reset|clean|checkout|rev-parse|status|ls-tree|ls-remote|remote) [ -z "$ev" ] && ev="$a";; esac',
    "done",
    'for a in "$@"; do [ "$a" = "set-url" ] && ev="set-url"; done',
    `echo "$ev" >> "${file("log")}"`,
    'if [ "$ev" = "set-url" ]; then',
    `  n=$(cat "${file("fail-count")}"); if [ "$n" -gt 0 ]; then echo $((n-1)) > "${file("fail-count")}"; echo "fatal: simulated" >&2; exit 128; fi`,
    "fi",
    `read bev bnth < "${file("bump")}"`,
    'if [ "$ev" = "$bev" ]; then',
    `  c=$(grep -c "^$ev$" "${file("log")}"); [ "$c" -eq "$bnth" ] && echo ${CLOCK_BIG} > "${file("clock")}"`,
    "fi",
    `read iev inth imode < "${file("inject")}"`,
    'if [ "$ev" = "$iev" ]; then',
    `  c=$(grep -c "^$ev$" "${file("log")}")`,
    '  if [ "$c" -eq "$inth" ]; then',
    '    if [ "$imode" = "garble" ]; then echo "not-an-object-id"; exit 0; fi',
    '    if [ "$imode" = "kill" ]; then kill -KILL $$; fi',
    '    echo "fatal: simulated" >&2; exit 128',
    "  fi",
    "fi",
    `exec ${real} "$@"`,
    "",
  ].join("\n");
  writeFileSync(file("git"), script, { mode: 0o755 });
  const saved = process.env.PATH;
  process.env.PATH = `${dir}:${saved ?? ""}`;
  return {
    events: () => readFileSync(file("log"), "utf8").split("\n").filter(Boolean),
    failSetUrl: (n) => writeFileSync(file("fail-count"), String(n)),
    bumpOn: (ev, nth) => writeFileSync(file("bump"), `${ev} ${nth}`),
    failOn: (ev, nth, mode = "fail") => writeFileSync(file("inject"), `${ev} ${nth} ${mode}`),
    mark: (name) => appendFileSync(file("log"), `${name}\n`),
    now: () => Number(readFileSync(file("clock"), "utf8")),
    restore: () => {
      process.env.PATH = saved;
    },
  };
}

let template = "";

beforeAll(() => {
  template = tmp("create-persist-template-x-access-token-");
  const git = gitFixture(template);
  git(["init", "-q", "-b", "main", "."]);
  const put = (p: string, t: string) => {
    mkdirSync(dirname(join(template, p)), { recursive: true });
    writeFileSync(join(template, p), t);
  };
  buildSyntheticPluginTree(put);
  put(README, "Soleur: 99 skills\n");
  put(PLUGIN_README, "| Skills | 99 |\n");
  put(PROMOTION_LOG_PATH, "| date | hash | target | n | status | tier | pr |\n");
  put("docs/unrelated.md", "unrelated\n");
  git(["add", "-A"]);
  git(["commit", "-qm", "init"]);
});

afterAll(() => {
  for (const r of roots) rmSync(r, { recursive: true, force: true });
});

interface World {
  remote: string;
  clone: string;
  /** Commit `files` to the remote's main. */
  advance: (files: Record<string, string>) => void;
  config: () => string;
  /** `git` run in the remote repository. */
  rgit: (args: string[]) => string;
}

function world(): World {
  const remote = tmp("create-persist-remote-x-access-token-");
  rmSync(remote, { recursive: true, force: true });
  cpSync(template, remote, { recursive: true });
  const rgit = gitFixture(remote);
  const cloneParent = tmp("create-persist-clone-");
  const clone = join(cloneParent, "repo");
  execFileSync("git", ["clone", "-q", "--depth=1", `file://${remote}`, clone], { env: cleanEnv() });
  h.url = `file://${remote}`;
  return {
    remote,
    clone,
    advance: (files) => {
      for (const [p, t] of Object.entries(files)) {
        mkdirSync(dirname(join(remote, p)), { recursive: true });
        writeFileSync(join(remote, p), t);
      }
      rgit(["add", "-A"]);
      rgit(["commit", "-qm", "advance"]);
    },
    config: () => readFileSync(join(clone, ".git", "config"), "utf8"),
    rgit,
  };
}

const poster = (proposal: Record<string, unknown>) => (async () => ({ text: JSON.stringify(proposal), stopReason: "end_turn" })) as never;

async function propose(w: World, proposalOver: Record<string, unknown> = {}): Promise<CreateVerdictCreate> {
  const counted = countDescriptionWords(join(w.clone, "plugins", "soleur"));
  if (!counted.ok) throw new Error(counted.detail);
  const merged: Record<string, unknown> = { ...structuredClone(PROPOSAL), ...proposalOver };
  merged.nearest_skill = rankOverlap(
    proposalOverlapText({ slug: String(merged.slug), description: String(merged.description), when_to_use: merged.when_to_use as string[] }),
    counted.records,
  )[0].name;
  const v = await runCreateProposeStep({
    repoRoot: w.clone,
    octokit: { request: async () => ({ data: [] }) } as never,
    patterns: [PATTERN],
    ledgerEntries: [],
    runStartedAt: RUN_AT,
    capLeft: 1,
    apiKey: "k",
    runId: "R",
    scanOpenPrPaths: async () => ({ paths: [], incomplete: null }),
    post: poster(merged),
  });
  if (v.kind !== "create") throw new Error(`step A: ${JSON.stringify(v)}`);
  return v;
}

const logger = () => ({ info: vi.fn(), warn: vi.fn(), error: vi.fn() });

function persistArgs(w: World, verdict: CreateVerdictCreate, over: Record<string, unknown> = {}) {
  const commit = vi.fn(async (cfg: { spawnCwd: string }) => {
    h.configAt.commit.push(readFileSync(join(cfg.spawnCwd, ".git", "config"), "utf8"));
    return { status: "committed", prNumber: 77, branch: "b", fileCount: 6, deletionCount: 0 };
  });
  return {
    repoRoot: w.clone,
    installationToken: "tok-synthetic",
    runStartedAt: RUN_AT,
    octokit: { request: async () => ({ data: [] }), graphql: async () => ({}) } as never,
    logger: logger(),
    verdict,
    patterns: [PATTERN],
    safeCommit: commit as never,
    ...over,
  } as Parameters<typeof runCreatePersistStep>[0] & { safeCommit: typeof commit };
}

const bumpReadmes = (root: string): void => {
  for (const rel of [README, PLUGIN_README]) writeFileSync(join(root, rel), readFileSync(join(root, rel), "utf8").replace("99", "100"));
};

beforeEach(() => {
  expect.hasAssertions();
  vi.mocked(reportSilentFallback).mockClear();
  h.configAt.scan.length = 0;
  h.configAt.sync.length = 0;
  h.configAt.commit.length = 0;
  h.scan.mockReset();
  h.sync.mockReset();
  h.scan.mockImplementation(async (o: { repoRoot: string }) => {
    h.configAt.scan.push(readFileSync(join(o.repoRoot, ".git", "config"), "utf8"));
    return { ok: true };
  });
  h.sync.mockImplementation(async (o: { repoRoot: string }) => {
    h.configAt.sync.push(readFileSync(join(o.repoRoot, ".git", "config"), "utf8"));
    bumpReadmes(o.repoRoot);
    return { ok: true };
  });
});

// ---------------------------------------------------------------------------------------------------------
describe("R4 -- the token is not in .git/config while any create-arm script runs", () => {
  it("the fixture is sound: a clone of the token-named remote HAS the marker in its config before Step B", async () => {
    const w = world();
    expect(w.config()).toContain("x-access-token");
  });

  it("the scanner and the README sync run against a config with the PLAIN origin; the commit helper sees the token URL; the step ends stripped", async () => {
    const w = world();
    const v = await propose(w);
    const a = persistArgs(w, v);
    expect(await runCreatePersistStep(a)).toEqual({ kind: "opened", pr: 77 });
    expect(h.configAt.scan).toHaveLength(1);
    expect(h.configAt.sync).toHaveLength(1);
    for (const cfg of [...h.configAt.scan, ...h.configAt.sync]) {
      expect(cfg).not.toContain("x-access-token");
      expect(cfg).toContain(PLAIN_ORIGIN_URL);
    }
    expect(h.configAt.commit).toHaveLength(1);
    expect(h.configAt.commit[0]).toContain("x-access-token"); // put back for the network calls only
    expect(w.config()).not.toContain("x-access-token");
    expect(w.config()).toContain(PLAIN_ORIGIN_URL);
  });

  it("a refusal still strips the token (the scanner refused)", async () => {
    const w = world();
    const v = await propose(w);
    h.scan.mockResolvedValue({ ok: false, detail: "high-risk", fileIndex: 0, exit: 0 });
    const r = await runCreatePersistStep(persistArgs(w, v));
    expect(r).toMatchObject({ kind: "refused", class: "scan", detail: "high-risk", numbers: { file_index: 0, exit_code: 0 } });
    expect(w.config()).not.toContain("x-access-token");
  });

  it("a failing origin write refuses persist/origin-failed with a closed cause and spawns nothing", async () => {
    const w = world();
    const v = await propose(w);
    const r = await runCreatePersistStep(persistArgs(w, v, { setOrigin: async () => { throw Object.assign(new Error("ghs_secret leaked"), { code: "EACCES" }); } }));
    expect(r).toEqual({ kind: "refused", class: "persist", detail: "origin-failed" });
    expect(h.scan).not.toHaveBeenCalled();
    expect(JSON.stringify(vi.mocked(reportSilentFallback).mock.calls)).not.toContain("ghs_secret");
    expect(vi.mocked(reportSilentFallback)).toHaveBeenCalledWith(null, expect.objectContaining({ extra: expect.objectContaining({ cause: "EACCES" }) }));
  });
});

// ---------------------------------------------------------------------------------------------------------
describe("R5 -- the stale depth-1 clone is refreshed to main before the render", () => {
  it("a README merged to main after the clone is the one the sync sees (the stale copy would revert it on commit)", async () => {
    const w = world();
    const v = await propose(w);
    w.advance({ [README]: "Soleur: 99 skills\nMerged line from another PR\n" });
    let seen = "";
    h.sync.mockImplementation(async (o: { repoRoot: string }) => {
      seen = readFileSync(join(o.repoRoot, README), "utf8");
      bumpReadmes(o.repoRoot);
      return { ok: true };
    });
    // The README the commit starts from is the refreshed one; moving it AFTER the base blobs were read is what base-moved catches.
    expect(await runCreatePersistStep(persistArgs(w, v))).toEqual({ kind: "opened", pr: 77 });
    expect(seen).toContain("Merged line from another PR");
  });

  it("an UNRELATED merge (a file none of the four blobs is) does not refuse", async () => {
    const w = world();
    const v = await propose(w);
    w.advance({ "docs/another.md": "x\n" });
    expect(await runCreatePersistStep(persistArgs(w, v))).toEqual({ kind: "opened", pr: 77 });
  });

  it("a skill with the same slug merged after the clone is caught by the re-check: slug/skill-exists, nothing rendered or scanned", async () => {
    const w = world();
    const v = await propose(w);
    w.advance({ [`plugins/soleur/skills/${SLUG}/SKILL.md`]: skillMd(SLUG, "This skill should be used when another PR added the same slug first and won the race.") });
    const a = persistArgs(w, v);
    expect(await runCreatePersistStep(a)).toMatchObject({ kind: "refused", class: "slug", detail: "skill-exists" });
    expect(h.scan).not.toHaveBeenCalled();
    expect(a.safeCommit).not.toHaveBeenCalled();
  });

  it("descriptions merged after the clone that eat the headroom are caught by the re-check: budget/over-headroom", async () => {
    const w = world();
    const v = await propose(w);
    const big = Array.from({ length: 200 }, (_, i) => `word${i}`).join(" ");
    w.advance({ "plugins/soleur/skills/greedy/SKILL.md": skillMd("greedy", `This skill should be used ${big}`) });
    const a = persistArgs(w, v);
    expect(await runCreatePersistStep(a)).toMatchObject({ kind: "refused", class: "budget", detail: "over-headroom" });
    expect(a.safeCommit).not.toHaveBeenCalled();
  });

  // Another PR merges `file` while the scanner runs; only the four base files (and a new-slug dir) refuse.
  it.each([
    [PLUGIN_README, "| Skills | 99 |\n| Agents | 5 |\n", 1],
    [README, "Soleur: 99 skills\nMerged line from another PR\n", 1],
    ["plugins/soleur/test/components.test.ts", "const SKILL_DESCRIPTION_WORD_BUDGET = 9999;\n", 1],
    [PROMOTION_LOG_PATH, "| date | hash | target | n | status | tier | pr |\n| 2026-10-26 | h | t | 5 | merged | skill | #1 |\n", 1],
    ["docs/unrelated.md", "changed\n", 0],
  ])("the base moving DURING the gates: %s changed -> %i blob(s) moved (0 = no refusal)", async (file, text, movedCount) => {
    const w = world();
    const v = await propose(w);
    h.scan.mockImplementation(async () => {
      w.advance({ [file]: text });
      return { ok: true };
    });
    const a = persistArgs(w, v);
    const r = await runCreatePersistStep(a);
    if (movedCount === 0) {
      expect(r).toEqual({ kind: "opened", pr: 77 });
      return;
    }
    expect(r).toEqual({ kind: "refused", class: "persist", detail: "base-moved", numbers: { changed_count: movedCount } });
    expect(a.safeCommit).not.toHaveBeenCalled();
    expect(w.config()).not.toContain("x-access-token");
  });

  it("a failing fetch is persist/fetch-failed (the remote is gone) with the git exit as evidence; the token is stripped and NOTHING of git's stderr reaches Sentry", async () => {
    const w = world();
    const v = await propose(w);
    rmSync(w.remote, { recursive: true, force: true });
    vi.mocked(reportSilentFallback).mockClear();
    expect(await runCreatePersistStep(persistArgs(w, v))).toEqual({ kind: "refused", class: "persist", detail: "fetch-failed", numbers: { exit_code: 128 } });
    expect(w.config()).not.toContain("x-access-token");
    expect(vi.mocked(reportSilentFallback)).toHaveBeenCalledWith(null, expect.objectContaining({ op: "create-refused", extra: expect.objectContaining({ detail: "fetch-failed", cause: "exit128", exit_code: 128 }) }));
    // git's stderr names the (token-shaped) remote path; the synthetic Error and the closed extras do not carry it
    const sent = JSON.stringify(vi.mocked(reportSilentFallback).mock.calls.map((c) => [String((c[0] as Error | null)?.message), c[1]]));
    expect(sent).not.toContain("x-access-token");
    expect(sent).not.toContain(w.remote);
    expect(vi.mocked(reportSilentFallback)).toHaveBeenCalledWith(expect.objectContaining({ message: "git fetch failed" }), expect.objectContaining({ op: "create-gate-git", extra: expect.objectContaining({ sub: "fetch", exit: 128 }) }));
  });
});

// ---------------------------------------------------------------------------------------------------------
describe("G1 -- the origin write and the final strip", () => {
  it("a planted-symlink refusal and an ordinary set-url failure carry DISTINCT closed causes, never git's message", async () => {
    const secret = "ghs_" + "Q9w8E7r6".repeat(5);
    for (const [message, cause] of [
      ["git remote set-url origin refused: a symlinked git entry", "symlink-refused"],
      [`git remote set-url origin failed (exit 128, signal null): fatal ${secret}`, "set-url-failed"],
    ] as const) {
      const w = world();
      const v = await propose(w);
      vi.mocked(reportSilentFallback).mockClear();
      const r = await runCreatePersistStep(persistArgs(w, v, { setOrigin: async () => { throw new Error(message); } }));
      expect(r).toEqual({ kind: "refused", class: "persist", detail: "origin-failed" });
      expect(vi.mocked(reportSilentFallback)).toHaveBeenCalledWith(null, expect.objectContaining({ extra: expect.objectContaining({ cause }) }));
      expect(JSON.stringify(vi.mocked(reportSilentFallback).mock.calls)).not.toContain(secret);
    }
  });

  let gw: GitWrapper;
  beforeEach(() => {
    gw = installGitWrapper();
  });
  afterEach(() => gw.restore());

  const commitThatBreaksStrip = (failures: number) =>
    vi.fn(async () => {
      gw.failSetUrl(failures);
      return { status: "committed", prNumber: 77, branch: "b", fileCount: 6, deletionCount: 0 };
    });

  it("the final strip failing once is retried and the clone ends clean; nothing is mirrored", async () => {
    const w = world();
    const v = await propose(w);
    vi.mocked(reportSilentFallback).mockClear();
    expect(await runCreatePersistStep(persistArgs(w, v, { safeCommit: commitThatBreaksStrip(1) }))).toEqual({ kind: "opened", pr: 77 });
    expect(w.config()).not.toContain("x-access-token");
    expect(vi.mocked(reportSilentFallback).mock.calls.some((c) => (c[1] as { op: string }).op === "create-origin-strip-failed")).toBe(false);
  });

  it("the final strip failing twice is MIRRORED (op create-origin-strip-failed) and the step result is unchanged", async () => {
    const w = world();
    const v = await propose(w);
    vi.mocked(reportSilentFallback).mockClear();
    expect(await runCreatePersistStep(persistArgs(w, v, { safeCommit: commitThatBreaksStrip(2) }))).toEqual({ kind: "opened", pr: 77 });
    expect(vi.mocked(reportSilentFallback)).toHaveBeenCalledWith(null, expect.objectContaining({ feature: "cron-compound-promote", op: "create-origin-strip-failed" }));
    expect(w.config()).toContain("x-access-token"); // the failure is real: the token IS still on disk, which is why it is mirrored
  });

  it("the in-step strip failing (after the first fetch) refuses persist/origin-strip-failed with the evidence, and the final strip still runs", async () => {
    const w = world();
    const v = await propose(w);
    // The first origin write succeeds; the next `set-url` (the in-step strip after the fetch) fails once.
    const setOrigin = async (root: string, token: string) => {
      await setOriginToken(root, token);
      gw.failSetUrl(1);
    };
    vi.mocked(reportSilentFallback).mockClear();
    const r = await runCreatePersistStep(persistArgs(w, v, { setOrigin }));
    expect(r).toEqual({ kind: "refused", class: "persist", detail: "origin-strip-failed", numbers: { exit_code: 128 } });
    expect(w.config()).not.toContain("x-access-token");
    expect(h.scan).not.toHaveBeenCalled();
  });
});

// ---------------------------------------------------------------------------------------------------------
describe("G3 -- Step B correctness: the second fetch, the PR body, the orphan branch, the lookups", () => {
  it("(a) a skill dir with the new slug that appears on main BETWEEN the gates is persist/slug-appeared; no commit, token stripped", async () => {
    for (const rel of [`plugins/soleur/skills/${SLUG}/SKILL.md`, `plugins/soleur/cursor/skills/soleur-${SLUG}/SKILL.md`]) {
      const w = world();
      const v = await propose(w);
      h.scan.mockImplementation(async () => {
        w.advance({ [rel]: skillMd(SLUG, "This skill should be used when another PR added the same slug while the gates ran.") });
        return { ok: true };
      });
      const a = persistArgs(w, v);
      expect(await runCreatePersistStep(a), rel).toEqual({ kind: "refused", class: "persist", detail: "slug-appeared" });
      expect(a.safeCommit).not.toHaveBeenCalled();
      expect(w.config()).not.toContain("x-access-token");
    }
  });

  it("(a) harness: an unrelated directory appearing between the gates does NOT refuse", async () => {
    const w = world();
    const v = await propose(w);
    h.scan.mockImplementation(async () => {
      w.advance({ "plugins/soleur/skills/another-new/NOTES.md": "x\n" });
      return { ok: true };
    });
    expect(await runCreatePersistStep(persistArgs(w, v))).toEqual({ kind: "opened", pr: 77 });
  });

  it("(b) the PR body states the REFRESHED check (words, headroom, total, cap), not Step A's", async () => {
    const w = world();
    const v = await propose(w);
    // another PR merged a 5-word description after Step A measured: the total moved, the headroom shrank by 5
    w.advance({ "plugins/soleur/skills/late-arrival/SKILL.md": skillMd("late-arrival", "five words in this description") });
    const a = persistArgs(w, v);
    expect(await runCreatePersistStep(a)).toEqual({ kind: "opened", pr: 77 });
    const body = String((a.safeCommit.mock.calls[0][0] as unknown as { prBody: string }).prBody);
    expect(body).toContain(`Budget headroom before this skill: ${v.headroom - 5} words (total ${v.total + 5}, cap ${v.cap}).`);
    expect(body).not.toContain(`(total ${v.total}, cap`);
  });

  it("(c) an orphan branch on the remote (pushed, PR never opened) is persist/branch-exists: named, mirrored, NOT deleted, no commit", async () => {
    const w = world();
    const v = await propose(w);
    const branch = `self-healing/auto-${v.clusterHash}-2026-10-26`;
    w.rgit(["branch", branch]);
    const a = persistArgs(w, v);
    vi.mocked(reportSilentFallback).mockClear();
    expect(await runCreatePersistStep(a)).toEqual({ kind: "refused", class: "persist", detail: "branch-exists" });
    expect(a.safeCommit).not.toHaveBeenCalled();
    expect(vi.mocked(reportSilentFallback)).toHaveBeenCalledWith(null, expect.objectContaining({ op: "create-refused", tags: { class: "persist" }, extra: expect.objectContaining({ detail: "branch-exists" }) }));
    expect(w.rgit(["branch", "--list", branch])).toContain(branch); // the arm never deletes a remote branch
    expect(w.config()).not.toContain("x-access-token");
  });

  it("(c) harness: a remote WITHOUT the branch proceeds to the commit, and the probe runs with the token on (the remote is private)", async () => {
    const w = world();
    const v = await propose(w);
    const a = persistArgs(w, v);
    expect(await runCreatePersistStep(a)).toEqual({ kind: "opened", pr: 77 });
    expect(a.safeCommit).toHaveBeenCalledTimes(1);
  });

  it("(d) a pattern list that lacks the verdict's pattern is persist/page-missing, MIRRORED, before any request or write", async () => {
    const w = world();
    const v = await propose(w);
    const request = vi.fn(async () => ({ data: [] }));
    const a = persistArgs(w, v, { patterns: [], octokit: { request, graphql: async () => ({}) } });
    vi.mocked(reportSilentFallback).mockClear();
    expect(await runCreatePersistStep(a)).toEqual({ kind: "refused", class: "persist", detail: "page-missing" });
    expect(request).not.toHaveBeenCalled();
    expect(h.scan).not.toHaveBeenCalled();
    expect(vi.mocked(reportSilentFallback)).toHaveBeenCalledWith(null, expect.objectContaining({ op: "create-refused", tags: { class: "persist" } }));
  });

  it("(d) recheck-mismatch: a verdict whose cluster hash is well-formed but not the page's is refused persist/recheck-mismatch; nothing rendered, no commit", async () => {
    const w = world();
    const v = await propose(w);
    const a = persistArgs(w, { ...v, clusterHash: "f".repeat(64) });
    expect(await runCreatePersistStep(a)).toEqual({ kind: "refused", class: "persist", detail: "recheck-mismatch" });
    expect(h.scan).not.toHaveBeenCalled();
    expect(a.safeCommit).not.toHaveBeenCalled();
    expect(w.config()).not.toContain("x-access-token");
  });
});

// ---------------------------------------------------------------------------------------------------------
describe("G9 -- the stage order, the deadline checkpoints, the commit config, the evidence count, the `since` baseline", () => {
  let gw: GitWrapper;
  beforeEach(() => {
    gw = installGitWrapper();
  });
  afterEach(() => gw.restore());

  /** Run Step B with every observable event on ONE time-ordered stream: the octokit lookup, the origin writes, the three doubles and every git call. */
  async function observed(over: Record<string, unknown> = {}) {
    const w = world();
    const v = await propose(w);
    h.scan.mockImplementation(async () => (gw.mark("scan"), { ok: true }));
    h.sync.mockImplementation(async (o: { repoRoot: string }) => (gw.mark("readme-sync"), bumpReadmes(o.repoRoot), { ok: true }));
    const a = persistArgs(w, v, {
      now: gw.now,
      octokit: { request: async () => (gw.mark("branch-taken"), { data: [] }), graphql: async () => ({}) },
      setOrigin: async (root: string, token: string) => (gw.mark("setOrigin"), setOriginToken(root, token)),
      ...over,
    });
    const commit = a.safeCommit;
    a.safeCommit = vi.fn(async (cfg: unknown) => (gw.mark("commit"), commit(cfg as never))) as never;
    const result = await runCreatePersistStep(a);
    return { w, v, a, result, events: gw.events() };
  }

  /** Map the event stream to CREATE_STAGE_ORDER ids. Everything outside the step body (the clean-main restores, the final strip) maps to nothing. */
  function stagesOf(events: readonly string[]): string[] {
    const stages: string[] = [];
    let fetches = 0;
    let setOrigins = 0;
    let internalSetUrl = false;
    for (const ev of events) {
      if (ev === "branch-taken") stages.push("branch-taken");
      else if (ev === "setOrigin") {
        setOrigins += 1;
        stages.push(setOrigins === 1 ? "token-set" : "token-restore");
        internalSetUrl = true; // the `set-url` setOriginToken performs is part of this stage
      } else if (ev === "set-url") {
        if (internalSetUrl) internalSetUrl = false;
        else if (fetches === 1) stages.push("token-strip");
      } else if (ev === "fetch") {
        fetches += 1;
        stages.push(fetches === 1 ? "fetch-reset" : "fetch");
      } else if (fetches === 1 && (ev === "reset" || ev === "rev-parse")) stages.push("fetch-reset");
      else if (fetches === 2 && ev === "rev-parse") stages.push("base-moved");
      else if (fetches === 2 && ev === "ls-tree") stages.push("slug-appeared");
      else if (fetches === 2 && ev === "ls-remote") stages.push("branch-exists");
      else if (ev === "scan" || ev === "readme-sync") stages.push(ev);
      else if (ev === "commit") {
        stages.push("commit");
        break;
      }
    }
    return stages.filter((id, i) => id !== stages[i - 1]);
  }

  it("the stages the arm PERFORMS, in order, are CREATE_STAGE_ORDER.stepB (minus the four pure stages no double can see)", async () => {
    const { result, events } = await observed();
    expect(result).toEqual({ kind: "opened", pr: 77 });
    const PURE = new Set(["recheck", "render", "rendered-gate", "bytes-differ"]);
    expect(stagesOf(events)).toEqual(CREATE_STAGE_ORDER.stepB.filter((id) => !PURE.has(id)));
  });

  it("the commit helper receives the WHOLE config: run start (memoized, not now), trailer, labels, draft, merge mode, checks, summary", async () => {
    const w = world();
    const v = await propose(w);
    const RUN = "2025-01-02T03:04:05.000Z"; // not today: a fresh Date would show
    const a = persistArgs(w, v, { runStartedAt: RUN });
    expect(await runCreatePersistStep(a)).toEqual({ kind: "opened", pr: 77 });
    const cfg = a.safeCommit.mock.calls[0][0] as unknown as Record<string, unknown>;
    const branch = `self-healing/auto-${v.clusterHash}-2025-01-02`;
    expect(cfg).toMatchObject({
      spawnCwd: w.clone,
      installationToken: "tok-synthetic",
      cronName: "cron-compound-promote",
      commitMessage: `chore(self-healing): create skill ${SLUG} from cluster ${v.clusterHash}`,
      allowedPaths: [],
      runStartedAt: RUN,
      scheduledIssueLabel: "scheduled-compound-promote",
      branchName: branch,
      prTitle: `self-healing(auto): promote cluster ${v.clusterHash} 2025-01-02`,
      prDraft: true,
      prLabels: ["self-healing/auto"],
      mergeMode: "none",
      syntheticChecks: { names: [...createSyntheticCheckNames()], summary: "self-healing/auto new-skill draft - operator review required" },
    });
    expect(String(cfg.commitBody)).toMatch(/^Bot-Author: compound-promotion-loop@\S+$/m);
    expect(String(cfg.commitBody).split("\n").slice(1)).toEqual([`Cluster-Hash: ${v.clusterHash}`, "Tier: skill", `Create-Skill: ${SLUG}`]);
    expect(String(cfg.prBody).split("\n")[0]).toBe("CREATE (new skill)");
  });

  it("the evidence count is the PAGE's: a 7-entry page writes n=7 to the promotion-log row and `7 evidence entries` to PURPOSE.md (not a constant)", async () => {
    const seven: PatternPage = { ...PATTERN, evidence: [1, 2, 3, 4, 5, 6, 7].map((n) => `knowledge-base/project/learnings/2026-10-0${n}-synthetic-${n}.md`) };
    const w = world();
    const counted = countDescriptionWords(join(w.clone, "plugins", "soleur"));
    if (!counted.ok) throw new Error(counted.detail);
    const merged: Record<string, unknown> = { ...structuredClone(PROPOSAL) };
    merged.nearest_skill = rankOverlap(proposalOverlapText({ slug: String(merged.slug), description: String(merged.description), when_to_use: merged.when_to_use as string[] }), counted.records)[0].name;
    const v = await runCreateProposeStep({
      repoRoot: w.clone, octokit: { request: async () => ({ data: [] }) } as never, patterns: [seven], ledgerEntries: [], runStartedAt: RUN_AT, capLeft: 1,
      apiKey: "k", runId: "R", scanOpenPrPaths: async () => ({ paths: [], incomplete: null }), post: poster(merged),
    });
    if (v.kind !== "create") throw new Error(JSON.stringify(v));
    const a = persistArgs(w, v, { patterns: [seven] });
    expect(await runCreatePersistStep(a)).toEqual({ kind: "opened", pr: 77 });
    const content = (a.safeCommit.mock.calls[0][0] as unknown as { expectedContent: Record<string, string> }).expectedContent;
    expect(content[PROMOTION_LOG_PATH]).toContain(`| ${v.clusterHash} | plugins/soleur/skills/${SLUG}/SKILL.md | 7 | pending | skill |`);
    expect(content[`plugins/soleur/skills/${SLUG}/PURPOSE.md`]).toContain("(7 evidence entries)");
  });

  it("the README sync gets the pre-scan clone snapshot as `since`: the new files and the log row at their gated hashes, and the scan-time write is NOT in it", async () => {
    const w = world();
    const v = await propose(w);
    const paths = createPathList(SLUG);
    let scanned = "";
    h.scan.mockImplementation(async (o: { repoRoot: string }) => {
      scanned = readFileSync(join(o.repoRoot, paths[1]), "utf8");
      writeFileSync(join(o.repoRoot, paths[1]), `${scanned}appended by the scanner\n`);
      return { ok: true };
    });
    const a = persistArgs(w, v);
    await runCreatePersistStep(a);
    const since = (h.sync.mock.calls[0][0] as { since: Map<string, string> }).since;
    expect(since).toBeInstanceOf(Map);
    const sha = (t: string) => createHash("sha256").update(t).digest("hex");
    expect(since.get(paths[1])).toBe(sha(scanned)); // the baseline predates the scanner's write
    for (const rel of [paths[0], paths[2], PROMOTION_LOG_PATH]) expect(since.has(rel), rel).toBe(true);
    expect(since.has(README)).toBe(false); // the READMEs are untouched at snapshot time
  });

  it("a resumed open (our own PR is already open) is logged, not silent, and never commits", async () => {
    const w = world();
    const v = await propose(w);
    const a = persistArgs(w, v, { octokit: { request: async () => ({ data: [{ number: 41, body: "CREATE (new skill)\nrest" }] }), graphql: async () => ({}) } });
    expect(await runCreatePersistStep(a)).toEqual({ kind: "opened", pr: 41 });
    expect(a.safeCommit).not.toHaveBeenCalled();
    expect((a.logger as unknown as { info: ReturnType<typeof vi.fn> }).info).toHaveBeenCalledWith(expect.objectContaining({ pr: 41 }), "create-resumed");
  });

  it("a deadline of zero ends the step at its first checkpoint: no origin write, no render, no scan", async () => {
    const w = world();
    const v = await propose(w);
    const setOrigin = vi.fn();
    const a = persistArgs(w, v, { now: gw.now, deadlineMs: 0, setOrigin });
    expect(await runCreatePersistStep(a)).toEqual({ kind: "refused", class: "persist", detail: "deadline" });
    expect(setOrigin).not.toHaveBeenCalled();
    expect(h.scan).not.toHaveBeenCalled();
  });

  // Each row kills the clock at ONE point and expects the NEXT checkpoint to fire and nothing after it to run, and the
  // refusal to NAME that checkpoint (`extra.stage`, a member of DEADLINE_STAGES).
  // (`set-url` #1 is the token write, #2 the strip; `status` #1 is the baseline snapshot; `ls-remote` is the last git call.)
  it.each([
    ["after the token strip, before the render and the file writes", () => gw.bumpOn("set-url", 2), { scan: 0, sync: 0, commit: 0, noGit: ["status"] }, "write"],
    ["after the baseline snapshot, before the scanner", () => gw.bumpOn("status", 1), { scan: 0, sync: 0, commit: 0, noGit: [] }, "scan"],
    ["after the scanner, before the README sync", () => h.scan.mockImplementation(async () => (writeFileSync(clockPath(), String(CLOCK_BIG)), { ok: true })), { scan: 1, sync: 0, commit: 0, noGit: [] }, "readme-sync"],
    ["after the README sync, before the second origin write", () => h.sync.mockImplementation(async (o: { repoRoot: string }) => (bumpReadmes(o.repoRoot), writeFileSync(clockPath(), String(CLOCK_BIG)), { ok: true })), { scan: 1, sync: 1, commit: 0, noGit: [] }, "final-fetch"],
    ["after the branch probe, before the commit", () => gw.bumpOn("ls-remote", 1), { scan: 1, sync: 1, commit: 0, noGit: [] }, "commit-guard"],
  ] as const)("deadline checkpoint: %s", async (_name, arrange, calls, stage) => {
    const w = world();
    const v = await propose(w);
    arrange();
    const a = persistArgs(w, v, { now: gw.now });
    expect(await runCreatePersistStep(a)).toEqual({ kind: "refused", class: "persist", detail: "deadline" });
    expect(vi.mocked(reportSilentFallback)).toHaveBeenCalledWith(null, expect.objectContaining({ op: "create-refused", extra: expect.objectContaining({ detail: "deadline", stage }) }));
    expect(DEADLINE_STAGES).toContain(stage);
    expect(h.scan).toHaveBeenCalledTimes(calls.scan);
    expect(h.sync).toHaveBeenCalledTimes(calls.sync);
    expect(a.safeCommit).toHaveBeenCalledTimes(calls.commit);
    for (const ev of calls.noGit) expect(gw.events(), `git ${ev} must not have run`).not.toContain(ev);
    expect(w.config()).not.toContain("x-access-token");
    expect(execFileSync("git", ["-C", w.clone, "status", "--porcelain", "-uall"], { env: cleanEnv(), encoding: "utf8" })).toBe("");
  });

  // A git call that FAILS because the budget ran out (the kill was ours) is the deadline, and says which call. One row per
  // git stage that has a deadline token; the clock jumps and the same call fails, so the deadline takes precedence over
  // the git refusal it would otherwise be.
  it.each([
    ["fetch", 1, "fetch"],
    ["reset", 2, "reset"], // reset #1 is the clean-main restore before the step proper
    ["rev-parse", 1, "blobs"],
    ["set-url", 2, "strip"],
    ["fetch", 2, "final-fetch"],
    ["rev-parse", 2, "final-blobs"],
    ["ls-tree", 1, "tree"],
    ["ls-remote", 1, "probe"],
  ] as const)("a failing git %s #%i with the budget gone is persist/deadline at stage %s (precedence over the git refusal)", async (ev, nth, stage) => {
    const w = world();
    const v = await propose(w);
    gw.bumpOn(ev, nth);
    gw.failOn(ev, nth);
    const a = persistArgs(w, v, { now: gw.now });
    expect(await runCreatePersistStep(a)).toEqual({ kind: "refused", class: "persist", detail: "deadline" });
    expect(vi.mocked(reportSilentFallback)).toHaveBeenCalledWith(null, expect.objectContaining({ op: "create-refused", extra: expect.objectContaining({ detail: "deadline", stage }) }));
    expect(a.safeCommit).not.toHaveBeenCalled();
    expect(w.config()).not.toContain("x-access-token");
  });

  it("every DEADLINE_STAGES token is the stage of some row above (the list has no dead entry, the rows no unlisted stage)", () => {
    const rows = ["write", "scan", "readme-sync", "final-fetch", "commit-guard", "fetch", "reset", "blobs", "strip", "final-fetch", "final-blobs", "tree", "probe"];
    expect([...new Set(rows)].sort()).toEqual([...DEADLINE_STAGES].sort());
  });

  it("OBS F3: git answering a blob read with the wrong shape (exit 0) is cause bad-output, not spawn, and carries no exit status", async () => {
    for (const nth of [1, 2]) {
      const w = world();
      const v = await propose(w);
      gw.failOn("rev-parse", nth, "garble");
      vi.mocked(reportSilentFallback).mockClear();
      const r = await runCreatePersistStep(persistArgs(w, v, { now: gw.now }));
      expect(r, `rev-parse #${nth}`).toEqual({ kind: "refused", class: "persist", detail: "blob-read-failed" });
      expect(vi.mocked(reportSilentFallback)).toHaveBeenCalledWith(null, expect.objectContaining({ op: "create-refused", extra: expect.objectContaining({ detail: "blob-read-failed", cause: "bad-output" }) }));
      expect(w.config()).not.toContain("x-access-token");
    }
  });

  it("budgetMs clamps each spawn to min(its own timeout, what is left): the scanner gets half of the budget, the sync the whole of it", async () => {
    const w = world();
    const v = await propose(w);
    await runCreatePersistStep(persistArgs(w, v, { now: gw.now, deadlineMs: 20_000 }));
    expect((h.scan.mock.calls[0][0] as { timeoutMs: number }).timeoutMs).toBe(10_000); // floor(20_000 / 2 files)
    expect((h.sync.mock.calls[0][0] as { timeoutMs: number }).timeoutMs).toBe(20_000); // min(30_000, 20_000)
    h.scan.mockClear();
    h.sync.mockClear();
    const w2 = world();
    await runCreatePersistStep(persistArgs(w2, await propose(w2), { now: gw.now, deadlineMs: 900_000 }));
    expect((h.scan.mock.calls[0][0] as { timeoutMs: number }).timeoutMs).toBe(SCAN_TIMEOUT_MS); // min(60_000, 450_000)
    expect((h.sync.mock.calls[0][0] as { timeoutMs: number }).timeoutMs).toBe(README_SYNC_TIMEOUT_MS); // min(30_000, 900_000)
  });
});

// ---------------------------------------------------------------------------------------------------------
describe("every git call of Step B that can fail refuses with ITS detail, the git exit status and a closed cause, and never commits", () => {
  let gw: GitWrapper;
  beforeEach(() => {
    gw = installGitWrapper();
  });
  afterEach(() => gw.restore());

  // `reset` #1 is the clean-main restore, #2 the refresh; `rev-parse` #1 reads the used blobs, #2 the moved ones;
  // `status` #1 is the baseline snapshot (its refusal carries no evidence of its own: the paired create-gate-git event does).
  it.each([
    ["reset", 1, "clone-not-clean", true],
    ["reset", 2, "reset-failed", true],
    ["rev-parse", 1, "blob-read-failed", true],
    ["rev-parse", 2, "blob-read-failed", true],
    ["ls-tree", 1, "tree-read-failed", true],
    ["ls-remote", 1, "branch-probe-failed", true],
    ["status", 1, "git-failed", false],
  ] as const)("git %s #%i failing is persist/%s", async (ev, nth, detail, carriesExit) => {
    const w = world();
    const v = await propose(w);
    gw.failOn(ev, nth);
    vi.mocked(reportSilentFallback).mockClear();
    const a = persistArgs(w, v, { now: gw.now });
    expect(await runCreatePersistStep(a)).toEqual({ kind: "refused", class: "persist", detail, ...(carriesExit ? { numbers: { exit_code: 128 } } : {}) });
    expect(a.safeCommit).not.toHaveBeenCalled();
    // the per-call event always names the subcommand and the exit; the refusal names the cause when it carries evidence
    expect(vi.mocked(reportSilentFallback)).toHaveBeenCalledWith(expect.objectContaining({ message: `git ${ev} failed` }), expect.objectContaining({ op: "create-gate-git", extra: expect.objectContaining({ sub: ev, exit: 128 }) }));
    if (carriesExit) {
      expect(vi.mocked(reportSilentFallback)).toHaveBeenCalledWith(null, expect.objectContaining({ op: "create-refused", extra: expect.objectContaining({ detail, cause: "exit128" }) }));
    }
    // (clone-not-clean fails before the step touched the origin, so the fixture clone's own token-named URL is still there)
    if (detail !== "clone-not-clean") expect(w.config()).not.toContain("x-access-token");
  });

  it("a git killed by a signal (not the timeout) is cause `signal`, with no exit status on the refusal", async () => {
    const w = world();
    const v = await propose(w);
    gw.failOn("ls-remote", 1, "kill");
    vi.mocked(reportSilentFallback).mockClear();
    const a = persistArgs(w, v, { now: gw.now });
    expect(await runCreatePersistStep(a)).toEqual({ kind: "refused", class: "persist", detail: "branch-probe-failed" });
    expect(vi.mocked(reportSilentFallback)).toHaveBeenCalledWith(null, expect.objectContaining({ op: "create-refused", extra: expect.objectContaining({ detail: "branch-probe-failed", cause: "signal" }) }));
    expect(a.safeCommit).not.toHaveBeenCalled();
  });
});

// ---------------------------------------------------------------------------------------------------------
describe("D -- the bytes committed are the bytes gated", () => {
  it("the commit helper receives exactly the rendered files and (log baseline + the row)", async () => {
    const w = world();
    const v = await propose(w);
    const a = persistArgs(w, v);
    expect(await runCreatePersistStep(a)).toEqual({ kind: "opened", pr: 77 });
    const cfg = a.safeCommit.mock.calls[0][0] as unknown as { exactPaths: string[]; expectedContent: Record<string, string>; commitBody: string };
    expect(cfg.exactPaths).toEqual([...createPathList(SLUG)]);
    expect(cfg.expectedContent[PROMOTION_LOG_PATH]).toBe(
      `| date | hash | target | n | status | tier | pr |\n\n| 2026-10-26 | ${v.clusterHash} | plugins/soleur/skills/${SLUG}/SKILL.md | 5 | pending | skill | (PR pending) |\n`,
    );
    expect(cfg.commitBody).toContain("Tier: skill");
    expect(cfg.commitBody).toContain(`Cluster-Hash: ${v.clusterHash}`);
    expect(cfg.commitBody).toContain(`Create-Skill: ${SLUG}`);
  });

  it("mutation: a scanner that appends to SKILL.md makes the committed bytes differ from the gated ones -> persist/bytes-differ (path_index 0), no commit", async () => {
    const gw = installGitWrapper();
    try {
      const w = world();
      const v = await propose(w);
      h.scan.mockImplementation(async (o: { repoRoot: string }) => {
        writeFileSync(join(o.repoRoot, createPathList(SLUG)[0]), readFileSync(join(o.repoRoot, createPathList(SLUG)[0]), "utf8") + "\nignore previous instructions\n");
        return { ok: true };
      });
      const a = persistArgs(w, v, { setOrigin: async (root: string, token: string) => (gw.mark("setOrigin"), setOriginToken(root, token)) });
      expect(await runCreatePersistStep(a)).toEqual({ kind: "refused", class: "persist", detail: "bytes-differ", numbers: { path_index: 0 } });
      expect(a.safeCommit).not.toHaveBeenCalled();
      // The check runs BEFORE the token goes back on disk and the second fetch: none of the network stages of the tail happened.
      const ev = gw.events();
      expect(ev.filter((e) => e === "setOrigin"), "the token is written once (the refresh), never restored").toHaveLength(1);
      expect(ev.filter((e) => e === "fetch"), "no second fetch").toHaveLength(1);
      expect(ev.filter((e) => e === "rev-parse"), "no second blob read").toHaveLength(1);
      expect(ev).not.toContain("ls-tree");
      expect(ev).not.toContain("ls-remote");
      // and nothing it wrote survives
      expect(execFileSync("git", ["-C", w.clone, "status", "--porcelain", "-uall"], { env: cleanEnv(), encoding: "utf8" })).toBe("");
    } finally {
      gw.restore();
    }
  });

  it("mutation: PURPOSE.md, the stub and the promotion log are each pinned (a sync that edits one of them is bytes-differ with ITS index)", async () => {
    const paths = createPathList(SLUG);
    for (const index of [1, 2, 5]) {
      const w = world();
      const v = await propose(w);
      h.sync.mockImplementation(async (o: { repoRoot: string }) => {
        bumpReadmes(o.repoRoot);
        writeFileSync(join(o.repoRoot, paths[index]), readFileSync(join(o.repoRoot, paths[index]), "utf8") + "tampered\n");
        return { ok: true };
      });
      expect(await runCreatePersistStep(persistArgs(w, v)), `index ${index}`).toEqual({ kind: "refused", class: "persist", detail: "bytes-differ", numbers: { path_index: index } });
    }
  });

  it("the scanner's refusal evidence rides the refusal numbers and the Sentry extra (signal name, missing tool names), never raw text", async () => {
    const w = world();
    const v = await propose(w);
    h.scan.mockResolvedValue({ ok: false, detail: "missing-tool", missing: ["jq", "cut"] });
    const r = await runCreatePersistStep(persistArgs(w, v));
    expect(r).toEqual({ kind: "refused", class: "scan", detail: "missing-tool", numbers: { missing_tools: 2 } });
    expect(vi.mocked(reportSilentFallback)).toHaveBeenCalledWith(null, expect.objectContaining({ extra: expect.objectContaining({ missing_tool_names: ["jq", "cut"] }) }));
    h.scan.mockResolvedValue({ ok: false, detail: "non-zero", fileIndex: 1, exit: 3, signal: "SIGKILL" });
    const w2 = world();
    const r2 = await runCreatePersistStep(persistArgs(w2, await propose(w2)));
    expect(r2).toEqual({ kind: "refused", class: "scan", detail: "non-zero", numbers: { file_index: 1, exit_code: 3 } });
    expect(vi.mocked(reportSilentFallback)).toHaveBeenCalledWith(null, expect.objectContaining({ extra: expect.objectContaining({ signal: "SIGKILL" }) }));
    h.scan.mockResolvedValue({ ok: true });
    h.sync.mockResolvedValue({ ok: false, detail: "unexpected-change", changedCount: 2 });
    const w3 = world();
    expect(await runCreatePersistStep(persistArgs(w3, await propose(w3)))).toEqual({ kind: "refused", class: "readme-sync", detail: "unexpected-change", numbers: { changed_count: 2 } });
  });
});

// ---------------------------------------------------------------------------------------------------------
describe("G -- one deadline, a lost clone, a short-circuiting restore", () => {
  it("an exhausted deadline is persist/deadline at the next stage boundary (the scanner used the whole budget); nothing is committed", async () => {
    const w = world();
    const v = await propose(w);
    let clock = 1_000_000;
    h.scan.mockImplementation(async () => {
      clock += CREATE_PERSIST_DEADLINE_MS + 1; // the scanner ran past the one Step B deadline
      return { ok: true };
    });
    const a = persistArgs(w, v, { now: () => clock });
    expect(await runCreatePersistStep(a)).toEqual({ kind: "refused", class: "persist", detail: "deadline" });
    expect(h.sync).not.toHaveBeenCalled();
    expect(a.safeCommit).not.toHaveBeenCalled();
    expect(w.config()).not.toContain("x-access-token");
  });

  it("a gate timeout that happens because the budget ran out is attributed to the deadline, not to the scanner", async () => {
    const w = world();
    const v = await propose(w);
    let clock = 5_000;
    h.scan.mockImplementation(async () => {
      clock += CREATE_PERSIST_DEADLINE_MS + 5;
      return { ok: false, detail: "timeout", fileIndex: 0 };
    });
    expect(await runCreatePersistStep(persistArgs(w, v, { now: () => clock }))).toEqual({ kind: "refused", class: "persist", detail: "deadline" });
  });

  it("each spawn gets min(its own timeout, what is left): the scanner is handed half of a short remaining budget", async () => {
    const w = world();
    const v = await propose(w);
    await runCreatePersistStep(persistArgs(w, v, { deadlineMs: 20_000 }));
    const timeouts = h.scan.mock.calls.map((c) => (c[0] as { timeoutMs: number }).timeoutMs);
    expect(timeouts).toHaveLength(1);
    expect(timeouts[0]).toBeLessThanOrEqual(10_000);
    expect(timeouts[0]).toBeGreaterThan(0);
  });

  it("the restore short-circuits: a directory that is not a git repo costs ONE git call, not six", async () => {
    const dir = tmp("create-persist-notgit-");
    const w = world();
    const v = await propose(w);
    vi.mocked(reportSilentFallback).mockClear();
    const a = persistArgs(w, v, { repoRoot: dir });
    expect(await runCreatePersistStep(a)).toEqual({ kind: "refused", class: "persist", detail: "clone-not-clean", numbers: { exit_code: 128 } });
    const gitMirrors = vi.mocked(reportSilentFallback).mock.calls.filter((c) => (c[1] as { op: string }).op === "create-gate-git");
    expect(gitMirrors).toHaveLength(1);
  });

  it("a clone that vanishes between the two steps is persist/clone-missing", async () => {
    const w = world();
    const v = await propose(w);
    rmSync(w.clone, { recursive: true, force: true });
    const a = persistArgs(w, v);
    expect(await runCreatePersistStep(a)).toEqual({ kind: "refused", class: "persist", detail: "clone-missing" });
    expect(existsSync(w.clone)).toBe(false);
  });
});

// ---------------------------------------------------------------------------------------------------------
describe("JSON-plain step results (memoized, under the 1 MiB step output bound)", () => {
  const long = (seed: string, n: number): string => {
    let s = "";
    while (s.length < n) s += `${seed} `;
    return s.slice(0, n).trim();
  };

  it("the MAXIMUM-size verdict and every persist result (opened, resumed, refused with numbers) round-trip through JSON unchanged, far under 1 MiB", async () => {
    const w = world();
    const items = (seed: string) => Array.from({ length: CREATE_LIST_MAX_ITEMS }, (_, i) => `${long(`${seed}${"abcdef"[i]}`, CREATE_ITEM_MAX_CHARS - 1)}x`.slice(0, CREATE_ITEM_MAX_CHARS));
    const v = await propose(w, {
      patch_rejection_reason: long("Qlorem", CREATE_FIELD_MAX_CHARS), when_to_use: items("Wzz"), steps: items("Szz"), sharp_edges: items("Ezz"), merge_retire_candidates: items("Mzz"),
    });
    const opened = await runCreatePersistStep(persistArgs(w, v));
    const refused = await runCreatePersistStep(persistArgs(world(), v, { verdict: { ...v, clusterHash: "NOT-A-HASH" } }));
    for (const r of [v, opened, refused, { kind: "opened", pr: 9 }]) {
      expect(JSON.parse(JSON.stringify(r))).toEqual(r);
      expect(Buffer.byteLength(JSON.stringify(r), "utf8")).toBeLessThan(1024 * 1024);
    }
    expect(Buffer.byteLength(JSON.stringify(v), "utf8")).toBeGreaterThan(4000); // the proposal really is large
  });
});
