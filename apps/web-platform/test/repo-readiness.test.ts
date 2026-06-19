import { describe, it, expect } from "vitest";
import {
  evaluateRepoReadiness,
  RepoNotReadyError,
  REPO_CLONING_MSG,
  REPO_CHECKOUT_MISSING_MSG,
  repoErrorMsg,
} from "@/server/repo-readiness";

// #5394 — the pure predicate behind the Concierge dispatch readiness gate.
// Drives every repo_status branch DB-free so the gate's load-bearing decision
// (block cloning/error, never block ready) is proven without spinning the SDK
// or the dispatcher.
describe("evaluateRepoReadiness", () => {
  it("AC1: cloning → blocked with the exact shared cloning message", () => {
    const r = evaluateRepoReadiness("cloning", null);
    expect(r.ok).toBe(false);
    if (r.ok) throw new Error("unreachable");
    expect(r.code).toBe("cloning");
    expect(r.message).toBe(REPO_CLONING_MSG);
    // cloning carries no errorCode (only error does — AC1 vs AC2)
    expect(r.errorCode).toBeUndefined();
  });

  it("AC2: error → blocked with reconnect copy + repo_setup_failed errorCode", () => {
    const r = evaluateRepoReadiness(
      "error",
      JSON.stringify({ code: "AUTH_FAILED", message: "Authentication failed" }),
    );
    expect(r.ok).toBe(false);
    if (r.ok) throw new Error("unreachable");
    expect(r.code).toBe("error");
    expect(r.errorCode).toBe("repo_setup_failed");
    expect(r.message).toContain("Authentication failed");
    expect(r.message).toContain("Reconnect in Settings → Repository");
  });

  it("AC2: error with a NULL reason still yields a non-empty reconnect message", () => {
    // workspaces.repo_error is always NULL; users.repo_error is the source.
    // A genuinely-absent reason must still produce actionable copy, never blank.
    const r = evaluateRepoReadiness("error", null);
    expect(r.ok).toBe(false);
    if (r.ok) throw new Error("unreachable");
    expect(r.code).toBe("error");
    expect(r.message).toContain("Reconnect in Settings → Repository");
    // Pin the actual fallback literal (not just "non-empty") so a future change
    // to the fallback string is caught rather than silently passing length-only.
    expect(r.message).toContain("setup failed");
  });

  it("AC3: ready → ok (dispatch proceeds, no regression)", () => {
    expect(evaluateRepoReadiness("ready", null)).toEqual({ ok: true });
  });

  it("not_connected → ok (flows to the existing repo-less path / #5392 fallback)", () => {
    expect(evaluateRepoReadiness("not_connected", null)).toEqual({ ok: true });
  });

  it("fail-open: a null/unknown status coerces to ok (never block a ready founder on a read blip)", () => {
    expect(evaluateRepoReadiness(null, null)).toEqual({ ok: true });
    expect(evaluateRepoReadiness(undefined, null)).toEqual({ ok: true });
    expect(evaluateRepoReadiness("some-future-status", null)).toEqual({
      ok: true,
    });
  });

  it("AC9: error reason routes through the shared sanitizer — no raw stderr / absolute path leaks", () => {
    const raw =
      "fatal: could not read Username for 'https://github.com': /home/soleur/workspaces/abc/.git/askpass";
    const r = evaluateRepoReadiness("error", raw);
    expect(r.ok).toBe(false);
    if (r.ok) throw new Error("unreachable");
    // No absolute filesystem path should survive into the user-facing message.
    expect(r.message).not.toMatch(/\/home\/soleur/);
    expect(r.message).toContain("<path>");
  });
});

describe("RepoNotReadyError", () => {
  it("carries code + optional errorCode and a stable name", () => {
    const e = new RepoNotReadyError("error", "boom", "repo_setup_failed");
    expect(e).toBeInstanceOf(Error);
    expect(e.name).toBe("RepoNotReadyError");
    expect(e.code).toBe("error");
    expect(e.errorCode).toBe("repo_setup_failed");
    expect(e.message).toBe("boom");

    const c = new RepoNotReadyError("cloning", REPO_CLONING_MSG);
    expect(c.code).toBe("cloning");
    expect(c.errorCode).toBeUndefined();
  });
});

describe("repoErrorMsg", () => {
  it("embeds the reason and the reconnect CTA", () => {
    expect(repoErrorMsg("disk full")).toBe(
      "Repository setup failed: disk full. Reconnect in Settings → Repository.",
    );
  });
});

describe("REPO_CHECKOUT_MISSING_MSG", () => {
  it("is retry-first with a reconnect fallback, and leaks no internal detail", () => {
    expect(REPO_CHECKOUT_MISSING_MSG).toContain("try again in a moment");
    expect(REPO_CHECKOUT_MISSING_MSG).toContain(
      "reconnect in Settings → Repository",
    );
    // No internal enum / path / tool name leaks to the user.
    expect(REPO_CHECKOUT_MISSING_MSG).not.toMatch(/\.git|gh api|workspace|null/);
    // Future-proof against a later "helpful" edit that interpolates context:
    // no absolute fs paths, no GitHub tokens, no raw id digit-runs.
    expect(REPO_CHECKOUT_MISSING_MSG).not.toMatch(/\/(home|tmp|root|Users)\//);
    expect(REPO_CHECKOUT_MISSING_MSG).not.toMatch(/gh[pousr]_/);
    expect(REPO_CHECKOUT_MISSING_MSG).not.toMatch(/\d{5,}/);
  });
});
