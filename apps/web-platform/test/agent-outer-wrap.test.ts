// Contract tests for `buildOuterWrapArgv` + `makeSandboxedSpawn` (#5863,
// ADR-075 Option B — arm F: mountns-only wrap via file-cap'd bwrap).
//
// The argv builder is the sole producer of the outer mount table; its shape
// IS the isolation contract:
//   - zero `--unshare-*` (measured: any outer userns kills the vendored
//     inner sandbox — see plan Phase-0 spike table),
//   - no mount target under the workspaces parent except the own-workspace
//     bind,
//   - `/proc` bound through (shared — #9723 residual),
//   - no `--clearenv` (it wipes the spawn env wholesale) and no secret on
//     argv (env carries credentials; argv carries paths only),
//   - `--die-with-parent` + `--new-session` for teardown.
//
// The committed fixture (infra/agent-outer-wrap-argv.json) pins the full
// emitted set so any mount-table drift is a reviewable diff.

import { describe, it, expect, vi, beforeEach } from "vitest";
import {
  mkdtempSync,
  mkdirSync,
  writeFileSync,
  realpathSync,
  readFileSync,
  rmSync,
  symlinkSync,
} from "node:fs";
import { execFileSync } from "node:child_process";
import { tmpdir } from "node:os";
import path from "node:path";

import {
  buildOuterWrapArgv,
  makeSandboxedSpawn,
  outerWrapEnabled,
  BWRAP_PATH,
} from "@/server/agent-outer-wrap";
import { classifySandboxStartupError } from "@/server/sandbox-startup-classifier";

// Emit-fork sinks for the realized-isolation probe — same mock shape as
// agent-runner-query-options.test.ts: spread the real module so unrelated
// transitive exports keep working, capture the two forks the probes emit.
const obs = vi.hoisted(() => ({ warnSilentFallback: vi.fn(), reportSilentFallback: vi.fn() }));
vi.mock("@/server/observability", async (importOriginal) => ({
  ...(await importOriginal<typeof import("@/server/observability")>()),
  warnSilentFallback: obs.warnSilentFallback,
  reportSilentFallback: obs.reportSilentFallback,
}));
const sentry = vi.hoisted(() => ({ captureMessage: vi.fn(), captureException: vi.fn() }));
vi.mock("@sentry/nextjs", () => sentry);

function fixture(): { root: string; ws: string; home: string; plugin: string } {
  const root = mkdtempSync(path.join(tmpdir(), "aow-"));
  const ws = path.join(root, "workspaces", "ws-aaaa");
  const sibling = path.join(root, "workspaces", "ws-bbbb");
  const home = path.join(root, "home", "soleur");
  const plugin = path.join(root, "app", "shared", "plugins", "soleur");
  mkdirSync(ws, { recursive: true });
  mkdirSync(sibling, { recursive: true });
  // The shared payload's vantage-(b) read targets <sibling>/marker.txt —
  // it must exist on the host so the ENOENT inside the wrap is isolation,
  // not an absent fixture (anti-vacuity).
  writeFileSync(path.join(sibling, "marker.txt"), "sibling-secret\n");
  mkdirSync(home, { recursive: true });
  mkdirSync(plugin, { recursive: true });
  mkdirSync(path.join(home, ".claude", "projects"), { recursive: true });
  writeFileSync(path.join(home, ".claude", ".credentials.json"), "{}");
  return { root, ws, home, plugin };
}


function pairs(argv: string[]): Array<[string, string, string | undefined]> {
  const out: Array<[string, string, string | undefined]> = [];
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--") break;
    if (argv[i].startsWith("--") && !argv[i + 1]?.startsWith("--")) {
      out.push([argv[i], argv[i + 1], argv[i + 2]?.startsWith("--") ? undefined : argv[i + 2]]);
    }
  }
  return out;
}

