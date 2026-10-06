# Tasks — security: shared bwrap seccomp filter denying nested user namespaces + close inherited fds in the agent sandbox

Plan: `knowledge-base/project/plans/2026-10-06-sec-bwrap-userns-seccomp-fd-hygiene-plan.md`
Issue: #8752 | PR: #9595 (draft) | Branch: `feat-one-shot-8752-bwrap-seccomp-fd-hygiene`

Note: `brand_survival_threshold: single-user incident` and
`requires_cpo_signoff: true` — CPO sign-off required before work begins
(pipeline records it; `soleur:engineering:review:user-impact-reviewer` runs at
review time).

## Phase 1 — Shared filter artifact (RED first per `cq-write-failing-tests-before`)

- [x] 1.1 Write `apps/web-platform/test/bwrap-userns-seccomp.test.ts` RED:
  disassembly decoder + ruleset assertions (arch gate; clone3→ENOSYS;
  clone/unshare `CLONE_NEWUSER`-masked→EPERM; default ALLOW) + generator
  byte-parity `--check`.
- [x] 1.2 Write `apps/web-platform/scripts/gen-bwrap-userns-seccomp.mjs`:
  emit a raw serialized `struct sock_filter[]` array (NO sock_fprog header — bwrap derives the count from the fd length) (x86_64 nrs: clone 56, unshare 272, clone3 435;
  `CLONE_NEWUSER=0x10000000`; `__X32_SYSCALL_BIT` variants) + `--check` mode.
- [x] 1.3 Generate `apps/web-platform/infra/bwrap-userns-clone3-deny.bpf`; suite
  GREEN (parity + semantics independent of bwrap availability).

## Phase 2 — C4 render argv integration

- [x] 2.1 Extend `CLOSE_FDS_SCRIPT` in `apps/web-platform/server/c4-render.ts`:
  after closing fds >3, `exec 9<"$SOLEUR_BWRAP_SECCOMP_BPF"` fail-closed
  (`|| exit 65`); env default `/app/infra/bwrap-userns-clone3-deny.bpf`.
- [x] 2.2 Add `"--seccomp", "9"` to `buildLikeC4SandboxArgv` setup args.
- [x] 2.3 Update `test/c4-render-sandbox.test.ts` (+ `-tenant-config` as needed):
  argv-shape assertion; real-bwrap row (`C4_BWRAP_REQUIRED=1`): render completes,
  `unshare -U` inside fails, a forked child inside succeeds (deviation: `unshare -m` is capability-impossible inside a capless payload — see session-state) — with a ran-presence
  assertion (no silent skip-green).

## Phase 3 — Agent SDK shim (fd hygiene + filter injection)

- [x] 3.1 Write `test/bwrap-shim.test.ts` RED against `infra/bwrap-shim/bwrap`
  using a stub real-bwrap replaying the real contract (argv record, fd
  readability, exit codes).
- [x] 3.2 Write `infra/bwrap-shim/bwrap` (bash): `--version`/`--help`
  pass-through; parse fd-consuming options (`--args`, `--seccomp`,
  `--add-seccomp-fd`, `--sync-fd`, `--info-fd`, `--json-status-fd`,
  `--block-fd`, `--userns-block-fd`) into a preserve-set — `--args <fd>` IS in
  the real SDK argv (verified against the shipped binary strings: `bash -c
  '…shift && exec "$@"' … --args <fd> …`), so the preserve-set is load-bearing;
  `exec {fd}<` the filter; close all other fds >2 except
  preserve-set/script-fd/bpf-fd; `exec /usr/bin/bwrap --add-seccomp-fd "$fd" "$@"` (deviation: repeatable/stacking, see session-state);
  fail-closed `bwrap-shim:` marker.
- [x] 3.3 `apps/web-platform/Dockerfile`: `COPY` shim → `/usr/local/bin/bwrap`
  (root-owned 0755), `.bpf` → `/app/infra/` (with the other `infra/` COPY block).
- [x] 3.4 Comment cross-reference: preserve-set ↔ `sandbox-canary.mjs`
  `BWRAP_ONE_ARG_OPAQUE` fd-option vocabulary.

## Phase 4 — Deploy canary + boot self-check

- [x] 4.1 `apps/web-platform/scripts/sandbox-canary.mjs`: replay gains three
  derived probes — `bwrap <argv> -- unshare -U true` MUST fail (else verdict
  `userns_filter_bypass`), a forked-child spawn inside MUST pass (else
  `userns_filter_overbroad`), and an in-sandbox fd census (`ls /proc/self/fd`
  count within `3 + #(fd-consuming argv args) + 1`, else `fd_hygiene_bypass`);
  fixture `sandbox-canary-argv.json` UNCHANGED.
- [x] 4.2 Update `test/sandbox-canary.test.ts` +
  `scripts/sandbox-canary-regression.test.sh` for the verdict contract +
  probe-presence assertions.
- [x] 4.3 Boot self-check at the `verifyC4RenderSandboxOnce` call site
  (`server/index.ts`): assert `command -v bwrap` resolves to the shim + filter
  present non-empty → `feature:"agent-sandbox", op:"sandbox-hardening-selfprobe"`
  info/warn. Keep `reportInheritableFds` unchanged.
- [x] 4.4 Write `apps/web-platform/scripts/bwrap-userns-seccomp-probe.sh`
  (discoverability command): artifact non-empty + `--check` parity + shim
  presence + real-bwrap probes when available; prints `USNS_SECCOMP_OK` /
  `USNS_SECCOMP_SKIP_NO_BWRAP`; <15 s, no pipes/metachars needed at call site.

## Phase 5 — ADR amendments + docs

- [x] 5.1 ADR-075 amendment (merge-date, #8752): shared filter + fd hygiene;
  denyRead residual + #5862 exit criterion unchanged.
- [x] 5.2 ADR-050 amendment extension: close the "nested user namespaces" and
  "inherited fds in other spawners" residual rows.
- [x] 5.3 Doc comments: `agent-runner-sandbox-config.ts` module header +
  `c4-render.ts` filter-fd plumbing note.

## Phase 6 — Verification

- [x] 6.1 New + updated suites green under the repo runner (vitest for
  `test/**/*.test.ts`; `.test.sh` per existing convention).
- [x] 6.2 Guard Contract mutation rows exercised RED at least once each.
- [x] 6.3 `npx markdownlint-cli2` clean on plan/tasks/ADR edits.
- [x] 6.4 Confirm `lint-orphan-test-suites.sh` registers the new suites.
