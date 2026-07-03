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

// Hermeticity: the kept-real postSentryHeartbeat ok-branch writes
// /var/lib/inngest/cron-fires/<slug>.json best-effort — neutralize so no test
// touches the host filesystem (test-design review P2).
vi.mock("node:fs/promises", async (importOriginal) => {
  const actual = await importOriginal<Record<string, unknown>>();
  return {
    ...actual,
    mkdir: vi.fn().mockResolvedValue(undefined),
    writeFile: vi.fn().mockResolvedValue(undefined),
  };
});

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
  escapeDiscordMarkup,
  isHighlightEligible,
  renderDigest,
  stripUrls,
  cronWeeklyReleaseDigestHandler,
} from "@/server/inngest/functions/cron-weekly-release-digest";
// sanitizeReleases moved to the shared release-notes module (#5958) — the cron
// and the in-app Releases page share the exact same hygiene.
import { sanitizeReleases } from "@/server/release-notes";
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
  releasePages: GhRelease[][] | null; // page-aware fixture for pagination tests
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
      // Dispatch on the PARSED hostname (not substring-includes) — exact-match
      // host comparison, per CodeQL js/incomplete-url-substring-sanitization.
      const url = String(input);
      const { hostname, pathname } = new URL(url);
      if (hostname === "api.github.com" && pathname.includes("/releases")) {
        const page = Number(new URL(url).searchParams.get("page") ?? "1");
        const body = fetchBehavior.releasePages
          ? (fetchBehavior.releasePages[page - 1] ?? [])
          : page === 1
            ? fetchBehavior.releases
            : [];
        return new Response(JSON.stringify(body), { status: 200 });
      }
      if (hostname === "api.anthropic.com") {
        if (fetchBehavior.anthropic) return fetchBehavior.anthropic();
        return validAnthropicResponse([
          { tag: "v3.154.0", title: "Model-tier optimization", why: "Workflow runs now pick the right model tier per call site." },
        ]);
      }
      if (hostname === "discord.com" && pathname.startsWith("/api/webhooks/")) {
        discordPosts.push({ url, body: JSON.parse(String(init?.body)) });
        // 204 (Discord's success status) cannot carry a body in the Response ctor.
        return new Response(null, { status: fetchBehavior.discordStatus });
      }
      if (hostname.endsWith(".sentry.io")) {
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
    weekKey?: string;
    highlights?: number;
    fallback?: boolean;
  };
  return { step, result };
}

