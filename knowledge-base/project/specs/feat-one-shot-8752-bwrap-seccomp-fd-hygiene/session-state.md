# Session State

## Plan Phase
- Plan file: /data/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-8752-bwrap-seccomp-fd-hygiene/knowledge-base/project/plans/2026-10-06-sec-bwrap-userns-seccomp-fd-hygiene-plan.md
- Status: complete

### Errors
- Harness limitation: no Task/subagent tool in the spawned planning subagent — every prescribed agent fan-out executed inline; disclosed as `Reviewed-Coverage: sequential-fallback` (no independent review claimed).
- Transient `edit`-tool "file not found" failures on two batched edits — retried individually, applied.
- One verification grep ran in wrong CWD — re-ran with explicit workdir, clean.
- Pre-existing uncommitted `.mcp.json` modification on branch — not created by this work, left untouched.

### Decisions
- One shared `bwrap --seccomp` BPF (generator + committed `.bpf` + byte-parity and disassembly tests): clone/unshare with CLONE_NEWUSER → EPERM; clone3 → blanket ENOSYS (moby/moby#42680 precedent).
- Two insertion points: `--seccomp 9` on `buildLikeC4SandboxArgv` (fd opened post-close in CLOSE_FDS_SCRIPT, fail-closed); baked `/usr/local/bin/bwrap` PATH shim intercepting the SDK spawn, closing inherited fds except argv-referenced ones.
- Observability/canary: three derived canary probes (unshare -U expect-EPERM, unshare -m expect-pass, in-sandbox fd census) + boot self-check `op=sandbox-hardening-selfprobe`; existing `op=sandbox-selfprobe-fds` retained.
- Deferral criteria re-checked: pinned node:22-slim still ships bubblewrap 0.8.0-2+deb12u1 (measured); SDK binary's embedded apply-seccomp facility is the wrong layer, inert; threshold single-user incident → requires_cpo_signoff: true; ADR-050 + ADR-075 amendments planned; setns(2) recorded as residual.

### Components Invoked
- skills/plan/SKILL.md (run to completion; commits ee9fc9c683)
- skills/deepen-plan/SKILL.md (run to completion; commit 83c5c33e62)
- Inline research: gh issue view ×12, docker run on pinned base digest, shipped-binary strings analysis, web research (moby#42680, runc)
- scripts/lint-guard-contract.py, npx markdownlint-cli2
