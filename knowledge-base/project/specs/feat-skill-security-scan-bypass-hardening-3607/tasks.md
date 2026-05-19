---
title: Tasks for #3607 — skill-security-scan tool-allowlist widening (aria2c, axel)
issue: 3607
branch: feat-skill-security-scan-bypass-hardening-3607
plan: knowledge-base/project/plans/2026-05-12-fix-skill-security-scan-tool-allowlist-widening-plan.md
---

# Tasks: skill-security-scan tool-allowlist widening (#3607)

Derived from the post-review plan. Phases 1+2 MUST land in the same commit (rule-pack SHA atomicity).

## Phase 1 — Widen alternation in code-exec.yaml

- [ ] 1.1 Read `plugins/soleur/skills/skill-security-scan/references/rules/code-exec.yaml` to confirm current state.
- [ ] 1.2 Single Edit with `replace_all: true`: substitute `(curl|wget|fetch)` → `(curl|wget|fetch|aria2c|axel)` across the file. Expected: 4 replacements (rule 1 line 60, rule 2 line 65, rule 3 line 70 has two — `$(...)` form + backtick form).
- [ ] 1.3 Post-edit verification grep:
  ```bash
  grep -cE '\(curl\|wget\|fetch\|aria2c\|axel\)' plugins/soleur/skills/skill-security-scan/references/rules/code-exec.yaml
  ```
  Expect: `4`.

## Phase 2 — Recompute manifest SHA (SAME COMMIT as Phase 1)

- [ ] 2.1 Compute new SHA:
  ```bash
  NEW_SHA=$(sha256sum plugins/soleur/skills/skill-security-scan/references/rules/code-exec.yaml | cut -d' ' -f1)
  echo "$NEW_SHA"
  ```
- [ ] 2.2 Edit `plugins/soleur/skills/skill-security-scan/references/rules/manifest.yaml`: replace the existing `sha256:` value for `code-exec.yaml` with the new SHA.
- [ ] 2.3 Stage BOTH files together:
  ```bash
  git add plugins/soleur/skills/skill-security-scan/references/rules/code-exec.yaml \
          plugins/soleur/skills/skill-security-scan/references/rules/manifest.yaml
  ```
- [ ] 2.4 Commit (Phase 1 + Phase 2 atomic):
  ```bash
  LEFTHOOK=0 git commit -m "feat(security): widen fetch-* rules to (curl|wget|fetch|aria2c|axel) + recompute SHA"
  ```

## Phase 3 — Extend fixture with 6 new snippets

- [ ] 3.1 Edit `plugins/soleur/skills/skill-security-scan/references/test-fixtures/malicious-curl-pipe-bash.skill.md`: append a new section with 6 exploit snippets (2 tools × 3 rules) per plan Phase 3.

## Phase 4 — Extend test count assertions

- [ ] 4.1 Edit `plugins/soleur/test/skill-security-scan.test.ts` at lines 84-91:
  - Bump `fetchPipeCount >= 3` → `>= 5`
  - Bump `fetchCmdsubCount >= 2` → `>= 4`
  - Add `fetchProcessSubCount >= 3` (new declaration + assertion)
  - Update inline comment to document aria2c|axel coverage

## Phase 5 — Verify (run from worktree root)

- [ ] 5.1 `bun test plugins/soleur/test/skill-security-scan.test.ts` — pass
- [ ] 5.2 `bash plugins/soleur/skills/skill-security-scan/scripts/run-self-test.sh` — exit 0
- [ ] 5.3 Calibration re-grep:
  ```bash
  for f in $(find plugins/soleur/skills -name SKILL.md); do
    verdict=$(bash plugins/soleur/skills/skill-security-scan/scripts/run-scan.sh "$f" 2>/dev/null | grep -oE 'HIGH-RISK|REVIEW|LOW-RISK' | head -1)
    if [ "$verdict" = "HIGH-RISK" ]; then echo "HIGH-RISK: $f"; fi
  done
  ```
  Expect: empty.
- [ ] 5.4 `bash scripts/test-all.sh` — ≥35/36 suites
- [ ] 5.5 `bun run --cwd apps/web-platform tsc --noEmit` — exit 0
- [ ] 5.6 SHA-atomicity machine check (AC3a):
  ```bash
  yaml_c=$(git log --oneline -- plugins/soleur/skills/skill-security-scan/references/rules/code-exec.yaml | head -1 | awk '{print $1}')
  manifest_c=$(git log --oneline -- plugins/soleur/skills/skill-security-scan/references/rules/manifest.yaml | head -1 | awk '{print $1}')
  [ "$yaml_c" = "$manifest_c" ] && echo ATOMIC || echo "SPLIT: $yaml_c vs $manifest_c"
  ```
  Expect: `ATOMIC`.

## Phase 6 — Ship-time follow-ups (BEFORE PR is marked ready)

- [ ] 6.1 Write class-(a) follow-up issue body to `/tmp/class-a-followup-body.md` per plan Phase 6a template.
- [ ] 6.2 File issue:
  ```bash
  gh issue create \
    --title "feat: skill-security-scan — detect split-line / indirect-invocation curl-pipe-bash obfuscation" \
    --label "priority/p3-low,domain/engineering,code-review,deferred-scope-out" \
    --milestone "Post-MVP / Later" \
    --body-file /tmp/class-a-followup-body.md
  ```
  Record the new issue number.
- [ ] 6.3 Update PR body to reference `Closes #3607` AND link the new (a) follow-up issue number.

## Phase 7 — Ship

- [ ] 7.1 `gh pr ready <PR-number>`
- [ ] 7.2 `gh pr merge <PR-number> --squash --auto`
- [ ] 7.3 Post-merge: comment on closed #3607 linking the new (b) PR and the new (a) follow-up issue (AC9).
