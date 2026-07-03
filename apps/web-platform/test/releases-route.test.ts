import { describe, test, expect, vi, beforeEach } from "vitest";

// GET /api/dashboard/releases (#5958) — session-gated in-app Releases feed.
//  - 200 { releases } on success
//  - 401 when unauthenticated
//  - 502 + Sentry tag surface:releases-list when fetchWebReleases throws

const { mockGetUser, mockFetchWebReleases, mockCaptureException } = vi.hoisted(
  () => ({
    mockGetUser: vi.fn(),
    mockFetchWebReleases: vi.fn(),
    mockCaptureException: vi.fn(),
  }),
);

vi.mock("@/lib/supabase/server", () => ({
  createClient: vi.fn(async () => ({ auth: { getUser: mockGetUser } })),
}));

vi.mock("@/server/release-notes", () => ({
  fetchWebReleases: mockFetchWebReleases,
}));

vi.mock("@sentry/nextjs", () => ({
  captureException: mockCaptureException,
}));

import { GET } from "@/app/api/dashboard/releases/route";

beforeEach(() => {
  mockGetUser.mockReset();
  mockFetchWebReleases.mockReset();
  mockCaptureException.mockReset();
});

describe("GET /api/dashboard/releases", () => {
  test("returns { releases } for an authenticated user", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: "u1" } } });
    const releases = [
      { tag: "web-v1.0.0", title: "X", bodyMarkdown: "y", publishedAt: "2026-07-01T00:00:00Z", htmlUrl: "h", securitySensitive: false },
    ];
    mockFetchWebReleases.mockResolvedValue(releases);

    const res = await GET();
    expect(res.status).toBe(200);
    expect(await res.json()).toEqual({ releases });
  });

  test("returns 401 when unauthenticated", async () => {
    mockGetUser.mockResolvedValue({ data: { user: null } });
    const res = await GET();
    expect(res.status).toBe(401);
    expect(mockFetchWebReleases).not.toHaveBeenCalled();
  });

  test("returns 502 + Sentry tag surface:releases-list when the fetch throws", async () => {
    mockGetUser.mockResolvedValue({ data: { user: { id: "u1" } } });
    mockFetchWebReleases.mockRejectedValue(new Error("GitHub releases API 503"));

    const res = await GET();
    expect(res.status).toBe(502);
    expect(await res.json()).toEqual({ error: "releases_query_error" });
    expect(mockCaptureException).toHaveBeenCalledWith(
      expect.any(Error),
      { tags: { surface: "releases-list" } },
    );
  });
});
