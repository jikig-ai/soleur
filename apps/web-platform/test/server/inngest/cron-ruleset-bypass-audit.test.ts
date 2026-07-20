// TR9 Phase-2 — cron-ruleset-bypass-audit handler unit tests.
//
// Coverage:
//   1. Registration shape (cron + manual-trigger, concurrency, retries).
//   2. Source-shape anchors (cron schedule, event name, concurrency).
//   3. compareBypassActors pure-function tests.

import { beforeEach, describe, expect, it, vi } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

// vi.hoisted runs BEFORE ES-module imports — set NEXT_PHASE so importing the
// inngest client (transitively pulled by the SUT) does not throw on a missing
// signing key in the test env, and expose the Octokit + Sentry spies the handler
// test drives. Mirrors cron-terraform-drift.test.ts.
const h = vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
  return {
    requestSpy: vi.fn(async (..._args: unknown[]) => ({ data: {} })),
    reportSilentFallbackSpy: vi.fn((..._args: unknown[]) => {}),
  };
});

// The SUT does `const { Octokit } = await import("@octokit/core")` inside each
// step; route every request through the observable spy.
vi.mock("@octokit/core", () => ({
  Octokit: class {
    request = h.requestSpy;
  },
}));

// Stub the installation-token mint so no GitHub App round-trip happens; keep
// every other _cron-shared export real (postSentryHeartbeat no-ops when the
// Sentry env is unset, which it is in the test env).
vi.mock("@/server/inngest/functions/_cron-shared", async () => {
  const actual = await vi.importActual<
    typeof import("@/server/inngest/functions/_cron-shared")
  >("@/server/inngest/functions/_cron-shared");
  return {
    ...actual,
    mintInstallationToken: vi.fn(async () => "fake-installation-token"),
  };
});

vi.mock("@/server/observability", async () => {
  const actual =
    await vi.importActual<typeof import("@/server/observability")>(
      "@/server/observability",
    );
  return { ...actual, reportSilentFallback: h.reportSilentFallbackSpy };
});

import {
  cronRulesetBypassAudit,
  cronRulesetBypassAuditHandler,
  compareBypassActors,
  compareRequiredStatusChecks,
  buildFindings,
  type BypassActor,
  type RequiredStatusCheck,
} from "@/server/inngest/functions/cron-ruleset-bypass-audit";

// =============================================================================
// Registration smoke test
// =============================================================================

describe("cronRulesetBypassAudit — registration shape (import-time smoke)", () => {
  it("loads without throwing (handler + client startup pass)", () => {
    expect(cronRulesetBypassAudit).toBeDefined();
    expect(typeof cronRulesetBypassAudit).toBe("object");
  });
});

// =============================================================================
// Source-shape anchors
// =============================================================================

const SUT_SOURCE = readFileSync(
  resolve(
    __dirname,
    "../../../server/inngest/functions/cron-ruleset-bypass-audit.ts",
  ),
  "utf-8",
);

describe("registration source-shape anchors", () => {
  it.each([
    ['id: "cron-ruleset-bypass-audit"', "canonical function id"],
    ['cron: "13 6 * * *"', "daily 06:13 UTC schedule"],
    [
      'event: "cron/ruleset-bypass-audit.manual-trigger"',
      "operator manual trigger",
    ],
    ['scope: "fn"', "fn-scoped serialization"],
    ['scope: "account"', "account-shared lane (cron-platform)"],
    ['key: \'"cron-platform"\'', "cross-handler concurrency lane"],
    ["retries: 1", "no retry storm on failure"],
  ])("source contains %s (%s)", (anchor) => {
    expect(SUT_SOURCE).toContain(anchor);
  });
});

