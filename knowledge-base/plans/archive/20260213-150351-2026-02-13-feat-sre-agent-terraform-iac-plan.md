---
title: "feat: Terraform architect agent"
type: feat
date: 2026-02-13
---

# Terraform Architect Agent

Single agent that generates and reviews Terraform configurations for Hetzner and AWS. Advises on state management and recommends cost-optimized setups.

## File

`plugins/soleur/agents/engineering/infra/terraform-architect.md`

Name: `soleur:engineering:infra:terraform-architect`

## Acceptance Criteria

- [x] Agent file at correct path with valid YAML frontmatter (name, description with 3 `<example>` blocks, `model: inherit`)
- [x] Agent prompt follows existing patterns (ddd-architect, security-sentinel): persona, protocol sections, output format
- [x] Version bump: MINOR from current version across plugin.json, CHANGELOG.md, README.md
- [x] README.md agent count and table updated
- [x] Root README.md version badge updated
- [x] `.github/ISSUE_TEMPLATE/bug_report.yml` version placeholder updated
- [x] `plugins/soleur/AGENTS.md` directory structure updated to show new `engineering/infra/` subdirectory

## Non-Goals

- Observability/monitoring setup
- CI/CD pipeline generation for Terraform
- Automated drift detection (requires `terraform plan`)
- Running terraform commands (generates/reviews HCL only)

## Agent Prompt: Sharp Edges Only

These are the non-obvious instructions worth embedding. Everything else Claude already knows from training data.

**Hetzner-specific:**
- Always attach `hcloud_firewall` + `hcloud_firewall_attachment` to servers (never naked servers)
- Hetzner Object Storage backend requires `skip_credentials_validation`, `skip_metadata_api_check`, `skip_region_validation`, `skip_requesting_account_id`, `use_path_style`, `skip_s3_checksum` flags
- Prefer CAX (ARM) instances for cost optimization; note ARM compatibility requirement

**AWS-specific:**
- Never use default VPC -- always create explicit VPC with public/private subnets
- Always include `aws_s3_bucket_public_access_block` on every S3 bucket

**Cross-provider:**
- S3 native locking for Terraform 1.10+ (DynamoDB locking deprecated)
- Generate modular file structure by default: main.tf, variables.tf, outputs.tf, versions.tf
- Review output format: findings grouped by severity (Critical/High/Medium/Low) with file references and remediation HCL
- Always disclaim pricing: "Prices reflect model training data. Verify current pricing at the provider's pricing page."
- IaC-specific security checks only. Refer to security-sentinel for application-level security.

## References

- Brainstorm: `knowledge-base/brainstorms/2026-02-13-sre-agent-brainstorm.md`
- Spec: `knowledge-base/specs/feat-sre-agent/spec.md`
- Issue: #39
- Pattern: `plugins/soleur/agents/engineering/design/ddd-architect.md`
- Pattern: `plugins/soleur/agents/engineering/review/security-sentinel.md`
