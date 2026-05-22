---
title: Parallel `gh issue create` scrambles ID→title mapping + review-agent design needs producer/consumer symmetry
date: 2026-05-22
category: best-practices
tags: [github-cli, parallel-execution, race-condition, review-agents, security-checklist]
pr: 4288
issue: 4233
status: documented
---

# Learning: Parallel `gh issue create` scrambles ID→title mapping + review-agent design needs producer/consumer symmetry

## Problem

Two distinct issues surfaced during the /work execution for #4233 (identity/RBAC reviewer agent). Both have reusable shape beyond this PR.

### Issue 1: Parallel `gh issue create` race scrambles ID→title mapping

Filing N related deferral issues via:

```bash
gh issue create --title "...kb_files..." & 
gh issue create --title "...kb_chunks..." &
gh issue create --title "...runtime_cost_state..." &
wait
```

returned URLs in completion order, not start order. The agent body that immediately cited `#4304 → kb_files` was wrong; `#4304` had actually been assigned to the `kb_chunks` issue because its `gh issue create` happened to finish first.

Worse, when the second parallel batch (`attachments` + `session-invalidation`) hit a transient GraphQL error:

```text
GraphQL: Something went wrong while executing your query on 2026-05-22T07:04:38Z. Please include `CD20:1906:2544BAF:23F2214:6A100005` when reporting this issue.
https://github.com/jikig-ai/soleur/issues/4307
```

I misread which `&`-job had errored. The 4307 URL was from the *session-invalidation* job (which succeeded silently); the *attachments* job had errored. I retried what I thought was the failed job — session-invalidation — creating duplicate `#4309`. Attachments was never filed in the original batch.

Net result entering review:

- 5 issue IDs cited in agent body — 3 inverted/wrong, 1 missing entirely.
- Multi-agent review (pattern-recognition + user-impact-reviewer) caught the drift at P1; recovery required closing `#4309`, filing `#4318` for attachments, and rewriting the agent body's `## Known gaps` block + SKILL.md dispatch reference.

### Issue 2: Review-agent checklist designed for consumer side, missed issuer side

The R3 check in `identity-rbac-reviewer.md` initially audited only:

> Routes / middleware that filter by workspace MUST consume the `current_organization_id` claim.

This is the *consumer* side. Security-sentinel flagged at review that the *issuer* side — the Custom Access Token Hook (migration 060) writing the claim — was unowned. The agent description's pointer to security-sentinel ("OWASP-generic auth/sessions") was too vague to firmly assign issuance-integrity concerns there.

The concrete attack surface I missed: a future PR modifies the hook to read `current_organization_id` from `raw_user_meta_data` (user-writable in Supabase) instead of `app_metadata`. Every R3 consumer check passes; the JWT is forged at issuance. Same shape applies to webhooks, signed events, capability tokens — any artifact where one side produces and many sides consume.

## Solution

### Issue 1 — `gh issue create` race

**Two viable shapes, both safer than `gh & wait`:**

**Shape A (preferred for ≤5 issues): serialize and capture-by-line.**

```bash
declare -a issue_ids
declare -a issue_titles
for spec in \
  "kb_files|feat: workspace-keyed RLS on kb_files (#4233 known gap)|body-kb-files.md" \
  "kb_chunks|feat: workspace-keyed RLS on kb_chunks (#4233 known gap)|body-kb-chunks.md"; do
  IFS='|' read -r short_name title body_file <<<"$spec"
  url=$(gh issue create --title "$title" --body-file "$body_file" --label deferred-scope-out --milestone "Post-MVP / Later")
  n=${url##*/}
  issue_titles+=("$short_name")
  issue_ids+=("$n")
  echo "  $short_name -> #$n"
done
```

Cost: serial latency (~1.5–3 s per `gh issue create`, so ~15 s for 5 issues). Benefit: deterministic mapping, no parse-after-the-fact, no error confusion.

**Shape B (necessary for >5 issues): parallel with explicit ID→title reconciliation.**

```bash
# Spawn in parallel, write each result to a file keyed by short_name
for spec in "kb_files|..." "kb_chunks|..." ...; do
  IFS='|' read -r short_name title body_file <<<"$spec"
  (
    url=$(gh issue create --title "$title" --body-file "$body_file" ...)
    echo "$url" > "/tmp/issue-$short_name.url"
  ) &
done
wait
# After all complete, reconcile each short_name to the issue it actually got
for spec in "kb_files|..." ...; do
  IFS='|' read -r short_name _ _ <<<"$spec"
  url=$(cat "/tmp/issue-$short_name.url" 2>/dev/null || echo "")
  if [[ -z "$url" ]]; then
    echo "FAILED: $short_name (file missing — likely a transient error)"
  fi
done
```