describe("source contains key constants", () => {
  it.each([
    ["scheduled-ruleset-bypass-audit", "Sentry monitor slug"],
    ["CI Required", "ruleset name"],
    [
      "ci-required-ruleset-canonical-bypass-actors.json",
      "canonical bypass_actors snapshot path",
    ],
    [
      "ci-required-ruleset-canonical-required-status-checks.json",
      "canonical required_status_checks snapshot path",
    ],
    ["ci/auth-broken", "drift issue label"],
    ["compliance/critical", "drift issue label"],
    [
      "[Ruleset Audit] CI Required ruleset drift",
      "combined drift issue title",
    ],
    ['detail.enforcement !== "active"', "enforcement-active check"],
    ["state_reason", "auto-close on green"],
    // CLA ruleset audit (#6061) — the second ruleset routed through the shared
    // auditOneRuleset helper.
    ["CLA Required", "CLA ruleset name"],
    [
      "ci-cla-required-ruleset-canonical-bypass-actors.json",
      "CLA canonical bypass_actors snapshot path",
    ],
    [
      "ci-cla-required-ruleset-canonical-required-status-checks.json",
      "CLA canonical required_status_checks snapshot path",
    ],
    [
      "[Ruleset Audit] CLA Required ruleset drift",
      "CLA drift issue title",
    ],
    ["auditOneRuleset", "shared per-ruleset audit helper"],
    ["guardBroken", "guard-fault-vs-drift routing flag"],
  ])("source contains %s (%s)", (anchor) => {
    expect(SUT_SOURCE).toContain(anchor);
  });
});

// =============================================================================
// compareBypassActors — pure function tests
// =============================================================================

describe("compareBypassActors", () => {
  const canonical: BypassActor[] = [
    {
      actor_id: null,
      actor_type: "OrganizationAdmin",
      bypass_mode: "pull_request",
    },
    {
      actor_id: 5,
      actor_type: "RepositoryRole",
      bypass_mode: "pull_request",
    },
  ];

  it("returns match=true when canonical and actual are identical", () => {
    const actual = [...canonical];
    const result = compareBypassActors(canonical, actual);
    expect(result.match).toBe(true);
    expect(result.drift).toBe(false);
    expect(result.added).toHaveLength(0);
    expect(result.removed).toHaveLength(0);
  });

  it("detects drift when actual has extra actors", () => {
    const actual: BypassActor[] = [
      ...canonical,
      {
        actor_id: 99,
        actor_type: "Team",
        bypass_mode: "always",
      },
    ];
    const result = compareBypassActors(canonical, actual);
    expect(result.drift).toBe(true);
    expect(result.match).toBe(false);
    expect(result.added).toHaveLength(1);
    expect(result.added[0].actor_id).toBe(99);
  });

  it("detects removed actors without triggering drift", () => {
    const actual: BypassActor[] = [canonical[0]];
    const result = compareBypassActors(canonical, actual);
    expect(result.drift).toBe(false);
    expect(result.match).toBe(false);
    expect(result.removed).toHaveLength(1);
    expect(result.removed[0].actor_id).toBe(5);
  });

  it("handles both added and removed simultaneously", () => {
    const actual: BypassActor[] = [
      canonical[0],
      {
        actor_id: 42,
        actor_type: "DeployKey",
        bypass_mode: "always",
      },
    ];
    const result = compareBypassActors(canonical, actual);
    expect(result.drift).toBe(true);
    expect(result.match).toBe(false);
    expect(result.added).toHaveLength(1);
    expect(result.removed).toHaveLength(1);
  });

  it("handles empty canonical (all actual actors are drift)", () => {
    const result = compareBypassActors([], canonical);
    expect(result.drift).toBe(true);
    expect(result.added).toHaveLength(2);
    expect(result.removed).toHaveLength(0);
  });

  it("handles empty actual (all canonical actors are removed)", () => {
    const result = compareBypassActors(canonical, []);
    expect(result.drift).toBe(false);
    expect(result.match).toBe(false);
    expect(result.removed).toHaveLength(2);
  });

  it("handles null actor_id correctly in key generation", () => {
    const a: BypassActor[] = [
      {
        actor_id: null,
        actor_type: "OrganizationAdmin",
        bypass_mode: "pull_request",
      },
    ];
    const b: BypassActor[] = [
      {
        actor_id: null,
        actor_type: "OrganizationAdmin",
        bypass_mode: "pull_request",
      },
    ];
    const result = compareBypassActors(a, b);
    expect(result.match).toBe(true);
  });
});

// =============================================================================
// compareRequiredStatusChecks — pure function tests
// =============================================================================

