// #10552 -- the skill-conflict guard: a skill-targeting cluster is refused only when an open PR
// changes THE SAME FILE, and a scan that hit a bound without finding it is never "clear".
//
// Table-driven unit tests of `scanOpenPrSkillPaths` (one run-wide scan over the open PRs' file
// lists) and `skillConflictVerdict` (the only place a verdict is made). The fake octokit records
// every `(route, params)`, so a request to anything but the two literal routes fails a row.
import { describe, expect, it, vi } from "vitest";

vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});
vi.mock("@/server/observability", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/observability")>()),
  reportSilentFallback: vi.fn(),
}));

import {
  SKILL_GUARD_FILE_PAGES_PER_PR,
  SKILL_GUARD_FILE_REQUEST_BUDGET,
  SKILL_GUARD_PR_PAGES,
  scanOpenPrSkillPaths,
  skillConflictVerdict,
} from "@/server/inngest/functions/cron-compound-promote";

const PULLS = "GET /repos/{owner}/{repo}/pulls";
const FILES = "GET /repos/{owner}/{repo}/pulls/{pull_number}/files";
const PAGE = 100;

const ALPHA = "plugins/soleur/skills/alpha/SKILL.md";
const BETA = "plugins/soleur/skills/beta/SKILL.md";

type Pr = {
  number: number;
  user?: { login: string } | null;
  /** The PR's changed files, in list order. */
  files?: Array<{ filename: string; previous_filename?: string }>;
};

type Call = { route: string; params: Record<string, unknown> };

/**
 * A fake octokit over a list of open PRs. `files` for a PR is served in pages of 100. A request
 * for a route other than the two literal ones, or with the wrong shape, throws: the row that
 * caused it fails by name rather than by an unrelated assertion.
 */
function fake(prs: Pr[], opts: { fileFor?: (pr: Pr, page: number) => unknown } = {}) {
  const calls: Call[] = [];
  const request = async (route: string, params: Record<string, unknown>) => {
    calls.push({ route, params });
    if (route === PULLS) {
      if (params.state !== "open" || params.per_page !== PAGE || typeof params.page !== "number") {
        throw new Error(`unexpected pulls params: ${JSON.stringify(params)}`);
      }
      const start = (params.page - 1) * PAGE;
      return { data: prs.slice(start, start + PAGE).map((p) => ({ number: p.number, user: p.user === undefined ? { login: "someone" } : p.user })) };
    }
    if (route === FILES) {
      if (params.per_page !== PAGE || typeof params.page !== "number" || typeof params.pull_number !== "number") {
        throw new Error(`unexpected files params: ${JSON.stringify(params)}`);
      }
      const pr = prs.find((p) => p.number === params.pull_number);
      if (!pr) throw new Error(`no such PR ${String(params.pull_number)}`);
      if (opts.fileFor) return { data: opts.fileFor(pr, params.page) };
      const start = (params.page - 1) * PAGE;
      return { data: (pr.files ?? []).slice(start, start + PAGE) };
    }
    throw new Error(`unexpected route ${route}`);
  };
  return { octokit: { request } as unknown as Parameters<typeof scanOpenPrSkillPaths>[0]["octokit"], calls };
}

const scan = (prs: Pr[], targets: string[], opts?: Parameters<typeof fake>[1]) => {
  const f = fake(prs, opts);
  return scanOpenPrSkillPaths({ octokit: f.octokit, owner: "o", repo: "r", targets }).then((s) => ({ s, calls: f.calls }));
};

const count = (calls: Call[], route: string) => calls.filter((c) => c.route === route).length;

/** `n` filler files that match no target. */
const filler = (n: number, tag = "f") => Array.from({ length: n }, (_, i) => ({ filename: `docs/${tag}-${i}.md` }));

