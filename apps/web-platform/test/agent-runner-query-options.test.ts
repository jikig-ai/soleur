// Drift-guard tests for `buildAgentQueryOptions` (#2922). Two consumers
// (legacy `agent-runner.ts startAgentSession` and cc-soleur-go
// `realSdkQueryFactory` in `cc-dispatcher.ts`) MUST receive the same
// canonical options shape for shared fields. Per-call divergent fields
// (mcpServers, allowedTools, model, maxTurns, etc.) flow through args.
//
// T1 — minimum-args call returns the canonical shape (cwd, model,
//      permissionMode, settingSources, includePartialMessages, sandbox,
//      plugins, hooks.PreToolUse).
// T2 — args.allowedTools wired through verbatim.
// T3 — args.systemPrompt wired through verbatim.
// T4 — drift-guard: stable JSON snapshot of canonical fields fails
//      LOUDLY when the helper drifts.

import { describe, it, expect, vi } from "vitest";

vi.mock("@/server/agent-env", () => ({
  // `satisfies typeof …buildAgentEnv` pins the mock to the REAL signature so a
  // 3rd-arg shape drift (e.g. a `pluginPath` rename) is a compile break here,
  // not a silently-green AC3 tested on the wrong side of the mock seam.
  buildAgentEnv: vi.fn(((credential, _tokens, opts) => ({
    ANTHROPIC_API_KEY: credential.value,
    // Mirror the real buildAgentEnv contract for the CLAUDE_PLUGIN_ROOT export
    // so the AC3 integration pin below can assert the value survives
    // pass-through into the final options.env (catches a downstream drop).
    ...(opts?.pluginPath ? { CLAUDE_PLUGIN_ROOT: opts.pluginPath } : {}),
  })) satisfies typeof import("@/server/agent-env").buildAgentEnv),
}));

vi.mock("@/server/sandbox-hook", () => ({
  createSandboxHook: vi.fn(() => async () => ({})),
}));

// Emit-fork sinks for the outer-wrap boot probe (#5863 T3.4) — same shape as
// the bwrap-shim probe tests: which surface each verdict branch writes to.
// Spread the real module so other exports (hashUserId, TtlDedupMap, …)
// transitive consumers rely on keep working.
const obs = vi.hoisted(() => ({ warnSilentFallback: vi.fn(), reportSilentFallback: vi.fn() }));
vi.mock("@/server/observability", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/observability")>()),
  warnSilentFallback: obs.warnSilentFallback,
  reportSilentFallback: obs.reportSilentFallback,
}));
const sentry = vi.hoisted(() => ({ captureMessage: vi.fn(), captureException: vi.fn() }));
vi.mock("@sentry/nextjs", () => sentry);

import { buildAgentQueryOptions } from "@/server/agent-runner-query-options";
import { buildAgentEnv } from "@/server/agent-env";
import { AGENT_AUTH_ENV_VARS } from "@/server/agent-auth-env-vars";
import { resolveWorkspaceMode } from "@/server/workspace-mode";

const WORKSPACE = "/tmp/test-workspace";
const PLUGIN = "/tmp/test-workspace/plugins/soleur";

const minArgs = {
  workspacePath: WORKSPACE,
  pluginPath: PLUGIN,
  mode: resolveWorkspaceMode("command_center"),
  credential: { value: "sk-test", scheme: "api_key" as const },
  serviceTokens: {} as Record<string, string>,
  systemPrompt: "you are a router",
  canUseTool: (async () => ({ behavior: "allow" as const, updatedInput: {} })) as never,
};