describe("compareRequiredStatusChecks", () => {
  const canonical: RequiredStatusCheck[] = [
    { context: "test", integration_id: 15368 },
    { context: "e2e", integration_id: 15368 },
    { context: "CodeQL", integration_id: 57789 },
  ];

  it("match=true when canonical and actual are identical", () => {
    const result = compareRequiredStatusChecks(canonical, [...canonical]);
    expect(result.match).toBe(true);
    expect(result.added).toHaveLength(0);
    expect(result.removed).toHaveLength(0);
  });

  it("flags a dropped required check as removed (the dangerous direction)", () => {
    const actual = canonical.filter((c) => c.context !== "CodeQL");
    const result = compareRequiredStatusChecks(canonical, actual);
    expect(result.match).toBe(false);
    expect(result.removed).toHaveLength(1);
    expect(result.removed[0].context).toBe("CodeQL");
    expect(result.added).toHaveLength(0);
  });

  it("flags an extra live check as added (divergence-only)", () => {
    const actual = [
      ...canonical,
      { context: "enforce", integration_id: 15368 },
    ];
    const result = compareRequiredStatusChecks(canonical, actual);
    expect(result.match).toBe(false);
    expect(result.added).toHaveLength(1);
    expect(result.added[0].context).toBe("enforce");
    expect(result.removed).toHaveLength(0);
  });

  it("treats a changed integration_id as both removed and added (CodeQL spoof guard)", () => {
    // CodeQL pinned to 57789; a same-name check from github-actions[bot]
    // (15368) must NOT satisfy the gate.
    const actual = [
      { context: "test", integration_id: 15368 },
      { context: "e2e", integration_id: 15368 },
      { context: "CodeQL", integration_id: 15368 },
    ];
    const result = compareRequiredStatusChecks(canonical, actual);
    expect(result.match).toBe(false);
    expect(result.removed).toHaveLength(1);
    expect(result.removed[0].integration_id).toBe(57789);
    expect(result.added).toHaveLength(1);
    expect(result.added[0].integration_id).toBe(15368);
  });
});

// =============================================================================
// buildFindings — audit assembly across all three drift classes
// =============================================================================

describe("buildFindings", () => {
  const canonicalBypassActors: BypassActor[] = [
    {
      actor_id: null,
      actor_type: "OrganizationAdmin",
      bypass_mode: "pull_request",
    },
  ];
  const canonicalChecks: RequiredStatusCheck[] = [
    { context: "test", integration_id: 15368 },
    { context: "CodeQL", integration_id: 57789 },
  ];
  const greenDetail = {
    enforcement: "active",
    bypassActors: [...canonicalBypassActors],
    requiredStatusChecks: [...canonicalChecks],
  };

  it("returns zero findings when everything matches (green)", () => {
    const findings = buildFindings(
      greenDetail,
      canonicalBypassActors,
      canonicalChecks,
    );
    expect(findings).toHaveLength(0);
  });

  it("flags suspended enforcement as critical", () => {
    const findings = buildFindings(
      { ...greenDetail, enforcement: "disabled" },
      canonicalBypassActors,
      canonicalChecks,
    );
    expect(findings).toHaveLength(1);
    expect(findings[0].kind).toBe("enforcement");
    expect(findings[0].critical).toBe(true);
  });

  it("flags a widened bypass_actors as critical", () => {
    const findings = buildFindings(
      {
        ...greenDetail,
        bypassActors: [
          ...canonicalBypassActors,
          { actor_id: 99, actor_type: "Team", bypass_mode: "always" },
        ],
      },
      canonicalBypassActors,
      canonicalChecks,
    );
    expect(findings).toHaveLength(1);
    expect(findings[0].kind).toBe("bypass_actors");
    expect(findings[0].critical).toBe(true);
  });

  it("flags a dropped required check as critical", () => {
    const findings = buildFindings(
      {
        ...greenDetail,
        requiredStatusChecks: [{ context: "test", integration_id: 15368 }],
      },
      canonicalBypassActors,
      canonicalChecks,
    );
    expect(findings).toHaveLength(1);
    expect(findings[0].kind).toBe("required_status_checks");
    expect(findings[0].critical).toBe(true);
  });

  it("flags an extra live check as non-critical divergence", () => {
    const findings = buildFindings(
      {
        ...greenDetail,
        requiredStatusChecks: [
          ...canonicalChecks,
          { context: "enforce", integration_id: 15368 },
        ],
      },
      canonicalBypassActors,
      canonicalChecks,
    );
    expect(findings).toHaveLength(1);
    expect(findings[0].kind).toBe("required_status_checks");
    expect(findings[0].critical).toBe(false);
  });

  it("accumulates multiple findings across drift classes", () => {
    const findings = buildFindings(
      {
        enforcement: "evaluate",
        bypassActors: [
          ...canonicalBypassActors,
          { actor_id: 99, actor_type: "Team", bypass_mode: "always" },
        ],
        requiredStatusChecks: [{ context: "test", integration_id: 15368 }],
      },
      canonicalBypassActors,
      canonicalChecks,
    );
    expect(findings.length).toBeGreaterThanOrEqual(3);
    expect(findings.filter((f) => f.critical).length).toBeGreaterThanOrEqual(3);
  });

  // #6061 — the whole required_status_checks RULE gone (not just a dropped
  // context) is signalled as `requiredStatusChecks: null` (data, not an uncaught
  // throw) so it maps to a critical finding that FILES the issue.
  it("flags a null requiredStatusChecks (rule missing entirely) as critical", () => {
    const findings = buildFindings(
      { ...greenDetail, requiredStatusChecks: null },
      canonicalBypassActors,
      canonicalChecks,
    );
    expect(findings).toHaveLength(1);
    expect(findings[0].kind).toBe("required_status_checks");
    expect(findings[0].critical).toBe(true);
  });
});

