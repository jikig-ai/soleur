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

import { describe, it, expect } from "vitest";
import {
  mkdtempSync,
  mkdirSync,
  writeFileSync,
  realpathSync,
  readFileSync,
  rmSync,
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

function fixture(): { root: string; ws: string; home: string; plugin: string } {
  const root = mkdtempSync(path.join(tmpdir(), "aow-"));
  const ws = path.join(root, "workspaces", "ws-aaaa");
  const sibling = path.join(root, "workspaces", "ws-bbbb");
  const home = path.join(root, "home", "soleur");
  const plugin = path.join(root, "app", "shared", "plugins", "soleur");
  mkdirSync(ws, { recursive: true });
  mkdirSync(sibling, { recursive: true });
  mkdirSync(home, { recursive: true });
  mkdirSync(plugin, { recursive: true });
  mkdirSync(path.join(home, ".claude", "projects"), { recursive: true });
  writeFileSync(path.join(home, ".claude", ".credentials.json"), "{}");
  return { root, ws, home, plugin };
}

const fixture2 = fixture;

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
    expect(p).toContainEqual(["--bind", projDir, projDir]);
    expect(p).toContainEqual(["--bind", path.join(f.home, ".claude", ".credentials.json"), path.join(f.home, ".claude", ".credentials.json")]);
    // the projects PARENT is a --dir (fresh), never a bind — sibling slugs
    // under it stay absent.
    expect(p).toContainEqual(["--dir", path.join(f.home, ".claude", "projects"), undefined]);
    expect(p.find(([, s]) => s === path.join(f.home, ".claude", "projects") && false)).toBeUndefined();
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
    const fixture = JSON.parse(
      readFileSync(
        path.join(__dirname, "..", "infra", "agent-outer-wrap-argv.json"),
        "utf8",
      ),
    );
    const f = fixture2();
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
    expect(projected2).toEqual(fixture.bwrapSetupArgv);
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
    const BIND_SRC_FLAGS = new Set(["--bind", "--ro-bind", "--dev-bind", "--ro-bind-try"]);
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
    const { err, code } = await spawnWith(
      { workspacePath: f.ws, home: f.home },
      path.join(f.root, "no-such-cli"),
    );
    expect(code).toBe(127);
    expect(err.message).toContain("command_missing:");
    expect(classifySandboxStartupError(err).sandboxKind).toBe("missing_binary");
  });

  it("bind source vanishing between argv build and spawn → bind_source_missing", async () => {
    const f = fixture();
    const creds = path.join(f.home, ".claude", ".credentials.json");
    const factory = makeSandboxedSpawn({ workspacePath: f.ws, home: f.home });
    rmSync(creds); // the file was --bind'ed at build time; gone by spawn time
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
    // script's getcap fallback).
    return execFileSync(
      BWRAP_PATH,
      [
        "--unshare-user",
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
          "--unshare-user",
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
          "--unshare-user",
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
