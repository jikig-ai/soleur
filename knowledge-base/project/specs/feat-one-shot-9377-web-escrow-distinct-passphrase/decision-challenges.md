# Decision challenges - feat-one-shot-9377-web-escrow-distinct-passphrase

Appended by plan-review on 2026-10-03 (headless pipeline: not asked, persisted for the ship phase to render and file). The plan proceeds with the owner's stated direction in every row.

## User-Challenge

1. **Make a web-class birth fail closed on missing escrow instead of only paging** (spec-flow, P1). The preflight reads Doppler names only, so a present-but-malformed or wrong R2 pair passes it, the provisioner formats the volume, and escrow then fails; the only remedy is a host replace. The reviewer proposes either value-level checks in the preflight (not possible names-only) or a provisioner that withholds service until escrow is ok. The owner's decision (B) is "page a person"; the existing design ("the provisioner formats even with escrow missing, by design") is kept. Default: the plan stands. Re-evaluate at #9372, before a web-class host holds data.

## Taste

2. **Run the preflight before the reviewer approval of the dispatch environment** (spec-flow, architecture). A separate ungated preceding job would save a reviewer approval on an aborted birth. Default: same-job step, because the credential read stays inside the approved job. 
3. **Put only the two web addresses in the jq rotation HALT** (DHH). Web-1's password leaves the push-apply graph after the swap, so its addresses are dormant. Default: all four addresses stay, because the owner asked for a HALT on "either" password and the inngest precedent lists both members.
4. **Consolidate the five prose surfaces** (ADR, Article 30 cell, compliance cell, ledger row, rationale runbook) (DHH). Default: all stay, they are owner asks 5 and 6 and the two legal cells and the ledger carry the superseded sentence.
5. **Dedicated cross-gate census** (CTO suggested, DHH and simplicity cut). Resolved toward the cut: per-gate removal rows plus a job-reach row in `terraform-target-parity.test.ts`.
