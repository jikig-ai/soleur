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
  closeSync,
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
const BPF_UNIXDENY = join(APP_ROOT, "infra/bwrap-userns-clone3-unixdeny.bpf");

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
      // The vendored tail bind is what engages the mask — include it.
      const res = spawnSync(SHIM, ["--unshare-user", "--unshare-pid", "--ro-bind", "/", "/", "--bind", "/proc", "/proc", "--", "/usr/bin/true"], {
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
      // #10032: the tail bind is dropped, never re-masked with --proc; the
      // argv carried no --tmpfs /proc so the shim appends the realized mask.
      expect(args.slice(2)).toEqual(["--unshare-user", "--unshare-pid", "--ro-bind", "/", "/", "--tmpfs", "/proc", "--", "/usr/bin/true"]);
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
      const res = spawnSync(SHIM, ["--args", "3", "--unshare-user", "--unshare-pid", "--bind", "/proc", "/proc"], {
        env: r.env(),
        encoding: "utf8",
        stdio: ["ignore", "pipe", "pipe", argsFd],
      });
      expect(res.status, res.stderr).toBe(0);
      const { args, fds, payload } = r.read();
      // #9723: the payload is consumed and re-emitted verbatim on a FRESH fd
      // (the original fd 3 is read to EOF and closed). #10032: the outer tail
      // `--bind /proc /proc` is dropped (selective re-emit); with no `--tmpfs
      // /proc` anywhere in the merged stream the shim appends the realized
      // tmpfs mask at the OUTER argv tail — outer options after an --args
      // token parse after the payload, so the outer end is always the last
      // setup position of the merged stream.
      expect(args[0]).toBe("--add-seccomp-fd");
      expect(args[1]).toMatch(/^\d+$/);
      expect(args[2]).toBe("--args");
      const renumFd = args[3];
      expect(renumFd).toMatch(/^\d+$/);
      expect(fds.has(renumFd)).toBe(true); // the re-emitted payload fd survives
      expect(payload).toEqual(["--unshare-user", "--unshare-pid", "--", "/usr/bin/true"]);
      expect(args.slice(4)).toEqual(["--unshare-user", "--unshare-pid", "--tmpfs", "/proc"]);
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
      const res = spawnSync(SHIM, [...argv, "--args", String(3 + OPTS.length), "--unshare-user", "--unshare-pid", "--bind", "/proc", "/proc", "--", "/usr/bin/true"], {
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
      // The appended mask lands at the OUTER setup end (before `--`), not
      // inside the re-emitted payload — outer options parse after the
      // payload regardless. The outer tail bind is dropped.
      expect(payload).toEqual(["--ro-bind", "/", "/", "--", "/usr/bin/true"]);
      const bi = args.indexOf("--");
      expect(args.slice(bi - 2, bi)).toEqual(["--tmpfs", "/proc"]);
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

  it("a `/proc/self/fd/N` path inside a command token IS preserved AND re-homed (apply-seccomp contract)", () => {
    const r = root();
    const helper = join(r.root, "helper-binary");
    writeFileSync(helper, "x");
    const helperFd = openSync(helper, "r"); // child fd 3
    try {
      // The vendored inner command execs its own binary through
      // `/proc/self/fd/3` (apply-seccomp multicall dispatch — see the command
      // tail the SDK emits). The fd is named by PATH inside a command token,
      // never by an option — the sweep must still preserve it, else the
      // sandboxed spawn dies on exec (ENOENT). #10032: under the tmpfs mask
      // there is no real procfs for the path to resolve through, so the shim
      // additionally binds the fd's resolved source AT the literal path —
      // `--ro-bind <helper> /proc/self/fd/3` at the last setup position,
      // after an appended `--tmpfs /proc` when the stream carries no mask.
      const res = spawnSync(
        SHIM,
        ["--unshare-user", "--unshare-pid", "--ro-bind", "/usr", "/usr", "--", "/bin/sh", "-c", "exec /proc/self/fd/3 arg"],
        { env: r.env(), encoding: "utf8", stdio: ["ignore", "pipe", "pipe", helperFd] },
      );
      expect(res.status, res.stderr).toBe(0);
      const { args, fds } = r.read();
      expect([...fds.values()]).toContain(helper);
      const bi = args.indexOf("--");
      expect(args.slice(2, bi)).toEqual([
        "--unshare-user", "--unshare-pid", "--ro-bind", "/usr", "/usr",
        "--tmpfs", "/proc",
        "--ro-bind", helper, "/proc/self/fd/3",
      ]);
      expect(args.slice(bi)).toEqual(["--", "/bin/sh", "-c", "exec /proc/self/fd/3 arg"]);
    } finally {
      cleanup();
    }
  });

  it("drops the vendor tail bind and emits NO procfs mount at /proc (plain setup argv)", () => {
    // #9723 — the vendored builder's enableWeakerNestedSandbox handling ends the
    // setup argv with `--bind /proc /proc`, re-mounting real procfs over the
    // denyRead `--tmpfs /proc` (later mounts win). #10032 — the #9723 `--proc`
    // splice itself EPERMs under docker's masked /proc, so the realization
    // changes: the tail bind (and any other procfs mount at /proc) is DROPPED
    // from the merged stream and `--proc` is never emitted. A `--tmpfs /proc`
    // is appended at the last setup position only when the stream carries no
    // mask of its own.
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
        "--tmpfs", "/proc",
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
        ["--unshare-user", "--unshare-pid", "--ro-bind", "/", "/", "--bind", "/proc", "/proc", "--", "/bin/sh", "-c", "x", "--"],
        { env: r.env(), encoding: "utf8" },
      );
      expect(res.status, res.stderr).toBe(0);
      const { args } = r.read();
      const boundary = args.indexOf("--");
      expect(boundary).toBeGreaterThan(0);
      expect(args.slice(boundary - 2, boundary)).toEqual(["--tmpfs", "/proc"]);
      // The command tail is passed through verbatim — including its own `--`.
      expect(args.slice(boundary + 1)).toEqual(["/bin/sh", "-c", "x", "--"]);
    } finally {
      cleanup();
    }
  });

  it("the --args transport (SDK shape): payload tail bind dropped on re-emit, stream mask survives", () => {
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
      // #10032: payload re-emit is SELECTIVE — the payload's own tail bind is
      // dropped; the denyRead `--tmpfs /proc` inside the payload survives and
      // IS the realized mask (so no outer --tmpfs append, and never --proc).
      expect(payload).toEqual([
        "--unshare-user", "--tmpfs", "/proc", "--ro-bind", "/", "/",
      ]);
      const argsIdx = args.indexOf("--args");
      const boundary = args.indexOf("--");
      expect(argsIdx).toBe(2); // [--add-seccomp-fd, N, --args, M, ...]
      expect(args.slice(argsIdx + 2, boundary)).toEqual(["--unshare-pid"]);
      expect(args).not.toContain("--proc");
    } finally {
      cleanup();
    }
  });

  it("a -- carried INSIDE the --args payload: exposure still dropped, mask emitted at the OUTER setup end", () => {
    const r = root();
    // Arm B semantics: upstream parse_args_recurse resumes OUTER-argv
    // option parsing after a payload ends — so a payload-internal tail bind
    // is still a merged-stream exposure (and the appended mask must land at
    // the outer end, after every payload mount).
    const payloadFile = join(r.root, "args-payload");
    writeFileSync(
      payloadFile,
      "--ro-bind\0/\0/\0--bind\0/proc\0/proc\0--\0/usr/bin/true\0",
    );
    const argsFd = openSync(payloadFile, "r");
    try {
      const res = spawnSync(SHIM, ["--args", "3", "--unshare-user", "--unshare-pid"], {
        env: r.env(),
        encoding: "utf8",
        stdio: ["ignore", "pipe", "pipe", argsFd],
      });
      expect(res.status, res.stderr).toBe(0);
      const { args, payload } = r.read();
      // The payload's tail bind is dropped on re-emit; its `--` boundary and
      // command pass through. With no tmpfs mask anywhere in the merged
      // stream, the shim appends one at the outer setup end.
      expect(payload).toEqual([
        "--ro-bind", "/", "/", "--", "/usr/bin/true",
      ]);
      expect(args).toEqual([
        "--add-seccomp-fd",
        expect.stringMatching(/^\d+$/),
        "--args",
        expect.stringMatching(/^\d+$/),
        "--unshare-user",
        "--unshare-pid",
        "--tmpfs", "/proc",
      ]);
    } finally {
      cleanup();
    }
  });

  it("no -- and no --args: the appended mask lands before the first non-option token", () => {
    const r = root();
    try {
      const res = spawnSync(
        SHIM,
        ["--unshare-user", "--unshare-pid", "--bind", "/proc", "/proc", "--chdir", "/", "/usr/bin/true"],
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
        "--tmpfs", "/proc",
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
      // The trailing outer tail bind is dropped; the appended tmpfs mask
      // lands at the last setup position — immediately before the operand.
      expect(args.slice(4)).toEqual([
        "--unshare-pid",
        "--tmpfs", "/proc",
        "/usr/bin/true",
      ]);
    } finally {
      cleanup();
    }
  });

  it("a payload's own operand (no inner --): the payload's tail bind is dropped, mask lands at the outer argv tail", () => {
    const r = root();
    // `bwrap --args FD` alone, payload carrying setup + bare command operand.
    const payloadFile = join(r.root, "args-payload");
    writeFileSync(payloadFile, "--ro-bind\0/\0/\0--bind\0/proc\0/proc\0/usr/bin/true\0");
    const argsFd = openSync(payloadFile, "r");
    try {
      const res = spawnSync(SHIM, ["--args", "3", "--unshare-user", "--unshare-pid"], {
        env: r.env(),
        encoding: "utf8",
        stdio: ["ignore", "pipe", "pipe", argsFd],
      });
      expect(res.status, res.stderr).toBe(0);
      const { args, payload } = r.read();
      expect(payload).toEqual(["--ro-bind", "/", "/", "/usr/bin/true"]);
      expect(args.slice(4)).toEqual(["--unshare-user", "--unshare-pid", "--tmpfs", "/proc"]);
    } finally {
      cleanup();
    }
  });

  it("a `--` in an option-VALUE position is not the boundary (`--setenv K --`)", () => {
    const r = root();
    try {
      const res = spawnSync(
        SHIM,
        ["--unshare-user", "--unshare-pid", "--setenv", "MARK", "--", "--bind", "/proc", "/proc", "--", "/usr/bin/true"],
        { env: r.env(), encoding: "utf8" },
      );
      expect(res.status, res.stderr).toBe(0);
      const { args } = r.read();
      // The real boundary is the SECOND `--` — the appended mask lands there,
      // not into the middle of --setenv's operands; the tail bind is dropped.
      expect(args.slice(2)).toEqual([
        "--unshare-user", "--unshare-pid", "--setenv", "MARK", "--",
        "--tmpfs", "/proc",
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
        ["--unshare-user", "--unshare-pid", "--level-prefix", "--bind", "/proc", "/proc", "--", "/usr/bin/true"],
        { env: r.env(), encoding: "utf8" },
      );
      expect(res.status, res.stderr).toBe(0);
      const { args } = r.read();
      const bi = args.indexOf("--");
      expect(args.slice(bi - 2, bi)).toEqual(["--tmpfs", "/proc"]);
      expect(args[bi + 1]).toBe("/usr/bin/true");
    } finally {
      cleanup();
    }
  });

  it("an argv that never mounts procfs at /proc passes through UNMASKED — the ci-deploy canary probe shape (v0.330.10 rollback)", () => {
    const r = root();
    try {
      // The deploy gate's exact probe argv has --unshare-pid but NO
      // --unshare-user and mounts no procfs — on in-image bwrap 0.8.0 a
      // spliced `--proc /proc` EPERMs ("Can't mount proc on /newroot/proc"),
      // which is what rolled back the v0.330.10 deploy. No /proc exposure →
      // nothing to mask → verbatim passthrough (plus the shim's own
      // --add-seccomp-fd prepended at args[0..1]).
      const res = spawnSync(
        SHIM,
        ["--new-session", "--dev", "/dev", "--unshare-pid", "--bind", "/", "/", "--", "/usr/bin/true"],
        { env: r.env(), encoding: "utf8" },
      );
      expect(res.status, res.stderr).toBe(0);
      const { args } = r.read();
      expect(args).not.toContain("--proc");
      const bi = args.indexOf("--");
      expect(args.slice(2, bi)).toEqual([
        "--new-session", "--dev", "/dev", "--unshare-pid", "--bind", "/", "/",
      ]);
    } finally {
      cleanup();
    }
  });

  it("a /proc exposure with pidns but NO userns refuses — unprivileged bwrap cannot mount a fresh procfs", () => {
    const r = root();
    try {
      const res = spawnSync(
        SHIM,
        ["--unshare-pid", "--bind", "/proc", "/proc", "--", "/usr/bin/true"],
        { env: r.env(), encoding: "utf8" },
      );
      expect(res.status).toBe(65);
      expect(res.stderr).toContain("bwrap-shim:");
      expect(res.stderr).toContain("unshare-user");
    } finally {
      cleanup();
    }
  });

  it("an exposure token AFTER the command boundary is not a trigger — setup-only scan", () => {
    const r = root();
    try {
      // The user command legitimately names /proc paths; a setup-scan that
      // ran past the boundary would splice a mask into this argv for no
      // reason (and on a userns-less argv, refuse a spawn that never exposed
      // procfs at all).
      const res = spawnSync(
        SHIM,
        ["--unshare-pid", "--bind", "/", "/", "--", "/bin/sh", "-c", "x", "--bind", "/proc", "/proc"],
        { env: r.env(), encoding: "utf8" },
      );
      expect(res.status, res.stderr).toBe(0);
      const { args } = r.read();
      const bi = args.indexOf("--");
      expect(args.slice(2, bi)).toEqual(["--unshare-pid", "--bind", "/", "/"]);
      expect(args.slice(bi + 1)).toEqual(["/bin/sh", "-c", "x", "--bind", "/proc", "/proc"]);
      expect(args.slice(2, bi)).not.toContain("--proc");
    } finally {
      cleanup();
    }
  });

  it("dest matching is exact-with-trailing-slash normalization — /procfoo does NOT trigger, /proc/ DOES", () => {
    const r = root();
    try {
      // Near-miss dest: not a procfs mount at /proc → passthrough.
      const near = spawnSync(
        SHIM,
        ["--unshare-user", "--unshare-pid", "--bind", "/proc", "/procfoo", "--", "/usr/bin/true"],
        { env: r.env(), encoding: "utf8" },
      );
      expect(near.status, near.stderr).toBe(0);
      const { args: nearArgs } = r.read();
      expect(nearArgs).not.toContain("--proc");

      // Trailing slash normalizes — a bind AT /proc/ is still an exposure and
      // gets dropped (the appended tmpfs mask lands before the boundary).
      const r2 = root();
      try {
        const slash = spawnSync(
          SHIM,
          ["--unshare-user", "--unshare-pid", "--bind", "/proc/", "/proc/", "--", "/usr/bin/true"],
          { env: r2.env(), encoding: "utf8" },
        );
        expect(slash.status, slash.stderr).toBe(0);
        const { args: slashArgs } = r2.read();
        const bi = slashArgs.indexOf("--");
        expect(slashArgs.slice(bi - 2, bi)).toEqual(["--tmpfs", "/proc"]);
        expect(slashArgs).not.toContain("--bind");
      } finally {
        cleanup();
      }
    } finally {
      cleanup();
    }
  });

  it("every procfs-exposing option shape is dropped — --bind-try, --ro-bind, --dev-bind, --proc", () => {
    for (const argv of [
      ["--unshare-user", "--unshare-pid", "--bind-try", "/proc", "/proc"],
      ["--unshare-user", "--unshare-pid", "--ro-bind", "/proc", "/proc"],
      ["--unshare-user", "--unshare-pid", "--dev-bind", "/proc", "/proc"],
      ["--unshare-user", "--unshare-pid", "--proc", "/proc"],
    ]) {
      const r = root();
      try {
        const res = spawnSync(SHIM, [...argv, "--", "/usr/bin/true"], {
          env: r.env(), encoding: "utf8",
        });
        expect(res.status, `${argv[4]}: ${res.stderr}`).toBe(0);
        const { args } = r.read();
        const bi = args.indexOf("--");
        // The exposure is dropped and the appended tmpfs mask lands before
        // the boundary — the emitted stream NEVER carries --proc.
        expect(args.slice(bi - 2, bi), `${argv[4]} should be neutralized`).toEqual(["--tmpfs", "/proc"]);
        expect(args, `${argv[4]} must not emit --proc`).not.toContain("--proc");
      } finally {
        cleanup();
      }
    }
  });

  it("--bind-fd/--ro-bind-fd DEST=/proc is the same exposure class (fd2 dest check)", () => {
    for (const opt of ["--bind-fd", "--ro-bind-fd"]) {
      const r = root();
      const procFd = openSync("/proc", "r", 0o40000); // O_DIRECTORY
      try {
        const res = spawnSync(SHIM, ["--unshare-user", "--unshare-pid", opt, "3", "/proc", "--", "/usr/bin/true"], {
          env: r.env(), encoding: "utf8",
          stdio: ["ignore", "pipe", "pipe", procFd],
        });
        expect(res.status, `${opt}: ${res.stderr}`).toBe(0);
        const { args, fds } = r.read();
        const bi = args.indexOf("--");
        expect(args.slice(bi - 2, bi), `${opt} dest=/proc must be neutralized`).toEqual(["--tmpfs", "/proc"]);
        expect(args).not.toContain(opt);
        // R1 (#10032 review): the dropped mount's fd has no surviving
        // consumer — it must NOT survive the sweep either. An O_PATH procfs
        // dirfd riding into the sandbox is an openat read channel that
        // unmasks what the drop just masked. (Discriminate on the TARGET:
        // the stub's own glob iteration lands a transient dirfd on whatever
        // low fd is free, resolving to empty — presence alone false-flags.)
        expect(fds.get("3"), `${opt}: dropped procfs fd must be swept`).not.toBe("/proc");
      } finally {
        closeSync(procFd);
        cleanup();
      }
    }
  });

  it("an a3 option (--overlay) before an exposure does not desync the filter — review C1/a3-stride", () => {
    const r = mkRoot();
    try {
      // --overlay consumes 4 tokens; a 3-stride mis-walks its third value as
      // an operand and copies the rest verbatim — including the tail bind.
      const res = spawnSync(SHIM, [
        "--unshare-user", "--unshare-pid",
        "--overlay", "/a", "/b", "/c",
        "--bind", "/proc", "/proc",
        "--", "/usr/bin/true",
      ], { env: r.env(), encoding: "utf8" });
      expect(res.status, String(res.stderr)).toBe(0);
      const { args } = r.read();
      expect(args).not.toContain("--bind");
      const bi = args.indexOf("--");
      expect(args.slice(bi - 2, bi)).toEqual(["--tmpfs", "/proc"]);
    } finally {
      cleanup();
    }
  });

  it("a payload carrying --bind-fd at /proc is neutralized AND its fd is swept", () => {
    const r = mkRoot();
    const plFile = join(mkdtempSync(join(tmpdir(), "shim-pl-")), "pl");
    // payload: --bind-fd 4 /proc (fd 4 = a /proc dirfd)
    const procFd = openSync("/proc", "r");
    writeFileSync(plFile, "--bind-fd\x004\x00/proc\x00--\x00/usr/bin/true\x00");
    const plFd = openSync(plFile, "r");
    try {
      const res = spawnSync(SHIM, ["--args", "3", "--unshare-user", "--unshare-pid"], {
        env: r.env(), encoding: "utf8",
        stdio: ["ignore", "pipe", "pipe", plFd, procFd],
      });
      expect(res.status, String(res.stderr)).toBe(0);
      const { payload, fds } = r.read();
      expect(payload).not.toContain("--bind-fd");
      expect(fds.get("4"), "dropped payload bind-fd's /proc dirfd must be swept").not.toBe("/proc");
    } finally {
      closeSync(plFd); closeSync(procFd); cleanup();
    }
  });

  it("a bind with a procfs SOURCE at a non-/proc dest is also exposure — dropped (security F3)", () => {
    const r = mkRoot();
    try {
      const res = spawnSync(SHIM, [
        "--unshare-user", "--unshare-pid",
        "--ro-bind", "/", "/",
        "--bind", "/proc", "/x",
        "--", "/usr/bin/true",
      ], { env: r.env(), encoding: "utf8" });
      expect(res.status, String(res.stderr)).toBe(0);
      const { args } = r.read();
      expect(args).not.toContain("--bind");
      const bi = args.indexOf("--");
      expect(args.slice(bi - 2, bi)).toEqual(["--tmpfs", "/proc"]);
    } finally {
      cleanup();
    }
  });

  it("a command-side ref to an fd that is NOT open skips re-home instead of refusing (mention-DoS, security F5)", () => {
    const r = mkRoot();
    try {
      const res = spawnSync(SHIM, [
        "--unshare-user", "--unshare-pid", "--ro-bind", "/", "/",
        "--", "/bin/sh", "-c", "cat /proc/self/fd/99 2>/dev/null || true",
      ], { env: r.env(), encoding: "utf8" });
      expect(res.status, String(res.stderr)).toBe(0);
      const { args } = r.read();
      // a non-open ref still triggers the rewrite arm (tmpfs mask emitted —
      // a real procfs ref can never resolve inside, so the mask is the
      // conservative realization) but no re-home mount is emitted.
      const bi = args.indexOf("--");
      expect(args.slice(bi - 2, bi)).toEqual(["--tmpfs", "/proc"]);
      // no /proc/self/fd/ mount token in the SETUP argv (the command's own
      // mention stays — it fails ENOENT inside, same as pre-#10032)
      expect(args.slice(0, bi).join(" ")).not.toContain("self/fd");
    } finally {
      cleanup();
    }
  });

  it("adjacent duplicate preserve entries collapse fully on bind-fd strip (review F2)", () => {
    const r = mkRoot();
    const procFd = openSync("/proc", "r");
    try {
      // fd 3 enters preserve twice: once via --sync-fd (surviving option),
      // once via the dropped --bind-fd 3 /proc. The strip is consumer-scoped
      // to the DROPPED option — but a same-number second preserve entry is
      // over-stripped (documented: loud EBADF direction, not a leak). The
      // pinned contract: the procfs dirfd never survives the sweep.
      const res = spawnSync(SHIM, [
        "--unshare-user", "--unshare-pid",
        "--sync-fd", "3", "--bind-fd", "3", "/proc",
        "--", "/usr/bin/true",
      ], { env: r.env(), encoding: "utf8", stdio: ["ignore", "pipe", "pipe", procFd] });
      expect(res.status, String(res.stderr)).toBe(0);
      const { fds } = r.read();
      expect(fds.get("3"), "the procfs dirfd must not reach the sandbox").not.toBe("/proc");
    } finally {
      closeSync(procFd); cleanup();
    }
  });

  it("an exposure in a payload AFTER a command-carrying payload still triggers the mask (resume semantics)", () => {
    const r = root();
    // Upstream parse_args_recurse resumes outer-argv option parsing after
    // EACH --args payload — a payload following one that carried `--` is
    // still SETUP, so its procfs bind must still be seen. (Regression: an
    // earlier consume loop stopped at the first command-carrying payload and
    // would have passed this shape through unmasked.)
    const p1 = join(r.root, "p1");
    const p2 = join(r.root, "p2");
    writeFileSync(p1, "--ro-bind\0/\0/\0--\0/usr/bin/true\0");
    writeFileSync(p2, "--bind\0/proc\0/proc\0");
    const fd1 = openSync(p1, "r"); // child fd 3
    const fd2 = openSync(p2, "r"); // child fd 4
    try {
      const res = spawnSync(
        SHIM,
        ["--unshare-user", "--unshare-pid", "--args", "3", "--args", "4"],
        { env: r.env(), encoding: "utf8", stdio: ["ignore", "pipe", "pipe", fd1, fd2] },
      );
      expect(res.status, res.stderr).toBe(0);
      const { args } = r.read();
      // The second payload's exposure was still seen and dropped; with no
      // mask anywhere the tmpfs append lands at the outer argv tail.
      expect(args.slice(-2)).toEqual(["--tmpfs", "/proc"]);
      expect(args).not.toContain("--proc");
    } finally {
      cleanup();
    }
  });

  it("dest canonicalization defeats slash/dot evasions — //proc, /proc//, /proc/./, /x/../proc all mount at /proc", () => {
    for (const dest of ["//proc", "/proc//", "/proc/./", "/x/../proc"]) {
      const r = root();
      try {
        const res = spawnSync(
          SHIM,
          ["--unshare-user", "--unshare-pid", "--bind", "/proc", dest, "--", "/usr/bin/true"],
          { env: r.env(), encoding: "utf8" },
        );
        expect(res.status, `dest=${dest}: ${res.stderr}`).toBe(0);
        const { args } = r.read();
        const bi = args.indexOf("--");
        expect(args.slice(bi - 2, bi), `dest=${dest} must be neutralized`).toEqual(["--tmpfs", "/proc"]);
      } finally {
        cleanup();
      }
    }
  });

  it("exposure inside a payload + no userns ANYWHERE in the merged stream refuses (union gate)", () => {
    const r = root();
    const payloadFile = join(r.root, "args-payload");
    writeFileSync(payloadFile, "--bind\0/proc\0/proc\0--\0/usr/bin/true\0");
    const argsFd = openSync(payloadFile, "r");
    try {
      const res = spawnSync(SHIM, ["--args", "3", "--unshare-pid"], {
        env: r.env(), encoding: "utf8", stdio: ["ignore", "pipe", "pipe", argsFd],
      });
      expect(res.status).toBe(65);
      expect(res.stderr).toContain("unshare-user");
    } finally {
      cleanup();
    }
  });

  it("--unshare-all satisfies BOTH namespace gates", () => {
    const r = root();
    try {
      const res = spawnSync(
        SHIM,
        ["--unshare-all", "--bind", "/proc", "/proc", "--", "/usr/bin/true"],
        { env: r.env(), encoding: "utf8" },
      );
      expect(res.status, res.stderr).toBe(0);
      const { args } = r.read();
      const bi = args.indexOf("--");
      expect(args.slice(bi - 2, bi)).toEqual(["--tmpfs", "/proc"]);
    } finally {
      cleanup();
    }
  });

  it("a bare --tmpfs /proc is a mask, not an exposure — passthrough with no splice", () => {
    const r = root();
    try {
      const res = spawnSync(
        SHIM,
        ["--unshare-user", "--unshare-pid", "--tmpfs", "/proc", "--", "/usr/bin/true"],
        { env: r.env(), encoding: "utf8" },
      );
      expect(res.status, res.stderr).toBe(0);
      const { args } = r.read();
      // One --proc pair at most — none here: the tmpfs deny stands alone.
      expect(args).not.toContain("--proc");
      const bi = args.indexOf("--");
      expect(args.slice(bi - 2, bi)).toEqual(["--tmpfs", "/proc"]);
    } finally {
      cleanup();
    }
  });

  it("a setup argv with NO option-position --unshare-pid refuses (a fresh --proc without a pidns is a decorative mask)", () => {
    const r = root();
    try {
      const res = spawnSync(SHIM, ["--unshare-user", "--ro-bind", "/", "/", "--bind", "/proc", "/proc", "--", "/usr/bin/true"], {
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
      const res = spawnSync(SHIM, ["--unshare-user", "--setenv", "K", "--unshare-pid", "--bind", "/proc", "/proc", "--", "/usr/bin/true"], {
        env: r.env(), encoding: "utf8",
      });
      expect(res.status).toBe(65);
      expect(res.stderr).toContain("unshare-pid");
    } finally {
      cleanup();
    }
  });

  it("a `/proc/self/fd/N` path inside a PAYLOAD's command tokens IS preserved AND re-homed", () => {
    const r = root();
    const fdFile = join(r.root, "cmd-fd");
    writeFileSync(fdFile, "cmd side fd");
    const cmdFd = openSync(fdFile, "r"); // child fd 4
    const payloadFile = join(r.root, "args-payload");
    writeFileSync(payloadFile, "--unshare-user\0--ro-bind\0/\0/\0--\0/proc/self/fd/4\0--version\0");
    const argsFd = openSync(payloadFile, "r"); // child fd 3
    try {
      const res = spawnSync(SHIM, ["--args", "3", "--unshare-pid"], {
        env: r.env(),
        encoding: "utf8",
        stdio: ["ignore", "pipe", "pipe", argsFd, cmdFd],
      });
      expect(res.status, res.stderr).toBe(0);
      const { args, fds, payload } = r.read();
      expect(fds.get("4")).toBe(fdFile);
      expect(payload.slice(payload.indexOf("--"))).toEqual([
        "--", "/proc/self/fd/4", "--version",
      ]);
      // #10032: the merged stream's command-side fd ref (payload-carried)
      // gets a re-home mount at the outer setup tail — the literal dest, the
      // resolved source, after the appended tmpfs mask.
      expect(args.slice(4)).toEqual([
        "--unshare-pid",
        "--tmpfs", "/proc",
        "--ro-bind", fdFile, "/proc/self/fd/4",
      ]);
    } finally {
      cleanup();
    }
  });

  it("a `/proc/self/fd/N` path in SETUP position is dropped as a procfs-source bind AND not cmd-preserved", () => {
    const r = root();
    const fdFile = join(r.root, "setup-fd");
    writeFileSync(fdFile, "setup side fd");
    const setupFd = openSync(fdFile, "r"); // child fd 4 — an option-position
    // path ref must not pin it (over-preserve is the leak direction). The
    // procfs-resident SOURCE also makes the bind an exposure (security F3):
    // with a userns the mount is neutralized — it never becomes a cmd ref.
    try {
      const res = spawnSync(
        SHIM,
        ["--unshare-user", "--unshare-pid", "--ro-bind", "/proc/self/fd/4", "/mnt/x", "--", "/usr/bin/true"],
        { env: r.env(), encoding: "utf8", stdio: ["ignore", "pipe", "pipe", "ignore", setupFd] },
      );
      expect(res.status, res.stderr).toBe(0);
      const { args, fds } = r.read();
      expect(fds.get("4")).not.toBe(fdFile);
      const bi = args.indexOf("--");
      expect(args.slice(bi - 2, bi), "the procfs-source bind is dropped; the mask follows").toEqual(["--tmpfs", "/proc"]);
      expect(args).not.toContain("/proc/self/fd/4");
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

  it("loads the ALTERNATE (unixdeny) artifact the selector names: the add-seccomp fd resolves to it", () => {
    const r = root();
    try {
      const res = spawnSync(SHIM, ["--unshare-user", "--unshare-pid", "--", "/usr/bin/true"], {
        env: r.env({ SOLEUR_BWRAP_SECCOMP_BPF: BPF_UNIXDENY }),
        encoding: "utf8",
      });
      expect(res.status, res.stderr).toBe(0);
      const { args, fds } = r.read();
      const i = args.indexOf("--add-seccomp-fd");
      expect(i).toBe(0);
      expect(fds.get(args[i + 1])).toBe(BPF_UNIXDENY);
    } finally {
      cleanup();
    }
  });

  it("exits 65 with the bwrap-shim marker when the ALTERNATE (unixdeny) artifact is unreadable (never a silent fallback to the base)", () => {
    const r = root();
    try {
      // The selector names the variant's basename in a directory where it does not exist.
      const unreadable = join(r.root, "bwrap-userns-clone3-unixdeny.bpf");
      const res = spawnSync(SHIM, ["--unshare-user", "--unshare-pid", "--", "/usr/bin/true"], {
        env: r.env({ SOLEUR_BWRAP_SECCOMP_BPF: unreadable }),
        encoding: "utf8",
      });
      expect(res.status).toBe(65);
      expect(res.stderr).toContain("bwrap-shim:");
      expect(res.stderr).toContain(unreadable);
      // and the real bwrap stub never ran (no spawn without the filter)
      expect(() => r.read()).toThrow();
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

  // ---- #10032: neutralize + re-home contract --------------------------------
  // The realized mask is the denyRead `--tmpfs /proc` (or an appended one),
  // never a fresh procfs — the `--proc` splice EPERMs under docker's masked
  // /proc (H6). Every procfs mount at /proc in the merged stream is dropped;
  // every command-side `/proc/self/fd/N` ref gets a re-home mount at the
  // literal path (rung-1 `--ro-bind` of the resolved source — the only rung
  // that exists on prod's bwrap 0.8.0: --bind-data EBADFs there, --bind-fd is
  // parse-only). Anything unresolvable refuses with exit 65.

  it("#10032: re-home count is per-UNIQUE-ref — two refs → two mounts, a repeat ref → one", () => {
    const r = root();
    const f3 = join(r.root, "helper-3");
    const f4 = join(r.root, "helper-4");
    writeFileSync(f3, "x");
    writeFileSync(f4, "y");
    const fd3 = openSync(f3, "r");
    const fd4 = openSync(f4, "r");
    try {
      const res = spawnSync(
        SHIM,
        ["--unshare-user", "--unshare-pid", "--ro-bind", "/", "/", "--tmpfs", "/proc", "--", "/bin/sh", "-c", "/proc/self/fd/3; /proc/self/fd/4; /proc/self/fd/3"],
        { env: r.env(), encoding: "utf8", stdio: ["ignore", "pipe", "pipe", fd3, fd4] },
      );
      expect(res.status, res.stderr).toBe(0);
      const { args } = r.read();
      const bi = args.indexOf("--");
      const setup = args.slice(2, bi);
      const rehomes: string[][] = [];
      for (let i = 0; i < setup.length - 2; i++) {
        if (setup[i] === "--ro-bind" && setup[i + 2].startsWith("/proc/self/fd/")) {
          rehomes.push([setup[i + 1], setup[i + 2]]);
        }
      }
      expect(rehomes).toEqual([[f3, "/proc/self/fd/3"], [f4, "/proc/self/fd/4"]]);
      // The stream's own --tmpfs /proc survives exactly once — never duplicated.
      expect(setup.filter((t, i) => t === "--tmpfs" && setup[i + 1] === "/proc")).toHaveLength(1);
      expect(args).not.toContain("--proc");
    } finally {
      cleanup();
    }
  });

  it("#10032: a command-side fd ref whose fd is NOT open is skipped — ENOENT inside, never a spawn-DoS", () => {
    const r = root();
    try {
      // fd 9 was never handed to the child — a ref naming a non-open fd is a
      // MENTION, not a live multicall ref (its fd is always open). The shim
      // skips it: inside the sandbox the path ENOENTs — the pre-#10032
      // outcome — instead of refusing the whole spawn (security F5). The
      // tmpfs mask is still emitted (the ref CAN never resolve, so the
      // conservative realization applies); no re-home mount appears.
      const res = spawnSync(
        SHIM,
        ["--unshare-user", "--unshare-pid", "--tmpfs", "/proc", "--", "/bin/sh", "-c", "/proc/self/fd/9"],
        { env: r.env(), encoding: "utf8" },
      );
      expect(res.status, String(res.stderr)).toBe(0);
      const { args } = r.read();
      const bi = args.indexOf("--");
      expect(args.slice(0, bi).join(" ")).not.toContain("self/fd");
    } finally {
      cleanup();
    }
  });

  it("#10032: a command-side fd ref to a pipe refuses — non-file fds cannot re-home", () => {
    const r = root();
    try {
      // stdio 'pipe' gives the child a pipe fd 3 — readlink resolves to
      // `pipe:[N]`, which is not bindable; refuse rather than shipping a
      // dead re-home.
      const res = spawnSync(
        SHIM,
        ["--unshare-user", "--unshare-pid", "--tmpfs", "/proc", "--", "/bin/sh", "-c", "/proc/self/fd/3"],
        { env: r.env(), encoding: "utf8", stdio: ["ignore", "pipe", "pipe", "pipe"] },
      );
      expect(res.status).toBe(65);
      expect(res.stderr).toContain("bwrap-shim:");
      expect(res.stderr).toContain("/proc/self/fd/3");
    } finally {
      cleanup();
    }
  });

  it("#10032: a command-side fd ref to a DELETED file refuses — no viable rung on bwrap 0.8.0", () => {
    const r = root();
    const gone = join(r.root, "deleted-helper");
    writeFileSync(gone, "x");
    const goneFd = openSync(gone, "r");
    rmSync(gone); // unlink while open — readlink yields `<path> (deleted)`
    try {
      // On 0.8.0 --bind-data EBADFs at write and --bind-fd cannot resolve the
      // fd source, so a deleted source has no realizable rung — refuse
      // (the vendored multicall fd is a live path; this is the edge arm).
      const res = spawnSync(
        SHIM,
        ["--unshare-user", "--unshare-pid", "--tmpfs", "/proc", "--", "/bin/sh", "-c", "/proc/self/fd/3"],
        { env: r.env(), encoding: "utf8", stdio: ["ignore", "pipe", "pipe", goneFd] },
      );
      expect(res.status).toBe(65);
      expect(res.stderr).toContain("bwrap-shim:");
      expect(res.stderr).toContain("/proc/self/fd/3");
    } finally {
      closeSync(goneFd);
      cleanup();
    }
  });

  it("#10032: command-side fd refs without --unshare-user refuse — re-home mounts cannot be applied", () => {
    const r = root();
    const helper = join(r.root, "helper");
    writeFileSync(helper, "x");
    const helperFd = openSync(helper, "r");
    try {
      // Mounts (tmpfs or re-home binds) need a userns; refusing early keeps
      // the failure a `bwrap-shim:` marker rather than a mid-setup mount EPERM.
      const res = spawnSync(
        SHIM,
        ["--unshare-pid", "--ro-bind", "/usr", "/usr", "--", "/bin/sh", "-c", "exec /proc/self/fd/3"],
        { env: r.env(), encoding: "utf8", stdio: ["ignore", "pipe", "pipe", helperFd] },
      );
      expect(res.status).toBe(65);
      expect(res.stderr).toContain("bwrap-shim:");
      expect(res.stderr).toContain("unshare-user");
    } finally {
      cleanup();
    }
  });

  it("#10032: a payload filtered to EMPTY re-emits as zero bytes — no phantom token", () => {
    const r = root();
    const payloadFile = join(r.root, "args-payload");
    // The payload is ENTIRELY the vendored tail bind — after neutralization
    // nothing remains; a `printf '%s\0'` on the empty array would emit a
    // lone NUL (one empty-string token → real bwrap would take it as an
    // operand). Re-emit must be byte-empty instead.
    writeFileSync(payloadFile, "--bind\0/proc\0/proc\0");
    const argsFd = openSync(payloadFile, "r");
    try {
      const res = spawnSync(SHIM, ["--args", "3", "--unshare-user", "--unshare-pid", "--", "/usr/bin/true"], {
        env: r.env(),
        encoding: "utf8",
        stdio: ["ignore", "pipe", "pipe", argsFd],
      });
      expect(res.status, res.stderr).toBe(0);
      const { args, payload } = r.read();
      expect(payload).toEqual([]); // zero tokens, not one empty token
      const bi = args.indexOf("--");
      expect(args.slice(bi - 2, bi)).toEqual(["--tmpfs", "/proc"]);
    } finally {
      cleanup();
    }
  });

  it("#10032: the committed vendored fixture — tail bind dropped, tmpfs survives once, no --proc, no re-homes", () => {
    const r = root();
    // infra/sandbox-canary-argv.json is the byte-pinned capture the fixture
    // gate diffs against; its setup stream is the exact shape the shim must
    // neutralize (124 tokens, tmpfs /proc at 20, tail bind at 122-124).
    const fixture = JSON.parse(
      readFileSync(join(APP_ROOT, "infra/sandbox-canary-argv.json"), "utf8"),
    ) as { bwrapSetupArgv: string[]; argv: string[] };
    const setup = fixture.bwrapSetupArgv.map((t) =>
      t
        .replaceAll("${CANARY_WS}", r.root)
        .replaceAll("${CANARY_EMPTY}", r.root)
        .replaceAll("${CANARY_C4_STAGING}", r.root)
        .replaceAll("${CANARY_BRIDGE_SPAWN}", r.root),
    );
    try {
      const res = spawnSync(SHIM, [...setup, "--", "/usr/bin/true"], {
        env: r.env(), encoding: "utf8",
      });
      expect(res.status, res.stderr).toBe(0);
      const { args } = r.read();
      expect(args).not.toContain("--proc");
      // No `--bind /proc /proc` remains anywhere in the emitted stream.
      for (let i = 0; i < args.length - 2; i++) {
        expect(
          args[i].startsWith("--") && args[i].includes("bind") && args[i + 1] === "/proc" && args[i + 2] === "/proc",
          `procfs mount remains at args[${i}]`,
        ).toBe(false);
      }
      // The denyRead --tmpfs /proc survives exactly once; the stream needs
      // no appended mask (it carries its own) and no re-homes (fixture argv
      // has no /proc/self/fd refs).
      const bi = args.indexOf("--");
      const emitted = args.slice(2, bi);
      expect(emitted.filter((t, i) => t === "--tmpfs" && emitted[i + 1] === "/proc")).toHaveLength(1);
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

  it("the Dockerfile bakes the AF_UNIX-deny variant next to the base artifact and .dockerignore re-includes it (#10455 a)", () => {
    expect(dockerfile).toContain(
      "COPY --from=builder /app/infra/bwrap-userns-clone3-unixdeny.bpf ./infra/bwrap-userns-clone3-unixdeny.bpf",
    );
    expect(readFileSync(join(APP_ROOT, ".dockerignore"), "utf8")).toMatch(/^!infra\/bwrap-userns-clone3-unixdeny\.bpf$/m);
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
    const p = probeAgentSandboxHardening({
      PATH: dir,
      SOLEUR_BWRAP_SECCOMP_BPF: BPF,
      SOLEUR_BWRAP_SECCOMP_BPF_UNIXDENY: BPF_UNIXDENY,
    });
    expect(p).toMatchObject({ shim: true, filter: true, unixdenyFilter: true, ok: true, bpfBytes: 128 });
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
    vi.stubEnv("SOLEUR_BWRAP_SECCOMP_BPF_UNIXDENY", BPF_UNIXDENY);
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

  it("#10032: the vendor's tail --bind /proc /proc is dropped — in-sandbox /proc is an EMPTY tmpfs, not host and not procfs", () => {
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
      // Probe (#10032): the tail bind is dropped, so the realized /proc is
      // the denyRead tmpfs — NO pid dirs at all (host, sandbox's own, or the
      // canary's), and no procfs self-view (environ is gone BY DESIGN; the
      // vendored apply-seccomp fd path is re-homed as a mount, not resolved
      // through procfs). This is the new mask discrimination.
      const probe = `for d in /proc/[0-9]*; do [ -d "$d" ] && exit 7; done; test ! -e /proc/self/environ`;
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
    vi.stubEnv("SOLEUR_BWRAP_SECCOMP_BPF_UNIXDENY", BPF_UNIXDENY);
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
      // MUTATION (#10455 a): point the "variant" at the BASE bytes - the probe must see the AF_UNIX socket get created
      // and report the variant as not live. Proves the probe discriminates (not a vacuous null).
      vi.stubEnv("SOLEUR_BWRAP_SECCOMP_BPF_UNIXDENY", BPF);
      expect(canary.runHardeningProbes(setupArgv)).toMatchObject({
        verdict: "sandbox_broken",
        reason: "unixdeny_filter_bypass",
        probe: "unixdeny_filter",
      });
      // and an unreadable variant is reported as an unusable artifact, not a pass
      vi.stubEnv("SOLEUR_BWRAP_SECCOMP_BPF_UNIXDENY", join(dir, "no-such-variant.bpf"));
      expect(canary.runHardeningProbes(setupArgv)).toMatchObject({
        verdict: "sandbox_broken",
        reason: "unixdeny_artifact_unusable",
      });
    } finally {
      vi.unstubAllEnvs();
      if (saved.PATH !== undefined) vi.stubEnv("PATH", saved.PATH);
      rmSync(dir, { recursive: true, force: true });
    }
  }, 60_000);
});
