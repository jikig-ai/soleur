// TR9 Phase-2 — cron-cloud-task-heartbeat unit tests.
//
// Test coverage:
//   (a) Registration smoke test — import loads without throwing.
//   (b) Source-shape anchor tests — id, cron, event, concurrency, retries.
//   (c) Exported constant — TASK_INVENTORY (5 output-producing tasks).
//   (d) Handler behavior — never-produced grace + three-origin daysSince:null.
//
// INVENTORY SCOPE (see knowledge-base/engineering/operations/runbooks/cloud-scheduled-tasks.md):
// The heartbeat monitors ONLY scheduled tasks that UNCONDITIONALLY produce a
// `scheduled-<task>` issue artifact. Non-producers (daily-triage, ux-audit,
// bug-fixer) and the conditional producer strategy-review were removed because
// the label-presence signal can never reliably observe their output — their cron
// LIVENESS is covered by per-function Sentry monitors (#4708), not here.

import { beforeEach, describe, expect, it, vi } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

// --- Handler-behavior harness: spies + mocked deps (lazy-referenced in the
// factories so vitest's hoist of vi.mock above these consts is safe — same
// indirection pattern as cron-shared.test.ts). These mocks do not affect the
// import-time smoke / source-shape tests below (those read the SUT source via
// readFileSync and never execute the handler). ---
const reportSilentFallbackSpy = vi.fn();
const warnSilentFallbackSpy = vi.fn();
vi.mock("@/server/observability", () => ({
  reportSilentFallback: (...a: unknown[]) => reportSilentFallbackSpy(...a),
  warnSilentFallback: (...a: unknown[]) => warnSilentFallbackSpy(...a),
}));

const octokitRequestSpy = vi.fn();
vi.mock("@octokit/core", () => ({
  Octokit: class {
    request = (...a: unknown[]) => octokitRequestSpy(...a);
  },
}));

vi.mock("@/server/inngest/functions/_cron-shared", () => ({
  REPO_OWNER: "jikig-ai",
  REPO_NAME: "soleur",
  mintInstallationToken: vi.fn().mockResolvedValue("ghs_test_token"),
  postSentryHeartbeat: vi.fn().mockResolvedValue(undefined),
}));

import {
  cronCloudTaskHeartbeat,
  cronCloudTaskHeartbeatHandler,
  isStaleBotPr,
  scheduledLabelFromHead,
  STALE_BOT_PR_WARN_OP,
  TASK_INVENTORY,
  type BotPrLite,
} from "@/server/inngest/functions/cron-cloud-task-heartbeat";

// =============================================================================
// Registration smoke test
// =============================================================================

describe("cronCloudTaskHeartbeat — registration shape (import-time smoke)", () => {
  it("loads without throwing (handler + client startup pass)", () => {
    expect(cronCloudTaskHeartbeat).toBeDefined();
    expect(typeof cronCloudTaskHeartbeat).toBe("object");
  });
});

// =============================================================================
// Exported constants — TASK_INVENTORY
// =============================================================================