describe("the guard decides on the FILE, not on the words of a PR", () => {
  it("different-file: the live #10812 shape (a Dependabot bump of requirements.txt) is clear", async () => {
    const prs: Pr[] = [
      { number: 10812, user: { login: "dependabot[bot]" }, files: [{ filename: "plugins/soleur/skills/gemini-imagegen/requirements.txt" }] },
    ];
    const { s, calls } = await scan(prs, [ALPHA]);
    expect(s).toEqual({ changed: {}, incomplete: null });
    expect(skillConflictVerdict(s, ALPHA)).toEqual({ kind: "clear" });
    // Dependabot is skipped for call saving: its file list is never fetched.
    expect(count(calls, FILES)).toBe(0);
  });

  it("different-file: a human PR in the same skills directory but another file is clear", async () => {
    const { s } = await scan([{ number: 1, files: [{ filename: BETA }] }], [ALPHA]);
    expect(skillConflictVerdict(s, ALPHA)).toEqual({ kind: "clear" });
  });

  it("a prefix-lookalike path is clear (equality, not startsWith/includes)", async () => {
    const lookalikes = [`${ALPHA}.orig`, `x/${ALPHA}`, `${ALPHA}/more`];
    const { s } = await scan([{ number: 2, files: lookalikes.map((filename) => ({ filename })) }], [ALPHA]);
    expect(s.changed).toEqual({});
    expect(skillConflictVerdict(s, ALPHA)).toEqual({ kind: "clear" });
  });

  it("same-file: an open PR that changes the target conflicts, naming the PR", async () => {
    const { s } = await scan([{ number: 77, files: [{ filename: ALPHA }] }], [ALPHA]);
    expect(skillConflictVerdict(s, ALPHA)).toEqual({ kind: "conflict", pr: 77 });
  });

  it("same-file via a rename: previous_filename counts", async () => {
    const { s } = await scan([{ number: 78, files: [{ filename: "plugins/soleur/skills/moved/SKILL.md", previous_filename: ALPHA }] }], [ALPHA]);
    expect(skillConflictVerdict(s, ALPHA)).toEqual({ kind: "conflict", pr: 78 });
  });

  it("same-file on the SECOND files page of a PR conflicts", async () => {
    const files = [...filler(PAGE), { filename: ALPHA }];
    const { s, calls } = await scan([{ number: 31, files }], [ALPHA]);
    expect(skillConflictVerdict(s, ALPHA)).toEqual({ kind: "conflict", pr: 31 });
    expect(calls.filter((c) => c.route === FILES).map((c) => c.params.page)).toEqual([1, 2]);
  });

  it("the scan does not stop at the first PR: a same-file PR listed second still conflicts", async () => {
    const prs: Pr[] = [
      { number: 1, files: [{ filename: BETA }] },
      { number: 2, files: [{ filename: ALPHA }] },
    ];
    const { s } = await scan(prs, [ALPHA]);
    expect(skillConflictVerdict(s, ALPHA)).toEqual({ kind: "conflict", pr: 2 });
  });

  it("only dependabot[bot] is skipped: the App's own bot PR on the same file conflicts", async () => {
    const { s } = await scan([{ number: 3, user: { login: "soleur-ai[bot]" }, files: [{ filename: ALPHA }] }], [ALPHA]);
    expect(skillConflictVerdict(s, ALPHA)).toEqual({ kind: "conflict", pr: 3 });
  });

  it("a Dependabot PR that does change the target is skipped (call saving), not a conflict", async () => {
    const { s, calls } = await scan([{ number: 4, user: { login: "dependabot[bot]" }, files: [{ filename: ALPHA }] }], [ALPHA]);
    expect(skillConflictVerdict(s, ALPHA)).toEqual({ kind: "clear" });
    expect(count(calls, FILES)).toBe(0);
  });

  it("a PR whose author is null (deleted account) does not throw", async () => {
    const { s } = await scan([{ number: 5, user: null, files: [{ filename: ALPHA }] }], [ALPHA]);
    expect(skillConflictVerdict(s, ALPHA)).toEqual({ kind: "conflict", pr: 5 });
  });

  it("no open PR at all is clear after a single request", async () => {
    const { s, calls } = await scan([], [ALPHA]);
    expect(s).toEqual({ changed: {}, incomplete: null });
    expect(calls).toHaveLength(1);
  });
});

