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
import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import { spawnSync } from "node:child_process";
import {
  mkdtempSync,
  symlinkSync,
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

// Sinks for the boot-probe emit fork (verifyAgentSandboxHardening) — the
// probe itself is pure+tested below; these mocks pin WHICH surface each
// verdict branch emits to (ok → info; broken → warnSilentFallback).
const obs = vi.hoisted(() => ({ reportSilentFallback: vi.fn(), warnSilentFallback: vi.fn() }));
vi.mock("@/server/observability", () => obs);
const childLog = vi.hoisted(() => ({ info: vi.fn(), warn: vi.fn(), error: vi.fn() }));
vi.mock("@/server/logger", () => ({ default: childLog, createChildLogger: vi.fn(() => childLog) }));
const sentry = vi.hoisted(() => ({ captureMessage: vi.fn(), captureException: vi.fn() }));
vi.mock("@sentry/nextjs", () => sentry);

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
    # Partial-record guard inside the loop too — an unterminated payload tail
    # (no trailing NUL) is still recorded, never silently dropped.
    while IFS= read -r -d '' -u "$a" line <&"$a" 2>/dev/null || [ -n "$line" ]; do
      printf 'PAYLOAD\\t%s\\n' "$line" >>"$out"
      line=
    done
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
      const env: NodeJS.ProcessEnv = {
        NODE_ENV: "test",
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
      expect(args.slice(2)).toEqual(["--unshare-user", "--unshare-pid", "--ro-bind", "/", "/", "--proc", "/proc", "--", "/usr/bin/true"]);
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
      const res = spawnSync(SHIM, ["--args", "3", "--unshare-pid"], {
        env: r.env(),
        encoding: "utf8",
        stdio: ["ignore", "pipe", "pipe", argsFd],
      });
      expect(res.status, res.stderr).toBe(0);
      const { args, fds, payload } = r.read();
      // #9723: the payload is consumed and re-emitted verbatim on a FRESH fd
      // (the original fd 3 is read to EOF and closed); the `--proc /proc`
      // mask lands at the OUTER argv tail — outer options after an --args
      // token parse after the payload, so the outer end is always the last
      // setup position of the merged stream.
      expect(args[0]).toBe("--add-seccomp-fd");
      expect(args[1]).toMatch(/^\d+$/);
      expect(args[2]).toBe("--args");
      const renumFd = args[3];
      expect(renumFd).toMatch(/^\d+$/);
      expect(fds.has(renumFd)).toBe(true); // the re-emitted payload fd survives
      expect(payload).toEqual(["--unshare-user", "--unshare-pid", "--", "/usr/bin/true"]);
      expect(args.slice(4)).toEqual(["--unshare-pid", "--proc", "/proc"]);
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
      const res = spawnSync(SHIM, ["--args", "3", "--unshare-pid"], {
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
      // #9723: the original --args fd is consumed and closed; the re-emitted
      // payload rides a FRESH fd (a pipe — readlink shows 'pipe:...', never
      // the source file path).
      expect(fds.get("3")).not.toBe(argsFile);
      expect([...fds.values()]).not.toContain(argsFile);

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

  it("every fd-valued bwrap option keeps its (distinct) fd — a dropped option is observed", () => {
    const r = root();
    // One open file per option so removing ANY single option from the shim's
    // preserve-set closes exactly that fd — shared-fd rows cannot discriminate
    // a single-option removal (verified: dropping --sync-fd still passed when
    // all options pointed at fd 3).
    const OPTS = [
      "--sync-fd", "--info-fd", "--json-status-fd", "--block-fd",
      "--userns-block-fd", "--seccomp", "--add-seccomp-fd", "--userns",
      "--userns2", "--pidns", "--file", "--bind-data", "--ro-bind-data",
      "--bind-fd", "--ro-bind-fd",
    ];
    const keep = join(r.root, "keep");
    writeFileSync(keep, "x");
    const fdsOpen = OPTS.map(() => openSync(keep, "r")); // child fds 3..3+n
    const argsFile = join(r.root, "args-payload");
    writeFileSync(argsFile, "--ro-bind\0/\0/\0--\0/usr/bin/true\0");
    const argsFd = openSync(argsFile, "r"); // last fd
    try {
      // fd2 options (FD DEST / FD PID) carry a trailing VALUE token — without
      // it the next option name is consumed as that value (a real
      // value-position desync the shim's arity table must handle).
      const argv = OPTS.flatMap((o, i) =>
        ["--file", "--bind-data", "--ro-bind-data", "--bind-fd", "--ro-bind-fd", "--userns2"].includes(o)
          ? [o, String(3 + i), "x"]
          : [o, String(3 + i)],
      );
      const res = spawnSync(SHIM, [...argv, "--args", String(3 + OPTS.length), "--unshare-pid", "--", "/usr/bin/true"], {
        env: r.env(),
        encoding: "utf8",
        stdio: ["ignore", "pipe", "pipe", ...fdsOpen, argsFd],
      });
      expect(res.status, res.stderr).toBe(0);
      const { args, fds, payload } = r.read();
      for (let i = 0; i < OPTS.length; i++) {
        expect(fds.get(String(3 + i)), `${OPTS[i]} fd must survive the sweep`).toBe(keep);
      }
      // #9723: the original --args fd is consumed; the payload rides the
      // re-emitted fd named in the forwarded argv (a pipe, never argsFile).
      const renumIdx = args.indexOf("--args") + 1;
      const renumFd = args[renumIdx];
      expect(renumFd).toMatch(/^\d+$/);
      expect(fds.has(renumFd)).toBe(true);
      expect([...fds.values()]).not.toContain(argsFile);
      // The mask lands at the OUTER setup end (before `--`), not inside the
      // re-emitted payload — outer options parse after the payload regardless.
      expect(payload).toEqual(["--ro-bind", "/", "/", "--", "/usr/bin/true"]);
      const bi = args.indexOf("--");
      expect(args.slice(bi - 2, bi)).toEqual(["--proc", "/proc"]);
    } finally {
      cleanup();
    }
  });

  it("a flag-named token in VALUE position does not preserve an fd (arity desync)", () => {
    const r = root();
    const secret = join(r.root, "desync-secret");
    writeFileSync(secret, "x");
    const secretFd = openSync(secret, "r"); // child fd 3
    try {
      // `--setenv --args 3` — "--args" is setenv's VAR value, "3" its VALUE:
      // a prev-token scan reads "--args"+"3" as an fd reference and keeps fd
      // 3 open into the sandbox (silent leak). The arity-aware scan must not.
      const res = spawnSync(
        SHIM,
        ["--unshare-pid", "--setenv", "--args", "3", "--ro-bind", "--sync-fd", "3", "--", "/usr/bin/true"],
        { env: r.env(), encoding: "utf8", stdio: ["ignore", "pipe", "pipe", secretFd] },
      );
      expect(res.status, res.stderr).toBe(0);
      const { fds } = r.read();
      expect([...fds.values()]).not.toContain(secret);
    } finally {
      cleanup();
    }
  });

  it("an fd reference AFTER the `--` command boundary is not preserved", () => {
    const r = root();
    const secret = join(r.root, "tail-secret");
    writeFileSync(secret, "x");
    const secretFd = openSync(secret, "r"); // child fd 3
    try {
      // Tokens past `--` are the sandboxed command, not options — a literal
      // `--sync-fd 3` there must NOT pin fd 3 open through the sweep.
      const res = spawnSync(
        SHIM,
        ["--unshare-pid", "--ro-bind", "/usr", "/usr", "--", "/bin/sh", "-c", "x", "--sync-fd", "3"],
        { env: r.env(), encoding: "utf8", stdio: ["ignore", "pipe", "pipe", secretFd] },
      );
      expect(res.status, res.stderr).toBe(0);
      const { fds } = r.read();
      expect([...fds.values()]).not.toContain(secret);
    } finally {
      cleanup();
    }
  });

  it("a `/proc/self/fd/N` path inside a command token IS preserved (apply-seccomp contract)", () => {
    const r = root();
    const helper = join(r.root, "helper-binary");
    writeFileSync(helper, "x");
    const helperFd = openSync(helper, "r"); // child fd 3
    try {
      // The vendored inner command execs its own binary through
      // `/proc/self/fd/3` (apply-seccomp multicall dispatch — see the command
      // tail the SDK emits). The fd is named by PATH inside a command token,
      // never by an option — the sweep must still preserve it, else the
      // sandboxed spawn dies on exec (ENOENT).
      const res = spawnSync(
        SHIM,
        ["--unshare-pid", "--ro-bind", "/usr", "/usr", "--", "/bin/sh", "-c", "exec /proc/self/fd/3 arg"],
        { env: r.env(), encoding: "utf8", stdio: ["ignore", "pipe", "pipe", helperFd] },
      );
      expect(res.status, res.stderr).toBe(0);
      const { fds } = r.read();
      expect([...fds.values()]).toContain(helper);
    } finally {
      cleanup();
    }
  });

  it("inserts --proc /proc immediately before the first -- (plain setup argv)", () => {
    // #9723 — the vendored builder's enableWeakerNestedSandbox handling ends the
    // setup argv with `--bind /proc /proc`, re-mounting real procfs over the
    // denyRead `--tmpfs /proc` (later mounts win). The shim re-masks at the tail
    // with a FRESH pidns-scoped procfs: `--proc /proc` must land BEFORE the
    // command boundary and AFTER every setup token (so after the vendor's tail
    // bind) — empty tmpfs would break the vendor's `apply-seccomp
    // /proc/self/fd/N` inner command.
    const r = root();
    try {
      const res = spawnSync(
        SHIM,
        ["--unshare-user", "--unshare-pid", "--ro-bind", "/", "/", "--bind", "/proc", "/proc", "--", "/usr/bin/true"],
        { env: r.env(), encoding: "utf8" },
      );
      expect(res.status, res.stderr).toBe(0);
      const { args } = r.read();
      expect(args).toEqual([
        "--add-seccomp-fd",
        expect.stringMatching(/^\d+$/),
        "--unshare-user",
        "--unshare-pid",
        "--ro-bind", "/", "/",
        "--bind", "/proc", "/proc",
        "--proc", "/proc",
        "--",
        "/usr/bin/true",
      ]);
    } finally {
      cleanup();
    }
  });

  it("targets the FIRST -- when the command tail carries another", () => {
    const r = root();
    try {
      const res = spawnSync(
        SHIM,
        ["--unshare-pid", "--ro-bind", "/", "/", "--", "/bin/sh", "-c", "x", "--"],
        { env: r.env(), encoding: "utf8" },
      );
      expect(res.status, res.stderr).toBe(0);
      const { args } = r.read();
      const boundary = args.indexOf("--");
      expect(boundary).toBeGreaterThan(0);
      expect(args.slice(boundary - 2, boundary)).toEqual(["--proc", "/proc"]);
      // The command tail is passed through verbatim — including its own `--`.
      expect(args.slice(boundary + 1)).toEqual(["/bin/sh", "-c", "x", "--"]);
    } finally {
      cleanup();
    }
  });

  it("the --args transport (SDK shape) gets the mask after the payload, before --", () => {
    const r = root();
    // Mirror of the committed fixture's shape: early --tmpfs /proc (denyRead
    // entry) + the vendor's tail --bind /proc /proc (token 118-119).
    const payloadFile = join(r.root, "args-payload");
    writeFileSync(
      payloadFile,
      "--unshare-user\0--tmpfs\0/proc\0--ro-bind\0/\0/\0--bind\0/proc\0/proc\0",
    );
    const argsFd = openSync(payloadFile, "r"); // child fd 3
    try {
      const res = spawnSync(SHIM, ["--args", "3", "--unshare-pid", "--", "/usr/bin/true"], {
        env: r.env(),
        encoding: "utf8",
        stdio: ["ignore", "pipe", "pipe", argsFd],
      });
      expect(res.status, res.stderr).toBe(0);
      const { args, payload } = r.read();
      // The payload is consumed and re-emitted verbatim on a fresh fd (the
      // fd NUMBER may differ — assert the re-emitted content, not the fd).
      expect(payload).toEqual([
        "--unshare-user", "--tmpfs", "/proc", "--ro-bind", "/", "/",
        "--bind", "/proc", "/proc",
      ]);
      const argsIdx = args.indexOf("--args");
      const boundary = args.indexOf("--");
      expect(argsIdx).toBe(2); // [--add-seccomp-fd, N, --args, M, ...]
      expect(args.slice(argsIdx + 2, boundary)).toEqual(["--unshare-pid", "--proc", "/proc"]);
    } finally {
      cleanup();
    }
  });

  it("a -- carried INSIDE the --args payload: the mask still lands at the OUTER setup end", () => {
    const r = root();
    // Arm B semantics corrected: upstream parse_args_recurse resumes OUTER-argv
    // option parsing after a payload ends — a mask spliced inside the payload
    // could be mounted over by trailing outer options (verified on bwrap
    // 0.12.0). The mask therefore always lands at the OUTER setup end: after
    // the --args fd token's expansion, i.e. after every payload mount.
    const payloadFile = join(r.root, "args-payload");
    writeFileSync(
      payloadFile,
      "--ro-bind\0/\0/\0--bind\0/proc\0/proc\0--\0/usr/bin/true\0",
    );
    const argsFd = openSync(payloadFile, "r");
    try {
      const res = spawnSync(SHIM, ["--args", "3", "--unshare-pid"], {
        env: r.env(),
        encoding: "utf8",
        stdio: ["ignore", "pipe", "pipe", argsFd],
      });
      expect(res.status, res.stderr).toBe(0);
      const { args, payload } = r.read();
      // Payload passes through verbatim; the mask is the outer-argv tail.
      expect(payload).toEqual([
        "--ro-bind", "/", "/", "--bind", "/proc", "/proc", "--", "/usr/bin/true",
      ]);
      expect(args).toEqual([
        "--add-seccomp-fd",
        expect.stringMatching(/^\d+$/),
        "--args",
        expect.stringMatching(/^\d+$/),
        "--unshare-pid",
        "--proc", "/proc",
      ]);
    } finally {
      cleanup();
    }
  });

  it("no -- and no --args: the mask lands before the first non-option token", () => {
    const r = root();
    try {
      const res = spawnSync(
        SHIM,
        ["--unshare-user", "--unshare-pid", "--chdir", "/", "/usr/bin/true"],
        { env: r.env(), encoding: "utf8" },
      );
      expect(res.status, res.stderr).toBe(0);
      const { args } = r.read();
      expect(args).toEqual([
        "--add-seccomp-fd",
        expect.stringMatching(/^\d+$/),
        "--unshare-user",
        "--unshare-pid",
        "--chdir", "/",
        "--proc", "/proc",
        "/usr/bin/true",
      ]);
    } finally {
      cleanup();
    }
  });

  it("an unreadable --args fd fails closed (exit 65 + marker)", () => {
    const r = root();
    try {
      // fd 9 is never opened — the payload read must refuse, never exec
      // an unmasked spawn.
      const res = spawnSync(SHIM, ["--args", "9", "--unshare-pid", "--", "/usr/bin/true"], {
        env: r.env(),
        encoding: "utf8",
      });
      expect(res.status).toBe(65);
      expect(res.stderr).toContain("bwrap-shim:");
    } finally {
      cleanup();
    }
  });

  it("an EMPTY --args payload fails closed — a silent re-emit would drop the whole setup argv", () => {
    const r = root();
    const payloadFile = join(r.root, "args-payload");
    writeFileSync(payloadFile, ""); // empty — never a real setup argv
    const argsFd = openSync(payloadFile, "r");
    try {
      const res = spawnSync(SHIM, ["--args", "3", "--unshare-pid", "--", "/usr/bin/true"], {
        env: r.env(),
        encoding: "utf8",
        stdio: ["ignore", "pipe", "pipe", argsFd],
      });
      expect(res.status).toBe(65);
      expect(res.stderr).toContain("bwrap-shim:");
      expect(res.stderr).toContain("empty --args payload");
    } finally {
      cleanup();
    }
  });

  it("a write-only --args fd fails closed — mapfile reports no error on O_WRONLY, so the empty check must trip", () => {
    const r = root();
    const payloadFile = join(r.root, "args-payload");
    writeFileSync(payloadFile, "--unshare-user\0");
    const argsFd = openSync(payloadFile, "w"); // write-only: read yields EOF/empty
    try {
      const res = spawnSync(SHIM, ["--args", "3", "--unshare-pid", "--", "/usr/bin/true"], {
        env: r.env(),
        encoding: "utf8",
        stdio: ["ignore", "pipe", "pipe", argsFd],
      });
      expect(res.status).toBe(65);
      expect(res.stderr).toContain("bwrap-shim:");
    } finally {
      cleanup();
    }
  });

  it("Arm C ordering: setup options AFTER an --args token still precede the mask (merged-stream position)", () => {
    const r = root();
    // `bwrap --args FD --bind /proc /proc cmd`: the payload is setup, the
    // trailing outer --bind is the vendor tail — the mask must land AFTER it
    // (before the operand), never inside the earlier payload.
    const payloadFile = join(r.root, "args-payload");
    writeFileSync(payloadFile, "--unshare-user\0");
    const argsFd = openSync(payloadFile, "r");
    try {
      const res = spawnSync(
        SHIM,
        ["--args", "3", "--unshare-pid", "--bind", "/proc", "/proc", "/usr/bin/true"],
        { env: r.env(), encoding: "utf8", stdio: ["ignore", "pipe", "pipe", argsFd] },
      );
      expect(res.status, res.stderr).toBe(0);
      const { args, payload } = r.read();
      expect(payload).toEqual(["--unshare-user"]);
      expect(args.slice(4)).toEqual([
        "--unshare-pid",
        "--bind", "/proc", "/proc",
        "--proc", "/proc",
        "/usr/bin/true",
      ]);
    } finally {
      cleanup();
    }
  });

  it("a payload's own operand (no inner --): the mask lands at the outer argv tail, payload verbatim", () => {
    const r = root();
    // `bwrap --args FD` alone, payload carrying setup + bare command operand.
    const payloadFile = join(r.root, "args-payload");
    writeFileSync(payloadFile, "--ro-bind\0/\0/\0/usr/bin/true\0");
    const argsFd = openSync(payloadFile, "r");
    try {
      const res = spawnSync(SHIM, ["--args", "3", "--unshare-pid"], {
        env: r.env(),
        encoding: "utf8",
        stdio: ["ignore", "pipe", "pipe", argsFd],
      });
      expect(res.status, res.stderr).toBe(0);
      const { args, payload } = r.read();
      expect(payload).toEqual(["--ro-bind", "/", "/", "/usr/bin/true"]);
      expect(args.slice(4)).toEqual(["--unshare-pid", "--proc", "/proc"]);
    } finally {
      cleanup();
    }
  });

  it("a `--` in an option-VALUE position is not the boundary (`--setenv K --`)", () => {
    const r = root();
    try {
      const res = spawnSync(
        SHIM,
        ["--unshare-user", "--unshare-pid", "--setenv", "MARK", "--", "--", "/usr/bin/true"],
        { env: r.env(), encoding: "utf8" },
      );
      expect(res.status, res.stderr).toBe(0);
      const { args } = r.read();
      // The real boundary is the SECOND `--` — the mask splices there, not
      // into the middle of --setenv's operands.
      expect(args.slice(2)).toEqual([
        "--unshare-user", "--unshare-pid", "--setenv", "MARK", "--",
        "--proc", "/proc",
        "--", "/usr/bin/true",
      ]);
    } finally {
      cleanup();
    }
  });

  it("a zero-arg option never consumes the boundary as a value (--level-prefix then --)", () => {
    const r = root();
    try {
      // --level-prefix is zero-arg (bwrap(1): "Prepend e.g. <3> to diagnostic
      // messages"); an arity-table error that gives it an operand swallows the
      // `--`, pushing the mask INTO the command argv — a silent unmask.
      const res = spawnSync(
        SHIM,
        ["--unshare-pid", "--level-prefix", "--", "/usr/bin/true"],
        { env: r.env(), encoding: "utf8" },
      );
      expect(res.status, res.stderr).toBe(0);
      const { args } = r.read();
      const bi = args.indexOf("--");
      expect(args.slice(bi - 2, bi)).toEqual(["--proc", "/proc"]);
      expect(args[bi + 1]).toBe("/usr/bin/true");
    } finally {
      cleanup();
    }
  });

  it("a setup argv with NO option-position --unshare-pid refuses (a fresh --proc without a pidns is a decorative mask)", () => {
    const r = root();
    try {
      const res = spawnSync(SHIM, ["--unshare-user", "--ro-bind", "/", "/", "--", "/usr/bin/true"], {
        env: r.env(), encoding: "utf8",
      });
      expect(res.status).toBe(65);
      expect(res.stderr).toContain("bwrap-shim:");
      expect(res.stderr).toContain("unshare-pid");
    } finally {
      cleanup();
    }
  });

  it("a `--unshare-pid` token in an option-VALUE position does NOT satisfy the pidns requirement (spoof-proof)", () => {
    const r = root();
    try {
      // `--setenv K --unshare-pid` puts the flag name in an a2 value slot —
      // real bwrap mounts no pidns, so the mask would be decorative; refuse.
      const res = spawnSync(SHIM, ["--unshare-user", "--setenv", "K", "--unshare-pid", "--", "/usr/bin/true"], {
        env: r.env(), encoding: "utf8",
      });
      expect(res.status).toBe(65);
      expect(res.stderr).toContain("unshare-pid");
    } finally {
      cleanup();
    }
  });

  it("a `/proc/self/fd/N` path inside a PAYLOAD's command tokens IS preserved", () => {
    const r = root();
    const fdFile = join(r.root, "cmd-fd");
    writeFileSync(fdFile, "cmd side fd");
    const cmdFd = openSync(fdFile, "r"); // child fd 4
    const payloadFile = join(r.root, "args-payload");
    writeFileSync(payloadFile, "--ro-bind\0/\0/\0--\0/proc/self/fd/4\0--version\0");
    const argsFd = openSync(payloadFile, "r"); // child fd 3
    try {
      const res = spawnSync(SHIM, ["--args", "3", "--unshare-pid"], {
        env: r.env(),
        encoding: "utf8",
        stdio: ["ignore", "pipe", "pipe", argsFd, cmdFd],
      });
      expect(res.status, res.stderr).toBe(0);
      const { fds, payload } = r.read();
      expect(fds.get("4")).toBe(fdFile);
      expect(payload.slice(payload.indexOf("--"))).toEqual([
        "--", "/proc/self/fd/4", "--version",
      ]);
    } finally {
      cleanup();
    }
  });

  it("a `/proc/self/fd/N` path in SETUP position is NOT preserved (command-side scan only)", () => {
    const r = root();
    const fdFile = join(r.root, "setup-fd");
    writeFileSync(fdFile, "setup side fd");
    const setupFd = openSync(fdFile, "r"); // child fd 4 — an option-position
    // path ref must not pin it (over-preserve is the leak direction).
    try {
      const res = spawnSync(
        SHIM,
        ["--unshare-pid", "--ro-bind", "/proc/self/fd/4", "/mnt/x", "--", "/usr/bin/true"],
        { env: r.env(), encoding: "utf8", stdio: ["ignore", "pipe", "pipe", "ignore", setupFd] },
      );
      expect(res.status, res.stderr).toBe(0);
      const { fds } = r.read();
      expect(fds.get("4")).not.toBe(fdFile);
    } finally {
      cleanup();
    }
  });

  it("fails closed with a marker when the seccomp artifact is missing", () => {
    const r = root();
    try {
      const res = spawnSync(SHIM, ["--unshare-user", "--unshare-pid", "--", "/usr/bin/true"], {
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
      const res = spawnSync(SHIM, ["--unshare-user", "--unshare-pid", "--", "/usr/bin/true"], {
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

// The boot self-probe (server/agent-runner-sandbox-config.ts ›
// probeAgentSandboxHardening) is a pure env-driven measurement — assert its
// verdict logic against real files, no module mocks.
const probeDirs: string[] = [];
function fakePathDir(kind: "shim" | "plain" | "none") {
  const dir = mkdtempSync(join(tmpdir(), "bwrap-probe-path-"));
  probeDirs.push(dir);
  if (kind !== "none") {
    const p = join(dir, "bwrap");
    writeFileSync(
      p,
      kind === "shim"
        ? '#!/usr/bin/env bash\nfail() { printf \'bwrap-shim: %s\\n\' "$1" >&2; exit 65; }\n'
        : "#!/usr/bin/env bash\nexec /usr/bin/true\n",
      { mode: 0o700 },
    );
  }
  return dir;
}
afterEach(() => {
  while (probeDirs.length) rmSync(probeDirs.pop()!, { recursive: true, force: true });
});

describe("probeAgentSandboxHardening — boot self-check verdicts", () => {
  let mod: typeof import("@/server/agent-runner-sandbox-config");
  const load = async () => {
    mod ??= await import("@/server/agent-runner-sandbox-config");
    return mod;
  };

  it("shim on PATH + shaped artifact ⇒ ok", async () => {
    const { probeAgentSandboxHardening } = await load();
    const dir = fakePathDir("shim");
    const p = probeAgentSandboxHardening({ PATH: dir, SOLEUR_BWRAP_SECCOMP_BPF: BPF });
    expect(p).toMatchObject({ shim: true, filter: true, ok: true, bpfBytes: 128 });
    expect(p.bwrapPath).toBe(join(dir, "bwrap"));
  });

  it("a non-shim bwrap first on PATH ⇒ shim:false, ok:false", async () => {
    const { probeAgentSandboxHardening } = await load();
    const p = probeAgentSandboxHardening({ PATH: fakePathDir("plain"), SOLEUR_BWRAP_SECCOMP_BPF: BPF });
    expect(p).toMatchObject({ shim: false, ok: false });
  });

  it("no bwrap on PATH ⇒ bwrapPath:null, ok:false", async () => {
    const { probeAgentSandboxHardening } = await load();
    const p = probeAgentSandboxHardening({ PATH: fakePathDir("none"), SOLEUR_BWRAP_SECCOMP_BPF: BPF });
    expect(p.bwrapPath).toBeNull();
    expect(p.ok).toBe(false);
  });

  it("missing or mis-shaped artifact ⇒ filter:false", async () => {
    const { probeAgentSandboxHardening } = await load();
    const dir = fakePathDir("shim");
    const missing = probeAgentSandboxHardening({ PATH: dir, SOLEUR_BWRAP_SECCOMP_BPF: join(dir, "absent.bpf") });
    expect(missing).toMatchObject({ filter: false, ok: false, bpfBytes: 0 });
    const bad = join(dir, "bad.bpf");
    writeFileSync(bad, Buffer.alloc(7)); // not a multiple of 8
    const misshapen = probeAgentSandboxHardening({ PATH: dir, SOLEUR_BWRAP_SECCOMP_BPF: bad });
    expect(misshapen).toMatchObject({ filter: false, ok: false });
  });
});

// The emit fork is the only un-pure edge: ok → pino info + Sentry info (the
// WARN-only Better Stack ship needs the Sentry line); !ok →
// warnSilentFallback. A swapped or dropped branch would page on every boot
// or silently lose the feature's only runtime tripwire.
describe("verifyAgentSandboxHardening — emit fork", () => {
  beforeEach(() => vi.clearAllMocks());
  afterEach(() => vi.unstubAllEnvs());

  it("ok ⇒ info emit (log + Sentry info), no warn", async () => {
    const { verifyAgentSandboxHardening } = await import("@/server/agent-runner-sandbox-config");
    vi.stubEnv("PATH", fakePathDir("shim"));
    vi.stubEnv("SOLEUR_BWRAP_SECCOMP_BPF", BPF);
    verifyAgentSandboxHardening();
    expect(childLog.info).toHaveBeenCalledWith(
      expect.objectContaining({ feature: "agent-sandbox", op: "sandbox-hardening-selfprobe" }),
      expect.any(String),
    );
    expect(sentry.captureMessage).toHaveBeenCalledWith(
      expect.stringContaining("hardening probe ok"),
      expect.objectContaining({ level: "info" }),
    );
    expect(obs.warnSilentFallback).not.toHaveBeenCalled();
  });

  it("broken pair ⇒ warnSilentFallback with the feature/op tags", async () => {
    const { verifyAgentSandboxHardening } = await import("@/server/agent-runner-sandbox-config");
    vi.stubEnv("PATH", fakePathDir("none"));
    vi.stubEnv("SOLEUR_BWRAP_SECCOMP_BPF", BPF);
    verifyAgentSandboxHardening();
    expect(obs.warnSilentFallback).toHaveBeenCalledTimes(1);
    expect(obs.warnSilentFallback.mock.calls[0][1]).toMatchObject({
      feature: "agent-sandbox",
      op: "sandbox-hardening-selfprobe",
    });
    expect(childLog.info).not.toHaveBeenCalled();
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
    const env: NodeJS.ProcessEnv = {
      NODE_ENV: "test",
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
    // Positive control: the same payload WITHOUT the shim must succeed —
    // else the deny below is unattributable (host-side denial greens a
    // vacuous row).
    const unfiltered = spawnSync("/usr/bin/bwrap", [...argv, "/usr/bin/unshare", "-U", "/usr/bin/true"], { encoding: "utf8", timeout: 30_000 });
    expect(unfiltered.status, `unfiltered control stderr=${unfiltered.stderr}`).toBe(0);
    const denied = spawnSync(SHIM, ["--unshare-pid", ...argv, "/usr/bin/unshare", "-U", "/usr/bin/true"], { env, encoding: "utf8", timeout: 30_000 });
    expect(denied.status).not.toBe(0);
    expect(String(denied.stderr)).not.toContain("bwrap:");
    expect(String(denied.stderr)).toMatch(/Operation not permitted/);
    const ok = spawnSync(SHIM, ["--unshare-pid", ...argv, "/usr/bin/sh", "-c", "/usr/bin/true"], { env, encoding: "utf8", timeout: 30_000 });
    expect(ok.status, String(ok.stderr)).toBe(0);
  }, 60_000);

  it("#9723: the vendor's tail --bind /proc /proc is re-masked — in-sandbox /proc is pidns-scoped, not host", () => {
    const env: NodeJS.ProcessEnv = {
      NODE_ENV: "test",
      PATH: process.env.PATH ?? "/usr/bin:/bin",
      SOLEUR_BWRAP_REAL: "/usr/bin/bwrap",
      SOLEUR_BWRAP_SECCOMP_BPF: BPF,
    };
    // The vendor shape: setup argv on --args <fd>, ending with the
    // enableWeakerNestedSandbox tail bind that shadows the denyRead tmpfs.
    const payload =
      "--unshare-user\0--unshare-pid\0--unshare-net\0" +
      "--ro-bind\0/\0/\0--tmpfs\0/proc\0--bind\0/proc\0/proc\0";
    const argsFile = join(mkdtempSync(join(tmpdir(), "shim-proc-")), "payload");
    writeFileSync(argsFile, payload);
    try {
      // Probe: the shim's tail `--proc /proc` mounts a procfs keyed to the
      // sandbox's OWN pidns — this worker's host pid must be ABSENT, while
      // the self-view (environ, fd) stays intact for `apply-seccomp
      // /proc/self/fd/N` et al.
      const probe = `test ! -d /proc/${process.pid} && test -e /proc/self/environ && test -d /proc/self/fd`;
      const throughShim = spawnSync(SHIM, ["--args", "3", "--unshare-pid", "--", "/usr/bin/sh", "-c", probe], {
        env,
        encoding: "utf8",
        timeout: 30_000,
        stdio: ["ignore", "pipe", "pipe", openSync(argsFile, "r")],
      });
      expect(throughShim.status, String(throughShim.stderr)).toBe(0);

      // CONTROL: the same argv through the REAL binary keeps the defect —
      // the tail bind exposes real procfs (this worker's host pid is a dir).
      const control = spawnSync(
        "/usr/bin/bwrap",
        ["--args", "3", "--", "/usr/bin/sh", "-c", `test -d /proc/${process.pid}`],
        { env, encoding: "utf8", timeout: 30_000, stdio: ["ignore", "pipe", "pipe", openSync(argsFile, "r")] },
      );
      expect(control.status, `control must see host procfs (the defect): ${control.stderr}`).toBe(0);
    } finally {
      rmSync(dirname(argsFile), { recursive: true, force: true });
    }
  }, 60_000);
});

// Deploy-probe live rows: drive the canary's runHardeningProbes +
// runArgsFdTransportProbe through THIS shim + REAL bwrap — the functions are
// exported for exactly this (verifying the census bound, the deliberate-leak
// fd, and the child-fd-index `--args` contract against a real kernel).
describe.skipIf(!BWRAP_OK)("canary hardening probes end-to-end (real bwrap + this shim)", () => {
  it("runHardeningProbes + runArgsFdTransportProbe return null through the shim", async () => {
    const dir = mkdtempSync(join(tmpdir(), "bwrap-probe-e2e-"));
    symlinkSync(SHIM, join(dir, "bwrap"));
    const saved = {
      PATH: process.env.PATH,
      REAL: process.env.SOLEUR_BWRAP_REAL,
      BPF: process.env.SOLEUR_BWRAP_SECCOMP_BPF,
    };
    vi.stubEnv("PATH", `${dir}:${process.env.PATH ?? "/usr/bin:/bin"}`);
    vi.stubEnv("SOLEUR_BWRAP_REAL", "/usr/bin/bwrap");
    vi.stubEnv("SOLEUR_BWRAP_SECCOMP_BPF", BPF);
    try {
      const canary = await import("../scripts/sandbox-canary.mjs");
      // Same shape as the committed fixture: root ro-bind + proc + pidns.
      const setupArgv = [
        "--unshare-user", "--unshare-pid", "--unshare-net",
        "--ro-bind", "/", "/",
        "--dev", "/dev", "--proc", "/proc", "--tmpfs", "/tmp",
      ];
      expect(canary.runHardeningProbes(setupArgv)).toBeNull();
      expect(canary.runArgsFdTransportProbe(setupArgv)).toBeNull();
    } finally {
      vi.unstubAllEnvs();
      if (saved.PATH !== undefined) vi.stubEnv("PATH", saved.PATH);
      rmSync(dir, { recursive: true, force: true });
    }
  }, 60_000);
});
