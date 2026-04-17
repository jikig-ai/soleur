import { describe, test, expect } from "vitest";
import { sanitizeProps } from "@/app/api/analytics/track/sanitize";

// Phase 1 RED tests for #2462 — server-side PII scrub of the `path` prop.
// See knowledge-base/project/plans/2026-04-17-fix-analytics-track-path-pii-plan.md
// §"Phase 1" for the full 17-case-group rationale. Each test asserts all
// three return fields (clean, dropped, scrubbed) since the return type is
// being extended additively with `scrubbed: string[]`.

describe("sanitizeProps — path PII scrub", () => {
  // Spec cases 1-10 (knowledge-base/project/specs/feat-fix-analytics-track-path-pii/spec.md).

  test("case 1 — email in path → [email] sentinel", () => {
    const out = sanitizeProps({ path: "/users/alice@example.com/settings" });
    expect(out.clean.path).toBe("/users/[email]/settings");
    expect(out.scrubbed).toEqual(["email"]);
    expect(out.dropped).toEqual([]);
  });

  test("case 2 — UUID v4 in path → [uuid] sentinel", () => {
    const out = sanitizeProps({
      path: "/u/550e8400-e29b-41d4-a716-446655440000/settings",
    });
    expect(out.clean.path).toBe("/u/[uuid]/settings");
    expect(out.scrubbed).toEqual(["uuid"]);
    expect(out.dropped).toEqual([]);
  });

  test("case 3 — 6+ digit run in path → [id] sentinel", () => {
    const out = sanitizeProps({ path: "/billing/customer/123456/invoices" });
    expect(out.clean.path).toBe("/billing/customer/[id]/invoices");
    expect(out.scrubbed).toEqual(["id"]);
    expect(out.dropped).toEqual([]);
  });

  test("case 4 — date with hyphens passes through (≤4 digit runs)", () => {
    const out = sanitizeProps({ path: "/blog/2026-04-17-foo" });
    expect(out.clean.path).toBe("/blog/2026-04-17-foo");
    expect(out.scrubbed).toEqual([]);
  });

  test("case 5 — version number with dots passes through", () => {
    const out = sanitizeProps({ path: "/docs/v12.4.1/install" });
    expect(out.clean.path).toBe("/docs/v12.4.1/install");
    expect(out.scrubbed).toEqual([]);
  });

  test("case 6 — query string passes through unchanged", () => {
    const out = sanitizeProps({ path: "/?q=hello" });
    expect(out.clean.path).toBe("/?q=hello");
    expect(out.scrubbed).toEqual([]);
  });

  test("case 7 — multiple patterns fire in one path, scrubbed in order", () => {
    const out = sanitizeProps({
      path: "/u/alice@example.com/550e8400-e29b-41d4-a716-446655440000",
    });
    expect(out.clean.path).toBe("/u/[email]/[uuid]");
    expect(out.scrubbed).toEqual(["email", "uuid"]);
  });

  test("case 8 — ordinary KB path passes through (regression: happy path)", () => {
    const out = sanitizeProps({ path: "/kb/docs/getting-started" });
    expect(out.clean.path).toBe("/kb/docs/getting-started");
    expect(out.scrubbed).toEqual([]);
  });

  test("case 9 — non-string path value passes through untouched", () => {
    const out = sanitizeProps({ path: 42 });
    expect(out.clean.path).toBe(42);
    expect(out.scrubbed).toEqual([]);
  });

  test("case 10 — 500-char non-PII path truncated to 200, scrubbed empty", () => {
    const long = "/".concat("a".repeat(499));
    const out = sanitizeProps({ path: long });
    expect(typeof out.clean.path).toBe("string");
    expect((out.clean.path as string).length).toBe(200);
    expect(out.scrubbed).toEqual([]);
  });

  // Plan cases 11-17 — edge cases locking design decisions beyond spec minimum.

  test("case 11 — uppercase UUID also scrubs (case-insensitive)", () => {
    const out = sanitizeProps({
      path: "/u/550E8400-E29B-41D4-A716-446655440000",
    });
    expect(out.clean.path).toBe("/u/[uuid]");
    expect(out.scrubbed).toEqual(["uuid"]);
  });

  test("case 12 — scrub runs BEFORE length-cap slice (FR4)", () => {
    // Input > 200 chars with the email fully inside the first 200. If the
    // implementation sliced BEFORE scrubbing, the raw email would survive in
    // the first-200-char window (position 179..191 here). Scrub-first
    // replaces the full email with [email] before slice touches the string.
    const prefix = "/a".repeat(90); // 180 chars, ends with "a" at pos 179
    const input = `${prefix}@example.com/tail${"z".repeat(50)}`;
    const out = sanitizeProps({ path: input });
    expect(typeof out.clean.path).toBe("string");
    expect(out.clean.path as string).toContain("[email]");
    expect(out.clean.path as string).not.toContain("@example.com");
    expect((out.clean.path as string).length).toBeLessThanOrEqual(200);
    expect(out.scrubbed).toEqual(["email"]);
  });

  test("case 13 — scrubbed array is unique-per-pattern when same pattern fires twice", () => {
    const out = sanitizeProps({ path: "/u/a@b.com/c@d.com" });
    expect(out.clean.path).toBe("/u/[email]/[email]");
    expect(out.scrubbed).toEqual(["email"]);
  });

  test("case 14 — multi-pattern scrubbed array is in scrub-application order", () => {
    const out = sanitizeProps({
      path: "/u/a@b.com/550e8400-e29b-41d4-a716-446655440000/654321",
    });
    expect(out.clean.path).toBe("/u/[email]/[uuid]/[id]");
    expect(out.scrubbed).toEqual(["email", "uuid", "id"]);
  });

  test("case 15 — dropped keys still report, scrub doesn't interfere", () => {
    const out = sanitizeProps({
      path: "x",
      email: "a@b.com",
      fingerprint: "f",
    });
    expect(out.clean).toEqual({ path: "x" });
    expect(out.dropped).toEqual(["email", "fingerprint"]);
    expect(out.scrubbed).toEqual([]);
  });

  test("case 16a — multi-part TLD email scrubs (plan deepen finding)", () => {
    const out = sanitizeProps({ path: "/u/alice.bob@example.co.uk/s" });
    expect(out.clean.path).toBe("/u/[email]/s");
    expect(out.scrubbed).toEqual(["email"]);
  });

  test("case 16b — plus-addressing email scrubs", () => {
    const out = sanitizeProps({ path: "/u/alice+tag@example.com/x" });
    expect(out.clean.path).toBe("/u/[email]/x");
    expect(out.scrubbed).toEqual(["email"]);
  });

  test("case 16c — underscores + hyphens in email scrub", () => {
    const out = sanitizeProps({ path: "/u/a_b-c@ex-am.co/x" });
    expect(out.clean.path).toBe("/u/[email]/x");
    expect(out.scrubbed).toEqual(["email"]);
  });

  test("case 16d — email regex is segment-bounded (NOT greedy across /)", () => {
    // If EMAIL_RE were `\S+@\S+\.\S+`, the WHOLE path would match as one
    // giant email. The correct pattern excludes slashes.
    const out = sanitizeProps({
      path: "/users/alice@example.com/settings/more",
    });
    expect(out.clean.path).toBe("/users/[email]/settings/more");
    expect(out.scrubbed).toEqual(["email"]);
  });

  test("case 17a — non-email @handle (no TLD suffix) does NOT scrub", () => {
    const out = sanitizeProps({ path: "/twitter/@handle" });
    expect(out.clean.path).toBe("/twitter/@handle");
    expect(out.scrubbed).toEqual([]);
  });

  test("case 17b — bare @ token does NOT scrub", () => {
    const out = sanitizeProps({ path: "/u/@/x" });
    expect(out.clean.path).toBe("/u/@/x");
    expect(out.scrubbed).toEqual([]);
  });

  test("case 17c — a@b without .TLD does NOT scrub", () => {
    const out = sanitizeProps({ path: "/u/a@b/x" });
    expect(out.clean.path).toBe("/u/a@b/x");
    expect(out.scrubbed).toEqual([]);
  });

  test("undefined props returns empty clean + empty scrubbed", () => {
    const out = sanitizeProps(undefined);
    expect(out.clean).toEqual({});
    expect(out.dropped).toEqual([]);
    expect(out.scrubbed).toEqual([]);
  });
});
