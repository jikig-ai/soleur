import { describe, test, expect } from "bun:test";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
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
  sanitizeSeatIdForMarker,
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

  test("grok supports asyncWait and childDiskHeartbeat without inBandNudge or subagentHooks", () => {
    expect(getLivenessCapabilities("grok")).toEqual({
      harness: "grok",
      inBandNudge: false,
      asyncWait: true,
      childDiskHeartbeat: true,
      subagentHooks: false,
    });
  });

  test("devin, opencode, cursor, and unknown have inBandNudge=false and degrade gracefully (TR2)", () => {
    expect(getLivenessCapabilities("devin")).toEqual({
      harness: "devin",
      inBandNudge: false,
      asyncWait: true,
      childDiskHeartbeat: false,
      subagentHooks: false,
    });

    expect(getLivenessCapabilities("opencode")).toEqual({
      harness: "opencode",
      inBandNudge: false,
      asyncWait: true,
      childDiskHeartbeat: true,
      subagentHooks: false,
    });

    expect(getLivenessCapabilities("cursor")).toEqual({
      harness: "cursor",
      inBandNudge: false,
      asyncWait: false,
      childDiskHeartbeat: false,
      subagentHooks: false,
    });

    expect(getLivenessCapabilities("unknown")).toEqual({
      harness: "unknown",
      inBandNudge: false,
      asyncWait: false,
      childDiskHeartbeat: false,
      subagentHooks: false,
    });
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
    expect(
      validateSeatMetadata(seat as unknown as Record<string, unknown>).seat_id,
    ).toBe("seat-review-security");
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

  test("rejects non-primitive nested payloads, multiline strings, or oversized strings under allowlisted keys", () => {
    expect(() =>
      validateSeatMetadata({
        ...baseSeat(),
        role: { nested: "object" },
      } as unknown as Record<string, unknown>),
    ).toThrow(/primitive|metadata-only/i);

    expect(() =>
      validateSeatMetadata({
        ...baseSeat({ role: "line1\nline2" }),
      } as unknown as Record<string, unknown>),
    ).toThrow(/single-line|metadata-only/i);

    expect(() =>
      validateSeatMetadata({
        ...baseSeat({ role: "x".repeat(600) }),
      } as unknown as Record<string, unknown>),
    ).toThrow(/length|metadata-only/i);
  });

  test("rejects invalid seat_id or path-traversal artifact_path and sanitizes marker IDs", () => {
    expect(() =>
      validateSeatMetadata({
        ...baseSeat({ seat_id: "../escape" }),
      } as unknown as Record<string, unknown>),
    ).toThrow(/invalid seat metadata/i);

    expect(() =>
      validateSeatMetadata({
        ...baseSeat({ artifact_path: "../outside/out.json" }),
      } as unknown as Record<string, unknown>),
    ).toThrow(/artifact_path/i);

    expect(sanitizeSeatIdForMarker("seat=1\nstatus=alive")).toBe(
      "seat_1_status_alive",
    );
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

  test("clean-completion positive control: exited with 0, present artifact, and passing floor classifies as alive", () => {
    const seat = baseSeat();
    expect(
      classifySeatSilence(seat, {
        now: 1_080_000,
        exited: true,
        exitCode: 0,
        artifactPresent: true,
        floorPassed: true,
      }),
    ).toBe("alive");
  });

  test("slow-progress control: progress heartbeats reset idle window (legit_long_turn) but NEVER extend deadline_at", () => {
    let seat = baseSeat();
    seat = recordSeatHeartbeat(seat, 1_100_000);
    seat = recordSeatHeartbeat(seat, 1_200_000);
    expect(seat.deadline_at).toBe(1_600_000);
    expect(classifySeatSilence(seat, { now: 1_250_000 })).toBe(
      "legit_long_turn",
    );

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

  test("dead/zombie control: silent past idle_timeout_ms on childDiskHeartbeat=true harness classifies as crash, while childDiskHeartbeat=false harness degrades to legit_long_turn until deadline_at (TR2)", () => {
    const seat = baseSeat();
    // Silent for 180s (> 120s idle_timeout_ms) on claude (childDiskHeartbeat: true)
    expect(classifySeatSilence(seat, { now: 1_180_000 })).toBe("crash");

    // Silent for 180s on devin (childDiskHeartbeat: false) degrades to parent-side deadline_at
    const devinSeat = baseSeat({ harness: "devin" });
    expect(classifySeatSilence(devinSeat, { now: 1_180_000 })).toBe(
      "legit_long_turn",
    );
    expect(classifySeatSilence(devinSeat, { now: 1_600_001 })).toBe("crash");

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
  test("healthy seat control: alive or legit_long_turn returns action=none without incrementing attempt", () => {
    const aliveDec = decideSeatRecovery(baseSeat({ classification: "alive" }));
    expect(aliveDec.action).toBe("none");
    expect(aliveDec.nextAttempt).toBe(0);
    expect(aliveDec.reviewedCoverage).toBe("full");

    const slowDec = decideSeatRecovery(
      baseSeat({ classification: "legit_long_turn" }),
    );
    expect(slowDec.action).toBe("none");
    expect(slowDec.nextAttempt).toBe(0);
  });

  test("accepts on-disk verified artifact or verified diff without respawning", () => {
    const seat = baseSeat({ classification: "crash", writable: true });
    const decision = decideSeatRecovery(seat, {
      dirtyDiff: true,
      diffVerified: true,
    });
    expect(decision.action).toBe("accept");
    expect(decision.reviewedCoverage).toBe("full");
    expect(decision.marker).toBe(
      "SOLEUR_SEAT_LIVENESS seat=seat-review-security status=crash action=accept attempt=0 fallback_tier=none reviewed_coverage=full",
    );

    const artSeat = baseSeat({ classification: "truncated", writable: false });
    const artDecision = decideSeatRecovery(artSeat, { artifactVerified: true });
    expect(artDecision.action).toBe("accept");
    expect(artDecision.reviewedCoverage).toBe("full");
  });

  test("writable seat with unverified dirty diff returns verify_disk first, never blind respawn (even if artifactVerified is true)", () => {
    const seat = baseSeat({ classification: "crash", writable: true });
    const unverified = decideSeatRecovery(seat, {
      dirtyDiff: true,
      artifactVerified: true,
    });
    expect(unverified.action).toBe("verify_disk");

    const failedVerify = decideSeatRecovery(seat, {
      dirtyDiff: true,
      diffVerified: false,
      artifactVerified: true,
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

  test("paused/truncated seat nudges on inBandNudge=true harness and respawns on inBandNudge=false harness", () => {
    const claudeSeat = baseSeat({
      harness: "claude",
      classification: "hook_deferred",
      attempt: 0,
    });
    const claudeDec = decideSeatRecovery(claudeSeat, {});
    expect(claudeDec.action).toBe("nudge");
    expect(claudeDec.nextAttempt).toBe(1);
    expect(claudeDec.marker).toBe(
      "SOLEUR_SEAT_LIVENESS seat=seat-review-security status=hook_deferred action=nudge attempt=1 fallback_tier=none reviewed_coverage=full",
    );

    const opencodeSeat = baseSeat({
      harness: "opencode",
      classification: "truncated",
      attempt: 0,
    });
    const opencodeDec = decideSeatRecovery(opencodeSeat, {});
    expect(opencodeDec.action).toBe("respawn");
    expect(opencodeDec.nextAttempt).toBe(1);
    expect(opencodeDec.marker).toBe(
      "SOLEUR_SEAT_LIVENESS seat=seat-review-security status=truncated action=respawn attempt=1 fallback_tier=same reviewed_coverage=full",
    );
  });

  test("rate_limit seat on standard tier falls back to cheap, while strong tier preserves never-downgrade (fallbackTier=null)", () => {
    const stdSeat = baseSeat({
      harness: "devin",
      tier: "standard",
      classification: "rate_limit",
      attempt: 0,
    });
    const stdDec = decideSeatRecovery(stdSeat, {});
    expect(stdDec.action).toBe("respawn");
    expect(stdDec.fallbackTier).toBe("cheap");
    expect(stdDec.nextAttempt).toBe(1);
    expect(stdDec.marker).toBe(
      "SOLEUR_SEAT_LIVENESS seat=seat-review-security status=rate_limit action=respawn attempt=1 fallback_tier=cheap reviewed_coverage=full",
    );

    const strongSeat = baseSeat({
      harness: "claude",
      tier: "strong",
      classification: "rate_limit",
      attempt: 0,
    });
    const strongDec = decideSeatRecovery(strongSeat, {});
    expect(strongDec.action).toBe("respawn");
    expect(strongDec.fallbackTier).toBeNull();
    expect(strongDec.marker).toBe(
      "SOLEUR_SEAT_LIVENESS seat=seat-review-security status=rate_limit action=respawn attempt=1 fallback_tier=same reviewed_coverage=full",
    );
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
    expect(decision.marker).toBe(
      "SOLEUR_SEAT_LIVENESS seat=seat-review-security status=rate_limit action=escalate attempt=1 fallback_tier=none reviewed_coverage=degraded",
    );
  });
});

function stripJsComments(src: string): string {
  return src
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .replace(/^\s*\/\/.*$/gm, "");
}

describe("fan-out workflow integration (FR6)", () => {
  const skillsRoot = resolve(import.meta.dir, "../skills");

  const fanoutSkills = [
    "one-shot",
    "review",
    "resolve-parallel",
    "resolve-pr-parallel",
    "resolve-todo-parallel",
    "drain-labeled-backlog",
  ] as const;

  test("all 6 fan-out SKILL.md files invoke seat-liveness.sh init and sweep/decide (ADR-332)", () => {
    for (const s of fanoutSkills) {
      const md = readFileSync(resolve(skillsRoot, s, "SKILL.md"), "utf-8");
      expect(md, `${s}/SKILL.md should invoke seat-liveness.sh init`).toMatch(
        /seat-liveness\.sh"\s+init\s+--run-dir/,
      );
      expect(md, `${s}/SKILL.md should invoke seat-liveness.sh sweep`).toMatch(
        /seat-liveness\.sh\s+sweep/,
      );
      expect(md, `${s}/SKILL.md should cite ADR-332`).toContain("ADR-332");
    }
  });

  test("all 5 fan-out .workflow.js scripts parse cleanly and anchor SOLEUR_SEAT_LIVENESS log + seat wrapper call sites", () => {
    const workflowSkills = [
      "review",
      "resolve-parallel",
      "resolve-pr-parallel",
      "resolve-todo-parallel",
      "drain-labeled-backlog",
    ] as const;
    for (const s of workflowSkills) {
      const rawWf = readFileSync(
        resolve(skillsRoot, s, "workflows", `${s}.workflow.js`),
        "utf-8",
      );
      const executableBody = rawWf.replace(/^\s*export\s+const\s+meta\s*=/m, "const meta =");
      expect(
        () =>
          new Function(
            "agent",
            "parallel",
            "pipeline",
            "phase",
            "log",
            "budget",
            "args",
            `return (async () => {\n${executableBody}\n})`,
          ),
        `${s}.workflow.js must be syntactically valid JS`,
      ).not.toThrow();

      const codeOnly = stripJsComments(rawWf);
      expect(
        codeOnly,
        `${s}.workflow.js must call log(\`SOLEUR_SEAT_LIVENESS seat=\${seatId} ...\`)`,
      ).toMatch(/log\(`SOLEUR_SEAT_LIVENESS seat=\$\{seatId\} status=\$\{cls[12]?\} action=/);
      expect(
        codeOnly,
        `${s}.workflow.js must wrap agent(...) in a run*Seat liveness helper`,
      ).toMatch(
        /run(?:Review|WritableResolver|WritablePrResolver|WritableTodoResolver|ReadOnlyBrief|SideEffectingDrain)Seat\([^,]+,\s*\(\)\s*=>\s*agent\(/,
      );
      expect(
        codeOnly,
        `${s}.workflow.js must export reviewedCoverage in its return object`,
      ).toMatch(/reviewedCoverage:\s*escalatedSeats\.length\s*\?\s*'degraded'\s*:\s*'full'/);
    }
  });
});
