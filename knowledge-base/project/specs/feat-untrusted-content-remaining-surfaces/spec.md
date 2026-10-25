---
title: Untrusted-content classification, remaining surfaces
issue: "#10194"
parent: "#4671"
epic: "#9601"
branch: feat-untrusted-content-remaining-surfaces
lane: cross-domain
brand_survival_threshold: single-user incident
brainstorm: knowledge-base/project/brainstorms/2026-10-25-untrusted-content-remaining-surfaces-brainstorm.md
---

# Spec: untrusted-content classification, remaining surfaces

## Problem Statement

ADR-287 covers WebFetch results only. Issue and PR text written by third parties reaches agents that hold real credentials through the `github_read_*` MCP tools, leader prompts and cron prompts, with no untrusted-data framing.

## Goals

- Route GitHub issue/PR text through `server/untrusted-content.ts` on the MCP-tool, leader-prompt and cron-prompt paths.
- Ship dark behind the existing `untrusted-content-classify` / `untrusted-content-wrap` flag family.
- Pin WebFetch-in-subagent coverage with a test and a queued dev check.

## Non-Goals

- Enabling any flag in prd (#10195).
- Taint downgrade and the LLM tier (#10196, blocked by #4672).
- New PostToolUse hooks for cron Bash output and KB/attachment reads, the plugin-side CLI, and wiring Playwright. Each is a tracked follow-up.
- Any public security claim or copy (#9603).

## Functional Requirements

- **FR1:** `github_read_issue`, `github_read_issue_comments`, `github_read_pr` and `github_list_pr_comments` return results through the shared envelope under a new source `github`.
- **FR2:** Leader prompts that interpolate issue/PR text (`triage.p0p1_issue.ts`, `engineering.pr_review_pending.ts`, and any other found by grep) wrap that text with `envelope("github", ...)` after the existing PII scrub.
- **FR3:** Every cron whose allowlist includes `gh issue view` or `gh issue list` carries an untrusted-content preamble line. The set is derived from code, not listed by hand.
- **FR4:** A hook unit test with `agent_id` set covers the WebFetch hook for subagent calls. Subagent coverage is not claimed until a dev session shows an `untrusted-classify` line with `agent_id`.

## Technical Requirements

- **TR1:** Add `github` to `UNTRUSTED_PREAMBLES`, `FLAG_THRESHOLDS` and `UntrustedSource`. A table-completeness test fails the build if any is missed.
- **TR2:** Keep the `untrustedRowsResponse` shape (preamble in `content[0]`, JSON in `content[1]`). Verify no consumer or test reads `content[0].text`.
- **TR3:** Telemetry is WARN level and a closed field set: scores, reason codes, lengths, hashed ids. No paths, filenames, titles, authors, repo names, URLs or matched text. Hash the conversation id.
- **TR4:** Any new runtime flag is added to `flip.sh` `FLAG_ENV_VARS` with the parity test.
- **TR5:** Amend ADR-287 for these slices.
- **TR6:** Run `soleur:gdpr-gate` at plan time and on the diff. Amend PA-8 (c) before prd enablement.
- **TR7:** The classifier must not be cited as closing #7122 or as a public claim.

## Open Questions

See the brainstorm document: attachment coverage conflict, `github_read_workflow_logs` / `github_read_ci_status`, response shape, cron enumeration.
