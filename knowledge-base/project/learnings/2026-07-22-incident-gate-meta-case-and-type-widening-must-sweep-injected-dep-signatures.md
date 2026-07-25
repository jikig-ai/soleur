---
title: An incident-detection gate cannot pass on a plan about incident detection; and a type-widening sweep must include injected-dependency signatures
date: 2026-07-22
category: best-practices
tags: [review, false-positive, type-widening, ship-gate, testing]
issues: [6813, 6802, 6799, 6801, 6798, 6800]
pr: 6834
---

# Learning

Two generalizable insights from the six-issue statutory-notify batch (#6798–#6802, #6813, #6800).

## 1. A regex gate whose SUBJECT is the thing it detects has an irreducible false-positive on its own documentation

`/ship` Phase 5.5's Incident-PIR gate (#6813) fires when a PR/plan matches a past-tense outage
signal AND a production signal. The whole point of #6813 was to stop it firing on every ordinary
`brand_survival_threshold: single-user incident` plan (which only carried the threshold LABEL + a
hypothetical `## User-Brand Impact` section). The fix — strip the threshold label, strip
hypothetical framing, strip fenced/inline code, match only past-tense report vocabulary, never bare
`incident` — correctly clears the common case (proven by both-direction fixtures).

But the plan that *fixes the gate* trips it, because it documents the gate's own vocabulary
(`OUTAGE_RE='(outage|incident|took down|…)'` in code blocks, and prose like "reading it as an
incident report is a category error", "the outage verbs", "the chat-RLS outage"). Fenced/inline-code
stripping removes the regex-quote noise, but the PROSE about outage detection is irreducible — no
regex can distinguish a meta-discussion of incidents from an incident report.

**Consequence for the test suite:** the plan-review panel (DHH, code-simplicity, cto) correctly
dropped the `this-plan.md` self-referential fixture (M14) — but the deeper reason is that it is an
**unsatisfiable fixture**: pinning "this plan → no signal" would require crippling the gate. A
self-referential fixture on a subject-matches-detector gate is a contradiction, not just bloat.

**Disposition:** the gate is fail-toward-PIR by design, so a meta-document tripping it is acceptable
over-production that the operator hand-adjudicates (exactly what #6782 did). Do NOT chase it to zero
— that is the overfitting trap. Add the cheap principled strips (code fences, threshold label,
hypotheticals); accept the meta-prose residual; adjudicate at ship. **Litmus for any regex/keyword
gate: does the artifact that DEFINES or DOCUMENTS the gate trip it? If yes, that is inherent, not a
bug — do not add fixtures that assert otherwise.**

## 2. A type-widening cross-consumer sweep must include INJECTED-DEPENDENCY signatures, not just call sites — and tsc DOES catch this class when the type is Promise-wrapped

The usual `hr-type-widening-cross-consumer-grep` framing is "tsc won't catch a widening at an
`unknown`/`any` boundary, so grep every consumer." Widening `notifyOfflineUser` from
`Promise<void>` → `Promise<boolean>` (#6802) had a consumer the plan's call-site grep missed:
`permission-callback.ts:169` declares it as an **injected dependency**
`notifyOfflineUser: (userId, payload) => Promise<void>` and calls it at 3 sites.

Two lessons: (a) the sweep must enumerate **declared dependency/interface signatures** (an object
property typed as a function), not only direct `notifyOfflineUser(...)` call expressions — those are
where a widened concrete function is *assigned into* a narrower slot. (b) Contrary to the usual
assumption, **tsc DID reject it**: a bare function-return `boolean`→`void` is assignable, but
`Promise<boolean>`→`Promise<void>` is NOT (the `Promise<>` wrapper defeats the void-return special
case). So for Promise-returning widenings, tsc is a real backstop — but only if the consumer's slot
is typed; an `unknown`/`any`-typed injection would still slip.

## Session Errors

- **Fake column-set drift broke every repin test at once (42703).** Recovery: added `acknowledged_at`
  to the fake's `TABLE_COLUMNS`. **Prevention:** when a change adds a column to a `.select()` over a
  faked table, the fake's column allowlist (whose whole purpose is to reject unknown columns — the
  #6781 42703 tripwire) must gain the column in the same edit. A mass-fail-from-one-root-cause is the
  signature.
- **Shared test spy failure scope.** Failing all `resend` sends to exercise the email fallback also
  failed the cron's unrelated ingress-probe send (same spy). Recovery: subject-conditional mock
  (`startsWith("Statutory item")`). **Prevention:** when a test forces a shared boundary (resend,
  fetch, spawn) to fail, scope the failure to the specific payload under test, not the whole spy.
- **Type-widening sweep missed an injected-dep signature** (see insight 2). **Prevention:** grep
  `: (…) => Promise<Old>` interface/dep declarations, not just call sites.
- **Background `nohup … > log &` reported the launcher's exit, not the runner's** (well-documented
  class). **Prevention:** read the runner's own summary line from its real log; never trust the
  wrapper notification's exit code.
- **Monitor `until`-grep false-matched a test's mocked "Failed to create pull request" log line**,
  stopping early. **Prevention:** key a completion Monitor on the process (`ps -p <pid>`) or the
  runner's exact terminal summary anchor, never a substring that test-scenario logs can emit.
- **Ship-gate fired on its own plan** (insight 1, hand-adjudicated).
- **A `grep -rn` in Phase 0.6 escaped into `node_modules`/`.git`.** Recovery: `git grep`.
  **Prevention:** enumerate repo content with `git grep`/`git ls-files`, not bare recursive `grep`.
