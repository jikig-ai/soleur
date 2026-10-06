#!/usr/bin/env node
// Generates the shared nested-user-namespace seccomp filter (#8752) as a raw
// `struct sock_filter[]` cBPF array — the format `bwrap --seccomp <fd>` reads
// (bwrap's seccomp_program_new does `len % 8 != 0 -> die; len / 8` — the fd
// carries instructions ONLY, no sock_fprog header; same serialization as
// libseccomp's seccomp_export_bpf).
// One artifact, both sandbox insertion points: the C4 render argv
// (apps/web-platform/server/c4-render.ts › buildLikeC4SandboxArgv) and the
// agent-SDK PATH shim (apps/web-platform/infra/bwrap-shim/bwrap).
//
//   node gen-bwrap-userns-seccomp.mjs            # write the committed artifact
//   node gen-bwrap-userns-seccomp.mjs --check [path]   # verify byte-parity, rc!=0 on drift
//
// Ruleset (x86_64 + __X32_SYSCALL_BIT variants; aarch64 is out of scope —
// replicas are amd64, and the arch gate KILLs anything else rather than
// letting a foreign syscall table slide past the nr comparisons):
//   arch != x86_64                         -> KILL_PROCESS
//   clone3                                 -> ERRNO(ENOSYS)   — flags live in a
//     clone_args struct seccomp cannot read, so clone3 must be blanket-ENOSYS:
//     glibc's posix_spawn prefers clone3 and falls back to clone ONLY on
//     ENOSYS; EPERM there is a fleet-wide spawn break (moby/moby#42680).
//   clone / unshare with CLONE_NEWUSER set -> ERRNO(EPERM)      — flag-masked,
//     so unrelated clone/unshare traffic (threads, mount ns, net ns) survives.
//   everything else                        -> ALLOW
import { writeFileSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

// classic BPF opcodes (linux/bpf_common.h / bpf.h)
const LD_W_ABS = 0x20;
const JA = 0x05;
const JEQ = 0x15;
const JSET = 0x45;
const RET = 0x06;

// seccomp_data field offsets (linux/seccomp.h): nr @0, arch @4, args[N] @16+8N
const OFF_NR = 0;
const OFF_ARCH = 4;
const OFF_ARG0_LO = 16;

const AUDIT_ARCH_X86_64 = 0xc000003e;
const X32 = 0x40000000;
const NR_CLONE = 56;
const NR_UNSHARE = 272;
const NR_CLONE3 = 435;
const CLONE_NEWUSER = 0x10000000;

const RET_ALLOW = 0x7fff0000;
const RET_ERRNO = 0x00050000;
const RET_KILL_PROCESS = 0x80000000;
const EPERM = 1;
const ENOSYS = 38;

// ---- tiny assembler --------------------------------------------------------
// Instructions are declared with label targets so jump offsets resolve from
// position — a hand-counted jt/jf rots silently the first time an instruction
// is inserted.
const labels = new Map();
const insns = [];
const label = (name) => labels.set(name, insns.length);
const ld = (off) => insns.push({ code: LD_W_ABS, jt: 0, jf: 0, k: off });
const jeq = (k, t, f) => insns.push({ code: JEQ, t, f, k });
const jset = (k, t, f) => insns.push({ code: JSET, t, f, k });
const ja = (t) => insns.push({ code: JA, t, k: 0 });
const ret = (k) => insns.push({ code: RET, jt: 0, jf: 0, k });

ld(OFF_ARCH);
jeq(AUDIT_ARCH_X86_64, "load-nr", "kill");
label("load-nr");
ld(OFF_NR);
jeq(NR_CLONE3, "enosys", null);
jeq(NR_CLONE3 | X32, "enosys", null);
jeq(NR_CLONE, "check-flags", null);
jeq(NR_UNSHARE, "check-flags", null);
jeq(NR_CLONE | X32, "check-flags", null);
jeq(NR_UNSHARE | X32, "check-flags", null);
ja("allow");
label("check-flags");
ld(OFF_ARG0_LO);
jset(CLONE_NEWUSER, "eperm", "allow");
label("enosys");
ret(RET_ERRNO | ENOSYS);
label("eperm");
ret(RET_ERRNO | EPERM);
label("allow");
ret(RET_ALLOW);
label("kill");
ret(RET_KILL_PROCESS);

const resolved = insns.map((i) => {
  const insn = { code: i.code, k: i.k };
  if (i.code === JA) {
    insn.jt = insn.jf = 0;
    insn.k = labels.get(i.t) - insns.indexOf(i) - 1;
  } else if (i.code === JEQ || i.code === JSET) {
    insn.jt = labels.get(i.t) - insns.indexOf(i) - 1;
    insn.jf = i.f == null ? 0 : labels.get(i.f) - insns.indexOf(i) - 1;
  } else {
    insn.jt = i.jt;
    insn.jf = i.jf;
  }
  for (const f of ["jt", "jf", "k"]) {
    if (!Number.isInteger(insn[f]) || insn[f] < 0 || insn[f] > 0xffffffff) {
      throw new Error(`unresolved or out-of-range ${f} on insn ${JSON.stringify(i)}`);
    }
  }
  if ((i.code === JEQ || i.code === JSET) && (insn.jt > 255 || insn.jf > 255)) {
    throw new Error("jump offset exceeds u8 — split the program");
  }
  return insn;
});

// ---- serialize: len x sock_filter, no header (bwrap derives len itself) ----
export function emit() {
  const buf = Buffer.alloc(resolved.length * 8);
  resolved.forEach((i, n) => {
    const off = n * 8;
    buf.writeUInt16LE(i.code, off);
    buf.writeUInt8(i.jt, off + 2);
    buf.writeUInt8(i.jf, off + 3);
    buf.writeUInt32LE(i.k >>> 0, off + 4);
  });
  return buf;
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const DEFAULT_OUT = join(dirname(fileURLToPath(import.meta.url)), "../infra/bwrap-userns-clone3-deny.bpf");
  const argv = process.argv.slice(2);
  if (argv[0] === "--check") {
    const want = emit();
    const path = argv[1] ?? DEFAULT_OUT;
    const got = readFileSync(path);
    if (!want.equals(got)) {
      console.error(
        `gen-bwrap-userns-seccomp: ${path} differs from the generator's output — ` +
          `regenerate with \`node apps/web-platform/scripts/gen-bwrap-userns-seccomp.mjs\``,
      );
      process.exit(1);
    }
    process.exit(0);
  }
  writeFileSync(argv[0] ?? DEFAULT_OUT, emit());
}
