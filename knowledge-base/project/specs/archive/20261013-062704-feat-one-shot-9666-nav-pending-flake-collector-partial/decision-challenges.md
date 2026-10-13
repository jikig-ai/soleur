# Decision challenges: feat-one-shot-9666-nav-pending-flake-collector-partial

Headless plan-review (one-shot) persisted these Taste items. They are not auto-applied; the plan keeps the operator's stated direction.

## T1 - Split the PR into two (Taste)

- Operator direction: one branch and draft PR #9676 for both the nav-pending flake (#9666) and the community-monitor collector partial gap.
- Panel (DHH review): the cron prompt and collector change is higher-stakes than a test and client-island fix, so reverting one drags the other; splitting is cheap.
- Disposition: plan keeps a single PR (operator-named vehicle). Revisit at ship if review comments show the two halves diverge in risk.

## T2 - Keep the `--status-line` arm and drop the follow-through `.test.sh` (Taste)

- Simplicity review: drop `--status-line` (second output mode) and the probe's test.
- Plan: keeps `--status-line` because preflight Check 10 treats a non-zero exit as a failed probe and the real arm exits 1 before the deploy; drops the separate `.test.sh` and exercises the three arms once inside the compact parity test.

## T3 - Keep `delayRoute` for the back-nav test rather than unifying with `holdNavFetch` (Taste)

- CTO devex review: two hold helpers duplicate the prefetch-abort and non-RSC fallback rules; migrate the back-nav test and delete `delayRoute`.
- Plan: leaves `delayRoute` for the one test that still uses it to avoid widening the flake fix beyond the two failing tests; unify later if a second flake touches it.

## T4 - UI-surface glob match on `nav-pending-island.tsx` treated as exempt (Taste)

- Rule: the shared UI-surface glob (`components/**/*.tsx`) forces the Product/UX gate to BLOCKING and requires a committed `.pen` wireframe.
- Judgment: the one component edit is an effect guard with no visible change (no markup, copy, layout or interaction change), which `ui-surface-terms.md` § Excluded covers. The plan records the reasoning in its Domain Review and does not produce a wireframe. Operator can overrule at review.
