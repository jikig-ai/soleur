import { describe, test, expect } from "bun:test";
import {
  getLivenessCapabilities,
  type Harness,
  type LivenessCapabilities,
} from "../lib/harness";
import {
  classifySeatSilence,
  decideSeatRecovery,
  validateSeatMetadata,
   recordSeatHeartbeat,
  type SeatMetadata,
} from "../lib/agent-liveness";

const ALL_HARNESSES: readonly Harness[] = [
  "claude",
  "grok",
  "codex",
  "devin",
  "cursor",
  "opencode",
  "antigravity",
  "unknown",
] as const;

describe("getLivenessCapabilities (FR1)", () => {
  test("covers all 8 Harness values with deterministic capability flags", () => {
    for (const h of ALL_HARNESSES) {
      const caps: LivenessCapabilities = getLivenessCapabilities(h);
      expect(caps.harness).toBe(h);
      expect(typeof caps.inBandNudge).toBe("boolean");
      expect(typeof caps.asyncWait).toBe("boolean");
      expect(typeof caps.childDiskHeartbeat).toBe("boolean");
      expect(typeof caps.subagentHooks).toBe("boolean");
    }
  });

  test("claude supports inBandNudge, asyncWait, childDiskHeartbeat, and subagentHooks", () => {
    expect(getLivenessCapabilities("claude")).toEqual({
      harness: "claude",
      inBandNudge: true,
      asyncWait: true,
      childDiskHeartbeat: true,
      subagentHooks: true,
    });
  });

  test("codex and antigravity support inBandNudge and asyncWait without subagentHooks", () => {
    expect(getLivenessCapabilities("codex")).toEqual({
      harness: "codex",
      inBandNudge: true,
      asyncWait: true,
      childDiskHeartbeat: true,
      subagentHooks: false,
    });
    expect(getLivenessCapabilities("antigravity")).toEqual({
      harness: "antigravity",
      inBandNudge: true,
      asyncWait: true,
      childDiskHeartbeat: true,
      subagentHooks: false,
    });
  });

  test("devin, opencode, and cursor have inBandNudge=false and degrade gracefully (TR2)", () => {
    const devin = getLivenessCapabilities("devin");
    expect(devin.inBandNudge).toBe(false);
    expect(devin.asyncWait).toBe(true);
    expect(devin.childDiskHeartbeat).toBe(false);
    expect(devin.subagentHooks).toBe(false);

    const opencode = getLivenessCapabilities("opencode");
    expect(opencode.inBandNudge).toBe(false);
    expect(opencode.asyncWait).toBe(true);
    expect(opencode.childDiskHeartbeat).toBe(true);
    expect(opencode.subagentHooks).toBe(false);

    const cursor = getLivenessCapabilities("cursor");
    expect(cursor.inBandNudge).toBe(false);
    expect(cursor.asyncWait).toBe(false);
    expect(cursor.childDiskHeartbeat).toBe(false);
    expect(cursor.subagentHooks).toBe(false);
  });
});

function baseSeat(overrides: Partial<SeatMetadata> = {}): SeatMetadata {
  return {
    seat_id: "seat-review-security",
    harness: "claude",
    role: "soleur:engineering:review:security-sentinel",
    tier: "standard",
    writable: false,
    side_effecting: false,
    started_at: 1_000_000,
    last_progress_at: 1_000_000,
    deadline_at: 1_600_000, // 10 min absolute cap
    idle_timeout_ms: 120_000, // 2 min idle window
    attempt: 0,
    status: "running",
    classification: "alive",
    artifact_path: ".soleur/runs/run-1/out.json",
    ...overrides,
  };
}