describe("buildOuterWrapArgv", () => {
  it("emits zero --unshare-* flags (mountns-only — arm F)", () => {
    const f = fixture();
    const argv = buildOuterWrapArgv({
      workspacePath: f.ws,
      home: f.home,
      pluginPath: f.plugin,
    });
    expect(argv.filter((a) => a.startsWith("--unshare"))).toEqual([]);
    expect(argv).toContain("--die-with-parent");
    expect(argv).not.toContain("--clearenv");
  });

  it("binds only the own workspace under the workspaces parent", () => {
    const f = fixture();
    const argv = buildOuterWrapArgv({
      workspacePath: f.ws,
      home: f.home,
      pluginPath: f.plugin,
    });
    const wsParent = path.dirname(f.ws);
    for (const [flag, src, dest] of pairs(argv)) {
      const target = dest ?? src;
      if (!target) continue;
      // Nothing under the workspaces parent except the workspace itself.
      // --chdir is a mount-target-free flag pointing at the bound ws — skip.
      if (flag === "--chdir") continue;
      if (target.startsWith(wsParent + path.sep)) {
        expect(target).toBe(realpathSync(f.ws));
        expect(flag).toBe("--bind"); // rw
      }
      expect(target).not.toContain("ws-bbbb");
    }
  });

  it("never mounts the workspaces parent itself", () => {
    const f = fixture();
    const argv = buildOuterWrapArgv({
      workspacePath: f.ws,
      home: f.home,
      pluginPath: f.plugin,
    });
    const wsParent = realpathSync(path.dirname(f.ws));
    for (const [, src, dest] of pairs(argv)) {
      expect(src).not.toBe(wsParent);
      if (dest) expect(dest).not.toBe(wsParent);
    }
  });

  it("never emits a secret-bearing flag (--setenv secrets, /run binds)", () => {
    const f = fixture();
    const argv = buildOuterWrapArgv({
      workspacePath: f.ws,
      home: f.home,
      pluginPath: f.plugin,
    });
    for (const a of argv) {
      expect(a).not.toBe("--setenv");
      expect(a).not.toMatch(/TOKEN|KEY|SECRET|PASSWORD/i);
      expect(a).not.toMatch(/\/run\//);
      expect(a).not.toContain("XDG_RUNTIME_DIR");
    }
  });

  it("shares /proc by design (arm F — #9723 residual), tmpfs /tmp", () => {
    const f = fixture();
    const argv = buildOuterWrapArgv({
      workspacePath: f.ws,
      home: f.home,
      pluginPath: f.plugin,
    });
    const p = pairs(argv);
    expect(p).toContainEqual(["--bind", "/proc", "/proc"]);
    expect(p).toContainEqual(["--tmpfs", "/tmp", undefined]);
  });

  it("narrow-binds ~/.claude: transcript slug bound rw, siblings absent", () => {
    const f = fixture();
    const slug = realpathSync(f.ws).replaceAll("/", "-");
    const projDir = path.join(f.home, ".claude", "projects", slug);
    mkdirSync(projDir, { recursive: true });
    const argv = buildOuterWrapArgv({
      workspacePath: f.ws,
      home: f.home,
      pluginPath: f.plugin,
    });
    const p = pairs(argv);
    expect(p).toContainEqual(["--bind-try", projDir, projDir]);
    expect(p).toContainEqual(["--bind-try", path.join(f.home, ".claude", ".credentials.json"), path.join(f.home, ".claude", ".credentials.json")]);
    // the projects PARENT is a --dir (fresh), never a bind — sibling slugs
    // under it stay absent.
    expect(p).toContainEqual(["--dir", path.join(f.home, ".claude", "projects"), undefined]);
    expect(p.filter(([fl, s]) => fl !== "--dir" && s === path.join(f.home, ".claude", "projects"))).toEqual([]);
  });

  it("ends with -- and chdirs to the resolved workspace", () => {
    const f = fixture();
    const argv = buildOuterWrapArgv({
      workspacePath: f.ws,
      home: f.home,
      pluginPath: f.plugin,
    });
    expect(argv[argv.length - 1]).toBe("--");
    const p = pairs(argv);
    expect(p).toContainEqual(["--chdir", realpathSync(f.ws), undefined]);
  });

  it("support persona: no workspacePath → nothing under any ws root, cwd = pluginPath", () => {
    const f = fixture();
    const argv = buildOuterWrapArgv({
      cwd: f.plugin,
      home: f.home,
      pluginPath: f.plugin,
    });
    expect(argv.filter((a) => a.includes("workspaces"))).toEqual([]);
    expect(pairs(argv)).toContainEqual(["--chdir", realpathSync(f.plugin), undefined]);
    // knowledge-base/ is absent-by-construction for EVERY persona — no
    // persona-specific deny is needed because nothing binds /app/shared.
    expect(argv.filter((a) => a.includes("knowledge-base"))).toEqual([]);
  });

  it("fails closed when workspacePath does not exist", () => {
    const f = fixture();
    expect(() =>
      buildOuterWrapArgv({ workspacePath: path.join(f.root, "nope"), home: f.home }),
    ).toThrow(/workspacePath missing/);
  });
});

describe("committed argv fixture (Guard 2)", () => {
  it("matches infra/agent-outer-wrap-argv.json under {{ROOT}} substitution", async () => {
    const fx = JSON.parse(
      readFileSync(
        path.join(__dirname, "..", "infra", "agent-outer-wrap-argv.json"),
        "utf8",
      ),
    );
    const f = fixture();
    const argv = buildOuterWrapArgv({
      workspacePath: f.ws,
      home: f.home,
      pluginPath: f.plugin,
      appRoot: path.join(f.root, "app"),
    });
    const projected = argv.map((a) => a.replaceAll(realpathSync(f.root), "{{ROOT}}"));
    // realpath may differ from the literal path (e.g. macOS /tmp symlink) —
    // project both forms.
    const projected2 = projected.map((a) => a.replaceAll(f.root, "{{ROOT}}"));
    expect(projected2).toEqual(fx.bwrapSetupArgv);
  });

  it("prep manifest covers every {{ROOT}} bind source exactly (argv/prep drift is red)", () => {
    const fixture = JSON.parse(
      readFileSync(
        path.join(__dirname, "..", "infra", "agent-outer-wrap-argv.json"),
        "utf8",
      ),
    );
    const argv: string[] = fixture.bwrapSetupArgv;
    // Anti-vacuity floor (Guard 2 mutation row 4): the fixture must carry
    // the placeholder AND no absolute sibling path — a fixture without
    // either would still diff-equal yet replay nothing meaningful.
    expect(argv.some((a) => a.includes("{{ROOT}}"))).toBe(true);
    expect(argv.filter((a) => /workspaces\/ws-(?!aaaa\b)/.test(a))).toEqual([]);

    // Bind flags take <src> <dst> pair; only the SOURCE must pre-exist.
    // --dir/--tmpfs targets are created inside the namespace — never prep.
    const BIND_SRC_FLAGS = new Set(["--bind", "--ro-bind", "--dev-bind", "--ro-bind-try", "--bind-try"]);
    const sources = new Set<string>();
    for (let i = 0; i < argv.length; i++) {
      if (argv[i] === "--") break;
      if (BIND_SRC_FLAGS.has(argv[i]) && argv[i + 1]?.includes("{{ROOT}}")) {
        sources.add(argv[i + 1]);
      }
    }
    const prep = new Set<string>([...fixture.prepDirs, ...fixture.prepFiles]);
    expect(prep).toEqual(sources);
  });
});

describe("outerWrapEnabled", () => {
  it("is off by default; on with AGENT_OUTER_WRAP=1; cohort allowlist works", () => {
    const env = process.env;
    delete env.AGENT_OUTER_WRAP;
    delete env.AGENT_OUTER_WRAP_WORKSPACES;
    expect(outerWrapEnabled("ws-1")).toBe(false);
    env.AGENT_OUTER_WRAP = "1";
    expect(outerWrapEnabled("ws-1")).toBe(true);
    env.AGENT_OUTER_WRAP_WORKSPACES = "ws-1, ws-2";
    expect(outerWrapEnabled("ws-1")).toBe(true);
    expect(outerWrapEnabled("ws-9")).toBe(false);
    delete env.AGENT_OUTER_WRAP;
    delete env.AGENT_OUTER_WRAP_WORKSPACES;
  });
});

describe("makeSandboxedSpawn — fail-closed preflight (T1.4)", () => {
  function spawnWith(inputs: Parameters<typeof makeSandboxedSpawn>[0], command: string) {
    const factory = makeSandboxedSpawn(inputs);
    const proc = factory({
      command,
      args: [],
      env: {},
    } as never);
    return new Promise<{ err: Error; code: number | null }>((resolve) => {
      proc.once("error", ((e: Error) => {
        proc.once("exit", ((code: number | null) => resolve({ err: e, code })) as never);
      }) as never);
    });
  }

  it("missing bwrap → synthetic exit 127 + missing_binary classification", async () => {
    const f = fixture();
    const { err, code } = await spawnWith(
      { workspacePath: f.ws, home: f.home, bwrapPath: path.join(f.root, "no-bwrap") },
      "/bin/true",
    );
    expect(code).toBe(127);
    expect(err.message).toContain("bwrap_missing:");
    const cls = classifySandboxStartupError(err);
    expect(cls.sandboxKind).toBe("missing_binary");
    expect(cls.errorCode).toBe("sandbox_unavailable");
  });

  it("missing command → synthetic exit 127 + missing_binary classification", async () => {
    const f = fixture();
    // bwrapPath DI → host-agnostic (a bwrap-less dev host would trip the
    // earlier preflight check instead of reaching the command check).
    const { err, code } = await spawnWith(
      { workspacePath: f.ws, home: f.home, bwrapPath: "/bin/true" },
      path.join(f.root, "no-such-cli"),
    );
    expect(code).toBe(127);
    expect(err.message).toContain("command_missing:");
    expect(classifySandboxStartupError(err).sandboxKind).toBe("missing_binary");
  });

  it("bind source vanishing between argv build and spawn → bind_source_missing", async () => {
    const f = fixture();
    // Try-binds tolerate a missing source by design; the STRICT-bind arm the
    // preflight guards is the workspace itself.
    const factory = makeSandboxedSpawn({ workspacePath: f.ws, home: f.home, bwrapPath: "/bin/true" });
    rmSync(f.ws, { recursive: true, force: true }); // --bind'ed at build time; gone by spawn time
    const proc = factory({ command: "/bin/true", args: [], env: {} } as never);
    const { err, code } = await new Promise<{ err: Error; code: number | null }>(
      (resolve) => {
        proc.once("error", ((e: Error) => {
          proc.once("exit", ((c: number | null) => resolve({ err: e, code: c })) as never);
        }) as never);
      },
    );
    expect(code).toBe(127);
    expect(err.message).toContain("bind_source_missing:");
    expect(classifySandboxStartupError(err).sandboxKind).toBe("missing_binary");
  });

  // Linux-only: the emitted argv carries a strict `--bind /proc /proc` —
  // absent on macOS, preflight fails closed there (exit 127) by design.
  it.skipIf(process.platform !== "linux")("spawn round-trip: wraps [bwrap, ...argv, command, ...args] + env verbatim/TMPDIR (T0.3)", async () => {
    const f = fixture();
    // An argv-dump script as the bwrapPath seam: the spawn composition is
    // asserted against what the child ACTUALLY receives, incl. env.
    const dump = path.join(f.root, "dump-argv.sh");
    writeFileSync(
      dump,
      '#!/bin/sh\nfor a in "$@"; do printf "%s\\n" "$a"; done\nprintf "TMPDIR=%s\\n" "$TMPDIR"\nprintf "PROBE_SENTINEL=%s\\n" "${PROBE_SENTINEL:-<unset>}"\n',
      { mode: 0o755 },
    );
    const factory = makeSandboxedSpawn({ workspacePath: f.ws, home: f.home, pluginPath: f.plugin, bwrapPath: dump });
    const proc = factory({
      command: "/bin/true",
      args: ["--flag-a", "value-b"],
      env: { PROBE_SENTINEL: "kept", TMPDIR: "/should/be/overridden" },
    } as never);
    const chunks: Buffer[] = [];
    const code = await new Promise<number | null>((resolve) => {
      proc.stdout.on("data", (b: Buffer) => chunks.push(b));
      proc.once("exit", ((c: number | null) => resolve(c)) as never);
    });
    const lines = Buffer.concat(chunks).toString("utf8").trim().split("\n");
    expect(code).toBe(0);
    // The wrap argv precedes the command; command + args come last.
    const cmdIdx = lines.indexOf("/bin/true");
    expect(cmdIdx).toBeGreaterThan(10);
    expect(lines.slice(cmdIdx, cmdIdx + 3)).toEqual(["/bin/true", "--flag-a", "value-b"]);
    expect(lines[cmdIdx - 1]).toBe("--"); // bwrap's own terminator
    expect(lines).toContain("TMPDIR=/tmp"); // pin to the session tmpfs, not the caller's
    expect(lines).toContain("PROBE_SENTINEL=kept"); // options.env verbatim
    // Secrets never ride argv — only the env channel.
    expect(lines.slice(0, cmdIdx).join(" ")).not.toContain("PROBE_SENTINEL");
  });
});

const INNER_PROBE = path.join(
  __dirname,
  "..",
  "scripts",
  "tenant-isolation-inner-probe.sh",
);

describe("spawn integration (real bwrap, if present)", () => {
  const bwrapOk = (() => {
    try {
      return (
        realpathSync(BWRAP_PATH) &&
        execFileSync("sh", ["-c", `"${BWRAP_PATH}" --version`], { stdio: "pipe" })
      );
    } catch {
      return false;
    }
  })();

  // Mirror tenant-isolation-probe.sh: --unshare-user is the documented
  // LOCAL fallback — prepend it ONLY when the host bwrap lacks file caps,
  // so a cap'd host exercises the same privileged arm production runs.
  const BWRAP_HAS_CAPS = (() => {
    try {
      return /cap_sys_admin/.test(
        execFileSync("getcap", [BWRAP_PATH], { encoding: "utf8" }),
      );
    } catch {
      return false;
    }
  })();
  const ELEVATION_PREFIX = BWRAP_HAS_CAPS ? [] : ["--unshare-user"];

  // Runs the SHARED inner-probe payload inside the wrap — the same
  // assertion set the founder check and the deploy canary replay use, so a
  // green here cannot drift green while the deployed guard regresses.
  // Returns the payload's stdout; throws (test fails) on non-zero exit.
  function runInnerProbe(f: { root: string; ws: string }) {
    const argv = buildOuterWrapArgv({
      workspacePath: f.ws,
      home: path.join(f.root, "home", "soleur"),
      pluginPath: path.join(f.root, "app", "shared", "plugins", "soleur"),
    });
    const parent = path.dirname(f.ws);
    const sibling = path.join(parent, "ws-bbbb");
    // On an unprivileged host bwrap needs --unshare-user to build the
    // mountns; the emitted argv stays mount-only — the flag is added by
    // the caller when bwrap lacks file caps (same convention as the probe
    // script's getcap fallback — gated by ELEVATION_PREFIX).
    return execFileSync(
      BWRAP_PATH,
      [
        ...ELEVATION_PREFIX,
        ...argv,
        "/bin/bash",
        "-s",
        "--",
        realpathSync(parent),
        realpathSync(f.ws),
        realpathSync(sibling),
      ],
      { input: readFileSync(INNER_PROBE, "utf8"), stdio: ["pipe", "pipe", "pipe"] },
    ).toString();
  }

  it.skipIf(!bwrapOk)(
    "inside the wrap the shared probe sees own workspace and not the sibling (T1.2)",
    () => {
      const f = fixture();
      const out = runInnerProbe(f);
      expect(out).toContain("isolation_ok");
      expect(out).not.toContain("FAIL:");
    },
  );

  it.skipIf(!bwrapOk)(
    "a sibling created after the argv was built stays invisible (T1.3 / AC3)",
    () => {
      const f = fixture();
      // The probe's sibling exists at spawn time — recreate the TOCTOU
      // shape by asserting against a SECOND sibling that did not exist when
      // the fixture tree was created but does now.
      const parent = path.dirname(f.ws);
      const late = path.join(parent, "ws-late");
      mkdirSync(late, { recursive: true });
      const argv = buildOuterWrapArgv({
        workspacePath: f.ws,
        home: path.join(f.root, "home", "soleur"),
      });
      const out = execFileSync(
        BWRAP_PATH,
        [
          ...ELEVATION_PREFIX,
          ...argv,
          "/bin/bash",
          "-s",
          "--",
          realpathSync(parent),
          realpathSync(f.ws),
          realpathSync(late),
        ],
        { input: readFileSync(INNER_PROBE, "utf8") },
      ).toString();
      expect(out).toContain("isolation_ok");
    },
  );

  it.skipIf(!bwrapOk)(
    "session child carries no sys_admin in CapEff/CapBnd (T1.7)",
    () => {
      const f = fixture();
      const argv = buildOuterWrapArgv({
        workspacePath: f.ws,
        home: path.join(f.root, "home", "soleur"),
      });
      const out = execFileSync(
        BWRAP_PATH,
        [
          ...ELEVATION_PREFIX,
          ...argv,
          "/bin/bash",
          "-c",
          "grep -E '^Cap(Eff|Bnd):' /proc/self/status",
        ],
      ).toString();
      // cap_sys_admin = bit 21. --cap-drop ALL should clear it in the child.
      const masks = Object.fromEntries(
        [...out.matchAll(/^Cap(Eff|Bnd):\s+([0-9a-f]+)$/gm)].map((m) => [
          m[1],
          BigInt(`0x${m[2]}`),
        ]),
      );
      for (const [k, mask] of Object.entries(masks)) {
        expect(mask & (1n << 21n), `${k} must not carry cap_sys_admin`).toBe(0n);
      }
    },
  );
});

// Boot self-probe (#5863 T3.2) — the realized mountns + shared payload run
// once at boot inside the prod container. Real-bwrap rows use the implicit-
// userns fallback locally; the prod image's file-cap'd bwrap takes the same
// argv verbatim.
describe("probeRealizedIsolation", () => {
  const bwrapOk = (() => {
    try {
      return Boolean(realpathSync(BWRAP_PATH)) && Boolean(
        execFileSync("sh", ["-c", `"${BWRAP_PATH}" --version`], { stdio: "pipe" }),
      );
    } catch {
      return false;
    }
  })();

  it.skipIf(!bwrapOk)("builds the real wrap and reports ok", async () => {
    const { probeRealizedIsolation } = await import("@/server/agent-outer-wrap");
    const p = probeRealizedIsolation();
    expect(p.ok).toBe(true);
  });

  it("missing bwrap binary → not ok with spawn reason", async () => {
    const { probeRealizedIsolation } = await import("@/server/agent-outer-wrap");
    const p = probeRealizedIsolation({ bwrapPath: "/nonexistent-bwrap" });
    expect(p.ok).toBe(false);
    expect(p.reason).toContain("spawn_");
  });
});

describe("verifyOuterWrapRealizedIsolation — opt-in emit", () => {
  it("no-op when the opt-in env is unset", async () => {
    const { verifyOuterWrapRealizedIsolation } = await import(
      "@/server/agent-outer-wrap"
    );
    expect(() => verifyOuterWrapRealizedIsolation({})).not.toThrow();
  });
});

describe("verifyOuterWrapRealizedIsolation — emit fork", () => {
  beforeEach(() => {
    obs.warnSilentFallback.mockClear();
    sentry.captureMessage.mockClear();
  });
  it("ok + privileged → info emit, no warn", async () => {
    const { verifyOuterWrapRealizedIsolation } = await import("@/server/agent-outer-wrap");
    verifyOuterWrapRealizedIsolation(
      { AGENT_OUTER_WRAP_BOOT_PROBE: "1" },
      { probe: () => ({ ok: true, elevation: "privileged" }) },
    );
    expect(obs.warnSilentFallback).not.toHaveBeenCalled();
    // The info-level Sentry emit is load-bearing — Vector forwards warn+ only,
    // so without this line the realized-isolation proof is unqueryable.
    expect(sentry.captureMessage).toHaveBeenCalledTimes(1);
    expect(sentry.captureMessage.mock.calls[0][0]).toContain("outer-wrap realized probe ok");
  });

  it("ok + userns → warn (file-cap posture not measured)", async () => {
    const { verifyOuterWrapRealizedIsolation } = await import("@/server/agent-outer-wrap");
    verifyOuterWrapRealizedIsolation(
      { AGENT_OUTER_WRAP_BOOT_PROBE: "1" },
      { probe: () => ({ ok: true, elevation: "userns" }) },
    );
    expect(obs.warnSilentFallback).toHaveBeenCalledTimes(1);
    expect(obs.warnSilentFallback.mock.calls[0][1]).toMatchObject({
      feature: "agent-sandbox",
      op: "outer-wrap-realized-probe",
    });
  });

  it("probe fail → warn with the reason carried", async () => {
    const { verifyOuterWrapRealizedIsolation } = await import("@/server/agent-outer-wrap");
    verifyOuterWrapRealizedIsolation(
      { AGENT_OUTER_WRAP_BOOT_PROBE: "1" },
      { probe: () => ({ ok: false, reason: "bwrap_operation_not_permitted" }) },
    );
    expect(obs.warnSilentFallback).toHaveBeenCalledTimes(1);
    expect(obs.warnSilentFallback.mock.calls[0][1]).toMatchObject({
      feature: "agent-sandbox",
      op: "outer-wrap-realized-probe",
    });
  });
});

describe("buildOuterWrapArgv — .git external-target binds are absent (review P0)", () => {
  it("gitdir: pointer file to an outside path → NO bind (tenant-controlled indirection must not become a bind primitive)", () => {
    const f = fixture();
    const repo = path.join(f.root, "repo");
    const gitdir = path.join(repo, ".git", "worktrees", "ws-aaaa");
    mkdirSync(gitdir, { recursive: true });
    writeFileSync(path.join(gitdir, "commondir"), "../..\n");
    writeFileSync(path.join(f.ws, ".git"), `gitdir: ${gitdir}\n`);
    const argv = buildOuterWrapArgv({
      workspacePath: f.ws,
      home: f.home,
      pluginPath: f.plugin,
    });
    expect(argv).not.toContain(gitdir);
    expect(argv).not.toContain(path.join(repo, ".git"));
  });

  it(".git symlink to an outside path → NO bind (a symlink to / would mount the whole root)", () => {
    const f = fixture();
    const outside = path.join(f.root, "outside");
    mkdirSync(outside, { recursive: true });
    symlinkSync(outside, path.join(f.ws, ".git"));
    const argv = buildOuterWrapArgv({
      workspacePath: f.ws,
      home: f.home,
      pluginPath: f.plugin,
    });
    expect(argv).not.toContain(realpathSync(outside));
  });

  it("intermediate-component symlink (~/.claude → outside) drops every home bind (fix-round P1)", () => {
    const f = fixture();
    // A planted ~/.claude symlink survives a leaf lstat on each file INSIDE
    // it — only resolved-path containment catches the redirect.
    const attacker = path.join(f.root, "attacker-claude");
    mkdirSync(attacker, { recursive: true });
    writeFileSync(path.join(attacker, ".credentials.json"), "{}");
    rmSync(path.join(f.home, ".claude"), { recursive: true });
    symlinkSync(attacker, path.join(f.home, ".claude"));
    const argv = buildOuterWrapArgv({
      workspacePath: f.ws,
      home: f.home,
      pluginPath: f.plugin,
    });
    expect(argv).not.toContain(attacker);
    for (const flag of ["--bind", "--bind-try"]) {
      for (let i = 0; i < argv.length; i++) {
        if (argv[i] === flag) expect(argv[i + 1]).not.toContain("attacker-claude");
      }
    }
  });
});
