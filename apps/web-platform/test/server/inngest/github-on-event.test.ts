import { describe, it, expect, vi, beforeEach } from "vitest";

// PR-H (#3244) Phase 4 — dispatcher matrix test. Exercises handler
// directly (not via Inngest runtime) — same pattern as the cfo
// function test. Mocks: tenant client + byok lease + reportSilentFallback.

const {
  mockInsert,
  mockGetFreshTenantClient,
  mockRunWithByokLease,
  mockReportSilentFallback,
  mockLogger,
} = vi.hoisted(() => ({
  mockInsert: vi.fn(),
  mockGetFreshTenantClient: vi.fn(),
  mockRunWithByokLease: vi.fn(),
  mockReportSilentFallback: vi.fn(),
  mockLogger: { info: vi.fn(), warn: vi.fn(), error: vi.fn() },
}));

vi.mock("@/lib/supabase/tenant", () => ({
  getFreshTenantClient: mockGetFreshTenantClient,
}));

vi.mock("@/server/byok-lease", () => ({
  runWithByokLease: mockRunWithByokLease,
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
}));

vi.mock("@/server/inngest/client", () => ({
  inngest: {
    createFunction: () => ({ id: "github-on-event-stub" }),
    send: vi.fn(),
  },
}));

import { githubOnEventHandler } from "@/server/inngest/functions/github-on-event";

const stepRun = async <T>(_name: string, cb: () => Promise<T>): Promise<T> => cb();

function makeArgs(overrides: {
  name?: string;
  v?: string;
  rawBody?: string;
  founderId?: string;
  tier?: string;
}) {
  return {
    event: {
      name: overrides.name ?? "engineering.pr_review_pending",
      v: overrides.v ?? "1",
      data: {
        founderId: overrides.founderId ?? "founder-1",
        installationId: 42,
        deliveryId: "delivery-abc",
        githubEvent: "pull_request",
        action: "opened",
        tier: overrides.tier as "draft_one_click" | undefined,
        rawBody:
          overrides.rawBody ??
          JSON.stringify({
            repository: { full_name: "jikig-ai/soleur" },
            pull_request: {
              number: 4066,
              title: "fix: leak in alice@example.com path",
              html_url: "https://github.com/jikig-ai/soleur/pull/4066",
            },
          }),
      },
    },
    step: { run: stepRun },
    logger: mockLogger,
  };
}

beforeEach(() => {
  vi.clearAllMocks();
  mockInsert.mockResolvedValue({ error: null });
  mockGetFreshTenantClient.mockResolvedValue({
    from: () => ({ insert: mockInsert }),
  });
  mockRunWithByokLease.mockImplementation(async (_id: string, cb: (lease: unknown) => unknown) =>
    cb({}),
  );
});

describe("github-on-event handler", () => {
  describe("schema-gate", () => {
    it("deadletters on schema_v != 1", async () => {
      const res = await githubOnEventHandler(makeArgs({ v: "2" }) as never);
      expect(res).toEqual({ deadlettered: true, reason: "schema_v=2" });
      expect(mockInsert).not.toHaveBeenCalled();
    });

    it("deadletters on unknown action class", async () => {
      const res = await githubOnEventHandler(makeArgs({ name: "stripe.foo" }) as never);
      expect(res).toEqual({
        deadlettered: true,
        reason: "unknown_action_class=stripe.foo",
      });
    });

    it("deadletters on malformed rawBody (not JSON)", async () => {
      const res = await githubOnEventHandler(makeArgs({ rawBody: "<<not json>>" }) as never);
      expect(res).toEqual({ deadlettered: true, reason: "rawBody-not-json" });
    });
  });

  describe("source_ref derivation", () => {
    it("pr_review_pending → pr-<org>:<repo>:<number>", async () => {
      await githubOnEventHandler(makeArgs({}) as never);
      expect(mockInsert).toHaveBeenCalledWith(
        expect.objectContaining({
          source: "github",
          source_ref: "pr-jikig-ai:soleur:4066",
          urgency: "normal",
          owning_domain: "engineering",
        }),
      );
    });

    it("ci_failed → ci-<workflow_run_id>", async () => {
      const rawBody = JSON.stringify({
        repository: { full_name: "jikig-ai/soleur" },
        workflow_run: { id: 88991, name: "build", html_url: "" },
      });
      await githubOnEventHandler(
        makeArgs({ name: "engineering.ci_failed", rawBody }) as never,
      );
      expect(mockInsert).toHaveBeenCalledWith(
        expect.objectContaining({
          source_ref: "ci-88991",
          urgency: "high",
        }),
      );
    });

    it("p0p1_issue with type/feature label → product owner", async () => {
      const rawBody = JSON.stringify({
        repository: { full_name: "jikig-ai/soleur" },
        issue: {
          number: 999,
          title: "Add SSO",
          body: "from foo@bar.io",
          labels: [{ name: "type/feature" }],
        },
      });
      await githubOnEventHandler(
        makeArgs({ name: "triage.p0p1_issue", rawBody }) as never,
      );
      expect(mockInsert).toHaveBeenCalledWith(
        expect.objectContaining({
          owning_domain: "product",
          source_ref: "issue-jikig-ai:soleur:999",
          urgency: "critical",
        }),
      );
    });
  });

  describe("INSERT-time redaction (Phase 6 belt-and-suspenders)", () => {
    it("redacts email in pr_review_pending draft_preview", async () => {
      await githubOnEventHandler(makeArgs({}) as never);
      const insertedRow = mockInsert.mock.calls[0][0];
      expect(insertedRow.draft_preview).toContain("[redacted-email]");
      expect(insertedRow.draft_preview).not.toContain("alice@example.com");
    });
  });

  describe("trust_tier pinning", () => {
    it("uses event.data.tier when present (consent-at-time pinning)", async () => {
      await githubOnEventHandler(makeArgs({ tier: "auto" }) as never);
      expect(mockInsert).toHaveBeenCalledWith(
        expect.objectContaining({ trust_tier: "auto" }),
      );
    });

    it("falls back to ACTION_CLASS_DEFAULTS when tier omitted (test/fixture replay)", async () => {
      await githubOnEventHandler(makeArgs({}) as never);
      expect(mockInsert).toHaveBeenCalledWith(
        expect.objectContaining({ trust_tier: "draft_one_click" }),
      );
    });
  });

  describe("ADR-035: PG_UNIQUE_VIOLATION on persist is idempotent", () => {
    it("does NOT throw on 23505 (partial-unique conflict)", async () => {
      mockInsert.mockResolvedValueOnce({ error: { code: "23505" } });
      const res = await githubOnEventHandler(makeArgs({}) as never);
      // Returns drafted:true — Inngest considers the step done, no retry.
      expect(res).toEqual({ drafted: true });
      expect(mockReportSilentFallback).not.toHaveBeenCalled();
    });

    it("reports + throws on non-conflict DB errors", async () => {
      mockInsert.mockResolvedValueOnce({ error: { code: "08006", message: "conn lost" } });
      await expect(githubOnEventHandler(makeArgs({}) as never)).rejects.toMatchObject({
        code: "08006",
      });
      expect(mockReportSilentFallback).toHaveBeenCalled();
    });
  });

  describe("ADR-030 I1: BYOK lease wraps SDK-calling step.run", () => {
    it("runWithByokLease invoked exactly once per event", async () => {
      await githubOnEventHandler(makeArgs({}) as never);
      expect(mockRunWithByokLease).toHaveBeenCalledTimes(1);
      expect(mockRunWithByokLease).toHaveBeenCalledWith(
        "founder-1",
        expect.any(Function),
      );
    });
  });
});
