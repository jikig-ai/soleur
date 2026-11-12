// #8211, ADR-323 Decision 9 (2026-11-10 amendment) — the git env of cron-content-vendor-drift is built when git is
// spawned, never from a snapshot taken when the module loaded. index.ts deletes the relay hello keys from process.env
// at boot, AFTER the hoisted imports have evaluated this module, so a module-load snapshot (a `{ ...process.env }`, an
// Object.assign copy, or a cached `gitIsolatedEnv()` result) would still hand them to every git child.
//
// Behavioural: the module is imported with a sentinel variable already in process.env (standing in for a key present
// at module load); the test then deletes it, adds a second one, and drives the handler through BOTH git spawners: the
// clone (spawnGit, stdout ignored) succeeds against a synthesized fixture, the bundle arm runs, and its attestation-age
// read is a stdout-piped `git show` (spawnGitStdout). The env of EVERY git spawn must reflect both changes, so a
// snapshot used by only one of the two spawners is RED. Separate file because vi.mock is file-wide (the sibling suite
// imports the real module for its source-shape rows).

import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { EventEmitter } from "node:events";
import { afterAll, describe, expect, it, vi } from "vitest";

const SENTINELS = vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
  const s = { deleted: "R2_VENDOR_DRIFT_ENV_DELETED_AFTER_LOAD", added: "R2_VENDOR_DRIFT_ENV_ADDED_AFTER_LOAD" };
  process.env[s.deleted] = "present-at-module-load";
  delete process.env[s.added];
  return s;
});

// The clone fixture's layout. Pinned against the module's exported constants in the row below.
const FIXTURE = vi.hoisted(() => ({
  skillsDir: "plugins/soleur/skills",
  slug: "vendored-fixture",
  parser: "plugins/soleur/skills/gdpr-gate/scripts/notice-frontmatter.sh",
  classifier: "plugins/soleur/skills/gdpr-gate/scripts/vendor-drift-classify.sh",
}));

const { spawnSpy, state } = vi.hoisted(() => ({
  spawnSpy: vi.fn(),
  state: { workspaceRoot: "" },
}));

vi.mock("node:child_process", async (importOriginal) => {
  const actual = await importOriginal<typeof import("node:child_process")>();
  const fs = await import("node:fs");
  const path = await import("node:path");
  const spawn = (cmd: string, args: string[], opts: { stdio?: unknown[] } = {}) => {
    spawnSpy(cmd, args, opts);
    const code = 0;
    let out = "";
    if (cmd === "git" && args[0] === "clone") {
      // A clone that succeeds: one schema-conforming bundle plus the shared parser and classifier.
      const repoRoot = args[args.length - 1];
      const notice = path.join(repoRoot, FIXTURE.skillsDir, FIXTURE.slug, "NOTICE");
      for (const f of [notice, path.join(repoRoot, FIXTURE.parser), path.join(repoRoot, FIXTURE.classifier)]) {
        fs.mkdirSync(path.dirname(f), { recursive: true });
        fs.writeFileSync(f, "synthesized fixture\n");
      }
    } else if (cmd === "git" && opts.stdio?.[1] === "pipe") {
      out = "---\nlast-verified: 2026-11-01\n---\n"; // the `git show origin/main:<NOTICE>` read
    } else if (cmd === "bash") {
      const [, ...rest] = args; // [script, ...args]
      const key = rest.join(" ");
      if (key === "field upstream") out = "github.com/example/upstream\n";
      else if (key === "field pinned-commit") out = `${"a".repeat(40)}\n`;
      else if (key.startsWith("record-count") || key.startsWith("key-count")) out = "0\n";
    }
    const child = Object.assign(new EventEmitter(), {
      stderr: new EventEmitter(),
      stdout: new EventEmitter(),
      stdin: { write: () => true, end: () => {} },
    });
    setImmediate(() => {
      if (out) child.stdout.emit("data", Buffer.from(out));
      child.emit("exit", code, null);
      child.emit("close", code);
    });
    return child;
  };
  return { ...actual, spawn, default: { ...actual, spawn } };
});

