# Learning: an ADR-093 `${CLAUDE_PLUGIN_ROOT}` migration that anchors a script resolved from ≥2 sibling SKILL.md files must ship a byte-identity parity test — and acceptance greps over the anchored literal must use `grep -F`

## Problem

Pulling forward the security-critical residual of the ADR-093 deployment-anchoring migration (#6156, subset of #6154) rewrote three agent-run script invocations to `${CLAUDE_PLUGIN_ROOT:-<preserved-anchor>}/...`. Two of the three sites — `legal-generate/SKILL.md` and `incident/SKILL.md` — resolve the **identical** `redact-sentinel.sh` (the fail-closed secret-redaction gate), so the migration duplicated the full anchored literal verbatim across both files. Two independent gaps surfaced:

1. **Duplicated security-critical literal, no coupling test (review P2).** The only test touching the sites was a loose `assert_grep 'redact-sentinel\.sh'` substring — it stays GREEN even if a future edit drops the git-root fallback from one site, switches one to a bare/`./plugins/soleur` anchor, or drops the `:-`. Exactly the silent-drift class the Slice C `plugin-root-list-carveout-coupling.test.ts` guard exists to prevent, but that guard is scoped to `worktree-manager.sh list|ls` only and does not cover the redaction gate.
2. **`grep -c` false-negative on the `${...}` literal (work-time friction + review P2).** The acceptance-criteria quick-ref used `grep -c '${CLAUDE_PLUGIN_ROOT:-plugins/soleur}/…' file` → returned `0`, not the expected `3`. `$`/`{`/`}` in an unescaped BRE pattern do not match literally, so anyone running the documented check verbatim gets a false "migration failed."

## Solution

1. **Add a byte-identity parity test in the SAME PR** for any literal the migration duplicates across sibling files. Added `redact-sentinel.test.sh` Test 18: `grep -Fc "<full anchored literal>"` must return exactly `1` in BOTH `legal-generate/SKILL.md` and `incident/SKILL.md`. Because both grep the same literal string, `1` in each proves byte-identity to the literal (hence to each other). Verified non-vacuous: a drifted `./plugins/soleur` anchor yields `0` → FAIL. Mirrors the `trigger-cron-allowlist-parity.test.ts` coupling pattern.
2. **Acceptance greps over a `${...}` literal must use `grep -F`** (fixed-string), never `grep -c`/`-E`. Fixed the plan + tasks quick-ref.

## Key Insight

- **Deployment-anchoring migrations create duplicated literals.** When ADR-093's `${CLAUDE_PLUGIN_ROOT:-anchor}/skills/<X>/scripts/<script>.sh` form is applied to a script resolved from ≥2 sibling SKILL.md files, the anchored literal is copy-identical across those files with no compiler and no existing guard pinning them. The default disposition is **fix-inline**: a byte-identity `grep -Fc … == 1`-in-each parity test, in the same PR, on a fail-closed gate. This is the concrete instance of the review defect-class "Replicated literals across ≥2 source files without parity test."
- **`${...}` in a grep pattern needs `-F`.** A `$` mid-pattern, `{`, `}` are not literal in BRE — a `grep -c '${VAR:-x}/…'` silently returns 0. Any acceptance-criteria or drift-guard grep whose needle contains a shell-expansion literal must be `grep -F`.

## Process notes

- The review→adjudication loop worked as designed: `user-impact-reviewer` rated a residual (server-var-unset → untrusted fallback) P1; `security-sentinel` rated the same scenario P3 (governed by the ADR-093 SDK-export invariant). Per the single-agent-HIGH-vs-contradicting cross-reconcile rule, the disagreement routed to the `cto` agent, which ruled **defer** (the residual is ADR-093-wide, not pr-introduced, and unfixable at the shell layer because the fallback is the legitimate CLI/worktree path). Captured as an ADR-093 §Amendments entry + tracking issue #6223 rather than blocking a PR that faithfully applies an Accepted ADR.

## Session Errors

1. **`grep -c` returned 0 for a `${...}` literal during Phase 2 verification.** Recovery: re-ran with `grep -Fc` (got 3). Prevention: acceptance/drift greps whose needle contains `${…}`/`{…}` must use `grep -F`; documented in the plan+tasks quick-ref fix and this learning.
2. **A plan Non-Goals `Edit` failed with "string not found" on the first attempt** (whitespace/wrap mismatch against the copied old_string). Recovery: re-read the exact line via `grep -n` + `Read`, then re-applied. One-off; standard `hr-always-read-a-file-before-editing-it` discipline.

## Tags
category: best-practices
module: plugins/soleur/skills (incident, legal-generate, trigger-cron); ADR-093
