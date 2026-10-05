---
module: Web Platform
date: 2026-09-27
problem_type: logic_error
component: frontend_stimulus
symptoms:
  - Remove-member button stayed permanently disabled after a confirm-cancel (window.confirm → false)
  - A watchdog-released retry had its pending state released mid-flight by the hung first attempt's late finally
  - A latched episode that failed left the control enabled but run() silently no-op'd forever
root_cause: logic_error
resolution_type: code_fix
severity: high
status: open
tags: [pending-state, latch, double-submit, zombie-episode, react-hook, ui-action-feedback]
---

# Troubleshooting: Resolution Is Not Terminality — a zombie episode can kill the retry

## Problem

`usePendingAction` originally offered `latchOnRedirect` — the hook latched pending-state
*whenever the asyncFn resolved*, on the theory that resolution meant "the hard navigation
was issued, hold pending through teardown." Three independent review agents found the same
defect class: an asyncFn that resolves on a NON-terminal path (confirm-cancel, handled
`!res.ok`, "success with no URL") latches forever, leaving the control permanently disabled.

Two further races compounded it: a latched episode that *failed* released pending but left
`latchedRef` set, so `run()` silently no-op'd on an enabled-looking control; and a
watchdog-released hung episode (a "zombie") could still run its `finally`/`setError` into
the NEXT episode the user retried into — releasing its pending mid-flight and clearing its
watchdog.

## Environment

