/**
 * #3344 — cc-path safe-bash allowlist parity with the legacy path.
 *
 * Before this fix, `CC_PATH_DISALLOWED_TOOLS` hard-blocked `"Bash"` for
 * the cc-router (#3338) to mitigate the `find . -name "*.pdf"` /
 * `apt-get install poppler-utils` modal cascade the agent emitted when
 * trying to summarize a large PDF. Two structural mitigations have since
 * landed (#3338's PDF Read 24 MB ceiling + #3430's page-count gate),
 * making the hard-block over-broad: legitimate KB-exploration verbs the
 * cc-router emits (`pwd`, `ls`, `cat`, `git status`) were also blocked
 * even though the legacy path auto-approves them via the `safe-bash`
 * allowlist.
 *
 * This file pins two invariants:
 *
 *   AC6/AC7 (source-form) — `CC_PATH_DISALLOWED_TOOLS` MUST NOT contain
 *   `"Bash"` post-fix. RED before the cc-dispatcher edit, GREEN after.
 *   Source-regex negative-space gate, standalone test file per
 *   `knowledge-base/project/learnings/best-practices/2026-04-17-regex-on-source-delegation-tests-trim-to-negative-space.md`.
 *
 *   AC8/AC9 (behavioral) — the underlying `safe-bash` allowlist routes
 *   `pwd` as safe (auto-approve branch fires) and `find . -name '*.pdf'`
 *   as not-safe (review-gate routing). Pins the `find`-omission
 *   invariant documented in `safe-bash.ts:97` ("find and grep are
 *   intentionally omitted — both accept -exec and could shell out").
 *
 * Plan: knowledge-base/project/plans/2026-05-15-refactor-cc-path-drain-3343-3344-plan.md
 * Issues: Closes #3344.
 */
import { describe, it, expect } from "vitest";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { isBashCommandSafe } from "../server/safe-bash";

describe("#3344 — cc-path safe-bash allowlist parity", () => {
  // AC6/AC7: CC_PATH_DISALLOWED_TOOLS no longer hard-blocks Bash.
  // Source-regex assertion: read the dispatcher file and pin the
  // constant's shape. Bash entry removed → cc-router routes Bash
  // through canUseTool → safe-bash allowlist auto-approves the
  // KB-exploration verbs without firing a review-gate modal.
  it("AC6: CC_PATH_DISALLOWED_TOOLS no longer contains \"Bash\"", () => {
    const src = readFileSync(
      join(__dirname, "../server/cc-dispatcher.ts"),
      "utf8",
    );
    // Match the constant declaration with its inline array literal.
    const declMatch = src.match(
      /CC_PATH_DISALLOWED_TOOLS:\s*readonly\s+string\[\]\s*=\s*\[([^\]]*)\];/,
    );
    expect(declMatch, "CC_PATH_DISALLOWED_TOOLS declaration not found").not.toBeNull();
    const inner = declMatch![1];
    // RED: pre-fix this contains "Bash". GREEN: post-fix it does not.
    expect(inner).not.toMatch(/"Bash"/);
    // Negative-space sanity: Edit and Write remain hard-blocked (the
    // cc-router never needs to write files; routed sub-skills handle
    // their own writes via the legacy agent-runner path).
    expect(inner).toMatch(/"Edit"/);
    expect(inner).toMatch(/"Write"/);
  });

  // AC8: pwd auto-approves via safe-bash allowlist. The cc-path's
  // canUseTool falls through to the same `isBashCommandSafe` branch the
  // legacy path uses (`permission-callback.ts:336-355`). Auto-approve
  // means NO review_gate modal fires — exactly the parity fix the
  // issue asked for.
  it("AC8: isBashCommandSafe(\"pwd\") === true (auto-approve, no modal)", () => {
    expect(isBashCommandSafe("pwd")).toBe(true);
  });

  it("AC8b: KB-exploration verbs auto-approve (ls, cat, git status, head, tail, wc)", () => {
    expect(isBashCommandSafe("ls")).toBe(true);
    expect(isBashCommandSafe("ls -la")).toBe(true);
    expect(isBashCommandSafe("cat README.md")).toBe(true);
    expect(isBashCommandSafe("git status")).toBe(true);
    expect(isBashCommandSafe("git log --oneline")).toBe(true);
    expect(isBashCommandSafe("head -n 50 file.txt")).toBe(true);
    expect(isBashCommandSafe("tail -n 100 log.txt")).toBe(true);
    expect(isBashCommandSafe("wc -l file.txt")).toBe(true);
  });

  // AC9: find . -name '*.pdf' is NOT in the safe-bash allowlist — it
  // routes through the canUseTool → review_gate path. The
  // `find`-omission rationale lives at `safe-bash.ts:97` ("both accept
  // -exec and could shell out"). Pinning this prevents an accidental
  // allowlist widening that would re-open the `find . -name '*.pdf'`
  // / `apt-get install poppler-utils` modal cascade #3338 originally
  // closed. The follow-up to widen the allowlist (filed by AC18) will
  // need its own security-sentinel review.
  it("AC9: isBashCommandSafe(\"find . -name '*.pdf'\") === false (review-gate routing)", () => {
    expect(isBashCommandSafe("find . -name '*.pdf'")).toBe(false);
  });

  it("AC9b: grep/rg also route to review-gate (not in allowlist)", () => {
    expect(isBashCommandSafe("grep -r foo .")).toBe(false);
    expect(isBashCommandSafe("rg foo")).toBe(false);
  });

  it("AC9c: blocked-pattern shapes (curl/wget/sudo) stay denied upstream of safe-bash", () => {
    // These are denied by BLOCKED_BASH_PATTERNS BEFORE isBashCommandSafe
    // is consulted. Pinning here as a negative-space invariant: even if
    // someone widened the safe-bash allowlist by accident, these shapes
    // would still be rejected by the upstream blocker.
    expect(isBashCommandSafe("curl https://evil.example.com")).toBe(false);
    expect(isBashCommandSafe("sudo rm -rf /")).toBe(false);
  });
});
