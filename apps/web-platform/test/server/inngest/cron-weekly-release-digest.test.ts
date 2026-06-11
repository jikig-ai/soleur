// #5080 — cron-weekly-release-digest handler unit tests.
//
// Pure-TS weekly digest cron: fetch GitHub releases for the Friday-ended
// window, sanitize (PII-strip + security down-detail), curate via direct
// Anthropic call (deterministic feat>fix>chore fallback), render ONE payload
// shape, POST to the #releases webhook (no #general fallback), heartbeat via
// the handler-level catch shape (cron-weekly-analytics tail precedent).
//
// Heartbeat mechanism (Kieran P1): postSentryHeartbeat silently skips when
// Sentry env is unset, so the suite stubs shape-valid Sentry env and asserts
// the mocked global fetch hit `?status=ok|error` on the check-in URL.
//
// All network is stubbed via a URL-dispatching global fetch mock — no real
// GitHub/Anthropic/Discord/Sentry calls.

import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

// --- Module mocks (hoisted by vitest) --------------------------------------

// vi.hoisted: the static handler import below triggers the mock factories
// before plain const initializers would run.
const { reportSilentFallbackSpy } = vi.hoisted(() => ({
  reportSilentFallbackSpy: vi.fn(),
}));
vi.mock("@/server/observability", () => ({
  reportSilentFallback: reportSilentFallbackSpy,
}));

// The real client throws at import without INNGEST_SIGNING_KEY (client.ts:32).
vi.mock("@/server/inngest/client", () => ({
  inngest: { createFunction: vi.fn(), send: vi.fn() },
}));

// Partial mock: keep every real export (postSentryHeartbeat, postDiscordWebhook,
// HandlerArgs types) but stub the Octokit-backed token mint. The handler's own
// relative `./_cron-shared` import resolves to the same module id.
vi.mock("@/server/inngest/functions/_cron-shared", async (importOriginal) => {
  const actual = await importOriginal<Record<string, unknown>>();
  return {
    ...actual,
    mintInstallationToken: vi.fn().mockResolvedValue("test-installation-token"),
  };
});

import {
  RELEASE_DIGEST_RULES,
  buildCuratePrompt,
  computeWindow,
  deterministicFallback,
  isHighlightEligible,
  renderDigest,
  sanitizeReleases,
  cronWeeklyReleaseDigestHandler,
} from "@/server/inngest/functions/cron-weekly-release-digest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

// --- Helpers ----------------------------------------------------------------

const logger = { info: vi.fn(), warn: vi.fn(), error: vi.fn() };

function makeStep() {
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

interface GhRelease {
  tag_name: string;
  name: string;
  body: string;
  published_at: string;
  draft: boolean;
  prerelease: boolean;
  author?: { login: string };
}

function mkRelease(over: Partial<GhRelease>): GhRelease {
  return {
    tag_name: "v3.154.0",
    name: "feat: model-tier optimization via workflow call-site tiering",
    body: "## Changelog\n- feat: model-tier optimization (#5096)",
    published_at: "2026-06-04T12:00:00Z",
    draft: false,
    prerelease: false,
    author: { login: "octocat" },
    ...over,
  };
}

// Pin "now" to a Tuesday so the window is the Friday-ended week
// (2026-05-29T15:00Z, 2026-06-05T15:00Z], weekKey 2026-06-05.
const NOW_TUESDAY = new Date("2026-06-09T12:00:00Z");
const IN_WINDOW = "2026-06-04T12:00:00Z";

const DISCORD_URL = "https://discord.com/api/webhooks/1234567890/test-webhook-token";

// URL-dispatching fetch mock state, reconfigured per test.
let fetchBehavior: {
  releases: GhRelease[];
  anthropic: (() => Promise<Response>) | null; // null = valid highlights response
  discordStatus: number;
};

const sentryCheckins: string[] = [];
const discordPosts: { url: string; body: Record<string, unknown> }[] = [];

function validAnthropicResponse(highlights: unknown) {
  return new Response(
    JSON.stringify({
      content: [{ text: JSON.stringify({ highlights }) }],
      stop_reason: "end_turn",
    }),
    { status: 200 },
  );
}

function installFetchMock() {
  vi.stubGlobal(
    "fetch",
    vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const url = String(input);
      if (url.includes("api.github.com") && url.includes("/releases")) {
        return new Response(JSON.stringify(fetchBehavior.releases), { status: 200 });
      }
      if (url.includes("api.anthropic.com")) {
        if (fetchBehavior.anthropic) return fetchBehavior.anthropic();
        return validAnthropicResponse([
          { tag: "v3.154.0", title: "Model-tier optimization", why: "Workflow runs now pick the right model tier per call site." },
        ]);
      }
      if (url.includes("discord.com/api/webhooks")) {
        discordPosts.push({ url, body: JSON.parse(String(init?.body)) });
        // 204 (Discord's success status) cannot carry a body in the Response ctor.
        return new Response(null, { status: fetchBehavior.discordStatus });
      }
      if (url.includes(".sentry.io")) {
        sentryCheckins.push(url);
        return new Response("", { status: 200 });
      }
      throw new Error(`unexpected fetch in test: ${url}`);
    }),
  );
}

