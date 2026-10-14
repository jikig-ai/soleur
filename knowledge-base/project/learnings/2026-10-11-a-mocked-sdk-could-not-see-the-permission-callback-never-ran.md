# Learning: the permission callback never ran for hosted Bash, and no mocked test could say so

## Problem

PR #9977 shipped a must-ask lane inside `createCanUseTool` (Approve/Reject card before a default-branch force-push, `terraform destroy`, `gh` repo delete). Every unit and wiring test was green. A real-SDK probe (SDK 0.3.284, bundled Claude Code 2.1.284, the production option builder, a throwaway repo with a local bare `origin`) showed `canUseTool` was **never called** for sandboxed Bash. Two independent causes, either enough:

1. `autoAllowBashIfSandboxed: true` in the sandbox config auto-allows the call before the callback.
2. The PreToolUse sandbox hook returned an explicit `allow` for every Bash command, and a hook allow resolves the permission before `canUseTool`.

So the safe-Bash allowlist, the blocklist, the autonomous toggle gate, the batch cache and the lane were all inert, and the shipped banner and toggle copy promised an ask that did not happen (#10054).

## Solution

`autoAllowBashIfSandboxed: false` (sandbox stays on) and the hook returns `{ continue: true }` (no decision) for Bash; the sensitive-env deny stays. The probe passes after the fix: three destroy forms reach the card and leave the remote untouched, and a plain feature-branch push is not asked.

Making the dead path live exposed what had never run: the three user-facing Bash gates (review card, first-run disclosure, opt-out) had no expiry handling, so they now share one `holdForUser` helper (expiry denies, status restores once for stacked cards, a failing status write never replaces the verdict). "Approve all" now grants one simple command (compound commands and destroy-capable heads are refused), and the card preview redacts `-var *_password=`, `--token <v>` and `PGPASSWORD=`.

## Key Insight

A permission chain is ordered (hooks, deny rules, mode, allow rules, `canUseTool`), and a mocked SDK cannot model the order. The only evidence that a gate fires is a real-SDK run that drives the production option builder against the real binary. Re-run `apps/web-platform/scripts/dev-probe-destroy-ask.ts` after any SDK, CLI or sandbox-option bump.

Second: a fix applied to the two instances a finding names is not a fix to the class. Three review seats independently found the third gate on the same primitive left unwrapped. After fixing a defect in one caller, grep every other caller of the same primitive (`abortableReviewGate` here) before calling it done.

Third: making a dead path live makes everything it gates reachable at once. The gate lifecycle code, the batch cache and the redaction shapes all had defects nobody had seen because none of it had ever executed in production.

## Session Errors

- **First probe PASS was vacuous** (the model never ran Bash; API 400 from a stale SDK). Recovery: CANT-RUN verdict, clean `npm ci`. **Prevention:** a probe that can pass without proving anything must return could-not-measure; the script now also refuses to print PASS for diagnostic runs.
- **Fixed two named gates, missed the third on the same primitive.** Recovery: one shared helper. **Prevention:** grep every call site of the primitive when fixing a class.
- **AC-14 read its own mock back** as evidence of the production value. Recovery: dropped; the test against the real builder pins it. **Prevention:** a test that mocks the builder cannot assert the builder's output.
- **CLI version and window start were inherited from my own earlier summary, unmeasured** (the bundled binary is 2.1.284, not 2.1.293; the window start predates the cited SDK bump). Recovery: corrected in ADR-284 and the post-mortem after the code-quality seat measured both. **Prevention:** run the command that would falsify each sentence the diff adds.
- **A blanket `sed` over test mocks would have flipped a live-SDK test that relies on auto-allow.** Recovery: read the consumer, restored with an explanatory comment. **Prevention:** a sweep over test fixtures is not safe until each consumer is read.
- **Slips:** helper constants inserted inside an interface by an `rfind("/**")`, a stray `cd ..` that made a script path unresolvable, a stacked-card test written against the wrong call order, a mutation script aimed at the wrong file. Each surfaced on the next command; no recurrence vector.

## Tags

category: security-issues
module: apps/web-platform/server permission chain (sandbox-hook, permission-callback, agent-runner-sandbox-config)
