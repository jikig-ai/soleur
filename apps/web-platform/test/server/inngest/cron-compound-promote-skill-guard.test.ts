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
  SKILL_GUARD_DEADLINE_MS,
  SKILL_GUARD_FILE_PAGES_PER_PR,
  SKILL_GUARD_FILE_REQUEST_BUDGET,
  SKILL_GUARD_PR_PAGES,
  SKILL_GUARD_REQUEST_TIMEOUT_MS,
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

const scan = (prs: Pr[], targets: string[], opts?: Parameters<typeof fake>[1] & { now?: () => number }) => {
  const f = fake(prs, opts);
  return scanOpenPrSkillPaths({ octokit: f.octokit, owner: "o", repo: "r", targets, now: opts?.now }).then((s) => ({ s, calls: f.calls }));
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
    expect(s).toEqual({ changed: {}, incomplete: null, scanned: [ALPHA] });
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
    expect(s).toEqual({ changed: {}, incomplete: null, scanned: [ALPHA] });
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
    for (const name of ["constructor", "__proto__", "toString"]) {
      expect(skillConflictVerdict(replayed, name)).toEqual({ kind: "clear" });
    }
    // Never scanned: unverifiable, and still never a conflict from the prototype chain.
    expect(skillConflictVerdict(replayed, "hasOwnProperty")).toEqual({ kind: "unverifiable", bound: "targets" });
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

describe("a PARTIAL last page is not a bound (the bounds fire only on a full final page)", () => {
  it("250 open PRs (two full pages and a partial third) scan clean", async () => {
    const prs: Pr[] = Array.from({ length: 250 }, (_, i) => ({ number: i + 1, user: { login: "dependabot[bot]" } }));
    const { s, calls } = await scan(prs, [ALPHA]);
    expect(s.incomplete).toBeNull();
    expect(count(calls, PULLS)).toBe(3);
    expect(skillConflictVerdict(s, ALPHA)).toEqual({ kind: "clear" });
  });

  it("a PR with 950 files (nine full pages and a partial tenth) scans clean", async () => {
    const { s, calls } = await scan([{ number: 40, files: filler(950) }], [ALPHA]);
    expect(s.incomplete).toBeNull();
    expect(count(calls, FILES)).toBe(10);
  });

  it("exactly the request budget with no further PR scans clean", async () => {
    const prs: Pr[] = Array.from({ length: SKILL_GUARD_FILE_REQUEST_BUDGET }, (_, i) => ({ number: i + 1, files: filler(1) }));
    const { s, calls } = await scan(prs, [ALPHA]);
    expect(s.incomplete).toBeNull();
    expect(count(calls, FILES)).toBe(SKILL_GUARD_FILE_REQUEST_BUDGET);
  });

  it("trailing Dependabot PRs after the budget is spent are skipped, not counted as a bound", async () => {
    const humans: Pr[] = Array.from({ length: SKILL_GUARD_FILE_REQUEST_BUDGET }, (_, i) => ({ number: i + 1, files: filler(1) }));
    const bots: Pr[] = Array.from({ length: 5 }, (_, i) => ({ number: 1000 + i, user: { login: "dependabot[bot]" } }));
    const { s } = await scan([...humans, ...bots], [ALPHA]);
    expect(s.incomplete).toBeNull();
  });

  it("the request budget stops the PR list too: no further pulls page is read once it is spent", async () => {
    // Page 2 is FULL (200 PRs) and a third page exists, so only the outer break keeps the scan at 2 pulls pages.
    const prs: Pr[] = Array.from({ length: 2 * PAGE + 20 }, (_, i) => ({ number: i + 1, files: filler(1) }));
    const { s, calls } = await scan(prs, [ALPHA]);
    expect(count(calls, PULLS)).toBe(2);
    expect(s.incomplete).toBe("requests");
  });
});

describe("every request is bounded in time", () => {
  it("the per-request timeout is 20 s (a 0 or an hour-long bound is a regression)", () => {
    expect(SKILL_GUARD_REQUEST_TIMEOUT_MS).toBe(20_000);
  });

  it("each request gets its OWN fresh AbortSignal.timeout(20 s), on both routes", async () => {
    const spy = vi.spyOn(AbortSignal, "timeout");
    try {
      const prs: Pr[] = [{ number: 1, files: filler(1) }, { number: 2, files: filler(1) }];
      const { calls } = await scan(prs, [ALPHA]);
      expect(calls.length).toBeGreaterThanOrEqual(3);
      const signals = calls.map((c) => (c.params.request as { signal?: AbortSignal } | undefined)?.signal);
      for (const sig of signals) expect(sig).toBeInstanceOf(AbortSignal);
      // one shared signal would abort every later request after the first 20 s
      expect(new Set(signals).size).toBe(calls.length);
      expect(spy).toHaveBeenCalledTimes(calls.length);
      for (const call of spy.mock.calls) expect(call[0]).toBe(SKILL_GUARD_REQUEST_TIMEOUT_MS);
      // a live signal is not yet aborted at call time
      for (const sig of signals) expect(sig!.aborted).toBe(false);
    } finally {
      spy.mockRestore();
    }
  });
});

describe("the whole scan is bounded in time (bound `time`)", () => {
  const prs = (n: number): Pr[] => Array.from({ length: n }, (_, i) => ({ number: i + 1, files: filler(1) }));

  it("the deadline is two minutes", () => {
    expect(SKILL_GUARD_DEADLINE_MS).toBe(120_000);
  });

  it("a clock past the deadline stops the scan with bound `time`, unverifiable, never clear", async () => {
    let t = 1_000;
    const now = () => t;
    // Each request advances the clock by 50 s: the third file request starts past 120 s.
    const f = fake(prs(10));
    const wrapped = {
      request: async (route: string, params: Record<string, unknown>) => {
        t += 50_000;
        return (f.octokit as unknown as { request: (r: string, p: Record<string, unknown>) => Promise<unknown> }).request(route, params);
      },
    } as unknown as Parameters<typeof scanOpenPrSkillPaths>[0]["octokit"];
    const s = await scanOpenPrSkillPaths({ octokit: wrapped, owner: "o", repo: "r", targets: [ALPHA], now });
    expect(s.incomplete).toBe("time");
    expect(count(f.calls, FILES)).toBeLessThan(10);
    expect(skillConflictVerdict(s, ALPHA)).toEqual({ kind: "unverifiable", bound: "time" });
  });

  it("the PAGE-loop check also stops the scan: a full first pulls page, then a late clock, reads no second page", async () => {
    // reads: 1 deadline, 2 page-1 check, 3..102 one file-request check per PR, 103 page-2 check (late).
    let reads = 0;
    const { s, calls } = await scan(prs(120), [ALPHA], { now: () => (++reads <= 102 ? 0 : 1_000_000) });
    expect(s.incomplete).toBe("time");
    expect(count(calls, PULLS)).toBe(1);
    expect(count(calls, FILES)).toBe(PAGE);
  });

  it("the edge: a clock exactly AT the deadline is on time, one millisecond past it is not", async () => {
    let reads = 0;
    const atDeadline = await scan(prs(3), [ALPHA], { now: () => (++reads === 1 ? 0 : SKILL_GUARD_DEADLINE_MS) });
    expect(atDeadline.s.incomplete).toBeNull();
    reads = 0;
    const past = await scan(prs(3), [ALPHA], { now: () => (++reads === 1 ? 0 : SKILL_GUARD_DEADLINE_MS + 1) });
    expect(past.s.incomplete).toBe("time");
  });

  it("a scan that finishes inside the deadline is untouched", async () => {
    const { s } = await scan(prs(5), [ALPHA], { now: () => 1_000 });
    expect(s.incomplete).toBeNull();
  });

  it("a match found before the deadline still wins over a later `time` bound", async () => {
    // Clock reads 1-3 (deadline, first page, first PR's file request) are on time; later reads are past it.
    let reads = 0;
    const list: Pr[] = [{ number: 1, files: [{ filename: ALPHA }] }, ...prs(5)];
    const { s } = await scan(list, [ALPHA, BETA], { now: () => (++reads <= 3 ? 0 : 1_000_000) });
    expect(s.changed).toEqual({ [ALPHA]: 1 });
    expect(skillConflictVerdict(s, ALPHA)).toEqual({ kind: "conflict", pr: 1 });
    expect(skillConflictVerdict(s, BETA)).toEqual({ kind: "unverifiable", bound: "time" });
  });
});

describe("attacker-controlled names never reach the stored result", () => {
  it("hostile filenames, previous_filenames and logins leave only the target, an integer and the scanned list", async () => {
    const hostile = "evil\nname\u2028with-control-chars";
    const prs: Pr[] = [
      { number: 5, user: { login: hostile }, files: [{ filename: hostile, previous_filename: `${hostile}-old` }, { filename: ALPHA }] },
    ];
    const { s } = await scan(prs, [ALPHA]);
    expect(JSON.stringify(s)).not.toContain("evil");
    expect(s).toEqual({ changed: { [ALPHA]: 5 }, incomplete: null, scanned: [ALPHA] });
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
    expect(err!.message).toMatch(/pulls payload was not an array/);
    expect(err!.message).not.toContain("SECRET-PAYLOAD-TEXT");
  });

  it("a STRING pulls payload (iterable, not an array) is rejected rather than read as a list", async () => {
    const octokit = { request: async () => ({ data: "rate limited" }) } as unknown as Parameters<typeof scanOpenPrSkillPaths>[0]["octokit"];
    await expect(scanOpenPrSkillPaths({ octokit, owner: "o", repo: "r", targets: [ALPHA] })).rejects.toThrow(/pulls payload was not an array/);
  });

  it("a pull request without an integer number is rejected, even if the author would be skipped", async () => {
    for (const bad of [{}, { number: "7" }, { number: 1.5 }, { number: null, user: { login: "dependabot[bot]" } }]) {
      const octokit = { request: async () => ({ data: [bad] }) } as unknown as Parameters<typeof scanOpenPrSkillPaths>[0]["octokit"];
      await expect(scanOpenPrSkillPaths({ octokit, owner: "o", repo: "r", targets: [ALPHA] })).rejects.toThrow(/without a number/);
    }
  });

  it("a non-array files payload rejects", async () => {
    const f = fake([{ number: 1 }], { fileFor: () => ({ message: "nope" }) });
    await expect(scanOpenPrSkillPaths({ octokit: f.octokit, owner: "o", repo: "r", targets: [ALPHA] })).rejects.toThrow(/files payload was not an array/);
  });

  it("a STRING files payload is rejected, never read as an empty list (a silent clear)", async () => {
    const f = fake([{ number: 1 }], { fileFor: () => "rate limited" });
    await expect(scanOpenPrSkillPaths({ octokit: f.octokit, owner: "o", repo: "r", targets: [ALPHA] })).rejects.toThrow(/files payload was not an array/);
  });
});

describe("skillConflictVerdict", () => {
  const mk = (over: Partial<Parameters<typeof skillConflictVerdict>[0]>) => ({ changed: {}, incomplete: null, scanned: [ALPHA], ...over });

  it("clear / conflict / unverifiable, and a conflict outranks an incomplete scan", () => {
    expect(skillConflictVerdict(mk({}), ALPHA)).toEqual({ kind: "clear" });
    expect(skillConflictVerdict(mk({ changed: { [ALPHA]: 9 } }), ALPHA)).toEqual({ kind: "conflict", pr: 9 });
    expect(skillConflictVerdict(mk({ incomplete: "requests" }), ALPHA)).toEqual({ kind: "unverifiable", bound: "requests" });
    expect(skillConflictVerdict(mk({ changed: { [ALPHA]: 9 }, incomplete: "prs" }), ALPHA)).toEqual({ kind: "conflict", pr: 9 });
  });

  it("`targets` outranks an incomplete scan: the label names the first reason the target is unchecked", () => {
    expect(skillConflictVerdict(mk({ incomplete: "prs", scanned: [] }), ALPHA)).toEqual({ kind: "unverifiable", bound: "targets" });
  });

  it("a scan result without a `scanned` array (an older shape) is unverifiable, not a crash and not clear", () => {
    const old = { changed: {}, incomplete: null } as unknown as Parameters<typeof skillConflictVerdict>[0];
    expect(skillConflictVerdict(old, ALPHA)).toEqual({ kind: "unverifiable", bound: "targets" });
  });

  it("a target the scan was never asked about is unverifiable, never clear", () => {
    expect(skillConflictVerdict(mk({}), BETA)).toEqual({ kind: "unverifiable", bound: "targets" });
    expect(skillConflictVerdict(mk({ scanned: [] }), ALPHA)).toEqual({ kind: "unverifiable", bound: "targets" });
  });

  it("the scan records exactly the targets it was given", async () => {
    const { s } = await scan([], [ALPHA, BETA, ALPHA]);
    expect(s.scanned.sort()).toEqual([ALPHA, BETA]);
  });
});
