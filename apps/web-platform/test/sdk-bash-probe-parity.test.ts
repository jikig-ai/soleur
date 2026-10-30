// #10453 — the deploy-time SDK Bash smoke's probe (infra/lib/sdk-bash-probe.mjs) runs inside the production image, which
// has no TypeScript sources, so it carries a LITERAL sandbox config and a literal seccomp-selector path. This suite pins
// both to what the production builders emit, and unit-tests the probe's own verdict function.
//
// Guard 4 of the plan (knowledge-base/project/plans/archive/20261019-203025-2026-10-19-fix-sandbox-incident-followups-plan.md):
//   (a) smokeSandboxConfig() deep-equals buildAgentSandboxConfig() for the no-egress shape; a failure prints the diff and
//       the exact line to change in the probe, so the test is a prompt rather than a puzzle;
//   (b) the BASE selector path stays pinned to today's value (the shim default), and the smoke tuple runs with the
//       unixdeny selector, equal to what buildAgentEnv emits for a no-egress session with the runtime flag ON (so a variant
//       that breaks Bash start is reported on the deploy that carries it, BEFORE the flag is ever turned on);
//   (c) the verdict table classifies every known outcome, including "Bash dispatched but no nonce" and "dispatched and hung".
//
// The egress shape is exercised pre-merge by the real-SDK egress arm (sandbox-wrapped-command-runtime.test.ts), not by the
// deploy smoke (recorded as out of scope in the plan).

