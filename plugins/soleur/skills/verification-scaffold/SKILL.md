---
name: verification-scaffold
description: "This skill should be used when installing the generic guardrail set (secret-scan, commit-on-main, block-stash, orphan-test) into a repo's hooks and CI."
---

<!-- grok-harness-invoke:start -->
**Grok Build (`plugins/soleur/lib/harness.ts` `invokeSkill()`):** Read this SKILL.md in this process and run it to completion. A one-segment `soleur:<name>` in this document names a SKILL — on Grok Build, Read `plugins/soleur/skills/<name>/SKILL.md` in this process; it is not a nested tool_use. A multi-segment id such as `soleur:<domain>:<name>` names an AGENT: spawn it, never Read it. **Claude Code:** Skill tool for a skill (`soleur:<name>`), Task tool with `subagent_type` for an agent. Forbidden is executing a subset, not the Read.
<!-- grok-harness-invoke:end -->

# verification-scaffold

Installs a curated set of **repo-generic guardrails** — audited in
`references/guardrail-audit.md` and manifested in `references/guards.tsv` —
into a user repository's `.claude/hooks/` + `.claude/settings.json` (agent
surface) and `.github/workflows/verification-gates.yml` (CI floor).
`constraint-scaffold` sibling (ADR-295): same emit-prove-document pattern, but
a multi-guard corpus with per-guard modes instead of one gate.

**v1 guards:** `secret-scan` (gitleaks staged scan, hook + CI),
`commit-on-main` (near-verbatim `precommit-guard.sh` emit, hook),
`block-stash` (chain-boundary `git stash` deny, hook), `orphan-test`
(every `*.test.sh` registered or reason-excluded, CI + runner script).

## Agent-owns-gates

The target user cannot hand-edit a gate. The agent authors, installs, and
uninstalls: emitted files carry "do not hand-edit" markers; mode promotion is
a one-line flip (`MODE=` in each hook, dropping `continue-on-error` in the
workflow) performed only after at least one observed clean run.

## Usage

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/verification-scaffold/scripts/verification-scaffold.sh" \
  --target /path/to/repo --headless
```

| Flag | Effect |
|---|---|
| `--target PATH` | repo to install into (default cwd; must be a git work tree) |
| `--guards a,b` | subset of the manifest (default: the v1 set) |
| `--all` | every guard with a template |
| `--mode advisory\|enforce` | decision verb only — identical predicates (default advisory) |
| `--dry-run` | print the emit plan; write nothing |
| `--list` | print the manifest and exit |
| `--uninstall GUARD` | remove one guard's artifacts + its settings entry (idempotent) |
| `--headless` | accept defaults; never prompts (it never does) |

## Emitted artifacts (per guard)

| Guard | `.claude/hooks/` | `scripts/verification/` | `.github/` + root |
|---|---|---|---|
| secret-scan | `secret-scan.sh` (ask/deny on findings) | — | `.gitleaks.toml` (only if absent), `verification-gates.yml` job (gitleaks-action, SHA-pinned) |
| commit-on-main | `commit-on-main.sh` | `precommit-guard.sh`, `lib/wrapper-boundary.sh` (stamped `@DEFAULT_BRANCHES@`) | — |
| block-stash | `block-stash.sh` | — | — |
| orphan-test | — | `orphan-test-check.sh` | `verification-gates.yml` job, `verification-known-orphans.txt` seed |

Non-destructive: refuses to overwrite any existing artifact (no `--force`);
`.gitleaks.toml` and `verification-known-orphans.txt` are emitted only when
absent; settings.json merges dedupe on the hook `command` string; a
`TMPDIR`-detached-worktree **bite-proof** proves every installed guard
pass → fail → pass before the doc block writes; the trap restores the tree on
any failure after the first write.

## Advisory-first contract

Advisory is a *decision-verb* difference, never a detection difference —
identical predicates in both modes. Promotion: flip `MODE=` in the hook or
drop `continue-on-error` in the workflow, after ≥1 clean run
(`wg-dark-launch-deploy-gates`). Tool problems (missing gitleaks, missing
detector) warn-and-allow in advisory, deny-with-remediation in enforce —
never a silent pass and never an `ask` on tool-error. Emitted guards are
local-only: zero network egress, findings redacted.

## Portability

Emitted scripts need bash + POSIX tools, `git`, and `node` **or** `jq`
(stdin/envelope JSON + settings merge — the generator refuses hook guards
when neither resolves, exit 68). `secret-scan`'s local scan needs `gitleaks`
on PATH; the CI job pins `gitleaks/gitleaks-action` by commit SHA (v3.0.0)
and needs `GITLEAKS_LICENSE` on org-owned repos. POSIX/Linux/macOS only.

## Self-tests

`test/generator.test.sh` (flags, refusals, settings merge, modes, uninstall),
`test/bite-proof.test.sh` (per-guard pass→fail→pass on emitted artifacts),
`test/manifest.test.sh` (guards.tsv↔templates↔audit census, template↔source
parity, emitted-content hygiene, actionlint).
