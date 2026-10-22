---
name: verification-scaffold
description: "This skill should be used when installing the generic guardrail set (secret-scan, commit-on-main, block-stash, orphan-test) into a user repository's hooks and CI, advisory-first."
---

<!-- grok-harness-invoke:start -->
**Grok Build (`plugins/soleur/lib/harness.ts` `invokeSkill()`):** Read this SKILL.md in this process and run it to completion. A one-segment `soleur:<name>` in this document names a SKILL — on Grok Build, Read `plugins/soleur/skills/<name>/SKILL.md` in this process; it is not a nested tool_use. A multi-segment id such as `soleur:<domain>:<name>` names an AGENT: spawn it, never Read it, and on Grok Build spawn_subagent takes the id with its colons replaced by hyphens (`agentIdToGrokSubagentType`). **Claude Code:** Skill tool for a skill (`soleur:<name>`), Task tool with `subagent_type` for an agent. Forbidden is executing a subset, not the Read.
<!-- grok-harness-invoke:end -->

# verification-scaffold

Installs a fixed, tested set of **generic** repo guardrails into a user repository —
the repo-generic fraction of Soleur's own hook/lint corpus, classified in
[guardrail-audit.md](references/guardrail-audit.md) (which corpus member is `generic`,
`generic-after-extraction`, or `soleur-coupled`, and why). This is the
`constraint-scaffold` sibling for the guardrail *corpus* rather than a single gate
(#10404, epic #10397).

## Usage

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/verification-scaffold/scripts/verification-scaffold.sh" --headless
```

Installs the v1 set into the current repo. Flags: `--target <path>` (default
cwd), `--guards a,b` / `--all` (default: all v1 rows of [guards.tsv](references/guards.tsv)),
`--mode advisory|enforce` (default `advisory`), `--dry-run`, `--list`,
`--uninstall <guard>`.

## What it emits

| Guard | Surfaces | Emitted |
|---|---|---|
| `secret-scan` | hook + CI | `.claude/hooks/secret-scan.sh` (gitleaks staged scan), `.gitleaks.toml` (only when absent — a default-ruleset pointer, never overwrites a user's), the `secret-scan` job in `.github/workflows/verification-gates.yml` |
| `commit-on-main` | hook | `.claude/hooks/commit-on-main.sh` → [scripts/verification/precommit-guard.sh](references/guards/precommit-guard.sh.template) + [lib/wrapper-boundary.sh](references/guards/wrapper-boundary.sh.template) (the near-verbatim canonical emit, default-branch set stamped) |
| `block-stash` | hook | `.claude/hooks/block-stash.sh` (chain-boundary `git stash`; `list`/`show` are documented read-only exceptions) |
| `orphan-test` | CI | [scripts/verification/orphan-test-check.sh](references/guards/orphan-test-check.sh.template) + the `orphan-test` job + `.github/verification-known-orphans.txt` (reason-required exclusion manifest, seeded with grandfathered rows) |

Hooks are registered as `PreToolUse` `Bash` entries in `.claude/settings.json`
(node-first, `jq` fallback — a repo with neither is refused with the dependency
named; malformed existing JSON is refused before any write). The workflow lands
at repo ROOT — a nested `.github/workflows/` is dormant.

## Advisory-first contract

Every guard installs **advisory**: identical predicates, different decision verb
— hooks warn+allow (`ask` only on a REAL secret-scan finding), CI jobs carry
`continue-on-error: true`. Promotion is the one-line flip the emitted
`VERIFICATION.md` documents (`MODE="enforce"`, `continue-on-error: false`), and
it requires ≥1 observed clean advisory run first. Non-destructive: any existing
artifact is a refusal — there is no `--force`.

## Agent-owns-gates

Same model as `constraint-scaffold`: the agent owns the emitted files; the
target user never hand-edits a gate. `--uninstall <guard>` removes only that
guard's artifacts + settings entry; it is idempotent and prints "not installed"
for a never-installed guard, and it strips the marker doc block from
VERIFICATION.md/README.md once no guard artifact remains.

## Bite-proof

Every install proves each selected guard **pass → fail → pass** on a detached
worktree under TMPDIR (a TMPDIR inside the repo is refused, exit 69) before the
doc block is written; a mid-install failure removes exactly the files that run
emitted. The `secret-scan` arm requires `gitleaks` on PATH and is reported as a
loud SKIP when absent — an advisory hook that cannot scan is a tool error, not
a silent guard.

## Requirements

bash + POSIX tools on the target host (stock macOS included). Emitted artifacts
carry no Soleur couplings and zero network egress; `manifest.test.sh` pins both.
