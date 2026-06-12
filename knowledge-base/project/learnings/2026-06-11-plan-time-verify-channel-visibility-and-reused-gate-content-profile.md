# Learning: Verify a "private channel" host's visibility, and a reused gate's content-profile, at plan time

## Problem

Two premise-class mistakes surfaced (and were caught at plan-review) while planning the operator
weekly digest (#5085), both of which a brainstorm/plan would otherwise carry into implementation:

1. **A "private GitHub issue" delivery channel was chosen for a brand-critical private-data digest
   without verifying the host repo's visibility.** `jikig-ai/soleur` is **public** — so a soleur
   issue is world-readable, and even *generating* the digest in soleur's GitHub Actions runs in
   **public logs**. The brainstorm's "private GitHub issue in the operator's repo" was impossible as
   written; it would have leaked the operator's financials/incidents.

2. **A redaction sentinel tuned for one artifact class (PIRs) was about to be reused verbatim as the
   gate for a different artifact class (a synthesized business digest).** `redact-sentinel.sh`
   `exit 1`-aborts on `email`/`UUID`/`IPv4` — fine for human-reviewed PIRs, but for a weekly digest
   it would (a) **over-abort on benign content** (a first-party `@jikigai.com` address is literally in `expenses.md`; a
   trace-id or node-IP in a PIR summary) → silently kill the digest (the exact failure the feature
   exists to prevent), AND (b) **miss the threat the digest actually carries** — a named person
   ("Jane Doe at Contoso") passes a shape-regex clean.

## Solution

**At plan/brainstorm time, before locking either decision, run the cheap verification:**

1. **Channel visibility:** `gh repo view <owner/repo> --json visibility`. A "private channel"
   decision (private issue, committed file, private artifact) is only valid if the *host* is private.
   For a public host, a private surface must move elsewhere (a dedicated private repo, email, etc.) —
   and remember CI logs inherit repo visibility too, so *generation* location matters as much as
   *delivery* location.

2. **Reused-gate content-profile:** before reusing a redaction/validation/lint gate built for artifact
   A on artifact B, **run the gate against real sample B data** and read its abort-classes against B's
   actual content profile. Decide per class: hard-abort (true secrets), warn-only (legitimate-in-B
   shapes like UUID/IPv4), or allowlist (first-party email). And recognize that a shape-regex gate
   cannot catch named PII — that control must be **upstream** (summaries-only synthesis), not the gate.

## Key Insight

Both are the same mistake in two costumes: **a decision premised on an unverified property of a thing
you're reusing** — the host repo's visibility, or a gate's fitness for a new artifact. The fix is a
10-second probe (`gh repo view`, or running the gate on real data) at the moment the decision is made,
not at implementation time when the premise is already load-bearing. Generalizes the
paraphrase-without-verification class to *channel hosts* and *reused gates*.

## Tags
category: workflow-patterns
module: plan, brainstorm
