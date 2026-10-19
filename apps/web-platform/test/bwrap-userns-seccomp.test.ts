// Guard Contract for the committed nested-user-namespace seccomp filter
// (#8752). The artifact `infra/bwrap-userns-clone3-deny.bpf` is a raw
// `struct sock_filter[]` consumed by `bwrap --seccomp <fd>` at BOTH sandbox insertion
// points (the C4 render argv and the agent-SDK PATH shim). Editing the filter
// is only safe via `scripts/gen-bwrap-userns-seccomp.mjs` — never hand-edit the
// committed bytes; `--check` asserts byte-parity.
//
// Semantics are verified by INTERPRETING the committed program over synthetic
// seccomp_data inputs, not by matching bytes — a byte-shape test cannot see a
// jump-target swap that still produces the same text. Every seccomp return
// value the filter can produce has a row that drives it, and a meta-row fails
// when the program contains a return no row reaches.
import { describe, it, expect } from "vitest";
import { closeSync, mkdtempSync, openSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { tmpdir } from "node:os";
import { createHash } from "node:crypto";

const APP_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const BPF_PATH = join(APP_ROOT, "infra/bwrap-userns-clone3-deny.bpf");
const UNIXDENY_PATH = join(APP_ROOT, "infra/bwrap-userns-clone3-unixdeny.bpf");
const GEN = join(APP_ROOT, "scripts/gen-bwrap-userns-seccomp.mjs");
const SECCOMP_PROFILE_PATH = join(APP_ROOT, "infra/seccomp-bwrap.json");

// ---- what bwrap reads off the --seccomp fd ---------------------------------
// Raw struct sock_filter[] — bwrap's seccomp_program_new reads the whole fd,
// requires len % 8 == 0 and derives the instruction count as len/8. NO
// sock_fprog header (that's the seccomp_export_bpf serialization shape too).
const INSN_BYTES = 8;

type Insn = { code: number; jt: number; jf: number; k: number };
function decode(buf: Buffer): Insn[] {
  expect(buf.length % INSN_BYTES).toBe(0);
  const insns: Insn[] = [];
  for (let off = 0; off < buf.length; off += INSN_BYTES) {
    insns.push({
      code: buf.readUInt16LE(off),
      jt: buf.readUInt8(off + 2),
      jf: buf.readUInt8(off + 3),
      k: buf.readUInt32LE(off + 4),
    });
  }
  return insns;
}

// ---- Minimal classic-BPF interpreter over the instructions we emit ---------
// seccomp_data: nr @0 (u32), arch @4 (u32), args[N] @16+8N (u64; low word first).
const BPF_LD_W_ABS = 0x20;
const BPF_JMP_JA = 0x05;
const BPF_JMP_JEQ = 0x15;
const BPF_JMP_JSET = 0x45;
const BPF_RET_K = 0x06;

const SECCOMP_RET_ALLOW = 0x7fff0000;
const SECCOMP_RET_ERRNO = 0x00050000;
const SECCOMP_RET_KILL_PROCESS = 0x80000000;

const AUDIT_ARCH_X86_64 = 0xc000003e;
const AUDIT_ARCH_AARCH64 = 0x400000b7;

const NR_CLONE = 56;
const NR_UNSHARE = 272;
const NR_CLONE3 = 435;
const X32_SYSCALL_BIT = 0x40000000;
const CLONE_NEWUSER = 0x10000000;
const CLONE_NEWNS = 0x00020000;
const CLONE_NEWNET = 0x40000000;
const EPERM = 1;
const ENOSYS = 38;

type SeccompInput = { arch: number; nr: number; arg0lo: number; arg0hi?: number };

/** Interprets the program to a terminal action. Throws on a malformed jump. */
function run(insns: Insn[], input: SeccompInput): number {
  let pc = 0;
  let a = 0;
  for (let steps = 0; steps < 64; steps++) {
    const ins = insns[pc];
    expect(ins, `pc ${pc} out of bounds`).toBeDefined();
    switch (ins.code) {
      case BPF_LD_W_ABS:
        if (ins.k === 0) a = input.nr;
        else if (ins.k === 4) a = input.arch;
        else if (ins.k === 16) a = input.arg0lo;
        else if (ins.k === 20) a = input.arg0hi ?? 0;
        else throw new Error(`unexpected LD ABS offset ${ins.k}`);
        pc += 1;
        break;
      case BPF_JMP_JA:
        pc += 1 + ins.k;
        break;
      case BPF_JMP_JEQ:
        pc += 1 + (a === ins.k ? ins.jt : ins.jf);
        break;
      case BPF_JMP_JSET:
        pc += 1 + ((a & ins.k) !== 0 ? ins.jt : ins.jf);
        break;
      case BPF_RET_K:
        return ins.k;
      default:
        throw new Error(`unexpected opcode 0x${ins.code.toString(16)} at pc ${pc}`);
    }
  }
  throw new Error("program did not terminate within 64 steps");
}

const prog = decode(readFileSync(BPF_PATH));

describe("bwrap-userns-clone3-deny filter semantics", () => {
  it("kills non-x86_64 architectures outright", () => {
    expect(run(prog, { arch: AUDIT_ARCH_AARCH64, nr: NR_CLONE3, arg0lo: 0 })).toBe(
      SECCOMP_RET_KILL_PROCESS,
    );
  });
  it("returns ENOSYS for clone3 (flags live in a struct — uninspectable)", () => {
    for (const arg0 of [0, CLONE_NEWUSER, CLONE_NEWUSER | CLONE_NEWNET]) {
      expect(run(prog, { arch: AUDIT_ARCH_X86_64, nr: NR_CLONE3, arg0lo: arg0 })).toBe(
        SECCOMP_RET_ERRNO | ENOSYS,
      );
    }
    expect(
      run(prog, { arch: AUDIT_ARCH_X86_64, nr: NR_CLONE3 | X32_SYSCALL_BIT, arg0lo: CLONE_NEWUSER }),
    ).toBe(SECCOMP_RET_ERRNO | ENOSYS);
  });
  it("denies clone/unshare carrying CLONE_NEWUSER with EPERM", () => {
    for (const nr of [NR_CLONE, NR_UNSHARE, NR_CLONE | X32_SYSCALL_BIT, NR_UNSHARE | X32_SYSCALL_BIT]) {
      for (const flags of [CLONE_NEWUSER, CLONE_NEWUSER | CLONE_NEWNET, CLONE_NEWUSER | CLONE_NEWNS]) {
        expect(run(prog, { arch: AUDIT_ARCH_X86_64, nr, arg0lo: flags })).toBe(
          SECCOMP_RET_ERRNO | EPERM,
        );
      }
    }
  });
  it("allows clone/unshare WITHOUT CLONE_NEWUSER (flag-selective, not blanket)", () => {
    expect(run(prog, { arch: AUDIT_ARCH_X86_64, nr: NR_CLONE, arg0lo: 0 })).toBe(SECCOMP_RET_ALLOW);
    expect(
      run(prog, { arch: AUDIT_ARCH_X86_64, nr: NR_UNSHARE, arg0lo: CLONE_NEWNS }),
    ).toBe(SECCOMP_RET_ALLOW);
    expect(
      run(prog, { arch: AUDIT_ARCH_X86_64, nr: NR_UNSHARE, arg0lo: CLONE_NEWNET }),
    ).toBe(SECCOMP_RET_ALLOW);
  });
  it("allows every other syscall by default", () => {
    for (const nr of [57 /* fork */, 59 /* execve */, 1 /* write */, 322 /* execveat */]) {
      expect(run(prog, { arch: AUDIT_ARCH_X86_64, nr, arg0lo: 0xffffffff })).toBe(
        SECCOMP_RET_ALLOW,
      );
    }
  });
  it("meta: every return kind the program can produce is covered by a row above", () => {
    const rets = new Set(prog.filter((i) => i.code === BPF_RET_K).map((i) => i.k));
    expect(rets).toEqual(
      new Set([
        SECCOMP_RET_ALLOW,
        SECCOMP_RET_ERRNO | EPERM,
        SECCOMP_RET_ERRNO | ENOSYS,
        SECCOMP_RET_KILL_PROCESS,
      ]),
    );
  });
});

describe("generator byte parity", () => {
  it("--check exits 0 (committed artifact regenerates byte-identically)", () => {
    const r = spawnSync(process.execPath, [GEN, "--check", BPF_PATH], { encoding: "utf8" });
    expect(r.status, r.stderr || r.stdout).toBe(0);
  });
  it("--check exits non-zero on a mutated artifact (vacuity pin)", () => {
    const mutated = Buffer.from(readFileSync(BPF_PATH));
    mutated[4] ^= 0xff;
    const tmp = join(mkdtempSync(join(tmpdir(), "bpf-mut-")), "mutated.bpf");
    writeFileSync(tmp, mutated);
    try {
      const r = spawnSync(process.execPath, [GEN, "--check", tmp], { encoding: "utf8" });
      // Pin the REASON, not just non-zero — an ENOENT/crash would also be 1.
      expect(r.status).not.toBe(0);
      expect(r.stderr).toContain("differs");
    } finally {
      rmSync(dirname(tmp), { recursive: true, force: true });
    }
  });
});

// ---- #10455 (a): the unixdeny variant --------------------------------------
// Second artifact, applied to NO-EGRESS sessions only (ADR-075 addendum
// 2026-10-19): the base rules plus `socket(AF_UNIX)` -> EPERM. `socketpair`
// stays allowed (Node IPC, libuv). The arg0 compare is on the LOW 32 bits only:
// the kernel's `socket(int family, ...)` truncates, so a caller passing junk in
// the upper word still opens an AF_UNIX socket and must still be denied.
const NR_SOCKET = 41;
const NR_SOCKETPAIR = 53;
const AF_UNIX = 1;
const AF_INET = 2;
const AF_INET6 = 10;
const AF_NETLINK = 16;
const AF_PACKET = 17;
const UNIX_SHA_BASE = "073221227c7250ce6ccb89eb4df9d6665315ea16451e2f7d69a94b6626da9521";

describe("unixdeny variant filter semantics", () => {
  const unix = (): Insn[] => decode(readFileSync(UNIXDENY_PATH));
  const X86 = AUDIT_ARCH_X86_64;
  const DENY = SECCOMP_RET_ERRNO | EPERM;

  // [label, input, expected]. Every row is evaluated; the floor below pins the count.
  const rows: Array<[string, SeccompInput, number]> = [
    ["socket(AF_UNIX)", { arch: X86, nr: NR_SOCKET, arg0lo: AF_UNIX }, DENY],
    ["socket(AF_UNIX) junk upper word", { arch: X86, nr: NR_SOCKET, arg0lo: AF_UNIX, arg0hi: 0xdeadbeef }, DENY],
    ["socket(AF_UNIX) x32 nr", { arch: X86, nr: NR_SOCKET | X32_SYSCALL_BIT, arg0lo: AF_UNIX }, DENY],
    ["socket(AF_UNIX) x32 nr junk upper word", { arch: X86, nr: NR_SOCKET | X32_SYSCALL_BIT, arg0lo: AF_UNIX, arg0hi: 1 }, DENY],
    ["socket(AF_INET)", { arch: X86, nr: NR_SOCKET, arg0lo: AF_INET }, SECCOMP_RET_ALLOW],
    ["socket(AF_INET6)", { arch: X86, nr: NR_SOCKET, arg0lo: AF_INET6 }, SECCOMP_RET_ALLOW],
    ["socket(AF_NETLINK)", { arch: X86, nr: NR_SOCKET, arg0lo: AF_NETLINK }, SECCOMP_RET_ALLOW],
    ["socket(AF_PACKET)", { arch: X86, nr: NR_SOCKET, arg0lo: AF_PACKET }, SECCOMP_RET_ALLOW],
    ["socket(0)", { arch: X86, nr: NR_SOCKET, arg0lo: 0 }, SECCOMP_RET_ALLOW],
    ["socket(AF_INET) x32 nr", { arch: X86, nr: NR_SOCKET | X32_SYSCALL_BIT, arg0lo: AF_INET }, SECCOMP_RET_ALLOW],
    ["socketpair(AF_UNIX)", { arch: X86, nr: NR_SOCKETPAIR, arg0lo: AF_UNIX }, SECCOMP_RET_ALLOW],
    ["socketpair(AF_UNIX) x32 nr", { arch: X86, nr: NR_SOCKETPAIR | X32_SYSCALL_BIT, arg0lo: AF_UNIX }, SECCOMP_RET_ALLOW],
    // the base rules survive in the variant
    ["clone3 stays ENOSYS", { arch: X86, nr: NR_CLONE3, arg0lo: 0 }, SECCOMP_RET_ERRNO | ENOSYS],
    ["clone(CLONE_NEWUSER) stays EPERM", { arch: X86, nr: NR_CLONE, arg0lo: CLONE_NEWUSER }, DENY],
    ["unshare(CLONE_NEWUSER) stays EPERM", { arch: X86, nr: NR_UNSHARE, arg0lo: CLONE_NEWUSER }, DENY],
    ["clone without NEWUSER allowed", { arch: X86, nr: NR_CLONE, arg0lo: 0 }, SECCOMP_RET_ALLOW],
    ["arch gate kept", { arch: AUDIT_ARCH_AARCH64, nr: NR_SOCKET, arg0lo: AF_INET }, SECCOMP_RET_KILL_PROCESS],
    ["other syscalls allowed", { arch: X86, nr: 1, arg0lo: AF_UNIX }, SECCOMP_RET_ALLOW],
  ];
  const ROW_FLOOR = 18;

  it("the row table is not empty (floor)", () => {
    expect(rows.length).toBeGreaterThanOrEqual(ROW_FLOOR);
  });
  it("every row returns its expected action", () => {
    const p = unix();
    let evaluated = 0;
    for (const [label, input, want] of rows) {
      expect(run(p, input), label).toBe(want);
      evaluated++;
    }
    expect(evaluated).toBeGreaterThanOrEqual(ROW_FLOOR);
  });
  it("meta: the variant returns exactly the same four action kinds as the base", () => {
    const rets = new Set(unix().filter((i) => i.code === BPF_RET_K).map((i) => i.k));
    expect(rets).toEqual(
      new Set([SECCOMP_RET_ALLOW, DENY, SECCOMP_RET_ERRNO | ENOSYS, SECCOMP_RET_KILL_PROCESS]),
    );
  });
  it("is a different program from the base", () => {
    expect(readFileSync(UNIXDENY_PATH).equals(readFileSync(BPF_PATH))).toBe(false);
  });
});

describe("base artifact golden bytes (the variant work must not move it)", () => {
  it("the committed base artifact has the pinned sha256", () => {
    const sha = createHash("sha256").update(readFileSync(BPF_PATH)).digest("hex");
    expect(sha).toBe(UNIX_SHA_BASE);
  });
  it("the base artifact equals the one on origin/main byte for byte (skipped only when the ref is absent)", () => {
    const rel = "apps/web-platform/infra/bwrap-userns-clone3-deny.bpf";
    const r = spawnSync("git", ["show", `origin/main:${rel}`], { cwd: APP_ROOT, encoding: "buffer", maxBuffer: 1 << 20 });
    if (r.status !== 0) {
      // no origin/main in this checkout (shallow clone): the pinned sha256 row above is the floor.
      return;
    }
    expect(Buffer.from(r.stdout).equals(readFileSync(BPF_PATH))).toBe(true);
  });
  it("the generator's default emit() is the base artifact", async () => {
    const mod = await import(/* @vite-ignore */ GEN);
    expect(Buffer.from(mod.emit()).equals(readFileSync(BPF_PATH))).toBe(true);
    expect(Buffer.from(mod.emit("unixdeny")).equals(readFileSync(UNIXDENY_PATH))).toBe(true);
    expect(Buffer.from(mod.emit("unixdeny")).equals(Buffer.from(mod.emit("base")))).toBe(false);
  });
});

describe("generator --check covers both artifacts", () => {
  it("--check with no path verifies BOTH committed artifacts (exit 0)", () => {
    const r = spawnSync(process.execPath, [GEN, "--check"], { encoding: "utf8" });
    expect(r.status, r.stderr || r.stdout).toBe(0);
  });
  it("--check --variant unixdeny <path> accepts the variant and rejects the base bytes", () => {
    const ok = spawnSync(process.execPath, [GEN, "--variant", "unixdeny", "--check", UNIXDENY_PATH], { encoding: "utf8" });
    expect(ok.status, ok.stderr).toBe(0);
    const bad = spawnSync(process.execPath, [GEN, "--variant", "unixdeny", "--check", BPF_PATH], { encoding: "utf8" });
    expect(bad.status).not.toBe(0);
    expect(bad.stderr).toContain("differs");
  });
  it("an unknown variant is refused", () => {
    const r = spawnSync(process.execPath, [GEN, "--variant", "nope", "--check"], { encoding: "utf8" });
    expect(r.status).not.toBe(0);
    expect(r.stderr).toContain("unknown variant");
  });
});

describe("the container seccomp profile keeps io_uring closed (Phase 0.2 go/no-go pin)", () => {
  it("no allow rule in the production profile names an io_uring syscall", () => {
    const prof = JSON.parse(readFileSync(SECCOMP_PROFILE_PATH, "utf8")) as {
      defaultAction: string;
      syscalls: Array<{ names: string[]; action: string }>;
    };
    expect(prof.defaultAction).toBe("SCMP_ACT_ERRNO");
    const names = prof.syscalls.flatMap((r) => r.names);
    expect(names.length).toBeGreaterThan(300); // floor: a parse that yields nothing must not pass
    expect(names.filter((n) => n.startsWith("io_uring"))).toEqual([]);
  });
});

// ---- real-bwrap functional rows --------------------------------------------
// Same convention as c4-render-tenant-config.test.ts: a module-level probe
// decides sandbox usability; C4_BWRAP_REQUIRED turns an unusable bwrap into a
// hard FAIL at load time so CI can never skip-green the real rows.
const BWRAP = "/usr/bin/bwrap";
const BWRAP_OK =
  spawnSync(
    BWRAP,
    [
      "--unshare-user", "--unshare-pid", "--unshare-net", "--ro-bind", "/usr", "/usr",
      "--symlink", "usr/lib", "/lib", "--symlink", "usr/lib64", "/lib64", "--", "/usr/bin/true",
    ],
    { stdio: "ignore", timeout: 15_000 },
  ).status === 0;
if (!BWRAP_OK && process.env.C4_BWRAP_REQUIRED) {
  throw new Error("C4_BWRAP_REQUIRED is set but /usr/bin/bwrap cannot create a sandbox here.");
}

/** Runs a payload inside bwrap with the committed filter on fd 3. */
function filteredRun(payload: string[]): { status: number | null; stderr: string } {
  const fd = openSync(BPF_PATH, "r");
  try {
    const r = spawnSync(
      BWRAP,
      [
        "--seccomp", "3",
        "--die-with-parent",
        "--unshare-user", "--unshare-pid",
        "--ro-bind", "/usr", "/usr",
        "--symlink", "usr/lib", "/lib", "--symlink", "usr/lib64", "/lib64",
        "--dev", "/dev",
        "--", ...payload,
      ],
      { stdio: ["ignore", "ignore", "pipe", fd], encoding: "utf8", timeout: 15_000 },
    );
    return { status: r.status, stderr: String(r.stderr ?? "") };
  } finally {
    closeSync(fd);
  }
}

describe.skipIf(!BWRAP_OK)("real-bwrap behavioral rows", () => {
  it("nested unshare -U inside the filtered sandbox fails with EPERM", () => {
    // Positive control FIRST: the same argv WITHOUT the filter must permit
    // the nested userns — else the deny below is unattributable (a host
    // denying nested userns anyway would green a vacuous row).
    const control = spawnSync(
      BWRAP,
      ["--unshare-user", "--unshare-pid", "--ro-bind", "/usr", "/usr", "--symlink", "usr/lib", "/lib", "--symlink", "usr/lib64", "/lib64", "--dev", "/dev", "--", "/usr/bin/unshare", "-U", "/usr/bin/true"],
      { encoding: "utf8", timeout: 30_000 },
    );
    expect(control.status, `unfiltered control stderr=${control.stderr}`).toBe(0);
    const r = filteredRun(["/usr/bin/unshare", "-U", "/usr/bin/true"]);
    // The denial must come from the SANDBOXED unshare (EPERM text), not from
    // bwrap's own setup failing — a `bwrap:` line would satisfy "non-zero" on
    // a filter that never installed (expected-fail inversion).
    expect(r.status, `stderr=${r.stderr}`).not.toBe(0);
    expect(r.stderr).not.toContain("bwrap:");
    expect(r.stderr).toMatch(/Operation not permitted/);
  });
  it("a forked child inside the filtered sandbox still works (not blanket-clone-deny)", () => {
    // Over-broad control. The plan prescribed `unshare -m` here; measured on
    // kernel 7.2.5 + bwrap 0.12, EVERY nested non-userns unshare fails inside
    // a bwrap sandbox regardless of the filter — the payload runs
    // capability-free (bwrap zeroes the capset before exec), so nested
    // CLONE_NEWNS needs a CAP_SYS_ADMIN it doesn't hold. A forked subprocess exercises clone() without
    // CLONE_NEWUSER — the exact thing a blanket-deny regression would break.
    // Flag-level selectivity (CLONE_NEWNS allowed) is asserted by the
    // interpreter rows above.
    const r = filteredRun(["/usr/bin/sh", "-c", "/usr/bin/true"]);
    expect(r.status, `stderr=${r.stderr}`).toBe(0);
  });
});

/** Same sandbox as filteredRun, with an explicit artifact. */
function filteredRunWith(bpf: string, payload: string[]): { status: number | null; stderr: string; stdout: string } {
  const fd = openSync(bpf, "r");
  try {
    const r = spawnSync(
      BWRAP,
      [
        "--seccomp", "3", "--die-with-parent", "--unshare-user", "--unshare-pid",
        "--ro-bind", "/usr", "/usr", "--symlink", "usr/lib", "/lib", "--symlink", "usr/lib64", "/lib64",
        "--dev", "/dev", "--", ...payload,
      ],
      { stdio: ["ignore", "pipe", "pipe", fd], encoding: "utf8", timeout: 15_000 },
    );
    return { status: r.status, stderr: String(r.stderr ?? ""), stdout: String(r.stdout ?? "") };
  } finally {
    closeSync(fd);
  }
}

const PERL_OK = spawnSync("/usr/bin/perl", ["-e", "1"], { stdio: "ignore" }).status === 0;
const REAL_VARIANT_ROWS = BWRAP_OK && PERL_OK;
let realVariantRowsRun = 0;

describe.skipIf(!REAL_VARIANT_ROWS)("real-bwrap rows for the unixdeny variant", () => {
  const sock = (dom: string) =>
    ["/usr/bin/perl", "-e", `use Socket; socket(S, ${dom}, SOCK_STREAM, 0) or do { print "ERR:$!\\n"; exit 3 }; print "OK\\n";`];
  it("control: the BASE artifact lets socket(AF_UNIX) through (else the deny below is unattributable)", () => {
    const r = filteredRunWith(BPF_PATH, sock("PF_UNIX"));
    realVariantRowsRun++;
    expect(r.stdout, r.stderr).toContain("OK");
  });
  it("the unixdeny artifact returns EPERM for socket(AF_UNIX)", () => {
    const r = filteredRunWith(UNIXDENY_PATH, sock("PF_UNIX"));
    realVariantRowsRun++;
    expect(r.status, r.stderr).toBe(3);
    expect(r.stdout).toContain("ERR:Operation not permitted");
  });
  it("the unixdeny artifact still allows socket(AF_INET) and socketpair(AF_UNIX)", () => {
    const inet = filteredRunWith(UNIXDENY_PATH, sock("PF_INET"));
    realVariantRowsRun++;
    expect(inet.stdout, inet.stderr).toContain("OK");
    const pair = filteredRunWith(UNIXDENY_PATH, [
      "/usr/bin/perl", "-e",
      'use Socket; socketpair(A, B, PF_UNIX, SOCK_STREAM, 0) or do { print "ERR:$!\\n"; exit 3 }; print "OK\\n";',
    ]);
    realVariantRowsRun++;
    expect(pair.stdout, pair.stderr).toContain("OK");
  });
  it("floor: the variant rows actually ran (a skipped describe cannot pass vacuously on a runner that has bwrap)", () => {
    expect(realVariantRowsRun).toBeGreaterThanOrEqual(4);
  });
});
if (!REAL_VARIANT_ROWS && process.env.C4_BWRAP_REQUIRED) {
  throw new Error("C4_BWRAP_REQUIRED is set but the real-bwrap variant rows cannot run here (bwrap or perl unusable).");
}