describe("validateSeatMetadata (FR2 metadata-only boundary)", () => {
  test("accepts valid metadata-only seat state", () => {
    const seat = baseSeat();
    expect(validateSeatMetadata(seat as unknown as Record<string, unknown>).seat_id).toBe(
      "seat-review-security",
    );
  });

  test("rejects forbidden transcript, prompt, or secret fields", () => {
    expect(() =>
      validateSeatMetadata({
        ...baseSeat(),
        prompt: "raw user prompt text",
      } as unknown as Record<string, unknown>),
    ).toThrow(/forbidden|metadata-only/i);

    expect(() =>
      validateSeatMetadata({
        ...baseSeat(),
        transcript: "assistant output...",
      } as unknown as Record<string, unknown>),
    ).toThrow(/forbidden|metadata-only/i);
  });

  test("rejects secret-shaped values embedded in string fields", () => {
    const fakeKey = "sk-ant-" + "api03-abcdefghijklmnopqrstuvwxyz012345";
    expect(() =>
      validateSeatMetadata({
        ...baseSeat({ role: fakeKey }),
      } as unknown as Record<string, unknown>),
    ).toThrow(/secret|redaction/i);
  });
});

describe("classifySeatSilence (FR3)", () => {
  test("live control: active seat within idle window classifies as alive", () => {
    const seat = baseSeat();
    expect(classifySeatSilence(seat, { now: 1_050_000 })).toBe("alive");
  });

  test("slow-progress control: progress heartbeats reset idle window (legit_long_turn) but NEVER extend deadline_at", () => {
    let seat = baseSeat();
    seat = recordSeatHeartbeat(seat, 1_100_000);
    seat = recordSeatHeartbeat(seat, 1_200_000);
    expect(seat.deadline_at).toBe(1_600_000);
    expect(classifySeatSilence(seat, { now: 1_250_000 })).toBe("legit_long_turn");

    // Once absolute deadline_at is reached, even a recent progress heartbeat classifies as crash/timeout
    seat = recordSeatHeartbeat(seat, 1_595_000);
    expect(classifySeatSilence(seat, { now: 1_600_001 })).toBe("crash");
  });

  test("rate-limit control: HTTP 429/529 or quota message classifies as rate_limit", () => {
    const seat = baseSeat();
    expect(
      classifySeatSilence(seat, {
        now: 1_050_000,
        exited: true,
        exitCode: 1,
        error: { status: 429, message: "Rate limit exceeded" },
      }),
    ).toBe("rate_limit");

    expect(
      classifySeatSilence(seat, {
        now: 1_050_000,
        exited: true,
        exitCode: 1,
        error: "529 Overloaded: resource exhausted",
      }),
    ).toBe("rate_limit");
  });

  test("truncated control: zero exit code with missing artifact or failed completion floor classifies as truncated", () => {
    const seat = baseSeat();
    expect(
      classifySeatSilence(seat, {
        now: 1_080_000,
        exited: true,
        exitCode: 0,
        artifactPresent: false,
      }),
    ).toBe("truncated");

    expect(
      classifySeatSilence(seat, {
        now: 1_080_000,
        exited: true,
        exitCode: 0,
        artifactPresent: true,
        floorPassed: false,
      }),
    ).toBe("truncated");
  });

  test("hook-deferred control: hookDeferred signal classifies as hook_deferred", () => {
    const seat = baseSeat();
    expect(
      classifySeatSilence(seat, {
        now: 1_080_000,
        hookDeferred: true,
      }),
    ).toBe("hook_deferred");
  });

  test("dead/zombie control: silent past idle_timeout_ms or non-zero exit classifies as crash", () => {
    const seat = baseSeat();
    // Silent for 180s (> 120s idle_timeout_ms)
    expect(classifySeatSilence(seat, { now: 1_180_000 })).toBe("crash");
    // Exited non-zero without saturation error
    expect(
      classifySeatSilence(seat, {
        now: 1_030_000,
        exited: true,
        exitCode: 137,
      }),
    ).toBe("crash");
  });
});

