# Decision challenges — feat-one-shot-plugin-version-visibility

Persisted by `soleur:plan` (headless). `ship` Phase 6 renders these into the PR body and files an
`action-required` issue.

## DC-1 (User-Challenge): item 1 reverses ADR-182 Decision 1 / #7471

- **Operator direction:** stamp a `version` into `plugin.json` and `marketplace.json` from the
  release workflow so `/plugin` shows a real version and update detection compares versions.
- **Conflict:** ADR-182 D1, ADR-017, rule `wg-never-bump-version-files-in-feature` (second half),
  the #7471 post-mortem (3 months of silent staleness, single-user-incident threshold), and four
  guard surfaces assert that no manifest carries a `version` key. A release-stamped value is not a
  constant, but it is stale between content merge and stamp merge. Measured bot-PR
  created-to-merged: 41, 43, 77, 80, 88, 112 minutes (`gh pr list --state merged --author app/soleur-infra`).
- **CTO view:** make the keyless path the default and ship items 2-4 first; enable the stamp only
  if `claude plugin update` is proven to detect a changed version string.
- **Plan default:** Slice A (items 2-4 + shared resolver, keyless-compatible) ships
  unconditionally; Slice B (the stamp) is gated on Phase 0 measurements M1/M3, dark-launched behind
  repo variable `PLUGIN_VERSION_STAMP`, canaried, and stamps `plugin.json` only (the brief's
  `marketplace.json` is redundant: manifest wins; the published manifest must stay keyless).
- **Operator decision needed:** accept the bounded stale window and the ADR-182 amendment, or
  drop Slice B and keep the keyless baseline.

## DC-2 (Taste): stamp `plugin.json` only, not `marketplace.json`

Deviation from the brief, justified by Claude Code's manifest-over-entry version precedence and
ADR-182 D4 (a release publishes nothing to any marketplace manifest).

## DC-3 (gate): CPO sign-off

Plan declares `Brand-survival threshold: single-user incident` -> `requires_cpo_signoff: true`.
CPO advisory result is recorded in the plan's Domain Review. Sign-off must be confirmed before
`soleur:work` starts.

## DC-4 (User-Challenge, from plan review): scope of Slice A

DHH and code-simplicity recommend cutting the SessionStart hook's cache/background-refresh/opt-in
network (and with it the privacy-policy carve-out, five legal gates and C4 edge), keeping only an
offline banner plus `/soleur:version` (user-initiated network). The brief asks for the cached,
opt-in network check, so the plan keeps it; the operator may drop it to shrink Slice A by roughly
a third.

## DC-1 update from plan review

CPO verdict: SLICE B CHANGES REQUESTED (not proportionate; stale window not acceptable as a
default; failure path unbounded). Plan response: Slice B retained but gated (Execution gate in
the plan); `soleur:work` stops after Slice A unless the operator confirms DC-1. Architecture
review added blockers now fixed in the plan text (dry-run cut a real release; `resolve-target`
fail-closed on a skipped release; prod-version-drift false alarm; no rollback path).
