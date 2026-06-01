// #4689 follow-on — git-clone-128 was undiagnosable because spawnSimple
// discarded the child's stderr (`stdio: "ignore"`). When setupEphemeralWorkspace
// throws `git clone failed (exit 128, ...)`, the actual git reason
// (auth/network/DNS) never reached Sentry. This file pins that spawnSimple now
// returns the child's captured stderr alongside the exit code (real-spawn,
// offline: a bogus git subcommand writes usage to stderr).
//
// The security-critical redaction of the installation token out of the thrown
// clone-failure error is tested in cron-clone-redaction.test.ts (separate file
// because it `vi.mock`s node:child_process, which hoists file-wide and would
// clobber the real-spawn calls below).

import { describe, expect, it, vi } from "vitest";

vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

import { spawnSimple } from "@/server/inngest/functions/_cron-claude-eval-substrate";

describe("spawnSimple — stderr capture (clone-128 diagnosability)", () => {
  it("returns the child's stderr text alongside a non-zero exit code", async () => {
    // A guaranteed-failing git command that writes usage to stderr —
    // deterministic and offline.
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
