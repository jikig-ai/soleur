// #5275 — the `isDisconnected` discriminant gates the in-flight checkpoint.
// AC4 (part a): only a `disconnected` abort sets `isDisconnected`; every other
// AbortKind leaves it false (so no checkpoint is written for them).
import { describe, it, expect } from "vitest";
import {
  classifyAbortReason,
  SessionAbortError,
  type AbortKind,
} from "@/server/abort-classifier";

const ALL_KINDS: AbortKind[] = [
  "disconnected",
  "superseded",
  "user_requested_stop",
  "account_deleted",
  "server_shutdown",
  "workspace_membership_revoked",
];

describe("classifyAbortReason — isDisconnected discriminant (#5275)", () => {
  it("sets isDisconnected ONLY for the disconnected kind", () => {
    for (const kind of ALL_KINDS) {
      const result = classifyAbortReason(new SessionAbortError(kind));
      expect(result.kind).toBe(kind);
      expect(result.isDisconnected).toBe(kind === "disconnected");
    }
  });

  it("treats an unknown/non-Error reason as NOT disconnected (no checkpoint)", () => {
    // The grace path aborts with a SessionAbortError("disconnected"), so the
    // unknown fallback must not accidentally trigger a checkpoint.
    expect(classifyAbortReason(undefined).isDisconnected).toBe(false);
    expect(classifyAbortReason("nope").isDisconnected).toBe(false);
    expect(classifyAbortReason(new Error("random")).isDisconnected).toBe(false);
  });

  it("keeps the existing user-requested / superseded discriminants intact", () => {
    const u = classifyAbortReason(new SessionAbortError("user_requested_stop"));
    expect(u.isUserRequested).toBe(true);
    expect(u.isDisconnected).toBe(false);
    const s = classifyAbortReason(new SessionAbortError("superseded"));
    expect(s.isSuperseded).toBe(true);
    expect(s.isDisconnected).toBe(false);
  });
});
