import { describe, test, expect } from "vitest";
import { computeFunnel } from "@/lib/analytics";
import type { UserRow, ConversationRow } from "@/lib/analytics";

const NOW = new Date("2026-06-08T00:00:00Z");
const DAY = 86_400_000;

function user(id: string, workspace_status: string): UserRow {
  return {
    id,
    email: `${id}@example.com`,
    created_at: "2026-01-01T00:00:00Z",
    kb_sync_history: [],
    workspace_status,
  };
}

function conv(
  user_id: string,
  domain_leader: string,
  status: string,
  created_at: string,
): ConversationRow {
  return { user_id, domain_leader, status, created_at };
}

describe("computeFunnel", () => {
  test("0 users → all-zero, signupCount 0", () => {
    const f = computeFunnel([], [], NOW);
    expect(f.signupCount).toBe(0);
    expect(f.activatedCount).toBe(0);
    expect(f.stages.map((s) => s.count)).toEqual([0, 0, 0, 0]);
    // first stage has no previous → dropoffLabel null; zero-prior stages → "—"
    expect(f.stages[0].dropoffLabel).toBeNull();
    expect(f.stages[1].dropoffLabel).toBe("—");
  });

  test("stage counts: signed-up, workspace-ready, first-conversation, activated", () => {
    const users = [
      user("u1", "ready"), // activated below
      user("u2", "ready"), // ready, has non-failed conv, 1 domain → not activated
      user("u3", "provisioning"), // signed up only
    ];
    const convs = [
      // u1: 2 domains across a 20-day span, all non-failed → activated
      conv("u1", "cto", "completed", "2026-05-01T00:00:00Z"),
      conv("u1", "cmo", "completed", "2026-05-21T00:00:00Z"),
      // u2: 1 domain, single session → not activated
      conv("u2", "cpo", "completed", "2026-05-10T00:00:00Z"),
    ];
    const f = computeFunnel(users, convs, NOW);
    expect(f.signupCount).toBe(3);
    const byKey = Object.fromEntries(f.stages.map((s) => [s.key, s.count]));
    expect(byKey["signed_up"]).toBe(3);
    expect(byKey["workspace_ready"]).toBe(2);
    expect(byKey["first_conversation"]).toBe(2);
    expect(byKey["activated"]).toBe(1);
    expect(f.activatedCount).toBe(1);
  });

  test("P0-2: domains from FAILED conversations do not count toward activation, and an all-failed user does not clear the first-conversation stage", () => {
    const users = [user("u1", "ready")];
    const convs = [
      // 2 distinct domains but BOTH failed, across >14 days
      conv("u1", "cto", "failed", "2026-05-01T00:00:00Z"),
      conv("u1", "cmo", "failed", "2026-05-21T00:00:00Z"),
    ];
    const f = computeFunnel(users, convs, NOW);
    const byKey = Object.fromEntries(f.stages.map((s) => [s.key, s.count]));
    expect(f.activatedCount).toBe(0);
    expect(byKey["activated"]).toBe(0);
    // all-failed → never clears first-conversation
    expect(byKey["first_conversation"]).toBe(0);
  });

  test("2 non-failed domains but <14-day span → not activated", () => {
    const users = [user("u1", "ready")];
    const convs = [
      conv("u1", "cto", "completed", "2026-05-01T00:00:00Z"),
      conv("u1", "cmo", "completed", "2026-05-10T00:00:00Z"), // 9-day span
    ];
    expect(computeFunnel(users, convs, NOW).activatedCount).toBe(0);
  });

  test("P0-1/P2-2: exact 14-day boundary — 14.0d activates, 13.99d does not", () => {
    const base = "2026-05-01T00:00:00Z";
    const baseMs = new Date(base).getTime();
    const exactly14 = new Date(baseMs + 14 * DAY).toISOString();
    const justUnder = new Date(baseMs + 14 * DAY - 60_000).toISOString();

    const activated = computeFunnel(
      [user("u1", "ready")],
      [
        conv("u1", "cto", "completed", base),
        conv("u1", "cmo", "completed", exactly14),
      ],
      NOW,
    );
    expect(activated.activatedCount).toBe(1);

    const notYet = computeFunnel(
      [user("u2", "ready")],
      [
        conv("u2", "cto", "completed", base),
        conv("u2", "cmo", "completed", justUnder),
      ],
      NOW,
    );
    expect(notYet.activatedCount).toBe(0);
  });

  test("P0-3: drop-off relative to previous stage; zero-prior renders — not NaN/Infinity", () => {
    // 4 signed up, 0 workspace-ready → everything downstream zero
    const users = [
      user("u1", "provisioning"),
      user("u2", "provisioning"),
      user("u3", "provisioning"),
      user("u4", "provisioning"),
    ];
    const f = computeFunnel(users, [], NOW);
    const ready = f.stages.find((s) => s.key === "workspace_ready")!;
    const firstConv = f.stages.find((s) => s.key === "first_conversation")!;
    // 4 → 0 is a 100% drop
    expect(ready.dropoffLabel).toBe("100%");
    // 0 → 0 has a zero prior → "—", never "NaN%"/"Infinity%"
    expect(firstConv.dropoffLabel).toBe("—");
    for (const s of f.stages) {
      expect(s.dropoffLabel ?? "").not.toMatch(/NaN|Infinity/);
    }
  });

  test("exposes a human-readable activationDef", () => {
    const f = computeFunnel([], [], NOW);
    expect(typeof f.activationDef).toBe("string");
    expect(f.activationDef.length).toBeGreaterThan(0);
  });
});
