# B5 eval results (#8290)

> **DRAFT: pre-run section only.** No API call has been made. The verdict, rates, tokens and cost are
> added after the paid run (Phase 3 steps 5-6). The raw grid is kept outside the repo.

## Pre-registration (committed before the run)

- Verdict module: `plugins/soleur/skills/eval-harness/scripts/rule-phrasing-verdict.cjs` sha256 `18c2481ca32bab7176cbfcb737b3b4233c38436e116438e59a6db5828c9cbf28`
- Scoring module: `plugins/soleur/skills/eval-harness/scripts/measure-rule-compliance.cjs` sha256 `8a2d24bd61941dfe97ef0563d070c8d2e5d78495ce6f58f03a0718846b0bbce2`
- Fixture: `plugins/soleur/skills/eval-harness/prompts/rule-phrasing-bodies.json` sha256 `d4f13b349914f9c9f0818b6c3afbdfb5b85a9c63df648152e542b1671b57d8ad`
- Tasks: `plugins/soleur/skills/eval-harness/tasks/rule-phrasing.jsonl` sha256 `bf1e99e70f283dd171b144476c98e6b64298b313d16468b5a8a6d4d93dcfdcfd` (24 rows, 6 per rule)
- MWE 0.10, epsilon 1/24, ceiling 0.95, interval Delta +/- 2 SE clustered by task. Precedence: ABORTED > INVALID > REJECT-CEILING > EXTEND > REJECT > INCONCLUSIVE.
- promptfoo 0.123.1. `npx promptfoo validate config -c promptfooconfig-rule-phrasing.yaml`: `Configuration is valid.` (exit 0).

## Fit check: B_ALWAYS with the positive bodies swapped in

| Rule | Prohibition body (B) | Positive body (B) | Delta (B) |
|---|---|---|---|
| `hr-never-git-stash-in-worktrees` | 236 | 278 | 42 |
| `hr-never-run-commands-with-unbounded-output` | 236 | 223 | -13 |
| `hr-never-write-to-claude-code-memory-claude` | 367 | 329 | -38 |
| `wg-never-bump-version-files-in-feature` | 422 | 286 | -136 |

- `python3 scripts/lint-agents-rule-budget.py AGENTS.md AGENTS.rules.md` on the live tree: `[OK] B_ALWAYS=42920`.
- The same lint on a temporary copy with the four positive bodies swapped in: `[OK] B_ALWAYS=42775` (-145 B). That is under the 44,000 warn tier, and every body is under the 600 B cap.

## AC-E2: rendered arms

Rendered with `node -e` over `prompts/rule-phrasing.cjs` (`buildCorpus(arm)`), then diffed.

```text
none.txt 41539 B sha256=41921a4dd5f1b530
positive.txt 42850 B sha256=95c0298ba05e66d7
prohibition.txt 42995 B sha256=d6c351d445db1ba5
```

### prohibition vs positive: exactly 4 lines change (the 4 target bodies)

