# Session State

## Plan Phase
- Plan file: knowledge-base/project/plans/2026-09-22-feat-migration-immutability-guard-plan.md
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
  Residual follow-up issue for the unmerged-apply self-mutation arm still to be filed at ship time.

## Review Phase
- Status: pending.

## QA Phase
- Status: pending.
