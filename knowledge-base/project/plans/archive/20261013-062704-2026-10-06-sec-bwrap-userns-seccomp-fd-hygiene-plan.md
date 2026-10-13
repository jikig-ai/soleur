---
title: "security: shared bwrap seccomp filter denying nested user namespaces + close inherited fds in the agent sandbox"
type: fix
date: 2026-10-06
slug: sec-bwrap-userns-seccomp-fd-hygiene
branch: feat-one-shot-8752-bwrap-seccomp-fd-hygiene
issue: 8752
closes: [8752]
refs: [5862, 5941, 5873, 5849, 5733, 8623, 8696, 8732]
priority: p2
domain: engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

# security: shared bwrap seccomp filter denying nested user namespaces + close inherited fds in the agent sandbox

## Enhancement Summary

**Deepened on:** 2026-10-06
**Sections enhanced:** 6 (Research Insights, Proposed Solution, Phases 3–4, Edge Cases, Risks, References)
**Research agents used:** none spawned — `Reviewed-Coverage: sequential-fallback` (this harness exposes no Task/subagent tool; deepen halts, quality-check verifications, and the reviewer lenses below were executed inline by the orchestrator and are disclosed as such, never as independent review)

### Key Improvements (deepen pass)

1. **Interception verified against the SHIPPED artifact, not a stale bundle:** `@anthropic-ai/claude-code` 2.1.284 (which `@anthropic-ai/claude-agent-sdk` 0.3.284 spawns) is a bun-compiled native ELF binary, not a readable `cli.js`. Binary strings confirm `"bwrap" via PATH` resolution and the argv shape `bash -c '…shift && exec "$@"' … bwrap --args <fd> …` — the PATH shim intercepts, and `--args <fd>` in the real argv makes the shim's fd preserve-set load-bearing rather than hypothetical.
2. **New edge case found:** the binary embeds an `apply-seccomp` unix-socket-block helper that itself calls `unshare(CLONE_NEWUSER)` inside the sandbox — inert today (our config sets no `allowUnixSockets`) but a recorded constraint on enabling that knob later.
3. **Third canary probe added:** an in-sandbox fd-count assertion proves fd-hygiene (P2) at deploy time, not only the userns property.
4. **`bwrapPath` documented as a managed-settings-only knob** — not usable as our interception point and only a bypass vector if a managed settings file ever lands (none does on the replica).

### New Considerations Discovered

- `enableWeakerNestedSandbox` semantics clarified (it only skips `--proc /proc` in the SDK argv for container nesting — no conflict with the filter).
- The deferral criterion "SDK has its own seccomp filter" is now partially TRUE at the binary level (embedded `apply-seccomp` machinery + a `seccomp filter:` dep-check item) but remains the wrong layer and is inert for our config — recorded in Premise Validation.

## Overview

Implement the deferred shared bwrap sandbox hardening recorded by #8752 (filed by
the C4-render bwrap work, PR #8732 / ADR-050 amendment of 2026-09-24). Two gaps,
one shared control surface:

1. **Nested user namespaces.** A process inside either sandbox can call
   `unshare(CLONE_NEWUSER|…)` or `clone(…, CLONE_NEWUSER)` and become
   root-mapped in a fresh user namespace, reaching namespace-scoped kernel
   surface (nf_tables, netlink, per-userns limits). `bwrap --disable-userns` is
   measured broken on the production stack (bwrap 0.8.0 under
   `infra/seccomp-bwrap.json`: `cannot open /proc/sys/user/max_user_namespaces:
   Read-only file system`), so the denial must happen at the syscall layer: ONE
   `bwrap --seccomp` BPF program that returns EPERM for `clone`/`unshare`
   carrying `CLONE_NEWUSER`, and returns **ENOSYS** for `clone3` — clone3's
   flags live in a `clone_args` struct that seccomp cannot inspect, so clone3
   must be blanket-ENOSYS (never blanket-EPERM: glibc's posix_spawn prefers
   clone3 and only falls back to `clone` on ENOSYS, where the flag filter then
   applies — moby/moby#42680 is the authoritative precedent). Applied to BOTH
   bwrap argv paths: the C4 render argv (`buildLikeC4SandboxArgv` in
   `apps/web-platform/server/c4-render.ts`) and the Agent SDK sandbox argv
   (built inside `@anthropic-ai/claude-agent-sdk`'s vendored builder — the repo
   intercepts it via a bwrap PATH shim, the same mechanism the ADR-079 canary
   and the plugin-root propagation probe already use).
2. **Inherited file descriptors in the Agent SDK spawn.** bwrap and libuv close
   nothing: an fd the server holds without close-on-exec reaches the sandboxed
   process (measured: a secret file's fd was readable inside). The C4 launch
   chain already closes fds >3 via `CLOSE_FDS_SCRIPT` (`c4-render.ts`); the
   SDK's bwrap spawn does not. The same PATH shim closes every inherited fd
   that the SDK's own argv does not reference before `exec`ing real bwrap.

Deploy-canary validation per ADR-079 applies: the deploy-time replay path is
extended so the prod canary container proves the filter engages (a nested
`unshare -U` must fail, a nested `unshare -m` must still pass).

## Research Insights

### Premise Validation (Phase 0.6 — all cited artifacts verified)

- **Issue #8752 is OPEN** (`type/security`, `domain/engineering`, `priority/p2-medium`);
  not closed by any merged PR. Its re-evaluation criteria re-checked on 2026-10-06:
  - *"bwrap in the runner image moves past 0.8.0"* — **still 0.8.0.** Measured
    directly: `node:22-slim@sha256:4f77a690…` (the pinned base for all four
    Dockerfile stages) is Debian 12 bookworm; `apt-cache policy bubblewrap`
    inside it reports candidate `0.8.0-2+deb12u1`. `--disable-userns` remains
    unusable; `--seccomp` is the only syscall-layer path.
  - *"the agent sandbox gets its own seccomp filter"* — **moved further than
    the issue anticipated, still not sufficient.** The shipped
    `@anthropic-ai/claude-code` 2.1.284 native binary (spawned by
    `@anthropic-ai/claude-agent-sdk` 0.3.284) embeds `apply-seccomp` machinery
    and its dep-check UI lists a `seccomp filter:` line item. That facility is
    the INNER unix-socket-block filter applied to the sandboxed *command* —
    the wrong layer for this property (it is not a `bwrap --seccomp` on the
    sandbox argv), it fixes nothing about inherited fds, it self-disables when
    its helper is unavailable (`"apply-seccomp binary not available - unix
    socket blocking disab…"`), and our config does not even engage it
    (`allowUnixSockets` is unset). The bwrap-layer filter remains required.
  - *"`op=sandbox-selfprobe-fds` reports a non-zero count in production"* —
    telemetry exists (`reportInheritableFds`, `c4-render.ts` — warnSilentFallback,
    emits only when count > 0, count+kinds only never paths). The operator's
    direction to implement IS the re-evaluation trigger regardless.
- **Cited files all exist on `origin/main`:** `apps/web-platform/server/c4-render.ts`
  (`buildLikeC4SandboxArgv`, `CLOSE_FDS_SCRIPT`, `sandboxLaunch`,
  `verifyC4RenderSandboxOnce`, `reportInheritableFds`), `apps/web-platform/scripts/
  sandbox-canary.mjs`, `apps/web-platform/infra/seccomp-bwrap.json` (the DOCKER-level
  container profile — a different layer than the `bwrap --seccomp` filter),
  `apps/web-platform/infra/test-fixtures/sandbox-canary/`,
  `apps/web-platform/infra/sandbox-canary-argv.json` (committed captured argv).
- **How the repo already wraps SDK argv:** PATH shim, twice. `sandbox-canary.mjs`
  `--capture` puts a bwrap-intercepting Node shim on PATH to record the real SDK
  SETUP argv; `apps/web-platform/scripts/plugin-root-sandbox-propagation-probe.mjs`
  uses the same trick. The SDK resolves `bwrap` by bare name — verified against
  the SHIPPED artifact (deepen pass): `@anthropic-ai/claude-code` 2.1.284 ships
  a bun-compiled native ELF binary (`node_modules/@anthropic-ai/
  claude-code-linux-x64/claude`), and its strings contain the literal
  `resolving "bwrap" via PATH` plus the argv shape
  `bash -c '…shift && exec "$@"' … --args <fd> …`. Container PATH order verified
  on the pinned digest: `/usr/local/bin` precedes `/usr/bin` — a baked
  `/usr/local/bin/bwrap` intercepts every PATH-resolved bwrap in the image with
  zero env surgery. (`SandboxSettings.bwrapPath` exists but is documented
  "only honored from admin-controlled managed settings" — not a usable
  interception point from our programmatic config.)
- **Sibling issues:** #5862 (vendored SDK bwrap-arg reorder, ADR-075 TOCTOU exit
  criterion) is a DIFFERENT residual — this plan does not touch it. #5941
  (deploy-time nested-unshare probe in prod canary) overlaps with the new canary
  probe added here — disposition: acknowledge; the `-U` probe this plan adds is at
  the bwrap-filter layer, not #5941's container-profile split-unshare layer.
- **Mechanism vs ADR corpus (Phase 0.6 step 4):** no ADR rejects the proposed
  mechanism. ADR-050's 2026-09-24 amendment *names this deferral verbatim* and
  records `--disable-userns` as measured-broken; ADR-079 prescribes the canary
  contract; ADR-075's residual is the #5862 vendored reorder (distinct);
  ADR-122's boot-delivery pattern is for host-side profiles — our files are
  container-consumed, plain image-bake suffices.
- **Open Code-Review Overlap (Phase 1.7.5):** 87 open `code-review` issues
  queried; only #3243 (decompose cc-dispatcher.ts) and #3242 name
  `apps/web-platform/server/cc-dispatcher.ts`. This plan does NOT edit
  `cc-dispatcher.ts` (interception is PATH/env-based, no call-site change).
  Disposition: acknowledge — no fold-in.
- **CLI verification (Step 6 gate):** `bwrap --seccomp` verified against local
  `bubblewrap 0.12.0` (`bwrap --version`); flag exists since at least bwrap 0.3.3 (bwrap.xml documents it there; prod's 0.8.0 carries it).
  `unshare`, `prlimit`, `choom`, `nice`, `bash` verified present in the pinned
  base image via `docker run`.
- **Precedent-diff (deepen §4.4):** two sibling precedents adopted with named
  divergences. (a) fd-close loop — precedent `CLOSE_FDS_SCRIPT` (fixed `n -gt
  3` threshold); divergence: the shim replaces the fixed threshold with an
  argv-derived keep-set because the SDK argv legitimately references fds >3
  (`--args <fd>` verified in the shipped binary) — closing fd 3+ unconditionally
  would break the SDK spawn. (b) PATH shim — precedent `SHIM_SOURCE` in
  `sandbox-canary.mjs` (Node capture shim with `--version` pass-through);
  divergence: ours is dependency-free bash (runs per sandboxed Bash call — node
  startup ~50 ms vs bash ~2 ms, and bash is guaranteed present in the image)
  and is exec-terminating (capture vs enforcement role). No SQL/atomic-write/
  mutex patterns introduced.
- **External research (security topic → Phase 1.6 researched):**
  moby/moby#42680 + moby commit `9f6b562`: EPERM on clone3 is treated as fatal by
  glibc and breaks every posix_spawn/fork consumer; **ENOSYS forces fallback to
  `clone`, where flag-based filtering applies.** This validates the issue's
  ENOSYS mandate exactly, and invalidates the Vetto commenter's blanket-`-EPERM`
  suggestion for clone3 (their fd/seccomp direction is otherwise sound: close via
  `close_range(3, ~0U, 0)` or `/proc/self/fd` loop; the shim uses the latter —
  same mechanism as the proven `CLOSE_FDS_SCRIPT`). A second finding warns the
  inverse failure: a blanket `clone` deny (not flag-masked) kills all forking —
  our filter masks on `CLONE_NEWUSER` only.

### Property List (Phase 0.6b)

| # | Property (observable outcome) | Mechanism that buys it |
|---|---|---|
| P1 | No syscall inside either sandbox can create a NEW user namespace | ONE shared `bwrap --seccomp` BPF (clone/unshare `CLONE_NEWUSER` → EPERM; clone3 → ENOSYS) applied at both insertion points |
| P2 | No fd the server holds without close-on-exec reaches an agent-sandboxed process | Shim closes every fd >2 not referenced by the spawn's own fd-consuming argv options |
| P3 | Deploy-time proof the filter engages (and stays flag-selective) in the real container | Canary replay extension: `unshare -U` must EPERM, `unshare -m` must pass |
| P4 | A silent disengagement (PATH drift, missing artifact, shim bug) is detected, not invisible | Boot self-check (`op=sandbox-hardening-selfprobe`) + canary verdict + existing `op=sandbox-selfprobe-fds`/`sdk-startup` telemetry |

### Cut List (Phase 0.6b)

- **`bwrap --disable-userns`** — buys P1 but measured broken on the stack
  (bwrap 0.8.0 + RO `/proc/sys`). Already rejected by ADR-050 amendment's own table.
- **SDK `sandbox.seccomp.{bpfPath,applyPath}`** — could carry an inner filter for
  the SDK side only; rejected: (a) vendored `apply-seccomp` binaries are not in the
  installed package — the knob is inert; (b) it cannot serve the C4 path so the
  "ONE filter" property would fork; (c) it fixes nothing about inherited fds.
- **Vendored/patched SDK bwrap builder** — #5862 already tracks vendoring for the
  argv-reorder TOCTOU; folding a second vendor-hack into this PR doubles review
  surface and blocks on upstream shape. PATH shim is the repo's existing
  interception pattern and needs no SDK internals.
- **Server-wide O_CLOEXEC retrofit** — auditing every `open`/`fs.open` in server/
  for missing cloexec is a large census; the shim closes the leak AT the spawn
  boundary (structural coverage, one chokepoint) — the enumeration stays as
  `op=sandbox-selfprobe-fds` telemetry so any new leak is still counted.

### File & symbol anchors (from repo research)

- `apps/web-platform/server/c4-render.ts` — `CLOSE_FDS_SCRIPT` (bash `/proc/self/fd`
  loop, closes `n -gt 3`), `buildLikeC4SandboxArgv` (pure argv builder, the
  `--seccomp` insertion point), `sandboxLaunch` (bash→choom→nice→bwrap chain),
  spawn site (`stdio: ["ignore","pipe","pipe","pipe"]`, fd 3 = `--json-status-fd`),
  `verifyC4RenderSandboxOnce` + `reportInheritableFds` (boot probes; called from
  `server/index.ts` listen callback).
- `apps/web-platform/server/agent-runner-sandbox-config.ts` —
  `buildAgentSandboxConfig` (shared literal for BOTH consumers: `startAgentSession`
  and `cc-dispatcher.ts`'s `realSdkQueryFactory`; drift-guarded by
  `agent-runner-helpers.test.ts`). No argv insertion point exists here — the argv
  is built inside the SDK.
- `apps/web-platform/server/agent-env.ts` — `AGENT_ENV_ALLOWLIST` copies `PATH`
  verbatim into the agent subprocess env → the agent env inherits container PATH
  → `/usr/local/bin/bwrap` intercepts with no env change.
- `apps/web-platform/scripts/sandbox-canary.mjs` — `buildBwrapInvocation`
  (replay spawns bare `cmd:"bwrap"` via PATH → the baked shim intercepts replay
  automatically); `SHIM_SOURCE` (the capture-shim precedent incl. the `--version`
  pass-through the real shim must also honor — the SDK probes `bwrap --version`
  for availability); `BWRAP_ONE_ARG_OPAQUE` (enumerates fd-bearing options:
  `--seccomp`, `--add-seccomp-fd`, `--sync-fd`, `--info-fd`, `--json-status-fd`,
  `--block-fd`, `--userns-block-fd` — plus `--args` handled separately).
- `apps/web-platform/scripts/sandbox-canary-regression.test.sh` — layer-B
  argv-independent nested-unshare probe runs against the committed profile in CI.
- `apps/web-platform/Dockerfile` — apt `bubblewrap` (line: `RUN apt-get update &&
  apt-get install -y --no-install-recommends ca-certificates git bubblewrap socat
  qpdf jq openssh-client`); `COPY --from=builder /app/infra/sandbox-canary-argv.json`
  precedent for baking an `infra/` artifact into the image; the `/usr/local/bin`
  PATH-order verified on the pinned digest.
- `apps/web-platform/scripts/sdk-bump-sandbox-gate.sh` — the SDK-bump ack gate;
  the shim adds no new gate but rides the same "SDK argv shape is a reviewed
  surface" contract.
- `apps/web-platform/test/` — `c4-render-sandbox.test.ts` (argv-shape +
  `C4_BWRAP_REQUIRED=1` real-bwrap rows — the functional-test precedent),
  `sandbox-canary.test.ts`, `agent-runner-helpers.test.ts` (sandbox-config drift
  guard), `agent-sandbox-sibling-deny.test.ts`.

### Institutional learnings applied

- `2026-09-24-sandboxing-a-render-child-with-bwrap-no-writable-host-bind.md` —
  the sibling learning for this exact file: fd-close mechanism, `--json-status-fd`
  classification, mount-order trap, `--disable-userns` residual (→ this plan).
- `bwrap-sandbox-three-layer-docker-fix-20260405.md` /
  `docker-seccomp-blocks-bwrap-sandbox-20260405.md` — the container profile vs
  bwrap-layer distinction this plan's title already encodes.
- `2026-08-10-a-guard-that-cannot-be-driven-red-is-vacuous-…` — Guard Contract
  written BEFORE the guard, matrix rows target the guard's own dispatch.
- `2026-07-01-blind-surface-needs-structured-probe-…` — the agent sandbox is a
  listed blind surface: `failure_modes` rows must name in-surface probes with
  discriminating structured fields, not host-side eyeballs.
- `2026-05-07-dockerfile-assertion-qa-via-docker-run` — Dockerfile behavior was
  verified against the pinned digest with `docker run`, not assumed.

## Research Reconciliation — Spec vs. Codebase

| Spec/issue claim | Codebase reality (verified) | Plan response |
|---|---|---|
| "The C4 render now closes fds in a bash step before its launch chain" | `CLOSE_FDS_SCRIPT` + `sandboxLaunch` exist exactly as described (closes `>3`, keeping `--json-status-fd 3`) | Reuse the same prelude shape; extend it to open the filter fd fail-closed |
| "the Agent SDK's bwrap spawn does not [close fds]" | SDK argv is built inside the vendored cli.js; no fd-close exists on that path | PATH shim performs the close before `exec`ing real bwrap |
| "production's bwrap 0.8.0" | Pinned base measured: bookworm, `bubblewrap 0.8.0-2+deb12u1` | Design targets `bwrap --seccomp FD`/`--add-seccomp-fd` (documented since 0.3.3/0.6.x) — compatible |
| External commenter: "Returning `-EPERM` ensures child processes cannot nest" | Correct for clone/unshare but WRONG for clone3 (moby#42680: EPERM is fatal to glibc's fallback; only ENOSYS triggers the clone fallback) | Treat comment as context: clone3 gets blanket-ENOSYS per the issue body, never EPERM |
| "one `bwrap --seccomp` BPF filter… applied to BOTH" | The SDK argv is unreachable without interception; PATH shim is the repo's interception precedent (×2) | One committed `.bpf` artifact, two insertion points: argv flag (C4) + shim injection (SDK) |

## Problem Statement

Both replica sandboxes share two exploitable gaps. A sandboxed process can create
a nested user namespace (unshare/clone with `CLONE_NEWUSER`; clone3 bypasses any
flag-based filter because its flags are struct-hidden), gaining capabilities in
its own namespace and reaching kernel surface the outer sandbox cannot see. And
every fd the server process holds without `O_CLOEXEC` is silently inherited into
the SDK-spawned sandbox — measured live with a secret file. The C4 launch chain
closes that fd window for ITS spawn only; the SDK path — which gives every
tenant arbitrary code execution BY DESIGN — has neither protection. The issue was
deferred pending operator re-evaluation; the operator has now directed
implementation.

## Proposed Solution

Three artifacts, two insertion points, one shared filter:

1. **`apps/web-platform/scripts/gen-bwrap-userns-seccomp.mjs`** — a Node
   generator emitting a serialized `sock_fprog` for x86_64 (plus the
   `__X32_SYSCALL_BIT`-masked variants of the same three rules as cheap
   defense-in-depth). Ruleset: arch gate (non-x86_64 → `SECCOMP_RET_KILL_PROCESS`);
   `clone3` (435) → `RET_ERRNO(ENOSYS)`; `clone` (56) and `unshare` (272) → inspect
   `args[0]` low word, `CLONE_NEWUSER` (0x10000000) set → `RET_ERRNO(EPERM)`;
   everything else → `RET_ALLOW`. Generated bytes committed as
   `apps/web-platform/infra/bwrap-userns-clone3-deny.bpf` — reviewed as a
   generated artifact with a byte-parity test, never hand-edited.
2. **C4 insertion point** — `buildLikeC4SandboxArgv` gains `--seccomp <FD>`; the
   `CLOSE_FDS_SCRIPT` prelude, after closing all fds >3, opens the filter on a
   fixed fd (`exec 9<"$SOLEUR_BWRAP_SECCOMP_BPF"`, fail-closed `|| exit 65`)
   so fd 9 survives the choom/nice exec chain into bwrap. Filter path default
   `/app/infra/bwrap-userns-clone3-deny.bpf`, env-overridable for tests.
3. **SDK insertion point** — a bash shim baked at `/usr/local/bin/bwrap`
   (root-owned 0755; `/usr/local/bin` precedes `/usr/bin` in the image PATH —
   verified). For `--version`/`--help`-only invocations it execs real bwrap
   verbatim (the SDK's availability probe must keep working). For setup
   invocations it: parses its own argv for the fd-consuming options
   (`--args`, `--seccomp`, `--add-seccomp-fd`, `--sync-fd`, `--info-fd`,
   `--json-status-fd`, `--block-fd`, `--userns-block-fd`), records their fd
   numbers as a preserve-set; opens the filter on an auto-allocated fd
   (`exec {bpf_fd}<"$SOLEUR_BWRAP_SECCOMP_BPF"` — cannot collide with the
   preserve-set); closes every `/proc/self/fd` entry >2 not in the preserve-set,
   not the bpf fd, and not the shim's own script fd; then
   `exec /usr/bin/bwrap --seccomp "$bpf_fd" "$@"`. Fail-closed (`exit 65` +
   `bwrap-shim:` stderr marker) when the filter or real bwrap is unreadable —
   consistent with `failIfUnavailable: true` posture, and the marker lands inside
   the existing `sandbox-startup-classifier` token set (`seccomp`).

## Technical Approach

### Implementation Phases

#### Phase 1 — Shared filter artifact + generator + semantics test

- `scripts/gen-bwrap-userns-seccomp.mjs` (new): pure-Node emitter of the
  `sock_fprog` binary above; `--check` mode byte-compares against the committed
  artifact. x86_64 syscall numbers + `__X32_SYSCALL_BIT` variants; arm64 noted
  as out of scope (prod replicas are amd64).
- `infra/bwrap-userns-clone3-deny.bpf` (new, generated, committed).
- `test/bwrap-userns-seccomp.test.ts` (new): (a) regeneration byte-parity;
  (b) disassembly semantics — decode the committed sock_fprog and assert the
  exact ruleset (arch gate present; clone3 → ENOSYS unconditional; clone/unshare
  flag-masked on `CLONE_NEWUSER` → EPERM; default ALLOW); (c) real-bwrap
  functional rows under the `C4_BWRAP_REQUIRED=1` precedent: inside a filtered
  sandbox, `unshare -U true` fails, `unshare -m true` succeeds (flag-selective),
  a posix_spawn consumer works (clone3 ENOSYS → clone fallback). The env-gated
  rows MUST carry a ran-presence assertion — a `skipIf` suite exits 0 with the
  check dark (#8878-shaped trap): name the CI-side assertion that proves the
  real-bwrap rows executed in the bwrap-capable environment, not merely
  skipped.
- Suite registration: every new `*.test.ts` lands under
  `apps/web-platform/test/` (the `vitest.config.ts` `test/**/*.test.ts` glob —
  verified against `vitest.config.ts` and the `c4-render-sandbox.test.ts`
  precedent) so `lint-orphan-test-suites.sh` counts them as run, not orphaned.
- Success: artifact committed; semantics test asserts the ruleset independent of
  bwrap availability.

#### Phase 2 — C4 render argv integration

- `server/c4-render.ts`: `buildLikeC4SandboxArgv` emits `--seccomp 9` among the
  setup args (position among flags, before `--`); `CLOSE_FDS_SCRIPT` gains the
  post-close filter-open line (fail-closed). `SOLEUR_BWRAP_SECCOMP_BPF` env
  override; default `/app/infra/bwrap-userns-clone3-deny.bpf`.
- `test/c4-render-sandbox.test.ts` (+ `-tenant-config` rows as needed): argv-shape
  assertion for the flag; real-bwrap row: `unshare -U` inside the render sandbox
  fails, render still completes end-to-end.
- Success: prod-shaped render works with the filter; nested userns denied.

#### Phase 3 — Agent SDK shim (fd hygiene + filter injection)

- `infra/bwrap-shim/bwrap` (new): the bash shim described above; `SOLEUR_BWRAP_REAL`
  env override for the real-binary path in tests (default `/usr/bin/bwrap`).
- `test/bwrap-shim.test.ts` (new): run the shim against a stub "real bwrap"
  recorder — asserts `--seccomp` injection with a valid fd; `--args`/`--sync-fd`/
  `--json-status-fd`-referenced fds preserved while an unrelated leaked fd is
  closed; `--version` pass-through; fail-closed on missing filter. The stub
  must replay the REAL bwrap contract (argv recording, fd readability check per
  `--args`-consumed fd, exit-code propagation), not the consumer's reading of
  it — a fake written to the author's mental model hides the bug it tests
  (#8642 shape).
- `Dockerfile`: `COPY` the shim to `/usr/local/bin/bwrap` and the `.bpf` to
  `/app/infra/` (two lines, placed with the other `infra/` COPY block; shim
  root-owned 0755 — inside the container only `soleur` reads it; root ownership
  prevents the runtime user from rewriting the interception point).
- Success: a non-cloexec fd held by the server is unreadable inside the SDK
  sandbox (the measured leak closes); nested `unshare -U` inside EPERMs.

#### Phase 4 — Deploy canary + boot self-check (ADR-079 contract)

- `scripts/sandbox-canary.mjs`: extend the replay leg with three derived probes
  sharing the captured setup argv — (a) `bwrap <argv> -- unshare -U true` MUST
  exit non-zero (EPERM; else verdict `userns_filter_bypass`); (b)
  `bwrap <argv> -- unshare -m true` MUST exit 0 (else verdict
  `userns_filter_overbroad`); (c) an in-sandbox fd census —
  `bwrap <argv> -- sh -c 'ls /proc/self/fd | wc -l'` MUST stay within the
  derived bound `3 (stdio) + #(fd-consuming args in the captured argv) + 1
  (the /proc dirfd itself)` (else verdict `fd_hygiene_bypass`) — deepened to
  prove P2 at deploy time, not only P1. Probes are derived constants, not
  fixture fields — `sandbox-canary-argv.json` unchanged; `--verify`/byte-diff
  unaffected. `classifyReplayVerdict`/`emitVerdict` carry the new verdicts;
  `ci-deploy.sh` already surfaces any non-PASS verdict to deploy-state + Sentry.
- `test/sandbox-canary.test.ts` + `scripts/sandbox-canary-regression.test.sh`:
  verdict-contract rows for the three probes; a regression layer asserting the
  probe invocations exist in the replay code path.
- `server/c4-render.ts` (`verifyC4RenderSandboxOnce` — or a sibling emitted from
  the same `server/index.ts` call site): boot self-check asserts
  `command -v bwrap` resolves to the shim path AND the filter artifact is
  present non-empty → `feature:"agent-sandbox", op:"sandbox-hardening-selfprobe"`
  Sentry info on pass / `warnSilentFallback` on any check failing. Existing
  `reportInheritableFds` (`op=sandbox-selfprobe-fds`) is RETAINED unchanged —
  it now measures what the shim closes at the boundary, and any new leak source
  still counts.
- Success: deploy canary proves engagement per-deploy; boot probe proves
  placement per-container-start; no SSH anywhere in the loop.

#### Phase 5 — ADR amendments + docs

- ADR-075 — append `## Amendment — <merge-date> (#8752)`: bwrap-layer seccomp
  (clone/unshare `CLONE_NEWUSER` → EPERM, clone3 → ENOSYS) applied via the shared
  filter + PATH shim; fd hygiene at the spawn boundary. The per-sibling denyRead
  residual and its #5862 exit criterion are UNCHANGED (distinct residual).
- ADR-050 — extend the 2026-09-24 amendment's residual list: the recorded
  "nested user namespaces tracked in #8752" and "inherited fds in other spawners"
  residuals now have their closer.
- `apps/web-platform/scripts/bwrap-userns-seccomp-probe.sh` (new — the
  discoverability command, see Observability).

## Alternative Approaches Considered

| Approach | Verdict | Reason |
|---|---|---|
| `bwrap --disable-userns` | Rejected | Measured broken on the production stack (bwrap 0.8.0 + RO `/proc/sys`); recorded in ADR-050 amendment |
| SDK `sandbox.seccomp.{bpfPath,applyPath}` inner filter | Rejected | Vendored `apply-seccomp` binary not shipped in 0.3.284 (knob inert); SDK-side only (forks the "ONE filter" property); cannot close inherited fds |
| Vendor/patch the SDK bwrap builder | Rejected (deferred to #5862) | #5862 already owns SDK vendoring for the argv-reorder TOCTOU; two vendor-hacks in one PR doubles blast radius; PATH shim is the repo's established interception mechanism |
| clone3 → EPERM (Vetto comment) | Rejected | glibc treats non-ENOSYS clone3 failure as fatal — breaks posix_spawn/fork fleet-wide (moby/moby#42680). ENOSYS triggers the clone fallback where the flag filter applies |
| Blanket `clone`/`unshare` deny | Rejected | Kills all forking/threading inside the sandbox (the LinuxAgent commit regression); flag-mask on `CLONE_NEWUSER` only |
| Server-wide O_CLOEXEC audit | Rejected as the fix (kept as telemetry) | Enumeration of every `open` is a snapshot; the shim closes the window at the spawn chokepoint — structural, covers future fd sources |
| New container-profile rules (seccomp-bwrap.json) | Rejected | Wrong layer — the container profile must ALLOW `CLONE_NEWUSER` for bwrap itself to work; the nested-deny must live inside the sandbox's own filter |

## User-Brand Impact

- **If this lands broken, the user experiences:** every agent session and C4
  render on the replica failing — the `bwrap-shim:`/`bwrap: … seccomp` error
  surfaces as sandbox-startup failures on all tenant sessions at once
  (the ENOSYS-vs-EPERM choice is precisely what stands between "hardened" and
  "hard-failed"), or a C4 save that renders nothing.
- **If this leaks, the user's data is exposed via:** (a) a nested user namespace
  giving a tenant's sandboxed process namespace-scoped kernel surface beyond the
  declared boundary; (b) an inherited non-cloexec fd (e.g., a secret file, a
  sibling-workspace handle, a socket) readable inside the sandbox — measured
  live on the replica.
- **Brand-survival threshold:** `single-user incident` — one tenant's secret
  readable by another tenant's agent session is a single-tenant breach the brand
  cannot absorb.
- **Threshold decision (challengeable):** the failure mode is cross-tenant
  isolation, whose unit of harm is a single leaked secret/session — the same
  tier the C4-hardening brainstorm set for a strictly weaker blast radius.

CPO sign-off is required at plan time before `soleur:work` begins (frontmatter
`requires_cpo_signoff: true`). At review time
`soleur:engineering:review:user-impact-reviewer` enumerates failure modes
against the diff (review-skill conditional agent; headless note for the
pipeline).

**GDPR gate (Phase 2.7, fired via trigger (b) — threshold `single-user incident`;
inline advisory, Task spawn unavailable in this harness):** no new processing of
personal data; the new telemetry emits counts/kinds and resolution booleans
only — never fd paths (existing `reportInheritableFds` contract) — and rides the
already-declared Sentry sink with `userIdHash` pseudonymization. No Art. 9
category, no new lawful basis, no Art. 30 row, no DSAR surface change. Advisory:
no compliance-posture.md write required.

## Observability

The agent sandbox is a listed blind surface (Phase 2.9.2): every failure mode
names an in-surface or in-container probe whose structured fields discriminate
the competing root causes in one event.

```yaml
liveness_signal:
  what: "deploy-time sandbox canary verdict + per-boot sandbox-hardening selfprobe"
  cadence: "per deploy (ci-deploy.sh canary leg) + per container start (server/index.ts listen callback)"
  alert_target: "Sentry web-platform events → issue alert; deploy-state on /hooks/deploy-status"
  configured_in: "apps/web-platform/scripts/sandbox-canary.mjs (replay probes) + apps/web-platform/server/c4-render.ts (verifyC4RenderSandboxOnce) + apps/web-platform/infra/ci-deploy.sh (verdict surfacing)"

error_reporting:
  destination: "Sentry web-platform via SENTRY_DSN (reportSilentFallback / warnSilentFallback contract)"
  fail_loud: "op=sandbox-hardening-selfprobe warn event; canary verdict userns_filter_bypass|userns_filter_overbroad; op=sdk-startup Sentry event when a legit spawn breaks; bwrap-shim: stderr marker classified by sandbox-startup-classifier"

failure_modes:
  - mode: "shim not engaged (PATH drift, base-image PATH reorder, SDK absolute-path drift)"
    detection: "boot self-check fields {shimResolved, shimPath, filterPresent, filterBytes} emitted from inside the container; deploy canary unshare -U probe as the behavioral backstop"
    alert_route: "op=sandbox-hardening-selfprobe warnSilentFallback → Sentry; canary verdict → deploy-state + Sentry"
  - mode: "filter present but not engaging (shim injection bug, fd plumbing loss)"
    detection: "in-sandbox behavioral probe: unshare -U inside the replayed real argv MUST fail (expected-EPERM inversion — a PASS here means the filter is dead)"
    alert_route: "canary verdict userns_filter_bypass → deploy-state + Sentry"
  - mode: "filter over-broad (denies more than CLONE_NEWUSER — e.g. blanket unshare/clone deny)"
    detection: "in-sandbox behavioral probe: unshare -m inside the same argv MUST succeed"
    alert_route: "canary verdict userns_filter_overbroad → deploy-state + Sentry"
  - mode: "server holds a new non-cloexec fd source (the leak the shim now closes at the boundary), or the shim's close loop regresses"
    detection: "existing op=sandbox-selfprobe-fds warn event — count+kinds only, never paths — PLUS the in-sandbox canary fd-census probe (behavioral backstop inside the surface itself)"
    alert_route: "warnSilentFallback → Sentry (existing); canary verdict fd_hygiene_bypass → deploy-state + Sentry"
  - mode: "legitimate spawn broken by ENOSYS mishandling (posix_spawn/posix consumer)"
    detection: "sandbox-startup-classifier op=sdk-startup Sentry event carrying sandboxKind + stderr; C4 boot selfprobe failure for the render side"
    alert_route: "existing ADR-079 emit sites (agent-runner / cc-dispatcher mirrors)"

logs:
  where: "pino child logger 'agent-sandbox' + 'c4-rerender' container logs → Vector → Better Stack (WARN+); Sentry events per above"
  retention: "existing pipeline retention; Sentry event retention per project"

discoverability_test:
  command: bash apps/web-platform/scripts/bwrap-userns-seccomp-probe.sh
  expected_output: "USNS_SECCOMP_OK or USNS_SECCOMP_SKIP_NO_BWRAP"
```

`bwrap-userns-seccomp-probe.sh` (committed in this PR): verifies the committed
`.bpf` is present non-empty, regenerates it via the generator `--check`, asserts
the shim file exists, and — when `bwrap` is installed — runs the two behavioral
probes through the shim (nested `unshare -U` must fail, `unshare -m` must pass,
a posix_spawn consumer must succeed). Prints exactly `USNS_SECCOMP_OK` on the
verified path, `USNS_SECCOMP_SKIP_NO_BWRAP` when bwrap is absent, and fails
noisily otherwise. Single-digit seconds either way.

**Soak Follow-Through Enrollment:** not triggered — no AC declares a
post-deploy time-gated close criterion (validation is per-deploy + per-boot, not
N-day soak).

## Guard Contract

The deliverable includes two drift-checks — written here BEFORE the guards.

### Guard 1 — seccomp-engagement census

**Property.** Every bwrap launch path inside the web-platform replica container
applies the shared `bwrap-userns-clone3-deny` filter.

**Assembly.** All three insertion surfaces, quantified structurally: (a) argv
builders — `buildLikeC4SandboxArgv`'s emitted token stream must contain a
`--seccomp` flag whose fd argument the launch prelude opens fail-closed (C4 is
the ONLY argv builder in the repo — census via `rg --seccomp` over
`apps/web-platform/server/`); (b) PATH resolution — the Dockerfile must COPY a
bwrap shim ahead of `/usr/bin` (the SDK's `Zn("bwrap")` bare-name lookup is the
chokepoint — every SDK spawn resolves through PATH); (c) the deploy canary —
its replay leg must carry the two behavioral probes, so an unfiltered prod
spawn CANNOT green. The anti-vacuity floor asserts ≥2 distinct insertion sites
are checked (a guard reporting "0 checked" is vacuous).

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete `--seccomp` from `buildLikeC4SandboxArgv`'s output | RED — argv-builder census row fails |
| 2 | Delete the shim's `--seccomp` injection but keep `exec /usr/bin/bwrap` (shim becomes a passthrough) | RED — shim-content assertion fails |
| 3 | Remove any of the canary's three probes (`unshare -U`, `unshare -m`, fd census) while keeping the main replay | RED — probe-contract assertion fails (the deploy-time safety net is itself guarded) |
| 4 | Add a second argv-builder/spawn site that reaches bwrap without the filter (e.g. a new `BWRAP_BIN` caller) | RED — census requires EVERY enumerated site to carry engagement evidence |
| 5 | (harness) Make the census count zero sites (stub the grep) | RED — floor assertion `sites >= 2` fails, not green |
| 6 | (must-pass) Reorder `--seccomp` to a different position among setup args | PASS — the guard asserts engagement, not byte-position |

**Anchor.** The committed `.bpf` bytes are verified by regeneration-parity —
a weakened hand-edit of the artifact fails the byte-compare unless the
generator is ALSO weakened in the same diff; both files are in this PR's diff
surface (single-PR consistency), and the disassembly test independently asserts
rule semantics so a consistent-but-wrong pair still reds.

### Guard 2 — spawn fd-keep-set hygiene

**Property.** No file descriptor reaches the sandboxed process that is not
stdio (0-2) or explicitly referenced by the spawn's own fd-consuming argv
options.

**Assembly.** The shim's `/proc/self/fd` enumeration at exec time — the
chokepoint is the fd table itself, not a list of fd producers (a new server
fd source is closed automatically; assembly is structural). Plus the preserve-set
parser covering the fd-consuming option vocabulary (`--args`, `--seccomp`,
`--add-seccomp-fd`, `--sync-fd`, `--info-fd`, `--json-status-fd`, `--block-fd`,
`--userns-block-fd`) — the same set `sandbox-canary.mjs` already enumerates for
argv parsing, so the vocabulary has one documented home.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Drop `--args` from the preserve-set while the stub argv passes `--args 5` | RED — stub real-bwrap can no longer read fd 5; test detects the closed fd |
| 2 | Skip the close loop entirely (shim injects --seccomp but never closes) | RED — an unrelated leaked fd (fixture fd 7) remains readable inside the stub spawn |
| 3 | Close fd 3 unconditionally (regress to the C4 `>3` rule) | RED — SDK argv legitimately uses fds >3; the keep-set is argv-derived, not a fixed threshold |
| 4 | (must-pass) Spawn with `--args 5` on a live fd | PASS — fd 5 readable by real-bwrap stub, all others >2 closed |

## Domain Review

**Domains relevant:** Engineering

### Engineering

**Status:** reviewed (inline — this harness exposes no Task/subagent spawn;
the assessment below is the orchestrator's, carrying the same content the
CTO-lens pass would: chokepoint selection, layer correctness, residual naming)

**Assessment:** the bwrap-layer filter is the correct chokepoint — it sits at
the sandbox boundary itself, covers both argv producers with ONE artifact, and
cannot be weakened by an SDK-builder change (the SDK could reorder every setup
arg and `--seccomp` still applies because the shim injects it). The inner
`sandbox.seccomp` knob is the wrong layer (and inert — binaries unshipped).
Fd hygiene belongs at the spawn boundary, not a server-wide cloexec audit —
the enumeration is a snapshot, the boundary close is structural. Residuals
named, not closed: `setns(2)` into a pre-existing userns is NOT denied (no
fd to a foreign userns is reachable inside the sandbox — `/proc` is denied and
no ns fds are passed in; revisit if a leak path emerges); clone3 blanket-ENOSYS
is an accepted semantic residual per the moby reasoning (any future runtime
REQUIRING clone3-only features fails — detection path is the sdk-startup
classifier).

### Product/UX Gate

**Tier:** none — Files-to-Create/Edit contain no UI-surface paths (no `*.tsx`,
no `app/**/page|layout`, no `components/**`); mechanical override does not fire
and the semantic sweep finds no user-facing surface. A sandbox change is
invisible UI-wise.

All 8 domains swept semantically (Marketing, Engineering, Operations, Product,
Legal, Sales, Finance, Support): only Engineering is relevant. Operations
note — no new infrastructure is provisioned (Phase 2.8 silent: files are
image-baked and deploy via the existing release pipeline; no Terraform, no
host change, no dashboard step). Legal note — the inline GDPR advisory above
records no regulated-data surface.

## Architecture Decision (ADR/C4)

Phase 2.10 fires: this changes a trust-boundary invariant (every bwrap launch on
the replica carries a shared syscall filter + fd hygiene — a new cross-cutting
invariant all sandbox consumers must honor).

### ADR

- **Amend ADR-075** (`ADR-075-agent-sandbox-tenant-read-isolation.md`) — new
  amendment block recording the shared bwrap-layer seccomp filter and the
  spawn-boundary fd hygiene; explicitly states the per-sibling denyRead
  residual + #5862 exit criterion is UNCHANGED (distinct residual — prevents
  a reader conflating "the sandbox residual closed" with the TOCTOU one).
- **Amend ADR-050** (`ADR-050-likec4-runtime-rerender-via-out-of-process-cli.md`)
  — extend the 2026-09-24 amendment's residual table: the "nested user
  namespaces" row and the "inherited fds in other spawners" row gain their
  closer (#8752 → this PR).

No NEW ADR: the decision extends two existing ADRs' own recorded residuals —
a new ordinal would split the story from its history. (This also avoids the
ordinal-collision class entirely.)

### C4 views

**No C4 impact.** Enumeration per the completeness mandate (all three model
files read — `model.c4` element inventory, `views.c4` include lists, `spec.c4`):
(a) external human actors — founder, betaContact, contributor, emailSender,
publicReader all already modeled; the change adds none; (b) external
systems/vendors — none new (a kernel syscall filter and a PATH shim add no
integration); (c) containers/data-stores — the filter and shim live INSIDE the
already-modeled `platform.webapp` Agent Runtime container and the image build;
no new container or store; (d) actor↔surface relationships — unchanged (no
access-relationship boundary moves). The sandbox's internal hardening is below
the C4 abstraction line, matching how the existing bwrap/AppArmor layer is
(un)modeled.

### Sequencing

Both amendments land in THIS PR describing the shipped state — no soak-gated
target state (the control is binary: filter engages or the canary fails).

## Encryption Posture

Skipped — no persistent data store and no new cross-component/network
connection is introduced (a file baked into the image and a PATH shim are
neither).

## Infrastructure (IaC)

Skipped — no new provisioned resource (no server, service, cron, vendor account,
DNS record, secret, firewall rule, or monitoring webhook). The shim + filter are
baked into the runner image by two `COPY` lines and ship through the existing
release pipeline; deployment needs no provisioning change.

## Open Code-Review Overlap

87 open `code-review` issues checked against the planned file set. Matches:
#3243 (decompose `cc-dispatcher.ts`) and #3242 name
`apps/web-platform/server/cc-dispatcher.ts`. **Disposition: acknowledge** — this
plan does not edit `cc-dispatcher.ts` (interception is PATH-based; no call-site
change), so neither scope-out is folded in. All other planned files: None.

## Scope Check

### Ask Mapping

| # | User ask (verbatim) | Plan item | Status |
|---|---------------------|-----------|--------|
| 1 | "ONE bwrap --seccomp BPF filter that denies CLONE_NEWUSER in clone/unshare and returns ENOSYS for clone3" | FR-1 / Phase 1 / `gen-bwrap-userns-seccomp.mjs` + `bwrap-userns-clone3-deny.bpf` | mapped |
| 2 | "applied to BOTH the C4 render argv (buildLikeC4SandboxArgv in apps/web-platform/server/c4-render.ts)" | FR-2 / Phase 2 / `c4-render.ts` edits | mapped |
| 3 | "and the Agent SDK sandbox argv (built by @anthropic-ai/claude-agent-sdk's vendored bwrap builder — find how the repo already patches or wraps SDK argv)" | FR-3 / Phase 3 / `infra/bwrap-shim/bwrap` + Dockerfile | mapped |
| 4 | "close inherited file descriptors in the Agent SDK bwrap spawn" | FR-3 / Phase 3 / shim fd-keep-set close loop | mapped |
| 5 | "during planning re-check the issue's stated criteria: whether the pinned node:22-slim base image's bubblewrap has moved past 0.8.0… whether the agent sandbox has since gained its own seccomp filter, and what op=sandbox-selfprobe-fds telemetry exists" | Premise Validation (done — recorded in Research Insights) | mapped |
| 6 | "Deploy-canary validation per ADR-079 applies" | FR-5 / Phase 4 / `sandbox-canary.mjs` replay probes | mapped |
| 7 | "the plan must declare an Observability block with a no-SSH discoverability_test command" | `## Observability` / `bwrap-userns-seccomp-probe.sh` | mapped |
| 8 | "An external comment on the issue by the Vetto maintainer is directionally correct … but misses the clone3/ENOSYS subtlety — treat it as context, never as spec" | Alternative Approaches row + Research Reconciliation row | mapped |

### Plan-Item Provenance

| Plan item | User words cited (verbatim quote) | Verdict |
|-----------|-----------------------------------|---------|
| `gen-bwrap-userns-seccomp.mjs` + `.bpf` artifact | "ONE bwrap --seccomp BPF filter" | asked |
| `c4-render.ts` --seccomp + prelude edit | "applied to BOTH the C4 render argv (buildLikeC4SandboxArgv in apps/web-platform/server/c4-render.ts)" | asked |
| `infra/bwrap-shim/bwrap` + Dockerfile COPY | "the Agent SDK sandbox argv … find how the repo already patches or wraps SDK argv" | asked |
| Shim fd keep-set close loop | "close inherited file descriptors in the Agent SDK bwrap spawn" | asked |
| `sandbox-canary.mjs` replay probes | "Deploy-canary validation per ADR-079 applies" | asked |
| Boot self-check + Observability block + probe script | "the plan must declare an Observability block with a no-SSH discoverability_test command" | asked |
| ADR-050/ADR-075 amendments | — | inferred — plan Phase 2.10 makes the ADR write a deliverable of THIS plan; the amendments close recorded residuals and must not lag the change |
| `bwrap-userns-seccomp.test.ts`, `bwrap-shim.test.ts`, `c4-render-sandbox.test.ts`/`sandbox-canary.test.ts` updates | — | inferred — `cq-write-failing-tests-before` + Guard Contract deliverables; a security control without mutation-tested assertions is unverifiable |
| Guard Contract (2 guards) | — | inferred — plan Phase 2.12 fires: the deliverable includes drift-checks (engagement census + keep-set hygiene) |

### Split Assessment

- Subsystems touched: 1 — `apps/web-platform` (plus `knowledge-base/` docs)
- Planned files: ~12 | Estimated changed lines: ~700
- Thresholds: >= 4 subsystem roots OR > 25 planned files OR > 800 estimated lines
- Recommendation: single PR

## Acceptance Criteria

### Functional Requirements

- [ ] FR-1: A committed generator (`apps/web-platform/scripts/gen-bwrap-userns-seccomp.mjs`)
  emits the shared filter; `apps/web-platform/infra/bwrap-userns-clone3-deny.bpf`
  is the committed artifact, regenerated byte-identically by `--check`.
- [ ] FR-2: The filter's semantics, asserted by a disassembly test on the
  committed bytes: arch gate present; `clone3` → ENOSYS unconditionally;
  `clone`/`unshare` → EPERM iff `CLONE_NEWUSER` set in flags; default ALLOW.
- [ ] FR-3: `buildLikeC4SandboxArgv` emits `--seccomp <fd>`; the render launch
  opens the filter fd fail-closed; under `C4_BWRAP_REQUIRED=1` a real render
  completes AND `unshare -U` inside fails while `unshare -m` inside succeeds.
- [ ] FR-4: The baked `/usr/local/bin/bwrap` shim intercepts PATH-resolved
  bwrap, injects `--seccomp` with an auto-allocated filter fd, preserves only
  argv-referenced fds (+stdio+script-fd+bpf-fd), closes the rest, passes
  `--version`/`--help` through unmodified, and fails closed (`bwrap-shim:`
  stderr marker, exit 65) when the filter or real bwrap is unreadable.
- [ ] FR-5: In the deployed image, a server-held non-cloexec fd is NOT readable
  inside the SDK sandbox (the measured leak shape is closed), verified by the
  canary/deploy path, and `op=sandbox-selfprobe-fds` telemetry is retained.
- [ ] FR-6: Canary replay adds the three-probe contract (`unshare -U`
  expected-fail, `unshare -m` expected-pass, in-sandbox fd-count within the
  argv-derived bound) with the new verdict classes surfaced through
  deploy-state + Sentry via the existing emit path.
- [ ] FR-7: Boot self-check emits `feature:"agent-sandbox", op:"sandbox-hardening-selfprobe"`
  (info on pass / warn on any check failing) covering shim PATH-resolution +
  filter presence.

### Non-Functional Requirements

- [ ] No new provisioned infrastructure; the shim and filter are image-baked
  (`COPY` lines only).
- [ ] No measurable startup regression: shim is a few-ms bash prelude per
  sandboxed command; C4 prelude gains one `exec 9<`.
- [ ] Fail-closed everywhere: missing filter/shim/bwrap ⇒ refusal with a
  classifier-recognizable marker, never a silently unfiltered sandbox.
- [ ] NFR register assessment: availability (a bad filter deploy breaks every
  session — mitigated by fail-loud canary + boot check, never silent degrade);
  security (the entire change); no performance/a11y surface.

### Quality Gates

- [ ] New test suites green (`bwrap-userns-seccomp`, `bwrap-shim`) +
  updated suites green (`c4-render-sandbox`, `sandbox-canary`,
  `agent-runner-helpers` drift-guard unaffected or updated).
- [ ] ADR-050 + ADR-075 amendments committed in the same PR.
- [ ] Guard Contract mutation matrices implemented as real test rows (each RED
  row driven red at least once during development per `cq-write-failing-tests-before`).

## Test Scenarios

### Acceptance Tests (RED phase targets)

- Given the committed `.bpf`, when disassembled by the test decoder, then the
  ruleset is exactly {arch-gate, clone3→ENOSYS, clone/unshare CLONE_NEWUSER-masked→EPERM, default-ALLOW}.
- Given the generator, when run with `--check`, then the committed artifact is
  byte-identical (parity).
- Given `C4_BWRAP_REQUIRED=1` and the filter baked, when a real render runs,
  then the model returns valid AND `unshare -U` inside fails AND `unshare -m`
  inside succeeds.
- Given a leaked non-cloexec fd (fixture), when the shim spawns the stub bwrap,
  then the fd is closed inside AND `--args 5`-style referenced fds are preserved.
- Given the shim invoked as `bwrap --version`, then real bwrap answers verbatim
  (SDK availability probe unaffected).
- Given the canary replay in a container with the shim + filter, when the
  `unshare -U` probe runs, then it fails (EPERM) and `unshare -m` passes —
  else the verdict discriminates `userns_filter_bypass` vs `userns_filter_overbroad`.

### Regression Tests

- Given a posix_spawn consumer (e.g., node `spawnSync`), when run inside the
  filtered sandbox, then it succeeds — clone3's ENOSYS triggers the glibc clone
  fallback; a blanket-EPERM regression would break this row.
- Given `--json-status-fd 3` and the new filter fd, when the C4 launch runs,
  then status classification still works (fd-numbering regression).
- Given the SDK's `--args <fd>` spawn shape (verified in the shipped binary:
  `bash -c '…shift && exec "$@"' … --args <fd> …`), when the shim runs, then
  that fd survives and bwrap still parses its args file.

### Edge Cases

- Given an SDK argv passing `--args FD` / `--sync-fd N` / `--json-status-fd N`,
  when the shim runs, then those exact fds survive and every other fd >2 closes.
- Given a future SDK passing its own `--seccomp F`, when the shim runs, then fd F
  is preserved and both filters stack (seccomp filters AND-combine — additional
  filters only restrict further).
- Given the filter file absent at runtime, when either launch path runs, then
  fail-closed exit 65 with the `bwrap-shim:`/prelude marker — never an
  unfiltered spawn.
- Given container PATH reordered by a future base image (shim shadowed), when
  the container boots, then `op=sandbox-hardening-selfprobe` warns — the drift
  is visible before tenants hit it.
- Given `bwrap` absent on a dev host, when the probe script runs, then it
  prints `USNS_SECCOMP_SKIP_NO_BWRAP` (Check-10-safe) instead of failing.
- Given a future config that sets `allowUnixSockets` (engaging the SDK's
  embedded `apply-seccomp` unix-socket helper — which calls
  `unshare(CLONE_NEWUSER)` INSIDE the sandbox to drop caps), when the filter is
  active, then the helper is denied → its unix-socket blocking degrades while
  the namespace boundary holds. CONSTRAINT recorded: enabling `allowUnixSockets`
  later must either accept the degradation or carve a clone/CLONE_NEWUSER
  exception for that helper's signature — a deliberate decision, never silent.
- Given `enableWeakerNestedSandbox: true` (set in `buildAgentSandboxConfig`),
  when the filter is active, then nothing changes — the flag only drops
  `--proc /proc` from the SDK argv for container nesting; it is not a
  nested-bwrap mechanism and does not conflict.

## Success Metrics

- Deploy canary reports the new probes PASS on the next deploy after merge.
- `op=sandbox-hardening-selfprobe` info event present per container start; zero
  warn events.
- `op=sandbox-selfprobe-fds` continues to report only pre-existing counts (the
  shim neutralizes them at the boundary; the metric still counts).
- Zero `sdk-startup` events attributable to the filter (clone3/ENOSYS regression
  detector stays silent).

## Dependencies & Prerequisites

- `bubblewrap >= 0.4.0` in the runner image (`--seccomp` flag) — 0.8.0 measured.
- The `unshare` binary present in the image for the canary probes (verified:
  util-linux `unshare` in the pinned base).
- No dependency on #5862 (distinct residual) — the shim is PATH-level, not a
  vendored-builder change.

## Risk Analysis & Mitigation

- **R1 — clone3-ENOSYS breaks a runtime that genuinely requires clone3:**
  accepted residual (moby reasoning — glibc runtimes all fall back; a
  clone3-only consumer is theoretical here). Detection: `op=sdk-startup`
  classifier events + C4 boot probe. Rollback = revert PR.
- **R2 — PATH-order drift shadows the shim (base-image bump):** the boot
  self-check + canary probe catch it fail-loud, per the ADR-079 contract —
  never silent unfiltered.
- **R3 — a future SDK fd-consuming option the preserve-set doesn't know:**
  argv-shape drift is already a reviewed surface (canary `--verify` byte-diff +
  sdk-bump gate). A new `*fd*` option would close an fd the SDK expects open →
  spawn failure surfaces via sdk-startup classifier, never silently. Mitigation:
  preserve-set shares the documented vocabulary with `sandbox-canary.mjs`'s
  `BWRAP_ONE_ARG_OPAQUE` enumeration (cross-referenced in a comment).
- **R4 — shim passthrough regression (shim present, filter not injected):**
  caught by canary `unshare -U` probe + Guard 1 matrix row 2.
- **R5 — filter over-broad (blanket clone/unshare deny):** caught by the
  `unshare -m` expected-pass probe + posix_spawn regression row.
- **R6 — bwrap-version drift in a base-image bump:** image is digest-pinned;
  a bump is a reviewed Dockerfile diff; the canary probes + test suite
  re-validate `--seccomp` semantics on any base change.
- **R7 — `setns(2)` into a pre-existing userns NOT denied:** accepted residual —
  no fd to a foreign userns is reachable inside the sandbox: the replayed SDK
  argv runs the payload in a nested pidns, so no foreign-userns process (and no
  `/proc/<pid>/ns/*` handle to one) is visible, and the fd sweep guarantees no
  ns fd is passed in. Recorded in ADR-075 amendment; revisit if a leak path
  emerges.
- **R8 — `apply-seccomp`/managed-settings drift:** (a) the SDK's embedded
  unix-socket helper calls `unshare(CLONE_NEWUSER)` inside the sandbox — inert
  for our config (no `allowUnixSockets`), recorded as an Edge-Case constraint;
  (b) `bwrapPath` is a managed-settings-only knob that bypasses PATH resolution
  — if a managed settings file ever lands pointing elsewhere, the shim is
  bypassed → covered by the boot self-check + canary probes (which exercise the
  real PATH-resolved and argv-replayed paths).

## Non-Goals

- Vendored SDK bwrap-arg reorder — #5862 owns it (ADR-075 exit criterion).
- Container-level seccomp profile changes (`infra/seccomp-bwrap.json` — a
  DIFFERENT layer; it must keep allowing `CLONE_NEWUSER` or bwrap itself dies).
- Server-wide `O_CLOEXEC` retrofit (the boundary-close covers it structurally;
  the telemetry that would justify an audit stays).
- Denying `setns(2)`, the new mount API (`fsopen`/`fsmount`/…), or any flag
  beyond `CLONE_NEWUSER` — the issue's blast radius is nested userns only.
- macOS Seatbelt parity (deployment is Linux-only).
- The Vetto maintainer's comment as spec — directionally consistent (fd close,
  seccomp on unshare/clone) but its blanket `-EPERM` is wrong for clone3; the
  issue body is authoritative.

## Documentation Plan

- ADR-075 amendment + ADR-050 amendment extension (Phase 5).
- Inline doc comments: `agent-runner-sandbox-config.ts` module header gains one
  line noting the shared filter layer (the file that documents the sandbox
  contract); `c4-render.ts` header comment on the filter fd plumbing.
- `apps/web-platform/scripts/bwrap-userns-seccomp-probe.sh` self-documents the
  discoverability check.

## Sharp Edges

- A plan whose `## User-Brand Impact` section omits the threshold fails
  deepen-plan Phase 4.6 — filled above.
- `--seccomp` reads an fd, not a path — every insertion point must open the
  filter itself; forgetting the fd (or closing it in the prelude's own loop) is
  the easiest silent break. The C4 prelude opens AFTER the close loop by
  construction; the shim auto-allocates.
- The shim runs per sandboxed Bash call — it MUST stay dependency-free bash
  (no node, no jq) and preserve its own script fd or it truncates itself
  mid-parse.
- `bwrap --version` is the SDK's availability probe — the shim's pass-through
  is load-bearing or `failIfUnavailable: true` bricks every session.
- `stderr` markers are the classifier's only handle — keep the literal
  `bwrap-shim:` + `seccomp` tokens in failure messages or the startup mirror
  goes blind.
- The canary replay fixture is UNCHANGED — only derived probes are added; do
  not touch `sandbox-canary-argv.json` (byte-diff gate treats fixture edits as
  a trust-boundary surface).
- Expected-EPERM inversion: a PASSING `unshare -U` inside the sandbox is the
  failure — the probe asserts the deny. Inverted expectations are the easiest
  way to write a vacuous green.
- `requires_cpo_signoff: true` is set — the work phase must surface CPO sign-off
  before implementation (headless: the pipeline records this in the PR body via
  decision-channels, not an interactive gate).

## References & Research

### Internal References

- `apps/web-platform/server/c4-render.ts` — `CLOSE_FDS_SCRIPT`,
  `buildLikeC4SandboxArgv`, `sandboxLaunch`, `verifyC4RenderSandboxOnce`,
  `reportInheritableFds`
- `apps/web-platform/server/agent-runner-sandbox-config.ts` —
  `buildAgentSandboxConfig`, module-header SDK-argv-order notes
- `apps/web-platform/server/agent-env.ts` — `AGENT_ENV_ALLOWLIST` (PATH passthrough)
- `apps/web-platform/scripts/sandbox-canary.mjs` — `SHIM_SOURCE`,
  `buildBwrapInvocation`, `BWRAP_ONE_ARG_OPAQUE`, `classifyReplayVerdict`
- `apps/web-platform/scripts/plugin-root-sandbox-propagation-probe.mjs` — second
  PATH-shim precedent
- ADR-050 (2026-09-24 amendment), ADR-075, ADR-079, ADR-122, ADR-080
- `knowledge-base/project/learnings/2026-09-24-sandboxing-a-render-child-with-bwrap-no-writable-host-bind.md`
- `knowledge-base/project/learnings/security-issues/bwrap-sandbox-three-layer-docker-fix-20260405.md`
- `knowledge-base/project/learnings/security-issues/docker-seccomp-blocks-bwrap-sandbox-20260405.md`

### External References

- [moby/moby#42680 — seccomp EPERM on clone3 breaks glibc fallback](https://github.com/moby/moby/issues/42680)
- [moby/moby commit 9f6b562 — clone3 → ENOSYS in default policy](https://github.com/moby/moby/commit/9f6b562dd12ef7b1f9e2f8e6f2ab6477790a6594)
- bubblewrap `--seccomp FD`/`--add-seccomp-fd FD` (raw sock_filter[] from fd; since ≤0.3.3/0.6.x)

### Related Work

- Issue: #8752 (this), #5862 (sibling vendored-reorder, NOT folded), #5941
  (prod-canary nested-unshare probe — partially overlapped, acknowledged),
  #5873/#5849 (the seccomp/userns outage lineage), #5733 (blind-surface lineage),
  #8623/#8696/#8732 (the C4 bwrap work that filed this deferral)
- Brainstorm context: `knowledge-base/project/brainstorms/2026-09-26-c4-hardening-residuals-brainstorm.md`
  (C4-hardening family; threshold precedent `single-user incident`)
