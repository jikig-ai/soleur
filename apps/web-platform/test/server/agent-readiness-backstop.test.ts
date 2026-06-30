import { describe, expect, it } from "vitest";
import { isInSandboxRevParseStrand } from "@/server/tool-labels";

// #5733 deliverable C2 (AC7) — the agent-context backstop predicate fires from
// the agent's OWN in-bwrap Step 0.0 rev-parse result, so a strand of ANY on-disk
// shape (escaping pointer / object-store residual the host confirm is blind to)
// is queryable. It MUST NOT false-positive a healthy probe (prints "true").
describe("isInSandboxRevParseStrand (#5733 C2)", () => {
  const PROBE = "git rev-parse --is-inside-work-tree";

  it("a healthy probe (output `true`) → NOT a strand", () => {
    expect(isInSandboxRevParseStrand(PROBE, "true\n")).toBe(false);
  });

  it('git "not a git repository" fatal → strand', () => {
    expect(
      isInSandboxRevParseStrand(
        PROBE,
        "fatal: not a git repository (or any of the parent directories): .git\n",
      ),
    ).toBe(true);
  });

  it("a bare `false` (not inside a work tree) → strand", () => {
    expect(isInSandboxRevParseStrand(PROBE, "false\n")).toBe(true);
  });

  it("any other `fatal:` line on the probe → strand", () => {
    expect(
      isInSandboxRevParseStrand(PROBE, "fatal: detected dubious ownership\n"),
    ).toBe(true);
  });

  it("a DIFFERENT git command that errors → NOT this strand (only the work-tree probe)", () => {
    expect(
      isInSandboxRevParseStrand("git status", "fatal: not a git repository\n"),
    ).toBe(false);
  });

  it("the probe wrapped in a cd/&& prelude is still detected", () => {
    expect(
      isInSandboxRevParseStrand(
        'cd "$WS" && git rev-parse --is-inside-work-tree',
        "fatal: not a git repository\n",
      ),
    ).toBe(true);
  });

  it("a non-git command is never a strand", () => {
    expect(isInSandboxRevParseStrand("ls -la", "fatal: not a git repository")).toBe(
      false,
    );
  });
});