// =============================================================================
// buildFindings — CLA-specific fixtures (#6061)
// =============================================================================

describe("buildFindings — CLA ruleset fixtures", () => {
  const claBypass: BypassActor[] = [
    { actor_id: null, actor_type: "OrganizationAdmin", bypass_mode: "pull_request" },
    { actor_id: 5, actor_type: "RepositoryRole", bypass_mode: "pull_request" },
    { actor_id: 1236702, actor_type: "Integration", bypass_mode: "always" },
  ];
  const claRsc: RequiredStatusCheck[] = [
    { context: "cla-check", integration_id: 15368 },
    { context: "cla-evidence", integration_id: 15368 },
  ];
  const claGreen = {
    enforcement: "active",
    bypassActors: [...claBypass],
    requiredStatusChecks: [...claRsc],
  };

  it("green CLA detail → 0 findings", () => {
    expect(buildFindings(claGreen, claBypass, claRsc)).toHaveLength(0);
  });

  it("dropped cla-evidence → critical removed finding", () => {
    const findings = buildFindings(
      { ...claGreen, requiredStatusChecks: [{ context: "cla-check", integration_id: 15368 }] },
      claBypass,
      claRsc,
    );
    expect(findings).toHaveLength(1);
    expect(findings[0].kind).toBe("required_status_checks");
    expect(findings[0].critical).toBe(true);
  });

  it("a 4th widened bypass actor → critical bypass_actors finding", () => {
    const findings = buildFindings(
      {
        ...claGreen,
        bypassActors: [
          ...claBypass,
          { actor_id: 77, actor_type: "Team", bypass_mode: "always" },
        ],
      },
      claBypass,
      claRsc,
    );
    expect(findings).toHaveLength(1);
    expect(findings[0].kind).toBe("bypass_actors");
    expect(findings[0].critical).toBe(true);
  });

  it("CLA enforcement disabled → critical enforcement finding", () => {
    const findings = buildFindings(
      { ...claGreen, enforcement: "disabled" },
      claBypass,
      claRsc,
    );
    expect(findings).toHaveLength(1);
    expect(findings[0].kind).toBe("enforcement");
    expect(findings[0].critical).toBe(true);
  });
});

// =============================================================================
// Handler — Octokit-mocked, per-ruleset isolation (#6061, MANDATORY)
// =============================================================================

const CI_DRIFT_TITLE = "[Ruleset Audit] CI Required ruleset drift";
const CLA_DRIFT_TITLE = "[Ruleset Audit] CLA Required ruleset drift";

