// Guard: distribution-content files that are about to publish (status: scheduled
// or draft) must match the contract that scripts/content-publisher.sh parses.
// The publisher fails SILENTLY at runtime on a malformed file — it skips the
// channel and files a "Manual posting required" issue, defeating automation.
// This test moves that failure left to CI so a hand-authored or drifted file is
// caught before merge, not at publish time.
//
// Why (#5088): the loop-engineering distribution draft was hand-authored in
// /work Phase 5 (bypassing the social-distribute skill, which prescribes the
// correct format) with wrong section headings (`## X / Twitter (thread)` instead
// of `## X/Twitter Thread`), relative `/blog/` URLs, and no UTM — none of which
// the publisher could parse. social-distribute SKILL.md already encodes the
// correct contract; this guard enforces it mechanically.

import { describe, test, expect } from "bun:test";
import { readFileSync, readdirSync } from "node:fs";
import { join, resolve } from "node:path";

const DIST_DIR = resolve(
  import.meta.dir,
  "../../../knowledge-base/marketing/distribution-content",
);

// Mirrors channel_to_section() in scripts/content-publisher.sh — keep in sync.
const CHANNEL_TO_SECTION: Record<string, string> = {
  discord: "Discord",
  x: "X/Twitter Thread",
  "linkedin-personal": "LinkedIn Personal",
  "linkedin-company": "LinkedIn Company Page",
  bluesky: "Bluesky",
};

const X_TWEET_MAX = 280; // X hard limit; URLs count as 23 (t.co) — approximated below.
const TCO_LEN = 23;

interface DistFile {
  name: string;
  status: string;
  channels: string[];
  body: string;
}

function loadActionableFiles(): DistFile[] {
  let entries: string[];
  try {
    entries = readdirSync(DIST_DIR).filter((f) => f.endsWith(".md"));
  } catch {
    return [];
  }
  const out: DistFile[] = [];
  for (const name of entries) {
    const src = readFileSync(join(DIST_DIR, name), "utf8");
    const status = src.match(/^status:\s*(\S+)/m)?.[1] ?? "";
    // Only validate files that are about to publish. `published` files are
    // immutable history; templates without a status are inert.
    if (status !== "scheduled" && status !== "draft") continue;
    const channelsRaw = src.match(/^channels:\s*(.+)$/m)?.[1] ?? "";
    const channels = channelsRaw
      .split(",")
      .map((c) => c.trim())
      .filter(Boolean);
    out.push({ name, status, channels, body: src });
  }
  return out;
}

function stripFrontmatter(src: string): string {
  // Posted content is the body only. Frontmatter fields (e.g. blog_url) are
  // metadata and never sent to any channel — must not be format-validated.
  const m = src.match(/^---\n[\s\S]*?\n---\n([\s\S]*)$/);
  return m ? m[1] : src;
}

function extractSection(body: string, heading: string): string | null {
  // Mirror content-publisher.sh extract_section: between "## heading" and the
  // next "## " (tolerate trailing whitespace on the heading line).
  const lines = body.split("\n");
  let capturing = false;
  const buf: string[] = [];
  for (const line of lines) {
    if (/^## /.test(line)) {
      if (line.replace(/\s+$/, "") === `## ${heading}`) {
        capturing = true;
        continue;
      }
      if (capturing) break;
    } else if (capturing) {
      buf.push(line);
    }
  }
  return capturing ? buf.join("\n").trim() : null;
}

function xTweets(section: string): string[] {
  // Labeled format: split on `**Tweet N ...**` markers, drop the label line.
  const labeled = /^\s*\*\*Tweet\s+\d/m.test(section);
  if (labeled) {
    return section
      .split(/^\s*\*\*Tweet\s+\d[^\n]*\n/m)
      .map((t) => t.trim())
      .filter(Boolean);
  }
  // Numbered fallback: hook + `N/ ` boundaries.
  return section
    .split(/\n(?=\d+\/\s)/)
    .map((t) => t.trim())
    .filter(Boolean);
}

function tweetLen(tweet: string): number {
  // Approximate X counting: each URL counts as TCO_LEN regardless of raw length.
  const withoutUrls = tweet.replace(/https?:\/\/\S+/g, "");
  const urlCount = (tweet.match(/https?:\/\/\S+/g) || []).length;
  return withoutUrls.length + urlCount * TCO_LEN;
}

const files = loadActionableFiles();

describe("distribution-content publish-format guard (status: scheduled|draft)", () => {
  test("guard self-check: CHANNEL_TO_SECTION covers the cron channels", () => {
    expect(Object.keys(CHANNEL_TO_SECTION)).toContain("x");
    expect(CHANNEL_TO_SECTION["linkedin-company"]).toBe("LinkedIn Company Page");
  });

  if (files.length === 0) {
    test("no scheduled/draft files to validate (inert)", () => {
      expect(files.length).toBe(0);
    });
  }

  for (const f of files) {
    describe(f.name, () => {
      test("no Liquid/Jinja markers (posted verbatim to third parties)", () => {
        expect(f.body).not.toMatch(/\{\{|\}\}|\{%|%\}/);
      });

      test("every declared channel has its required section heading", () => {
        for (const ch of f.channels) {
          const section = CHANNEL_TO_SECTION[ch];
          if (!section) continue; // manual-only channel (reddit/hn/etc.)
          expect(
            extractSection(f.body, section),
            `channel "${ch}" needs a "## ${section}" section (content-publisher.sh channel_to_section)`,
          ).not.toBeNull();
        }
      });

      test("posted body links are absolute soleur.ai URLs (no relative /blog/)", () => {
        // Validate the POSTED BODY only — frontmatter (e.g. blog_url) is metadata.
        // A bare `/blog/...` in a channel section posts a dead link to X/LinkedIn.
        const body = stripFrontmatter(f.body);
        const relative = body.match(/(?<!soleur\.ai)\/blog\/[a-z0-9-]+\//g) || [];
        expect(
          relative,
          `relative blog links in posted body (use https://soleur.ai/blog/...): ${relative.join(", ")}`,
        ).toEqual([]);
      });

      if (f.channels.includes("x")) {
        const xSection = extractSection(f.body, "X/Twitter Thread");
        // Per-tweet length is only checked for the LABELED format (`**Tweet N**`),
        // where tweet boundaries are unambiguous. The numbered/freeform format's
        // trailing-CTA merge is too ambiguous to split reliably in CI; the
        // publisher's X API rejection + manual-issue fallback covers that case.
        const labeled = xSection != null && /^\s*\*\*Tweet\s+\d/m.test(xSection);
        test("X/Twitter Thread section exists", () => {
          expect(xSection).not.toBeNull();
        });
        if (labeled) {
          test("labeled X thread tweets are within the 280-char limit", () => {
            const tweets = xTweets(xSection!);
            expect(tweets.length).toBeGreaterThan(0);
            for (const [i, t] of tweets.entries()) {
              expect(
                tweetLen(t),
                `tweet ${i + 1} exceeds ${X_TWEET_MAX} chars: "${t.slice(0, 60)}…"`,
              ).toBeLessThanOrEqual(X_TWEET_MAX);
            }
          });
        }
      }
    });
  }
});