describe("cronCloudTaskHeartbeat — TASK_INVENTORY", () => {
  it("contains exactly 5 output-producing tasks", () => {
    expect(TASK_INVENTORY).toHaveLength(5);
  });

  it("every entry has name, label, and maxGapDays", () => {
    for (const task of TASK_INVENTORY) {
      expect(typeof task.name).toBe("string");
      expect(task.name.length).toBeGreaterThan(0);
      expect(typeof task.label).toBe("string");
      expect(task.label.length).toBeGreaterThan(0);
      expect(typeof task.maxGapDays).toBe("number");
      expect(task.maxGapDays).toBeGreaterThan(0);
    }
  });

  it("label is always `scheduled-` + name (guards future typos)", () => {
    for (const task of TASK_INVENTORY) {
      expect(task.label).toBe(`scheduled-${task.name}`);
    }
  });

  it.each([
    ["content-generator", "scheduled-content-generator", 9],
    ["legal-audit", "scheduled-legal-audit", 95],
    ["competitive-analysis", "scheduled-competitive-analysis", 40],
    ["community-monitor", "scheduled-community-monitor", 3],
    ["roadmap-review", "scheduled-roadmap-review", 9],
  ] as const)(
    "task %s has label %s and maxGapDays %d",
    (name, label, maxGapDays) => {
      const entry = TASK_INVENTORY.find((t) => t.name === name);
      expect(entry).toBeDefined();
      expect(entry!.label).toBe(label);
      expect(entry!.maxGapDays).toBe(maxGapDays);
    },
  );

  // Exclusion guard: none of these create a reliably-cadenced `scheduled-<task>`
  // issue, so the label-presence signal false-fires. daily-triage labels existing
  // issues only; ux-audit runs dry-run to Supabase/stdout; bug-fixer opens bot-fix
  // PRs (#4708 rationale). strategy-review is a CONDITIONAL/idempotent producer —
  // it opens an issue only per KB file needing review (title-dedup, skips
  // up_to_date), so quiet weeks legitimately yield zero issues; its liveness is
  // covered by the Sentry monitor scheduled-strategy-review (#4874). They must
  // NOT be in the inventory.
  it.each(["daily-triage", "ux-audit", "bug-fixer", "strategy-review"])(
    "non-producer %s is excluded from the inventory",
    (removed) => {
      expect(TASK_INVENTORY.find((t) => t.name === removed)).toBeUndefined();
    },
  );

  // Cadence-vs-threshold anchor: legal-audit runs quarterly
  // (`0 11 1 1,4,7,10 *`); the longest quarter gap (Jul 1 → Oct 1) is 92 days,
  // so its threshold MUST clear that floor or it false-fires every quarter.
  it("legal-audit threshold clears the quarterly (92-day) floor", () => {
    const legal = TASK_INVENTORY.find((t) => t.name === "legal-audit");
    expect(legal).toBeDefined();
    expect(legal!.maxGapDays).toBeGreaterThanOrEqual(92);
  });
});

// =============================================================================
// Source-shape anchor tests
// =============================================================================

const SUT_SOURCE = readFileSync(
  resolve(
    __dirname,
    "../../../server/inngest/functions/cron-cloud-task-heartbeat.ts",
  ),
  "utf-8",
);

describe("registration source-shape anchors (cross-check the import-time smoke)", () => {
  it.each([
    ['id: "cron-cloud-task-heartbeat"', "canonical function id"],
    ['cron: "30 9 * * *"', "daily at 09:30 UTC schedule"],
    ['event: "cron/cloud-task-heartbeat.manual-trigger"', "operator manual trigger"],
    ['scope: "fn"', "fn-scoped serialization"],
    ['scope: "account"', "account-shared lane (cron-platform)"],
    ['key: \'"cron-platform"\'', "cross-handler concurrency lane"],
    ["retries: 1", "no retry storm on heartbeat failure"],
  ])("source contains %s (%s)", (anchor) => {
    expect(SUT_SOURCE).toContain(anchor);
  });
});

describe("cron-cloud-task-heartbeat — Sentry monitor slug", () => {
  it("source contains the correct Sentry monitor slug", () => {
    expect(SUT_SOURCE).toContain('"scheduled-cloud-task-heartbeat"');
  });
});

describe("cron-cloud-task-heartbeat — key logic anchors", () => {
  it.each([
    ["[cloud-task-silence]", "silence issue title prefix"],
    ["cloud-task-silence", "issue label"],
    ["GET /repos/{owner}/{repo}/issues", "issues API endpoint"],
    ["#2714", "tracking issue reference"],
  ])("source contains %s (%s)", (anchor) => {
    expect(SUT_SOURCE).toContain(anchor);
  });
});

// =============================================================================
// Handler behavior — never-produced grace + three-origin daysSince:null
// =============================================================================
//
// Drives the exported handler with a pass-through `step.run`, a stub `logger`,
// and the file-level mocked `@octokit/core` / `_cron-shared` / observability.
// The Octokit dispatcher routes by request string; per-label issue specs let a
// single task be isolated while every other inventory task returns a fresh
// (within-threshold, non-pending) issue so it contributes no noise.

const RECENT_ISSUE = () => ({ created_at: new Date().toISOString() });
const OLD_ISSUE = () => ({
  created_at: new Date(Date.now() - 100 * 86400 * 1000).toISOString(),
});

type LabelSpec = {
  issues?: Array<{ created_at: string; number?: number }>;
  throw?: boolean;
};

/**
 * Optional bot-PR-watchdog overlays for the dispatcher. `pulls` is the
 * `GET …/pulls` page-1 payload (page ≥ 2 returns empty, matching the handler's
 * `length < per_page` break); `comments` maps an issue number to its existing
 * comment list for the dedup check; `pullsThrow` simulates a list-API failure.
 * Default (omitted) → no open bot PRs, so the watchdog steps no-op and existing
 * silence tests are unaffected.
 */
