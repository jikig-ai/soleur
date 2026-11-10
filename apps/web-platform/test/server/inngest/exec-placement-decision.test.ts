// exec-placement-decision.test.ts — unit tests for the pure placement
// decision (#9137, Phase 0 task 0.3). Every row of the plan's decision table
// plus the Test-Scenario edge cases (identity: unset vs empty vs 0.0.0.0 vs
// 10.0.1.10 vs 10.0.1.11 vs whitespace-padded; classification: -failure
// suffix, unknown id, doubled/missing prefix; POST with no fnId and no probe).
// All fixtures synthesized (cq-test-fixtures-synthesized-only).
//
// Manifest ids used: "agent-on-spawn-requested" (volume-bound),
// "cron-agent-native-audit" (host-affine), "cron-anthropic-cost-report"
// (portable) — all real EXECUTION_PLACEMENT rows so the tests exercise the
// imported table, not a copy (Guard 1's identity rule).

import { afterEach, describe, expect, it, vi } from "vitest";

const { mockReport, mockWarn } = vi.hoisted(() => ({
  mockReport: vi.fn(),
  mockWarn: vi.fn(),
}));
vi.mock("@/server/observability", () => ({
  reportSilentFallback: mockReport,
  warnSilentFallback: mockWarn,
  infoSilentFallback: vi.fn(),
}));

import {
  EXEC_FORWARD_HEADER,
  EXEC_FORWARD_URL,
  EXEC_HOST_PRIVATE_IP,
  classifyFnId,
  decidePlacement,
  gatherPlacementFacts,
  recordPlacementDecision,
  type PlacementFacts,
} from "@/server/inngest/exec-placement";
import {
  isExecHost,
  readHostPrivateIp,
} from "@/server/host-private-ip";

const PINNED_VOLUME = "soleur-runtime-agent-on-spawn-requested"; // volume-bound
const PINNED_AFFINE = "soleur-runtime-cron-agent-native-audit"; // host-affine
const PORTABLE = "soleur-runtime-cron-anthropic-cost-report"; // portable
const EXEC = EXEC_HOST_PRIVATE_IP; // 10.0.1.10
const NONEXEC = "10.0.1.11";

function facts(over: Partial<PlacementFacts> = {}): PlacementFacts {
  return {
    method: "POST",
    hasProbe: false,
    fnId: PINNED_VOLUME,
    marked: false,
    isExec: false,
    hasSignature: true,
    hostIp: null,
    ...over,
  };
}

afterEach(() => {
  vi.clearAllMocks();
  vi.unstubAllEnvs();
});

describe("classifyFnId", () => {
  it("resolves a manifest id through the soleur-runtime- prefix", () => {
    expect(classifyFnId(PINNED_VOLUME)).toBe("volume-bound");
    expect(classifyFnId(PINNED_AFFINE)).toBe("host-affine");
    expect(classifyFnId(PORTABLE)).toBe("portable");
  });

  it("strips the -failure suffix — onFailure inherits the parent's class", () => {
    expect(classifyFnId(`${PINNED_VOLUME}-failure`)).toBe("volume-bound");
    expect(classifyFnId(`${PORTABLE}-failure`)).toBe("portable");
  });

  it("unknown manifest id → null (fail-closed direction)", () => {
    expect(classifyFnId("soleur-runtime-not-a-real-fn")).toBeNull();
  });

  it("missing prefix → null", () => {
    expect(classifyFnId("agent-on-spawn-requested")).toBeNull();
    expect(classifyFnId("otherapp-agent-on-spawn-requested")).toBeNull();
  });

  it("doubled prefix → null", () => {
    expect(
      classifyFnId("soleur-runtime-soleur-runtime-agent-on-spawn-requested"),
    ).toBeNull();
  });

  it("empty, blank, null and undefined → null", () => {
    expect(classifyFnId("")).toBeNull();
    expect(classifyFnId("   ")).toBeNull();
    expect(classifyFnId(null)).toBeNull();
    expect(classifyFnId(undefined)).toBeNull();
    expect(classifyFnId("soleur-runtime-")).toBeNull();
    expect(classifyFnId("soleur-runtime--failure")).toBeNull();
  });
});

