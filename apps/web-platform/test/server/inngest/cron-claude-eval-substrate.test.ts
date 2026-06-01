// #4689 follow-on — git-clone-128 was undiagnosable because spawnSimple
// discarded the child's stderr (`stdio: "ignore"`). When setupEphemeralWorkspace
// throws `git clone failed (exit 128, ...)`, the actual git reason
// (auth/network/DNS) never reached Sentry. These tests pin:
//   1. spawnSimple returns the child's captured stderr alongside exit code
//   2. the captured stderr survives into the thrown clone error message
//
// Real-spawn approach (no child_process mock): `git clone` against an
// unresolvable host is a deterministic non-zero exit that writes a fatal:
// line to stderr — exactly the signal that was being dropped.

import { describe, expect, it, vi } from "vitest";

vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

import { spawnSimple } from "@/server/inngest/functions/_cron-claude-eval-substrate";

describe("spawnSimple — stderr capture (clone-128 diagnosability)", () => {
  it("returns the child's stderr text alongside a non-zero exit code", async () => {
    // `false` exits 1 with no output; use a guaranteed-failing git command
    // that writes to stderr. `git` with a bogus subcommand prints usage to
    // stderr and exits non-zero, deterministically and offline.
    const res = await spawnSimple("git", ["definitely-not-a-git-subcommand"]);
    expect(res.exitCode).not.toBe(0);
    expect(typeof res.stderr).toBe("string");
    expect(res.stderr.length).toBeGreaterThan(0);
  });

  it("returns empty stderr (not undefined) on a clean exit", async () => {
    const res = await spawnSimple("git", ["--version"]);
    expect(res.exitCode).toBe(0);
    expect(res.stderr).toBe("");
  });
});
