// Parity between the read side and the emit side of the per-host quiet-window reporter line (#11704, PR 11713 fix round).
//
// scripts/followthroughs/git-data-replication-signal.sh counts a Better Stack row as a "reporter row" when its raw text matches
// REPORTER_RE (the `match(raw, ...)` in its SQL), and reads the live-session count with `extract(raw, 'agent_sessions_live=([0-9]+)')`.
// The emitter is formatLiveSessionsLine (server/quiet-window.ts). The replication marker has the same kind of parity row
// (git-data-replication.test.ts, MARKER_RE); this is its twin for the reporter line, so a grammar change on either side fails here
// instead of turning every host into READ_UNCLEAN (no reporter row) in the flip's pause/signal reads.
//
// Reads a file outside the app (the signal script), so it is registered in test/repo-wide-suites.ts.
import { describe, it, expect, vi } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

vi.mock("@/lib/feature-flags/server", () => ({ isNewAgentSessionsPaused: vi.fn() }));
vi.mock("@/server/observability", () => ({
  warnSilentFallback: vi.fn(),
  infoSilentFallback: vi.fn(),
  reportSilentFallback: vi.fn(),
}));
vi.mock("@/server/logger", () => ({
  default: { info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() },
  createChildLogger: () => ({ info: vi.fn(), warn: vi.fn(), error: vi.fn(), debug: vi.fn() }),
}));

import { formatLiveSessionsLine } from "@/server/quiet-window";

const SIGNAL_SCRIPT = resolve(__dirname, "../../../scripts/followthroughs/git-data-replication-signal.sh");
const SRC = readFileSync(SIGNAL_SCRIPT, "utf8");

function reporterRe(): RegExp {
  const m = /^REPORTER_RE='([^']+)'$/m.exec(SRC);
  expect(m, "REPORTER_RE assignment not found in the signal script").not.toBeNull();
  return new RegExp(m![1]);
}

function liveExtractRe(): RegExp {
  const m = /extract\(raw,'(agent_sessions_live=\(\[0-9\]\+\))'\)/.exec(SRC);
  expect(m, "the agent_sessions_live extract() not found in the signal script SQL").not.toBeNull();
  return new RegExp(m![1]);
}

const CASES: Array<{ name: string; counts: Parameters<typeof formatLiveSessionsLine>[0]; paused: boolean }> = [
  { name: "idle, not paused", counts: { ccQueries: 0, legacySessions: 0 }, paused: false },
  { name: "idle, paused", counts: { ccQueries: 0, legacySessions: 0 }, paused: true },
  { name: "live sessions of every kind", counts: { ccQueries: 2, legacySessions: 1, startingSessions: 3, refusedSinceLast: 4 }, paused: false },
  { name: "paused with refusals", counts: { ccQueries: 0, legacySessions: 0, refusedSinceLast: 7 }, paused: true },
  { name: "counts at the cap", counts: { ccQueries: 5e9, legacySessions: 1, startingSessions: 0, refusedSinceLast: 5e9 }, paused: false },
  { name: "non-finite and negative inputs read as 0", counts: { ccQueries: Number.NaN, legacySessions: -3, startingSessions: Infinity }, paused: false },
];

describe("quiet-window reporter line: REPORTER_RE parity with formatLiveSessionsLine", () => {
  it.each(CASES)("REPORTER_RE (from the signal script) matches the line emitted for: $name", ({ counts, paused }) => {
    const line = formatLiveSessionsLine(counts, paused);
    expect(reporterRe().test(line)).toBe(true);
  });

  it.each(CASES)("the signal script's agent_sessions_live extract reads the emitted live count for: $name", ({ counts, paused }) => {
    const line = formatLiveSessionsLine(counts, paused);
    const m = liveExtractRe().exec(line);
    expect(m).not.toBeNull();
    // The first field of the line IS the live count (cc + legacy + starting, each capped and floored at 0).
    expect(m![1]).toBe(/^agent_sessions_live=(\d+) /.exec(line)![1]);
  });

  it("the regex is not vacuous: it rejects a changed grammar", () => {
    const re = reporterRe();
    const good = formatLiveSessionsLine({ ccQueries: 1, legacySessions: 0 }, false);
    expect(re.test(good)).toBe(true);
    expect(re.test(good.replace("refused_since_last", "refused_total"))).toBe(false);
    expect(re.test(good.replace("new_sessions_paused=0", "new_sessions_paused=2"))).toBe(false);
    expect(re.test(good.replace(/ starting=\d+/, ""))).toBe(false);
    expect(re.test("agent_sessions_live=1")).toBe(false);
  });
});