describe("readHostPrivateIp / isExecHost identity edges", () => {
  it("unset → unknown", () => {
    vi.stubEnv("SOLEUR_HOST_PRIVATE_IP", undefined as unknown as string);
    expect(process.env.SOLEUR_HOST_PRIVATE_IP).toBeUndefined();
    expect(readHostPrivateIp()).toBeNull();
    expect(isExecHost(EXEC)).toBe("unknown");
  });

  it("empty and whitespace-only → unknown", () => {
    for (const v of ["", "   ", "\t "]) {
      expect(readHostPrivateIp(v)).toBeNull();
      expect(isExecHost(EXEC, v)).toBe("unknown");
    }
  });

  it("0.0.0.0 wildcard → unknown (a bind address is never an identity)", () => {
    expect(readHostPrivateIp("0.0.0.0")).toBeNull();
    expect(isExecHost(EXEC, "0.0.0.0")).toBe("unknown");
  });

  it("10.0.1.10 → exec; 10.0.1.11 → not exec; whitespace-padded still matches", () => {
    expect(isExecHost(EXEC, "10.0.1.10")).toBe(true);
    expect(isExecHost(EXEC, "10.0.1.11")).toBe(false);
    expect(isExecHost(EXEC, "  10.0.1.10  ")).toBe(true);
    expect(isExecHost(EXEC, " 10.0.1.11\t")).toBe(false);
  });
});

