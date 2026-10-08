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
import { mkdtempSync, mkdirSync, writeFileSync, realpathSync, readFileSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { tmpdir } from "node:os";
import path from "node:path";

import {
  buildOuterWrapArgv,
  outerWrapEnabled,
  BWRAP_PATH,
} from "@/server/agent-outer-wrap";

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

  it.skipIf(!bwrapOk)(
    "a real wrapped bash sees the own workspace and not the sibling",
    () => {
      const f = fixture();
      const argv = buildOuterWrapArgv({
        workspacePath: f.ws,
        home: f.home,
        pluginPath: f.plugin,
      });
      // On an unprivileged host bwrap needs --unshare-user to build the
      // mountns; the emitted argv stays mount-only — the flag is added by
      // the caller when bwrap lacks file caps.
      const out = execFileSync(BWRAP_PATH, [
        "--unshare-user",
        ...argv.slice(0, -1),
        "/bin/bash",
        "-c",
        `ls ${path.dirname(f.ws)} && (stat ${path.dirname(f.ws)}/ws-bbbb && echo SIBLING-VISIBLE || echo SIBLING-ABSENT) && cat /proc/self/mounts | grep -c ws-bbbb || true`,
      ]).toString();
      expect(out).toContain("ws-aaaa");
      expect(out).not.toContain("ws-bbbb\n");
      expect(out).toContain("SIBLING-ABSENT");
    },
  );
});
