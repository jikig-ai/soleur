---
title: "Awk pipe-delimited markdown table column offset and TF backend collision"
date: 2026-05-26
category: integration-issues
module: plugins/soleur/skills/provision-*
issues: [3769, 3770, 3771, 3772]
pr: 4501
severity: critical
tags: [awk, markdown-table, terraform, multi-agent-review]
---

# Learning: Awk pipe-delimited markdown table column offset

## Problem

Four provisioning scripts parsed a markdown table (`tenant-dpa-register.md`) using `awk -F'|'` and checked `$7` for the Status column. The DPA gate appeared to work during initial testing (no rows existed to match), but was checking the Sub-processors column ($7) instead of Status ($8).

The root cause: markdown tables start with a leading `|`, making `$1` empty. Visual column 7 (Status) maps to awk field `$8`.

Additionally, the slug match used awk's `~` regex operator (`$2 ~ slug`), which performs substring matching — `acme` would match `acme-prd-ext`. Combined with the wrong column, the DPA compliance gate was functionally non-operational.

A second critical issue: all 3 TF-generating skills wrote separate `.tf` files with duplicate `terraform { backend "s3" { ... } }` blocks into the same directory. Terraform requires exactly one backend block per root — the second `terraform init` would fail.

## Solution

1. Changed `$7` to `$8` and anchored the status regex: `$8 ~ /^ *(dpa-signed|provisioning-in-progress) *$/`
2. Changed slug match from substring (`$2 ~ slug`) to exact with whitespace trim: `gsub(/^ +| +$/, "", $2); $2 == slug`
3. Split TF output into per-provider subdirectories: `provisioning/<slug>/doppler/`, `cloudflare/`, `github/` with distinct state keys

## Key Insight

When parsing pipe-delimited markdown tables with `awk -F'|'`, always verify column indices empirically — the leading `|` shifts all fields by +1. Test with `echo '<row>' | awk -F'|' '{ for(i=1;i<=NF;i++) printf "$%d=[%s]\n", i, $i }'` before coding the gate.

Multi-agent review caught all 3 critical issues (DPA column, DPA substring, TF collision) independently across 6 of 9 agents. The 5-agent plan review panel did not catch them because the plan specified `$7` and the reviewers validated the plan's logic without empirically testing the column offset.

## Session Errors

1. **Plan-quoted description budget stale** — Plan said 1894 baseline, actual was 1866. No impact (budget passed at 1950/1950). **Prevention:** /work Phase 1 already requires re-measuring plan-quoted numbers; this instance was caught by the existing gate.
2. **CF DPA gate test used invalid hex** — Test input `aaaabbbbccccddddeeeeffffgggghhhh` contains `g`/`h` which aren't hex. Format validation correctly rejected before reaching DPA gate. **Prevention:** Use `$(printf '%032x' 0)` or known-good test fixtures for hex ID validation testing.

## Tags

category: integration-issues
module: plugins/soleur/skills/provision-*