describe("decidePlacement — the decision table", () => {
  it("GET/PUT registration → execute locally on any host", () => {
    for (const method of ["GET", "PUT"]) {
      for (const isExec of [true, false, "unknown"] as const) {
        expect(decidePlacement(facts({ method, isExec, fnId: null, hasSignature: false }))).toEqual({
          action: "execute",
        });
      }
    }
  });

  it("?probe= → execute locally on any host (probes answer anywhere)", () => {
    for (const isExec of [true, false, "unknown"] as const) {
      expect(
        decidePlacement(facts({ hasProbe: true, isExec, fnId: PINNED_VOLUME })),
      ).toEqual({ action: "execute" });
      // probe + no fnId is still a probe — execute
      expect(
        decidePlacement(facts({ hasProbe: true, isExec, fnId: null })),
      ).toEqual({ action: "execute" });
    }
  });

  it("portable class → execute locally on exec, non-exec and unknown hosts", () => {
    for (const isExec of [true, false, "unknown"] as const) {
      expect(decidePlacement(facts({ fnId: PORTABLE, isExec }))).toEqual({
        action: "execute",
      });
    }
  });

  it("pinned class on the exec host → execute locally (volume-bound AND host-affine)", () => {
    for (const fnId of [PINNED_VOLUME, PINNED_AFFINE]) {
      expect(decidePlacement(facts({ fnId, isExec: true }))).toEqual({
        action: "execute",
      });
    }
  });

  it("pinned class on a non-exec host → forward to the literal pin with the signed call", () => {
    const d = decidePlacement(facts({ isExec: false }));
    expect(d).toEqual({ action: "forward", target: EXEC_FORWARD_URL });
    expect(EXEC_FORWARD_URL).toBe("https://10.0.1.10:8445/api/inngest");
  });

  it("pinned class on a non-exec host WITHOUT x-inngest-signature → refuse 401, never dial", () => {
    expect(
      decidePlacement(facts({ isExec: false, hasSignature: false })),
    ).toEqual({
      action: "refuse",
      reason: "missing_signature",
      status: 401,
      error: "placement.missing_signature",
    });
  });

  it("pinned class + SOLEUR_HOST_PRIVATE_IP unestablished → refuse 503 placement.exec_identity_missing", () => {
    expect(decidePlacement(facts({ isExec: "unknown" }))).toEqual({
      action: "refuse",
      reason: "exec_identity_missing",
      status: 503,
      error: "placement.exec_identity_missing",
    });
  });

  it("marked call on a non-exec host → refuse (loop-guard, never re-forward)", () => {
    expect(decidePlacement(facts({ marked: true, isExec: false }))).toEqual({
      action: "refuse",
      reason: "marked_on_nonexec",
      status: 403,
      error: "placement.marked_on_nonexec",
    });
  });

  it("marked call on the exec host → execute locally (private-ingress trust)", () => {
    expect(decidePlacement(facts({ marked: true, isExec: true }))).toEqual({
      action: "execute",
    });
  });

  it("marked call on an unidentifiable host → refuse exec_identity_missing", () => {
    expect(decidePlacement(facts({ marked: true, isExec: "unknown" }))).toEqual({
      action: "refuse",
      reason: "exec_identity_missing",
      status: 503,
      error: "placement.exec_identity_missing",
    });
  });

  it("marked portable call on a non-exec host → still refuse (marker only trusted on exec)", () => {
    expect(
      decidePlacement(facts({ marked: true, isExec: false, fnId: PORTABLE })),
    ).toEqual({
      action: "refuse",
      reason: "marked_on_nonexec",
      status: 403,
      error: "placement.marked_on_nonexec",
    });
  });

  it("POST with no fnId and no probe → forward on non-exec (fail-closed direction)", () => {
    expect(decidePlacement(facts({ fnId: null, isExec: false }))).toEqual({
      action: "forward",
      target: EXEC_FORWARD_URL,
    });
    // …and executes (then the SDK rejects it) on the exec host itself
    expect(decidePlacement(facts({ fnId: null, isExec: true }))).toEqual({
      action: "execute",
    });
  });

  it("unknown/unclassifiable fnId behaves as pinned on every host", () => {
    for (const fnId of [
      "soleur-runtime-not-a-real-fn",
      "agent-on-spawn-requested", // missing prefix
      "soleur-runtime-soleur-runtime-cron-ux-audit", // doubled prefix
    ]) {
      expect(decidePlacement(facts({ fnId, isExec: false }))).toEqual({
        action: "forward",
        target: EXEC_FORWARD_URL,
      });
      expect(decidePlacement(facts({ fnId, isExec: true }))).toEqual({
        action: "execute",
      });
      expect(decidePlacement(facts({ fnId, isExec: "unknown" }))).toEqual({
        action: "refuse",
        reason: "exec_identity_missing",
        status: 503,
        error: "placement.exec_identity_missing",
      });
    }
  });

  it("-failure ids behave as their parent's class (forward on non-exec, execute on exec)", () => {
    expect(
      decidePlacement(facts({ fnId: `${PINNED_VOLUME}-failure`, isExec: false })),
    ).toEqual({ action: "forward", target: EXEC_FORWARD_URL });
    expect(
      decidePlacement(facts({ fnId: `${PORTABLE}-failure`, isExec: false })),
    ).toEqual({ action: "execute" });
  });
});

