# SRE Agent for Terraform IaC

**Date:** 2026-02-13
**Status:** Decided
**Issue:** #39
**Branch:** feat-sre-agent

## What We're Building

A single SRE agent (`agents/operations/sre-agent.md`) that generates and reviews Terraform configurations. Supports Hetzner and AWS in v1. Covers compute, networking, storage, and state management. Does NOT cover observability, monitoring, or operational runbooks -- those are separate concerns.

## Why This Approach

**Single agent over split agents:** Claude already has deep Terraform/Hetzner/AWS knowledge. The agent prompt sets framing and conventions, not teaching from scratch. One file is easier to iterate. Split by function (generator vs reviewer) or by provider would introduce duplication without clear benefit at this stage.

**Hetzner + AWS over Hetzner-only:** Both are likely providers. AWS adds breadth without significant prompt complexity since Terraform patterns are largely shared across providers.

**Infra only over infra + observability:** Keeps the agent focused. Observability is a distinct domain with different tools and patterns. Can be added as a separate agent later if needed.

## Context Shift from Original Issue

Original issue #39 was deferred from #28 (Cloud Deploy) as premature -- "build after running the bridge on Hetzner for a few weeks." The motivation has shifted: this is now a general-purpose IaC helper, decoupled from the bridge project. It's useful for any project that needs Terraform configs, not just the Telegram bridge.

## Key Decisions

1. **Single agent** at `agents/operations/sre-agent.md` -- handles both generation and review
2. **Hetzner + AWS** providers in v1, with interface designed for adding more later
3. **Infrastructure provisioning only** -- compute, network, storage, state management
4. **No observability** -- monitoring/alerting is a separate concern for a future agent
5. **State management included** -- backend config, workspace strategy, state imports
6. **Cost optimization** -- recommend cheapest viable configs when generating

## What the Agent Should Do

### Generation
- Scaffold Terraform configs from natural language descriptions
- Understand server types, firewall rules, SSH keys, volumes, cloud-init (Hetzner)
- Understand EC2, VPC, security groups, IAM roles, S3 (AWS)
- Recommend cheapest viable configuration
- Generate proper module structure with variables and outputs

### Review
- Audit existing .tf files for security issues
- Check for cost optimization opportunities
- Validate best practices (naming, tagging, module structure)
- Detect infrastructure drift patterns
- Review state backend configuration

### State Management
- Advise on backend configuration (S3, Consul, HCP)
- Workspace strategy recommendations
- State import guidance for existing resources

## Open Questions

- Should the agent have access to `terraform plan` output for review? (Requires Bash tool access)
- How deep should cost estimation go? Ballpark or detailed pricing?
- Should it generate `.tfvars` example files alongside configs?

## What We're NOT Building

- Observability/monitoring agent (separate concern)
- Operational runbook automation
- CI/CD pipeline generation for Terraform
- Multi-cloud abstraction layer (Pulumi, CDK)
- Drift detection automation (requires running `terraform plan`)