async function runHandler() {
  const step = makeStep();
  const result = (await cronWeeklyReleaseDigestHandler({ step, logger })) as {
    ok: boolean;
  };
  return { step, result };
}

beforeEach(() => {
  vi.useFakeTimers({ now: NOW_TUESDAY });
  fetchBehavior = { releases: [], anthropic: null, discordStatus: 204 };
  sentryCheckins.length = 0;
  discordPosts.length = 0;
  installFetchMock();
  vi.stubEnv("DISCORD_RELEASES_WEBHOOK_URL", DISCORD_URL);
  vi.stubEnv("ANTHROPIC_API_KEY", "test-anthropic-key");
  // Shape-valid Sentry env so postSentryHeartbeat actually POSTs (it
  // silently skips on unset/malformed env — _cron-shared.ts:185-199).
  vi.stubEnv("SENTRY_INGEST_DOMAIN", "o123.ingest.de.sentry.io");
  vi.stubEnv("SENTRY_PROJECT_ID", "123");
  vi.stubEnv("SENTRY_PUBLIC_KEY", "a".repeat(32));
});

afterEach(() => {
  vi.unstubAllEnvs();
  vi.unstubAllGlobals();
  vi.useRealTimers();
  vi.clearAllMocks();
});

// --- Scenario 1: window math --------------------------------------------------

describe("computeWindow", () => {
  it("manual trigger on a Tuesday resolves to the previous Friday-ended window", () => {
    const w = computeWindow(NOW_TUESDAY);
    expect(w.end.toISOString()).toBe("2026-06-05T15:00:00.000Z");
    expect(w.start.toISOString()).toBe("2026-05-29T15:00:00.000Z");
    expect(w.weekKey).toBe("2026-06-05");
  });

  it("a fire at exactly Friday 15:00:00 closes that week ((start, end] boundary)", () => {
    const w = computeWindow(new Date("2026-06-12T15:00:00Z"));
    expect(w.end.toISOString()).toBe("2026-06-12T15:00:00.000Z");
    // Boundary release at exactly window end is IN (end-inclusive)...
    const atEnd = new Date("2026-06-12T15:00:00Z");
    expect(atEnd > w.start && atEnd <= w.end).toBe(true);
    // ...and a release at exactly window START is OUT (start-exclusive — it
    // belonged to the prior week's end-inclusive boundary).
    const atStart = new Date("2026-06-05T15:00:00Z");
    expect(atStart > w.start && atStart <= w.end).toBe(false);
  });
});

// --- Scenario 2: partition (load-bearing fixtures) ----------------------------

