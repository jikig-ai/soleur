#!/usr/bin/env node
// Generates the shared nested-user-namespace seccomp filter (#8752) as a raw
// `struct sock_filter[]` cBPF array — the format `bwrap --seccomp <fd>` reads
// (bwrap's seccomp_program_new does `len % 8 != 0 -> die; len / 8` — the fd
// carries instructions ONLY, no sock_fprog header; same serialization as
// libseccomp's seccomp_export_bpf).
// TWO committed artifacts (variants), one program family:
//   base      infra/bwrap-userns-clone3-deny.bpf       serves BOTH sandbox insertion points: the C4 render argv
//             (apps/web-platform/server/c4-render.ts › buildLikeC4SandboxArgv) and the agent-SDK PATH shim
//             (apps/web-platform/infra/bwrap-shim/bwrap). Byte-identical to the artifact that predates the variant.
//   unixdeny  infra/bwrap-userns-clone3-unixdeny.bpf   base + the socket(AF_UNIX) deny; selected ONLY by the agent-SDK shim
//             (via SOLEUR_BWRAP_SECCOMP_BPF) for no-egress sessions while the runtime flag is on. The C4 render never uses it.
//
//   node gen-bwrap-userns-seccomp.mjs                       # write BOTH committed artifacts
//   node gen-bwrap-userns-seccomp.mjs [--variant V] [path]  # write one variant (V: base | unixdeny)
//   node gen-bwrap-userns-seccomp.mjs --check               # verify byte-parity of BOTH, rc!=0 on drift
//   node gen-bwrap-userns-seccomp.mjs [--variant V] --check <path>   # verify one artifact (V defaults to base)
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
//
// Variant `unixdeny` (#10455 a, ADR-075 addendum 2026-10-19) adds, for NO-EGRESS
// sessions only:
//   socket / socket|X32 with the LOW 32 bits of arg0 == AF_UNIX(1) -> ERRNO(EPERM)
//     (the kernel truncates the family to int, so junk in the upper word still
//     opens an AF_UNIX socket and must still be denied). `socketpair` is
//     untouched (Node IPC and libuv use it). The base artifact stays
//     byte-identical so the C4 render path and the egress sessions are unchanged.
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
const NR_SOCKET = 41;
const NR_CLONE = 56;
const NR_UNSHARE = 272;
const NR_CLONE3 = 435;
const CLONE_NEWUSER = 0x10000000;
const AF_UNIX = 1;

const RET_ALLOW = 0x7fff0000;
const RET_ERRNO = 0x00050000;
const RET_KILL_PROCESS = 0x80000000;
const EPERM = 1;
const ENOSYS = 38;

