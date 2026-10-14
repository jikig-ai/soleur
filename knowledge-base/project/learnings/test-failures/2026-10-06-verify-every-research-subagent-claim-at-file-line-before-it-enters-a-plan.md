# Learning: verify every research-subagent claim at file:line before it enters a plan

## Problem

The repo-research subagent for this plan made two carrier claims that read as hard facts: that the script edits "could
cross the 23,800 B user_data budget", and that `cron-egress-enforce-probe.sh` is hashed into
`private_nic_guard_install`'s `triggers_replace`. Both were wrong. The plan-time prototype of the edits also had to be
run on scratch copies before the design was trusted.

## Root cause

`user_data` carries only a 64-character `host_scripts_content_hash`; script bytes are baked into the image, so the size
test is unaffected. `triggers_replace` of that resource hashes only the guard, its unit and timer, the private IP, the
ingest URL and a token digest; the probe appears once in `server.tf`, in `host_script_files`.

## Solution

Re-read the cited lines (`server.tf` around the `host_script_files` map, the `triggers_replace` block) before writing the
claim, record the correction in the plan's reconciliation table, and run the size suite anyway as a check.

## Key insight

A subagent's summary is a claim about files, not a measurement of them. The cost of a false carrier claim is a wrong
blast-radius statement in the PR body, which an operator then trusts; the check is one `grep -n` per claim.

## Tags

category: test-failures
module: planning
