/**
 * Cross-workspace isolation suite — Path C (hybrid) per
 * knowledge-base/project/specs/feat-verify-workspace-isolation/{spec,sdk-probe-notes}.md.
 *
 * Direct-bwrap cases (this file): FR2/3/4/5/7 — tier-4 process isolation, deterministic.
 * SDK-query cases (this file): FR2-smoke/8/9 — full-stack LLM sandbox, live API key.
 * Out of scope here: FR10/FR11 (LS, NotebookRead — covered by sandbox-hook/sandbox tests),
 * FR12 Task subagent (deferred follow-up). Coverage matrix pinned at EOF.
 */

import { afterEach, beforeAll, describe, expect, test } from "vitest";
import {
  createWorkspacePair,
  probeSkip,
  rescueStaleFixtures,
  seedMarker,
  spawnBwrap,
  type WorkspacePair,
} from "./helpers/sandbox-isolation-fixtures";

const directProbe = probeSkip("direct");

describe.runIf(!directProbe.skip)("sandbox-isolation: direct bwrap (tier 4)", () => {
  const pairs: WorkspacePair[] = [];

  beforeAll(() => {
    rescueStaleFixtures();
  });

  afterEach(() => {
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
      {
        pair,
        timeoutMs: 5_000,
        // PHASE-3.3 TDD INVERSION — relax isolation to prove the test discriminates.
        // Binding rootB into the sandbox should make cat succeed and stdout contain
        // the marker. Remove before committing the restored state.
        extraArgs: ["--bind", pair.rootB, pair.rootB],
      },
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