// ---- tiny assembler --------------------------------------------------------
// Instructions are declared with label targets so jump offsets resolve from
// position — a hand-counted jt/jf rots silently the first time an instruction
// is inserted.
function assemble(build) {
  const labels = new Map();
  const insns = [];
  const a = {
    label: (name) => labels.set(name, insns.length),
    ld: (off) => insns.push({ code: LD_W_ABS, jt: 0, jf: 0, k: off }),
    jeq: (k, t, f) => insns.push({ code: JEQ, t, f, k }),
    jset: (k, t, f) => insns.push({ code: JSET, t, f, k }),
    ja: (t) => insns.push({ code: JA, t, k: 0 }),
    ret: (k) => insns.push({ code: RET, jt: 0, jf: 0, k }),
  };
  build(a);
  return insns.map((i, at) => {
    const insn = { code: i.code, k: i.k };
    if (i.code === JA) {
      insn.jt = insn.jf = 0;
      insn.k = labels.get(i.t) - at - 1;
    } else if (i.code === JEQ || i.code === JSET) {
      insn.jt = labels.get(i.t) - at - 1;
      insn.jf = i.f == null ? 0 : labels.get(i.f) - at - 1;
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
}

// The shared rules. `withUnixDeny` inserts ONLY the socket dispatch rows and the
// check-domain block; every pre-existing instruction keeps its order, so the
// base program (withUnixDeny=false) is byte-identical to the original artifact.
function buildProgram({ withUnixDeny }) {
  return assemble(({ label, ld, jeq, jset, ja, ret }) => {
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
    if (withUnixDeny) {
      jeq(NR_SOCKET, "check-domain", null);
      jeq(NR_SOCKET | X32, "check-domain", null);
    }
    ja("allow");
    label("check-flags");
    ld(OFF_ARG0_LO);
    jset(CLONE_NEWUSER, "eperm", "allow");
    if (withUnixDeny) {
      // socket(int domain, ...): arg0's LOW word only (the kernel truncates to int).
      label("check-domain");
      ld(OFF_ARG0_LO);
      jeq(AF_UNIX, "eperm", "allow");
    }
    label("enosys");
    ret(RET_ERRNO | ENOSYS);
    label("eperm");
    ret(RET_ERRNO | EPERM);
    label("allow");
    ret(RET_ALLOW);
    label("kill");
    ret(RET_KILL_PROCESS);
  });
}

/** variant name -> committed artifact (relative to apps/web-platform/infra) and program builder. */
export const VARIANTS = Object.freeze({
  base: Object.freeze({ file: "bwrap-userns-clone3-deny.bpf", build: () => buildProgram({ withUnixDeny: false }) }),
  unixdeny: Object.freeze({ file: "bwrap-userns-clone3-unixdeny.bpf", build: () => buildProgram({ withUnixDeny: true }) }),
});

// ---- serialize: len x sock_filter, no header (bwrap derives len itself) ----
export function emit(variant = "base") {
  const v = VARIANTS[variant];
  if (!v) throw new Error(`unknown variant: ${variant}`);
  const resolved = v.build();
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
  const INFRA = join(dirname(fileURLToPath(import.meta.url)), "../infra");
  const argv = process.argv.slice(2);
  let variant = null;
  let check = false;
  const positional = [];
  for (let n = 0; n < argv.length; n++) {
    if (argv[n] === "--check") check = true;
    else if (argv[n] === "--variant") variant = argv[++n] ?? "";
    else if (argv[n].startsWith("--")) {
      // An unknown flag must not be taken for a path: `--chek` would WRITE an artifact file named "--chek" and exit 0.
      console.error(`gen-bwrap-userns-seccomp: unknown argument: ${argv[n]}`);
      process.exit(2);
    } else positional.push(argv[n]);
  }
  if (variant !== null && !VARIANTS[variant]) {
    console.error(`gen-bwrap-userns-seccomp: unknown variant: ${variant}`);
    process.exit(2);
  }
  const verify = (name, path) => {
    const want = emit(name);
    let got;
    try {
      got = readFileSync(path);
    } catch (e) {
      console.error(`gen-bwrap-userns-seccomp: ${path} unreadable: ${e.code ?? e}`);
      return false;
    }
    if (!want.equals(got)) {
      console.error(
        `gen-bwrap-userns-seccomp: ${path} differs from the generator's output (variant ${name}) — ` +
          `regenerate with \`node apps/web-platform/scripts/gen-bwrap-userns-seccomp.mjs\``,
      );
      return false;
    }
    return true;
  };
  if (check) {
    if (positional.length === 0 && variant === null) {
      // no path: verify BOTH committed artifacts
      const results = Object.keys(VARIANTS).map((name) => verify(name, join(INFRA, VARIANTS[name].file)));
      process.exit(results.every(Boolean) ? 0 : 1);
    }
    const name = variant ?? "base";
    process.exit(verify(name, positional[0] ?? join(INFRA, VARIANTS[name].file)) ? 0 : 1);
  }
  if (positional.length === 0 && variant === null) {
    for (const name of Object.keys(VARIANTS)) writeFileSync(join(INFRA, VARIANTS[name].file), emit(name));
  } else {
    const name = variant ?? "base";
    writeFileSync(positional[0] ?? join(INFRA, VARIANTS[name].file), emit(name));
  }
}
