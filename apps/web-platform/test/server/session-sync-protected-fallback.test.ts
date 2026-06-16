// #5426 — KB-sync protected-branch trigger fix.
//
// Phase 1: classifyPushError — pure classifier over git/GitHub push-rejection
// stderr. Distinguishes a protected-branch rejection (→ side-branch + PR
// fallback) from a persistent non-protection reject that must NOT loop
// (`shallow update not allowed`) from transient/other (existing best-effort
// retry). Fixtures are synthesized from real GitHub stderr shapes per
// cq-test-fixtures-synthesized-only.

import { describe, test, expect } from "vitest";
import { classifyPushError } from "@/server/session-sync";

function pushErr(message: string, stderr?: string): Error {
  const e = new Error(message);
  if (stderr !== undefined) {
    (e as Error & { stderr?: string }).stderr = stderr;
  }
  return e;
}

describe("classifyPushError", () => {
  test("GH006 protected-branch rejection → protected_branch", () => {
    const err = pushErr(
      "Command failed: git push",
      [
        "remote: error: GH006: Protected branch update failed for refs/heads/main.",
        "remote: error: Changes must be made through a pull request.",
        "To github.com:owner/repo.git",
        " ! [remote rejected] main -> main (protected branch hook declined)",
        "error: failed to push some refs to 'github.com:owner/repo.git'",
      ].join("\n"),
    );
    expect(classifyPushError(err)).toBe("protected_branch");
  });

  test("required-approving-review tail still classifies protected_branch", () => {
    const err = pushErr(
      "push failed",
      "remote: error: GH006: Protected branch update failed for refs/heads/main.\nremote: error: At least 1 approving review is required by reviewers with write access.",
    );
    expect(classifyPushError(err)).toBe("protected_branch");
  });

  test("required-status-check tail still classifies protected_branch", () => {
    const err = pushErr(
      "push failed",
      " ! [remote rejected] main -> main (protected branch hook declined)\nremote: error: Required status check \"ci\" is expected.",
    );
    expect(classifyPushError(err)).toBe("protected_branch");
  });

  test("shallow clone reject → persistent_other (must not loop)", () => {
    const err = pushErr(
      "push failed",
      " ! [remote rejected] main -> main (shallow update not allowed)\nerror: failed to push some refs",
    );
    expect(classifyPushError(err)).toBe("persistent_other");
  });

  test("auth failure → other (existing best-effort retry)", () => {
    const err = pushErr(
      "Command failed: git push",
      "remote: Invalid username or password.\nfatal: Authentication failed for 'https://github.com/owner/repo.git/'",
    );
    expect(classifyPushError(err)).toBe("other");
  });

  test("network failure → other", () => {
    const err = pushErr(
      "Command failed: git push",
      "fatal: unable to access 'https://github.com/owner/repo.git/': Could not resolve host: github.com",
    );
    expect(classifyPushError(err)).toBe("other");
  });

  test("non-Error input does not throw and classifies other", () => {
    expect(classifyPushError("some string")).toBe("other");
    expect(classifyPushError(undefined)).toBe("other");
  });
});
