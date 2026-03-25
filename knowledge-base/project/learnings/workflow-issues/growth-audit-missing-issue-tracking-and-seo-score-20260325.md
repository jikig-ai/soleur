---
module: System
date: 2026-03-25
problem_type: workflow_issue
component: tooling
symptoms:
  - "Growth audit issue #1111 listed 5 findings under 'Open Issues Without GitHub Tracking' but no issues were created"
  - "SEO audit report produced qualitative findings (Critical/Warnings/Pass) but no numerical score, while AEO audit had a weighted 0-100 score"
root_cause: missing_workflow_step
resolution_type: workflow_improvement
severity: medium
tags: [growth-audit, seo-score, aeo-score, github-issues, scheduled-workflow, marketing-pipeline]
---

# Troubleshooting: Growth Audit Workflow Missing Issue Tracking and SEO Score

## Problem

The scheduled growth audit workflow generated comprehensive reports but had two gaps: (1) findings were listed in the summary issue without creating individual GitHub tracking issues, and (2) the SEO audit lacked a numerical score while the AEO audit had one, making it impossible to track SEO health over time.

## Environment

- Module: System (scheduled-growth-audit workflow + seo-aeo-analyst agent)
- Affected Component: `.github/workflows/scheduled-growth-audit.yml`, `plugins/soleur/agents/marketing/seo-aeo-analyst.md`
- Date: 2026-03-25

## Symptoms

- Growth audit issue #1111 listed 5 items under "Open Issues Without GitHub Tracking" — the workflow identified the gap but did not close it
- The issue displayed "AEO Score: 74/100" but had no corresponding SEO score section
- No way to track SEO health trend week-over-week (AEO: 68 → 74 trackable, SEO: no data)

## What Didn't Work

**Direct solution:** The problems were identified on first inspection — no failed attempts.

## Solution

### 1. Created tracking issues for untracked findings

Created 4 new GitHub issues (#1121-#1124) for findings without tracking. Referenced existing #1051 for the "plugin in meta descriptions" finding which was already covered. Updated #1111 body to replace the "Open Issues Without GitHub Tracking" section with a "Tracking Issues" table linking all 5 items.

### 2. Added SEO scoring rubric to seo-aeo-analyst agent

Added a weighted scoring table to the agent's Step 3 (Report) section, mirroring the AEO scoring approach:

| Category | Weight |
|----------|--------|
| Meta Tags | 20% |
| Structured Data | 15% |
| AI Discoverability | 15% |
| E-E-A-T Signals | 15% |
| Sitemap | 10% |
| Content Quality | 10% |
| Core Web Vitals | 10% |
| Technical SEO | 5% |

Score = weighted average × 20 (converts 1-5 scale to 0-100), with letter grade (A through F).

### 3. Updated workflow prompt

- Step 3: Added instruction to produce SEO Score section with weighted scoring table
- Step 5: Added requirement for issue body to include both AEO and SEO score sections

## Why This Works

1. **Issue tracking gap:** The workflow's Step 5 prompt only asked for a "summary" of findings — it never instructed the agent to create individual issues. Findings without tracking issues are invisible to the issue-based workflow.
2. **Score parity:** The AEO audit agent (growth-strategist) had a weighted scoring rubric built into its instructions. The SEO audit agent (seo-aeo-analyst) only had a qualitative report template (Critical/Warnings/Pass). Adding a parallel scoring rubric makes both audits produce comparable, trend-trackable metrics.

## Prevention

- When building automated audit workflows, ensure the workflow creates individual tracking issues for findings — not just summary reports. A finding without a tracking issue is a finding that gets forgotten.
- When parallel audit dimensions exist (AEO + SEO), ensure both produce comparable output formats. If one dimension has a score, the other should too.

## Related Issues

- See also: [growth-strategist-agent-skill-development](../2026-02-19-growth-strategist-agent-skill-development.md) — original growth-strategist agent design
- GitHub: #1111 (growth audit), #1121-#1124 (created tracking issues), #1051 (plugin meta description)