import { spawnSync } from "node:child_process";
import { mkdirSync, mkdtempSync, readFileSync, realpathSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { afterAll, beforeAll, describe, expect, it, vi } from "vitest";

import { buildAgentEnv } from "@/server/agent-env";
import {
  buildAgentSandboxConfig,
  peerMessagingSocketDirs,
  probeAgentSandboxHardening,
  sessionTranscriptDirs,
} from "@/server/agent-runner-sandbox-config";
import { AGENT_SESSION_TMP_ROOT } from "@/server/agent-session-tmp";
import * as probe from "../infra/lib/sdk-bash-probe.mjs";

const APP_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const PROBE_REL = "apps/web-platform/infra/lib/sdk-bash-probe.mjs";
const read = (...p: string[]): string => readFileSync(join(APP_ROOT, ...p), "utf8");

// ---- (a) config parity --------------------------------------------------------------------------------------------

/** Every leaf path at which two JSON-ish values differ (arrays compare by index: deny-list order is the builder's). */
function diffPaths(a: unknown, b: unknown, path = "$"): string[] {
  if (Array.isArray(a) || Array.isArray(b)) {
    if (!Array.isArray(a) || !Array.isArray(b)) return [`${path}: probe=${JSON.stringify(a)} builder=${JSON.stringify(b)}`];
    const out: string[] = [];
    for (let i = 0; i < Math.max(a.length, b.length); i++) out.push(...diffPaths(a[i], b[i], `${path}[${i}]`));
    return out;
  }
  if (a && b && typeof a === "object" && typeof b === "object") {
    const keys = new Set([...Object.keys(a as object), ...Object.keys(b as object)]);
    return [...keys].flatMap((k) => diffPaths((a as Record<string, unknown>)[k], (b as Record<string, unknown>)[k], `${path}.${k}`));
  }
  return Object.is(a, b) ? [] : [`${path}: probe=${JSON.stringify(a)} builder=${JSON.stringify(b)}`];
}

function parityMessage(diffs: string[]): string {
  return (
    `${PROBE_REL} smokeSandboxConfig() has drifted from buildAgentSandboxConfig() (server/agent-runner-sandbox-config.ts):\n  ` +
    `${diffs.join("\n  ")}\nFIX: edit the literal returned by smokeSandboxConfig() in ${PROBE_REL} so each path above equals the ` +
    "builder value, keeping the builder's order for arrays. The probe is plain ESM baked into the image; it cannot import the builder."
  );
}

describe("the smoke probe's literal sandbox config tracks buildAgentSandboxConfig (no-egress shape)", () => {
  let home: string;
  let workspace: string;
  const savedEnvNames = ["HOME", "WORKSPACES_ROOT", "WORKTREE_ROOT", "C4_RENDER_STAGING_ROOT", "EGRESS_TOKEN_DIR", "XDG_RUNTIME_DIR", "CLAUDE_CODE_TMPDIR", "TMPDIR", "CLAUDE_CONFIG_DIR", "GOOGLE_APPLICATION_CREDENTIALS"];

  beforeAll(() => {
    home = realpathSync(mkdtempSync(join(tmpdir(), "sdk-probe-parity-home-")));
    workspace = join(home, "scratch-workspace");
    mkdirSync(workspace, { recursive: true });
    // The container env the probe models: a real HOME and none of the overrides the builder consults.
    for (const n of savedEnvNames) vi.stubEnv(n, undefined as unknown as string);
    vi.stubEnv("HOME", home);
  });
  afterAll(() => {
    vi.unstubAllEnvs();
    rmSync(home, { recursive: true, force: true });
  });

  const probeConfig = () => probe.smokeSandboxConfig({ workspace, uid: process.getuid!(), home });

  it("deep-equals the builder output, printing the diff and the exact fix on drift", () => {
    const builder = buildAgentSandboxConfig(workspace);
    const diffs = diffPaths(probeConfig(), builder);
    expect(diffs, parityMessage(diffs)).toEqual([]);
  });

  it("the masked dirs equal the production derivations for this container env (uid and HOME)", () => {
    const uid = process.getuid!();
    expect(probe.maskedDirs(uid, home)).toEqual(["/tmp/cc-socks", `/tmp/cc-socks-${uid}`, `${home}/.claude/projects`]);
    const builder = buildAgentSandboxConfig(workspace) as { filesystem: { denyRead: string[] } };
    expect(builder.filesystem.denyRead).toEqual(expect.arrayContaining(probe.maskedDirs(uid, home)));
  });

  // Guard 2 (#10455 PR-B): the set the runtime probe CREATES equals, as a SET, the set the production builder pre-creates under the
  // default container env. Built from the builder's own helpers, called directly (no exported chokepoint); equality, not arrayContaining.
  const sameSet = (a: string[], b: string[]): boolean => a.length === new Set(a).size && b.length === new Set(b).size && a.length === b.length && a.every((x) => b.includes(x));
  const builderPrecreateSet = (uid: number, h: string): string[] => {
    // the controlled env: HOME fixed, every override unset
    const env = { HOME: h } as Record<string, string | undefined>;
    return [...new Set([...peerMessagingSocketDirs(env, uid), ...sessionTranscriptDirs(env), AGENT_SESSION_TMP_ROOT])];
  };

  it("Guard 2: precreateDirs(uid, home) equals the builder's pre-create set (exactly 4 members), for two different uids and HOMEs", () => {
    for (const [uid, h] of [[process.getuid!(), home], [4242, "/home/other"]] as const) {
      const builderSet = builderPrecreateSet(uid, h);
      expect(builderSet, "floor: the controlled-env derivation must yield exactly the 4 default dirs").toHaveLength(4);
      const probeSet = probe.precreateDirs(uid, h);
      expect([...probeSet].sort(), `probe=${JSON.stringify(probeSet)} builder=${JSON.stringify(builderSet)}`).toEqual([...builderSet].sort());
      expect(sameSet(probeSet, builderSet)).toBe(true);
    }
  });

  it("Guard 2: SESSION_TMP_ROOT is pinned to AGENT_SESSION_TMP_ROOT, and the builder's denyRead carries every member of the probe's create set", () => {
    expect(probe.SESSION_TMP_ROOT).toBe(AGENT_SESSION_TMP_ROOT);
    const uid = process.getuid!();
    const builder = buildAgentSandboxConfig(workspace) as { filesystem: { denyRead: string[] } };
    expect(builder.filesystem.denyRead).toEqual(expect.arrayContaining(probe.precreateDirs(uid, home)));
  });

  it("HARNESS control (Guard 2 row 7): the set comparison rejects a superset, a subset and a duplicate, so it is not arrayContaining", () => {
    const uid = process.getuid!();
    const builderSet = builderPrecreateSet(uid, home);
    expect(sameSet([...probe.precreateDirs(uid, home), "/tmp/extra"], builderSet)).toBe(false);
    expect(sameSet(probe.precreateDirs(uid, home).slice(1), builderSet)).toBe(false);
    expect(sameSet([...probe.precreateDirs(uid, home).slice(1), "/tmp/cc-socks"], [...builderSet.slice(1), builderSet[1]])).toBe(false);
    expect(sameSet(probe.precreateDirs(uid, home), builderSet)).toBe(true);
    // and the floor row's input: an empty derivation is not "equal to an empty probe set"
    expect(builderSet.length).toBeGreaterThan(0);
  });

  it("HARNESS must-PASS: a config differing from the canonical only by key order is still equal", () => {
    const canonical = probeConfig() as Record<string, unknown>;
    const reordered = Object.fromEntries(Object.entries(canonical).reverse());
    expect(diffPaths(reordered, buildAgentSandboxConfig(workspace))).toEqual([]);
  });

  it("HARNESS control: the diff helper does detect a drifted entry (the parity row above is not vacuous)", () => {
    const drifted = probeConfig() as { network: Record<string, unknown> };
    delete drifted.network.allowAllUnixSockets;
    expect(diffPaths(drifted, buildAgentSandboxConfig(workspace))).toEqual(["$.network.allowAllUnixSockets: probe=undefined builder=true"]);
  });
});

// ---- (b) selector pin ---------------------------------------------------------------------------------------------

describe("the smoke probe's seccomp selector path equals what the production env selects today", () => {
  it("is the base artifact: the shim default, the hardening self-probe default, the Dockerfile COPY", () => {
    const selected = probe.SMOKE_SELECTOR_PATHS.base;
    expect(selected).toBe("/app/infra/bwrap-userns-clone3-deny.bpf"); // today's value, never edited by the variant work
    const shim = read("infra", "bwrap-shim", "bwrap");
    expect(shim).toContain(`BPF=\${SOLEUR_BWRAP_SECCOMP_BPF:-${selected}}`);
    // The server-side default (what probeAgentSandboxHardening certifies when nothing overrides the selector).
    vi.stubEnv("SOLEUR_BWRAP_SECCOMP_BPF", undefined as unknown as string);
    try {
      expect(probeAgentSandboxHardening({}).bpfPath).toBe(selected);
      // buildAgentEnv passes no override today: an absent ambient value stays absent, so the shim default (the base
      // artifact) is what every production session runs under.
      const env = buildAgentEnv({ value: "decoy", scheme: "api_key" }, undefined, { pluginPath: "/app/shared/plugins/soleur" });
      expect(env.SOLEUR_BWRAP_SECCOMP_BPF).toBeUndefined();
    } finally {
      vi.unstubAllEnvs();
    }
    const dockerfile = read("Dockerfile");
    expect(dockerfile).toContain(`COPY --from=builder /app/infra/bwrap-userns-clone3-deny.bpf .${selected.replace("/app", "")}`);
  });

  it("the smoke tuple runs with the unixdeny selector: equal to buildAgentEnv for a no-egress session with the flag ON, baked in the image, certified by the self-probe", () => {
    const selected = probe.smokeSelectorPath();
    expect(selected).toBe(probe.SMOKE_SELECTOR_PATHS.unixdeny);
    expect(selected).toBe("/app/infra/bwrap-userns-clone3-unixdeny.bpf");
    vi.stubEnv("SOLEUR_BWRAP_SECCOMP_BPF", undefined as unknown as string);
    vi.stubEnv("SOLEUR_BWRAP_SECCOMP_BPF_UNIXDENY", undefined as unknown as string);
    try {
      const env = buildAgentEnv({ value: "decoy", scheme: "api_key" }, undefined, {
        pluginPath: "/app/shared/plugins/soleur",
        sandboxUnixDeny: true,
      });
      expect(env.SOLEUR_BWRAP_SECCOMP_BPF).toBe(selected);
      // an EGRESS session with the flag ON does not get it
      const egress = buildAgentEnv({ value: "decoy", scheme: "api_key" }, undefined, {
        pluginPath: "/app/shared/plugins/soleur",
        ghToken: "ghs_decoy",
        sandboxUnixDeny: true,
      });
      expect(egress.SOLEUR_BWRAP_SECCOMP_BPF).toBeUndefined();
      expect(probeAgentSandboxHardening({}).unixdenyPath).toBe(selected);
    } finally {
      vi.unstubAllEnvs();
    }
    expect(read("Dockerfile")).toContain(
      `COPY --from=builder /app/infra/bwrap-userns-clone3-unixdeny.bpf .${selected.replace("/app", "")}`,
    );
    expect(read(".dockerignore")).toMatch(/^!infra\/bwrap-userns-clone3-unixdeny\.bpf$/m);
    expect(read("infra", "lib", "sdk-bash-probe.mjs")).toContain("smokeSelectorPath");
  });

  it("an ambient override reaches the SDK child through buildAgentEnv unchanged (the incident-time override the smoke must not mask)", () => {
    vi.stubEnv("SOLEUR_BWRAP_SECCOMP_BPF", "/tmp/override.bpf");
    try {
      const env = buildAgentEnv({ value: "decoy", scheme: "api_key" }, undefined, { pluginPath: "/app/shared/plugins/soleur" });
      expect(env.SOLEUR_BWRAP_SECCOMP_BPF).toBe("/tmp/override.bpf");
    } finally {
      vi.unstubAllEnvs();
    }
  });
});

// ---- image bake + deploy wiring parity ----------------------------------------------------------------------------

describe("the probe is baked into the image and ci-deploy.sh execs the baked path", () => {
  const dockerfile = read("Dockerfile");
  const dockerignore = read(".dockerignore");
  const deploy = read("infra", "ci-deploy.sh");

  it("Dockerfile COPY, .dockerignore bang and the ci-deploy.sh default agree on /app/infra/lib/sdk-bash-probe.mjs", () => {
    expect(dockerfile).toMatch(/^COPY --from=builder \/app\/infra\/lib\/sdk-bash-probe\.mjs \.\/infra\/lib\/sdk-bash-probe\.mjs$/m);
    expect(dockerignore).toMatch(/^!infra\/lib\/sdk-bash-probe\.mjs$/m);
    expect(deploy).toContain('SDK_BASH_SMOKE_PROBE="${SDK_BASH_SMOKE_PROBE:-/app/infra/lib/sdk-bash-probe.mjs}"');
  });

  it("the dispatched marker: the probe prints it beside state.dispatched (smoke mode only) and the host's 124 arm reads the same literal", () => {
    const src = read("infra", "lib", "sdk-bash-probe.mjs");
    const MARKER = "SDK_BASH_DISPATCHED";
    // printed right after the assignment, gated on the smoke-only `announce` flag so the docker suite's default mode stays one-line
    expect(src).toMatch(/state\.dispatched = true;\n\s*if \(state\.announce\) console\.log\("SDK_BASH_DISPATCHED"\);/);
    expect(src).toMatch(/const state = \{ dispatched: false, announce: true \};/);
    // the 124 arm reads the identical literal, and the result parse ignores it (it is anchored on `SDK_BASH_RESULT `). The rc/marker
    // mapping moved out of run_sdk_bash_smoke into the sourced lib shared with the runtime synthetic (ADR-079 "Addendum — 2026-10-22 (#10455 b)"),
    // so the contract is the function plus the lib it calls.
    const smokeFn = deploy.slice(deploy.indexOf("run_sdk_bash_smoke() {")) + read("infra", "sdk-bash-verdict.sh");
    expect(deploy).toContain("sdk_bash_map_result");
    expect(smokeFn).toContain(`SDK_BASH_DISPATCHED`);
    expect(smokeFn).toContain("grep -a '^SDK_BASH_RESULT '");
    expect(smokeFn).toContain("host_timeout_before_dispatch");
    expect(MARKER).not.toMatch(/^SDK_BASH_RESULT /);
  });

  it("the bang is an exact path (no directory bang that would re-include siblings)", () => {
    expect(dockerignore).not.toMatch(/^!infra\/lib\/?$/m);
    expect(dockerignore).not.toMatch(/^!infra\/lib\/\*/m);
  });
});

// ---- (c) verdict table --------------------------------------------------------------------------------------------

const NONCE = "0123456789abcdef0123456789abcdef";
const OTHER_NONCE = "fedcba9876543210fedcba9876543210";
// What `tr 0-9a-f a-f0-9` makes of NONCE, written out by hand (independent of the probe's transformNonce): 0->a ... 5->f, 6->0 ... 9->3, a->4 ... f->9.
const EXECUTED = "abcdef0123456789abcdef0123456789";
const HELPER_EPERM = "apply-seccomp: unshare(CLONE_NEWUSER): Operation not permitted";
const FULL = probe.SMOKE_COVERAGE_FULL;

interface Row {
  name: string;
  obs: Record<string, unknown>;
  verdict: string;
  reason: RegExp;
  coverage?: string;
}

const ROWS: Row[] = [
  { name: "pass: dispatched, real tool_result carries the nonce, full coverage", obs: { nonce: NONCE, dispatched: true, toolResult: { isError: false, content: `SDK_SMOKE_${EXECUTED}\n` }, coverage: FULL }, verdict: "pass", reason: /^ok$/, coverage: FULL },
  { name: "failed: the #10445 helper EPERM line in an error result", obs: { nonce: NONCE, dispatched: true, toolResult: { isError: true, content: HELPER_EPERM }, coverage: FULL }, verdict: "sdk_bash_smoke_failed", reason: /apply-seccomp: unshare\(CLONE_NEWUSER\)/ },
  { name: "failed: dispatched, clean (non-error) result WITHOUT the nonce (Bash ran nothing we can verify)", obs: { nonce: NONCE, dispatched: true, toolResult: { isError: false, content: "" }, coverage: FULL }, verdict: "sdk_bash_smoke_failed", reason: /^no_nonce/ },
  { name: "failed: dispatched, unknown error wording without any sandbox signature (signature-independent)", obs: { nonce: NONCE, dispatched: true, toolResult: { isError: true, content: "the widget exploded" }, coverage: FULL }, verdict: "sdk_bash_smoke_failed", reason: /widget exploded/ },
  { name: "failed: dispatched and hung past the internal cap", obs: { nonce: NONCE, dispatched: true, timedOut: true, coverage: FULL }, verdict: "sdk_bash_smoke_failed", reason: /^hung_after_dispatch$/ },
  { name: "failed: dispatched, the SDK threw a non-sandbox error", obs: { nonce: NONCE, dispatched: true, thrown: "Error: stream closed", coverage: FULL }, verdict: "sdk_bash_smoke_failed", reason: /^dispatched_then_error/ },
  { name: "infra: dispatched, the SDK's child died to the OOM killer (exited with code 137): a host memory event, never a /fail page", obs: { nonce: NONCE, dispatched: true, thrown: "Error: Claude Code process exited with code 137", coverage: FULL }, verdict: "smoke_infra_error", reason: /^cli_child_killed/ },
  { name: "infra: dispatched, the SDK's child got SIGTERM (a container stop or a deploy signal)", obs: { nonce: NONCE, dispatched: true, thrown: "Error: Claude Code process terminated by signal SIGTERM", coverage: FULL }, verdict: "smoke_infra_error", reason: /^cli_child_killed/ },
  { name: "infra: the SDK's child was killed before Bash was dispatched too (code 143)", obs: { nonce: NONCE, dispatched: false, thrown: "Error: Claude Code process exited with code 143", coverage: FULL }, verdict: "smoke_infra_error", reason: /^cli_child_killed/ },
  { name: "failed: dispatched, the SDK's child exited with code 1 (an ordinary failure, not a kill) stays a failure", obs: { nonce: NONCE, dispatched: true, thrown: "Error: Claude Code process exited with code 1", coverage: FULL }, verdict: "sdk_bash_smoke_failed", reason: /^dispatched_then_error/ },
  { name: "failed: dispatched, no tool_result at all", obs: { nonce: NONCE, dispatched: true, coverage: FULL }, verdict: "sdk_bash_smoke_failed", reason: /^dispatched_no_tool_result$/ },
  { name: "failed: the SDK threw 'sandbox required but unavailable' before Bash was dispatched (a sandbox that cannot start is the incident)", obs: { nonce: NONCE, dispatched: false, thrown: "Error: sandbox required but unavailable", coverage: FULL }, verdict: "sdk_bash_smoke_failed", reason: /sandbox required but unavailable/ },
  { name: "failed: nonce present but the result is error-flagged (a failing command cannot certify)", obs: { nonce: NONCE, dispatched: true, toolResult: { isError: true, content: `SDK_SMOKE_${EXECUTED}\nboom` }, coverage: FULL }, verdict: "sdk_bash_smoke_failed", reason: /./ },
  { name: "A8: failed: a clean result that only QUOTES the command text (the printf pipeline with the raw nonce) does not pass", obs: { nonce: NONCE, dispatched: true, toolResult: { isError: false, content: `$ echo SDK_SMOKE_$(printf %s '${NONCE}' | tr 0-9a-f a-f0-9)\nSDK_SMOKE_${NONCE}` }, coverage: FULL }, verdict: "sdk_bash_smoke_failed", reason: /^no_nonce/ },
  { name: "A8: failed: another run's executed output (a different nonce) does not pass", obs: { nonce: NONCE, dispatched: true, toolResult: { isError: false, content: `SDK_SMOKE_${probe.transformNonce(OTHER_NONCE)}\n` }, coverage: FULL }, verdict: "sdk_bash_smoke_failed", reason: /^no_nonce/ },
  { name: "A8: failed: the pre-transform spelling (SDK_SMOKE_<raw nonce>) is no longer a pass", obs: { nonce: NONCE, dispatched: true, toolResult: { isError: false, content: `SDK_SMOKE_${NONCE}\n` }, coverage: FULL }, verdict: "sdk_bash_smoke_failed", reason: /^no_nonce/ },
  { name: "infra: Bash never dispatched, non-signature SDK error before dispatch", obs: { nonce: NONCE, dispatched: false, thrown: "Error: spawn ENOENT", coverage: FULL }, verdict: "smoke_infra_error", reason: /^sdk_error_before_dispatch/ },
  { name: "infra: Bash never dispatched, nothing happened", obs: { nonce: NONCE, dispatched: false, coverage: FULL }, verdict: "smoke_infra_error", reason: /^bash_not_dispatched$/ },
  { name: "infra: hung before Bash was dispatched", obs: { nonce: NONCE, dispatched: false, timedOut: true, coverage: FULL }, verdict: "smoke_infra_error", reason: /^hung_before_dispatch$/ },
  { name: "infra: the probe's own precondition failed (SDK module missing)", obs: { nonce: NONCE, infraError: "sdk_module_unavailable: Cannot find package" }, verdict: "smoke_infra_error", reason: /^sdk_module_unavailable/ },
  { name: "HOLD: a pass-shaped result with replay_only coverage is smoke_infra_error (never moves the soak counter)", obs: { nonce: NONCE, dispatched: true, toolResult: { isError: false, content: `SDK_SMOKE_${EXECUTED}` }, coverage: probe.SMOKE_COVERAGE_REPLAY_ONLY }, verdict: "smoke_infra_error", reason: /^coverage_replay_only$/, coverage: probe.SMOKE_COVERAGE_REPLAY_ONLY },
  { name: "unknown coverage string is treated as replay_only", obs: { nonce: NONCE, dispatched: true, toolResult: { isError: false, content: `SDK_SMOKE_${EXECUTED}` }, coverage: "whatever" }, verdict: "smoke_infra_error", reason: /^coverage_replay_only$/, coverage: probe.SMOKE_COVERAGE_REPLAY_ONLY },
];

describe("smokeVerdict classifies every known outcome", () => {
  // Anti-vacuity floor: the table must not be emptied (a verdict suite that runs zero rows passes).
  it("runs at least the floor of rows", () => {
    expect(ROWS.length).toBeGreaterThanOrEqual(22);
  });

  for (const row of ROWS) {
    it(row.name, () => {
      const v = probe.smokeVerdict(row.obs);
      expect(v.verdict).toBe(row.verdict);
      expect(v.reason).toMatch(row.reason);
      if (row.coverage) expect(v.coverage).toBe(row.coverage);
    });
  }

  it("the reason is print-safe and length-capped (it rides journald and Sentry)", () => {
    const v = probe.smokeVerdict({ nonce: NONCE, dispatched: true, toolResult: { isError: true, content: `bad\u0000line\u001b[31m${"x".repeat(500)}` }, coverage: FULL });
    expect(v.reason).toMatch(/^[\x20-\x7e]*$/);
    expect(v.reason.length).toBeLessThanOrEqual(170);
  });

  it("never echoes anything that looks like the decoy credential into the reason of a pass", () => {
    const v = probe.smokeVerdict({ nonce: NONCE, dispatched: true, toolResult: { isError: false, content: `SDK_SMOKE_${EXECUTED}` }, coverage: FULL });
    expect(JSON.stringify(v)).not.toContain(probe.SMOKE_DECOY_API_KEY);
  });
});

describe("A8: the smoke command's output differs from its text", () => {
  it("transformNonce matches the hand-written expectation and changes every digit", () => {
    expect(probe.transformNonce(NONCE)).toBe(EXECUTED);
    expect(probe.smokeExpectedOutput(NONCE)).toBe(`SDK_SMOKE_${EXECUTED}`);
    for (let i = 0; i < NONCE.length; i++) expect(EXECUTED[i]).not.toBe(NONCE[i]);
  });

  it("the command text never contains the output it is verified against", () => {
    const cmd = probe.smokeCommand(NONCE);
    expect(cmd).toContain(NONCE); // the raw nonce is the printf argument...
    expect(cmd).not.toContain(probe.smokeExpectedOutput(NONCE)); // ...and the transformed value only exists after execution
    expect(cmd).not.toContain(`SDK_SMOKE_${NONCE}`);
  });

  it("really executing the command in a shell prints exactly the expected output", () => {
    const r = spawnSync("sh", ["-c", probe.smokeCommand(NONCE)], { encoding: "utf8" });
    expect(r.status).toBe(0);
    expect(r.stdout).toBe(`${probe.smokeExpectedOutput(NONCE)}\n`);
    // and the verdict accepts that very output
    const v = probe.smokeVerdict({ nonce: NONCE, dispatched: true, toolResult: { isError: false, content: r.stdout }, coverage: FULL });
    expect(v.verdict).toBe("pass");
  });
});

describe("coverage is the shim-and-wrapper tuple only under the pinned artifact", () => {
  it("full only with the shim on PATH, a sock_filter-sized artifact and the pinned (unixdeny) path; the base path alone is not the smoke tuple", () => {
    const pinned = probe.smokeSelectorPath();
    expect(probe.smokeCoverage({ shim: true, filter: true, bpfPath: probe.SMOKE_SELECTOR_PATHS.base })).toBe(
      probe.SMOKE_COVERAGE_REPLAY_ONLY,
    );
    expect(probe.smokeCoverage({ shim: true, filter: true, bpfPath: pinned })).toBe(probe.SMOKE_COVERAGE_FULL);
    expect(probe.smokeCoverage({ shim: false, filter: true, bpfPath: pinned })).toBe(probe.SMOKE_COVERAGE_REPLAY_ONLY);
    expect(probe.smokeCoverage({ shim: true, filter: false, bpfPath: pinned })).toBe(probe.SMOKE_COVERAGE_REPLAY_ONLY);
    expect(probe.smokeCoverage({ shim: true, filter: true, bpfPath: "/tmp/other.bpf" })).toBe(probe.SMOKE_COVERAGE_REPLAY_ONLY);
  });

  it("measureShimAndFilter recognises the repo's real shim by its content marker", () => {
    const m = probe.measureShimAndFilter(join(APP_ROOT, "infra", "bwrap-shim"), join(APP_ROOT, "infra", "bwrap-userns-clone3-deny.bpf"));
    expect(m).toEqual({ shim: true, filter: true });
    expect(probe.measureShimAndFilter("/nonexistent", "/nonexistent/x.bpf")).toEqual({ shim: false, filter: false });
  });
});
