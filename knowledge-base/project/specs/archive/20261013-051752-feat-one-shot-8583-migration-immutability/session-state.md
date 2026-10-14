# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/archive/20260923-095513-2026-09-22-feat-migration-immutability-guard-plan.md
- Status: complete
- Plan artifact: complete (selector=branch; new file — no prior plan for this branch)
- Issue: #8583 (OPEN, `meta/machinery`); draft PR #8597; base `origin/main` = `d1fe38939d`.

### Errors
None. Deepen-plan ran sequentially (no Task-agent fan-out in this harness); halt-gate verdicts
are the gates' own, recorded in the plan's "Deepen-Plan Pass" section.

### Decisions
- **Placement:** the guard is a step in the always-run `detect-changes` job of
  `.github/workflows/tenant-integration.yml`, not a new required job — zero ABI churn on
  `required-checks.txt` / `ruleset-ci-required.tf` / canonical JSON, and a `detect-changes` failure
  already fails `tenant-integration-required` closed via `tenant-integration-gate-verdict.sh`.
  This also gives `merge_group` coverage for free (heavy suite is deliberately skipped there).
- **Baseline semantics:** `git diff --no-renames --name-only origin/main...HEAD` — `--no-renames`
  is load-bearing: rename detection hides the source path of a `git mv` (verified live in a
  fixture repo). Per-path authority is `git ls-tree` mode+blob sha on base vs head.
- **`.down.sql` exempt** — never applied by `run-migrations.sh` (glob skip ~line 256), never
  ledgered, so mutation cannot drift the ledger.
- **No escape hatch** — repo doctrine already treats applied migrations as undeletable
  (deletion creates missing-file drift on the probe); remedy for a bad merged migration is a new
  forward file.
- **Named residual (out of scope):** a PR can still mutate its own just-applied unmerged migration
  (`ALLOW_UNMERGED_DEV_APPLY` applies it, then a later commit edits it) — post-section re-probe is
  `::warning::`-only on PRs. Follow-up issue to be filed at work/ship time.
- `lane: cross-domain` — no `spec.md` exists for this branch (direct one-shot entry), so the
  fail-closed default applies per plan SKILL "Save Tasks".

### Components Invoked
- `soleur:plan`
- `soleur:deepen-plan` (sequential fallback — halt gates 4.4–4.11 evaluated inline)

## Work Phase
- Status: complete — guard + suite + workflow wiring implemented; 10/10 matrix rows green;
  FK-lint regression, orphan lint, fixture baselines, workflow lints, vacuity floor all green.
  Residual follow-up arm is covered by existing issue #8521 (verified during review).

## Review Phase
- Status: panel complete — 11 seats, 10 SHIP / 1 NO-SHIP (test-design, suite-completeness
  grounds — all mechanical). Design-validity pass KEEP/SOUND; design-pass fixes landed
  `e12e27a4a1` (fail-closed ls-tree rc, base-copy execution via `git show`, stronger T10/T11
  wiring assertions, `-z` enumeration, BASE_REF normalization).
- Panel findings fixed inline (uncommitted at time of writing → next commit):
  dangling-flag infinite loop (`need_value`), T10/T11 invocation-specific greps,
  `--from-pr-diff` e2e fixture arm (file:// origin remote), ls-tree rc≠0 arm (rc 2),
  assertion floor (CASES/EXPECTED_CASES, direct printf+exit), fetch moved after
  `_assert_repo_root`, base_ref-aware fetch + warning, two-PR neuter closed
  (`git log` existence check — deleted-guard-on-base now fails closed),
  symlink/gitlink admission refused on new files (E6 unguarded channel), mode-only
  change arm, `--from-pr-diff`+`--base` combo rejected, break-glass remediation text
  (never-applied on-main file → auditable ruleset-bypass path), `migration-rollback.md`
  §Emergency Deploy Blocking updated, stale `run-migrations.sh:124` citation in the FK
  sibling repointed to a content anchor, suite promoted into guard-vacuity-floor
  PROMOTED_FILES (deferred ledger stays 47; bound adjacent to `if` for mutant
  constructibility), fixture-relative baseline regenerated (+1 row: the guard's
  `git -C` fetch site).
- Suite now 20/20; shellcheck clean on both scripts; vacuity gate 23/23 (FIRES-verified).
- Deferred residual: unmerged-apply self-mutation arm is covered by existing issue #8521 —
  no new issue needed; cite #8521 in the PR body.

## QA Phase
- Status: pending.