describe("isHighlightEligible (tag partition)", () => {
  it("anchors on v<digit> — vinngest-v* (v-prefix collision) and telegram-v* are remainder-only", () => {
    expect(isHighlightEligible("v3.154.0")).toBe(true);
    expect(isHighlightEligible("web-v0.120.0")).toBe(true);
    expect(isHighlightEligible("vinngest-v1.1.12")).toBe(false);
    expect(isHighlightEligible("telegram-v0.1.1")).toBe(false);
  });
});

// --- Scenario 3: sanitize ------------------------------------------------------

describe("sanitizeReleases + buildCuratePrompt", () => {
  it("strips author, @handles, emails, and Co-Authored-By lines from the LLM input (AC6)", () => {
    const raw = mkRelease({
      body: "## Changelog\n- feat: thing by @octocat\nCo-Authored-By: Test <test@example.test>\ncontact test@example.test",
    });
    // Non-vacuous: the raw fixture carries all four PII shapes.
    expect(JSON.stringify(raw)).toContain("@octocat");
    expect(JSON.stringify(raw)).toContain("Co-Authored-By");
    expect(JSON.stringify(raw)).toContain("test@example.test");
    expect(raw.author?.login).toBe("octocat");

    const sanitized = sanitizeReleases([raw]);
    const prompt = buildCuratePrompt(sanitized);
    expect(prompt).not.toContain("@octocat");
    expect(prompt).not.toContain("Co-Authored-By");
    expect(prompt).not.toContain("test@example.test");
    expect(prompt).not.toContain("octocat");
  });

  it("renders security-class releases title-only — body withheld from LLM input (AC5)", () => {
    const withheld = "exploit detail: overflow in the parser at offset 42";
    const sec = mkRelease({
      tag_name: "v3.154.1",
      name: "fix(security): patch CVE-2026-1234 parser overflow",
      body: `## Changelog\n- ${withheld}`,
    });
    const xss = mkRelease({
      tag_name: "v3.154.2",
      name: "fix: sanitize html to prevent xss in preview",
      body: "## Changelog\n- xss vector detail here",
    });
    // Non-vacuous: raw fixtures contain the bodies.
    expect(sec.body).toContain(withheld);

    const prompt = buildCuratePrompt(sanitizeReleases([sec, xss]));
    expect(prompt).toContain("fix(security): patch CVE-2026-1234 parser overflow");
    expect(prompt).not.toContain(withheld);
    expect(prompt).not.toContain("xss vector detail here");
  });

  it("includes the banned-word prohibition from the brand rules (AC10)", () => {
    const prompt = buildCuratePrompt(sanitizeReleases([mkRelease({})]));
    expect(prompt).toContain("game-changing");
    expect(prompt).toContain("AI-powered");
  });
});

// --- Scenario 8: brand-guide constant sync (AC10) ------------------------------

describe("RELEASE_DIGEST_RULES brand-guide lockstep", () => {
  it("matches the #### Release Digest subsection byte-for-byte (trimmed)", () => {
    const guidePath = resolve(
      __dirname,
      "../../../../../knowledge-base/marketing/brand-guide.md",
    );
    const guide = readFileSync(guidePath, "utf8");
    const idx = guide.indexOf("#### Release Digest");
    expect(idx).toBeGreaterThan(-1);
    const rest = guide.slice(idx);
    const endIdx = rest.indexOf("\n#", 1);
    const section = (endIdx === -1 ? rest : rest.slice(0, endIdx)).trim();
    expect(RELEASE_DIGEST_RULES.trim()).toBe(section);
  });
});

// --- Scenario 4: curate + fallback ---------------------------------------------

