---
type: bug-fix
lane: single-domain
requires_cpo_signoff: true
brand_survival_threshold: single-user-incident
closes: 3915
partially_unblocks: 4392
---

# fix: Widen destroy-guard to catch `required_check` block removals (#3915)

## Overview

The destroy-guard at `.github/workflows/apply-github-infra.yml:234-235` counts only **resource-level deletes**:

```bash
destroy_count=$(terraform show -json tfplan | \
  jq '[.resource_changes[]? | select(.change.actions? | index("delete"))] | length')
```

When a Terraform diff removes a **nested block** — e.g., a `required_check { ... }` inside `github_repository_ruleset.ci_required.rules[0].required_status_checks[0]` — the parent resource's `change.actions` is `["update"]`, not `["delete"]`. `destroy_count = 0`, the `[ack-destroy]` gate never engages, the apply proceeds silently. The AC20 probe in PR #4395 (closed today) proved this empirically: `Plan: 0 to add, 1 to change, 0 to destroy` while removing the load-bearing `enforce` required_check.

The fix is a **path-specific** widening: count `required_check` array shrinkage on `github_repository_ruleset` resources, sum with the existing resource-delete count, run the same `[ack-destroy]` gate against the combined total. The filter targets exactly the surface that the AC20 probe attacked; it does not generalize to other resources, other nested-block types, or other apply workflows — those are tracked as a follow-up issue.

