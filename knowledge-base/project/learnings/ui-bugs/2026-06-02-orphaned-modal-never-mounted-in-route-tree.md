---
date: 2026-06-02
issue: SOL-49
pr: 4778
category: ui-bugs
tags: [react, nextjs-15, app-router, modal, server-components, consent-ui, byok-delegation]
related:
  - knowledge-base/project/learnings/2026-05-19-optimistic-local-state-and-server-prop-conjunction-needs-router-refresh.md
  - knowledge-base/project/learnings/2026-05-04-in-isolation-probe-missed-user-shape-and-scope-out-exacerbation.md
---

# Orphaned modal: the component shipped but no parent ever mounted it

## Problem

The grantee acceptance modal `apps/web-platform/components/settings/delegation-acceptance-modal.tsx` was created in PR #4508 ("BYOK delegation PR-B legal scaffolding") and extended in PR #4627 ("BYOK delegation consent enforcement"). Both PRs added the modal's internal contract (3 callbacks, telemetry-ack gate, withdraw branch, sentry-mirrored try/catch) and the SQL-side enforcement (mig 075 acceptance-EXISTS gate, mig 076 WORM withdrawal ledger). The PRs also wrote a text-only "Pending acceptance" banner into `apps/web-platform/components/chat/delegation-banner.tsx`.

What never landed: **the parent component that imports `DelegationAcceptanceModal` and mounts it on a route**. PR #4508 task 5.3 ("Update DelegationBanner for pending-acceptance state") shipped as text-only; the modal-mount step was silently dropped during /work. A grantee with a pending delegation saw the "Pending acceptance" copy but had no clickable surface to record consent — the SQL gate refused to lease the grantor's key until acceptance was recorded, leaving the grantee stuck on the chat surface with no entry to the consent flow.

The reporter symptom — "La fenêtre de confirmation ne se ferme pas" — was the secondary manifestation: whatever ad-hoc mount the dogfood operator was using called `onAccepted()`, but the parent never re-fetched the server-component data (no `router.refresh()`), so on the next render the modal re-opened. The modal itself has no internal `isOpen` state — it renders unconditionally and relies on the parent's `{open && <Modal />}` conditional for unmount semantics.

`grep -rn 'DelegationAcceptanceModal' apps/web-platform/components apps/web-platform/app | grep -v test | grep -v '/components/settings/delegation-acceptance-modal.tsx'` returned **0** matches at SOL-49 file time.

## Root cause

Two interacting failure modes:

1. **Orphan-component class.** A multi-PR feature lands the consumed primitive (the modal) and the contract surfaces (route + WORM ledger + telemetry-ack) but the parent-mount step is dropped silently during execution. `tsc --noEmit` is silent on "no one imports this component." The full suite is silent. The only signal is a grep for the component name in the route tree — which is not part of any pre-merge gate.

