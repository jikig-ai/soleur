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
import {
  classifySandboxStartupError,
  classifyBashSandboxFailure,
} from "@/server/sandbox-startup-classifier";

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

  it("tags the #8752 PATH-shim refusal marker as a sandbox-namespace denial", () => {
    // The shim fails closed with `bwrap-shim: <cause>` + exit 65 — the
    // `bwrap` token inside the marker routes it to seccomp_or_userns_denial,
    // not a generic environment error.
    const c = classifySandboxStartupError(
      new Error("Command failed with exit code 65: bwrap-shim: seccomp artifact not readable: /app/infra/bwrap-userns-clone3-deny.bpf"),
      "0.3.197",
    );
    expect(c.sandboxKind).toBe("seccomp_or_userns_denial");
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

  it("also scans err.cause when the sandbox text is not on .message", () => {
    // Future-proofing: an SDK that moves bwrap/seccomp stderr onto `.cause`
    // must not degrade to "other" (silent #5873 recurrence).
    const err = new Error("Command failed with exit code 1", {
      cause: new Error("bwrap: Operation not permitted"),
    });
    const c = classifySandboxStartupError(err, "0.3.197");
    expect(c.sandboxKind).toBe("seccomp_or_userns_denial");
    expect(c.errorCode).toBe("bwrap_eperm");
    expect(c.stderr).toContain("bwrap: Operation not permitted");
  });

  it("also scans a string .stderr property", () => {
    const err = Object.assign(new Error("Command failed"), {
      stderr: "bwrap: setting up uid map: Operation not permitted",
    });
    const c = classifySandboxStartupError(err, "0.3.197");
    expect(c.sandboxKind).toBe("seccomp_or_userns_denial");
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

// #10032 (ADR-075 addendum 2026-10-11) — a Bash tool_result whose output carries a bwrap denial. The session-start
// classifier above only sees errors THROWN out of the SDK iterator; a failed sandbox spawn that the SDK returns to
// the model as a tool_result (the shape the shim's fresh `--proc /proc` refusal takes under docker's masked /proc)
// reached Sentry as nothing. Fixtures use bwrap's REAL stderr text, never a paraphrase.
describe("classifyBashSandboxFailure — Bash tool_result sandbox denial (#10032)", () => {
  const PROC_MOUNT_EPERM = "bwrap: Can't mount proc on /newroot/proc: Operation not permitted";

  it("classifies the shim's fresh-procfs refusal as proc_mount_eperm and returns ONLY the matched line", () => {
    const f = classifyBashSandboxFailure(PROC_MOUNT_EPERM, "0.3.284");
    expect(f).not.toBeNull();
    expect(f?.errorCode).toBe("proc_mount_eperm");
    expect(f?.sdkVersion).toBe("0.3.284");
    expect(f?.matchedLine).toBe(PROC_MOUNT_EPERM);
  });

  it("data minimisation: a secret-looking neighbour line never reaches the result (Art. 5(1)(c))", () => {
    const secretLine = "DATABASE_URL=postgres://user:hunter2@db.internal/prod";
    const out = `${secretLine}\n${PROC_MOUNT_EPERM}\nsk-ant-api03-notarealkeynotarealkeynotarealkey\n`;
    const f = classifyBashSandboxFailure(out, "0.3.284");
    expect(f?.matchedLine).toBe(PROC_MOUNT_EPERM);
    expect(JSON.stringify(f)).not.toContain("hunter2");
    expect(JSON.stringify(f)).not.toContain("sk-ant-api03");
  });

  it("scrubs workspace paths and uuids out of the matched line", () => {
    const uuid = "754ee124-706a-4f21-a4f4-e828257b0380";
    const line = `bwrap: Can't bind mount /workspaces/${uuid}/repo on /newroot/workspaces/${uuid}/repo: Operation not permitted`;
    const f = classifyBashSandboxFailure(line, null);
    expect(f).not.toBeNull();
    expect(f?.matchedLine).not.toContain(uuid);
    expect(f?.matchedLine).not.toContain("/workspaces/");
    expect(f?.matchedLine).toContain("Operation not permitted");
  });

  it("caps the matched line (no unbounded tool output reaches Sentry)", () => {
    const f = classifyBashSandboxFailure(`bwrap: ${"x".repeat(5000)}: Operation not permitted`, null);
    expect(f).not.toBeNull();
    expect(f!.matchedLine.length).toBeLessThanOrEqual(300);
  });

  it("classifies a generic bwrap namespace EPERM as bwrap_eperm", () => {
    const f = classifyBashSandboxFailure("bwrap: Creating new namespace failed: Operation not permitted", null);
    expect(f?.errorCode).toBe("bwrap_eperm");
  });

  it("returns null for an ordinary permission error with no sandbox token", () => {
    expect(classifyBashSandboxFailure("cat: /etc/shadow: Permission denied", null)).toBeNull();
    expect(classifyBashSandboxFailure("rm: cannot remove 'x': Operation not permitted", null)).toBeNull();
  });

  it("returns null when the output merely MENTIONS bwrap without a denial on the same line", () => {
    expect(classifyBashSandboxFailure("$ which bwrap\n/usr/local/bin/bwrap\n", null)).toBeNull();
    expect(classifyBashSandboxFailure("bubblewrap 0.8.0", null)).toBeNull();
  });

  it("returns null for empty and non-string-ish input", () => {
    expect(classifyBashSandboxFailure("", null)).toBeNull();
  });
});
