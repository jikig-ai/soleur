# Session State

## Plan Phase

- Plan file: /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-8752-bwrap-seccomp-fd-hygiene/knowledge-base/project/plans/2026-10-06-sec-bwrap-userns-seccomp-fd-hygiene-plan.md
- Status: complete

## Work Phase

- Status: complete (2026-10-06)
- Phases 1-4 landed; ADR-050/ADR-075 amendments + module-header doc comments landed.
- Suite state: 171/171 green across the six touched vitest suites under `C4_BWRAP_REQUIRED=1 LIKEC4_REQUIRED=1`; sandbox-canary-regression.test.sh 16/16; dockerignore parity guard green; tsc clean; lint-orphan-test-suites clean; markdownlint clean.

### Errors

- Harness limitation: no Task/subagent tool in the spawned planning subagent — every prescribed agent fan-out executed inline; disclosed as `Reviewed-Coverage: sequential-fallback` (no independent review claimed).
- Transient `edit`-tool "file not found" failures on two batched edits — retried individually, applied.
- One verification grep ran in wrong CWD — re-ran with explicit workdir, clean.
- Pre-existing uncommitted `.mcp.json` modification on branch — not created by this work, left untouched.
- Generator initially emitted a `sock_fprog` header — `bwrap --seccomp` expects the raw `sock_filter[]` array only (len%8 check in bubblewrap source); fixed, real-bwrap row then proved the filter installs.
- The first real-bwrap `unshare -U` row passed vacuously on the EINVAL setup failure — tightened to require the payload's own EPERM signature, never a `bwrap:` setup error.

### Decisions

- One shared `bwrap --seccomp` BPF (generator + committed `.bpf` + byte-parity and disassembly tests): clone/unshare with CLONE_NEWUSER → EPERM; clone3 → blanket ENOSYS (moby/moby#42680 precedent).
- Two insertion points: `--seccomp 9` on `buildLikeC4SandboxArgv` (fd opened post-close in CLOSE_FDS_SCRIPT, fail-closed); baked `/usr/local/bin/bwrap` PATH shim intercepting the SDK spawn, closing inherited fds except argv-referenced ones.
- Observability/canary: FOUR derived canary probes (nested-userns deny, fork survival, fd census carrying a deliberate unreferenced fd, `--args <fd>` transport) + boot self-check `op=sandbox-hardening-selfprobe`; existing `op=sandbox-selfprobe-fds` retained. `bwrap-shim:` stderr classifies `sandbox_broken`/`bwrap_shim_refused`.
- Deferral criteria re-checked: pinned node:22-slim still ships bubblewrap 0.8.0-2+deb12u1 (measured); SDK binary's embedded apply-seccomp facility is the wrong layer, inert; threshold single-user incident → requires_cpo_signoff: true; ADR-050 + ADR-075 amendments planned; setns(2) recorded as residual.

### Deviations from plan (measured, documented in ADR-050 addendum)

- `unshare -m` "must-pass" control replaced by a forked-child control: the payload runs capability-free (bwrap zeroes the capset before exec), so nested `CLONE_NEWNS` needs a `CAP_SYS_ADMIN` it never holds — EPERM on every kernel, so the control could never discriminate (measured kernel 7.2.5 / bwrap 0.12: all nested non-userns unshares fail inside a bwrap sandbox, `-U` alone passes).
- Shim injects via `--add-seccomp-fd`, not `--seccomp`: repeatable + stacks with a future SDK filter; a hypothetical SDK `--seccomp` conflicts loudly at parse instead of last-wins silently overriding ours. `--add-seccomp-fd` exists since bwrap 0.6.x — prod's 0.8.0 has it.
- bwrap single-fd consumption quirk recorded: `--seccomp <fd>` reads to EOF — each spawn needs a fresh open (the C4 prelude's `exec 9<` per launch and the shim's `exec {fd}<` per invocation both satisfy this).

### Components Invoked

- skills/plan/SKILL.md (run to completion; commits ee9fc9c683)
- skills/deepen-plan/SKILL.md (run to completion; commit 83c5c33e62)
- Inline research: gh issue view ×12, docker run on pinned base digest, shipped-binary strings analysis, web research (moby#42680, runc)
- scripts/lint-guard-contract.py, npx markdownlint-cli2

## Review Phase (12 seats, sequential-fallback panel)

No P1 in the committed state; the panel caught and the fix commits `b91b180beb`/`cdf018520e` resolved:
- shim preserve-scan rewritten arity-aware (`--` boundary, value-position desync closed, all 16 bwrap fd options)
- canary: `bwrap-shim:` → `sandbox_broken`/`bwrap_shim_refused`; fd census fail-loud (`ls|wc -l`, n<3) + deliberate leaked-fd discriminator; 4th `args_fd_transport` probe with the child-fd-index fix (host fd ≠ stdio index — would have paged every deploy); fork/args-fd classifiers discriminate infra vs broken; 15s timeouts
- `SOLEUR_BWRAP_SECCOMP_BPF` forwarded through `AGENT_ENV_ALLOWLIST` (incident-override parity)
- Guard-1 census mechanized (server/ bwrap-spawn enumeration + ≥2-sites anti-vacuity floor); §D4 byte-identity between shim and canary fd vocabularies
- unfiltered positive controls on both deny rows; emit-fork coverage for verifyAgentSandboxHardening; shim fails closed when `/proc/self/fd` is unenumerable
- docs: ADR-050/075 name all four probes; plan/tasks corrected (moby attribution, `--add-seccomp-fd`, raw sock_filter[], setns-pidns rationale); canary-probe-set.md decodes the five verdict reasons; apply-deploy-pipeline-fix prints reason+probe
- Verified live: probes pass through shim+real bwrap; mutant shim without the sweep trips `fd_hygiene_bypass`; no-shim trips `userns_filter_bypass`; unfiltered control permits nested userns
