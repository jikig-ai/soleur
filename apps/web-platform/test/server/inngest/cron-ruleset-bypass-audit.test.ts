// TR9 Phase-2 — cron-ruleset-bypass-audit handler unit tests.
//
// Coverage:
//   1. Registration shape (cron + manual-trigger, concurrency, retries).
//   2. Source-shape anchors (cron schedule, event name, concurrency).
//   3. compareBypassActors pure-function tests.

import { describe, expect, it, vi } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

import {
  cronRulesetBypassAudit,
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
});
