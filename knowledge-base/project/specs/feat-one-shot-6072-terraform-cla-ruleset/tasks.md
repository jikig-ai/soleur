---
title: "Tasks — Terraform-ify the CLA Required ruleset (#6072)"
issue: 6072
branch: feat-one-shot-6072-terraform-cla-ruleset
lane: single-domain
plan: knowledge-base/project/plans/2026-07-06-chore-terraform-cla-required-ruleset-plan.md
---

# Tasks — chore(infra): Terraform-ify the CLA Required ruleset (#6072)

Single atomic PR. Phases are dependency-ordered for `/work` (not a merge split).

## Phase 0 — Preconditions

- [ ] 0.1 Re-run the code-review overlap query (two-stage `gh --json` + standalone
      `jq --arg`) against the 8 planned file paths; confirm zero matches.
- [ ] 0.2 Confirm the daily `cron-ruleset-bypass-audit` CLA step is currently green
      (substantiates live == canonical == `.tf`, i.e. the no-op-first-apply premise).

## Phase 1 — Author `infra/github/ruleset-cla-required.tf`

- [ ] 1.1 Create `infra/github/ruleset-cla-required.tf` with
      `resource "github_repository_ruleset" "cla_required"`: `name = "CLA Required"`,
      `repository = var.gh_repo`, `target = "branch"`, `enforcement = "active"`;
      `conditions { ref_name { include = ["~DEFAULT_BRANCH"]; exclude = [] } }`.
- [ ] 1.2 Add three `bypass_actors` blocks: OrganizationAdmin `actor_id = 0`/pull_request;
      RepositoryRole `actor_id = 5`/pull_request; Integration `actor_id = 1236702`/always.
- [ ] 1.3 Add `rules { required_status_checks { strict_required_status_checks_policy = false;
      do_not_enforce_on_create = false; required_check "cla-check" @ var.actions_integration_id;
      required_check "cla-evidence" @ var.actions_integration_id } }`.
- [ ] 1.4 Write the header comment (byte-identical-to-canonical note; `strict=false` + third
      bypass-actor divergences from CI; SE-1 `0`↔`null` sentinel; job-name ABI contract).
      **Token hygiene (SE-3):** header/block comments must contain NO literal
      `context = "..."`, `required_check {`, or `bypass_actors {` token, and NO inline
      `# ... = ...` on any assignment line. Keep SE-1 rationale in the header only.
- [ ] 1.5 `cd infra/github && terraform fmt` then `terraform init -backend=false &&
      terraform validate` — both green for the now-two-resource root.

## Phase 2 — Wire into the apply path (`.github/workflows/apply-github-infra.yml`)

- [ ] 2.1 Replace the blanket `grep -qE '^github_repository_ruleset\.'` import gate with a
      per-address `import_ruleset()` helper importing BOTH `ci_required soleur:14145388`
      AND `cla_required soleur:13304872` (`grep -qxF` full-line match; refresh `state_list`
      after each import). Add the `moved {}`-rename caveat comment.
- [ ] 2.2 Extend the Post-apply verify step to probe `rulesets/13304872` (reuse the minted
      `INSTALL_TOKEN`; `select(.type=="required_status_checks") | ... | length` == 2);
      surface `cla_actual_count` in `$GITHUB_OUTPUT` + Post-apply summary.

## Phase 3 — Repoint the CLA sync gates (`tests/scripts/test-audit-ruleset-bypass.sh`)

- [ ] 3.1 Delete the `_cla_create_payload` heredoc-slice helper.
- [ ] 3.2 Rewrite `T-cla-1` to pin the CLA RSC canonical to
      `infra/github/ruleset-cla-required.tf`: context-set equality via the T-rsc-9 grep +
      integration_id pin (canonical rows all 15368; `.tf` binds `var.actions_integration_id`
      x2, no `codeql_integration_id`); no-dup; `>= 2` floor. Guard the two negative greps for
      `set -e` (`|| true` / `if grep -q; then fail`).
- [ ] 3.3 Rewrite `T-cla-1b` to pin the CLA bypass canonical to the `.tf`: awk-parse the
      `bypass_actors` blocks into triples, `sed 's/^0|/null|/'` normalize, compare to canonical
      `jq -r '.[] | "\(.actor_id)|\(.actor_type)|\(.bypass_mode)"' | sort`; no-dup; `>= 3` floor.
- [ ] 3.4 Update the CLA-gate section header comment (imperative/deferred → Terraform-managed,
      gates pin canonicals to the `.tf`).

## Phase 4 — Demote `scripts/create-cla-required-ruleset.sh` to DR-only skeleton

- [ ] 4.1 Rewrite header: DR restore path only; SSOT is `infra/github/ruleset-cla-required.tf`
      + `apply-github-infra.yml`; run `terraform import`+`apply` after to reconcile.
- [ ] 4.2 Read + validate the two CLA canonical JSONs and merge via `jq --slurpfile`; REMOVE
      the inline `cat > "$payload" << 'EOF'` heredoc. Preserve `strict=false`, `enforcement=active`,
      `do_not_enforce_on_create=false`.
- [ ] 4.3 Add the DR-only existence guard (exit 0 if "CLA Required" ruleset already exists).
      Do NOT copy create-ci's `context=test` bot-workflow preflight (CI-semantic, wrong for CLA).

## Phase 5 — Reconcile docs + cron hint

- [ ] 5.1 `cron-ruleset-bypass-audit.ts`: `CLA_AUDIT_CONFIG.sourceHint` →
      `"infra/github/ruleset-cla-required.tf"`; update the file-header comment (drop the
      "imperative / deferred #6061 Phase 6.1" assertion). `tsc --noEmit` green.
- [ ] 5.2 `ruleset-bypass-drift.md`: CLA is now Terraform-managed (apply via
      `apply-github-infra.yml`); "kept in lockstep with the create-script's inline blocks" →
      "with `infra/github/ruleset-cla-required.tf`"; remedy reconcile line → the `.tf` + canonicals.
- [ ] 5.3 `cla-signature-evidence-retrieval.md:428`: `.tf` is SSOT; create-script is DR-only.
- [ ] 5.4 `infra/github/README.md`: add CLA import subsection (resource `cla_required`,
      id `13304872`, mirrors the CI Phase 1 manual reconcile with `soleur:13304872`).
- [ ] 5.5 ADR-032: append dated CLA amendment (CLA ruleset now managed by the same root;
      create-script demoted to DR skeleton).

## Phase 6 — Verify

- [ ] 6.1 `bash tests/scripts/test-audit-ruleset-bypass.sh` exits 0; `T-cla-1`/`T-cla-1b`
      report `ok` against the `.tf`; `T-rsc-9` still green (file-scoped grep unperturbed).
- [ ] 6.2 RED-proof `T-cla-1b`: flip OrgAdmin `actor_id → 7`, confirm `fail`, revert.
- [ ] 6.3 Comment-safe count ACs: `grep -cE '^[[:space:]]*required_check[[:space:]]*\{'` → 2;
      `grep -cE '^[[:space:]]*bypass_actors[[:space:]]*\{'` → 3;
      `grep -c 'import_ruleset github_repository_ruleset' apply-github-infra.yml` → 2;
      `grep -c _cla_create_payload tests/scripts/test-audit-ruleset-bypass.sh` → 0.
- [ ] 6.4 `bash -n scripts/create-cla-required-ruleset.sh`; confirm no `<< 'EOF'` heredoc.
- [ ] 6.5 PR body uses `Ref #6072` (NOT `Closes`); `/ship` closes #6072 after the post-merge
      apply run is green.