describe("buildAgentQueryOptions — canonical shape (T1)", () => {
  it("T1: returns the canonical shape for minimum args", () => {
    const opts = buildAgentQueryOptions(minArgs);

    expect(opts.cwd).toBe(WORKSPACE);
    expect(opts.model).toBe("claude-sonnet-5-5");
    expect(opts.permissionMode).toBe("default");
    expect(opts.settingSources).toEqual([]);
    expect(opts.includePartialMessages).toBe(true);
    expect(opts.disallowedTools).toEqual(["WebSearch", "WebFetch"]);
    expect(opts.sandbox).toBeDefined();
    // biome-ignore lint/style/noNonNullAssertion: shape verified by toBeDefined
    expect(opts.sandbox!.failIfUnavailable).toBe(true);
    expect(opts.plugins).toEqual([{ type: "local", path: PLUGIN }]);
    expect(opts.hooks?.PreToolUse).toBeDefined();
    // biome-ignore lint/style/noNonNullAssertion: shape verified above
    expect(Array.isArray(opts.hooks!.PreToolUse)).toBe(true);
    // biome-ignore lint/style/noNonNullAssertion: shape verified above
    expect(opts.hooks!.PreToolUse![0].matcher).toContain("Bash");
    expect(opts.systemPrompt).toBe("you are a router");
    expect(opts.canUseTool).toBe(minArgs.canUseTool);
  });
});

// W1 (#9601, ADR-272): the credential deny is only real if the sandbox object
// the REAL factories hand to `query()` carries it. `agent-sandbox-credential-deny`
// pins `buildAgentSandboxConfig`; this pins the wire from that builder to the
// consumer. It drives EVERY combination of the inputs production varies (the cc
// dispatch passes ghToken + askpass, connected services add serviceTokens, the
// support persona is read-only, some callers add disallowed tools): a branch that
// drops the deny for one shape passes any single hand-picked case.
describe("buildAgentQueryOptions — Anthropic credential deny reaches opts.sandbox (W1)", () => {
  const TOGGLES: [string, Record<string, unknown>][] = [
    ["ghToken", { ghToken: "ghs_install_tok" }],
    ["askpass", { gitAskpassScriptPath: "/tmp/test-workspace/.askpass-xyz.sh" }],
    ["serviceTokens", { serviceTokens: { PLAUSIBLE_API_KEY: "svc-token" } }],
    ["extraDisallowedTools", { extraDisallowedTools: ["mcp__example__tool"] }],
  ];
  const MODES = ["command_center", "support"] as const;

  const cases: [string, Record<string, unknown>][] = [];
  for (const mode of MODES) {
    for (let mask = 0; mask < 1 << TOGGLES.length; mask += 1) {
      const picked = TOGGLES.filter((_, i) => mask & (1 << i));
      cases.push([
        `${mode} + [${picked.map(([n]) => n).join(", ") || "nothing"}]`,
        { mode: resolveWorkspaceMode(mode), ...Object.assign({}, ...picked.map(([, v]) => v)) },
      ]);
    }
  }

  it("covers every combination (the instrument is not empty)", () => {
    expect(cases).toHaveLength(MODES.length * (1 << TOGGLES.length));
  });

  it.each(cases)("%s", (_label, extra) => {
    vi.mocked(buildAgentEnv).mockClear();
    const opts = buildAgentQueryOptions({ ...minArgs, ...extra });
    const entries = (opts.sandbox as { credentials?: { envVars: { name: string; mode: string }[] } })
      .credentials?.envVars;
    expect(entries).toBeDefined();
    expect((entries ?? []).map((e) => e.name).sort()).toEqual([...AGENT_AUTH_ENV_VARS].sort());
    for (const e of entries ?? []) expect(e.mode).toBe("deny");
    // The factory hands the CLI exactly what buildAgentEnv built: it adds no
    // key (an auth variable set from the credential here would bypass the
    // derived-set test, which reads buildAgentEnv's return).
    expect(opts.env).toEqual(vi.mocked(buildAgentEnv).mock.results.at(-1)?.value);
  });
});