```diff
--- prohibition
+++ positive
@@ -141 +141 @@
-- Never `git stash` in worktrees [id: hr-never-git-stash-in-worktrees] [hook-enforced: guardrails.sh guardrails:block-stash-in-worktrees]. Commit WIP first; `git show <commit>:<path>` inspects old code without touching the working tree.
+- In a worktree, commit WIP before switching context [id: hr-never-git-stash-in-worktrees] [hook-enforced: guardrails.sh guardrails:block-stash-in-worktrees]; inspect old code with `git show <commit>:<path>`, which leaves the working tree untouched. `git stash` is blocked here.
@@ -162,2 +162,2 @@
-- Never run unbounded-output commands in subagents — pipe through `| head -n 500` or `| tail -n 200` [id: hr-never-run-commands-with-unbounded-output]. Subagent stdout goes to tmpfs; unbounded output fills it and crashes all sessions.
-- Never write to Claude Code memory (`~/.claude/projects/*/memory/`) or local-only locations [id: hr-never-write-to-claude-code-memory-claude] [hook-enforced: .claude/hooks/no-memory-write.sh]. All knowledge goes to committed files: AGENTS.md, constitution.md, `knowledge-base/project/learnings/`, `.mcp.json`. Test: would a new Soleur user cloning the repo get this?
+- In subagents, bound every command's output — `| head -n 500` or `| tail -n 200` [id: hr-never-run-commands-with-unbounded-output]. Subagent stdout lands on tmpfs, and unbounded output fills it and crashes every session.
+- Put all knowledge in committed files — AGENTS.md, constitution.md, `knowledge-base/project/learnings/`, `.mcp.json` — so a new Soleur user cloning the repo gets it [id: hr-never-write-to-claude-code-memory-claude] [hook-enforced: .claude/hooks/no-memory-write.sh]. Claude Code memory and other local-only paths are blocked.
@@ -194 +194 @@
-- Never bump version files in feature branches [id: wg-never-bump-version-files-in-feature]. Version comes from git tags — CI creates `vX.Y.Z` GitHub Releases at merge time via semver labels (set with `soleur:ship`). No plugin manifest carries a `version` key; never add one back — `plugin update` compares version strings, so a constant one always compares equal and the update no-ops while reporting success (#7471).
+- Leave version files to CI [id: wg-never-bump-version-files-in-feature]: `vX.Y.Z` releases are cut from git tags at merge via semver labels (set with `soleur:ship`). No plugin manifest carries a `version` key, and adding one makes `plugin update` no-op while reporting success (#7471).
```

### prohibition vs none: exactly 8 lines removed (4 AGENTS.md pointers + 4 bodies), none added

```diff
--- prohibition
+++ none
@@ -7 +6,0 @@
-- [id: hr-never-git-stash-in-worktrees]
@@ -28,2 +26,0 @@
-- [id: hr-never-run-commands-with-unbounded-output]
-- [id: hr-never-write-to-claude-code-memory-claude]
@@ -60 +56,0 @@
-- [id: wg-never-bump-version-files-in-feature]
@@ -141 +136,0 @@
-- Never `git stash` in worktrees [id: hr-never-git-stash-in-worktrees] [hook-enforced: guardrails.sh guardrails:block-stash-in-worktrees]. Commit WIP first; `git show <commit>:<path>` inspects old code without touching the working tree.
@@ -162,2 +156,0 @@
-- Never run unbounded-output commands in subagents — pipe through `| head -n 500` or `| tail -n 200` [id: hr-never-run-commands-with-unbounded-output]. Subagent stdout goes to tmpfs; unbounded output fills it and crashes all sessions.
-- Never write to Claude Code memory (`~/.claude/projects/*/memory/`) or local-only locations [id: hr-never-write-to-claude-code-memory-claude] [hook-enforced: .claude/hooks/no-memory-write.sh]. All knowledge goes to committed files: AGENTS.md, constitution.md, `knowledge-base/project/learnings/`, `.mcp.json`. Test: would a new Soleur user cloning the repo get this?
@@ -194 +186,0 @@
-- Never bump version files in feature branches [id: wg-never-bump-version-files-in-feature]. Version comes from git tags — CI creates `vX.Y.Z` GitHub Releases at merge time via semver labels (set with `soleur:ship`). No plugin manifest carries a `version` key; never add one back — `plugin update` compares version strings, so a constant one always compares equal and the update no-ops while reporting success (#7471).
```

### `[`-tag tokens

```text
tags prohibition=240 positive=240 none=230 | positive==prohibition: true | none==prohibition-minus-removed-lines: true | tags on removed lines: 10
```

The positive arm carries all 240 `[tag: …]` tokens byte-identical and in order. The none arm carries the
230 tokens on its surviving lines, identical to the same lines in prohibition. The 10 tokens that are missing
are the ones on the 8 removed lines.

### Hash-lock observed

`bash plugins/soleur/skills/eval-harness/test/rule-phrasing.test.sh` mutates one fixture body on a temp copy. The generator then throws
`rule-phrasing: hash-lock: fixture hr-never-git-stash-in-worktrees.prohibition does not hash to its prohibition_sha256`.
A re-hashed but mutated body, and a drifted live body, each throw `hash-lock: live body … != fixture prohibition_sha256`.