The key insight: never trust the stdout order of `gh & wait`. The shape that works is *short_name → file → URL*, never *short_name → stdout-line-N → URL*.

**Mandatory post-creation verification (both shapes):**

```bash
for n in "${issue_ids[@]}"; do
  actual=$(gh issue view "$n" --json title --jq .title)
  echo "#$n: $actual"
done
```

Run this BEFORE writing any artifact that cites the issue numbers (agent body, README, SKILL.md, plan). The cost is ~N seconds; the cost of catching wrong IDs at PR review is ~30 minutes of recovery (close duplicate, file missing, edit artifacts, force-push).

### Issue 2 — Producer/consumer symmetry in review-agent design

When designing a review agent for a class of vulnerability, enumerate **both ends of every security-relevant artifact**:

| Artifact class | Producer (issuer/writer) | Consumer (reader/handler) |
|---|---|---|
| JWT custom claim | Access Token Hook / JWT-mint RPC | Route middleware / RPC parameter check |
| Signed webhook | Sender (HMAC sign) | Receiver (HMAC verify + replay guard) |
| Capability token | Mint RPC | Authz check before action |
| RLS-protected row | INSERT-time write-boundary sentinel | SELECT-time RLS predicate |
| Encrypted blob | Encryption call site | Decryption call site + key-version check |

R3 in `identity-rbac-reviewer.md` v1 only audited consumers; v2 splits into:

- **Consumption** — routes/middleware MUST read the claim from `app_metadata`.
- **Issuance integrity** — the hook MUST read from `app_metadata`, NOT `raw_user_meta_data`, and re-validate membership.
- **Write-path** — writes to the claim's underlying state MUST route through the membership-checking RPC.

The general lesson: a checklist for a security class is incomplete until every artifact in the class has both producer and consumer coverage. When you can't fit both into one rule, the rule name should signal which half is missing ("R3-consumer", "R3-issuance") so audits can detect the gap.

## Key Insight

**Race conditions in shell parallelism rarely manifest in computed data; they manifest in identifier-to-payload mapping.** `gh issue create &` is one instance — the "data" (issue body) is correct, but the "identifier" (issue number) maps to the wrong payload. The same pattern shows up in any parallel-spawn-then-collect shape: `xargs -P`, `parallel`, `make -j`, async `Promise.all` where the result array is reordered. The fix is universal: never use stdout order as the join key; key results by an explicit, stable name on the producer side.

For review-agent design: **the checklist's coverage map should be visible as a matrix.** Walking through the producer/consumer table above for each security-relevant artifact at design time would have surfaced the R3 gap before the security-sentinel found it. Multi-agent review is a backstop, not the primary defense.

## Session Errors

1. **Parallel `gh issue create` race scrambled ID→title mapping** — 3 of 5 issue IDs were wrong in the agent body, 1 was dropped, 1 was a duplicate. **Recovery:** closed duplicate #4309, filed #4318 for missing attachments, edited agent body + SKILL.md to use correct IDs. **Prevention:** when filing N related issues, either serialize the calls OR key results by an explicit name on the producer side; never trust stdout order. Always run `gh issue view <N> --json title` reconciliation before citing IDs in any artifact.

2. **Agent-description budget not measured at plan time** — Plan AC2 measured only the SKILL.md cumulative description budget (1835/1850, 15 words headroom). Pattern-recognition reviewer flagged the separate AGENT description budget (per `plugins/soleur/AGENTS.md`, 2,500-word soft cap) is at 2,781 — pre-existing debt the plan didn't surface. **Recovery:** none required for this PR (pre-existing). **Prevention:** when planning a new agent, measure both budgets at Phase 1.8 — they have separate caps and separate measurement methods. Plan skill's Phase 1.8 should be extended.

3. **R3 designed for consumer only, missed issuer** — Original R3 audited only routes/middleware consuming `current_organization_id`, missing the Custom Access Token Hook that issues it. **Recovery:** security-sentinel flagged at review; fixed inline by splitting R3 into Consumption + Issuance integrity + Write-path. **Prevention:** for any review-agent checklist covering a security class, walk through a producer/consumer matrix at design time. Every security-relevant artifact has at least two endpoints; covering only one leaves the other class of bug uncatchable.

4. **R4 severity-promotion was prose-only** — Original R4 said "promote to high once mechanisms exist" with no detection rule. **Recovery:** fixed inline with `git grep -nE 'revokeWorkspaceSession|invalidateMemberSession'` tripwire. **Prevention:** any "promote when X happens" instruction in a review-agent body must encode a deterministic detection rule (grep, file-exists check, type-existence probe) so the promotion is mechanical, not prose-dependent. Stale-rot is silent.

## Tags

category: best-practices
module: github-cli + review-agents
