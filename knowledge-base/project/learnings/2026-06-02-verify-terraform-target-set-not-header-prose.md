# Learning: Verify which CI workflow applies a Terraform resource by reading the `-target=` set, not header prose

## Problem

During the #4844 brainstorm, the `apply-web-platform-infra.yml` header comment claimed the 7
SSH-provisioned `terraform_data.*` resources "land via `apply-deploy-pipeline-fix.yml`". Taken at
face value this would have inverted the issue's premise (the resources would NOT be drifting). The
issue body separately claimed both `apparmor_bwrap_profile` AND `docker_seccomp_config` are pulled
into the CI graph via `deploy_pipeline_fix`'s `depends_on`.

Both claims were wrong:
- `apply-deploy-pipeline-fix.yml` only `-target`s `deploy_pipeline_fix` +
  `infra_config_handler_bootstrap`. The 7 siblings are genuinely excluded and drift.
- Only `apparmor_bwrap_profile` has a `depends_on` edge (`server.tf:502`). `docker_seccomp_config`
  appears only in prose comments — no edge anywhere.

## Solution

When validating which CI workflow applies a given Terraform resource (or which resources are
coupled), grep the **actual machine-readable truth**, never the narrative:
- For "which workflow applies resource X": `grep -nE '\-target=' .github/workflows/*.yml` and read
  the literal target addresses — header comments drift from the target set they describe.
- For `depends_on` coupling: `grep -nE 'depends_on' apps/web-platform/infra/*.tf` and read the
  actual edges, not issue-body coupling claims.

## Key Insight

Header comments and issue bodies are point-in-time prose that drift from the `-target=` enumerations
and `depends_on` edges they describe. The `-target=` set is the load-bearing truth for "what CI
applies"; the resource graph is the load-bearing truth for "what's coupled". A 30-second grep of the
machine-readable side beats trusting either.

**Corollary — the `-target=` allowlists are an unguarded drift surface.** Across the 3 Terraform
apply workflows, a resource added to `server.tf` but NOT appended to a workflow's `-target=` list is
planned-but-never-applied — a silent no-op on merge that `validate` and local `plan` give zero hint
about. This is an instance of the
`2026-05-22-ci-parity-test-docs-arrays-are-themselves-a-drift-surface.md` class: the hand-edited
allowlist is itself a drift surface. The #4844 plan adds a self-healing parity-guard test (modeled
on `ship-deploy-pipeline-fix-gate.test.ts`) that derives the expected set from the `.tf` resource
declarations and asserts set-equality with the workflow `-target=` list.

## Session Errors

None detected (clean brainstorm session). The two items above are codebase premise-corrections
surfaced and documented during the brainstorm, not session-process errors.

## Tags
category: integration-issues
module: ci-infra-terraform
issue: 4844
related: 2026-05-22-ci-parity-test-docs-arrays-are-themselves-a-drift-surface.md, 2026-05-29-targeted-apply-workflow-needs-new-resource-in-target-list.md, 2026-06-02-reintroduce-removed-ci-mechanism-from-git-history.md