beforeEach(() => {
  vi.useFakeTimers({ now: NOW_TUESDAY });
  fetchBehavior = { releases: [], releasePages: null, anthropic: null, discordStatus: 204 };
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

  it("strips @handles from TITLES too (the fallback path renders titles verbatim)", () => {
    const raw = mkRelease({ name: "fix: race reported by @octocat" });
    const sanitized = sanitizeReleases([raw]);
    expect(sanitized[0].title).not.toContain("@octocat");
    expect(deterministicFallback(sanitized)[0].why).not.toContain("octocat");
  });

  it("derives titles from the first changelog line when the release name is a bare version", () => {
    // Live failure class (operator report 2026-06-11): plugin releases are
    // named by their tag, so the fallback digest posted bare version strings.
    const raw = mkRelease({
      tag_name: "v3.148.0",
      name: "v3.148.0",
      body: "## Changelog\n- feat: model-tier optimization via workflow call-site tiering (#5096)\n- internal detail",
    });
    const sanitized = sanitizeReleases([raw]);
    expect(sanitized[0].title).toBe(
      "feat: model-tier optimization via workflow call-site tiering (#5096)",
    );
    // Rank improves too: the derived feat: title sorts first in the fallback.
    expect(deterministicFallback(sanitized)[0].why).toContain("model-tier optimization");
  });

  it("keeps the version title when the body is empty (nothing better to derive)", () => {
    const raw = mkRelease({ tag_name: "v3.148.1", name: "v3.148.1", body: "" });
    expect(sanitizeReleases([raw])[0].title).toBe("v3.148.1");
  });

  it("does NOT mine security-sensitive bodies for titles (down-detail holds)", () => {
    const raw = mkRelease({
      tag_name: "v3.148.2",
      name: "v3.148.2",
      body: "## Changelog\n- fix: patch xss exploit detail at parser offset 42",
    });
    const sanitized = sanitizeReleases([raw]);
    expect(sanitized[0].securitySensitive).toBe(true);
    expect(sanitized[0].title).toBe("v3.148.2");
    expect(sanitized[0].title).not.toContain("exploit");
  });

  it("does NOT down-detail releases merely mentioning 'source' (word-boundary, perf note)", () => {
    const raw = mkRelease({
      name: "feat: open source the resource loader",
      body: "## Changelog\n- enforce resource limits in the source tree",
    });
    const sanitized = sanitizeReleases([raw]);
    expect(sanitized[0].securitySensitive).toBe(false);
    expect(sanitized[0].body).toContain("resource limits");
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
    expect(xss.body).toContain("xss vector detail here");

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
  it("ranks feat > fix > other > chore with verbatim titles", () => {
    const releases = sanitizeReleases([
      mkRelease({ tag_name: "v1.0.1", name: "chore: bump deps" }),
      mkRelease({ tag_name: "v1.0.2", name: "fix: cart total rounding" }),
      mkRelease({ tag_name: "v1.0.4", name: "docs: update readme" }),
      mkRelease({ tag_name: "v1.0.3", name: "feat: csv export" }),
    ]);
    const highlights = deterministicFallback(releases);
    expect(highlights.map((h) => h.title)).toEqual([
      "feat: csv export",
      "fix: cart total rounding",
      "docs: update readme",
      "chore: bump deps",
    ]);
  });

  it("caps at 5 highlights (non-vacuous: 7 inputs)", () => {
    const releases = sanitizeReleases(
      Array.from({ length: 7 }, (_, i) =>
        mkRelease({ tag_name: `v1.0.${i}`, name: `feat: thing ${i}` }),
      ),
    );
    expect(deterministicFallback(releases).length).toBe(5);
  });
});

describe("escapeDiscordMarkup + stripUrls (security P2-1/P2-2)", () => {
  it("backslash-prefixed mention cannot un-escape itself", () => {
    // Attacker writes `\<@123>` hoping our `<` escape produces `\\<@123>`
    // (literal backslash + LIVE mention). Backslash-first escaping yields
    // `\\\<@123>` — escaped backslash THEN escaped `<`.
    expect(escapeDiscordMarkup("\\<@123>")).toBe("\\\\\\<@123>");
  });

  it("masked links are broken by [ escaping", () => {
    expect(escapeDiscordMarkup("[click me](https://evil.example)")).toContain("\\[");
  });

  it("bare URLs in free text are defanged", () => {
    expect(stripUrls("see https://evil.example/phish now")).toBe("see ‹link› now");
    expect(stripUrls("no links here")).toBe("no links here");
  });

  it("renderDigest applies URL strip to why text (end-to-end)", () => {
    const out = renderDigest({
      highlights: [{ tag: "v1.0.0", title: "t", why: "Claim credits at https://evil.example" }],
      remainder: { count: 0, fromTag: "", toTag: "" },
      weekKey: "2026-06-05",
    });
    expect(out).not.toContain("https://evil.example");
    expect(out).toContain("‹link›");
  });
});

describe("curate step (via handler)", () => {
  it("happy path: curated `why` posts, fallback:false, NO silent-fallback event (test-design P1)", async () => {
    fetchBehavior.releases = [mkRelease({ published_at: IN_WINDOW })];
    // default anthropic mock returns one valid highlight
    const { result } = await runHandler();
    expect(result.ok).toBe(true);
    expect(result.fallback).toBe(false);
    expect(result.highlights).toBe(1);
    expect(result.weekKey).toBe("2026-06-05");
    expect(String(discordPosts[0].body.content)).toContain(
      "Workflow runs now pick the right model tier per call site.",
    );
    expect(reportSilentFallbackSpy).not.toHaveBeenCalled();
  });

  it("dedupes repeated valid tags from the LLM (one bullet per release)", async () => {
    fetchBehavior.releases = [mkRelease({ published_at: IN_WINDOW })];
    fetchBehavior.anthropic = async () =>
      validAnthropicResponse([
        { tag: "v3.154.0", title: "t", why: "First mention." },
        { tag: "v3.154.0", title: "t", why: "Duplicate mention." },
      ]);
    const { result } = await runHandler();
    expect(result.highlights).toBe(1);
    expect(String(discordPosts[0].body.content)).toContain("First mention.");
    expect(String(discordPosts[0].body.content)).not.toContain("Duplicate mention.");
  });

  it("parses structured-output JSON directly (no fence-stripping after the #5186 migration)", async () => {
    // #5186: the curate call now sends output_config.format json_schema, so the
    // model returns un-fenced schema-valid JSON and the digest parses it
    // directly (extractModelJson was retired). This replaces the prior
    // #5080 fence-stripping regression test — structured outputs make fenced
    // responses impossible, so a plain object is the canonical happy path.
    fetchBehavior.releases = [mkRelease({ published_at: IN_WINDOW })];
    fetchBehavior.anthropic = async () =>
      new Response(
        JSON.stringify({
          content: [
            {
              text: '{"highlights":[{"tag":"v3.154.0","title":"t","why":"Schema-valid JSON."}]}',
            },
          ],
          stop_reason: "end_turn",
        }),
        { status: 200 },
      );
    const { result } = await runHandler();
    expect(result.ok).toBe(true);
    expect(result.fallback).toBe(false);
    expect(String(discordPosts[0].body.content)).toContain("Schema-valid JSON.");
  });

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

  it("malformed secret -> shape guard fails BEFORE fetch; secret never reaches an error message (cq P2-1)", async () => {
    vi.stubEnv("DISCORD_RELEASES_WEBHOOK_URL", "hooks.example/not-discord/sekret-token-value");
    fetchBehavior.releases = [mkRelease({ published_at: IN_WINDOW })];
    const { result } = await runHandler();
    expect(result.ok).toBe(false);
    expect(discordPosts.length).toBe(0);
    // The secret value must not appear in any Sentry-bound message.
    for (const call of reportSilentFallbackSpy.mock.calls) {
      expect(String(call[0])).not.toContain("sekret-token-value");
      expect(JSON.stringify(call[1] ?? {})).not.toContain("sekret-token-value");
    }
    expect(sentryCheckins.some((u) => u.includes("status=error"))).toBe(true);
  });
});

// --- Pagination (git-history P2: ~100 releases/week measured live) --------------

describe("release pagination", () => {
  it("fetches page 2 when page 1 is full and still inside the window", async () => {
    const fullPage = Array.from({ length: 100 }, (_, i) =>
      mkRelease({ tag_name: `v9.0.${i}`, name: `feat: item ${i}`, published_at: IN_WINDOW }),
    );
    const page2 = [
      mkRelease({ tag_name: "v8.9.9", name: "feat: from page two", published_at: IN_WINDOW }),
    ];
    fetchBehavior.releasePages = [fullPage, page2];
    const { result } = await runHandler();
    expect(result.ok).toBe(true);
    // totalCount spans both pages (101 in-window); default anthropic mock's
    // tag is outside this window -> deterministic fallback (5 highlights).
    expect(String(discordPosts[0].body.content)).toContain("plus 96 more releases");
  });

  it("warns loudly when the page cap still truncates the window", async () => {
    const fullPage = (tagPrefix: string) =>
      Array.from({ length: 100 }, (_, i) =>
        mkRelease({ tag_name: `${tagPrefix}.${i}`, name: "feat: x", published_at: IN_WINDOW }),
      );
    fetchBehavior.releasePages = [fullPage("v9.1"), fullPage("v9.2"), fullPage("v9.3")];
    const { result } = await runHandler();
    expect(result.ok).toBe(true);
    expect(
      reportSilentFallbackSpy.mock.calls.some((c) =>
        String(c[0]).includes("release window truncated"),
      ),
    ).toBe(true);
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
