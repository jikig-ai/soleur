import { describe, it, expect } from "vitest";
import {
  parseSentryRateParams,
  buildSentryUrl,
  computeRatePerDay,
  MAX_WINDOW_HOURS,
} from "@/lib/inngest/sentry-issue-rate";

describe("parseSentryRateParams", () => {
  const ok = {
    tag: "event_type:server-startup",
    max_per_day: 1,
    window_hours: 72,
    close_on_pass: true,
  };

  it("accepts a valid param set", () => {
    const r = parseSentryRateParams(ok);
    expect(r.ok).toBe(true);
    if (r.ok) {
      expect(r.value).toEqual({
        tag: "event_type:server-startup",
        maxPerDay: 1,
        windowHours: 72,
        closeOnPass: true,
      });
    }
  });

  it("defaults closeOnPass to false when absent or non-true", () => {
    const r = parseSentryRateParams({ ...ok, close_on_pass: undefined });
    expect(r.ok && r.value.closeOnPass).toBe(false);
    const r2 = parseSentryRateParams({ ...ok, close_on_pass: "true" });
    expect(r2.ok && r2.value.closeOnPass).toBe(false);
  });

  it("rejects missing params", () => {
    expect(parseSentryRateParams(undefined)).toEqual({
      ok: false,
      reason: "missing-params",
    });
  });

  it.each([
    "event_type=server-startup", // wrong separator
    "event_type:server startup", // whitespace
    "event_type:foo&bar", // query-injection char
    "event_type:foo?x=1", // query-injection char
    "event_type:foo#frag", // fragment
    "event_type:../../etc", // traversal
    "no-colon-here",
  ])("rejects injection/invalid tag %j", (tag) => {
    expect(parseSentryRateParams({ ...ok, tag })).toEqual({
      ok: false,
      reason: "invalid-tag",
    });
  });

  it.each([0, -1, Infinity, NaN, "1"])(
    "rejects invalid max_per_day %j",
    (max_per_day) => {
      expect(
        parseSentryRateParams({ ...ok, max_per_day }).ok,
      ).toBe(false);
    },
  );

  it.each([0, MAX_WINDOW_HOURS + 1, 72.5, -24])(
    "rejects out-of-bounds/non-integer window_hours %j",
    (window_hours) => {
      const r = parseSentryRateParams({ ...ok, window_hours });
      expect(r).toEqual({ ok: false, reason: "invalid-window-hours" });
    },
  );

  it("accepts the window bounds 1 and 168", () => {
    expect(parseSentryRateParams({ ...ok, window_hours: 1 }).ok).toBe(true);
    expect(
      parseSentryRateParams({ ...ok, window_hours: MAX_WINDOW_HOURS }).ok,
    ).toBe(true);
  });
});

describe("buildSentryUrl", () => {
  it("builds an EU host URL and percent-encodes query values", () => {
    const url = buildSentryUrl(
      "jikigai-eu.sentry.io",
      "/api/0/organizations/jikigai-eu/issues/",
      { query: "event_type:server-startup", project: "web-platform" },
    );
    expect(url).toContain("https://jikigai-eu.sentry.io/api/0/organizations/jikigai-eu/issues/");
    // EU host literal, NOT eu.sentry.io
    expect(url).toContain("jikigai-eu.sentry.io");
    expect(url).not.toContain("//eu.sentry.io");
    // colon is encoded; the value cannot break out of the query string
    expect(url).toContain("query=event_type%3Aserver-startup");
    expect(url).toContain("project=web-platform");
  });

  it("a crafted query value cannot inject a second param", () => {
    const url = buildSentryUrl("h", "/p", { query: "a:b&admin=1" });
    const u = new URL(url);
    expect(u.searchParams.get("admin")).toBeNull();
    expect(u.searchParams.get("query")).toBe("a:b&admin=1");
  });
});

describe("computeRatePerDay", () => {
  const daily = (counts: number[]): Array<[number, number]> =>
    counts.map((c, i) => [1_700_000_000 + i * 86_400, c]);

  it("sums the last ceil(window/24) daily buckets and divides by days", () => {
    // 14 daily buckets; last 3 are 0,1,0 → sum 1 over 3 days → 1/3 per day
    const buckets = daily([9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 0, 1, 0]);
    const r = computeRatePerDay(buckets, 72);
    expect(r.sum).toBe(1);
    expect(r.days).toBe(3);
    expect(r.ratePerDay).toBeCloseTo(1 / 3, 5);
  });

  it("a still-churning issue exceeds the threshold", () => {
    const buckets = daily([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 40, 60, 12]);
    const r = computeRatePerDay(buckets, 72);
    expect(r.sum).toBe(112);
    expect(r.ratePerDay).toBeCloseTo(112 / 3, 5);
  });

  it("treats non-finite counts as 0", () => {
    const buckets: Array<[number, number]> = [
      [1, Number.NaN],
      [2, 3],
    ];
    expect(computeRatePerDay(buckets, 24).sum).toBe(3);
  });
});
