import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import path from "node:path";

// AC5 (2026-06-15 login-blocking fix): configure-auth.sh MUST set the GoTrue
// rate-limit ceilings in its PATCH payload as JSON KEYS (not just comments),
// so a re-run raises them off the over-aggressive prd actuals (email_sent=2/hr)
// that locked legitimate users out. Source-grep regression guard — a standalone
// file (no node:fs mock to collide with) per the regex-on-source learning.
//
// This is config, not behavior, so positive key-presence assertions are the
// only available gate. The negative-space half (the fields must be real JSON
// keys, not just prose in a comment) is enforced by requiring the
// `"key": <integer>` shape rather than a bare substring match.

const SCRIPT_PATH = path.resolve(
  __dirname,
  "../supabase/scripts/configure-auth.sh",
);
const src = readFileSync(SCRIPT_PATH, "utf8");

describe("configure-auth.sh GoTrue rate-limit ceilings (AC5)", () => {
  it("sets rate_limit_email_sent as an integer JSON key in the PATCH payload", () => {
    expect(src).toMatch(/"rate_limit_email_sent"\s*:\s*\d+/);
  });

  it("sets rate_limit_verify as an integer JSON key in the PATCH payload", () => {
    expect(src).toMatch(/"rate_limit_verify"\s*:\s*\d+/);
  });

  it("documents the defense relaxation with an old->new ceiling comment", () => {
    // Defense-relaxation discipline: the old value the new ceiling no longer
    // bounds must be named in-script (2026-05-05-defense-relaxation rule).
    expect(src).toMatch(/->/);
    expect(src).toMatch(/rate_limit_email_sent:\s*2\b/);
  });
});
