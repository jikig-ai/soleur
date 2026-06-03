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
  TASK_INVENTORY,
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

type LabelSpec = { issues?: Array<{ created_at: string }>; throw?: boolean };

/**
 * Build an Octokit `.request` dispatcher. `perLabel` overrides the issues
 * returned for specific `scheduled-<task>` labels; any label not listed returns
 * a single fresh issue (silent:false, not pending). `/search/issues` returns no
 * existing silence issue unless `existing` is provided.
 */
function dispatcher(
  perLabel: Record<string, LabelSpec>,
  existing?: { number: number; matchTask: string },
) {
  return async (route: string, params: Record<string, unknown> = {}) => {
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
