# Decision challenges — feat-one-shot-8695-8696-c4-banner-bwrap

Recorded headless during `soleur:plan` (one-shot pipeline, 2026-09-24). Plan:
`knowledge-base/project/plans/2026-09-24-fix-c4-stale-banner-diagnostic-and-likec4-bwrap-sandbox-plan.md`.
`ship` renders these into the PR body and files them as an `action-required` issue.

## 1. Wireframe gate: copy-only exemption (taste)

- **Decision taken:** no `.pen` wireframe for #8695. The change swaps the text of the existing second line of the `C4Diagnostics` amber strip (same element, classes, position, show condition) and threads a prop; `wg-ui-feature-requires-pen-wireframe` and `ui-surface-terms.md` §Excluded exclude pure copy changes. The three `.tsx` files match the mechanical glob only because they host the banner.
- **Why it is surfaced:** the mechanical gates (plan Phase 2.5 override, deepen-plan 4.9, work Check-9) match on file globs and would otherwise require a `.pen`. The plan carries an explicit override naming the surface.
- **If you disagree:** run `soleur:product:design:ux-design-lead` for a `c4-stale-banner-diagnostic` Pencil file in the `kb-viewer` design folder (two states) before implementation of Phase 1.

## 2. CPO condition "alert on sandbox start failure" met without a new IaC alert rule (taste)

- **Decision taken:** sandbox failures report through `reportSilentFallback` (level error) with `feature=c4-rerender`, `reason=sandbox_error`, and a boot self-probe (`op=sandbox-selfprobe`) that fires on every container start. The first occurrence of a new error group notifies through the Sentry-default high-priority first-seen route.
- **Alternative not taken:** a dedicated `sentry_alert` in `apps/web-platform/infra/sentry/issue-alerts.tf`. It would also change the rule counts pinned by `plugins/soleur/test/c4-count-parity.test.sh` in `model.c4`, and the default route is UI-managed (tracked as #7142), not IaC.
- **If you disagree:** add the rule plus the `model.c4` count edits in this PR.

## 3. CTO recommendation "add the C4 argv as a sandbox-canary row" replaced by a report-only boot self-probe (taste)

- **Decision taken:** `verifyC4RenderSandboxOnce()` runs the exact argv in the real container (seccomp + AppArmor) at every start, report-only. It does not gate deploys (learning 2026-06-04: never gate on an unproven probe).
- **If you disagree:** promote to a canary row after the probe has reported `ok:true` across real deploys.

## 4. Scope expansion beyond #8695/#8696 (user-challenge)

- **Decision taken:** the plan folds in a production bug measured while sizing #8696: likec4 defaults `--use-dot` inside containers, the image has no `dot`, so server re-renders commit zero-view models. Fix: `--no-use-dot`, a views gate (`layout_failed`), a render-slot wait bound (real layouts take 3-7 s, not the documented 0.8 s), and a read-only census of affected tenant repos.
- **Why fold in:** same spawn, same argv, same tests; the bwrap change alone would fix it only incidentally (no `/.dockerenv` inside the sandbox).
- **If you disagree:** split the `--no-use-dot`/views-gate/slot-wait work into its own issue and PR.
