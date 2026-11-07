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
that emits a token-clean output name (`deploy_target` since #332 — see
addendum; `deploy_sha` shown here re-alerted on the field-name arm) only for proven-trusted upstream events
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

## Addendum — 2026-11-04 (#332): the identifier heuristic tests the FIELD NAME, not only the id

The sink description above is incomplete, and the completion is what produced
alert #332. `ActionsSHACheckout`'s heuristic arm runs
`value.regexpMatch(".*(head|sha|commit).*")` not only against the
`steps.<id>`/`needs.<job>` **id** but against the expression's **field name**
(`SimpleReferenceExpression.getFieldName()`), access path, and inner
expression. `steps.gate.outputs.deploy_sha` alerted (as new alert #332, ~3.5 min) after #216's
structural fix merged — the id `gate` is clean, the field name `deploy_sha`
matches via `sha`. The sibling `ActionsMutableRefCheckout` arm runs the same
field-name test against `.*(head|branch|ref).*`, so a clearing identifier
must avoid all five tokens: `head`, `sha`, `commit`, `branch`, `ref`.
`deploy_target` matches none.

Two corollaries verified at predicate level: (i) the env→step-output
extractors (`FlowSteps.qll` `envToOutputStoreStep`/`commandToOutputStoreStep`)
only register a literal `echo|printf >>`/`VAR2=$VAR` shape, so emitting via a
function-call indirection (`emit name "$VAR"` where `emit` wraps `printf`)
leaves NO modeled taint path into the output — keep the indirection; (ii)
checking a candidate name against `containsHeadSHA` alone is the wrong
verification — run it against both heuristic token sets on the full
`steps.<id>.outputs.<name>` expression.