describe("buildAgentQueryOptions — PostToolUse(Bash) git-lock telemetry always-on (#4826)", () => {
  it("ALWAYS registers the Bash git-lock marker hook, even for the legacy caller", () => {
    const off = buildAgentQueryOptions(minArgs);
    // PostToolUse is now always present: the #4826 telemetry hook is unconditional
    // (a git-lock wedge is path-agnostic). The Bash entry is index 0; Skill hints append.
    expect(Array.isArray(off.hooks?.PostToolUse)).toBe(true);
    expect(off.hooks!.PostToolUse![0].matcher).toBe("Bash");
    // The other hooks remain regardless.
    expect(off.hooks?.PreToolUse).toBeDefined();
    expect(off.hooks?.SubagentStart).toBeDefined();
  });

  it("registers ONLY the Bash hook when neither Skill opt-in is set", () => {
    const off = buildAgentQueryOptions(minArgs);
    expect(off.hooks!.PostToolUse!).toHaveLength(1);
    expect(off.hooks!.PostToolUse![0].matcher).toBe("Bash");
  });
});

describe("buildAgentQueryOptions — phase-surface hint per-caller opt-in (#5772 lever 1)", () => {
  it("appends PostToolUse(Skill) after the always-on Bash hook when enablePhaseSurfaceHint is true", () => {
    const on = buildAgentQueryOptions({ ...minArgs, enablePhaseSurfaceHint: true });
    expect(on.hooks!.PostToolUse!).toHaveLength(2);
    expect(on.hooks!.PostToolUse![0].matcher).toBe("Bash");
    expect(on.hooks!.PostToolUse![1].matcher).toBe("Skill");
  });
});

describe("buildAgentQueryOptions — context_queries hook per-caller opt-in (#6046, AC9)", () => {
  it("appends one Skill entry after the Bash hook when only enableContextQueries is true", () => {
    const on = buildAgentQueryOptions({ ...minArgs, enableContextQueries: true });
    expect(on.hooks!.PostToolUse!).toHaveLength(2);
    expect(on.hooks!.PostToolUse![0].matcher).toBe("Bash");
    expect(on.hooks!.PostToolUse![1].matcher).toBe("Skill");
  });

  it("registers the Bash hook + TWO independent Skill entries when both flags are true", () => {
    const both = buildAgentQueryOptions({
      ...minArgs,
      enablePhaseSurfaceHint: true,
      enableContextQueries: true,
    });
    expect(both.hooks!.PostToolUse!).toHaveLength(3);
    expect(both.hooks!.PostToolUse![0].matcher).toBe("Bash");
    expect(both.hooks!.PostToolUse!.slice(1).every((e: { matcher?: string }) => e.matcher === "Skill")).toBe(true);
  });
});

describe("buildAgentQueryOptions — tool-attempt telemetry per-caller opt-in (#5843, AC5)", () => {
  const telemetryHook = (async () => ({})) as never;

  it("appends a SEPARATE matcher-less PreToolUse entry only when the hook is passed", () => {
    const on = buildAgentQueryOptions({
      ...minArgs,
      toolAttemptPreToolUseHook: telemetryHook,
    });
    // The sandbox entry stays first + unchanged (its matcher is preserved), and
    // the telemetry entry is appended matcher-less (full-surface capture).
    expect(on.hooks!.PreToolUse).toHaveLength(2);
    expect(on.hooks!.PreToolUse![0].matcher).toContain("Bash");
    expect(on.hooks!.PreToolUse![1].matcher).toBeUndefined();
    expect(on.hooks!.PreToolUse![1].hooks).toEqual([telemetryHook]);
  });

  it("legacy caller (hook absent) keeps exactly ONE PreToolUse entry — the sandbox hook (AC5 byte-unchanged)", () => {
    const off = buildAgentQueryOptions(minArgs);
    expect(off.hooks!.PreToolUse).toHaveLength(1);
    expect(off.hooks!.PreToolUse![0].matcher).toContain("Bash");
  });
});

