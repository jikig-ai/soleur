// TR9 Phase-2 — cron-cloud-task-heartbeat unit tests.
//
// Test coverage:
//   (a) Registration smoke test — import loads without throwing.
//   (b) Source-shape anchor tests — id, cron, event, concurrency, retries.
//   (c) Exported constant — TASK_INVENTORY (6 output-producing tasks).
//
// INVENTORY SCOPE (see knowledge-base/engineering/ops/runbooks/cloud-scheduled-tasks.md):
// The heartbeat monitors ONLY scheduled tasks that produce a `scheduled-<task>`
// issue artifact. Non-producers (daily-triage, ux-audit, bug-fixer) were removed
// because the label-presence signal can never observe output they never create —
// their cron LIVENESS is covered by per-function Sentry monitors (#4708), not here.

import { describe, expect, it, vi } from "vitest";
import { readFileSync } from "node:fs";
import { resolve } from "node:path";

vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

import {
  cronCloudTaskHeartbeat,
  TASK_INVENTORY,
} from "@/server/inngest/functions/cron-cloud-task-heartbeat";

// =============================================================================
// Registration smoke test
// =============================================================================

describe("cronCloudTaskHeartbeat — registration shape (import-time smoke)", () => {
  it("loads without throwing (handler + client startup pass)", () => {
    expect(cronCloudTaskHeartbeat).toBeDefined();
    expect(typeof cronCloudTaskHeartbeat).toBe("object");
  });
});

// =============================================================================
// Exported constants — TASK_INVENTORY
// =============================================================================

describe("cronCloudTaskHeartbeat — TASK_INVENTORY", () => {
  it("contains exactly 6 output-producing tasks", () => {
    expect(TASK_INVENTORY).toHaveLength(6);
  });

  it("every entry has name, label, and maxGapDays", () => {
    for (const task of TASK_INVENTORY) {
      expect(typeof task.name).toBe("string");
      expect(task.name.length).toBeGreaterThan(0);
      expect(typeof task.label).toBe("string");
      expect(task.label.length).toBeGreaterThan(0);
      expect(typeof task.maxGapDays).toBe("number");
      expect(task.maxGapDays).toBeGreaterThan(0);
    }
  });

  it("label is always `scheduled-` + name (guards future typos)", () => {
    for (const task of TASK_INVENTORY) {
      expect(task.label).toBe(`scheduled-${task.name}`);
    }
  });

  it.each([
    ["content-generator", "scheduled-content-generator", 9],
    ["strategy-review", "scheduled-strategy-review", 9],
    ["legal-audit", "scheduled-legal-audit", 95],
    ["competitive-analysis", "scheduled-competitive-analysis", 40],
    ["community-monitor", "scheduled-community-monitor", 3],
    ["roadmap-review", "scheduled-roadmap-review", 9],
  ] as const)(
    "task %s has label %s and maxGapDays %d",
    (name, label, maxGapDays) => {
      const entry = TASK_INVENTORY.find((t) => t.name === name);
      expect(entry).toBeDefined();
      expect(entry!.label).toBe(label);
      expect(entry!.maxGapDays).toBe(maxGapDays);
    },
  );

  // Non-producer exclusion guard: these three never create a `scheduled-<task>`
  // issue (daily-triage labels existing issues only; ux-audit runs dry-run to
  // Supabase/stdout; bug-fixer opens bot-fix PRs) so the label-presence signal
  // false-fires forever. They must NOT be in the inventory. (#4708 rationale.)
  it.each(["daily-triage", "ux-audit", "bug-fixer"])(
    "non-producer %s is excluded from the inventory",
    (removed) => {
      expect(TASK_INVENTORY.find((t) => t.name === removed)).toBeUndefined();
    },
  );

  // Cadence-vs-threshold anchor: legal-audit runs quarterly
  // (`0 11 1 1,4,7,10 *`); the longest quarter gap (Jul 1 → Oct 1) is 92 days,
  // so its threshold MUST clear that floor or it false-fires every quarter.
  it("legal-audit threshold clears the quarterly (92-day) floor", () => {
    const legal = TASK_INVENTORY.find((t) => t.name === "legal-audit");
    expect(legal).toBeDefined();
    expect(legal!.maxGapDays).toBeGreaterThanOrEqual(92);
  });
});

// =============================================================================
// Source-shape anchor tests
// =============================================================================

const SUT_SOURCE = readFileSync(
  resolve(
    __dirname,
    "../../../server/inngest/functions/cron-cloud-task-heartbeat.ts",
  ),
  "utf-8",
);

describe("registration source-shape anchors (cross-check the import-time smoke)", () => {
  it.each([
    ['id: "cron-cloud-task-heartbeat"', "canonical function id"],
    ['cron: "30 9 * * *"', "daily at 09:30 UTC schedule"],
    ['event: "cron/cloud-task-heartbeat.manual-trigger"', "operator manual trigger"],
    ['scope: "fn"', "fn-scoped serialization"],
    ['scope: "account"', "account-shared lane (cron-platform)"],
    ['key: \'"cron-platform"\'', "cross-handler concurrency lane"],
    ["retries: 1", "no retry storm on heartbeat failure"],
  ])("source contains %s (%s)", (anchor) => {
    expect(SUT_SOURCE).toContain(anchor);
  });
});

describe("cron-cloud-task-heartbeat — Sentry monitor slug", () => {
  it("source contains the correct Sentry monitor slug", () => {
    expect(SUT_SOURCE).toContain('"scheduled-cloud-task-heartbeat"');
  });
});

describe("cron-cloud-task-heartbeat — key logic anchors", () => {
  it.each([
    ["[cloud-task-silence]", "silence issue title prefix"],
    ["cloud-task-silence", "issue label"],
    ["GET /repos/{owner}/{repo}/issues", "issues API endpoint"],
    ["#2714", "tracking issue reference"],
  ])("source contains %s (%s)", (anchor) => {
    expect(SUT_SOURCE).toContain(anchor);
  });
});
