# Drift-guard assertion false-passes when its grep target appears in comment prose

## Problem

`deploy-script-tests` ran RED on `main` (#4864): `journald-config.test.sh`
asserted the SSH `connection` block in `server.tf` uses literal `agent = true`,
but PR #4845 had converted every hardening connection block to a **dual-context**
form — `agent = var.ci_ssh_private_key == null` (operator ssh-agent locally;
explicit Doppler key in CI, where there is no ssh-agent). The literal-`true`
assertion went stale and failed honestly.

The non-obvious half: a **sibling** test (`infra-config-handler-bootstrap.test.sh`)
carried the byte-identical assertion (`grep -qE 'agent[[:space:]]*=[[:space:]]*true'`)
yet **PASSED — by accident**. Its awk-extracted `BLOCK` uniquely includes the
`#4829` dual-context explanatory COMMENT, whose prose reads
"… so `agent = true` uses the operator's ssh-agent …" (`server.tf:381`). The
grep matched that **comment text**, not real config. After #4845 changed the
real config line, the assertion was asserting nothing — green-blind.

## Solution

Narrow the assertion to anchor on a token that exists ONLY on the real config
line and never in surrounding prose: `agent[[:space:]]*=[[:space:]]*var\.ci_ssh_private_key[[:space:]]*==[[:space:]]*null`.
That regex matches the real `agent = var…` line in both blocks and cannot match
the `agent = true` / `agent = false` comment prose. Both drift guards then pass
for the *right* reason. `server.tf` was correct and left untouched (the fix is
test-only).

Proof of non-vacuity: run the test's own awk extraction, apply OLD vs NEW regex.
OLD matched only the comment in the bootstrap block (the false-pass) and nothing
in the journald block (the honest fail); NEW matches exactly the one real config
line in each.

## Key Insight

This is the **comment-prose sibling** of the bare-path drift-guard trap in
[[2026-06-02-drift-guard-bare-path-grep-vacuous-and-terraform-cwd]] (#4811, where
a bare path also recurred in `chown`/`chmod` lifecycle lines). Same root class:
**a grep-based drift guard whose target string also appears in NON-CONFIG text
inside the awk-extracted block (a comment, a lifecycle command, an example) can
false-pass even after the construct it claims to assert is deleted or changed.**

Generalizable rules:
1. Anchor the assertion regex on a token that can only appear on the real config
   line (a variable reference, an HCL operator like `== null`) — never on a bare
   literal/path/boolean that could legitimately appear in prose.
2. When fixing one named drift-guard test, run a **sibling-query audit** across
   `apps/web-platform/infra/*.test.sh` for the same assertion class
   (`grep -rln "<stale phrase>" …`) — the false-passing siblings are invisible
   until you grep for them, and they regress silently when their comment is later
   edited.
3. Prove non-vacuity: mutate out the asserted construct and watch the guard go
   red, or apply OLD-vs-NEW regex to the extracted block.

## Tags
category: best-practices
module: apps/web-platform/infra
issue: 4864
related: 4811, 4845, 4829