vi.mock("@octokit/core", () => ({
  // Every GitHub call fails (no network): label creation is reported, the repo probe reads `unreachable`.
  Octokit: vi.fn().mockImplementation(function (this: Record<string, unknown>) {
    this.request = vi.fn(async () => {
      throw Object.assign(new Error("offline fixture"), { status: 503 });
    });
  }),
}));
vi.mock("@/server/observability", () => ({
  reportSilentFallback: vi.fn(),
  warnSilentFallback: vi.fn(),
  mirrorWarnWithDebounce: vi.fn(),
}));
vi.mock("@/server/inngest/client", () => ({ inngest: { createFunction: vi.fn(), send: vi.fn() } }));
vi.mock("@/server/inngest/functions/_cron-shared", async (importOriginal) => {
  const actual = await importOriginal<typeof import("@/server/inngest/functions/_cron-shared")>();
  return {
    ...actual,
    mintInstallationToken: vi.fn(async () => "ghs_test_token"),
    buildAuthenticatedCloneUrl: vi.fn(() => "file:///nonexistent-fixture-remote"),
    resolveCronWorkspaceRoot: vi.fn(() => state.workspaceRoot),
    warnIfCronWorkspaceLowOnDisk: vi.fn(async () => {}),
    postSentryHeartbeat: vi.fn(async () => {}),
  };
});

import {
  CLASSIFIER_REL,
  PARSER_REL,
  SKILLS_DIR_REL,
  cronContentVendorDriftHandler,
} from "@/server/inngest/functions/cron-content-vendor-drift";

afterAll(() => {
  if (state.workspaceRoot) rmSync(state.workspaceRoot, { recursive: true, force: true });
});

describe("cron-content-vendor-drift: the git env is read at spawn time (#8211)", () => {
  it("a variable deleted after the module loaded never reaches git, and one added after it does, on both git spawners", async () => {
    expect([FIXTURE.skillsDir, FIXTURE.parser, FIXTURE.classifier]).toEqual([SKILLS_DIR_REL, PARSER_REL, CLASSIFIER_REL]);
    state.workspaceRoot = mkdtempSync(join(tmpdir(), "vendor-drift-env-"));
    // The module has loaded (static import above) while the sentinel was set.
    expect(process.env[SENTINELS.deleted]).toBe("present-at-module-load");
    delete process.env[SENTINELS.deleted];
    process.env[SENTINELS.added] = "added-after-module-load";
    let result: unknown;
    try {
      const logger = { info: vi.fn(), warn: vi.fn(), error: vi.fn() };
      const step = { run: <T,>(_n: string, cb: () => Promise<T>) => cb() };
      result = await cronContentVendorDriftHandler({ step, logger } as never);
    } finally {
      delete process.env[SENTINELS.added];
    }
    // The handler got past setup into the bundle arm (not the top-level catch).
    expect(result).toMatchObject({ bundles: [{ slug: FIXTURE.slug }] });

    const gitCalls = spawnSpy.mock.calls.filter((c) => c[0] === "git");
    const stdio = (c: unknown[]) => (c[2] as { stdio?: unknown[] }).stdio ?? [];
    expect((gitCalls[0][1] as string[])[0]).toBe("clone");
    // Vacuity floors: both spawners ran. spawnGit ignores stdout; spawnGitStdout pipes it.
    expect(gitCalls.filter((c) => stdio(c)[1] === "ignore").length).toBeGreaterThanOrEqual(1);
    const piped = gitCalls.filter((c) => stdio(c)[1] === "pipe");
    expect(piped.length).toBeGreaterThanOrEqual(1);
    expect((piped[0][1] as string[])[0]).toBe("show");
    for (const call of gitCalls) {
      const env: Record<string, string | undefined> = (call[2] as { env?: NodeJS.ProcessEnv }).env ?? {};
      const label = (call[1] as string[]).join(" ");
      expect(SENTINELS.deleted in env, label).toBe(false);
      expect(env[SENTINELS.added], label).toBe("added-after-module-load");
      expect(env.GIT_CONFIG_GLOBAL, label).toBe("/dev/null"); // the isolated env, not a bare passthrough
    }
  });
});