const CI_BYPASS_CANON: BypassActor[] = [
  { actor_id: null, actor_type: "OrganizationAdmin", bypass_mode: "pull_request" },
  { actor_id: 5, actor_type: "RepositoryRole", bypass_mode: "pull_request" },
];
const CI_RSC_CANON: RequiredStatusCheck[] = [
  { context: "test", integration_id: 15368 },
  { context: "CodeQL", integration_id: 57789 },
];
const CLA_BYPASS_CANON: BypassActor[] = [
  { actor_id: null, actor_type: "OrganizationAdmin", bypass_mode: "pull_request" },
  { actor_id: 5, actor_type: "RepositoryRole", bypass_mode: "pull_request" },
  { actor_id: 1236702, actor_type: "Integration", bypass_mode: "always" },
];
const CLA_RSC_CANON: RequiredStatusCheck[] = [
  { context: "cla-check", integration_id: 15368 },
  { context: "cla-evidence", integration_id: 15368 },
];

const CANON_PATHS = {
  ciBypass: "scripts/ci-required-ruleset-canonical-bypass-actors.json",
  ciRsc: "scripts/ci-required-ruleset-canonical-required-status-checks.json",
  claBypass: "scripts/ci-cla-required-ruleset-canonical-bypass-actors.json",
  claRsc: "scripts/ci-cla-required-ruleset-canonical-required-status-checks.json",
};

interface LiveDetail {
  enforcement: string;
  bypass_actors?: BypassActor[];
  rules: Array<{ type: string; parameters?: { required_status_checks?: RequiredStatusCheck[] } }>;
}

function liveDetail(
  bypass: BypassActor[] | undefined,
  rsc: RequiredStatusCheck[] | null,
  enforcement = "active",
): LiveDetail {
  return {
    enforcement,
    bypass_actors: bypass,
    rules:
      rsc === null
        ? []
        : [{ type: "required_status_checks", parameters: { required_status_checks: rsc } }],
  };
}

interface FakeState {
  rulesets: Array<{ id: number; name: string }>;
  details: Record<number, LiveDetail>;
  contents: Record<string, unknown>;
  openIssues: Array<{ number: number; title: string }>;
  created: Array<{ title: string; labels: string[] }>;
  closed: number[];
  comments: Array<{ issue: number; body: string }>;
}

// Default: both rulesets green (live == canonical), no open issues.
function makeState(overrides: Partial<FakeState> = {}): FakeState {
  return {
    rulesets: [
      { id: 1, name: "CI Required" },
      { id: 2, name: "CLA Required" },
    ],
    details: {
      1: liveDetail(CI_BYPASS_CANON, CI_RSC_CANON),
      2: liveDetail(CLA_BYPASS_CANON, CLA_RSC_CANON),
    },
    contents: {
      [CANON_PATHS.ciBypass]: CI_BYPASS_CANON,
      [CANON_PATHS.ciRsc]: CI_RSC_CANON,
      [CANON_PATHS.claBypass]: CLA_BYPASS_CANON,
      [CANON_PATHS.claRsc]: CLA_RSC_CANON,
    },
    openIssues: [],
    created: [],
    closed: [],
    comments: [],
    ...overrides,
  };
}

function installDispatch(
  state: FakeState,
  opts: { throwOnCreate?: boolean } = {},
) {
  h.requestSpy.mockImplementation(async (...args: unknown[]) => {
    const route = args[0] as string;
    const params = (args[1] ?? {}) as Record<string, unknown>;
    if (route === "GET /repos/{owner}/{repo}/rulesets") {
      return { data: state.rulesets };
    }
    if (route === "GET /repos/{owner}/{repo}/rulesets/{ruleset_id}") {
      const d = state.details[params.ruleset_id as number];
      if (!d) throw new Error(`no fake detail for ruleset ${String(params.ruleset_id)}`);
      return { data: d };
    }
    if (route === "GET /repos/{owner}/{repo}/contents/{path}") {
      const raw = state.contents[params.path as string];
      if (raw === undefined) {
        throw new Error(`fake 404: ${String(params.path)}`);
      }
      return {
        data: {
          content: Buffer.from(JSON.stringify(raw)).toString("base64"),
          encoding: "base64",
        },
      };
    }
    if (route === "GET /repos/{owner}/{repo}/issues") {
      return { data: state.openIssues };
    }
    if (route === "POST /repos/{owner}/{repo}/issues") {
      if (opts.throwOnCreate) {
        throw new Error("fake GitHub 500 on issue create");
      }
      const number = 9000 + state.created.length;
      state.created.push({
        title: params.title as string,
        labels: (params.labels as string[]) ?? [],
      });
      return { data: { number } };
    }
    if (route === "POST /repos/{owner}/{repo}/issues/{issue_number}/comments") {
      state.comments.push({
        issue: params.issue_number as number,
        body: params.body as string,
      });
      return { data: {} };
    }
    if (route === "PATCH /repos/{owner}/{repo}/issues/{issue_number}") {
      state.closed.push(params.issue_number as number);
      return { data: {} };
    }
    throw new Error(`unexpected route ${route}`);
  });
}

