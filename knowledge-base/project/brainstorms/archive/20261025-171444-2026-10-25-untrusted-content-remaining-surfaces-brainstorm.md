---
title: Untrusted-content classification for the remaining agent input surfaces
date: 2026-10-25
issue: "#10194"
parent: "#4671"
epic: "#9601"
branch: feat-untrusted-content-remaining-surfaces
lane: cross-domain
brand_survival_threshold: single-user incident
---

# Brainstorm: untrusted-content classification, remaining surfaces (#10194)

## What We're Building

Slice 1 of #4671 (ADR-287, merged 2026-10-14) classifies and annotates **WebFetch** results only, behind two flags that are off in prd. This feature extends untrusted-content handling to the next-highest-risk surfaces, **dark behind the existing flag family**:

- **Slice A:** the four `github_read_*` MCP tools and the leader prompts that interpolate issue/PR text. Static envelope framing through the shared `server/untrusted-content.ts` module, under one new source, `github`.
- **Slice B:** cron prompts whose allowlist includes `gh issue view` / `gh issue list`. Prompt-level framing, plus a test asserting every such cron carries the line.
- **Subagent check:** a hook unit test with `agent_id` set, plus a queued dev-session check for WebFetch inside Task subagents.

Out of scope here, tracked as follow-ups: new PostToolUse hooks (cron Bash output, KB/attachment Read), the plugin-side CLI, and the Playwright "not wired" pin. Soak/enable stays on #10195; taint downgrade and LLM tier stay on #10196 (blocked by #4672).

## Why This Approach

- Both the CPO and CTO rank the same surfaces first: issue/PR text is the one channel a third party can write for free, and the same session holds `github_push_branch`, `github_trigger_workflow` and PR creation.
- Envelope-only framing rides the existing module with a test. Scoring would need a new, non-web corpus, and nothing measures a need for it yet.
- Shipping dark behind the existing flags adds no public claim (CPO and CLO: no claim ahead of a measured control).
- Annotate-only protects the model's reasoning, not the founder's visibility. Capability downgrade is the real control and belongs to #4672/#10196.

## Key Decisions

| # | Decision | Owner |
|---|----------|-------|
| 1 | Scope = slices A and B above; hooks, plugin CLI and Playwright deferred | Operator, 2026-10-25 |
| 2 | Static framing, not scoring, for GitHub text. Revisit after the #10195 soak | Ruled by CTO agent |
| 3 | One source `github` for all four tools. Add it to `UNTRUSTED_PREAMBLES`, `FLAG_THRESHOLDS` and `UntrustedSource` (they are `Record`s, so the build fails without it) | Ruled by CTO agent |
| 4 | Leader prompts wrap with `envelope("github", ...)`. The PII scrub stays and runs first | Ruled by CTO agent |
| 5 | Crons get a prompt-level preamble line now. A CLI PostToolUse hook is deferred because the `.mjs` hook cannot share the TS scorer without bundling | Ruled by CTO agent |
| 6 | Subagent coverage stays "not claimed" until a live dev session shows an `untrusted-classify` line with `agent_id` set. Typings alone do not close it | Ruled by CTO agent |
| 7 | Amend ADR-287 for slices A and B. The KB/attachment Read hook and the plugin CLI each get a new ADR when taken up | Ruled by CTO agent |
| 8 | New log fields must be a closed set: scores, reason codes, lengths, hashed ids. Never paths, filenames, titles, authors, repo names, URLs or matched text | CLO |
| 9 | Productize Candidate: none. This is a one-time extension, not a recurring pattern | Brainstorm |

## User-Brand Impact

- **Artifact:** the GitHub read tools, leader prompts and cron prompts that hand third-party issue/PR text to agents holding real credentials.
- **Vector:** an attacker-written issue or PR comment steers an unattended agent into acting with the founder's credentials, with no visible sign to the founder.
- **Threshold:** single-user incident.

## Open Questions

- **Reconcile attachment coverage (plan-time, CTO).** The CTO reads `attachment-pipeline.ts` as already labeling contents "untrusted data". Repo research finds leader PDF text inlined into the prompt (`leader-document-resolver.ts`, `agent-runner.ts` around `:1395`) with no envelope. These conflict. Verify at plan time. The PDF-text path may be cheap enough to ride slice A.
- **Adjacent surface (plan-time).** `github_read_workflow_logs` and `github_read_ci_status` may carry attacker-controlled log text from fork PRs. Unverified. Could ride the `github` source at no extra cost.
- **Response shape.** `untrustedRowsResponse` puts the preamble in `content[0]` and JSON in `content[1]`. Check that nothing reads `content[0].text` in the GitHub tool tests.
- **Cron enumeration.** Repo research did not enumerate every per-cron `gh issue view` allowlist. Derive the set from the code, never from a hand list.
- **Playwright result text.** Whether `browser_navigate` results carry page text into context is unverified. Deferred. (out of scope)
- **Conversation id is logged unhashed.** The CLO recommends hashing it before the flag goes on in prd.
- **Art. 30 amendment.** PA-8 (c) needs a one-line amendment for ADR-287 before `untrusted-content-classify` is enabled in prd. #10195 already gates that step.

## Domain Assessments

**Assessed:** Marketing, Engineering, Operations, Product, Legal, Sales, Finance, Support

### Engineering

**Summary:** Surfaces ranked by attacker-writability and blast radius. GitHub read tools and leader prompts are the highest risk and fit the shared module with a test. Cron prompt framing is next. KB Read hook, plugin CLI and Playwright need new architecture or are not wired.

### Product

**Summary:** Cron issue/PR bodies plus the GitHub MCP tools are the unattended channels that matter most for the solo-founder ICP. Annotate-only gives no founder-visible protection, so no founder UI now and no "Soleur protects you" copy. #9603 stays blocked: it also needs the egress audit log (#9545) and credential isolation.

### Legal

**Summary:** The heuristic, metadata-only classifier is not a new processing activity, but PA-8 needs an amendment before prd enablement. No public claim is permissible today. Afterwards only a scoped "heuristically screened and flagged" sentence per measured surface. `soleur:gdpr-gate` applies at plan time.

## Capability Gaps

None reported by any leader.
