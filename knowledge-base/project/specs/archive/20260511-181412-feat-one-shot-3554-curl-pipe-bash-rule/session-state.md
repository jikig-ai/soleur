# Session State

## Plan Phase
- Plan file: /home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-one-shot-3554-curl-pipe-bash-rule/knowledge-base/project/plans/2026-05-11-fix-skill-security-scan-curl-pipe-bash-rule-plan.md
- Status: complete

### Errors
None.

### Decisions
- Three independent rules (pipe, process-substitution, command-substitution) not one combined regex — matches `code-exec.yaml` convention.
- Single-line YAML descriptions are load-bearing: `apply_yaml_rules` awk parser silently drops `description: |` block scalars. Now a halting Sharp Edge + enforcement AC.
- End-to-end empirical verification at plan time: scanner verdict flips `LOW-RISK` → `HIGH-RISK` on issue-body reproducer + three-variant fixture.
- Calibration corpus is clean: zero current matches across `plugins/soleur/skills/**/SKILL.md` + `plugins/soleur/agents/**/*.md`. No grandfathering needed.
- Adversary-bypass hardening (split-line / indirect-invocation obfuscation) deferred via tracking issue at merge, not absorbed.

### Components Invoked
- soleur:plan, soleur:deepen-plan
- Bash (~25 invocations for live verification: gh issue/pr view, regex calibration grep, parser smoke-tests, end-to-end integration test)
- Read (8 invocations: brainstorm doc, rule pack source, lib.sh parser, run-scan.sh, run-self-test.sh, PR-trailer workflow, test suite, spec.md)
- Edit / Write (1 Write + 5 Edits)
