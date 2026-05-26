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
  type BypassActor,
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
      "canonical snapshot path",
    ],
    ["ci/auth-broken", "drift issue label"],
    ["compliance/critical", "drift issue label"],
    [
      "[Ruleset Audit] CI Required bypass_actors drift",
      "drift issue title",
    ],
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
