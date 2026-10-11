# Phase 0 Measurements — #10032 sandbox shim procfs-free realization

Date: 2026-10-13. Host: Omarchy dev (docker 29.7.2, bwrap 0.12.0).
Image: `soleur-codex9051-production-candidate:a2ff13ca8d56` (bwrap 0.8.0, `/usr/local/bin/bwrap`=shim, `/usr/bin/bwrap`=real).

## Deviation from prod posture

In-image verify ran `--security-opt apparmor=unconfined` + repo `infra/seccomp-bwrap.json`.
Prod runs `apparmor=soleur-bwrap`; this host cannot load it (no root) and has
`apparmor_restrict_unprivileged_userns=1` (prod's `kernel_ns` row reads `restrict=0`).
Docker's default masked `/proc` — the H6 trigger — is identical in both.

## 0.1 — real multicall `/proc/self/fd` surface (static, vendored binary)

- `claude` binary emits `applyPath: "/proc/self/fd/${_ct}"`, `argv0: "apply-seccomp"`
  where `_ct` is an fd opened on `/proc/self/exe` → resolves to the claude binary
  (regular file, executable → rung-1 `--ro-bind` suffices).
- Command-side ref shape: `ARGV0=apply-seccomp /proc/self/fd/<N> <command>` env-prefixed
  inside the `-c` payload (`$V()` prefix; `seccomp(unix-block)` arm). Exactly ONE fd ref
  per wrapped command; zero refs when the wrapper is absent — both shapes must be handled.
- `seccompConfig` = `De?.seccomp` (defaults to embedded `fO()` helper in the resolved
  config map); `usesSeccompHelper` drives `BV()`'s `--cap-add CAP_SETFCAP` (root-only arm;
  prod euid=1001 emits only `--cap-drop ALL`). Fixture's CAP_SETFCAP is a root-capture
  artifact, not a runtime fingerprint.

## 0.2 — realized merged stream through the REAL shim (SOLEUR_BWRAP_REAL=recorder)

- Shape A (outer tokens): `… --bind /proc /proc --proc /proc -- /bin/true` —
  tail bind lands, then `--proc` splice at last setup position.
- Shape B (`--args <fd>`): payload re-emitted VERBATIM on a fresh fd (tail bind inside
  payload), `--proc /proc` spliced in outer argv. Rewrite must therefore act on the
  MERGED stream (payload content), not just the outer argv — confirmed `rewrite` runs
  on the merged token list, then re-splits.

## 0.3 — in-image verify (bwrap 0.8.0, docker masked /proc)

- **H6 reproduced:** today's emitted argv (fixture + `--proc /proc`) →
  `bwrap: Can't mount proc on /newroot/proc: Operation not permitted` (rc=1).
- **Rewritten argv spawns:** fixture minus tail `--bind /proc /proc`, NO `--proc`,
  plus `--ro-bind <claude-binary> /proc/self/fd/6` → rc=0.
  - `ls /proc` → only `self`; `ls /proc | grep -c '^[0-9]+$'` → 0 (mask realized).
  - `/proc/self/fd/6` resolves to the bound claude binary; exec works
    (`--version` prints Bun banner; `ARGV0=apply-seccomp` prints multicall Usage).
- apply-seccomp multicall inside sandbox: `unshare(CLONE_NEWUSER): Operation not
  permitted` → rc=1 **with and without our bpf, with and without euid=0-in-userns**
  (this host denies unprivileged NEWUSER in-container). On the bare host the same
  multicall completes rc=0 (maps euid→euid, runs payload, mounts own /proc).
- **Rung-2 dead on prod's bwrap 0.8.0:** `--bind-data`/`--ro-bind-data` →
  "Can't write data to file: Bad file descriptor"; `--bind-fd` parses but
  "Can't find source path /proc/self/fd/N" (fd closed before source
  resolution); `--ro-bind /proc/self/fd/N` as source likewise cannot resolve.
  The re-home ladder collapses to rung-1 `--ro-bind <resolved real path>` or
  REFUSE — deleted/memfd/pipe/socket/unreadable/O_PATH refs fail closed.
- Empty `--args` payload after filtering is legal: 0-byte fd re-emit accepted
  (verified on 0.12; a payload that was entirely the tail bind re-emits empty).
- **Invariance:** our injected bpf (`clone/unshare`+CLONE_NEWUSER→EPERM, clone3→ENOSYS —
  decoded from the committed .bpf) kills apply-seccomp's FIRST syscall under ANY /proc
  realization. Whether the wrapper is present in prod's real command is therefore
  invariant to this fix: it either isn't emitted (then moot) or it dies at NEWUSER
  identically under `--proc` and tmpfs (then the rewrite changes nothing for it).

## 0.4 — in-sandbox /proc pseudo-file dependency census (rewritten shape)

| path | status | classification |
|---|---|---|
| `/proc/<pid>` dirs | absent | intended (mask) |
| `/proc/self/fd` | only re-home mounts | cosmetic degrade for fd-enumerating tools |
| `/proc/self/environ` | absent | by design — canary probe re-spec required |
| `/proc/self/mounts`, `meminfo`, `cpuinfo`, `uptime`, `loadavg`, `sys/*` | absent | cosmetic degrade — no functional dep found |
| `ps` | absent in image anyway | moot |
| `exec /proc/self/fd/N` | works via re-home | functional — preserved |

## 0.5 — Decision: **GO**

Chosen path = plan candidate 2+3 (procfs-free argv + fd re-home), i.e. the
`sdk_noproc` class: drop the vendored tail `--bind /proc /proc` from the merged
stream, let denyRead's `--tmpfs /proc` be the realized mask, re-home every
command-side `/proc/self/fd/N` ref via `--ro-bind` of the resolved source,
fail closed (exit 65) on unresolvable refs. `systempaths=unconfined` NOT needed.

Open risk recorded (not gating): if prod's real command DOES wrap apply-seccomp,
its NEWUSER dies under our bpf the same under old and new mask — pre-existing
posture question, belongs to a follow-up, not this PR.
