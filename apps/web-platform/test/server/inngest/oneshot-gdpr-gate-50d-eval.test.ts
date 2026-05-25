import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// --- Module mocks (hoisted by vitest) --------------------------------------

const {
  reportSilentFallbackSpy,
  generateInstallationTokenSpy,
  createProbeOctokitSpy,
  inngestSendSpy,
} = vi.hoisted(() => ({
  reportSilentFallbackSpy: vi.fn(),
  generateInstallationTokenSpy: vi.fn(async () => "ghs_test_token_abc"),
  createProbeOctokitSpy: vi.fn(async () => ({
    request: vi.fn(async () => ({ data: { id: 12345 } })),
  })),
  inngestSendSpy: vi.fn(),
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: reportSilentFallbackSpy,
}));

vi.mock("@/server/github-app", () => ({
  generateInstallationToken: generateInstallationTokenSpy,
}));

vi.mock("@/server/github/probe-octokit", () => ({
  createProbeOctokit: createProbeOctokitSpy,
}));

vi.mock("@/server/inngest/client", () => ({
  inngest: {
    createFunction: vi.fn(),
    send: inngestSendSpy,
  },
}));

// --- SUT import (module does not exist yet — RED) ----------------------------

import { oneshotGdprGate50dEvalHandler } from "@/server/inngest/functions/oneshot-gdpr-gate-50d-eval";

// --- Helpers ----------------------------------------------------------------

interface MockStep {
  calls: { name: string; result: unknown }[];
  run<T>(name: string, cb: () => Promise<T>): Promise<T>;
}

function makeStep(): MockStep {
  const calls: { name: string; result: unknown }[] = [];
  return {
    calls,
    async run<T>(name: string, cb: () => Promise<T>): Promise<T> {
      const result = await cb();
      calls.push({ name, result });
      return result;
    },
  };
}

const logger = { info: vi.fn(), warn: vi.fn(), error: vi.fn() };

// --- Tests -------------------------------------------------------------------

describe("oneshot-gdpr-gate-50d-eval", () => {
  beforeEach(() => {
    vi.clearAllMocks();
    vi.stubEnv("SENTRY_INGEST_DOMAIN", "");
    vi.stubEnv("SENTRY_PROJECT_ID", "");
    vi.stubEnv("SENTRY_PUBLIC_KEY", "");
  });

  afterEach(() => {
    vi.unstubAllEnvs();
  });

  describe("D3 date guard", () => {
    it("rejects when today !== event.data.expected_date", async () => {
      const step = makeStep();
      const result = await oneshotGdprGate50dEvalHandler({
        event: {
          data: {
            issue: 3516,
            comment_id: 4415647777,
            expected_date: "2099-12-31",
            expectedAuthor: "deruelle",
          },
        },
        step,
        logger,
      });

      expect(result).toEqual(
        expect.objectContaining({ ok: false, reason: "date-guard" }),
      );
      expect(reportSilentFallbackSpy).toHaveBeenCalledWith(
        expect.any(Error),
        expect.objectContaining({
          feature: "oneshot-gdpr-gate-50d-eval",
          op: "date-guard",
        }),
      );
    });

    it("passes when event.data.date_override matches expected_date", async () => {
      const step = makeStep();
      const mockFetch = vi.fn();
      globalThis.fetch = mockFetch;

      // Octokit constructor mock for the eval step
      vi.doMock("@octokit/core", () => ({
        Octokit: class {
          request = vi.fn(async (route: string) => {
            if (route.includes("/issues/comments/")) {
              return { data: { user: { login: "deruelle" } } };
            }
            if (route.includes("/contents/")) {
              return {
                data: { content: Buffer.from("no-matches-here").toString("base64") },
              };
            }
            if (route === "GET /repos/{owner}/{repo}/pulls") {
              return { data: [] };
            }
            if (route.includes("/issues/") && route.includes("/comments")) {
              return { data: { id: 123 } };
            }
            return { data: {} };
          });
        },
      }));

      const result = await oneshotGdprGate50dEvalHandler({
        event: {
          data: {
            issue: 3516,
            comment_id: 4415647777,
            expected_date: "2026-06-29",
            expectedAuthor: "deruelle",
            date_override: "2026-06-29",
          },
        },
        step,
        logger,
      });

      expect(result.ok).toBe(true);
      expect(inngestSendSpy).toHaveBeenCalledWith(
        expect.objectContaining({
          name: "oneshot/gdpr-gate-50d-eval.fire",
          id: "gdpr-gate-90d-eval-2026-08-10-v1",
          data: expect.objectContaining({
            expected_date: "2026-08-10",
            actor: "platform",
          }),
        }),
      );
    });
  });

  describe("author check", () => {
    it("rejects when comment author does not match expectedAuthor", async () => {
      const step = makeStep();

      vi.doMock("@octokit/core", () => ({
        Octokit: class {
          request = vi.fn(async () => ({
            data: { user: { login: "attacker" } },
          }));
        },
      }));

      const result = await oneshotGdprGate50dEvalHandler({
        event: {
          data: {
            issue: 3516,
            comment_id: 4415647777,
            expected_date: "2026-06-29",
            expectedAuthor: "deruelle",
            date_override: "2026-06-29",
          },
        },
        step,
        logger,
      });

      expect(result).toEqual(
        expect.objectContaining({ ok: false, reason: "author-mismatch" }),
      );
      expect(reportSilentFallbackSpy).toHaveBeenCalledWith(
        expect.any(Error),
        expect.objectContaining({
          feature: "oneshot-gdpr-gate-50d-eval",
          op: "author-check",
        }),
      );
    });
  });
});