type WatchdogOpts = {
  pulls?: BotPrLite[];
  comments?: Record<number, Array<{ body?: string }>>;
  pullsThrow?: boolean;
};

/**
 * Build an Octokit `.request` dispatcher. `perLabel` overrides the issues
 * returned for specific `scheduled-<task>` labels; any label not listed returns
 * a single fresh issue (silent:false, not pending). `/search/issues` returns no
 * existing silence issue unless `existing` is provided. `opts` overlays the
 * bot-PR-watchdog routes (`…/pulls`, `…/comments`).
 */
function dispatcher(
  perLabel: Record<string, LabelSpec>,
  existing?: { number: number; matchTask: string },
  opts: WatchdogOpts = {},
) {
  return async (route: string, params: Record<string, unknown> = {}) => {
    if (route === "GET /repos/{owner}/{repo}/pulls") {
      if (opts.pullsThrow) throw new Error("GitHub 502 — simulated pulls list error");
      const page = (params.page as number | undefined) ?? 1;
      return { data: page === 1 ? (opts.pulls ?? []) : [] };
    }
    if (route === "GET /repos/{owner}/{repo}/issues/{issue_number}/comments") {
      return { data: opts.comments?.[params.issue_number as number] ?? [] };
    }
    if (route === "GET /repos/{owner}/{repo}/issues") {
      const spec = perLabel[params.labels as string] ?? { issues: [RECENT_ISSUE()] };
      if (spec.throw) throw new Error("GitHub 502 — simulated API error");
      return { data: spec.issues ?? [] };
    }
    if (route === "GET /search/issues") {
      // The handler's search query embeds `[cloud-task-silence] <task> silent`.
      // Return the stale issue ONLY for the targeted task so other tasks'
      // recovery branches don't comment on it.
      const match =
        existing && (params.q as string).includes(`${existing.matchTask} silent`);
      return { data: { items: match ? [{ number: existing!.number }] : [] } };
    }
    if (route === "POST /repos/{owner}/{repo}/issues") {
      return { data: { number: 9999 } };
    }
    // comment POSTs + PATCH close
    return { data: {} };
  };
}

/** Build a minimal open-PR payload for watchdog tests. */
function botPr(over: Partial<BotPrLite> & { number: number }): BotPrLite {
  return {
    number: over.number,
    head: over.head ?? { ref: `ci/content-publisher-2026-05-19-164226` },
    created_at:
      over.created_at ?? new Date(Date.now() - 100 * 3600 * 1000).toISOString(),
    draft: over.draft ?? false,
    labels: over.labels ?? [],
    html_url: over.html_url ?? `https://github.com/jikig-ai/soleur/pull/${over.number}`,
  };
}

function makeArgs() {
  return {
    step: { run: async (_name: string, fn: () => unknown) => fn() },
    logger: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
  } as unknown as Parameters<typeof cronCloudTaskHeartbeatHandler>[0];
}

