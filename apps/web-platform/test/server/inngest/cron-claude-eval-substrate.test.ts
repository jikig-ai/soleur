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

import { tmpdir } from "node:os";
import { afterEach, describe, expect, it, vi } from "vitest";

vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

import { resolveCronWorkspaceRoot } from "@/server/inngest/functions/_cron-shared";
import { spawnSimple } from "@/server/inngest/functions/_cron-claude-eval-substrate";

// #4684/#4689 — crons mkdtemp'd under os.tmpdir() (the 256 MB /tmp tmpfs in
// prod), so a git clone of the ~100 MB soleur tree ENOSPC'd. The fix routes the
// ephemeral-workspace parent through resolveCronWorkspaceRoot(), which prod sets
// to /workspaces (the roomy /mnt/data volume) via CRON_WORKSPACE_ROOT. This
// block pins the pure env→string resolution (the clone itself is not the unit
// under test); the docker-run wiring is asserted in ci-deploy.test.sh.
describe("resolveCronWorkspaceRoot", () => {
  const ORIGINAL = process.env.CRON_WORKSPACE_ROOT;
  afterEach(() => {
    if (ORIGINAL === undefined) delete process.env.CRON_WORKSPACE_ROOT;
    else process.env.CRON_WORKSPACE_ROOT = ORIGINAL;
  });

  it("returns CRON_WORKSPACE_ROOT when set", () => {
    process.env.CRON_WORKSPACE_ROOT = "/workspaces";
    expect(resolveCronWorkspaceRoot()).toBe("/workspaces");
  });

  it("falls back to os.tmpdir() when the env var is unset", () => {
    delete process.env.CRON_WORKSPACE_ROOT;
    expect(resolveCronWorkspaceRoot()).toBe(tmpdir());
  });

  it("falls back to os.tmpdir() when the env var is whitespace-only", () => {
    process.env.CRON_WORKSPACE_ROOT = "   ";
    expect(resolveCronWorkspaceRoot()).toBe(tmpdir());
  });

  it("trims surrounding whitespace from a set value", () => {
    process.env.CRON_WORKSPACE_ROOT = "  /workspaces  ";
    expect(resolveCronWorkspaceRoot()).toBe("/workspaces");
  });
});

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