CODEOWNERS protection on `/infra/github/` is **already present** at `.github/CODEOWNERS:74` (added by #3895/#3896). This plan verifies the existing row still applies; no new CODEOWNERS edit.

## User-Brand Impact

**If this lands broken, the user experiences:** CI failures during `apply-github-infra` runs if the widened filter has a bug (false positive on legitimate updates, or false negative on the case it should catch). Surfaces as a workflow-run failure on the merge commit; operator-noticed within minutes. No user-visible regression.

**If this leaks, the user's data is exposed via:** N/A — no PII, no user data. Workflow operates on Terraform plan JSON.

**Brand-survival threshold:** `single-user-incident` — the chain this defends is `silent un-requiring of a required_check → next PR with a broken status-check merges past CI → broken behavior deployed → user-impact`. The #4333 incident already exercised this chain; closed by #4353. CPO sign-off required at plan time per the brainstorm framing carried forward into this plan.

**Residual sibling-workflow gap (carried by AC10 follow-up):** `apply-sentry-infra.yml` and `apply-web-platform-infra.yml` retain the pre-fix resource-only counter until the AC10 follow-up issue lands; a hypothetical `cloudflare_ruleset`-shaped nested-block removal there is still un-gated. This PR scopes only `apply-github-infra.yml` per the plan-review iteration; it does not regress the siblings, but the class is not fully closed.

## Research Reconciliation — Spec vs. Codebase

The user's original input prescribed two layers and three workflow edits. Reconciliation against the live repo collapses scope:

- **Layer 1 (CODEOWNERS):** already exists at `.github/CODEOWNERS:74` (`/infra/github/ @deruelle`). Drop new-row edit; verify-only.
- **Layer 2 scope:** the user said "widen filter at `apply-github-infra.yml:234-235`." Sibling workflows (`apply-sentry-infra.yml`, `apply-web-platform-infra.yml`) share the same inline filter, BUT (a) the AC20 probe only exercised `apply-github-infra.yml`, and (b) sibling workflows manage resources (`sentry_cron_monitor`, Hetzner/Cloudflare) whose nested-block shape may not match the same fix. Path-specific filter scoped to `github_repository_ruleset` is the right fix here; sibling workflows go to a follow-up tracking issue ("Non-Goals").
- **Filter design:** initial plan draft proposed a recursive-walk jq function. Plan-review (Kieran) reproduced two P0 jq bugs in that design against jq 1.8.1: (a) call-by-name filter-args re-evaluate on a string key during recursion → crash; (b) equal-length parent arrays never recurse → returns 0 on the exact #4395 shape. Path-specific filter avoids both bugs entirely — no recursion, no filter-args ambiguity.
- **Fixture sourcing:** synthesized JSON alone could drift from real provider output across `integrations/github` version bumps. Add one captured fixture from a local `terraform plan` against `infra/github/` HEAD (redacted, no apply) as a regression anchor.

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1 — Widened filter inline in workflow.** `.github/workflows/apply-github-infra.yml` "Destroy guard" step uses the path-specific jq filter (specified in Phase 2). The filter MUST emit `{resource_deletes, nested_deletes}`; the script then sums to `destroy_count = resource_deletes + nested_deletes` before the `[ack-destroy]` gate. Error message preserves the existing `"on github infra"` literal at line 248 (byte-identical phrasing).
- [x] **AC2 — Unit tests pass.** `bash tests/scripts/test-destroy-guard-counter.sh` exits 0. Four cases cover: (a) resource-level delete trips guard, (b) nested `required_check` removal on `github_repository_ruleset` trips guard, (c) no-changes plan passes, (d) `HEAD_MSG` containing line-anchored `[ack-destroy]` allows a destructive plan through.
- [x] **AC3 — Captured real-CI fixture exists.** `tests/scripts/fixtures/tfplan-real-ruleset-baseline.json` is generated via `terraform plan` against `infra/github/` HEAD, then `terraform show -json tfplan`, redacted (`bypass_actors[].actor_id` and any token fields scrubbed), committed. Test asserts `destroy_count == 0` on this fixture (it's a baseline plan with zero destructive changes).
- [x] **AC4 — `shellcheck` passes.** `shellcheck -x tests/scripts/test-destroy-guard-counter.sh` exits 0. The workflow's inline jq filter is also lint-clean (yaml-extracted; verified via `actionlint`).
- [x] **AC5 — Inline old filter fully replaced.** `git grep -nE 'resource_changes\[\?\]\?.*delete.*length' .github/workflows/apply-github-infra.yml` returns zero matches. Also verify `git grep -nE 'destroy_count=\$\(' .github/workflows/apply-github-infra.yml` returns exactly one match (the new assignment). Old single-line filter is gone, not commented out.
- [x] **AC6 — `[ack-destroy]` regex byte-identical.** The bash regex `(^|$'\n')\[ack-destroy\]($|$'\n')` is preserved character-for-character from `apply-github-infra.yml:244`. Verified via `diff` against the pre-edit file.
- [x] **AC7 — `actionlint` passes** on the modified workflow. `actionlint .github/workflows/apply-github-infra.yml` exits 0.

### Post-merge (operator / automation)

- [ ] **AC8 — Close #3915.** `gh issue close 3915 --comment "Fixed in <merge-commit-sha>. Path-specific filter on github_repository_ruleset.required_check now catches nested-block removals; AC20 verified via unit test against PR #4395-shape fixture."`
- [ ] **AC9 — Comment on #4392.** `gh issue comment 4392 --body "AC20 follow-up resolved by <PR-N>. Sibling workflow gaps tracked at <new-issue-N>. AC21 still passive."`
- [ ] **AC10 — File follow-up tracking issue for sibling workflows.** `gh issue create --title "chore: extend destroy-guard widening to apply-sentry-infra and apply-web-platform-infra" --body "..." --label chore --label domain/engineering`. Document the cap-coupling concern and link to this PR.

## Implementation Phases

### Phase 0 — Preconditions

1. **CWD verification.** `pwd` equals `/home/jean/git-repositories/jikig-ai/soleur/.worktrees/feat-fix-destroy-guard-nested-block-3915`. Bash CWD does not persist between tool calls — every command runs with absolute paths or `git -C <abs>` form.
2. **Tooling probe.** `command -v jq actionlint shellcheck terraform` — all four available (verified at plan-time: jq 1.8.1, actionlint + shellcheck in `~/.local/bin/`, terraform via Doppler-wired CI).
3. **Re-read the inline filter** at `.github/workflows/apply-github-infra.yml:234-235` to confirm exact byte boundaries before edit. Re-read `apply-github-infra.yml:244` to lift the `[ack-destroy]` regex verbatim into a `diff`-confirmable comparison.
4. **Confirm CODEOWNERS row** for `/infra/github/` at line 74 — no edit needed.

### Phase 1 — RED (write failing tests + capture fixtures)

1. Create `tests/scripts/fixtures/` directory.
2. **Synthesized fixtures** (raw JSON matching `integrations/github` v6.12.1 `terraform show -json` schema):
   - `tfplan-nested-block-removal.json` — single `github_repository_ruleset.ci_required` with `change.actions = ["update"]`, `change.before.rules[0].required_status_checks[0].required_check[]` length=15, `change.after.required_check[]` length=14 (one `enforce` block removed). Mirrors PR #4395 plan output.
   - `tfplan-no-changes.json` — empty `resource_changes` array.
   - `tfplan-resource-delete.json` — single resource with `change.actions = ["delete"]`, `change.before` populated, `change.after = null`.
3. **Captured fixture** — `tfplan-real-ruleset-baseline.json`:
   - Operator step (single command, in-PR): `cd infra/github && terraform init -backend=false && terraform plan -out=tfplan -refresh=false && terraform show -json tfplan > /tmp/raw.json`
   - Redact via `jq 'del(.. | .bypass_actors? | .[]?.actor_id?) | del(.. | .actions_v2?)' /tmp/raw.json > tests/scripts/fixtures/tfplan-real-ruleset-baseline.json`
   - Manual review of the result: no token values, no `actor_id` integers. If redaction misses a sensitive field, add a `del()` and re-redact.
4. Create `tests/scripts/test-destroy-guard-counter.sh` with four cases (see Test Scenarios table). The test extracts the jq filter from the workflow YAML at runtime via `yq` OR maintains the same filter as a separate `tests/scripts/lib/destroy-guard-filter.jq` file that the workflow `cat`s inline. **Decision:** maintain as a separate `.jq` file at `tests/scripts/lib/destroy-guard-filter.jq`, imported via `jq --slurpfile` in BOTH the workflow's inline shell AND the test — single source of truth, easy to grep, no YAML extraction. (Not a "shared script" — just a `.jq` file the workflow inlines.)
5. **At this point: test references the `.jq` file that doesn't exist yet.** Test fails with `jq: error: Could not open file...`. That's the RED state.

### Phase 2 — GREEN (write the path-specific filter)

1. Create `tests/scripts/lib/destroy-guard-filter.jq`:
   ```jq
   def required_check_count($side):
     ($side // {}) | [.rules[]?.required_status_checks[]?.required_check[]?] | length;

   {
     resource_deletes: ([.resource_changes[]? | select(.change.actions? | index("delete"))] | length),
     nested_deletes:   ([.resource_changes[]?
                         | select(.type == "github_repository_ruleset")
                         | select(.change.actions? | index("delete") | not)
                         | (required_check_count(.change.before) - required_check_count(.change.after))
                         | select(. > 0)
                        ] | add // 0)
   }
   ```
   Notes: uses `$side` (value-arg, jq 1.7+, safe on jq 1.8.1). No recursion. `select(.change.actions? | index("delete") | not)` excludes resources that the outer resource-level count already caught (no double-counting). `select(. > 0)` filters out additions and reorders.

2. Edit `.github/workflows/apply-github-infra.yml` "Destroy guard" step. Replace the inline filter section. The new body (preserving working-directory `${{ env.INFRA_DIR }}` = `infra/github` and `${HEAD_MSG}` env passthrough):
   ```yaml
   - name: Destroy guard
     working-directory: ${{ env.INFRA_DIR }}
     env:
       HEAD_MSG: ${{ github.event.head_commit.message }}
     run: |
       set -euo pipefail
       terraform show -no-color tfplan > tfplan.txt
       counts=$(terraform show -json tfplan | \
         jq -f "${GITHUB_WORKSPACE}/tests/scripts/lib/destroy-guard-filter.jq")
       resource_deletes=$(echo "$counts" | jq -r '.resource_deletes')
       nested_deletes=$(echo "$counts" | jq -r '.nested_deletes')
       if [[ ! "$resource_deletes" =~ ^[0-9]+$ ]] || [[ ! "$nested_deletes" =~ ^[0-9]+$ ]]; then
         echo "::error::destroy-guard counter parse failed (resource_deletes='${resource_deletes}', nested_deletes='${nested_deletes}')."
         exit 1
       fi
       destroy_count=$((resource_deletes + nested_deletes))
       ack_destroy=false
       if [[ "$HEAD_MSG" =~ (^|$'\n')\[ack-destroy\]($|$'\n') ]]; then
         ack_destroy=true
       fi
       if [[ "$destroy_count" -gt 0 ]] && [[ "$ack_destroy" != "true" ]]; then
         echo "::error::terraform plan shows ${destroy_count} destructive change(s) on github infra (${resource_deletes} resource-level delete(s) + ${nested_deletes} nested-block removal(s))."
         echo "::error::Add a line containing exactly '[ack-destroy]' to the merge commit message to acknowledge, or revert the trigger commit."
         grep -E 'will be destroyed|Plan:' tfplan.txt | head -20 >&2
         exit 1
       fi
   ```
3. Run `bash tests/scripts/test-destroy-guard-counter.sh` — must exit 0 (GREEN).
4. Run `shellcheck -x tests/scripts/test-destroy-guard-counter.sh` — must exit 0.
5. Run `actionlint .github/workflows/apply-github-infra.yml` — must exit 0.

### Phase 3 — Pre-ship sanity

1. `git grep -nE 'resource_changes\[\?\]\?.*delete.*length' .github/workflows/apply-github-infra.yml` → 0 matches (AC5 part 1).
2. `git grep -nE 'destroy_count=\$\(' .github/workflows/apply-github-infra.yml` → 1 match (AC5 part 2).
3. `diff <(grep -F '[[ "$HEAD_MSG" =~' .github/workflows/apply-github-infra.yml) <(echo '          if [[ "$HEAD_MSG" =~ (^|$'\''\n'\'')\[ack-destroy\]($|$'\''\n'\'')]]; then')` → no output (AC6, byte-identical regex).
4. PR body draft includes `Closes #3915` line and a Test Plan section enumerating the 4 AC2 cases.

## Files to Edit

- `.github/workflows/apply-github-infra.yml` — replace inline destroy-guard with reference to the shared `.jq` filter; preserve `[ack-destroy]` regex byte-identical; preserve `"on github infra"` error message literal

## Files to Create

- `tests/scripts/lib/destroy-guard-filter.jq` — the path-specific jq filter (single source of truth, used by workflow + test)
- `tests/scripts/test-destroy-guard-counter.sh` — four-case bash test
- `tests/scripts/fixtures/tfplan-nested-block-removal.json` — synthesized, PR #4395 shape
- `tests/scripts/fixtures/tfplan-no-changes.json` — synthesized
- `tests/scripts/fixtures/tfplan-resource-delete.json` — synthesized
- `tests/scripts/fixtures/tfplan-real-ruleset-baseline.json` — captured from real `terraform plan`, redacted

## Open Code-Review Overlap

None. `gh issue list --label code-review --state open --search "infra/github OR apply-github-infra OR destroy-guard"` at plan-time returned 2 unrelated issues (#3414 Playwright E2E, #3829 Sentry monitor scrub-gate) — neither touches the destroy-guard or the proposed paths.

## Infrastructure (IaC)

No new infrastructure. This PR modifies an existing CI workflow that runs against an already-provisioned Terraform root (`infra/github/`). No new Doppler secrets, no new providers, no new vendor accounts.

## Observability

```yaml
liveness_signal:
  what: apply-github-infra workflow runs on every push to main touching infra/github/*.tf
  cadence: per-merge (event-driven)
  alert_target: GitHub Actions UI; failed runs visible in the merge commit's status checks
  configured_in: .github/workflows/apply-github-infra.yml
error_reporting:
  destination: GitHub Actions logs (stderr via ::error:: annotations) + workflow-run failure status
  fail_loud: yes — destroy-guard step exits non-zero with ::error:: naming destroy_count, resource_deletes, nested_deletes
failure_modes:
  - mode: destroy-guard mis-counts nested-block removal (the gap this fixes)
    detection: unit test on `tests/scripts/lib/destroy-guard-filter.jq` against synthesized + captured fixtures
    alert_route: CI failure on any PR touching the .jq file or the workflow
  - mode: jq syntax error in the filter
    detection: jq exits non-zero with parse error; bash `set -euo pipefail` fails the step
    alert_route: Actions log surfaces the jq error directly
  - mode: false positive on a legitimate update
    detection: operator surfaces during apply
    alert_route: PR author adds `[ack-destroy]` to merge commit; no code change
  - mode: filter scope too narrow (e.g., future ruleset adds new nested-block type besides required_check)
    detection: operator surfaces during apply
    alert_route: file a new tracking issue to widen the filter
logs:
  where: GitHub Actions workflow run logs (per-step)
  retention: 90 days (GitHub default)
discoverability_test:
  command: |
    cat tests/scripts/fixtures/tfplan-nested-block-removal.json | jq -f tests/scripts/lib/destroy-guard-filter.jq
  expected_output: '{"resource_deletes":0,"nested_deletes":1}'
```

## Domain Review

**Domains relevant:** engineering (only)

### Engineering — assessed inline

**Status:** reviewed (inline; multi-agent plan-review pass already ran for v1 and surfaced the architecture choices that v2 adopts)
**Assessment:** CI/CD defense-layer fix. Path-specific filter on a well-defined surface. No cross-domain implications. CPO sign-off requirement carries forward from the `single-user-incident` threshold (the user-set framing in the original input); review-time `user-impact-reviewer` will enumerate failure modes against the diff.

### Product/UX Gate

Not applicable. **Tier:** NONE. No user-facing surface modified.

## Test Scenarios

| # | Fixture                              | `HEAD_MSG`              | Expected `resource_deletes` | Expected `nested_deletes` | Expected `destroy_count` | Expected exit |
| - | ------------------------------------ | ----------------------- | --------------------------- | ------------------------- | ------------------------ | ------------- |
| 1 | tfplan-resource-delete.json          | (no ack)                | 1                           | 0                         | 1                        | 1 (gate trips)|
| 2 | tfplan-nested-block-removal.json     | (no ack)                | 0                           | 1                         | 1                        | 1 (gate trips)|
| 3 | tfplan-no-changes.json               | (no ack)                | 0                           | 0                         | 0                        | 0             |
| 4 | tfplan-nested-block-removal.json     | `feat: x\n\n[ack-destroy]\n` | 0                      | 1                         | 1                        | 0 (ack present)|

Plus a regression-anchor probe: `tfplan-real-ruleset-baseline.json` (captured from real `terraform plan`) must yield `destroy_count == 0` (it's a baseline no-op plan).

## Risks

- **R1 — Filter scoped too narrowly (future-proof concern).** Path-specific to `github_repository_ruleset.required_check`. A future ruleset edit that introduces a new nested-block type (e.g., `branch_name_pattern` rules with nested `pattern_rules[]`) would silently bypass this guard. **Mitigation:** documented in Failure Modes; sibling-workflow tracking issue (AC10) is the natural place to widen scope when the second case appears.
- **R2 — Provider version churn changes the JSON path.** `integrations/github` v6.12.1 emits `change.before.rules[].required_status_checks[].required_check[]`; a hypothetical v7 rename to `required_status_check_contexts` would break the filter silently. **Mitigation:** the `tfplan-real-ruleset-baseline.json` fixture (AC3) is the regression anchor — a provider upgrade that breaks the path will surface as the test fixture's `destroy_count` diverging from the asserted value, OR (more likely) the workflow itself failing on the upgrade PR before any guard logic runs.
- **R3 — `terraform show -json` schema stability.** `change.before`/`change.after` are documented contracts (https://developer.hashicorp.com/terraform/internals/json-format#change-representation). Low risk; if Terraform breaks this contract, the entire ecosystem breaks with it.
- **R4 — Squash-merge `[ack-destroy]` placement.** GitHub's "Squash and merge" replaces the merge commit message with PR title + body. Operator must put `[ack-destroy]` on its own line in the PR title or PR body for it to land in the merge commit. The existing regex `(^|$'\n')\[ack-destroy\]($|$'\n')` matches either location as long as the merged HEAD message contains the line-anchored token. Documented in the PR body's notice for any future destructive PR.
- **R5 — Fixture realism (Kieran P1-1).** Synthesized JSON could mis-match real provider output. **Mitigation:** AC3 captures one real `terraform show -json` output, redacted, as a regression anchor. Synthesized fixtures cover the cases real plans rarely produce (e.g., a single nested-block removal without other diff noise).

## Sharp Edges

- **`will be destroyed` literal is NOT emitted on nested-block removals.** I (the plan author) initially considered a grep-based approach (`grep -c 'will be destroyed' tfplan.txt`). Verified against the PR #4395 plan output: Terraform's text formatter writes `# X will be destroyed` for resource-level deletes only; nested-block removals show up as `- required_check {` (minus-prefix on the block opener). A grep on the literal phrase would have replicated the original bug. Documented here so future plan iterations don't re-propose it.
- **`[ack-destroy]` squash-merge interaction.** Squash-merge concatenates PR title + body. `[ack-destroy]` must be on its own line in one of them; not in a feature-branch commit message that gets discarded.
- **Cap-coupling tracked, not fixed.** Sibling workflows (apply-sentry-infra.yml, apply-web-platform-infra.yml) share the same inline filter pattern but manage different resources. Path-specific filter for `github_repository_ruleset` does not apply there. AC10 files a follow-up to evaluate whether sibling workflows need a parallel widening (cloudflare_ruleset has nested-block resources; sentry_cron_monitor does not).

## Non-Goals

- **Generalizing the filter to recursive walk.** Plan v1 proposed this; multi-agent review caught two latent jq bugs and a false-positive risk. Path-specific is correct for the proven attack surface.
- **Fixing the destroy-guard in sibling apply workflows.** Tracked at follow-up (AC10). Cloudflare/Hetzner/Sentry nested-block exposure not yet measured.
- **Re-evaluating ruleset-level "Require review from Code Owners" enforcement.** Out of scope; orthogonal to the destroy-guard fix. Comment at `.github/CODEOWNERS:5-7` notes this is a separate operator-level question.
- **Re-running the AC20 probe live post-merge.** Unit-test against the AC20-shape synthesized fixture IS the equivalent verification. A real re-probe would require merging a destructive PR to fire the guard, which is the exact action the guard exists to prevent.
- **Closing #4392 fully.** AC21 still passive until next bot PR after #4385 merges. This PR closes #3915 only.

## References

- **#3915** — destroy-guard end-to-end test gap (this closes)
- **#4392** — AC19/AC20/AC21 tracking issue (partially unblocks)
- **#4395** — closed today, surfaced the gap via `Plan: 0 to add, 1 to change, 0 to destroy` on a `required_check` removal
- **#4385** — the migration that introduced the `enforce` required_check
- **#4333** / **#4353** — prior incident chain this defense prevents
- **`.github/workflows/apply-github-infra.yml:234-251`** — current destroy-guard
- **`.github/CODEOWNERS:74`** — existing `/infra/github/` CODEOWNERS row
- **`infra/github/ruleset-ci-required.tf`** — the protected resource
- **Terraform JSON output format** — https://developer.hashicorp.com/terraform/internals/json-format#change-representation
- **Plan-review iteration log** — three reviewers (DHH, Kieran, simplicity) on plan v1 produced this v2; Kieran caught two latent P0 jq bugs (call-by-name args, equal-length-arrays don't recurse) that v2 dissolves by going path-specific
- **Existing test convention** — `tests/scripts/test-audit-ruleset-bypass.sh`, `tests/scripts/test-kb-drift-walker.sh`
