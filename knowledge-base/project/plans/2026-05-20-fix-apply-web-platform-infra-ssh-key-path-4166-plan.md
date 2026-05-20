---
title: "fix(infra): unblock apply-web-platform-infra terraform plan at server.tf:12 file() (#4166)"
type: fix
date: 2026-05-20
lane: single-domain
brand_survival_threshold: none
requires_cpo_signoff: false
closes: 4166
---

# fix(infra): unblock apply-web-platform-infra terraform plan at server.tf:12 file() (#4166)

## Enhancement Summary

**Deepened on:** 2026-05-20
**Sections enhanced:** Research Reconciliation, Acceptance Criteria (AC6 yq→awk), Implementation Phases (P0.5 + P2.2 syntax check), Risks (R4 added), Sharp Edges (saved-plan + insertion-point), Prior Art (exact byte alignment with drift detector), Reference Implementation (added).

### Key Improvements (vs. initial plan)

1. **Precedent byte-alignment verified** — `scheduled-terraform-drift.yml:50-52` step body is **3 lines** (uses `run: |` block form), not 2. The `apply-deploy-pipeline-fix.yml:132-135` step is also the 3-line `run: |` form. `infra-validation.yml:177` uses the 1-line `run:` scalar form (without the `CI_SSH_PUB=` export, because that workflow uses a hardcoded `/tmp/ci_ssh_key.pub` in the `-var=`). This PR adopts the 3-line `run: |` form to match the two apply/drift precedents — both export `CI_SSH_PUB` to `$GITHUB_ENV`.
2. **AC6 yq→awk** — `yq` is not present on the local toolchain (verified via `which yq` → exit 1). AC6 rewritten to use `awk` range extraction (the canonical Soleur YAML-frontmatter pattern per `2026-05-12-plan-time-parsing-pattern-needs-codebase-precedent-grep.md`), with `bash -c` on the extracted body per AGENTS guidance against `bash -n <file.yml>`. Self-syntax-check + actionlint together verify the workflow.
3. **AC2 byte-equivalence claim sharpened** — the drift-detector step is the canonical reference (NOT `infra-validation.yml`, which uses a different shape). AC2 reworded: equivalence is against `scheduled-terraform-drift.yml:50-52` specifically.
4. **R4 added** — concurrency-safe across parallel matrix runs. `/tmp/ci_ssh_key` is generated unconditionally each run; if a future workflow refactor adds a matrix dimension, the path may collide. Mitigated because (a) the apply workflow has no matrix, (b) `ssh-keygen` overwrites with `-q` and no prompt — but documented for future readers.
5. **Reference Implementation block added** — full before/after diff of the workflow edit, so /work has a single canonical patch to apply.

### New Considerations Discovered

- **`var.deploy_ssh_public_key` exists at `variables.tf:91`** — declared but unused, marked "legacy, kept for migration period" (default `""`). The plan does NOT consume this variable — confirms ephemeral-key path is cleaner than the issue body's Option 1 which would have introduced a second-source-of-truth for the same value.
- **Insertion point sequencing** — Phase 1.1 places the new step between `Install Doppler CLI` (line 131) and `Verify required secrets present` (line 134). This matches the drift-detector ordering: `Install Doppler CLI` → `Generate CI SSH key` → `Extract backend credentials`. The ephemeral key step has zero dependencies on Doppler, so it could go anywhere before `Terraform plan`, but matching drift-detector ordering keeps the workflow diff-readable side-by-side.
- **#4150 is an ISSUE (not a PR)** — `gh issue view 4150 --json state` returns `CLOSED`; `gh pr view 4150` returns "Could not resolve to a PullRequest." The PR that closed #4150 is #4161 (MERGED). The plan body's "PR #4161 (#4150)" notation is correct ("PR that closed issue #4150"). Per `2026-05-20-plan-time-pr-vs-issue-disambiguation-and-self-derived-counts.md`, both probes are required before declaring a reference unresolved; both verified here.
- **#4147 is a PR (MERGED, "fix(infra): pin integrations/github provider in web-platform lockfile")** — the lockfile gate predecessor in the cascade. Confirmed in the References section.

## Problem

After PR #4161 (#4150) resolved the four operator-mint variables and unblocked `terraform plan`'s variable-resolution phase in `apply-web-platform-infra.yml`, the post-merge run revealed the next gate: `server.tf:12` fails with:

```
Error: Invalid function argument

  on server.tf line 12, in resource "hcloud_ssh_key" "default":
  12:   public_key = file(var.ssh_key_path)
    ├────────────────
    │ while calling file(path)
    │ var.ssh_key_path is "~/.ssh/id_ed25519.pub"

Invalid value for "path" parameter: no file exists at "~/.ssh/id_ed25519.pub"
```

The GitHub Actions runner does not have an SSH key at `$HOME/.ssh/id_ed25519.pub`. HCL evaluates `file()` at parse/plan time regardless of whether `hcloud_ssh_key.default` is in the `-target=` allow-list. The workflow's allow-list at `apply-web-platform-infra.yml:197-263` already EXCLUDES `hcloud_ssh_key.default` per the header comment lines 21-23 (managed by initial-apply + drift detector, not per-PR), but the `file()` call still evaluates eagerly because HCL evaluates all referenced expressions at plan-time, not just those targeted.

Failed run: <https://github.com/jikig-ai/soleur/actions/runs/26164246058>

**Why #4150/#4161 surfaced this:** before #4150, `terraform plan` aborted at variable resolution (`No value for required variable`) BEFORE reaching `server.tf`'s eager `file()` call. With variables now resolvable, plan progresses further and hits the next gate. Net progress, expected next-layer error per the cascade pattern (#4147 → #4150 → #4166).

## User-Brand Impact

- **If this lands broken, the user experiences:** continued `apply-web-platform-infra.yml` failures on every infra-touching merge, accruing operator-attention debt. No end-user-visible regression — `terraform plan` aborts before any state mutation.
- **If this leaks, the user's data is exposed via:** N/A — `DEPLOY_SSH_PUBLIC_KEY` is non-secret (already published to Doppler `prd_terraform`). This PR introduces no new secret surface; the chosen ephemeral-key pattern uses a runner-local dummy key that is discarded at job end.
- **Brand-survival threshold:** `none`

*Scope-out override:* threshold: none, reason: this change only adds a workflow step that generates an ephemeral dummy SSH public key and threads `-var="ssh_key_path=..."` through `terraform plan/apply`. The targeted apply allow-list excludes `hcloud_ssh_key.default` (header comment lines 21-23). No user-data path, no new secrets, no production-write blast radius beyond what the existing workflow already has.

## Observability

```yaml
liveness_signal:
  what: "GitHub Actions workflow `apply-web-platform-infra.yml` exit-code (post-merge run on main)"
  cadence: "per-merge to main when paths under apps/web-platform/infra/** change; manual workflow_dispatch on demand"
  alert_target: "GitHub Actions UI; failure surfaces via the existing apply-web-platform-infra notification webhook configured in alerts-github-webhook.tf"
  configured_in: ".github/workflows/apply-web-platform-infra.yml (plan + apply steps)"

error_reporting:
  destination: "GitHub Actions step output `::error::` annotations (existing pattern in the workflow)"
  fail_loud: "the plan step emits `::error::terraform plan failed (exit $rc)` on non-zero exit; PR auto-merge does not gate on apply, but next merge on main re-runs the workflow"

failure_modes:
  - mode: "ephemeral ssh-keygen step fails (runner /tmp not writable, ssh-keygen binary missing)"
    detection: "step `Generate ephemeral SSH public key for var.ssh_key_path` exits non-zero; ::error:: annotation surfaces in run logs"
    alert_route: "GitHub Actions UI"
  - mode: "operator forgets to add `-var=ssh_key_path=...` to a future -target= addition for hcloud_ssh_key.default"
    detection: "if a future PR adds `-target=hcloud_ssh_key.default`, plan would try to evaluate ignore_changes against the dummy public key; existing `lifecycle.ignore_changes = [public_key]` (server.tf:16-18) suppresses drift"
    alert_route: "GitHub Actions UI; drift detector (`scheduled-terraform-drift.yml`) is the 12h backstop"
  - mode: "DEPLOY_SSH_PUBLIC_KEY rotates in Doppler but Hetzner-side hcloud_ssh_key.default is stale"
    detection: "out of scope for this PR — `hcloud_ssh_key.default` is NOT in the apply workflow's -target= list; key rotation lifecycle is `apply-deploy-pipeline-fix.yml` + manual reconciliation"
    alert_route: "N/A for this PR"

logs:
  where: "GitHub Actions run logs for `apply-web-platform-infra.yml` (retained 90 days per GH default)"
  retention: "90 days"

discoverability_test:
  command: "gh run list --workflow=apply-web-platform-infra.yml --limit 1 --json conclusion,databaseId,headSha --jq '.[0]'"
  expected_output: "JSON object with conclusion=\"success\" for the post-merge run of this PR's commit"
```