describe("decideSeatRecovery (FR4 & FR5)", () => {
  test("accepts on-disk verified artifact or verified diff without respawning", () => {
    const seat = baseSeat({ classification: "crash", writable: true });
    const decision = decideSeatRecovery(seat, {
      dirtyDiff: true,
      diffVerified: true,
    });
    expect(decision.action).toBe("accept");
    expect(decision.reviewedCoverage).toBe("full");
    expect(decision.marker).toContain("SOLEUR_SEAT_LIVENESS");
    expect(decision.marker).toContain("action=accept");
  });

  test("writable seat with unverified dirty diff returns verify_disk first, never blind respawn", () => {
    const seat = baseSeat({ classification: "crash", writable: true });
    const unverified = decideSeatRecovery(seat, { dirtyDiff: true });
    expect(unverified.action).toBe("verify_disk");

    const failedVerify = decideSeatRecovery(seat, {
      dirtyDiff: true,
      diffVerified: false,
    });
    expect(failedVerify.action).toBe("escalate");
    expect(failedVerify.reviewedCoverage).toBe("degraded");
  });

  test("side_effecting seat never auto-respawns and escalates immediately", () => {
    const seat = baseSeat({
      classification: "crash",
      side_effecting: true,
      attempt: 0,
    });
    const decision = decideSeatRecovery(seat, {});
    expect(decision.action).toBe("escalate");
    expect(decision.reviewedCoverage).toBe("degraded");
  });

  test("paused/truncated seat on a harness with inBandNudge nudges once on attempt 0", () => {
    const seat = baseSeat({
      harness: "claude",
      classification: "hook_deferred",
      attempt: 0,
    });
    const decision = decideSeatRecovery(seat, {});
    expect(decision.action).toBe("nudge");
    expect(decision.nextAttempt).toBe(1);
    expect(decision.marker).toContain("action=nudge");
  });

  test("rate_limit seat on standard tier respawns once with resolveFallbackTier (cheap) on attempt 0", () => {
    const seat = baseSeat({
      harness: "devin",
      tier: "standard",
      classification: "rate_limit",
      attempt: 0,
    });
    const decision = decideSeatRecovery(seat, {});
    expect(decision.action).toBe("respawn");
    expect(decision.fallbackTier).toBe("cheap");
    expect(decision.nextAttempt).toBe(1);
    expect(decision.marker).toContain("action=respawn");
  });

  test("exhausted seat (attempt >= 1) never retries again and escalates with degraded coverage", () => {
    const seat = baseSeat({
      harness: "claude",
      classification: "rate_limit",
      attempt: 1,
    });
    const decision = decideSeatRecovery(seat, {});
    expect(decision.action).toBe("escalate");
    expect(decision.reviewedCoverage).toBe("degraded");
    expect(decision.marker).toContain("action=escalate");
  });
});

describe("fan-out workflow integration (FR6)", () => {
  const { readFileSync } = require("node:fs");
  const { resolve } = require("node:path");
  const skillsRoot = resolve(import.meta.dir, "../skills");

  const fanoutSkills = [
    "one-shot",
    "review",
    "resolve-parallel",
    "resolve-pr-parallel",
    "resolve-todo-parallel",
    "drain-labeled-backlog",
  ] as const;

  test("all 6 fan-out SKILL.md files reference seat-liveness.sh and ADR-332", () => {
    for (const s of fanoutSkills) {
      const md = readFileSync(resolve(skillsRoot, s, "SKILL.md"), "utf-8");
      expect(md, `${s}/SKILL.md should wire seat-liveness.sh`).toContain(
        "seat-liveness.sh",
      );
      expect(md, `${s}/SKILL.md should cite ADR-332`).toContain("ADR-332");
    }
  });

  test("all 5 fan-out .workflow.js scripts wire SOLEUR_SEAT_LIVENESS and reviewedCoverage", () => {
    const workflowSkills = [
      "review",
      "resolve-parallel",
      "resolve-pr-parallel",
      "resolve-todo-parallel",
      "drain-labeled-backlog",
    ] as const;
    for (const s of workflowSkills) {
      const wf = readFileSync(
        resolve(skillsRoot, s, "workflows", `${s}.workflow.js`),
        "utf-8",
      );
      expect(wf, `${s}.workflow.js should emit SOLEUR_SEAT_LIVENESS`).toContain(
        "SOLEUR_SEAT_LIVENESS",
      );
      expect(wf, `${s}.workflow.js should report reviewedCoverage`).toContain(
        "reviewedCoverage",
      );
    }
  });
});

