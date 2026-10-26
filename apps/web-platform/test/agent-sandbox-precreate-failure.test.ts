// #10445: a masked dir that cannot be pre-created leaves its read-deny OFF (the SDK skips a deny landing that does not
// exist), so the failure must reach reportSilentFallback with op `masked-dir-precreate`, and the dir must STILL be in
// denyRead (the mask fails open per dir, never by dropping the entry).
// #10455 (PR-B): the emit is routed by the Sentry rule `masked-dir-precreate-failed` (feature=agent-sandbox AND
// op=masked-dir-precreate), so each of the three kinds must carry `tags.dir_kind`, `extra.{dir,code,syscall}`, and be
// emitted on the MESSAGE path (first argument the literal `null`, never the Error): an Error would be mirrored by the
// pino logger as feature=pino-mirror and the tagged capture deduplicated behind it. The real-path proof is
// agent-sandbox-precreate-sentry-path.test.ts; this file keeps the mock of reportSilentFallback.
import { mkdtempSync, rmSync, statSync, writeFileSync } from "fs";
import { tmpdir } from "os";
import { join } from "path";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";

type Reported = {
  first: unknown;
  feature?: string;
  op?: string;
  message?: string;
  tags?: Record<string, string>;
  extra?: { dir?: string; code?: string; syscall?: string };
};
const reported = vi.hoisted(() => [] as Array<Reported>);
vi.mock("@/server/observability", async (orig) => {
  const real = await orig<typeof import("@/server/observability")>();
  return {
    ...real,
    reportSilentFallback: (first: unknown, o: Omit<Reported, "first">) => {
      reported.push({ first, ...o });
    },
  };
});

// Passthrough `mkdirSync` that records every call and can be told to fail for specific paths (the session-tmp root
// is a constant `/tmp/.cs`, so it cannot be forced to fail through the environment).
const mkdirCalls = vi.hoisted(() => [] as Array<{ dir: string; opts: unknown }>);
const failMkdir = vi.hoisted(() => new Map<string, string>());
vi.mock("fs", async (orig) => {
  const real = await orig<typeof import("fs")>();
  return {
    ...real,
    mkdirSync: ((dir: string, opts: unknown) => {
      mkdirCalls.push({ dir: String(dir), opts });
      const code = failMkdir.get(String(dir));
      if (code) throw Object.assign(new Error(`${code}: mkdir '${dir}'`), { code, syscall: "mkdir" });
      return (real.mkdirSync as (d: string, o: unknown) => unknown)(dir, opts);
    }) as typeof real.mkdirSync,
  };
});

import { AGENT_SESSION_TMP_ROOT } from "@/server/agent-session-tmp";
import { c4RenderStagingRoot } from "@/server/c4-staging-root";
import {
  buildAgentSandboxConfig,
  peerMessagingSocketDirs,
  sessionTranscriptDirs,
} from "@/server/agent-runner-sandbox-config";

const OPS = (op: string) => reported.filter((o) => o.op === op);

describe("masked-dir pre-create failure (#10445, #10455)", () => {
  let root: string;
  beforeEach(() => {
    root = mkdtempSync(join(tmpdir(), "sbx-precreate-"));
    reported.length = 0;
    mkdirCalls.length = 0;
    failMkdir.clear();
  });
  afterEach(() => {
    vi.unstubAllEnvs();
    rmSync(root, { recursive: true, force: true });
  });

  const ws = () => join(root, "00000000-0000-0000-0000-000000000001");

  it("peer-socket: reports masked-dir-precreate with dir_kind, code and the null first argument; keeps the dir in denyRead", () => {
    // A regular FILE as the TMPDIR base makes `<base>/cc-socks` fail with ENOTDIR.
    const notADir = join(root, "file");
    writeFileSync(notADir, "");
    vi.stubEnv("TMPDIR", notADir);
    vi.stubEnv("WORKSPACES_ROOT", root);
    const cfg = buildAgentSandboxConfig(ws());
    const bad = join(notADir, "cc-socks");
    expect(peerMessagingSocketDirs()).toContain(bad);
    const hit = OPS("masked-dir-precreate").filter((o) => o.extra?.dir === bad);
    expect(hit).toHaveLength(1);
    expect(hit[0].first).toBeNull();
    expect(hit[0].feature).toBe("agent-sandbox");
    expect(hit[0].tags).toEqual({ dir_kind: "peer-socket" });
    expect(hit[0].extra?.code).toBe("ENOTDIR");
    expect(hit[0].extra?.syscall).toBe("mkdir");
    expect(cfg.filesystem.denyRead).toContain(bad);
  });

  it("transcript: a HOME that is a file fails <HOME>/.claude/projects with dir_kind=transcript", () => {
    const notADir = join(root, "homefile");
    writeFileSync(notADir, "");
    vi.stubEnv("HOME", notADir);
    vi.stubEnv("CLAUDE_CONFIG_DIR", "");
    vi.stubEnv("WORKSPACES_ROOT", root);
    const cfg = buildAgentSandboxConfig(ws());
    const bad = join(notADir, ".claude", "projects");
    expect(sessionTranscriptDirs()).toContain(bad);
    const hit = OPS("masked-dir-precreate").filter((o) => o.extra?.dir === bad);
    expect(hit).toHaveLength(1);
    expect(hit[0].first).toBeNull();
    expect(hit[0].feature).toBe("agent-sandbox");
    expect(hit[0].tags).toEqual({ dir_kind: "transcript" });
    expect(["ENOTDIR", "EEXIST"]).toContain(hit[0].extra?.code);
    expect(cfg.filesystem.denyRead).toContain(bad);
  });

  it("session-tmp: a failing /tmp/.cs reports dir_kind=session-tmp with the errno code and keeps the root in denyRead", () => {
    failMkdir.set(AGENT_SESSION_TMP_ROOT, "ENOSPC");
    vi.stubEnv("WORKSPACES_ROOT", root);
    const cfg = buildAgentSandboxConfig(ws());
    const hit = OPS("masked-dir-precreate").filter((o) => o.extra?.dir === AGENT_SESSION_TMP_ROOT);
    expect(hit).toHaveLength(1);
    expect(hit[0].first).toBeNull();
    expect(hit[0].feature).toBe("agent-sandbox");
    expect(hit[0].tags).toEqual({ dir_kind: "session-tmp" });
    expect(hit[0].extra).toEqual({ dir: AGENT_SESSION_TMP_ROOT, code: "ENOSPC", syscall: "mkdir" });
    expect(cfg.filesystem.denyRead).toContain(AGENT_SESSION_TMP_ROOT);
  });

  it("the message is constant per kind, names the kind and never the path", () => {
    failMkdir.set(AGENT_SESSION_TMP_ROOT, "EACCES");
    failMkdir.set("/tmp/cc-socks", "EACCES");
    vi.stubEnv("WORKSPACES_ROOT", root);
    buildAgentSandboxConfig(ws());
    const msgs = OPS("masked-dir-precreate").map((o) => o.message);
    expect(msgs.length).toBeGreaterThanOrEqual(2);
    for (const m of msgs) {
      expect(m).toMatch(/^agent-sandbox: (peer-socket|transcript|session-tmp) masked dir could not be created; its read-deny may not apply$/);
    }
    expect(new Set(msgs).size).toBe(msgs.length);
  });

  it("no emit when every pre-create succeeds", () => {
    vi.stubEnv("WORKSPACES_ROOT", root);
    buildAgentSandboxConfig(ws());
    expect(OPS("masked-dir-precreate")).toHaveLength(0);
  });
});

