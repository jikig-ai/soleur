# Terraform `-var=` injection: pick the precedent whose SHAPE matches your workflow

## Problem

PR #4166 needed to unblock `apply-web-platform-infra.yml` at `server.tf:12 file(var.ssh_key_path)`. Three sibling workflows already implement an ephemeral-SSH-key + `-var=ssh_key_path=...` pattern, but they are NOT interchangeable templates — they differ along two orthogonal axes that matter at integration time:

| Workflow | Root scope | Apply pattern |
|---|---|---|
| `scheduled-terraform-drift.yml` | multi-root (iterates over many TF roots) | `terraform plan` only (drift detection) |
| `infra-validation.yml` | multi-root | `terraform plan -detailed-exitcode` only |
| `apply-deploy-pipeline-fix.yml` | single-root | inline `apply -target -var=...` (NO saved plan) |
| `apply-web-platform-infra.yml` (this PR) | single-root | **saved-plan** apply (`plan -out=tfplan` → `apply tfplan`) |

Each axis dictates a different `-var=` placement:

- **Multi-root** workflows wrap the `-var=` injection in `if grep -q 'variable "ssh_key_path"' variables.tf` (because not all roots declare the variable). Single-root workflows inject unconditionally.
- **Inline-plan** workflows pass `-var=` to BOTH `plan` and `apply`. **Saved-plan** workflows pass `-var=` to `plan` ONLY — `terraform apply <plan-file>` rejects `-var=` with `Can't set variables when applying a saved plan`.

A naive "mirror the precedent" reading picks the wrong one along one axis and breaks. The git-history-analyzer surfaced exactly this risk at review time ("byte-equivalent" framing overstates similarity because the conditional guard is missing).

## Solution

Before mirroring a precedent, classify the target workflow on both axes:

1. `grep -c "for .* in" <workflow>.yml` — multi-root if the apply step iterates; single-root if it doesn't.
2. `grep -n "out=tfplan\|-out=" <workflow>.yml` — saved-plan if present; inline-plan otherwise.

Then pick the precedent that matches on BOTH axes. For PR #4166 the closest match was `apply-deploy-pipeline-fix.yml` (single-root, but inline-plan) — and even that required adapting the `-var=` placement from "both steps" to "plan step only" because of the saved-plan difference.

When NO precedent matches both axes exactly, the comment in the new workflow MUST state which axis differs from the cited precedent. The PR landed:

```
# Mirrors scheduled-terraform-drift.yml:49-52.
```

This is accurate for the ephemeral-keygen STEP BODY (which is axis-independent), but a future reader extending the `-var=` injection logic must know NOT to copy the conditional guard from the same precedent.

## Key Insight

The 3 sibling workflows share the keygen step body byte-for-byte, but diverge on `-var=` placement and conditional-guard presence. Treat "Mirrors X" annotations as scoped to the specific block being mirrored (here: the `run:` body of the keygen step), not as a blanket claim that the new workflow follows X's overall pattern.

For saved-plan workflows specifically: the Terraform CLI's `-var=` rejection is a hard contract, not a stylistic preference. AC4 in the PR plan ("apply step carries no `-var=`") is enforced by the toolchain itself; the workflow author cannot violate it accidentally.

## Tags
category: best-practices
module: infra/terraform/ci-workflows