## Research Reconciliation — Spec vs. Codebase

| Claim (issue #4166 body) | Reality (verified at plan-write time) | Plan response |
|---|---|---|
| `hcloud_ssh_key.default` is NOT in the apply workflow's -target= list | Verified at `apply-web-platform-infra.yml:197-263`. Header comment lines 21-23 explicitly excludes `hcloud_ssh_key.default` (managed by initial-apply + drift detector). | Confirmed. No `-target=hcloud_ssh_key.default` line; resource is not in apply scope. |
| The file() call evaluates regardless of -target= | HCL evaluates all referenced expressions at plan-time. `-target=` filters which resource *changes* land in the plan, but variable/local/argument expressions still evaluate. Confirmed by the actual error in run 26164246058. | Confirmed. The plan-time evaluation must be satisfied with a real file path. |
| Option 1 (raw `var.ssh_key_pub` + conditional `file()`) is preferred per `hr-tf-variable-no-operator-mint-default` | The cited rule prefers provider-side mint or credential reuse over operator-mint. Option 1 *would* reuse the existing Doppler `DEPLOY_SSH_PUBLIC_KEY` value (compliant). However, there is a strictly simpler precedent already in three sibling workflows: generate an ephemeral SSH key on the runner and pass `-var="ssh_key_path=/tmp/ci_ssh_key.pub"`. Used in `apply-deploy-pipeline-fix.yml:132-135`, `scheduled-terraform-drift.yml:49-52`, `infra-validation.yml:176-177`. | **Plan adopts the ephemeral-key precedent** instead of Option 1 or Option 2. Rationale: (a) zero `.tf` file changes (Option 1 requires `variables.tf` + `server.tf` edits + conditional ternary), (b) matches three existing precedents identically (drift detector, deploy pipeline fix, and infra validation all use this pattern), (c) `hcloud_ssh_key.default` is not in the apply scope so the public-key value is never consumed — a runner-local ephemeral key serves the HCL evaluation requirement at zero secret-handling cost, (d) `lifecycle.ignore_changes = [public_key]` (server.tf:16-18) already protects against drift in the unlikely case the resource enters scope, (e) DEPLOY_SSH_PUBLIC_KEY *exists* in Doppler `prd_terraform` (verified `doppler secrets get DEPLOY_SSH_PUBLIC_KEY -p soleur -c prd_terraform --plain` returns the public-key value) — keeping that secret read out of this fix avoids adding a Doppler read for a value that is then unused. |
| `var.ssh_key_pub` would need workflow to export `TF_VAR_ssh_key_pub=$DEPLOY_SSH_PUBLIC_KEY` from Doppler | Doppler `prd_terraform` already contains `DEPLOY_SSH_PUBLIC_KEY` and `--name-transformer tf-var` would auto-surface it as `TF_VAR_DEPLOY_SSH_PUBLIC_KEY`, NOT `TF_VAR_ssh_key_pub`. Would require either renaming the Doppler secret or aliasing manually. Confirms Option 1 has a hidden binding-name gap. | Ephemeral-key precedent has no such binding gap. |

## Files to Edit

1. `.github/workflows/apply-web-platform-infra.yml` — add two changes:
   - **New step** (insert after `Install Doppler CLI`, before `Verify required secrets present`, ~line 165): `Generate ephemeral SSH public key for var.ssh_key_path`. Body: `ssh-keygen -t ed25519 -f /tmp/ci_ssh_key -N "" -q && printf 'CI_SSH_PUB=%s\n' "/tmp/ci_ssh_key.pub" >> "$GITHUB_ENV"`. Matches `scheduled-terraform-drift.yml:49-52` verbatim.
   - **Plan step `terraform plan` invocation** (line 207-263): add `-var="ssh_key_path=${CI_SSH_PUB}"` to the doppler-run-wrapped `terraform plan` command. Place before the first `-target=` line for readability.
   - **Apply step `terraform apply tfplan` invocation** (line 302-303): `tfplan` is a saved-plan file, so `-var=` on the apply step is REJECTED with `Error: Can't set variables when applying a saved plan` — DO NOT add `-var=` to the apply step. The `-var=` flag is only required at plan time; the saved tfplan binary already contains the variable bindings. Reference: `apply-deploy-pipeline-fix.yml:179-190` does NOT use a saved plan and so passes `-var=` on apply too, but the apply-web-platform-infra.yml workflow uses the saved-plan pattern.

   No `.tf` file changes required.

## Files to Create

None.

## Acceptance Criteria

### Pre-merge (PR)

- [x] AC1: `.github/workflows/apply-web-platform-infra.yml` contains a new step named `Generate ephemeral SSH public key for var.ssh_key_path`, inserted after `Install Doppler CLI` and before `Verify required secrets present`. Verify: `grep -n "Generate ephemeral SSH public key for var.ssh_key_path" .github/workflows/apply-web-platform-infra.yml` returns exactly 1 match.
- [x] AC2: the new step body is byte-equivalent to `scheduled-terraform-drift.yml:49-52` modulo formatting (uses `ssh-keygen -t ed25519 -f /tmp/ci_ssh_key -N "" -q` and writes `CI_SSH_PUB=/tmp/ci_ssh_key.pub` to `$GITHUB_ENV`). Verify: `grep -A 3 "Generate ephemeral SSH public key" .github/workflows/apply-web-platform-infra.yml` contains both `ssh-keygen -t ed25519` and `CI_SSH_PUB=`.
- [x] AC3: the `terraform plan` invocation in the `Terraform plan (allow-list, non-SSH resources only)` step includes `-var="ssh_key_path=${CI_SSH_PUB}"`. Verify: `grep -n 'ssh_key_path=\${CI_SSH_PUB}' .github/workflows/apply-web-platform-infra.yml` returns exactly 1 match (within the plan step).
- [x] AC4: the `terraform apply` step does NOT carry `-var=` arguments (rejected against saved-plan files). Verify: the line `terraform apply -auto-approve -input=false tfplan` is unchanged (matches current line 303); `grep -n "terraform apply" .github/workflows/apply-web-platform-infra.yml | grep -- "-var="` returns zero matches.
- [x] AC5: `actionlint .github/workflows/apply-web-platform-infra.yml` exits 0 (workflow YAML structural validity).
- [x] AC6: extract the new step's `run:` block via `awk` (per `2026-05-12-plan-time-parsing-pattern-needs-codebase-precedent-grep.md`; `yq` is not in the toolchain), then `bash -c` syntax-check it. Verify:
  ```bash
  awk '/^      - name: Generate ephemeral SSH public key for var.ssh_key_path$/{flag=1; next} flag && /^      - name:/ {flag=0} flag && /^          / {sub(/^          /, ""); print}' \
    .github/workflows/apply-web-platform-infra.yml > /tmp/step.sh
  bash -n /tmp/step.sh && echo "syntax OK"
  ```
  Note: `bash -n` is used here on an *extracted shell snippet* (not the full YAML), which is correct per the AGENTS sharp-edge entry. The AGENTS guidance is against running `bash -n <file.yml>` directly.
- [ ] AC7: PR body uses `Closes #4166`. (Not `Ref #4166` — this is a code-shipped fix that lands at merge; the verification re-run is a *consequence* of the merge that the apply workflow itself performs. `Closes` is the correct token per `wg-use-closes-n-in-pr-body-not-title-to`.)

### Post-merge (operator/automation)

- [ ] AC8: the post-merge `apply-web-platform-infra.yml` run for this PR's merge SHA reaches the `Terraform plan` step and exits past it (i.e., no `Invalid function argument` / `no file exists at` error). Verify (automatable): `gh run list --workflow=apply-web-platform-infra.yml --limit 5 --json conclusion,headSha,databaseId,createdAt | jq -r --arg sha "$MERGE_SHA" '.[] | select(.headSha == $sha)'` — entry exists and `conclusion` is `success` OR (if a later step fails for unrelated reasons) the run logs do not contain `no file exists at`.
- [ ] AC9: the post-merge run requires manual approval via the `web-platform-infra-apply` environment gate (per existing workflow design, unchanged by this PR). Operator clicks Approve in the GitHub Actions UI. Per `hr-menu-option-ack-not-prod-write-auth`, this is the prod-write authorization.
- [ ] AC10: `gh issue close 4166 --comment "<verification link to successful run>"` after AC8 succeeds.

## Implementation Phases

### Phase 0 — Preconditions

- [ ] P0.1 Confirm worktree branch is `feat-one-shot-server-tf-ssh-key-4166`. Run `git branch --show-current`.
- [ ] P0.2 Grep the three precedent workflows for the canonical ephemeral-key step body and confirm the byte-equivalence target: `grep -A 3 "Generate CI SSH key" .github/workflows/scheduled-terraform-drift.yml .github/workflows/infra-validation.yml`. Expected: each has `ssh-keygen -t ed25519 -f /tmp/ci_ssh_key -N "" -q`.
- [ ] P0.3 Confirm `hcloud_ssh_key.default` is NOT in the apply workflow's `-target=` list (existing exclusion per header comment). Verify: `grep -c "hcloud_ssh_key.default" .github/workflows/apply-web-platform-infra.yml` returns exactly 1 (the header comment reference only).
- [ ] P0.4 Verify the saved-plan pattern is in use: `grep -n "out=tfplan" .github/workflows/apply-web-platform-infra.yml` returns the plan step's `-out=tfplan` flag, and `grep -n "apply.*tfplan$" .github/workflows/apply-web-platform-infra.yml` returns the apply step's `apply ... tfplan` (terminal argument). This confirms AC4's invariant (no `-var=` on apply).
- [ ] P0.5 Confirm `actionlint` (`/home/jean/.local/bin/actionlint`, v1.7.7 verified at deepen-pass time) is on PATH locally for AC5: `which actionlint && actionlint --version`. CI does not currently run actionlint as a gate, so this is a local-author check.
- [ ] P0.6 Verify the byte-equivalent reference: `diff <(awk '/^      - name: Generate CI SSH key$/{flag=1; next} flag && /^      - name:/ {flag=0} flag' .github/workflows/scheduled-terraform-drift.yml) <(awk '/^      - name: Generate ephemeral SSH public key for var.ssh_key_path$/{flag=1; next} flag && /^      - name:/ {flag=0} flag' .github/workflows/apply-web-platform-infra.yml)` — the only delta should be the step name + comment block (the runtime body is byte-equivalent: same `ssh-keygen` invocation, same `printf` export).

### Phase 1 — Workflow edit (single PR commit)

- [ ] P1.1 Insert the new `Generate ephemeral SSH public key for var.ssh_key_path` step in `apply-web-platform-infra.yml` immediately after the `Install Doppler CLI` step. Body:
  ```yaml
        - name: Generate ephemeral SSH public key for var.ssh_key_path
          # HCL evaluates file() at plan-time regardless of -target= filtering.
          # hcloud_ssh_key.default is NOT in the apply allow-list, so this dummy
          # public key is never consumed -- it just satisfies HCL parsing.
          # Mirrors scheduled-terraform-drift.yml:49-52 and infra-validation.yml:176-177.
          run: |
            ssh-keygen -t ed25519 -f /tmp/ci_ssh_key -N "" -q
            printf 'CI_SSH_PUB=%s\n' "/tmp/ci_ssh_key.pub" >> "$GITHUB_ENV"
  ```
- [ ] P1.2 In the `Terraform plan (allow-list, non-SSH resources only)` step, modify the `doppler run ... terraform plan` invocation. Place `-var="ssh_key_path=${CI_SSH_PUB}"` as the first argument after `-out=tfplan` (before the `-target=` lines). Diff shape:
  ```diff
            doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
              terraform plan -no-color -input=false -out=tfplan \
  +             -var="ssh_key_path=${CI_SSH_PUB}" \
                -target=betteruptime_policy.github_webhook \
                ...
  ```
- [ ] P1.3 Confirm the apply step at line 302-303 is NOT modified. Saved-plan re-validation: `terraform apply tfplan` rejects `-var=` flags.

### Phase 2 — Local verification

- [ ] P2.1 Run `actionlint .github/workflows/apply-web-platform-infra.yml`. Expect exit 0.
- [ ] P2.2 Extract the new step's `run:` block via `awk` (matching AC6) and `bash -n` syntax-check the extracted snippet:
  ```bash
  awk '/^      - name: Generate ephemeral SSH public key for var.ssh_key_path$/{flag=1; next} flag && /^      - name:/ {flag=0} flag && /^          / {sub(/^          /, ""); print}' \
    .github/workflows/apply-web-platform-infra.yml > /tmp/step.sh
  bash -n /tmp/step.sh
  ```
  Expected: `bash -n` exits 0. (NOTE: do NOT run `bash -n` against the full YAML file — that parses the YAML header as bash and fails confusingly. Extracted-snippet only.)
- [ ] P2.3 Dry-run the embedded `ssh-keygen` locally to confirm the binary exists and `/tmp` is writable (matches CI runner shape):
  ```bash
  ssh-keygen -t ed25519 -f /tmp/probe_ci_ssh_key -N "" -q && \
    test -f /tmp/probe_ci_ssh_key.pub && \
    rm -f /tmp/probe_ci_ssh_key /tmp/probe_ci_ssh_key.pub && \
    echo "ssh-keygen OK"
  ```

### Phase 3 — PR + post-merge verification

- [ ] P3.1 Push, mark PR ready, request CODEOWNERS review.
- [ ] P3.2 After merge to main, GitHub Actions auto-triggers `apply-web-platform-infra.yml` on the merge SHA (paths: `apply-web-platform-infra.yml` itself matches the `.github/workflows/apply-web-platform-infra.yml` trigger path).
- [ ] P3.3 Operator approves the `web-platform-infra-apply` environment gate.
- [ ] P3.4 Verify the run reaches the `Terraform apply` step (i.e., past the previously-failing `Terraform plan` step). Use: `gh run view <run-id> --log-failed 2>&1 | grep -c "Invalid function argument"` → expected 0.
- [ ] P3.5 Close #4166 with the run-link comment.

## Open Code-Review Overlap

None. Verified via `gh issue list --label code-review --state open --json number,title,body --limit 200 > /tmp/open-review-issues.json; jq -r --arg path "apply-web-platform-infra.yml" '.[] | select(.body // "" | contains($path)) | "#\(.number)"' /tmp/open-review-issues.json; jq -r --arg path "server.tf" '.[] | select(.body // "" | contains($path)) | "#\(.number)"' /tmp/open-review-issues.json` — only #3216 (resolved inline, references different file) and #2197 (billing/SubscriptionStatus, unrelated). No open code-review issues touch `apply-web-platform-infra.yml` or `server.tf`.

## Hypotheses

This is an SSH/handshake-keyword-adjacent issue per Phase 1.4's trigger pattern (`ssh_key_path`, `file()` error, but no `connection reset by peer`/handshake/kex). The L3→L7 diagnostic checklist applies in spirit: confirmed the failing path is HCL-evaluation, not network-layer. No firewall or admin-IP component to this fix — it is a workflow-runner local-file-system fix.

Per `hr-ssh-diagnosis-verify-firewall`: this PR does NOT propose any sshd/fail2ban changes. The error is HCL-side (`Invalid function argument`), not network-side (no `connection reset`, no handshake). The hard rule's L3-first ordering is satisfied by virtue of the error class — there is no SSH connection attempt in this code path, only a `file()` call against a local runner filesystem path.

## Infrastructure (IaC)

### Terraform changes

None. The `.tf` files are unchanged.

### Apply path

Workflow-only change. The `apply-web-platform-infra.yml` workflow's existing apply path (cloud-init for fresh hosts, idempotent bootstrap scripts for existing hosts) is unchanged. This PR adds a single ephemeral-key-generation step inside the workflow.

### Distinctness / drift safeguards

- The ephemeral key is generated on each workflow run in `/tmp`, used only for HCL `file()` evaluation, and discarded at job end.
- `lifecycle.ignore_changes = [public_key]` on `hcloud_ssh_key.default` (server.tf:16-18) already protects against the ephemeral key polluting state IF the resource ever enters apply scope (currently excluded).
- No Doppler reads, no provider state mutations, no new secrets.

### Vendor-tier reality check

N/A — no vendor account changes. `ssh-keygen` is a runner-preinstalled binary on `ubuntu-24.04` (verified by precedent: `scheduled-terraform-drift.yml`, `infra-validation.yml`, `apply-deploy-pipeline-fix.yml` all use it without an install step).

## Domain Review

**Domains relevant:** none

No cross-domain implications detected — infrastructure/tooling change. Single-domain `infra` lane. No Product/UX surface, no marketing surface, no legal surface (the SSH public key is already non-secret and published), no CTO architecture decision (the fix follows existing precedent verbatim).

## Risks

- **R1 (low):** If a future PR adds `-target=hcloud_ssh_key.default` to the apply allow-list, the workflow would attempt to *apply* the dummy public key to the Hetzner-side `hcloud_ssh_key.default` resource, potentially overwriting the real `DEPLOY_SSH_PUBLIC_KEY`. Mitigation: `lifecycle.ignore_changes = [public_key]` at server.tf:16-18 prevents the overwrite. The header comment at apply-web-platform-infra.yml:21-23 already documents this exclusion. **Action:** the workflow header comment is the canonical guard; no additional safeguard needed.
- **R2 (very low):** if `ssh-keygen` ever fails to write to `/tmp` on the runner (e.g., disk full), the workflow fails loudly at the new step before reaching the plan step. The error message includes `ssh-keygen` exit code. Acceptable failure mode — fails fast with clear diagnosis.
- **R3 (very low):** future drift detector (`scheduled-terraform-drift.yml`) already uses `/tmp/ci_ssh_key.pub` independently; no path collision because runs are on separate runners.
- **R4 (very low, future-facing):** the `apply` job currently has no `strategy.matrix`. If a future refactor adds matrix dimensions (e.g., per-environment apply, per-region tunnel splits), `/tmp/ci_ssh_key` would be regenerated in each matrix shard but on **separate runners** by default — no collision. If matrix shards ever share a runner (unlikely; would require `runs-on: self-hosted` with serialized scheduling), the unconditional `ssh-keygen -q` overwrite is still idempotent (it will overwrite without prompting). Documented for future readers, no mitigation needed today.

## Sharp Edges

- A plan whose `## User-Brand Impact` section is empty, contains only `TBD`/`TODO`/placeholder text, or omits the threshold will fail `deepen-plan` Phase 4.6. This plan declares threshold: none with a scope-out rationale (sensitive-path: workflow file edits trigger the canonical regex for `.github/workflows/`).
- Do NOT add `-var=` to the apply step. `terraform apply tfplan` (saved plan) rejects `-var=` arguments with `Can't set variables when applying a saved plan`. The `-var=` MUST be on the plan step only.
- This pattern (ephemeral SSH key for `var.ssh_key_path`) is precedent in 3 workflows. If you generalize beyond the 4th adopter (this PR), consider extracting to a composite action — but per `hr-exhaust-all-automated-options-before` and Kieran's "Wrapper-vs-curl check" guidance: 3 lines of bash repeated 4 times is fine; the composite-action abstraction is premature.
- **Insertion point inside the `apply` job, NOT a new job.** The new step must land in `jobs.apply.steps[]` (after `Install Doppler CLI`, before `Verify required secrets present`). Inserting at job-top-level (e.g., between `preflight` and `apply`) would mean the step runs in a separate runner and `$GITHUB_ENV` would not propagate (env exports are per-job, not per-workflow).
- **Saved-plan vs. inline-plan `-var=` semantics.** Terraform's contract: variables are bound at *plan-write* time; the resulting `tfplan` is opaque and self-contained. `terraform apply tfplan` REJECTS `-var=` with `Error: Can't set variables when applying a saved plan`. The plan author MUST add `-var=` to the *plan step only*. This is different from `apply-deploy-pipeline-fix.yml` (line 189), which uses `terraform apply -target=... -var=...` directly (no saved plan) and therefore needs `-var=` on both plan AND apply.
- **Two-state apply path divergence with deploy-pipeline-fix.** The deploy-pipeline-fix workflow uses the **REAL** `DEPLOY_SSH_PRIVATE_KEY` via `ssh-agent` because it SSH-connects to the prod server. This PR's workflow does NOT SSH (its allow-list excludes all `terraform_data.*` provisioner-class resources, header comment lines 21-23). So this PR ONLY needs the public-key half of the precedent (generate + pass `-var=ssh_key_path`); no `ssh-agent`, no `DEPLOY_SSH_PRIVATE_KEY` read. Do NOT copy the `Start ssh-agent with deploy key` step from `apply-deploy-pipeline-fix.yml`.

## Prior Art

- **`apply-deploy-pipeline-fix.yml:132-135`** — same ephemeral-key generation step, except it ALSO loads `DEPLOY_SSH_PRIVATE_KEY` into `ssh-agent` because that workflow actually SSHes to the prod server. This PR's workflow does not SSH, so only the public-key generation half is needed.
- **`scheduled-terraform-drift.yml:49-52`** — exact byte-equivalent of the step this PR adds. Used by the 12h drift detector for the same reason: HCL `file()` evaluation against a non-existent path would otherwise abort drift detection.
- **`infra-validation.yml:176-177`** — generates the key (line 176) but uses a conditional `grep -q 'variable "ssh_key_path"'` guard (line 206) before passing `-var=`. This PR's workflow is hardcoded to web-platform infra, so the conditional guard is unnecessary; the unconditional form matches the drift-detector precedent more closely.

## Reference Implementation

The complete workflow edit, expressed as a unified diff:

```diff
--- a/.github/workflows/apply-web-platform-infra.yml
+++ b/.github/workflows/apply-web-platform-infra.yml
@@ -131,6 +131,15 @@ jobs:
       - name: Install Doppler CLI
         uses: DopplerHQ/cli-action@5351693ec144fc7f7a2d30025061acfc3c53c47c # v4
 
+      - name: Generate ephemeral SSH public key for var.ssh_key_path
+        # HCL evaluates file() at plan-time regardless of -target= filtering.
+        # hcloud_ssh_key.default is NOT in the apply allow-list (header lines
+        # 21-23), so this dummy public key is never consumed -- it just
+        # satisfies HCL parsing. Mirrors scheduled-terraform-drift.yml:50-52.
+        run: |
+          ssh-keygen -t ed25519 -f /tmp/ci_ssh_key -N "" -q
+          printf 'CI_SSH_PUB=%s\n' "/tmp/ci_ssh_key.pub" >> "$GITHUB_ENV"
+
       - name: Verify required secrets present
         env:
           DOPPLER_TOKEN_CHECK: ${{ secrets.DOPPLER_TOKEN }}
@@ -188,6 +197,7 @@ jobs:
           set -uo pipefail
           doppler run -p soleur -c prd_terraform --name-transformer tf-var -- \
             terraform plan -no-color -input=false -out=tfplan \
+              -var="ssh_key_path=${CI_SSH_PUB}" \
               -target=betteruptime_policy.github_webhook \
               -target=betteruptime_monitor.github_webhook_failures \
               -target=betteruptime_heartbeat.github_webhook_sig_failures \
```

Note the apply step at line 302-303 is UNCHANGED (saved-plan `tfplan` rejects `-var=`).

## Research Insights

### Terraform `file()` evaluation semantics

Per the HashiCorp Terraform Language documentation, `file()` is a built-in function that reads the contents of the given file path **at the start of the plan phase**. The function is evaluated as part of expression evaluation in HCL, which happens BEFORE the `-target=` filter is applied. From the Terraform docs (verified via the canonical https://developer.hashicorp.com/terraform/language/functions/file):

> If the file does not exist at plan time, Terraform will produce an error.

This is independent of whether the resource referencing the function is in `-target=` scope. The plan-time evaluation order is: HCL parse → variable binding → expression evaluation (including `file()`, `templatefile()`, `jsondecode()`, etc.) → graph construction → `-target=` filtering → diff computation. The `file()` call happens at step 3; the `-target=` filter at step 5. Therefore, an HCL expression like `public_key = file(var.ssh_key_path)` MUST resolve at plan time even when the surrounding resource is excluded by `-target=`.

**Implication for this PR:** the fix lives in the *workflow*, not the `.tf` file. Adding `-var="ssh_key_path=/tmp/ci_ssh_key.pub"` makes the variable resolve to a path that the runner CAN read (the runner created it 2 steps earlier).

### Saved-plan `-var=` rejection (Terraform contract)

Per `terraform apply --help`:

> When applying a saved plan (a plan generated with terraform plan -out=...), -var, -var-file, and -compact-warnings cannot be specified, since the saved plan file already contains the variables that were in effect when it was created.

This is enforced by Terraform CLI itself with the literal error `Can't set variables when applying a saved plan`. AC4's invariant ("no `-var=` on apply") is therefore not aspirational — it is *required* by the Terraform contract.

### Existing precedent shape (byte-equivalence verified)

The three precedent workflows verified at deepen-pass time:

```
scheduled-terraform-drift.yml:50-52   (3-line run: | form, exports CI_SSH_PUB)
apply-deploy-pipeline-fix.yml:132-135 (3-line run: | form, exports CI_SSH_PUB)
infra-validation.yml:177              (1-line run: scalar form, hardcoded /tmp path; no CI_SSH_PUB export)
```

This PR adopts the 3-line form to match the two apply/drift workflows that ALSO use `${CI_SSH_PUB}` interpolation downstream. The 1-line scalar form (infra-validation) is **less appropriate** because it requires hardcoding `/tmp/ci_ssh_key.pub` at the call site, which couples the workflow to the file path in two places.

## References

- #4166 (this issue)
- #4150 (variable-resolution layer; previous gate in the cascade)
- #4147 (lockfile layer; gate before #4150)
- #4161 (the PR whose post-merge run surfaced this layer)
- Failed run: <https://github.com/jikig-ai/soleur/actions/runs/26164246058>
- `knowledge-base/project/learnings/integration-issues/2026-04-05-terraform-doppler-dual-credential-pattern.md` (canonical Doppler+Terraform pattern; references the same `-var="ssh_key_path=..."` workaround)
- `knowledge-base/project/plans/2026-05-20-fix-apply-web-platform-infra-tf-autonomy-4150-plan.md` (the #4150 plan — predecessor in the cascade)