function makeStep() {
  return {
    run: async <T>(_name: string, cb: () => Promise<T>): Promise<T> => cb(),
  };
}
const handlerLogger = { info: vi.fn(), warn: vi.fn(), error: vi.fn() };

describe("cronRulesetBypassAuditHandler — per-ruleset audit isolation (#6061)", () => {
  beforeEach(() => {
    h.requestSpy.mockReset();
    h.reportSilentFallbackSpy.mockClear();
    handlerLogger.info.mockClear();
    handlerLogger.warn.mockClear();
    handlerLogger.error.mockClear();
  });

  const createdTitles = (s: FakeState) => s.created.map((c) => c.title);

  it("both rulesets green → ok, no issue filed or closed", async () => {
    const state = makeState();
    installDispatch(state);
    const result = await cronRulesetBypassAuditHandler({
      step: makeStep(),
      logger: handlerLogger,
    });
    expect(result.ok).toBe(true);
    expect(state.created).toHaveLength(0);
    expect(state.closed).toHaveLength(0);
    expect(h.reportSilentFallbackSpy).not.toHaveBeenCalled();
  });

  it("CLA-only critical drift → ok=false, files ONLY the CLA issue, CI untouched", async () => {
    const state = makeState({
      details: {
        1: liveDetail(CI_BYPASS_CANON, CI_RSC_CANON), // CI green
        2: liveDetail(CLA_BYPASS_CANON, [
          { context: "cla-check", integration_id: 15368 },
        ]), // CLA dropped cla-evidence
      },
    });
    installDispatch(state);
    const result = await cronRulesetBypassAuditHandler({
      step: makeStep(),
      logger: handlerLogger,
    });
    expect(result.ok).toBe(false);
    expect(createdTitles(state)).toEqual([CLA_DRIFT_TITLE]);
    expect(createdTitles(state)).not.toContain(CI_DRIFT_TITLE);
    expect(state.closed).toHaveLength(0);
    // A real critical drift is NOT a guard fault — no Sentry silent-fallback.
    expect(h.reportSilentFallbackSpy).not.toHaveBeenCalled();
  });

  it("CLA green after prior drift → closes ONLY the CLA issue; CI drift issue untouched", async () => {
    const state = makeState({
      details: {
        // CI still drifting (dropped CodeQL) → keeps its open issue, not closed
        1: liveDetail(CI_BYPASS_CANON, [{ context: "test", integration_id: 15368 }]),
        2: liveDetail(CLA_BYPASS_CANON, CLA_RSC_CANON), // CLA green
      },
      openIssues: [
        { number: 4001, title: CLA_DRIFT_TITLE },
        { number: 4002, title: CI_DRIFT_TITLE },
      ],
    });
    installDispatch(state);
    const result = await cronRulesetBypassAuditHandler({
      step: makeStep(),
      logger: handlerLogger,
    });
    expect(result.ok).toBe(false); // CI still critical
    expect(state.closed).toEqual([4001]); // only the CLA issue closed
    expect(state.closed).not.toContain(4002);
    // CI drift issue already open → skip creation (de-dupe), do not re-file.
    expect(createdTitles(state)).not.toContain(CI_DRIFT_TITLE);
  });

  it("RSC rule entirely missing on CLA → critical finding files the CLA issue (not an uncaught throw)", async () => {
    const state = makeState({
      details: {
        1: liveDetail(CI_BYPASS_CANON, CI_RSC_CANON), // CI green
        2: liveDetail(CLA_BYPASS_CANON, null), // CLA has NO required_status_checks rule
      },
    });
    installDispatch(state);
    const result = await cronRulesetBypassAuditHandler({
      step: makeStep(),
      logger: handlerLogger,
    });
    expect(result.ok).toBe(false);
    expect(createdTitles(state)).toEqual([CLA_DRIFT_TITLE]);
    // Real drift, not a guard fault.
    expect(h.reportSilentFallbackSpy).not.toHaveBeenCalled();
  });

  it("empty/corrupt CLA canonical → guardBroken: ok=false + reportSilentFallback + NO drift issue; CI step unaffected", async () => {
    const state = makeState({
      details: {
        // CI drifting → files its own issue, proving the CI step ran despite the CLA fault
        1: liveDetail(CI_BYPASS_CANON, [{ context: "test", integration_id: 15368 }]),
        2: liveDetail(CLA_BYPASS_CANON, CLA_RSC_CANON), // CLA live is fine…
      },
      contents: {
        [CANON_PATHS.ciBypass]: CI_BYPASS_CANON,
        [CANON_PATHS.ciRsc]: CI_RSC_CANON,
        [CANON_PATHS.claBypass]: CLA_BYPASS_CANON,
        [CANON_PATHS.claRsc]: [], // …but its RSC canonical on main is EMPTY (corrupt)
      },
    });
    installDispatch(state);
    const result = await cronRulesetBypassAuditHandler({
      step: makeStep(),
      logger: handlerLogger,
    });
    expect(result.ok).toBe(false);
    // Guard fault routed to Sentry, NOT a compliance/critical drift issue.
    expect(h.reportSilentFallbackSpy).toHaveBeenCalled();
    const fallbackOptions = h.reportSilentFallbackSpy.mock.calls[0][1] as {
      feature?: string;
    };
    expect(fallbackOptions).toMatchObject({ feature: "cron-ruleset-bypass-audit" });
    expect(createdTitles(state)).not.toContain(CLA_DRIFT_TITLE);
    // Behavioral isolation: the CI step still filed its own drift issue.
    expect(createdTitles(state)).toContain(CI_DRIFT_TITLE);
  });

  it("CLA bypass_actors redacted (token scope) → guardBroken: ok=false + reportSilentFallback + NO issue", async () => {
    const state = makeState({
      details: {
        1: liveDetail(CI_BYPASS_CANON, CI_RSC_CANON), // CI green
        // CLA live detail is missing bypass_actors (non-admin token redaction
        // shape) → fetchRulesetDetail throws → guard fault, not a drift issue.
        2: liveDetail(undefined, CLA_RSC_CANON),
      },
    });
    installDispatch(state);
    const result = await cronRulesetBypassAuditHandler({
      step: makeStep(),
      logger: handlerLogger,
    });
    expect(result.ok).toBe(false);
    expect(result.cla.guardBroken).toBe(true);
    expect(h.reportSilentFallbackSpy).toHaveBeenCalled();
    expect(createdTitles(state)).not.toContain(CLA_DRIFT_TITLE);
  });

  it("issue-file throw on real CLA drift → drift result PRESERVED (ok=false, not guardBroken) + reportSilentFallback", async () => {
    const state = makeState({
      details: {
        1: liveDetail(CI_BYPASS_CANON, CI_RSC_CANON), // CI green
        2: liveDetail(CLA_BYPASS_CANON, [
          { context: "cla-check", integration_id: 15368 },
        ]), // CLA dropped cla-evidence → critical drift
      },
    });
    installDispatch(state, { throwOnCreate: true });
    const result = await cronRulesetBypassAuditHandler({
      step: makeStep(),
      logger: handlerLogger,
    });
    // The write hiccup is reported to Sentry but must NOT discard the computed
    // drift: criticalCount survives so the heartbeat still degrades, and the
    // fault is NOT mislabeled guardBroken (it's an issue-lifecycle hiccup).
    expect(result.ok).toBe(false);
    expect(result.cla.criticalCount).toBe(1);
    expect(result.cla.guardBroken).toBe(false);
    expect(h.reportSilentFallbackSpy).toHaveBeenCalled();
  });
});