describe("cronCloudTaskHeartbeatHandler — never-produced grace", () => {
  beforeEach(() => {
    octokitRequestSpy.mockReset();
    reportSilentFallbackSpy.mockReset();
    warnSilentFallbackSpy.mockReset();
  });

  it("zero issues ever → pending-first-run (silent:false), warns, files NO issue", async () => {
    octokitRequestSpy.mockImplementation(
      dispatcher({ "scheduled-legal-audit": { issues: [] } }),
    );

    const out = await cronCloudTaskHeartbeatHandler(makeArgs());

    const legal = out.results.find((r) => r.name === "legal-audit");
    expect(legal).toBeDefined();
    expect(legal!.silent).toBe(false);
    expect(legal!.daysSince).toBeNull();
    expect(out.silentCount).toBe(0);

    // warns at the pending-first-run op, exactly once (only legal-audit is empty)
    expect(warnSilentFallbackSpy).toHaveBeenCalledTimes(1);
    expect(warnSilentFallbackSpy.mock.calls[0][1].op).toBe("task-pending-first-run");
    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();

    // files NO new silence issue
    const posts = octokitRequestSpy.mock.calls.filter(
      (c) => c[0] === "POST /repos/{owner}/{repo}/issues",
    );
    expect(posts).toHaveLength(0);
  });

  it("pending-first-run with a stale open silence issue → auto-closes it with a null-safe comment", async () => {
    octokitRequestSpy.mockImplementation(
      dispatcher(
        { "scheduled-legal-audit": { issues: [] } },
        { number: 4875, matchTask: "legal-audit" },
      ),
    );

    await cronCloudTaskHeartbeatHandler(makeArgs());

    // recovery branch: comment + PATCH-close the stale issue for the pending task
    const comment = octokitRequestSpy.mock.calls.find(
      (c) =>
        c[0] === "POST /repos/{owner}/{repo}/issues/{issue_number}/comments" &&
        (c[1] as { issue_number?: number }).issue_number === 4875,
    );
    expect(comment).toBeDefined();
    const body = (comment![1] as { body: string }).body;
    expect(body).toContain("pending first run (never produced an issue)");
    expect(body).not.toContain("null days ago");

    const close = octokitRequestSpy.mock.calls.find(
      (c) =>
        c[0] === "PATCH /repos/{owner}/{repo}/issues/{issue_number}" &&
        (c[1] as { state?: string }).state === "closed",
    );
    expect(close).toBeDefined();
    // still NO new silence issue filed for a pending task
    expect(
      octokitRequestSpy.mock.calls.filter(
        (c) => c[0] === "POST /repos/{owner}/{repo}/issues",
      ),
    ).toHaveLength(0);
  });

  it("over-threshold issue → silent:true and files a silence issue (control)", async () => {
    octokitRequestSpy.mockImplementation(
      dispatcher({ "scheduled-content-generator": { issues: [OLD_ISSUE()] } }),
    );

    const out = await cronCloudTaskHeartbeatHandler(makeArgs());

    const cg = out.results.find((r) => r.name === "content-generator");
    expect(cg!.silent).toBe(true);
    expect(out.silentCount).toBe(1);
    expect(warnSilentFallbackSpy).not.toHaveBeenCalled();

    const posts = octokitRequestSpy.mock.calls.filter(
      (c) => c[0] === "POST /repos/{owner}/{repo}/issues",
    );
    expect(posts).toHaveLength(1);
  });

  it("issues query throws → reportSilentFallback(check-task), silent:true (error ≠ pending)", async () => {
    octokitRequestSpy.mockImplementation(
      dispatcher({ "scheduled-content-generator": { throw: true } }),
    );

    const out = await cronCloudTaskHeartbeatHandler(makeArgs());

    const cg = out.results.find((r) => r.name === "content-generator");
    expect(cg!.silent).toBe(true);
    expect(reportSilentFallbackSpy).toHaveBeenCalledTimes(1);
    expect(reportSilentFallbackSpy.mock.calls[0][1].op).toBe("check-task");
    // an API error is NOT a pending-first-run grace
    expect(warnSilentFallbackSpy).not.toHaveBeenCalled();
  });

  it("unparseable created_at → daysSince:null via NaN path, silent:true (corrupt ≠ pending)", async () => {
    octokitRequestSpy.mockImplementation(
      dispatcher({
        "scheduled-content-generator": { issues: [{ created_at: "not-a-date" }] },
      }),
    );

    const out = await cronCloudTaskHeartbeatHandler(makeArgs());

    const cg = out.results.find((r) => r.name === "content-generator");
    expect(cg!.silent).toBe(true);
    expect(cg!.daysSince).toBeNull();
    // the NaN-parse path is NOT the zero-rows grace and NOT an API error
    expect(warnSilentFallbackSpy).not.toHaveBeenCalled();
    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();
  });
});

// =============================================================================
// Stale bot-PR watchdog (#5138) — pure helpers
// =============================================================================

describe("scheduledLabelFromHead", () => {
  it.each([
    ["ci/content-publisher-2026-05-19-164226", "scheduled-content-publisher"],
    ["ci/rule-prune-2026-06-01-093000", "scheduled-rule-prune"],
    // digit/hyphen cron names survive the $-anchored timestamp strip
    ["ci/nag-4216-readiness-2026-06-01-120000", "scheduled-nag-4216-readiness"],
    // no timestamp suffix → whole rest becomes the label (Sentry-only fallback)
    ["ci/manual-rename", "scheduled-manual-rename"],
  ])("maps %s → %s", (head, label) => {
    expect(scheduledLabelFromHead(head)).toBe(label);
  });

  it.each([
    ["self-healing/auto-abc123-2026-06-01"],
    ["feature-foo"],
    ["bot-fix/123-something"],
  ])("returns null for non-ci head %s", (head) => {
    expect(scheduledLabelFromHead(head)).toBeNull();
  });
});

