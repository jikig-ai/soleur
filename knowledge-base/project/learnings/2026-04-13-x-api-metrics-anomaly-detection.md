---
title: "X API metrics anomaly detection: verify data before assuming API fault"
date: 2026-04-13
category: integration-issues
tags: [x-api, community-monitor, anomaly-detection, shell-scripting]
module: plugins/soleur/skills/community
---

# Learning: X API metrics anomaly detection

## Problem

The community monitor daily digest reported 0 X/Twitter followers starting
April 11, 2026. The initial assumption was that the X API was returning
incorrect data, possibly due to the February 2026 pay-per-use migration.

## Investigation

Three independent verification paths were tested:

1. X API v2 (authenticated via Doppler `prd_scheduled` credentials)
2. X GraphQL guest token endpoint (`UserByScreenName`)
3. Playwright visual snapshot of the X profile page

All three confirmed `followers_count: 0`. The API was accurate — the account
genuinely lost its followers (likely spam cleanup on a 3-follower account).

## Solution

Instead of "fixing" correct data, added anomaly detection to
`x-community.sh`:

- `_has_metrics_anomaly` function detects suspicious patterns (active account
  with 0 followers, all-zeros degradation) and emits stderr warnings
- Integrated into `cmd_fetch_metrics` without changing the stdout JSON schema
- Updated `community-manager.md` to instruct the agent to surface warnings

## Key Insight

When monitoring data looks wrong, verify the data source independently before
assuming the API is at fault. Three verification paths (API, GraphQL, visual)
cost 5 minutes but prevented building a web scraping fallback that would not
have helped. The correct fix was diagnostics, not data correction.

## Review Findings Applied

- Added numeric guard for non-numeric jq output (defensive arithmetic)
- Renamed from `_check_metrics_anomaly` to `_has_metrics_anomaly` (shell
  boolean convention: 0=true)
- Consolidated 5 jq subshells to 2 (single `@tsv` extraction)
- Added `listed_count` edge-case test documenting its exclusion from detection

## Tags

category: integration-issues
module: plugins/soleur/skills/community