// Guard 2 (builder-versus-reality): the set the production builder pre-creates under the default container env is
// exactly four dirs, the builder really creates every one of them (recursive, 0700), nothing ELSE is created that
// way (a fifth dir added inside an existing kind turns this red), and removing any list from its pre-create loop
// turns this red. The probe's `precreateDirs` is compared to the same set in
// sdk-bash-probe-parity.test.ts.
describe("builder-versus-reality (Guard 2)", () => {
  let root: string;
  beforeEach(() => {
    root = mkdtempSync(join(tmpdir(), "sbx-reality-"));
    reported.length = 0;
    mkdirCalls.length = 0;
    failMkdir.clear();
  });
  afterEach(() => {
    vi.unstubAllEnvs();
    rmSync(root, { recursive: true, force: true });
  });

  function defaultEnvBuild(): string[] {
    // Controlled default container env: HOME fixed, every base override unset.
    vi.stubEnv("HOME", root);
    for (const k of ["XDG_RUNTIME_DIR", "CLAUDE_CODE_TMPDIR", "TMPDIR", "CLAUDE_CONFIG_DIR"]) vi.stubEnv(k, "");
    vi.stubEnv("WORKSPACES_ROOT", root);
    buildAgentSandboxConfig(join(root, "00000000-0000-0000-0000-000000000002"));
    const uid = typeof process.getuid === "function" ? process.getuid() : undefined;
    return [
      ...peerMessagingSocketDirs({ HOME: root }, uid),
      ...sessionTranscriptDirs({ HOME: root }),
      AGENT_SESSION_TMP_ROOT,
    ];
  }

  it("the builder's default-env set is exactly four dirs (floor: an empty derivation must not pass)", () => {
    const expected = defaultEnvBuild();
    const uid = process.getuid?.();
    expect([...expected].sort()).toEqual(
      ["/tmp/cc-socks", `/tmp/cc-socks-${uid}`, join(root, ".claude", "projects"), "/tmp/.cs"].sort(),
    );
  });

  it("the set of dirs the builder creates (recursive, mode 0700) IS the expected four: a fifth dir inside an existing kind must be mirrored in the probe", () => {
    const expected = defaultEnvBuild();
    // The one other recursive-0700 mkdir a default-env build makes is the C4 staging root (best-effort, its own contract, not a masked
    // dir). Any OTHER dir the builder starts creating this way has to be classified here, and a masked one in the probe's precreateDirs.
    const c4Root = c4RenderStagingRoot();
    const created = [
      ...new Set(
        mkdirCalls
          .filter((c) => (c.opts as { recursive?: boolean; mode?: number } | undefined)?.recursive === true && (c.opts as { mode?: number }).mode === 0o700)
          .map((c) => c.dir)
          .filter((d) => d !== c4Root),
      ),
    ].sort();
    expect(created).toEqual([...expected].sort());
    expect(created).toHaveLength(4);
  });

  it("the builder attempts mkdir (recursive, mode 0700) for every member and each is a real directory", () => {
    const expected = defaultEnvBuild();
    for (const dir of expected) {
      const call = mkdirCalls.find((c) => c.dir === dir);
      expect(call, `no mkdirSync attempt for ${dir}`).toBeDefined();
      expect(call?.opts).toEqual({ recursive: true, mode: 0o700 });
      expect(statSync(dir).isDirectory(), `${dir} is not a directory on disk`).toBe(true);
    }
    expect(OPS("masked-dir-precreate")).toHaveLength(0);
  });
});