- Module: `apps/web-platform/hooks/use-pending-action.ts` + all mutation surfaces
- Date: 2026-09-27 (PR #8904, feat-ui-action-feedback / #8917)

## Symptoms

- team-membership-list Remove member: confirm → cancel resolved the asyncFn without
  navigation → the latch inferred terminality → button disabled forever.
- billing-section Subscribe: `res.ok && !data.url` (embedded checkout returns `url:null`)
  resolved "success" with no navigation — same inferred-latch shape via hand-rolled pending.
- Sign-out "Still working…" modal could not be dismissed at all during teardown — a stalled
  `removeAllChannels`/`getUser` call parked it indefinitely with every exit inert.

## What Didn't Work

**Attempted Solution 1:** `latchOnRedirect` — latch on resolution.

- **Why it failed:** resolution and terminality are different facts. Any asyncFn with a
  non-nav success path (cancel, early return, no-URL success) resolves without navigating,
  and the latch bricks the control. The inference reads intent off an outcome that doesn't
  carry it.

**Attempted Solution 2:** Watchdog-only release (`pending=false` at 30s, no episode tracking).

- **Why it failed:** after the watchdog releases episode A, the user retries into episode B.
  A's late `finally` then released B's pending and cleared B's watchdog — the stale
  continuation reached across episodes because nothing tokenized them.

## Session Errors

**`return` inside `finally` in the hook's zombie guard** (eslint `no-unsafe-finally`, baseline 0)

- **Recovery:** restructured as a guarded `if` block inside the `finally`.
- **Prevention:** never `return` from `finally` — it suppresses a pending throw; the repo's eslint gate now has a zero-baseline rule for it.

**Staged `useCallback` import left unused after refactor** (baseline 74→75)

- **Recovery:** removed the import.
- **Prevention:** after deleting a helper's uses, grep the file for the import name before committing; run `eslint` on `git diff --name-only` files as a pre-commit cheap check.

**Nav-sentinel enumeration grep `<a[[:space:]]` missed `<a` at line end** — a planted multi-line violation passed the mutation test.

- **Recovery:** switched enumeration to `git grep -lF '<a'` (literal, not line-bound regex); re-ran all 5 violation classes.
- **Prevention:** when a sentinel greps to *enumerate files*, use the widest literal token (`-F`) and slice inside a real parser — any regex that encodes layout assumptions silently narrows the corpus.

**happy-dom lacks `window.confirm`/`window.alert`** — `vi.spyOn(window, 'confirm')` throws "can only spy on a function".

- **Recovery:** `vi.stubGlobal('confirm', fn)` + `vi.unstubAllGlobals()` in beforeEach.
- **Prevention:** in happy-dom tests, always stub window-dialog APIs via `stubGlobal`, never `spyOn`.

**Mount-effect raced test typing** — `TypedConfirmModal`'s `useEffect([open]) → setValue("")` landed AFTER `findByRole` resolved and wiped the typed SEND; the submit stayed disabled and `waitFor` timed out 10s.

- **Recovery:** `await act(async () => {})` after `findByRole` to flush mount effects before `fireEvent.change`.
- **Prevention:** in React tests, treat `findBy*` as "element exists", not "component settled" — flush an act boundary before interacting with controlled state a mount effect resets.

**Timeout-error test asserted Cancel re-enabled too early** — the alert paints before `startTransition`'s isPending clears.

- **Recovery:** wrapped the re-enable assertion in `waitFor`.
- **Prevention:** pending-release assertions after an error surface must waitFor — error state and transition-pending commit on different ticks.

**`.navfix-test` mutation fixtures left staged as `A`+deleted** — scratch files for manual sentinel testing survived as `AD` entries.

- **Recovery:** `git rm --cached` then deleted the dir; moved positive coverage into tracked `test/fixtures/` + vitest wrappers.
- **Prevention:** mutation fixtures for sentinel testing belong under `test/fixtures/` tracked by the repo — an untracked scratch dir is invisible to `git grep` on a clean checkout AND to the commit gate's staged-diff scans.

**`python3 -c` edit whose quoted replacement silently didn't match** — reported `done` while the target string was unchanged (quoting escape lost inside `bash -c`).

- **Recovery:** re-applied via the Edit tool.
- **Prevention:** after a scripted replace, assert `grep -c "<old>" == 0` AND `grep -c "<new>" == 1` on the file — "ran without error" is not "edited".

**`gh issue create` blocked 3× by the filing gate** (User-Impact/Fix-Size lines rejected in each format tried).

- **Recovery:** used `Mandated-By: wg-when-deferring-a-capability-create-a` whole-line anchor.
- **Prevention:** when a deferred-scope-out issue is rule-mandated, lead with `Mandated-By:` on its own line — it's the anchor the gate and the merge boundary both read.

**Ran the nav sentinel from the repo root** — the script lives under `apps/web-platform/scripts`.

- **Recovery:** reran from `apps/web-platform`.
- **Prevention:** sentinel scripts are app-scoped; `cd apps/web-platform` before invoking.

**Edit-pair drift** — an `old_string` anchored on text a previous edit in the same batch had just replaced.

- **Recovery:** re-read the file section, edited against current content.
- **Prevention:** in multi-edit batches on one file, anchor each edit on content the earlier edits didn't touch, or re-read before editing.

**Auto-merge produced `<Link>` with no import** — main added JSX elements to `crm-surface.tsx` post-merge-base; merge placed them but the `next/link` import line didn't survive.

- **Recovery:** converted both `<Link>` to `<NavLink>` (the sentinel-required primitive).
- **Prevention:** after auto-merge of files your branch convention-gates (nav channels, Button primitive), run the sentinels + tsc before `merge --continue`.

## Solution

**Explicit `latch()` + monotonic episode tokens.** Terminality is an explicit call the
asyncFn makes immediately before `window.location.assign` — never inferred from resolution.
Each `run()` increments `episodeRef`; the watchdog and the `finally` both bail when
`episode !== episodeRef.current` (guarded block inside `finally`, not `return` — a
ReturnStatement in `finally` trips `no-unsafe-finally` and can swallow a pending throw).
A failed episode releases AND clears the latch — failure is definitionally non-terminal.

```ts
// After (contract):
const { run, pending, error, latch } = usePendingAction(async () => {
  const res = await fetch(url, { signal: AbortSignal.timeout(PENDING_WATCHDOG_MS) });
  if (!res.ok) { setError(...); return; }          // resolves, does NOT latch
  latch();                                        // terminality is explicit
  window.location.assign(next);                   // promised teardown
});
```

Adjacent invariants that fell out of the same pass:

- `res.json()` must sit inside the `try` — a non-JSON error body otherwise throws into
  the hook's `error` slot nobody renders (silent dead click).
- `res.ok && !data.url` must transition to a visible error when the success contract
  requires a URL (`/api/checkout` embedded sessions return `url: null`).
- Every inert-dismiss-vector surface (typed-confirm, sign-out, setup-key) needs an
  `AbortSignal.timeout(PENDING_WATCHDOG_MS)` bound — a hung POST cannot be allowed to
  leave cancel disabled.

## Why This Works

1. Root cause: terminality was inferred from an outcome (promise resolution) that does not
   encode it. The fix moves the fact to an explicit call at the point where the promise is
   made (the hard-nav line), so non-terminal resolutions can't masquerade.
2. Episode tokens convert "whichever asyncFn settles last wins" into "only the current
   episode's continuation can mutate state" — the zombie's effects become no-ops.
3. Clearing the latch on failure restores the retry contract: the only permanently-held
   pending state is one with a promised teardown still in flight.

## Prevention

- When designing state machines over promises, ask "what does resolution actually prove?"
  Never bind a terminal/latched flag to it; require the caller to declare the terminal
  transition explicitly at the site that promises it.
- Any released-then-retried episode needs a token/epoch so a superseded continuation can't
  reach across into the new episode's state.
- Cancellation-sensitive guards in `finally` must be scoped blocks, never `return`.
- The review pattern that found this: trace EVERY resolve path in each consumer (cancel,
  early-return, no-URL success) against "would this latch?" — one trace, three P1s.

## Related Issues

- Deferred residual (per-episode abort-signal injection for full zombie-nav suppression):
  noted in `use-pending-action.ts` episodeRef comment.
- ~13 grandfathered hand-rolled pending sites: jikig-ai/soleur#9053.
- The commit-gate operational lessons from the same session:
  ../workflow-issues/2026-09-27-a-blocking-gate-diffing-against-moving-main-fails-on-drift-and-staging-then-merging-deadlocks.md