describe("buildAgentQueryOptions — per-call overrides (T2/T3)", () => {
  it("T2: allowedTools is wired through verbatim", () => {
    const opts = buildAgentQueryOptions({
      ...minArgs,
      allowedTools: ["mcp__soleur_platform__kb_share_create"],
    });
    expect(opts.allowedTools).toEqual([
      "mcp__soleur_platform__kb_share_create",
    ]);
  });

  it("T3: systemPrompt is wired through verbatim", () => {
    const opts = buildAgentQueryOptions({
      ...minArgs,
      systemPrompt: "alpha bravo charlie",
    });
    expect(opts.systemPrompt).toBe("alpha bravo charlie");
  });

  it("threads resumeSessionId into options.resume when present", () => {
    const opts = buildAgentQueryOptions({
      ...minArgs,
      resumeSessionId: "sess-abc",
    });
    expect(opts.resume).toBe("sess-abc");
  });

  it("omits options.resume when no resumeSessionId provided", () => {
    const opts = buildAgentQueryOptions(minArgs);
    expect(opts.resume).toBeUndefined();
  });

  it("threads model override (cc path uses claude-sonnet-5-5 too — same default)", () => {
    const opts = buildAgentQueryOptions({
      ...minArgs,
      model: "claude-opus-4-7",
    });
    expect(opts.model).toBe("claude-opus-4-7");
  });

  it("maxTurns/maxBudgetUsd flow through (legacy path)", () => {
    const opts = buildAgentQueryOptions({
      ...minArgs,
      maxTurns: 50,
      maxBudgetUsd: 5.0,
    });
    expect(opts.maxTurns).toBe(50);
    expect(opts.maxBudgetUsd).toBe(5.0);
  });

  it("mcpServers={} (cc path) is preserved", () => {
    const opts = buildAgentQueryOptions({
      ...minArgs,
      mcpServers: {},
    });
    expect(opts.mcpServers).toEqual({});
  });

  it("subagentStartPayloadOverride switches the SubagentStart hook payload (legacy vs cc)", () => {
    // Legacy path strips [\r\n]; cc strips control chars + Unicode line/paragraph
    // separators + adds ccPath: true. Helper must accept the override.
    const cc = buildAgentQueryOptions({
      ...minArgs,
      subagentStartPayloadOverride: {
        sanitizer: (v: unknown) =>
          String(v ?? "")
            .replace(/[\x00-\x1f\x7f\u2028\u2029]/g, " ")
            .slice(0, 200),
        extraLogFields: { ccPath: true },
        logMessage: "Subagent started (cc-soleur-go)",
      },
    });
    expect(cc.hooks?.SubagentStart).toBeDefined();
    // biome-ignore lint/style/noNonNullAssertion: shape verified above
    expect(Array.isArray(cc.hooks!.SubagentStart)).toBe(true);
  });
});

describe("buildAgentQueryOptions — in-sandbox git askpass threading (item 1c)", () => {
  it("threads gitAskpassScriptPath + ghToken into buildAgentEnv (token reused as gitInstallationToken)", () => {
    vi.mocked(buildAgentEnv).mockClear();
    buildAgentQueryOptions({
      ...minArgs,
      ghToken: "ghs_install_tok",
      gitAskpassScriptPath: "/tmp/test-workspace/.askpass-xyz.sh",
    });
    expect(buildAgentEnv).toHaveBeenCalledWith(
      minArgs.credential,
      minArgs.serviceTokens,
      {
        ghToken: "ghs_install_tok",
        gitAskpassScriptPath: "/tmp/test-workspace/.askpass-xyz.sh",
        // The askpass token IS the installation token (same value as ghToken).
        gitInstallationToken: "ghs_install_tok",
        // Slice B: deployed plugin root → CLAUDE_PLUGIN_ROOT for the agent's
        // bash shell-outs; threaded verbatim from args.pluginPath.
        pluginPath: PLUGIN,
      },
    );
  });

  // AC3 (dispatch integration pin). The CLAUDE_PLUGIN_ROOT that buildAgentEnv
  // exports must survive verbatim into the FINAL returned options.env — asserting
  // the returned object (not the buildAgentEnv call args) catches any downstream
  // drop/allowlist-filter after buildAgentEnv returns. Positive-only by design:
  // a negative case cannot isolate the buildAgentEnv guard because
  // assertTrustedPluginPath(args.pluginPath) at :197 throws first — the
  // guard-specific negatives live in agent-env.test.ts (AC2).
  it("AC3: threads CLAUDE_PLUGIN_ROOT through to the final options.env", () => {
    const opts = buildAgentQueryOptions({
      ...minArgs,
      pluginPath: "/app/shared/plugins/soleur",
    });
    expect(
      (opts.env as Record<string, string>).CLAUDE_PLUGIN_ROOT,
    ).toBe("/app/shared/plugins/soleur");
  });

  it("omits the askpass path when gitAskpassScriptPath is absent (legacy runner parity)", () => {
    vi.mocked(buildAgentEnv).mockClear();
    buildAgentQueryOptions(minArgs);
    expect(buildAgentEnv).toHaveBeenCalledWith(
      minArgs.credential,
      minArgs.serviceTokens,
      {
        ghToken: undefined,
        gitAskpassScriptPath: undefined,
        gitInstallationToken: undefined,
        // Slice B: pluginPath is ALWAYS threaded (both factories pass
        // getPluginPath()); only the git-askpass extras are per-call divergent.
        pluginPath: PLUGIN,
      },
    );
  });
});

