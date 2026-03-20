# SRE Agent for Terraform IaC

**Issue:** #39
**Branch:** feat-sre-agent
**Status:** Draft

## Problem Statement

Projects need Terraform configurations for infrastructure provisioning, but writing HCL from scratch is tedious and reviewing existing configs for security/cost issues requires deep provider knowledge. A specialized agent can generate and review Terraform configs with best practices baked in.

## Goals

- G1: Generate Terraform configurations from natural language descriptions
- G2: Review existing .tf files for security, cost, and best practice issues
- G3: Support Hetzner and AWS providers in v1
- G4: Advise on state management (backends, workspaces, imports)
- G5: Recommend cheapest viable configurations

## Non-Goals

- Observability/monitoring setup (separate agent concern)
- Operational runbooks or incident response
- CI/CD pipeline generation for Terraform
- Multi-cloud abstraction layers (Pulumi, CDK, Crossplane)
- Automated drift detection (requires running `terraform plan`)

## Functional Requirements

- FR1: Agent generates valid HCL for Hetzner resources (servers, firewalls, SSH keys, volumes, cloud-init)
- FR2: Agent generates valid HCL for AWS resources (EC2, VPC, security groups, IAM, S3)
- FR3: Agent reviews existing .tf files and reports issues with severity levels
- FR4: Agent recommends cost-optimized resource configurations
- FR5: Agent advises on Terraform state backend configuration
- FR6: Agent follows Terraform module structure conventions (variables, outputs, modules)

## Technical Requirements

- TR1: Single agent file at `plugins/soleur/agents/operations/sre-agent.md`
- TR2: YAML frontmatter with examples per agent conventions
- TR3: New agent category directory: `plugins/soleur/agents/operations/`
- TR4: Version bump: MINOR (new agent)
- TR5: Update versioning triad: plugin.json, CHANGELOG.md, README.md

## Acceptance Criteria

- AC1: Agent generates a working Hetzner server config when asked
- AC2: Agent generates a working AWS EC2 config when asked
- AC3: Agent identifies at least 3 categories of issues when reviewing .tf files (security, cost, best practices)
- AC4: Agent includes state backend recommendations in generated configs
- AC5: Agent file has valid YAML frontmatter with example blocks
