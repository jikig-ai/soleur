import { randomBytes, randomUUID } from "node:crypto";
import { describe, expect, it } from "vitest";

import { createReplayCache, signProxyHello, verifyProxyHello } from "@/server/proxy-hello";

// #8211 (ADR-323 Decision 9, B3) — Guard 2: why a routine rotation of the relay hello key takes THREE phases. Every
// host both signs and verifies, and a rolling restart leaves two hosts in adjacent phases for one stagger, so every
// adjacent pair must complete a signed round trip in BOTH directions. A skipped phase splits the hosts in the direction
// predicted below. The PHASES table is a test fixture (the executable statement the ADR cites), not a production
// definition. A host signs with its CURRENT key only (production rule: the sender is given `current`); the
// accept-only slot is verify-only. Real signProxyHello on one side, real verifyProxyHello on the other.

interface HostState {
  readonly phase: string;
  readonly signWith: Buffer;
  readonly accept: { readonly current: Buffer; readonly acceptAlso: Buffer | null };
}

function phases(oldKey: Buffer, newKey: Buffer): readonly HostState[] {
  const host = (phase: string, current: Buffer, acceptAlso: Buffer | null): HostState => ({
    phase,
    signWith: current,
    accept: { current, acceptAlso },
  });
  return [
    host("P0", oldKey, null), // before the rotation
    host("P1", oldKey, newKey), // sign old, slot holds new
    host("P2", newKey, oldKey), // sign new, slot holds old
    host("P3", newKey, null), // sign new, slot unset
  ];
}

const U = randomUUID();
const W = randomUUID();
const NOW_MS = 1_800_000_000_000;
const now = () => NOW_MS;

/** A sends one hello to B; B verifies it on a fresh replay cache. */
function roundTrip(from: HostState, to: HostState) {
  const text = signProxyHello(from.signWith, U, W, { now });
  return verifyProxyHello(Buffer.from(text), false, to.accept, createReplayCache(), now);
}

// Must-PASS: the table holds for two independent synthetic old/new key pairs.
const KEY_PAIRS: Array<[string, Buffer, Buffer]> = [
  ["key pair A", randomBytes(32), randomBytes(32)],
  ["key pair B", randomBytes(32), randomBytes(32)],
];

describe.each(KEY_PAIRS)("rotation phases (%s)", (_label, OLD, NEW) => {
  const P = phases(OLD, NEW);
  const byName = (n: string) => {
    const h = P.find((p) => p.phase === n);
    if (!h) throw new Error(`no phase ${n}`);
    return h;
  };

  it("fixture distinctness: old and new are different keys (else every refusal row is vacuous)", () => {
    expect(OLD.equals(NEW)).toBe(false);
    expect(P.map((p) => p.phase)).toEqual(["P0", "P1", "P2", "P3"]);
  });

  it("every adjacent pair completes a signed round trip in both directions (exactly 3 pairs x 2 = 6)", () => {
    const done: string[] = [];
    for (let i = 0; i + 1 < P.length; i++) {
      for (const [a, b] of [
        [P[i], P[i + 1]],
        [P[i + 1], P[i]],
      ] as const) {
        expect(roundTrip(a, b), `${a.phase}->${b.phase}`).toEqual({ ok: true, userId: U, workspaceId: W });
        done.push(`${a.phase}->${b.phase}`);
      }
    }
    expect(done).toEqual(["P0->P1", "P1->P0", "P1->P2", "P2->P1", "P2->P3", "P3->P2"]);
  });

  it.each([
    ["P2", "P0", false],
    ["P0", "P2", true],
    ["P1", "P3", false],
    ["P3", "P1", true],
  ] as const)("skipped phase: %s -> %s accepted=%s", (from, to, accepted) => {
    const r = roundTrip(byName(from), byName(to));
    if (accepted) expect(r).toEqual({ ok: true, userId: U, workspaceId: W });
    else expect(r).toEqual({ ok: false, reason: "mac" });
  });

  it("the accepted skip directions are admitted ONLY through the accept-only slot (the verifier must read acceptAlso)", () => {
    for (const [from, to] of [
      ["P0", "P2"],
      ["P3", "P1"],
    ] as const) {
      const target = byName(to);
      const withoutSlot: HostState = { ...target, accept: { current: target.accept.current, acceptAlso: null } };
      expect(roundTrip(byName(from), withoutSlot), `${from}->${to} without the slot`).toEqual({ ok: false, reason: "mac" });
      expect(roundTrip(byName(from), target), `${from}->${to} with the slot`).toEqual({ ok: true, userId: U, workspaceId: W });
    }
  });

  it("no host ever signs with its accept-only key: each phase's signing key is its current key", () => {
    for (const h of P) expect(h.signWith.equals(h.accept.current), h.phase).toBe(true);
  });
});