2. **Stale-server-prop-on-success class** (same shape as PR-G #4059, learning 2026-05-19). The modal's `if (res.ok) onAccepted()` callback is correct, but the parent-conditional mount requires the parent's server-rendered `acceptance.accepted` state to flip from `false` to `true` for the modal to unmount. With no `router.refresh()` in the parent, the next React render reads the stale server payload and re-evaluates `acceptance.accepted === false`, re-mounting the modal.

## Solution

1. **Wire the orphan modal into the existing banner** (`components/chat/delegation-banner.tsx`) — the canonical entry surface per the PR-B spec. Extend the text-only banner with state (`useState(false)` for open/closed), `useRouter()` from `next/navigation`, conditional mount `{open && <DelegationAcceptanceModal … />}`, and 3 success-only callbacks that close the modal AND call `router.refresh()`.

2. **3-state enum (not 2)**: the `AcceptanceStatus` resolver returns two booleans (`accepted`, `withdrawn`). Three legal combinations carry distinct UI semantics: never-accepted (accept flow), active (manage/withdraw), withdrawn (re-accept, same UX as never-accepted because the SQL gate at mig 075 closes-out on `withdrawn=true`). The single predicate `showAcceptFlow = !alreadyAccepted || withdrawn` collapses the 3 states into 2 UI branches without losing the state distinction.

3. **3 distinct refresh call sites, not a shared helper.** The success-only invariant (don't `router.refresh()` on non-2xx or fetch throw — would clobber the modal's pessimistic-revert path) is locked in by negative-space tests on every callback. Factoring to a shared `handleClose = () => { setOpen(false); router.refresh(); }` invites a future refactor that hoists into a `finally` block and reintroduces the regression. The 3 textually-identical handlers carry an inline `// success-only` comment citing the originating learning.

4. **Modal a11y additive**: `role="dialog"`, `aria-modal="true"`, `aria-labelledby` on the modal container. Improves screen-reader experience AND enables `screen.getByRole('dialog')` in the new banner test suite without coupling tests to brittle markup.

5. **Symmetric `try/catch/finally` with `reportSilentFallback`** on all 3 modal handlers — both the throw path AND the `!res.ok` path mirror to Sentry per `cq-silent-fallback-must-mirror-to-sentry`. Pre-fix shape (`try { … } finally { setLoading(false) }`) leaked unhandled rejections in tests and silently dropped 4xx/5xx in production.

6. **No new RPC, no new route, no new schema.** The fix is 3 production file edits + 1 new test file + 1 compliance-changelog row. The SQL/routes/WORM layer shipped intact in PR #4508/#4627; this PR closes the UX entry-point gap only.

## Key insight

**When a multi-PR feature ships a UI primitive (modal, drawer, sheet, popover) intended to be mounted by a parent in a different file, the mount step is the most likely thing to be silently dropped.** The primitive's existence + the SQL/route enforcement looks like coverage; in fact the user-facing entry path is invisible to typecheck, unit tests, AND the green-CI gate. The cheapest detection is a single grep at plan time: `grep -rn '<ComponentName>' apps/<app>/(components|app) | grep -v test | grep -v <component-own-path>` — every UI primitive whose intended-mount-surface PR is closed must return ≥1 match. If it returns 0, file as P0 against the originating PR before the next dogfood.

The grep gate would have caught both #4508 task 5.3 (mount step dropped) and would have caught any future PR that ships an orphan modal/drawer/popover.

## Prevention

1. **Plan-time orphan grep** for any PR introducing a new UI primitive: AC adds `grep -rn '<ComponentName>' <app>/(components|app) | grep -v test | grep -v '<component-own-path>' returns ≥1` to the Pre-merge ACs.

2. **Multi-PR-feature mount sweep**: when a feature is split across N PRs and PR-N introduces a UI primitive consumed by PR-N+1's parent surface, the PR-N+1 plan must include "mount the orphan modal" as the first GREEN task.

3. **Symmetric silent-fallback on all conditional callback fires**: any `if (res.ok) callback()` pattern in a fetch-bound modal/banner/popover must have an `else { reportSilentFallback(...) }` mirror — asymmetric closure produces silent 4xx/5xx drops AND vitest unhandled-rejection exit-code failures.

4. **Grep-counted ACs must not match comment prose**: when an AC enforces `grep -cE 'pattern' file = N`, the code body must own the literal pattern alone. Comments referencing the pattern textually inflate the count and force either comment rephrasing or AC weakening — neither is ideal. Phrase doc comments to describe the pattern semantically without quoting it.

5. **Anti-slop "mirror is exacerbation"** (learning 2026-05-04 carry-forward): a pre-existing brittle pattern (e.g., `bg-soleur-accent-gold-fg text-white` failing AA contrast) copied verbatim into a new component IS exacerbation, not preservation. Even if the new site is "consistent with siblings," fix both the new and the originally-touched siblings when the brand-anti-slop scanner flags them in the same PR.

## Session Errors

1. **Anti-slop scan `mapfile` builtin missing under zsh** — the SKILL.md script used `mapfile -d ''` which is a bash 4+ builtin not available in this zsh harness. **Recovery:** pivoted to `xargs -a` after the first `mapfile` failure. **Prevention:** skill scripts that target both bash and zsh should use POSIX-compatible patterns (`xargs -0`, `while IFS= read -r`). File issue against `plugins/soleur/skills/review/SKILL.md` line 290-303 to widen the snippet for zsh hosts.

2. **NUL-delimited multi-stage pipeline lost matches** — second anti-slop scan's `git diff -z … | grep -zE … > tmp; tr '\0' '\n' < tmp > targets` produced an empty list. **Recovery:** re-ran via single-stage `git diff … | grep -E … | xargs`. **Prevention:** when piping NUL-delimited git output for shell consumption, single-stage pipes are more reliable than multi-stage with intermediate files.

3. **AC4-AC5 grep returned 4 not 3** — the implementation comment line `// 3 distinct router.refresh() call sites — success-only` contained the literal pattern `router.refresh()` and inflated the grep count. **Recovery:** rephrased comment to `// 3 distinct refresh call sites — success-only`. **Prevention:** when an AC enforces a literal count via `grep -cE 'pattern' file`, the code body must own that pattern alone; phrase doc comments to describe the pattern semantically without quoting it.

4. **Vitest exit 1 from unhandled fetch rejection** — pre-existing modal handlers used `try { fetch(...) } finally { setLoading(false); }` with no catch; the new banner test's `fetchMock.mockRejectedValueOnce(new Error("network"))` surfaced this as an unhandled promise rejection that failed the runner exit code even with all 13 assertions passing. **Recovery:** added symmetric `try/catch/finally` with `reportSilentFallback` per `cq-silent-fallback-must-mirror-to-sentry` — the proper fix per the existing rule. **Prevention:** when a test rejects a promise the SUT awaits, the SUT must have a catch (silent or sentry-mirroring) — vitest counts unhandled rejections as a non-zero exit even when all assertions pass.

5. **CWD drift across Bash calls in pipeline mode** — early `cd apps/web-platform && vitest …` failed with "no such file or directory" because the harness Bash tool's CWD already persisted from a prior `cd`. **Recovery:** verified via `pwd` then issued subsequent commands without redundant `cd`. **Prevention:** the harness Bash tool persists CWD across calls; verify CWD once at phase boundaries, then issue commands relative to it. Skill instructions that chain `cd worktree-abs-path && <cmd>` in a single Bash call are robust; skill instructions that say "cd into X first" risk drift if the agent assumes CWD reset between calls.

## Tags

category: ui-bugs
module: byok-delegation
file: apps/web-platform/components/chat/delegation-banner.tsx
file: apps/web-platform/components/settings/delegation-acceptance-modal.tsx
file: apps/web-platform/app/(dashboard)/dashboard/chat/layout.tsx