describe("the result is bounded and replay-safe", () => {
  it("records only the requested targets, and the first PR to change one wins", async () => {
    const big = [...filler(PAGE - 2, "a"), { filename: ALPHA }, { filename: "plugins/soleur/skills/unrequested/SKILL.md" }];
    const prs: Pr[] = [
      { number: 10, files: big },
      { number: 11, files: [{ filename: ALPHA }, { filename: BETA }] },
    ];
    const { s } = await scan(prs, [ALPHA, BETA]);
    expect(s.changed).toEqual({ [ALPHA]: 10, [BETA]: 11 });
    expect(Object.keys(s.changed).length).toBeLessThanOrEqual(2);
  });

  it("a 1000-file PR yields at most one entry per target", async () => {
    const files = [...filler(998), { filename: ALPHA }, { filename: BETA }];
    const { s } = await scan([{ number: 12, files }], [ALPHA]);
    expect(s.changed).toEqual({ [ALPHA]: 12 });
  });

  it("survives a JSON round trip, and a target named like an Object.prototype member is never a conflict", async () => {
    const { s } = await scan([{ number: 13, files: [{ filename: ALPHA }] }], [ALPHA, "constructor", "__proto__", "toString"]);
    const replayed = JSON.parse(JSON.stringify(s)) as typeof s;
    expect(skillConflictVerdict(replayed, ALPHA)).toEqual({ kind: "conflict", pr: 13 });
    for (const name of ["constructor", "__proto__", "toString", "hasOwnProperty"]) {
      expect(skillConflictVerdict(replayed, name)).toEqual({ kind: "clear" });
    }
  });

  it("stops requesting once every target is found", async () => {
    const prs: Pr[] = Array.from({ length: 5 }, (_, i) => ({ number: i + 1, files: [{ filename: i === 0 ? ALPHA : BETA }] }));
    const { s, calls } = await scan(prs, [ALPHA]);
    expect(s.changed).toEqual({ [ALPHA]: 1 });
    expect(count(calls, PULLS)).toBe(1);
    expect(count(calls, FILES)).toBe(1);
  });

  it("makes only the two literal routes, with state open, per_page 100 and an incrementing page", async () => {
    const prs: Pr[] = Array.from({ length: PAGE + 1 }, (_, i) => ({ number: i + 1, files: filler(1) }));
    const { calls } = await scan(prs, [ALPHA]);
    const pulls = calls.filter((c) => c.route === PULLS);
    expect(pulls.map((c) => c.params.page)).toEqual([1, 2]);
    for (const c of calls) {
      expect([PULLS, FILES]).toContain(c.route);
      expect(c.params).toMatchObject({ owner: "o", repo: "r", per_page: PAGE });
    }
    expect(calls.some((c) => c.route.startsWith("POST") || c.route.includes("search"))).toBe(false);
  });
});

describe("a bound reached without a match is unverifiable, never clear", () => {
  it("prs: three full pages of PRs", async () => {
    const prs: Pr[] = Array.from({ length: SKILL_GUARD_PR_PAGES * PAGE }, (_, i) => ({ number: i + 1, user: { login: "dependabot[bot]" } }));
    const { s, calls } = await scan(prs, [ALPHA]);
    expect(s.incomplete).toBe("prs");
    expect(count(calls, PULLS)).toBe(SKILL_GUARD_PR_PAGES);
    expect(skillConflictVerdict(s, ALPHA)).toEqual({ kind: "unverifiable", bound: "prs" });
  });

  it("files: one PR whose file list fills every page (the fake answers a full page forever)", async () => {
    const { s, calls } = await scan([{ number: 20 }], [ALPHA], { fileFor: () => filler(PAGE) });
    expect(s.incomplete).toBe("files");
    expect(count(calls, FILES)).toBe(SKILL_GUARD_FILE_PAGES_PER_PR);
    expect(skillConflictVerdict(s, ALPHA)).toEqual({ kind: "unverifiable", bound: "files" });
  });

  it("requests: the run-wide file-list budget runs out", async () => {
    const prs: Pr[] = Array.from({ length: SKILL_GUARD_FILE_REQUEST_BUDGET + 20 }, (_, i) => ({ number: i + 1, files: filler(1) }));
    const { s, calls } = await scan(prs, [ALPHA]);
    expect(s.incomplete).toBe("requests");
    expect(count(calls, FILES)).toBe(SKILL_GUARD_FILE_REQUEST_BUDGET);
    expect(skillConflictVerdict(s, ALPHA)).toEqual({ kind: "unverifiable", bound: "requests" });
  });

  it("the first bound reached wins: files before requests", async () => {
    const prs: Pr[] = [{ number: 1 }, ...Array.from({ length: SKILL_GUARD_FILE_REQUEST_BUDGET + 5 }, (_, i) => ({ number: i + 2, files: filler(1) }))];
    const { s } = await scan(prs, [ALPHA], { fileFor: (pr) => (pr.number === 1 ? filler(PAGE) : filler(1)) });
    expect(s.incomplete).toBe("files");
  });

  it("a match found after a bound was hit is not lost, and a conflict outranks the bound", async () => {
    const prs: Pr[] = [{ number: 1 }, { number: 2, files: [{ filename: ALPHA }] }];
    const { s } = await scan(prs, [ALPHA], { fileFor: (pr, page) => (pr.number === 1 ? filler(PAGE) : (pr.files ?? []).slice((page - 1) * PAGE, page * PAGE)) });
    expect(s.incomplete).toBe("files");
    expect(s.changed).toEqual({ [ALPHA]: 2 });
    expect(skillConflictVerdict(s, ALPHA)).toEqual({ kind: "conflict", pr: 2 });
  });

  it("an incomplete scan is unverifiable for a target it did not find, conflict for one it did", async () => {
    const prs: Pr[] = [{ number: 1 }, { number: 2, files: [{ filename: ALPHA }] }];
    const { s } = await scan(prs, [ALPHA, BETA], { fileFor: (pr, page) => (pr.number === 1 ? filler(PAGE) : (pr.files ?? []).slice((page - 1) * PAGE, page * PAGE)) });
    expect(skillConflictVerdict(s, ALPHA)).toEqual({ kind: "conflict", pr: 2 });
    expect(skillConflictVerdict(s, BETA)).toEqual({ kind: "unverifiable", bound: "files" });
  });
});