describe("gatherPlacementFacts", () => {
  it("reads method, probe, fnId, marker, signature and env identity from the request", () => {
    vi.stubEnv("SOLEUR_HOST_PRIVATE_IP", NONEXEC);
    const req = new Request(
      "https://app.soleur.ai/api/inngest?fnId=soleur-runtime-cron-ux-audit&stepId=step",
      {
        method: "POST",
        headers: {
          "x-inngest-signature": "t=1&s=abc",
          [EXEC_FORWARD_HEADER]: "1",
        },
      },
    );
    const f = gatherPlacementFacts(req);
    expect(f.method).toBe("POST");
    expect(f.hasProbe).toBe(false);
    expect(f.fnId).toBe("soleur-runtime-cron-ux-audit");
    expect(f.marked).toBe(true);
    expect(f.isExec).toBe(false);
    expect(f.hasSignature).toBe(true);
    expect(f.hostIp).toBe(NONEXEC);
  });

  it("?probe= and missing signature are read correctly; unset env → unknown", () => {
    vi.stubEnv("SOLEUR_HOST_PRIVATE_IP", undefined as unknown as string);
    const req = new Request(
      "https://app.soleur.ai/api/inngest?probe=trust_probe",
      { method: "POST" },
    );
    const f = gatherPlacementFacts(req);
    expect(f.hasProbe).toBe(true);
    expect(f.hasSignature).toBe(false);
    expect(f.isExec).toBe("unknown");
    expect(f.hostIp).toBeNull();
    expect(f.marked).toBe(false);
  });

  it("an EMPTY ?probe= is a run request to the SDK — never the probe bypass (review #12554 P1)", () => {
    // The SDK tests `get(queryKeys.Probe) || void 0` (truthiness): `?probe=` and
    // bare `?probe` fall through to fnId processing and EXECUTE the function.
    // A presence check would let a signed pinned call execute on a non-exec
    // host and would bypass the marked loop-guard — the defect this PR closes.
    vi.stubEnv("SOLEUR_HOST_PRIVATE_IP", NONEXEC);
    for (const shape of ["probe=", "probe", "probe=&fnId="] as const) {
      const req = new Request(
        `https://app.soleur.ai/api/inngest?fnId=${PINNED_VOLUME}&${shape}`,
        { method: "POST", headers: { "x-inngest-signature": "t=1&s=a" } },
      );
      const f = gatherPlacementFacts(req);
      expect(f.hasProbe, `${shape} must not read as a probe`).toBe(false);
      expect(
        decidePlacement(f),
        `${shape} must take the pinned direction on a non-exec host`,
      ).toEqual({ action: "forward", target: EXEC_FORWARD_URL });
    }
    // …and the empty-probe loop-guard bypass: marked + `?probe=` still refuses.
    const marked = new Request(
      `https://app.soleur.ai/api/inngest?fnId=${PINNED_VOLUME}&probe=`,
      {
        method: "POST",
        headers: {
          "x-inngest-signature": "t=1&s=a",
          [EXEC_FORWARD_HEADER]: "1",
        },
      },
    );
    expect(decidePlacement(gatherPlacementFacts(marked))).toEqual({
      action: "refuse",
      reason: "marked_on_nonexec",
      status: 403,
      error: "placement.marked_on_nonexec",
    });
  });
});

describe("recordPlacementDecision — observability wiring (3.4)", () => {
  it("refuse exec_identity_missing → reportSilentFallback with feature inngest-exec-placement", () => {
    const f = facts({ isExec: "unknown" });
    recordPlacementDecision(f, decidePlacement(f));
    expect(mockReport).toHaveBeenCalledTimes(1);
    const [err, opts] = mockReport.mock.calls[0] as [
      unknown,
      { feature: string; op: string; extra: Record<string, unknown> },
    ];
    expect(err).toBeNull();
    expect(opts.feature).toBe("inngest-exec-placement");
    expect(opts.op).toBe("placement.exec_identity_missing");
    expect(opts.extra.fnId).toBe(PINNED_VOLUME);
  });

  it("refuse marked_on_nonexec → reportSilentFallback with the marked op", () => {
    const f = facts({ marked: true, isExec: false });
    recordPlacementDecision(f, decidePlacement(f));
    expect(mockReport).toHaveBeenCalledTimes(1);
    const [, opts] = mockReport.mock.calls[0] as [
      unknown,
      { feature: string; op: string },
    ];
    expect(opts.feature).toBe("inngest-exec-placement");
    expect(opts.op).toBe("placement.marked_on_nonexec");
  });

  it("execute and forward decisions → no Sentry report", () => {
    const cases: PlacementFacts[] = [
      facts({ isExec: true }), // execute
      facts({ fnId: PORTABLE, isExec: false }), // execute
      facts({ isExec: false }), // forward
    ];
    for (const f of cases) {
      recordPlacementDecision(f, decidePlacement(f));
    }
    expect(mockReport).not.toHaveBeenCalled();
  });

  it("missing_signature refuse → warn-only, never a Sentry report", () => {
    const f = facts({ isExec: false, hasSignature: false });
    recordPlacementDecision(f, decidePlacement(f));
    expect(mockReport).not.toHaveBeenCalled();
    expect(mockWarn).not.toHaveBeenCalled(); // rate-limited pino warn, not the Sentry helper
  });
});