// Expected signed-URL account fleet, generated locally (NOT imported from the
// source const) so a typo in the source list cannot self-verify: sa0..sa99
// minus sa22 (NXDOMAIN — see the docblock on GITHUB_ACTIONS_LOG_ACCOUNTS).
const EXPECTED_SA_ACCOUNTS = Array.from(
  { length: 100 },
  (_, i) => `productionresultssa${i}.blob.core.windows.net`,
).filter((h) => h !== "productionresultssa22.blob.core.windows.net");

describe("buildAgentQueryOptions — GitHub egress derived from ghToken (#5041 follow-up)", () => {
  it("truthy ghToken → sandbox allowlist carries the GitHub hosts + Actions blob/npm downloads", () => {
    const opts = buildAgentQueryOptions({
      ...minArgs,
      ghToken: "ghs_install_tok",
    });
    // Literal on purpose (canonical-literal style, do not import the
    // const) — an import would make a typo in the const self-verify.
    expect(opts.sandbox?.network?.allowedDomains).toEqual([
      "github.com",
      "api.github.com",
      "registry.npmjs.org",
      ...EXPECTED_SA_ACCOUNTS,
    ]);
  });

  it("absent ghToken → sandbox stays fully closed (legacy runner parity)", () => {
    const opts = buildAgentQueryOptions(minArgs);
    expect(opts.sandbox?.network?.allowedDomains).toEqual([]);
  });

  it("empty-string ghToken → fully closed (graceful-degradation parity with GH_TOKEN injection)", () => {
    const opts = buildAgentQueryOptions({ ...minArgs, ghToken: "" });
    expect(opts.sandbox?.network?.allowedDomains).toEqual([]);
  });
});

describe("buildAgentQueryOptions — SDK skills allowlist (support scope)", () => {
  it("omits `skills` by default (Command Center loads every skill)", () => {
    const opts = buildAgentQueryOptions(minArgs);
    expect("skills" in opts).toBe(false);
  });

  it("threads `skills` verbatim when provided (support passes ['kb-search'])", () => {
    const opts = buildAgentQueryOptions({ ...minArgs, skills: ["kb-search"] });
    expect(opts.skills).toEqual(["kb-search"]);
  });

  it("support extra-disallowed pins Edit/Write/Task/Agent alongside the canonical list, keeping Bash out of it", () => {
    const opts = buildAgentQueryOptions({
      ...minArgs,
      extraDisallowedTools: ["Edit", "Write", "MultiEdit", "NotebookEdit", "Task", "Agent"],
    });
    expect(opts.disallowedTools).toEqual([
      "WebSearch",
      "WebFetch",
      "Edit",
      "Write",
      "MultiEdit",
      "NotebookEdit",
      "Task",
      "Agent",
    ]);
    expect(opts.disallowedTools).not.toContain("Bash");
  });
});

