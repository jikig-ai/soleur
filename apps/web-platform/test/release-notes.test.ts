import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// _cron-shared is heavy (pulls probe-octokit / github-app / spawn substrate);
// release-notes.ts only uses these three symbols, so a wholesale mock is safe —
// nothing else in this test graph needs the module's other exports.
// Spies via vi.hoisted() so the hoisted vi.mock factories can reference them.
const { mintInstallationToken, reportSilentFallback } = vi.hoisted(() => ({
  mintInstallationToken: vi.fn(async () => "test-token"),
  reportSilentFallback: vi.fn(),
}));
vi.mock("@/server/inngest/functions/_cron-shared", () => ({
  REPO_OWNER: "jikig-ai",
  REPO_NAME: "soleur",
  mintInstallationToken,
}));
vi.mock("@/server/observability", () => ({
  reportSilentFallback,
  warnSilentFallback: vi.fn(),
}));

import {
  fetchWebReleases,
  sanitizeReleases,
  type RawGithubRelease,
} from "@/server/release-notes";

function rel(overrides: Partial<RawGithubRelease>): RawGithubRelease {
  return {
    tag_name: "web-v0.1.0",
    name: "web-v0.1.0",
    body: "- Did a thing",
    published_at: "2026-07-01T00:00:00Z",
    draft: false,
    prerelease: false,
    html_url: "https://github.com/jikig-ai/soleur/releases/tag/web-v0.1.0",
    ...overrides,
  };
}

/** A page response of the given releases; `ok:true`. */
function page(releases: RawGithubRelease[]) {
  return { ok: true, json: async () => releases } as unknown as Response;
}

describe("sanitizeReleases", () => {
  it("strips emails, @handles, and Co-Authored-By lines from the body", () => {
    const [s] = sanitizeReleases([
      rel({
        tag_name: "web-v1.0.0",
        name: "Shiny feature",
        body: "Shipped it, thanks alice@example.com and @octocat\nCo-Authored-By: Bot <bot@x.com>",
      }),
    ]);
    expect(s.body).not.toContain("alice@example.com");
    expect(s.body).not.toContain("@octocat");
    expect(s.body.toLowerCase()).not.toContain("co-authored-by");
  });

  it("renders a security-sensitive release title-only (empty body)", () => {
    const [s] = sanitizeReleases([
      rel({
        tag_name: "web-v1.2.0",
        name: "Patch",
        body: "Fixes an auth bypass (CVE-2026-1234) via path traversal.",
      }),
    ]);
    expect(s.securitySensitive).toBe(true);
    expect(s.body).toBe("");
  });

  it("derives a title from the first body line when the name is version-shaped", () => {
    const [s] = sanitizeReleases([
      rel({ tag_name: "web-v1.3.0", name: "web-v1.3.0", body: "- Faster dashboard tab switching" }),
    ]);
    expect(s.title).toBe("Faster dashboard tab switching");
  });
});

describe("fetchWebReleases", () => {
  let fetchMock: ReturnType<typeof vi.fn>;
  beforeEach(() => {
    fetchMock = vi.fn();
    vi.stubGlobal("fetch", fetchMock);
    mintInstallationToken.mockClear();
    reportSilentFallback.mockClear();
  });
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it("returns only web-v* releases, excluding plugin/draft/prerelease tags", async () => {
    fetchMock.mockResolvedValueOnce(
      page([
        rel({ tag_name: "web-v0.1.0" }),
        rel({ tag_name: "v3.1.0" }), // plugin
        rel({ tag_name: "web-v9.9.9", draft: true }),
        rel({ tag_name: "web-v8.8.8", prerelease: true }),
        rel({ tag_name: "vinngest-v1.0.0" }),
      ]),
    );
    const cards = await fetchWebReleases();
    expect(cards).toHaveLength(1);
    expect(cards[0].tag).toBe("web-v0.1.0");
    expect(cards[0].htmlUrl).toContain("/releases/tag/");
    expect(cards[0].publishedAt).toBe("2026-07-01T00:00:00Z");
  });

  it("mints a least-privilege contents:read token scoped to the soleur repo", async () => {
    fetchMock.mockResolvedValueOnce(page([rel({ tag_name: "web-v0.1.0" })]));
    await fetchWebReleases();
    expect(mintInstallationToken).toHaveBeenCalledWith(
      expect.objectContaining({
        permissions: { contents: "read" },
        repositories: ["soleur"],
      }),
    );
  });

  it("gives every card a non-empty body via fallback (never blank)", async () => {
    fetchMock.mockResolvedValueOnce(
      page([
        rel({ tag_name: "web-v1.0.0", name: "Real", body: "- Something" }),
        rel({ tag_name: "web-v1.1.0", name: "web-v1.1.0", body: "" }),
        rel({ tag_name: "web-v1.2.0", name: "Sec", body: "Fixes an XSS vulnerability." }),
      ]),
    );
    const cards = await fetchWebReleases();
    const empty = cards.find((c) => c.tag === "web-v1.1.0");
    const sec = cards.find((c) => c.tag === "web-v1.2.0");
    expect(empty?.bodyMarkdown).toBe("Behind-the-scenes improvements and fixes.");
    expect(sec?.bodyMarkdown).toBe("Security and stability improvements.");
    expect(sec?.securitySensitive).toBe(true);
    for (const c of cards) expect(c.bodyMarkdown).not.toBe("");
  });

  it("paginates to reach the limit when early pages are all plugin tags", async () => {
    const fullPluginPage = Array.from({ length: 100 }, (_, i) =>
      rel({ tag_name: `v3.${i}.0` }),
    );
    fetchMock
      .mockResolvedValueOnce(page(fullPluginPage)) // page 1: 0 web-v*
      .mockResolvedValueOnce(
        page([rel({ tag_name: "web-v2.0.0" }), rel({ tag_name: "web-v2.1.0" })]),
      ); // page 2: short page → break
    const cards = await fetchWebReleases({ limit: 2 });
    expect(cards.map((c) => c.tag)).toEqual(["web-v2.0.0", "web-v2.1.0"]);
    expect(fetchMock).toHaveBeenCalledTimes(2);
    expect(String(fetchMock.mock.calls[1][0])).toContain("page=2");
    expect(reportSilentFallback).not.toHaveBeenCalled();
  });

  it("emits releases-page-undercount when the page cap is hit before the limit", async () => {
    const fullPluginPage = Array.from({ length: 100 }, (_, i) =>
      rel({ tag_name: `v3.${i}.0` }),
    );
    // 5 full pages, all plugin → never fills limit → hits MAX_PAGES cap.
    for (let i = 0; i < 5; i++) fetchMock.mockResolvedValueOnce(page(fullPluginPage));
    const cards = await fetchWebReleases({ limit: 10 });
    expect(cards).toHaveLength(0);
    expect(reportSilentFallback).toHaveBeenCalledWith(
      expect.any(Error),
      expect.objectContaining({ op: "releases-page-undercount" }),
    );
  });

  it("throws on a non-200 GitHub response", async () => {
    fetchMock.mockResolvedValueOnce({ ok: false, status: 503 } as Response);
    await expect(fetchWebReleases()).rejects.toThrow(/503/);
  });
});