describe("isStaleBotPr", () => {
  const NOW = Date.UTC(2026, 5, 12, 0, 0, 0); // fixed clock
  const ago = (hours: number) => new Date(NOW - hours * 3600 * 1000).toISOString();

  it("47h59m-old ci/* PR is NOT stale (strict > 48h)", () => {
    expect(isStaleBotPr(botPr({ number: 1, created_at: ago(47.983) }), NOW)).toBe(false);
  });

  it("48h01m-old ci/* PR IS stale", () => {
    expect(isStaleBotPr(botPr({ number: 2, created_at: ago(48.017) }), NOW)).toBe(true);
  });

  it("non-bot head is never stale regardless of age", () => {
    expect(
      isStaleBotPr(
        botPr({ number: 3, head: { ref: "feature-foo" }, created_at: ago(100) }),
        NOW,
      ),
    ).toBe(false);
  });

  it("draft self-healing/auto PR is EXCLUDED (compound-promote human review)", () => {
    expect(
      isStaleBotPr(
        botPr({
          number: 4,
          head: { ref: "self-healing/auto-abc-2026-06-01" },
          draft: true,
          labels: [{ name: "self-healing/auto" }],
          created_at: ago(72),
        }),
        NOW,
      ),
    ).toBe(false);
  });

  it("NON-draft self-healing/auto PR IS stale (exclusion is draft AND label)", () => {
    expect(
      isStaleBotPr(
        botPr({
          number: 5,
          head: { ref: "self-healing/auto-abc-2026-06-01" },
          draft: false,
          labels: [{ name: "self-healing/auto" }],
          created_at: ago(72),
        }),
        NOW,
      ),
    ).toBe(true);
  });

  it("malformed created_at → not stale, does not throw", () => {
    expect(
      isStaleBotPr(botPr({ number: 6, created_at: "not-a-date" }), NOW),
    ).toBe(false);
  });
});

// =============================================================================
// Stale bot-PR watchdog (#5138) — handler behavior
// =============================================================================

