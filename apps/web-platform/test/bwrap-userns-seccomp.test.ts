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

const APP_ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const BPF_PATH = join(APP_ROOT, "infra/bwrap-userns-clone3-deny.bpf");
const GEN = join(APP_ROOT, "scripts/gen-bwrap-userns-seccomp.mjs");

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

type SeccompInput = { arch: number; nr: number; arg0lo: number };

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
