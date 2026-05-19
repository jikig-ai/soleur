---
title: Plan-prescribed runtime shapes (library API method names, DOM render predicates, config glob coverage) must be grepped against the installed version, not paraphrased from docs or spec memory
date: 2026-05-14
category: best-practices
module: plan
issue: 2939
related_pr: 3743
tags: [plan-skill, paraphrase-without-verification, playwright, conditional-render, config-glob, kieran-review]
---

# Learning: Plan-prescribed runtime shapes must be grepped against the installed version, not paraphrased

## Problem

During /work execution of PR-A (Stage 6 cc-soleur-go bubble e2e net, #2939, PR #3743), three plan-prescribed runtime shapes failed verification only at /work time, after the plan had already been reviewed by DHH+Kieran+Simplicity at plan-time:

1. **Playwright WebSocketRoute API name.** The plan prescribed `routeRef.sendToClient(JSON.stringify(event))` and `ws.connectToServer(); // default pass-through; tests inject via sendToClient`. The actual Playwright 1.58.2 `WebSocketRoute` type (`node_modules/playwright-core/types/types.d.ts`) exposes `send()` as the page-facing sender (semantics flip based on which side the handler is registered on); there is no `sendToClient`. Plan-review didn't catch this because the agents reviewed the plan text, not the installed type defs. The /work-time fix required reading the type definition and rewriting the helper to `routeRef.send(...)`.

2. **DOM conditional-render predicate vs assertion shape.** The plan prescribed for subagent-group test 3.1: `await expect(page.locator('[data-parent-spawn-id="p-test-1"][data-expanded="false"]')).toBeVisible()` AND `await expect(page.locator('[data-parent-spawn-id="p-test-1"] [data-child-spawn-id]')).toHaveCount(3)`. These are logically contradictory: `subagent-group.tsx:157` renders the child block only when `expanded === true` (`{expanded ? (<div...>...</div>) : null}`). A collapsed bubble has zero `[data-child-spawn-id]` matches. Both assertions were "spec-derived" from the FR text but no agent walked the component's conditional-render predicate. The /work-time fix was to click the expand toggle between the two assertions.

3. **Playwright project `testMatch` glob coverage.** The plan asserted "Uses the `authenticated` Playwright project (mock-Supabase, port 3100, `storageState: 'e2e/.auth/user.json'`)" for the new `cc-soleur-go-bubbles.e2e.ts` file. The actual `playwright.config.ts:45` set `testMatch: "**/start-fresh-*.e2e.ts"` — a string, not an array, and the new file's name did not match. The new test file would have silently run on the wrong project (chromium, no storageState, public Supabase URL). The /work-time fix was to widen `testMatch` to `["**/start-fresh-*.e2e.ts", "**/cc-soleur-go-*.e2e.ts"]` (and mirror in `chromium.testIgnore`).

The unifying theme: every plan-time `grep` precondition was correctly listed in the plan, but every gap was at a layer the listed greps did not cover — the installed library's TypeScript type defs, the consuming component's JSX render predicate, and the test-runner config's glob string. These are not "implementation details to handle in /work" — they are load-bearing assumptions the plan declared without verifying.

## Solution

**Plan-skill addition (Sharp Edges):** When a plan prescribes any of the three shapes below, the verification grep must target the installed/consuming code, not the plan author's recollection of the spec/docs:

- **Library API method names.** For any plan that prescribes a third-party library method call (Playwright `routeRef.sendToClient`, supabase-js `.maybeSingle()`, Sentry `addBreadcrumb`, etc.), the plan's Phase 0 preconditions must include `grep -E "(method-name-1|method-name-2)" node_modules/<package>/types/types.d.ts` (or equivalent for the installed major version). Docstring / online-doc paraphrase is insufficient — the type defs are the contract.

- **DOM assertions against React conditional renders.** For any plan that prescribes a Playwright/RTL assertion of the form `locator('[<selector1>] [<selector2>]').toHaveCount(N)` where `<selector1>` and `<selector2>` live on different DOM levels, the plan's Phase 0 must include `grep -n "<selector2>" <component>.tsx` and verify the surrounding JSX render predicate (`{expanded ? ... : null}`, `{state === 'X' && ...}`, etc.) is consistent with the prescribed assertion path. If `<selector2>` is conditionally rendered, the test sequence must include the precondition action (click expand, drive state to X) between the outer-selector assertion and the inner-selector assertion.

- **Test runner `testMatch` / `testIgnore` glob coverage.** For any plan that adds a new test file under a non-default naming and asserts which test-runner project (Playwright project, Vitest workspace, Jest project) the file lands on, the plan's Phase 0 must include `grep -E "testMatch|testIgnore" <test-runner>.config.ts` and verify the proposed filename matches the project's glob. Two common failure modes: (a) the config field is a string, not an array, so the new file silently lands on the default project; (b) the config field has both `testMatch` and `testIgnore` on sibling projects, and the new filename collides with neither — silent default-project assignment.

In all three cases, the verification command output is the binding source of truth, not the plan author's "I remember the API like X" or "the spec said selector Y."

## Why plan-review didn't catch these

DHH, Kieran, and Simplicity reviewers operate on the plan text. They surface design contradictions, scope creep, and pattern drift — but they do not (and should not) be expected to run `grep` against the installed `node_modules/` or against component source unless the plan explicitly cites a line that they would then re-verify. The plan's Phase 0 preconditions ARE the plan author's gesture toward "I have grepped these"; if the gesture is incomplete, the review chain doesn't re-do the work.

The fix is structural, not "review harder." Plan-time precondition lists must enumerate (a) every third-party method call by name AND its installed type-def file, (b) every nested DOM selector pair AND its component conditional-render check, (c) every new test file AND its config-glob coverage. If the plan lists these and grep proves them, the review chain has a verifiable artifact. If the plan asserts shapes without these greps, /work pays the cost — sometimes catastrophically (a `sendToClient` cargo-culted into a downstream PR-B would silently no-op for an entire helper layer).

## Session Errors

**Stale `.next/types/app/(dashboard)/layout.ts` triggered tsc failure on the (dashboard) layout's `PaymentWarningBanner` re-export.** — Recovery: `rm -rf .next/types && ./node_modules/.bin/tsc --noEmit` returns clean. — Prevention: skill instruction for `/work` and `/review` Phase 4 verification: before running `tsc --noEmit` in a Next.js app, run `rm -rf .next/types` to clear stale Next.js-generated type artifacts from prior dev-server boots. Without this, a stale artifact reads as a tsc regression that has nothing to do with the PR's changes.

**Playwright chromium browser binary was not installed in the worktree's `~/.cache/ms-playwright/`.** — Recovery: `npx playwright install chromium` (110MB download, ~30s on this machine). — Prevention: pre-flight check in `/work` Phase 4 (or in any skill that runs `playwright test`): before invoking `playwright test`, run `ls ~/.cache/ms-playwright/ | grep chromium_headless_shell-` (or the equivalent for the project's `@playwright/test` version's bundled chromium tag). If absent, run `npx playwright install chromium` first.

**Initial scope-out filing for `bootChat()` helper extraction proposed `cross-cutting-refactor` criterion based on feature-surface unrelatedness ("cc-soleur-go bubbles" vs "start-fresh onboarding/conversations-rail").** — Recovery: `code-simplicity-reviewer` DISSENTed, citing the criterion's literal text: `core change = files named in the PR's linked issue, OR files in the same top-level directory (e.g., apps/web-platform/, plugins/soleur/) as the primary changed file`. All three target files live under `apps/web-platform/e2e/` — same directory, related per the criterion's own definition. Flipped to fix-inline; landed the helper extraction (-184 lines duplicated, +60 lines helper) in the same PR. — Prevention: when invoking the scope-out CONCUR gate, the proposer must quote the criterion's literal text and demonstrate that the proposed filing matches it word-for-word. "Feature-surface unrelatedness" is not the directory-scoped test the criterion actually defines; conflating the two is the modal false-positive pattern for `cross-cutting-refactor`.

**Initial `Bash(cd apps/web-platform && ...)` failed with "No such file or directory" because the prior `cd` had already moved the shell into `apps/web-platform/`.** — Recovery: re-ran the command without the `cd` prefix. — Prevention: the Bash tool does NOT persist CWD across calls in some hosts but DOES persist in others, and the model cannot reliably predict which mode it's in. Use absolute paths (`cd /home/jean/.../apps/web-platform && cmd`) or chained `cd worktree-root && cd subdir && cmd` in a single Bash call when the subsequent command depends on a working directory. See AGENTS.md `hr-the-bash-tool-runs-in-a-non-interactive` for the canonical guidance.

**e2e test 6 (FQN render) failed 154ms during a sequential 22-test run on the `authenticated` Playwright project; passed 100% when re-run alone (1.4s) or as part of the cc-soleur-go batch alone (1.8s).** — Recovery: rerun. — Prevention: this appears to be a dev-server cold-start race when ≥22 tests run sequentially against a single Next.js dev server with `workers: 1`. No fix in PR-A; flag if the symptom recurs in PR-B/PR-C. If it does, consider `test.describe.configure({ retries: 1 })` for the first cc-soleur-go test or splitting the dev-server boot into per-suite workers.

## Cross-references

- Sibling learning (same PR, different surface): `2026-05-13-plan-verify-reducer-case-arms-with-grep-not-read-first-n.md` — reducer/switch-statement exhaustiveness via `grep "case "` enumeration.
- Sibling learning (brainstorm-time symbol verification): `2026-05-13-brainstorm-grep-cited-flag-symbol-against-main-before-spawning-leaders.md`.
- Plan: `knowledge-base/project/plans/2026-05-13-feat-cc-soleur-go-smoke-2939-pr-a-plan.md` §Research Reconciliation (which DID catch 6 plan-vs-codebase drifts at plan-time, demonstrating the value of the same discipline at the layers it actually covered).
- Issue: #2939
- PR: #3743
