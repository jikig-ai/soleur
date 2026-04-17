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

  // --- Review findings (PR #2462 multi-agent review) ---

  test("R1 — ReDoS bound: 100KB input scrubs in <100ms", () => {
    // Review P1 (security-sentinel): without a length bound, EMAIL_RE on
    // 100KB of 'a' + '@' causes quadratic backtracking. scrubPath now caps
    // input at MAX_SCRUB_INPUT_LEN = 400 before regex. Runtime bounded.
    const pathological =
      "/u/" + "a".repeat(50_000) + "@" + "b".repeat(50_000) + ".com";
    const t0 = Date.now();
    const out = sanitizeProps({ path: pathological });
    const elapsed = Date.now() - t0;
    expect(elapsed).toBeLessThan(100);
    expect(typeof out.clean.path).toBe("string");
    expect((out.clean.path as string).length).toBeLessThanOrEqual(200);
  });

  test("R2 — non-v4 UUID (v1, v7) also scrubs (review P2)", () => {
    // Review P2 (security-sentinel): v1 UUIDs encode MAC + timestamp —
    // stronger PII than v4. Restricting the regex to v4 would leak v1.
    // The regex now matches any 8-4-4-4-12 hex shape.
    const v1 = sanitizeProps({ path: "/u/550e8400-e29b-11d4-a716-446655440000" });
    expect(v1.clean.path).toBe("/u/[uuid]");
    expect(v1.scrubbed).toContain("uuid");

    const v7 = sanitizeProps({ path: "/u/018fabcd-1234-7000-8000-abcdef012345" });
    expect(v7.clean.path).toBe("/u/[uuid]");
    expect(v7.scrubbed).toContain("uuid");
  });

  test("R3 — CRLF / U+2028 / U+2029 / DEL are stripped from path before Plausible", () => {
    // Review P2 (security-sentinel): path never ran through sanitizeForLog.
    // Plausible's CSV export + log viewers treat LS/PS as row breaks — log
    // injection into the analytics pipeline.
    const out = sanitizeProps({
      path: "/kb\u2028fake_admin_view\nextra\u2029end\x7fdel",
    });
    expect(out.clean.path).toBe("/kbfake_admin_viewextraenddel");
    expect(out.clean.path).not.toMatch(/[\n\r\u2028\u2029\x7f]/);
  });

  test("R4 — percent-encoded @ (%40) scrubs as email (review P3)", () => {
    const out = sanitizeProps({ path: "/u/alice%40example.com/settings" });
    expect(out.clean.path).toBe("/u/[email]/settings");
    expect(out.scrubbed).toContain("email");
  });

  test("R5 — percent-encoded hyphen (%2D) UUID scrubs (review P3)", () => {
    const out = sanitizeProps({
      path: "/u/550e8400%2De29b%2D41d4%2Da716%2D446655440000/x",
    });
    expect(out.clean.path).toBe("/u/[uuid]/x");
    expect(out.scrubbed).toContain("uuid");
  });

  test("R6 — NBSP / tab adjacent to @ does NOT bypass email scrub (review P3)", () => {
    // Email local/domain character class now excludes whitespace AND @ AND /.
    // NBSP (\u00A0) is whitespace per \s, so NBSP-prefix splits into two
    // non-email segments — correct rejection, not a bypass.
    const nbsp = sanitizeProps({ path: "/u/alice\u00A0bob@example.com/x" });
    // The scrub matches "bob@example.com" — segment-bounded, not the full
    // local. This is the correct defense: no leaked literal `@example.com`.
    expect(nbsp.clean.path).toBe("/u/alice\u00A0[email]/x");
    expect(nbsp.scrubbed).toContain("email");
  });

  test("R7 — scrubbed return type is ScrubPatternName[] (union, not string[])", () => {
    // Review P2 (architecture): type narrows to a literal union so callers
    // get compile-time safety on `scrubbed.includes("emial")` typos.
    const out = sanitizeProps({ path: "/u/a@b.com" });
    // Runtime check: each entry is one of the three known names.
    for (const name of out.scrubbed) {
      expect(["email", "uuid", "id"]).toContain(name);
    }
  });

  test("R8 — UUID with 12-digit numeric tail scrubs as uuid only (not uuid+id)", () => {
    // Review P3 (test-design): pattern-interaction edge case. Scrub order
    // email→uuid→id means UUID collapses first; the 12-digit tail is gone
    // before LONG_DIGIT_RUN_RE runs. Pins the order invariant.
    const out = sanitizeProps({
      path: "/u/550e8400-e29b-41d4-a716-123456789012",
    });
    expect(out.clean.path).toBe("/u/[uuid]");
    expect(out.scrubbed).toEqual(["uuid"]);
  });

  test("R9 — IDN email with Latin-extended local scrubs", () => {
    // Review P3 (test-design): IDN/Unicode email coverage gap.
    const out = sanitizeProps({ path: "/u/müller@domain.de/x" });
    expect(out.clean.path).toBe("/u/[email]/x");
    expect(out.scrubbed).toContain("email");
  });
});