describe("fail closed on an API fault", () => {
  it("a pulls request error rejects", async () => {
    const octokit = { request: async () => { throw new Error("HTTP 502"); } } as unknown as Parameters<typeof scanOpenPrSkillPaths>[0]["octokit"];
    await expect(scanOpenPrSkillPaths({ octokit, owner: "o", repo: "r", targets: [ALPHA] })).rejects.toThrow("HTTP 502");
  });

  it("a files request error rejects (no try/catch that returns an empty scan)", async () => {
    const f = fake([{ number: 1 }], { fileFor: () => { throw new Error("HTTP 500"); } });
    await expect(scanOpenPrSkillPaths({ octokit: f.octokit, owner: "o", repo: "r", targets: [ALPHA] })).rejects.toThrow("HTTP 500");
  });

  it("a non-array pulls payload rejects with a fixed string that never echoes the payload", async () => {
    const octokit = { request: async () => ({ data: { message: "SECRET-PAYLOAD-TEXT" } }) } as unknown as Parameters<typeof scanOpenPrSkillPaths>[0]["octokit"];
    const err = await scanOpenPrSkillPaths({ octokit, owner: "o", repo: "r", targets: [ALPHA] }).then(
      () => null,
      (e: unknown) => e as Error,
    );
    expect(err).toBeInstanceOf(Error);
    expect(err!.message).not.toContain("SECRET-PAYLOAD-TEXT");
  });

  it("a non-array files payload rejects", async () => {
    const f = fake([{ number: 1 }], { fileFor: () => ({ message: "nope" }) });
    await expect(scanOpenPrSkillPaths({ octokit: f.octokit, owner: "o", repo: "r", targets: [ALPHA] })).rejects.toThrow();
  });
});

describe("skillConflictVerdict", () => {
  it("clear / conflict / unverifiable, and a conflict outranks an incomplete scan", () => {
    expect(skillConflictVerdict({ changed: {}, incomplete: null }, ALPHA)).toEqual({ kind: "clear" });
    expect(skillConflictVerdict({ changed: { [ALPHA]: 9 }, incomplete: null }, ALPHA)).toEqual({ kind: "conflict", pr: 9 });
    expect(skillConflictVerdict({ changed: {}, incomplete: "requests" }, ALPHA)).toEqual({ kind: "unverifiable", bound: "requests" });
    expect(skillConflictVerdict({ changed: { [ALPHA]: 9 }, incomplete: "prs" }, ALPHA)).toEqual({ kind: "conflict", pr: 9 });
  });
});
