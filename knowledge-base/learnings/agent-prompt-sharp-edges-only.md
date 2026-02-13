---
title: "Agent prompts: embed sharp edges only"
category: agent-design
tags: [agents, prompt-design, plan-review, simplicity]
module: plugins/soleur/agents
symptom: "Agent plan or prompt is longer than the deliverable it describes"
root_cause: "Including knowledge Claude already has from training data"
---

# Agent Prompts: Embed Sharp Edges Only

## Problem

Initial terraform-architect plan was 257 lines for an agent that ended up being ~80 lines. Three independent reviewers (DHH, Kieran, Simplicity) converged on the same feedback: the plan contained general Terraform knowledge that Claude already knows from training data.

## Solution

Only embed "sharp edges" -- non-obvious, provider-specific gotchas that Claude would get wrong without explicit instruction:

- Hetzner Object Storage backend requires 6 skip flags (`skip_credentials_validation`, `skip_metadata_api_check`, etc.)
- Hetzner servers must always have `hcloud_firewall` + `hcloud_firewall_attachment` (no naked servers)
- S3 native locking replaces DynamoDB locking in Terraform 1.10+ (recent change)
- Hetzner CAX (ARM) instances are cheapest but need ARM64 compatibility note

Everything else (VPC structure, encryption, tagging, variable design) Claude handles correctly without prompting.

## Key Insight

**Agent prompts should contain only what the model would get wrong without them.** General best practices, standard patterns, and well-documented conventions are already in training data. The prompt's job is to correct for blind spots, not to be a reference manual.

**Heuristic:** If you can find it in the first page of the official docs, don't put it in the agent prompt. If it requires combining multiple sources or knowing provider-specific quirks, include it.

## Outcome

Plan: 257 lines -> 55 lines (78% reduction)
Agent: ~80 lines of focused, high-value instructions
