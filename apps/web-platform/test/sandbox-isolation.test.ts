/**
 * Cross-workspace isolation suite — Path C (hybrid) per
 * knowledge-base/project/specs/feat-verify-workspace-isolation/{spec,sdk-probe-notes}.md.
 *
 * Direct-bwrap cases (this file): FR2/3/4/5/7 — tier-4 process isolation, deterministic.
 * SDK-query cases (this file): FR2-smoke/8/9 — full-stack LLM sandbox, live API key.
 * Out of scope here: FR10/FR11 (LS, NotebookRead — covered by sandbox-hook/sandbox tests),
 * FR12 Task subagent (deferred follow-up). Coverage matrix pinned at EOF.
 */

import { randomBytes } from "node:crypto";
import fs from "node:fs";
import path from "node:path";
import { afterEach, beforeAll, describe, expect, test } from "vitest";
import {
  createNamedWorkspacePair,
  createWorkspacePair,
  linkEscape,
  probeSkip,
  rescueStaleFixtures,
  seedMarker,
  spawnBwrap,
  spawnSandboxB,
  type SandboxBHandle,
  type WorkspacePair,
} from "./helpers/sandbox-isolation-fixtures";

const directProbe = probeSkip("direct");

describe.runIf(!directProbe.skip)("sandbox-isolation: direct bwrap (tier 4)", () => {
  const pairs: WorkspacePair[] = [];
  const sandboxes: SandboxBHandle[] = [];

  beforeAll(() => {
    rescueStaleFixtures();
  });

  afterEach(async () => {
    while (sandboxes.length) {
      const handle = sandboxes.pop();
      if (!handle) continue;
      handle.kill();
      await handle.waitExit().catch(() => undefined);
    }
    while (pairs.length) {
      pairs.pop()?.cleanup();
    }
  });

  test("FR2: rootA sandbox cannot read rootB/secret.md (cat exits non-zero, marker absent)", () => {
    const pair = createWorkspacePair();
    pairs.push(pair);
    const { token } = seedMarker(pair.rootB, "secret.md");

    const result = spawnBwrap(
      pair.rootA,
      `cat ${shellQuote(pair.rootB + "/secret.md")}`,
      { pair, timeoutMs: 5_000 },
    );

    // Setup-failure guard: if bwrap itself failed (missing socat at runtime,
    // seccomp denial, etc.), the test signal is meaningless. Fail loudly.
    expect(result.setupFailed, `bwrap setup failed: ${result.stderr}`).toBe(false);
    // Isolation assertions: cat must have failed AND the marker must be absent
    // from combined stdio. Post-state is pinned (cq-mutation-assertions-pin-exact-post-state).
    expect(result.status).not.toBe(0);
    expect(result.stdout).not.toContain(token);
    expect(result.stderr).toMatch(/No such file|cannot open|Permission denied/);
  });

  test("FR3: rootA sandbox write to rootB/leaked.md does not mutate host rootB", () => {
    const pair = createWorkspacePair();
    pairs.push(pair);
    const preMarker = seedMarker(pair.rootB, "existing.md");
    const preEntries = fs.readdirSync(pair.rootB).sort();
    const leakPath = path.join(pair.rootB, "leaked.md");

    const result = spawnBwrap(
      pair.rootA,
      `echo "leaked-${Date.now()}" > ${shellQuote(leakPath)} 2>/dev/null; echo DONE`,
      { pair, timeoutMs: 5_000 },
    );

    expect(result.setupFailed, `bwrap setup failed: ${result.stderr}`).toBe(false);
    // Host-side assertions: rootB must be identical to pre-state. Inside the
    // sandbox the write may "succeed" against the tmpfs overlay (ephemeral),
    // but the host directory is the blast-radius boundary we care about.
    const postEntries = fs.readdirSync(pair.rootB).sort();
    expect(postEntries).toEqual(preEntries);
    expect(fs.existsSync(leakPath)).toBe(false);
    // Existing marker must be intact.
    expect(fs.readFileSync(preMarker.path, "utf8")).toBe(preMarker.token);
  });

  test("FR4: prefix collision (user1 vs user10) does not grant user1 sandbox access to user10", () => {
    const pair = createNamedWorkspacePair(["user1", "user10"]);
    pairs.push(pair);
    const { token } = seedMarker(pair.rootB, "secret.md");

    const result = spawnBwrap(
      pair.rootA,
      `cat ${shellQuote(pair.rootB + "/secret.md")}`,
      { pair, timeoutMs: 5_000 },
    );

    expect(result.setupFailed, `bwrap setup failed: ${result.stderr}`).toBe(false);
    expect(result.status).not.toBe(0);
    expect(result.stdout).not.toContain(token);
    expect(result.stderr).toMatch(/No such file|cannot open|Permission denied/);
  });

  test("FR7: rootA sandbox cannot read /proc/<rootB-pid>/environ (pid namespace isolation)", async () => {
    const pair = createWorkspacePair();
    pairs.push(pair);
    const sentinel = `FR7_SECRET_${randomBytes(8).toString("hex")}`;

    const handle = spawnSandboxB(pair.rootB, {
      pair,
      readyTimeoutMs: 5_000,
      env: { ...process.env, FR7_SECRET: sentinel },
    });
    sandboxes.push(handle);
    await handle.ready;
    const hostPid = handle.pid;

    // Precondition: on the HOST (outside any sandbox), /proc/<hostPid>/environ
    // MUST contain the sentinel. If not, the test lacks discriminative power —
    // sandboxA would appear isolated even though the target data was never there.
    const hostEnviron = fs.readFileSync(`/proc/${hostPid}/environ`, "utf8");
    expect(
      hostEnviron,
      `precondition: host /proc/${hostPid}/environ must contain sentinel`,
    ).toContain(sentinel);

    // Cross-read attempt from sandboxA. With --unshare-pid, sandboxA's /proc
    // reflects sandboxA's own pid namespace — host pid does not exist there.
    const result = spawnBwrap(
      pair.rootA,
      `cat /proc/${hostPid}/environ 2>&1; echo "__EXIT__$?"`,
      { pair, timeoutMs: 5_000 },
    );
    expect(result.setupFailed, `bwrap setup failed: ${result.stderr}`).toBe(false);
    expect(result.stdout).not.toContain(sentinel);
    // Must surface a no-such-file or permission-denied signal, otherwise we
    // somehow read a legitimate /proc/<pid>/environ and got lucky that the
    // sentinel wasn't there.
    expect(result.stdout + result.stderr).toMatch(
      /No such file|cannot open|Permission denied/,
    );
  });

  test("FR5: symlink escape from rootA to rootB/secret.md is blocked by tmpfs overlay", () => {
    const pair = createWorkspacePair();
    pairs.push(pair);
    const { token } = seedMarker(pair.rootB, "secret.md");
    linkEscape(pair.rootA, "peek", path.join(pair.rootB, "secret.md"));

    const result = spawnBwrap(
      pair.rootA,
      `cat ${shellQuote(pair.rootA + "/peek")}`,
      { pair, timeoutMs: 5_000 },
    );

    expect(result.setupFailed, `bwrap setup failed: ${result.stderr}`).toBe(false);
    // Following the symlink inside the sandbox must fail — rootB is tmpfs'd out,
    // so the link target does not resolve. Token MUST NOT appear in stdout.
    expect(result.status).not.toBe(0);
    expect(result.stdout).not.toContain(token);
    expect(result.stderr).toMatch(/No such file|cannot open|Permission denied/);
  });
});

// ---------- test-helpers ----------

function shellQuote(s: string): string {
  return `'${s.replace(/'/g, `'\\''`)}'`;
}

/**
 * Coverage matrix — do not remove. Phase 7 adds a load-time lint test.
 *
 * | Surface                | Tier | FRs covered                    |
 * | direct-bwrap / Bash    |   4  | FR2, FR3, FR4, FR5, FR7        |
 * | sdk-query / Bash       | full | FR2-smoke, FR8, FR9            |
 *
 * Tier-2/3 tool-path coverage: test/sandbox-hook.test.ts + test/sandbox.test.ts.
 */
export const COVERAGE = {
  "direct-bwrap/Bash": "FR2/FR3/FR4/FR5/FR7",
  "sdk-query/Bash": "FR2-smoke/FR8/FR9",
} as const;
