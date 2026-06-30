import { describe, expect, it } from "vitest";
import { isInSandboxRevParseStrand } from "@/server/tool-labels";

// #5733 deliverable D3 — the agent-context backstop predicate must recognise the
// STDERR-SUPPRESSED empty-output form the agent's `/soleur:go` Step 0.0 actually
// produces (`git rev-parse … 2>/dev/null || true` → empty stdout). The previous
// detector matched only `not a git repository` / `^fatal:` / bare `false`, so the
// `|| true`-swallowed empty output slipped through → the strand was unqueryable
// (0 prod events). The verdict is now: a work-tree probe whose output carries NO
// standalone `true` token is a strand.
describe("isInSandboxRevParseStrand (#5733 D3 — empty-output strand)", () => {
  // The EXACT go.md Step 0.0 command (commands/go.md).
  const GO_STEP_00 =
    "git rev-parse --is-bare-repository 2>/dev/null || true; git rev-parse --is-inside-work-tree 2>/dev/null || true";
  const PROBE = "git rev-parse --is-inside-work-tree";

  it("AC1: the go.md Step 0.0 command with EMPTY output → strand", () => {
    expect(isInSandboxRevParseStrand(GO_STEP_00, "")).toBe(true);
    expect(isInSandboxRevParseStrand(GO_STEP_00, "\n")).toBe(true);
    expect(isInSandboxRevParseStrand(GO_STEP_00, "   \n  ")).toBe(true);
  });

  it("AC1: healthy compound output `false\\ntrue` (not bare, IS a work tree) → NOT a strand", () => {
    expect(isInSandboxRevParseStrand(GO_STEP_00, "false\ntrue\n")).toBe(false);
  });

  it("AC1: bare-repo output `true\\nfalse` (a bare repo to make a worktree from) → NOT a strand", () => {
    expect(isInSandboxRevParseStrand(GO_STEP_00, "true\nfalse\n")).toBe(false);
  });

  it("a lone `true` (the simple probe healthy path) → NOT a strand", () => {
    expect(isInSandboxRevParseStrand(PROBE, "true\n")).toBe(false);
  });

  // Keep the pre-existing failure-signal cases green (regression guard).
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

  it("the probe wrapped in a cd/&& prelude is still detected (empty output)", () => {
    expect(
      isInSandboxRevParseStrand(
        'cd "$WS" && git rev-parse --is-inside-work-tree 2>/dev/null || true',
        "",
      ),
    ).toBe(true);
  });

  // AC1 negative — a NON-probe command that merely EMBEDS the rev-parse tokens
  // (e.g. echoing/grepping the probe string) with empty output must NOT be a
  // strand: the command guard requires the probe to be the operative statement,
  // not a substring inside an unrelated command (architecture-review bound).
  it("AC1: a non-probe command embedding the tokens with empty output → NOT a strand", () => {
    expect(
      isInSandboxRevParseStrand(
        'echo "git rev-parse --is-inside-work-tree"',
        "",
      ),
    ).toBe(false);
    expect(
      isInSandboxRevParseStrand(
        "grep -r 'rev-parse --is-inside-work-tree' .",
        "",
      ),
    ).toBe(false);
  });

  it("a DIFFERENT git command → NOT this strand (only the work-tree probe)", () => {
    expect(
      isInSandboxRevParseStrand("git status", "fatal: not a git repository\n"),
    ).toBe(false);
  });

  it("a non-git command is never a strand", () => {
    expect(
      isInSandboxRevParseStrand("ls -la", "fatal: not a git repository"),
    ).toBe(false);
  });
});
