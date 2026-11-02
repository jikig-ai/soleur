/**
 * #10543 — decideReplay: the pure pre-gate decision for a re-click on a draft that already has an
 * approval row. Pins the arm ORDER (terminal -> no_artifact -> age -> hash) and both age boundaries
 * exactly, with a fixed clock, so no route mock is needed.
 */

import { describe, test, expect } from "vitest";

import {
  decideReplay,
  CLOCK_SKEW_TOLERANCE_MS,
  REPLAY_MAX_AGE_MS,
  type ExistingApprovalRow,
} from "@/server/action-sends/decide-replay";

const NOW = Date.parse("2026-10-26T12:00:00.000Z");
const HASH = "a".repeat(64);

function row(over: Partial<ExistingApprovalRow> = {}): ExistingApprovalRow {
  return {
    id: "44444444-4444-4444-aaaa-444444444444",
    per_send_body_sha256: HASH,
    tier_at_send: "draft_one_click",
    clicked_at: new Date(NOW - 60 * 60 * 1000).toISOString(),
    acknowledged_at: null,
    failure_reason: null,
    undone_at: null,
    cancellation_requested_at: null,
    ...over,
  };
}

const decide = (
  existing: ExistingApprovalRow,
  over: { parsed?: boolean; draftPreviewHash?: string } = {},
) =>
  decideReplay({
    existing,
    parsed: over.parsed ?? true,
    nowMs: NOW,
    draftPreviewHash: over.draftPreviewHash ?? HASH,
  });

describe("decideReplay", () => {
  test("a fresh pending row with a matching hash replays", () => {
    expect(decide(row())).toEqual({ kind: "replay" });
  });

  test.each([
    ["acknowledged_at", { acknowledged_at: "2026-10-26T11:30:00.000Z" }],
    ["failure_reason", { failure_reason: "boom" }],
    ["undone_at", { undone_at: "2026-10-26T11:30:00.000Z" }],
    [
      "cancellation_requested_at",
      { cancellation_requested_at: "2026-10-26T11:30:00.000Z" },
    ],
  ] as const)("%s set is terminal", (_n, over) => {
    expect(decide(row(over))).toEqual({ kind: "terminal" });
  });

  test("arm order: terminal beats no_artifact, expiry and hash", () => {
    const r = row({
      acknowledged_at: "2026-10-25T01:00:00.000Z",
      clicked_at: new Date(NOW - 30 * 60 * 60 * 1000).toISOString(),
      per_send_body_sha256: null,
    });
    expect(decide(r, { parsed: false })).toEqual({ kind: "terminal" });
  });

  test("arm order: no_artifact beats expiry and hash", () => {
    const r = row({
      clicked_at: new Date(NOW - 30 * 60 * 60 * 1000).toISOString(),
      per_send_body_sha256: null,
    });
    expect(decide(r, { parsed: false })).toEqual({ kind: "no_artifact" });
  });

  test("arm order: expiry beats the hash check", () => {
    const r = row({
      clicked_at: new Date(NOW - REPLAY_MAX_AGE_MS - 1).toISOString(),
      per_send_body_sha256: null,
    });
    expect(decide(r)).toEqual({ kind: "expired" });
  });

  test("age boundary: exactly 23h replays, 23h + 1ms is expired", () => {
    expect(
      decide(row({ clicked_at: new Date(NOW - REPLAY_MAX_AGE_MS).toISOString() })),
    ).toEqual({ kind: "replay" });
    expect(
      decide(
        row({ clicked_at: new Date(NOW - REPLAY_MAX_AGE_MS - 1).toISOString() }),
      ),
    ).toEqual({ kind: "expired" });
  });

  test("clock skew: a click up to 60s in the FUTURE replays; one ms past that fails closed", () => {
    expect(
      decide(
        row({
          clicked_at: new Date(NOW + CLOCK_SKEW_TOLERANCE_MS).toISOString(),
        }),
      ),
    ).toEqual({ kind: "replay" });
    expect(
      decide(
        row({
          clicked_at: new Date(NOW + CLOCK_SKEW_TOLERANCE_MS + 1).toISOString(),
        }),
      ),
    ).toEqual({ kind: "clock_skew" });
  });

  test.each([
    ["garbage", "not-a-timestamp"],
    ["null", null],
    ["empty", ""],
  ])("a %s clicked_at fails closed to clock_skew (never replays)", (_n, v) => {
    expect(decide(row({ clicked_at: v }))).toEqual({ kind: "clock_skew" });
  });

  test("a NULL or different stored hash is draft_changed", () => {
    expect(decide(row({ per_send_body_sha256: null }))).toEqual({
      kind: "draft_changed",
    });
    expect(decide(row(), { draftPreviewHash: "b".repeat(64) })).toEqual({
      kind: "draft_changed",
    });
  });
});
