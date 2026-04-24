import { describe, it, expect } from "vitest";

import {
  createStartSessionRateLimiter,
  DEFAULT_PER_USER_PER_HOUR,
  DEFAULT_PER_IP_PER_HOUR,
  type StartSessionRateCheck,
} from "@/server/start-session-rate-limit";

// RED test for Stage 2.5 of plan 2026-04-23-feat-cc-route-via-soleur-go-plan.md.
//
// Sliding-window rate limiter guarding `start_session` against runaway
// conversation spawning. Two caps layered:
//
//   (a) Per-user: 10 new conversations / hour / userId — prevents a
//       single authenticated user from drowning the runner pool.
//   (b) Per-IP: 30 new conversations / hour / IP — catches a single bad
//       actor across multiple anonymous or multi-account paths.
//
// The limiter is stateful but process-local. Container restart drops the
// window — accepted V1 behavior (see plan Stage 5). Injectable `now()`
// keeps tests deterministic.

describe("createStartSessionRateLimiter (Stage 2.5)", () => {
  it("exports defaults: 10/hour/user, 30/hour/IP", () => {
    expect(DEFAULT_PER_USER_PER_HOUR).toBe(10);
    expect(DEFAULT_PER_IP_PER_HOUR).toBe(30);
  });

  it("allows up to the per-user cap, then rejects the 11th", () => {
    let t = 0;
    const rl = createStartSessionRateLimiter({
      perUserPerHour: 10,
      perIpPerHour: 30,
      now: () => t,
    });
    for (let i = 0; i < 10; i++) {
      const r = rl.check({ userId: "u1", ip: `1.1.1.${i}` });
      expect(r.allowed).toBe(true);
      t += 1000; // 1s apart
    }
    const eleventh = rl.check({ userId: "u1", ip: "1.1.1.99" });
    expect(eleventh.allowed).toBe(false);
    if (!eleventh.allowed) {
      expect(eleventh.reason).toBe("user");
      expect(eleventh.retryAfterMs).toBeGreaterThan(0);
    }
  });

  it("allows up to the per-IP cap, then rejects the 31st", () => {
    let t = 0;
    const rl = createStartSessionRateLimiter({
      perUserPerHour: 10,
      perIpPerHour: 30,
      now: () => t,
    });
    // 30 distinct users from the same IP.
    for (let i = 0; i < 30; i++) {
      const r = rl.check({ userId: `u-${i}`, ip: "1.1.1.1" });
      expect(r.allowed).toBe(true);
      t += 1000;
    }
    const thirtyFirst = rl.check({ userId: "u-30", ip: "1.1.1.1" });
    expect(thirtyFirst.allowed).toBe(false);
    if (!thirtyFirst.allowed) {
      expect(thirtyFirst.reason).toBe("ip");
    }
  });

  it("sliding window: entries older than 1 hour are evicted", () => {
    let t = 0;
    const rl = createStartSessionRateLimiter({
      perUserPerHour: 3,
      perIpPerHour: 100,
      now: () => t,
    });
    // Exhaust the cap.
    expect(rl.check({ userId: "u1", ip: "1.1.1.1" }).allowed).toBe(true);
    t = 1000;
    expect(rl.check({ userId: "u1", ip: "1.1.1.1" }).allowed).toBe(true);
    t = 2000;
    expect(rl.check({ userId: "u1", ip: "1.1.1.1" }).allowed).toBe(true);
    t = 3000;
    expect(rl.check({ userId: "u1", ip: "1.1.1.1" }).allowed).toBe(false);

    // Jump forward past the 1-hour window from the FIRST check.
    t = 3600_001;
    const after = rl.check({ userId: "u1", ip: "1.1.1.1" });
    expect(after.allowed).toBe(true);
  });

  it("retryAfterMs is the wall-clock distance to the oldest in-window entry's expiry", () => {
    let t = 0;
    const rl = createStartSessionRateLimiter({
      perUserPerHour: 1,
      perIpPerHour: 100,
      now: () => t,
    });
    rl.check({ userId: "u1", ip: "1.1.1.1" });
    t = 100;
    const r = rl.check({ userId: "u1", ip: "1.1.1.1" }) as StartSessionRateCheck & {
      allowed: false;
    };
    expect(r.allowed).toBe(false);
    // Oldest entry at t=0; expires at t=3_600_000. Now is 100. retry ≈ 3_599_900.
    expect(r.retryAfterMs).toBe(3_600_000 - 100);
  });

  it("user and IP are independent keys — one user's cap does not affect another", () => {
    let t = 0;
    const rl = createStartSessionRateLimiter({
      perUserPerHour: 2,
      perIpPerHour: 100,
      now: () => t,
    });
    expect(rl.check({ userId: "alice", ip: "1.1.1.1" }).allowed).toBe(true);
    t += 1000;
    expect(rl.check({ userId: "alice", ip: "1.1.1.2" }).allowed).toBe(true);
    t += 1000;
    // alice exhausted.
    expect(rl.check({ userId: "alice", ip: "1.1.1.3" }).allowed).toBe(false);
    // bob unaffected.
    expect(rl.check({ userId: "bob", ip: "1.1.1.4" }).allowed).toBe(true);
  });

  it("check() with allowed=true commits the timestamp (no separate commit call)", () => {
    // A caller that receives `allowed: true` must be able to trust that
    // the token was consumed — no TOCTOU window where two concurrent
    // checks both pass. The single-method shape enforces this by
    // construction.
    let t = 0;
    const rl = createStartSessionRateLimiter({
      perUserPerHour: 1,
      perIpPerHour: 100,
      now: () => t,
    });
    const r1 = rl.check({ userId: "u1", ip: "1.1.1.1" });
    expect(r1.allowed).toBe(true);
    t += 1;
    const r2 = rl.check({ userId: "u1", ip: "1.1.1.1" });
    expect(r2.allowed).toBe(false);
  });

  it("default ctor uses Date.now when no now() is injected", () => {
    const rl = createStartSessionRateLimiter({
      perUserPerHour: 1,
      perIpPerHour: 1,
    });
    expect(rl.check({ userId: "u1", ip: "1.1.1.1" }).allowed).toBe(true);
    expect(rl.check({ userId: "u1", ip: "1.1.1.1" }).allowed).toBe(false);
  });
});
