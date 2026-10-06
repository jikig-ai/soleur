// Contract for infra/bwrap-shim/bwrap (#8752), the PATH shim the Agent SDK's
// PATH-resolved `bwrap` spawn lands on. Two obligations, tested against a fake
// "real bwrap" (SOLEUR_BWRAP_REAL) that records what it received, plus one
// real-bwrap end-to-end row under the C4_BWRAP_REQUIRED convention:
//
//   1. probe passthrough — `bwrap --version` (the SDK's failIfUnavailable
//      probe) execs verbatim, no filter injected, no fd sweep.
//   2. setup invocations — inject `--add-seccomp-fd N` onto a freshly opened
//      fd carrying the artifact, preserve fds the argv references (`--args`
//      transports the whole setup argv on a pipe/file fd), close every other
//      fd above stderr, fail closed (exit 65 + `bwrap-shim:` marker) when the
//      real binary or artifact is missing.
import { describe, it, expect } from "vitest";
import { spawnSync } from "node:child_process";
import {
  mkdirSync,
  mkdtempSync,
  openSync,
  readFileSync,
  rmSync,
  writeFileSync,
  chmodSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const APP_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const SHIM = join(APP_ROOT, "infra/bwrap-shim/bwrap");
const BPF = join(APP_ROOT, "infra/bwrap-userns-clone3-deny.bpf");

// The fake "real bwrap": records its argv (one ARG per line), every fd it can
// see (FD lines with readlink targets), and — when `--args <fd>` was passed —
// the payload bytes (PAYLOAD lines, NUL split to newlines). Exits 0.
const FAKE_BWRAP = `#!/usr/bin/env bash
out=${"$"}{SOLEUR_SHIM_STUB_OUT:?}
: >"$out"
for a in "$@"; do printf 'ARG\\t%s\\n' "$a" >>"$out"; done
for p in /proc/self/fd/*; do
  n=\${p##*/}
  printf 'FD\\t%s\\t%s\\n' "$n" "$(readlink "$p" 2>/dev/null || echo '?')" >>"$out"
done
prev=""
for a in "$@"; do
  if [ "$prev" = "--args" ]; then
    if IFS= read -r -d '' -u "$a" line <&"$a" 2>/dev/null || [ -n "$line" ]; then
      printf 'PAYLOAD\\t%s\\n' "$line" >>"$out"
      while IFS= read -r -d '' -u "$a" line <&"$a"; do printf 'PAYLOAD\\t%s\\n' "$line" >>"$out"; done
    fi
  fi
  prev=$a
done
exit 0
`;

function mkRoot() {
  const root = mkdtempSync(join(tmpdir(), "bwrap-shim-test-"));
  const stub = join(root, "fake-bwrap");
  writeFileSync(stub, FAKE_BWRAP, { mode: 0o700 });
  chmodSync(stub, 0o700);
  const out = join(root, "stub-out");
  return {
    root,
    stub,
    out,
    env(over: Record<string, string | undefined> = {}) {
      const env: Record<string, string> = {
        PATH: process.env.PATH ?? "/usr/bin:/bin",
        SOLEUR_BWRAP_REAL: stub,
        SOLEUR_BWRAP_SECCOMP_BPF: BPF,
        SOLEUR_SHIM_STUB_OUT: out,
      };
      for (const [k, v] of Object.entries(over)) {
        if (v === undefined) delete env[k];
        else env[k] = v;
      }
      return env;
    },
    read() {
      const raw = readFileSync(out, "utf8");
      const args: string[] = [];
      const fds = new Map<string, string>();
      const payload: string[] = [];
      for (const line of raw.split("\n")) {
        const [kind, a, b] = line.split("\t");
        if (kind === "ARG") args.push(a);
        else if (kind === "FD") fds.set(a, b);
        else if (kind === "PAYLOAD") payload.push(a);
      }
      return { args, fds, payload };
    },
  };
}

describe("bwrap PATH shim (#8752)", () => {
  let roots: string[] = [];
  const root = () => {
    const r = mkRoot();
    roots.push(r.root);
    return r;
  };
  const cleanup = () => {
    for (const r of roots) rmSync(r, { recursive: true, force: true });
    roots = [];
  };

  it("bwrap --version execs the real binary verbatim (SDK availability probe)", () => {
    const r = root();
    try {
      const res = spawnSync(SHIM, ["--version"], { env: r.env(), encoding: "utf8" });
      expect(res.status, res.stderr).toBe(0);
      const { args } = r.read();
      expect(args).toEqual(["--version"]);
    } finally {
      cleanup();
    }
  });

  it("a setup invocation gets --add-seccomp-fd N on a live fd carrying the artifact bytes", () => {
    const r = root();
    try {
      const res = spawnSync(SHIM, ["--unshare-user", "--unshare-pid", "--ro-bind", "/", "/", "--", "/usr/bin/true"], {
        env: r.env(),
        encoding: "utf8",
      });
      expect(res.status, res.stderr).toBe(0);
      const { args, fds } = r.read();
      const i = args.indexOf("--add-seccomp-fd");
      expect(i).toBe(0); // injected first, before the SDK's own argv
      const fd = args[i + 1];
      expect(fd).toMatch(/^\d+$/);
      expect(Number(fd)).toBeGreaterThan(2);
      // The fd was open inside the stub and resolves to the artifact.
      expect(fds.get(fd)).toBe(BPF);
      expect(args.slice(2)).toEqual(["--unshare-user", "--unshare-pid", "--ro-bind", "/", "/", "--", "/usr/bin/true"]);
    } finally {
      cleanup();
    }
  });

  it("an --args transport fd survives the sweep and its payload is readable by real bwrap", () => {
    const r = root();
    const payloadFile = join(r.root, "args-payload");
    writeFileSync(payloadFile, "--unshare-user\0--unshare-pid\0--\0/usr/bin/true\0");
    const argsFd = openSync(payloadFile, "r"); // host fd; child sees it as fd 3
    try {
      const res = spawnSync(SHIM, ["--args", "3"], {
        env: r.env(),
        encoding: "utf8",
        stdio: ["ignore", "pipe", "pipe", argsFd],
      });
      expect(res.status, res.stderr).toBe(0);
      const { args, fds, payload } = r.read();
      expect(args).toEqual(["--add-seccomp-fd", expect.any(String) as unknown as string, "--args", "3"]);
      expect(fds.has("3")).toBe(true);
      expect(payload).toEqual(["--unshare-user", "--unshare-pid", "--", "/usr/bin/true"]);
    } finally {
      cleanup();
    }
  });

  it("an unrelated inherited fd does not reach the real bwrap", () => {
    const r = root();
    const secret = join(r.root, "fd-secret");
    writeFileSync(secret, "fd secret");
    const secretFd = openSync(secret, "r"); // child fd 4
    const argsFile = join(r.root, "args-payload");
    writeFileSync(argsFile, "--ro-bind\0/\0/\0--\0/usr/bin/true\0");
    const argsFd = openSync(argsFile, "r"); // child fd 3
    try {
      const res = spawnSync(SHIM, ["--args", "3"], {
        env: r.env(),
        encoding: "utf8",
        stdio: ["ignore", "pipe", "pipe", argsFd, secretFd],
      });
      expect(res.status, res.stderr).toBe(0);
      const { fds } = r.read();
      // The discriminating assertion is the TARGET: no fd inside the real
      // bwrap resolves to the secret file. (A bare `fds.has("4")` check is a
      // false-positive trap — the stub's own /proc/self/fd glob dir fd appears
      // transiently as the lowest free fd and readlinks to '?'.)
      expect([...fds.values()]).not.toContain(secret);
      expect(fds.get("3")).toBe(argsFile); // the argv-referenced fd survives

      // Positive control: WITHOUT the shim the same stub inherits the secret
      // fd — the sweep is what removed it, not node/libuv fd hygiene.
      const leak = spawnSync(r.stub, [], {
        env: r.env(),
        encoding: "utf8",
        stdio: ["ignore", "pipe", "pipe", argsFd, secretFd],
      });
      expect(leak.status, leak.stderr).toBe(0);
      expect(r.read().fds.get("4")).toBe(secret);
    } finally {
      cleanup();
    }
  });

  it("fd-consuming options across the bwrap vocabulary are preserved", () => {
    const r = root();
    const keep = join(r.root, "keep");
    writeFileSync(keep, "x");
    const keepFd = openSync(keep, "r"); // child fd 3
    try {
      const res = spawnSync(
        SHIM,
        ["--sync-fd", "3", "--info-fd", "3", "--json-status-fd", "3", "--block-fd", "3", "--userns-block-fd", "3", "--seccomp", "3", "--", "/usr/bin/true"],
        { env: r.env(), encoding: "utf8", stdio: ["ignore", "pipe", "pipe", keepFd] },
      );
      expect(res.status, res.stderr).toBe(0);
      const { fds } = r.read();
      expect(fds.has("3")).toBe(true);
    } finally {
      cleanup();
    }
  });

  it("fails closed with a marker when the seccomp artifact is missing", () => {
    const r = root();
    try {
      const res = spawnSync(SHIM, ["--unshare-user", "--", "/usr/bin/true"], {
        env: r.env({ SOLEUR_BWRAP_SECCOMP_BPF: join(r.root, "nonexistent.bpf") }),
        encoding: "utf8",
      });
      expect(res.status).toBe(65);
      expect(res.stderr).toContain("bwrap-shim:");
    } finally {
      cleanup();
    }
  });

  it("fails closed with a marker when the real bwrap is missing", () => {
    const r = root();
    try {
      const res = spawnSync(SHIM, ["--unshare-user", "--", "/usr/bin/true"], {
        env: r.env({ SOLEUR_BWRAP_REAL: join(r.root, "no-bwrap") }),
        encoding: "utf8",
      });
      expect(res.status).toBe(65);
      expect(res.stderr).toContain("bwrap-shim:");
    } finally {
      cleanup();
    }
  });
});

// The pair is only live if the runner image bakes BOTH surfaces — the shim
// onto PATH ahead of /usr/bin, and the artifact where both wrappers' default
// SOLEUR_BWRAP_SECCOMP_BPF resolves. This row pins the Dockerfile shape; the
// dockerignore re-includes are asserted by the repo-wide COPY parity guard.
describe("runner-image wiring (#8752)", () => {
  const dockerfile = readFileSync(join(APP_ROOT, "Dockerfile"), "utf8");

  it("the Dockerfile bakes the artifact at the shared default path", () => {
    expect(dockerfile).toContain(
      "COPY --from=builder /app/infra/bwrap-userns-clone3-deny.bpf ./infra/bwrap-userns-clone3-deny.bpf",
    );
  });

  it("the Dockerfile installs the shim onto PATH ahead of /usr/bin", () => {
    expect(dockerfile).toMatch(
      /COPY --from=builder --chmod=0755 \/app\/infra\/bwrap-shim\/bwrap \/usr\/local\/bin\/bwrap/,
    );
  });

  it("the shim file is committed executable (COPY --chmod is the belt, the git mode the suspenders)", () => {
    const res = spawnSync("git", ["ls-files", "-s", "--", "apps/web-platform/infra/bwrap-shim/bwrap"], {
      cwd: join(APP_ROOT, "..", ".."),
      encoding: "utf8",
    });
    expect(res.status).toBe(0);
    expect(res.stdout.trim()).toMatch(/^100755 /);
  });
});

// End-to-end through REAL bwrap (same ran-presence convention as
// test/c4-render-tenant-config.test.ts): skips locally without bwrap, fails
// the suite when C4_BWRAP_REQUIRED is set but a sandbox cannot be built.
const BWRAP_HINT =
  "apt-get install bubblewrap && sysctl -w kernel.apparmor_restrict_unprivileged_userns=0 (Ubuntu)";
const BWRAP_OK =
  spawnSync(
    "/usr/bin/bwrap",
    [
      "--unshare-user", "--unshare-pid", "--unshare-net", "--ro-bind", "/usr", "/usr",
      "--symlink", "usr/lib", "/lib", "--symlink", "usr/lib64", "/lib64", "--", "/usr/bin/true",
    ],
    { stdio: "ignore", timeout: 15_000 },
  ).status === 0;
if (!BWRAP_OK && process.env.C4_BWRAP_REQUIRED) {
  throw new Error(`C4_BWRAP_REQUIRED is set but /usr/bin/bwrap cannot create a sandbox here. ${BWRAP_HINT}`);
}

describe.skipIf(!BWRAP_OK)("bwrap shim end-to-end with the real binary", () => {
  it("unshare -U inside is denied by the injected filter; a forked child still works", () => {
    const env = {
      PATH: process.env.PATH ?? "/usr/bin:/bin",
      SOLEUR_BWRAP_REAL: "/usr/bin/bwrap",
      SOLEUR_BWRAP_SECCOMP_BPF: BPF,
    };
    const argv = [
      "--unshare-user", "--unshare-pid",
      "--ro-bind", "/usr", "/usr",
      "--symlink", "usr/lib", "/lib",
      "--symlink", "usr/lib64", "/lib64",
      "--dev", "/dev",
      "--",
    ];
    const denied = spawnSync(SHIM, [...argv, "/usr/bin/unshare", "-U", "/usr/bin/true"], { env, encoding: "utf8", timeout: 30_000 });
    expect(denied.status).not.toBe(0);
    expect(String(denied.stderr)).not.toContain("bwrap:");
    expect(String(denied.stderr)).toMatch(/Operation not permitted/);
    const ok = spawnSync(SHIM, [...argv, "/usr/bin/sh", "-c", "/usr/bin/true"], { env, encoding: "utf8", timeout: 30_000 });
    expect(ok.status, String(ok.stderr)).toBe(0);
  }, 60_000);
});