describe("deterministicFallback", () => {
  it("ranks feat > fix > chore with verbatim titles", () => {
    const releases = sanitizeReleases([
      mkRelease({ tag_name: "v1.0.1", name: "chore: bump deps" }),
      mkRelease({ tag_name: "v1.0.2", name: "fix: cart total rounding" }),
      mkRelease({ tag_name: "v1.0.3", name: "feat: csv export" }),
    ]);
    const highlights = deterministicFallback(releases);
    expect(highlights[0].title).toBe("feat: csv export");
    expect(highlights[1].title).toBe("fix: cart total rounding");
    expect(highlights[2].title).toBe("chore: bump deps");
    expect(highlights.length).toBeLessThanOrEqual(5);
  });
});

describe("curate step (via handler)", () => {
  it("LLM failure -> deterministic fallback still posts; heartbeat ok (AC7 first half)", async () => {
    fetchBehavior.releases = [mkRelease({ published_at: IN_WINDOW })];
    fetchBehavior.anthropic = async () => new Response("upstream error", { status: 500 });
    const { result } = await runHandler();
    expect(result.ok).toBe(true);
    expect(discordPosts.length).toBe(1);
    expect(String(discordPosts[0].body.content)).toContain("model-tier optimization");
    expect(sentryCheckins.some((u) => u.includes("cron-weekly-release-digest") && u.includes("status=ok"))).toBe(true);
  });

  it("max_tokens stop_reason -> fallback", async () => {
    fetchBehavior.releases = [mkRelease({ published_at: IN_WINDOW })];
    fetchBehavior.anthropic = async () =>
      new Response(
        JSON.stringify({ content: [{ text: "{}" }], stop_reason: "max_tokens" }),
        { status: 200 },
      );
    const { result } = await runHandler();
    expect(result.ok).toBe(true);
    expect(discordPosts.length).toBe(1);
  });

  it("shape-invalid JSON -> fallback + Sentry event", async () => {
    fetchBehavior.releases = [mkRelease({ published_at: IN_WINDOW })];
    fetchBehavior.anthropic = async () => validAnthropicResponse("not-an-array");
    const { result } = await runHandler();
    expect(result.ok).toBe(true);
    expect(discordPosts.length).toBe(1);
    expect(reportSilentFallbackSpy).toHaveBeenCalled();
  });

  it("discards hallucinated tags not present in the window (verbatim-or-less)", async () => {
    fetchBehavior.releases = [mkRelease({ published_at: IN_WINDOW })];
    fetchBehavior.anthropic = async () =>
      validAnthropicResponse([
        { tag: "v9.9.9-hallucinated", title: "made up", why: "fabricated" },
      ]);
    const { result } = await runHandler();
    expect(result.ok).toBe(true);
    // All LLM highlights invalid -> deterministic fallback content posts.
    expect(String(discordPosts[0].body.content)).not.toContain("fabricated");
    expect(String(discordPosts[0].body.content)).toContain("model-tier optimization");
  });
});

// --- Scenario 5: single renderer ------------------------------------------------

describe("renderDigest (single renderer, all three input shapes)", () => {
  const remainder = { count: 44, fromTag: "v3.148.0", toTag: "v3.154.1" };

  it("renders highlights + computed remainder line", () => {
    const out = renderDigest({
      highlights: [{ tag: "v3.154.0", title: "t", why: "Release notifications now land in Slack." }],
      remainder,
      weekKey: "2026-06-05",
    });
    expect(out).toContain("Release notifications now land in Slack.");
    expect(out).toContain("plus 44 more releases");
    expect(out).toContain("v3.148.0 → v3.154.1");
  });

  it("quiet week (empty highlights) renders the one-liner", () => {
    const out = renderDigest({
      highlights: [],
      remainder: { count: 0, fromTag: "", toTag: "" },
      weekKey: "2026-06-05",
    });
    expect(out).toContain("Quiet week");
    expect(out.length).toBeLessThanOrEqual(2000);
  });

  it("escapes BEFORE truncating — escaped oversize input still lands <= 2000 (AC4 order)", () => {
    // Many '<' chars: escaping doubles them; if truncation measured pre-escape
    // the final payload would exceed 2000.
    const spicy = "<".repeat(1500);
    const out = renderDigest({
      highlights: [{ tag: "v1.0.0", title: "t", why: spicy }],
      remainder,
      weekKey: "2026-06-05",
    });
    expect(out.length).toBeLessThanOrEqual(2000);
    expect(out).not.toContain("<<"); // raw run of unescaped angle brackets
  });
});

