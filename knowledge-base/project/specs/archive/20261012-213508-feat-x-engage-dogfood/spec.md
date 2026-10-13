# Spec: X Engage Dogfood (Graceful Degradation)

**Brainstorm:** [2026-03-10-x-engage-dogfood-brainstorm.md](../../brainstorms/2026-03-10-x-engage-dogfood-brainstorm.md)
**Branch:** feat-x-engage-dogfood
**PR:** #495

## Problem Statement

The `/soleur:community engage` sub-command requires the X API paid tier ($100/mo) for `fetch-mentions`. On the Free tier, it fails with a 403. This blocks dogfooding the engagement pipeline entirely, even though the posting path (`post-tweet --reply-to`) works fine on the Free tier.

## Goals

1. Enable dogfooding the engage workflow on the Free tier via graceful degradation
2. Track the paid tier upgrade as a deferred expense gated on revenue milestones
3. Add light moderation guardrails for X engagement before going live

## Non-Goals

- Upgrading to the paid X API tier
- Building rate-limit tracking for the 50 tweets/month cap
- Creating a full moderation runbook with SLAs and escalation paths
- Browser automation for thread discovery
- Fixing #478 or #492 (separate work items)

## Functional Requirements

- **FR1:** When `fetch-mentions` returns HTTP 403, the engage sub-command catches the error and prompts the user to paste a mention URL or tweet text manually
- **FR2:** Parse tweet ID from standard X URLs (`https://x.com/<user>/status/<id>` or `https://twitter.com/<user>/status/<id>`)
- **FR3:** After manual input, the existing brand-voice draft + approval pipeline runs unchanged
- **FR4:** When `fetch-mentions` succeeds (paid tier active), the manual fallback is never triggered -- seamless upgrade path
- **FR5:** A "deferred-expense" labeled GitHub issue tracks the paid tier upgrade with revenue trigger criteria
- **FR6:** Expense ledger entry with DEFERRED status, $100/mo amount, and revenue trigger condition
- **FR7:** Brand guide X engagement guardrails section: topics to avoid, when not to reply, reply cadence guidance

## Technical Requirements

- **TR1:** 403 detection must distinguish "paid tier required" (reason: "client-not-enrolled") from other 403 errors (e.g., suspended account)
- **TR2:** URL parsing must handle both `x.com` and `twitter.com` domains, with and without query parameters
- **TR3:** Manual input path must validate tweet ID is numeric before passing to `post-tweet --reply-to`
- **TR4:** No changes to the `x-community.sh` script -- degradation logic lives in the SKILL.md engage workflow
- **TR5:** Since-id state file is not updated in manual mode (no pagination to track)