describe("buildAgentQueryOptions — WorkspaceMode-driven cwd + sandbox write-set (ADR-113)", () => {
  it("command_center: cwd = workspace, sandbox allowWrite = [workspace]", () => {
    const opts = buildAgentQueryOptions({ ...minArgs, mode: resolveWorkspaceMode("command_center") });
    expect(opts.cwd).toBe(WORKSPACE);
    expect(opts.sandbox?.filesystem?.allowWrite).toEqual([WORKSPACE]);
  });

  it("support: cwd = plugin root, sandbox allowWrite = [] (T3 — the P1 read-only invariant)", () => {
    const opts = buildAgentQueryOptions({ ...minArgs, mode: resolveWorkspaceMode("support") });
    // cwd is the boot-validated plugin root, NOT the workspace.
    expect(opts.cwd).toBe(PLUGIN);
    // The write-set is EMPTY — a cwd=pluginPath session must not be able to write
    // into the shared platform plugin root (the CTO-flagged supply-chain escape).
    expect(opts.sandbox?.filesystem?.allowWrite).toEqual([]);
    expect(opts.sandbox?.filesystem?.allowWrite).not.toContain(PLUGIN);
  });

  it("support: sandbox denyRead obscures the internal knowledge base (containment defense)", () => {
    // PLUGIN = /tmp/test-workspace/plugins/soleur → internal KB is two levels up.
    const opts = buildAgentQueryOptions({ ...minArgs, mode: resolveWorkspaceMode("support") });
    expect(opts.sandbox?.filesystem?.denyRead).toContain("/tmp/test-workspace/knowledge-base");
  });

  it("command_center: does NOT add the internal-KB deny (no support containment)", () => {
    const opts = buildAgentQueryOptions({ ...minArgs, mode: resolveWorkspaceMode("command_center") });
    expect(opts.sandbox?.filesystem?.denyRead ?? []).not.toContain("/tmp/test-workspace/knowledge-base");
  });
});

describe("buildAgentQueryOptions — drift-guard snapshot (T4)", () => {
  // Stable JSON serialization across Node versions per plan Enhancement #2:
  // sort keys explicitly and exclude function-valued fields (canUseTool,
  // hooks, sandbox is object-only).
  function stableShape(opts: Record<string, unknown>): string {
    const SHARED_KEYS = [
      "cwd",
      "model",
      "permissionMode",
      "settingSources",
      "includePartialMessages",
      "disallowedTools",
    ] as const;
    const subset: Record<string, unknown> = {};
    for (const k of SHARED_KEYS) subset[k] = opts[k];
    return JSON.stringify(subset, Object.keys(subset).sort());
  }

  it("T4a: shared shape stable for legacy minimum args", () => {
    const opts = buildAgentQueryOptions(minArgs);
    expect(stableShape(opts as unknown as Record<string, unknown>)).toBe(
      JSON.stringify(
        {
          cwd: WORKSPACE,
          model: "claude-sonnet-5-5",
          permissionMode: "default",
          settingSources: [],
          includePartialMessages: true,
          disallowedTools: ["WebSearch", "WebFetch"],
        },
        [
          "cwd",
          "disallowedTools",
          "includePartialMessages",
          "model",
          "permissionMode",
          "settingSources",
        ],
      ),
    );
  });

  it("T4b: shared shape identical between legacy + cc args (drift-guard)", () => {
    const legacy = buildAgentQueryOptions({
      ...minArgs,
      maxTurns: 50,
      maxBudgetUsd: 5.0,
      allowedTools: ["mcp__soleur_platform__kb_share_create"],
    });
    const cc = buildAgentQueryOptions({
      ...minArgs,
      mcpServers: {},
      subagentStartPayloadOverride: {
        sanitizer: (v: unknown) => String(v ?? ""),
        extraLogFields: { ccPath: true },
        logMessage: "Subagent started (cc)",
      },
    });
    expect(stableShape(legacy as unknown as Record<string, unknown>)).toBe(
      stableShape(cc as unknown as Record<string, unknown>),
    );
  });
});

