import { describe, it, expect, vi, beforeEach } from "vitest";

// feat-shared-workspace-email-triage-inbox — detail page data-resolution test.
//
// Node project (vitest.config.ts: test/**/*.test.ts). Exercises the three
// data-resolution branches of the server component WITHOUT a DOM: the error
// and absence branches throw via notFound() before any JSX renders; the
// present branch returns a React element tree (createElement works in node).
//
// Contract (mig 111 + AC6):
//   - query error (non-null `error`) → reportSilentFallback(error, { feature:
//     "email-triage", op: "inbox-detail-lookup-error", extra: { emailId } })
//     then notFound(). `extra` carries ONLY emailId — never sender/subject/
//     summary (attacker-controlled) and never a foreign user_id.
//   - clean absence ({ data: null, error: null }) → notFound(), NO mirror.
//   - row present → renders (no notFound, no mirror).
//   - unauthenticated → redirect("/login").
//   - NO `.eq("user_id", ...)` filter — reads gated solely by the
//     workspace-owner RLS (verified by asserting the query chain shape).

const {
  mockGetUser,
  queryResult,
  mockReportSilentFallback,
  eqCalls,
  notFoundError,
  redirectError,
} = vi.hoisted(() => ({
  mockGetUser: vi.fn(),
  queryResult: { data: null as unknown, error: null as unknown },
  mockReportSilentFallback: vi.fn(),
  eqCalls: [] as unknown[][],
  notFoundError: new Error("NEXT_NOT_FOUND"),
  redirectError: new Error("NEXT_REDIRECT"),
}));

vi.mock("next/navigation", () => ({
  notFound: () => {
    throw notFoundError;
  },
  redirect: () => {
    throw redirectError;
  },
}));

vi.mock("@/lib/supabase/server", () => ({
  createClient: async () => ({
    auth: { getUser: mockGetUser },
    from: () => {
      const builder: Record<string, unknown> = {};
      builder.select = () => builder;
      builder.eq = (...args: unknown[]) => {
        eqCalls.push(args);
        return builder;
      };
      builder.maybeSingle = async () => queryResult;
      return builder;
    },
  }),
}));

vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReportSilentFallback,
}));

async function importPage() {
  return (
    await import(
      "@/app/(dashboard)/dashboard/inbox/email/[emailId]/page"
    )
  ).default;
}

const EMAIL_ID = "11111111-1111-1111-1111-111111111111";
const params = () => Promise.resolve({ emailId: EMAIL_ID });

beforeEach(() => {
  vi.clearAllMocks();
  eqCalls.length = 0;
  mockGetUser.mockResolvedValue({ data: { user: { id: "u1" } } });
  queryResult.data = null;
  queryResult.error = null;
});

describe("EmailTriageDetailPage (mig 111 workspace-shared reads)", () => {
  it("query error → mirrors to Sentry with ONLY emailId, then notFound()", async () => {
    queryResult.error = { code: "42P01", message: "relation missing" };
    const Page = await importPage();
    await expect(Page({ params: params() })).rejects.toBe(notFoundError);
    expect(mockReportSilentFallback).toHaveBeenCalledTimes(1);
    expect(mockReportSilentFallback).toHaveBeenCalledWith(
      { code: "42P01", message: "relation missing" },
      {
        feature: "email-triage",
        op: "inbox-detail-lookup-error",
        extra: { emailId: EMAIL_ID },
      },
    );
  });

  it("clean absence (data null, error null) → notFound(), NO mirror", async () => {
    const Page = await importPage();
    await expect(Page({ params: params() })).rejects.toBe(notFoundError);
    expect(mockReportSilentFallback).not.toHaveBeenCalled();
  });

  it("unauthenticated → redirect('/login')", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null } });
    const Page = await importPage();
    await expect(Page({ params: params() })).rejects.toBe(redirectError);
    expect(mockReportSilentFallback).not.toHaveBeenCalled();
  });

  it("row present → renders (no notFound, no mirror)", async () => {
    queryResult.data = {
      id: EMAIL_ID,
      message_id: null,
      sender: "sender@example.test",
      subject: "Subject",
      summary: null,
      mail_class: "legal-review",
      statutory_class: null,
      rule_id: null,
      status: "new",
      received_at: "2026-06-10T10:00:00Z",
    };
    const Page = await importPage();
    const element = await Page({ params: params() });
    expect(element).toBeTruthy();
    expect(mockReportSilentFallback).not.toHaveBeenCalled();
  });

  it("query is gated by id ONLY — no `.eq(\"user_id\", ...)` re-narrows below RLS", async () => {
    queryResult.data = null;
    const Page = await importPage();
    await expect(Page({ params: params() })).rejects.toBe(notFoundError);
    expect(eqCalls).toContainEqual(["id", EMAIL_ID]);
    expect(eqCalls.some((c) => c[0] === "user_id")).toBe(false);
  });
});
