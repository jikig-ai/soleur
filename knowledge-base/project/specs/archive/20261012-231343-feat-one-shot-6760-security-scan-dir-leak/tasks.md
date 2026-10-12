# Tasks — feat-one-shot-6760-security-scan-dir-leak

Plan: `knowledge-base/project/plans/2026-10-12-fix-skill-security-scan-runtime-dir-retention-plan.md`

## Phase 1 — Code

- [ ] 1.1 In `plugins/soleur/skills/skill-security-scan/scripts/run-scan.sh`,
      add the scratch-orphan sweep adjacent to the existing `meta_dir` reap
      (after the `skill-security-scan-*` block, reusing `_reap_min`):
      `find "${TMPDIR:-/tmp}" -mindepth 1 -maxdepth 1 -user "$(id -u)" -mmin "+${_reap_min}" \( -name 'skill-security-scan-*' -o -name 'skill-scan-*' \) ! -path "$INPUT" ! -path "$results_dir" -exec rm -rf {} + 2>/dev/null || true`
      behind an `[ -d "${TMPDIR:-/tmp}" ]` guard. Keep the shipped meta sweep
      untouched.
- [ ] 1.2 In the same block's rationale comment, add `#6760` alongside `#6789`
      and note both families are bounded here; state why `! -path` exclusions
      exist (own-scratch predates the reap — the asymmetry the shipped comment
      does not cover).
- [ ] 1.3 Extend `plugins/soleur/skills/skill-security-scan/test/meta-dir-reap.test.sh`
      with scratch-family arms (test sets `TMPDIR` to a fixture root):
      old `skill-scan-input-*` file reaped; old `skill-scan-results-*` dir
      reaped; old `skill-scan-*.code`-style sibling reaped; an old
      `skill-security-scan-*` dir under `TMPDIR` reaped (XDG-toggle
      crossover arm); fresh `skill-scan-*` entry spared; source anchors for
      `-name 'skill-scan-*'`, `-user "$(id -u)"`, and the `! -path` exclusions
      (with a positive control that each regex matches the live code).
- [ ] 1.4 In `plugins/soleur/scripts/lib/tmp-classify.sh`, replace the
      `# #6760 deliberate retention` comment (protection row at
      `tc_is_protected`) with the accurate justification — bounded by the
      scanner's own startup reap; generic sweepers must not out-race the
      evidence window. Do not change the `return 0` arm.
- [ ] 1.5 Verify: `bash plugins/soleur/skills/skill-security-scan/test/meta-dir-reap.test.sh`
      exits 0 with `0 failed`.

## Phase 2 — Docs

- [ ] 2.1 In `plugins/soleur/skills/skill-security-scan/SKILL.md`, extend the
      Output section: `.scan-meta.json` lives under
      `$XDG_RUNTIME_DIR/skill-security-scan-<pid>/` (or `SKILL_SCAN_META_BASE`),
      is startup-reaped past `SKILL_SCAN_META_REAP_MIN` (default 7 days), and
      is deliberately NOT EXIT-trap-cleaned (post-exit consumer contract).
- [ ] 2.2 In `plugins/soleur/skills/skill-security-scan/references/override-mechanism.md`,
      note in the `findings_json` path-form guidance that the path is valid
      only inside the retention window; name the durable alternative (inline
      copy, schema-permitted) for references that must outlive it.
- [ ] 2.3 Lint the two edited docs with the repo markdownlint path
      (`bash scripts/markdown-lint.sh <files>`) — both are in lint scope.

## Phase 3 — Close-out

- [ ] 3.1 PR body: `Closes #6760`, evidence trail (reap shipped via #6828;
      this PR documents the policy, extends the sweep to scratch orphans,
      corrects the stale `tmp-classify.sh` justification), `## Changelog`
      section.
- [ ] 3.2 Label: `semver:patch` (plugins/soleur change).
- [ ] 3.3 AC sweep against the plan's Acceptance Criteria list before
      `soleur:ship`.