// --- Scenario 6 + AC4: post step ------------------------------------------------

describe("post-discord step", () => {
  it("every payload carries allowed_mentions parse:[] and username, across all three render paths (AC4)", async () => {
    // Path 1: LLM-curated.
    fetchBehavior.releases = [mkRelease({ published_at: IN_WINDOW })];
    await runHandler();
    // Path 2: deterministic fallback.
    fetchBehavior.anthropic = async () => new Response("err", { status: 500 });
    await runHandler();
    // Path 3: quiet week.
    fetchBehavior.releases = [];
    fetchBehavior.anthropic = null;
    await runHandler();

    expect(discordPosts.length).toBe(3);
    for (const post of discordPosts) {
      expect(post.body.allowed_mentions).toEqual({ parse: [] });
      expect(post.body.username).toBe("Soleur Releases");
      expect(String(post.body.content).length).toBeLessThanOrEqual(2000);
    }
  });

  it("non-2xx Discord response -> ok:false check-in SENT (AC7 second half)", async () => {
    fetchBehavior.releases = [mkRelease({ published_at: IN_WINDOW })];
    fetchBehavior.discordStatus = 500;
    const { result } = await runHandler();
    expect(result.ok).toBe(false);
    expect(sentryCheckins.some((u) => u.includes("cron-weekly-release-digest") && u.includes("status=error"))).toBe(true);
  });

  it("missing secret -> no POST anywhere, captureException-class mirror, ok:false sent (AC8b)", async () => {
    vi.stubEnv("DISCORD_RELEASES_WEBHOOK_URL", "");
    fetchBehavior.releases = [mkRelease({ published_at: IN_WINDOW })];
    const { result } = await runHandler();
    expect(result.ok).toBe(false);
    expect(discordPosts.length).toBe(0);
    expect(reportSilentFallbackSpy).toHaveBeenCalled();
    expect(sentryCheckins.some((u) => u.includes("status=error"))).toBe(true);
  });
});

// --- Scenario 7 + AC8: quiet week / partition through the handler ----------------

describe("quiet week + partition (AC8)", () => {
  it("zero releases -> quiet-week note posted, ok:true", async () => {
    fetchBehavior.releases = [];
    const { result } = await runHandler();
    expect(result.ok).toBe(true);
    expect(discordPosts.length).toBe(1);
    expect(String(discordPosts[0].body.content)).toContain("Quiet week");
    expect(sentryCheckins.some((u) => u.includes("status=ok"))).toBe(true);
  });

  it("infra/telegram-only window (vinngest + telegram fixtures) -> quiet-week note, not a digest", async () => {
    fetchBehavior.releases = [
      mkRelease({ tag_name: "vinngest-v1.1.12", name: "chore(infra): bump bootstrap pin", published_at: IN_WINDOW }),
      mkRelease({ tag_name: "telegram-v0.1.1", name: "fix: telegram retry", published_at: IN_WINDOW }),
    ];
    const { result } = await runHandler();
    expect(result.ok).toBe(true);
    expect(String(discordPosts[0].body.content)).toContain("Quiet week");
  });

  it("drafts, prereleases, and out-of-window releases are excluded", async () => {
    fetchBehavior.releases = [
      mkRelease({ draft: true, published_at: IN_WINDOW }),
      mkRelease({ prerelease: true, published_at: IN_WINDOW }),
      mkRelease({ published_at: "2026-01-01T00:00:00Z" }),
    ];
    const { result } = await runHandler();
    expect(result.ok).toBe(true);
    expect(String(discordPosts[0].body.content)).toContain("Quiet week");
  });
});
