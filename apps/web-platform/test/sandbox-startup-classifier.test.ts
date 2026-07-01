// feat-harden-agent-sandbox #5875 PR1 (ADR-079) — deterministic classifier
// tests. The 2026-07-01 P0 (#5873) was a seccomp EPERM on the SDK's split
// unshare() introduced by bump #5849; the catch sites only tagged the SDK's
// missing-binary preflight substring, so the EPERM fell through untagged.
//
// Phase-0 spike (recorded in #5875): the bwrap/seccomp stderr — including
// "Operation not permitted" — is merged into the thrown Error's `.message`
// (plain Error, no `.stderr`/`.cause`). These tests use a SYNTHESIZED signal
// in that exact shape (cq-test-fixtures-synthesized-only) — no LLM in the
// assertion path.
import { describe, it, expect } from "vitest";
import { classifySandboxStartupError } from "@/server/sandbox-startup-classifier";

// The #5873 shape: bwrap fails to set up the userns after the split unshare()
// because the container seccomp profile denied the second unshare() call.
const SECCOMP_EPERM_STDERR =
  "Command failed with exit code 1: bwrap --unshare-user --unshare-pid --unshare-ns ...\n" +
  "bwrap: Creating new namespace failed: Operation not permitted";

// The SDK's own missing-binary preflight (the ONLY signature the pre-PR1 catch
// sites recognized).
const MISSING_BINARY_STDERR = "sandbox required but unavailable";

describe("classifySandboxStartupError — sandboxKind (Phase-0 shape, #5875)", () => {
  it("tags the #5873 seccomp/userns EPERM as seccomp_or_userns_denial", () => {
    const c = classifySandboxStartupError(
      new Error(SECCOMP_EPERM_STDERR),
      "0.3.197",
    );
    expect(c.sandboxKind).toBe("seccomp_or_userns_denial");
    expect(c.errorCode).toBe("bwrap_eperm");
    expect(c.sdkVersion).toBe("0.3.197");
    // Raw stderr is preserved verbatim for the human reading Sentry.
    expect(c.stderr).toBe(SECCOMP_EPERM_STDERR);
  });

  it("tags the SDK missing-binary preflight as missing_binary", () => {
    const c = classifySandboxStartupError(
      new Error(MISSING_BINARY_STDERR),
      "0.3.197",
    );
    expect(c.sandboxKind).toBe("missing_binary");
    expect(c.errorCode).toBe("sandbox_unavailable");
  });

  it("recognizes a bwrap/unshare token even without an explicit EPERM", () => {
    const c = classifySandboxStartupError(
      new Error("bwrap: setting up uid map failed"),
      "0.3.197",
    );
    expect(c.sandboxKind).toBe("seccomp_or_userns_denial");
    expect(c.errorCode).toBe("bwrap_error");
  });

  it("does NOT mis-tag a generic model/API error (no sandbox token)", () => {
    const c = classifySandboxStartupError(
      new Error("Anthropic API 529 overloaded_error"),
      "0.3.197",
    );
    expect(c.sandboxKind).toBe("other");
    expect(c.errorCode).toBe("unclassified");
  });

  it("does NOT mis-tag a bare EPERM with no bubblewrap/namespace token", () => {
    // A mid-conversation file-permission EPERM must not read as a sandbox
    // startup failure — the whole point of the incident-class narrowing.
    const c = classifySandboxStartupError(
      new Error("EACCES: permission denied, open '/etc/shadow' — Operation not permitted"),
      "0.3.197",
    );
    expect(c.sandboxKind).toBe("other");
  });

  it("tolerates a non-Error thrown value (stringifies into stderr)", () => {
    const c = classifySandboxStartupError("bwrap: Operation not permitted", null);
    expect(c.sandboxKind).toBe("seccomp_or_userns_denial");
    expect(c.stderr).toBe("bwrap: Operation not permitted");
    expect(c.sdkVersion).toBeNull();
  });

  it("resolves the installed SDK version by default (best-effort: string|null)", () => {
    const c = classifySandboxStartupError(new Error(SECCOMP_EPERM_STDERR));
    expect(c.sdkVersion === null || typeof c.sdkVersion === "string").toBe(true);
  });
});

// Tagging-decision contract (CTO ruling, ADR-079): both catch sites tag
// `feature:"agent-sandbox"` IFF `sandboxKind !== "other"` — the SIGNATURE, not a
// stream-phase gate. `streamStartSent` is always true at the catch (set before
// the iterator loop) and the seccomp denial surfaces mid-stream, so a phase gate
// would silently suppress the real signal. The signature axis is exercised by
// the `sandboxKind` cases above; the emit wiring (per-user, tag/extra shape) is
// covered end-to-end by test/agent-runner-sandbox-config.test.ts (positive:
// iterator-throw still tags with streamStartSent===true) and
// test/cc-dispatcher-real-factory.test.ts (T16).
