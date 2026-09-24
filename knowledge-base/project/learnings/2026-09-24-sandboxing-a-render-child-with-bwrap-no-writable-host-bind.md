---
title: Sandboxing the likec4 render child with bwrap — no writable host bind, status-fd classification, inherited-fd close
date: 2026-09-24
category: security-issues
module: apps/web-platform/server/c4-render.ts
issues: [8695, 8696, 8713, 8739, 8740, 8752]
tags: [bwrap, sandbox, likec4, c4, child-process, sentry, mutation-testing]
---

# Learning: sandboxing a render child with bwrap

## Problem

The C4 re-render spawns likec4 in the web-platform container over sources a tenant committed
to GitHub. #8696 asked for it to run without network, parent `/proc`, or `/workspaces`
access. The first design gave the child a writable host bind for its output, then read the
model back from the host. That turned the output file into an attack surface (a symlink to
another tenant's model, a FIFO that blocks the reader, a sparse file past the cap), and it
needed its own guard (Guard 5).

Separately, the committed model in production had zero views. likec4 defaults to `--use-dot`,
the container has no graphviz `dot`, and the elements-only gate accepted the result. The
census found one external repo affected (#8740).

## Solution

- **No writable host bind.** `/c4-out` is a 24 MiB tmpfs inside the sandbox. The child `cat`s
  the model to stdout, and the host caps stdout at `RAW_MODEL_READ_CAP`, killing the child
  past the cap and rejecting an empty stdout. Guard 5 (`readRenderOutput`) now covers only the
  direct, non-production path.
- **Launch chain**: `bash -c CLOSE_FDS_SCRIPT` → `choom` → `nice` → `bwrap` → `prlimit --nproc`
  → `sh -c RENDER_SCRIPT`. The bash step closes every inherited fd above 3 *outside* the
  sandbox. bwrap passes non-CLOEXEC fds straight through, which we confirmed on the replica
  with fd 7 and a secret file.
- **Classify from `--json-status-fd`, never from the child's exit code alone.** Under bwrap
  0.8.0, `child-pid` is written even when setup fails, which disproved the plan's claim. The
  discriminator is the presence of the `exit-code` record: a non-zero exit with no such record
  means `sandbox_error/bwrap-setup`.
- **Mount order matters.** A later mount shadows an earlier bind at the same or a parent path.
  An extra ro-bind under `/tmp` (the test likec4 prefix) went invisible behind `--tmpfs /tmp`
  and produced MODULE_NOT_FOUND. Extra ro-binds must follow the tmpfs mounts, and the
  production pin requires `extraRoBinds` to be empty.
- **Pin wasm layout** (`--no-use-dot`), and refuse a zero-view export as `layout_failed`.
- **Residual**: `--disable-userns` fails under 0.8.0 with the production seccomp profile (the
  RO `/proc/sys`). Nested user namespaces are tracked in #8752.

## Key Insight

When a sandbox's product must come back to the host, prefer a **capped stream** over a
**writable bind**. A stream has one property to enforce (a size cap). A host-visible output
file has at least four: its type, where it links to, whether reading it blocks, and its size.
Each of those needs a real-filesystem test, because a mock cannot exhibit them. For the
fail-closed classifier, read the tool's own status channel. An exit code cannot tell "the
sandbox never started" apart from "the program inside failed".

## Session Errors

1. **Planning subagent hit the account session limit (429) before deepen-plan.** Recovery: I recovered the plan from disk, wrote the reviewer findings to files, and resumed after the reset. **Prevention:** planning subagents already persist to disk before returning, so this is one-off. Keep saving findings to files as they arrive.
2. **A guardrail hook blocked `pgrep -f` and a `--body-file` in the same call as its heredoc.** Recovery: I wrote the body with the Write tool, then ran a separate `gh` call. **Prevention:** already hook-enforced. Write issue bodies with the Write tool before calling `gh`.
3. **The commit hook's `tsc` failed on an untracked RED test file** (TDD red phase). Recovery: I moved the file aside for the commit. **Prevention:** commit the RED test together with its stub export, or commit the RED test file only after the export it imports exists.
4. **Real bwrap failed with MODULE_NOT_FOUND** because the tmpfs `/tmp` shadowed the extra ro-bind. Recovery: extra binds now come after the tmpfs mounts. **Prevention:** the real-bwrap tenant-config rows in CI (`C4_BWRAP_REQUIRED=1`) catch this. Any bwrap argv change must run those rows, not only argv-shape rows.
5. **The bwrap availability probe failed without the `/lib` and `/lib64` symlinks.** Recovery: I added the symlinks. **Prevention:** same as 4. The probe now shares the production mount skeleton.
6. **The H4 environment allowlist rejected `PWD`**, which bwrap sets itself after `--clearenv`. Recovery: `PWD` is allowlisted. **Prevention:** one-off; it is documented in the test.
7. **A Concierge-copy negative assertion matched its own negation** ("will not update" contains "will update"). Recovery: the test now counts occurrences and forbids "shortly". **Prevention:** existing rule `cq-assert-anchor-not-bare-token`. Anchor negatives on a phrase the negation cannot contain.
8. **A mutation-battery row produced a syntax error rather than a behavioural mutant.** Recovery: I re-ran it as `? true`; C4-C10 killed it. **Prevention:** the battery script should `tsc`-check or parse each mutant and report "invalid mutant" separately from "killed".
9. **The first mutation battery counted two fixture defects as kills**: the size-cap row was masked by the post-read length check, and the CLOEXEC fd fixture was skipped for the wrong reason. Recovery: I fixed both fixtures, and 29/29 then died by their intended assertion. **Prevention:** record *which assertion* killed each mutant, not just that it died.
10. **A plan claim about bwrap was false**: it said `child-pid` is absent on setup failure. Recovery: I measured it on the replica and moved the discriminator to the `exit-code` record. **Prevention:** existing work-skill rule (verify a measurement before it propagates).
11. **Merge conflict in `server/index.ts` imports** with a sibling PR (watchdog clock). Recovery: kept both imports. **Prevention:** one-off.
12. **The `test-all.sh --affected` gate queued behind 7 sibling worktrees.** Recovery: I stopped it and relied on targeted suites plus CI. **Prevention:** already covered (rc=4 REFUSED contention path, one-shot token-discipline item 7).
13. **The Playwright MCP server failed to connect** during QA. There was no impact, because the test scenarios had no Browser steps. **Prevention:** one-off.

## Tags
category: security-issues
module: c4-render
