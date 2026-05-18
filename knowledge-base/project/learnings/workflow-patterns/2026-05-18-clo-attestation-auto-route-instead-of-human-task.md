---
module: System
date: 2026-05-18
problem_type: workflow_pattern
component: soleur-go
symptoms:
  - "follow-through issue says 'CLO/human attestation' and waits indefinitely for the human to do statutory-text verification"
  - "/soleur:go #N on the follow-through routes to /soleur:review (PR-number heuristic), but the issue is not a PR"
  - "soleur assumes users have legal-domain knowledge sufficient to verify GDPR / CCPA / statute text"
root_cause: incorrect_routing_assumption
resolution_type: routing_table_update
severity: medium
tags: [soleur-go, clo, legal, attestation, follow-through, manual-because, eur-lex, leginfo]
---

# CLO attestation should auto-route to the clo agent, not the human user

## Problem

When `/soleur:ship` Phase 7 Step 3.5 scans a merged legal-doc PR's body for unchecked ⏳ follow-through items, it creates GitHub issues with `type: manual, manual_because: subjective-design-call` for any external-statutory-source verification the PR couldn't complete in-line (e.g., "verify AUP §4.7 GDPR Art. 9 enumeration against EUR-Lex"). The issue body framing is "CLO/human pre-merge legal-source attestation" — placing the human user on equal footing with the CLO agent for the verification task.

This assumption is wrong. The Soleur user is typically a non-lawyer founder. Asking them to do EUR-Lex / leginfo statutory-text verification:

1. **Bottlenecks the follow-through indefinitely.** The user is unlikely to do the work themselves; the issue ages out.
2. **Mis-allocates expertise.** The `clo` agent is the legal-domain specialist (orchestrates `legal-document-generator` + `legal-compliance-auditor`); it can do mechanical text-diff against EUR-Lex / leginfo and produce a verdict + recommended amendments in one cycle.
3. **Misroutes `/soleur:go #N`.** The numeric-prefix heuristic in `/soleur:go`'s classification table sends `#N` to `/soleur:review` (PR review), but a follow-through *issue* about statutory-text verification is not a code review — it is a legal-domain attestation task.

## Environment

- Module: System (`/soleur:go` routing, `/soleur:ship` Phase 7 Step 3.5 follow-through template)
- Affected components:
  - `plugins/soleur/commands/soleur-go.md` — classification table
  - `plugins/soleur/skills/ship/SKILL.md` Phase 7 Step 3.5 — follow-through body template
- Date: 2026-05-18
- Triggering session: `/soleur:go #3998` (the AUP §4.7/§4.8 CLO/human legal-source attestation follow-through tracking PR #3988)

## Symptoms

- `/soleur:go #3998` initially routed to `/soleur:review` because `#3998` matches the PR-number heuristic — but #3998 is an issue, not a PR. Surfaced the type mismatch only after `gh pr view 3998` returned `Could not resolve to a PullRequest`.
- The issue body said "CLO/human pre-merge legal-source attestation" and offered manual verification with `manual_because: subjective-design-call`.
- The user had to explicitly redirect: "Our CLO should be the one to verify those issues not me — assume users don't know anything about legal."
- Once routed to the `clo` agent, the verification completed in ~90 seconds: EUR-Lex re-fetch (failed, tooling), two-mirror cross-confirm (passed verbatim), CCPA §1798.140(ae) leginfo fetch (passed; AB 947 + SB 1223 confirmed), §4.8 catch-all coverage judgment (ACCEPT with non-blocking AMEND), recommended disposition (close + 1 small follow-up PR for explicit enumeration).

## Root Cause

Two coupled gaps:

1. **`/soleur:go` classification table assumes `#N` references PRs first, issues second.** No branch in the classification logic checks "is this `#N` an *issue* whose `Verification → manual_because:` indicates a legal-domain attestation task?" — the heuristic falls through to `/soleur:review` (PR review) instead of routing to the legal specialist.
2. **`/soleur:ship` Phase 7 Step 3.5 follow-through template defaults to `type: manual` for subjective-design-call cases without considering whether the `clo` agent could deterministically execute the verification.** The template's "manual" framing presumes human judgment; in legal-source attestation, the judgment is bounded by statutory text + interpretation rules the `clo` agent has access to.

## Resolution

Two complementary changes (filed for follow-up — not landed in this session because the user prioritized shipping the in-flight §4.8 amendment first):

### Change 1: `/soleur:go` classification table

Add a new row to the classification table BEFORE the `review` row:

```text
| clo-attestation | The user input is `#N` where N is a GitHub issue (not a PR) AND the issue body contains `type: manual` + `manual_because: subjective-design-call` AND references at least one external legal-source URL (eur-lex.europa.eu, leginfo.legislature.ca.gov, congress.gov, federalregister.gov, gov.uk legislation, justice.gc.ca laws-lois.justice, or a `Art\.\s*\d+|§\s*\d+` statute citation) | `clo` agent (Task spawn) |
```

Detection logic before routing to `/soleur:review`:

```bash
# If $INPUT matches ^#?[0-9]+$
ISSUE_NUM=$(echo "$INPUT" | tr -d '#')
ISSUE_BODY=$(gh issue view "$ISSUE_NUM" --json body --jq .body 2>/dev/null)
if [[ -n "$ISSUE_BODY" ]] && \
   echo "$ISSUE_BODY" | grep -qE 'type:\s*manual' && \
   echo "$ISSUE_BODY" | grep -qE 'manual_because:\s*subjective-design-call' && \
   echo "$ISSUE_BODY" | grep -qiE '(eur-lex\.europa\.eu|leginfo\.legislature\.ca\.gov|congress\.gov|federalregister\.gov|legislation\.gov\.uk|laws-lois\.justice\.gc\.ca|Art\.\s*[0-9]+|§\s*[0-9]+)'; then
  # Route to clo agent
  spawn clo with the issue context
fi
```

### Change 2: `/soleur:ship` Phase 7 Step 3.5 follow-through template

When emitting `type: manual, manual_because: subjective-design-call` for a legal-source attestation, ADD a routing hint to the issue body:

```markdown
## Verification

```yaml
type: manual
manual_because: subjective-design-call
clo_routable: true  # /soleur:go #<this issue> auto-routes to the clo agent
sla_business_days: 14
```

Run `/soleur:go #<this issue>` to invoke the CLO for verification.
This is faster, more accurate, and does not require legal-domain expertise from the operator.
```

The `clo_routable: true` field is the structured signal that `/soleur:go`'s detection logic above checks for (alternative to URL-pattern matching, which has higher false-positive risk).

## Why this matters

Solo-operator velocity: every "please verify this against EUR-Lex" task that gets routed to the human stops the founder's day. The CLO agent exists to do exactly this work; misrouting wastes both the agent's capability and the operator's attention. The fix is small (one classification row, one template field) and reversible (operator can always override the route via `/soleur:go --no-route` or by spawning a different agent directly).

## Cross-references

- Session that surfaced this: `/soleur:go #3998` → `/soleur:review` → user redirect → `clo` agent → PR #3999 (AUP §4.8 amendment).
- Related rule: `pdr-when-a-user-message-contains-a-clear` (passive domain routing) — same principle, applied to `/soleur:go` numeric-prefix detection.
- Related skill: `plugins/soleur/agents/legal/clo.md` (CLO agent spec).

## Tags

category: process
module: soleur-go / ship Phase 7 Step 3.5
