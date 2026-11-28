# Tasks: feat-one-shot-p5-atok-wait

Plan: `knowledge-base/project/plans/2026-11-28-fix-p5-browser-bodies-wait-for-atok-plan.md`. Ref #12931 (never Closes).

Out of scope: any bootstrap write stage, mint, revoke, Doppler write, browser session, or printing a token value.
The archived plan under `knowledge-base/project/plans/archive/` is never edited.

## 1. Setup

- [ ] 1.1 `git grep -n` the three old shas; confirm the sites are the manifest, runbook (198-200, 426, 433, 568) and the archived plan.
- [ ] 1.2 Grep every write site of the floors 219, 66 and the pristine count 22 in the test.

## 2. RED tests (`tests/scripts/test-cf-old-login-token-remint-browser.sh`)

- [ ] 2.1 Stub `page(world).waitForFunction(fn, arg, opts)`: serialize `fn` into the page vm context; up to 3 polls; with `world.lateAtok`, install the atok after the first falsy poll; push `{timeout, polling, resolved}` to `world.waits`; reject with `name='TimeoutError'` when never truthy. Read options from the third parameter only.
- [ ] 2.2 `makeWorld`: `lateAtok: false, waits: []`; `win.bootstrap = {}` when `lateAtok`.
- [ ] 2.3 Rows L1 (read groups), L2 (mint), L3 (revoke): result `want(...)` first, then `waits.length === 1`, `resolved === true`, finite timeout in (0, 30000], numeric polling.
- [ ] 2.4 Run; confirm L1-L3 RED on the current bodies.

## 3. Bodies

- [ ] 3.1 Add after each `page.goto`: `await page.waitForFunction(() => !!(window.bootstrap && window.bootstrap.atok), null, { timeout: 15000, polling: 100 }).catch(() => {});` in `p5-read.js`, `p5-mint.js` and `p5-revoke.js`.
- [ ] 3.2 Add one FLOW comment clause per body. Leave `p5-mint.js` `cleanup()` untouched.
- [ ] 3.3 L1-L3 GREEN; M3, R6, D7, M16f GREEN.

## 4. Hold compare and pins

- [ ] 4.1 `holds_norm` (grep `^- Hold:` then sed `sha256=[0-9a-f]{64}` to `sha256=<pinned>`) for both `ph` and `rh`; update the `PLAN_FILE=` comment.
- [ ] 4.2 Recompute the three shas; write `p5-browser.sha256` (sink line unchanged).
- [ ] 4.3 Runbook: section 5 block, the two sha-bearing holds, the section 12 retire line, and one sentence saying the go-time `<sha256>` comes from this runbook.
- [ ] 4.4 `git grep -l` each old sha lists only the archived plan.

## 5. Mutants and floors

- [ ] 5.1 XW1/XW2/XW3: delete the wait in read/mint/revoke, turning L1/L2/L3 RED with `"atok":false`.
- [ ] 5.2 XW4: drop `.catch(() => {})` in `p5-read.js`, turning D7 RED with `"error":"TimeoutError"`.
- [ ] 5.3 XH1: a hold wording edit in a runbook copy makes `holds_norm` differ.
- [ ] 5.4 `SCORED` += L1, L2, L3, D7; pristine count 26.
- [ ] 5.5 Set `EXPECT_FULL` / `EXPECT_MUTANTS` from a real run; update the header PROPERTIES / MUTATIONS comment.

## 6. Verify

- [ ] 6.1 Full run and `--mutants` both exit 0.
- [ ] 6.2 One-off, not committed: drop `, polling: 100` and swap in `!!window.bootstrap` as the condition in scratch copies; each turns its L row RED. Delete a hold line and shorten a sha to 63 hex in a runbook copy; each turns the hold compare RED.
- [ ] 6.3 `sha256sum -c p5-browser.sha256` after the last body edit; archived plan byte-unchanged vs `origin/main`.
