# Decision challenges - feat-one-shot-9377-web-escrow-distinct-passphrase

Appended by plan-review on 2026-10-03 (headless pipeline: not asked, persisted for the ship phase to render and file). The plan proceeds with the owner's stated direction in every row.

## User-Challenge

1. **Make a web-class birth fail closed on missing escrow instead of only paging** (spec-flow, P1). The preflight reads Doppler names only, so a present-but-malformed or wrong R2 pair passes it, the provisioner formats the volume, and escrow then fails; the only remedy is a host replace. The reviewer proposes either value-level checks in the preflight (not possible names-only) or a provisioner that withholds service until escrow is ok. The owner's decision (B) is "page a person"; the existing design ("the provisioner formats even with escrow missing, by design") is kept. Default: the plan stands. Re-evaluate at #9372, before a web-class host holds data.

## Taste

2. **Run the preflight before the reviewer approval of the dispatch environment** (spec-flow, architecture). A separate ungated preceding job would save a reviewer approval on an aborted birth. Default: same-job step, because the credential read stays inside the approved job. 
3. **Put only the two web addresses in the jq rotation HALT** (DHH). Web-1's password leaves the push-apply graph after the swap, so its addresses are dormant. Default: all four addresses stay, because the owner asked for a HALT on "either" password and the inngest precedent lists both members.
4. **Consolidate the five prose surfaces** (ADR, Article 30 cell, compliance cell, ledger row, rationale runbook) (DHH). Default: all stay, they are owner asks 5 and 6 and the two legal cells and the ledger carry the superseded sentence.
5. **Dedicated cross-gate census** (CTO suggested, DHH and simplicity cut). Resolved toward the cut: per-gate removal rows plus a job-reach row in `terraform-target-parity.test.ts`.

## Phase 4/5 implementation forks (appended at work time; the plan did not settle these)

6. **A decode row for `resolve_link_local` in the egress runbook (scope beyond the plan).** Routing an op onto a paging rule without a decode row is the class the egress suite already guards for the GHCR ops (every routed op must be named in a runbook table row). The plan only asked for `ROUTED_OPS` and the reference entry. Default taken: add one row and one header sentence to `cron-egress-blocked.md`, and extend the suite's decode-literal list. Cheap to drop if a reviewer prefers the minimal diff.
7. **The `resolve_link_local` message interpolates the resolving source.** Each source is therefore its own Sentry issue group and pages once on first seen; the resolver also posts once per source until it answers clean. Accepted and recorded in the rule comment; the plan's "no new frequency slot" is unaffected. The op was NOT given a static message (a change to the emitter is outside this PR).
8. **The shape check runs in a subshell, `( LC_ALL=C; [[ ... ]] && [[ ... ]] )`, not `local LC_ALL=C`.** Chosen so the locale pin cannot leak into the later `cryptsetup`, `curl` and `awk` calls of the same function. Cost: one fork. The pre-existing bucket and endpoint shape line directly above it still runs under the ambient locale (its classes are `[a-z0-9]`, `[0-9a-f]`); the plan scoped the C-locale pin to the credential pair, so that line is unchanged. A possible follow-up, not taken here.
9. **The Guard 5 locale row is runner-dependent.** It runs a non-ASCII key id under a range-widening locale (en_US) when one is installed, and otherwise records a single pass row naming that no such locale exists, so the assertion count stays constant across runners. The static row (the pinned spelling with `LC_ALL=C`, mutation 107) carries the claim either way.
10. **The suite's default R2 key id fixture changed from the 13-character `TESTKEYID0001` to a 32-hex synthetic value.** The new lower bound (16) would otherwise refuse every existing escrow row. Nothing else read the old value.
11. **Op-contract suites were run with the main checkout's `node_modules` symlinked into this worktree** (removed afterwards, never committed), because the worktree has no installed dependencies and installing was not needed for two pure file-reading suites. The versions are the main checkout's, not a fresh `npm ci` of this branch's lockfile.