describe("cronCloudTaskHeartbeatHandler — stale bot-PR watchdog", () => {
  beforeEach(() => {
    octokitRequestSpy.mockReset();
    reportSilentFallbackSpy.mockReset();
    warnSilentFallbackSpy.mockReset();
  });

  const stalePr = (over: Partial<BotPrLite> & { number: number }) =>
    botPr({ created_at: new Date(Date.now() - 100 * 3600 * 1000).toISOString(), ...over });

  it("a stale ci/* PR emits exactly one warn at op stale-bot-pr", async () => {
    octokitRequestSpy.mockImplementation(
      dispatcher({}, undefined, {
        pulls: [stalePr({ number: 4242, head: { ref: "ci/content-publisher-2026-05-19-164226" } })],
        // owning issue lookup returns none → Sentry-only, no comment POST
      }),
    );

    await cronCloudTaskHeartbeatHandler(makeArgs());

    const warnCalls = warnSilentFallbackSpy.mock.calls.filter(
      (c) => c[1].op === STALE_BOT_PR_WARN_OP,
    );
    expect(warnCalls).toHaveLength(1);
    expect(warnCalls[0][1].extra.pr_number).toBe(4242);
  });

  it("comments on the owning scheduled issue, deduped by marker", async () => {
    octokitRequestSpy.mockImplementation(
      dispatcher(
        { "scheduled-content-publisher": { issues: [{ created_at: RECENT_ISSUE().created_at, number: 777 }] } },
        undefined,
        {
          pulls: [stalePr({ number: 88, head: { ref: "ci/content-publisher-2026-05-19-164226" } })],
          comments: { 777: [] }, // no existing marker → one comment posted
        },
      ),
    );

    await cronCloudTaskHeartbeatHandler(makeArgs());

    const comment = octokitRequestSpy.mock.calls.find(
      (c) =>
        c[0] === "POST /repos/{owner}/{repo}/issues/{issue_number}/comments" &&
        (c[1] as { issue_number?: number }).issue_number === 777,
    );
    expect(comment).toBeDefined();
    expect((comment![1] as { body: string }).body).toContain("<!-- stale-bot-pr:88 -->");
  });

  it("skips the comment when the marker already exists (dedup)", async () => {
    octokitRequestSpy.mockImplementation(
      dispatcher(
        { "scheduled-content-publisher": { issues: [{ created_at: RECENT_ISSUE().created_at, number: 777 }] } },
        undefined,
        {
          pulls: [stalePr({ number: 88, head: { ref: "ci/content-publisher-2026-05-19-164226" } })],
          comments: { 777: [{ body: "earlier\n<!-- stale-bot-pr:88 -->\n" }] },
        },
      ),
    );

    await cronCloudTaskHeartbeatHandler(makeArgs());

    const posted = octokitRequestSpy.mock.calls.filter(
      (c) => c[0] === "POST /repos/{owner}/{repo}/issues/{issue_number}/comments",
    );
    // only the existing-silence recovery path could post; none for the watchdog
    expect(
      posted.some((c) => (c[1] as { issue_number?: number }).issue_number === 777),
    ).toBe(false);
    // warn still fired (Sentry is the primary signal)
    expect(
      warnSilentFallbackSpy.mock.calls.some((c) => c[1].op === STALE_BOT_PR_WARN_OP),
    ).toBe(true);
  });

  it("no open labeled issue → Sentry-only, no comment, no throw", async () => {
    octokitRequestSpy.mockImplementation(
      dispatcher({ "scheduled-content-publisher": { issues: [] } }, undefined, {
        pulls: [stalePr({ number: 91, head: { ref: "ci/content-publisher-2026-05-19-164226" } })],
      }),
    );

    await cronCloudTaskHeartbeatHandler(makeArgs());

    expect(
      warnSilentFallbackSpy.mock.calls.some((c) => c[1].op === STALE_BOT_PR_WARN_OP),
    ).toBe(true);
    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();
  });

  it("pulls-list API error → reportSilentFallback(stale-bot-pr-scan-failed), no throw, ok unaffected", async () => {
    octokitRequestSpy.mockImplementation(
      dispatcher({}, undefined, { pullsThrow: true }),
    );

    const out = await cronCloudTaskHeartbeatHandler(makeArgs());

    const scanFail = reportSilentFallbackSpy.mock.calls.filter(
      (c) => c[1].op === "stale-bot-pr-scan-failed",
    );
    expect(scanFail).toHaveLength(1);
    // heartbeat orthogonality: no silent tasks → ok stays true
    expect(out.ok).toBe(true);
    expect(out.silentCount).toBe(0);
  });

  it("stale bot PR does NOT flip ok/silentCount (orthogonal to the monitor)", async () => {
    octokitRequestSpy.mockImplementation(
      dispatcher({}, undefined, {
        pulls: [stalePr({ number: 5, head: { ref: "ci/rule-prune-2026-06-01-093000" } })],
      }),
    );

    const out = await cronCloudTaskHeartbeatHandler(makeArgs());

    expect(out.ok).toBe(true);
    expect(out.silentCount).toBe(0);
  });

  it("early-exits pagination once a PR newer than the threshold is seen", async () => {
    // page 1 is full (100 entries) and ends with a fresh PR → page 2 must NOT be fetched.
    const page1: BotPrLite[] = Array.from({ length: 100 }, (_, i) =>
      i < 99
        ? stalePr({ number: 1000 + i, head: { ref: "feature-human" } }) // non-bot, old
        : stalePr({
            number: 2000,
            head: { ref: "feature-human" },
            created_at: new Date(Date.now() - 1 * 3600 * 1000).toISOString(), // 1h old → fresh
          }),
    );
    octokitRequestSpy.mockImplementation(dispatcher({}, undefined, { pulls: page1 }));

    await cronCloudTaskHeartbeatHandler(makeArgs());

    const pullPages = octokitRequestSpy.mock.calls.filter(
      (c) => c[0] === "GET /repos/{owner}/{repo}/pulls",
    );
    expect(pullPages).toHaveLength(1);
  });
});

// =============================================================================
// Stale bot-PR watchdog (#5138) — source-shape anchors
// =============================================================================

describe("stale bot-PR watchdog source-shape anchors", () => {
  it.each([
    ["STALE_BOT_PR_THRESHOLD_MS", "48h threshold constant"],
    ['op: STALE_BOT_PR_WARN_OP', "warn op routed to the Sentry alert"],
    ['"check-stale-bot-prs"', "scan step id"],
    ['"stale-bot-pr-handling"', "handling step id"],
    ["stale-bot-pr-scan-failed", "scan-failure op"],
    ["stale-bot-pr-comment-failed", "comment-failure op"],
  ])("source contains %s (%s)", (anchor) => {
    expect(SUT_SOURCE).toContain(anchor);
  });
});
