import { describe, it, expect } from "vitest";
import {
  segmentToDrillLevel,
  DRILL_SEGMENTS,
  isKbDocView,
} from "@/hooks/segment-to-drill-level";

describe("segmentToDrillLevel — sole drill-state authority (RQ8 / AC4c)", () => {
  it("returns null at the dashboard root", () => {
    expect(segmentToDrillLevel("/dashboard")).toBeNull();
  });

  it.each([
    ["/dashboard/kb", "kb"],
    ["/dashboard/kb/engineering/adr-044.md", "kb"],
    ["/dashboard/settings", "settings"],
    ["/dashboard/settings/members", "settings"],
    ["/dashboard/chat", "chat"],
    ["/dashboard/chat/abc-123", "chat"],
  ])("drills %s → %s", (pathname, expected) => {
    expect(segmentToDrillLevel(pathname)).toBe(expected);
  });

  // RQ6 / Kieran P0-1: analytics lives UNDER /dashboard/admin and must NOT
  // drill — the allowlist is the whole point. A denylist would break here.
  it.each([
    "/dashboard/admin/analytics",
    "/dashboard/admin",
    "/dashboard/admin/anything/deeper",
  ])("does NOT drill the admin route %s", (pathname) => {
    expect(segmentToDrillLevel(pathname)).toBeNull();
  });

  it("does not false-match a segment that is only a path-substring", () => {
    // `/dashboard/kbx` is a different route, not the kb section.
    expect(segmentToDrillLevel("/dashboard/kbx")).toBeNull();
    expect(segmentToDrillLevel("/dashboard/settings-archive")).toBeNull();
  });

  it("exposes exactly the three allowlisted segments", () => {
    expect([...DRILL_SEGMENTS].sort()).toEqual(["chat", "kb", "settings"]);
  });
});

// #4915: isKbDocView is the depth-within-section companion that drives the
// one-back-per-state wiring (band suppressBack + KB page-header back key on it).
describe("isKbDocView — KB doc view vs landing (one-back-per-state predicate)", () => {
  it("is true ONLY for a path BELOW /dashboard/kb/ (a doc is open)", () => {
    expect(isKbDocView("/dashboard/kb/engineering/adr-044.md")).toBe(true);
    expect(isKbDocView("/dashboard/kb/x.md")).toBe(true);
  });

  it("is false on the KB landing and every non-doc route", () => {
    expect(isKbDocView("/dashboard/kb")).toBe(false); // landing, not a doc
    expect(isKbDocView("/dashboard")).toBe(false);
    expect(isKbDocView("/dashboard/settings/members")).toBe(false);
    expect(isKbDocView("/dashboard/kbx")).toBe(false); // substring, not the section
  });
});
