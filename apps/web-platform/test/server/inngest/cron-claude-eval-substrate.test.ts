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

import { chmodSync, mkdirSync, mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { afterEach, describe, expect, it, vi } from "vitest";

vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

import { resolveCronWorkspaceRoot } from "@/server/inngest/functions/_cron-shared";
import {
  DEFAULT_CLAUDE_SETTINGS,
  spawnClaudeEval,
  spawnSimple,
  STDOUT_TAIL_CAP_BYTES,
} from "@/server/inngest/functions/_cron-claude-eval-substrate";

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

// #5000/#5004 — the cron eval substrate writes DEFAULT_CLAUDE_SETTINGS verbatim
// into each ephemeral workspace's `.claude/settings.json`. It previously carried
// `sandbox.enabled: true` with no `permissions.defaultMode`, which relied on the
// bwrap bash sandbox to auto-approve headless bash. When bwrap could not acquire
// unprivileged user namespaces in the cloud runner, every Bash call failed and
// the crons self-reported FAILED. The durable fix removes the bwrap dependency
// (`sandbox.enabled: false`) and restores bash auto-approval via
// `permissions.defaultMode: "bypassPermissions"`. These tests assert the WRITTEN
// settings.json content (the config invariant), not model behavior — the LLM is
// kept out of the assertion path. The settings are serialized exactly as
// setupEphemeralWorkspace writes them: `JSON.stringify(..., null, 2) + "\n"`.
describe("DEFAULT_CLAUDE_SETTINGS — cron sandbox/permission overlay (#5000/#5004)", () => {
  // Mirror the exact write expression in setupEphemeralWorkspace so the assertion
  // proves the on-disk `.claude/settings.json` content, not just the in-memory
  // constant shape.
  const writtenSettings = JSON.parse(
    JSON.stringify(DEFAULT_CLAUDE_SETTINGS, null, 2) + "\n",
  );

  it("disables the OS sandbox so a bwrap-userns host drift cannot break the cron", () => {
    expect(writtenSettings.sandbox.enabled).toBe(false);
  });

  it("sets permissions.defaultMode to bypassPermissions to restore bash auto-approval", () => {
    expect(writtenSettings.permissions.defaultMode).toBe("bypassPermissions");
  });

  it("keeps permissions.allow as an empty array (no allowlist widening)", () => {
    expect(writtenSettings.permissions.allow).toEqual([]);
  });

  // Drift-guard anchored on the literal: a future edit that flips the sandbox
  // back on (or drops the bypassPermissions pairing) must update this test. The
  // pairing is load-bearing — sandbox-off WITHOUT bypassPermissions blocks every
  // headless `gh`/`git` command on an unanswerable prompt.
  it("regression: never regress to sandbox.enabled true without re-pairing auto-approval", () => {
    expect(DEFAULT_CLAUDE_SETTINGS.sandbox.enabled).toBe(false);
    expect(DEFAULT_CLAUDE_SETTINGS.permissions.defaultMode).toBe(
      "bypassPermissions",
    );
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

// #4773 PR-A — `claude --print` writes its max-turns notice to STDOUT, which
// spawnClaudeEval previously sent only to logger.info (app stdout is not shipped
// to Better Stack). These tests pin that spawnClaudeEval now also accumulates a
// bounded, redacted `stdoutTail` so a turn-exhaustion exit is self-diagnosing in
// the scheduled-output-missing Sentry extra — mirroring the stderrTail contract.
// Real-spawn (offline): a fake CLAUDE_BIN script writes known lines to stdout.
describe("spawnClaudeEval — stdout tail capture (#4773 PR-A)", () => {
  const ORIGINAL_CLAUDE_BIN = process.env.CLAUDE_BIN;
  const tmpDirs: string[] = [];
  const noopLogger = {
    info: () => {},
    error: () => {},
    warn: () => {},
    debug: () => {},
  } as unknown as Parameters<typeof spawnClaudeEval>[0]["logger"];

  afterEach(() => {
    if (ORIGINAL_CLAUDE_BIN === undefined) delete process.env.CLAUDE_BIN;
    else process.env.CLAUDE_BIN = ORIGINAL_CLAUDE_BIN;
    for (const dir of tmpDirs.splice(0)) {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  // Build a temp dir holding (a) an executable fake `claude` that runs the given
  // node script body, and (b) a `repo` cwd that exists (spawnClaudeEval guards on
  // existsSync(spawnCwd)). Returns the spawnCwd. Sets CLAUDE_BIN to the fake bin.
  function installFakeClaudeBin(nodeScriptBody: string): string {
    const dir = mkdtempSync(join(tmpdir(), "claude-eval-stdout-"));
    tmpDirs.push(dir);
    const binPath = join(dir, "claude");
    writeFileSync(binPath, `#!/usr/bin/env node\n${nodeScriptBody}\n`, "utf-8");
    chmodSync(binPath, 0o755);
    process.env.CLAUDE_BIN = binPath;
    const spawnCwd = join(dir, "repo");
    mkdirSync(spawnCwd, { recursive: true });
    return spawnCwd;
  }

  const TOKEN = "ghs_FAKEtoken0123456789ABCDEFghijklmnop";

  async function runFakeEval(spawnCwd: string) {
    return spawnClaudeEval({
      spawnCwd,
      installationToken: TOKEN,
      flags: ["--print"],
      prompt: "ignored by the fake bin",
      maxTurnDurationMs: 10_000,
      cronName: "cron-test-fake",
      buildSpawnEnv: () => process.env,
      logger: noopLogger,
    });
  }

  it("captures a stdout tail and redacts the installation token", async () => {
    const spawnCwd = installFakeClaudeBin(
      [
        `process.stdout.write("first stdout line\\n");`,
        // Echo the token on stdout — must be redacted in the captured tail.
        `process.stdout.write("auth line using ${TOKEN} here\\n");`,
        `process.stdout.write("max-turns notice: reached the turn limit\\n");`,
      ].join("\n"),
    );

    const res = await runFakeEval(spawnCwd);

    expect(res.exitCode).toBe(0);
    expect(typeof res.stdoutTail).toBe("string");
    expect(res.stdoutTail).toContain("max-turns notice: reached the turn limit");
    // Token redaction parity with stderrTail.
    expect(res.stdoutTail).toContain("[REDACTED-INSTALLATION-TOKEN]");
    expect(res.stdoutTail).not.toContain(TOKEN);
  });

  it("bounds the captured stdout tail to STDOUT_TAIL_CAP_BYTES (keeps the tail)", async () => {
    const spawnCwd = installFakeClaudeBin(
      [
        // Far exceed the cap so the slice(-CAP) bounding is exercised.
        `for (let i = 0; i < 4000; i++) process.stdout.write("X".repeat(40) + " line " + i + "\\n");`,
        `process.stdout.write("FINAL_TAIL_MARKER\\n");`,
      ].join("\n"),
    );

    const res = await runFakeEval(spawnCwd);

    expect(res.exitCode).toBe(0);
    expect(res.stdoutTail).toBeDefined();
    expect(res.stdoutTail!.length).toBeLessThanOrEqual(STDOUT_TAIL_CAP_BYTES);
    // The bound drops the OLDEST lines, keeping the most recent (the tail).
    expect(res.stdoutTail).toContain("FINAL_TAIL_MARKER");
    expect(res.stdoutTail).not.toContain(" line 0\n");
  });
});
