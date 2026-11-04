# CodeQL `actions/untrusted-checkout` has no `if:`/`persist-credentials` sanitizer — read the query source before choosing a remediation

**Date:** 2026-11-03 · **Context:** CodeQL alert #216 (`actions/untrusted-checkout/medium`) on `.github/workflows/web-platform-release.yml` `resolve-target`'s checkout, `ref: ${{ github.event.workflow_run.head_sha || github.sha }}` (PR #12033).

## Learning

The obvious remediations do not clear this alert class. Reading
`github/codeql`'s `UntrustedCheckoutMedium.ql` +
`UntrustedCheckoutQuery.qll` + `Helper.qll` `inNonPrivilegedContext` directly:

- The sink is a checkout whose `ref:`/`repository:` **expression text** matches
  `containsHeadSHA` regexes (`github.event.workflow_run.head_sha`,
  `\bhead_sha\b`, `merge_sha`, `head.sha`, …) or is a `steps.<id>`/`needs.<job>`
  expression whose id matches `.*(head|sha|commit).*`.
- **No `if:` gate is modelled as a sanitizer and neither is
  `persist-credentials: false`** — they address real risks but not the pattern
  this query matches. An `if:`-gated checkout with a head-SHA `ref:` still
  alerts.
- The `medium` variant fires only in a **non-privileged** job (explicit
  read-only permissions, no secrets, no write). A privileged sibling checkout
  with the identical expression falls outside it — but is no safer at runtime.
- `git\s+(fetch|pull)` in a `run:` script is a separate sink class
  (`GitSHACheckout`) — and `git -c <flag> fetch` incidentally evades the
  adjacency regex today. Do not rely on the spelling.

## Consequence

The only clearing fixes are **structural**: remove the checkout, or make
`ref:` read a *validated* value that names no event field — e.g. a gate step
that emits `deploy_sha` only for proven-trusted upstream events
(`workflow_run.event == 'push' && head_branch == 'main'`, or dispatch →
`github.sha`), with the checkout conditioned on it. That is semantic
indirection (the gate is real at runtime), not cosmetic renaming — and it is
the same trust boundary the repo's runtime re-checks encode, hoisted above
the sink per the ADR-074 precedent ("the sink is structurally absent, or at
least unreachable before trust is established").

**Enumerate the whole file, not just the flagged line.** The sibling
`verify-doppler-secrets` job carried the identical `ref:` expression and then
*executed* a script from that tree under `doppler run -c prd` — strictly worse
than the flagged site, invisible to the alert only because its job is
privileged. Same-class sinks one job over are the expected shape.
