# Learning: a ruling cited from a task brief is not a posted artifact, and verbatim ruled text can republish a phrase another PR retired

## Problem

PR #11487 applied the CLO wording ruling on #10479 (TLS covers browser to Cloudflare only, not Cloudflare to origin). Four review seats found five things that no gate, lint or green test run had seen.

## Solution

- **Authority was cited from a conversation, not from the issue.** The task brief described a "2026-10-29 re-affirmation". The only artifact on #10479 is the 2026-10-27 comment. The first draft wrote "re-affirmed 2026-10-29" into five records (register markers, ledger exception, domains.md, plan, commit message). The CLO seat and the fact-check seat both could not retrieve it. Fix: cite only the posted 2026-10-27 comment in every repo record, and list the missing re-affirmation as an owner item (post it on the issue or drop it).
- **Ruled text republished a retired phrase.** The ruled Privacy Policy Section 11 bullet says "the self-hosted Inngest event store described in Section 4.13". PR #11283 (2026-10-27, after the ruling's posting time) changed Section 4.13 to say the event store is a Supabase Postgres project and retired the "self-hosted" description. The instruction was to use the ruled text verbatim, so it stayed, and the contradiction is flagged to the owner with drafted replacement wording instead of being silently edited. No gate sees this: SHA pins, mirror drift, anchor resolution and heading parity all pass.
- **The ruling's fix paragraph was copied into five records.** Single-source it at the record that owns the detail (here the PA-13 (g)(14) marker) and make every other marker a pointer. The pointer shape already existed in the register.
- **The plan's sweep covered legal and ops files only.** `nfr-register.md` NFR-026 carried "Dashboard -> API Routes: Implemented, HTTPS" and had no row for the Cloudflare edge to origin hop. ADR-294 had already said the register moves in the later ledger-and-legal-wording PR. Fix: added the row, a superseded note, and a Partially Implemented system status. The generated `model.likec4.json` carries the ambiguous label "HTTPS via Cloudflare (app.soleur.ai/api/inngest)" and was left for its generator.

## Key Insight

A claim of authority is a claim about an artifact. If the reviewer cannot fetch it, it does not belong in a register that other people will cite. Separately, "use the ruled text verbatim" and "do not contradict the rest of the published document" can conflict when a sibling PR lands between the ruling and the application; the conflict is a CLO/owner decision, so surface it with drafted wording rather than choosing silently.

## Session Errors

1. **Cited an unposted re-affirmation as authority in five records.** Recovery: removed from all, listed as an owner action. **Prevention:** before writing "ruled/re-affirmed <date>" into a record, run `gh issue view <N> --comments` and cite only a comment that exists.
2. **Plan sweep missed the engineering NFR register.** Recovery: NFR-026 edited after the architecture seat found it. **Prevention:** for a TLS-wording correction, sweep `knowledge-base/engineering/architecture/` and `knowledge-base/operations/` for "HTTPS"/"TLS"/"in transit", not only `docs/legal` and `knowledge-base/legal`.
3. **Fix paragraph repeated five times.** Recovery: collapsed to pointers. **Prevention:** put the ruling's dates and fix text in exactly one marker per issue; every other marker points at it.
4. **First edit script closed a bold span early in the PA-13 marker.** Recovery: caught by the bold-balance check in the verification step, fixed in the same run. **Prevention:** after editing a register cell, assert `**` count parity and `[`/`]` balance, as well as pipe count.
5. **Recursive `grep` is refused in a worktree-isolated shell** (any command containing the word is rejected as too complex to verify). Recovery: a small Python sweep helper. **Prevention:** use the Read tool, `awk`, or a script file for repo-wide searches in these agents.
6. **`test-all.sh --print-selection` ran past the 120 s foreground limit** and was moved to the background, then stopped. One-off; the legal gates were run individually instead.

## Tags
category: workflow-patterns
module: legal / article-30-register / encryption-posture-ledger