// --- outer-wrap interpose boot probe (#5863 T3.4) -----------------------------
// The rollout flag dark-launches the wrap; the probe asserts that a flag-on
// build actually installs `spawnClaudeCodeProcess` — a flag-on-but-unwired
// build would silently run the CLI unwrapped (file-tool tier exposed).
import { mkdtempSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  probeOuterWrapInterpose,
  verifyOuterWrapInterpose,
} from "@/server/agent-runner-query-options";

describe("probeOuterWrapInterpose — interpose wiring under the rollout flag", () => {
  it("flag off → ok, not installed (legal dark-launch posture)", () => {
    const p = probeOuterWrapInterpose({ AGENT_OUTER_WRAP: "0" });
    expect(p).toMatchObject({ flagOn: false, installed: false, ok: true });
  });

  it("flag on → real build installs spawnClaudeCodeProcess", () => {
    const ws = mkdtempSync(join(tmpdir(), "aow-probe-ws-"));
    const plugin = mkdtempSync(join(tmpdir(), "aow-probe-plugin-"));
    const p = probeOuterWrapInterpose(
      { AGENT_OUTER_WRAP: "1" },
      { pluginPath: plugin, makeWorkspace: () => ws },
    );
    expect(p).toMatchObject({ flagOn: true, installed: true, ok: true });
  });

  it("flag on + cohort allowlist → probes with an allowlisted workspace id", () => {
    const ws = mkdtempSync(join(tmpdir(), "aow-probe-ws-"));
    const plugin = mkdtempSync(join(tmpdir(), "aow-probe-plugin-"));
    const p = probeOuterWrapInterpose(
      { AGENT_OUTER_WRAP: "1", AGENT_OUTER_WRAP_WORKSPACES: "ws-cohort-1" },
      { pluginPath: plugin, makeWorkspace: () => ws },
    );
    expect(p).toMatchObject({ flagOn: true, installed: true, ok: true });
  });

  it("flag on + interpose missing from build output → not ok", () => {
    const p = probeOuterWrapInterpose(
      { AGENT_OUTER_WRAP: "1" },
      { buildOptions: (() => ({})) as never },
    );
    expect(p).toMatchObject({ flagOn: true, installed: false, ok: false });
  });

  it("flag on + build throw → not ok with the error carried", () => {
    const p = probeOuterWrapInterpose(
      { AGENT_OUTER_WRAP: "1" },
      {
        buildOptions: (() => {
          throw new Error("argv build boom");
        }) as never,
      },
    );
    expect(p).toMatchObject({ flagOn: true, installed: false, ok: false });
    expect(p.error).toContain("argv build boom");
  });
});

describe("verifyOuterWrapInterpose — emit fork", () => {
  it("flag-on + installed → info emit (log + Sentry info), no warn", async () => {
    vi.stubEnv("AGENT_OUTER_WRAP", "1");
    vi.stubEnv("SOLEUR_PLUGIN_PATH", mkdtempSync(join(tmpdir(), "aow-probe-plugin-")));
    const { verifyOuterWrapInterpose: run } = await import(
      "@/server/agent-runner-query-options"
    );
    run();
    expect(obs.warnSilentFallback).not.toHaveBeenCalled();
    vi.unstubAllEnvs();
  });

  it("flag-on + unwired → warnSilentFallback with the feature/op tags", async () => {
    vi.stubEnv("AGENT_OUTER_WRAP", "1");
    vi.stubEnv("SOLEUR_PLUGIN_PATH", "/nonexistent-plugin-root");
    const { verifyOuterWrapInterpose: run } = await import(
      "@/server/agent-runner-query-options"
    );
    run();
    expect(obs.warnSilentFallback).toHaveBeenCalledTimes(1);
    expect(obs.warnSilentFallback.mock.calls[0][1]).toMatchObject({
      feature: "agent-sandbox",
      op: "outer-wrap-selfprobe",
    });
    vi.unstubAllEnvs();
  });
});
